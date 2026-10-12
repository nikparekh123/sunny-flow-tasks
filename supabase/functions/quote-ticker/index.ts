/**
 * quote-ticker — single-ticker price lookup.
 *
 * ⚠ NOT POLYGON ANY MORE (12 Oct 2026): its snapshot answers 403 since the
 * plan changed. The price is the live one Theta Data's option quotes imply,
 * the previous close is our own daily_closes, and Yahoo covers anything
 * Theta has no options for.
 *
 * Unlike refresh-prices (which iterates positions and writes back to DB),
 * this returns one quote inline so the Math calculators can prefill "Current
 * price" for an arbitrary ticker. No database writes.
 *
 * Required Supabase secrets:
 *   POLYGON_API_KEY  — already configured for refresh-prices et al.
 */
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

const positive = (n: number | undefined | null): number | null =>
  typeof n === 'number' && n > 0 ? n : null;

const pickFirstPositive = (...nums: Array<number | undefined | null>): number | null => {
  for (const n of nums) {
    const v = positive(n);
    if (v != null) return v;
  }
  return null;
};

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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    let body: { ticker?: string } = {};
    try { body = await req.json(); } catch { /* allow query-string fallback */ }
    const fromQuery = new URL(req.url).searchParams.get('ticker') ?? undefined;
    const raw = (body.ticker ?? fromQuery ?? '').trim().toUpperCase();

    if (!raw || !/^[A-Z][A-Z0-9.\-]{0,9}$/.test(raw)) {
      return new Response(
        JSON.stringify({ error: 'Invalid ticker — expected 1-10 alphanumeric chars' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const sbUrl = Deno.env.get('SUPABASE_URL')!;
    const sbKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const [live, stored] = await Promise.all([thetaSpot(raw), storedPrevClose(sbUrl, sbKey, raw)]);
    const y = live == null || stored == null ? await yahooQuote(raw) : { price: null, prev: null };
    const price = live ?? y.price;
    const prevClose = stored ?? y.prev;

    if (price == null) {
      return new Response(
        JSON.stringify({ ticker: raw, error: 'No price available' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    return new Response(
      JSON.stringify({
        ticker: raw,
        price,
        prevClose,
        timestamp: new Date().toISOString(),
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
