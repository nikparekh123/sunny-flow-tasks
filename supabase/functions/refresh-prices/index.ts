/**
 * refresh-prices — live quotes for every ticker in `positions`, written to
 * current_price / prev_close / last_price_update.
 *
 * ⚠ NOT POLYGON ANY MORE (12 Oct 2026): its snapshot answers 403 since the
 * plan changed. A name the app already quotes (ticker_quotes_latest, written
 * every 30 seconds) reuses that spot; any other name asks Theta Data's option
 * quotes, then Yahoo. The previous close is our own daily_closes.
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

/* ───────── Live spot without Polygon (12 Oct 2026) ─────────
   Polygon's stock snapshot answers 403 since the plan changed. A name's live
   price is the one its nearest option expiry implies on Theta Data (put-call
   parity at the strike where call and put are closest); a name with no
   listed options falls back to Yahoo's chart quote. */
const THETA_URL = Deno.env.get('THETA_URL') ?? '';
const THETA_KEY = Deno.env.get('THETA_PROXY_KEY') ?? '';
const nyDate = () => new Date().toLocaleDateString('en-CA', { timeZone: 'America/New_York' });
async function thetaJson(path: string): Promise<Array<Record<string, unknown>>> {
  const r = await fetch(`${THETA_URL}${path}&format=json`, {
    headers: { 'x-proxy-key': THETA_KEY }, signal: AbortSignal.timeout(15_000) });
  if (!r.ok) return [];
  return ((await r.json())?.response ?? []) as Array<Record<string, unknown>>;
}
async function thetaSpot(t: string): Promise<number | null> {
  if (!THETA_URL || !THETA_KEY) return null;
  try {
    const today = nyDate();
    const next = (await thetaJson(`/v3/option/list/expirations?symbol=${t}`))
      .map((x) => String(x.expiration)).filter((e) => e > today).sort()[0];
    if (!next) return null;
    const T = Math.max(1 / 365, (Date.parse(`${next}T20:00:00Z`) - Date.now()) / (365 * 864e5));
    const by = new Map<number, { c?: number; p?: number }>();
    for (const r of await thetaJson(`/v3/option/snapshot/quote?symbol=${t}&expiration=${next.replaceAll('-', '')}`)) {
      const c = r.contract as { right: string; strike: number };
      const d = (r.data as Array<Record<string, number>>)?.[0];
      if (!d || !(d.bid > 0 && d.ask > 0)) continue;
      const e = by.get(c.strike) ?? {}; e[c.right.toLowerCase() === 'call' ? 'c' : 'p'] = (d.bid + d.ask) / 2;
      by.set(c.strike, e);
    }
    let best: number | null = null, gap = Infinity;
    for (const [k, e] of by) {
      if (e.c == null || e.p == null) continue;
      if (Math.abs(e.c - e.p) < gap) { gap = Math.abs(e.c - e.p); best = e.c - e.p + k * Math.exp(-0.04 * T); }
    }
    return best;
  } catch { return null; }
}
async function yahooQuote(t: string): Promise<{ price: number | null; prev: number | null }> {
  try {
    const r = await fetch(`https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(t)}?range=1d&interval=1d`,
      { headers: { 'User-Agent': 'Mozilla/5.0 (compatible; Sunnyfi/1.0)' }, signal: AbortSignal.timeout(10_000) });
    if (!r.ok) return { price: null, prev: null };
    const m = (await r.json())?.chart?.result?.[0]?.meta ?? {};
    const pos = (v: unknown) => (typeof v === 'number' && v > 0 ? v : null);
    return { price: pos(m.regularMarketPrice), prev: pos(m.chartPreviousClose) ?? pos(m.previousClose) };
  } catch { return { price: null, prev: null }; }
}
/** The last stored close before today, from our own daily_closes, and only
    if it is from the last five days: a name nobody holds stops being captured,
    and AAPL's "previous close" was 2 Sep. */
async function storedPrevClose(sbUrl: string, sbKey: string, t: string): Promise<number | null> {
  try {
    const since = new Date(Date.now() - 5 * 864e5).toISOString().slice(0, 10);
    const r = await fetch(`${sbUrl}/rest/v1/daily_closes?ticker=eq.${encodeURIComponent(t)}&date=lt.${nyDate()}&date=gte.${since}`
      + '&select=close_price&order=date.desc&limit=1', { headers: { apikey: sbKey, Authorization: `Bearer ${sbKey}` } });
    if (!r.ok) return null;
    const v = Number((await r.json())?.[0]?.close_price);
    return v > 0 ? v : null;
  } catch { return null; }
}

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

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
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

    // 2) Live spots: the app's own 30-second quotes first, then Theta, then Yahoo.
    const now = new Date().toISOString();
    let updated = 0;
    const missing: string[] = [];
    const uniq = [...new Set(tickers)];
    const fresh = new Date(Date.now() - 10 * 60_000).toISOString();
    const { data: q } = await admin.from('ticker_quotes_latest')
      .select('ticker, spot, captured_at').in('ticker', uniq).gte('captured_at', fresh);
    const spotBy = new Map<string, number>();
    for (const r of (q ?? []) as Array<{ ticker: string; spot: number }>) if (Number(r.spot) > 0) spotBy.set(r.ticker, Number(r.spot));
    const prevBy = new Map<string, number>();
    const todo = uniq.slice();
    await Promise.all(Array.from({ length: 3 }, async () => {
      while (todo.length) {
        const t = todo.shift()!;
        const [live, prev] = await Promise.all([
          spotBy.has(t) ? Promise.resolve(spotBy.get(t)!) : thetaSpot(t),
          storedPrevClose(supabaseUrl, serviceRoleKey, t),
        ]);
        let price = live, pc = prev;
        if (price == null || pc == null) {
          const y = await yahooQuote(t);
          price = price ?? y.price; pc = pc ?? y.prev;
        }
        if (price != null) spotBy.set(t, price);
        if (pc != null) prevBy.set(t, pc);
      }
    }));

    for (const t of tickers) {
      const last = spotBy.get(t) ?? null;
      const prev = prevBy.get(t) ?? null;
      if (last == null && prev == null) {
        missing.push(t);
        continue;
      }
      const patch: Record<string, unknown> = { last_price_update: now };
      if (last != null) patch.current_price = last;
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
