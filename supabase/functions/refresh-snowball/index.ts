/**
 * refresh-snowball — pull current quote + 52-week range for every ticker in
 * `public.snowball` and write them back. Scheduled daily before market open
 * via Supabase Cron (recommended: `0 13 * * 1-5` in UTC = 9:00 AM ET, EDT).
 *
 * Required Supabase secrets:
 *   POLYGON_API_KEY  — Polygon / Massive paid plan
 *
 * Polygon endpoint used:
 *   GET /v2/snapshot/locale/us/markets/stocks/tickers?tickers=AAPL,MSFT,...
 *     accepts up to ~250 tickers per call; we batch into chunks of 200.
 *
 * For 52-week high/low:
 *   GET /v2/aggs/ticker/{T}/range/1/day/{from}/{to}
 *     one call per ticker. To stay polite we run these sequentially with a
 *     tiny delay (Massive paid plan has 100+ req/sec; this won't sweat it).
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface SnapshotTicker {
  ticker: string;
  lastTrade?: { p?: number };
  day?: { c?: number };
  prevDay?: { c?: number };
  todaysChangePerc?: number;
}

interface SnapshotResponse {
  tickers?: SnapshotTicker[];
  status?: string;
  error?: string;
}

// Polygon's "previous close + day's last" gives current price + change.
// 52-week extremes need a separate aggregates call.
async function fetchSnapshotBatch(
  tickers: string[],
  apiKey: string,
): Promise<Map<string, SnapshotTicker>> {
  const url = new URL(
    "https://api.polygon.io/v2/snapshot/locale/us/markets/stocks/tickers",
  );
  url.searchParams.set("tickers", tickers.join(","));
  url.searchParams.set("apiKey", apiKey);

  const resp = await fetch(url.toString());
  if (!resp.ok) {
    throw new Error(`Polygon snapshot ${resp.status}: ${await resp.text()}`);
  }
  const data = (await resp.json()) as SnapshotResponse;
  const out = new Map<string, SnapshotTicker>();
  for (const t of data.tickers ?? []) {
    if (t.ticker) out.set(t.ticker.toUpperCase(), t);
  }
  return out;
}

interface AggsResponse {
  results?: { h?: number; l?: number; c?: number }[];
  status?: string;
}

async function fetch52w(
  ticker: string,
  apiKey: string,
): Promise<{ low: number | null; high: number | null }> {
  const to = new Date();
  const from = new Date(to);
  from.setFullYear(from.getFullYear() - 1);
  const fmt = (d: Date) => d.toISOString().slice(0, 10);

  const url = new URL(
    `https://api.polygon.io/v2/aggs/ticker/${encodeURIComponent(
      ticker,
    )}/range/1/day/${fmt(from)}/${fmt(to)}`,
  );
  url.searchParams.set("adjusted", "true");
  url.searchParams.set("sort", "asc");
  url.searchParams.set("limit", "300");
  url.searchParams.set("apiKey", apiKey);

  const resp = await fetch(url.toString());
  if (!resp.ok) return { low: null, high: null };
  const data = (await resp.json()) as AggsResponse;
  const bars = data.results ?? [];
  if (bars.length === 0) return { low: null, high: null };
  const lows = bars.map((b) => b.l ?? Infinity);
  const highs = bars.map((b) => b.h ?? -Infinity);
  return { low: Math.min(...lows), high: Math.max(...highs) };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const polygonKey = Deno.env.get("POLYGON_API_KEY");

    if (!polygonKey) {
      return new Response(
        JSON.stringify({ error: "POLYGON_API_KEY not set" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // 1) Read all tickers from snowball.
    const { data: rows, error: readErr } = await admin
      .from("snowball")
      .select("ticker");
    if (readErr) throw readErr;
    const tickers = (rows ?? []).map((r) => r.ticker.toUpperCase());

    if (tickers.length === 0) {
      return new Response(
        JSON.stringify({ updated: 0, message: "No tickers to refresh." }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // 2) Snapshot in batches of 200.
    const batchSize = 200;
    const snapshots = new Map<string, SnapshotTicker>();
    for (let i = 0; i < tickers.length; i += batchSize) {
      const batch = tickers.slice(i, i + batchSize);
      const part = await fetchSnapshotBatch(batch, polygonKey);
      for (const [k, v] of part) snapshots.set(k, v);
    }

    // 3) For each ticker, fetch 52w from aggregates. Keep concurrency
    //    modest (8 at a time) so we stay polite even on a paid plan.
    const concurrency = 8;
    const queue = [...tickers];
    const ranges = new Map<
      string,
      { low: number | null; high: number | null }
    >();

    async function worker() {
      while (queue.length > 0) {
        const t = queue.shift()!;
        try {
          ranges.set(t, await fetch52w(t, polygonKey!));
        } catch {
          ranges.set(t, { low: null, high: null });
        }
      }
    }
    await Promise.all(Array.from({ length: concurrency }, worker));

    // 4) Write back.
    const now = new Date().toISOString();
    let updated = 0;
    const missing: string[] = [];

    for (const t of tickers) {
      const snap = snapshots.get(t);
      const range = ranges.get(t) ?? { low: null, high: null };
      const last =
        snap?.lastTrade?.p ?? snap?.day?.c ?? snap?.prevDay?.c ?? null;
      if (last == null && range.low == null && range.high == null) {
        missing.push(t);
        continue;
      }
      const patch: Record<string, unknown> = { last_quote_at: now };
      if (last != null) patch.price = last;
      if (range.low != null) patch.low_52w = range.low;
      if (range.high != null) patch.high_52w = range.high;
      if (snap?.todaysChangePerc != null) patch.change_pct = snap.todaysChangePerc;

      const { error: upErr } = await admin
        .from("snowball")
        .update(patch)
        .eq("ticker", t);
      if (upErr) missing.push(`${t} (${upErr.message})`);
      else updated++;
    }

    return new Response(
      JSON.stringify({
        updated,
        total: tickers.length,
        missing: missing.slice(0, 20),
        missing_count: missing.length,
        timestamp: now,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: (err as Error).message || "Server error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
