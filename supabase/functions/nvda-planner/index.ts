/**
 * nvda-planner — decision support for the next NVDA short-call sale.
 *
 * A faithful server-side port of the shipped Planner model (planner-data.jsx +
 * ink-planner-commit.jsx). The MATH is verbatim — single-clock Black-Scholes
 * (T = vol_days ÷ 252 used for both the vol term and the discount), the gate,
 * vol-time expiries, the strike chain, guardrail selection, the scenario grid,
 * and the calibration coefficients. Only the INPUTS are live:
 *
 *   • Fresh NVDA spot + the real listed expiry calendar from Polygon.
 *   • Vol/book context (IV, IV-percentile, HV20/30/60/90, the derived book and
 *     greeks) come in on the request from the app's own NvDerive output, so the
 *     Gate's Seller Score is identical to the Volatility card and the P&L
 *     glossary logic is never forked server-side.
 *
 * Request body (all optional except `book` + `vol`):
 *   {
 *     book: { shares, buyAvg, realizedPremium, netDelta, longTheta,
 *             shortCallDelta, shortCallCt,
 *             openShortCalls:[{strike,ct}], longCalls:[{strike,ct,expiry}] },
 *     vol:  { iv, ivPct, hv20, hv30, hv60, hv90 },
 *     earnings: { date:"2026-08-26", label:"Aug 26" },
 *     wash: { hit, on, amount, daysLeft } | null,
 *     settings: { minNetDelta, maxAssign, edgeFloor, weekendVol, edgeLookback } | null,
 *     refStrike?: number, selExpiry?: "YYYY-MM-DD", selStrike?: number,
 *     scenario?: { conv:"expiry"|"half"|"t1", ivSource:"nvda"|"generic" },
 *     spot?: number   // fallback if Polygon is unreachable
 *   }
 *
 * Secret: POLYGON_API_KEY.
 */

const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' };
const json = (s: number, b: unknown) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

const POLY = 'https://api.polygon.io';
const PL_R = 0.045;              // risk-free, matches planner-data.jsx
const STRIKE_STEP = 2.5;
const RIP = 0.15;               // adverse-pair stress move (+15%)
const CADENCE = 126;            // sales a year, for the calibration annualisation

// ---------- Black-Scholes (single clock, verbatim from planner-data.jsx) ----------
function ncdf(x: number): number {
  // Abramowitz–Stegun 7.1.26 — plenty for probability columns quoted to a whole percent.
  const a1 = .254829592, a2 = -.284496736, a3 = 1.421413741, a4 = -1.453152027, a5 = 1.061405429, p = .3275911;
  const s = x < 0 ? -1 : 1;
  const z = Math.abs(x) / Math.SQRT2;
  const t = 1 / (1 + p * z);
  const y = 1 - ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * Math.exp(-z * z);
  return .5 * (1 + s * y);
}
function bsD(S: number, K: number, T: number, v: number): [number, number] {
  const sq = v * Math.sqrt(T);
  const d1 = (Math.log(S / K) + (PL_R + v * v / 2) * T) / sq;
  return [d1, d1 - sq];
}
function bsDelta(S: number, K: number, T: number, v: number): number {
  if (T <= 0) return S > K ? 1 : 0;
  return ncdf(bsD(S, K, T, v)[0]);
}
function bsCall(S: number, K: number, T: number, v: number): number {
  if (T <= 0 || v <= 0) return Math.max(S - K, 0);
  const [d1, d2] = bsD(S, K, T, v);
  return S * ncdf(d1) - K * Math.exp(-PL_R * T) * ncdf(d2);
}
/** Risk-neutral chance of finishing above K. NOT delta — delta is N(d1) and runs high. */
function bsAssign(S: number, K: number, T: number, v: number): number {
  if (T <= 0) return S > K ? 1 : 0;
  return ncdf(bsD(S, K, T, v)[1]);
}

