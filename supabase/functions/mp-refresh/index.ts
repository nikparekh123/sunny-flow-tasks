/**
 * mp-refresh — refresh option Greeks/OI/IV + ticker quotes for the
 * /portfolio master page.
 *
 * Reads:
 *   - public.option_trades  (open legs with remaining contracts > 0)
 *   - public.positions      (held tickers with quantity > 0, status=open)
 * Writes (append):
 *   - public.option_greeks  (one new row per open option trade per
 *     cron run; latest exposed via option_greeks_latest view)
 *   - public.ticker_quotes  (one new row per held ticker per run;
 *     latest exposed via ticker_quotes_latest view)
 *
 * Polygon endpoints:
 *   - per option contract:
 *       GET /v3/snapshot/options/{underlying}/{occ_ticker}
 *     returns { results: { greeks, implied_volatility, open_interest,
 *                          day, last_quote, last_trade, fair_market_value } }
 *   - all held stocks in ONE call:
 *       GET /v2/snapshot/locale/us/markets/stocks/tickers?tickers=A,B,C
 *
 * Invoked:
 *   - Manually from the Portfolio page "↻ refresh" button.
 *   - On a 15-min cron during US market hours (separate cron migration).
 *
 * Required Supabase secret: POLYGON_API_KEY (shared with refresh-prices,
 * option-chain, etc.)
 *
 * ⚠ THETA DATA, LIVE (Nik, 9 Oct 2026). Option marks can now come from Theta
 * Data's Options Standard feed, real-time NBBO instead of Polygon's 15-minute
 * delay, through our Theta Terminal on Fly.io (infra/theta). The source is the
 * MARKS_SOURCE secret, `polygon` until the Monday comparison against IBKR, then
 * `theta`; flipping it back is the whole rollback. A body of {"compare":true}
 * pulls both, writes nothing, and returns the differences leg by leg.
 *
 * Theta is asked once per (ticker, expiry) for every strike's NBBO quote and
 * open interest. The spot is the one the quotes imply (put-call parity at the
 * strike nearest the money) and every greek is worked out here from the mid,
 * because Theta's own underlying price, and so its greeks, can be wrong (BABA
 * at 57 against 111 on 9 Oct). A leg Theta has no quote for falls back to
 * Polygon for that run.
 *
 * ⚠ EVERY 30 SECONDS (Nik, 9 Oct 2026). The cron still fires each minute in
 * market hours; a cron call refreshes twice, the second pass 30s after the
 * first. A manual call refreshes once.
 *
 * ⚠ EVERY 15 SECONDS IN THE REGULAR SESSION (Nik, 14 Oct 2026). From 9:30 to
 * 16:00 New York a cron call refreshes four times, 15 s apart. Storage stays
 * as it was: only the passes on :00 and :30 append to option_greeks and
 * ticker_quotes (their triggers feed the live tables); the passes between
 * write the live tables only.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

// ─── Polygon response shapes (only the fields we read) ──────────
interface PolyOptionSnapshot {
  greeks?: { delta?: number; gamma?: number; theta?: number; vega?: number };
  implied_volatility?: number;
  open_interest?: number;
  day?: { volume?: number; close?: number; vwap?: number };
  last_quote?: { midpoint?: number; bid?: number; ask?: number };
  last_trade?: { price?: number };
  fair_market_value?: number;
  /* ⚠ THE SPOT THIS MARK WAS QUOTED AGAINST, and the reason it is stamped. The
     stock snapshot in step 4 is a SECOND call on its own clock, and it can also
     be skipped entirely when it returns null (we keep the last good quote), so
     intrinsic computed from it is against a spot that may be minutes away from
     the mark. On a deep-ITM leg whose extrinsic is a few cents that made
     intrinsic exceed the mark and time value go negative. This field is the
     option chain's own answer and cannot drift from the mark beside it. */
  underlying_asset?: { price?: number };
}
interface PolyOptionResp {
  status?: string;
  results?: PolyOptionSnapshot;
  error?: string;
  message?: string;
}
interface PolyStockTicker {
  ticker: string;
  lastTrade?: { p?: number };
  lastQuote?: { p?: number };
  prevDay?: { c?: number };
  day?: { c?: number };
  todaysChangePerc?: number;
}
interface PolyStockResp {
  status?: string;
  tickers?: PolyStockTicker[];
  results?: PolyStockTicker[];
}

// ─── Domain shapes from our DB ──────────────────────────────────
interface OpenTradeRow {
  id: string;
  ticker: string;
  action: 'open' | 'close';
  option_type: 'call' | 'put';
  direction: 'long' | 'short';
  contracts: number;
  strike: number;
  expiry: string;     // 'YYYY-MM-DD'
  closes_trade_id: string | null;
}

// ─── Theta Data (via the Fly.io gate) ───────────────────────────
interface ThetaRow {
  contract: { symbol: string; expiration: string; right: string; strike: number };
  data: Array<Record<string, number | string>>;
}
const THETA_URL = Deno.env.get('THETA_URL') ?? '';
const THETA_KEY = Deno.env.get('THETA_PROXY_KEY') ?? '';
async function theta(path: string): Promise<ThetaRow[]> {
  const r = await fetch(`${THETA_URL}${path}${path.includes('?') ? '&' : '?'}format=json`, {
    headers: { 'x-proxy-key': THETA_KEY }, signal: AbortSignal.timeout(20_000),
  });
  if (r.status === 472 || r.status === 404) return [];   // no data for that query
  if (!r.ok) throw new Error(`theta ${r.status} ${(await r.text()).slice(0, 120)}`);
  const j = await r.json();
  return (j?.response ?? []) as ThetaRow[];
}
/** Run `fns` at most `n` at a time. */
async function pool<T>(fns: Array<() => Promise<T>>, n: number): Promise<T[]> {
  const out: T[] = new Array(fns.length); let i = 0;
  await Promise.all(Array.from({ length: Math.min(n, fns.length) }, async () => {
    while (i < fns.length) { const k = i++; out[k] = await fns[k](); }
  }));
  return out;
}
const ND = (x: number) => Math.exp(-x * x / 2) / Math.sqrt(2 * Math.PI);
function NC(x: number): number {
  const t = 1 / (1 + 0.3275911 * Math.abs(x) / Math.SQRT2);
  const y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t
    + 0.254829592) * t * Math.exp(-x * x / 2);
  return x >= 0 ? (1 + y) / 2 : (1 - y) / 2;
}
const RATE = 0.04;
/* ⚠ DIVIDENDS ARE IN THE MODEL (audit, 13 Oct 2026), the escrowed way: each
   leg is priced on spot LESS the present value of the dividends expected
   before ITS expiry (see `pvDivs`), with q left at 0. Tested on three NKE legs
   against IBKR's own greeks: no dividends put the Jan 2028 LEAP's theta at
   -0.0065 (IBKR -0.0077), a flat trailing yield at -0.0051, escrowed at
   -0.0080; the Mar 2027 put -0.0103 / -0.0111 / -0.0084 (IBKR -0.0088); a
   weekly is untouched (no ex-date before Friday) and still matches. The long
   side's theta is the Theta ratio's denominator. `q` stays for the record. */
