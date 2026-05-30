/**
 * **Unrealized P&L = A1 − A2** — pure compute.
 *
 *   unrealized = equityMarketValue − equityCostBasis
 *
 * Lives in its own file (no React, no Supabase) so it's directly testable
 * and so the parity test against `computePortfolio` doesn't pull in the
 * client. The React hook `useUnrealizedPL` wraps this.
 */
import { type AtomFilter, equityCostBasis, equityMarketValue } from "./atoms";
import type { PositionRow } from "../types";

export interface UnrealizedPL {
  total: number;
  totalPct: number;
  byTicker: Map<string, number>;
  marketValue: number;
  costBasis: number;
}

export function computeUnrealizedPL(
  positions: PositionRow[],
  filter?: AtomFilter,
): UnrealizedPL {
  const marketValue = equityMarketValue(positions, filter);
  const costBasis = equityCostBasis(positions, filter);
  const total = marketValue - costBasis;
  const totalPct = costBasis === 0 ? 0 : (total / costBasis) * 100;

  // Per-ticker: one filtered atom-pair per ticker would be O(N × tickers);
  // do a single grouped pass instead.
  const mvByTicker = new Map<string, number>();
  const cbByTicker = new Map<string, number>();
  for (const p of positions) {
    if (p.status === "closed" || p.quantity <= 0) continue;
    if (filter?.ticker && p.ticker !== filter.ticker) continue;
    const px = p.current_price ?? p.avg_cost;
    mvByTicker.set(p.ticker, (mvByTicker.get(p.ticker) ?? 0) + p.quantity * px);
    cbByTicker.set(
      p.ticker,
      (cbByTicker.get(p.ticker) ?? 0) + p.quantity * p.avg_cost,
    );
  }
  const byTicker = new Map<string, number>();
  for (const [t, mv] of mvByTicker) {
    byTicker.set(t, mv - (cbByTicker.get(t) ?? 0));
  }

  return { total, totalPct, byTicker, marketValue, costBasis };
}
