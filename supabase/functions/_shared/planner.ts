// ── shared planner core ─────────────────────────────────────────────────────
// Everything tlt-planner and nvda-accumulate do IDENTICALLY. They were forks, 75%
// the same line for line, and that cost real money on 12 Aug 2026: the position
// netting bug was fixed in NVDA and lived on in TLT for hours because the fix had
// to be applied twice by hand. fmtDay had already drifted -- NVDA printed the year
// on a 2028 LEAP, TLT did not.
//
// What belongs here: anything with no ticker in it. Black-Scholes, dates, money
// formatting, the Polygon and Postgres clients, market state, the slice weights.
//
// What does NOT: strike step, IV fallback, the price/MA bands, conviction caps and
// weighting, the phase table, the copy. Those are what makes each engine its own,
// and pushing them in here would rebuild the monolith with extra steps.


export const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' };

export const json = (s: number, b: unknown) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

export const POLY = 'https://api.polygon.io';

export const FRED = 'https://api.stlouisfed.org/fred/series/observations';

export const FISCAL = 'https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v1/accounting/od/auctions_query';

export const R_FREE = 0.045;

// Mon/Wed/Fri each write a slice of the week. Friday's is smallest: it carries
// the weekend, and the weekend is when you cannot react.
export const SLICE: Record<number, number> = { 1: 0.40, 3: 0.40, 5: 0.20 };
// The same slices, accumulated. Sizing works against the week TO DATE rather than
// the isolated day, because whole-contract rounding on a lone slice throws away the
// remainder: at 63 delta a week, every slice lands near 0.47 contracts and rounds to
// zero, so the week writes NOTHING — while five hundredths of delta the other way
// rounds all three up and writes double. Carrying within the week makes the reachable
// output continuous instead of all-or-nothing. It resets each Monday, so a slow week
// never banks contracts into a fast one.

// The same slices, accumulated. Sizing works against the week TO DATE rather than
// the isolated day, because whole-contract rounding on a lone slice throws away the
// remainder: at 63 delta a week, every slice lands near 0.47 contracts and rounds to
// zero, so the week writes NOTHING — while five hundredths of delta the other way
// rounds all three up and writes double. Carrying within the week makes the reachable
// output continuous instead of all-or-nothing. It resets each Monday, so a slow week
// never banks contracts into a fast one.
export const SLICE_CUM: Record<number, number> = { 1: 0.40, 3: 0.80, 5: 1.00 };

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

// ── Black-Scholes (single clock) ────────────────────────────────────────────
export function ncdf(x: number): number {
  const a1 = .254829592, a2 = -.284496736, a3 = 1.421413741, a4 = -1.453152027, a5 = 1.061405429, p = .3275911;
  const s = x < 0 ? -1 : 1, z = Math.abs(x) / Math.SQRT2, t = 1 / (1 + p * z);
  const y = 1 - ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * Math.exp(-z * z);
  return .5 * (1 + s * y);
}

export function d1of(S: number, K: number, T: number, v: number): number {
  return (Math.log(S / K) + (R_FREE + v * v / 2) * T) / (v * Math.sqrt(T));
}
/** |delta| of a put. Short put is +this much delta; long put is −this much. */

export function putDeltaAbs(S: number, K: number, T: number, v: number): number {
  if (T <= 0 || v <= 0) return S < K ? 1 : 0;
  return ncdf(-d1of(S, K, T, v));
}

export function callDelta(S: number, K: number, T: number, v: number): number {
  if (T <= 0 || v <= 0) return S > K ? 1 : 0;
  return ncdf(d1of(S, K, T, v));
}

// ── small numerics ──────────────────────────────────────────────────────────

// ── small numerics ──────────────────────────────────────────────────────────
export const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));

export const fin = (x: number) => (Number.isFinite(x) ? x : 0);

export const num = (x: unknown): number | null => {
  const n = Number(x);
  return Number.isFinite(n) ? n : null;
};

export function mean(xs: number[]): number { return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0; }

export function sd(xs: number[]): number {
  if (xs.length < 2) return 0;
  const m = mean(xs);
  return Math.sqrt(xs.reduce((a, b) => a + (b - m) * (b - m), 0) / (xs.length - 1));
}
/** Where v sits in xs, 0–1. The percentile is the point of `real`: a level means
 *  nothing without the history it is a level against. */

export function pctRank(xs: number[], v: number): number {
  if (!xs.length) return 0.5;
  return xs.filter((x) => x <= v).length / xs.length;
}

// ── dates ───────────────────────────────────────────────────────────────────

// ── dates ───────────────────────────────────────────────────────────────────
export const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

export const DOWN = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

export function ymd(d: Date): string {
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
}

export function parseISO(s: string): Date { const [y, m, d] = String(s).slice(0, 10).split('-').map(Number); return new Date(Date.UTC(y, m - 1, d)); }

export function addDays(d: Date, n: number): Date { const x = new Date(d.getTime()); x.setUTCDate(x.getUTCDate() + n); return x; }

export function daysBetween(a: Date, b: Date): number { return Math.round((b.getTime() - a.getTime()) / 86400000); }
// ── market state ────────────────────────────────────────────────────────────
// Read off the exchange's own clock via the IANA zone, not a hardcoded UTC offset:
// New York is UTC-4 half the year and UTC-5 the other half, and a fixed offset is
// wrong for one of them. Holidays are NOT handled — the NYSE calendar is not
// derivable, so Thanksgiving reads "Live" until a holiday table exists.
// Polygon knows the exchange calendar -- holidays, half-days, early closes -- which a
// clock cannot derive. The clock version below stays as the fallback: if this call
// fails or the plan does not cover it, a wrong label is better than a dead screen.

