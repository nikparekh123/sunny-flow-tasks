/**
 * bnf-scan — daily BNF/Kotegawa mean-reversion scanner.
 *
 * Reads a sibling universe.json (~1000 tickers covering the full S&P
 * MidCap 400 + SmallCap 600), pulls Polygon day aggregates for each,
 * computes SMA25 / SMA200 / 20-day ADV / today's intraday move, and
 * filters per the strategy:
 *
 *   • Deviation from SMA25 ∈ [-15%, -7%]      (dislocated but not collapsing)
 *   • Close > SMA200                          (still in long-term uptrend)
 *   • Today's intraday > -5%                  (not catching a knife today)
 *   • Sector ETF dev > -5% vs its own SMA25   (idiosyncratic, not sector-wide)
 *   • [skipped in v1] Earnings ≥ 3 trading days out
 *
 * For survivors we pull an options snapshot for risk context (IV30, OI,
 * volume, P/C ratio). IV rank is null in v1 — needs 252-day IV history
 * we don't currently store.
 *
 * Result is written to public.bnf_candidates, replacing the user's
 * previous scan (delete-then-insert).
 *
 * Required secrets:
 *   POLYGON_API_KEY
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (for the delete-then-insert)
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
// Universe lives in a sibling .ts module — ~1000 tickers covering the
// full S&P MidCap 400 + SmallCap 600. Edit universe.ts to grow/shrink
// the list, then redeploy. We use .ts (not .json) because Supabase's
// Deno runtime doesn't support JSON-import attributes yet.
import { UNIVERSE, type UniverseEntry } from './universe.ts';
import { ETF_UNIVERSE } from './etf-universe.ts';
import {
  cikFor, fetchRecentFilings, extract8Ks, fetchInsiderActivity,
  daysSinceFromTradingDays,
  type Item8K, type InsiderActivity,
} from './edgar.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Distinct sector ETFs we need to pre-fetch (~11) so we can compute each
// candidate's "is my sector also dumping?" guard.
const SECTOR_ETFS = Array.from(new Set(UNIVERSE.map((u: UniverseEntry) => u.sectorEtf)));

// ── Filter thresholds (per BNF/Kotegawa spec) ──
const DEV_MIN = -15;      // deviation% must be ≥ this (i.e. less negative than −15%)
const DEV_MAX = -7;       // and ≤ this (more negative than −7%)
const TODAY_INTRADAY_FLOOR = -5;
const SECTOR_DEV_FLOOR = -5;
const MIN_ADV_M = 20;     // $20M 20-day avg dollar volume
const MIN_PRICE = 10;

interface Agg { c: number; o: number; v: number; }

/** Aggregates now come from the bnf_universe_data CACHE, not from
 *  Polygon. The cache is populated by bnf-cache-backfill (one-time +
 *  manual) and bnf-cache-update (nightly cron). Scan reads in
 *  milliseconds instead of 999 Polygon calls per scan. */
async function fetchAggsBars(
  admin: Admin, ticker: string, fromIso: string, toIso: string,
): Promise<Agg[]> {
  const { data } = await admin
    .from('bnf_universe_data')
    .select('open, close, volume, date')
    .eq('ticker', ticker)
    .gte('date', fromIso)
    .lte('date', toIso)
    .order('date', { ascending: true });
  type Row = { open: number; close: number; volume: number; date: string };
  return ((data ?? []) as Row[]).map((r) => ({
    c: Number(r.close),
    o: Number(r.open),
    v: Number(r.volume),
  }));
}

/** Bulk read — pulls ALL rows for a list of tickers in one query.
 *  Used by the equity scan's main loop so we don't do 999 separate
 *  selects. Returns a Map<ticker, Array<Agg>>. */
