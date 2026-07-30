/**
 * nvda-iv — NVDA ATM-30d implied-volatility feed for the Seller Score.
 *
 *   • cron (default): read the CURRENT ATM-30d call IV from Polygon's option
 *     snapshot and upsert today's row into public.nvda_iv_daily. Run every
 *     30 min during market hours. The iOS app reads the freshest nvda_iv_daily
 *     row as "current IV" and ranks it against the history for the percentile.
 *
 *   • {"trigger":"backfill", "from":"YYYY-MM-DD", "to":"YYYY-MM-DD"}:
 *     Polygon has NO historical-IV endpoint, so we RECONSTRUCT it: for each
 *     trading day D we find that day's ATM-30d call, pull its historical close,
 *     and solve Black-Scholes for the implied vol. Upserts one nvda_iv_daily
 *     row per day. Capped per run (BACKFILL_CAP days) and returns `next_to` so
 *     the caller can loop older ranges. Idempotent (upsert on ticker,date).
 *     Defaults: to = today, from = today − 365d.
 *
 * Secret: POLYGON_API_KEY (same key mp-refresh / ticker-iv-snapshot use).
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' };
const json = (s: number, b: unknown) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

const POLY = 'https://api.polygon.io';
const R = 0.043;              // risk-free rate (annualized)
const Q = 0.0;               // NVDA dividend yield ≈ 0
const TARGET_DTE = 30;
const DTE_LO = 20, DTE_HI = 45;   // acceptable expiry window
const STRIKE_PCT = 0.06;          // ATM strike within ±6% of spot
const BACKFILL_CAP = 130;         // max trading days per invocation

// ── Black-Scholes + implied-vol solver ──────────────────────────
function normCdf(x: number): number {
  // Abramowitz & Stegun 7.1.26
  const t = 1 / (1 + 0.2316419 * Math.abs(x));
  const d = 0.3989422804014327 * Math.exp(-x * x / 2);
  let p = d * t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
  p = 1 - p;
  return x >= 0 ? p : 1 - p;
}
function bsCall(S: number, K: number, T: number, sig: number): number {
  if (T <= 0 || sig <= 0) return Math.max(0, S - K);
  const d1 = (Math.log(S / K) + (R - Q + sig * sig / 2) * T) / (sig * Math.sqrt(T));
  const d2 = d1 - sig * Math.sqrt(T);
  return S * Math.exp(-Q * T) * normCdf(d1) - K * Math.exp(-R * T) * normCdf(d2);
}
/** Solve for σ given a call price via bisection. null if price is below intrinsic. */
function impliedVol(C: number, S: number, K: number, T: number): number | null {
  const intrinsic = Math.max(0, S * Math.exp(-Q * T) - K * Math.exp(-R * T));
  if (C <= intrinsic + 1e-6 || T <= 0) return null;
  let lo = 0.001, hi = 5.0, mid = 0.5;
  for (let i = 0; i < 100; i++) {
    mid = (lo + hi) / 2;
    const p = bsCall(S, K, T, mid);
    if (Math.abs(p - C) < 1e-4) return mid;
    if (p > C) hi = mid; else lo = mid;
  }
  return mid;
}

const ymd = (d: Date) => d.toISOString().slice(0, 10);
const addDays = (d: Date, n: number) => new Date(d.getTime() + n * 86400000);

interface Contract { ticker: string; strike_price: number; expiration_date: string; contract_type: string }

/** Pick the ATM-30d call from a candidate list, given spot and the as-of date. */
function pickAtm(cands: Contract[], spot: number, asOf: Date): Contract | null {
  let best: Contract | null = null, bestScore = Infinity;
  for (const c of cands) {
    if (c.contract_type !== 'call') continue;
    const dte = Math.round((new Date(c.expiration_date + 'T16:00:00Z').getTime() - asOf.getTime()) / 86400000);
    if (dte < DTE_LO || dte > DTE_HI) continue;
    const sd = Math.abs(c.strike_price - spot) / spot;
    if (sd > STRIKE_PCT) continue;
    const score = Math.abs(dte - TARGET_DTE) * 2 + sd * 100;
    if (score < bestScore) { bestScore = score; best = c; }
  }
  return best;
}