// ── market state ────────────────────────────────────────────────────────────
// Read off the exchange's own clock via the IANA zone, not a hardcoded UTC offset:
// New York is UTC-4 half the year and UTC-5 the other half, and a fixed offset is
// wrong for one of them. Holidays are NOT handled — the NYSE calendar is not
// derivable, so Thanksgiving reads "Live" until a holiday table exists.
// Polygon knows the exchange calendar -- holidays, half-days, early closes -- which a
// clock cannot derive. The clock version below stays as the fallback: if this call
// fails or the plan does not cover it, a wrong label is better than a dead screen.
export async function marketNow(key: string): Promise<{ open: boolean; label: string } | null> {
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

// The trading day is NEW YORK's, not UTC's. ymd(new Date()) rolls over at midnight
// UTC — 8pm ET on daylight time — so for four hours every evening the engines were a
// calendar day ahead of the market they price. It showed as "30-year today" on the
// Wednesday evening before a Thursday auction, and it moved every date comparison in
// both engines with it: the event calendar, the expiry filter, the week-start.
export function nyToday(): string {
  const p = Object.fromEntries(
    new Intl.DateTimeFormat('en-CA', {
      timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit',
    }).formatToParts(new Date()).map((x) => [x.type, x.value]),
  );
  return `${p.year}-${p.month}-${p.day}`;
}

export function marketState(now: Date): { open: boolean; label: string } {
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

export const fmtDay = (iso: string, thisYear?: number) => {
  const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number);
  if (!(y && m && d)) return String(iso);
  // The year appears only when it is NOT the current one, so the common case stays
  // short — but a Dec 2028 LEAP must never render as "Dec 15" beside a Sep 18 weekly.
  return thisYear != null && y !== thisYear ? `${MONTHS[m - 1]} ${d} ${y}` : `${MONTHS[m - 1]} ${d}`;
};

export const fmtUsd = (v: number) => {
  const sign = v < 0 ? '−' : '';
  const a = Math.abs(v);
  // Auction sizes are tens of billions. Without this branch supply reads "$67000M".
  if (a >= 1_000_000_000) return `${sign}$${(a / 1_000_000_000).toFixed(a >= 10_000_000_000 ? 0 : 1)}B`;
  if (a >= 1_000_000) return `${sign}$${(a / 1_000_000).toFixed(a >= 10_000_000 ? 0 : 1)}M`;
  if (a >= 1000) return `${sign}$${Math.round(a / 1000)}K`;
  return `${sign}$${Math.round(a)}`;
};

export function quarterStart(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), Math.floor(d.getUTCMonth() / 3) * 3, 1));
}

// ── Supabase REST ───────────────────────────────────────────────────────────

// ── Supabase REST ───────────────────────────────────────────────────────────
export type Row = Record<string, unknown>;

export function db(url: string, key: string) {
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

// ── Polygon: daily closes, for MA100 and realised vol ─────────────────────
export async function dailyCloses(ticker: string, key: string, fromISO: string, toISO: string): Promise<Array<{ d: string; c: number }>> {
  try {
    const r = await fetch(`${POLY}/v2/aggs/ticker/${ticker}/range/1/day/${fromISO}/${toISO}`
      + `?adjusted=true&sort=asc&limit=50000&apiKey=${key}`);
    if (!r.ok) return [];
    const j = await r.json() as { results?: Array<Record<string, number>> };
    return (j?.results ?? []).map((x) => ({ d: new Date(x.t).toISOString().slice(0, 10), c: x.c }));
  } catch { return []; }
}

// ── Polygon ─────────────────────────────────────────────────────────────────

// ── Polygon ─────────────────────────────────────────────────────────────────
export async function spotOf(ticker: string, key: string): Promise<number | null> {
  try {
    const r = await fetch(`${POLY}/v3/snapshot/options/${ticker}?limit=1&apiKey=${key}`);
    if (!r.ok) return null;
    const j = await r.json() as { results?: Array<{ underlying_asset?: { price?: number } }> };
    return num((j?.results ?? [])[0]?.underlying_asset?.price);
  } catch { return null; }
}

export async function putExpiries(ticker: string, fromISO: string, key: string): Promise<string[]> {
  try {
    const r = await fetch(`${POLY}/v3/reference/options/contracts?underlying_ticker=${ticker}&contract_type=put`
      + `&expiration_date.gte=${fromISO}&expired=false&limit=1000&sort=expiration_date&order=asc&apiKey=${key}`);
    if (!r.ok) return [];
    const j = await r.json() as { results?: Array<{ expiration_date?: string }> };
    const set: string[] = [];
    for (const c of j?.results ?? []) if (c.expiration_date && !set.includes(c.expiration_date)) set.push(c.expiration_date);
    return set;
  } catch { return []; }
}

export type Quote = { strike: number; bid: number; ask: number; mid: number; delta: number | null; oi: number };

export async function chain(ticker: string, kind: 'put' | 'call', expiry: string, lo: number, hi: number, key: string): Promise<Quote[]> {
  const out: Quote[] = [];
  try {
    const r = await fetch(`${POLY}/v3/snapshot/options/${ticker}?expiration_date=${expiry}`
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