async function fetchAggsBulk(
  admin: Admin, tickers: string[], fromIso: string, toIso: string,
): Promise<Map<string, Agg[]>> {
  const out = new Map<string, Agg[]>();
  if (tickers.length === 0) return out;
  // Supabase limits .in() to ~1k values; we chunk to be safe.
  const CHUNK = 500;
  for (let i = 0; i < tickers.length; i += CHUNK) {
    const slice = tickers.slice(i, i + CHUNK);
    const { data } = await admin
      .from('bnf_universe_data')
      .select('ticker, open, close, volume, date')
      .in('ticker', slice)
      .gte('date', fromIso)
      .lte('date', toIso)
      .order('date', { ascending: true });
    type Row = { ticker: string; open: number; close: number; volume: number; date: string };
    for (const r of (data ?? []) as Row[]) {
      const arr = out.get(r.ticker) ?? [];
      arr.push({ c: Number(r.close), o: Number(r.open), v: Number(r.volume) });
      out.set(r.ticker, arr);
    }
  }
  return out;
}

function sma(closes: number[], n: number): number | null {
  if (closes.length < n) return null;
  const slice = closes.slice(closes.length - n);
  return slice.reduce((s, x) => s + x, 0) / n;
}

function adv20Millions(rows: Agg[]): number | null {
  if (rows.length < 20) return null;
  const slice = rows.slice(-20);
  let dollars = 0;
  for (const b of slice) dollars += (b.c ?? 0) * (b.v ?? 0);
  return dollars / 20 / 1_000_000;
}

interface OptionsContract {
  details?: { contract_type?: string; expiration_date?: string; strike_price?: number };
  implied_volatility?: number;
  open_interest?: number;
  day?: { volume?: number };
}
interface OptionsResp { results?: OptionsContract[]; }

interface OptionsContext {
  iv30: number | null;
  options_volume: number;
  put_call_ratio: number | null;
  open_interest: number;
}

/** Best-effort metadata lookup via Yahoo's public quoteSummary endpoint.
 *  No API key required; we set a browser-style User-Agent because Yahoo
 *  blocks the default Deno UA. Returns:
 *    - daysToEarnings — trading days to next earnings (positive = future,
 *      negative = past, null = unknown). Calendar days × 5/7 since the
 *      BNF spec measures windows in market sessions.
 *    - name — short company name (e.g. "Five Below, Inc.").
 *  Both modules come in one HTTP round-trip. */
interface YahooCtx {
  daysToEarnings: number | null;
  name: string | null;
}
async function fetchYahooCtx(ticker: string): Promise<YahooCtx> {
  try {
    const url = `https://query1.finance.yahoo.com/v10/finance/quoteSummary/${ticker}?modules=calendarEvents,price`;
    const res = await fetch(url, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; BNFScanner/1.0)' },
    });
    if (!res.ok) return { daysToEarnings: null, name: null };
    const j = await res.json() as {
      quoteSummary?: {
        result?: Array<{
          calendarEvents?: {
            earnings?: { earningsDate?: Array<{ raw?: number }> };
          };
          price?: {
            shortName?: string;
            longName?: string;
          };
        }>;
      };
    };
    const node = j?.quoteSummary?.result?.[0];

    let daysToEarnings: number | null = null;
    const raw = node?.calendarEvents?.earnings?.earningsDate?.[0]?.raw;
    if (typeof raw === 'number') {
      const calDays = (raw * 1000 - Date.now()) / 86400000;
      daysToEarnings = Math.round(calDays * 5 / 7);
    }

    const name = node?.price?.shortName ?? node?.price?.longName ?? null;

    return { daysToEarnings, name };
  } catch {
    return { daysToEarnings: null, name: null };
  }
}

/** Bundle the two SEC EDGAR pulls per ticker: one submissions fetch +
 *  any subsequent Form 4 XML fetches share the same filings list. */
async function fetchEdgarFlags(ticker: string): Promise<{ insider: InsiderActivity; eightKs: Item8K[] }> {
  const cik = await cikFor(ticker);
  if (!cik) {
    return {
      insider: { sellers_count: 0, total_sold_usd: 0, details: [] },
      eightKs: [],
    };
  }
  const filings = await fetchRecentFilings(cik);
  // 8-K: walk filings in last 14 cal days (≈ 10 trading days)
  const eightKs = extract8Ks(filings, 14, cik);
  // Form 4: 14 cal days per spec; insider parsing fetches one XML per filing
  const insider = await fetchInsiderActivity(cik, filings, 14);
  return { insider, eightKs };
}