async function fetchContracts(tk: string, spot: number, asOf: string, key: string, expired: boolean): Promise<Contract[]> {
  const lo = (spot * (1 - STRIKE_PCT)).toFixed(2), hi = (spot * (1 + STRIKE_PCT)).toFixed(2);
  const expFrom = ymd(addDays(new Date(asOf + 'T00:00:00Z'), DTE_LO));
  const expTo = ymd(addDays(new Date(asOf + 'T00:00:00Z'), DTE_HI));
  // No `as_of`: the expiration window + strike window already pinpoint the
  // ATM-30d contract for day D. We DON'T know if that contract is expired yet
  // (recent days' 30-DTE contracts are still active), so the caller queries
  // BOTH expired and active and merges.
  const url = `${POLY}/v3/reference/options/contracts?underlying_ticker=${tk}`
    + `&contract_type=call&expired=${expired}`
    + `&expiration_date.gte=${expFrom}&expiration_date.lte=${expTo}`
    + `&strike_price.gte=${lo}&strike_price.lte=${hi}&limit=250&apiKey=${key}`;
  const r = await fetch(url);
  if (!r.ok) return [];
  return ((await r.json())?.results ?? []) as Contract[];
}
/** Candidate ATM-30d calls for `asOf`, robust to whether they've expired yet. */
async function contractsAsOf(tk: string, spot: number, asOf: string, key: string): Promise<Contract[]> {
  const [exp, act] = await Promise.all([
    fetchContracts(tk, spot, asOf, key, true),
    fetchContracts(tk, spot, asOf, key, false),
  ]);
  const seen = new Set<string>(); const out: Contract[] = [];
  for (const c of [...act, ...exp]) if (!seen.has(c.ticker)) { seen.add(c.ticker); out.push(c); }
  return out;
}

/** Upsert one NVDA IV row. iv stored as a decimal (0.48 = 48%). `date` is the PK. */
async function upsertIv(admin: ReturnType<typeof createClient>, date: string, iv: number, source: string) {
  await admin.from('nvda_iv_daily').upsert({ ticker: 'NVDA', date, iv, source }, { onConflict: 'date' });
}

// ── live: current ATM-30d IV from the snapshot ──────────────────
async function live(admin: ReturnType<typeof createClient>, key: string) {
  const today = ymd(new Date());
  // spot from nvda_quote (freshest), else Polygon
  let spot: number | null = null;
  const { data: q } = await admin.from('nvda_quote').select('spot').eq('ticker', 'NVDA').maybeSingle();
  spot = (q as { spot?: number } | null)?.spot ?? null;
  if (!spot) {
    const r = await fetch(`${POLY}/v2/snapshot/locale/us/markets/stocks/tickers/NVDA?apiKey=${key}`);
    if (r.ok) { const t = (await r.json())?.ticker; spot = t?.lastTrade?.p ?? t?.day?.c ?? null; }
  }
  if (!spot) return json(200, { ok: false, error: 'no spot' });

  const cands = await contractsAsOf('NVDA', spot, today, key, false);
  const picked = pickAtm(cands, spot, new Date());
  if (!picked) return json(200, { ok: false, error: 'no ATM-30d contract' });

  const sr = await fetch(`${POLY}/v3/snapshot/options/NVDA/${picked.ticker}?apiKey=${key}`);
  const iv = sr.ok ? ((await sr.json())?.results?.implied_volatility ?? null) : null;
  if (iv == null) return json(200, { ok: false, error: 'no IV in snapshot', contract: picked.ticker });

  await upsertIv(admin, today, iv, 'cron');
  return json(200, { ok: true, date: today, iv, contract: picked.ticker, spot });
}

