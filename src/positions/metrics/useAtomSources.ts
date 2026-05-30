/**
 * The thin adapter between `usePositions()` and the atom layer.
 *
 * Atoms are pure functions over raw rows — they don't know about Supabase,
 * React Query, or any of the heavy data plumbing in `usePositions`. This
 * hook pulls just the four arrays each atom needs and memoizes the bundle
 * so downstream metric hooks (`useUnrealizedPL`, `useIncome`, …) don't
 * re-render on unrelated changes.
 *
 * Downstream hooks should consume this — they should NEVER pull from
 * `usePositions()` directly. Single source of truth.
 */
import { useMemo } from "react";
import { usePositions } from "../usePositions";
import type { DailyClose, OptionTrade, PositionRow, ShareSell } from "../types";

export interface AtomSources {
  positions: PositionRow[];
  trades: OptionTrade[];
  shareSells: ShareSell[];
  dailyCloses: DailyClose[];
  isLoading: boolean;
}

export function useAtomSources(): AtomSources {
  const u = usePositions();
  return useMemo<AtomSources>(
    () => ({
      positions: u.positions,
      trades: u.trades,
      shareSells: u.shareSells,
      dailyCloses: u.dailyCloses,
      isLoading: u.isLoading,
    }),
    // Each reference is stable within React Query's cache; identity changes
    // exactly when the underlying row set changes.
    [u.positions, u.trades, u.shareSells, u.dailyCloses, u.isLoading],
  );
}
