/**
 * ticker-iv-snapshot — daily per-ticker IV + HV30 snapshot.
 *
 * Runs once after market close (4:15pm ET weekdays via pg_cron).
 * For every ticker that has at least one open option leg, captures:
 *   • atm_iv  — IV of the ATM 30-day contract from Polygon
 *   • hv30    — 30-day realized vol (annualized stdev of log returns
 *               from daily_closes)
 *
 * Output: one upsert per ticker into `ticker_iv_daily`. The view
 * `ticker_iv_summary` rolls it up to per-ticker current/low/high/
 * window. iOS computes IVR / spread / Seller Score from there.
 *
 * Polygon endpoints used:
 *   • /v3/reference/options/contracts?underlying_ticker=X&expiration_date.gte=...&expiration_date.lte=...&strike_price.gte=...&strike_price.lte=...&limit=250
 *     → find candidate contracts near 30 DTE around spot
 *   • /v3/snapshot/options/{underlying}/{occ_ticker}
 *     → fetch IV for the chosen contract
 *
 * Required Supabase secret: POLYGON_API_KEY (same one mp-refresh uses).
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

const TARGET_DTE = 30;
const DTE_WINDOW = 14;            // accept contracts 16–44 DTE around target
const STRIKE_WINDOW_PCT = 0.10;   // accept strikes within ±10% of spot
const HV_DAYS = 30;
const TRADING_DAYS_PER_YEAR = 252;

interface PolyContractRef {
  ticker: string;             // OCC, e.g. O:AAPL250620C00200000
  underlying_ticker: string;
  strike_price: number;
  expiration_date: string;    // YYYY-MM-DD
  contract_type: 'call' | 'put';
}

interface PolyOptionSnap {
  implied_volatility?: number;
  details?: { ticker?: string; strike_price?: number; expiration_date?: string };
}

interface SnapshotResult {
  ticker: string;
  atm_iv: number | null;
  hv30: number | null;
  contract_used: string | null;
  error?: string;
}

/* ───────── HV30: annualized stdev of log returns ───────── */
function hv30FromCloses(closes: number[]): number | null {
  // Need at least 2 closes to make 1 return; use up to last HV_DAYS+1
  // closes to make HV_DAYS returns. Caller passes oldest → newest.
  if (closes.length < 3) return null;
  const returns: number[] = [];
  for (let i = 1; i < closes.length; i++) {
    const prev = closes[i - 1];
    const cur = closes[i];
    if (prev > 0 && cur > 0) returns.push(Math.log(cur / prev));
  }
  if (returns.length < 2) return null;
  const mean = returns.reduce((s, r) => s + r, 0) / returns.length;
  const variance = returns.reduce((s, r) => s + (r - mean) ** 2, 0) / (returns.length - 1);
  const dailyStdev = Math.sqrt(variance);
  return dailyStdev * Math.sqrt(TRADING_DAYS_PER_YEAR);
}

/* ───────── ATM-30d picker ───────── */
function pickAtm30dContract(
  contracts: PolyContractRef[],
  spot: number,
  asOf: Date,
): PolyContractRef | null {
  // Score = |DTE − TARGET_DTE| * 2 + |strike − spot| / spot * 100
  // (DTE distance weighted slightly heavier than strike distance.)
  let best: PolyContractRef | null = null;
  let bestScore = Infinity;
  for (const c of contracts) {
    if (c.contract_type !== 'call') continue;  // ATM call is the canonical proxy
    const exp = new Date(c.expiration_date + 'T16:00:00Z');
    const dte = Math.round((exp.getTime() - asOf.getTime()) / 86400000);
    if (dte < TARGET_DTE - DTE_WINDOW || dte > TARGET_DTE + DTE_WINDOW) continue;
    const strikeDist = Math.abs(c.strike_price - spot) / spot;
    if (strikeDist > STRIKE_WINDOW_PCT) continue;
    const score = Math.abs(dte - TARGET_DTE) * 2 + strikeDist * 100;
    if (score < bestScore) { bestScore = score; best = c; }
  }
  return best;
}

