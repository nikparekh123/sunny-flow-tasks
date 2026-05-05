/**
 * Snowball data layer — DCF / valuation universe from `public.snowball`.
 * The table is populated daily by the refresh-snowball edge function and
 * one-shot by the CSV import script.
 */
import { supabase } from "@/integrations/supabase/client";

export interface Stock {
  ticker: string;
  name: string;
  sector: string | null;
  industry: string | null;
  shares_outstanding: number | null;
  intrinsic_value: number | null;
  stage1_growth_pct: number | null;
  discount_rate_pct: number | null;
  terminal_growth_pct: number | null;
  total_owner_earnings: number | null;
  tbp_aggressive_15: number | null;
  tbp_conservative_30: number | null;
  tbp_deep_value_50: number | null;
  distance_to_buy: string | null;
  valuation_profile: string | null;
  tier: number | null;       // 1–6 (1 = strong buy)
  hold_position: boolean;
  watchlist: boolean;
  dividend_yield_pct: number | null;
  earnings_date: string | null;
  price: number | null;
  low_52w: number | null;
  high_52w: number | null;
  change_pct: number | null;
  last_quote_at: string | null;
}

/** Computed view of a Stock with the derived fields used by the UI. */
export interface ComputedStock extends Stock {
  upside: number;          // % margin of safety, derived
  market_cap: number;      // USD billions, derived
  rank?: number;           // populated by sort step
}

/** Tier labels match the 6-step gradient in snowball.css. */
export const TIER_LABEL: Record<number, string> = {
  1: "Strong buy",
  2: "Undervalued",
  3: "Slight upside",
  4: "Fair value",
  5: "Watch",
  6: "Overvalued",
};

export type SortKey =
  | "Most undervalued"
  | "Most overvalued"
  | "Market cap"
  | "A → Z";

export const SORTS: SortKey[] = [
  "Most undervalued",
  "Most overvalued",
  "Market cap",
  "A → Z",
];

// ─── Compute derived fields ───────────────────────────────────
function compute(s: Stock): ComputedStock {
  const price = s.price ?? 0;
  const intrinsic = s.intrinsic_value ?? 0;
  const upside = price > 0 ? ((intrinsic - price) / price) * 100 : 0;
  const shares = s.shares_outstanding ?? 0;
  // shares are in millions in the CSV → market cap in $B = price × shares / 1000
  const market_cap = (price * shares) / 1000;
  return { ...s, upside, market_cap };
}

// ─── Queries ──────────────────────────────────────────────────
export async function fetchStocks(): Promise<ComputedStock[]> {
  const { data, error } = await supabase
    .from("snowball" as never)
    .select("*")
    .order("ticker");
  if (error) throw error;
  return ((data ?? []) as unknown as Stock[]).map(compute);
}

export async function setWatch(
  ticker: string,
  watchlist: boolean,
): Promise<void> {
  const { error } = await supabase
    .from("snowball" as never)
    .update({ watchlist } as never)
    .eq("ticker", ticker);
  if (error) throw error;
}

export async function setHold(
  ticker: string,
  hold_position: boolean,
): Promise<void> {
  const { error } = await supabase
    .from("snowball" as never)
    .update({ hold_position } as never)
    .eq("ticker", ticker);
  if (error) throw error;
}

// ─── Sorting / filtering ──────────────────────────────────────
export function sortStocks(
  list: ComputedStock[],
  by: SortKey,
): ComputedStock[] {
  const r = [...list];
  if (by === "Most undervalued") r.sort((a, b) => b.upside - a.upside);
  else if (by === "Most overvalued") r.sort((a, b) => a.upside - b.upside);
  else if (by === "Market cap") r.sort((a, b) => b.market_cap - a.market_cap);
  else r.sort((a, b) => a.ticker.localeCompare(b.ticker));
  return r.map((s, i) => ({ ...s, rank: i + 1 }));
}

// ─── Formatters ───────────────────────────────────────────────
export const fmtUps = (u: number | null | undefined): string => {
  if (u == null || isNaN(u)) return "—";
  return (u >= 0 ? "+" : "") + u.toFixed(1) + "%";
};

export const fmtPrice = (p: number | null | undefined): string => {
  if (p == null || isNaN(p)) return "—";
  return "$" + p.toFixed(p < 10 ? 2 : 0);
};

export const fmtPrice2 = (p: number | null | undefined): string => {
  if (p == null || isNaN(p)) return "—";
  return "$" + p.toFixed(2);
};

export const fmtMcap = (b: number | null | undefined): string => {
  if (b == null || isNaN(b) || b === 0) return "—";
  if (b >= 1000) return "$" + (b / 1000).toFixed(1) + "T";
  return "$" + b.toFixed(0) + "B";
};

export const fmtPct = (n: number | null | undefined, d = 2): string => {
  if (n == null || isNaN(n)) return "—";
  return n.toFixed(d) + "%";
};
