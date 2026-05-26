/**
 * bnf-cache-backfill — multi-day cache load.
 *
 * Loops Polygon's grouped daily endpoint for each trading day in a
 * window and upserts each day's universe-relevant bars into
 * bnf_universe_data. Designed to be batched by the client so each
 * invocation fits in the edge timeout.
 *
 * Body:
 *   { from_date?: 'YYYY-MM-DD', to_date?: 'YYYY-MM-DD' }
 *
 * Defaults:
 *   from_date = today − 260 calendar days (~ 200 trading days + buffer)
 *   to_date   = yesterday
 *
 * Typical use:
 *   - First time: client batches the full backfill into ~5 calls of
 *     50 dates each
 *   - Top-up: pass an explicit narrow window to fill gaps
 *
 * Writes progress to bnf_scan_status so the existing banner shows
 * "Cache backfill: 87 / 250 days · 41,200 rows inserted".
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { UNIVERSE } from '../bnf-scan/universe.ts';
import { ETF_UNIVERSE } from '../bnf-scan/etf-universe.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const SECTOR_ETFS = ['XLE', 'XLF', 'XLK', 'XLV', 'XLY', 'XLP', 'XLI', 'XLB', 'XLU', 'XLRE', 'XLC', 'SPY'];
const TARGET_TICKERS = new Set<string>([
  ...UNIVERSE.map((u) => u.ticker),
  ...ETF_UNIVERSE.map((e) => e.ticker),
  ...SECTOR_ETFS,
]);

interface GroupedBar { T: string; o: number; c: number; v: number; }
interface GroupedResp { results?: GroupedBar[]; }

function jsonErr(message: string, status: number): Response {
  return new Response(
    JSON.stringify({ error: message }),
    { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
}

/** Walk dates from `from` to `to` inclusive, skipping weekends. Returns
 *  ISO date strings ordered chronologically. */
function tradingDaysInRange(fromIso: string, toIso: string): string[] {
  const out: string[] = [];
  const start = new Date(fromIso + 'T00:00:00Z');
  const end = new Date(toIso + 'T00:00:00Z');
  for (const d = new Date(start); d <= end; d.setUTCDate(d.getUTCDate() + 1)) {
    const dow = d.getUTCDay();
    if (dow === 0 || dow === 6) continue;     // skip Sat/Sun
    out.push(d.toISOString().slice(0, 10));
  }
  return out;
}

async function pullDayRows(key: string, date: string): Promise<GroupedBar[]> {
  const url = `https://api.polygon.io/v2/aggs/grouped/locale/us/market/stocks/${date}?adjusted=true&apiKey=${key}`;
  try {
    const res = await fetch(url);
    if (!res.ok) return [];
    const j: GroupedResp = await res.json();
    return (j.results ?? []).filter((b) => TARGET_TICKERS.has(b.T));
  } catch {
    return [];
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });

  try {
    const key = Deno.env.get('POLYGON_API_KEY');
    if (!key) return jsonErr('POLYGON_API_KEY not set', 500);
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceKey) return jsonErr('Supabase env not configured', 500);

    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return jsonErr('Missing Authorization header', 401);
    const userClient = createClient(supabaseUrl, serviceKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) return jsonErr('Unauthorized', 401);
    const userId = userData.user.id;
    const admin = createClient(supabaseUrl, serviceKey);

    let fromDate: string | undefined;
    let toDate: string | undefined;
    try {
      const body = await req.json() as { from_date?: string; to_date?: string };
      if (typeof body?.from_date === 'string') fromDate = body.from_date;
      if (typeof body?.to_date === 'string') toDate = body.to_date;
    } catch { /* defaults */ }

    if (!toDate) {
      const d = new Date();
      d.setUTCDate(d.getUTCDate() - 1);
      toDate = d.toISOString().slice(0, 10);
    }
    if (!fromDate) {
      const d = new Date(toDate + 'T00:00:00Z');
      d.setUTCDate(d.getUTCDate() - 260);
      fromDate = d.toISOString().slice(0, 10);
    }

    const dates = tradingDaysInRange(fromDate, toDate);
    if (dates.length === 0) {
      return new Response(
        JSON.stringify({ from_date: fromDate, to_date: toDate, dates: 0, inserted: 0 }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Update status row so the banner shows cache progress.
    const writeStatus = async (msg: string) => {
      try {
        await admin.from('bnf_scan_status').upsert({
          user_id: userId,
          scan_id: 'cache-backfill',
          mode: 'both',
          stage: 'starting',
          message: msg,
          updated_at: new Date().toISOString(),
        }, { onConflict: 'user_id' });
      } catch { /* swallow */ }
    };

    // Process dates in serial-ish batches: 8 in parallel per chunk
    // (Polygon grouped endpoint is heavier than per-ticker; 8 is gentle).
    let totalInserted = 0;
    let totalRows = 0;
    const CHUNK = 8;
    for (let i = 0; i < dates.length; i += CHUNK) {
      const slice = dates.slice(i, i + CHUNK);
      const dayResults = await Promise.all(slice.map((d) => pullDayRows(key, d).then((bars) => ({ date: d, bars }))));

      // Build a flat row list across all dates in this chunk, then
      // upsert once.
      const flatRows: Array<{ ticker: string; date: string; open: number; close: number; volume: number; }> = [];
      for (const dayResult of dayResults) {
        for (const b of dayResult.bars) {
          flatRows.push({
            ticker: b.T,
            date: dayResult.date,
            open: b.o,
            close: b.c,
            volume: b.v,
          });
        }
      }
      if (flatRows.length > 0) {
        // Upsert in 500-row sub-chunks to stay under request size limits.
        const SUB = 500;
        for (let j = 0; j < flatRows.length; j += SUB) {
          const sub = flatRows.slice(j, j + SUB);
          const { error } = await admin
            .from('bnf_universe_data')
            .upsert(sub, { onConflict: 'ticker,date' });
          if (error) {
            console.error('cache backfill upsert failed:', error.message);
            return jsonErr(`upsert failed: ${error.message}`, 500);
          }
          totalInserted += sub.length;
        }
        totalRows += flatRows.length;
      }
      await writeStatus(`Cache backfill: ${Math.min(i + CHUNK, dates.length)} / ${dates.length} dates · ${totalInserted} rows`);
    }

    // Mark done. We use stage='done' on this status row even though it's
    // not a "scan" so the banner auto-fades like a scan-done.
    try {
      await admin.from('bnf_scan_status').upsert({
        user_id: userId,
        scan_id: 'cache-backfill',
        mode: 'both',
        stage: 'done',
        message: `Cache backfill complete: ${dates.length} dates, ${totalInserted} rows.`,
        updated_at: new Date().toISOString(),
      }, { onConflict: 'user_id' });
    } catch { /* swallow */ }

    return new Response(
      JSON.stringify({
        from_date: fromDate,
        to_date: toDate,
        dates: dates.length,
        inserted: totalInserted,
        rows_pulled: totalRows,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    console.error('bnf-cache-backfill failed:', e);
    return jsonErr((e as Error).message, 500);
  }
});
