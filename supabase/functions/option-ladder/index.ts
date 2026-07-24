/**
 * option-ladder — the strike ladder for ONE expiry, with a live per-share
 * premium on each strike. Powers the covered-call "Plan premium" tool:
 * pick an expiry, see what every nearby strike would pay.
 *
 * Sibling of option-chain (which returns one strike across many expiries);
 * this returns many strikes for one expiry.
 *
 * Input (JSON body or query string):
 *   ticker         — e.g. "NVDA"
 *   expiry         — "YYYY-MM-DD"
 *   contract_type  — "call" | "put"  (default "call")
 *   center         — reference price to window around (default: no window)
 *   window_pct     — % band around center to return (default 12)
 *
 * Output:
 *   { ticker, expiry, contract_type, spot,
 *     strikes: [{ strike, premium, delta }] }   // ascending by strike
 *
 * NOTE: premiums are ~15-min delayed on the current Polygon plan — fine for
 * planning. Requires the shared POLYGON_API_KEY secret.
 */
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface PolyContract {
  details?: { contract_type?: string; strike_price?: number; expiration_date?: string };
  greeks?: { delta?: number };
  last_quote?: { midpoint?: number; bid?: number; ask?: number };
  last_trade?: { price?: number };
  day?: { close?: number };
  fair_market_value?: number;
  underlying_asset?: { price?: number };
}
interface PolyResp { status?: string; results?: PolyContract[]; error?: string; message?: string }

function pickPremium(c: PolyContract): number | null {
  if (typeof c.last_trade?.price === 'number' && c.last_trade.price > 0) return c.last_trade.price;
  if (typeof c.last_quote?.midpoint === 'number' && c.last_quote.midpoint > 0) return c.last_quote.midpoint;
  const bid = c.last_quote?.bid, ask = c.last_quote?.ask;
  if (typeof bid === 'number' && typeof ask === 'number' && bid > 0 && ask > 0) return (bid + ask) / 2;
  if (typeof c.day?.close === 'number' && c.day.close > 0) return c.day.close;
  if (typeof c.fair_market_value === 'number' && c.fair_market_value > 0) return c.fair_market_value;
  return null;
}

const bad = (msg: string, status = 400) =>
  new Response(JSON.stringify({ error: msg }),
    { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  try {
    const key = Deno.env.get('POLYGON_API_KEY');
    if (!key) return bad('POLYGON_API_KEY is not set', 500);

    let body: Record<string, unknown> = {};
    try { body = await req.json(); } catch { /* query-string fallback */ }
    const url = new URL(req.url);
    const pick = (k: string) => (body[k] as string | undefined) ?? url.searchParams.get(k) ?? undefined;

    const ticker = String(pick('ticker') ?? '').trim().toUpperCase();
    const expiry = String(pick('expiry') ?? '').trim();
    const contractType = String(pick('contract_type') ?? 'call').toLowerCase();
    const center = Number(pick('center') ?? NaN);
    const windowPct = Number(pick('window_pct') ?? 12);

    if (!/^[A-Z][A-Z0-9.\-]{0,9}$/.test(ticker)) return bad('Invalid ticker');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(expiry)) return bad('Invalid expiry (YYYY-MM-DD)');
    if (contractType !== 'call' && contractType !== 'put') return bad('contract_type must be call or put');

    const pUrl = new URL(`https://api.polygon.io/v3/snapshot/options/${ticker}`);
    pUrl.searchParams.set('contract_type', contractType);
    pUrl.searchParams.set('expiration_date', expiry);
    if (isFinite(center) && center > 0) {
      const band = center * (windowPct / 100);
      pUrl.searchParams.set('strike_price.gte', String(Math.max(0, center - band)));
      pUrl.searchParams.set('strike_price.lte', String(center + band));
    }
    pUrl.searchParams.set('limit', '250');
    pUrl.searchParams.set('apiKey', key);

    const resp = await fetch(pUrl.toString());
    if (!resp.ok) {
      const t = await resp.text();
      return bad(`Polygon snapshot failed (${resp.status}): ${t.slice(0, 200)}`, 502);
    }
    const data = (await resp.json()) as PolyResp;
    const items = data.results ?? [];

    let spot: number | null = null;
    const strikes: Array<{ strike: number; premium: number; delta: number | null }> = [];
    for (const c of items) {
      if (c.underlying_asset?.price && spot == null) spot = c.underlying_asset.price;
      const strike = c.details?.strike_price;
      if (typeof strike !== 'number') continue;
      const premium = pickPremium(c);
      if (premium == null) continue;
      strikes.push({ strike, premium, delta: c.greeks?.delta ?? null });
    }
    strikes.sort((a, b) => a.strike - b.strike);

    return new Response(
      JSON.stringify({ ticker, expiry, contract_type: contractType, spot, strikes }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    return bad(`option-ladder error: ${String(e)}`, 500);
  }
});
