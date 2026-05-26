/**
 * bnf-cache-update — incremental daily cache refresh.
 *
 * Pulls Polygon's grouped daily snapshot for ONE date (default: most
 * recent trading day) and upserts each universe ticker's OHLCV into
 * bnf_universe_data. One Polygon call per invocation; finishes in
 * <10 seconds.
 *
 * Designed for two callers:
 *   1. Nightly pg_cron after market close → keeps cache fresh
 *   2. Manual "Refresh universe cache" button → same path, on demand
 *
 * Optional body: { date: 'YYYY-MM-DD' } — explicit override; defaults
 * to yesterday in US/Eastern.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { UNIVERSE } from '../bnf-scan/universe.ts';
import { ETF_UNIVERSE } from '../bnf-scan/etf-universe.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

/** Set of all tickers we care about — equity universe + the ETF universe
 *  + the SPDR sector ETFs (used by bnf-scan for the broad-market guard
 *  and the sector breadth filter). Building this once at module load so
 *  the per-day filter is O(1). */
const SECTOR_ETFS = ['XLE', 'XLF', 'XLK', 'XLV', 'XLY', 'XLP', 'XLI', 'XLB', 'XLU', 'XLRE', 'XLC', 'SPY'];
const TARGET_TICKERS = new Set<string>([
  ...UNIVERSE.map((u) => u.ticker),
  ...ETF_UNIVERSE.map((e) => e.ticker),
  ...SECTOR_ETFS,
]);

interface GroupedBar { T: string; o: number; c: number; v: number; }
interface GroupedResp { results?: GroupedBar[]; status?: string; resultsCount?: number; }

function jsonErr(message: string, status: number): Response {
  return new Response(
    JSON.stringify({ error: message }),
    { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
}

/** Return the most recent US trading day, in YYYY-MM-DD. Falls back to
 *  the previous weekday if today is Sat/Sun. */
function mostRecentTradingDay(): string {
  const now = new Date();
  // Use UTC date, then walk back to weekday.
  // (US markets close at 4pm ET = 21:00 UTC. By the time the cron fires
  //  at 6pm ET / 22:00 UTC, today's data is available.)
  const d = new Date(now);
  while (d.getUTCDay() === 0 || d.getUTCDay() === 6) {
    d.setUTCDate(d.getUTCDate() - 1);
  }
  return d.toISOString().slice(0, 10);
}

export async function pullDate(
  admin: ReturnType<typeof createClient>,
  key: string,
  date: string,
): Promise<{ inserted: number; rateLimited: boolean; reason?: string }> {
  const url = `https://api.polygon.io/v2/aggs/grouped/locale/us/market/stocks/${date}?adjusted=true&apiKey=${key}`;
  const res = await fetch(url);
  if (res.status === 429) return { inserted: 0, rateLimited: true, reason: 'Polygon 429' };
  if (!res.ok) return { inserted: 0, rateLimited: false, reason: `Polygon ${res.status}` };
  const j: GroupedResp = await res.json();
  const bars = j.results ?? [];
  if (bars.length === 0) {
    return { inserted: 0, rateLimited: false, reason: 'no bars (market closed?)' };
  }

  // Filter to tickers we care about. Polygon's grouped endpoint returns
  // ALL US stocks (~10K), so dropping the others first keeps the
  // payload small.
  const ourBars = bars.filter((b) => TARGET_TICKERS.has(b.T));
  if (ourBars.length === 0) return { inserted: 0, rateLimited: false, reason: 'no universe tickers in payload' };

  // For prev_close we need the bar from the previous trading day. The
  // grouped endpoint doesn't return prev_close, so we look it up from
  // our own cache table — populated by yesterday's run.
  const tickers = ourBars.map((b) => b.T);
  const { data: prevRows } = await admin
    .from('bnf_universe_data')
    .select('ticker, close')
    .in('ticker', tickers)
    .lt('date', date)
    .order('date', { ascending: false });
  const prevMap = new Map<string, number>();
  for (const r of (prevRows ?? []) as Array<{ ticker: string; close: number }>) {
    if (!prevMap.has(r.ticker)) prevMap.set(r.ticker, r.close);
  }

  const rows = ourBars.map((b) => ({
    ticker: b.T,
    date,
    open: b.o,
    close: b.c,
    prev_close: prevMap.get(b.T) ?? null,
    volume: b.v,
  }));

  // Upsert in chunks so we don't hit URL/payload limits (rows can be ~1k).
  const CHUNK = 500;
  let inserted = 0;
  for (let i = 0; i < rows.length; i += CHUNK) {
    const slice = rows.slice(i, i + CHUNK);
    const { error } = await admin
      .from('bnf_universe_data')
      .upsert(slice, { onConflict: 'ticker,date' });
    if (error) return { inserted, rateLimited: false, reason: `upsert: ${error.message}` };
    inserted += slice.length;
  }
  return { inserted, rateLimited: false };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });

  try {
    const key = Deno.env.get('POLYGON_API_KEY');
    if (!key) return jsonErr('POLYGON_API_KEY not set', 500);
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceKey) return jsonErr('Supabase env not configured', 500);

    let date: string | undefined;
    try {
      const body = await req.json() as { date?: string };
      if (typeof body?.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(body.date)) {
        date = body.date;
      }
    } catch { /* no body = use default */ }

    const targetDate = date ?? mostRecentTradingDay();
    const admin = createClient(supabaseUrl, serviceKey);
    const result = await pullDate(admin, key, targetDate);

    return new Response(
      JSON.stringify({ date: targetDate, ...result }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    console.error('bnf-cache-update failed:', e);
    return jsonErr((e as Error).message, 500);
  }
});