function bsPrice(call: boolean, S: number, K: number, T: number, v: number, q = 0): number {
  const sq = v * Math.sqrt(T), d1 = (Math.log(S / K) + (RATE - q + v * v / 2) * T) / sq, d2 = d1 - sq;
  const Sq = S * Math.exp(-q * T);
  return call ? Sq * NC(d1) - K * Math.exp(-RATE * T) * NC(d2)
              : K * Math.exp(-RATE * T) * NC(-d2) - Sq * NC(-d1);
}
/** ⚠ EVERY GREEK IS WORKED OUT HERE, from the live mid at the option-implied
    spot. Theta's own greeks use its `underlying_price`, which read BABA at
    57.00 against a real 111 on 9 Oct, so its delta and IV were nonsense for
    that name. Vega is per vol point and theta per calendar day, Polygon's units. */
function greeksFrom(call: boolean, mid: number, S: number, K: number, T: number, q = 0) {
  const eq = Math.exp(-q * T), er = Math.exp(-RATE * T);
  const floor = Math.max(0, call ? S * eq - K * er : K * er - S * eq);
  if (!(S > 0 && K > 0 && T > 0) || !(mid > floor + 0.005)) return null;
  let lo = 0.01, hi = 4;
  for (let i = 0; i < 60; i++) { const m = (lo + hi) / 2; if (bsPrice(call, S, K, T, m, q) < mid) lo = m; else hi = m; }
  const v = (lo + hi) / 2, sq = v * Math.sqrt(T);
  const d1 = (Math.log(S / K) + (RATE - q + v * v / 2) * T) / sq, d2 = d1 - sq;
  const decay = -S * eq * ND(d1) * v / (2 * Math.sqrt(T));
  const carry = RATE * K * er;
  return {
    iv: v,
    delta: call ? eq * NC(d1) : eq * (NC(d1) - 1),
    gamma: eq * ND(d1) / (S * sq),
    vega: S * eq * ND(d1) * Math.sqrt(T) / 100,
    theta: (call ? decay - carry * NC(d2) + q * S * eq * NC(d1)
                 : decay + carry * NC(-d2) - q * S * eq * NC(-d1)) / 365,
  };
}
const legKey = (right: string, strike: number) => `${right.toLowerCase()}|${Number(strike).toFixed(3)}`;
/** The stock price a chain's own quotes imply: C - P + K at the strike where
    call and put are closest (both two-sided). ⚠ Theta's `underlying_price` is
    from its FREE stock tier and read BABA at 57.00 against a real 111 on
    9 Oct, so it is never used for a spot. */
function impliedSpot(rows: ThetaRow[], T: number): number | null {
  const by = new Map<number, { c?: number; p?: number }>();
  for (const r of rows) {
    const d = r.data?.[0]; if (!d) continue;
    const bid = Number(d.bid), ask = Number(d.ask);
    if (!(bid > 0 && ask > 0)) continue;
    const k = Number(r.contract.strike), e = by.get(k) ?? {};
    e[r.contract.right.toLowerCase() === 'call' ? 'c' : 'p'] = (bid + ask) / 2; by.set(k, e);
  }
  let best: number | null = null, gap = Infinity;
  for (const [k, e] of by) {
    if (e.c == null || e.p == null) continue;
    if (Math.abs(e.c - e.p) < gap) { gap = Math.abs(e.c - e.p); best = e.c - e.p + k * Math.exp(-0.04 * T); }
  }
  return best;
}

// ─── Helpers ────────────────────────────────────────────────────
const positive = (n: number | undefined | null): number | null =>
  typeof n === 'number' && n > 0 ? n : null;

/* ⚠ THE MIDPOINT IS THE MARK, AND THE LAST TRADE IS THE LAST RESORT. Nik chose
   this on 27 Aug after the two screens disagreed by $254 with the market shut,
   which was never a timing gap: open-premium reads the midpoint and this read
   the last trade, so they were two different definitions of one word.

   A last trade can be hours old on a thin contract and can print BELOW
   INTRINSIC, which no live two-sided market ever does — PEP's 144 put last
   traded at 3.17 against 3.99 of intrinsic on a 2-lot. That stale print is what
   drove time value negative. A midpoint is always a current quote, so it cannot.

   The order below is therefore: the quote's own midpoint, a midpoint we compute
   from bid and ask, the day's close, the last trade, and only then Polygon's
   fair value. The last trade is kept because a quote can vanish outside hours
   and a stale print beats no price at all — the per-leg clamp in sunny-rail is
   what stops it lying when it is the one we fall to. */
const pickPremium = (s: PolyOptionSnapshot): number | null => {
  const mid = positive(s.last_quote?.midpoint);
  if (mid != null) return mid;
  const bid = positive(s.last_quote?.bid);
  const ask = positive(s.last_quote?.ask);
  if (bid != null && ask != null) return (bid + ask) / 2;
  const dc = positive(s.day?.close);
  if (dc != null) return dc;
  const lt = positive(s.last_trade?.price);
  if (lt != null) return lt;
  return positive(s.fair_market_value);
};

/** OCC option symbol: O:TICKER YYMMDD C/P 00000000 (strike × 1000, 8 digits).
 *  Example: META 2026-06-19 call $660 → "O:META260619C00660000". */
function occSymbol(ticker: string, expiry: string, type: 'call' | 'put', strike: number): string {
  const yy = expiry.slice(2, 4);
  const mm = expiry.slice(5, 7);
  const dd = expiry.slice(8, 10);
  const k  = Math.round(strike * 1000).toString().padStart(8, '0');
  const cp = type === 'call' ? 'C' : 'P';
  return `O:${ticker}${yy}${mm}${dd}${cp}${k}`;
}

