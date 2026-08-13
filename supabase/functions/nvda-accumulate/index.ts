/**
 * nvda-accumulate — the next NVDA short-put decision.
 *
 * Spec: docs/NVDA_ACCUMULATION.md. Evidence: research/nvda-tenor.
 *
 * This is tlt-planner's machinery, because NVDA has switched from monetising a
 * block to building one and that is the same strategy. The old nvda-planner and
 * its screen are untouched.
 *
 * Three things differ, and all three were measured:
 *
 *   STRIKE   1% out of the money, not at it. 1% won on everything at once — more
 *            shares, better basis, +$69,583 over two years — for $27K more
 *            capital. The curve peaks there: 2% is a coin flip, 3% loses.
 *
 *   DIAL     Distance below MA100, not an absolute price. TLT oscillates around a
 *            yield so a price band works; NVDA trends, and a fixed price either
 *            never fires or fires forever. MA100 discriminated best of seven
 *            references: below it the next month averaged +9.4%, above it +2.6%.
 *
 *   SCORE    Conviction ships at WEIGHT ZERO. Six candidate signals tested against
 *            62 real weekly writes and none cleared the noise; the largest tertile
 *            spread was 1.29 against a 0.66 standard error, and it was negative.
 *            The score is computed and stored so the trail can eventually judge it.
 *            It does not move size until it has earned the right.
 *
 * Cadence is weekly. Dip-triggered writing was tested and loses: the premium really
 * is richer (+23% to +37%) but delivery falls from 100% to 80%, because a drop is
 * the condition most likely to bounce back above the strike. A dip is a better
 * moment to be paid and a worse moment to be delivered, and this book is paid in
 * shares.
 *
 * Env: POLYGON_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
 * Body (all optional): {"dry_run":true,"stream":true,"asof":"2026-08-26"}
 */
const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' };
const json = (s: number, b: unknown) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

const POLY = 'https://api.polygon.io';
const FRED = 'https://api.stlouisfed.org/fred/series/observations';
const FISCAL = 'https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v1/accounting/od/auctions_query';
const TICKER = 'NVDA';
const STRIKE_STEP = 2.5;
const R_FREE = 0.045;
const IV_FALLBACK = 0.37;          // NVDA realised 37% over the last year; only a fallback

// ── the nine families ───────────────────────────────────────────────────────
// Eight positives sum to 100. calendar is a damper and never adds.
// Candidates, not conclusions. Caps are placeholders until the trail can rank them;
// what matters today is that each is computed the same way every day so the history
// is comparable. `calendar` and `earnings` are the exception — they are dampers, and
// a damper is risk management rather than prediction, so they DO cut size.
const CAPS = {
  vrp: 30, ivRank: 25, trend: 25, relative: 20,
  earnings: -20, calendar: -12,
} as const;

// The dial reads DISTANCE BELOW MA100, never a price. NVDA trends, so an absolute
// band would either never fire or fire forever. Cuts are the real tertiles of the
// days NVDA spent below its own MA100, and the forward-20d return in each:
//   deeper than -11.2%  +7.0%   ·   -11.2 to -3.3%  +5.7%
//   -3.3% to flat       +1.4%   ·   above           +1.3%
// ORDER MATTERS: scanned with find(vsMa < hi) and must stay ASCENDING.
const MA_BANDS: Array<[number, number, string]> = [
  [-11.2, 2.50, 'more than 11% below'],
  [-3.3, 1.50, '3 to 11% below'],
  [0, 1.00, 'just below'],
  [Infinity, 0.60, 'above the mean'],
];

// Conviction is the trim: a continuous ramp between the agreed 0.7x and 1.3x.
//
// This was three steps. Steps put a 30% swing on a 1-point move, and the live run
// landed conviction at exactly 70 the day CPI cleared — one point from doubling
// the trade. The ramp is anchored through the centres of the old bands (15 / 50 /
// 85) rather than drawn 0-to-100, so the endpoints stay REACHABLE: a plain line
// would make 0.7x and 1.3x require a 0 or a 100, which never happen, quietly
// compressing the range everyone agreed to.
// WEIGHT ZERO, on purpose. Six candidate signals were tested against 62 real
// weekly writes and none cleared the noise: the largest tertile spread was 1.29
// against a 0.66 standard error, and that one was NEGATIVE. A 30% trim driven by
// signals that do not predict adds variance and subtracts nothing else.
//
// The score is still computed and written to the trail every day, because in a few
// months there will be enough history to judge it against outcomes. Raise
// conviction_wt in nvda_planner_state when, and only when, something earns it.
function convFactor(score: number, weight: number): { f: number; band: string } {
  if (weight <= 0) return { f: 1, band: 'unweighted' };
  const s = clamp(score, 0, 100);
  const raw = s <= 15 ? 0.7
    : s <= 50 ? 0.7 + 0.3 * ((s - 15) / 35)
    : s <= 85 ? 1.0 + 0.3 * ((s - 50) / 35)
    : 1.3;
  const f = 1 + (raw - 1) * clamp(weight, 0, 1);
  return { f: Math.round(f * 1000) / 1000, band: `weighted ${Math.round(weight * 100)}%` };
}

