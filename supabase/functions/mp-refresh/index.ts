/**
 * mp-refresh — refresh option Greeks/OI/IV + ticker quotes for the
 * /portfolio master page.
 *
 * Reads:
 *   - public.option_trades  (open legs with remaining contracts > 0)
 *   - public.positions      (held tickers with quantity > 0, status=open)
 * Writes (upsert):
 *   - public.option_greeks  (1 row per open option trade)
 *   - public.ticker_quotes  (1 row per held ticker)
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
  contracts: number;
  strike: number;
  expiry: string;     // 'YYYY-MM-DD'
  closes_trade_id: string | null;
}

// ─── Helpers ────────────────────────────────────────────────────
const positive = (n: number | undefined | null): number | null =>
  typeof n === 'number' && n > 0 ? n : null;

const pickPremium = (s: PolyOptionSnapshot): number | null => {
  const lt = positive(s.last_trade?.price);
  if (lt != null) return lt;
  const mid = positive(s.last_quote?.midpoint);
  if (mid != null) return mid;
  const bid = positive(s.last_quote?.bid);
  const ask = positive(s.last_quote?.ask);
  if (bid != null && ask != null) return (bid + ask) / 2;
  const dc = positive(s.day?.close);
  if (dc != null) return dc;
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

/** Build remaining-contracts map by walking opens + closes_trade_id closes.
 *  Mirrors src/positions/metrics/atoms.ts remainingByOpenId. */
function remainingByOpenId(trades: OpenTradeRow[]): Map<string, number> {
  const open = new Map<string, OpenTradeRow>();
  const closed = new Map<string, number>();
  for (const t of trades) {
    if (t.action === 'open') open.set(t.id, t);
    else if (t.action === 'close' && t.closes_trade_id) {
      closed.set(t.closes_trade_id, (closed.get(t.closes_trade_id) ?? 0) + t.contracts);
    }
  }
  const out = new Map<string, number>();
  for (const [id, o] of open) {
    out.set(id, Math.max(0, o.contracts - (closed.get(id) ?? 0)));
  }
  return out;
}

// ─── Handler ────────────────────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }
  const now = new Date().toISOString();
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
    const { data: tradeRows, error: tradesErr } = await admin
      .from('option_trades')
      .select('id, ticker, action, option_type, contracts, strike, expiry, closes_trade_id');
    if (tradesErr) throw tradesErr;

    const remaining = remainingByOpenId((tradeRows ?? []) as OpenTradeRow[]);
    const openLegs = (tradeRows ?? []).filter(
      (t) => t.action === 'open' && (remaining.get(t.id) ?? 0) > 0,
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
    const allTickers = Array.from(new Set([
      ...heldTickers,
      ...openLegs.map((l) => l.ticker.toUpperCase()),
    ]));

    // ─── 3. Per-leg option snapshot calls ───────────────────────
    const legResults: Array<{
      id: string; delta: number | null; gamma: number | null;
      theta: number | null; vega: number | null;
      iv: number | null; oi: number | null; vol: number | null;
      last_mark: number | null;
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
    for (const leg of openLegs) {
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
        });
      } catch (err) {
        legFailures.push({ id: leg.id, ticker: leg.ticker, occ, reason: (err as Error).message });
      }
    }

    // ─── 4. Stock snapshot — one batched call for all tickers ───
    const stockResults: Array<{ ticker: string; spot: number | null; day_change_pct: number | null }> = [];
    if (allTickers.length > 0) {
      const sUrl = new URL('https://api.polygon.io/v2/snapshot/locale/us/markets/stocks/tickers');
      sUrl.searchParams.set('tickers', allTickers.join(','));
      // Bearer header (see above); no apiKey query param.
      const sResp = await fetch(sUrl.toString(), { headers: authHeaders });
      if (sResp.ok) {
        const sData = (await sResp.json()) as PolyStockResp;
        const items = sData.tickers ?? sData.results ?? [];
        for (const t of allTickers) {
          const it = items.find((x) => x.ticker?.toUpperCase() === t);
          if (!it) {
            stockResults.push({ ticker: t, spot: null, day_change_pct: null });
            continue;
          }
          const spot = positive(it.lastTrade?.p)
            ?? positive(it.lastQuote?.p)
            ?? positive(it.day?.c)
            ?? positive(it.prevDay?.c);
          // Polygon returns this field directly; if absent, derive from spot vs prevDay.
          let day = it.todaysChangePerc;
          if (typeof day !== 'number' && spot != null) {
            const prev = positive(it.prevDay?.c);
            if (prev != null) day = ((spot - prev) / prev) * 100;
          }
          stockResults.push({
            ticker: t,
            spot,
            day_change_pct: typeof day === 'number' ? day : null,
          });
        }
      }
    }

    // ─── 5. Upserts ─────────────────────────────────────────────
    if (legResults.length > 0) {
      const rows = legResults.map((r) => ({
        option_trade_id: r.id,
        delta: r.delta, gamma: r.gamma, theta: r.theta, vega: r.vega,
        iv: r.iv, open_interest: r.oi, volume: r.vol, last_mark: r.last_mark,
        captured_at: now,
      }));
      const { error: gErr } = await admin
        .from('option_greeks')
        .upsert(rows, { onConflict: 'option_trade_id' });
      if (gErr) throw new Error(`option_greeks upsert failed: ${gErr.message}`);
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
        const { error: qErr } = await admin
          .from('ticker_quotes')
          .upsert(rows, { onConflict: 'ticker' });
        if (qErr) throw new Error(`ticker_quotes upsert failed: ${qErr.message}`);
      }
    }

    const summary = {
      ok: true,
      legs: { total: openLegs.length, updated: legResults.length, failed: legFailures.length, failures: legFailures.slice(0, 10) },
      tickers: { total: allTickers.length, updated: stockResults.filter((r) => r.spot != null).length },
      timestamp: now,
    };
    // A run with zero successful upserts is functionally a failure even
    // if no exception was thrown — surface it that way on /health so the
    // staleness traffic-light catches "Polygon returned 403 on every leg".
    const allFailed = openLegs.length > 0 && legResults.length === 0;
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
});