/** Pooled-FIFO remaining-contracts, mirroring the iOS OptionFIFO
 *  (ios-app/.../OptionFIFO.swift). Groups by contract key
 *  (ticker, option_type, direction, strike, expiry) and consumes closes
 *  oldest-first, IGNORING closes_trade_id — that single-FK link cannot
 *  represent multi-lot chains and is set naively by the sync.
 *
 *  WHY THIS CHANGED (2026-07-09): the prior per-id logic here disagreed
 *  with the app. It (a) left over-closed opens looking forever-open, so
 *  mp-refresh 404-quoted expired contracts every run, and (b) skipped
 *  genuinely-open legs whose open had a close wrongly linked to it —
 *  freezing those legs' marks (Value now / Time value went stale, some
 *  back to June 1). Pooling by key matches the app's open set exactly. */
function remainingByOpenId(trades: OpenTradeRow[]): Map<string, number> {
  const keyOf = (t: OpenTradeRow) =>
    `${t.ticker.toUpperCase()}|${t.option_type}|${t.direction}|${t.strike}|${t.expiry}`;

  const groups = new Map<string, OpenTradeRow[]>();
  for (const t of trades) {
    const k = keyOf(t);
    const arr = groups.get(k);
    if (arr) arr.push(t); else groups.set(k, [t]);
  }

  const out = new Map<string, number>();
  for (const rows of groups.values()) {
    // Stable oldest-first by id (trade_date isn't selected here; the
    // per-key TOTAL remaining is order-independent, and all opens in a
    // key share one OCC symbol, so id-order is a safe proxy).
    const opens = rows
      .filter((r) => r.action === 'open')
      .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
    let closeQty = rows
      .filter((r) => r.action === 'close')
      .reduce((s, c) => s + c.contracts, 0);

    const slots = opens.map((o) => ({ id: o.id, left: o.contracts }));
    let cursor = 0;
    while (closeQty > 0 && cursor < slots.length) {
      const take = Math.min(closeQty, slots[cursor].left);
      slots[cursor].left -= take;
      closeQty -= take;
      if (slots[cursor].left <= 0) cursor++;
    }
    for (const s of slots) out.set(s.id, Math.max(0, s.left));
  }
  return out;
}

// ─── Handler ────────────────────────────────────────────────────
/* ⚠ WHO MAY CALL (audit, 13 Oct 2026). verify_jwt is off so pg_cron can call
   in, so the function checks instead: the scheduler's x-cron-key (vault
   `cron_secret`, secret CRON_SECRET; sent as x-admin-key for a manual
   admin call), the service-role key, or, where `users`
   is set, a signed-in user of the app or website. Anyone else gets a 401. */
