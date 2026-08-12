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

// Conviction is the trim. Stepped, per spec — see the cliff note in the payload.
function convFactor(score: number): { f: number; band: string } {
  if (score <= 30) return { f: 0.7, band: '0–30' };
  if (score <= 70) return { f: 1.0, band: '31–70' };
  return { f: 1.3, band: '71–100' };
}

// The call side is a function of the PHASE, not the ticker. HARVEST is the only
// phase that inherits NVDA's ATM result, because it is the only one where the
// intention matches: monetising a block you are content to lose.
const PHASE_CALLS: Record<string, { delta: number; coverage: number; why: string }> = {
  ACCUMULATE: { delta: 0.15, coverage: 0.20, why: 'trim delta — a call caps shares you are paying to acquire' },
  HOLD:       { delta: 0.25, coverage: 0.50, why: 'earn income on a block that has stopped growing' },
  HARVEST:    { delta: 0.50, coverage: 1.00, why: 'exit — assignment is the point' },
};

// Mon/Wed/Fri each write a slice of the week. Friday's is smallest: it carries
// the weekend, and the weekend is when you cannot react.
const SLICE: Record<number, number> = { 1: 0.40, 3: 0.40, 5: 0.20 };

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
      D.get('tlt_option_trades?voided_at=is.null&select=id,action,option_type,direction,contracts,strike,premium,expiry,closes_trade_id'),
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
  const putDeltaTgt = Number(st.put_delta_tgt ?? 0.45);

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
    F.push(fam('print', 'Inflation vs priced', CAPS.print,
      gap == null ? null : clamp((gap + 1.0) / 2.0, 0, 1),
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

  type Leg = { type: string; dir: string; ct: number; strike: number; expiry: string; delta: number; shares: number };
  const legs: Leg[] = open.map((t) => {
    const ct = fin(Number(t.contracts));
    const K = fin(Number(t.strike));
    const T = Math.max(daysBetween(today, parseISO(String(t.expiry))), 0) / 365;
    const isPut = String(t.option_type) === 'put';
    const short = String(t.direction) === 'short';
    const mag = isPut ? putDeltaAbs(spot!, K, T, iv) : callDelta(spot!, K, T, iv);
    // short put = +delta · short call = −delta · long put (the floor) = −delta
    const signed = isPut ? (short ? mag : -mag) : (short ? -mag : mag);
    return { type: String(t.option_type), dir: String(t.direction), ct, strike: K, expiry: String(t.expiry).slice(0, 10), delta: signed, shares: signed * ct * 100 };
  });

  const shortPuts = legs.filter((l) => l.type === 'put' && l.dir === 'short');
  const longPuts = legs.filter((l) => l.type === 'put' && l.dir === 'long');
  const shortCalls = legs.filter((l) => l.type === 'call' && l.dir === 'short');
  const optDelta = legs.reduce((s, l) => s + l.shares, 0);
  const netDelta = shares + optDelta;

  // A short put is a commitment to buy, never income. Every unexpired one counts,
  // not just this week's.
  const outstanding = shortPuts.reduce((s, l) => s + l.strike * 100 * l.ct, 0);
  const pendingShares = shortPuts.reduce((s, l) => s + l.ct * 100, 0);
  const fullyAssigned = shares + pendingShares;
  const floorCoverage = fullyAssigned > 0 ? (longPuts.reduce((s, l) => s + l.ct * 100, 0) / fullyAssigned) : 0;

  // ── sizing ───────────────────────────────────────────────────────────────
  const band = PRICE_BANDS.find(([hi]) => spot! < hi) ?? PRICE_BANDS[0];
  const priceFactor = band[1], priceBand = band[2];
  const cf = convFactor(conviction);
  const weeklyDelta = (quarterBudget / 13) * priceFactor * cf.f;

  const dow = today.getUTCDay();
  const decisionDow = SLICE[dow] != null ? dow : (dow === 0 || dow === 6 ? 1 : dow < 3 ? 3 : dow < 5 ? 5 : 1);
  const sliceW = SLICE[decisionDow];
  const sliceDelta = weeklyDelta * sliceW;
  const isDecisionDay = SLICE[dow] != null;

  // ── the put pick ─────────────────────────────────────────────────────────
  const expiries = await putExpiries(ymd(addDays(today, 2)), polyKey);
  const expiry = expiries[0] ?? null;
  let putQuotes: Quote[] = [];
  if (expiry) putQuotes = await chain('put', expiry, Math.floor(spot * 0.92), Math.ceil(spot * 1.04), polyKey);

  const Tput = expiry ? Math.max(daysBetween(today, parseISO(expiry)), 0) / 365 : 0;
  const withDelta = putQuotes.map((q) => ({
    ...q,
    dAbs: q.delta != null ? Math.abs(q.delta) : putDeltaAbs(spot!, q.strike, Tput, iv),
    modelled: q.delta == null,
  }));
  const pick = withDelta.length
    ? withDelta.reduce((a, b) => Math.abs(a.dAbs - putDeltaTgt) <= Math.abs(b.dAbs - putDeltaTgt) ? a : b)
    : null;

  const putStrike = pick?.strike ?? Math.round((spot * 0.99) / STRIKE_STEP) * STRIKE_STEP;
  const putDelta = pick?.dAbs ?? putDeltaTgt;
  const putMid = pick?.mid ?? 0;

  const wantCt = putDelta > 0 ? Math.max(0, Math.round(sliceDelta / (putDelta * 100))) : 0;
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
  const callsWarranted = phase === 'ACCUMULATE'
    ? (putCt === 0 && deltaOver > 200 ? Math.min(coverRoom, Math.floor(deltaOver / (cs.delta * 100))) : 0)
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
  };
  if (!body.dry_run) {
    await D.upsert('tlt_planner_factor_daily', [{
      taken_on: todayISO, phase, spot, conviction, families: F, sizing,
    }], 'taken_on');
  }

  return json(200, {
    ok: true,
    asof: todayISO,
    day: DOWN[dow],
    isDecisionDay,
    spot,
    iv,

    phase: {
      state: phase,
      calls: cs.why,
      note: phase === 'ACCUMULATE'
        ? 'Puts do the work. Calls are the last lever, not the first.'
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
      cliff: 'Stepped per spec: a 1-point move across 30 or 70 swings size ~30%. Smooth ramp available.',
    },

    sizing: {
      ...sizing,
      quarterBudget,
      perWeek: Math.round(quarterBudget / 13),
      slice: sliceW,
      sliceOf: DOWN[decisionDow],
      formula: '(quarter budget ÷ 13) × price × conviction',
    },

    ceiling: {
      limit: cashCeiling,
      outstanding: Math.round(outstanding),
      headroom: Math.round(headroom),
      binds: ceilingBinds,
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
        say: callsWarranted > 0 && callStrike != null
          ? `Sell ${callsWarranted} call${callsWarranted === 1 ? '' : 's'} at ${callStrike}.`
          : phase === 'ACCUMULATE' ? 'No calls — the put side is doing the work.' : 'No calls warranted.',
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
