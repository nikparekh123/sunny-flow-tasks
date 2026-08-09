/**
 * nvda-planner — pricing + context for the next NVDA short-call sale (rev 2).
 *
 * The edge prices every candidate expiry's chain with single-clock Black-Scholes
 * (T = vol_days ÷ 252) and supplies the raw technicals for the Upside Room card.
 * The APP owns the instant decision math (upside score, target-moneyness
 * selection, size scaling, scenario) so taps update in place without a re-fetch;
 * a re-call happens only when a pricing input changes (weekend-vol).
 *
 * Live inputs: fresh Polygon spot + real listed expiry calendar; ticker_stats
 * (52w range, MA50/200, RSI14, ATH) read with the service role. Vol/book context
 * comes in on the request from the app's own NvDerive output, so the Seller Score
 * stays identical to the Volatility card.
 *
 * Request body (required: book.shares, vol.iv):
 *   { book:{shares,buyAvg,realizedPremium,netDelta,longTheta,shortCallDelta,
 *            shortCallCt,openShortCalls[{strike,ct,expiry?}],longCalls[],
 *            longCallDelta?,putDelta?,putFloor?,putCost?},
 *     vol:{iv,ivPct,hv20,hv30,hv60,hv90}, earnings:{date,label}, wash|null,
 *     weekendVol?:0.3, refStrike?, spot? }
 *
 * rev 3 adds the decision layer, additively — every rev-2 field is untouched.
 *
 *   week      the WEEK score: stance, prescription (delta band + size), lot
 *             capacity, and eight weighted forces. Strike-invariant by design —
 *             most of what makes a week good is identical in every cell, so
 *             folding it into the per-strike number leaves the ladder ranking to
 *             the penalties alone.
 *   posture   upside-participation delta (puts excluded), the dynamic floor and
 *             the modifiers that moved it, tape state, and the freeroll with its
 *             regime — an OTM floor struck above basis zeroes the corridor, and
 *             freeroll becomes "is the hedge paid for" rather than "can I survive
 *             a drawdown".
 *   assignment  expected call-away priced per leg off N(d2), against the tail case
 *             of every call being assigned. The hedge is sized to the whole share
 *             block and does not leave with the shares, so a long-only book can
 *             end up short by arithmetic. Capacity keys off the expected path.
 *   events    the seeded calendar with severity, and 14-day density.
 *   expiries[].chain[]  each cell gains fit / fitParts / blocks / warns, scored
 *             against the week's prescription; expiries gain load and pickStrike.
 *
 * Env: POLYGON_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
 */
const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' };
const json = (s: number, b: unknown) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

const POLY = 'https://api.polygon.io';
const PL_R = 0.045;
const RIP = 0.15;

// Per-instrument constants. Everything else in this function is symbol-agnostic —
// adding a book is an entry here, not a code change.
const INSTRUMENT: Record<string, { step: number; floorPct: number }> = {
  NVDA: { step: 2.5, floorPct: 0.15 },
  TLT:  { step: 0.5, floorPct: 0.10 },
};

// ── Black-Scholes (single clock, fixture-exact) ──
function ncdf(x: number): number {
  const a1 = .254829592, a2 = -.284496736, a3 = 1.421413741, a4 = -1.453152027, a5 = 1.061405429, p = .3275911;
  const s = x < 0 ? -1 : 1, z = Math.abs(x) / Math.SQRT2, t = 1 / (1 + p * z);
  const y = 1 - ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * Math.exp(-z * z);
  return .5 * (1 + s * y);
}
function bsD(S: number, K: number, T: number, v: number): [number, number] {
  const sq = v * Math.sqrt(T);
  const d1 = (Math.log(S / K) + (PL_R + v * v / 2) * T) / sq;
  return [d1, d1 - sq];
}
function bsDelta(S: number, K: number, T: number, v: number): number { return T <= 0 ? (S > K ? 1 : 0) : ncdf(bsD(S, K, T, v)[0]); }
function bsCall(S: number, K: number, T: number, v: number): number {
  if (T <= 0 || v <= 0) return Math.max(S - K, 0);
  const [d1, d2] = bsD(S, K, T, v);
  return S * ncdf(d1) - K * Math.exp(-PL_R * T) * ncdf(d2);
}
function bsPut(S: number, K: number, T: number, v: number): number {
  if (T <= 0 || v <= 0) return Math.max(K - S, 0);
  const [d1, d2] = bsD(S, K, T, v);
  return K * Math.exp(-PL_R * T) * ncdf(-d2) - S * ncdf(-d1);
}
function bsAssign(S: number, K: number, T: number, v: number): number { return T <= 0 ? (S > K ? 1 : 0) : ncdf(bsD(S, K, T, v)[1]); }

// ── scoring primitives ──
// Every sub-factor lands on the same ±50 scale, so the weights are the only lever.
// tanh rather than a clamp: a clamp saturates and lets cells tie at the ceiling,
// which is exactly when the ladder most needs to tell them apart.
const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
const sTanh = (x: number) => 50 * Math.tanh(x);
const sPct = (pct: number) => clamp(pct - 50, -50, 50);            // 0–100 percentile
const sDecay = (clearDays: number, tau = 5) =>                      // days clear of an event
  clearDays <= 0 ? -50 : 50 * (1 - Math.exp(-clearDays / tau));
const fin = (x: number) => (Number.isFinite(x) ? x : 0);

// What a scheduled date is worth. NVDA's own print dwarfs everything; macro still
// moves a high-beta name, so it counts, but at a third of the weight.
const SEVERITY: Record<string, number> = {
  earnings: 5, fomc: 3, cpi: 3, pce: 2, nfp: 2, gtc: 2, other: 1,
};
function severityOf(name: string): number {
  const n = (name || '').toUpperCase();
  if (/EARNING|RESULTS|Q[1-4]/.test(n)) return SEVERITY.earnings;
  if (/FOMC|FED |RATE DECISION/.test(n)) return SEVERITY.fomc;
  if (/\bCPI\b|INFLATION/.test(n)) return SEVERITY.cpi;
  if (/\bPCE\b/.test(n)) return SEVERITY.pce;
  if (/PAYROLL|\bNFP\b|JOBS/.test(n)) return SEVERITY.nfp;
  if (/\bGTC\b|\bCES\b|KEYNOTE/.test(n)) return SEVERITY.gtc;
  return SEVERITY.other;
}

// What decides the week depends on the week. A fixed allocation gives the calendar
// 23% in a quiet week and 23% in earnings week, which is how you end up with the
// average answer every time. Rows are normalised at use, so they need only be
// proportions rather than exact fractions.
const REGIME_WEIGHTS: Record<string, Record<string, number>> = {
  // Thirteen factors, five families. The calendar used to be ONE factor keyed on
  // the heaviest event in the window, which meant a severity-3 CPI print two days
  // out was invisible behind a severity-5 earnings date sixteen days out. Split
  // three ways, each date keeps its own clock and nothing can mask anything else.
  //
  // `record` and `relative` are new to the score. The print record previously moved
  // keepPct and nothing else, so the number on the card never reflected the one
  // thing measured over 159 observations.
  'EARNINGS WEEK':        { print: .24, iv_pctile: .18, iv_spread: .15, record: .13,
                            assignment: .08, peers: .06, headroom: .04, macro: .03,
                            trend: .03, freeroll: .02, stretch: .02, relative: .01, rsi: .01 },

  // After the print the record is the sharpest thing available: vol is crushed, the
  // tape is resetting, and what this name did next is measured rather than guessed.
  'JUST AFTER THE PRINT': { record: .20, iv_spread: .18, stretch: .15, trend: .12,
                            assignment: .10, headroom: .07, relative: .06, iv_pctile: .04,
                            peers: .03, freeroll: .02, macro: .02, rsi: .01, print: .01 },

  'BEATEN DOWN':          { stretch: .20, rsi: .13, trend: .12, record: .12, headroom: .12,
                            relative: .08, iv_pctile: .08, iv_spread: .07, assignment: .04,
                            macro: .02, peers: .01, freeroll: .01, print: .01 },

  'EXTENDED RUN':         { stretch: .20, trend: .17, iv_pctile: .12, relative: .08, rsi: .08,
                            assignment: .08, macro: .06, record: .06, headroom: .06,
                            iv_spread: .05, peers: .03, print: .02, freeroll: .01 },

  'RANGE':                { iv_pctile: .22, iv_spread: .14, freeroll: .12, headroom: .10,
                            macro: .09, stretch: .08, assignment: .07, record: .05,
                            relative: .05, peers: .04, print: .03, trend: .03, rsi: .02 },
};


// One priced strike. The first block is the original pricing payload; the second is
// what the fit pass adds once the week's prescription is known.
interface Cell {
  strike: number; prem: number; fair: number; sellable: boolean;
  intrinsic: number; ext: number; extPct: number;
  edge: number; edgePct: number; edgeHi: number; edgeLo: number;
  edgePctHi: number; edgePctLo: number; edgeCrosses: boolean;
  assign: number; delta: number; effective: number; vsBasis: number;
  side: string; advCost: number; affected: number;
  perDay?: number; deltaSold?: number; freeAfter?: number; afterAssign?: number; em?: number;
  calledPerCt?: number; clearsBy?: number; calledShares?: number; calledCost?: number; calledPL?: number; calledAvg?: number; suggestCt?: number; wantCt?: number; cappedBy?: string | null;
  credit?: number; income?: number; paidPerDelta?: number; normalIncome?: number | null; ivPremium?: number | null; upsideAfterMove?: number; deltaAfterMove?: number;
  netCarry?: number; rank?: number; perDayPkg?: number; coversPct?: number; requiredHere?: number;
  warns?: string[]; blocks?: string[]; fit?: number; isPick?: boolean;
  fitParts?: { k: string; w: number; s: number; contribution: number }[];
}

// ── Polygon: spot + expiry calendar ──
interface Snap { underlying_asset?: { price?: number }; }
async function nearestSpot(key: string, tk: string): Promise<number | null> {
  try {
    const r = await fetch(`${POLY}/v3/snapshot/options/${tk}?limit=1&apiKey=${key}`);
    if (!r.ok) return null;
    const j = await r.json();
    return ((j?.results ?? [])[0] as Snap | undefined)?.underlying_asset?.price ?? null;
  } catch { return null; }
}
async function callExpiries(fromISO: string, key: string, tk: string): Promise<string[]> {
  try {
    const r = await fetch(`${POLY}/v3/reference/options/contracts?underlying_ticker=${tk}&contract_type=call`
      + `&expiration_date.gte=${fromISO}&expired=false&limit=1000&sort=expiration_date&order=asc&apiKey=${key}`);
    if (!r.ok) return [];
    const j = await r.json();
    const set: string[] = [];
    for (const c of (j?.results ?? []) as { expiration_date?: string }[]) if (c.expiration_date && !set.includes(c.expiration_date)) set.push(c.expiration_date);
    return set;
  } catch { return []; }
}

