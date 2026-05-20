/**
 * refresh-signals — compute daily technical indicators for every ticker
 * in `positions` and upsert into `ticker_signals`.
 *
 * Indicators (kept intentionally small — see types.ts `chipsForSignals`):
 *   • 20d / 50d / 200d moving averages
 *   • RSI(14) (Wilder's smoothing)
 *   • 5-day  rate of change %
 *   • 21-day rate of change %
 *
 * Per-ticker Polygon aggregates call (1/req per ticker) throttled to
 * the free-tier limit (5/min ≙ 13s between calls).
 *
 * Required Supabase secrets:
 *   POLYGON_API_KEY
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function mean(xs: number[]): number {
  return xs.reduce((s, x) => s + x, 0) / xs.length;
}

/** Wilder's RSI(14). Returns null if there's <15 closes. */
function rsi14(closes: number[]): number | null {
  if (closes.length < 15) return null;
  let gain = 0;
  let loss = 0;
  for (let i = 1; i <= 14; i++) {
    const d = closes[i] - closes[i - 1];
    if (d > 0) gain += d;
    else loss -= d;
  }
  let avgGain = gain / 14;
  let avgLoss = loss / 14;
  for (let i = 15; i < closes.length; i++) {
    const d = closes[i] - closes[i - 1];
    const g = d > 0 ? d : 0;
    const l = d < 0 ? -d : 0;
    avgGain = (avgGain * 13 + g) / 14;
    avgLoss = (avgLoss * 13 + l) / 14;
  }
  if (avgLoss === 0) return 100;
  const rs = avgGain / avgLoss;
  return 100 - 100 / (1 + rs);
}

interface PolyAgg {
  c: number; // close
  t: number; // ms timestamp
}
interface PolyResponse {
  results?: PolyAgg[];
  status?: string;
  error?: string;
  message?: string;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const polygonKey = Deno.env.get('POLYGON_API_KEY');

    if (!polygonKey) {
      return new Response(
        JSON.stringify({ error: 'POLYGON_API_KEY is not set as a Supabase secret' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: positions, error: readError } = await admin
      .from('positions')
      .select('ticker');
    if (readError) throw readError;

    const tickers = [
      ...new Set((positions ?? []).map((p) => (p.ticker as string).toUpperCase())),
    ];
    if (tickers.length === 0) {
      return new Response(
        JSON.stringify({ updated: 0, message: 'No positions to refresh.' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // ~400 calendar days back gives us comfortably more than 200 trading
    // days for the 200-day MA.
    const today = new Date();
    const from = new Date(today.getTime() - 400 * 86_400_000);
    const fromStr = from.toISOString().slice(0, 10);
    const toStr = today.toISOString().slice(0, 10);

    const out: Array<Record<string, unknown>> = [];
    const errors: string[] = [];
    let firstCall = true;

    for (const ticker of tickers) {
      // Free tier: 5 calls / minute. Pause 13s between calls (skip on
      // the first to keep the function snappy when there's just one).
      if (!firstCall) await sleep(13_000);
      firstCall = false;

      try {
        const url =
          `https://api.polygon.io/v2/aggs/ticker/${encodeURIComponent(ticker)}` +
          `/range/1/day/${fromStr}/${toStr}` +
          `?adjusted=true&sort=asc&limit=500&apiKey=${polygonKey}`;
        const resp = await fetch(url);
        if (!resp.ok) {
          errors.push(`${ticker}: HTTP ${resp.status}`);
          continue;
        }
        const json = (await resp.json()) as PolyResponse;
        const bars = json.results ?? [];
        if (bars.length < 30) {
          errors.push(`${ticker}: only ${bars.length} bars`);
          continue;
        }
        const closes = bars.map((b) => b.c);
        const lastIdx = closes.length - 1;
        const price = closes[lastIdx];

        const ma = (n: number): number | null =>
          closes.length >= n ? mean(closes.slice(-n)) : null;
        const ma20 = ma(20);
        const ma50 = ma(50);
        const ma200 = ma(200);
        const rsi = rsi14(closes);

        const chgPct = (n: number): number | null => {
          if (closes.length <= n) return null;
          const prev = closes[lastIdx - n];
          if (prev === 0) return null;
          return ((price - prev) / prev) * 100;
        };
        const chg5 = chgPct(5);
        const chg21 = chgPct(21);

        const asofDate = new Date(bars[bars.length - 1].t)
          .toISOString()
          .slice(0, 10);

        out.push({
          ticker,
          asof_date: asofDate,
          price,
          ma20,
          ma50,
          ma200,
          rsi14: rsi,
          chg_5d_pct: chg5,
          chg_21d_pct: chg21,
          updated_at: new Date().toISOString(),
        });
      } catch (e) {
        errors.push(`${ticker}: ${(e as Error).message}`);
      }
    }

    if (out.length > 0) {
      const { error: upsertError } = await admin
        .from('ticker_signals')
        .upsert(out as never, { onConflict: 'ticker' });
      if (upsertError) throw upsertError;
    }

    return new Response(
      JSON.stringify({
        updated: out.length,
        total: tickers.length,
        errors,
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
