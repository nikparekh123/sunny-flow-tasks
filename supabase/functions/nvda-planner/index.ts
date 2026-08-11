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
  // TEN factors, and every one of them describes the WORLD. The position no longer
  // scores.
  //
  // It used to. assignment + headroom + freeroll carried ~20% of the weight, and
  // because both of the first two pin high whenever the book has room, they pushed
  // the score UP on exactly the days there was least worth selling. Run NVDA at 190,
  // 224 and 275 after a print and the old score came back 59 / 53 / 52, all SELL
  // NORMAL, all 25-30 delta: capacity was drowning out the world.
  //
  // Capacity did not disappear, it moved to where it belongs. The world decides
  // WHETHER to sell (this score, the stance, the delta band). The book decides HOW
  // MUCH (keepPct, budget, capacityCt) and can still veto down to zero. One question
  // per mechanism.
  //
  // KEYS MUST MATCH the wf.push keys exactly. Lookup is `rw[f.key] ?? 0.01`, so a
  // mismatch does not throw — it silently pins that factor at 1% in every regime.
  'EARNINGS WEEK':        { event: .26, iv_pctile: .20, iv_spread: .17, record: .15,
                            peers: .07, macro: .04, trend: .04, stretch: .03,
                            relative: .02, rsi: .02 },

  'JUST AFTER THE PRINT': { record: .24, iv_spread: .21, stretch: .17, trend: .14,
                            relative: .07, iv_pctile: .05, peers: .04, macro: .03,
                            rsi: .03, event: .02 },

  'BEATEN DOWN':          { stretch: .24, record: .15, rsi: .15, trend: .14,
                            relative: .10, iv_pctile: .09, iv_spread: .08, macro: .03,
                            peers: .01, event: .01 },

  'EXTENDED RUN':         { stretch: .24, trend: .20, iv_pctile: .14, relative: .10,
                            rsi: .09, macro: .07, record: .07, iv_spread: .06,
                            peers: .02, event: .01 },

  'RANGE':                { iv_pctile: .27, iv_spread: .17, macro: .11, stretch: .10,
                            record: .07, relative: .07, trend: .06, peers: .05,
                            rsi: .05, event: .05 },
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
/** '2026-08-12' → 'Aug 12'. Chips and notes read as dates, never as ISO strings. */
/** 2068 → "$2K" · −59758 → "−$60K". Pre-formatted server-side so three figures
 *  that must agree cannot disagree by rounding in two places. */
const fmtUsd = (v: number, signed = false) => {
  const sign = v < 0 ? '\u2212' : signed ? '+' : '';
  const a = Math.abs(v);
  if (a >= 1000) return `${sign}$${Math.round(a / 1000)}K`;
  return `${sign}$${Math.round(a)}`;
};
const fmtDay = (iso: string) => {
  const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number);
  return y && m && d ? `${MONTHS[m - 1]} ${d}` : String(iso);
};
const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
/** Real quotes for one expiry across a strike window. The planner priced every pick
 *  with Black-Scholes, which is fine for ranking and wrong for an order: a theoretical
 *  is not a price you can hit. Mid of bid/ask, never `last` — last can be hours stale
 *  on a strike nobody has touched today.
 *
 *  A strike with no bid is quoted but not tradeable, so it falls back to the model and
 *  says so rather than showing a mid nobody will pay. */
