/**
 * Math — single-ticker quote lookup.
 *
 * Priority chain:
 *   1. public.positions row owned by the signed-in user → cheap, instant,
 *      already kept fresh by the refresh-prices cron.
 *   2. quote-ticker edge function → live Polygon (massive.com) snapshot for
 *      any ticker the user doesn't hold.
 *
 * Returns { price, source, shares? } or throws.
 */
import { supabase } from "@/integrations/supabase/client";

export interface TickerQuote {
  ticker: string;
  price: number;
  source: "positions" | "polygon";
  /** When sourced from positions, hand the user their actual holding size too. */
  shares?: number;
}

interface PositionRow {
  ticker: string;
  current_price: number | null;
  quantity: number | null;
}

export async function pullTickerQuote(rawTicker: string): Promise<TickerQuote> {
  const ticker = rawTicker.trim().toUpperCase();
  if (!ticker) throw new Error("Enter a ticker first");

  // 1) own-position lookup (RLS limits the result to the signed-in user's rows)
  try {
    const { data, error } = await supabase
      .from("positions" as never)
      .select("ticker, current_price, quantity")
      .eq("ticker", ticker)
      .maybeSingle<PositionRow>();
    if (!error && data?.current_price && data.current_price > 0) {
      return {
        ticker,
        price: data.current_price,
        source: "positions",
        shares: typeof data.quantity === "number" ? data.quantity : undefined,
      };
    }
  } catch {
    // fall through to live quote
  }

  // 2) live snapshot via edge function
  const { data, error } = await supabase.functions.invoke("quote-ticker", {
    body: { ticker },
  });
  if (error) {
    throw new Error(`Quote failed: ${error.message}`);
  }
  const payload = data as { ticker?: string; price?: number; error?: string } | null;
  if (!payload || payload.error || !payload.price) {
    throw new Error(payload?.error ?? "Quote unavailable");
  }
  return { ticker: payload.ticker ?? ticker, price: payload.price, source: "polygon" };
}

// ── Option chain ────────────────────────────────────────────────
export interface OptionContractQuote {
  expiry: string;   // 'YYYY-MM-DD'
  strike: number;
  premium: number;  // per-share
}

/** Fetch all puts (or calls) at (or near) a target strike across all
 *  available expiries. Used by the Math Variants sweep when it needs real
 *  prices per cadence — long-dated puts cost much more than short-dated. */
export async function pullOptionChain(
  ticker: string,
  strike: number,
  contractType: "put" | "call",
): Promise<OptionContractQuote[]> {
  if (!ticker || !isFinite(strike) || strike <= 0) {
    throw new Error("ticker and strike are required");
  }
  const { data, error } = await supabase.functions.invoke("option-chain", {
    body: { ticker, strike, contract_type: contractType },
  });
  if (error) throw new Error(`Option chain failed: ${error.message}`);
  const payload = data as { contracts?: OptionContractQuote[]; error?: string } | null;
  if (!payload || payload.error) throw new Error(payload?.error ?? "Chain unavailable");
  return payload.contracts ?? [];
}

/** Pick the contract whose expiry is closest to `targetDate` (ISO date). */
export function nearestExpiry(
  contracts: OptionContractQuote[],
  targetDate: string,
): OptionContractQuote | null {
  if (contracts.length === 0) return null;
  const target = new Date(targetDate + "T00:00:00Z").getTime();
  let best = contracts[0];
  let bestDist = Math.abs(new Date(best.expiry + "T00:00:00Z").getTime() - target);
  for (const c of contracts.slice(1)) {
    const d = Math.abs(new Date(c.expiry + "T00:00:00Z").getTime() - target);
    if (d < bestDist) { best = c; bestDist = d; }
  }
  return best;
}

/** Decide which cadence ids are realistically available given the chain.
 *  A cadence counts as "available" when there's a listed expiry within
 *  ±tolerance days of (today + cadence.calDays). Tolerance scales with
 *  cadence so weekly/monthly aren't punished for being a few days off the
 *  exact target, but daily / 3×wk only match if there's a genuinely
 *  short-dated contract.
 */
export function availableCadenceIds(
  contracts: OptionContractQuote[],
  cadences: Array<{ id: string; calDays: number }>,
): Set<string> {
  const out = new Set<string>();
  if (contracts.length === 0) return out;
  const todayMs = new Date(new Date().toISOString().slice(0, 10) + "T00:00:00Z").getTime();
  const expiryMs = contracts.map((c) =>
    new Date(c.expiry + "T00:00:00Z").getTime(),
  );
  for (const cad of cadences) {
    const targetMs = todayMs + cad.calDays * 86400000;
    const tolMs = Math.max(1, cad.calDays * 0.5) * 86400000;
    for (const ms of expiryMs) {
      if (Math.abs(ms - targetMs) <= tolMs) { out.add(cad.id); break; }
    }
  }
  return out;
}
