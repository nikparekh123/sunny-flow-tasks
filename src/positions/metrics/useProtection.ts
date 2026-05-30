/**
 * React hook for protection cost (A5 − A7).
 */
import { useMemo } from "react";
import type { AtomFilter } from "./atoms";
import { computeProtection, type Protection } from "./protection";
import { useAtomSources } from "./useAtomSources";

export type { Protection } from "./protection";
export { computeProtection } from "./protection";

export interface UseProtectionResult extends Protection {
  isLoading: boolean;
}

export function useProtection(filter?: AtomFilter): UseProtectionResult {
  const { trades, isLoading } = useAtomSources();
  return useMemo(
    () => ({ ...computeProtection(trades, filter), isLoading }),
    [trades, filter, isLoading],
  );
}
