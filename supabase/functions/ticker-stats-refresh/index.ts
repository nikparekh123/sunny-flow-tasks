/**
 * ticker-stats-refresh — daily technicals for the Planner's Upside Room card.
 *
 * Pulls the full adjusted daily history from Polygon and stores:
 *   • ath / ath_date   — max adjusted close over the whole series
 *   • high_52w/low_52w — max/min close over the trailing 252 sessions
 *   • ma50 / ma200     — trailing simple moving averages
 *   • rsi14            — Wilder RSI on daily closes
 *
 * Adjusted closes so splits do not create false highs. Idempotent upsert.
 * Body: {"ticker":"NVDA"} (default NVDA). Env: POLYGON_API_KEY,
 * SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY. Trigger: cron (daily).
 */
const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' };
const json = (s: number, b: unknown) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
const POLY = 'https://api.polygon.io';

function wilderRSI(closes: number[], period = 14): number | null {
  if (closes.length < period + 1) return null;
  let gain = 0, loss = 0;
  for (let i = 1; i <= period; i++) {
    const d = closes[i] - closes[i - 1];
    if (d >= 0) gain += d; else loss -= d;
  }
  let avgGain = gain / period, avgLoss = loss / period;
  for (let i = period + 1; i < closes.length; i++) {
    const d = closes[i] - closes[i - 1];
    avgGain = (avgGain * (period - 1) + Math.max(0, d)) / period;
    avgLoss = (avgLoss * (period - 1) + Math.max(0, -d)) / period;
  }
  if (avgLoss === 0) return 100;
  const rs = avgGain / avgLoss;
  return 100 - 100 / (1 + rs);
}
const mean = (a: number[]) => a.reduce((x, y) => x + y, 0) / a.length;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const pkey = Deno.env.get('POLYGON_API_KEY');
  const url = Deno.env.get('SUPABASE_URL');
  const skey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!pkey || !url || !skey) return json(500, { ok: false, error: 'env not set' });

  const body = await req.json().catch(() => ({})) as { ticker?: string };
  const ticker = (body.ticker ?? 'NVDA').toUpperCase();

  // 20 years of adjusted daily bars in one call.
  const to = new Date().toISOString().slice(0, 10);
  const from = `${new Date().getUTCFullYear() - 20}-01-01`;
  const aggRes = await fetch(`${POLY}/v2/aggs/ticker/${ticker}/range/1/day/${from}/${to}?adjusted=true&sort=asc&limit=50000&apiKey=${pkey}`);
  if (!aggRes.ok) return json(502, { ok: false, error: `polygon ${aggRes.status}` });
  const agg = await aggRes.json();
  const bars = (agg?.results ?? []) as { c: number; t: number }[];
  if (bars.length < 30) return json(200, { ok: false, error: `too few bars (${bars.length})` });

  const closes = bars.map((b) => b.c);
  let ath = -Infinity, athT = 0;
  for (const b of bars) if (b.c > ath) { ath = b.c; athT = b.t; }
  const athDate = new Date(athT).toISOString().slice(0, 10);

  const last252 = closes.slice(-252);
  const row = {
    ticker,
    high_52w: Math.max(...last252),
    low_52w: Math.min(...last252),
    ma50: closes.length >= 50 ? mean(closes.slice(-50)) : null,
    ma200: closes.length >= 200 ? mean(closes.slice(-200)) : null,
    rsi14: wilderRSI(closes.slice(-260)),
    ath,
    ath_date: athDate,
    updated_at: new Date().toISOString(),
  };

  const up = await fetch(`${url}/rest/v1/ticker_stats?on_conflict=ticker`, {
    method: 'POST',
    headers: { apikey: skey, Authorization: `Bearer ${skey}`, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates,return=minimal' },
    body: JSON.stringify(row),
  });
  if (!up.ok) return json(500, { ok: false, error: `upsert ${up.status}`, detail: await up.text() });

  return json(200, { ok: true, ticker, bars: bars.length, ...row });
});