async function fetchOptionsCtx(ticker: string, spot: number, key: string): Promise<OptionsContext> {
  // Polygon options snapshot — one page of contracts (typically 50–250).
  // Good enough for an aggregate view; we don't need every contract.
  const url = `https://api.polygon.io/v3/snapshot/options/${ticker}?limit=250&apiKey=${key}`;
  let contracts: OptionsContract[] = [];
  try {
    const res = await fetch(url);
    if (res.ok) {
      const j: OptionsResp = await res.json();
      contracts = j.results ?? [];
    }
  } catch { /* ignore — option data is optional */ }

  if (contracts.length === 0) {
    return { iv30: null, options_volume: 0, put_call_ratio: null, open_interest: 0 };
  }

  let callVol = 0, putVol = 0, oi = 0;
  // Find nearest-the-money call within the nearest expiry for IV30 proxy.
  let bestIVPick: { iv: number; expiryDist: number; strikeDist: number } | null = null;
  const today = Date.now();
  for (const c of contracts) {
    const vol = c.day?.volume ?? 0;
    oi += c.open_interest ?? 0;
    const type = c.details?.contract_type;
    if (type === 'call') callVol += vol;
    else if (type === 'put') putVol += vol;
    if (type === 'call' && c.implied_volatility && c.details?.expiration_date && c.details?.strike_price) {
      const expMs = new Date(c.details.expiration_date + 'T00:00:00Z').getTime();
      const expDist = (expMs - today) / 86400000;
      if (expDist <= 0) continue;
      const strikeDist = Math.abs(c.details.strike_price - spot) / spot;
      // Prefer ~30 DTE near-the-money; weight expiry distance higher.
      const score = Math.abs(expDist - 30) + strikeDist * 50;
      if (!bestIVPick || score < bestIVPick.expiryDist + bestIVPick.strikeDist * 50) {
        bestIVPick = { iv: c.implied_volatility, expiryDist: Math.abs(expDist - 30), strikeDist };
      }
    }
  }

  return {
    iv30: bestIVPick?.iv ?? null,
    options_volume: callVol + putVol,
    put_call_ratio: callVol > 0 ? putVol / callVol : null,
    open_interest: oi,
  };
}

interface TickerResult {
  ticker: string;
  sector: string;
  sectorEtf: string;
  price: number;
  sma25: number;
  sma200: number;
  deviation_pct: number;
  adv20_m: number;
  today_intraday_pct: number;
}

function processOneFromCache(u: UniverseEntry, aggs: Agg[]): TickerResult | null {
  if (aggs.length < 200) return null;
  const closes = aggs.map((a) => a.c);
  const sma25 = sma(closes, 25);
  const sma200 = sma(closes, 200);
  const adv = adv20Millions(aggs);
  const last = aggs[aggs.length - 1];
  if (!sma25 || !sma200 || !adv || !last) return null;
  if (last.c < MIN_PRICE) return null;
  if (adv < MIN_ADV_M) return null;
  const deviation_pct = ((last.c - sma25) / sma25) * 100;
  const today_intraday_pct = last.o > 0 ? ((last.c - last.o) / last.o) * 100 : 0;
  return {
    ticker: u.ticker,
    sector: u.sector,
    sectorEtf: u.sectorEtf,
    price: last.c,
    sma25,
    sma200,
    deviation_pct,
    adv20_m: adv,
    today_intraday_pct,
  };
}

/** Run an array of async fns in chunks to avoid hammering Polygon. */
async function inChunks<T, U>(items: T[], size: number, fn: (item: T) => Promise<U>): Promise<U[]> {
  const out: U[] = [];
  for (let i = 0; i < items.length; i += size) {
    const slice = items.slice(i, i + size);
    const results = await Promise.all(slice.map(fn));
    out.push(...results);
  }
  return out;
}

// ──────────────────────────────────────────────────────────────────
// Universe scan implementations — equity (existing) and ETF (new).
// Both share Polygon + the SMA/dev compute. ETF scan skips earnings /
// insider / 8-K (not applicable), skips ADV (all ETFs liquid), and
// replaces the sector-breadth guard with a single SPY broad-market
// check (the candidate IS a sector ETF).
// ──────────────────────────────────────────────────────────────────