async function callerOk(req: Request, users: boolean): Promise<boolean> {
  const cron = Deno.env.get('CRON_SECRET');
  if (cron && (req.headers.get('x-cron-key') === cron || req.headers.get('x-admin-key') === cron)) return true;
  const auth = req.headers.get('authorization') ?? '';
  if (auth && auth === `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`) return true;
  if (!users || !auth.startsWith('Bearer ')) return false;
  const r = await fetch(`${Deno.env.get('SUPABASE_URL')}/auth/v1/user`,
    { headers: { apikey: Deno.env.get('SUPABASE_ANON_KEY') ?? '', Authorization: auth } });
  await r.body?.cancel();
  return r.ok;
}
const refused = () => new Response(JSON.stringify({ ok: false, error: 'not allowed' }),
  { status: 401, headers: { 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method !== 'OPTIONS' && !(await callerOk(req, true))) return refused();
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }
  let body: { source?: string; compare?: boolean; passes?: number; shadow?: boolean } = {};
  try { if (req.method === 'POST') body = await req.json(); } catch { /* no body is fine */ }
  const t0 = Date.now();
  const fromCron = req.headers.get('user-agent')?.includes('pg_net') ?? false;
  /* ⚠ NEW YORK DECIDES, NOT THE CRON (12 Oct 2026). pg_cron speaks UTC, so a
     fixed 13-20 UTC window is 9:00-16:59 in summer but 8:00-15:59 once the
     clocks go back on 1 Nov, and the 4:00 close would never be marked. The
     cron now fires 13-21 UTC and a scheduled call outside 9:00-16:59 New
     York on a weekday returns at once. A manual call always runs. */
  /* Compare mode lists every leg and its marks: service-role key only
     (audit, 13 Oct 2026; verify_jwt is off for pg_cron). */
  if (body.compare && req.headers.get('authorization') !== `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`
      && !(Deno.env.get('CRON_SECRET') && req.headers.get('x-admin-key') === Deno.env.get('CRON_SECRET'))) {
    return new Response(JSON.stringify({ ok: false, error: 'compare needs the service-role key' }),
      { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
  if (fromCron) {
    const p = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York',
      weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
      .formatToParts(new Date()).map((x) => [x.type, x.value]));
    const mins = Number(p.hour) * 60 + Number(p.minute);
    if (['Sat', 'Sun'].includes(p.weekday) || mins < 9 * 60 || mins >= 17 * 60) {
      return new Response(JSON.stringify({ ok: true, skipped: 'outside 9:00-16:59 New York' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
  }
  const nyNow = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York',
    weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
    .formatToParts(new Date()).map((x) => [x.type, x.value]));
  const nyMins = Number(nyNow.hour) * 60 + Number(nyNow.minute);
  const regular = !['Sat', 'Sun'].includes(nyNow.weekday) && nyMins >= 9 * 60 + 30 && nyMins < 16 * 60;
  const passes = Math.max(1, Math.min(4, body.passes ?? (fromCron ? (regular ? 4 : 2) : 1)));
  const step = passes === 4 ? 15_000 : 30_000;
  let last: Response | null = null;
  for (let i = 0; i < passes; i++) {
    /* Each pass lands `step` after the previous one STARTED. */
    if (i > 0) await new Promise((r) => setTimeout(r, Math.max(0, t0 + i * step - Date.now())));
    last = await refresh(req, body, { history: passes !== 4 || i % 2 === 0 });
    if (body.compare) break;
  }
  return last!;
});

async function refresh(req: Request, body: { source?: string; compare?: boolean; shadow?: boolean },
                       opts: { history: boolean } = { history: true }): Promise<Response> {
  const now = new Date().toISOString();
  const source = (body.source ?? Deno.env.get('MARKS_SOURCE') ?? 'polygon').toLowerCase();
  const useTheta = (source === 'theta' || body.compare) && !!THETA_URL && !!THETA_KEY;
  const supabaseUrl    = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const polygonKey     = Deno.env.get('POLYGON_API_KEY');

  if (!polygonKey) {
    return new Response(
      JSON.stringify({ error: 'POLYGON_API_KEY is not set as a Supabase secret' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Heuristic: pg_cron POSTs via pg_net which doesn't forward an
  // `Authorization` header beyond service-role; browser/curl traffic
  // does. Not perfect but good enough to colour-code rows in /health.
  const invokedBy = req.headers.get('user-agent')?.includes('pg_net') ? 'cron' : 'manual';

  // Log the run upfront so /health can see "still running" if we ever
  // hang. The id lets the completion update target this exact row.
  let runId: string | null = null;
  try {
    const { data: runRow, error: insErr } = await admin
      .from('mp_refresh_runs' as never)
      .insert({ started_at: now, status: 'running', invoked_by: invokedBy } as never)
      .select('id')
      .single();
    if (!insErr && runRow) runId = (runRow as { id: string }).id;
  } catch { /* logging is best-effort; never block the actual refresh */ }

  /** Finalize the log row with status + counts. Best-effort — never
   *  throws (we don't want a logging glitch to fail the whole run). */
  const finishRun = async (
    status: 'ok' | 'error',
    extra: Record<string, unknown>,
  ) => {
    if (!runId) return;
    try {
      await admin
        .from('mp_refresh_runs' as never)
        .update({ finished_at: new Date().toISOString(), status, ...extra } as never)
        .eq('id', runId);
    } catch { /* swallow */ }
  };

  try {

    // ─── 1. Read open option legs with remaining contracts > 0 ──
    /* ⚠ PAGED (12 Oct 2026). PostgREST returns at most 1,000 rows a request,
       silently. option_trades crossed 1,000 on 9 Oct and the newest legs
       (BABA 111/114, LULU 94, two LEAP lots) fell off the end and were never
       marked, which is what made Credit & theta read 56% low. */
    const tradeRows: OpenTradeRow[] = [];
    for (let from = 0; from < 50_000; from += 1000) {
      const { data, error: tradesErr } = await admin
        .from('option_trades')
        .select('id, ticker, action, option_type, direction, contracts, strike, expiry, closes_trade_id')
        .is('voided_at', null)
        .order('id', { ascending: true })
        .range(from, from + 999);
      if (tradesErr) throw tradesErr;
      tradeRows.push(...((data ?? []) as OpenTradeRow[]));
      if (!data || data.length < 1000) break;
    }

    const remaining = remainingByOpenId(tradeRows);
    // Today in US-Eastern (the market clock) as 'YYYY-MM-DD'. Skip legs
    // whose expiry is already past — Polygon 404s expired contracts, and
    // an expired leg isn't a live position anyway.
    const estToday = new Date().toLocaleDateString('en-CA', {
      timeZone: 'America/New_York',
    });
    const openLegs = tradeRows.filter(
      (t) => t.action === 'open'
        && (remaining.get(t.id) ?? 0) > 0
        && t.expiry >= estToday,
    ) as OpenTradeRow[];

    // ─── 2. Read held tickers (open positions with qty > 0) ──────
    const { data: posRows, error: posErr } = await admin
      .from('positions')
      .select('ticker, quantity, status');
    if (posErr) throw posErr;
    const heldTickers = Array.from(new Set(
      (posRows ?? [])
        .filter((p) => p.status === 'open' && p.quantity > 0)
        .map((p) => p.ticker.toUpperCase()),
    ));
    // Union held tickers with option-leg tickers (we want quotes for both
    // — the user might hold options on something they don't own outright).
    /* The market tapes are quoted every minute too (Nik, 28 Sep 2026): SPY,
       QQQ, IWM are read like the book's names, never held. Every reader of
       ticker_quotes looks a name up, so an extra row adds no card row. */
    const MARKET = ['SPY', 'QQQ', 'IWM'];
    const allTickers = Array.from(new Set([
      ...heldTickers,
      ...openLegs.map((l) => l.ticker.toUpperCase()),
      ...MARKET,
    ]));

    // ─── 3. Per-leg option snapshot calls ───────────────────────
    const legResults: Array<{
      id: string; delta: number | null; gamma: number | null;
      theta: number | null; vega: number | null;
      iv: number | null; oi: number | null; vol: number | null;
      last_mark: number | null; underlying: number | null;
    }> = [];
    const legFailures: Array<{ id: string; ticker: string; occ: string; reason: string }> = [];

    // Sequential fetch — Polygon's options-snapshot rate limits are gentler
    // than burst; a parallel storm on 50+ contracts trips throttling. If
    // we ever need throughput, switch to a small concurrency pool.
    //
    // Auth via the `Authorization: Bearer <key>` HEADER, not the
    // `?apiKey=` query param the older functions use. Massive.com (which
    // proxies Polygon) accepts only the header form and returns 403 for
    // query-param auth; Polygon itself accepts both. So Bearer is the
    // strict superset that works against either backend.
    const authHeaders = { Authorization: `Bearer ${polygonKey}` };

    /* THETA, one call per (ticker, expiry) for every strike's NBBO + first-
       order greeks, one for open interest. Two groups at a time = the plan's
       four concurrent requests. */
    type TV = { mark: number | null; delta: number | null; theta: number | null; vega: number | null;
                gamma: number | null; iv: number | null; oi: number | null; underlying: number | null;
                bid: number | null; ask: number | null };
    const thetaBy = new Map<string, TV>();
    let thetaErr: string | null = null;
    let shadowNote: unknown = null;
    if (useTheta) {
      const groups = [...new Set(openLegs.map((l) => `${l.ticker.toUpperCase()}|${l.expiry}`))];
      try {
        const res = await pool(groups.map((g) => async () => {
          const [t, e] = g.split('|'); const ex = e.replaceAll('-', '');
          const [gr, oi] = await Promise.all([
            theta(`/v3/option/snapshot/quote?symbol=${t}&expiration=${ex}`),
            theta(`/v3/option/snapshot/open_interest?symbol=${t}&expiration=${ex}`).catch(() => [] as ThetaRow[]),
          ]);
          return { t, e, gr, oi };
        }), 2);
        /* ⚠ ONE SPOT PER NAME, FROM ITS NEAREST EXPIRY. Parity on a two-year
           LEAP gives the forward, not today's price (BABA's Jan 2028 chain
           implied 117.75 against 111.4), so every expiry of a name is priced
           against the spot its nearest weekly implies. */
        const yrs = (e: string) => Math.max(1 / 365, (Date.parse(`${e}T20:00:00Z`) - Date.now()) / (365 * 864e5));
        const spotOf = new Map<string, number>();
        for (const { t, e, gr } of [...res].sort((a, b) => a.e.localeCompare(b.e))) {
          if (spotOf.has(t)) continue;
          const sx = impliedSpot(gr, yrs(e));
          if (sx != null) spotOf.set(t, sx);
        }
        /* ⚠ A NAME HOLDING ONLY LONG-DATED LEGS ASKS FOR ITS NEAREST LISTED
           EXPIRY (audit, 13 Oct 2026). KR's only leg is the Jan 2028 LEAP, and
           parity two years out is dragged down by the dividends paid before
           then: 61.74 against IBKR's 62.56 close. Anything whose nearest held
           expiry is over 45 days away now prices off the nearest weekly. */
        const farOnly = [...spotOf.keys()].filter((t) => {
          const e = res.filter((r) => r.t === t).map((r) => r.e).sort()[0];
          return (Date.parse(`${e}T20:00:00Z`) - Date.now()) / 864e5 > 45;
        });
        await pool(farOnly.map((t) => async () => {
          try {
            const ex = (await fetch(`${THETA_URL}/v3/option/list/expirations?symbol=${t}&format=json`,
              { headers: { 'x-proxy-key': THETA_KEY }, signal: AbortSignal.timeout(15_000) })
              .then((r) => r.ok ? r.json() : { response: [] })).response as Array<{ expiration: string }>;
            const next = ex.map((x) => x.expiration).filter((e) => e > estToday).sort()[0];
            if (!next) return;
            const rows = await theta(`/v3/option/snapshot/quote?symbol=${t}&expiration=${next.replaceAll('-', '')}`);
            const sx = impliedSpot(rows, yrs(next));
            if (sx != null) spotOf.set(t, sx);
          } catch { /* keep the long-dated estimate */ }
        }), 2);
        /* Expected dividends per name: every declared ex-date still ahead, then
           the last regular dividend repeated at its own cadence (frequency, or
           the gap between the last two). Regular cash dividends only. */
        const divPlan = new Map<string, Array<{ d: number; amt: number }>>();
        try {
          const since = new Date(Date.now() - 800 * 864e5).toISOString().slice(0, 10);
          const { data: dv } = await admin.from('dividends')
            .select('ticker, ex_date, cash_amount, frequency, dividend_type')
            .in('ticker', [...spotOf.keys()]).gte('ex_date', since).order('ex_date', { ascending: true });
          const by = new Map<string, Array<{ ex: string; amt: number; freq: number | null }>>();
          for (const d of (dv ?? []) as Array<{ ticker: string; ex_date: string; cash_amount: number | null;
                                                frequency: number | null; dividend_type: string | null }>) {
            if (d.dividend_type && d.dividend_type !== 'CD') continue;      // specials do not repeat
            if (!(Number(d.cash_amount) > 0)) continue;
            (by.get(d.ticker) ?? by.set(d.ticker, []).get(d.ticker)!).push(
              { ex: d.ex_date, amt: Number(d.cash_amount), freq: d.frequency });
          }
          const now0 = Date.parse(`${estToday}T12:00:00Z`);
          for (const [t, rows] of by) {
            const plan: Array<{ d: number; amt: number }> = rows.filter((r) => r.ex > estToday)
              .map((r) => ({ d: Date.parse(`${r.ex}T12:00:00Z`), amt: r.amt }));
            const past = rows.filter((r) => r.ex <= estToday);
            const last = past.at(-1), prev = past.at(-2);
            const gap = last?.freq && last.freq > 0 ? 365 / last.freq
              : last && prev ? (Date.parse(last.ex) - Date.parse(prev.ex)) / 864e5 : null;
            if (last && gap && gap >= 25) {
              let d = Date.parse(`${last.ex}T12:00:00Z`) + gap * 864e5;
              const lastDeclared = plan.length ? Math.max(...plan.map((p) => p.d)) : 0;
              while (d < now0 + 3 * 365 * 864e5) {
                if (d > now0 && d > lastDeclared + gap * 0.5 * 864e5) plan.push({ d, amt: last.amt });
                d += gap * 864e5;
              }
            }
            divPlan.set(t, plan.sort((a, b) => a.d - b.d));
          }
        } catch { /* no dividends: priced as before */ }
        /** PV of the dividends expected before `expiry`, at the model's rate. */
        const pvDivs = (t: string, expiry: string) => {
          const end = Date.parse(`${expiry}T20:00:00Z`), now1 = Date.now();
          return (divPlan.get(t) ?? []).filter((x) => x.d > now1 && x.d < end)
            .reduce((s, x) => s + x.amt * Math.exp(-RATE * (x.d - now1) / (365 * 864e5)), 0);
        };
        for (const { t, e, gr, oi } of res) {
          const oiBy = new Map(oi.map((r) => [legKey(r.contract.right, r.contract.strike),
                                             Number(r.data?.[0]?.open_interest)]));
          const T = Math.max(1 / 365, (Date.parse(`${e}T20:00:00Z`) - Date.now()) / (365 * 864e5));
          const Sx = spotOf.get(t) ?? null;
          /* Priced on spot less the dividends due before this expiry. */
          const Sd = Sx != null ? Math.max(0.01, Sx - pvDivs(t, e)) : null;
          for (const r of gr) {
            const d = r.data?.[0]; if (!d) continue;
            const bid = Number(d.bid), ask = Number(d.ask);
            /* The midpoint is the mark (27 Aug ruling). A one-sided market
               with no bid marks at half the ask; no quote at all falls back. */
            const mark = bid > 0 && ask > 0 ? (bid + ask) / 2 : ask > 0 ? ask / 2 : null;
            const k = legKey(r.contract.right, r.contract.strike);
            const fin = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
            const g = mark != null && Sd != null
              ? greeksFrom(r.contract.right.toLowerCase() === 'call', mark, Sd, Number(r.contract.strike), T)
              : null;
            thetaBy.set(`${t}|${e}|${k}`, {
              mark, bid: fin(bid), ask: fin(ask),
              delta: g?.delta ?? null, theta: g?.theta ?? null, vega: g?.vega ?? null,
              gamma: g?.gamma ?? null, iv: g?.iv ?? null,
              oi: fin(oiBy.get(k)) ?? null, underlying: Sx,
            });
          }
        }
        /* ── LEAP MODEL PRICES, SHADOW ONLY (Nik, 14 Oct 2026) ──────────
           IBKR values the LEAPs with its own model inside wide quotes (NKE
           Jan 2028 30C closed 8.70 x 10.15: our mid 9.43, IBKR 8.99), so the
           account read $3.6K above IBKR. Three model prices are logged beside
           the midpoint at the close and compared each night with IBKR's own
           statement mark (view leap_model_vs_ibkr). Nothing reads them yet;
           the app keeps the midpoint until one wins. Same model as the marks:
           r 4%, spot less the dividends due before the expiry. */
        const nyP = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York',
          hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(new Date()).map((x) => [x.type, x.value]));
        const nyM = Number(nyP.hour) * 60 + Number(nyP.minute);
        if (body.shadow === true || (nyM >= 15 * 60 + 58 && nyM <= 16 * 60 + 45)) {
          try {
            type Lp = { t: string; e: string; k: number; call: boolean; n: number; ids: string[] };
            const leaps = new Map<string, Lp>();
            for (const l of openLegs) {
              if (l.direction !== 'long' || yrs(l.expiry) < 0.5) continue;
              const key = `${l.ticker.toUpperCase()}|${l.expiry}|${l.option_type}|${Number(l.strike)}`;
              const cur = leaps.get(key) ?? { t: l.ticker.toUpperCase(), e: l.expiry, k: Number(l.strike),
                                               call: l.option_type === 'call', n: 0, ids: [] };
              cur.n += remaining.get(l.id) ?? 0; cur.ids.push(l.id); leaps.set(key, cur);
            }
            const L = [...leaps.values()].filter((x) => x.n > 0);
            const since = new Date(Date.now() - 12 * 864e5).toISOString().slice(0, 10);
            const [lmd, apd] = await Promise.all([
              admin.from('leg_marks_daily').select('option_trade_id, day, iv')
                .in('option_trade_id', L.flatMap((x) => x.ids)).gte('day', since).lt('day', estToday),
              admin.from('account_positions_daily').select('report_date, underlying, put_call, strike, expiry, mark_price')
                .eq('asset_category', 'OPT').gte('report_date', since).lt('report_date', estToday)
                .in('underlying', [...new Set(L.map((x) => x.t))]),
            ]);
            const ivDays = (lmd.data ?? []) as Array<{ option_trade_id: string; day: string; iv: number | null }>;
            const ib = (apd.data ?? []) as Array<{ report_date: string; underlying: string; put_call: string;
                                                   strike: number; expiry: string; mark_price: number }>;
            const ibDays = [...new Set(ib.map((r) => r.report_date))];
            const cl = ibDays.length ? ((await admin.from('daily_closes').select('ticker, date, close_price')
              .in('ticker', [...new Set(L.map((x) => x.t))]).in('date', ibDays)).data ?? []) as
              Array<{ ticker: string; date: string; close_price: number }> : [];
            const median = (v: number[]) => { const a = [...v].sort((x, y) => x - y); return a.length ? a[Math.floor(a.length / 2)] : null; };
            const rowsOut: Array<Record<string, unknown>> = [];
            for (const x of L) {
              const T = yrs(x.e), Sx = spotOf.get(x.t); if (Sx == null) continue;
              const pv = pvDivs(x.t, x.e), Sd = Math.max(0.01, Sx - pv);
              const tv = thetaBy.get(`${x.t}|${x.e}|${legKey(x.call ? 'call' : 'put', x.k)}`);
              const mid = tv?.mark ?? null;
              const price = (v: number | null) => (v != null && v > 0.01 && v < 4 ? bsPrice(x.call, Sd, x.k, T, v) : null);
              // 1. Smoothed: the median of this contract's daily IVs, last five sessions.
              const byDay = new Map<string, number>();
              for (const r of ivDays) if (x.ids.includes(r.option_trade_id) && r.iv != null) byDay.set(r.day, Number(r.iv));
              const ivSmooth = median([...byDay.entries()].sort((a, b) => b[0].localeCompare(a[0])).slice(0, 5).map((e) => e[1]));
              // 2. IBKR-anchored: the IV IBKR's last statement mark implies, repriced now.
              const last = ib.filter((r) => r.underlying === x.t && r.put_call === (x.call ? 'C' : 'P')
                && Number(r.strike) === x.k && String(r.expiry) === x.e).sort((a, b) => b.report_date.localeCompare(a.report_date))[0];
              let ivIb: number | null = null;
              if (last) {
                const S0 = cl.find((c) => c.ticker === x.t && c.date === last.report_date)?.close_price;
                const T0 = Math.max(1 / 365, (Date.parse(`${x.e}T20:00:00Z`) - Date.parse(`${last.report_date}T20:00:00Z`)) / (365 * 864e5));
                if (S0) ivIb = greeksFrom(x.call, Number(last.mark_price), Math.max(0.01, Number(S0) - pv), x.k, T0)?.iv ?? null;
              }
              // 3. Smile: IVs of the same expiry's tight out-of-the-money strikes, fitted at this strike.
              const chain = res.find((r) => r.t === x.t && r.e === x.e)?.gr ?? [];
              const pts: Array<{ x: number; iv: number; w: number }> = [];
              for (const r of chain) {
                const d = r.data?.[0]; if (!d) continue;
                const b = Number(d.bid), a = Number(d.ask); if (!(b > 0 && a > 0)) continue;
                const m = (a + b) / 2, sp = (a - b) / m; if (sp > 0.12) continue;
                const K = Number(r.contract.strike), isCall = r.contract.right.toLowerCase() === 'call';
                if (isCall ? K < Sx : K >= Sx) continue;
                const lx = Math.log(K / Sd); if (Math.abs(lx) > 0.6) continue;
                const v = greeksFrom(isCall, m, Sd, K, T)?.iv; if (v == null) continue;
                pts.push({ x: lx, iv: v, w: 1 / Math.max(sp, 0.01) });
              }
              let ivSmile: number | null = null;
              if (pts.length >= 3) {
                const quad = pts.length >= 6;
                // Weighted least squares on [1, x, x^2] (or [1, x]).
                const n = quad ? 3 : 2, A = Array.from({ length: n }, () => Array(n).fill(0)), B = Array(n).fill(0);
                for (const p of pts) {
                  const f = quad ? [1, p.x, p.x * p.x] : [1, p.x];
                  for (let i = 0; i < n; i++) { B[i] += p.w * f[i] * p.iv; for (let j = 0; j < n; j++) A[i][j] += p.w * f[i] * f[j]; }
                }
                for (let i = 0; i < n; i++) {          // Gauss-Jordan
                  let piv = i; for (let r2 = i + 1; r2 < n; r2++) if (Math.abs(A[r2][i]) > Math.abs(A[piv][i])) piv = r2;
                  [A[i], A[piv]] = [A[piv], A[i]]; [B[i], B[piv]] = [B[piv], B[i]];
                  const dv = A[i][i]; if (Math.abs(dv) < 1e-12) { ivSmile = null; break; }
                  for (let j = 0; j < n; j++) A[i][j] /= dv; B[i] /= dv;
                  for (let r2 = 0; r2 < n; r2++) if (r2 !== i) { const f = A[r2][i]; for (let j = 0; j < n; j++) A[r2][j] -= f * A[i][j]; B[r2] -= f * B[i]; }
                  ivSmile = 0;
                }
                if (ivSmile != null) {
                  const x0 = Math.log(x.k / Sd), xs = Math.max(Math.min(...pts.map((p) => p.x)), Math.min(Math.max(...pts.map((p) => p.x)), x0));
                  ivSmile = B[0] + B[1] * xs + (quad ? B[2] * xs * xs : 0);
                }
              }
              const r3 = (v: number | null) => (v == null || !Number.isFinite(v) ? null : Math.round(v * 10000) / 10000);
              rowsOut.push({ day: estToday, ticker: x.t, put_call: x.call ? 'C' : 'P', strike: x.k, expiry: x.e, position: x.n,
                spot: r3(Sx), bid: tv?.bid ?? null, ask: tv?.ask ?? null, mid, iv_mid: r3(tv?.iv ?? null),
                iv_smooth: r3(ivSmooth), m_smooth: r3(price(ivSmooth)),
                iv_ibkr: r3(ivIb), m_ibkr: r3(price(ivIb)), ibkr_from: last?.report_date ?? null,
                iv_smile: r3(ivSmile), m_smile: r3(price(ivSmile)), smile_points: pts.length,
                captured_at: new Date().toISOString() });
            }
            if (rowsOut.length) {
              const { error } = await admin.from('leap_model_shadow').upsert(rowsOut, { onConflict: 'day,ticker,put_call,strike,expiry' });
              shadowNote = error ? { error: error.message } : { rows: rowsOut.length, sample: rowsOut.slice(0, 8) };
            } else shadowNote = { rows: 0 };
          } catch (e) { shadowNote = { error: (e as Error).message }; }
        }
      } catch (err) { thetaErr = (err as Error).message; }
    }
    const thetaOf = (leg: OpenTradeRow) =>
      thetaBy.get(`${leg.ticker.toUpperCase()}|${leg.expiry}|${legKey(leg.option_type, leg.strike)}`);
    const compareRows: Array<Record<string, unknown>> = [];
    let thetaUsed = 0;

    for (const leg of openLegs) {
      const tv = thetaOf(leg);
      if (useTheta && !body.compare && tv && tv.mark != null) {
        thetaUsed++;
        legResults.push({ id: leg.id, delta: tv.delta, gamma: tv.gamma, theta: tv.theta, vega: tv.vega,
                          iv: tv.iv, oi: tv.oi, vol: null, last_mark: tv.mark, underlying: tv.underlying });
        continue;
      }
      const occ = occSymbol(leg.ticker.toUpperCase(), leg.expiry, leg.option_type, leg.strike);
      const url = `https://api.polygon.io/v3/snapshot/options/${leg.ticker.toUpperCase()}/${occ}`;
      try {
        const resp = await fetch(url, { headers: authHeaders });
        if (!resp.ok) {
          legFailures.push({ id: leg.id, ticker: leg.ticker, occ, reason: `HTTP ${resp.status}` });
          continue;
        }
        const data = (await resp.json()) as PolyOptionResp;
        const s = data.results;
        if (!s) {
          legFailures.push({ id: leg.id, ticker: leg.ticker, occ, reason: 'no results' });
          continue;
        }
        if (body.compare) {
          compareRows.push({ leg: occ, polygon: pickPremium(s), theta: tv?.mark ?? null,
                             bid: tv?.bid ?? null, ask: tv?.ask ?? null,
                             delta_p: s.greeks?.delta ?? null, delta_t: tv?.delta ?? null,
                             iv_p: s.implied_volatility ?? null, iv_t: tv?.iv ?? null,
                             spot_p: s.underlying_asset?.price ?? null, spot_t: tv?.underlying ?? null });
          continue;
        }
        legResults.push({
          id: leg.id,
          delta:     s.greeks?.delta ?? null,
          gamma:     s.greeks?.gamma ?? null,
          theta:     s.greeks?.theta ?? null,
          vega:      s.greeks?.vega ?? null,
          iv:        s.implied_volatility ?? null,
          oi:        s.open_interest ?? null,
          vol:       s.day?.volume ?? null,
          last_mark: pickPremium(s),
          underlying: s.underlying_asset?.price ?? null,
        });
      } catch (err) {
        legFailures.push({ id: leg.id, ticker: leg.ticker, occ, reason: (err as Error).message });
      }
    }

    if (body.compare) {
      await finishRun('ok', { legs_total: openLegs.length, legs_updated: 0, error_text: 'compare only, nothing written' });
      return new Response(JSON.stringify({ ok: true, compare: true, theta_error: thetaErr,
        legs: openLegs.length, theta_quoted: [...thetaBy.values()].filter((v) => v.mark != null).length,
        rows: compareRows }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // ─── 4. Stock prices ────────────────────────────────────────
    /* ⚠ POLYGON'S SNAPSHOTS ARE GONE (12 Oct 2026). From the open every stock
       and option snapshot answered 403 "not entitled": the plan changed when
       the add-ons were cancelled, and only daily history still works. So with
       Theta on, every spot is the one the option quotes imply: a name with a
       leg uses the spot already worked out for its legs, any other name (the
       SPY/QQQ/IWM tapes) asks Theta for its nearest expiry and works it out
       the same way. The day's change is against the last stored close in
       daily_closes. Polygon's snapshot stays as the last resort, for the day
       the plan allows it again. */
    const stockResults: Array<{ ticker: string; spot: number | null; day_change_pct: number | null }> = [];
    if (allTickers.length > 0) {
      const spotBy = new Map<string, number>();
      if (useTheta) {
        for (const l of openLegs) {
          const u = thetaOf(l)?.underlying;
          if (typeof u === 'number' && u > 0 && !spotBy.has(l.ticker.toUpperCase())) spotBy.set(l.ticker.toUpperCase(), u);
        }
        const rest = allTickers.filter((t) => !spotBy.has(t));
        await pool(rest.map((t) => async () => {
          try {
            const ex = (await fetch(`${THETA_URL}/v3/option/list/expirations?symbol=${t}&format=json`,
              { headers: { 'x-proxy-key': THETA_KEY }, signal: AbortSignal.timeout(15_000) })
              .then((r) => r.ok ? r.json() : { response: [] })).response as Array<{ expiration: string }>;
            const next = ex.map((x) => x.expiration).filter((e) => e > estToday).sort()[0];
            if (!next) return;
            const rows = await theta(`/v3/option/snapshot/quote?symbol=${t}&expiration=${next.replaceAll('-', '')}`);
            const T = Math.max(1 / 365, (Date.parse(`${next}T20:00:00Z`) - Date.now()) / (365 * 864e5));
            const sx = impliedSpot(rows, T);
            if (sx != null) spotBy.set(t, sx);
          } catch { /* that name keeps its last good quote */ }
        }), 3);
      }
      /* Polygon only for what Theta could not price. */
      const polyBy = new Map<string, PolyStockTicker>();
      const missing = allTickers.filter((t) => !spotBy.has(t));
      if (missing.length) {
        try {
          const sUrl = new URL('https://api.polygon.io/v2/snapshot/locale/us/markets/stocks/tickers');
          sUrl.searchParams.set('tickers', missing.join(','));
          const sResp = await fetch(sUrl.toString(), { headers: authHeaders });
          if (sResp.ok) {
            const sData = (await sResp.json()) as PolyStockResp;
            for (const it of sData.tickers ?? sData.results ?? []) polyBy.set(String(it.ticker).toUpperCase(), it);
          }
        } catch { /* keep last good quotes */ }
      }
      /* The previous close each name's day change is measured against. */
      const prevBy = new Map<string, number>();
      const since = new Date(Date.now() - 12 * 864e5).toISOString().slice(0, 10);
      const { data: closes } = await admin.from('daily_closes')
        .select('ticker, date, close_price').in('ticker', allTickers)
        .lt('date', estToday).gte('date', since).order('date', { ascending: false });
      for (const c of (closes ?? []) as Array<{ ticker: string; close_price: number }>) {
        if (!prevBy.has(c.ticker) && Number(c.close_price) > 0) prevBy.set(c.ticker, Number(c.close_price));
      }
      for (const t of allTickers) {
        const it = polyBy.get(t);
        const spot = spotBy.get(t)
          ?? (it ? positive(it.lastTrade?.p) ?? positive(it.lastQuote?.p) ?? positive(it.day?.c) ?? positive(it.prevDay?.c) : null);
        const prev = prevBy.get(t) ?? (it ? positive(it.prevDay?.c) : null);
        stockResults.push({
          ticker: t, spot,
          day_change_pct: spot != null && prev != null ? ((spot - prev) / prev) * 100 : null,
        });
      }
    }

    // ─── 5. Upserts ─────────────────────────────────────────────
    if (legResults.length > 0) {
      const rows = legResults.map((r) => ({
        option_trade_id: r.id,
        delta: r.delta, gamma: r.gamma, theta: r.theta, vega: r.vega,
        iv: r.iv, open_interest: r.oi, volume: r.vol, last_mark: r.last_mark,
        underlying: r.underlying,
        captured_at: now,
      }));
      // Append-only: each cron run inserts a new row. The
      // `option_greeks_latest` view exposes the most recent capture
      // per trade for read paths. 90-day retention prune runs daily.
      /* A 15 s pass between :00 and :30 writes the live table only. */
      const { error: gErr } = opts.history
        ? await admin.from('option_greeks').insert(rows)
        : await admin.from('option_greeks_live')
            .upsert(rows.map((r) => ({ ...r, id: crypto.randomUUID() })), { onConflict: 'option_trade_id' });
      if (gErr) throw new Error(`option_greeks insert failed: ${gErr.message}`);
    }
    if (stockResults.length > 0) {
      const rows = stockResults
        .filter((r) => r.spot != null) // skip nulls — keep last good quote
        .map((r) => ({
          ticker: r.ticker,
          spot: r.spot,
          day_change_pct: r.day_change_pct,
          captured_at: now,
        }));
      if (rows.length > 0) {
        // Append-only — see `ticker_quotes_latest` view. 30-day prune.
        const { error: qErr } = opts.history
          ? await admin.from('ticker_quotes').insert(rows)
          : await admin.from('ticker_quotes_live')
              .upsert(rows.map((r) => ({ ...r, id: crypto.randomUUID() })), { onConflict: 'ticker' });
        if (qErr) throw new Error(`ticker_quotes insert failed: ${qErr.message}`);
      }
    }

    const summary = {
      ok: true,
      source: useTheta ? 'theta' : 'polygon', theta_used: thetaUsed, theta_error: thetaErr, shadow: shadowNote,
      legs: { total: openLegs.length, updated: legResults.length, failed: legFailures.length, failures: legFailures.slice(0, 10) },
      tickers: { total: allTickers.length, updated: stockResults.filter((r) => r.spot != null).length },
      timestamp: now,
    };
    // A run with zero successful upserts is functionally a failure even
    // if no exception was thrown — surface it that way on /health so the
    // staleness traffic-light catches "Polygon returned 403 on every leg".
    const allFailed = openLegs.length > 0 && legResults.length === 0;
    // Raise / clear a Polygon-outage alert in system_alerts so the iOS
    // banner reflects upstream state immediately rather than waiting
    // for the 30-min health-monitor.
    if (allFailed) {
      await admin.rpc('raise_system_alert', {
        p_code: 'polygon.outage',
        p_severity: 'critical',
        p_title: 'Polygon feed unavailable',
        p_detail: `All ${openLegs.length} legs failed this refresh — upstream feed may be down.`,
        p_meta: { failures: legFailures.slice(0, 5) },
      });
    } else {
      await admin.rpc('clear_system_alert', { p_code: 'polygon.outage' });
    }
    await finishRun(allFailed ? 'error' : 'ok', {
      legs_total: openLegs.length,
      legs_updated: legResults.length,
      legs_failed: legFailures.length,
      tickers_total: allTickers.length,
      tickers_updated: stockResults.filter((r) => r.spot != null).length,
      failures: legFailures.slice(0, 10),
      error_text: allFailed ? 'every leg failed (check failures[].reason)' : null,
    });
    return new Response(
      JSON.stringify(summary),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    const msg = (err as Error).message || 'Server error';
    await finishRun('error', { error_text: msg });
    return new Response(
      JSON.stringify({ error: msg, timestamp: now }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
}
