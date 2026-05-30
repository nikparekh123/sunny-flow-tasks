/**
 * React hook wrapper around `computeUnrealizedPL`. Pulls raw positions
 * from `useAtomSources` and memoizes the result.
 *
 * Pages should read from this hook instead of `usePositions().portfolio
 * .total_pnl` — single source of truth for "unrealized P&L".
 */
import { useMemo } from "react";
import type { AtomFilter } from "./atoms";
import { useAtomSources } from "./useAtomSources";
import { computeUnrealizedPL, type UnrealizedPL } from "./unrealizedPL";

export type { UnrealizedPL } from "./unrealizedPL";
export { computeUnrealizedPL } from "./unrealizedPL";

export interface UseUnrealizedPLResult extends UnrealizedPL {
  isLoading: boolean;
}

export function useUnrealizedPL(filter?: AtomFilter): UseUnrealizedPLResult {
  const { positions, isLoading } = useAtomSources();
  return useMemo(
    () => ({ ...computeUnrealizedPL(positions, filter), isLoading }),
    [positions, filter, isLoading],
  );
}