interface ScanResult { scanned: number; with_data: number; candidates: number; }

/* eslint-disable @typescript-eslint/no-explicit-any */
type Admin = ReturnType<typeof createClient>;

// ── Progress writer ─────────────────────────────────────────────
// Upserts the user's bnf_scan_status row with whatever fields are
// supplied. Best-effort: a status write failing should NEVER kill the
// scan, so we log + swallow. Caller is responsible for the cadence
// (~every 50 tickers in the equity loop, once per phase elsewhere).
type Progress = Partial<{
  stage: string;                  // overall: starting | running | done | error
  equity_stage: string;           // per-universe: idle | pricing | enriching | done
  etf_stage: string;
  equity_scanned: number; equity_total: number; equity_candidates: number;
  etf_scanned: number;    etf_total: number;    etf_candidates: number;
  equity_rate_limited: number;
  etf_rate_limited: number;
  message: string | null;
}>;
function makeProgressWriter(admin: Admin, userId: string, scanId: string, mode: string) {
  // Track everything seen so each upsert has the full snapshot — handy
  // when Realtime delivers individual row UPDATE events.
  const state: Progress & { scan_id: string; mode: string } = { scan_id: scanId, mode };
  return async (patch: Progress): Promise<void> => {
    Object.assign(state, patch);
    try {
      await admin.from('bnf_scan_status').upsert({
        user_id: userId,
        ...state,
        updated_at: new Date().toISOString(),
      }, { onConflict: 'user_id' });
    } catch (e) {
      // Don't crash the scan because progress writes failed.
      console.error('progress write failed:', (e as Error).message);
    }
  };
}
type ProgressFn = ReturnType<typeof makeProgressWriter>;

