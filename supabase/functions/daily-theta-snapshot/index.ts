/**
 * daily-theta-snapshot — capture today's hedge θ burn for the
 * Hedge tab's day-over-day and sparkline views.
 *
 * Reads:
 *   - public.option_trades  (open long puts with remaining > 0)
 *   - public.option_greeks  (latest θ per trade)
 * Writes (upsert by snapshot_date):
 *   - public.daily_theta_snapshot { total_burn, long_put_count, per_ticker }
 *
 * Invoked:
 *   - Daily cron post-close (~16:15 ET, Mon–Fri).
 *   - Manually for backfill / debugging.
 *
 * Scope (v1): long puts only. Long calls have a clean toggle path
 * for later if the user decides to include them.
 *
 * Idempotency: upsert keyed on snapshot_date (the EST calendar
 * date). Re-running same day overwrites — useful for backfill.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

interface OptionTradeRow {
  id: string;
  ticker: string;
  action: string;
  option_type: string;
  direction: string;
  contracts: number;
  premium: number;
}
interface OptionCloseRow {
  closes_trade_id: string | null;
  contracts: number;
}
interface OptionGreeksRow {
  option_trade_id: string;
  theta: number | null;
  captured_at: string | null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const supabase = createClient(supabaseUrl, serviceKey);

  // EST calendar date — same clock used everywhere else in the app.
  const estDate = new Date().toLocaleDateString('en-CA', {
    timeZone: 'America/New_York',
  }); // YYYY-MM-DD

  // 1. Pull every open option trade row (we'll filter to long puts
  //    after computing remaining contracts).
  const { data: trades, error: tErr } = await supabase
    .from('option_trades')
    .select('id, ticker, action, option_type, direction, contracts, premium, closes_trade_id');
  if (tErr) {
    return new Response(JSON.stringify({ error: tErr.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
  const allTrades = (trades ?? []) as (OptionTradeRow & { closes_trade_id?: string | null })[];

  // 2. Compute remaining contracts per open id (open.contracts minus
  //    closes against that id).
  const closedByOpen: Record<string, number> = {};
  for (const t of allTrades) {
    if (t.action === 'close' && t.closes_trade_id) {
      closedByOpen[t.closes_trade_id] = (closedByOpen[t.closes_trade_id] ?? 0) + Number(t.contracts);
    }
  }
  const openLongPuts = allTrades.filter((t) => {
    if (t.action !== 'open') return false;
    if (t.direction !== 'long') return false;
    if (t.option_type !== 'put') return false;
    const remaining = Number(t.contracts) - (closedByOpen[t.id] ?? 0);
    return remaining > 0.0001;
  });

  // 3. Fetch latest greeks for those trade ids.
  const ids = openLongPuts.map((t) => t.id);
  let greeks: OptionGreeksRow[] = [];
  if (ids.length > 0) {
    const { data: g, error: gErr } = await supabase
      .from('option_greeks')
      .select('option_trade_id, theta, captured_at')
      .in('option_trade_id', ids);
    if (gErr) {
      return new Response(JSON.stringify({ error: gErr.message }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    greeks = (g ?? []) as OptionGreeksRow[];
  }
  // option_greeks is upserted per trade so one row is expected, but
  // dedupe defensively to the latest captured_at.
  const greeksByTrade: Record<string, OptionGreeksRow> = {};
  for (const row of greeks) {
    const existing = greeksByTrade[row.option_trade_id];
    if (!existing) {
      greeksByTrade[row.option_trade_id] = row;
    } else {
      const lhs = existing.captured_at ? Date.parse(existing.captured_at) : 0;
      const rhs = row.captured_at ? Date.parse(row.captured_at) : 0;
      if (rhs > lhs) greeksByTrade[row.option_trade_id] = row;
    }
  }

  // 4. Aggregate today's burn.
  let totalBurn = 0;
  const perTicker: Record<string, number> = {};
  for (const t of openLongPuts) {
    const remaining = Number(t.contracts) - (closedByOpen[t.id] ?? 0);
    const g = greeksByTrade[t.id];
    const theta = g?.theta;
    if (theta === null || theta === undefined) continue;
    const burn = Math.abs(Number(theta)) * remaining * 100;
    totalBurn += burn;
    perTicker[t.ticker] = (perTicker[t.ticker] ?? 0) + burn;
  }

  // 5. Upsert today's row.
  const { error: upErr } = await supabase
    .from('daily_theta_snapshot')
    .upsert(
      {
        snapshot_date: estDate,
        total_burn: totalBurn,
        long_put_count: openLongPuts.length,
        per_ticker: perTicker,
      },
      { onConflict: 'snapshot_date' }
    );
  if (upErr) {
    return new Response(JSON.stringify({ error: upErr.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  return new Response(
    JSON.stringify({
      snapshot_date: estDate,
      total_burn: totalBurn,
      long_put_count: openLongPuts.length,
      tickers: Object.keys(perTicker).length,
    }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
});