// ---------- Polygon: fresh spot + the real expiry calendar ----------
interface Snap { details?: { strike_price?: number }; underlying_asset?: { price?: number }; day?: { close?: number }; last_quote?: { midpoint?: number }; }

async function nearestSpot(key: string): Promise<number | null> {
  // Underlying price rides along on any option snapshot; the front expiry is the freshest.
  try {
    const r = await fetch(`${POLY}/v3/snapshot/options/NVDA?limit=1&apiKey=${key}`);
    if (!r.ok) return null;
    const j = await r.json();
    const c = (j?.results ?? [])[0] as Snap | undefined;
    return c?.underlying_asset?.price ?? null;
  } catch { return null; }
}

async function callExpiries(fromISO: string, key: string): Promise<string[]> {
  // Distinct listed call expirations from today forward, ascending.
  try {
    const url = `${POLY}/v3/reference/options/contracts?underlying_ticker=NVDA&contract_type=call`
      + `&expiration_date.gte=${fromISO}&expired=false&limit=1000&sort=expiration_date&order=asc&apiKey=${key}`;
    const r = await fetch(url);
    if (!r.ok) return [];
    const j = await r.json();
    const set: string[] = [];
    for (const c of (j?.results ?? []) as { expiration_date?: string }[]) {
      const e = c.expiration_date;
      if (e && !set.includes(e)) set.push(e);
    }
    return set;
  } catch { return []; }
}

// ---------- date helpers (server "now", America/New_York trading calendar) ----------
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
function ymd(d: Date): string {
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
}
function parseISO(s: string): Date { const [y, m, dd] = s.split('-').map(Number); return new Date(Date.UTC(y, m - 1, dd)); }
/** Calendar / trading / weekend day counts between now and an expiry date (exclusive→inclusive). */
function spanTo(nowISO: string, target: Date): { cal: number; td: number; we: number } {
  const d = parseISO(nowISO);
  let cal = 0, td = 0, we = 0;
  while (d < target) {
    d.setUTCDate(d.getUTCDate() + 1);
    cal++;
    const w = d.getUTCDay();
    if (w === 0 || w === 6) we++; else td++;
  }
  return { cal, td, we };
}

// ---------- guardrails + IV response (verbatim) ----------
const LOOKBACKS = ['hv20', 'hv30', 'hv60', 'hv90'] as const;
type Settings = { minNetDelta: number; maxAssign: number; edgeFloor: number; weekendVol: number; edgeLookback: string };
const DEFAULTS: Settings = { minNetDelta: 500, maxAssign: .55, edgeFloor: -.40, weekendVol: .3, edgeLookback: 'hv30' };

