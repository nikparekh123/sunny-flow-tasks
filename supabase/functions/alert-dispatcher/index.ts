/**
 * alert-dispatcher — decides which notifications need to be sent
 * and writes them into `alert_dispatch`. A separate push worker
 * drains that queue (not in this scope — Apple Developer setup
 * required before we can deliver).
 *
 * Categories evaluated:
 *   theta_cliff         — leg DTE just crossed 21
 *   theta_critical      — leg DTE just crossed 7
 *   short_call_itm      — short call where spot >= strike
 *   long_put_itm        — long put where spot <= strike
 *   earnings_day_before — positions with earnings_date = tomorrow
 *
 * Idempotency is enforced via `alert_dispatch.dedup_key` UNIQUE.
 * A typical key includes a date so the alert fires at most once
 * per day per leg/event.
 *
 * Invoked:
 *   • Daily cron at ~07:00 ET (pre-market) for the day's expected
 *     transitions
 *   • Also runs after mp-refresh during market hours so the ITM
 *     alerts fire as positions cross (15-min cadence good enough)
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
  strike: number;
  expiry: string;
  closes_trade_id: string | null;
}
interface TickerQuoteRow { ticker: string; spot: number | null; }
interface PositionRow    { ticker: string; earnings_date: string | null; }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const todayEST = new Date().toLocaleDateString('en-CA', { timeZone: 'America/New_York' });
  const queued: { category: string; dedup_key: string; title: string }[] = [];

  // Pull everything we need in parallel.
  const [{ data: trades }, { data: quotes }, { data: positions }] = await Promise.all([
    supabase.from('option_trades').select('id, ticker, action, option_type, direction, contracts, strike, expiry, closes_trade_id'),
    supabase.from('ticker_quotes_latest').select('ticker, spot'),
    supabase.from('positions').select('ticker, earnings_date'),
  ]);
  const allTrades = (trades ?? []) as OptionTradeRow[];
  const spotByTicker: Record<string, number> = {};
  for (const q of (quotes ?? []) as TickerQuoteRow[]) {
    if (q.spot != null) spotByTicker[q.ticker] = Number(q.spot);
  }

  // Remaining contracts per open id.
  const closedBy: Record<string, number> = {};
  for (const t of allTrades) {
    if (t.action === 'close' && t.closes_trade_id) {
      closedBy[t.closes_trade_id] = (closedBy[t.closes_trade_id] ?? 0) + Number(t.contracts);
    }
  }
  const openLegs = allTrades.filter(t => {
    if (t.action !== 'open') return false;
    const rem = Number(t.contracts) - (closedBy[t.id] ?? 0);
    return rem > 0.0001;
  });

  // Per-leg evaluations.
  for (const leg of openLegs) {
    const dte = daysUntilEST(leg.expiry);
    const spot = spotByTicker[leg.ticker] ?? 0;

    // theta_cliff — DTE == 21 (first day in cliff zone)
    if (dte === 21) {
      await enqueue(queued, supabase, {
        category: 'theta_cliff',
        dedup_key: `theta_cliff:${leg.id}:${todayEST}`,
        ticker: leg.ticker,
        title: `${leg.ticker} $${Math.round(leg.strike)}${leg.option_type[0]} enters cliff zone`,
        body: `21 days to expiry. Theta acceleration starts now.`,
        deep_link: `hedge://leg/${leg.id}`,
      });
    }
    // theta_critical — DTE == 7
    if (dte === 7) {
      await enqueue(queued, supabase, {
        category: 'theta_critical',
        dedup_key: `theta_critical:${leg.id}:${todayEST}`,
        ticker: leg.ticker,
        title: `${leg.ticker} $${Math.round(leg.strike)}${leg.option_type[0]} — critical`,
        body: `7 days to expiry. Burn is steep — roll or commit.`,
        deep_link: `hedge://leg/${leg.id}`,
      });
    }
    // short_call_itm — short call, spot >= strike (assignment risk)
    if (spot > 0 && leg.option_type === 'call' && leg.direction === 'short' && spot >= Number(leg.strike)) {
      await enqueue(queued, supabase, {
        category: 'short_call_itm',
        dedup_key: `short_call_itm:${leg.id}:${todayEST}`,
        ticker: leg.ticker,
        title: `${leg.ticker} short call is ITM`,
        body: `Spot $${spot.toFixed(2)} ≥ strike $${Number(leg.strike).toFixed(0)}. Assignment risk.`,
        deep_link: `trades://leg/${leg.id}`,
      });
    }
    // long_put_itm — long put, spot <= strike (insurance kicking in)
    if (spot > 0 && leg.option_type === 'put' && leg.direction === 'long' && spot <= Number(leg.strike)) {
      await enqueue(queued, supabase, {
        category: 'long_put_itm',
        dedup_key: `long_put_itm:${leg.id}:${todayEST}`,
        ticker: leg.ticker,
        title: `${leg.ticker} long put is ITM`,
        body: `Spot $${spot.toFixed(2)} ≤ strike $${Number(leg.strike).toFixed(0)}. Hedge is active.`,
        deep_link: `hedge://leg/${leg.id}`,
      });
    }
  }

  // earnings_day_before — positions with earnings_date == tomorrow EST.
  const tomorrowEST = isoTomorrow(todayEST);
  for (const p of (positions ?? []) as PositionRow[]) {
    if (p.earnings_date === tomorrowEST) {
      await enqueue(queued, supabase, {
        category: 'earnings_day_before',
        dedup_key: `earnings:${p.ticker}:${tomorrowEST}`,
        ticker: p.ticker,
        title: `${p.ticker} reports tomorrow`,
        body: `Earnings after close. Check exposure.`,
        deep_link: `company://${p.ticker}`,
      });
    }
  }

  return new Response(
    JSON.stringify({ ok: true, queued: queued.length, items: queued }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
});

async function enqueue(
  acc: { category: string; dedup_key: string; title: string }[],
  supabase: ReturnType<typeof createClient>,
  payload: {
    category: string;
    dedup_key: string;
    ticker: string;
    title: string;
    body?: string;
    deep_link?: string;
    meta?: Record<string, unknown>;
  }
) {
  // ON CONFLICT (dedup_key) DO NOTHING via PostgREST's
  // ignoreDuplicates option.
  const { error } = await supabase
    .from('alert_dispatch')
    .upsert(
      [{
        category: payload.category,
        dedup_key: payload.dedup_key,
        ticker: payload.ticker,
        title: payload.title,
        body: payload.body ?? null,
        deep_link: payload.deep_link ?? null,
        meta: payload.meta ?? {},
      }],
      { onConflict: 'dedup_key', ignoreDuplicates: true }
    );
  if (!error) acc.push({ category: payload.category, dedup_key: payload.dedup_key, title: payload.title });
}

function daysUntilEST(iso: string): number {
  const eastern = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' });
  const today = new Date(`${eastern.format(new Date())}T00:00:00-05:00`);
  const target = new Date(`${iso.slice(0, 10)}T00:00:00-05:00`);
  return Math.round((target.getTime() - today.getTime()) / 86400000);
}

function isoTomorrow(today: string): string {
  const d = new Date(`${today}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10);
}
