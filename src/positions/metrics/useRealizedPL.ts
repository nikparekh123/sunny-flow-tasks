/**
 * React hook for canonical Realized P&L = A3 + A8.
 *
 * Pages should read from this for "Realized" rather than summing per-row
 * `realized_pl + realized_stock_pl` themselves.
 */
import { useMemo } from "react";
import type { AtomFilter } from "./atoms";
import { computeRealizedPL, type RealizedPL } from "./realizedPL";
import { useAtomSources } from "./useAtomSources";

export type { RealizedPL } from "./realizedPL";
export { computeRealizedPL } from "./realizedPL";

export interface UseRealizedPLResult extends RealizedPL {
  isLoading: boolean;
}

export function useRealizedPL(filter?: AtomFilter): UseRealizedPLResult {
  const { trades, shareSells, isLoading } = useAtomSources();
  return useMemo(
    () => ({ ...computeRealizedPL(trades, shareSells, filter), isLoading }),
    [trades, shareSells, filter, isLoading],
  );
}
