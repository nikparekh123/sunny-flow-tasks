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
const STRIKE_STEP = 2.5;
const RIP = 0.15;

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

// One priced strike. The first block is the original pricing payload; the second is
// what the fit pass adds once the week's prescription is known.
interface Cell {
  strike: number; prem: number; fair: number; sellable: boolean;
  intrinsic: number; ext: number; extPct: number;
  edge: number; edgePct: number; edgeHi: number; edgeLo: number;
  edgePctHi: number; edgePctLo: number; edgeCrosses: boolean;
  assign: number; delta: number; effective: number; vsBasis: number;
  side: string; advCost: number; affected: number;
  perDay?: number; deltaSold?: number; freeAfter?: number; afterAssign?: number;
  warns?: string[]; blocks?: string[]; fit?: number; isPick?: boolean;
  fitParts?: { k: string; w: number; s: number; contribution: number }[];
}

// ── Polygon: spot + expiry calendar ──
interface Snap { underlying_asset?: { price?: number }; }
async function nearestSpot(key: string): Promise<number | null> {
  try {
    const r = await fetch(`${POLY}/v3/snapshot/options/NVDA?limit=1&apiKey=${key}`);
    if (!r.ok) return null;
    const j = await r.json();
    return ((j?.results ?? [])[0] as Snap | undefined)?.underlying_asset?.price ?? null;
  } catch { return null; }
}
async function callExpiries(fromISO: string, key: string): Promise<string[]> {
  try {
    const r = await fetch(`${POLY}/v3/reference/options/contracts?underlying_ticker=NVDA&contract_type=call`
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
  const nowISO = ymd(new Date());
  const [polySpot, polyExpiries] = key ? await Promise.all([nearestSpot(key), callExpiries(nowISO, key)]) : [null, [] as string[]];
  const spot = (b.spot as number) ?? polySpot ?? 0;
  if (!spot) return json(200, { ok: false, error: 'no spot' });

  // ── ticker_stats (technicals for Upside Room) ──
  let ts: Record<string, number | string | null> = {};
  if (supaUrl && supaKey) {
    try {
      const r = await fetch(`${supaUrl}/rest/v1/ticker_stats?ticker=eq.NVDA&select=*`, { headers: { apikey: supaKey, Authorization: `Bearer ${supaKey}` } });
      if (r.ok) ts = ((await r.json()) as Record<string, number | string | null>[])[0] ?? {};
    } catch { /* leave empty → app degrades the card */ }
  }
  // ── the calendar, from the seeded event tables ──
  // The old gate knew one date: earnings. A high-beta name still reacts to macro,
  // so density (severity summed over a horizon) is what the week score reads.
  type Cat = { key: string; label: string; date: string; days: number; sev: number };
  const cats: Cat[] = [];
  if (supaUrl && supaKey) {
    const h = { apikey: supaKey, Authorization: `Bearer ${supaKey}` };
    const soon = ymd(new Date(Date.now() + 120 * 86400000));
    const grab = async (table: string, dateCol: string, nameCol: string) => {
      try {
        const r = await fetch(`${supaUrl}/rest/v1/${table}?select=*&${dateCol}=gte.${nowISO}&${dateCol}=lte.${soon}&order=${dateCol}.asc&limit=40`, { headers: h });
        if (!r.ok) return;
        for (const row of (await r.json()) as Record<string, unknown>[]) {
          const d = String(row[dateCol] ?? '').slice(0, 10);
          if (!d) continue;
          const label = String(row[nameCol] ?? row.title ?? row.name ?? table);
          cats.push({ key: table, label, date: d, sev: severityOf(label),
            days: Math.round((parseISO(d).getTime() - parseISO(nowISO).getTime()) / 86400000) });
        }
      } catch { /* a missing table just means a thinner calendar */ }
    };
    await Promise.all([
      grab('earnings_events', 'event_date', 'label'),
      grab('macro_events', 'event_date', 'label'),
    ]);
  }
  cats.sort((x, y) => x.days - y.days);

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
    daysToEarnings, earnings: earnings.label ?? earnings.date ?? '—', wash, blocked: false,
    flags: [] as { key: string; level: string; head: string; body: string }[],
  };
  if (!gate.scorePass) gate.flags.push({ key: 'score', level: 'block', head: 'Skip this cycle', body: `Options underpriced against realized. Seller Score ${score.toFixed(2)}, implied ${iv}% sits under ${HV.hv30}% realized, and IV percentile ${ivPct} discounts it further.` });
  if (!gate.earningsPass) gate.flags.push({ key: 'earnings', level: 'block', head: 'Earnings inside 5 days', body: `Earnings ${gate.earnings}. Short-dated premium is event premium, not edge.` });
  if (wash?.hit) gate.flags.push({ key: 'wash', level: 'note', head: 'Wash-sale window open', body: `Loss of $${wash.amount.toLocaleString()} realized ${wash.on}, ${wash.daysLeft} days left. Assignment at a loss plus a next-day rebuy disallows it and rolls it into new basis.` });

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
  const expectedCalled = (openShortCalls as { strike: number; ct: number; expiry?: string }[])
    .reduce((a, l) => a + bsAssign(spot, l.strike, legT(l.expiry), iv / 100) * l.ct * 100, 0);
  const sharesAfterAssign = shares - book.shortCallCt * 100;          // tail: all called
  const deltaAfterWorst = sharesAfterAssign + putDelta;
  const deltaAfterAssign = shares - expectedCalled + putDelta;        // expected path
  const assignFloor = shares * 0.15;
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
    gate.flags.push({ key: 'assign', level: 'block', head: 'Assignment would leave you net short',
      body: `On current odds ${Math.round(expectedCalled).toLocaleString()} of ${shares.toLocaleString()} shares get called away, against a put hedge carrying ${Math.round(putDelta).toLocaleString()} delta — a net ${Math.round(deltaAfterAssign).toLocaleString()}. The hedge is sized to the whole block and does not leave with the shares.` });
  } else if (assignment.known && (assignment.thin || assignment.worstNetShort)) {
    gate.flags.push({ key: 'assign', level: 'note', head: 'Thin after assignment',
      body: `Expected call-away of ${Math.round(expectedCalled).toLocaleString()} shares leaves ${Math.round(deltaAfterAssign).toLocaleString()} delta against a ${Math.round(assignFloor).toLocaleString()} floor.`
        + (assignment.worstNetShort ? ` If all ${book.shortCallCt} were assigned it would be ${Math.round(deltaAfterWorst).toLocaleString()} — short.` : '') });
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
  if (events.daysToHeavy <= HORIZON) push('event', 1.40, `${heavy?.label ?? 'print'} in ${events.daysToHeavy}d — don't be capped into a gap`);
  if (state === 'WASHOUT') push('washout', 1.25, "under its mean — don't cap the bounce");
  if (state === 'STRETCH') push('stretch', 0.85, 'extended — fine to cap here');
  if (spot < book.buyAvg) push('under_basis', 1.20, 'spot under your average — assignment books a loss');
  const floorBase = shares * 0.15;
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

  // ── the week's forces ──
  const wf: { key: string; name: string; w: number; score: number; rows: [string, string][]; push: string }[] = [];
  wf.push({ key: 'iv_pctile', name: 'IV PERCENTILE', w: .16, score: sPct(ivPct),
    rows: [['IV percentile', String(Math.round(ivPct))], ['30d IV', `${iv.toFixed(1)}%`], ['factor', pctFactor.toFixed(2)]],
    push: ivPct >= 60 ? 'implied rich against its own year — sell into it' : ivPct <= 30 ? 'implied cheap against its own year — stay short-dated' : 'implied mid-range — no edge from level alone' });
  wf.push({ key: 'iv_spread', name: 'PAID VS REALIZED', w: .11, score: sTanh(((iv - HV.hv30) / (HV.hv30 || 1)) * 2.5),
    rows: [['30d IV', `${iv.toFixed(1)}%`], ['30d realized', `${HV.hv30.toFixed(1)}%`], ['trend', hvTrend]],
    push: iv > HV.hv30 ? `implied over realized by ${(iv - HV.hv30).toFixed(1)} — paid for movement that isn't there` : 'realized over implied — underpaid for this tape' });
  wf.push({ key: 'event', name: 'EVENT CLOCK', w: .23, score: sDecay(events.daysToHeavy - 7),
    rows: [['next heavy', heavy ? `${heavy.label} ${heavy.days}d` : '—'], ['density 14d', String(density)], ['earnings', `${daysToEarnings}d`]],
    push: events.daysToHeavy <= 7 ? 'a print lands inside the week — short-dated premium is event premium' : `clear of the print by ${events.daysToHeavy - 7}d` });
  wf.push({ key: 'trend', name: 'TREND', w: .13, score: trendUp ? -trendStrength * 40 : trendStrength * 30,
    rows: [['50 vs 200', `${(trendRaw * 100).toFixed(1)}%`], ['strength', trendStrength.toFixed(2)], ['direction', trendUp ? 'up' : 'down/flat']],
    push: trendUp ? 'trending up — writing tight caps the move you own it for' : 'no upward trend to cap — write with a freer hand' });
  wf.push({ key: 'stretch', name: 'STRETCH', w: .09, score: clamp(dev * 18, -35, 35) * (1 - .8 * trendStrength),
    rows: [['vs 50-day', `${dev > 0 ? '+' : ''}${dev}σ`], ['state', state], ['damped by trend', `×${(1 - .8 * trendStrength).toFixed(2)}`]],
    push: state === 'STRETCH' ? 'extended — reversion pays the seller' : state === 'WASHOUT' ? "under its mean — don't cap the bounce" : 'mid-range — no regime edge' });
  wf.push({ key: 'rsi', name: 'RSI', w: .05, score: technicals.rsi14 != null ? sPct(technicals.rsi14) : 0,
    rows: [['RSI 14', technicals.rsi14 != null ? technicals.rsi14.toFixed(0) : '—'], ['52w high', technicals.high52?.toFixed(2) ?? '—'], ['52w low', technicals.low52?.toFixed(2) ?? '—']],
    push: (technicals.rsi14 ?? 50) >= 70 ? 'overbought — the tape is stretched with you' : (technicals.rsi14 ?? 50) <= 30 ? 'oversold — a bounce would run into your strikes' : 'neutral' });
  wf.push({ key: 'freeroll', name: 'FREEROLL', w: .08, score: clamp((freeroll - 100) / 2, -30, 30),
    rows: [['banked premium', `$${Math.round(banked).toLocaleString()}`], ['structural risk', maxLoss > 0 ? `$${Math.round(maxLoss).toLocaleString()}` : '—'], ['regime', freerollRegime]],
    push: freerollRegime === 'insurance' ? 'floor sits above basis — premium only has the hedge to pay for' : freeroll >= 100 ? 'the corridor is paid for' : `${100 - freeroll}% of the corridor still open` });
  wf.push({ key: 'headroom', name: 'HEADROOM', w: .05, score: floor > 0 ? sTanh(headroom / floor) : 0,
    rows: [['upside Δ', Math.round(upsideDelta).toLocaleString()], ['floor', floor.toLocaleString()], ['headroom', Math.round(headroom).toLocaleString()]],
    push: headroom <= 0 ? 'the floor is already eaten' : `${Math.round(headroom).toLocaleString()}Δ over the floor` });

  wf.push({ key: 'assignment', name: 'AFTER ASSIGNMENT', w: .10, score: floor > 0 ? sTanh(deltaAfterAssign / floor) : 0,
    rows: [['expected call-away', Math.round(expectedCalled).toLocaleString()], ['hedge Δ', Math.round(putDelta).toLocaleString()], ['net after', Math.round(deltaAfterAssign).toLocaleString()]],
    push: deltaAfterAssign < 0 ? 'full assignment turns the book short — write nothing more until the hedge or the calls move' : `${Math.round(deltaAfterAssign).toLocaleString()}Δ survives a full call-away` });

  const weekScore = Math.round(clamp(50 + wf.reduce((a, f) => a + f.w * f.score, 0), 0, 100));
  const stance = weekScore >= 65 ? 'SELL HARD' : weekScore >= 45 ? 'SELL NORMAL' : weekScore >= 30 ? 'SELL LIGHT' : 'SIT OUT';
  const prescription = {
    'SELL HARD':   { deltaLo: .30, deltaHi: .35, sizePct: 1.0,  tenor: 'reach for the richer date' },
    'SELL NORMAL': { deltaLo: .25, deltaHi: .30, sizePct: 0.75, tenor: 'nearest clear expiry' },
    'SELL LIGHT':  { deltaLo: .18, deltaHi: .25, sizePct: 0.5,  tenor: 'short-dated only' },
    'SIT OUT':     { deltaLo: .15, deltaHi: .22, sizePct: 0.0,  tenor: 'the week is the answer' },
  }[stance]!;
  const maxLotsFloor = Math.floor((upsideDelta - floor) / 100);
  const maxLotsAssign = Math.floor((shares - expectedCalled + putDelta) / 100);
  const maxLots = Math.max(0, Math.min(maxLotsFloor, maxLotsAssign));
  const binding = maxLots === 0 ? (maxLotsAssign <= maxLotsFloor ? 'assignment' : 'floor')
    : maxLotsAssign < maxLotsFloor ? 'assignment' : 'floor';
  // A rich week you cannot act on is not a sell signal. Capacity overrides the score.
  const effStance = maxLots === 0 ? 'SIT OUT' : stance;
  const stanceReason = maxLots === 0
    ? (binding === 'assignment' ? 'no capacity — assignment already goes net short' : 'no capacity — the floor is eaten')
    : null;
  const week = {
    score: weekScore, stance: effStance, rawStance: stance, stanceReason, binding, prescription,
    lots: { base: Math.max(0, Math.round(maxLots * prescription.sizePct)), max: maxLots,
            byFloor: Math.max(0, maxLotsFloor), byAssignment: Math.max(0, maxLotsAssign), free: book.freeShares / 100 },
    forces: wf.map((f) => ({ ...f, contribution: +(f.w * f.score).toFixed(1) })),
    caption: (() => {
      const sorted = wf.slice().sort((x, y) => y.w * y.score - x.w * x.score);
      const up = sorted.filter((f) => f.score > 0), dn = sorted.filter((f) => f.score < 0);
      return `${up.length ? up.slice(0, 2).map((f) => f.name.toLowerCase()).join(' + ') + ' carry it' : 'nothing carries it'} · ${dn.length ? dn[dn.length - 1].name.toLowerCase() + ' is the drag' : 'nothing pushes back'}`;
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
  const bandMid = (prescription.deltaLo + prescription.deltaHi) / 2;
  const bandHalf = (prescription.deltaHi - prescription.deltaLo) / 2;

  const expiries = expiryDates.map((iso) => {
    const dt = parseISO(iso); const s = spanTo(nowISO, dt); const volDays = s.td + wv * s.we; const T = Math.max(volDays, .25) / 252;
    const load = loadByExpiry[iso] ?? 0;
    const eventInside = cats.filter((c) => c.sev >= 4 && c.days <= s.cal)[0] ?? null;
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
    for (const c of chain) {
      const perDay = (c.prem * 100) / Math.max(s.cal, 1);
      const deltaSold = c.delta * refLots * 100;
      const freeAfter = upsideDelta - deltaSold;
      const afterAssign = shares - expectedCalled - c.delta * refLots * 100 + putDelta;
      const bandDist = Math.max(0, Math.abs(c.delta - bandMid) - bandHalf);
      const parts = [
        { k: 'per_day', w: .25, s: sTanh(2 * (perDay / bestPerDay - .75)) },
        { k: 'in_band', w: .25, s: clamp(50 - bandDist * 500, -50, 50) },
        { k: 'headroom', w: .20, s: floor > 0 ? sTanh((freeAfter - floor) / floor) : 0 },
        { k: 'assignment', w: .15, s: floor > 0 ? sTanh(afterAssign / floor) : 0 },
        { k: 'over_basis', w: .10, s: sTanh(((c.strike - book.basis) / (book.basis || 1)) * 20) },
        { k: 'expiry_load', w: .05, s: clamp(50 - load * 1.5, -50, 50) },
      ];
      const warns: string[] = [];
      if (c.delta > .45) warns.push('NEAR ATM');
      if (c.prem < .12) warns.push('THIN BID');
      if (perDay < bestPerDay * .75) warns.push('$/DAY LIGHT');
      if (state === 'STRETCH' && c.delta > .35) warns.push('FIGHTS STRETCH');
      if (state === 'WASHOUT' && c.delta > .30) warns.push('CAPS THE BOUNCE');
      const blocks: string[] = [];
      if (c.strike < book.basis) blocks.push(`below basis ${book.basis.toFixed(2)}`);
      if (freeAfter < floor) blocks.push(`free Δ ${Math.round(freeAfter).toLocaleString()} < floor ${floor.toLocaleString()}`);
      if (afterAssign < 0) blocks.push('assignment goes net short');
      if (eventInside) blocks.push(`spans ${eventInside.label}`);
      const PEN: Record<string, number> = { '$/DAY LIGHT': 12, 'NEAR ATM': 10, 'THIN BID': 14, 'FIGHTS STRETCH': 10, 'CAPS THE BOUNCE': 10 };
      const raw = clamp(50 + parts.reduce((a, p) => a + p.w * p.s, 0), 0, 100);
      Object.assign(c, {
        perDay, deltaSold, freeAfter, afterAssign, warns, blocks,
        fitParts: parts.map((p) => ({ ...p, s: +p.s.toFixed(1), contribution: +(p.w * p.s).toFixed(1) })),
        fit: Math.round(Math.max(0, raw - warns.reduce((a, w) => a + (PEN[w] ?? 8), 0))),
      });
    }
    const live = chain.filter((c) => !c.blocks?.length);
    const pick = live.slice().sort((x, y) => (y.fit ?? 0) - (x.fit ?? 0))[0] ?? null;
    if (pick) pick.isPick = true;

    return { key: iso, iso, label: `${MONTHS[dt.getUTCMonth()]} ${dt.getUTCDate()}`, dow: DOW[dt.getUTCDay()], cal: s.cal, td: s.td, we: s.we, volDays: +volDays.toFixed(1), T,
      load, eventInside, pickStrike: pick?.strike ?? null, chain };
  });

  const refStrike = (b.refStrike as number) ?? Math.round(spot / STRIKE_STEP) * STRIKE_STEP;

  return json(200, {
    ok: true, asOf: new Date().toISOString(),
    source: { spot: polySpot != null ? 'polygon' : 'request', expiries: polyExpiries.length ? 'polygon' : 'fallback', technicals: technicals.ath != null ? 'ticker_stats' : 'missing' },
    gate, book, technicals, assignment, refStrike, weekendVol: wv, expiries,
    week, posture, events, refLots,
    meta: { STRIKE_STEP, RIP, lookbacks: LOOKBACKS, ivSources: { nvda: { label: 'NVDA · 2y regression', down: 1.05, up: -.62, note: '504 sessions, R² 0.61' }, generic: { label: 'Generic equity skew', down: .80, up: -.50, note: 'default, uncalibrated' } } },
  });
});
