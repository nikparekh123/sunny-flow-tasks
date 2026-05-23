/**
 * option-chain — fetch all available put or call options for an underlying
 * at (or near) a target strike, returning one row per expiry with the
 * latest reasonable per-share premium.
 *
 * Used by the Math Variants sweep: when sweeping put frequency, the client
 * needs the real put premium at each cadence's nearest expiry instead of
 * holding premium constant (which understates cost on long-dated puts).
 *
 * Input (JSON body or query string):
 *   ticker       — e.g. "NVDA"
 *   strike       — number, e.g. 215
 *   contract_type — "put" or "call"
 *   strike_window — optional, dollars to broaden strike search if exact
 *                   strike has no listed contracts. default: 2.5
 *
 * Output:
 *   { ticker, strike, contract_type,
 *     contracts: [{ expiry: 'YYYY-MM-DD', strike, premium }] }
 *
 * Required Supabase secret: POLYGON_API_KEY (shared with other Polygon fns).
 */
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

interface PolygonContract {
  details?: {
    contract_type?: string;
    strike_price?: number;
    expiration_date?: string;
  };
  last_quote?: { midpoint?: number; bid?: number; ask?: number };
  last_trade?: { price?: number };
  day?: { close?: number };
  fair_market_value?: number;
}

interface PolygonChainResponse {
  status?: string;
  results?: PolygonContract[];
  next_url?: string;
  error?: string;
  message?: string;
}

function pickPremium(c: PolygonContract): number | null {
  if (typeof c.last_trade?.price === 'number' && c.last_trade.price > 0) return c.last_trade.price;
  if (typeof c.last_quote?.midpoint === 'number' && c.last_quote.midpoint > 0) return c.last_quote.midpoint;
  const bid = c.last_quote?.bid, ask = c.last_quote?.ask;
  if (typeof bid === 'number' && typeof ask === 'number' && bid > 0 && ask > 0) {
    return (bid + ask) / 2;
  }
  if (typeof c.day?.close === 'number' && c.day.close > 0) return c.day.close;
  if (typeof c.fair_market_value === 'number' && c.fair_market_value > 0) return c.fair_market_value;
  return null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }
  try {
    const polygonKey = Deno.env.get('POLYGON_API_KEY');
    if (!polygonKey) {
      return new Response(
        JSON.stringify({ error: 'POLYGON_API_KEY is not set as a Supabase secret' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    let body: { ticker?: string; strike?: number; contract_type?: string; strike_window?: number } = {};
    try { body = await req.json(); } catch { /* allow query-string fallback */ }
    const url = new URL(req.url);
    const ticker = (body.ticker ?? url.searchParams.get('ticker') ?? '').trim().toUpperCase();
    const strike = Number(body.strike ?? url.searchParams.get('strike') ?? NaN);
    const contractType = (body.contract_type ?? url.searchParams.get('contract_type') ?? 'put').toLowerCase();
    const strikeWindow = Number(body.strike_window ?? url.searchParams.get('strike_window') ?? 2.5);

    if (!ticker || !/^[A-Z][A-Z0-9.\-]{0,9}$/.test(ticker)) {
      return new Response(
        JSON.stringify({ error: 'Invalid ticker' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }
    if (!isFinite(strike) || strike <= 0) {
      return new Response(
        JSON.stringify({ error: 'Invalid strike' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }
    if (contractType !== 'put' && contractType !== 'call') {
      return new Response(
        JSON.stringify({ error: 'contract_type must be "put" or "call"' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Polygon snapshot endpoint — filter by contract_type and a strike range
    // so we don't pull the whole chain. expiration_date.gte=today drops
    // already-expired contracts.
    const today = new Date().toISOString().slice(0, 10);
    const lo = Math.max(0, strike - strikeWindow);
    const hi = strike + strikeWindow;

    const pUrl = new URL(
      `https://api.polygon.io/v3/snapshot/options/${ticker}`,
    );
    pUrl.searchParams.set('contract_type', contractType);
    pUrl.searchParams.set('strike_price.gte', String(lo));
    pUrl.searchParams.set('strike_price.lte', String(hi));
    pUrl.searchParams.set('expiration_date.gte', today);
    pUrl.searchParams.set('limit', '250');
    pUrl.searchParams.set('apiKey', polygonKey);

    const resp = await fetch(pUrl.toString());
    if (!resp.ok) {
      const text = await resp.text();
      return new Response(
        JSON.stringify({ error: `Polygon snapshot failed (${resp.status})`, detail: text.slice(0, 300) }),
        { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }
    const data = (await resp.json()) as PolygonChainResponse;
    const items = data.results ?? [];

    // For each contract, pull a premium; keep only the closest-to-target
    // strike per expiry (in case the strike window admitted multiple).
    const byExpiry = new Map<string, { strike: number; premium: number; distance: number }>();
    for (const c of items) {
      const expiry = c.details?.expiration_date;
      const cStrike = c.details?.strike_price;
      if (!expiry || typeof cStrike !== 'number') continue;
      const prem = pickPremium(c);
      if (prem == null) continue;
      const dist = Math.abs(cStrike - strike);
      const existing = byExpiry.get(expiry);
      if (!existing || dist < existing.distance) {
        byExpiry.set(expiry, { strike: cStrike, premium: prem, distance: dist });
      }
    }

    const contracts = [...byExpiry.entries()]
      .map(([expiry, v]) => ({ expiry, strike: v.strike, premium: v.premium }))
      .sort((a, b) => a.expiry.localeCompare(b.expiry));

    return new Response(
      JSON.stringify({ ticker, strike, contract_type: contractType, contracts }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: (err as Error).message || 'Server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
