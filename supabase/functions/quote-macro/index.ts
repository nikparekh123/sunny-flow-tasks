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
 *
 * ⚠ HISTORY FOR THE DASHBOARD'S MACRO ZOOM (12 Oct 2026). With {history:true}
 * each extra ticker also carries `closes` (its last 30 daily closes, oldest
 * first) and `sma25DevPct` (today's price against its 25-day average). These
 * came from the BNF scanner's price cache, which was retired with the New
 * Strategy page; Yahoo's daily chart is the same data without the cache.
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

/** Last 30 daily closes from Yahoo, oldest first. */
async function yahooCloses(symbol: string): Promise<number[]> {
  try {
    const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?range=3mo&interval=1d`;
    const resp = await fetch(url, { headers: { "User-Agent": "Mozilla/5.0 (compatible; Sunnyfi/1.0)" } });
    if (!resp.ok) return [];
    const data = await resp.json() as {
      chart?: { result?: Array<{ indicators?: { quote?: Array<{ close?: Array<number | null> }> } }> };
    };
    const c = data.chart?.result?.[0]?.indicators?.quote?.[0]?.close ?? [];
    return c.filter((v): v is number => typeof v === "number" && v > 0).slice(-30);
  } catch {
    return [];
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

  // Optional: extra plain equity/ETF tickers (e.g. SPY, QQQ, IWM) fetched
  // live from Yahoo so the dashboard's index quotes reflect today, not the
  // nightly cache. The Yahoo symbol is the ticker itself for stocks/ETFs.
  let extra: string[] = [];
  let history = false;
  try {
    const body = await req.json();
    history = body?.history === true;
    if (Array.isArray(body?.tickers)) {
      extra = body.tickers
        .filter((t: unknown): t is string => typeof t === "string")
        .map((t: string) => t.trim().toUpperCase())
        .filter((t: string) => /^[A-Z][A-Z0-9.\-]{0,9}$/.test(t))
        .slice(0, 40);
    }
  } catch {
    /* no body — macro-only call */
  }

  const labels = Object.keys(SYMBOLS) as Label[];
  const macro = await Promise.all(
    labels.map(async (label) => {
      const { polygon, yahoo } = SYMBOLS[label];
      let q: Quote | null = polygonKey ? await fromPolygon(polygon, polygonKey) : null;
      if (!q) q = await fromYahoo(yahoo);
      return [label, q ?? { price: null, changePct: null, source: null }] as const;
    }),
  );
  const tickerQuotes = await Promise.all(
    extra.map(async (t) => {
      const [q, closes] = await Promise.all([fromYahoo(t), history ? yahooCloses(t) : Promise.resolve([])]);
      const base = q ?? { price: null, changePct: null, source: null };
      if (!history) return [t, base] as const;
      const last25 = closes.slice(-25);
      const sma = last25.length >= 20 ? last25.reduce((a, b) => a + b, 0) / last25.length : null;
      const px = base.price ?? closes[closes.length - 1] ?? null;
      return [t, { ...base, closes, sma25DevPct: sma && px ? (px / sma - 1) * 100 : null }] as const;
    }),
  );

  const items = Object.fromEntries([...macro, ...tickerQuotes]) as Record<string, Quote & { closes?: number[]; sma25DevPct?: number | null }>;
  return new Response(JSON.stringify({ items, timestamp: new Date().toISOString() }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
