/**
 * quote-ticker — single-ticker price lookup against Polygon (massive.com).
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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const polygonKey = Deno.env.get('POLYGON_API_KEY');
    if (!polygonKey) {
      return new Response(
        JSON.stringify({ error: 'POLYGON_API_KEY is not set as a Supabase secret' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

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

    // Polygon snapshot endpoint — single-ticker URL form.
    const url = new URL(
      `https://api.polygon.io/v2/snapshot/locale/us/markets/stocks/tickers/${raw}`,
    );
    url.searchParams.set('apiKey', polygonKey);

    const resp = await fetch(url.toString());
    if (!resp.ok) {
      const text = await resp.text();
      return new Response(
        JSON.stringify({
          error: `Polygon snapshot failed (${resp.status})`,
          detail: text.slice(0, 300),
        }),
        { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const data = (await resp.json()) as SnapshotResponse & { ticker?: SnapshotTicker };
    // Single-ticker endpoint returns { ticker: { ... } } not an array. Be
    // lenient about either shape.
    const item: SnapshotTicker | undefined =
      data.ticker ?? data.results?.[0] ?? data.tickers?.[0];

    if (!item) {
      return new Response(
        JSON.stringify({ ticker: raw, error: 'Not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const price = pickFirstPositive(
      item.lastTrade?.p,
      item.lastQuote?.p,
      item.day?.c,
      item.prevDay?.c,
    );
    const prevClose = positive(item.prevDay?.c);

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