const IV_SOURCES: Record<string, { label: string; down: number; up: number; note: string }> = {
  nvda: { label: 'NVDA · 2y regression', down: 1.05, up: -.62, note: '504 sessions, R² 0.61' },
  generic: { label: 'Generic equity skew', down: .80, up: -.50, note: 'default, uncalibrated' },
};
const SCENARIO_STEPS = [-5, -3, -2, -1, -.5, 0, .5, 1, 2, 3, 5];

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const key = Deno.env.get('POLYGON_API_KEY');
  const b = await req.json().catch(() => ({})) as Record<string, unknown>;

  const bookIn = (b.book ?? {}) as Record<string, unknown>;
  const volIn = (b.vol ?? {}) as Record<string, number>;
  if (bookIn.shares == null || volIn.iv == null)
    return json(400, { ok: false, error: 'book.shares and vol.iv are required' });

  const settings: Settings = { ...DEFAULTS, ...((b.settings ?? {}) as Partial<Settings>) };
  const scenarioReq = (b.scenario ?? {}) as { conv?: string; ivSource?: string };
  const conv = scenarioReq.conv === 'half' || scenarioReq.conv === 't1' ? scenarioReq.conv : 'expiry';
  const ivSourceKey = scenarioReq.ivSource === 'generic' ? 'generic' : 'nvda';

  // ---- live inputs ----
  const nowISO = ymd(new Date());
  const [polySpot, polyExpiries] = key
    ? await Promise.all([nearestSpot(key), callExpiries(nowISO, key)])
    : [null, [] as string[]];
  const spot = (b.spot as number) ?? polySpot ?? 0;
  if (!spot) return json(200, { ok: false, error: 'no spot (Polygon unreachable and no spot in request)' });

  // ---- the book, read off the app's NvDerive output ----
  const openShortCalls = (bookIn.openShortCalls ?? []) as { strike: number; ct: number }[];
  const longCallsIn = (bookIn.longCalls ?? []) as { strike: number; ct: number; expiry?: string }[];
  const shares = Number(bookIn.shares);
  const shortCallCt = Number(bookIn.shortCallCt ?? openShortCalls.reduce((a, s) => a + s.ct, 0));
  const book = {
    shares,
    buyAvg: Number(bookIn.buyAvg ?? 0),
    realizedPremium: Number(bookIn.realizedPremium ?? 0),
    netDelta: Number(bookIn.netDelta ?? shares),
    longTheta: Number(bookIn.longTheta ?? 0),
    shortCallDelta: Number(bookIn.shortCallDelta ?? 0),
    shortCallCt,
    longCallCt: longCallsIn.reduce((a, l) => a + l.ct, 0),
    wall: longCallsIn.length ? Math.min(...longCallsIn.map((l) => l.strike)) : Infinity,
    committedShares: shortCallCt * 100,
    freeShares: shares - shortCallCt * 100,
    capacity: Math.max(0, Math.floor((shares - shortCallCt * 100) / 100)),
    basis: 0,
  };
  book.basis = book.buyAvg - book.realizedPremium / (book.shares || 1);

  // ---- vol / gate context ----
  const HV: Record<string, number> = {
    hv20: Number(volIn.hv20 ?? volIn.hv30 ?? 0),
    hv30: Number(volIn.hv30 ?? 0),
    hv60: Number(volIn.hv60 ?? volIn.hv30 ?? 0),
    hv90: Number(volIn.hv90 ?? volIn.hv30 ?? 0),
  };
  const earnings = (b.earnings ?? {}) as { date?: string; label?: string };
  const daysToEarnings = earnings.date
    ? Math.max(0, Math.round((parseISO(earnings.date).getTime() - parseISO(nowISO).getTime()) / 86400000))
    : Number((b.daysToEarnings as number) ?? 99);
  const wash = (b.wash ?? null) as { hit: boolean; on: string; amount: number; daysLeft: number } | null;

  const iv = Number(volIn.iv);
  const ivPct = Number(volIn.ivPct ?? 50);
  const pctFactor = ivPct > 70 ? 1.2 : ivPct < 30 ? .8 : 1.0;
  const hvTrend = HV.hv30 > HV.hv60 && HV.hv60 > HV.hv90 ? 'expanding'
    : HV.hv30 < HV.hv60 && HV.hv60 < HV.hv90 ? 'compressing' : 'stable';
  const hvGap = +Math.abs(HV.hv30 - HV.hv90).toFixed(1);
  const score = (iv / (HV.hv30 || 1)) * pctFactor;
  const scorePass = score >= .80, earningsPass = daysToEarnings >= 5, capacityPass = book.capacity > 0;

  const gate = {
    spot, iv, ivPct, pctFactor,
    hv20: HV.hv20, hv30: HV.hv30, hv60: HV.hv60, hv90: HV.hv90,
    hvTrend, hvGap, score, scorePass, earningsPass, capacityPass,
    daysToEarnings, earnings: earnings.label ?? earnings.date ?? '—', wash,
    blocked: false,
    flags: [] as { key: string; level: string; head: string; body: string }[],
  };
  if (!scorePass) gate.flags.push({ key: 'score', level: 'block', head: 'Skip this cycle',
    body: `Options underpriced against realized. Seller Score ${score.toFixed(2)}, implied ${iv}% sits under ${HV.hv30}% realized, and IV percentile ${ivPct} discounts it further.` });
  if (!earningsPass) gate.flags.push({ key: 'earnings', level: 'block', head: 'Earnings inside 5 days',
    body: `Earnings ${gate.earnings}. Short-dated premium is event premium, not edge.` });
  if (wash?.hit) gate.flags.push({ key: 'wash', level: 'note', head: 'Wash-sale window open',
    body: `Loss of $${wash.amount.toLocaleString()} realized ${wash.on}, ${wash.daysLeft} days left. Assignment at a loss plus a next-day rebuy disallows it and rolls it into new basis.` });
  gate.blocked = gate.flags.some((f) => f.level === 'block');

  // ---- expiry candidates (next 4 listed, vol-time) ----
  const wv = settings.weekendVol;
  const expiryDates = (polyExpiries.length ? polyExpiries : fallbackExpiries(nowISO)).slice(0, 4);
  const expiries = expiryDates.map((iso) => {
    const dt = parseISO(iso);
    const s = spanTo(nowISO, dt);
    const volDays = s.td + wv * s.we;
    return {
      key: iso, iso,
      label: `${MONTHS[dt.getUTCMonth()]} ${dt.getUTCDate()}`,
      dow: DOW[dt.getUTCDay()],
      cal: s.cal, td: s.td, we: s.we,
      volDays: +volDays.toFixed(1),
      T: Math.max(volDays, .25) / 252,
    };
  });
  const selExpiry = expiries.find((e) => e.iso === b.selExpiry) ?? expiries[0];

  // ---- strike chain for the selected expiry ----
  const chain = chainFor(selExpiry.T, book.capacity, settings.edgeLookback, gate, book, HV);

  // ---- expiry comparison table (priced at one reference strike) ----
  const refStrike = (b.refStrike as number) ?? Math.round(spot / STRIKE_STEP) * STRIKE_STEP;
  const expiryRows = expiries.map((e) => {
    const prem = bsCall(spot, refStrike, e.T, iv / 100);
    const fair = bsCall(spot, refStrike, e.T, HV.hv30 / 100);
    return {
      ...e, prem, perDay: prem / (e.td || 1), credit: prem * 100 * book.capacity,
      assign: bsAssign(spot, refStrike, e.T, iv / 100), edge: (prem - fair) * 100,
    };
  });

  // ---- recommendation + signals ----
  const rec = recommend(chain, settings, gate);
  const selStrike = (b.selStrike as number) ?? (rec && !rec.none ? rec.strike : (chain.find((r) => r.sellable) ?? chain[0])?.strike);
  const selRow = chain.find((r) => r.strike === selStrike) ?? chain[0];
  const histAssign = Number((b.histAssign as number) ?? 0);
  const signals = chain.map((r) => ({ strike: r.strike, signals: signalsFor(r, settings, gate, histAssign) }));

  // ---- scenario grid for the selected strike ----
  const co = IV_SOURCES[ivSourceKey];
  const T2 = conv === 'expiry' ? 0 : conv === 'half' ? selExpiry.T / 2 : Math.max(selExpiry.volDays - 1, .25) / 252;
  const scenarioRows = SCENARIO_STEPS.map((p) => {
    const s = spot * (1 + p / 100);
    const ivUsed = Math.max(8, iv + (p < 0 ? Math.abs(p) * co.down : p * co.up));
    const opt = bsCall(s, selRow.strike, T2, ivUsed / 100);
    const shortPl = (selRow.prem - opt) * 100 * book.capacity;
    const sharePl = (s - spot) * book.shares;
    return { p, s: +s.toFixed(2), ivUsed: +ivUsed.toFixed(1), opt: +opt.toFixed(2), shortPl: Math.round(shortPl), sharePl: Math.round(sharePl), combined: Math.round(sharePl + shortPl) };
  });
  const topScen = scenarioRows[scenarioRows.length - 1];

  return json(200, {
    ok: true,
    asOf: new Date().toISOString(),
    source: { spot: polySpot != null ? 'polygon' : 'request', expiries: polyExpiries.length ? 'polygon' : 'fallback' },
    gate, book,
    settings, refStrike,
    expiries: expiryRows,
    selExpiry: selExpiry.iso,
    chain, signals,
    recommendation: rec,
    selStrike: selRow.strike,
    scenario: { conv, ivSource: ivSourceKey, source: co, T2, steps: scenarioRows, givenUp: topScen.sharePl - topScen.combined, topPct: SCENARIO_STEPS[SCENARIO_STEPS.length - 1] },
    meta: { CADENCE, RIP, STRIKE_STEP, ivSources: IV_SOURCES, lookbacks: LOOKBACKS },
  });
});

