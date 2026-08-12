/**
 * tlt-planner — the accumulation mechanism for the TLT sleeve.
 *
 * Spec: docs/TLT_ACCUMULATION.md. Read it before changing weights here.
 *
 * This is NOT nvda-planner parameterised. NVDA has one intention forever — hold
 * the block, sell vol against it. TLT's intention rotates: want shares, keep
 * shares, sell shares. Almost every sign in this file follows from that.
 *
 * The shape of a week:
 *
 *   weekly delta = (quarter budget ÷ 13) × price factor × conviction factor
 *
 * Price is the driver (0.25×–2.5×), conviction is the trim (0.7×–1.3×), and the
 * $400K commitment ceiling is the only thing allowed to say no. When the top
 * corner of both multipliers lands past the ceiling, the ceiling cuts the trade —
 * that is the design, not a miscalibration.
 *
 * Nine families score conviction. Eight are positive and normalise to 100 over
 * whatever data actually arrived; `calendar` is a damper that only subtracts.
 * A family whose source is down drops out of the denominator rather than
 * scoring zero — a missing feed must not read as bearish.
 *
 * Sources, all free:
 *   FRED       real · curve · path · print · stretch · carry   (FRED_API_KEY)
 *   Treasury   supply                                          (no key)
 *   Postgres   bloc (tlt_voter_bloc) · calendar (tlt_macro_events)
 *   Polygon    spot, chains, dividends                         (POLYGON_API_KEY)
 *
 * Env: FRED_API_KEY, POLYGON_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
 * Body (all optional): {"dry_run":true,"phase":"HOLD","asof":"2026-08-12"}
 */

const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' };
const json = (s: number, b: unknown) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

const POLY = 'https://api.polygon.io';
const FRED = 'https://api.stlouisfed.org/fred/series/observations';
const FISCAL = 'https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v1/accounting/od/auctions_query';
const TICKER = 'TLT';
const STRIKE_STEP = 0.5;
const R_FREE = 0.045;
const IV_FALLBACK = 0.13;          // TLT sits 11–15%; only used if tlt_iv_daily is empty

// ── the nine families ───────────────────────────────────────────────────────
// Eight positives sum to 100. calendar is a damper and never adds.
const CAPS = {
  real: 16, curve: 16, path: 14, print: 12,
  stretch: 12, carry: 12, supply: 10, bloc: 8,
  calendar: -12,
} as const;

// Price is the driver. Bands are Nik's, absolute, and deliberately coarse.
// ORDER MATTERS: these are scanned with find(spot < hi) and must stay ASCENDING.
// With Infinity first, every price matches the first row and the multiplier pins
// at 0.25x forever — which is exactly what happened on the first live run.
const PRICE_BANDS: Array<[number, number, string]> = [
  [75, 2.50, 'below 75'],
  [80, 1.50, '75–80'],
  [85, 0.75, '80–85'],
  [Infinity, 0.25, 'above 85'],
];

// Conviction is the trim: a continuous ramp between the agreed 0.7x and 1.3x.
//
// This was three steps. Steps put a 30% swing on a 1-point move, and the live run
// landed conviction at exactly 70 the day CPI cleared — one point from doubling
// the trade. The ramp is anchored through the centres of the old bands (15 / 50 /
// 85) rather than drawn 0-to-100, so the endpoints stay REACHABLE: a plain line
// would make 0.7x and 1.3x require a 0 or a 100, which never happen, quietly
// compressing the range everyone agreed to.
function convFactor(score: number): { f: number; band: string } {
  const s = clamp(score, 0, 100);
  const f = s <= 15 ? 0.7
    : s <= 50 ? 0.7 + 0.3 * ((s - 15) / 35)
    : s <= 85 ? 1.0 + 0.3 * ((s - 50) / 35)
    : 1.3;
  return {
    f: Math.round(f * 1000) / 1000,
    band: s <= 15 ? 'floor (≤15)' : s >= 85 ? 'ceiling (≥85)' : 'ramp',
  };
}

// The call side is a function of the PHASE, not the ticker. HARVEST is the only
// phase that inherits NVDA's ATM result, because it is the only one where the
// intention matches: monetising a block you are content to lose.
//
// ACCUMULATE is OFF, measured rather than assumed (research/tlt-strike-policy,
// 105 weekly rolls on real marks). Across the whole window calls looked worth
// ~$40K — but that window fell 91.6 to 82.2, and the winning arms ended holding
// 25-28% of what they bought. They were not earning premium, they were selling
// shares into a decline. In the rally sub-period, where the answer is not
// contaminated by direction, calls cost $6,589 at 0.15 delta and $13,921 at the
// money, and gave away a third to 41% of the block. A smaller dose of a losing
// trade is still a losing trade, so the old 0.15 delta / 20% setting is gone
// rather than reduced.
const PHASE_CALLS: Record<string, { enabled: boolean; delta: number; coverage: number; why: string }> = {
  ACCUMULATE: { enabled: false, delta: 0, coverage: 0,
                why: 'off — measured to cost money and shares in a rally while the block is being built' },
  HOLD:       { enabled: true, delta: 0.25, coverage: 0.50, why: 'Income on a block that has stopped growing' },
  HARVEST:    { enabled: true, delta: 0.50, coverage: 1.00, why: 'Exit. Assignment is the point' },
};

// Mon/Wed/Fri each write a slice of the week. Friday's is smallest: it carries
// the weekend, and the weekend is when you cannot react.
const SLICE: Record<number, number> = { 1: 0.40, 3: 0.40, 5: 0.20 };

// ── the strike picker ───────────────────────────────────────────────────────
// Intrinsic value is not income. Selling the 82.5 put with TLT at 82.31 collects
// 19c of intrinsic and then hands it straight back at assignment: you buy a share
// worth 82.31 for 82.50. Only the extrinsic is earned.
//
// That matters here more than it would on an income book, because this one WANTS
// assignment. The case to optimise is therefore the ASSIGNED case, and in the
// assigned case the extra strike is pure cost. On Nik's own chain the 82.5 and
// the 82 were 2c apart on extrinsic and 29c apart on basis.
//
// So: rank by extrinsic, and when strikes are close on extrinsic take the LOWER
// one — same income, cheaper basis. An income seller would break the tie the
// other way; the objective differs, not the arithmetic. Nothing here is pinned to
// moneyness, which is the point: the answer moves with where spot sits in the
// grid that day.
const DELTA_FLOOR = 0.25;   // below this the test showed accumulation stalls in a rally
const DELTA_CEIL  = 0.70;   // above this the premium is mostly intrinsic, not earnings
const TIE_ABS = 0.03;       // "three cents less" — Nik's own threshold
const TIE_REL = 0.15;       // and scaled, so a 5-day expiry is not judged on 2-day ticks

// The 5,000-share call floor that stood here is gone — superseded, not relaxed.
// It existed to keep calls off while the block was small; the test then showed
// calls lose money in a rally at ANY size, so ACCUMULATE turns them off outright
// and the floor has nothing left to guard.

// ── Black-Scholes (single clock) ────────────────────────────────────────────
function ncdf(x: number): number {
  const a1 = .254829592, a2 = -.284496736, a3 = 1.421413741, a4 = -1.453152027, a5 = 1.061405429, p = .3275911;
  const s = x < 0 ? -1 : 1, z = Math.abs(x) / Math.SQRT2, t = 1 / (1 + p * z);
  const y = 1 - ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * Math.exp(-z * z);
  return .5 * (1 + s * y);
}
function d1of(S: number, K: number, T: number, v: number): number {
  return (Math.log(S / K) + (R_FREE + v * v / 2) * T) / (v * Math.sqrt(T));
}
/** |delta| of a put. Short put is +this much delta; long put is −this much. */
function putDeltaAbs(S: number, K: number, T: number, v: number): number {
  if (T <= 0 || v <= 0) return S < K ? 1 : 0;
  return ncdf(-d1of(S, K, T, v));
}
function callDelta(S: number, K: number, T: number, v: number): number {
  if (T <= 0 || v <= 0) return S > K ? 1 : 0;
  return ncdf(d1of(S, K, T, v));
}

// ── small numerics ──────────────────────────────────────────────────────────
const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
const fin = (x: number) => (Number.isFinite(x) ? x : 0);
const num = (x: unknown): number | null => {
  const n = Number(x);
  return Number.isFinite(n) ? n : null;
};
function mean(xs: number[]): number { return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0; }
function sd(xs: number[]): number {
  if (xs.length < 2) return 0;
  const m = mean(xs);
  return Math.sqrt(xs.reduce((a, b) => a + (b - m) * (b - m), 0) / (xs.length - 1));
}
/** Where v sits in xs, 0–1. The percentile is the point of `real`: a level means
 *  nothing without the history it is a level against. */