async function runEquityScan(
  admin: Admin, key: string, userId: string, fromIso: string, toIso: string,
  progress?: ProgressFn,
): Promise<ScanResult> {
  await progress?.({
    equity_stage: 'pricing', equity_total: UNIVERSE.length,
    equity_scanned: 0, equity_candidates: 0,
  });

  // 1) Sector ETF deviations — read from cache, fast.
  const sectorDevs = new Map<string, number | null>();
  await Promise.all(SECTOR_ETFS.map(async (etf) => {
    const aggs = await fetchAggsBars(admin, etf, fromIso, toIso);
    if (aggs.length < 25) { sectorDevs.set(etf, null); return; }
    const closes = aggs.map((a) => a.c);
    const s = sma(closes, 25);
    const last = aggs[aggs.length - 1].c;
    sectorDevs.set(etf, s ? ((last - s) / s) * 100 : null);
  }));

  // 2) Bulk-read ALL universe ticker aggregates in ~2-3 chunked queries.
  // This replaces 999 separate Polygon calls with a handful of database
  // selects against the bnf_universe_data cache.
  const aggsByTicker = await fetchAggsBulk(
    admin, UNIVERSE.map((u) => u.ticker), fromIso, toIso,
  );

  // 3) Compute per-ticker SMA / filters in memory. No I/O in this loop.
  const tickerResults: Array<TickerResult | null> = [];
  for (const u of UNIVERSE) {
    const aggs = aggsByTicker.get(u.ticker) ?? [];
    tickerResults.push(processOneFromCache(u, aggs));
    // Update progress every 100 tickers — cheap since the loop is fast.
    if (tickerResults.length % 100 === 0) {
      await progress?.({ equity_scanned: tickerResults.length });
    }
  }
  await progress?.({ equity_scanned: tickerResults.length });

  // Diagnostic: how many tickers have NO cached data? Indicates the cache
  // needs a backfill / cron run, not a Polygon failure.
  const missing = UNIVERSE.filter((u) => (aggsByTicker.get(u.ticker)?.length ?? 0) < 200).length;
  if (missing > 0) {
    console.error(`equity scan: ${missing} / ${UNIVERSE.length} tickers had <200 days of cached data (run cache backfill)`);
  }

  // 3) Apply BNF filters.
  const survivors = tickerResults.filter((r): r is TickerResult => {
    if (!r) return false;
    if (r.deviation_pct < DEV_MIN || r.deviation_pct > DEV_MAX) return false;
    if (r.price <= r.sma200) return false;
    if (r.today_intraday_pct < TODAY_INTRADAY_FLOOR) return false;
    const sectorDev = sectorDevs.get(r.sectorEtf);
    if (sectorDev != null && sectorDev < SECTOR_DEV_FLOOR) return false;
    return true;
  });
  await progress?.({ equity_stage: 'enriching', equity_candidates: survivors.length });

  // 4) Survivor enrichment — Polygon options + Yahoo (earnings/name) +
  //    SEC EDGAR (8-K + insider $) in parallel per ticker. Chunked at 5
  //    so we don't burst SEC's ~10-req/sec ceiling.
  const preEnriched = await inChunks(survivors, 5, async (s) => {
    const [ctx, yahoo, edgar] = await Promise.all([
      fetchOptionsCtx(s.ticker, s.price, key).catch(() => ({
        iv30: null, options_volume: 0, put_call_ratio: null, open_interest: 0,
      })),
      fetchYahooCtx(s.ticker).catch(() => ({ daysToEarnings: null, name: null })),
      fetchEdgarFlags(s.ticker).catch(() => ({
        insider: { sellers_count: 0, total_sold_usd: 0, details: [] } as InsiderActivity,
        eightKs: [] as Item8K[],
      })),
    ]);
    return { ...s, ctx, yahoo, edgar, sectorEtfDev: sectorDevs.get(s.sectorEtf) ?? null };
  });

  // 4b) Earnings-window filter (soft on missing data).
  const EARNINGS_WINDOW_DAYS = 3;
  const enriched = preEnriched.filter((e) =>
    e.yahoo.daysToEarnings == null ||
    Math.abs(e.yahoo.daysToEarnings) > EARNINGS_WINDOW_DAYS,
  );

  // 5) Replace previous equity candidates with this scan's survivors.
  await admin.from('bnf_candidates').delete()
    .eq('user_id', userId).eq('universe', 'EQUITY');
  if (enriched.length > 0) {
    const rows = enriched.map((e) => ({
      user_id: userId,
      universe: 'EQUITY',
      ticker: e.ticker,
      name: e.yahoo.name,
      sector: e.sector,
      category: null,
      price: e.price,
      sma25: e.sma25,
      sma200: e.sma200,
      deviation_pct: e.deviation_pct,
      adv20_m: e.adv20_m,
      days_to_earnings: e.yahoo.daysToEarnings,
      days_since_earnings: daysSinceFromTradingDays(e.yahoo.daysToEarnings),
      today_intraday_pct: e.today_intraday_pct,
      sector_etf: e.sectorEtf,
      sector_etf_dev_pct: e.sectorEtfDev,
      iv30: e.ctx.iv30,
      iv_rank: null,
      options_volume: e.ctx.options_volume,
      put_call_ratio: e.ctx.put_call_ratio,
      open_interest: e.ctx.open_interest,
      insider_sales: e.edgar.insider.sellers_count > 0 ? e.edgar.insider : null,
      recent_8ks: e.edgar.eightKs.length > 0 ? e.edgar.eightKs : null,
    }));
    const { error: insErr } = await admin.from('bnf_candidates').insert(rows);
    if (insErr) throw new Error(`Equity insert failed: ${insErr.message}`);
  }

  await progress?.({ equity_stage: 'done', equity_candidates: enriched.length });
  return {
    scanned: UNIVERSE.length,
    with_data: tickerResults.filter(Boolean).length,
    candidates: enriched.length,
  };
}

/** ETF scan path — simpler signal pipeline:
 *  - SPY broad-market guard (skip when SPY < −5% vs its own SMA25)
 *  - Per-ETF SMA25/200/dev/intraday/signal-day vol ratio
 *  - Options snapshot per survivor (optional, fail-soft)
 *  - No earnings / no EDGAR / no ADV / no sector breadth */
