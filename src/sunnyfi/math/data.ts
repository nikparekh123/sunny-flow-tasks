/**
 * Math — calculator catalog.
 *
 * Each entry powers the palette (Cmd-K search) and the calc-shell header
 * crumbs. Adding a calculator is purely additive here; the shell binds by
 * `key` to the `calc-<key>` component when one is wired in.
 */

export type CalcCategory =
  | "pre-trade"
  | "scenario"
  | "macro"
  | "post-trade";

export interface CalcMeta {
  key: string;
  name: string;
  category: CalcCategory;
  // Short hint shown in the palette next to the calc name.
  hint: string;
  // True when there's no real component wired yet — palette can still find it
  // but the calc-loaded state shows a "coming soon" placeholder.
  comingSoon?: boolean;
}

export const CATEGORIES: Record<CalcCategory, { label: string; comingSoon?: boolean }> = {
  "pre-trade":  { label: "Pre-trade planning" },
  "scenario":   { label: "Scenario & risk" },
  "macro":      { label: "Macro",             comingSoon: true },
  "post-trade": { label: "Post-trade review", comingSoon: true },
};

export const CALCS: CalcMeta[] = [
  // Pre-trade planning
  { key: "pct-diff",        name: "Percentage difference", category: "pre-trade", hint: "Pre-trade planning" },
  { key: "expected-income", name: "Expected income",       category: "pre-trade", hint: "Pre-trade planning" },
  { key: "expected-move",   name: "Expected move",         category: "pre-trade", hint: "Pre-trade planning" },
  { key: "put-cost",        name: "Put cost",              category: "pre-trade", hint: "Pre-trade planning" },
  { key: "income-vs-cost",  name: "Income vs cost",        category: "pre-trade", hint: "Pre-trade planning" },

  // Scenario & risk
  { key: "scenario",        name: "Scenario calculator",   category: "scenario",  hint: "Scenario & risk" },
  { key: "stress",          name: "Stress calculator",     category: "scenario",  hint: "Scenario & risk" },
  { key: "expiration-pnl",  name: "Expiration P&L",        category: "scenario",  hint: "Scenario & risk" },
];

export function findCalc(key: string | null): CalcMeta | null {
  if (!key) return null;
  return CALCS.find((c) => c.key === key) ?? null;
}

export function categoryLabel(c: CalcCategory): string {
  return CATEGORIES[c].label;
}

export function popularCalcs(limit = 3): CalcMeta[] {
  // No usage data yet — use a curated list matching the design's "Popular this week".
  const order = ["expected-income", "put-cost", "scenario"];
  return order.map((k) => CALCS.find((c) => c.key === k)).filter(Boolean) as CalcMeta[];
}
