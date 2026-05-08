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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // Optional `{ ticker }` body filters the run to a single stock — used by
  // "Add stock" so the new row gets a price quote within seconds instead
  // of waiting for the next universe-wide cron.
  let onlyTicker: string | null = null;
  try {
    const body = (await req.json().catch(() => null)) as
      | { ticker?: string }
      | null;
    if (body?.ticker) onlyTicker = body.ticker.toUpperCase();
  } catch {
    /* no-op: empty body is allowed */
  }

  // Diagnostic envelope — capture any error and report it as JSON instead
  // of letting the Edge Runtime swallow it into a useless 500.
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const polygonKey = Deno.env.get("POLYGON_API_KEY");

    if (!supabaseUrl) {
      return new Response(
        JSON.stringify({ error: "SUPABASE_URL not set" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    if (!serviceRoleKey) {
      return new Response(
        JSON.stringify({ error: "SUPABASE_SERVICE_ROLE_KEY not set" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

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

    // 1) Read all tickers from snowball (or just the one we were asked for).
    const baseQuery = admin.from("snowball").select("ticker");
    const tickerQuery = onlyTicker
      ? baseQuery.eq("ticker", onlyTicker)
      : baseQuery;
    const { data: rows, error: readErr } = await tickerQuery;
    if (readErr) throw readErr;
    const tickers = (rows ?? []).map((r) => r.ticker.toUpperCase());

    if (tickers.length === 0) {
      return new Response(
        JSON.stringify({ updated: 0, message: "No tickers to refresh." }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // 2) Snapshot in batches of 200. This is the only API call we do —
    //    52-week aggregates (1 call per ticker) blow past the Edge
    //    Function CPU/wall-clock budget. They live in a separate function
    //    `refresh-snowball-52w` (run weekly) if needed.
    const batchSize = 200;
    const snapshots = new Map<string, SnapshotTicker>();
    for (let i = 0; i < tickers.length; i += batchSize) {
      const batch = tickers.slice(i, i + batchSize);
      const part = await fetchSnapshotBatch(batch, polygonKey);
      for (const [k, v] of part) snapshots.set(k, v);
    }

    // 3) Write back in a single bulk upsert via parallel updates (chunked).
    const now = new Date().toISOString();
    let updated = 0;
    const missing: string[] = [];

    // Build all the patches first, then run them in parallel chunks.
    const writes: { ticker: string; patch: Record<string, unknown> }[] = [];
    for (const t of tickers) {
      const snap = snapshots.get(t);
      const last =
        snap?.lastTrade?.p ?? snap?.day?.c ?? snap?.prevDay?.c ?? null;
      if (last == null) {
        missing.push(t);
        continue;
      }
      const patch: Record<string, unknown> = { last_quote_at: now, price: last };
      if (snap?.todaysChangePerc != null) patch.change_pct = snap.todaysChangePerc;
      writes.push({ ticker: t, patch });
    }

    // Run updates in parallel chunks of 25 to keep CPU bounded.
    const chunk = 25;
    for (let i = 0; i < writes.length; i += chunk) {
      const slice = writes.slice(i, i + chunk);
      const results = await Promise.all(
        slice.map((w) =>
          admin.from("snowball").update(w.patch).eq("ticker", w.ticker),
        ),
      );
      results.forEach((r, idx) => {
        if (r.error) missing.push(`${slice[idx].ticker} (${r.error.message})`);
        else updated++;
      });
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
    // Log everything we can see — the Edge Runtime's default 500 page
    // truncates messages, so we serialize the whole error here.
    console.error("refresh-snowball error", err);
    const e = err as Error & { cause?: unknown };
    return new Response(
      JSON.stringify({
        error: e?.message || String(err) || "Server error",
        name: e?.name,
        stack: e?.stack,
        cause: e?.cause ? String(e.cause) : undefined,
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
