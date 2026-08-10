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

  // A Request body reads ONCE. Two modes each calling req.json() meant the first
  // consumed it and the second fell through to the normal snapshot without a word.
  const reqBody = await req.json().catch(() => ({})) as {
    backfillCloses?: { tickers?: string[]; days?: number };
    dividends?: { tickers?: string[]; limit?: number };
  };

  // ── deep backfill of daily_closes ──────────────────────────────────────────
  // The scheduled run fetches 120 calendar days, which is right for the 5-session
  // chart and HV30 but leaves the planner's `relative` family comparing NVDA to SMH
  // over whatever overlap happens to exist — twelve sessions today, against the
  // twenty-one it is designed for. A short window is not wrong, it is just noisy, and
  // one gap distorts it.
  //
  // Separate mode rather than a wider default: the nightly job should stay cheap.
  {
    const bf = reqBody.backfillCloses;
    if (bf) {
      const admin0 = createClient(supabaseUrl, serviceKey, {
        auth: { autoRefreshToken: false, persistSession: false },
      });
      const tks = bf.tickers?.length ? bf.tickers : ['SMH', 'QQQ', 'NVDA'];
      const days = Math.min(Math.max(Number(bf.days ?? 800), 30), 1500);
      const to = new Date().toISOString().slice(0, 10);
      const from = new Date(Date.now() - days * 86400000).toISOString().slice(0, 10);
      const out: Record<string, number | string> = {};
      for (const tk of tks) {
        try {
          // sort=asc, matching the call shape that works. desc returns 404 here.
          const r = await fetch(`https://api.polygon.io/v2/aggs/ticker/${tk}/range/1/day/${from}/${to}`
            + `?adjusted=true&sort=asc&limit=5000&apiKey=${polygonKey}`);
          if (!r.ok) { out[tk] = `HTTP${r.status}`; continue; }
          const bars = ((await r.json())?.results ?? []) as { t: number; c: number }[];
          const rows = bars
            .filter((x) => Number.isFinite(x.c) && x.c > 0)
            .map((x) => ({ ticker: tk, date: new Date(x.t).toISOString().slice(0, 10), close_price: x.c }));
          for (let i = 0; i < rows.length; i += 200) {
            await admin0.from('daily_closes').upsert(rows.slice(i, i + 200), { onConflict: 'ticker,date' });
          }
          out[tk] = rows.length;
        } catch { out[tk] = 'error'; }
      }
      return new Response(JSON.stringify({ ok: true, mode: 'backfillCloses', from, to, written: out }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
  }

  // ── dividends ─────────────────────────────────────────────────────────────
  // Polygon carries declared FUTURE ex-dates as well as history, which is the whole
  // point: an ex-date already on the calendar inside the expiry you are writing is a
  // known mechanical drop, not a surprise. Past rows are kept so the yield can be
  // measured from what was actually paid rather than annualised off one month.
  {
    const dv = reqBody.dividends;
    if (dv) {
      const admin1 = createClient(supabaseUrl, serviceKey, {
        auth: { autoRefreshToken: false, persistSession: false },
      });
      const tks = dv.tickers?.length ? dv.tickers : ['TLT'];
      const lim = Math.min(Math.max(Number(dv.limit ?? 40), 1), 200);
      const out: Record<string, number | string> = {};
      for (const tk of tks) {
        try {
          const r = await fetch(`https://api.polygon.io/v3/reference/dividends?ticker=${tk}`
            + `&limit=${lim}&order=desc&sort=ex_dividend_date&apiKey=${polygonKey}`);
          if (!r.ok) { out[tk] = `HTTP${r.status}`; continue; }
          const res = ((await r.json())?.results ?? []) as Record<string, string | number>[];
          const rows = res
            .filter((x) => x.ex_dividend_date)
            .map((x) => ({
              ticker: tk,
              ex_date: String(x.ex_dividend_date).slice(0, 10),
              pay_date: x.pay_date ? String(x.pay_date).slice(0, 10) : null,
              record_date: x.record_date ? String(x.record_date).slice(0, 10) : null,
              declared_on: x.declaration_date ? String(x.declaration_date).slice(0, 10) : null,
              cash_amount: Number(x.cash_amount ?? 0) || null,
              frequency: Number(x.frequency ?? 0) || null,
              dividend_type: x.dividend_type ? String(x.dividend_type) : null,
              source: 'polygon',
            }));
          for (let i = 0; i < rows.length; i += 100) {
            await admin1.from('dividends').upsert(rows.slice(i, i + 100), { onConflict: 'ticker,ex_date' });
          }
          const today = new Date().toISOString().slice(0, 10);
          out[tk] = rows.length;
          out[`${tk}_next`] = rows.filter((x) => x.ex_date >= today).map((x) => x.ex_date).sort()[0] ?? 'none declared';
        } catch { out[tk] = 'error'; }
      }
      return new Response(JSON.stringify({ ok: true, mode: 'dividends', written: out }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
  }

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
    // Reference tapes (SMH, QQQ) are always included so the Today screen's
    // 5-session cards have real closes + IV even though they aren't held.
    const REFERENCE_TICKERS = ['SMH', 'QQQ'];
    const heldTickers = Array.from(new Set([
      ...(trades ?? [])
        .filter((t) => (t as { action: string }).action === 'open')
        .map((t) => (t as { ticker: string }).ticker.toUpperCase()),
      ...REFERENCE_TICKERS,
    ]));

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

    // ── 3. REAL daily closes from Polygon aggregates. ──
    // The old `capture-daily-close` cron copied positions.current_price,
    // which was stale/flat (42 rows → 2 distinct prices), so HV30 came out
    // 0 and the 5-session chart was dead. We fetch the truth here, backfill
    // `daily_closes` with it, and compute HV30 from real closes.
    const closesByTicker = new Map<string, number[]>();
    const aggFrom = new Date(startedAt.getTime() - 120 * 86400000).toISOString().slice(0, 10);
    const aggTo = snapshotDate;
    for (const tk of heldTickers) {
      try {
        const aggUrl = `https://api.polygon.io/v2/aggs/ticker/${tk}/range/1/day/${aggFrom}/${aggTo}`
          + `?adjusted=true&sort=asc&limit=200&apiKey=${polygonKey}`;
        const r = await fetch(aggUrl);
        if (!r.ok) continue;
        const j = await r.json() as { results?: { t: number; c: number }[] };
        const bars = j.results ?? [];
        if (bars.length === 0) continue;
        // Backfill real closes so daily_closes (5-session chart, HV30) is truthful.
        const rows = bars.map((b) => ({
          ticker: tk,
          date: new Date(b.t).toISOString().slice(0, 10),
          close_price: b.c,
        }));
        for (let i = 0; i < rows.length; i += 100) {
          await admin.from('daily_closes').upsert(rows.slice(i, i + 100), { onConflict: 'ticker,date' });
        }
        closesByTicker.set(tk, bars.map((b) => b.c));  // oldest → newest (sort=asc)
        // Reference tickers aren't in ticker_quotes_latest — seed a spot
        // from the latest bar so their ATM-IV lookup can run.
        if (!spotByTicker.has(tk)) spotByTicker.set(tk, bars[bars.length - 1].c);
      } catch { /* skip this ticker's closes; HV30 stays null for it */ }
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
