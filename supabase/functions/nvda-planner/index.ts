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
 *            shortCallCt,openShortCalls[],longCalls[]},
 *     vol:{iv,ivPct,hv20,hv30,hv60,hv90}, earnings:{date,label}, wash|null,
 *     weekendVol?:0.3, refStrike?, spot? }
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
  const sharesAfterAssign = shares - book.shortCallCt * 100;
  const deltaAfterAssign = sharesAfterAssign + putDelta;
  const assignFloor = shares * 0.15;
  const assignment = {
    sharesAfter: sharesAfterAssign, putDelta, deltaAfter: deltaAfterAssign,
    coveredPct: shares > 0 ? (book.shortCallCt * 100) / shares : 0,
    netShort: deltaAfterAssign < 0, thin: deltaAfterAssign < assignFloor,
    known: netDeltaSent || bookIn.putDelta != null,
  };
  if (assignment.known && assignment.netShort) {
    gate.flags.push({ key: 'assign', level: 'block', head: 'Assignment would leave you net short',
      body: `${book.shortCallCt} contracts cover ${(book.shortCallCt * 100).toLocaleString()} of ${shares.toLocaleString()} shares. If they are all called away you keep ${sharesAfterAssign.toLocaleString()} shares against a put hedge carrying ${Math.round(putDelta).toLocaleString()} delta — a net ${Math.round(deltaAfterAssign).toLocaleString()}. The hedge is sized to the whole block and does not leave with the shares.` });
  } else if (assignment.known && assignment.thin) {
    gate.flags.push({ key: 'assign', level: 'note', head: 'Thin after assignment',
      body: `Full assignment leaves ${Math.round(deltaAfterAssign).toLocaleString()} delta against a ${Math.round(assignFloor).toLocaleString()} floor. Writing more here shrinks it further.` });
  }
  gate.blocked = gate.flags.some((f) => f.level === 'block');

  // ── expiries + priced chains (per-contract, ct-independent; the app scales) ──
  const expiryDates = (polyExpiries.length ? polyExpiries : fallbackExpiries(nowISO)).slice(0, 6);
  const lo = Math.ceil((spot * .96) / STRIKE_STEP) * STRIKE_STEP;
  const hi = Math.floor((spot * 1.12) / STRIKE_STEP) * STRIKE_STEP;
  const affected = book.longCallCt;

  const expiries = expiryDates.map((iso) => {
    const dt = parseISO(iso); const s = spanTo(nowISO, dt); const volDays = s.td + wv * s.we; const T = Math.max(volDays, .25) / 252;
    const chain = [];
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
    return { key: iso, iso, label: `${MONTHS[dt.getUTCMonth()]} ${dt.getUTCDate()}`, dow: DOW[dt.getUTCDay()], cal: s.cal, td: s.td, we: s.we, volDays: +volDays.toFixed(1), T, chain };
  });

  const refStrike = (b.refStrike as number) ?? Math.round(spot / STRIKE_STEP) * STRIKE_STEP;

  return json(200, {
    ok: true, asOf: new Date().toISOString(),
    source: { spot: polySpot != null ? 'polygon' : 'request', expiries: polyExpiries.length ? 'polygon' : 'fallback', technicals: technicals.ath != null ? 'ticker_stats' : 'missing' },
    gate, book, technicals, assignment, refStrike, weekendVol: wv, expiries,
    meta: { STRIKE_STEP, RIP, lookbacks: LOOKBACKS, ivSources: { nvda: { label: 'NVDA · 2y regression', down: 1.05, up: -.62, note: '504 sessions, R² 0.61' }, generic: { label: 'Generic equity skew', down: .80, up: -.50, note: 'default, uncalibrated' } } },
  });
});
