/**
 * dashboard-news — recent headlines per ticker, from Polygon.
 *
 * Was a Yahoo Finance scrape, but Yahoo's public search endpoint now
 * blocks non-browser clients (returns an HTML challenge, not JSON), so
 * this uses Polygon's reference-news API instead — the same
 * POLYGON_API_KEY secret the rest of the app already uses.
 *
 * Endpoint:  https://api.polygon.io/v2/reference/news?ticker=TICKER&limit=3
 *
 * Request:  POST { tickers: string[] }
 * Response: { items: Array<{ ticker, headline, url, publisher, ts }> }
 *           ts is an ISO-8601 string (Polygon's published_utc).
 *
 * Per-ticker failures are isolated — one bad fetch doesn't kill the batch.
 */
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface PolyNewsResult {
  title?: string;
  article_url?: string;
  published_utc?: string;               // ISO-8601
  publisher?: { name?: string };
}
interface PolyNewsResponse {
  results?: PolyNewsResult[];
}

interface OutItem {
  ticker: string;
  headline: string;
  url: string | null;
  publisher: string | null;
  ts: string | null;                    // ISO-8601
}

async function fetchTicker(ticker: string, key: string): Promise<OutItem[]> {
  const url = new URL("https://api.polygon.io/v2/reference/news");
  url.searchParams.set("ticker", ticker.toUpperCase());
  url.searchParams.set("limit", "3");
  url.searchParams.set("order", "desc");
  url.searchParams.set("sort", "published_utc");
  url.searchParams.set("apiKey", key);
  try {
    const res = await fetch(url.toString());
    if (!res.ok) return [];
    const j = (await res.json()) as PolyNewsResponse;
    return (j.results ?? [])
      .filter((r) => r.title)
      .map((r) => ({
        ticker,
        headline: r.title as string,
        url: r.article_url ?? null,
        publisher: r.publisher?.name ?? null,
        ts: r.published_utc ?? null,
      }));
  } catch {
    return [];
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const key = Deno.env.get("POLYGON_API_KEY");
    if (!key) {
      return new Response(
        JSON.stringify({ error: "POLYGON_API_KEY is not set", items: [] }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    let tickers: string[] = [];
    try {
      const body = (await req.json()) as { tickers?: string[] };
      if (Array.isArray(body?.tickers)) {
        tickers = body.tickers
          .filter((t): t is string => typeof t === "string" && t.length > 0)
          .slice(0, 10);
      }
    } catch { /* empty list */ }

    if (tickers.length === 0) {
      return new Response(
        JSON.stringify({ items: [] }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const perTicker = await Promise.all(tickers.map((t) => fetchTicker(t, key)));
    const items = perTicker.flat();

    return new Response(
      JSON.stringify({ items }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("dashboard-news failed:", e);
    return new Response(
      JSON.stringify({ error: (e as Error).message, items: [] }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
