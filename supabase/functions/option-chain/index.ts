/**
 * option-chain — live option premiums from Polygon. Two modes:
 *
 *  1. CHAIN (default): given a target `strike`, return the closest-strike
 *     premium at EACH expiry. Used by the Math Variants put-frequency sweep.
 *       in:  { ticker, strike, contract_type, strike_window? }
 *       out: { ticker, strike, contract_type, contracts:[{expiry,strike,premium}] }
 *
 *  2. LADDER: given an `expiry`, return EVERY nearby strike for that one
 *     expiry. Used by the covered-call Plan Premium tool.
 *       in:  { ticker, expiry, contract_type, center?, window_pct? }
 *       out: { ticker, expiry, contract_type, spot, strikes:[{strike,premium,delta}] }
 *
 * Premiums are ~15-min delayed on the current Polygon plan — fine for
 * planning. Requires the shared POLYGON_API_KEY secret.
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
  greeks?: { delta?: number };
  last_quote?: { midpoint?: number; bid?: number; ask?: number };
  last_trade?: { price?: number };
  day?: { close?: number };
  fair_market_value?: number;
  underlying_asset?: { price?: number };
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

const bad = (msg: string, status = 400) =>
  new Response(JSON.stringify({ error: msg }),
    { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }
  try {
    const polygonKey = Deno.env.get('POLYGON_API_KEY');
    if (!polygonKey) return bad('POLYGON_API_KEY is not set as a Supabase secret', 500);

    let body: Record<string, unknown> = {};
    try { body = await req.json(); } catch { /* allow query-string fallback */ }
    const url = new URL(req.url);
    const g = (k: string) => (body[k] as string | undefined) ?? url.searchParams.get(k) ?? undefined;

    const ticker = String(g('ticker') ?? '').trim().toUpperCase();
    const contractType = String(g('contract_type') ?? 'put').toLowerCase();

    if (!ticker || !/^[A-Z][A-Z0-9.\-]{0,9}$/.test(ticker)) return bad('Invalid ticker');
    if (contractType !== 'put' && contractType !== 'call') {
      return bad('contract_type must be "put" or "call"');
    }

    const expiryParam = String(g('expiry') ?? '').trim();

    // ─── LADDER MODE: one expiry, every nearby strike ───────────────
    if (expiryParam) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(expiryParam)) return bad('Invalid expiry (YYYY-MM-DD)');
      const center = Number(g('center') ?? NaN);
      const windowPct = Number(g('window_pct') ?? 12);

      const pUrl = new URL(`https://api.polygon.io/v3/snapshot/options/${ticker}`);
      pUrl.searchParams.set('contract_type', contractType);
      pUrl.searchParams.set('expiration_date', expiryParam);
      if (isFinite(center) && center > 0) {
        const band = center * (windowPct / 100);
        pUrl.searchParams.set('strike_price.gte', String(Math.max(0, center - band)));
        pUrl.searchParams.set('strike_price.lte', String(center + band));
      }
      pUrl.searchParams.set('limit', '250');
      pUrl.searchParams.set('apiKey', polygonKey);

      const resp = await fetch(pUrl.toString());
      if (!resp.ok) {
        const t = await resp.text();
        return bad(`Polygon snapshot failed (${resp.status}): ${t.slice(0, 200)}`, 502);
      }
      const data = (await resp.json()) as PolygonChainResponse;
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
        JSON.stringify({ ticker, expiry: expiryParam, contract_type: contractType, spot, strikes }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // ─── CHAIN MODE: one strike, closest premium per expiry ─────────
    const strike = Number(g('strike') ?? NaN);
    const strikeWindow = Number(g('strike_window') ?? 2.5);
    if (!isFinite(strike) || strike <= 0) return bad('Invalid strike');

    const today = new Date().toISOString().slice(0, 10);
    const lo = Math.max(0, strike - strikeWindow);
    const hi = strike + strikeWindow;

    const pUrl = new URL(`https://api.polygon.io/v3/snapshot/options/${ticker}`);
    pUrl.searchParams.set('contract_type', contractType);
    pUrl.searchParams.set('strike_price.gte', String(lo));
    pUrl.searchParams.set('strike_price.lte', String(hi));
    pUrl.searchParams.set('expiration_date.gte', today);
    pUrl.searchParams.set('limit', '250');
    pUrl.searchParams.set('apiKey', polygonKey);

    const resp = await fetch(pUrl.toString());
    if (!resp.ok) {
      const text = await resp.text();
      return bad(`Polygon snapshot failed (${resp.status})`, 502);
    }
    const data = (await resp.json()) as PolygonChainResponse;
    const items = data.results ?? [];

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
    return bad((err as Error).message || 'Server error', 500);
  }
});