// ---------- chain (verbatim chainFor) ----------
function chainFor(T: number, ct: number, lookback: string, gate: { spot: number; iv: number }, book: { netDelta: number; shortCallDelta: number; shares: number; longCallCt: number; wall: number; basis: number }, HV: Record<string, number>) {
  const n = ct;
  const lb = LOOKBACKS.includes(lookback as typeof LOOKBACKS[number]) ? lookback : 'hv30';
  const lo = Math.ceil((gate.spot * .96) / STRIKE_STEP) * STRIKE_STEP;
  const hi = Math.floor((gate.spot * 1.12) / STRIKE_STEP) * STRIKE_STEP;
  const affected = Math.min(book.longCallCt, n);
  const out = [];
  for (let k = lo; k <= hi + 1e-9; k += STRIKE_STEP) {
    const prem = bsCall(gate.spot, k, T, gate.iv / 100);
    const fair = bsCall(gate.spot, k, T, HV[lb] / 100);
    const d1 = bsDelta(gate.spot, k, T, gate.iv / 100);
    const sellable = prem >= .05;
    const netDeltaAfter = Math.round(book.netDelta - book.shortCallDelta - d1 * n * 100);
    const span = LOOKBACKS.map((L) => (prem - bsCall(gate.spot, k, T, HV[L] / 100)) * 100);
    const edgeHi = Math.max(...span), edgeLo = Math.min(...span);
    const belowWall = k < book.wall;
    out.push({
      strike: +k.toFixed(2),
      prem, fair, sellable,
      edge: (prem - fair) * 100,
      edgePct: (prem - fair) / prem,
      edgeHi, edgeLo,
      edgePctHi: edgeHi / (prem * 100),
      edgePctLo: edgeLo / (prem * 100),
      edgeCrosses: edgeHi > 0 && edgeLo < 0,
      assign: bsAssign(gate.spot, k, T, gate.iv / 100),
      delta: d1,
      netDeltaAfter,
      pctLong: netDeltaAfter / book.shares,
      effective: k + prem,
      vsBasis: k + prem - book.basis,
      side: belowWall ? 'adverse' : k === book.wall ? 'matched' : 'favorable',
      advCost: belowWall ? (book.wall - k) * 100 * affected : 0,
      affected,
    });
  }
  return out;
}

