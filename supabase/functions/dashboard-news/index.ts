/**
 * dashboard-news — Yahoo Finance scrape of recent headlines per ticker.
 *
 * Used by the dashboard's NewsBand block to surface the latest news for
 * each held position. Yahoo's public search endpoint returns a JSON
 * payload that includes a `news` array per ticker query — no API key
 * required, but we set a browser-style User-Agent because the default
 * Deno UA gets blocked.
 *
 * Endpoint:  https://query1.finance.yahoo.com/v1/finance/search
 *            ?q=TICKER&newsCount=3&quotesCount=0
 *
 * Request:  POST { tickers: string[] }
 * Response: { items: Array<{ ticker, headline, url, publisher, ts }> }
 *
 * Brittle by design — Yahoo can change shape anytime. Failures per
 * ticker are isolated (one bad fetch doesn't kill the rest of the
 * batch). We swallow + skip silently.
 */
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface YahooNewsItem {
  uuid?: string;
  title?: string;
  publisher?: string;
  providerPublishTime?: number;       // unix seconds
  link?: string;
  type?: string;
}

interface YahooSearchResponse {
  news?: YahooNewsItem[];
}

interface OutItem {
  ticker: string;
  headline: string;
  url: string | null;
  publisher: string | null;
  ts: number | null;                  // unix seconds
}

async function fetchOne(ticker: string): Promise<OutItem | null> {
  const url = `https://query1.finance.yahoo.com/v1/finance/search?q=${encodeURIComponent(ticker)}&newsCount=3&quotesCount=0`;
  try {
    const res = await fetch(url, {
      headers: {
        "User-Agent": "Mozilla/5.0 (compatible; Sunnyfi/1.0)",
        "Accept": "application/json",
      },
    });
    if (!res.ok) return null;
    const j = await res.json() as YahooSearchResponse;
    const news = j.news ?? [];
    // Take the most recent STORY (skip 'pressrelease' / video stubs
    // when we can — they're noisy). Yahoo orders newest-first already.
    const pick = news.find((n) => n.type === "STORY" || n.type === undefined) ?? news[0];
    if (!pick || !pick.title) return null;
    return {
      ticker,
      headline: pick.title,
      url: pick.link ?? null,
      publisher: pick.publisher ?? null,
      ts: pick.providerPublishTime ?? null,
    };
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    let tickers: string[] = [];
    try {
      const body = await req.json() as { tickers?: string[] };
      if (Array.isArray(body?.tickers)) {
        tickers = body.tickers.filter((t): t is string => typeof t === "string" && t.length > 0).slice(0, 10);
      }
    } catch { /* fall through with empty list */ }

    if (tickers.length === 0) {
      return new Response(
        JSON.stringify({ items: [] }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Fetch in parallel — Yahoo is happy enough with 10 concurrent
    // requests from one client. Each ticker's failure is isolated.
    const results = await Promise.all(tickers.map(fetchOne));
    const items = results.filter((r): r is OutItem => r != null);

    return new Response(
      JSON.stringify({ items }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("dashboard-news failed:", e);
    return new Response(
      JSON.stringify({ error: (e as Error).message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
