/**
 * position-snapshot — capture today's portfolio state into
 * position_history. One row per (snapshot_date, ticker) so we have
 * a daily audit trail of qty + cost basis + lifetime realized.
 *
 * Reads:
 *   - public.positions  (current state)
 * Writes (upsert by composite key):
 *   - public.position_history
 *
 * Invoked:
 *   - Daily cron at ~16:30 ET (post-close, after mp-refresh's last
 *     intraday capture).
 *   - Manually for backfill.
 *
 * Idempotency: PK is (snapshot_date, ticker) so re-running on the
 * same day overwrites instead of duplicating.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

interface PositionRow {
  ticker: string;
  quantity: number | null;
  avg_cost: number | null;
  current_price: number | null;
  realized_stock_pl: number | null;
  status: string | null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const supabase = createClient(supabaseUrl, serviceKey);

  // EST calendar date — same clock used elsewhere in the app.
  const snapshotDate = new Date().toLocaleDateString('en-CA', {
    timeZone: 'America/New_York',
  });

  const { data, error } = await supabase
    .from('positions')
    .select('ticker, quantity, avg_cost, current_price, realized_stock_pl, status');
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const positions = (data ?? []) as PositionRow[];
  const rows = positions.map((p) => {
    const qty = Number(p.quantity ?? 0);
    const avg = Number(p.avg_cost ?? 0);
    const cur = p.current_price != null ? Number(p.current_price) : null;
    const unreal = cur != null && qty > 0 ? (cur - avg) * qty : 0;
    return {
      snapshot_date: snapshotDate,
      ticker: p.ticker,
      quantity: qty,
      avg_cost: avg,
      current_price: cur,
      unrealized_pl: unreal,
      realized_stock_pl: Number(p.realized_stock_pl ?? 0),
    };
  });

  if (rows.length > 0) {
    const { error: upErr } = await supabase
      .from('position_history')
      .upsert(rows, { onConflict: 'snapshot_date,ticker' });
    if (upErr) {
      return new Response(JSON.stringify({ error: upErr.message }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
  }

  /* ⚠ THE FEED SAYS IT RAN. THE CRON CANNOT. pg_cron logs "succeeded" the
     moment net.http_post hands back a request id and never learns whether this
     function ran, wrote, or threw. health-monitor watches the AGE of this row
     instead. Stamped last, after the writes, on the success path only — an
     error return must leave the row old, or the alarm is decorative.

     This one matters most: tracker #19 is position_history coming up empty
     while its cron reported success, and the check for it in health-monitor is
     switched off precisely because cron status could not be trusted. */
  await supabase.from('sync_heartbeat').upsert({
    feed: 'position-snapshot', ran_at: new Date().toISOString(),
    rows_written: rows.length,
    detail: `snapshot ${snapshotDate} · ${rows.length} tickers`,
  }, { onConflict: 'feed' });

  return new Response(
    JSON.stringify({ snapshot_date: snapshotDate, tickers: rows.length }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
});
