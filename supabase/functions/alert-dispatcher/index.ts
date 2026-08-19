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
    supabase.from('option_trades').select('id, ticker, action, option_type, direction, contracts, strike, expiry, closes_trade_id, voided_at'),
    supabase.from('ticker_quotes_latest').select('ticker, spot'),
    /* Held positions only. Without the filter this warned about earnings for
       every ticker ever entered, INTU included, which Nik has not owned since
       July. A print only matters if there is exposure to it. */
    supabase.from('positions').select('ticker, earnings_date').eq('status', 'open').gt('quantity', 0),
  ]);
  const allTrades = (trades ?? []) as OptionTradeRow[];
  const spotByTicker: Record<string, number> = {};
  for (const q of (quotes ?? []) as TickerQuoteRow[]) {
    if (q.spot != null) spotByTicker[q.ticker] = Number(q.spot);
  }

  /* What is actually still open, netted by CONTRACT.
     ────────────────────────────────────────────────────────────────────────
     This used to subtract closes from the specific open row they pointed at:

         rem = t.contracts - closedBy[t.id]

     but ibkr-flex-sync links every close to the OLDEST matching open, FIFO. So
     one open absorbs a pile of closes and goes far negative (filtered out),
     while later identical opens are never pointed at by anything and read as
     fully open forever. NVDA has 855 contracts opened and 855 closed, every
     close linked, and this still reported 40 short calls sitting in the money
     on an account that is flat. That is where most of the 88 daily alerts came
     from: positions Nik closed weeks ago.

     Netting per (ticker, type, direction, strike, expiry) is the same thing
     open-premium does, which is why that screen has always had NVDA right.

     Two more holes closed while here: voided_at was never filtered, so
     soft-deleted trades still alerted, and expiry was never checked, so an
     expired leg that was never explicitly closed alerted every single day. */
  const todayKey = todayEST;
  const netKey = (t: OptionTradeRow) =>
    `${t.ticker}|${t.option_type}|${t.direction}|${Number(t.strike)}|${String(t.expiry).slice(0, 10)}`;

  const net = new Map<string, { open: number; close: number; row: OptionTradeRow | null }>();
  for (const t of allTrades) {
    if ((t as { voided_at?: string | null }).voided_at != null) continue;
    const k = netKey(t);
    const e = net.get(k) ?? { open: 0, close: 0, row: null };
    if (t.action === 'open') { e.open += Number(t.contracts); e.row = t; }
    else { e.close += Number(t.contracts); }
    net.set(k, e);
  }

  const openLegs = [...net.values()]
    .filter((e) => e.row !== null && e.open - e.close > 0.0001)
    .filter((e) => String(e.row!.expiry).slice(0, 10) >= todayKey)
    .map((e) => ({ ...e.row!, contracts: e.open - e.close }));

  /* ── Grouped per ticker, not per leg ────────────────────────────────────
     Every one of these used to enqueue with dedup_key `<cat>:<leg.id>:<date>`,
     so one notification fired per option leg. Nik holds a lot of legs, and the
     12:00 run produced 88 alerts on 19 Aug, 99 on the 18th, 97 on the 17th.
     Three separate "NVDA short call is ITM" pushes in one batch, saying the
     same thing about the same underlying three times.

     It went unnoticed for two months because APNs was never configured, so the
     rows piled up unseen. The moment delivery started working it would have
     been ~90 notifications a morning, which is the same as no notifications.

     Now the key is `<cat>:<ticker>:<date>` and the leg detail moves into the
     body, where it costs nothing to read. Roughly 4 or 5 pushes a day. */
  type Bucket = { legs: typeof openLegs; spot: number };
  const buckets = new Map<string, Map<string, Bucket>>();
  const collect = (cat: string, leg: typeof openLegs[number], spot: number) => {
    let byTicker = buckets.get(cat);
    if (!byTicker) { byTicker = new Map(); buckets.set(cat, byTicker); }
    const b = byTicker.get(leg.ticker) ?? { legs: [], spot };
    b.legs.push(leg);
    b.spot = spot;
    byTicker.set(leg.ticker, b);
  };

  for (const leg of openLegs) {
    const dte = daysUntilEST(leg.expiry);
    const spot = spotByTicker[leg.ticker] ?? 0;

    if (dte === 21) collect('theta_cliff', leg, spot);
    if (dte === 7)  collect('theta_critical', leg, spot);
    if (spot > 0 && leg.option_type === 'call' && leg.direction === 'short' && spot >= Number(leg.strike)) {
      collect('short_call_itm', leg, spot);
    }
    if (spot > 0 && leg.option_type === 'put' && leg.direction === 'long' && spot <= Number(leg.strike)) {
      collect('long_put_itm', leg, spot);
    }
  }

  // Strikes read better than ids, and they are what Nik actually recognises.
  const strikeList = (legs: typeof openLegs) => {
    const ks = [...new Set(legs.map((l) => Number(l.strike)))].sort((a, b) => a - b);
    const txt = ks.map((k) => (Number.isInteger(k) ? String(k) : k.toFixed(1)));
    return txt.length === 1 ? txt[0]
      : txt.slice(0, -1).join(', ') + ' and ' + txt[txt.length - 1];
  };

  // Contracts, not rows. "3 short calls" should mean three contracts.
  const ct = (b: Bucket) => b.legs.reduce((a, l) => a + Number(l.contracts), 0);

  const COPY: Record<string, (t: string, b: Bucket) => { title: string; body: string; link: string }> = {
    theta_cliff: (t, b) => ({
      title: b.legs.length === 1
        ? `${t} $${Math.round(Number(b.legs[0].strike))}${b.legs[0].option_type[0]} enters cliff zone`
        : `${t}: ${ct(b)} legs enter the cliff zone`,
      body: `21 days to expiry on ${strikeList(b.legs)}. Theta acceleration starts now.`,
      link: `hedge://leg/${b.legs[0].id}`,
    }),
    theta_critical: (t, b) => ({
      title: b.legs.length === 1
        ? `${t} $${Math.round(Number(b.legs[0].strike))}${b.legs[0].option_type[0]} is critical`
        : `${t}: ${ct(b)} legs critical`,
      body: `7 days to expiry on ${strikeList(b.legs)}. Burn is steep, roll or commit.`,
      link: `hedge://leg/${b.legs[0].id}`,
    }),
    short_call_itm: (t, b) => ({
      title: ct(b) === 1
        ? `${t} short call is ITM`
        : `${t}: ${ct(b)} short calls ITM`,
      body: `Spot $${b.spot.toFixed(2)} at or above ${strikeList(b.legs)}. Assignment risk.`,
      link: `trades://leg/${b.legs[0].id}`,
    }),
    long_put_itm: (t, b) => ({
      title: ct(b) === 1
        ? `${t} long put is ITM`
        : `${t}: ${ct(b)} long puts ITM`,
      body: `Spot $${b.spot.toFixed(2)} at or below ${strikeList(b.legs)}. Hedge is active.`,
      link: `hedge://leg/${b.legs[0].id}`,
    }),
  };

  for (const [cat, byTicker] of buckets) {
    for (const [ticker, b] of byTicker) {
      const c = COPY[cat](ticker, b);
      await enqueue(queued, supabase, {
        category: cat,
        // One per ticker per category per day, NOT one per leg.
        dedup_key: `${cat}:${ticker}:${todayEST}`,
        ticker,
        title: c.title,
        body: c.body,
        deep_link: c.link,
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

  // system health alerts — pull unresolved rows from system_alerts.
  // health-monitor raises these (mp_refresh_stale, ibkr_flex_stale,
  // etc.); we mirror them into alert_dispatch so the push pipeline
  // delivers them to APNs. Dedup_key includes the alert id so a
  // single alert fires push at most once even if the dispatcher
  // sees it across many minute-cron runs.
  //
  // We deliberately don't push for 'warn' tier — those are transient
  // (Polygon hiccup) and self-resolve within a cron cycle. Only
  // 'critical' interrupts the user.
  const { data: sysAlerts } = await supabase
    .from('system_alerts')
    .select('id, code, severity, title, detail, created_at, resolved_at')
    .is('resolved_at', null)
    .eq('severity', 'critical');

  for (const a of (sysAlerts ?? []) as Array<{
    id: string;
    code: string;
    severity: string;
    title: string;
    detail: string | null;
    created_at: string;
  }>) {
    await enqueue(queued, supabase, {
      category: 'system_health',
      dedup_key: `system:${a.id}`,    // alert.id is stable per-incident
      ticker: 'SYSTEM',                // placeholder — system alerts aren't per-ticker
      title: a.title,
      body: a.detail ?? 'Open Sunnyfi to investigate.',
      deep_link: 'app://settings',
      meta: { code: a.code, severity: a.severity, created_at: a.created_at },
    });
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