// ── dates ──
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
function ymd(d: Date): string { return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`; }
function parseISO(s: string): Date { const [y, m, dd] = s.split('-').map(Number); return new Date(Date.UTC(y, m - 1, dd)); }
function spanTo(nowISO: string, target: Date): { cal: number; td: number; we: number } {
  const d = parseISO(nowISO); let cal = 0, td = 0, we = 0;
  while (d < target) { d.setUTCDate(d.getUTCDate() + 1); cal++; const w = d.getUTCDay(); if (w === 0 || w === 6) we++; else td++; }
  return { cal, td, we };
}
function fallbackExpiries(nowISO: string): string[] {
  const out: string[] = [], d = parseISO(nowISO);
  for (let i = 1; i <= 21 && out.length < 6; i++) { d.setUTCDate(d.getUTCDate() + 1); const w = d.getUTCDay(); if (w === 1 || w === 3 || w === 5) out.push(ymd(d)); }
  return out;
}

const LOOKBACKS = ['hv20', 'hv30', 'hv60', 'hv90'] as const;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const key = Deno.env.get('POLYGON_API_KEY');
  const supaUrl = Deno.env.get('SUPABASE_URL');
  const supaKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const b = await req.json().catch(() => ({})) as Record<string, unknown>;

  const bookIn = (b.book ?? {}) as Record<string, unknown>;
  const volIn = (b.vol ?? {}) as Record<string, number>;
  if (bookIn.shares == null || volIn.iv == null) return json(400, { ok: false, error: 'book.shares and vol.iv are required' });

  const wv = Number(b.weekendVol ?? 0.3);
  const TICKER = String(b.ticker ?? 'NVDA').toUpperCase();
  const INST = INSTRUMENT[TICKER] ?? INSTRUMENT.NVDA;
  const STRIKE_STEP = INST.step;
  const nowISO = ymd(new Date());
  const [polySpot, polyExpiries] = key
    ? await Promise.all([nearestSpot(key, TICKER), callExpiries(nowISO, key, TICKER)])
    : [null, [] as string[]];
  const spot = (b.spot as number) ?? polySpot ?? 0;
  if (!spot) return json(200, { ok: false, error: 'no spot' });

  // ── ticker_stats (technicals for Upside Room) ──
  let ts: Record<string, number | string | null> = {};
  if (supaUrl && supaKey) {
    try {
      const r = await fetch(`${supaUrl}/rest/v1/ticker_stats?ticker=eq.${TICKER}&select=*`, { headers: { apikey: supaKey, Authorization: `Bearer ${supaKey}` } });
      if (r.ok) ts = ((await r.json()) as Record<string, number | string | null>[])[0] ?? {};
    } catch { /* leave empty → app degrades the card */ }
  }
  // ── the calendar, from the seeded event tables ──
  // The old gate knew one date: earnings. A high-beta name still reacts to macro,
  // so density (severity summed over a horizon) is what the week score reads.
  type Cat = { key: string; label: string; date: string; days: number; sev: number };
  const cats: Cat[] = [];
  const calSources: string[] = [];
  let lastPrintISO: string | null = null;
  let lastReaction: { band: string; move_pct: number; report_date: string } | null = null;
  let bandStats: { band: string; n: number; d30: number } | null = null;
  let record: { n: number; survived: number; med: number } | null = null;
  type Peer = { ticker: string; date: string; days: number; confirmed: boolean };
  let peers: Peer[] = [];
  let peersKnown = false;
  let relStrength: { vs: string; self: number; ref: number; gap: number; days: number } | null = null;
  if (supaUrl && supaKey) {
    const h = { apikey: supaKey, Authorization: `Bearer ${supaKey}` };
    const soon = ymd(new Date(Date.now() + 120 * 86400000));
    // Each table names its own date column — earnings_events is keyed on report_date
    // and scoped by ticker, macro_events on event_date and global.
    const grab = async (table: string, dateCol: string, nameCol: string, extra = '', labelAs = '') => {
      try {
        const r = await fetch(`${supaUrl}/rest/v1/${table}?select=*&${dateCol}=gte.${nowISO}&${dateCol}=lte.${soon}${extra}&order=${dateCol}.asc&limit=40`, { headers: h });
        if (!r.ok) { calSources.push(`${table}:HTTP${r.status}`); return; }
        const rows = (await r.json()) as Record<string, unknown>[];
        for (const row of rows) {
          const d = String(row[dateCol] ?? '').slice(0, 10);
          if (!d) continue;
          const label = labelAs || String(row[nameCol] ?? row.title ?? row.name ?? table);
          // Severity is judged on what the event IS, which is not always what the
          // row is labelled. tlt_macro_events puts the date in `label` ("Aug 12")
          // and the kind in class_name/tag ("Inflation prints", "CPI · July") — read
          // on `label` alone, a CPI print scored the same as a Fed speaker.
          const kind = [row.class_name, row.class_key, row.tag, row.company_name, label]
            .filter(Boolean).join(' ');
          cats.push({ key: table, label, date: d, sev: severityOf(kind),
            days: Math.round((parseISO(d).getTime() - parseISO(nowISO).getTime()) / 86400000) });
        }
        calSources.push(`${table}:${rows.length}`);
      } catch (e) { calSources.push(`${table}:ERR`); }
    };
    const tables: [string, string, string, string, string][] = TICKER === 'TLT'
      ? [['tlt_macro_events', 'event_date', 'label', '', '']]
      : [['earnings_events', 'report_date', 'company_name', `&ticker=eq.${TICKER}`, `${TICKER} earnings`],
         ['macro_events', 'event_date', 'label', '', '']];
    // The last print matters as much as the next one: IV crush and how the tape
    // absorbed the news define the weeks after it.
    if (TICKER !== 'TLT') {
      try {
        const back = ymd(new Date(parseISO(nowISO).getTime() - 45 * 86400000));
        const r = await fetch(`${supaUrl}/rest/v1/earnings_events?select=report_date&ticker=eq.${TICKER}`
          + `&report_date=gte.${back}&report_date=lt.${nowISO}&order=report_date.desc&limit=1`, { headers: h });
        if (r.ok) {
          const rows = (await r.json()) as { report_date?: string }[];
          if (rows[0]?.report_date) lastPrintISO = String(rows[0].report_date).slice(0, 10);
        }
      } catch { /* no past print on record is a normal state */ }
    }
    await Promise.all(tables.map(([t, d, n, x, l]) => grab(t, d, n, x, l)));
  }
  cats.sort((x, y) => x.days - y.days);

  // A year of implied vol, so "rich" can be stated in dollars rather than as a
  // ratio nobody can act on. Median, not mean: a single earnings spike should not
  // define normal.
  let ivMedian: number | null = null;
  if (supaUrl && supaKey) {
    try {
      const r = await fetch(`${supaUrl}/rest/v1/${TICKER === 'TLT' ? 'tlt' : 'nvda'}_iv_daily`
        + `?select=iv&ticker=eq.${TICKER}&order=date.desc&limit=252`,
        { headers: { apikey: supaKey, Authorization: `Bearer ${supaKey}` } });
      if (r.ok) {
        const xs = ((await r.json()) as { iv?: number }[])
          .map((x) => Number(x.iv)).filter((x) => Number.isFinite(x) && x > 0).sort((a, b) => a - b);
        if (xs.length >= 30) {
          const m = xs[Math.floor(xs.length / 2)];
          // nvda_iv_daily stores implied vol as a FRACTION (0.40) while the rest of
          // this function speaks percent (40). Priced raw, "normal" came out at 0.4%
          // vol and every dollar of income read as IV premium.
          ivMedian = m < 1.5 ? m * 100 : m;
        }
      }
    } catch { /* no history yet just means no comparison */ }
  }

  // What this stock actually did after prints like the last one. NVDA's own record
  // only — the peers say the opposite about bad prints (they stay down, NVDA
  // recovers), so falling back to them would mislead in the one band that differs
  // most. Used at whatever sample exists, with the count carried through so a number
  // resting on four observations can be read as such.
  if (supaUrl && supaKey && TICKER !== 'TLT') {
    const h = { apikey: supaKey, Authorization: `Bearer ${supaKey}` };
    try {
      const r = await fetch(`${supaUrl}/rest/v1/earnings_reactions`
        + `?select=band,move_pct,report_date,d30_pct&ticker=eq.${TICKER}&order=report_date.desc&limit=200`,
        { headers: h });
      if (r.ok) {
        const rows = (await r.json()) as { band: string; move_pct: number; report_date: string; d30_pct: number }[];
        if (rows.length) {
          lastReaction = { band: rows[0].band, move_pct: Number(rows[0].move_pct), report_date: rows[0].report_date };
          const same = rows.filter((x) => x.band === rows[0].band).map((x) => Number(x.d30_pct))
            .filter(Number.isFinite).sort((a, b) => a - b);
          if (same.length) bandStats = { band: rows[0].band, n: same.length, d30: +same[Math.floor(same.length / 2)].toFixed(2) };
          // The whole distribution, not just the matching band. "36 of the last 40
          // landed better than -8%" is a claim about the world; the band median is a
          // claim about one situation. The card wants both, at different moments.
          const moves = rows.map((x) => Number(x.move_pct)).filter(Number.isFinite).sort((a, b) => a - b);
          if (moves.length >= 8) {
            record = { n: moves.length, survived: moves.filter((m) => m > -8).length,
                       med: +moves[Math.floor(moves.length / 2)].toFixed(1) };
          }
        }
      }
    } catch { /* no record yet just means the hand-set numbers stand */ }
  }

  // ── the neighbourhood ──
  // The domain the card had nothing for. A semi that printed six days ago or reports
  // next week is context about the position that the position cannot supply. The
  // window reaches backwards as well as forwards: a print just behind is as
  // informative as one just ahead.
  if (supaUrl && supaKey && TICKER !== 'TLT') {
    const h = { apikey: supaKey, Authorization: `Bearer ${supaKey}` };
    const from = ymd(new Date(parseISO(nowISO).getTime() - 12 * 86400000));
    const to = ymd(new Date(parseISO(nowISO).getTime() + 45 * 86400000));
    try {
      const r = await fetch(`${supaUrl}/rest/v1/earnings_events`
        + `?select=ticker,report_date,notes&scope_tag=eq.peer&report_date=gte.${from}`
        + `&report_date=lte.${to}&order=report_date.asc&limit=20`, { headers: h });
      if (r.ok) {
        // peersKnown is set on a successful READ, not on a non-empty one. An empty
        // table and a failed fetch are different states: the first lets the card say
        // "no chip earnings", the second must leave it silent.
        peersKnown = true;
        peers = ((await r.json()) as { ticker: string; report_date: string; notes?: string }[]).map((x) => {
          const d = String(x.report_date).slice(0, 10);
          return { ticker: x.ticker, date: d,
            days: Math.round((parseISO(d).getTime() - parseISO(nowISO).getTime()) / 86400000),
            // "AVGO reports Wednesday" and "AVGO probably reports Wednesday" are
            // different claims, and the card must never blur them.
            confirmed: !/estimat/i.test(String(x.notes ?? '')) };
        });
      }
    } catch { /* no read, no claim */ }

    // Where the money is going inside the sector. Both legs use the same window, so
    // a missing session on either side shortens the comparison rather than skewing it.
    try {
      const back = ymd(new Date(parseISO(nowISO).getTime() - 45 * 86400000));
      const r = await fetch(`${supaUrl}/rest/v1/daily_closes`
        + `?select=ticker,date,close_price&ticker=in.(${TICKER},SMH)&date=gte.${back}`
        + `&order=date.desc&limit=200`, { headers: h });
      if (r.ok) {
        const rows = (await r.json()) as { ticker: string; date: string; close_price: number }[];
        const series = (tk: string) => rows.filter((x) => x.ticker === tk)
          .sort((a, b) => (a.date < b.date ? 1 : -1))
          .map((x) => Number(x.close_price)).filter((v) => Number.isFinite(v) && v > 0);
        const a = series(TICKER), r2 = series('SMH');
        const n = Math.min(a.length, r2.length, 21);
        if (n >= 10) {
          const pa = ((a[0] - a[n - 1]) / a[n - 1]) * 100;
          const pr = ((r2[0] - r2[n - 1]) / r2[n - 1]) * 100;
          relStrength = { vs: 'SMH', self: +pa.toFixed(1), ref: +pr.toFixed(1), gap: +(pa - pr).toFixed(1), days: n };
        }
      }
    } catch { /* no reference series, no claim */ }
  }

  const num = (v: unknown) => (v == null ? null : Number(v));
  const technicals = {
    high52: num(ts.high_52w), low52: num(ts.low_52w), ma50: num(ts.ma50), ma200: num(ts.ma200),
    rsi14: num(ts.rsi14), ath: num(ts.ath), athDate: (ts.ath_date as string | null) ?? null,
    updatedAt: (ts.updated_at as string | null) ?? null,
  };

  // ── book ──
  const openShortCalls = (bookIn.openShortCalls ?? []) as { strike: number; ct: number }[];
  const longCallsIn = (bookIn.longCalls ?? []) as { strike: number; ct: number }[];
  const shares = Number(bookIn.shares);
  const shortCallCt = Number(bookIn.shortCallCt ?? openShortCalls.reduce((a, s) => a + s.ct, 0));
  const book = {
    shares, buyAvg: Number(bookIn.buyAvg ?? 0), realizedPremium: Number(bookIn.realizedPremium ?? 0),
    netDelta: Number(bookIn.netDelta ?? shares), longTheta: Number(bookIn.longTheta ?? 0),
    shortCallDelta: Number(bookIn.shortCallDelta ?? 0), shortCallCt,
    longCallCt: longCallsIn.reduce((a, l) => a + l.ct, 0),
    wall: longCallsIn.length ? Math.min(...longCallsIn.map((l) => l.strike)) : null,
    committedShares: shortCallCt * 100, freeShares: shares - shortCallCt * 100,
    capacity: Math.max(0, Math.floor(shares / 100)), basis: 0,
  };
  book.basis = book.buyAvg - book.realizedPremium / (book.shares || 1);
  const wall = book.wall ?? Infinity;

  // ── vol / gate ──
  const HV: Record<string, number> = {
    hv20: Number(volIn.hv20 ?? volIn.hv30 ?? 0), hv30: Number(volIn.hv30 ?? 0),
    hv60: Number(volIn.hv60 ?? volIn.hv30 ?? 0), hv90: Number(volIn.hv90 ?? volIn.hv30 ?? 0),
  };
  const earnings = (b.earnings ?? {}) as { date?: string; label?: string };
  const daysToEarnings = earnings.date ? Math.max(0, Math.round((parseISO(earnings.date).getTime() - parseISO(nowISO).getTime()) / 86400000)) : Number((b.daysToEarnings as number) ?? 99);
  const wash = (b.wash ?? null) as { hit: boolean; on: string; amount: number; daysLeft: number } | null;
  const iv = Number(volIn.iv), ivPct = Number(volIn.ivPct ?? 50);
  const pctFactor = ivPct > 70 ? 1.2 : ivPct < 30 ? .8 : 1.0;
  const hvTrend = HV.hv30 > HV.hv60 && HV.hv60 > HV.hv90 ? 'expanding' : HV.hv30 < HV.hv60 && HV.hv60 < HV.hv90 ? 'compressing' : 'stable';
  const hvGap = +Math.abs(HV.hv30 - HV.hv90).toFixed(1);
  const score = (iv / (HV.hv30 || 1)) * pctFactor;
  const gate = {
    spot, iv, ivPct, pctFactor, hv20: HV.hv20, hv30: HV.hv30, hv60: HV.hv60, hv90: HV.hv90,
    hvTrend, hvGap, score, scorePass: score >= .80, earningsPass: daysToEarnings >= 5, capacityPass: book.capacity > 0,
    daysToEarnings, earnings: earnings.label ?? earnings.date ?? 'none', wash, blocked: false,
    flags: [] as { key: string; level: string; head: string; body: string }[],
  };
  if (!gate.scorePass) gate.flags.push({ key: 'score', level: 'block', head: 'Not worth selling this week', body: `Options are cheaper than the stock's own movement. Buyers pay for ${iv}% while it actually moves ${HV.hv30}%, so you would be underpaid.` });
  if (!gate.earningsPass) gate.flags.push({ key: 'earnings', level: 'block', head: 'Earnings is too close', body: `Earnings lands ${gate.earnings}. What you would collect is payment for that event, not for your patience.` });
  if (wash?.hit) gate.flags.push({ key: 'wash', level: 'note', head: 'A tax window is open', body: `You booked a $${wash.amount.toLocaleString()} loss on ${wash.on} and ${wash.daysLeft} days remain. Being called away at a loss and buying back straight after cancels that deduction.` });

  // ── assignment exposure ──
  // Calls are written against the share block, but the put hedge is sized to the
  // WHOLE block. So if the calls are assigned the shares leave and the hedge stays,
  // and a book that is long by construction can end up short by arithmetic.
  // Puts aren't in the request body; derive their delta from the identity
  //   netDelta = shares + longCallΔ − shortCallΔ + putΔ
  // (longCallΔ is not sent either — with no long calls on the book it drops out).
  const netDeltaSent = bookIn.netDelta != null;
  const putDelta = Number(bookIn.putDelta ?? (netDeltaSent ? book.netDelta - shares + book.shortCallDelta : 0));

  // Two readings, because they answer different questions. EVERY call being assigned
  // is the tail; what each leg is actually likely to do is N(d2) per leg, priced off
  // the same chain as the ladder. Capacity keys off the expected path, the warning
  // off the tail — otherwise a book that is merely short-dated looks uninvestable.
  const legT = (exp?: string) => {
    if (!exp) return .25 / 252;
    const sp = spanTo(nowISO, parseISO(exp));
    return Math.max(sp.td + wv * sp.we, .25) / 252;
  };
  // What the put floor costs to keep, every day, whatever the stock does. Sitting
  // out is not free, and a small sale can easily fail to cover it.
  // The floor is ROLLED, not held to decay, so its cost is the premium paid each
  // cycle rather than theta. Theta said ~$1,100/day; a monthly roll of this book is
  // nearer $3,000. Understating the largest expense by 3x is what made far-OTM
  // lottery tickets look free — nothing in the model knew there was a bill to pay.
  const putCt = Number(bookIn.putCt ?? 0) || Math.max(1, Math.round(Math.abs(Number(bookIn.putDelta ?? 0)) / 40));
  const putSpend = Number(bookIn.putCost ?? 0);          // premium paid for the floor
  const putDays  = Math.max(1, Number(bookIn.putDays ?? 30));   // days of cover bought
  const hedgeCarry = putSpend > 0 ? putSpend / putDays : Math.abs(Number(bookIn.longTheta ?? 0));
  const requiredWeekly = hedgeCarry * 7;

  // Shares leave oldest-first, so an assignment books the cost of THOSE lots. The
  // book average is only a stand-in, and on a position built up over time it can be
  // well off. Falls back to the average when no lots are supplied.
  const lotsIn = (bookIn.lots ?? []) as { qty: number; cost: number }[];
  function fifoCost(n: number): number {
    if (!lotsIn.length) return n * book.buyAvg;
    let left = n, cost = 0;
    for (const l of lotsIn) {
      if (left <= 0) break;
      const take = Math.min(left, l.qty);
      cost += take * l.cost; left -= take;
    }
    if (left > 0) cost += left * book.buyAvg;     // more called than we hold lots for
    return cost;
  }
  const legOdds = (openShortCalls as { strike: number; ct: number; expiry?: string }[])
    .map((l) => ({ expiry: l.expiry ?? '', shares: bsAssign(spot, l.strike, legT(l.expiry), iv / 100) * l.ct * 100 }));
  const expectedCalled = legOdds.reduce((a, l) => a + l.shares, 0);
  const sharesAfterAssign = shares - book.shortCallCt * 100;          // tail: all called
  const deltaAfterWorst = sharesAfterAssign + putDelta;
  const deltaAfterAssign = shares - expectedCalled + putDelta;        // expected path
  const assignFloor = shares * INST.floorPct;
  const assignment = {
    sharesAfter: sharesAfterAssign, putDelta,
    expectedCalled: Math.round(expectedCalled),
    deltaAfter: deltaAfterAssign, deltaAfterWorst,
    coveredPct: shares > 0 ? (book.shortCallCt * 100) / shares : 0,
    netShort: deltaAfterAssign < 0, worstNetShort: deltaAfterWorst < 0,
    thin: deltaAfterAssign < assignFloor,
    known: netDeltaSent || bookIn.putDelta != null,
  };
  if (assignment.known && assignment.netShort) {
    gate.flags.push({ key: 'assign', level: 'block', head: 'You would end up betting against it',
      body: `On current odds about ${Math.round(expectedCalled).toLocaleString()} of your ${shares.toLocaleString()} shares get called away. Your puts cover the whole block and stay behind when the shares go, which leaves you ${Math.round(deltaAfterAssign).toLocaleString()}, pointing the wrong way.` });
  } else if (assignment.known && (assignment.thin || assignment.worstNetShort)) {
    gate.flags.push({ key: 'assign', level: 'note', head: 'Not much left if they go',
      body: `About ${Math.round(expectedCalled).toLocaleString()} shares would be called away, leaving ${Math.round(deltaAfterAssign).toLocaleString()} of upside against the ${Math.round(assignFloor).toLocaleString()} you said you would keep.`
        + (assignment.worstNetShort ? ` If all ${book.shortCallCt} went, it would be ${Math.round(deltaAfterWorst).toLocaleString()}, the wrong way round.` : '') });
  }
  gate.blocked = gate.flags.some((f) => f.level === 'block');

  // ══════════════════════════════════════════════════════════════════════
  //  THE WEEK — strike-invariant. Answers "sell or don't, and how much".
  //  Kept apart from the per-strike fit score on purpose: most of what makes a
  //  week good is identical in every cell of the ladder, so folding the two into
  //  one number leaves the strike ranking to the penalties alone.
  // ══════════════════════════════════════════════════════════════════════

  // Upside participation delta — shares + long calls − short calls, PUTS EXCLUDED.
  // Puts are downside insurance; they shouldn't shrink the right to write a call.
  const longCallDelta = Number(bookIn.longCallDelta ?? 0);
  const upsideDelta = shares + longCallDelta - book.shortCallDelta;

  // Tape: where spot sits against its own mean, measured in daily sigmas, and how
  // hard it is trending. Trend matters because mean reversion only pays the seller
  // when there is a mean to revert to — in a persistent trend it caps a melt-up.
  const dailySig = (spot * (HV.hv30 / 100)) / Math.sqrt(252);
  const mean = technicals.ma50 ?? spot;
  const dev = dailySig > 0 ? +((spot - mean) / dailySig).toFixed(2) : 0;
  const trendRaw = technicals.ma50 != null && technicals.ma200 != null && technicals.ma200 !== 0
    ? (technicals.ma50 - technicals.ma200) / technicals.ma200 : 0;
  const trendStrength = clamp(Math.abs(trendRaw) * 12, 0, 1);          // 0…1
  const trendUp = trendRaw > 0 && spot > mean;
  const state = Math.abs(dev) <= 1 ? 'RANGE' : dev > 2 ? 'STRETCH' : dev < -2 ? 'WASHOUT' : 'TREND';

  // Event density over the coming fortnight, and the first thing that really bites.
  const HORIZON = 14;
  const density = cats.filter((c) => c.days <= HORIZON).reduce((a, c) => a + c.sev, 0);
  const heavy = cats.filter((c) => c.sev >= 4)[0] ?? null;
  const nearest = cats[0] ?? null;
  const events = {
    density, horizon: HORIZON, nearest, heavy,
    list: cats.slice(0, 12),
    daysToHeavy: heavy ? heavy.days : (daysToEarnings ?? 99),
  };

  // Dynamic floor — how much upside must stay yours. A flat percentage is wrong
  // into a print and wrong when you are already extended; the modifiers say why.
  const floorParts: { k: string; mult: number; why: string }[] = [];
  let floorMult = 1;
  const push = (k: string, mult: number, why: string) => { floorMult *= mult; floorParts.push({ k, mult, why }); };
  if (events.daysToHeavy <= HORIZON) push('event', 1.40, `${heavy?.label ?? 'a print'} in ${events.daysToHeavy}d, so do not get capped into a gap`);
  if (state === 'WASHOUT') push('washout', 1.25, "below its average, so do not cap the bounce");
  if (state === 'STRETCH') push('stretch', 0.85, 'run up hard, so capping here is fine');
  if (spot < book.buyAvg) push('under_basis', 1.20, 'price is under your average, so being called away books a loss');
  const floorBase = shares * INST.floorPct;
  const floor = Math.round(clamp(floorBase * floorMult, shares * 0.08, shares * 0.40));
  const headroom = upsideDelta - floor;

  // Freeroll. With an OTM floor struck ABOVE basis the corridor is zero and the
  // only structural loss left is the premium paid for the hedge — so the question
  // stops being "can I survive a drawdown" and becomes "is the insurance free yet".
  const putFloor = Number(bookIn.putFloor ?? 0);
  const putCost = Number(bookIn.putCost ?? 0);
  const corridor = putFloor > 0 ? Math.max(0, (book.basis - putFloor) * shares) : 0;
  const maxLoss = corridor + putCost;
  // Numerator is realized PREMIUM, not total realized P&L — the question is whether
  // premium has paid for the structure, so closed share and long-option results
  // don't belong in it.
  const banked = book.realizedPremium;
  const freeroll = maxLoss > 0 ? Math.round((banked / maxLoss) * 100) : 100;
  const freerollRegime = maxLoss <= 0 ? 'unknown' : corridor === 0 ? 'insurance' : 'corridor';

  // ── which week is this? ──────────────────────────────────────────────────────
  // Blending nine factors every week produces the average answer. The situation
  // decides which handful matter, and how much upside is worth giving up.
  const daysSincePrint = lastPrintISO
    ? Math.round((parseISO(nowISO).getTime() - parseISO(lastPrintISO).getTime()) / 86400000) : 999;
  // Without a 52-week high there is no drawdown to measure, and defaulting it to
  // zero would classify every week as EXTENDED RUN — a silent wrong answer rather
  // than an honest missing one.
  const high = Number(b.high52 ?? technicals.high52 ?? 0);
  const haveHigh = high > 0;
  const drawdown = haveHigh ? ((high - spot) / high) * 100 : null;
  const daysToPrint = daysToEarnings ?? 99;
  const dd = drawdown ?? 0;

  const regime =
      daysToPrint <= 7    ? 'EARNINGS WEEK'
    : daysSincePrint <= 5  ? 'JUST AFTER THE PRINT'
    : (haveHigh && dd >= 12) ? 'BEATEN DOWN'
    : (dev >= 1.5 || (haveHigh && dd <= 3)) ? 'EXTENDED RUN'
    : 'RANGE';

  const regimeWhy =
      regime === 'EARNINGS WEEK'         ? `Earnings in ${daysToPrint}d. Premium is event premium; what matters is how far above normal it is.`
    : regime === 'JUST AFTER THE PRINT'  ? `${daysSincePrint}d past the print. Implied vol has collapsed and the tape is still absorbing it.`
    : regime === 'BEATEN DOWN'           ? `${dd.toFixed(0)}% off the high. A bounce is worth being part of.`
    : regime === 'EXTENDED RUN'          ? (haveHigh
        ? `${dd.toFixed(0)}% off the high, ${dev > 0 ? '+' : ''}${dev} from its 50-day. Run up, no event in the way.`
        : `${dev > 0 ? '+' : ''}${dev} from its 50-day. Run up, no event in the way.`)
    : haveHigh                           ? 'No event near, sitting mid-range.'
    :                                      'No event near. No 52-week high on file, so the drawdown is unknown.';

  // How much upside to KEEP, not how much to sell. Rises when the stock is beaten
  // down — a bounce is worth joining — and falls when the premium on offer is
  // exceptional. The old model paid you more the more you held back, which had it
  // exactly backwards: it never asked what you were being offered to give it up.
  // No drawdown known -> sit at the neutral 30% rather than the aggressive floor.
  let keepPct = haveHigh ? clamp(20 + dd * 2, 20, 50) : 30;
  const keepWhy: string[] = [haveHigh ? `${dd.toFixed(0)}% off the high` : 'drawdown unknown, using a neutral keep'];
  if (ivPct >= 70) { keepPct = Math.max(20, keepPct - 5); keepWhy.push('premium is rich, so take more of it'); }
  if (ivPct <= 30) { keepPct = Math.min(50, keepPct + 5); keepWhy.push('premium is thin, so hold back'); }
  if (regime === 'JUST AFTER THE PRINT') { keepPct = Math.max(10, keepPct - 8); keepWhy.push('vol crushed, little left to wait for'); }

  // Measured history overrides the guess. After a print, what matters is what this
  // stock has actually done next: if it recovers, keep more and be in it; if it
  // stays down, there is less upside to protect. NVDA's own record says it recovers
  // ~6% within thirty days of a bad print, which is the opposite of the assumption
  // the placeholder encoded.
  let measured: { band: string; n: number; d30: number; applied: boolean } | null = null;
  if (bandStats && daysSincePrint <= 30) {
    const lift = clamp(bandStats.d30 * 2, -15, 25);
    keepPct = clamp(keepPct + lift, 10, 60);
    keepWhy.push(`after ${bandStats.band} prints this has run ${bandStats.d30 > 0 ? '+' : ''}${bandStats.d30}% in 30 days (${bandStats.n} on record)`);
    measured = { ...bandStats, applied: true };
  } else if (bandStats) {
    measured = { ...bandStats, applied: false };
  }

  // The floor and the calls are one decision, and this is where they meet. Whatever
  // sits between spot and the put strike is unprotected, and call premium is the only
  // thing cushioning it. A floor tucked close underneath means you are already
  // covered, so you can afford to keep more upside and sell fewer calls. A floor left
  // far below means the premium is doing that work, and you need more of it.
  const floorGapPct = putFloor > 0 ? ((spot - putFloor) / spot) * 100 : null;
  if (floorGapPct != null) {
    if (floorGapPct <= 3) {
      keepPct = Math.min(60, keepPct + 8);
      keepWhy.push(`floor only ${floorGapPct.toFixed(0)}% under spot, so you are covered without selling as much`);
    } else if (floorGapPct >= 10) {
      keepPct = Math.max(15, keepPct - 6);
      keepWhy.push(`floor ${floorGapPct.toFixed(0)}% under spot, so premium is carrying the downside`);
    }
  }

  // Keep is a share of the SHARE BLOCK, which is how you actually think about it:
  // "keep 1,500 shares uncovered". The budget is whatever upside sits above that.
  keepPct = Math.round(keepPct);
  const keepDelta = Math.round(shares * keepPct / 100);
  const hardFloor = keepDelta;
  const room = Math.max(0, upsideDelta - hardFloor);
  const budget = Math.round(room);
  const aggression = upsideDelta > 0 ? budget / upsideDelta : 0;

  // ── the week's forces ──
  // Named and worded for a reader, not a desk. Every label answers a question a
  // person would actually ask, and every push line is a sentence rather than a
  // term of art. The maths is unchanged.
  const wf: { key: string; family: string; name: string; w: number; score: number; rows: [string, string][]; push: string }[] = [];
  wf.push({ key: 'iv_pctile', family: 'OPTIONS MARKET', name: 'OPTION PRICING', w: .16, score: sPct(ivPct),
    rows: [['vs the past year', `${Math.round(ivPct)} out of 100`], ['option pricing now', `${iv.toFixed(1)}%`], ['size multiplier', pctFactor.toFixed(2)]],
    push: ivPct >= 60 ? 'Options cost more than they usually do, which makes this a good week to be the seller.'
        : ivPct <= 30 ? 'Options are cheap against their own year, so sell small and keep it short.'
        : 'Option pricing is middling, so the level on its own gives you no edge.' });

  wf.push({ key: 'iv_spread', family: 'OPTIONS MARKET', name: 'PAY VS MOVEMENT', w: .11, score: sTanh(((iv - HV.hv30) / (HV.hv30 || 1)) * 2.5),
    rows: [['buyers are paying for', `${iv.toFixed(1)}%`], ['it is actually moving', `${HV.hv30.toFixed(1)}%`], ['movement is', hvTrend === 'expanding' ? 'picking up' : hvTrend === 'compressing' ? 'settling down' : 'steady']],
    push: iv > HV.hv30
      ? `You are paid for ${(iv - HV.hv30).toFixed(1)} points more movement than the stock is making.`
      : 'The stock is moving more than buyers are paying for, so you are underpaid this week.' });

  // THE CALENDAR, split three ways. Each date gets its own clock, so none can hide
  // behind another. The key stays 'event' so a week of stored snapshots still lines up.
  wf.push({ key: 'event', family: 'THE CALENDAR', name: 'THE PRINT', w: .23, score: sDecay(daysToEarnings - 7),
    rows: [['next print', earnings.date ?? 'none'], ['days away', String(daysToEarnings)], ['how busy, 2 weeks', String(density)]],
    push: daysToEarnings <= 7
      ? `The print is ${daysToEarnings}d away, so do not get capped into a gap.`
      : `Nothing from this name for ${daysToEarnings - 7} days after this expiry, so the week is clear of it.` });

  {
    const nextPeer = peers.filter((x) => x.days >= 0).sort((x, y) => x.days - y.days)[0] ?? null;
    wf.push({ key: 'peers', family: 'THE CALENDAR', name: 'THE NEIGHBOURHOOD', w: .04,
      // Unknown is NOT clear. With no peer table the factor sits neutral rather than
      // claiming a clear runway it never checked.
      score: !peersKnown ? 0 : nextPeer ? sDecay(nextPeer.days - 3) : 30,
      rows: [['next chip print', nextPeer ? `${nextPeer.ticker}, ${nextPeer.days}d` : peersKnown ? 'none in range' : 'not on file'],
             ['confirmed', nextPeer ? (nextPeer.confirmed ? 'yes' : 'estimated') : '-'],
             ['vs SMH', relStrength ? `${relStrength.gap > 0 ? '+' : ''}${relStrength.gap}% / ${relStrength.days}d` : 'no series']],
      push: !peersKnown ? 'No peer calendar on file, so this is sitting neutral rather than guessing.'
          : nextPeer && nextPeer.days <= 3 ? `${nextPeer.ticker} reports in ${nextPeer.days}d and semis move together, so the gap risk is not only NVDA's.`
          : 'No chip print close enough to drag the group around this week.' });
  }

  {
    const nextMacro = cats.filter((c) => c.key === 'macro_events' && c.sev >= 3)[0] ?? null;
    const macroOnFile = calSources.some((x) => /^macro_events:\d+$/.test(x));
    wf.push({ key: 'macro', family: 'THE CALENDAR', name: 'THE ECONOMY', w: .05,
      score: !macroOnFile ? 0 : nextMacro ? sDecay(nextMacro.days - 2) : 30,
      rows: [['next print', nextMacro ? nextMacro.label : macroOnFile ? 'none in range' : 'not on file'],
             ['days away', nextMacro ? String(nextMacro.days) : '-'],
             ['calendar', macroOnFile ? 'on file' : 'missing']],
      push: !macroOnFile ? 'No economic calendar on file, so this is sitting neutral.'
          : nextMacro && nextMacro.days <= 3 ? `${nextMacro.label} lands in ${nextMacro.days}d, inside what you would be writing.`
          : 'Nothing scheduled close enough to move the week.' });
  }

  wf.push({ key: 'trend', family: 'THE TAPE', name: 'THE TREND', w: .13, score: trendUp ? -trendStrength * 40 : trendStrength * 30,
    rows: [['50-day vs 200-day', `${(trendRaw * 100).toFixed(1)}%`], ['how strong', trendStrength >= .66 ? 'strong' : trendStrength >= .33 ? 'moderate' : 'weak'], ['direction', trendUp ? 'rising' : 'flat or falling']],
    push: trendUp
      ? 'It is climbing, so selling tight here caps the run you own the shares for.'
      : 'No climb to cap right now, so you can write with a freer hand.' });

  wf.push({ key: 'stretch', family: 'THE TAPE', name: 'THE RUN-UP', w: .09, score: clamp(dev * 18, -35, 35) * (1 - .8 * trendStrength),
    rows: [['above its 50-day', `${dev > 0 ? '+' : ''}${dev} normal days`], ['reading', state === 'STRETCH' ? 'run up hard' : state === 'WASHOUT' ? 'beaten down' : state === 'TREND' ? 'drifting' : 'mid-range'], ['trimmed for the trend', `x${(1 - .8 * trendStrength).toFixed(2)}`]],
    push: state === 'STRETCH' ? 'It has run well past its average, so a pullback from here pays you.'
        : state === 'WASHOUT' ? 'It is well below its average, so do not cap the bounce back.'
        : 'Sitting near its average, with no real edge either way.' });

  wf.push({ key: 'rsi', family: 'THE TAPE', name: 'MOMENTUM', w: .05, score: technicals.rsi14 != null ? sPct(technicals.rsi14) : 0,
    rows: [['momentum, 0 to 100', technicals.rsi14 != null ? technicals.rsi14.toFixed(0) : 'none'], ['high this year', technicals.high52 != null ? `$${technicals.high52.toFixed(2)}` : 'none'], ['low this year', technicals.low52 != null ? `$${technicals.low52.toFixed(2)}` : 'none']],
    push: (technicals.rsi14 ?? 50) >= 70 ? 'Buyers are in charge, and the run is stretched alongside you.'
        : (technicals.rsi14 ?? 50) <= 30 ? 'Sellers are in charge, and a bounce would run straight into your strikes.'
        : 'Balanced, with neither side pushing hard.' });

  wf.push({ key: 'relative', family: 'THE TAPE', name: 'AGAINST THE GROUP', w: .06,
    // Outperformance is a stretch measure, so it carries the same sign as the run-up:
    // leading the group is a better moment to sell upside, lagging it is a worse one.
    score: relStrength ? clamp(relStrength.gap * 3, -35, 35) : 0,
    rows: [['this name', relStrength ? `${relStrength.self > 0 ? '+' : ''}${relStrength.self}%` : 'no series'],
           ['SMH', relStrength ? `${relStrength.ref > 0 ? '+' : ''}${relStrength.ref}%` : '-'],
           ['sessions compared', relStrength ? String(relStrength.days) : '-']],
    push: !relStrength ? 'No reference series, so the group comparison is sitting out.'
        : relStrength.gap >= 5 ? `Running ${relStrength.gap}% ahead of the group, which is a better moment to sell upside than a worse one.`
        : relStrength.gap <= -5 ? `Lagging the group by ${Math.abs(relStrength.gap)}%, so there is catch-up you would be capping.`
        : 'Moving with the group, so nothing here argues either way.' });

  // THE RECORD — measured, not assumed. Rising into and through prints argues
  // AGAINST capping upside, hence the negative sign. It only speaks when a print is
  // actually in play; the rest of the year it has nothing to say about one week.
  {
    const after = daysSincePrint <= 30 && bandStats;
    const before = daysToEarnings <= 21 && record;
    const sc = after ? -clamp(bandStats!.d30 * 3, -40, 40)
             : before ? -clamp(record!.med * 4, -40, 40) : 0;
    wf.push({ key: 'record', family: 'THE RECORD', name: 'WHAT IT DID LAST TIME', w: .08, score: sc,
      rows: [['prints on file', record ? String(record.n) : 'none'],
             ['landed better than -8%', record ? `${record.survived} of ${record.n}` : '-'],
             ['after the last one', bandStats ? `${bandStats.d30 > 0 ? '+' : ''}${bandStats.d30}% by day 30, n=${bandStats.n}` : 'no band match']],
      push: after ? `After ${bandStats!.band} prints this has run ${bandStats!.d30 > 0 ? '+' : ''}${bandStats!.d30}% inside 30 sessions, on ${bandStats!.n}. Capping that costs you.`
          : before ? `${record!.survived} of ${record!.n} prints landed better than -8%, median ${record!.med > 0 ? '+' : ''}${record!.med}%. Its record argues against capping into one.`
          : 'No print close enough for its record to say anything about this week.' });
  }

  wf.push({ key: 'freeroll', family: 'THE POSITION', name: 'THE HEDGE', w: .08, score: clamp((freeroll - 100) / 2, -30, 30),
    rows: [['premium banked', `$${Math.round(banked).toLocaleString()}`], ['what it has to cover', maxLoss > 0 ? `$${Math.round(maxLoss).toLocaleString()}` : 'none'], ['covered so far', `${freeroll}%`]],
    push: freerollRegime === 'insurance'
      ? 'Your put floor sits above what you paid for the shares, so premium only has the insurance left to pay for.'
      : freeroll >= 100 ? 'Premium collected already covers the whole downside gap.'
      : `${100 - freeroll}% of the downside gap is still uncovered.` });

  wf.push({ key: 'headroom', family: 'THE POSITION', name: 'ROOM TO RISE', w: .05, score: floor > 0 ? sTanh(headroom / floor) : 0,
    rows: [['upside you still own', `${Math.round(upsideDelta).toLocaleString()} shares`], ['least you will keep', `${floor.toLocaleString()} shares`], ['spare', `${Math.round(headroom).toLocaleString()} shares`]],
    push: headroom <= 0
      ? 'You are already at the least upside you said you would keep.'
      : `About ${Math.round(headroom).toLocaleString()} shares of upside above your own minimum.` });

  wf.push({ key: 'assignment', family: 'THE POSITION', name: 'BEING CALLED AWAY', w: .10, score: floor > 0 ? sTanh(deltaAfterAssign / floor) : 0,
    rows: [['likely called away', `${Math.round(expectedCalled).toLocaleString()} shares`], ['hedge that stays', `${Math.round(putDelta).toLocaleString()}`], ['upside left after', `${Math.round(deltaAfterAssign).toLocaleString()}`]],
    push: deltaAfterAssign < 0
      ? 'If these calls get exercised the shares go but the put hedge stays, and you end up betting against the stock. Write nothing more until that changes.'
      : `About ${Math.round(deltaAfterAssign).toLocaleString()} shares of upside survives if the calls get exercised.` });

  // Swap the fixed weights for the regime's, then normalise so the composite stays
  // on the same 0-100 scale however the rows are written.
  const rw = REGIME_WEIGHTS[regime];
  if (rw) {
    for (const f of wf) f.w = rw[f.key] ?? 0.01;
    const tot = wf.reduce((a, f) => a + f.w, 0) || 1;
    for (const f of wf) f.w = +(f.w / tot).toFixed(4);
  }

  const weekScore = Math.round(clamp(50 + wf.reduce((a, f) => a + f.w * f.score, 0), 0, 100));

  // A score means little on its own — 68 reads differently if last week was 61.
  // One snapshot per ticker per day, idempotent, so opening the planner repeatedly
  // does not litter the series. Comparison is on CONTRIBUTION rather than raw score,
  // because that is what the screen shows and a weight change would otherwise read
  // as a market change.
  type Snap = { taken_on: string; score: number; stance: string; factors: Record<string, number> };
  let prior: Snap | null = null;
  let snapNote = 'skipped';
  const nowContrib: Record<string, number> = {};
  for (const f of wf) nowContrib[f.key] = +(f.w * f.score).toFixed(1);
  const stance = weekScore >= 65 ? 'SELL HARD' : weekScore >= 45 ? 'SELL NORMAL' : weekScore >= 30 ? 'SELL LIGHT' : 'SIT OUT';
  const prescription = {
    'SELL HARD':   { deltaLo: .30, deltaHi: .35, sizePct: 1.0,  tenor: 'take the date that pays more' },
    'SELL NORMAL': { deltaLo: .25, deltaHi: .30, sizePct: 0.75, tenor: 'the nearest clear date' },
    'SELL LIGHT':  { deltaLo: .18, deltaHi: .25, sizePct: 0.5,  tenor: 'keep it short' },
    'SIT OUT':     { deltaLo: .15, deltaHi: .22, sizePct: 0.0,  tenor: 'sitting this one out is the answer' },
  }[stance]!;
  // ── the score buys a DELTA BUDGET, and the ladder spends it ──────────────────
  // The old model picked one of four buckets, so 46 and 64 gave identical orders.
  // Aggression is continuous now: how much of the room above the hard floor this
  // week justifies selling. That is the score's actual job.
  // Capacity in CONTRACTS, not delta. Anything being bought back frees its lots,
  // which is why "65 contracts" is reachable on a roll and not otherwise.
  const rollingCt = Number(bookIn.rollingCt ?? 0);
  const capacityCt = Math.max(0, Math.floor(shares / 100) - book.shortCallCt + rollingCt);

  const maxLotsFloor = Math.floor((upsideDelta - floor) / 100);
  const maxLotsAssign = Math.floor((shares - expectedCalled + putDelta) / 100);
  const maxLots = Math.max(0, Math.min(maxLotsFloor, maxLotsAssign, capacityCt));
  const binding = maxLots === 0 ? (maxLotsAssign <= maxLotsFloor ? 'assignment' : 'floor')
    : maxLotsAssign < maxLotsFloor ? 'assignment' : 'floor';
  // A rich week you cannot act on is not a sell signal. Capacity overrides the score.
  const effStance = maxLots === 0 ? 'SIT OUT' : stance;
  const stanceReason = maxLots === 0
    ? (binding === 'assignment'
        ? 'No room to write. If what you already hold gets called away, you end up betting against the stock.'
        : 'No room to write. You are already at the least upside you said you would keep.')
    : null;
  if (supaUrl && supaKey) {
    const sh = { apikey: supaKey, Authorization: `Bearer ${supaKey}`, 'Content-Type': 'application/json' };
    const backTo = ymd(new Date(parseISO(nowISO).getTime() - 5 * 86400000));
    try {
      const r = await fetch(`${supaUrl}/rest/v1/planner_week_snapshots?ticker=eq.${TICKER}&taken_on=lte.${backTo}`
        + `&select=taken_on,score,stance,factors&order=taken_on.desc&limit=1`, { headers: sh });
      if (r.ok) prior = ((await r.json()) as Snap[])[0] ?? null;
    } catch { /* no history yet is a normal state, not an error */ }
    try {
      const wr = await fetch(`${supaUrl}/rest/v1/planner_week_snapshots?on_conflict=ticker,taken_on`, {
        method: 'POST',
        headers: { ...sh, Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify({ ticker: TICKER, taken_on: nowISO, score: weekScore, stance: effStance,
          factors: nowContrib,
          posture: { floor, upsideDelta, freeroll, headroom } }),
      });
      // Reported, not swallowed: a write that fails quietly means the comparison
      // simply never starts, and you would not find out for a week.
      snapNote = wr.ok ? 'written' : `HTTP${wr.status}: ${(await wr.text()).slice(0, 120)}`;
    } catch (e) { snapNote = `ERR ${e}`; }
  }

  const week = {
    score: weekScore, stance: effStance, rawStance: stance, stanceReason, binding, prescription,
    lots: { base: Math.max(0, Math.round(maxLots * prescription.sizePct)), max: maxLots,
            byFloor: Math.max(0, maxLotsFloor), byAssignment: Math.max(0, maxLotsAssign), free: book.freeShares / 100 },
    forces: wf.map((f) => ({
      ...f,
      contribution: nowContrib[f.key],
      change: prior ? +(nowContrib[f.key] - (prior.factors?.[f.key] ?? 0)).toFixed(1) : null,
    })),
    prior: prior ? {
      score: prior.score, stance: prior.stance, takenOn: prior.taken_on,
      change: weekScore - prior.score,
      daysAgo: Math.round((parseISO(nowISO).getTime() - parseISO(prior.taken_on).getTime()) / 86400000),
    } : null,
    caption: (() => {
      const sorted = wf.slice().sort((x, y) => y.w * y.score - x.w * x.score);
      const up = sorted.filter((f) => f.score > 0), dn = sorted.filter((f) => f.score < 0);
      const lead = up.length ? up[0].name.toLowerCase() : 'nothing';
      const drag = dn.length ? dn[dn.length - 1].name.toLowerCase() : null;
      return `${lead} does most of the work, ${drag ? drag + ' is what argues back' : 'nothing argues back'}`;
    })(),
  };

  const posture = {
    upsideDelta, floor, floorBase: Math.round(floorBase), floorMult: +floorMult.toFixed(2), floorParts,
    headroom, dev, state, trendStrength: +trendStrength.toFixed(2), trendUp,
    freeroll, freerollRegime, banked, corridor, putCost, maxLoss,
  };

  // ── expiries + priced chains (per-contract, ct-independent; the app scales) ──
  const expiryDates = (polyExpiries.length ? polyExpiries : fallbackExpiries(nowISO)).slice(0, 6);
  const lo = Math.ceil((spot * .96) / STRIKE_STEP) * STRIKE_STEP;
  const hi = Math.floor((spot * 1.12) / STRIKE_STEP) * STRIKE_STEP;
  const affected = book.longCallCt;

  // How many contracts each expiry already carries — piling a sixth lot onto a date
  // that already holds sixty is not the same trade as opening a fresh one.
  const loadByExpiry: Record<string, number> = {};
  for (const s of openShortCalls as { strike: number; ct: number; expiry?: string }[]) {
    if (s.expiry) loadByExpiry[s.expiry] = (loadByExpiry[s.expiry] ?? 0) + s.ct;
  }
  const refLots = Math.max(1, week.lots.base || 1);
  const STYLE_SHIFT: Record<string, number> = { closer: 0.16, balanced: 0, further: -0.13 };
  const style = String(b.style ?? 'balanced');
  const bandMid = clamp((prescription.deltaLo + prescription.deltaHi) / 2 + (STYLE_SHIFT[style] ?? 0), .10, .60);
  const bandHalf = (prescription.deltaHi - prescription.deltaLo) / 2;

  const expiries = expiryDates.map((iso) => {
    const dt = parseISO(iso); const s = spanTo(nowISO, dt); const volDays = s.td + wv * s.we; const T = Math.max(volDays, .25) / 252;
    const load = loadByExpiry[iso] ?? 0;
    const eventInside = cats.filter((c) => c.sev >= 4 && c.days <= s.cal)[0] ?? null;
    // You are normally rolling: contracts expiring on or before this date get
    // bought back, which hands their lots back to you. Only calls dated PAST this
    // expiry genuinely tie shares up.
    // Default: you are normally rolling, so anything expiring on or before this
    // date gets bought back and hands its lots back. If you have actually picked
    // legs to close, that choice wins outright — never both, or the lots
    // double-count.
    const autoRollable = (openShortCalls as { ct: number; expiry?: string }[])
      .reduce((a, l) => a + (l.expiry && l.expiry <= iso ? l.ct : 0), 0);
    const rollableHere = rollingCt > 0 ? rollingCt : autoRollable;
    const capHere = Math.max(0, Math.floor(shares / 100) - book.shortCallCt + rollableHere);
    // Legs being closed cannot be called away. Counting them against the new sale
    // made every near-the-money package look like it turned the book short.
    const keptCalled = rollingCt > 0
      ? Math.max(0, expectedCalled * (1 - rollingCt / Math.max(book.shortCallCt, 1)))
      : legOdds.reduce((a, l) => a + (l.expiry && l.expiry <= iso ? 0 : l.shares), 0);
    const chain: Cell[] = [];
    for (let k = lo; k <= hi + 1e-9; k += STRIKE_STEP) {
      const prem = bsCall(spot, k, T, iv / 100);
      const fair = bsCall(spot, k, T, HV.hv30 / 100);
      const d1 = bsDelta(spot, k, T, iv / 100);
      const intrinsic = Math.max(0, spot - k);
      const span = LOOKBACKS.map((L) => (prem - bsCall(spot, k, T, HV[L] / 100)) * 100);
      const edgeHi = Math.max(...span), edgeLo = Math.min(...span);
      const belowWall = k < wall;
      const fin = (x: number) => (Number.isFinite(x) ? x : 0);        // never emit NaN/Infinity → JSON null
      chain.push({
        strike: +k.toFixed(2), prem, fair, sellable: prem >= .05,
        intrinsic, ext: prem - intrinsic, extPct: prem > 0 ? (prem - intrinsic) / prem : 0,
        edge: (prem - fair) * 100, edgePct: prem > 0 ? (prem - fair) / prem : 0,
        edgeHi, edgeLo, edgePctHi: prem > 0 ? fin(edgeHi / (prem * 100)) : 0, edgePctLo: prem > 0 ? fin(edgeLo / (prem * 100)) : 0, edgeCrosses: edgeHi > 0 && edgeLo < 0,
        assign: bsAssign(spot, k, T, iv / 100), delta: d1,
        effective: k + prem, vsBasis: k + prem - book.basis,
        side: belowWall ? 'adverse' : k === wall ? 'matched' : 'favorable',
        advCost: belowWall ? (wall - k) * 100 * Math.min(affected, book.capacity) : 0,
        affected: Math.min(affected, book.capacity),
      });
    }
    // ── the fit score — strike-varying only, measured against the week's prescription.
    // Everything the week already decided (vol, tape, events) is deliberately absent:
    // it is identical in every cell and would only shift the whole ladder.
    const bestPerDay = Math.max(...chain.map((c) => (c.prem * 100) / Math.max(s.cal, 1)), 1);
    // One expected move for this tenor, so a strike can say how far out it sits in
    // units the tape actually trades in rather than in dollars.
    const emMove = spot * (iv / 100) * Math.sqrt(T);
    for (const c of chain) {
      const perDay = (c.prem * 100) / Math.max(s.cal, 1);
      const bandDist = Math.max(0, Math.abs(c.delta - bandMid) - bandHalf);
      // The concrete instruction: at this strike, this many contracts spends the
      // week's budget. Further out means a smaller delta each, so more of them —
      // which is why the same budget reads as 25 near the money and 65 far out.
      const wantCt = c.delta > 0 ? Math.round(budget / (c.delta * 100)) : 0;
      const floorCt = c.delta > 0 ? Math.floor((upsideDelta - floor) / (c.delta * 100)) : capHere;
      const suggestCt = Math.max(0, Math.min(wantCt, capHere, floorCt));
      const useCt = suggestCt > 0 ? suggestCt : refLots;
      const deltaSold = c.delta * useCt * 100;
      const freeAfter = upsideDelta - deltaSold;
      const afterAssign = shares - keptCalled - deltaSold + putDelta;
      const credit = c.prem * suggestCt * 100;          // cash received, incl. intrinsic
      // Only EXTRINSIC value is income. A strike below spot pays a big "premium"
      // that is mostly your own stock's value being handed back — scoring on the
      // gross made deep-in-the-money strikes look like the best earners on the
      // board, when they are really a discount on the shares.
      const income = c.ext * suggestCt * 100;
      // The same package priced at the year's median implied vol. The gap is what
      // today's vol is worth in cash — the sentence "normally $18K, today $43K".
      const normalIncome = ivMedian != null
        ? Math.max(0, bsCall(spot, c.strike, T, ivMedian / 100) - Math.max(0, spot - c.strike)) * suggestCt * 100
        : null;
      const ivPremium = normalIncome != null ? income - normalIncome : null;
      const paidPerDelta = deltaSold > 0 ? income / deltaSold : 0;
      // Gamma, as a scenario rather than a Greek: the budget says 2,145 of upside
      // sold, but only while nothing moves. One expected move up and a package can
      // have sold everything you own.
      const deltaAfterMove = bsDelta(spot + emMove, c.strike, T, iv / 100) * suggestCt * 100;
      const upsideAfterMove = upsideDelta - deltaAfterMove;
      // Theta, at the level that matters: does this week's premium out-earn the
      // daily bleed on the hedge?
      const perDayPkg = income / Math.max(s.cal, 1);
      const netCarry = perDayPkg - hedgeCarry;
      // What share of the floor's cost this package pays for over its own life.
      const requiredHere = hedgeCarry * s.cal;
      const coversPct = requiredHere > 0 ? Math.round((income / requiredHere) * 100) : 100;
      const parts = [
        { k: 'paid_per_delta', w: .20, s: 0 },   // filled in below, needs the whole ladder
        { k: 'holds_a_move',   w: .18, s: floor > 0 ? sTanh((upsideAfterMove - floor) / floor) : 0 },
        { k: 'in_band',        w: .18, s: clamp(50 - bandDist * 500, -50, 50) },
        { k: 'covers_carry',   w: .13, s: clamp((coversPct - 100) / 2, -50, 50) },
        { k: 'assignment',     w: .11, s: floor > 0 ? sTanh(afterAssign / floor) : 0 },
        { k: 'headroom',       w: .10, s: floor > 0 ? sTanh((freeAfter - floor) / floor) : 0 },
        { k: 'over_basis',     w: .07, s: sTanh(((c.strike - book.basis) / (book.basis || 1)) * 20) },
        { k: 'expiry_load',    w: .03, s: clamp(50 - load * 1.5, -50, 50) },
      ];
      const warns: string[] = [];
      if (c.delta > .45) warns.push('NEAR THE MONEY');
      if (c.prem < .12) warns.push('BARELY PAYS');
      if (income < 50) warns.push('BARELY WORTH IT');
      if (coversPct < 60) warns.push(`ONLY ${coversPct}% OF THE HEDGE`);
      if (upsideAfterMove < 0) warns.push('SOLD OUT ON A MOVE');
      if (state === 'STRETCH' && c.delta > .35) warns.push('TOO TIGHT');
      if (state === 'WASHOUT' && c.delta > .30) warns.push('CAPS THE BOUNCE');
      const blocks: string[] = [];
      if (c.strike < book.basis) blocks.push(`Below the $${book.basis.toFixed(2)} you paid`);
      if (freeAfter < floor) blocks.push(`Leaves ${Math.round(freeAfter).toLocaleString()} upside, under your ${floor.toLocaleString()} minimum`);
      if (afterAssign < 0) blocks.push('Being called away here would leave you short');
      if (eventInside) blocks.push(`${eventInside.label} lands before this expiry`);
      const PEN: Record<string, number> = { 'SLOW EARNER': 12, 'NEAR THE MONEY': 10, 'BARELY PAYS': 14, 'TOO TIGHT': 10, 'CAPS THE BOUNCE': 10 };
      const raw = clamp(50 + parts.reduce((a, p) => a + p.w * p.s, 0), 0, 100);
      Object.assign(c, {
        perDay, deltaSold, freeAfter, afterAssign, warns, blocks,
        em: emMove > 0 ? (c.strike - spot) / emMove : 0,
        suggestCt, wantCt, credit, income, paidPerDelta, rollable: rollableHere, capHere,
        normalIncome: normalIncome == null ? null : Math.round(normalIncome),
        ivPremium: ivPremium == null ? null : Math.round(ivPremium),
        upsideAfterMove: Math.round(upsideAfterMove), deltaAfterMove: Math.round(deltaAfterMove),
        perDayPkg: Math.round(perDayPkg), netCarry: Math.round(netCarry),
        coversPct, requiredHere: Math.round(requiredHere),
        cappedBy: wantCt > capHere ? 'covered shares' : null,
        // What the shares book if this package is called away: sale proceeds less
        // the cost of the specific lots that leave, oldest first.
        calledShares: suggestCt * 100,
        calledCost: +fifoCost(suggestCt * 100).toFixed(2),
        calledPL: +(c.strike * suggestCt * 100 - fifoCost(suggestCt * 100)).toFixed(2),
        calledAvg: suggestCt > 0 ? +(fifoCost(suggestCt * 100) / (suggestCt * 100)).toFixed(2) : 0,
        calledPerCt: (c.strike - book.buyAvg) * 100,
        // How far the strike clears the break-even the whole position is measured
        // against (purchase average adjusted for option results). Strike alone, not
        // strike-plus-premium: the premium is already its own line, and folding it in
        // here would flatter every strike by the amount you are paid to take it.
        clearsBy: +(c.strike - book.basis).toFixed(2),
        fitParts: parts.map((p) => ({ ...p, s: +p.s.toFixed(1), contribution: +(p.w * p.s).toFixed(1) })),
        fit: Math.round(Math.max(0, raw - warns.reduce((a, w) => a + (PEN[w] ?? 8), 0))),
      });
    }
    // paid-per-delta only means something against the rest of the ladder, so it is
    // scored once every package exists, then folded into the fit.
    const bestPPD = Math.max(...chain.map((c) => c.paidPerDelta ?? 0), 0.0001);
    const PEN2: Record<string, number> = { 'BARELY WORTH IT': 14, 'NEAR THE MONEY': 10, 'BARELY PAYS': 14,
      'TOO TIGHT': 10, 'CAPS THE BOUNCE': 10, 'DOES NOT COVER THE HEDGE': 16, 'SOLD OUT ON A MOVE': 14 };
    for (const c of chain) {
      const p = c.fitParts?.find((x) => x.k === 'paid_per_delta');
      if (!p) continue;
      p.s = +sTanh(2 * ((c.paidPerDelta ?? 0) / bestPPD - .7)).toFixed(1);
      p.contribution = +(p.w * p.s).toFixed(1);
      const raw = clamp(50 + (c.fitParts ?? []).reduce((a, x) => a + x.w * x.s, 0), 0, 100);
      c.fit = Math.round(Math.max(0, raw - (c.warns ?? []).reduce((a, w) => a + (PEN2[w] ?? 8), 0)));
    }
    const live = chain.filter((c) => !c.blocks?.length);
    const ordered = live.slice().sort((x, y) => (y.fit ?? 0) - (x.fit ?? 0));
    ordered.forEach((c, i) => { if (i < 3) c.rank = i + 1; });
    const pick = ordered[0] ?? null;
    if (pick) pick.isPick = true;

    return { key: iso, iso, label: `${MONTHS[dt.getUTCMonth()]} ${dt.getUTCDate()}`, dow: DOW[dt.getUTCDay()], cal: s.cal, td: s.td, we: s.we, volDays: +volDays.toFixed(1), T,
      load, eventInside, rollable: rollableHere, rollSource: rollingCt > 0 ? 'selected' : 'auto',
      keptCalled: Math.round(keptCalled),
      capacityCt: capHere,
      pickStrike: pick?.strike ?? null, chain };
  });

  // ── split packages ───────────────────────────────────────────────────────────
  // The normal trade is the nearest expiry AND the one after — from a Monday, both
  // Wednesday and Friday. Two ladders side by side cannot express that: the legs
  // share ONE delta budget and ONE pool of covered lots, so a 30/30 split spends
  // what 60 on a single date spends while spreading the assignment across two.
  interface Split {
    legs: { iso: string; label: string; strike: number; ct: number; income: number; delta: number }[];
    ct: number; income: number; deltaSold: number; coversPct: number; days: number;
    normalIncome: number | null; ivPremium: number | null;
  }
  const splits: Split[] = [];
  if (expiries.length >= 2 && budget > 0) {
    const [e1, e2] = expiries;
    // Selling into the later date implies buying back anything expiring before it,
    // so the pool is the further expiry's capacity, shared by both legs.
    const pool = Math.max(0, e2.capacityCt ?? 0);
    const best = (e: typeof e1) =>
      e.chain.filter((c) => !c.blocks?.length && c.delta > 0.05).sort((x, y) => (y.fit ?? 0) - (x.fit ?? 0)).slice(0, 3);
    for (const a of best(e1)) {
      for (const b of best(e2)) {
        const ctA = clamp(Math.round((budget / 2) / (a.delta * 100)), 1, pool);
        const ctB = clamp(Math.round((budget / 2) / (b.delta * 100)), 1, pool - ctA);
        if (ctB < 1) continue;
        const incA = a.ext * ctA * 100, incB = b.ext * ctB * 100;
        const days = Math.max(e1.cal, e2.cal);
        const nA = ivMedian != null ? Math.max(0, bsCall(spot, a.strike, e1.T, ivMedian / 100) - Math.max(0, spot - a.strike)) * ctA * 100 : null;
        const nB = ivMedian != null ? Math.max(0, bsCall(spot, b.strike, e2.T, ivMedian / 100) - Math.max(0, spot - b.strike)) * ctB * 100 : null;
        const norm = nA != null && nB != null ? nA + nB : null;
        splits.push({
          legs: [{ iso: e1.iso, label: e1.label, strike: a.strike, ct: ctA, income: Math.round(incA), delta: a.delta },
                 { iso: e2.iso, label: e2.label, strike: b.strike, ct: ctB, income: Math.round(incB), delta: b.delta }],
          ct: ctA + ctB, income: Math.round(incA + incB),
          deltaSold: Math.round(a.delta * ctA * 100 + b.delta * ctB * 100),
          coversPct: hedgeCarry > 0 ? Math.round(((incA + incB) / (hedgeCarry * days)) * 100) : 100,
          days, normalIncome: norm == null ? null : Math.round(norm),
          ivPremium: norm == null ? null : Math.round(incA + incB - norm),
        });
      }
    }
    splits.sort((x, y) => y.income - x.income);
    splits.length = Math.min(3, splits.length);
  }

  // ── the floor ────────────────────────────────────────────────────────────────
  // Calls and puts are one decision. A floor left where it was while the stock ran
  // away protects a price you are well above, and forces the call side to sell
  // deeper than it should to make up the difference. This says whether the floor has
  // fallen behind and what moving it would cost.
  const floorAdvice = (() => {
    if (!putFloor || !putSpend) return null;
    const gapPct = ((spot - putFloor) / spot) * 100;        // how far spot sits above the floor
    const T = Math.max(putDays, 1) / 365;
    const nowValue = bsPut(spot, putFloor, T, iv / 100) * putCt * 100;
    // Roll to a floor the same distance below spot as the book was originally set at,
    // defaulting to 2% under — close enough to matter, far enough to stay OTM.
    const target = Math.round((spot * 0.98) / INST.step) * INST.step;
    const newCost = bsPut(spot, target, T, iv / 100) * putCt * 100;
    const rollCost = newCost - nowValue;
    const stale = gapPct >= 6 && target > putFloor;
    return {
      stale, gapPct: +gapPct.toFixed(1), floor: putFloor, target,
      nowValue: Math.round(nowValue), newCost: Math.round(newCost), rollCost: Math.round(rollCost),
      // Raising the floor lifts the whole downside, which is what buys the freedom to
      // sell fewer, further-out calls rather than reaching for depth.
      why: stale
        ? `Spot is ${gapPct.toFixed(0)}% above the ${putFloor} floor. Rolling to ${target} costs ${Math.round(rollCost).toLocaleString()} and lifts the whole floor with it.`
        : `The ${putFloor} floor is ${gapPct.toFixed(0)}% below spot, still close enough to be doing its job.`,
    };
  })();

  // ── the observer ────────────────────────────────────────────────────────────
  // Deliberately NOT the score's top contributors. That version collapsed into
  // chart-and-options every single week, because six of the nine week factors read
  // price or option pricing: a scoring model describing itself back to you.
  //
  // An observation is a claim about the WORLD with a measured number behind it.
  // Six domains, each with its own rule and its own data, and a domain may
  // contribute AT MOST ONE line. That cap is the entire mechanism. It is what stops
  // the chart taking the list on a week when the chart happens to be loud.
  //
  // Three states, not two:
  //   loud   — notable, goes to "what matters"
  //   quiet  — measured and unremarkable, goes to "what won't matter"
  //   silent — no data, so the domain says NOTHING at all. "No chip earnings this
  //            week" drawn from an empty peer table is a lie about the world, and
  //            silence is the only honest alternative to it.
  //
  // Every observation also carries what the SCORE makes of it. `blind` is the one
  // worth reading: the observer saw something the number cannot.
  type Obs = {
    domain: string; tag: string; text: string;
    kind: 'measured' | 'read';                       // read = from headlines, never scored
    seen: 'priced' | 'underweighted' | 'blind';
    note: number;                                    // 0..1, ranks the loud list
  };
  const loud: Obs[] = [], calm: Obs[] = [];
  const RW = REGIME_WEIGHTS[regime] ?? REGIME_WEIGHTS.RANGE;
  const seenBy = (...keys: string[]): Obs['seen'] => {
    const w = keys.reduce((a, k) => a + (RW[k] ?? 0), 0);
    return w === 0 ? 'blind' : w < 0.10 ? 'underweighted' : 'priced';
  };
  const say = (isLoud: boolean, o: Omit<Obs, 'kind'>) =>
    (isLoud ? loud : calm).push({ kind: 'measured', ...o });
  const dayStr = (n: number) => `${n} day${n === 1 ? '' : 's'}`;

  // THE RECORD — what this name has done in this situation before. Not in the score
  // at all today: it moves keepPct and nothing else, so the number never reflects it.
  const seenRecord = seenBy('record');
  if (record && record.n >= 8) {
    if (daysSincePrint <= 30 && bandStats) {
      say(true, { domain: 'record', tag: 'The record', seen: seenRecord, note: .90,
        text: `After ${bandStats.band} prints this has run ${bandStats.d30 > 0 ? '+' : ''}${bandStats.d30}% inside 30 sessions, on ${bandStats.n} observation${bandStats.n === 1 ? '' : 's'}.` });
    } else if ((earnings.date ? daysToPrint : (cats.find((c) => c.key === 'earnings_events')?.days ?? daysToPrint)) <= 21) {
      say(true, { domain: 'record', tag: 'The record', seen: seenRecord, note: .75,
        text: `${record.survived} of the last ${record.n} prints landed better than -8%, median ${record.med > 0 ? '+' : ''}${record.med}%. Capping upside into that record has been the losing side of it.` });
    } else {
      say(false, { domain: 'record', tag: 'The record', seen: seenRecord, note: .10,
        text: `Nothing in ${record.n} prints on file says this week is unusual.` });
    }
  }

  // THE WINDOW — how much room is left before the print, counted in expiries you
  // could actually write rather than in days.
  // daysToPrint keys off b.earnings, which the APP supplies. The table knows the
  // date too, and an observer that goes silent because the caller left a field out
  // is reporting on the request rather than on the world.
  const printCat = cats.find((c) => c.key === 'earnings_events') ?? null;
  const eDate = earnings.date ?? printCat?.date ?? null;
  const dPrint = earnings.date ? daysToPrint : (printCat?.days ?? daysToPrint);
  if (eDate) {
    const before = expiryDates.filter((d) => d < eDate).length;
    const seen = seenBy('event');
    if (dPrint <= 3) {
      say(true, { domain: 'window', tag: 'The window', seen, note: 1.0,
        text: `The print is ${dayStr(dPrint)} out. Everything you write now carries it.` });
    } else if (dPrint <= 21) {
      say(true, { domain: 'window', tag: 'The window', seen, note: .60,
        text: `${before} expir${before === 1 ? 'y' : 'ies'} left before the ${eDate} print. Anything written past them carries the event.` });
    } else {
      say(false, { domain: 'window', tag: 'The window', seen, note: .10,
        text: `The print is ${dayStr(dPrint)} out, past everything you would write this week.` });
    }
  }

  // THE NEIGHBOURHOOD — peers and where this name sits inside the group. Nothing in
  // the score reads either, so every line here is blind to the number.
  if (peersKnown) {
    const behind = peers.filter((p) => p.days < 0).sort((a, b) => b.days - a.days)[0];
    const ahead = peers.filter((p) => p.days >= 0).sort((a, b) => a.days - b.days)[0];
    const nextExp = expiryDates[0];
    const rel = relStrength;
    const est = (p: Peer) => (p.confirmed ? '' : ', though that date is an estimate');
    const seenHood = seenBy('peers', 'relative');
    if (ahead && nextExp && ahead.date <= nextExp) {
      say(true, { domain: 'neighbourhood', tag: 'The neighbourhood', seen: seenHood, note: .95,
        text: `${ahead.ticker} reports ${ahead.days === 0 ? 'today' : `in ${dayStr(ahead.days)}`}, inside this expiry${est(ahead)}. Semis move as a bloc through it.` });
    } else if (behind && behind.days >= -7) {
      say(true, { domain: 'neighbourhood', tag: 'The neighbourhood', seen: seenHood, note: .70,
        text: `${behind.ticker} printed ${dayStr(-behind.days)} ago${rel ? `, and ${TICKER} has run ${rel.gap > 0 ? '+' : ''}${rel.gap}% against SMH over ${rel.days} sessions` : ''}.` });
    } else if (rel && Math.abs(rel.gap) >= 5) {
      say(true, { domain: 'neighbourhood', tag: 'The neighbourhood', seen: seenHood, note: .65,
        text: `${TICKER} has run ${rel.gap > 0 ? '+' : ''}${rel.gap}% against SMH over ${rel.days} sessions, so it is ${rel.gap > 0 ? 'leading' : 'lagging'} the group.` });
    } else if (ahead) {
      say(false, { domain: 'neighbourhood', tag: 'The neighbourhood', seen: seenHood, note: .10,
        text: `No chip earnings before this expiry. ${ahead.ticker} is next, ${dayStr(ahead.days)} out.` });
    } else {
      say(false, { domain: 'neighbourhood', tag: 'The neighbourhood', seen: seenHood, note: .05,
        text: 'No chip earnings on the calendar.' });
    }
  }

  // THE CALENDAR — macro only; the print has its own domain above.
  const macroKnown = calSources.some((x) => /^macro_events:\d+$/.test(x));
  if (macroKnown) {
    const hits = cats.filter((c) => c.key === 'macro_events' && c.sev >= 3);
    const m = hits[0] ?? null;
    // Macro has its own factor now, on its own clock, so the tag reads straight off
    // the regime weight rather than working around the old severity threshold.
    const seen = seenBy('macro');
    // Not "is it before the next expiry" — that reads CPI landing squarely on the
    // 12 Aug book as "just past this expiry" because the 10th happens to expire
    // first. What matters is which expiry it lands INSIDE, and whether that is one
    // you are about to write.
    const covering = m ? expiryDates.find((d) => d >= m.date) ?? null : null;
    const near = covering ? expiryDates.indexOf(covering) <= 1 : false;
    if (m && near && covering) {
      say(true, { domain: 'macro', tag: 'The calendar', seen, note: .92,
        text: `${m.label} lands ${m.days === 0 ? 'today' : `in ${dayStr(m.days)}`}, inside your ${covering} expiry.` });
    } else if (m && m.days <= 14) {
      say(true, { domain: 'macro', tag: 'The calendar', seen, note: .50,
        text: `${m.label} in ${dayStr(m.days)}, past the expiries you would write now.` });
    } else if (m) {
      say(false, { domain: 'macro', tag: 'The calendar', seen, note: .10,
        text: `Nothing before ${m.label}, ${dayStr(m.days)} out.` });
    } else {
      say(false, { domain: 'macro', tag: 'The calendar', seen: 'priced', note: .05,
        text: 'Nothing scheduled inside the window.' });
    }
  }

  // WHAT YOU ARE PAID — stated against this name's own year, not an absolute level.
  if (ivMedian != null && Number.isFinite(iv) && ivMedian > 0) {
    const extra = (iv / ivMedian - 1) * 100;
    const seen = seenBy('iv_pctile', 'iv_spread');
    if (Math.abs(extra) >= 12) {
      say(true, { domain: 'paid', tag: 'What you are paid', seen, note: .85,
        text: `${iv.toFixed(0)}% implied against a ${ivMedian.toFixed(0)}% normal, so you are paid ${Math.abs(extra).toFixed(0)}% ${extra > 0 ? 'over' : 'under'} the usual price.` });
    } else {
      say(false, { domain: 'paid', tag: 'What you are paid', seen, note: .10,
        text: `${iv.toFixed(0)}% against a ${ivMedian.toFixed(0)}% normal. There is no premium argument this week.` });
    }
  }

  // THE CHART — one line, and capped at .60 notability on purpose. The chart is the
  // best-covered domain in the score and the one that used to eat the whole list, so
  // it should lose ties against anything the number cannot already see.
  if (technicals.ma50 != null) {
    const rsi = technicals.rsi14;
    const seen = seenBy('trend', 'stretch', 'rsi');
    const hot = rsi != null && rsi >= 70, cold = rsi != null && rsi <= 30;
    const deep = drawdown != null && drawdown >= 12;
    const stretched = Math.abs(dev) >= 1.5;
    const text = stretched
      ? `${dev > 0 ? '+' : ''}${dev} normal days from its 50-day${drawdown != null ? `, and ${drawdown.toFixed(0)}% off the high` : ''}.`
      : hot ? `RSI ${rsi!.toFixed(0)}. Buyers are in charge and the run is stretched alongside you.`
      : cold ? `RSI ${rsi!.toFixed(0)}, the most washed out end of its range.`
      : deep ? `${drawdown!.toFixed(0)}% off the high, which is where its own record starts to disagree with the tape.`
      : `Sitting mid-range, ${dev > 0 ? '+' : ''}${dev} from its 50-day.`;
    say(stretched || hot || cold || deep, { domain: 'chart', tag: 'The chart', seen,
      note: Math.min(.60, Math.abs(dev) / 5), text });
  }

  // SENTIMENT is deliberately absent rather than omitted. It stays OUT of the score
  // by design, and it is not wired yet, so it reports as silent — which is the card
  // telling you what it does not know instead of quietly not having it.
  const DOMAINS = ['record', 'window', 'neighbourhood', 'macro', 'paid', 'chart', 'sentiment'];
  const rank = (o: Obs) => DOMAINS.indexOf(o.domain);
  // Loud is capped at three. Four domains firing is ordinary once the calendar is
  // real, and a six-line list is the thing this redesign exists to remove. The cut is
  // by notability, NOT by domain order, so a CPI print two days out beats a chart
  // that merely happens to be stretched.
  const matters = [...loud].sort((a, b) => b.note - a.note).slice(0, 3).sort((a, b) => rank(a) - rank(b));
  const spoke = new Set([...loud, ...calm].map((o) => o.domain));
  const observations = {
    matters,
    quiet: [...calm].sort((a, b) => rank(a) - rank(b)).slice(0, 3),
    dropped: loud.filter((o) => !matters.includes(o)).map((o) => o.domain),
    silent: DOMAINS.filter((d) => !spoke.has(d)),
  };

  const refStrike = (b.refStrike as number) ?? Math.round(spot / STRIKE_STEP) * STRIKE_STEP;

  return json(200, {
    ok: true, asOf: new Date().toISOString(),
    source: { spot: polySpot != null ? 'polygon' : 'request', expiries: polyExpiries.length ? 'polygon' : 'fallback', technicals: technicals.ath != null ? 'ticker_stats' : 'missing' },
    gate, book, technicals, assignment, refStrike, weekendVol: wv, expiries,
    week, posture, events, refLots, ticker: TICKER, ivMedian, splits, floorAdvice, observations,
    hedge: { spend: putSpend, days: putDays, perDay: Math.round(hedgeCarry), requiredWeekly: Math.round(requiredWeekly) },
    budget: { room, hardFloor, aggression: +aggression.toFixed(3), delta: budget, capacityCt, style, rollingCt },
    regime: { name: regime, why: regimeWhy, keepPct, keepDelta, keepWhy,
              measured, lastReaction,
              floorGapPct: floorGapPct == null ? null : +floorGapPct.toFixed(1),
              drawdown: drawdown == null ? null : +drawdown.toFixed(1), haveHigh,
              daysToPrint, daysSincePrint, lastPrint: lastPrintISO },
    meta: { STRIKE_STEP, RIP, calSources, snapshot: snapNote, floorPct: INST.floorPct, lookbacks: LOOKBACKS, ivSources: { nvda: { label: 'NVDA · 2y regression', down: 1.05, up: -.62, note: '504 sessions, R² 0.61' }, generic: { label: 'Generic equity skew', down: .80, up: -.50, note: 'default, uncalibrated' } } },
  });
});