// The call side is a function of the PHASE, not the ticker. HARVEST is the only
// phase that inherits NVDA's ATM result, because it is the only one where the
// intention matches: monetising a block you are content to lose.
//
// ACCUMULATE was off on the strength of the TLT study below. NVDA's own data says
// otherwise, and the rule that replaced it is not about strike -- it is ROLL OR DIE.
// research/nvda_calls_acc: with the share path endogenous and assignment allowed,
// weekly calls on a growing block called away 16,900 shares and left 1,700 against a
// 15,000 target. Rolled instead, the same overwrite is worth ~$4/share of basis at no
// cost in shares. The overlay is therefore only ever safe while every in-the-money
// call is rolled; one skipped roll is the difference between the two outcomes.
//
// ATM at 30% cover is Nik's structure and it ties 4%-out at 50% on basis (16 of 38
// windows, medians 23c apart). It leaves 70% of the block uncapped for a run and
// needs ~42 contracts rather than ~70; it costs ~$94K more in roll debits. That is a
// preference, not an error, so it is the default and both dials live in state.
//
// The TLT finding, kept because it is why the phase table exists at all
// (research/tlt-strike-policy,
// 105 weekly rolls on real marks). Across the whole window calls looked worth
// ~$40K — but that window fell 91.6 to 82.2, and the winning arms ended holding
// 25-28% of what they bought. They were not earning premium, they were selling
// shares into a decline. In the rally sub-period, where the answer is not
// contaminated by direction, calls cost $6,589 at 0.15 delta and $13,921 at the
// money, and gave away a third to 41% of the block. A smaller dose of a losing
// trade is still a losing trade, so the old 0.15 delta / 20% setting is gone
// rather than reduced.
const PHASE_CALLS: Record<string, { enabled: boolean; delta: number; coverage: number; why: string }> = {
  ACCUMULATE: { enabled: true, delta: 0.50, coverage: 0.30,
                why: 'ATM on part of the block — worth ~$4/share of basis, but ONLY while every in-the-money call is rolled' },
  HOLD:       { enabled: true, delta: 0.25, coverage: 0.50, why: 'Income on a block that has stopped growing' },
  HARVEST:    { enabled: true, delta: 0.50, coverage: 1.00, why: 'Exit. Assignment is the point' },
};

// Mon/Wed/Fri each write a slice of the week. Friday's is smallest: it carries
// the weekend, and the weekend is when you cannot react.
const SLICE: Record<number, number> = { 1: 0.40, 3: 0.40, 5: 0.20 };
// The same slices, accumulated. Sizing works against the week TO DATE rather than
// the isolated day, because whole-contract rounding on a lone slice throws away the
// remainder: at 63 delta a week, every slice lands near 0.47 contracts and rounds to
// zero, so the week writes NOTHING — while five hundredths of delta the other way
// rounds all three up and writes double. Carrying within the week makes the reachable
// output continuous instead of all-or-nothing. It resets each Monday, so a slow week
// never banks contracts into a fast one.
const SLICE_CUM: Record<number, number> = { 1: 0.40, 3: 0.80, 5: 1.00 };

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
// ── market state ────────────────────────────────────────────────────────────
// Read off the exchange's own clock via the IANA zone, not a hardcoded UTC offset:
// New York is UTC-4 half the year and UTC-5 the other half, and a fixed offset is
// wrong for one of them. Holidays are NOT handled — the NYSE calendar is not
// derivable, so Thanksgiving reads "Live" until a holiday table exists.
// Polygon knows the exchange calendar -- holidays, half-days, early closes -- which a
// clock cannot derive. The clock version below stays as the fallback: if this call
// fails or the plan does not cover it, a wrong label is better than a dead screen.
async function marketNow(key: string): Promise<{ open: boolean; label: string } | null> {
  try {
    const r = await fetch(`${POLY}/v1/marketstatus/now?apiKey=${key}`);
    if (!r.ok) return null;
    const j = await r.json();
    const m = String(j?.market ?? '');
    if (!m) return null;
    // Extended hours counts as closed: Polygon's feed is delayed and the planner
    // prices off the regular session, so "Live" would overstate what it is reading.
    return m === 'open' ? { open: true, label: 'Live' } : { open: false, label: 'Market closed' };
  } catch { return null; }
}

function marketState(now: Date): { open: boolean; label: string } {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-US', {
      timeZone: 'America/New_York', hour12: false,
      weekday: 'short', hour: '2-digit', minute: '2-digit',
    }).formatToParts(now).map((p) => [p.type, p.value]),
  );
  const wd = String(parts.weekday);
  if (wd === 'Sat' || wd === 'Sun') return { open: false, label: 'Market closed' };
  const mins = Number(parts.hour) * 60 + Number(parts.minute);
  const open = mins >= 9 * 60 + 30 && mins < 16 * 60;   // 09:30–16:00 ET
  return { open, label: open ? 'Live' : 'Market closed' };
}

const fmtDay = (iso: string, thisYear?: number) => {
  const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number);
  if (!(y && m && d)) return String(iso);
  // The year appears only when it is NOT the current one, so the common case stays
  // short — but a Dec 2028 LEAP must never render as "Dec 15" beside a Sep 18 weekly.
  return thisYear != null && y !== thisYear ? `${MONTHS[m - 1]} ${d} ${y}` : `${MONTHS[m - 1]} ${d}`;
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

