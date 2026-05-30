/**
 * React hook for the live-leg state of the option book (A9 + A10 + A11).
 *
 * Consumers should read counts/premium-outstanding from here rather than
 * computing them inline from `liveByTicker` etc.
 */
import { useMemo } from "react";
import type { AtomFilter } from "./atoms";
import { computeLiveLegs, type LiveLegs } from "./liveLegs";
import { useAtomSources } from "./useAtomSources";

export type { LiveLegs } from "./liveLegs";
export { computeLiveLegs } from "./liveLegs";

export interface UseLiveLegsResult extends LiveLegs {
  isLoading: boolean;
}

export function useLiveLegs(filter?: AtomFilter): UseLiveLegsResult {
  const { trades, isLoading } = useAtomSources();
  return useMemo(
    () => ({ ...computeLiveLegs(trades, filter), isLoading }),
    [trades, filter, isLoading],
  );
}
