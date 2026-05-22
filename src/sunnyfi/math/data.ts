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
  "scenario":   { label: "Scenario & risk",   comingSoon: true },
  "macro":      { label: "Macro",             comingSoon: true },
  "post-trade": { label: "Post-trade review", comingSoon: true },
};

export const CALCS: CalcMeta[] = [
  { key: "pct-diff",        name: "Percentage difference", category: "pre-trade", hint: "Pre-trade planning" },
  { key: "expected-income", name: "Expected income",       category: "pre-trade", hint: "Pre-trade planning" },
  { key: "put-cost",        name: "Put cost",              category: "pre-trade", hint: "Pre-trade planning" },
  { key: "income-vs-cost",  name: "Income vs cost",        category: "pre-trade", hint: "Pre-trade planning" },
];

export function findCalc(key: string | null): CalcMeta | null {
  if (!key) return null;
  return CALCS.find((c) => c.key === key) ?? null;
}

export function categoryLabel(c: CalcCategory): string {
  return CATEGORIES[c].label;
}

export function popularCalcs(limit = 5): CalcMeta[] {
  // Quick-links row on the resting hero — first N live calcs in catalog order.
  return CALCS.slice(0, limit);
}
