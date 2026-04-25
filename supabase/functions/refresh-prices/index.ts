/**
 * refresh-prices — pull live quotes for every ticker in `positions` from
 * Polygon (now massive.com) and write last_price / prev_close / last_updated.
 *
 * Invoked manually from the UI when the user clicks "↻ Refresh prices",
 * and on a schedule once per market day via pg_cron.
 *
 * Required Supabase secrets:
 *   POLYGON_API_KEY  — your Polygon/Massive API key
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

interface SnapshotTicker {
  ticker: string;
  lastTrade?: { p?: number };
  lastQuote?: { p?: number };
  prevDay?: { c?: number };
  day?: { c?: number };
}

interface SnapshotResponse {
  status: string;
  tickers?: SnapshotTicker[];
  results?: SnapshotTicker[];
  error?: string;
  message?: string;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const polygonKey = Deno.env.get('POLYGON_API_KEY');

    if (!polygonKey) {
      return new Response(
        JSON.stringify({ error: 'POLYGON_API_KEY is not set as a Supabase secret' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // 1) read all tickers
    const { data: positions, error: readError } = await admin
      .from('positions')
      .select('id, ticker');
    if (readError) throw readError;

    const tickers = (positions ?? []).map((p) => p.ticker.toUpperCase());
    if (tickers.length === 0) {
      return new Response(
        JSON.stringify({ updated: 0, message: 'No positions to refresh.' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 2) Polygon snapshot endpoint — returns up to all stocks with one call.
    //    We pass an explicit tickers list so we only get the ones we own.
    const url = new URL(
      'https://api.polygon.io/v2/snapshot/locale/us/markets/stocks/tickers',
    );
    url.searchParams.set('tickers', tickers.join(','));
    url.searchParams.set('apiKey', polygonKey);

    const resp = await fetch(url.toString());
    if (!resp.ok) {
      const body = await resp.text();
      throw new Error(`Polygon snapshot failed (${resp.status}): ${body.slice(0, 300)}`);
    }
    const data = (await resp.json()) as SnapshotResponse;
    const items = data.tickers ?? data.results ?? [];

    // 3) update each row. Polygon may not return every ticker (e.g. delisted) —
    //    we only update what came back, leave the rest untouched.
    const now = new Date().toISOString();
    let updated = 0;
    const missing: string[] = [];

    for (const t of tickers) {
      const item = items.find((x) => x.ticker?.toUpperCase() === t);
      if (!item) {
        missing.push(t);
        continue;
      }
      const last = item.lastTrade?.p ?? item.lastQuote?.p ?? item.day?.c;
      const prev = item.prevDay?.c;
      if (last == null && prev == null) {
        missing.push(t);
        continue;
      }
      const patch: Record<string, unknown> = { last_updated: now };
      if (last != null) patch.last_price = last;
      if (prev != null) patch.prev_close = prev;
      const { error: updateError } = await admin
        .from('positions')
        .update(patch)
        .eq('ticker', t);
      if (updateError) {
        missing.push(`${t} (write failed: ${updateError.message})`);
      } else {
        updated++;
      }
    }

    return new Response(
      JSON.stringify({
        updated,
        total: tickers.length,
        missing,
        timestamp: now,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: (err as Error).message || 'Server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