async function runEtfScan(
  admin: Admin, key: string, userId: string, fromIso: string, toIso: string,
  progress?: ProgressFn,
): Promise<ScanResult> {
  await progress?.({ etf_stage: 'pricing', etf_total: ETF_UNIVERSE.length, etf_scanned: 0 });
  // 1) SPY broad-market guard.
  const spyAggs = await fetchAggsBars(admin, 'SPY', fromIso, toIso);
  let spyOk = true;
  if (spyAggs.length >= 25) {
    const closes = spyAggs.map((a) => a.c);
    const spySma = sma(closes, 25);
    const spyLast = spyAggs[spyAggs.length - 1].c;
    if (spySma) {
      const spyDev = ((spyLast - spySma) / spySma) * 100;
      if (spyDev < SECTOR_DEV_FLOOR) spyOk = false;
    }
  }

  // 2) Per-ETF aggregates from the cache. Bulk-read once, iterate locally.
  const etfAggsByTicker = await fetchAggsBulk(
    admin, ETF_UNIVERSE.map((e) => e.ticker), fromIso, toIso,
  );
  const etfResults = await inChunks(ETF_UNIVERSE, ETF_UNIVERSE.length, async (etf) => {
    try {
      const aggs = etfAggsByTicker.get(etf.ticker) ?? [];
      if (aggs.length < 200) return null;
      const closes = aggs.map((a) => a.c);
      const sma25 = sma(closes, 25);
      const sma200 = sma(closes, 200);
      const last = aggs[aggs.length - 1];
      if (!sma25 || !sma200 || !last) return null;
      const deviation_pct = ((last.c - sma25) / sma25) * 100;
      const today_intraday_pct = last.o > 0 ? ((last.c - last.o) / last.o) * 100 : 0;
      // Signal-day volume ratio = today's volume / 20-day avg volume.
      const vol20 = aggs.slice(-21, -1).reduce((s, b) => s + (b.v ?? 0), 0) / 20;
      const signal_day_vol_ratio = vol20 > 0 ? (last.v ?? 0) / vol20 : null;
      return {
        etf, price: last.c, sma25, sma200, deviation_pct,
        today_intraday_pct, signal_day_vol_ratio,
      };
    } catch { return null; }
  });

  await progress?.({ etf_scanned: etfResults.length, etf_stage: 'pricing' });

  // 3) Apply ETF-specific filters.
  const survivors = etfResults.filter((r): r is NonNullable<typeof r> => {
    if (!r) return false;
    if (!spyOk) return false;                                       // broad-market guard
    if (r.deviation_pct < DEV_MIN || r.deviation_pct > DEV_MAX) return false;
    if (r.price <= r.sma200) return false;
    if (r.today_intraday_pct < TODAY_INTRADAY_FLOOR) return false;
    return true;
  });
  await progress?.({ etf_stage: 'enriching', etf_candidates: survivors.length });

  // 4) Options snapshot per survivor — optional, fail-soft.
  const enriched = await inChunks(survivors, 6, async (s) => {
    const ctx = await fetchOptionsCtx(s.etf.ticker, s.price, key).catch(() => ({
      iv30: null, options_volume: 0, put_call_ratio: null, open_interest: 0,
    }));
    return { ...s, ctx };
  });

  // 5) Replace previous ETF rows for this user.
  await admin.from('bnf_candidates').delete()
    .eq('user_id', userId).eq('universe', 'ETF');
  if (enriched.length > 0) {
    const rows = enriched.map((e) => ({
      user_id: userId,
      universe: 'ETF',
      ticker: e.etf.ticker,
      name: e.etf.name,
      sector: null,
      category: e.etf.category,
      price: e.price,
      sma25: e.sma25,
      sma200: e.sma200,
      deviation_pct: e.deviation_pct,
      adv20_m: null,                       // not applied to ETFs
      days_to_earnings: null,              // n/a
      days_since_earnings: null,
      today_intraday_pct: e.today_intraday_pct,
      sector_etf: null,
      sector_etf_dev_pct: null,
      signal_day_vol_ratio: e.signal_day_vol_ratio,
      iv30: e.ctx.iv30,
      iv_rank: null,
      options_volume: e.ctx.options_volume,
      put_call_ratio: e.ctx.put_call_ratio,
      open_interest: e.ctx.open_interest,
      insider_sales: null,
      recent_8ks: null,
    }));
    const { error: insErr } = await admin.from('bnf_candidates').insert(rows);
    if (insErr) throw new Error(`ETF insert failed: ${insErr.message}`);
  }

  await progress?.({ etf_stage: 'done', etf_candidates: enriched.length });
  return {
    scanned: ETF_UNIVERSE.length,
    with_data: etfResults.filter(Boolean).length,
    candidates: enriched.length,
  };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });

  try {
    const key = Deno.env.get('POLYGON_API_KEY');
    if (!key) return jsonErr('POLYGON_API_KEY is not set as a Supabase secret', 500);
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceKey) return jsonErr('Supabase service env not configured', 500);

    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return jsonErr('Missing Authorization header', 401);
    const userClient = createClient(supabaseUrl, serviceKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) return jsonErr('Unauthorized', 401);
    const userId = userData.user.id;

    const admin = createClient(supabaseUrl, serviceKey);

    // Universe mode dispatch — accepts {universe: 'equity'|'etf'|'both'},
    // defaults to 'both' so a bare invocation hits the same surface as
    // the original. Empty body is fine.
    let mode: 'equity' | 'etf' | 'both' = 'both';
    try {
      const body = await req.json() as { universe?: string };
      if (body?.universe === 'equity' || body?.universe === 'etf' || body?.universe === 'both') {
        mode = body.universe;
      }
    } catch { /* no body / bad JSON = default to 'both' */ }

    // Date window — same for both universes.
    const toDate = new Date();
    const fromDate = new Date(toDate);
    fromDate.setDate(fromDate.getDate() - 400);
    const fromIso = fromDate.toISOString().slice(0, 10);
    const toIso = toDate.toISOString().slice(0, 10);

    // Progress writer — upserts bnf_scan_status under the calling user.
    const scanId = crypto.randomUUID();
    const progress = makeProgressWriter(admin, userId, scanId, mode);
    await progress({
      stage: 'starting',
      equity_stage: 'idle', etf_stage: 'idle',
      equity_scanned: 0, equity_total: 0, equity_candidates: 0, equity_rate_limited: 0,
      etf_scanned: 0,    etf_total: 0,    etf_candidates: 0,    etf_rate_limited: 0,
      message: null,
    });

    // Run scans IN PARALLEL when both are requested — sequential was tipping
    // past the edge timeout once the equity universe grew to 1000 names.
    // Each branch has its own try/catch so one throwing doesn't sink the
    // other; the response surfaces partial results.
    const equityP = (mode === 'equity' || mode === 'both')
      ? runEquityScan(admin, key, userId, fromIso, toIso, progress)
          .then((r) => r as ScanResult | { error: string })
          .catch((e) => {
            console.error('equity scan failed:', e);
            return { error: (e as Error).message };
          })
      : Promise.resolve(null);
    const etfP = (mode === 'etf' || mode === 'both')
      ? runEtfScan(admin, key, userId, fromIso, toIso, progress)
          .then((r) => r as ScanResult | { error: string })
          .catch((e) => {
            console.error('etf scan failed:', e);
            return { error: (e as Error).message };
          })
      : Promise.resolve(null);

    const [equityResult, etfResult] = await Promise.all([equityP, etfP]);

    // Determine final stage: error if BOTH ran and both errored, done otherwise.
    const equityErr = equityResult && 'error' in equityResult;
    const etfErr = etfResult && 'error' in etfResult;
    const anyError = equityErr || etfErr;
    const allError = (equityResult ? equityErr : true) && (etfResult ? etfErr : true);
    await progress({
      stage: allError ? 'error' : 'done',
      message: anyError
        ? [equityErr ? `equity: ${(equityResult as { error: string }).error}` : null,
           etfErr ? `etf: ${(etfResult as { error: string }).error}` : null]
          .filter(Boolean).join(' · ')
        : null,
    });

    return new Response(
      JSON.stringify({ mode, scan_id: scanId, equity: equityResult, etf: etfResult }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    console.error('bnf-scan dispatcher failed:', e);
    return jsonErr((e as Error).message, 500);
  }
});

function jsonErr(message: string, status: number): Response {
  return new Response(
    JSON.stringify({ error: message }),
    { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
}