/* ───────── Handler ───────── */
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const polygonKey = Deno.env.get('POLYGON_API_KEY');

  if (!polygonKey) {
    return new Response(
      JSON.stringify({ ok: false, error: 'POLYGON_API_KEY not set' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const startedAt = new Date();
  const snapshotDate = startedAt.toISOString().slice(0, 10);  // UTC date; market close is well within
  const results: SnapshotResult[] = [];

  try {
    // ── 1. Find tickers with open option positions ────────────
    const { data: trades, error: tradesErr } = await admin
      .from('option_trades')
      .select('ticker, action, contracts, closes_trade_id, voided_at')
      .is('voided_at', null);
    if (tradesErr) throw tradesErr;

    // Build remaining-contracts map (mirror mp-refresh logic).
    const opens = new Map<string, { ticker: string; contracts: number }>();
    const closed = new Map<string, number>();
    for (const t of (trades ?? [])) {
      if (t.action === 'open') {
        opens.set(
          (t as { ticker: string }).ticker + ':' + JSON.stringify(t),  // placeholder, see below
          { ticker: (t as { ticker: string }).ticker, contracts: (t as { contracts: number }).contracts },
        );
      }
    }
    // Simpler: just collect distinct tickers with at least one open-row.
    // Remaining-contracts precision doesn't matter for the IV snapshot;
    // if you ever opened a leg on a ticker, you care about its IV.
    const heldTickers = Array.from(new Set(
      (trades ?? [])
        .filter((t) => (t as { action: string }).action === 'open')
        .map((t) => (t as { ticker: string }).ticker.toUpperCase()),
    ));

    if (heldTickers.length === 0) {
      return new Response(
        JSON.stringify({ ok: true, ticker_count: 0, results: [], note: 'no held option tickers' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // ── 2. Get spot prices for those tickers ──────────────────
    const { data: quotes, error: qErr } = await admin
      .from('ticker_quotes_latest')
      .select('ticker, spot')
      .in('ticker', heldTickers);
    if (qErr) throw qErr;
    const spotByTicker = new Map<string, number>(
      (quotes ?? [])
        .filter((q) => (q as { spot: number | null }).spot != null)
        .map((q) => [(q as { ticker: string }).ticker.toUpperCase(), (q as { spot: number }).spot]),
    );

    // ── 3. Get last HV_DAYS+5 daily closes per ticker (5 day buffer for weekends/holidays) ──
    const closesByTicker = new Map<string, number[]>();
    for (const tk of heldTickers) {
      const { data: dc } = await admin
        .from('daily_closes')
        .select('date, close_price')
        .eq('ticker', tk)
        .order('date', { ascending: false })
        .limit(HV_DAYS + 5);
      if (dc && dc.length > 0) {
        // Reverse to oldest → newest for hv30FromCloses
        const closes = (dc as { close_price: number }[])
          .map((r) => r.close_price)
          .reverse();
        closesByTicker.set(tk, closes);
      }
    }

    // ── 4. For each ticker: ATM-30d IV + HV30, then upsert ────
    const targetExpFrom = new Date(startedAt.getTime() + (TARGET_DTE - DTE_WINDOW) * 86400000)
      .toISOString().slice(0, 10);
    const targetExpTo = new Date(startedAt.getTime() + (TARGET_DTE + DTE_WINDOW) * 86400000)
      .toISOString().slice(0, 10);

    for (const tk of heldTickers) {
      const spot = spotByTicker.get(tk);
      if (!spot) {
        results.push({ ticker: tk, atm_iv: null, hv30: null, contract_used: null, error: 'no spot in ticker_quotes_latest' });
        continue;
      }
      const closes = closesByTicker.get(tk) ?? [];
      const hv30 = hv30FromCloses(closes);

      try {
        // 4a. Find candidate contracts in the strike + expiry window.
        const strikeMin = (spot * (1 - STRIKE_WINDOW_PCT)).toFixed(2);
        const strikeMax = (spot * (1 + STRIKE_WINDOW_PCT)).toFixed(2);
        const refUrl = `https://api.polygon.io/v3/reference/options/contracts`
          + `?underlying_ticker=${tk}`
          + `&expiration_date.gte=${targetExpFrom}`
          + `&expiration_date.lte=${targetExpTo}`
          + `&strike_price.gte=${strikeMin}`
          + `&strike_price.lte=${strikeMax}`
          + `&contract_type=call`
          + `&limit=250`
          + `&apiKey=${polygonKey}`;
        const refResp = await fetch(refUrl);
        if (!refResp.ok) throw new Error(`contracts ${refResp.status}`);
        const refJson = await refResp.json() as { results?: PolyContractRef[] };
        const candidates = refJson.results ?? [];

        const picked = pickAtm30dContract(candidates, spot, startedAt);
        if (!picked) {
          results.push({ ticker: tk, atm_iv: null, hv30, contract_used: null, error: 'no ATM-30d candidate in window' });
          // Still write HV30 so the spread column has a value down the line.
          if (hv30 != null) {
            await admin.from('ticker_iv_daily').upsert({
              ticker: tk, snapshot_date: snapshotDate,
              atm_iv: 0, hv30, source: 'cron', contract_used: null,
            }, { onConflict: 'ticker,snapshot_date' });
          }
          continue;
        }

        // 4b. Fetch that contract's snapshot for IV.
        const snapUrl = `https://api.polygon.io/v3/snapshot/options/${tk}/${picked.ticker}?apiKey=${polygonKey}`;
        const snapResp = await fetch(snapUrl);
        if (!snapResp.ok) throw new Error(`snapshot ${snapResp.status}`);
        const snapJson = await snapResp.json() as { results?: PolyOptionSnap };
        const iv = snapJson.results?.implied_volatility ?? null;
        if (iv == null) {
          results.push({ ticker: tk, atm_iv: null, hv30, contract_used: picked.ticker, error: 'no IV in snapshot' });
          continue;
        }

        // 4c. Upsert.
        const { error: upErr } = await admin
          .from('ticker_iv_daily')
          .upsert({
            ticker: tk,
            snapshot_date: snapshotDate,
            atm_iv: iv,
            hv30,
            source: 'cron',
            contract_used: picked.ticker,
          }, { onConflict: 'ticker,snapshot_date' });

        if (upErr) {
          results.push({ ticker: tk, atm_iv: iv, hv30, contract_used: picked.ticker, error: `upsert: ${upErr.message}` });
        } else {
          results.push({ ticker: tk, atm_iv: iv, hv30, contract_used: picked.ticker });
        }

        // Polite gap between tickers — Polygon free tier ratelimits at 5/min on some endpoints.
        await new Promise((r) => setTimeout(r, 200));

      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        results.push({ ticker: tk, atm_iv: null, hv30, contract_used: null, error: msg });
      }
    }

    const ok_count = results.filter((r) => r.atm_iv != null && !r.error).length;
    return new Response(
      JSON.stringify({
        ok: true,
        ticker_count: heldTickers.length,
        captured: ok_count,
        snapshot_date: snapshotDate,
        duration_ms: Date.now() - startedAt.getTime(),
        results,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );

  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return new Response(
      JSON.stringify({ ok: false, error: msg, results }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
