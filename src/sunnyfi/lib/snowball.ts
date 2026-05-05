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

/**
 * Trigger the refresh-snowball edge function on demand. Returns the
 * function's response so the UI can surface { updated, total, missing }.
 */
export interface RefreshResult {
  updated: number;
  total: number;
  missing: string[];
  missing_count: number;
  timestamp: string;
}
export async function refreshSnowball(): Promise<RefreshResult> {
  const { data, error } = await supabase.functions.invoke("refresh-snowball", {
    body: {},
  });
  if (error) throw error;
  return data as RefreshResult;
}

/**
 * Two-stage DCF intrinsic value per share.
 * - Years 1-10: project FCF growing at `stage1_growth_pct`
 * - Terminal: Gordon growth model with `terminal_growth_pct`
 * - Discount everything to PV at `discount_rate_pct`
 *
 * Returns intrinsic per share, or null if inputs are invalid (e.g.
 * discount ≤ terminal makes the terminal value diverge).
 */
export function dcfIntrinsic(opts: {
  total_owner_earnings: number; // starting FCF (in millions, matches CSV)
  shares_outstanding: number;   // millions
  stage1_growth_pct: number;
  discount_rate_pct: number;
  terminal_growth_pct: number;
}): number | null {
  const { total_owner_earnings, shares_outstanding } = opts;
  const g = opts.stage1_growth_pct / 100;
  const d = opts.discount_rate_pct / 100;
  const tg = opts.terminal_growth_pct / 100;
  if (!shares_outstanding || shares_outstanding <= 0) return null;
  if (d <= tg) return null; // Gordon model diverges
  // Stage 1: 10 years of growth, discounted.
  let pv = 0;
  let fcf = total_owner_earnings;
  for (let y = 1; y <= 10; y++) {
    fcf = fcf * (1 + g);
    pv += fcf / Math.pow(1 + d, y);
  }
  // Terminal value at end of year 10, discounted back.
  const tv = (fcf * (1 + tg)) / (d - tg);
  pv += tv / Math.pow(1 + d, 10);
  return pv / shares_outstanding;
}

export interface AssumptionPatch {
  stage1_growth_pct?: number;
  discount_rate_pct?: number;
  terminal_growth_pct?: number;
}

/**
 * Save assumption changes for a single ticker, recomputing intrinsic from
 * the existing total_owner_earnings + shares_outstanding (those don't move
 * unless you re-import the CSV). Returns the updated row.
 */
export async function updateAssumptions(
  ticker: string,
  patch: AssumptionPatch,
): Promise<Stock> {
  // Read current row to recompute intrinsic from the new inputs.
  const { data: current, error: readErr } = await supabase
    .from("snowball" as never)
    .select("*")
    .eq("ticker", ticker)
    .maybeSingle();
  if (readErr) throw readErr;
  if (!current) throw new Error(`Ticker ${ticker} not found.`);

  const row = current as unknown as Stock;
  const merged = {
    total_owner_earnings: row.total_owner_earnings ?? 0,
    shares_outstanding: row.shares_outstanding ?? 0,
    stage1_growth_pct:
      patch.stage1_growth_pct ?? row.stage1_growth_pct ?? 0,
    discount_rate_pct:
      patch.discount_rate_pct ?? row.discount_rate_pct ?? 0,
    terminal_growth_pct:
      patch.terminal_growth_pct ?? row.terminal_growth_pct ?? 0,
  };
  const newIntrinsic = dcfIntrinsic(merged);

  const updatePatch: Record<string, unknown> = { ...patch };
  if (newIntrinsic != null) {
    updatePatch.intrinsic_value = newIntrinsic;
    // Recompute the three TBP fields with their margins of safety.
    updatePatch.tbp_aggressive_15 = newIntrinsic * 0.85;
    updatePatch.tbp_conservative_30 = newIntrinsic * 0.7;
    updatePatch.tbp_deep_value_50 = newIntrinsic * 0.5;
  }

  const { data, error } = await supabase
    .from("snowball" as never)
    .update(updatePatch as never)
    .eq("ticker", ticker)
    .select()
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new Error("Update blocked or row not found.");
  return data as unknown as Stock;
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
