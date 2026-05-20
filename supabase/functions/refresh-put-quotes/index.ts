/**
 * refresh-put-quotes — for every row in `put_protection` that has the data
 * required to construct an OCC option symbol (ticker + expiry + strike +
 * contracts), fetch the latest per-share premium from Polygon (Massive)
 * and write current_premium + current_premium_at.
 *
 * OCC symbol format (Polygon's options ticker):
 *   O:{UNDERLYING}{YYMMDD}{P|C}{STRIKE_E3}
 * where STRIKE_E3 is the strike × 1000 as an 8-digit zero-padded integer.
 * Example: META 2026-06-18 $480 put → O:META260618P00480000
 *
 * Quote source: /v3/snapshot/options/{underlying}/{option_ticker}
 * Premium pick order: last_trade.price → last_quote.midpoint → day.close.
 *
 * Required Supabase secret:
 *   POLYGON_API_KEY  — same key as refresh-prices.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

interface PutRow {
  id: string;
  ticker: string;
  expiry: string;          // 'YYYY-MM-DD'
  strike: number | null;
  contracts: number | null;
}

interface PolygonSnapshot {
  status?: string;
  results?: {
    last_trade?: { price?: number };
    last_quote?: { midpoint?: number; bid?: number; ask?: number };
    day?: { close?: number };
    fair_market_value?: number;
  };
  error?: string;
  message?: string;
}

/** Build the OCC ticker for a put. Returns null if any input is invalid. */
function occPutTicker(underlying: string, expiry: string, strike: number): string | null {
  // expiry format: YYYY-MM-DD
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(expiry);
  if (!m) return null;
  const [, y, mo, d] = m;
  const yymmdd = `${y.slice(2)}${mo}${d}`;
  // strike × 1000, 8 digits, zero-padded
  const strikeE3 = Math.round(strike * 1000).toString().padStart(8, '0');
  return `O:${underlying.toUpperCase()}${yymmdd}P${strikeE3}`;
}

/** Pick the freshest reasonable per-share premium from the Polygon snapshot. */
function pickPremium(snap: PolygonSnapshot): number | null {
  const r = snap.results;
  if (!r) return null;
  if (typeof r.last_trade?.price === 'number' && r.last_trade.price > 0) return r.last_trade.price;
  if (typeof r.last_quote?.midpoint === 'number' && r.last_quote.midpoint > 0) return r.last_quote.midpoint;
  if (typeof r.last_quote?.bid === 'number' && typeof r.last_quote?.ask === 'number'
      && r.last_quote.bid > 0 && r.last_quote.ask > 0) {
    return (r.last_quote.bid + r.last_quote.ask) / 2;
  }
  if (typeof r.day?.close === 'number' && r.day.close > 0) return r.day.close;
  if (typeof r.fair_market_value === 'number' && r.fair_market_value > 0) return r.fair_market_value;
  return null;
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

    const { data: rows, error: readError } = await admin
      .from('put_protection')
      .select('id, ticker, expiry, strike, contracts');
    if (readError) throw readError;

    const candidates = (rows ?? []).filter(
      (r: PutRow) => r.strike != null && r.contracts != null && r.expiry,
    );
    const total = (rows ?? []).length;
    const skipped = total - candidates.length;
    const now = new Date().toISOString();

    let updated = 0;
    const failures: Array<{ ticker: string; reason: string }> = [];

    // Sequential to stay polite to the API and to surface per-row errors;
    // there are typically <10 active put contracts, so latency is fine.
    for (const r of candidates as PutRow[]) {
      const occ = occPutTicker(r.ticker, r.expiry, r.strike!);
      if (!occ) {
        failures.push({ ticker: r.ticker, reason: 'bad OCC inputs' });
        continue;
      }
      const url = new URL(
        `https://api.polygon.io/v3/snapshot/options/${r.ticker.toUpperCase()}/${occ}`,
      );
      url.searchParams.set('apiKey', polygonKey);

      try {
        const resp = await fetch(url.toString());
        if (!resp.ok) {
          failures.push({ ticker: r.ticker, reason: `HTTP ${resp.status}` });
          continue;
        }
        const json = (await resp.json()) as PolygonSnapshot;
        const premium = pickPremium(json);
        if (premium == null) {
          failures.push({ ticker: r.ticker, reason: 'no premium in snapshot' });
          continue;
        }
        const { error: updErr } = await admin
          .from('put_protection')
          .update({ current_premium: premium, current_premium_at: now })
          .eq('id', r.id);
        if (updErr) {
          failures.push({ ticker: r.ticker, reason: updErr.message });
          continue;
        }
        updated += 1;
      } catch (e) {
        failures.push({ ticker: r.ticker, reason: (e as Error).message });
      }
    }

    return new Response(
      JSON.stringify({ updated, skipped, total, failures }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: (e as Error).message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
