/**
 * nvda-scenario — "what if I sell this strike" covered-call scenario engine.
 *
 * Pulls NVDA's live option chain from Polygon and re-prices a chosen contract
 * under a spot/IV/time scenario via Black-Scholes.
 *
 *   • {"expiry":"2026-08-07","kind":"call"}
 *       → the chain for that expiry: strike, current IV, mark, delta (to pick from).
 *
 *   • {"strike":197.5,"expiry":"2026-08-07","kind":"call",
 *      "spot_to":198, "days":2, "iv_mode":"skew"|"constant"|"manual", "iv_manual":55}
 *       → premium now + the option's value under the scenario, the IV it used,
 *         and the short-side P&L (premium collected − buy-back value).
 *     Use `spot_pct` instead of `spot_to` to move by a percentage.
 *
 * IV modes:
 *   • skew     — read today's IV of the strike that's ATM at the scenario spot
 *                (the market's own read of that moneyness). Default.
 *   • constant — hold the chosen strike's current IV.
 *   • manual   — use `iv_manual` (%), your own assumption.
 *
 * Secret: POLYGON_API_KEY.
 */
const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' };
const json = (s: number, b: unknown) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

const POLY = 'https://api.polygon.io';
const R = 0.043, Q = 0.0;

function normCdf(x: number): number {
  const t = 1 / (1 + 0.2316419 * Math.abs(x));
  const d = 0.3989422804014327 * Math.exp(-x * x / 2);
  let p = d * t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
  p = 1 - p;
  return x >= 0 ? p : 1 - p;
}
function bs(kind: string, S: number, K: number, T: number, sig: number): number {
  if (T <= 0 || sig <= 0) return Math.max(0, kind === 'call' ? S - K : K - S);
  const d1 = (Math.log(S / K) + (R - Q + sig * sig / 2) * T) / (sig * Math.sqrt(T));
  const d2 = d1 - sig * Math.sqrt(T);
  if (kind === 'call') return S * Math.exp(-Q * T) * normCdf(d1) - K * Math.exp(-R * T) * normCdf(d2);
  return K * Math.exp(-R * T) * normCdf(-d2) - S * Math.exp(-Q * T) * normCdf(-d1);
}

interface Snap {
  details: { strike_price: number; expiration_date: string; contract_type: string };
  implied_volatility?: number;
  greeks?: { delta?: number };
  day?: { close?: number };
  last_quote?: { midpoint?: number };
  underlying_asset?: { price?: number };
}

/** Full chain snapshot for one expiry + type (paged). */
async function chain(expiry: string, kind: string, key: string): Promise<{ rows: Snap[]; spot: number | null }> {
  let url: string | null = `${POLY}/v3/snapshot/options/NVDA?expiration_date=${expiry}`
    + `&contract_type=${kind}&limit=250&apiKey=${key}`;
  const rows: Snap[] = [];
  let spot: number | null = null;
  for (let i = 0; i < 6 && url; i++) {
    const r = await fetch(url);
    if (!r.ok) break;
    const j = await r.json();
    for (const c of (j?.results ?? []) as Snap[]) {
      rows.push(c);
      if (spot == null && c.underlying_asset?.price) spot = c.underlying_asset.price;
    }
    url = j?.next_url ? `${j.next_url}&apiKey=${key}` : null;
  }
  return { rows, spot };
}

const mid = (c: Snap) => c.last_quote?.midpoint ?? c.day?.close ?? null;
const yearFrac = (expiry: string, from: Date) =>
  Math.max(0, (new Date(expiry + 'T20:00:00Z').getTime() - from.getTime()) / (365 * 86400000));

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const key = Deno.env.get('POLYGON_API_KEY');
  if (!key) return json(500, { ok: false, error: 'POLYGON_API_KEY not set' });

  const b = await req.json().catch(() => ({})) as Record<string, unknown>;
  const kind = (b.kind as string) === 'put' ? 'put' : 'call';
  const expiry = b.expiry as string | undefined;
  if (!expiry) return json(400, { ok: false, error: 'expiry (YYYY-MM-DD) required' });

  const { rows, spot } = await chain(expiry, kind, key);
  if (rows.length === 0) return json(200, { ok: false, error: 'no chain for that expiry' });
  const spotNow = (b.spot_now as number) ?? spot ?? 0;

  // list mode: hand back the chain to pick from
  if (b.strike == null) {
    const list = rows
      .map((c) => ({ strike: c.details.strike_price, iv: c.implied_volatility ?? null, mark: mid(c), delta: c.greeks?.delta ?? null }))
      .filter((r) => r.mark != null)
      .sort((a, b2) => a.strike - b2.strike);
    return json(200, { ok: true, mode: 'chain', expiry, kind, spot: spotNow, count: list.length, chain: list });
  }

  // scenario mode
  const strike = Number(b.strike);
  const picked = rows.find((c) => Math.abs(c.details.strike_price - strike) < 1e-6);
  if (!picked) return json(200, { ok: false, error: `strike ${strike} not in chain` });
  const ivNow = picked.implied_volatility ?? null;
  const premNow = mid(picked);

  const now = new Date();
  const days = Number(b.days ?? 0);
  const scenAt = new Date(now.getTime() + days * 86400000);
  const T1 = yearFrac(expiry, scenAt);
  const S1 = b.spot_to != null ? Number(b.spot_to)
           : b.spot_pct != null ? spotNow * (1 + Number(b.spot_pct) / 100)
           : spotNow;

  // IV under the scenario
  const ivMode = (b.iv_mode as string) ?? 'skew';
  let iv1: number | null = null, ivSource = ivMode;
  if (ivMode === 'manual' && b.iv_manual != null) {
    iv1 = Number(b.iv_manual) / 100;
  } else if (ivMode === 'constant') {
    iv1 = ivNow;
  } else {
    // skew: IV of the strike nearest S1 in today's chain
    let best: Snap | null = null, bd = Infinity;
    for (const c of rows) {
      if (c.implied_volatility == null) continue;
      const d = Math.abs(c.details.strike_price - S1);
      if (d < bd) { bd = d; best = c; }
    }
    iv1 = best?.implied_volatility ?? ivNow;
    ivSource = `skew (${best?.details.strike_price} strike)`;
  }

  const valAtScen = iv1 != null ? bs(kind, S1, strike, T1, iv1) : null;
  const shortPL = (premNow != null && valAtScen != null) ? (premNow - valAtScen) * 100 : null;   // per contract
  const itm = kind === 'call' ? S1 >= strike : S1 <= strike;

  return json(200, {
    ok: true, mode: 'scenario', kind, strike, expiry,
    now: { spot: spotNow, iv_pct: ivNow != null ? +(ivNow * 100).toFixed(1) : null,
           premium: premNow != null ? +premNow.toFixed(2) : null,
           premium_contract: premNow != null ? Math.round(premNow * 100) : null },
    scenario: {
      spot: +S1.toFixed(2), days, iv_pct: iv1 != null ? +(iv1 * 100).toFixed(1) : null, iv_source: ivSource,
      option_value: valAtScen != null ? +valAtScen.toFixed(2) : null,
      short_pl_contract: shortPL != null ? Math.round(shortPL) : null,
      moneyness: itm ? 'ITM' : 'OTM',
    },
  });
});