function pctRank(xs: number[], v: number): number {
  if (!xs.length) return 0.5;
  return xs.filter((x) => x <= v).length / xs.length;
}

// ── dates ───────────────────────────────────────────────────────────────────
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const DOWN = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
function ymd(d: Date): string {
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
}
function parseISO(s: string): Date { const [y, m, d] = String(s).slice(0, 10).split('-').map(Number); return new Date(Date.UTC(y, m - 1, d)); }
function addDays(d: Date, n: number): Date { const x = new Date(d.getTime()); x.setUTCDate(x.getUTCDate() + n); return x; }
function daysBetween(a: Date, b: Date): number { return Math.round((b.getTime() - a.getTime()) / 86400000); }
const fmtDay = (iso: string) => {
  const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number);
  return y && m && d ? `${MONTHS[m - 1]} ${d}` : String(iso);
};
const fmtUsd = (v: number) => {
  const sign = v < 0 ? '−' : '';
  const a = Math.abs(v);
  // Auction sizes are tens of billions. Without this branch supply reads "$67000M".
  if (a >= 1_000_000_000) return `${sign}$${(a / 1_000_000_000).toFixed(a >= 10_000_000_000 ? 0 : 1)}B`;
  if (a >= 1_000_000) return `${sign}$${(a / 1_000_000).toFixed(a >= 10_000_000 ? 0 : 1)}M`;
  if (a >= 1000) return `${sign}$${Math.round(a / 1000)}K`;
  return `${sign}$${Math.round(a)}`;
};
function quarterStart(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), Math.floor(d.getUTCMonth() / 3) * 3, 1));
}

// ── Supabase REST ───────────────────────────────────────────────────────────
type Row = Record<string, unknown>;
function db(url: string, key: string) {
  const h = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
  return {
    async get(path: string): Promise<Row[]> {
      try {
        const r = await fetch(`${url}/rest/v1/${path}`, { headers: h });
        if (!r.ok) return [];
        return (await r.json()) as Row[];
      } catch { return []; }
    },
    async upsert(table: string, rows: Row[], onConflict: string): Promise<void> {
      if (!rows.length) return;
      try {
        await fetch(`${url}/rest/v1/${table}?on_conflict=${onConflict}`, {
          method: 'POST',
          headers: { ...h, Prefer: 'resolution=merge-duplicates,return=minimal' },
          body: JSON.stringify(rows),
        });
      } catch { /* the cache is a convenience; a failed write must not fail a plan */ }
    },
  };
}

// ── FRED ────────────────────────────────────────────────────────────────────
type Obs = { date: string; value: number };
const SERIES = ['DFII30', 'DFII10', 'DGS30', 'DGS10', 'DGS2', 'FEDFUNDS', 'CPIAUCSL', 'T10YIE', 'SOFR'] as const;
type SeriesId = typeof SERIES[number];

async function fredSeries(id: string, key: string, startISO: string): Promise<Obs[]> {
  try {
    const r = await fetch(`${FRED}?series_id=${id}&api_key=${key}&file_type=json&observation_start=${startISO}`);
    if (!r.ok) return [];
    const j = await r.json() as { observations?: Array<{ date?: string; value?: string }> };
    const out: Obs[] = [];
    for (const o of j?.observations ?? []) {
      const v = num(o?.value);            // FRED writes '.' for a missing print
      if (v != null && o?.date) out.push({ date: o.date, value: v });
    }
    return out;
  } catch { return []; }
}

// ── Treasury: long end only. Bills and the front do not move TLT. ───────────
type Auction = {
  cusip: string; type: string; termYears: number; auctionDate: string;
  announcedOn: string | null; offering: number | null; btc: number | null;
  dealer: number | null; accepted: number | null; highYield: number | null;
};
function termYearsOf(original: string, term: string): number | null {
  const s = String(original || term || '');
  const m = s.match(/^(\d+)-Year/);
  if (!m) return null;
  const y = Number(m[1]);
  return y === 10 || y === 20 || y === 30 ? y : null;
}
async function treasuryLongEnd(fromISO: string): Promise<Auction[]> {
  const out: Auction[] = [];
  const fields = 'cusip,security_type,security_term,original_security_term,auction_date,announcemt_date,'
    + 'offering_amt,total_accepted,bid_to_cover_ratio,primary_dealer_accepted,high_yield';
  try {
    // The security_type filter is load-bearing, not an optimisation. Bills are
    // most of this dataset, so an unfiltered 400-row page reaches back about ten
    // months — and `typical` below would then be measured over a span far shorter
    // than it looks, making every upcoming calendar seem heavy. Filtered, 400 rows
    // comfortably covers two years.
    const url = `${FISCAL}?fields=${fields}`
      + `&filter=auction_date:gte:${fromISO},security_type:in:(Bond,Note)`
      + `&sort=-auction_date&page%5Bsize%5D=400`;
    const r = await fetch(url);
    if (!r.ok) return out;
    const j = await r.json() as { data?: Row[] };
    for (const d of j?.data ?? []) {
      const type = String(d.security_type ?? '');
      if (type !== 'Bond' && type !== 'Note') continue;
      const ty = termYearsOf(String(d.original_security_term ?? ''), String(d.security_term ?? ''));
      if (ty == null) continue;
      out.push({
        cusip: String(d.cusip ?? ''),
        type, termYears: ty,
        auctionDate: String(d.auction_date ?? '').slice(0, 10),
        announcedOn: d.announcemt_date ? String(d.announcemt_date).slice(0, 10) : null,
        offering: num(d.offering_amt), btc: num(d.bid_to_cover_ratio),
        dealer: num(d.primary_dealer_accepted), accepted: num(d.total_accepted),
        highYield: num(d.high_yield),
      });
    }
  } catch { /* supply drops out of the denominator */ }
  return out;
}

// ── Polygon ─────────────────────────────────────────────────────────────────
async function spotOf(key: string): Promise<number | null> {
  try {
    const r = await fetch(`${POLY}/v3/snapshot/options/${TICKER}?limit=1&apiKey=${key}`);
    if (!r.ok) return null;
    const j = await r.json() as { results?: Array<{ underlying_asset?: { price?: number } }> };
    return num((j?.results ?? [])[0]?.underlying_asset?.price);
  } catch { return null; }
}
async function putExpiries(fromISO: string, key: string): Promise<string[]> {
  try {
    const r = await fetch(`${POLY}/v3/reference/options/contracts?underlying_ticker=${TICKER}&contract_type=put`
      + `&expiration_date.gte=${fromISO}&expired=false&limit=1000&sort=expiration_date&order=asc&apiKey=${key}`);
    if (!r.ok) return [];
    const j = await r.json() as { results?: Array<{ expiration_date?: string }> };
    const set: string[] = [];
    for (const c of j?.results ?? []) if (c.expiration_date && !set.includes(c.expiration_date)) set.push(c.expiration_date);
    return set;
  } catch { return []; }
}
type Quote = { strike: number; bid: number; ask: number; mid: number; delta: number | null; oi: number };
async function chain(kind: 'put' | 'call', expiry: string, lo: number, hi: number, key: string): Promise<Quote[]> {
  const out: Quote[] = [];
  try {
    const r = await fetch(`${POLY}/v3/snapshot/options/${TICKER}?expiration_date=${expiry}`
      + `&contract_type=${kind}&strike_price.gte=${lo}&strike_price.lte=${hi}&limit=120&apiKey=${key}`);
    if (!r.ok) return out;
    const j = await r.json() as { results?: Array<Record<string, Record<string, number>>> };
    for (const row of j?.results ?? []) {
      const k = num(row?.details?.strike_price);
      if (k == null) continue;
      const bid = fin(Number(row?.last_quote?.bid ?? 0)), ask = fin(Number(row?.last_quote?.ask ?? 0));
      const dl = num(row?.greeks?.delta);
      out.push({
        strike: k, bid, ask,
        mid: bid > 0 && ask > 0 ? (bid + ask) / 2 : 0,
        delta: dl, oi: fin(Number(row?.open_interest ?? 0)),
      });
    }
  } catch { /* the model prices it and the pick says so */ }
  return out.sort((a, b) => a.strike - b.strike);
}
/** Trailing-twelve-month distribution yield. `carry` is the whole reason this is
 *  fetched: what it costs to be early is the question a 100-week accumulation
 *  actually turns on. */
async function ttmYield(key: string, spot: number): Promise<number | null> {
  try {
    const r = await fetch(`${POLY}/v3/reference/dividends?ticker=${TICKER}&limit=16&apiKey=${key}`);
    if (!r.ok) return null;
    const j = await r.json() as { results?: Array<{ cash_amount?: number; ex_dividend_date?: string }> };
    const rows = (j?.results ?? []).filter((x) => num(x.cash_amount) != null).slice(0, 12);
    if (rows.length < 6) return null;
    const sum = rows.reduce((a, b) => a + Number(b.cash_amount), 0);
    return spot > 0 ? (sum / spot) * 100 : null;
  } catch { return null; }
}