type Row = ReturnType<typeof chainFor>[number];

// ---------- guardrails + selection (verbatim) ----------
const GUARDS = [
  { key: 'tick', label: 'Sellable premium', test: (r: Row) => r.sellable, miss: (r: Row) => .05 - r.prem, fmt: (m: number) => `$${m.toFixed(2)} of premium` },
  { key: 'delta', label: 'Min net delta', test: (r: Row, st: Settings) => r.netDeltaAfter >= st.minNetDelta, miss: (r: Row, st: Settings) => st.minNetDelta - r.netDeltaAfter, fmt: (m: number) => `${Math.round(m).toLocaleString()} delta short` },
  { key: 'edge', label: 'Edge floor', test: (r: Row, st: Settings) => r.edgePct >= st.edgeFloor, miss: (r: Row, st: Settings) => st.edgeFloor - r.edgePct, fmt: (m: number) => `${Math.abs(m * 100).toFixed(0)} points of premium` },
  { key: 'assign', label: 'Max assign', test: (r: Row, st: Settings) => r.assign <= st.maxAssign, miss: (r: Row, st: Settings) => r.assign - st.maxAssign, fmt: (m: number) => `${(m * 100).toFixed(0)} points of assignment` },
];

function recommend(rows: Row[], st: Settings, gate: { blocked: boolean }) {
  const pass = rows.filter((r) => GUARDS.every((g) => g.test(r, st)));
  if (pass.length) {
    const r = pass[0];
    return {
      none: false, strike: r.strike, blocked: gate.blocked,
      why: `Lowest strike the guardrails allow, so the most premium they allow. ${Math.round(r.assign * 100)}% assign, ${(r.edgePct < 0 ? '−' : '+')}${Math.abs(r.edgePct * 100).toFixed(0)}% of premium in edge, ${(r.netDeltaAfter >= 0 ? '+' : '−')}${Math.abs(r.netDeltaAfter).toLocaleString()} delta left on the book.`,
    };
  }
  let best: { guard: typeof GUARDS[number]; row: Row; miss: number } | null = null;
  GUARDS.forEach((g) => {
    rows.forEach((r) => {
      if (GUARDS.some((o) => o.key !== g.key && !o.test(r, st))) return;
      const m = g.miss(r, st);
      if (!best || m < best.miss) best = { guard: g, row: r, miss: m };
    });
  });
  if (!best) {
    const counts = GUARDS.map((g) => ({ g, n: rows.filter((r) => !g.test(r, st)).length })).sort((a, c) => c.n - a.n)[0];
    return { none: true, strike: null, blocked: gate.blocked, why: `No strike clears the guardrails. ${counts.g.label} rejects ${counts.n} of ${rows.length} rows, and every remaining row fails a second one.` };
  }
  const bst = best as { guard: typeof GUARDS[number]; row: Row; miss: number };
  return { none: true, strike: null, blocked: gate.blocked, why: `${bst.guard.label} binds. The closest row, ${bst.row.strike}, misses by ${bst.guard.fmt(bst.miss)}. Loosen it or skip the cycle. No higher strike is offered as a substitute.` };
}