// ── Polygon: daily closes, for MA100 and realised vol ─────────────────────
async function dailyCloses(key: string, fromISO: string, toISO: string): Promise<Array<{ d: string; c: number }>> {
  try {
    const r = await fetch(`${POLY}/v2/aggs/ticker/${TICKER}/range/1/day/${fromISO}/${toISO}`
      + `?adjusted=true&sort=asc&limit=50000&apiKey=${key}`);
    if (!r.ok) return [];
    const j = await r.json() as { results?: Array<Record<string, number>> };
    return (j?.results ?? []).map((x) => ({ d: new Date(x.t).toISOString().slice(0, 10), c: x.c }));
  } catch { return []; }
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

// The boot layer's stages are REAL steps, so they are emitted in the order the
// engine actually works: conviction is scored before the chain is priced, which is
// the reverse of the first design draft. Showing them in the drawn order would mean
// marking a step done before it ran, which is the one thing the spec forbids.
const BOOT_STAGES = [
  'Reading current position',
  'Scoring conviction',
  'Pricing the chain',
  'Building your updated plan',
];

async function build(req: Request, emit: (n: number) => void): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const polyKey = Deno.env.get('POLYGON_API_KEY');
  const fredKey = Deno.env.get('FRED_API_KEY');
  const supaUrl = Deno.env.get('SUPABASE_URL');
  const supaKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!polyKey) return json(500, { ok: false, error: 'POLYGON_API_KEY not set' });
  if (!supaUrl || !supaKey) return json(500, { ok: false, error: 'SUPABASE_URL / SERVICE_ROLE_KEY not set' });

  let body: { dry_run?: boolean; phase?: string; asof?: string; what_if?: { shares?: number; drop_calls?: boolean } } = {};
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
  const [stateRows, eventRows, earnRows, tradeRows, lotRows, ivRows, spotLive, closes, polyMarket] =
    await Promise.all([
      D.get('nvda_planner_state?id=eq.1&select=*'),
      D.get(`macro_events?event_date=gte.${todayISO}&select=name,event_date&order=event_date.asc&limit=12`),
      D.get(`earnings_events?select=*&order=event_date.asc&limit=8`),
      D.get('nvda_option_trades?voided_at=is.null&select=id,action,option_type,direction,contracts,strike,premium,expiry,closes_trade_id,trade_date,last_synced_at'),
      D.get('nvda_share_lots?voided_at=is.null&select=acquired_date,qty_remaining'),
      D.get('nvda_iv_daily?select=*&order=date.desc&limit=260'),
      spotOf(polyKey),
      dailyCloses(polyKey, ymd(addDays(today, -400)), todayISO),
      // Was a second identical 400-day dailyCloses whose result was destructured to
      // `smh` and never read once -- a full Polygon round-trip discarded on every load.
      marketNow(polyKey),
    ]);
  emit(1);                                   // position read: book, lots, legs, spot, closes

  const st = (stateRows[0] ?? {}) as Row;
  const phase = 'ACCUMULATE';   // no phase switch here: NVDA is building a block, full stop
  if (!PHASE_CALLS[phase]) return json(400, { ok: false, error: `unknown phase ${phase}` });
  const targetShares = Number(st.target_shares ?? 15000);
  const quarterBudget = Number(st.quarter_budget ?? 2450);
  const cashCeiling = Number(st.cash_ceiling ?? 400000);
  const horizonLo = Number(st.horizon_lo_wk ?? 66);
  const horizonHi = Number(st.horizon_hi_wk ?? 78);
  const startedOn = String(st.started_on ?? '2026-08-26');
  // 0.50, not the 0.45 first drafted. ATM won the full window, was never worst in
  // any sub-period, and — the reason that actually decides it — kept accumulating
  // through the rally where OTM stalled: 7,800 shares against OTM's 5,100. An OTM
  // put stops delivering exactly when TLT runs away from you.
  const otmPct = Number(st.otm_pct ?? 0.01);
  const maWindow = Number(st.ma_window ?? 100);
  const convWeight = Number(st.conviction_wt ?? 0);
  // The picker still needs a delta target for its fallback; the STRIKE is set by
  // otmPct, which is what the test settled.
  const putDeltaTgt = 0.42;

  // spot: Polygon first, nvda_quote as the fallback
  let spot = spotLive;
  if (spot == null) {
    const q = await D.get(`nvda_quote?ticker=eq.${TICKER}&select=spot`);
    spot = num(q[0]?.spot);
  }
  if (spot == null || spot <= 0) return json(502, { ok: false, error: 'no TLT spot from Polygon or nvda_quote' });

  const iv = num(ivRows[0]?.iv) ?? num(ivRows[0]?.iv_30d) ?? IV_FALLBACK;

  // ── the candidates ───────────────────────────────────────────────────────
  // None of these move size. They are computed identically every day so the trail
  // has a comparable history to judge them against later. See the weight-zero note
  // on convFactor.
  const cl = closes.map((x) => x.c);
  const ma = (n: number) => cl.length >= n ? cl.slice(-n).reduce((a, b) => a + b, 0) / n : null;
  const ma100 = ma(maWindow), ma50 = ma(50), ma200 = ma(200);
  const hv = (n: number) => {
    if (cl.length < n + 1) return null;
    const w = cl.slice(-(n + 1));
    const lr = w.slice(1).map((c, k) => Math.log(c / w[k]));
    return sd(lr) * Math.sqrt(252);
  };
  const hv20 = hv(20);
  const ivHist = (ivRows as Row[]).map((r) => num(r.iv) ?? num(r.iv_30d)).filter((x): x is number => x != null);
  const ivNow = ivHist[0] ?? null;

  const F: Family[] = [];

  // vrp — implied against realised. The one edge an option seller is supposed to
  // have, and it scored +0.25 on a 2.94 standard deviation. Recorded, not trusted.
  {
    const gap = ivNow != null && hv20 != null ? ivNow - hv20 : null;
    F.push(fam('vrp', 'Implied vs realised', CAPS.vrp,
      gap == null ? null : clamp((gap + 0.10) / 0.25, 0, 1),
      gap == null ? 'no IV or realised'
        : `IV ${(ivNow! * 100).toFixed(0)}% vs realised ${(hv20! * 100).toFixed(0)}% · ${gap >= 0 ? 'paid over' : 'paid under'}`));
  }

  // ivRank — where implied sits in its own year.
  {
    const r = ivNow != null && ivHist.length >= 60 ? pctRank(ivHist, ivNow) : null;
    F.push(fam('ivRank', 'IV rank', CAPS.ivRank, r,
      r == null ? 'not enough IV history' : `${Math.round(r * 100)}th percentile of ${ivHist.length} days`));
  }

  // trend — is the uptrend intact. Not the same reading as the dial, which measures
  // DISTANCE from the mean; this measures the mean's own slope.
  {
    const t = ma50 != null && ma200 != null ? (ma50 / ma200 - 1) * 100 : null;
    F.push(fam('trend', 'Trend', CAPS.trend,
      t == null ? null : clamp((t + 5) / 25, 0, 1),
      t == null ? 'not enough history'
        : `50d ${t >= 0 ? '+' : '−'}${Math.abs(t).toFixed(1)}% vs 200d · ${t > 0 ? 'intact' : 'broken'}`));
  }

  // relative — is weakness NVDA's own or the whole complex. Not wired to a peer feed
  // yet, so it reports absent rather than inventing a reading.
  F.push(fam('relative', 'Vs the complex', CAPS.relative, null, 'peer feed not wired'));

  // ── conviction: normalise over the families that actually answered ────────
  const positives = F.filter((f) => f.ok);
  const capSum = positives.reduce((s, f) => s + f.cap, 0);
  const rawSum = positives.reduce((s, f) => s + f.score, 0);
  const base = capSum > 0 ? (rawSum / capSum) * 100 : 50;

  // calendar — a damper, never an addition. This is what thrice-weekly buys:
  // "write half now, the rest Friday after CPI" is a sentence a weekly cadence
  // cannot produce.
  const nextHeavy = (eventRows as Row[])[0];
  const nextEarn = (earnRows as Row[])
    .map((e) => String(e.event_date ?? e.date ?? '').slice(0, 10))
    .filter((d) => d >= todayISO).sort()[0] ?? null;
  let calPenalty = 0, calNote = 'clear for a week';
  if (nextHeavy) {
    const dd = daysBetween(today, parseISO(String(nextHeavy.event_date)));
    calPenalty = dd <= 2 ? CAPS.calendar : dd <= 4 ? CAPS.calendar / 2 : dd <= 7 ? CAPS.calendar / 4 : 0;
    calNote = `${String(nextHeavy.name ?? 'event')} ${fmtDay(String(nextHeavy.event_date))}${dd <= 7 ? ` · ${dd}d out` : ''}`;
  }
  F.push({ key: 'calendar', label: 'Calendar', cap: CAPS.calendar, score: Math.round(calPenalty * 10) / 10, pct: null, note: calNote, ok: true });

  const conviction = Math.round(clamp(base + calPenalty, 0, 100));
  emit(2);                                   // conviction scored: FRED, Treasury, bloc, calendar

  // ── the book ─────────────────────────────────────────────────────────────
  // Positions are NETTED by contract, not resolved through closes_trade_id.
  //
  // That link is one-to-one and IBKR's closes are not: a 47-contract floor opened
  // across nine fills is closed by two aggregated rows, each of which can only point
  // at ONE opener. The other seven stayed "open" forever. On 12 Aug the book showed
  // 229 long puts and a floor covering 1527% of the block; the true floor was 75.
  // Expired legs hid it -- they are filtered by date before anyone looks.
  //
  // Netting needs no back-reference to be right: opens add, closes subtract, and a
  // contract survives only while the sum is positive.
  const live = (tradeRows as Row[]).filter((t) => String(t.expiry).slice(0, 10) >= todayISO);
  const netByKey = new Map<string, number>();
  for (const t of live) {
    const key = `${t.option_type}|${t.direction}|${t.strike}|${String(t.expiry).slice(0, 10)}`;
    const ct = fin(Number(t.contracts));
    netByKey.set(key, (netByKey.get(key) ?? 0) + (String(t.action) === 'open' ? ct : -ct));
  }
  const open = live.filter((t) => String(t.action) === 'open');

  // what_if lets the plan be read against a position that does not exist yet -- the
  // point being to see the post-reduction planner BEFORE committing to the reduction.
  // It never writes the trail (forced below), so a hypothesis cannot become history.
  const wi = (body.what_if ?? null) as { shares?: number; drop_calls?: boolean } | null;
  const shares = wi?.shares != null
    ? Number(wi.shares)
    : (lotRows as Row[]).reduce((s, l) => s + fin(Number(l.qty_remaining)), 0);
  const qStart = quarterStart(today);
  // Under what_if the real lots are not the hypothesis. Left unoverridden this row
  // kept reporting the true 7,500 beside a hypothetical 1,500, which reads as a
  // quarter already 306% delivered on a block that has not been bought yet.
  const sharesThisQuarter = wi?.shares != null ? 0 : (lotRows as Row[])
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
    // Premium and fill dates come from the opens; the COUNT comes from the net below,
    // so a partially closed position keeps an honest basis on the contracts left.
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
  for (const [key, agg] of [...byContract]) {
    const net = netByKey.get(key) ?? 0;
    if (net <= 0) { byContract.delete(key); continue; }
    if (net < agg.ct) {                       // partially closed: scale the basis with it
      agg.premWeighted = agg.premWeighted * (net / agg.ct);
      agg.ct = net;
    }
  }

  const legsAll: Leg[] = [...byContract.values()].map((a) => {
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

  // drop_calls models closing the legacy overwrite as part of the reduction — the only
  // safe sequencing, since 65 short calls against 1,500 shares is 5,000 shares of NAKED
  // call, the one position here with unbounded loss. Filtered HERE rather than at each
  // use site: the first attempt patched shortCalls and the delta sum only, so the book
  // and tonight cards went on listing calls the same screen said had been closed.
  const legs: Leg[] = wi?.drop_calls
    ? legsAll.filter((l) => !(l.type === 'call' && l.dir === 'short'))
    : legsAll;
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
  // Written = NET delta put on, not gross opens. A contract opened and closed inside
  // the same window added no delta and must not spend the week's budget: TLT opened
  // and closed 10 puts on 12 Aug and the week read 894 of 547 delta — "slice filled" —
  // when the real figure was 394 and three contracts were still owed.
  //
  // Netted by contract over the window so a close cancels its open wherever both fall
  // inside it. Built from raw fills rather than the aggregated legs, because
  // aggregation keeps only the earliest fill date.
  const writtenSince = (from: string): { delta: number; contracts: number } => {
    const net = new Map<string, number>();
    for (const t of tradeRows as Row[]) {
      if (String(t.option_type) !== 'put' || String(t.direction) !== 'short') continue;
      if (String(t.trade_date ?? '').slice(0, 10) < from) continue;
      const key = `${t.strike}|${String(t.expiry).slice(0, 10)}`;
      const ct = fin(Number(t.contracts));
      net.set(key, (net.get(key) ?? 0) + (String(t.action) === 'open' ? ct : -ct));
    }
    let delta = 0, contracts = 0;
    for (const [key, ct] of net) {
      if (ct <= 0) continue;
      const [K, exp] = key.split('|');
      const T = Math.max(daysBetween(today, parseISO(exp)), 0) / 365;
      delta += putDeltaAbs(spot!, Number(K), T, iv) * ct * 100;
      contracts += ct;
    }
    return { delta, contracts };
  };
  const today_ = writtenSince(todayISO);
  const writtenToday = today_.delta;
  const contractsToday = today_.contracts;
  const weekStart = (() => {
    const d = new Date(today.getTime());
    const dow = d.getUTCDay();
    d.setUTCDate(d.getUTCDate() - ((dow + 6) % 7));   // back to Monday
    return d.toISOString().slice(0, 10);
  })();
  const writtenWeek = writtenSince(weekStart).delta;

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
        ? `${l.ct}× ${l.strike} ${l.type} · the floor, ${fmtDay(l.expiry, today.getUTCFullYear())}`
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
  // CONDITIONAL, always. "3,500 shares called" is a claim about something that has
  // not happened -- these settle at the bell and the stock moves until then. Said
  // flatly it also contradicted the roll instruction directly beneath it, which
  // offered to keep the very shares this line said were gone.
  const expiryIsToday = nearestExp === todayISO;
  const expirySay = !nearestExp ? 'Nothing expiring'
    : arriving > 0
      ? `${strikeSet(itmShorts.filter((e) => e.type === 'put'))}s *in the money*.`
        + ` ^${arriving.toLocaleString()} shares^ arrive ${expiryIsToday ? 'tonight' : 'if it closes here'}`
      : leaving > 0
        ? `${strikeSet(itmShorts.filter((e) => e.type === 'call'))}s *in the money*.`
          + ` ^${leaving.toLocaleString()} shares^ go ${expiryIsToday ? 'tonight' : 'if it closes here'}`
        : 'Nothing in the money. All expire worthless as it stands';

  // ── sizing ───────────────────────────────────────────────────────────────
  // The dial. Distance below MA100, not a price.
  // Signed against the mean: POSITIVE is above it, negative is below. Named for what
  // it is rather than for the direction we care about — a field called below_pct
  // holding +9.51 to mean "9.5% above" is a wrong conclusion waiting to happen.
  const vsMa = ma100 ? (spot! / ma100 - 1) * 100 : 0;
  const band = MA_BANDS.find(([hi]: [number, number, string]) => vsMa < hi) ?? MA_BANDS[MA_BANDS.length - 1];
  const priceFactor = band[1], priceBand = band[2];
  const cf = convFactor(conviction, convWeight);

  // The rate chases a shortfall, bounded at 2x.
  //
  // It used to be open-loop on delivery: quarter budget x price x conviction, never
  // looking at whether shares actually ARRIVED. That undershot, because puts expire
  // worthless in a rally and the longest real dry spell at 1% OTM ran TWELVE weeks --
  // ~2,280 shares never bought. Over every 72-week window in the data the fixed rate
  // landed a median 12,600 of 15,000.
  //
  // So the rate is now what is still needed per remaining week. The bound matters as
  // much as the chase: unbounded, the same test produced 40-contract weeks and $0.7M
  // outstanding, because the event that starves delivery is a rally, and chasing into
  // one fights the price dial -- the part of this model that measured best. Capped at
  // 2x it lands a median 14,100 for about $5/share of basis, and the cash ceiling
  // below is still the hard backstop. See research/nvda-tenor/nvda_catchup.py.
  const baseRate = quarterBudget / 13;
  const horizonWk = (horizonLo + horizonHi) / 2;              // the doc's ~72 weeks
  const wkElapsed = Math.max(0, Math.floor(daysBetween(parseISO(startedOn), today) / 7));
  const wkLeft = Math.max(1, horizonWk - wkElapsed);
  const stillNeed = Math.max(0, targetShares - shares);
  const chaseRate = Math.min(stillNeed / wkLeft, 2 * baseRate);
  const chasing = chaseRate > baseRate * 1.02;
  const weeklyDelta = chaseRate * priceFactor * cf.f;

  const dow = today.getUTCDay();
  const decisionDow = SLICE[dow] != null ? dow : (dow === 0 || dow === 6 ? 1 : dow < 3 ? 3 : dow < 5 ? 5 : 1);
  const sliceW = SLICE[decisionDow];
  const sliceDelta = weeklyDelta * sliceW;
  // Target through today, less everything written since Monday — so an earlier slice
  // that rounded to zero is still owed rather than forgotten.
  const weekToDate = weeklyDelta * (SLICE_CUM[decisionDow] ?? 1);
  const sliceLeft = Math.max(0, weekToDate - writtenWeek);
  const sliceFilled = writtenWeek > 0 && sliceLeft < weekToDate * 0.15;
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
  emit(3);                                   // chain priced: real quotes for the candidates

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

  // 1% out is the settled strike, so the ladder is centred there rather than on a
  // delta. The extrinsic rule still picks between the neighbours around it.
  const wantStrike = Math.round((spot! * (1 - otmPct)) / STRIKE_STEP) * STRIKE_STEP;
  const putBand = cands.filter((c) => c.tradeable && c.extrinsic > 0
    && Math.abs(c.strike - wantStrike) <= STRIKE_STEP * 2);
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
  const cs = (() => {
    const base = PHASE_CALLS[phase];
    if (!base.enabled) return base;
    return {
      ...base,
      enabled: st.calls_on == null ? base.enabled : !!st.calls_on,
      delta: Number(st.call_delta ?? base.delta),
      coverage: Number(st.call_coverage ?? base.coverage),
    };
  })();
  const coveredNow = shortCalls.reduce((s, l) => s + l.ct * 100, 0);
  const coverRoom = Math.max(0, Math.floor((shares * cs.coverage - coveredNow) / 100));
  // Write up to the coverage target. This is a deliberate overwrite sized to a share
  // of the block, not a delta-overflow valve — the old rule only fired after a run of
  // assignments and so never wrote at all in the ordinary case.
  const callsWarranted = !cs.enabled ? 0 : coverRoom;

  // Everything above is premised on rolling. Surface any short call already in the
  // money so the obligation is on the screen rather than in a comment.
  const dueToRoll = shortCalls.filter((l) => spot! > l.strike);
  const rollCost = dueToRoll.reduce((s, l) => s + (spot! - l.strike) * 100 * l.ct, 0);

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
  // Same numbers the rate was sized from, so the readout cannot disagree with the
  // instruction: projected off the rate actually being written, not the base budget.
  const weeksElapsed = wkElapsed;
  const remaining = stillNeed;
  const weeksAtBudget = chaseRate > 0 ? remaining / chaseRate : Infinity;
  const projectedTotal = Math.round(weeksElapsed + weeksAtBudget);
  const standing = projectedTotal < horizonLo ? 'early' : projectedTotal <= horizonHi ? 'on plan' : 'behind';

  // ── the trail ────────────────────────────────────────────────────────────
  const sizing = {
    weeklyDelta: Math.round(weeklyDelta), sliceDelta: Math.round(sliceDelta),
    priceFactor, priceBand, convFactor: cf.f, convBand: cf.band,
    baseRate: Math.round(baseRate), chaseRate: Math.round(chaseRate), chasing,
    weeksLeft: Math.round(wkLeft), stillNeed,
    contracts: putCt, wanted: wantCt, ceilingBinds,
    writtenToday: Math.round(writtenToday), writtenWeek: Math.round(writtenWeek),
    weekToDate: Math.round(weekToDate), contractsToday,
    sliceLeft: Math.round(sliceLeft), sliceFilled,
  };
  if (!body.dry_run && !wi) {
    await D.upsert('nvda_planner_factor_daily', [{
      taken_on: todayISO, spot, ma: ma100, vs_ma_pct: Math.round(vsMa * 100) / 100,
      conviction, families: F, sizing,
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
  const lastSync = (tradeRows as Row[]).map((t) => String(t.last_synced_at ?? '')).filter(Boolean).sort().pop() ?? null;

  const sheet = {
    ticker: TICKER,
    boot: { stages: BOOT_STAGES, mark: 'one moment' },
    asOf: { label: dayLabel, refresh: `${spot.toFixed(2)} \u00b7 ${phase}`,
            market: polyMarket ?? marketState(new Date()) },
    phase: `${phase.charAt(0)}${phase.slice(1).toLowerCase()} phase`,

    instruction: {
      label: 'The instruction',
      verb: putCt > 0 ? `Sell ${putCt} put${putCt === 1 ? '' : 's'} at ${putStrike}`
        : sliceFilled ? "Today's slice is filled" : 'Nothing this slice',
      meta: putCt === 0 && sliceFilled
        ? `${contractsToday} written today \u00b7 ${Math.round(writtenWeek)} of ${Math.round(weekToDate)} delta this week`
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

    // The SECOND card. Calls had two jobs scattered across two places -- what to
    // write, and what to do about contracts expiring -- and the screen managed to say
    // "3,500 shares called" above "roll to keep the shares", which are opposite
    // claims about the same contracts. One card, both jobs, and the tense is
    // conditional throughout: nothing is called until it settles.
    callCard: (() => {
      const coverPct = shares > 0 ? coveredNow / shares : 0;
      const targetCt = Math.floor(shares * cs.coverage / 100);
      const overCt = Math.max(0, Math.round(coveredNow / 100) - targetCt);
      const itmCt = dueToRoll.reduce((n, l) => n + l.ct, 0);
      const itmShares = itmCt * 100;
      const nearest = shortCalls.length
        ? shortCalls.map((l) => l.expiry).sort()[0] : null;
      return {
        label: 'The calls',
        verb: !cs.enabled ? 'No calls while accumulating'
          : callsWarranted > 0 && callStrike != null
            ? `Sell ${callsWarranted} call${callsWarranted === 1 ? '' : 's'} at ${callStrike}`
            : 'Nothing to sell',
        // Mirrors the instruction's cadence exactly: date · figure · source.
        meta: !cs.enabled ? 'Trim delta by writing fewer puts'
          : `${nearest ? `${DOWN[parseISO(nearest).getUTCDay()].slice(0, 3)} ${fmtDay(nearest, today.getUTCFullYear())}` : 'none open'}`
            // No "real quotes" here: unlike the put card, nothing below is a quote.
            + ` \u00b7 ${itmCt} of ${shortCalls.reduce((n, l) => n + l.ct, 0)} in the money`,
        commit: [
          [coveredNow.toLocaleString(), 'covered'],
          [overCt > 0 ? String(overCt) : String(Math.max(0, targetCt - Math.round(coveredNow / 100))),
           overCt > 0 ? 'over target' : 'to target'],
        ],
        // CONDITIONAL. These settle on Friday and Friday has not happened. The
        // caveat lives in the cover card below; a stat label is not the place for it.
        // Intrinsic, and labelled as such. "to roll" overstated it -- a roll sells a
        // later call and gives back some of this in time value -- and the honest
        // figure is simply how far in the money the calls are.
        basis: itmCt > 0
          ? { value: usd0(rollCost), label: 'in the money' }
          : { value: '\u2014', label: 'none in the money' },
        earn: itmCt > 0
          ? { value: itmShares.toLocaleString(), label: 'shares at risk' }
          : { value: String(shortCalls.reduce((n, l) => n + l.ct, 0)), label: 'calls open' },
        mark: itmCt > 0 ? 'roll or they go' : null,
        when: nearest ? `${DOWN[parseISO(nearest).getUTCDay()].slice(0, 3)} ${fmtDay(nearest, today.getUTCFullYear())}` : null,
      };
    })(),

    // Everything the call card used to carry in its labels. Same shape as `why`, so
    // the existing renderer draws it and no new component is invented.
    cover: !cs.enabled ? null : (() => {
      const coverPct = shares > 0 ? coveredNow / shares : 0;
      const targetCt = Math.floor(shares * cs.coverage / 100);
      const haveCt = Math.round(coveredNow / 100);
      const overCt = Math.max(0, haveCt - targetCt);
      return {
        label: 'Cover',
        chain: [
          { text: `${haveCt} calls written`, out: `${coveredNow.toLocaleString()} shares` },
          { text: `against ${shares.toLocaleString()} held`, out: `${Math.round(coverPct * 100)}%` },
          { text: `target ${Math.round(cs.coverage * 100)}%`, out: `${targetCt} contracts` },
        ],
        verdict: overCt > 0
          ? `*${overCt} over.* ~Expiry brings it down — nothing to buy back~`
          : haveCt === targetCt ? '*At target*'
            : `*${targetCt - haveCt} short* of the target`,
      };
    })(),

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
      // Named for WHEN, not "Tonight" regardless. This card shows the nearest expiry,
      // which is only tonight some of the time: with the nearest at Friday it was
      // headed "Tonight · 3,500 shares called" for contracts two days away.
      label: nearestExp === todayISO ? 'Tonight'
        : nearestExp ? `Expiring ${fmtDay(nearestExp, today.getUTCFullYear())}` : 'Expiring',
      tag: 'per leg',
      headline: expirySay,
      lines: expiringDetail.map((e) => e.say),
      foot: arriving > 0 ? `Average basis *${avgBasis.toFixed(2)}*` : null,
    } : null,

    holdback: calPenalty < 0 ? {
      label: 'Held back', action: `|${Math.abs(Math.round(calPenalty))} points|`,
      headline: (() => {
        if (!nextHeavy) return 'Event ahead';
        const short = String(nextHeavy.name ?? 'Event').split('\u00b7')[0].trim();
        const dd = daysBetween(today, parseISO(String(nextHeavy.event_date)));
        return dd <= 0 ? `${short} today` : dd === 1 ? `${short} tomorrow` : `${short} in ${dd} days`;
      })(),
      cause: `Conviction *${Math.round(base)} \u2192 ${conviction}*`,
      note: sliceSay,
    } : null,

    calls: {
      // The roll line comes FIRST when anything is in the money. Letting one assign is
      // the difference between 14,100 shares and 1,700, so it outranks the new write.
      label: !cs.enabled ? 'No calls' : dueToRoll.length ? 'Roll first' : 'Calls',
      lines: !cs.enabled
        ? [['^No calls while accumulating^', null], ['cost money and shares', 'in a rally']]
        : [
            ...(dueToRoll.length
              ? [[`|Roll ${dueToRoll.reduce((n, l) => n + l.ct, 0)} call${dueToRoll.reduce((n, l) => n + l.ct, 0) === 1 ? '' : 's'}|`,
                  `${fmtUsd(rollCost)} to keep the shares`] as [string, string | null]]
              : []),
            ...(callsWarranted > 0 && callStrike != null
              ? [[`^Sell ${callsWarranted} call${callsWarranted === 1 ? '' : 's'} at ${callStrike}^`,
                  `${Math.round(cs.coverage * 100)}% covered`] as [string, string | null]]
              : [['^Nothing to write^', 'at the coverage target'] as [string, string | null]]),
          ],
      note: !cs.enabled ? 'Trim delta by *writing fewer puts*'
        : dueToRoll.length
          ? '*Never let one assign.* Assigned, the overwrite ends at ~1,700 shares of 15,000'
          : cs.why,
    },

    why: {
      label: 'Why this size',
      chain: [
        { text: `${Math.round(chaseRate)}/wk \u00d7 ${priceFactor} (${priceBand}) \u00d7 ${cf.f} (conv ${conviction})`,
          out: `${Math.round(weeklyDelta)} weekly` },
        { text: `through ${DOWN[decisionDow].slice(0, 3)} that is ${Math.round((SLICE_CUM[decisionDow] ?? 1) * 100)}% of the week`,
          out: `${Math.round(weekToDate)} delta` },
        { text: writtenWeek > 0
            ? `less ${Math.round(writtenWeek)} written since Monday, at ${putDelta.toFixed(2)} delta`
            : `at ${putDelta.toFixed(2)} delta`,
          out: `${putCt} contract${putCt === 1 ? '' : 's'}` },
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
      // "7,500 assigned" was fullyAssigned = shares + pending, i.e. what you would
      // hold if every open put landed. With no puts open that equals what you already
      // hold, so the card announced an assignment that never happened. The pending
      // clause now appears only when something is actually pending.
      headline: pendingShares > 0
        ? `*${shares.toLocaleString()} shares* \u00b7 ^${pendingShares.toLocaleString()} more^ if the open puts land`
        : `*${shares.toLocaleString()} shares* \u00b7 ~no puts open, nothing due to arrive~`,
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
        String(e.name ?? ''),
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
          when: l.dir === 'long' ? `${fmtDay(l.expiry, today.getUTCFullYear())} \u00b7 the floor`
            : (l.type === 'put' ? spot! < l.strike : spot! > l.strike) ? 'in the money' : 'OTM',
        })),
      };
    })(),

    sources: {
      label: 'Freshness',
      rows: [
        ['Spot', spotLive != null ? 'live' : 'cached', spotLive != null ? 'now' : 'stale'],
        ['Chains', pick?.modelled ? 'modelled' : 'real quotes', expiry ? 'now' : 'no chain'],
        ['Closes', 'daily', closes.length ? fmtDay(closes[closes.length - 1].d) : 'none'],
        ['IV', 'daily', ivRows.length ? String((ivRows[0] as Row).date ?? '').slice(0, 10) : 'none'],
        ['Book', 'on sync', ageOf(lastSync)],
      ],
    },
  };

  emit(4);                                   // plan built: sizing, ceiling, the pick
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
      formula: '(shares still needed ÷ weeks left, capped at 2×) × price × conviction',
      chase: chasing
        ? `Behind: ${stillNeed.toLocaleString()} shares in ${Math.round(wkLeft)} weeks needs `
          + `*${Math.round(chaseRate)}/wk* against a ${Math.round(baseRate)} base`
          + (chaseRate >= 2 * baseRate * 0.99 ? ' — |held at the 2× cap|' : '')
        : `On rate. ${stillNeed.toLocaleString()} shares in ${Math.round(wkLeft)} weeks needs `
          + `~${Math.round(chaseRate)}/wk, at or under the ${Math.round(baseRate)} base`,
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
      earnings: nextEarn,


    },

    meta: {
      caps: CAPS,
      maBands: MA_BANDS.map((b) => ({ belowUnder: b[0], factor: b[1], label: b[2] })),
      convictionWeight: convWeight,
      phaseCalls: PHASE_CALLS, sliceWeights: SLICE, strikeStep: STRIKE_STEP,
      spec: 'docs/TLT_ACCUMULATION.md',
    },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  let wantsStream = false;
  try { wantsStream = !!(await req.clone().json())?.stream; } catch { /* no body is the normal case */ }
  if (!wantsStream) return await build(req, () => {});

  // NDJSON: one {"stage":n} line as each step actually resolves, then the payload.
  // The client cannot see inside a single atomic fetch, so without this the boot
  // layer could only ever run on a timer the data ignores.
  const enc = new TextEncoder();
  const stream = new ReadableStream({
    async start(c) {
      const line = (o: unknown) => c.enqueue(enc.encode(JSON.stringify(o) + '\n'));
      try {
        line({ stages: BOOT_STAGES });
        const res = await build(req, (n) => line({ stage: n }));
        line(await res.json());
      } catch (e) {
        line({ ok: false, error: String(e) });
      } finally {
        c.close();
      }
    },
  });
  return new Response(stream, {
    headers: { ...corsHeaders, 'Content-Type': 'application/x-ndjson', 'Cache-Control': 'no-store' },
  });
});