// ── backfill: reconstruct daily IV via Black-Scholes ────────────
async function backfill(admin: ReturnType<typeof createClient>, key: string, from: string, to: string) {
  // one aggregates call for NVDA daily closes across the whole range
  const aggUrl = `${POLY}/v2/aggs/ticker/NVDA/range/1/day/${from}/${to}?adjusted=true&sort=desc&limit=400&apiKey=${key}`;
  const ar = await fetch(aggUrl);
  if (!ar.ok) return json(500, { ok: false, error: `NVDA aggs ${ar.status}` });
  const bars = (((await ar.json())?.results ?? []) as { t: number; c: number }[])
    .map((b) => ({ date: ymd(new Date(b.t)), close: b.c }));   // newest → oldest

  const out: { date: string; iv: number | null; note?: string }[] = [];
  let processed = 0;
  for (const bar of bars) {
    if (processed >= BACKFILL_CAP) break;
    processed++;
    const asOf = new Date(bar.date + 'T16:00:00Z');
    try {
      const cands = await contractsAsOf('NVDA', bar.close, bar.date, key);
      // Rank ALL in-window ATM calls; a single strike is often illiquid, so we
      // walk candidates closest-to-ATM first and use the first that actually
      // traded (has a daily bar) near D. NVDA is liquid enough that one of the
      // top few always has a close.
      const ranked = cands
        .filter((c) => c.contract_type === 'call')
        .map((c) => {
          const dte = Math.round((new Date(c.expiration_date + 'T16:00:00Z').getTime() - asOf.getTime()) / 86400000);
          const sd = Math.abs(c.strike_price - bar.close) / bar.close;
          return { c, dte, sd, score: Math.abs(dte - TARGET_DTE) * 2 + sd * 100 };
        })
        .filter((x) => x.dte >= DTE_LO && x.dte <= DTE_HI && x.sd <= STRIKE_PCT)
        .sort((a, b) => a.score - b.score);
      if (ranked.length === 0) { out.push({ date: bar.date, iv: null, note: 'no contract' }); continue; }

      const from6 = ymd(addDays(asOf, -6));
      let iv: number | null = null;
      for (const { c } of ranked.slice(0, 8)) {
        const oc = await fetch(`${POLY}/v2/aggs/ticker/${c.ticker}/range/1/day/${from6}/${bar.date}?adjusted=true&sort=desc&limit=6&apiKey=${key}`);
        const ob = oc.ok ? (((await oc.json())?.results ?? []) as { t: number; c: number }[]) : [];
        if (ob.length === 0) continue;
        const optDate = new Date(ob[0].t);
        const T = (new Date(c.expiration_date + 'T16:00:00Z').getTime() - optDate.getTime()) / (365 * 86400000);
        const solved = impliedVol(ob[0].c, bar.close, c.strike_price, T);
        if (solved != null) { iv = solved; break; }
      }
      if (iv == null) { out.push({ date: bar.date, iv: null, note: 'no liquid close' }); continue; }
      await upsertIv(admin, bar.date, iv, 'backfill');
      out.push({ date: bar.date, iv: Math.round(iv * 10000) / 10000 });
    } catch (e) {
      out.push({ date: bar.date, iv: null, note: e instanceof Error ? e.message : String(e) });
    }
  }
  const oldest = bars.length ? bars[Math.min(processed, bars.length) - 1]?.date : to;
  const next_to = processed >= BACKFILL_CAP && oldest ? ymd(addDays(new Date(oldest + 'T00:00:00Z'), -1)) : null;
  const solved = out.filter((o) => o.iv != null).length;
  return json(200, { ok: true, from, to, processed, solved, next_to, sample: out.slice(0, 8) });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const url = Deno.env.get('SUPABASE_URL')!;
  const svc = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const key = Deno.env.get('POLYGON_API_KEY');
  if (!key) return json(500, { ok: false, error: 'POLYGON_API_KEY not set' });
  const admin = createClient(url, svc, { auth: { autoRefreshToken: false, persistSession: false } });

  const body = await req.json().catch(() => ({})) as { trigger?: string; from?: string; to?: string };
  if (body.trigger === 'backfill') {
    const to = body.to ?? ymd(new Date());
    const from = body.from ?? ymd(addDays(new Date(), -365));
    return backfill(admin, key, from, to);
  }
  return live(admin, key);
});
