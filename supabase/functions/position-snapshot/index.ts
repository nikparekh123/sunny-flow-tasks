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

  return new Response(
    JSON.stringify({ snapshot_date: snapshotDate, tickers: rows.length }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
});
