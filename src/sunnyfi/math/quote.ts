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