type Quote = { strike: number; bid: number; ask: number; mid: number; delta: number | null; oi: number };
async function chainQuotes(tk: string, expiry: string, lo: number, hi: number, key: string): Promise<Map<number, Quote>> {
  const out = new Map<number, Quote>();
  try {
    const r = await fetch(`${POLY}/v3/snapshot/options/${tk}?expiration_date=${expiry}`
      + `&contract_type=call&strike_price.gte=${lo}&strike_price.lte=${hi}&limit=60&apiKey=${key}`);
    if (!r.ok) return out;
    const j = await r.json();
    for (const row of ((j?.results ?? []) as Record<string, Record<string, number>>[])) {
      const k = Number(row?.details?.strike_price);
      if (!Number.isFinite(k)) continue;
      const bid = Number(row?.last_quote?.bid ?? 0), ask = Number(row?.last_quote?.ask ?? 0);
      const mid = bid > 0 && ask > 0 ? (bid + ask) / 2 : 0;
      const dl = Number(row?.greeks?.delta);
      out.set(k, { strike: k, bid, ask, mid, delta: Number.isFinite(dl) && dl > 0 ? dl : null,
                   oi: Number(row?.open_interest ?? 0) });
    }
  } catch { /* no quotes just means the model prices it, and the pick says so */ }
  return out;
}

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
  // The guard screens PLANNING input. Neither a commit nor a scoring run carries a
  // book, and both were being rejected for lacking fields they have no use for.
  if (b.commit == null && b.score !== true && b.holdings == null && (bookIn.shares == null || volIn.iv == null))
    return json(400, { ok: false, error: 'book.shares and vol.iv are required' });

  const wv = Number(b.weekendVol ?? 0.3);
  const TICKER = String(b.ticker ?? 'NVDA').toUpperCase();
  const INST = INSTRUMENT[TICKER] ?? INSTRUMENT.NVDA;
  const STRIKE_STEP = INST.step;
  const nowISO = ymd(new Date());
  const [polySpot, polyExpiries] = key
    ? await Promise.all([nearestSpot(key, TICKER), callExpiries(nowISO, key, TICKER)])
    : [null, [] as string[]];
  // ── holdings ──────────────────────────────────────────────────────────────
  // Reads the per-ticker store with the service role. The anon key sees zero rows
  // through RLS on every one of these tables, so "empty" and "no permission" look
  // identical from outside and neither can be ruled out.
  if (b.holdings != null && supaUrl && supaKey) {
    const tk = String(b.holdings).toUpperCase();
    const pre = tk === 'TLT' ? 'tlt' : 'nvda';
    const h = { apikey: supaKey, Authorization: `Bearer ${supaKey}` };
    const grab = async (t: string, sel: string) => {
      try {
        const r = await fetch(`${supaUrl}/rest/v1/${t}?select=${sel}&voided_at=is.null&limit=200`, { headers: h });
        return r.ok ? (await r.json()) as Record<string, unknown>[] : [{ error: `HTTP${r.status}` }];
      } catch { return [{ error: 'fetch failed' }]; }
    };
    const [opts, lots, legacy] = await Promise.all([
      grab(`${pre}_option_trades`, 'trade_date,action,option_type,direction,contracts,strike,premium,expiry'),
      grab(`${pre}_share_lots`, 'acquired_date,qty_remaining,cost_per_share'),
      // The legacy table is where ibkr-flex-sync actually writes; comparing the two
      // says whether the problem is the sync or the mirror that feeds the store.
      (async () => {
        try {
          const r = await fetch(`${supaUrl}/rest/v1/option_trades?select=trade_date,option_type,direction,contracts,strike,expiry`
            + `&ticker=eq.${tk}&limit=200`, { headers: h });
          return r.ok ? (await r.json()) as Record<string, unknown>[] : [{ error: `HTTP${r.status}` }];
        } catch { return [{ error: 'fetch failed' }]; }
      })(),
    ]);
    return json(200, { ok: true, ticker: tk,
      store: { optionTrades: opts.length, shareLots: lots.length, legs: opts },
      legacy: { optionTrades: legacy.length, legs: legacy } });
  }

  // ── score ─────────────────────────────────────────────────────────────────
  // Resolves every commit whose expiry has passed. Scores ALL THREE picks, not just
  // the one taken — the taken one measures which way NVDA went, which the tool does
  // not control; the other two are the only way to ask whether the RANKING was any
  // good, and that is the actual question about the model.
  //
  // The measure is what the call trade added or cost AGAINST SIMPLY HOLDING. Below the
  // strike a call is pure premium; above it you keep the premium and hand back the
  // difference. Doing nothing scores exactly zero, which is what makes a declined week
  // comparable to a traded one instead of missing from the record.
  if (b.score === true && supaUrl && supaKey) {
    const h = { apikey: supaKey, Authorization: `Bearer ${supaKey}` };
    const rows = await (async () => {
      try {
        const r = await fetch(`${supaUrl}/rest/v1/planner_commits?select=*&scored_at=is.null`
          + `&expiry=lt.${nowISO}&order=expiry.asc&limit=50`, { headers: h });
        return r.ok ? (await r.json()) as Record<string, unknown>[] : [];
      } catch { return []; }
    })();

    const closeOn = async (d: string): Promise<number | null> => {
      if (!key) return null;
      try {
        const r = await fetch(`${POLY}/v2/aggs/ticker/${TICKER}/range/1/day/${d}/${d}?adjusted=true&apiKey=${key}`);
        if (!r.ok) return null;
        const c = Number(((await r.json())?.results ?? [])[0]?.c);
        return Number.isFinite(c) ? c : null;
      } catch { return null; }
    };

    const done: unknown[] = [];
    for (const row of rows) {
      const expiry = String(row.expiry ?? '');
      const close = expiry ? await closeOn(expiry) : null;
      // No close yet is not a zero. Leave it unscored and try again tomorrow.
      if (close == null) { done.push({ id: row.id, expiry, skipped: 'no close on file' }); continue; }

      const picks = (row.picks ?? []) as Record<string, number>[];
      const outs = picks.map((p, i) => {
        const ct = Number(p.ct ?? 0), strike = Number(p.strike ?? 0), income = Number(p.income ?? 0);
        const overBy = Math.max(0, close - strike);
        const givenUp = overBy * ct * 100;
        return { pick: i + 1, strike, ct, income,
                 assigned: close > strike, calledShares: close > strike ? ct * 100 : 0,
                 givenUp: Math.round(givenUp),
                 // vs holding the shares and writing nothing
                 pl: Math.round(income - givenUp) };
      });
      const best = outs.reduce((a2, x) => (x.pl > a2.pl ? x : a2), outs[0] ?? { pl: 0, pick: 0 });
      const chosen = row.chosen == null ? null : Number(row.chosen);
      const tookPl = chosen == null ? 0 : (outs[chosen - 1]?.pl ?? 0);
      // Was the order the tool offered the order the market produced? The headline
      // question, and it is answerable at n=1 in a way "was the trade good" is not.
      const rankedRight = outs.length >= 2 && outs.every((x, i) => i === 0 || outs[i - 1].pl >= x.pl);

      const patch = {
        underlying_close: close, scored_at: new Date().toISOString(),
        outcomes: { close, picks: outs, best: best.pick, took: chosen, tookPl,
                    regret: Math.round((best.pl ?? 0) - tookPl), rankedRight,
                    declined: chosen == null },
      };
      try {
        await fetch(`${supaUrl}/rest/v1/planner_commits?id=eq.${row.id}`, {
          method: 'PATCH',
          headers: { ...h, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
          body: JSON.stringify(patch),
        });
      } catch { /* retried on the next run, since scored_at stays null */ }
      done.push({ id: row.id, expiry, close, took: chosen, tookPl,
                  best: best.pick, regret: Math.round((best.pl ?? 0) - tookPl), rankedRight });
    }
    return json(200, { ok: true, found: rows.length, scored: done.length, results: done });
  }

  // ── commit ────────────────────────────────────────────────────────────────
  // Records a decision. The plan block is echoed back verbatim rather than
  // recomputed, because a decision has to be stored as it was READ — recomputing it
  // an hour later against a different spot would archive a plan that never existed.
  if (b.commit != null && supaUrl && supaKey) {
    const c = b.commit as Record<string, unknown>;
    const pl = (c.plan ?? {}) as Record<string, unknown>;
    const row = {
      ticker: TICKER, taken_on: nowISO,
      spot: c.spot ?? null, iv: c.iv ?? null, iv_median: c.ivMedian ?? null,
      event_state: pl.event ?? null, price_state: pl.price ?? null,
      conviction: pl.conviction ?? null, conviction_parts: pl.convictionParts ?? null,
      keep_pct: pl.keepPct ?? null, keep_delta: pl.keepDelta ?? null,
      hedge_needs: (pl.hedge as Record<string, unknown> | undefined)?.needs ?? null,
      picks: pl.picks ?? [],
      // null is a real answer: doing nothing is a decision and gets scored like one.
      chosen: c.chosen ?? null, declined_why: c.declinedWhy ?? null,
      observations: c.observations ?? null,
      quotes_source: (pl.quotes as Record<string, unknown> | undefined)?.source ?? null,
      // WHICH WEEK the picks belong to. `chosen` alone names a tier, and the same
      // tier exists in both chains — storing one without the other records the
      // right decision against the wrong expiry, which the scorer then resolves
      // against a close that was never relevant to it.
      chosen_chain: c.chosenChain ?? 0,
      shares: (c.book as Record<string, unknown> | undefined)?.shares ?? null,
      book: c.book ?? null,
      expiry: pl.expiry ?? null,
    };
    const r = await fetch(`${supaUrl}/rest/v1/planner_commits?on_conflict=ticker,taken_on,expiry`, {
      method: 'POST',
      headers: { apikey: supaKey, Authorization: `Bearer ${supaKey}`, 'Content-Type': 'application/json',
                 Prefer: 'resolution=merge-duplicates,return=representation' },
      body: JSON.stringify(row),
    });
    const body = await r.text();
    // A receipt, not an echo. The caller does not need the row back — it needs to know
    // WHAT was captured, because the failure that matters here is a row that saves
    // with the picks or the conviction parts missing. Echoing and truncating hid that.
    if (!r.ok) return json(500, { ok: false, saved: false, status: r.status, detail: body.slice(0, 400) });
    let stored: Record<string, unknown> = {};
    try { stored = (JSON.parse(body) as Record<string, unknown>[])[0] ?? {}; } catch { /* receipt degrades, row is safe */ }
    const obs = (stored.observations ?? {}) as Record<string, unknown[]>;
    return json(200, {
      ok: true, saved: true, id: stored.id ?? null,
      takenOn: stored.taken_on ?? null, expiry: stored.expiry ?? null,
      chosen: stored.chosen ?? null,
      captured: {
        picks: ((stored.picks ?? []) as unknown[]).length,
        convictionParts: Object.keys((stored.conviction_parts ?? {}) as Record<string, unknown>).length,
        observerMatters: (obs.matters ?? []).length,
        conviction: stored.conviction ?? null, keepPct: stored.keep_pct ?? null,
        quotes: stored.quotes_source ?? null,
      },
    });
  }

  const spot = (b.spot as number) ?? polySpot ?? 0;
  const expiryDates = (polyExpiries.length ? polyExpiries : fallbackExpiries(nowISO)).slice(0, 6);
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
  let sectorHealth: { pctAbove200: number; norm: number; dev: number; n: number } | null = null;
  // How many rows each series actually returned. A factor that reads zero because the
  // data is thin looks identical to one that reads zero because the world is neutral.
  let closesSeen: { self: number; smh: number } | null = null;
  let peerPrints: { ticker: string; days: number; move: number; band: string }[] = [];
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
        // 45 days: the LAST print, not any print. A wider window would return one from
        // two years ago and call it recent, which would set daysSincePrint and put the
        // whole model into POST on a random Tuesday.
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

  // ALL the implied vol on file, not a year of it. The read was capped at 252 while the
  // table held 537 sessions, so "normal" was measured against the most recent year only
  // and came out at 40. Across the full history it is 44 — four points higher, which
  // means every "you are paid an ordinary price" line was judging against too low a bar.
  // ratio nobody can act on. Median, not mean: a single earnings spike should not
  // define normal.
  let ivMedian: number | null = null;
  if (supaUrl && supaKey) {
    try {
      const r = await fetch(`${supaUrl}/rest/v1/${TICKER === 'TLT' ? 'tlt' : 'nvda'}_iv_daily`
        + `?select=iv&ticker=eq.${TICKER}&order=date.desc&limit=800`,
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

    // How the neighbours' own reports actually LANDED. A different signal from relative
    // price: AMD dropping hard on its print says something about what the group is being
    // told, which a price ratio cannot see.
    try {
      const since = ymd(new Date(parseISO(nowISO).getTime() - 75 * 86400000));
      const r = await fetch(`${supaUrl}/rest/v1/earnings_reactions`
        + `?select=ticker,reaction_date,move_pct,band&ticker=neq.${TICKER}`
        + `&reaction_date=gte.${since}&order=reaction_date.desc&limit=12`, { headers: h });
      if (r.ok) {
        peerPrints = ((await r.json()) as { ticker: string; reaction_date: string; move_pct: number; band: string }[])
          .map((x) => ({ ticker: x.ticker, band: x.band, move: Number(x.move_pct),
            days: Math.round((parseISO(nowISO).getTime() - parseISO(String(x.reaction_date ?? '').slice(0, 10)).getTime()) / 86400000) }))
          .filter((x) => Number.isFinite(x.move) && Number.isFinite(x.days) && x.days >= 0);
      }
    } catch { /* nothing on file means zero, which is silence rather than optimism */ }

    // Where the money is going inside the sector. Both legs use the same window, so
    // a missing session on either side shortens the comparison rather than skewing it.
    try {
      // Deep enough for SMH's own 200-day AND a norm to compare it against. Two
      // identically-worded windows in this file already sent one edit to the wrong
      // fetch; this one is matched on its query, not on the line.
      const back = ymd(new Date(parseISO(nowISO).getTime() - 640 * 86400000));
      const r = await fetch(`${supaUrl}/rest/v1/daily_closes`
        + `?select=ticker,date,close_price&ticker=in.(${TICKER},SMH)&date=gte.${back}`
        + `&order=date.desc&limit=1200`, { headers: h });
      if (r.ok) {
        const rows = (await r.json()) as { ticker: string; date: string; close_price: number }[];
        const series = (tk: string) => rows.filter((x) => x.ticker === tk)
          .sort((a, b) => (a.date < b.date ? 1 : -1))
          .map((x) => Number(x.close_price)).filter((v) => Number.isFinite(v) && v > 0);
        const a = series(TICKER), r2 = series('SMH');
        closesSeen = { self: a.length, smh: r2.length };
        const n = Math.min(a.length, r2.length, 21);
        if (n >= 10) {
          const pa = ((a[0] - a[n - 1]) / a[n - 1]) * 100;
          const pr = ((r2[0] - r2[n - 1]) / r2[n - 1]) * 100;
          relStrength = { vs: 'SMH', self: +pa.toFixed(1), ref: +pr.toFixed(1), gap: +(pa - pr).toFixed(1), days: n };
        }

        // SECTOR HEALTH. `relative` asks whether NVDA is beating SMH; this asks whether
        // SMH itself is any good. Outperforming a sector that is rolling over is a
        // different situation from outperforming one that is climbing, and nothing in
        // the model could tell them apart.
        //
        // Measured as a DEVIATION from SMH's own norm, never as an absolute. "Above its
        // 200-day" is true most weeks of a bull market; scored raw it would add points
        // to almost every reading and discriminate nothing.
        if (r2.length >= 250) {
          const pctAbove = (i: number) => {
            const win = r2.slice(i, i + 200);
            const ma = win.reduce((x, y) => x + y, 0) / win.length;
            return ma > 0 ? ((r2[i] / ma) - 1) * 100 : 0;
          };
          const hist: number[] = [];
          for (let i = 0; i + 200 < r2.length; i += 5) hist.push(pctAbove(i));
          if (hist.length >= 8) {
            const sorted = hist.slice().sort((x, y) => x - y);
            const norm = sorted[Math.floor(sorted.length / 2)];
            const now = pctAbove(0);
            sectorHealth = { pctAbove200: +now.toFixed(1), norm: +norm.toFixed(1),
                             dev: +(now - norm).toFixed(1), n: hist.length };
          }
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
  // The clock, resolved once. It used to read b.earnings and fall through to 99 when
  // the caller left it out, which silently switched off every factor keyed to the
  // print — the record scored 0 while the observer had it as the top line. The table
  // knows the date; the engine should not depend on being told.
  const printRow = cats.find((c) => c.key === 'earnings_events') ?? null;
  const daysToEarnings = earnings.date
    ? Math.max(0, Math.round((parseISO(earnings.date).getTime() - parseISO(nowISO).getTime()) / 86400000))
    : printRow ? printRow.days : Number((b.daysToEarnings as number) ?? 99);
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
  // The floor's own expiry. Sent rather than derived from putDays: adding a day count
  // to today lands on a date no option actually expires on, and the page prints it.
  const putExpISO = typeof bookIn.putExpiry === 'string' ? String(bookIn.putExpiry).slice(0, 10) : null;
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
// The 50/200 spread alone is frozen over a two-day horizon: after a 15% gap the
  // averages have not moved, so trend reported the identical -32.3 whether NVDA sat
  // at 224 or 275. Blend the spread with where PRICE sits against the 200-day, which
  // reprices instantly. Half each: the averages carry the regime, price carries the
  // shock.
  const maSpread = technicals.ma50 != null && technicals.ma200 != null && technicals.ma200 !== 0
    ? (technicals.ma50 - technicals.ma200) / technicals.ma200 : 0;
  const priceVs200 = technicals.ma200 != null && technicals.ma200 !== 0
    ? (spot - technicals.ma200) / technicals.ma200 : 0;
  const trendRaw = 0.5 * maSpread + 0.5 * priceVs200;
  // x12 saturated at an 8% spread, which NVDA clears in a normal quarter. x5 needs
  // 20% before it pins, so a strong trend and an extreme one read differently.
  const trendStrength = clamp(Math.abs(trendRaw) * 5, 0, 1);
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
  // ── the keep model ──────────────────────────────────────────────────────────
  // docs/PLANNER_KEEP_MODEL.md. Keep is measured in DELTA, not shares. Nik's three
  // pre-earnings answers were 32/50/20% of SHARES and all landed on ~77% of delta —
  // he varied count and strike in opposite directions and they cancelled. The share
  // number was the route; delta was the destination he was actually steering to.
  //
  // So the baseline is ONE number per event state and price state does not appear in
  // it at all. Price decides the distance, distance decides the delta per contract,
  // and the count falls out of the arithmetic.
  // An expiry with no sessions left is not something to write. expiryDates[0] is
  // today's on any expiry morning, and NVDA has one every Mon, Wed and Fri — so a
  // third of the time the model was pricing a zero-day option and calling it the plan.
  const liveExps = expiryDates.filter((d) => spanTo(nowISO, parseISO(d)).td >= 1);
  // The planner has always written the nearest live expiry. Rolling is the norm,
  // and the week you roll INTO is a real choice — into the print or past it, before
  // CPI or after — so the caller may name one.
  //
  // Validated against liveExps rather than trusted: an expiry that has already
  // expired, or one this underlying does not list, must fall back to the nearest
  // rather than price a contract that cannot be sold. A silent fallback is right
  // here; the response reports which expiry was actually used, and the app reads
  // that rather than assuming its request was honoured.
  const askedExp = typeof b.plannedExpiry === 'string' ? String(b.plannedExpiry).slice(0, 10)
                 : typeof b.expiry === 'string' ? String(b.expiry).slice(0, 10) : null;
  const nextExp = (askedExp && liveExps.includes(askedExp) ? askedExp : liveExps[0]) ?? null;
  const secondExp = liveExps.find((e) => e !== nextExp) ?? null;
  const sincePrint = b.daysSincePrint != null ? Number(b.daysSincePrint) : daysSincePrint;
  // Does the contract you are about to write actually CARRY the print?
  //
  // This used to ask "is there a print within 7 days", which is a fact about the
  // calendar, not about your position. With the expiry a choice, that reads wrong
  // in both directions: rolling deliberately PAST earnings still priced as PRE,
  // and a two-day contract expiring before a print six days out was treated as
  // carrying an event it would never see.
  //
  // Now it asks whether the print falls on or before the expiry being written.
  // That is the thing the keep model should be reacting to, and it is why picking
  // an expiry changes the judgement rather than only the price.
  const printISO = earnings.date ? String(earnings.date).slice(0, 10) : null;
  const printInside = !!(printISO && nextExp
    && printISO > nowISO.slice(0, 10) && printISO <= nextExp);
  const evState = printInside ? 'PRE' : sincePrint <= 5 ? 'POST' : 'CLEAR';
  const reactMove = lastReaction ? Number(lastReaction.move_pct) : null;
  // The caller may know these better than we do, and must be able to say so. pxMove
  // otherwise reads relStrength off daily_closes, which holds ~12 rows for the
  // reference series; sincePrint otherwise needs a past print already in the table.
  // Neither is a reason for the model to be undrivable — the engine should accept the
  // caller's knowledge when it is offered and fall back to its own when it is not.
  const pxMove = b.priceMove != null ? Number(b.priceMove)
    : evState === 'POST' && reactMove != null ? reactMove : (relStrength?.self ?? 0);
  const pxState = pxMove <= -8 ? 'down' : pxMove >= 8 ? 'up' : 'flat';

  // CLEAR was 68, extrapolated rather than calibrated — it was the one cell Nik never
  // gave an answer for. He has now: 60-70% of 75 contracts on an ordinary week, which
  // is a keep near 71% and a baseline of 65.
  //
  // The reasoning behind it matters more than the number. ROLLING DEFEATS DRIFT; IT DOES
  // NOT DEFEAT GAPS. A grind from 224 to 250 gets rolled up the whole way and you keep
  // nearly all of it. A gap there in one session you eat. Since a clear week's only real
  // risk is drift, caution belongs in PRE and POST, where the gap lives, not here.
  //
  // The arithmetic: a 10% gap costs about $78k against the cap, and three rolls a week
  // collect about $34k. Roughly 2.3 weeks of premium pays for one gap.
  const BASE_KEEP: Record<string, number> = { PRE: 77, CLEAR: 65, POST: 59 };
  const BASE_OTM: Record<string, number> = {
    'PRE|down': 1.5, 'PRE|flat': 0.0, 'PRE|up': 2.5,
    'CLEAR|down': 1.5, 'CLEAR|flat': 1.5, 'CLEAR|up': 2.0,
    'POST|down': 0.5, 'POST|flat': 1.5, 'POST|up': 2.0 };
  // Every modifier measures DEVIATION from what the cell already implies. Absolute
  // readings double-count: "SMH above its 200-day" is true most weeks of a bull market
  // and, scored raw, quietly added points to every single reading.
  const RSI_EXP: Record<string, number> = { down: 30, flat: 50, up: 70 };
  const GRADE_EXP: Record<string, number> = { down: 2, flat: 5, up: 9 };
  const REL_EXP: Record<string, number> = { down: -8, flat: 0, up: 12 };
  const DK = 1 / 2.8;                         // share-points -> delta-points

  // The grade is the one input no feed supplies: was that actually a good quarter?
  // Only meaningful inside the post-print window, and it decays out over 60 sessions.
  // Read from planner_earnings_grade first: it is keyed by QUARTER, so a grade given
  // for the May print stops applying the moment the August one lands rather than
  // silently carrying over. The request body still wins when it carries one — the
  // stepper has to show its own value immediately, before the write settles.
  let gradeRows: Array<{ quarter: string; reported_on: string; grade: number | null }> = [];
  if (supaUrl && supaKey) {
    try {
      const r = await fetch(
        `${supaUrl}/rest/v1/planner_earnings_grade?select=quarter,reported_on,grade` +
        `&ticker=eq.${TICKER}&order=reported_on.desc&limit=8`,
        { headers: { apikey: supaKey, Authorization: `Bearer ${supaKey}` } });
      if (r.ok) gradeRows = await r.json();
    } catch { /* the dial still works; only the history is missing */ }
  }
  // Newest print that has actually happened is the one being asked about.
  const gradeCur = gradeRows[0] ?? null;
  const grade = b.earningsGrade != null ? Number(b.earningsGrade)
    : bookIn.earningsGrade != null ? Number(bookIn.earningsGrade)
    : gradeCur?.grade != null ? Number(gradeCur.grade) : null;
  const gDecay = clamp((60 - sincePrint) / 50, 0, 1);
  const macroHit = cats.filter((c) => c.key === 'macro_events' && c.sev >= 3)[0] ?? null;
  const peerHit = peers.filter((x) => x.days >= 0).sort((x, y) => x.days - y.days)[0] ?? null;
  const inWindow = (d: string) => (nextExp && d <= nextExp ? 2 : secondExp && d <= secondExp ? 1 : 0);

  // ── conviction ──────────────────────────────────────────────────────────────
  // How bullish the tool is on the STOCK. Nothing to do with how many calls to sell.
  // Keeping it separate is what lets Nik disagree with the view without disagreeing
  // with the trade, and lets the tracking loop ask "does conviction predict the next
  // ten sessions" — which is answerable, unlike "was keep 70% correct".
  //
  // Families are capped so five ways of saying "the stock is up" cannot stack. An
  // additive model makes that double-count invisible: it looks like five independent
  // confirmations. 50 is neutral. 80 needs a real reason and 90 a powerful one, so the
  // tails stay rare rather than the whole thing sitting range-bound in the middle.
  const cv: Record<string, number> = {};
  const ma50 = technicals.ma50, ma200 = technicals.ma200, peak = technicals.ath ?? technicals.high52;
  // TREND, capped +22. Above the averages, and how close to the high.
  /* TREND, graded by distance rather than switched on it.
     Both moving-average terms used to be binary: +8 above the 50-day, −8 below,
     with nothing in between, and the same for ±10 on the 200-day. Two consequences,
     both bad, and both visible in one scenario.

     NUMB: NVDA at 220 falling 5% to 209 stays above both averages, so 18 of trend's
     20 points do not move at all. A 5% day moved the whole score by 3.

     THEN A CLIFF: at 205 it crosses the 50-day and that term swings +8 to −8 — a
     16-point lurch in the score on one dollar of price. Nearly blind across the
     range, violently sensitive at one point.

     Proportional fixes both. The scalars are set so TODAY's reading is preserved
     (6.8% above the 50-day still saturates at 8, 14% above the 200-day reaches
     ~9.8 against the old 10) — this is a sensitivity change, not a recalibration,
     and the caps and the meaning are untouched. The same 5% drop now takes trend
     from ~19.7 to ~6.4, and a break of the average is a slope rather than a step. */
  const pctAbove = (v: number, ref: number) => ((v - ref) / ref) * 100;
  const t50 = ma50 != null ? clamp(pctAbove(spot, ma50) * 1.2, -8, 8) : 0;
  const t200 = ma200 != null ? clamp(pctAbove(spot, ma200) * 0.7, -10, 10) : 0;
  const tHigh = peak ? clamp(8 - ((peak - spot) / peak) * 100 * 0.8, -6, 8) : 0;
  const trendParts = { ma50: +t50.toFixed(1), ma200: +t200.toFixed(1), high: +tHigh.toFixed(1) };
  cv.trend = Math.min(22, t50 + t200 + tHigh);
  // CATALYST. The print itself is the reason to be bullish into it — Nik's own words:
  // everything usually looks positive before the print.
  cv.catalyst = daysToEarnings <= 7 ? 12 : daysToEarnings <= 21 ? 10 : daysToEarnings <= 40 ? 4 : 0;
  // STRETCHED, one-directional. Extension is a reason to be LESS bullish, never more.
  cv.stretch = -clamp(Math.abs(dev) >= 1.5 ? (Math.abs(dev) - 1.5) * 5 : 0, 0, 12) * (dev > 0 ? 1 : 0.4);
  cv.record = record && record.n >= 8 ? clamp((record.survived / record.n - 0.7) * 25, -8, 8) : 0;
  cv.relative = relStrength ? clamp(relStrength.gap * 0.6, -6, 6) : 0;
  // A sector stronger than its own norm is a reason to hold more upside; one rolling
  // over is a reason to hold less. Zero when the history cannot support it.
  cv.sector = sectorHealth ? clamp(sectorHealth.dev * 0.5, -8, 8) : 0;
  // PEER PRINTS. Recency-weighted mean of how the neighbours' own reports landed. A
  // print from last week still colours how this one gets read; one from ten weeks ago
  // has been absorbed. Empty table means zero, which is silence rather than optimism.
  cv.peers = peerPrints.length
    ? clamp(peerPrints.reduce((a, x) => a + clamp(x.move, -15, 15) * ((75 - x.days) / 75), 0)
            / peerPrints.length * 0.8, -8, 8)
    : 0;
  // The grade is a bullishness input, so it belongs here rather than moving keep directly.
  cv.grade = grade != null ? clamp((grade - 5) * 2 * gDecay, -8, 8) : 0;
  // Sticky inflation and a live conflict are conditions, not release dates, so no feed
  // carries them. A manual dial, like the grade: the input nobody can fetch is the one
  // worth asking for. Defaults to 0, not to optimism.
  cv.macro = clamp(Number(b.macroBackdrop ?? 0), -12, 12);
  const conviction = Math.round(clamp(50 + Object.values(cv).reduce((a, v) => a + v, 0), 0, 100));

  // Conviction moves keep; IV does not belong in a bullishness read, so it stays here
  // as the one direct keep modifier. Rich premium is a reason to sell, not to be bearish.
  const mods: Record<string, number> = {
    conviction: (conviction - 50) * 0.25,
    // Was capped at +-4 pre-scaling, so +-1.4 points of keep: about four contracts
    // across the ENTIRE range from cheapest to richest options of the year. For a
    // strategy whose whole income is selling volatility, that is no say at all.
    // Now +-11, so roughly +-4 points, which can lean in without outvoting conviction.
    iv: clamp(-11 * (ivPct - 50) / 50, -11, 11) * DK,
  };
  const modRaw = +Object.values(mods).reduce((a, v) => a + v, 0).toFixed(2);
  const readings = mods.iv, gradeMod = cv.grade;
  const keepTarget = clamp(BASE_KEEP[evState] + mods.conviction + mods.iv, 55, 95);
  // The same rule with conviction switched off. Page 01's hero is a comparison —
  // "22 of 60 contracts" — and the 60 has to be a real second run of the sizing,
  // not a guess. Only mods.conviction is removed: the event state, the IV lean and
  // the hedge floor are not opinions about the stock and stay exactly as they are.
  const keepNeutral = clamp(BASE_KEEP[evState] + mods.iv, 55, 95);

  // Distance, scaled by sqrt(time). A fixed % OTM does not hold its delta across expiry
  // lengths: 1.5% out is 36 delta on a four-day and 30 on a two-day. NVDA expires Mon,
  // Wed and Fri, so this is not an edge case.
  const expDays = nextExp ? Math.max(1, spanTo(nowISO, parseISO(nextExp)).td) : 2;
  const tScale = Math.sqrt(expDays / 4);
  // No IV term. It was here on the reasoning that rich premium lets you sell the same
  // money further out — true if you size by premium, wrong when you size by DELTA. At
  // IV 60 it pushed the strike a step out, delta fell 32 to 20, and 75 contracts of a
  // 20-delta strike collected LESS than 70 of a 32-delta one. Being paid a third more
  // made the model take a third less.
  //
  // Without it, rich IV does the right thing unaided: the same strike carries a higher
  // delta, so fewer contracts reach the same exposure and each one pays more.
  /* AT THE MONEY. The distance is no longer a state-dependent percentage.

     Measured two ways and they agree. Against real option marks over two years,
     selling at the money beat 3% out by $99K on NVDA and $71K on MSFT, and tied
     on AAPL. Across 36 synthetic paths in three regimes at two entry prices, it
     won five of six cells.

     The mechanism is contract count, not premium. Holding the delta budget
     fixed, a 0.35-sigma strike carries about 0.37 delta and needs 52 contracts;
     at the money carries 0.50 and needs 38. Those 14 contracts are 1,400 shares
     that can never be called away no matter how far it runs — and a large
     out-of-the-money position's delta EXPANDS on exactly the rally you wanted to
     be in, while a small one is bounded by its own contract count.

     BASE_OTM stays defined and reported: it is the setting this replaced, and a
     future test may want to move off zero rather than rediscover the number. */
  const otmTarget = 0;
  const otmPrior = clamp(BASE_OTM[`${evState}|${pxState}`] * tScale, 0, 4);
  const targetStrike = Math.round(spot / STRIKE_STEP) * STRIKE_STEP;

  // Contract count is arithmetic. Covered calls cannot sell unlimited delta — 75 of them
  // at 3% out reach only ~2,200 — so when the target is out of reach the pick REPORTS the
  // shortfall rather than silently pulling the strike closer to hide it.
  // Two strikes either side of target, which is exactly the span the three picks use.
  // Live quotes replace both premium AND delta, which is right for trading and useless
  // for testing: feeding the model IV 30 against IV 80 changed nothing downstream
  // because the market answered both times. dryQuotes forces the Black-Scholes path so
  // an input sweep actually reaches the output. Never for a real card — the response
  // says `dry` so a modelled number can never be mistaken for a quoted one.
  // From the app's NvPnL — docs/PNL_GLOSSARY.md is the authority on what REALISED
  // means, and re-deriving it here would create a second definition. Null when not
  // sent, and the all-in figure is then omitted rather than guessed at.
  const realisedPL = b.realisedPL != null ? Number(b.realisedPL) : null;
  const dryQuotes = b.dryQuotes === true;
  const quotes = !dryQuotes && key && nextExp
    ? await chainQuotes(TICKER, nextExp, targetStrike - STRIKE_STEP * 2, targetStrike + STRIKE_STEP * 2, key)
    : new Map<number, Quote>();
  const planT = Math.max(expDays, .25) / 252;
  const maxCt = Math.floor(shares / 100);
  // THE HEDGE FLOOR. The puts cost real money every day and the calls have to carry
  // their share of it plus something on top. This is not a preference the score can
  // outvote — it is a floor under the contract count. Being bullish therefore stops
  // meaning "sell nothing" and starts meaning "sell the minimum that pays for the
  // hedge, at the furthest strike that still clears it".
  const HEDGE_MARGIN = Number(b.hedgeMargin ?? 1.5);   // 1.0 = break even, no income
  // THE INCOME TARGET. Set 2026-08-10 from the yield Nik wants net of the hedge:
  // 15-20% on a $1.56M block is $234k-$312k, the puts cost $400k a year, so net premium
  // has to run $634k-$712k — about $12,700 a week.
  //
  // This is what makes rich IV mean something. Sizing off delta alone, a 60-vol week
  // sells the same contract count as a 40-vol week and simply collects more. Sizing off
  // INCOME, the same money needs fewer contracts, and the delta you did not have to sell
  // stays yours. Selling less for the same cheque is the whole point.
  // Period-to-date, for a PACE READOUT only. It reports where the sleeve stands; it
  // does not size anything. Sizing is conviction and keep, with the hedge as a floor.
  const collected = Number(b.premiumCollected ?? 0);
  const boughtBack = Number(b.premiumPaid ?? 0);
  const drag = collected > 0 ? +(boughtBack / collected).toFixed(2) : null;
  const carryPerDay = putSpend > 0 && putDays > 0 ? putSpend / putDays : 0;
  const tradeCal = nextExp ? Math.max(1, spanTo(nowISO, parseISO(nextExp)).cal) : 2;
  const hedgeNeeds = Math.round(carryPerDay * tradeCal * HEDGE_MARGIN);
  /* ── one week's worth of context ──────────────────────────────────────────
     Everything that changes when the expiry changes, and nothing that does not.
     Conviction, the observer, the floor and the book are identical across weeks —
     only the clock and whether the contract carries the print differ. So a second
     week is a small recompute, not a second plan.

     The primary expiry's values already exist above (evState and keepTarget follow
     nextExp), so ctx0 reuses them rather than computing them twice: two code paths
     for the same week is how they drift apart.
     ── */
  type Ctx = {
    exp: string; expDays: number; evState: string; printInside: boolean;
    keepTarget: number; keepNeutral: number; otmTarget: number; targetStrike: number;
    quotes: Map<number, Quote>; planT: number; tradeCal: number; hedgeNeeds: number;
  };
  const ctx0: Ctx = { exp: nextExp ?? '', expDays, evState, printInside,
                      keepTarget, keepNeutral, otmTarget, targetStrike,
                      quotes, planT, tradeCal, hedgeNeeds };

  const mkCtxFor = async (exp: string): Promise<Ctx> => {
    const days = Math.max(1, spanTo(nowISO, parseISO(exp)).td);
    const cal = Math.max(1, spanTo(nowISO, parseISO(exp)).cal);
    const ts = Math.sqrt(days / 4);
    // The same test the primary uses: does THIS contract carry the print.
    const pi = !!(printISO && printISO > nowISO.slice(0, 10) && printISO <= exp);
    const ev = pi ? 'PRE' : sincePrint <= 5 ? 'POST' : 'CLEAR';
    const kt = clamp(BASE_KEEP[ev] + mods.conviction + mods.iv, 55, 95);
    const kn = clamp(BASE_KEEP[ev] + mods.iv, 55, 95);
    // Same rule per chain: at the money, whichever week is being priced.
    const otm = 0;
    const tgt = Math.round(spot / STRIKE_STEP) * STRIKE_STEP;
    const qs = !dryQuotes && key
      ? await chainQuotes(TICKER, exp, tgt - STRIKE_STEP * 2, tgt + STRIKE_STEP * 2, key)
      : new Map<number, Quote>();
    return { exp, expDays: days, evState: ev, printInside: pi,
             keepTarget: kt, keepNeutral: kn, otmTarget: otm, targetStrike: tgt,
             quotes: qs, planT: Math.max(days, .25) / 252, tradeCal: cal,
             hedgeNeeds: Math.round(carryPerDay * cal * HEDGE_MARGIN) };
  };

  const mkPick = (k: number, x: Ctx = ctx0) => {
    const { expDays, quotes, planT, keepTarget, keepNeutral, hedgeNeeds, tradeCal } = x;
    // NVDA expires Mon, Wed and Fri, so a week is THREE rolls, not five sessions divided
    // by the expiry length. The old 2.5 asked each roll to carry too much.
    const rollsWk = Number(b.rollsPerWeek ?? (expDays <= 3 ? 3 : 5 / expDays));
    const q = quotes.get(k);
    const tradeable = !!q && q.mid > 0 && q.bid > 0;
    // Delta from the market when it is quoting one; the model only fills gaps.
    const d = tradeable && q!.delta != null ? q!.delta : bsDelta(spot, k, planT, iv / 100);
    const want = ((100 - keepTarget) / 100) * shares;
    const rawCt = d > 0 ? want / (d * 100) : 0;
    const wantCt = Math.max(0, Math.min(Math.round(rawCt), maxCt));
    const prem = tradeable ? q!.mid : bsCall(spot, k, planT, iv / 100);
    // When the floor binds, the achieved keep will NOT be what conviction asked for.
    // Both numbers are reported: hiding the gap would repeat the exact failure this
    // whole rebuild removed.
    const minCt = prem > 0 && hedgeNeeds > 0 ? Math.min(maxCt, Math.ceil(hedgeNeeds / (prem * 100))) : 0;
    // Three constraints, in plain terms: the hedge sets a floor you cannot go under,
    // conviction sets a ceiling you should not go over, and the income target sits
    // between them. The floor outranks the ceiling — an unpaid hedge is not a choice.
    // KEEP decides the size. A dollar target sat on top of this for a while and
    // overrode it — every pick came back bound by the target, and conviction, the keep
    // model and the whole calibration stopped touching the answer. The hedge floor is
    // the one thing allowed to override, because an unpaid hedge is not a preference.
    const ct = Math.min(Math.max(wantCt, minCt), maxCt);
    // What THIS tier would have sold at a neutral 50. Same strike, same delta, same
    // floor — the only thing that differs is the keep conviction bought. Anything
    // else varying would make the comparison dishonest.
    const rawCtN = d > 0 ? (((100 - keepNeutral) / 100) * shares) / (d * 100) : 0;
    const ctNeutral = Math.min(Math.max(Math.max(0, Math.min(Math.round(rawCtN), maxCt)), minCt), maxCt);
    // wantCt is ALREADY capped at maxCt, so `wantCt > maxCt` could never be true and a
    // capacity-limited pick reported itself as conviction-limited. Compare the uncapped
    // figure. Capacity first: it is a physical limit, not a judgement.
    const wantedRaw = Math.max(0, Math.round(rawCt));
    const boundBy = wantedRaw > maxCt ? 'capacity'
      : minCt > wantCt ? 'hedge floor'
      : 'conviction';
    const income = Math.round(prem * 100 * ct);
    // BREAK-EVEN IS THE STRIKE PLUS WHAT YOU COLLECTED, and you collect again every
    // roll. The model priced each trade standalone, so a 0.5% strike read as a 0.5%
    // cap — when in practice the cushion compounds three times a week while the strike
    // ratchets up behind the stock. Rolling defeats DRIFT. It is gaps it cannot defeat,
    // which is why this cushion is quoted next to the gap test rather than alone.
    const cushWk = prem * rollsWk, cushMo = cushWk * 4.3;

    // What the cap actually costs on a jump, against what you collect waiting for one.
    const GAP = 10;
    const after = spot * (1 + GAP / 100);
    const called = Math.min(ct * 100, shares);
    const cappedGain = called * (k - spot) + income + (shares - called) * (after - spot);
    const freeGain = shares * (after - spot);
    const gapCost = Math.round(freeGain - cappedGain);
    const weeksToCover = income > 0 ? gapCost / (income * rollsWk) : null;
    return { strike: k, otmPct: +(((k - spot) / spot) * 100).toFixed(2),
             delta: Math.round(d * 100), ct, wantCt, minCt,
             floorBinds: minCt > wantCt, boundBy, wantedRaw,
             covers: hedgeNeeds > 0 ? +(income / hedgeNeeds).toFixed(1) : null,
             capped: Math.round(rawCt) > maxCt,
             keptPct: shares > 0 ? +(((shares - ct * d * 100) / shares) * 100).toFixed(0) : 0,
             prem: +prem.toFixed(2), income,
             // Three break-evens: this roll alone, a week of rolling, a month of it. The
             // first is what a single trade caps you at; the other two are what the
             // position actually caps you at, because the cushion compounds.
             breakEven: +(k + prem).toFixed(2),
             beWeek: +(k + cushWk).toFixed(2),
             cushionWeek: +((cushWk / spot) * 100).toFixed(1),
             cushionMonth: +((cushMo / spot) * 100).toFixed(1),
             beMonth: +(k + cushMo).toFixed(2),
             gapPct: GAP, gapCost, weeksToCover: weeksToCover == null ? null : +weeksToCover.toFixed(1),
             rollsPerWeek: +rollsWk.toFixed(1),
             // Which of these you are looking at matters more than the number itself.
             priced: tradeable ? 'market' : 'model',
             bid: q ? +q.bid.toFixed(2) : null, ask: q ? +q.ask.toFixed(2) : null,
             oi: q ? q.oi : null,
             assign: +bsAssign(spot, k, planT, iv / 100).toFixed(2),
             wasCt: ctNeutral,
             // Breakeven against what the shares actually cost, not against spot.
             // Strike plus premium says where the call stops paying; this says what
             // that is worth on a book carried at buyAvg, which is the only version
             // that answers "is this a good place to be called away".
             beBasisPct: book.buyAvg > 0 ? +(((k + prem) / book.buyAvg - 1) * 100).toFixed(2) : null,
             // Assignment odds as a percent, which is how the page states them.
             called: Math.round(bsAssign(spot, k, planT, iv / 100) * 100),
             uncovered: Math.max(0, shares - called),
             label: fmtUsd(income),
             // THE COMPARABILITY NUMBER. $2K over 2 days and $4K over 26 are not
             // comparable as totals — they are $1,000 a day against $154. Without
             // this the expiry choice reads as "more money" when it is usually less.
             creditPerDay: tradeCal > 0 ? Math.round(income / tradeCal) : income,
             // What this goes on to be worth, in three widening frames. Strings, not
             // numbers: the app prints them, and three figures that must agree cannot
             // be rounded independently in two places.
             //   opt      — the credit, which is yours either way
             //   stockOpt — plus what the called shares realise against their cost
             //   all      — plus the P&L already banked this year
             out: {
               opt: fmtUsd(income, true),
               stockOpt: fmtUsd(income + called * (k - book.buyAvg), true),
               all: realisedPL == null ? null
                 : fmtUsd(income + called * (k - book.buyAvg) + realisedPL, true),
             } };
  };
  const plan = {
    event: evState, price: pxState, priceMove: +pxMove.toFixed(1), sincePrint,
    baseline: BASE_KEEP[evState], modifiers: mods, modRaw, readings, gradeMod,
    conviction, convictionParts: cv, trendParts, peerPrints, sectorHealth, closesSeen,
    hedge: { carryPerDay: Math.round(carryPerDay), tradeCal, margin: HEDGE_MARGIN,
             needs: hedgeNeeds, quarterRunRate: Math.round(carryPerDay * 91) },
    // Reported, never used to size.
    pace: { collected, boughtBack, drag },
    keepPct: +keepTarget.toFixed(0), keepDelta: Math.round((keepTarget / 100) * shares),
    otmTarget: +otmTarget.toFixed(2), otmPrior: +otmPrior.toFixed(2),
    targetStrike, expiry: nextExp, expDays,
    // What the caller asked for against what was actually priced. The app must read
    // expiry, never assume its ask was honoured — a stale or unlisted date falls
    // back to the nearest, and silently showing the requested one would put a
    // contract on screen that cannot be sold.
    expiryAsked: askedExp, expiryHonoured: askedExp == null || askedExp === nextExp,
    // WHY the week reads as it does. evState drives BASE_KEEP, so when picking a
    // different expiry changes the size, this is the line that explains it.
    printInside, printDate: printISO,
    // The weeks that can actually be written, so the picker offers only real ones.
    expiryOptions: liveExps.slice(0, 6),
    // One sigma over the life of the trade. Without it "out of the money" reads as safe:
    // at 40% IV over two sessions a strike 2.8% out sits INSIDE one sigma.
    expectedMove: +(spot * (iv / 100) * Math.sqrt(expDays / 252)).toFixed(2),
    quotes: { source: dryQuotes ? 'dry' : quotes.size > 0 ? 'polygon' : 'none', strikes: quotes.size, dry: dryQuotes },
    grade, gradeDecay: +gDecay.toFixed(2),
    // Which quarter the number answers for, and every grade given before it.
    // sessionsAgo is the same trading-day count the decay uses, so the page cannot
    // say "53 sessions ago" while the model fades on a different clock.
    gradeQuarter: gradeCur ? {
      label: gradeCur.quarter, reported: gradeCur.reported_on,
      sessionsAgo: sincePrint, graded: gradeCur.grade != null,
      nextPrint: printRow?.date ? String(printRow.date).slice(0, 10) : null,
    } : null,
    // Oldest first, so the strip reads left to right through time. `current` marks
    // the one the stepper edits; a null grade is "not graded yet", never a zero.
    gradeHistory: gradeRows.slice().reverse().map((g) => ({
      q: g.quarter, on: g.reported_on, g: g.grade,
      current: gradeCur ? g.quarter === gradeCur.quarter : false,
    })),
    picks: [targetStrike, targetStrike - STRIKE_STEP, targetStrike + STRIKE_STEP]
      .map((k) => mkPick(k)),
    keepNeutral: +keepNeutral.toFixed(0),
  };
  /* ── what conviction did to the size ──────────────────────────────────────
     ONE HONEST NOTE, because the card must not overstate the model: conviction
     moves the COUNT, not the strike. otmTarget is BASE_OTM[event|price] scaled by
     sqrt(time) — conviction is not a term in it, so the three tiers sit at the
     same strikes at 91 as they would at 50. A sentence reading "22 at 227.50, not
     60 at 222.50" would be claiming a strike shift the engine does not make.

     So: same strike, different size. If conviction should move the strike too,
     that is a change to the model, not a missing field.
     ── */
  /* ── the weeks on offer ───────────────────────────────────────────────────
     TWO, not four, and chosen by MEANING rather than by count. The nearest live
     expiry is the default — it is what gets written most weeks. The second is the
     first expiry that crosses the next print, because that is the only choice
     that changes the KIND of answer rather than its length: it flips evState to
     PRE, which raises BASE_KEEP, which sizes the sale down.
     Three weeks of the same answer at different lengths is a longer list, not a
     better decision. When no print is in range there is one week, and the page
     should say so rather than pad the row.
     ── */
  /* TIER IS A FUNCTION OF STRIKE, NOT OF ARRAY POSITION.
     picks are built [target, target − step, target + step], and naming them by
     index put "conservative" on the strike one step CLOSER to spot — 0.4% out,
     46% odds of being called — while the furthest strike was called aggressive.
     Exactly backwards, and the stance sentence then repeated the inversion in
     words: "caps almost nothing" on the pick most likely to be called away.
     Sorted furthest-first, the names follow the meaning. */
  const tiers = ['conservative', 'balanced', 'aggressive'];
  const chainFrom = (x: Ctx, picks: ReturnType<typeof mkPick>[]) => ({
    expiry: x.exp,
    chip: x.exp ? fmtDay(x.exp) : '—',
    expCode: x.exp.slice(5),
    expDays: x.expDays,
    evState: x.evState,
    // Null on a clear week. A string here is a consequence, not a label: it is why
    // this week's count is smaller than the one beside it.
    note: x.printInside && printISO
      ? `The ${fmtDay(printISO)} print lands inside this expiry, and conviction sizes it down.`
      : null,
    keepPct: +x.keepTarget.toFixed(0),
    // The neutral-50 sale for this week, so "conviction cut this from 45 lots to 15"
    // has a source rather than being asserted.
    size: { full: picks[0]?.wasCt ?? null, fullStrike: picks[0]?.strike ?? null },
    picks: picks.map((pk, i) => {
      const tier = tiers[i] ?? `tier ${i + 1}`;
      // The recommendation is the TARGET strike, not a fixed slot: after sorting it
      // is usually the middle, but a floor-blocked target can move it.
      const isRec = Math.abs(pk.strike - x.targetStrike) < 1e-6;
      const calledSh = Math.min(pk.ct * 100, shares);
      const free = Math.max(0, shares - calledSh);
      const onBasis = book.buyAvg > 0 ? calledSh * (pk.strike - book.buyAvg) : null;
      const days = x.expDays === 1 ? 'a day' : `${x.expDays} days`;
      /* STANCE — what this tier DOES, in one sentence. Written here rather than in
         the app because it has to name real figures, and a sentence assembled from
         numbers the client re-derived is a sentence that can contradict them. */
      const stance = isRec && !x.printInside
        // Nothing. "Conviction sized this" is already in the row above, and saying
        // it twice in different words was the weakest sentence on the page.
        ? null
        : tier === 'conservative'
        // "Caps almost nothing" was an assumption about the furthest tier, and on a
        // two-day expiry it was flatly wrong: 75 lots at 2.7% out covers EVERY share.
        // Read what is actually left uncapped instead of asserting a shape.
        ? (free > 0
            ? `Caps almost nothing. ${pk.ct} lots, ${pk.otmPct.toFixed(1)}% out, so if the run comes you are still in it.`
            : `${pk.ct} lots at ${pk.otmPct.toFixed(1)}% out, the furthest strike on offer, but it covers every share you hold.`)
        : tier === 'balanced'
        ? (x.printInside
            ? `Sells the print at ${pk.otmPct.toFixed(1)}% out. Conviction cut this from ${pk.wasCt} lots to ${pk.ct}.`
            : `The size conviction sized. Caps the top of the expected move and nothing below it.`)
        : `${fmtUsd(pk.income)} in ${days}, and the next ${pk.otmPct.toFixed(1)}% is the price of it.`;
      /* THE WORLDS — the sale's whole story in three rows: above the strike, between,
         and below. Every covered call has exactly these three outcomes, and stating
         them beats any single summary number. */
      const worlds = [
        { when: `above ${pk.strike}`,
          then: onBasis != null && tier !== 'conservative'
            ? `${calledSh.toLocaleString('en-US')} called at ${pk.strike.toFixed(2)}, ${fmtUsd(onBasis, true)} on basis.`
            : `${calledSh.toLocaleString('en-US')} called. ${free.toLocaleString('en-US')} shares run free.` },
        // The middle row — "nothing called, the credit is yours" — is what BOTH
        // other rows already imply, and it was the one nobody read.
        { when: `under ${Math.round(spot)}`,
          then: tier === 'aggressive'
            ? `${pk.prem.toFixed(2)} of cushion, the deepest of the three.`
            : `${pk.prem.toFixed(2)} a share of cushion, then the floor.` },
      ];
      return { ...pk, tier, rec: isRec, stance, worlds,
               // The design prints this verbatim; a number here would be re-formatted
               // in the app and drift from the credit above it.
               creditPerDayLabel: `${fmtUsd(pk.creditPerDay)}/day` };
    }),
  });
  // Literally the next two. Nik rolls every expiry — Mon, Wed, Fri — and does not
  // write two or three weeks out, so a "first expiry past the print" rule offered a
  // 19-day contract he would never sell. The print is a FLAG on whichever of these
  // two happens to span it, not the reason a week is on the list.
  const altExp = secondExp;
  // Furthest strike first, so index order and tier order are the same thing and
  // cannot drift apart. rec marks the target, wherever it lands in that order.
  const byStrike = (ps: ReturnType<typeof mkPick>[]) =>
    ps.slice().sort((x, y) => y.strike - x.strike);
  const chains = [chainFrom(ctx0, byStrike(plan.picks))];
  if (altExp) {
    const cx = await mkCtxFor(altExp);
    chains.push(chainFrom(cx, byStrike([cx.targetStrike, cx.targetStrike - STRIKE_STEP,
                                        cx.targetStrike + STRIKE_STEP].map((k) => mkPick(k, cx)))));
  }
  (plan as Record<string, unknown>).chains = chains;

  /* ── THE MECHANISM ────────────────────────────────────────────────────────
     The planner's whole answer is two numbers: how much exposure to keep, and
     how far out to sell it. Everything else — which expiry, which strike, how
     many contracts — falls out of those two once a week is chosen, and Nik can
     do that arithmetic faster than the tool can present six versions of it.

     Both are reported in BOTH units, because they are the same decision counted
     two ways and which one reads better depends on the day: delta is what the
     model sizes on, shares is what actually gets called away.

     The distance carries a sigma reading because a bare percentage is silent
     about the thing that matters. At 43 vol over two sessions, one sigma is
     about 2.4% — so "sell 2.4% out" and "sell at the edge of the expected move"
     are the same sentence, and only one of them is legible.
     ── */
  {
    const rec = plan.picks.find((k) => Math.abs(k.strike - targetStrike) < 1e-6) ?? plan.picks[0];
    const covered = Math.min(rec.ct * 100, shares);
    // rec.delta is already per-contract × 100, so ct × delta IS the delta sold.
    const soldDelta = Math.round(rec.ct * rec.delta);
    const em = spot * (iv / 100) * Math.sqrt(Math.max(expDays, 1) / 252);
    (plan as Record<string, unknown>).mechanism = {
      // what conviction asked for, and what the chain could actually deliver —
      // the floor can bind, and hiding that gap is the failure this rebuild removed
      keepPctTarget: +keepTarget.toFixed(0),
      keepPct: shares > 0 ? +(((shares - soldDelta) / shares) * 100).toFixed(0) : null,
      keepDelta: Math.max(0, shares - soldDelta),
      soldDelta, totalDelta: shares,
      contracts: rec.ct, coveredShares: covered, freeShares: Math.max(0, shares - covered),
      otmPct: +rec.otmPct.toFixed(2),
      // The distance is deliberate now, not a residue of rounding, so the page
      // can say "at the money" rather than warn that it is inside a sigma.
      atTheMoney: Math.abs(rec.strike - spot) <= STRIKE_STEP / 2,
      strike: rec.strike,
      // How far the distance sits in the move the market is pricing. Under 1.0
      // means the strike is inside one sigma — which reads as "safely out" and
      // is not.
      sigmas: em > 0 ? +((rec.strike - spot) / em).toFixed(2) : null,
      expectedMove: +em.toFixed(2),
      expiry: nextExp, expDays,
    };
    (plan as Record<string, unknown>).size = {
      sold: rec.ct, full: rec.wasCt,
      strike: rec.strike, fullStrike: rec.strike,
      strikeMoves: false,
    };
  }
  // The old drawdown/IV/measured chain no longer decides this. It stays computed above
  // because keepWhy still reads well, but the number itself now comes from the model.
  keepPct = plan.keepPct;
  keepWhy.unshift(`${evState.toLowerCase()} week, baseline ${BASE_KEEP[evState]}% of delta`);

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
      // sDecay alone asked "is it more than two days out", which scored CPI landing
      // ON the 12 Aug book as mildly safe to sell. The real question is whether it
      // lands inside an expiry you would write now, and if it does the sign flips.
      score: !macroOnFile ? 0 : !nextMacro ? 30
           : (expiryDates[1] && nextMacro.date <= expiryDates[1])
             ? clamp(-45 + nextMacro.days * 4, -45, -10)
             : sDecay(nextMacro.days - 2),
      rows: [['next print', nextMacro ? nextMacro.label : macroOnFile ? 'none in range' : 'not on file'],
             ['days away', nextMacro ? String(nextMacro.days) : '-'],
             ['calendar', macroOnFile ? 'on file' : 'missing']],
      push: !macroOnFile ? 'No economic calendar on file, so this is sitting neutral.'
          : nextMacro && expiryDates[1] && nextMacro.date <= expiryDates[1]
            ? `${nextMacro.label} lands in ${nextMacro.days}d, inside what you would be writing.`
          : 'Nothing scheduled close enough to move the week.' });
  }

  wf.push({ key: 'trend', family: 'THE TAPE', name: 'THE TREND', w: .13, score: trendUp ? -trendStrength * 40 : trendStrength * 30,
    rows: [['50-day vs 200-day', `${(trendRaw * 100).toFixed(1)}%`], ['how strong', trendStrength >= .66 ? 'strong' : trendStrength >= .33 ? 'moderate' : 'weak'], ['direction', trendUp ? 'rising' : 'flat or falling']],
    push: trendUp
      ? 'It is climbing, so selling tight here caps the run you own the shares for.'
      : 'No climb to cap right now, so you can write with a freer hand.' });

  wf.push({ key: 'stretch', family: 'THE TAPE', name: 'THE RUN-UP', w: .09, // clamp(dev * 18, +-35) pinned at 1.94 sigma. Today's dev is 3.59 and a 275 print
    // would be 7.65, so fair value and 23%-above both reported the same +35. tanh over
    // a 4-sigma scale keeps them apart without ever running away.
    score: sTanh(dev / 4) * (1 - .8 * trendStrength),
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

  // CAPACITY, not score. Same shape as a force so the app can render it the same
  // way, but it is summed nowhere: these three answer "how much can you sell", which
  // keepPct, budget and capacityCt already enforce. Scoring them as well meant the
  // book voted twice, and it voted loudest exactly when it had least left to sell.
  const cap: typeof wf = [];
  cap.push({ key: 'freeroll', family: 'THE POSITION', name: 'THE HEDGE', w: .08, score: clamp((freeroll - 100) / 2, -30, 30),
    rows: [['premium banked', `$${Math.round(banked).toLocaleString()}`], ['what it has to cover', maxLoss > 0 ? `$${Math.round(maxLoss).toLocaleString()}` : 'none'], ['covered so far', `${freeroll}%`]],
    push: freerollRegime === 'insurance'
      ? 'Your put floor sits above what you paid for the shares, so premium only has the insurance left to pay for.'
      : freeroll >= 100 ? 'Premium collected already covers the whole downside gap.'
      : `${100 - freeroll}% of the downside gap is still uncovered.` });

  cap.push({ key: 'headroom', family: 'THE POSITION', name: 'ROOM TO RISE', w: .05, // Scaled against the SHARE BLOCK, not against the floor. Dividing spare room by
      // the same floor it sits above made the ratio six-ish and tanh flattened it: the
      // factor pinned at +50 and stopped being a reading at all. Half the block of
      // spare upside now scores ~38, the whole block ~46, so it uses its range.
      score: shares > 0 ? sTanh(headroom / (shares * 0.5)) : 0,
    rows: [['upside you still own', `${Math.round(upsideDelta).toLocaleString()} shares`], ['least you will keep', `${floor.toLocaleString()} shares`], ['spare', `${Math.round(headroom).toLocaleString()} shares`]],
    push: headroom <= 0
      ? 'You are already at the least upside you said you would keep.'
      : `About ${Math.round(headroom).toLocaleString()} shares of upside above your own minimum.` });

  cap.push({ key: 'assignment', family: 'THE POSITION', name: 'BEING CALLED AWAY', w: .10, score: floor > 0 ? sTanh(deltaAfterAssign / floor) : 0,
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

      /* THE SLEEVE, not a blanket. The puts cover putCt × 100 shares out of the
         book, so below the floor the position keeps falling — just more slowly.
         Saying "protected" of a book that is 1/3 covered is the single most
         dangerous thing this page could imply, so every figure here is scoped to
         what is actually covered. */
      puts: putCt, covers: Math.min(putCt * 100, shares), prem: +(putSpend / (putCt * 100)).toFixed(2),
      days: putDays, expiry: putExpISO ? fmtDay(putExpISO) : null,
      cost: -Math.round(putSpend), costLabel: fmtUsd(-putSpend),
      // Where the whole position, puts included, gets back to flat.
      breakeven: +(spot + putSpend / Math.max(shares, 1)).toFixed(2),

      /* THE STRESS CASE, priced rather than implied. A floor is worth what it saves
         in the fall it was bought for, and that number cannot be read off the chart.
         25% down is stated out loud so the figure beside it is legible. */
      stress: (() => {
        const dropPct = 25;
        const to = +(spot * (1 - dropPct / 100)).toFixed(2);
        const cov = Math.min(putCt * 100, shares), unc = Math.max(0, shares - cov);
        const unhedged = shares * (to - spot);
        // Below the floor the covered sleeve stops falling; the rest does not.
        const hedged = cov * (Math.max(to, putFloor) - spot) + unc * (to - spot) - putSpend;
        return { to, dropPct,
                 hedged: Math.round(hedged), unhedged: Math.round(unhedged),
                 saved: Math.round(hedged - unhedged),
                 hedgedLabel: fmtUsd(hedged), unhedgedLabel: fmtUsd(unhedged),
                 savedLabel: fmtUsd(hedged - unhedged, true) };
      })(),

      /* The payoff line's three points, computed HERE. The design had the app derive
         pl(p) from a formula the server never checked — the one place in the deck
         where a drawn line could disagree with the figures printed beside it. Three
         points is all a two-slope line needs. */
      payoff: (() => {
        const cov = Math.min(putCt * 100, shares), unc = Math.max(0, shares - cov);
        const at = (px: number) => Math.round(
          (px >= putFloor ? shares * (px - spot) : cov * (putFloor - spot) + unc * (px - spot)) - putSpend);
        const lo = Math.round(spot * 0.72), hi = Math.round(spot * 1.21);
        return { lo, hi, floor: putFloor, spot,
                 points: [{ px: lo, pl: at(lo) }, { px: putFloor, pl: at(putFloor) }, { px: hi, pl: at(hi) }] };
      })(),
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
    // Which way this argues about SELLING. The composer joins on direction alone and
    // never on causation — "against that" claims two facts are in tension, which is a
    // relationship the tool can see. "because of" would be one it cannot.
    lean?: 'for' | 'against' | 'block';              // block = an event in the way
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

  // Copy register, agreed 2026-08-09. Five rules:
  //   1. Lead with the fact in plain words. The domain label is a quiet eyebrow on the
  //      card, never a bolded prefix, so every sentence has to stand on its own.
  //   2. Attach the consequence. A line that ends on a measurement is not finished.
  //   3. One or two numbers, only where they carry the argument. "2026-08-12" is
  //      "Wednesday".
  //   4. Second person when it touches the book: "the expiry you would be writing".
  //   5. Say what it means for THIS decision.
  // The tension in rule 2 is real: conclusions are where a tool overreaches. A line may
  // explain the tool's own reasoning. It may never predict the stock.
  // The table knows the print date even when the caller does not name it.
  const eDate = earnings.date ?? printRow?.date ?? null;
  const dPrint = daysToPrint;
  const WD = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const when = (iso: string, days: number) =>
    days === 0 ? 'today' : days === 1 ? 'tomorrow'
    : days <= 6 ? `on ${WD[parseISO(iso).getUTCDay()]}`
    : `in ${dayStr(days)}`;

  if (record && record.n >= 8) {
    if (sincePrint <= 30 && bandStats) {
      say(true, { domain: 'record', tag: 'The record', seen: seenBy('record'), note: .90,
        lean: 'against', text: `NVDA has come back ${bandStats.d30 > 0 ? '+' : ''}${bandStats.d30}% within thirty sessions of prints that landed like the last one. On ${bandStats.n} of them${bandStats.n < 8 ? ', so treat it as a lean rather than a law' : ''}.` });
    } else if (dPrint <= 21) {
      say(true, { domain: 'record', tag: 'The record', seen: seenBy('record'), note: .75,
        lean: 'against', text: `This name has landed better than -8% in ${record.survived} of its last ${record.n} prints. Selling upside into that record has been the losing side of it.` });
    } else {
      say(false, { domain: 'record', tag: 'The record', seen: seenBy('record'), note: .10,
        lean: 'for', text: `${record.n} prints on file and none of them make this week look unusual.` });
    }
  }

  if (eDate) {
    const before = expiryDates.filter((d) => d < eDate).length;
    const seen = seenBy('event');
    if (dPrint <= 3) {
      say(true, { domain: 'window', tag: 'The window', seen, note: 1.0,
        lean: 'block', text: `The print is ${dayStr(dPrint)} away. Everything you write now carries it.` });
    } else if (dPrint <= 21) {
      say(true, { domain: 'window', tag: 'The window', seen, note: .60,
        lean: 'block', text: `Earnings in ${dayStr(dPrint)}, with ${before} clean ${before === 1 ? 'expiry' : 'expiries'} before it. Anything past those is an earnings trade whether you meant it or not.` });
    } else {
      say(false, { domain: 'window', tag: 'The window', seen, note: .10,
        lean: 'for', text: `The next print is ${dayStr(dPrint)} out, past anything you would write this week.` });
    }
  }

  if (peersKnown) {
    const behind = peers.filter((x) => x.days < 0).sort((x, y) => y.days - x.days)[0];
    const ahead = peers.filter((x) => x.days >= 0).sort((x, y) => x.days - y.days)[0];
    const nextExp = expiryDates[0];
    const seenHood = seenBy('peers', 'relative');
    const rel = relStrength;
    if (ahead && nextExp && ahead.date <= nextExp) {
      say(true, { domain: 'neighbourhood', tag: 'The neighbourhood', seen: seenHood, note: .95,
        lean: 'block', text: `${ahead.ticker} reports ${when(ahead.date, ahead.days)}, inside the expiry you would be writing${ahead.confirmed ? '' : ', though that date is still an estimate'}. Semis move together through these, so the gap risk is not only NVDA's.` });
    } else if (behind && behind.days >= -7) {
      const landed = peerPrints.filter((x) => x.ticker === behind.ticker).sort((x, y) => x.days - y.days)[0];
      // Direction words keyed at +-8, the band cut, so a -7% print came out as "moved 7%"
      // and lost its sign entirely. The band decides how the RECORD is classified; it has
      // no business deciding whether a sentence says up or down.
      const how = landed
        ? `${landed.move <= -2 ? 'dropped' : landed.move >= 2 ? 'jumped' : 'went nowhere'} ${Math.abs(landed.move) >= 2 ? `${Math.abs(landed.move).toFixed(0)}% ` : ''}on it`
        : 'reported';
      say(true, { domain: 'neighbourhood', tag: 'The neighbourhood', seen: seenHood, note: .70,
        lean: 'against', text: `${behind.ticker} ${how} ${dayStr(-behind.days)} ago${rel ? `, and NVDA is ${rel.gap > 0 ? '+' : ''}${rel.gap}% against the group since. The read-across has not stuck` : ''}.` });
    } else if (rel && Math.abs(rel.gap) >= 5) {
      say(true, { domain: 'neighbourhood', tag: 'The neighbourhood', seen: seenHood, note: .65,
        text: rel.gap > 0
          ? `NVDA is ${rel.gap}% ahead of the group over ${rel.days} sessions. Leading is a better moment to sell upside than a worse one.`
          : `NVDA is ${Math.abs(rel.gap)}% behind the group over ${rel.days} sessions. There is catch-up here you would be capping.` });
    } else if (ahead) {
      say(false, { domain: 'neighbourhood', tag: 'The neighbourhood', seen: seenHood, note: .10,
        lean: 'for', text: `No chip earnings before this expiry. ${ahead.ticker} is next, ${dayStr(ahead.days)} out.` });
    } else {
      say(false, { domain: 'neighbourhood', tag: 'The neighbourhood', seen: seenHood, note: .05,
        text: 'Nothing from the neighbours on the calendar.' });
    }
  }

  const macroKnown = calSources.some((x) => /^macro_events:\d+$/.test(x));
  if (macroKnown) {
    const hits = cats.filter((c) => c.key === 'macro_events' && c.sev >= 3);
    const m = hits[0] ?? null;
    const seen = seenBy('macro');
    const covering = m ? expiryDates.find((d) => d >= m.date) ?? null : null;
    const near = covering ? expiryDates.indexOf(covering) <= 1 : false;
    if (m && near) {
      say(true, { domain: 'macro', tag: 'The calendar', seen, note: .92,
        lean: 'block', text: `${m.label.replace(/\s*\([^)]*\)/, '')} lands ${when(m.date, m.days)}, inside the expiry you would be writing.` });
    } else if (m && m.days <= 14) {
      say(true, { domain: 'macro', tag: 'The calendar', seen, note: .50,
        text: `${m.label.replace(/\s*\([^)]*\)/, '')} ${when(m.date, m.days)}, just past what you would write now.` });
    } else if (m) {
      say(false, { domain: 'macro', tag: 'The calendar', seen, note: .10,
        lean: 'for', text: `Nothing on the economic calendar until ${m.label.replace(/\s*\([^)]*\)/, '')}, ${dayStr(m.days)} out.` });
    } else {
      say(false, { domain: 'macro', tag: 'The calendar', seen: 'priced', note: .05,
        text: 'Nothing scheduled inside the window.' });
    }
  }

  if (ivMedian != null && Number.isFinite(iv) && ivMedian > 0) {
    const extra = (iv / ivMedian - 1) * 100;
    const seen = seenBy('iv_pctile', 'iv_spread');
    if (Math.abs(extra) >= 12) {
      say(true, { domain: 'paid', tag: 'What you are paid', seen, note: .85,
        lean: extra > 0 ? 'for' : 'against',
        text: extra > 0
          ? `You are paid ${extra.toFixed(0)}% over the usual price for this name, ${iv.toFixed(0)}% against a ${ivMedian.toFixed(0)}% normal. That is the argument for doing this today.`
          : `You are paid ${(-extra).toFixed(0)}% under the usual price, ${iv.toFixed(0)}% against a ${ivMedian.toFixed(0)}% normal. Thin premium for the same risk.` });
    } else {
      say(false, { domain: 'paid', tag: 'What you are paid', seen, note: .10,
        lean: 'against', text: `An ordinary price. ${iv.toFixed(0)}% against a ${ivMedian.toFixed(0)}% normal, so there is no premium argument for doing this beyond the roll you were making anyway.` });
    }
  }

  if (technicals.ma50 != null) {
    const rsi = technicals.rsi14;
    const seen = seenBy('trend', 'stretch', 'rsi');
    const hot = rsi != null && rsi >= 70, cold = rsi != null && rsi <= 30;
    const deep = drawdown != null && drawdown >= 12;
    const stretched = Math.abs(dev) >= 1.5;
    const text = stretched
      ? `${dev > 0 ? '+' : ''}${dev} normal days from the 50-day${drawdown != null ? `, ${drawdown.toFixed(0)}% off the high` : ''}. Extension argues for keeping more, not for selling more.`
      : hot ? `Momentum at ${rsi!.toFixed(0)}. Buyers are in charge and the run is stretched alongside you.`
      : cold ? `Momentum at ${rsi!.toFixed(0)}, the washed-out end of its range. Bounces from here run straight into your strikes.`
      : deep ? `${drawdown!.toFixed(0)}% off the high, which is where this name's own record starts to disagree with the tape.`
      : `Mid-range and going nowhere in particular, ${dev > 0 ? '+' : ''}${dev} from the 50-day.`;
    say(stretched || hot || cold || deep, { domain: 'chart', tag: 'The chart', seen,
      // Extension argues for keeping upside; a washed-out tape argues the same way.
      lean: 'against',
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
  // Three bullets are a list; a list makes the reader assemble the argument. Joining on
  // direction gives it an arc — the case, the turn, the obstacle — using only relations
  // the tool can actually see. Deliberately dumb: it never says "because".
  const story = (() => {
    const xs = matters;
    if (xs.length === 0) return null;
    const trim = (t: string) => t.replace(/\.$/, '');
    // "CPI" must not become "cPI". Only lower a leading word that is not an acronym.
    const lower = (t: string) => (/^[A-Z]{2,}/.test(t) ? t : t.replace(/^./, (c) => c.toLowerCase()));
    const parts: string[] = [];
    let turned = false;
    xs.forEach((o, i) => {
      if (i === 0) { parts.push(trim(o.text)); return; }
      const prev = xs[i - 1].lean;
      const opposed = o.lean && prev && o.lean !== prev && o.lean !== 'block' && prev !== 'block';
      if (o.lean === 'block') parts.push(`The one thing in the way is that ${lower(trim(o.text))}`);
      else if (opposed && !turned) { turned = true; parts.push(`Against that, ${lower(trim(o.text))}`); }
      else parts.push(trim(o.text));
    });
    return parts.join('. ') + '.';
  })();

  const observations = {
    matters, story,
    quiet: [...calm].sort((a, b) => rank(a) - rank(b)).slice(0, 3),
    dropped: loud.filter((o) => !matters.includes(o)).map((o) => o.domain),
    silent: DOMAINS.filter((d) => !spoke.has(d)),
  };

  const refStrike = (b.refStrike as number) ?? Math.round(spot / STRIKE_STEP) * STRIKE_STEP;

  /* ── the daily series ───────────────────────────────────────────────────
     Conviction only means something against what it read yesterday, and until
     now nothing kept that. planner_commits holds the parts, but only on days a
     pick was committed — a trail drawn from it would skip every day you did not
     trade and still label the gap "yesterday".

     Written on every full compute, upserted on (ticker, date), so the last read
     of the day is the one that stands. Fire-and-forget on purpose: a history
     table failing to write must never take down the plan the user is waiting on.
     ── */
  const todayIso = new Date().toISOString().slice(0, 10);
  const cvParts: Record<string, number> = {};
  for (const [k, v] of Object.entries(cv as Record<string, number>)) {
    // The engine keys these cv.trend / cv.macro; the page speaks in family names.
    cvParts[k.replace(/^cv\./, '')] = typeof v === 'number' ? +v.toFixed(1) : v;
  }
  let trail: Array<{ date: string; conviction: number; parts: Record<string, number> }> = [];
  if (supaUrl && supaKey) {
    const hdr = { apikey: supaKey, Authorization: `Bearer ${supaKey}`, 'Content-Type': 'application/json' };
    try {
      await fetch(`${supaUrl}/rest/v1/planner_factor_daily?on_conflict=ticker,date`, {
        method: 'POST',
        headers: { ...hdr, Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify({ ticker: TICKER, date: todayIso, conviction, parts: cvParts,
                               spot, event_state: evState, captured_at: new Date().toISOString() }),
      });
    } catch { /* history is a nicety; the plan is not */ }
    try {
      // Three readings INCLUDING today, newest first, then reversed — so the trail
      // reads left to right the way it is drawn. Earlier readings are whatever days
      // actually exist: on a Monday the middle value is Friday, and calling that
      // "yesterday" in the copy would be a lie the data cannot support.
      const r = await fetch(
        `${supaUrl}/rest/v1/planner_factor_daily?select=date,conviction,parts` +
        `&ticker=eq.${TICKER}&order=date.desc&limit=3`, { headers: hdr });
      if (r.ok) trail = ((await r.json()) as typeof trail).reverse();
    } catch { /* an empty trail renders as one reading, which is honest */ }
  }

  return json(200, {
    ok: true, asOf: new Date().toISOString(),
    // The series the conviction page is built on: the hero's trail, each family's
    // own history, and the "what moved" sentence all read from here.
    history: { trail, today: { date: todayIso, conviction, parts: cvParts } },
    source: { spot: polySpot != null ? 'polygon' : 'request', expiries: polyExpiries.length ? 'polygon' : 'fallback', technicals: technicals.ath != null ? 'ticker_stats' : 'missing' },
    gate, book, technicals, assignment, refStrike, weekendVol: wv, expiries,
    // What "all-in" folds in, so the caption can name it rather than the app
    // reaching for a number it was never given.
    outcome: realisedPL == null ? null
      : { realised: realisedPL, realisedLabel: fmtUsd(realisedPL) },
    week, posture, events, refLots, ticker: TICKER, ivMedian, splits, floorAdvice, observations, plan,
    capacity: cap.map((f) => ({ key: f.key, family: f.family, name: f.name, score: +f.score.toFixed(1), rows: f.rows, push: f.push })),
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
