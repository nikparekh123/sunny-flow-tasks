/**
 * React hook wrapping `computeIncome`. Pulls trades from `useAtomSources`.
 *
 * The Income page and dashboard should both read from this — single source
 * of truth for "Net premium kept" (Income = A4 − A6).
 */
import { useMemo } from "react";
import type { AtomFilter } from "./atoms";
import { computeIncome, type Income } from "./income";
import { useAtomSources } from "./useAtomSources";

export type { Income } from "./income";
export { computeIncome } from "./income";

export interface UseIncomeResult extends Income {
  isLoading: boolean;
}

export function useIncome(filter?: AtomFilter): UseIncomeResult {
  const { trades, isLoading } = useAtomSources();
  return useMemo(
    () => ({ ...computeIncome(trades, filter), isLoading }),
    [trades, filter, isLoading],
  );
}