// ── families ────────────────────────────────────────────────────────────────
type Family = { key: string; label: string; cap: number; score: number; pct: number | null; note: string; ok: boolean };
const fam = (key: string, label: string, cap: number, pct: number | null, note: string): Family =>
  pct == null
    ? { key, label, cap, score: 0, pct: null, note, ok: false }
    : { key, label, cap, score: Math.round(cap * clamp(pct, 0, 1) * 10) / 10, pct: clamp(pct, 0, 1), note, ok: true };

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const polyKey = Deno.env.get('POLYGON_API_KEY');
  const fredKey = Deno.env.get('FRED_API_KEY');
  const supaUrl = Deno.env.get('SUPABASE_URL');
  const supaKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!polyKey) return json(500, { ok: false, error: 'POLYGON_API_KEY not set' });
  if (!supaUrl || !supaKey) return json(500, { ok: false, error: 'SUPABASE_URL / SERVICE_ROLE_KEY not set' });

  let body: { dry_run?: boolean; phase?: string; asof?: string } = {};
  try { if (req.method === 'POST') body = await req.json(); } catch { /* no body is the normal case */ }

  const D = db(supaUrl, supaKey);
  // Normalised to UTC midnight. `new Date()` carries a time, every parsed date is
  // midnight, and daysBetween rounds the difference — so an event dated today read
  // as "−1d out" once the clock passed noon UTC. Option T and weeksElapsed had the
  // same skew.
  const today = parseISO(body.asof ?? ymd(new Date()));
  const todayISO = ymd(today);
  const fiveYrAgo = ymd(addDays(today, -5 * 365));

  // ── state, book, and every network call that does not depend on spot ──────
  const [stateRows, blocRows, blocMetaRows, eventRows, tradeRows, lotRows, ivRows, spotLive, auctions] =
    await Promise.all([
      D.get('tlt_planner_state?id=eq.1&select=*'),
      D.get('tlt_voter_bloc?select=code,name,lean,chair&order=sort.asc'),
      D.get('tlt_bloc_meta?id=eq.1&select=*'),
      D.get(`tlt_macro_events?event_date=gte.${todayISO}&select=class_key,class_name,event_date,label,tag&order=event_date.asc&limit=12`),
      // trade_date and premium carry the per-leg assignment basis. Without them the
      // Tonight card has no honest number: the ladder's basis belongs to a trade you
      // would open TODAY at today's premium, not to a leg sold a week ago.
      D.get('tlt_option_trades?voided_at=is.null&select=id,action,option_type,direction,contracts,strike,premium,expiry,closes_trade_id,trade_date,last_synced_at'),
      D.get('tlt_share_lots?voided_at=is.null&select=acquired_date,qty_remaining'),
      D.get('tlt_iv_daily?select=*&order=date.desc&limit=1'),
      spotOf(polyKey),
      treasuryLongEnd(ymd(addDays(today, -730))),
    ]);

  const st = (stateRows[0] ?? {}) as Row;
  const phase = String(body.phase ?? st.phase ?? 'ACCUMULATE').toUpperCase();
  if (!PHASE_CALLS[phase]) return json(400, { ok: false, error: `unknown phase ${phase}` });
  const targetShares = Number(st.target_shares ?? 100000);
  const quarterBudget = Number(st.quarter_budget ?? 11000);
  const cashCeiling = Number(st.cash_ceiling ?? 400000);
  const horizonLo = Number(st.horizon_lo_wk ?? 100);
  const horizonHi = Number(st.horizon_hi_wk ?? 120);
  const startedOn = String(st.started_on ?? '2026-08-10');
  // 0.50, not the 0.45 first drafted. ATM won the full window, was never worst in
  // any sub-period, and — the reason that actually decides it — kept accumulating
  // through the rally where OTM stalled: 7,800 shares against OTM's 5,100. An OTM
  // put stops delivering exactly when TLT runs away from you.
  const putDeltaTgt = Number(st.put_delta_tgt ?? 0.50);

  // spot: Polygon first, tlt_quote as the fallback
  let spot = spotLive;
  if (spot == null) {
    const q = await D.get(`tlt_quote?ticker=eq.${TICKER}&select=spot`);
    spot = num(q[0]?.spot);
  }
  if (spot == null || spot <= 0) return json(502, { ok: false, error: 'no TLT spot from Polygon or tlt_quote' });

  const iv = num(ivRows[0]?.iv) ?? num(ivRows[0]?.iv_30d) ?? IV_FALLBACK;

  // ── FRED, in parallel, with the cache as fallback ─────────────────────────
  const fredOut: Partial<Record<SeriesId, Obs[]>> = {};
  const fredMissing: string[] = [];
  if (fredKey) {
    const got = await Promise.all(SERIES.map((s) => fredSeries(s, fredKey, fiveYrAgo)));
    SERIES.forEach((s, i) => { fredOut[s] = got[i]; });
  }
  for (const s of SERIES) {
    if (!fredOut[s]?.length) {
      const cached = await D.get(`rates_daily?series=eq.${s}&select=date,value&order=date.asc&limit=1400`);
      const obs = cached.map((r) => ({ date: String(r.date), value: Number(r.value) })).filter((o) => Number.isFinite(o.value));
      if (obs.length) fredOut[s] = obs; else fredMissing.push(s);
    }
  }
  const last = (s: SeriesId): number | null => { const a = fredOut[s]; return a?.length ? a[a.length - 1].value : null; };
  const back = (s: SeriesId, n: number): number | null => { const a = fredOut[s]; return a && a.length > n ? a[a.length - 1 - n].value : null; };
  const vals = (s: SeriesId): number[] => (fredOut[s] ?? []).map((o) => o.value);

  // keep the cache warm — last 30 observations per series, cheap and idempotent
  if (!body.dry_run) {
    for (const s of SERIES) {
      const a = fredOut[s];
      if (a?.length) await D.upsert('rates_daily', a.slice(-30).map((o) => ({ series: s, date: o.date, value: o.value })), 'series,date');
    }
    await D.upsert('tlt_auctions', auctions.filter((a) => a.cusip).map((a) => ({
      cusip: a.cusip, security_type: a.type, term_years: a.termYears, auction_date: a.auctionDate,
      announced_on: a.announcedOn, offering_amt: a.offering, total_accepted: a.accepted,
      bid_to_cover: a.btc, dealer_accepted: a.dealer, high_yield: a.highYield,
    })), 'cusip');
  }

  // ── the nine ─────────────────────────────────────────────────────────────
  const F: Family[] = [];

  // real — the best cheapness read there is, and better than price, because price
  // conflates the real rate with inflation expectations.
  {
    const v = last('DFII30'), hist = vals('DFII30');
    F.push(fam('real', 'Real yield', CAPS.real,
      v == null || hist.length < 60 ? null : pctRank(hist, v),
      v == null ? 'no DFII30' : `30y real ${v.toFixed(2)}% · ${Math.round(pctRank(hist, v) * 100)}th pct of 5y`));
  }

  // curve — steepening is not one thing. Decompose it or you score a bear
  // steepener, which is TLT bleeding, as if it were the pre-cut rally.
  {
    const l30 = last('DGS30'), b30 = back('DGS30', 20), l2 = last('DGS2'), b2 = back('DGS2', 20);
    if (l30 == null || b30 == null || l2 == null || b2 == null) {
      F.push(fam('curve', 'Curve', CAPS.curve, null, 'no DGS30/DGS2'));
    } else {
      const d30 = l30 - b30, d2 = l2 - b2;
      const longLeg = clamp((-d30 / 0.30 + 1) / 2, 0, 1);   // 30y yield falling 30bp over 20d = 1
      const lead = d2 < d30 ? 1 : d2 > d30 ? 0 : 0.5;       // front-led = bull steepener
      const shape = d30 - d2 > 0.02 ? (d30 > 0 ? 'bear steepener' : 'steepening, long-led')
        : d2 - d30 > 0.02 ? (d2 < 0 ? 'bull steepener' : 'flattening, front-led')
        : 'parallel';
      F.push(fam('curve', 'Curve', CAPS.curve, 0.6 * longLeg + 0.4 * lead,
        `${shape} · 30y ${d30 >= 0 ? '+' : '−'}${Math.abs(d30 * 100).toFixed(0)}bp, 2y ${d2 >= 0 ? '+' : '−'}${Math.abs(d2 * 100).toFixed(0)}bp over 20d`));
    }
  }

  // path — deliberately contrarian. Cuts already priced means the good news is
  // in the bond and you are buying after the move. Expect this to read weakest
  // exactly when the rate-cut story is loudest.
  {
    const l2 = last('DGS2'), ff = last('FEDFUNDS');
    const gap = l2 != null && ff != null ? l2 - ff : null;
    F.push(fam('path', 'Priced path', CAPS.path,
      gap == null ? null : clamp((gap + 2.0) / 2.5, 0, 1),
      gap == null ? 'no DGS2/FEDFUNDS'
        : `2y ${gap >= 0 ? '+' : '−'}${Math.abs(gap).toFixed(2)}% vs funds · ${gap < -1 ? 'cuts largely priced' : gap < -0.4 ? 'some cuts priced' : 'little priced'}`));
  }

  // print — CPI against what the market has priced, not against a survey. There
  // is no free consensus feed, and breakevens are the expectation you actually
  // trade against.
  {
    const cpi = fredOut.CPIAUCSL ?? [], be = last('T10YIE');
    let yoy: number | null = null;
    if (cpi.length > 12) {
      const nowV = cpi[cpi.length - 1].value, yrV = cpi[cpi.length - 13].value;
      if (yrV > 0) yoy = (nowV / yrV - 1) * 100;
    }
    const gap = yoy != null && be != null ? be - yoy : null;   // + = cooling faster than priced
    // Scale is ±1.5, not the ±1.0 first drafted: the live gap was −1.43, which
    // pinned the family at exactly 0 and lost the difference between hot and
    // very hot. A family that saturates stops carrying information.
    F.push(fam('print', 'Inflation vs priced', CAPS.print,
      gap == null ? null : clamp((gap + 1.5) / 3.0, 0, 1),
      gap == null ? 'no CPIAUCSL/T10YIE'
        : `CPI ${yoy!.toFixed(1)}% vs ${be!.toFixed(2)}% breakeven · ${gap > 0 ? 'cooler than priced' : 'hotter than priced'}`));
  }

  // stretch — deviation, never level. Level is the price multiplier's job, and
  // if both measured cheapness they would compound.
  {
    const hist = vals('DGS30'), v = last('DGS30');
    const win = hist.slice(-100);
    const z = v != null && win.length >= 40 && sd(win) > 0 ? (v - mean(win)) / sd(win) : null;
    F.push(fam('stretch', 'Stretch', CAPS.stretch,
      z == null ? null : clamp((z + 2) / 4, 0, 1),
      z == null ? 'no DGS30 history' : `30y yield ${z >= 0 ? '+' : '−'}${Math.abs(z).toFixed(1)}σ vs 100d mean`));
  }

  // carry — what it costs to be early, which is the question a 100-week
  // accumulation actually turns on.
  {
    const y = await ttmYield(polyKey, spot);
    const cash = last('SOFR');
    const c = y != null && cash != null ? y - cash : null;
    F.push(fam('carry', 'Carry', CAPS.carry,
      c == null ? null : clamp((c + 1.5) / 3.0, 0, 1),
      c == null ? 'no dividends/SOFR'
        : `TLT ${y!.toFixed(2)}% vs cash ${cash!.toFixed(2)}% · ${c >= 0 ? 'paid to wait' : 'paying to wait'}`));
  }

  // supply — do not step in front of the long-end calendar. Bills are ignored;
  // they do not move TLT.
  {
    const upcoming = auctions.filter((a) => a.auctionDate >= todayISO && a.auctionDate <= ymd(addDays(today, 35)));
    const past = auctions.filter((a) => a.auctionDate < todayISO);
    const upSize = upcoming.reduce((s, a) => s + (a.offering ?? 0), 0);
    // A typical 35-day window, measured over the span the data ACTUALLY covers.
    // Assuming two years and getting ten months would inflate every ratio here.
    const oldest = past.reduce((m, a) => (a.auctionDate < m ? a.auctionDate : m), past[0]?.auctionDate ?? todayISO);
    const spanDays = Math.max(60, daysBetween(parseISO(oldest), today));
    const typical = past.length ? (past.reduce((s, a) => s + (a.offering ?? 0), 0) / spanDays) * 35 : 0;
    const btcs = past.filter((a) => a.btc != null).slice(0, 12).map((a) => a.btc as number);
    const lastBtc = btcs[0] ?? null;
    if (!past.length || typical <= 0) {
      F.push(fam('supply', 'Supply', CAPS.supply, null, 'Treasury unavailable'));
    } else {
      const r = upSize / typical;
      const sizeScore = clamp(1.5 - r, 0, 1);
      const btcScore = lastBtc != null && btcs.length >= 4 && sd(btcs) > 0
        ? clamp(((lastBtc - mean(btcs)) / sd(btcs) + 2) / 4, 0, 1) : 0.5;
      F.push(fam('supply', 'Supply', CAPS.supply, 0.6 * sizeScore + 0.4 * btcScore,
        `${fmtUsd(upSize)} long-end in 35d (${r.toFixed(2)}× typical)${lastBtc != null ? ` · last b/c ${lastBtc.toFixed(2)}` : ''}`));
    }
  }

  // bloc — small on purpose: slow, soft, and the only family with no feed.
  // SIGN ASSUMPTION: lean > 0 is read as HAWKISH (the seed has Hammack and Logan
  // at +2, and both are hawks). Hawkish is bad for TLT, so a hawkish committee
  // scores low. If the convention is the other way round, flip this one line.
  {
    const leans = blocRows.map((r) => num(r.lean)).filter((x): x is number => x != null);
    const m = leans.length ? mean(leans) : null;
    F.push(fam('bloc', 'Committee', CAPS.bloc,
      m == null ? null : clamp((2 - m) / 4, 0, 1),
      m == null ? 'no voter bloc rows'
        : `${leans.length} seats · mean lean ${m >= 0 ? '+' : '−'}${Math.abs(m).toFixed(1)} · ${m > 0.5 ? 'hawkish' : m < -0.5 ? 'dovish' : 'split'}`));
  }

  // ── conviction: normalise over the families that actually answered ────────
  const positives = F.filter((f) => f.ok);
  const capSum = positives.reduce((s, f) => s + f.cap, 0);
  const rawSum = positives.reduce((s, f) => s + f.score, 0);
  const base = capSum > 0 ? (rawSum / capSum) * 100 : 50;

  // calendar — a damper, never an addition. This is what thrice-weekly buys:
  // "write half now, the rest Friday after CPI" is a sentence a weekly cadence
  // cannot produce.
  const HEAVY = new Set(['fomc', 'prints', 'refunding', 'auctions']);
  const nextHeavy = (eventRows as Row[]).find((e) => HEAVY.has(String(e.class_key ?? '')));
  let calPenalty = 0, calNote = 'clear for a week';
  if (nextHeavy) {
    const dd = daysBetween(today, parseISO(String(nextHeavy.event_date)));
    calPenalty = dd <= 2 ? CAPS.calendar : dd <= 4 ? CAPS.calendar / 2 : dd <= 7 ? CAPS.calendar / 4 : 0;
    calNote = `${nextHeavy.class_name} ${fmtDay(String(nextHeavy.event_date))}${dd <= 7 ? ` · ${dd}d out` : ''}`;
  }
  F.push({ key: 'calendar', label: 'Calendar', cap: CAPS.calendar, score: Math.round(calPenalty * 10) / 10, pct: null, note: calNote, ok: true });

  const conviction = Math.round(clamp(base + calPenalty, 0, 100));

  // ── the book ─────────────────────────────────────────────────────────────
  const closedIds = new Set((tradeRows as Row[]).map((t) => String(t.closes_trade_id ?? '')).filter(Boolean));
  const open = (tradeRows as Row[]).filter((t) =>
    String(t.action) === 'open' && !closedIds.has(String(t.id)) && String(t.expiry).slice(0, 10) >= todayISO);

  const shares = (lotRows as Row[]).reduce((s, l) => s + fin(Number(l.qty_remaining)), 0);
  const qStart = quarterStart(today);
  const sharesThisQuarter = (lotRows as Row[])
    .filter((l) => String(l.acquired_date).slice(0, 10) >= ymd(qStart))
    .reduce((s, l) => s + fin(Number(l.qty_remaining)), 0);

  type Leg = {
    type: string; dir: string; ct: number; strike: number; expiry: string;
    delta: number; shares: number; premium: number; soldOn: string; basis: number; fills: number;
  };
  // Fills are not positions. IBKR delivers a 4-lot as separate rows, so the book
  // read "1× short put 82" and "3× short put 82" as two lines for one position.
  // Aggregate by contract identity, weighting premium by size so the basis stays
  // honest when the fills went off at different prices.
  type Agg = { row: Row; ct: number; premWeighted: number; soldOn: string; fills: number };
  const byContract = new Map<string, Agg>();
  for (const t of open) {
    const key = `${t.option_type}|${t.direction}|${t.strike}|${String(t.expiry).slice(0, 10)}`;
    const ct = fin(Number(t.contracts));
    const prem = fin(Number(t.premium));
    const soldOn = String(t.trade_date ?? '').slice(0, 10);
    const prev = byContract.get(key);
    if (prev) {
      prev.ct += ct;
      prev.premWeighted += prem * ct;
      prev.fills += 1;
      if (soldOn && (!prev.soldOn || soldOn < prev.soldOn)) prev.soldOn = soldOn;
    } else {
      byContract.set(key, { row: t, ct, premWeighted: prem * ct, soldOn, fills: 1 });
    }
  }

  const legs: Leg[] = [...byContract.values()].map((a) => {
    const t = a.row;
    const ct = a.ct;
    const K = fin(Number(t.strike));
    const T = Math.max(daysBetween(today, parseISO(String(t.expiry))), 0) / 365;
    const isPut = String(t.option_type) === 'put';
    const short = String(t.direction) === 'short';
    const mag = isPut ? putDeltaAbs(spot!, K, T, iv) : callDelta(spot!, K, T, iv);
    // short put = +delta · short call = −delta · long put (the floor) = −delta
    const signed = isPut ? (short ? mag : -mag) : (short ? -mag : mag);
    const prem = ct > 0 ? a.premWeighted / ct : 0;
    return {
      type: String(t.option_type), dir: String(t.direction), ct, strike: K,
      expiry: String(t.expiry).slice(0, 10), delta: signed, shares: signed * ct * 100,
      premium: Math.round(prem * 1000) / 1000, soldOn: a.soldOn, fills: a.fills,
      // What this position actually costs if it delivers: the strike it commits to,
      // less the size-weighted premium it was sold at. Never today's candidate.
      basis: Math.round((K - prem) * 100) / 100,
    };
  }).sort((a, b) => a.expiry.localeCompare(b.expiry) || a.strike - b.strike);

  const shortPuts = legs.filter((l) => l.type === 'put' && l.dir === 'short');
  const longPuts = legs.filter((l) => l.type === 'put' && l.dir === 'long');
  const shortCalls = legs.filter((l) => l.type === 'call' && l.dir === 'short');
  const optDelta = legs.reduce((s, l) => s + l.shares, 0);
  const netDelta = shares + optDelta;

  // ── what today already did ───────────────────────────────────────────────
  // The slice is a budget for the DAY, so the recommendation has to be what is
  // LEFT of it, not what it was worth this morning. Computed from the raw fills
  // rather than the aggregated legs, because aggregation keeps only the earliest
  // fill date and would miss a position topped up today at a strike opened
  // earlier.
  const writtenToday = (open as Row[])
    .filter((t) => String(t.option_type) === 'put' && String(t.direction) === 'short'
      && String(t.trade_date ?? '').slice(0, 10) === todayISO)
    .reduce((sum, t) => {
      const ct = fin(Number(t.contracts));
      const K = fin(Number(t.strike));
      const T = Math.max(daysBetween(today, parseISO(String(t.expiry))), 0) / 365;
      return sum + putDeltaAbs(spot!, K, T, iv) * ct * 100;
    }, 0);
  const contractsToday = (open as Row[])
    .filter((t) => String(t.option_type) === 'put' && String(t.direction) === 'short'
      && String(t.trade_date ?? '').slice(0, 10) === todayISO)
    .reduce((n, t) => n + fin(Number(t.contracts)), 0);

  // A short put is a commitment to buy, never income. Every unexpired one counts,
  // not just this week's.
  const outstanding = shortPuts.reduce((s, l) => s + l.strike * 100 * l.ct, 0);
  const pendingShares = shortPuts.reduce((s, l) => s + l.ct * 100, 0);
  const fullyAssigned = shares + pendingShares;
  const floorCoverage = fullyAssigned > 0 ? (longPuts.reduce((s, l) => s + l.ct * 100, 0) / fullyAssigned) : 0;

  // ── what the next expiry actually does ───────────────────────────────────
  // Listing the legs is not the same as saying what tonight does to the share
  // count, and the second is the one worth acting on. A book that shows "4x
  // short put 82.5, expiring today" is making the reader do the moneyness
  // comparison themselves — and that comparison is the whole event.
  const openExps = legs.map((l) => l.expiry).sort();
  const nearestExp = openExps[0] ?? null;
  const expiringLegs = nearestExp ? legs.filter((l) => l.expiry === nearestExp) : [];
  let arriving = 0, leaving = 0, basisWeighted = 0;
  const expiringDetail = expiringLegs.map((l) => {
    const itm = l.type === 'put' ? spot! < l.strike : spot! > l.strike;
    if (itm && l.dir === 'short') {
      if (l.type === 'put') { arriving += l.ct * 100; basisWeighted += l.basis * l.ct * 100; }
      else leaving += Math.min(shares, l.ct * 100);
    }
    const away = Math.round(Math.abs(l.strike - spot!) * 100) / 100;
    return {
      type: l.type, dir: l.dir, ct: l.ct, strike: l.strike, itm,
      moves: itm && l.dir === 'short' ? l.ct * 100 : 0,
      premium: l.premium, soldOn: l.soldOn, basis: l.basis,
      // Per leg, from the premium THAT leg was sold at.
      say: l.dir !== 'short'
        ? `${l.ct}× ${l.strike} ${l.type} · the floor, ${fmtDay(l.expiry)}`
        : itm
          ? `${l.ct}× ${l.strike} ${l.type} · sold *${l.premium.toFixed(2)}*`
            + `${l.soldOn ? ` ${fmtDay(l.soldOn)}` : ''} · basis *${l.basis.toFixed(2)}*`
          : `${l.ct}× ${l.strike} ${l.type} · ~${away.toFixed(2)} OTM, expires~`,
    };
  });
  // Conditional, always. With hours of trading left assignment can flip, so the
  // engine says "in the money now" and "likely" — never "assigns today".
  const expWhen = nearestExp === todayISO ? 'likely tomorrow' : `likely after ${fmtDay(nearestExp ?? todayISO)}`;
  const itmShorts = expiringDetail.filter((e) => e.itm && e.dir === 'short');
  const otmShorts = expiringDetail.filter((e) => !e.itm && e.dir === 'short');
  const avgBasis = arriving > 0 ? Math.round((basisWeighted / arriving) * 100) / 100 : 0;
  const strikeSet = (xs: typeof expiringDetail) =>
    [...new Set(xs.map((e) => String(e.strike)))].join(' and ');
  const expirySay = !nearestExp ? 'Nothing expiring'
    : arriving > 0
      ? `${strikeSet(itmShorts.filter((e) => e.type === 'put'))}s *in the money*.`
        + ` ^${arriving.toLocaleString()} shares^ likely`
      : leaving > 0
        ? `${strikeSet(itmShorts.filter((e) => e.type === 'call'))}s *in the money*.`
          + ` ^${leaving.toLocaleString()} shares^ called`
        : 'Nothing in the money. All expire worthless';

  // ── sizing ───────────────────────────────────────────────────────────────
  const band = PRICE_BANDS.find(([hi]) => spot! < hi) ?? PRICE_BANDS[0];
  const priceFactor = band[1], priceBand = band[2];
  const cf = convFactor(conviction);
  const weeklyDelta = (quarterBudget / 13) * priceFactor * cf.f;

  const dow = today.getUTCDay();
  const decisionDow = SLICE[dow] != null ? dow : (dow === 0 || dow === 6 ? 1 : dow < 3 ? 3 : dow < 5 ? 5 : 1);
  const sliceW = SLICE[decisionDow];
  const sliceDelta = weeklyDelta * sliceW;
  const sliceLeft = Math.max(0, sliceDelta - writtenToday);
  const sliceFilled = writtenToday > 0 && sliceLeft < sliceDelta * 0.15;
  const isDecisionDay = SLICE[dow] != null;

  // Emitted, not hand-written on the card. A design draft said "write the
  // Wednesday 40%, the rest Friday" — but Friday is 20%, not the rest, and copy
  // that restates the mechanism from memory drifts away from it.
  const laterDows = [1, 3, 5].filter((x) => x > decisionDow);
  const sliceSay = laterDows.length
    ? `*${Math.round(sliceW * 100)}%* now · `
      + laterDows.map((x) => `*${Math.round(SLICE[x] * 100)}%* ${DOWN[x]}`).join(' · ')
    : `*${Math.round(sliceW * 100)}%* now, last of the week`;

  const expiries = await putExpiries(ymd(addDays(today, 2)), polyKey);
  const expiry = expiries[0] ?? null;
  let putQuotes: Quote[] = [];
  if (expiry) putQuotes = await chain('put', expiry, Math.floor(spot * 0.92), Math.ceil(spot * 1.04), polyKey);

  const Tput = expiry ? Math.max(daysBetween(today, parseISO(expiry)), 0) / 365 : 0;
  const cands = putQuotes.map((q) => {
    const intrinsic = Math.max(0, q.strike - spot!);
    return {
      ...q,
      dAbs: q.delta != null ? Math.abs(q.delta) : putDeltaAbs(spot!, q.strike, Tput, iv),
      modelled: q.delta == null,
      intrinsic,
      // A strike with no bid is quoted but not tradeable, so its "mid" is not a
      // price anyone will pay and it must not win on a phantom extrinsic.
      extrinsic: q.mid > 0 ? Math.max(0, q.mid - intrinsic) : 0,
      tradeable: q.mid > 0,
    };
  });

  const putBand = cands.filter((c) => c.tradeable && c.extrinsic > 0 && c.dAbs >= DELTA_FLOOR && c.dAbs <= DELTA_CEIL);
  let pick: typeof cands[number] | null = null;
  let pickBy = 'none';
  if (putBand.length) {
    const best = Math.max(...putBand.map((c) => c.extrinsic));
    const tie = Math.max(TIE_ABS, TIE_REL * best);
    // lowest strike among those within a tie of the best extrinsic
    pick = putBand.filter((c) => c.extrinsic >= best - tie).reduce((a, b) => (a.strike <= b.strike ? a : b));
    pickBy = 'extrinsic';
  } else if (cands.length) {
    // Nothing tradeable in the band — fall back to the old delta target so the
    // planner still answers, and say which rule produced the answer.
    pick = cands.reduce((a, b) => (Math.abs(a.dAbs - putDeltaTgt) <= Math.abs(b.dAbs - putDeltaTgt) ? a : b));
    pickBy = 'delta-fallback';
  }

  const putStrike = pick?.strike ?? Math.round((spot * 0.99) / STRIKE_STEP) * STRIKE_STEP;
  const putDelta = pick?.dAbs ?? putDeltaTgt;
  const putMid = pick?.mid ?? 0;
  const putIntrinsic = pick?.intrinsic ?? 0;
  const putExtrinsic = pick?.extrinsic ?? 0;

  const wantCt = putDelta > 0 ? Math.max(0, Math.round(sliceLeft / (putDelta * 100))) : 0;
  const headroom = Math.max(0, cashCeiling - outstanding);
  const maxCt = Math.floor(headroom / (putStrike * 100));
  const putCt = Math.min(wantCt, maxCt);
  const ceilingBinds = putCt < wantCt;

  // ── the call side, per phase, against DELIVERED shares only ──────────────
  // Pending assignment is not coverage. Write calls against shares that have not
  // arrived and a rally leaves them naked: the puts expire worthless, the shares
  // never come, and the calls are uncovered into strength.
  const cs = PHASE_CALLS[phase];
  const coveredNow = shortCalls.reduce((s, l) => s + l.ct * 100, 0);
  const coverRoom = Math.max(0, Math.floor((shares * cs.coverage - coveredNow) / 100));
  // In ACCUMULATE calls are the LAST lever — the first move is to write fewer
  // puts. They only appear once the put side is at its floor and delta is still
  // over, which in practice means after a run of assignments.
  const deltaTarget = shares + sliceDelta;
  const deltaOver = netDelta - deltaTarget;
  const callsWarranted = !cs.enabled ? 0
    : Math.min(coverRoom, Math.max(0, Math.floor((deltaOver > 0 ? deltaOver : shares * cs.coverage) / (cs.delta * 100))));

  let callStrike: number | null = null, callMid = 0;
  if (callsWarranted > 0 && expiry) {
    const cq = await chain('call', expiry, Math.floor(spot * 0.98), Math.ceil(spot * 1.12), polyKey);
    const Tc = Math.max(daysBetween(today, parseISO(expiry)), 0) / 365;
    const withD = cq.map((q) => ({ ...q, dAbs: q.delta != null ? Math.abs(q.delta) : callDelta(spot!, q.strike, Tc, iv) }));
    const cp = withD.length ? withD.reduce((a, b) => Math.abs(a.dAbs - cs.delta) <= Math.abs(b.dAbs - cs.delta) ? a : b) : null;
    callStrike = cp?.strike ?? null;
    callMid = cp?.mid ?? 0;
  }

  // ── horizon band ─────────────────────────────────────────────────────────
  const weeksElapsed = Math.max(0, Math.floor(daysBetween(parseISO(startedOn), today) / 7));
  const remaining = Math.max(0, targetShares - shares);
  const weeksAtBudget = quarterBudget > 0 ? remaining / (quarterBudget / 13) : Infinity;
  const projectedTotal = Math.round(weeksElapsed + weeksAtBudget);
  const standing = projectedTotal < horizonLo ? 'early' : projectedTotal <= horizonHi ? 'on plan' : 'behind';

  // ── the trail ────────────────────────────────────────────────────────────
  const sizing = {
    weeklyDelta: Math.round(weeklyDelta), sliceDelta: Math.round(sliceDelta),
    priceFactor, priceBand, convFactor: cf.f, convBand: cf.band,
    contracts: putCt, wanted: wantCt, ceilingBinds,
    writtenToday: Math.round(writtenToday), contractsToday, sliceLeft: Math.round(sliceLeft), sliceFilled,
  };
  if (!body.dry_run) {
    await D.upsert('tlt_planner_factor_daily', [{
      taken_on: todayISO, phase, spot, conviction, families: F, sizing,
    }], 'taken_on');
  }

  // ── the sheet ────────────────────────────────────────────────────────────
  // Every string the screen renders, assembled here. The view formats nothing,
  // rounds nothing and writes no sentences — it maps fields to type.
  //
  // This is not tidiness. Copy that restates the mechanism from memory drifts
  // away from it, and did twice in one day: a card printed an assignment basis
  // borrowed from a candidate trade, and another said "the rest Friday" when
  // Friday is 20%. Both were correct-looking and wrong. Emphasis travels inside
  // the strings as *bold* ~thin~ ^thick^ _underline_ for the client's parser.
  const nowTs = new Date();
  const usd0 = (v: number) => `$${Math.round(v).toLocaleString('en-US')}`;
  const cents = (v: number) => `${Math.round(v * 100)}¢`;
  const ageOf = (iso: string | null | undefined): string => {
    if (!iso) return 'unknown';
    const t = Date.parse(String(iso));
    if (!Number.isFinite(t)) return 'unknown';
    const s = Math.max(0, Math.round((nowTs.getTime() - t) / 1000));
    if (s < 90) return `${s}s ago`;
    if (s < 5400) return `${Math.round(s / 60)}m ago`;
    if (s < 172800) return `${Math.round(s / 3600)}h ago`;
    return `${Math.round(s / 86400)}d ago`;
  };
  const dayLabel = `${DOWN[parseISO(todayISO).getUTCDay()]} ${parseISO(todayISO).getUTCDate()} `
    + MONTHS[parseISO(todayISO).getUTCMonth()];

  const famPositives = F.filter((f) => f.key !== 'calendar');
  const topThree = [...famPositives].filter((f) => f.ok).sort((a, b) => b.score - a.score).slice(0, 3).map((f) => f.key);
  const lastFred = (fredOut.DGS30 ?? []).slice(-1)[0]?.date ?? null;
  const lastSync = (tradeRows as Row[]).map((t) => String(t.last_synced_at ?? '')).filter(Boolean).sort().pop() ?? null;

  const sheet = {
    ticker: TICKER,
    asOf: { label: dayLabel, refresh: `${spot.toFixed(2)} \u00b7 ${phase}` },
    phase: `${phase.charAt(0)}${phase.slice(1).toLowerCase()} phase`,

    instruction: {
      label: 'The instruction',
      verb: putCt > 0 ? `Sell ${putCt} put${putCt === 1 ? '' : 's'} at ${putStrike}`
        : sliceFilled ? "Today's slice is filled" : 'Nothing this slice',
      meta: putCt === 0 && sliceFilled
        ? `${contractsToday} written today \u00b7 ${Math.round(writtenToday)} of ${Math.round(sliceDelta)} delta`
        : `${expiry ? `${DOWN[parseISO(expiry).getUTCDay()].slice(0, 3)} ${fmtDay(expiry)}` : 'no expiry'}`
          + ` \u00b7 ${putDelta.toFixed(2)} delta \u00b7 ${pick?.modelled ? 'modelled' : 'real quotes'}`,
      commit: [[usd0(putStrike * 100 * putCt), 'committed'], [String(putCt * 100), 'shares if assigned']],
      basis: { value: (putStrike - putMid).toFixed(2), label: 'basis if assigned' },
      // One figure, one label. The old three-line earn column made a subordinate
      // number look like a third tier of its own.
      earn: {
        value: cents(putExtrinsic),
        label: putIntrinsic <= 0.005 ? 'no intrinsic' : `${cents(putIntrinsic)} intrinsic`,
      },
      mark: putIntrinsic <= 0.005 ? 'all extrinsic' : null,
    },

    ladder: (() => {
      // The ladder EXPLAINS the pick, so it must always show what the pick beat.
      // Built from tradeable strikes WITHOUT the delta band: the band decides which
      // strike is chosen, not which comparison is worth showing. Filtering the
      // display by it left a one-row ladder and no verdict at all, on a day when the
      // runner-up happened to sit just outside the band.
      const pool = pickBy === 'extrinsic' ? cands.filter((c) => c.tradeable && c.extrinsic > 0) : [];
      const chosen = pool.find((c) => c.strike === putStrike);
      const other = pool.filter((c) => c.strike !== putStrike)
        .sort((a, b) => Math.abs(a.strike - spot!) - Math.abs(b.strike - spot!))[0];
      const rows = [chosen, other].filter((c): c is typeof cands[number] => !!c)
        .sort((a, b) => b.strike - a.strike);
      // Earned is usually identical across candidates, so it belongs in the
      // verdict, not in a column of its own. Each row carries the ONE fact that
      // separates it: how much of its premium is not really premium.
      const verdict = (!chosen || !other) ? null : (() => {
        const dBasis = Math.abs((other.strike - other.mid) - (putStrike - putMid));
        const dEarn = Math.abs(other.extrinsic - chosen.extrinsic);
        return dEarn <= 0.005
          ? `Both earn ${cents(chosen.extrinsic)}. _${cents(dBasis)} cheaper_`
          : `${chosen.strike} earns ${cents(dEarn)} less. _${cents(dBasis)} cheaper_`;
      })();
      return {
        label: 'Why this strike',
        rows: rows.map((c) => ({
          strike: String(c.strike),
          detail: c.intrinsic <= 0.005 ? 'no intrinsic' : `${c.intrinsic.toFixed(2)} intrinsic`,
          basis: (c.strike - c.mid).toFixed(2),
          chosen: c.strike === putStrike,
        })),
        verdict,
        fallback: pickBy === 'extrinsic' ? null : {
          state: 'delta fallback',
          headline: 'No ladder',
          note: `Chain quotes missing. Picked on *${putDeltaTgt.toFixed(2)} delta*`,
        },
      };
    })(),

    tonight: nearestExp ? {
      label: 'Tonight', tag: 'per leg',
      headline: expirySay,
      lines: expiringDetail.map((e) => e.say),
      foot: arriving > 0 ? `Average basis *${avgBasis.toFixed(2)}*` : null,
    } : null,

    holdback: calPenalty < 0 ? {
      label: 'Held back', action: `|${Math.abs(Math.round(calPenalty))} points|`,
      headline: (() => {
        if (!nextHeavy) return 'Event ahead';
        const short = String(nextHeavy.tag ?? nextHeavy.class_name).split('\u00b7')[0].trim();
        const dd = daysBetween(today, parseISO(String(nextHeavy.event_date)));
        return dd <= 0 ? `${short} today` : dd === 1 ? `${short} tomorrow` : `${short} in ${dd} days`;
      })(),
      cause: `Conviction *${Math.round(base)} \u2192 ${conviction}*`,
      note: sliceSay,
    } : null,

    calls: {
      label: cs.enabled ? 'Calls' : 'No calls',
      lines: cs.enabled
        ? [[`^Sell ${callsWarranted} call${callsWarranted === 1 ? '' : 's'} at ${callStrike ?? '\u2014'}^`, null]]
        : [['^No calls while accumulating^', null], ['cost money and shares', 'in a rally']],
      note: cs.enabled ? cs.why : 'Trim delta by *writing fewer puts*',
    },

    why: {
      label: 'Why this size',
      chain: [
        { text: `${Math.round(quarterBudget / 13)}/wk \u00d7 ${priceFactor} (${priceBand}) \u00d7 ${cf.f} (conv ${conviction})`,
          out: `${Math.round(weeklyDelta)} weekly` },
        { text: `${DOWN[decisionDow].slice(0, 3)} takes ${Math.round(sliceW * 100)}% \u00b7 ${Math.round(sliceDelta)} delta`,
          out: writtenToday > 0 ? `${Math.round(writtenToday)} written` : `${Math.round(sliceDelta)} delta` },
        ...(writtenToday > 0 ? [{ text: `${Math.round(sliceDelta)} less ${Math.round(writtenToday)} already written`,
          out: `${putCt} contract${putCt === 1 ? '' : 's'}` }] : [{ text: `at ${putDelta.toFixed(2)} delta`,
          out: `${putCt} contract${putCt === 1 ? '' : 's'}` }]),
      ],
      // "0 of 0, nothing clipped" is true and useless on a day that is already
      // done. wanted-versus-got only means something while there is something
      // left to want.
      verdict: sliceFilled
        ? `*${contractsToday} written*, _slice filled_`
        : ceilingBinds
          ? `*${putCt} of ${wantCt}*, _the ceiling cut it_`
          : `*${putCt} of ${wantCt}*, _nothing clipped_`,
    },

    where: {
      label: 'Where you are',
      headline: `*${shares.toLocaleString()} shares* \u00b7 ${pendingShares.toLocaleString()} pending \u00b7 ^${fullyAssigned.toLocaleString()} assigned^`,
      lines: [
        `Net delta *${Math.round(netDelta)}* \u2192 \`${Math.round(netDelta + putCt * 100 * putDelta - callsWarranted * 100 * cs.delta)}\``,
        `Floor covers *${Math.round(floorCoverage * 100)}%*`,
      ],
    },

    progress: {
      label: 'Progress',
      rows: [
        { label: 'Quarter', value: `${sharesThisQuarter.toLocaleString()} of ${quarterBudget.toLocaleString()}`,
          pct: quarterBudget > 0 ? Math.min(1, sharesThisQuarter / quarterBudget) : 0,
          note: `*${Math.round((sharesThisQuarter / Math.max(1, quarterBudget)) * 100)}%* ~since ${fmtDay(ymd(qStart))}~` },
        { label: 'Horizon', value: `${shares.toLocaleString()} of ${targetShares.toLocaleString()}`,
          pct: targetShares > 0 ? Math.min(1, shares / targetShares) : 0,
          note: `~week ${weeksElapsed}, projects to~ *${projectedTotal}*` },
      ],
      standing: standing.toUpperCase(),
      band: `band ${horizonLo}\u2013${horizonHi}`,
    },

    ceiling: {
      label: 'Ceiling',
      head: ceilingBinds ? 'after the cut' : 'after this trade',
      value: usd0(outstanding + putStrike * 100 * putCt),
      of: `of ${usd0(cashCeiling)}`,
      pct: cashCeiling > 0 ? Math.min(1, (outstanding + putStrike * 100 * putCt) / cashCeiling) : 0,
      room: `${ceilingBinds ? '|' : '*'}${usd0(cashCeiling - (outstanding + putStrike * 100 * putCt))}${ceilingBinds ? '|' : '*'} room`,
      before: `${usd0(headroom)} before`,
      state: ceilingBinds ? '|binding|' : 'not binding',
      cut: ceilingBinds ? `Wanted *${wantCt}*, wrote *${putCt}*` : null,
    },

    conviction: {
      label: 'Conviction score',
      score: conviction, base: Math.round(base), calendar: Math.round(calPenalty),
      movers: 'largest contributors',
      normalised: capSum < 100 ? `normalised over *${Math.round(capSum)}*` : null,
      families: [...F].sort((a, b) => {
        if (a.key === 'calendar') return 1;
        if (b.key === 'calendar') return -1;
        const at = topThree.includes(a.key) ? 1 : 0, bt = topThree.includes(b.key) ? 1 : 0;
        return bt - at || b.score - a.score;
      }).map((f) => ({
        label: f.label, score: f.score.toFixed(1), cap: f.cap < 0 ? `\u2212${Math.abs(f.cap)}` : String(f.cap),
        pct: f.cap !== 0 ? Math.min(1, Math.abs(f.score / f.cap)) : 0,
        read: f.note,
        top: topThree.includes(f.key) || undefined,
        damper: f.key === 'calendar' || undefined,
        down: f.ok ? undefined : 'Feed down, out of the denominator',
      })),
    },

    coming: {
      label: "What's coming",
      events: (eventRows as Row[]).slice(0, 6).map((e) => [
        fmtDay(String(e.event_date)),
        String(e.tag ?? e.class_name ?? ''),
        String(e.event_date).slice(0, 10) === todayISO,
      ]),
    },

    book: (() => {
      // Two positions can share a strike and differ only by expiry. Today the book
      // listed "82 put" twice, one expiring tonight and one just written for Friday,
      // with nothing to tell them apart. The date appears only when it IS the thing
      // that distinguishes them.
      const name = (l: typeof legs[number]) => `${l.strike} ${l.type}`;
      const count = new Map<string, number>();
      for (const l of legs) count.set(name(l), (count.get(name(l)) ?? 0) + 1);
      return {
        label: 'The book',
        legs: legs.map((l) => ({
          qty: `${l.ct}\u00d7`,
          leg: (count.get(name(l)) ?? 0) > 1 ? `${name(l)} \u00b7 ${fmtDay(l.expiry)}` : name(l),
          when: l.dir === 'long' ? `${fmtDay(l.expiry)} \u00b7 the floor`
            : (l.type === 'put' ? spot! < l.strike : spot! > l.strike) ? 'in the money' : 'OTM',
        })),
      };
    })(),

    sources: {
      label: 'Freshness',
      rows: [
        ['Spot', spotLive != null ? 'live' : 'cached', spotLive != null ? 'now' : ageOf(String(st.updated_at ?? ''))],
        ['Chains', pick?.modelled ? 'modelled' : 'real quotes', expiry ? 'now' : 'no chain'],
        ['FRED', 'daily', fredMissing.length ? 'feed down' : (lastFred ? fmtDay(lastFred) : 'unknown')],
        ['Treasury', 'daily', auctions.length ? fmtDay(todayISO) : 'feed down'],
        ['Book', 'on sync', ageOf(lastSync)],
      ],
    },
  };

  return json(200, {
    ok: true,
    sheet,
    asof: todayISO,
    day: DOWN[dow],
    isDecisionDay,
    spot,
    iv,

    phase: {
      state: phase,
      calls: cs.why,
      note: phase === 'ACCUMULATE'
        ? 'Puts do the work. Net delta is trimmed by writing fewer puts, not by selling calls.'
        : phase === 'HOLD' ? 'Stop adding. Keep the shares. Calls earn.'
        : 'Calls do the work. Assignment is the point.',
    },

    conviction: {
      score: conviction,
      base: Math.round(base),
      calendar: Math.round(calPenalty * 10) / 10,
      factor: cf.f,
      band: cf.band,
      families: F,
      normalisedOver: capSum,
      missing: F.filter((f) => !f.ok).map((f) => f.key),
      ramp: 'Continuous 0.7×–1.3×, anchored at 15 / 50 / 85. No step, so no 1-point cliff.',
    },

    sizing: {
      ...sizing,
      quarterBudget,
      perWeek: Math.round(quarterBudget / 13),
      slice: sliceW,
      sliceOf: DOWN[decisionDow],
      sliceSay,
      formula: '(quarter budget ÷ 13) × price × conviction',
    },

    expiring: {
      date: nearestExp,
      isToday: nearestExp === todayISO,
      sharesArriving: arriving,
      sharesLeaving: leaving,
      avgBasis,
      legs: expiringDetail,
      say: expirySay,
      tag: 'per leg · from the premium sold',
      foot: arriving > 0
        ? `Average basis on the ${arriving.toLocaleString()} if they arrive · *${avgBasis.toFixed(2)}*`
        : null,
    },

    ceiling: {
      limit: cashCeiling,
      outstanding: Math.round(outstanding),
      headroom: Math.round(headroom),
      // The state AFTER the trade the page just recommended. Headroom before it
      // answers a question the reader did not ask — they are about to commit more.
      committedAfter: Math.round(outstanding + putStrike * 100 * putCt),
      headroomAfter: Math.round(cashCeiling - (outstanding + putStrike * 100 * putCt)),
      pctAfter: cashCeiling > 0
        ? Math.round(((outstanding + putStrike * 100 * putCt) / cashCeiling) * 1000) / 1000 : 0,
      binds: ceilingBinds,
      cut: ceilingBinds
        ? `Wanted *${wantCt}*, wrote *${putCt}* — ~the ceiling took ${wantCt - putCt} contract${wantCt - putCt === 1 ? '' : 's'}~`
        : null,
      note: ceilingBinds
        ? `Cut from ${wantCt} to ${putCt} — ${fmtUsd(headroom)} of room against ${fmtUsd(cashCeiling)}.`
        : `${fmtUsd(headroom)} of room.`,
    },

    position: {
      shares,
      pendingShares,
      fullyAssigned,
      netDelta: Math.round(netDelta),
      optionDelta: Math.round(optDelta),
      floorCoverage: Math.round(floorCoverage * 100) / 100,
      floorNote: 'Floor is sized to the fully-assigned count, not to shares held — it anticipates assignment.',
      deltaNote: 'Net delta and share count diverge as TLT falls: the floor gets longer exactly while assignments add shares.',
      openLegs: legs.map((l) => ({ type: l.type, dir: l.dir, ct: l.ct, strike: l.strike, expiry: l.expiry, delta: Math.round(l.delta * 100) / 100 })),
    },

    plan: {
      expiry,
      puts: {
        contracts: putCt,
        strike: putStrike,
        delta: Math.round(putDelta * 100) / 100,
        mid: putMid,
        credit: Math.round(putMid * 100 * putCt),
        commits: Math.round(putStrike * 100 * putCt),
        shares: putCt * 100,
        modelled: pick?.modelled ?? true,
        // The split, surfaced rather than buried: only the extrinsic is earned.
        intrinsic: Math.round(putIntrinsic * 100) / 100,
        extrinsic: Math.round(putExtrinsic * 100) / 100,
        basisIfAssigned: Math.round((putStrike - putMid) * 100) / 100,
        pickedBy: pickBy,
        premium: putMid <= 0 ? 'no bid — modelled'
          : putIntrinsic <= 0.005
            ? `${Math.round(putMid * 100)}¢, all time value`
            : `${Math.round(putMid * 100)}¢, of which ${Math.round(putIntrinsic * 100)}¢ is intrinsic`,
        ladder: [...putBand].sort((a, b) => b.extrinsic - a.extrinsic).slice(0, 4).map((c) => ({
          strike: c.strike, delta: Math.round(c.dAbs * 100) / 100,
          mid: c.mid, intrinsic: Math.round(c.intrinsic * 100) / 100,
          extrinsic: Math.round(c.extrinsic * 100) / 100,
          basis: Math.round((c.strike - c.mid) * 100) / 100,
          chosen: c.strike === putStrike,
        })),
        say: putCt > 0
          ? `Sell ${putCt} put${putCt === 1 ? '' : 's'} at ${putStrike} — ${fmtUsd(putStrike * 100 * putCt)} committed, ${putCt * 100} shares if assigned.`
          : ceilingBinds ? 'No room under the ceiling.' : 'Nothing this slice.',
      },
      calls: {
        contracts: callsWarranted,
        strike: callStrike,
        delta: cs.delta,
        mid: callMid,
        credit: Math.round(callMid * 100 * callsWarranted),
        coverageCap: cs.coverage,
        coveredNow,
        enabled: cs.enabled,
        say: callsWarranted > 0 && callStrike != null
          ? `Sell ${callsWarranted} call${callsWarranted === 1 ? '' : 's'} at ${callStrike}.`
          : !cs.enabled
            ? 'No calls while accumulating — they cost money and shares in a rally.'
            : 'No calls warranted.',
      },
      netAfter: Math.round(netDelta + putCt * 100 * putDelta - callsWarranted * 100 * cs.delta),
    },

    quarter: {
      startedOn: ymd(qStart),
      budget: quarterBudget,
      acquired: sharesThisQuarter,
      pct: quarterBudget > 0 ? Math.round((sharesThisQuarter / quarterBudget) * 100) : 0,
      note: 'A budget, not a quota. A missed quarter spends weeks in the band; it never raises next quarter.',
    },

    horizon: {
      startedOn, weeksElapsed, target: targetShares, shares, remaining,
      projectedTotal, lo: horizonLo, hi: horizonHi, standing,
      say: `${shares.toLocaleString()} of ${targetShares.toLocaleString()} · week ${weeksElapsed} · projects to ${projectedTotal} (${standing})`,
    },

    evidence: {
      events: eventRows,
      bloc: { seats: blocRows, meta: blocMetaRows[0] ?? null, signConvention: 'lean > 0 read as HAWKISH' },
      auctions: auctions.filter((a) => a.auctionDate >= todayISO).slice(0, 6),
      fredMissing,
    },

    meta: {
      caps: CAPS, priceBands: PRICE_BANDS.map(([hi, f, l]) => ({ under: hi, factor: f, label: l })),
      phaseCalls: PHASE_CALLS, sliceWeights: SLICE, strikeStep: STRIKE_STEP,
      spec: 'docs/TLT_ACCUMULATION.md',
    },
  });
});
