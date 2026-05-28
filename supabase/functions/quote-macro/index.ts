/**
 * quote-macro — live macro index quotes for the dashboard / positions
 * ticker strip: 10Y Treasury yield, VIX, and DXY (dollar index).
 *
 * Polygon's stock plan does not reliably entitle the Indices product, so
 * each symbol is fetched Polygon-first (indices snapshot) and falls back to
 * the Yahoo chart endpoint — the same source we already scrape for news.
 * No database writes; returns the three quotes inline so the client can
 * cache them with React Query.
 *
 * Required Supabase secrets:
 *   POLYGON_API_KEY  — already configured for refresh-prices et al.
 *
 * Response shape:
 *   { items: { "10Y": { price, changePct, source }, "VIX": {...}, "DXY": {...} } }
 *   price/changePct are null when both sources fail for that symbol.
 */
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type Label = "10Y" | "VIX" | "DXY";

interface Quote {
  price: number | null;
  changePct: number | null;
  source: "polygon" | "yahoo" | null;
}

// Display label → { Polygon indices ticker, Yahoo symbol }
const SYMBOLS: Record<Label, { polygon: string; yahoo: string }> = {
  "10Y": { polygon: "I:TNX", yahoo: "^TNX" },
  VIX: { polygon: "I:VIX", yahoo: "^VIX" },
  DXY: { polygon: "I:DXY", yahoo: "DX-Y.NYB" },
};

const positive = (n: unknown): number | null =>
  typeof n === "number" && Number.isFinite(n) ? n : null;

async function fromPolygon(ticker: string, key: string): Promise<Quote | null> {
  try {
    const url = new URL("https://api.polygon.io/v3/snapshot/indices");
    url.searchParams.set("ticker.any_of", ticker);
    url.searchParams.set("apiKey", key);
    const resp = await fetch(url.toString());
    if (!resp.ok) return null;
    const data = (await resp.json()) as {
      results?: Array<{ value?: number; session?: { change_percent?: number } }>;
    };
    const r = data.results?.[0];
    const price = positive(r?.value);
    if (price == null) return null;
    return { price, changePct: positive(r?.session?.change_percent), source: "polygon" };
  } catch {
    return null;
  }
}

async function fromYahoo(symbol: string): Promise<Quote | null> {
  try {
    const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?range=1d&interval=1d`;
    const resp = await fetch(url, {
      headers: { "User-Agent": "Mozilla/5.0 (compatible; Sunnyfi/1.0)" },
    });
    if (!resp.ok) return null;
    const data = (await resp.json()) as {
      chart?: { result?: Array<{ meta?: { regularMarketPrice?: number; chartPreviousClose?: number; previousClose?: number } }> };
    };
    const meta = data.chart?.result?.[0]?.meta;
    const price = positive(meta?.regularMarketPrice);
    const prev = positive(meta?.chartPreviousClose) ?? positive(meta?.previousClose);
    if (price == null) return null;
    const changePct = prev != null && prev !== 0 ? ((price - prev) / prev) * 100 : null;
    return { price, changePct, source: "yahoo" };
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const polygonKey = Deno.env.get("POLYGON_API_KEY") ?? "";

  const labels = Object.keys(SYMBOLS) as Label[];
  const quotes = await Promise.all(
    labels.map(async (label) => {
      const { polygon, yahoo } = SYMBOLS[label];
      let q: Quote | null = polygonKey ? await fromPolygon(polygon, polygonKey) : null;
      if (!q) q = await fromYahoo(yahoo);
      return [label, q ?? { price: null, changePct: null, source: null }] as const;
    }),
  );

  const items = Object.fromEntries(quotes) as Record<Label, Quote>;
  return new Response(JSON.stringify({ items, timestamp: new Date().toISOString() }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