function signalsFor(r: Row, st: Settings, gate: { blocked: boolean }, histAssign: number) {
  return [
    { k: 'gate', ok: !gate.blocked, label: 'Gate' },
    { k: 'edge', ok: r.edge > 0, label: `Edge at ${st.edgeLookback.toUpperCase()}` },
    { k: 'span', ok: r.edgeHi > 0 && r.edgeLo > 0, label: 'Edge across lookbacks' },
    { k: 'pair', ok: r.advCost === 0, label: 'Long-call pairing' },
    { k: 'assign', ok: !histAssign || r.assign <= histAssign * 1.5, label: 'Assignment vs your rate' },
    { k: 'delta', ok: r.netDeltaAfter >= st.minNetDelta, label: 'Net delta after' },
  ];
}

// ---------- fallback expiry calendar (next 4 weekly Fridays + near sessions) ----------
function fallbackExpiries(nowISO: string): string[] {
  const out: string[] = [];
  const d = parseISO(nowISO);
  for (let i = 1; i <= 21 && out.length < 4; i++) {
    d.setUTCDate(d.getUTCDate() + 1);
    const w = d.getUTCDay();
    if (w === 1 || w === 3 || w === 5) out.push(ymd(d));  // Mon/Wed/Fri listed dailies
  }
  return out;
}
