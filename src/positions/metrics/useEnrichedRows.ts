/**
 * useEnrichedRows — decorate computePortfolio's PositionComputed[] with
 * master-data fields (ticker_quotes.spot for current_price, etc.) so the
 * legacy ledger surfaces and downstream readers automatically pick up the
 * fresher master prices without touching their JSX.
 *
 * Read pattern stays the same — rows[i].current_price still works, it
 * just resolves to `ticker_quotes.spot ?? positions.current_price ??
 * avg_cost` now. The hook is read-only and pure; pass any PositionComputed[]
 * through it.
 *
 * Used by PositionsPage and downstream modals so they share the same
 * spot that /portfolio's GreeksBar and /dashboard's totalValue read.
 */
import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import type { PositionComputed } from "../types";

interface QuoteRow { ticker: string; spot: number | null; day_change_pct: number | null }

/** Hook layer — fetches quotes (same React Query key the master uses, so
 *  it's cached across pages) and returns a decorator function. */
export function useMasterQuotes(): {
  decorate: (rows: PositionComputed[]) => PositionComputed[];
  spotByTicker: Map<string, number>;
  isLoading: boolean;
} {
  const q = useQuery({
    queryKey: ["mp_quotes"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("ticker_quotes" as never)
        .select("ticker, spot, day_change_pct");
      if (error) throw error;
      return (data ?? []) as unknown as QuoteRow[];
    },
    staleTime: 30_000,
  });

  return useMemo(() => {
    const spotByTicker = new Map<string, number>();
    for (const row of q.data ?? []) {
      if (row.spot != null) spotByTicker.set(row.ticker.toUpperCase(), row.spot);
    }
    const decorate = (rows: PositionComputed[]): PositionComputed[] => {
      if (spotByTicker.size === 0) return rows; // no master data yet — leave as-is
      return rows.map((r) => {
        const masterSpot = spotByTicker.get(r.ticker.toUpperCase());
        if (masterSpot == null) return r;
        // Override current_price + recompute downstream derived fields so
        // the ledger reads master pricing transparently.
        const market_value = r.quantity * masterSpot;
        const pnl_dollar = r.status === "closed" ? 0 : market_value - r.cost_basis;
        const pnl_pct = r.cost_basis === 0 ? 0 : (pnl_dollar / r.cost_basis) * 100;
        return {
          ...r,
          current_price: masterSpot,
          market_value,
          pnl_dollar,
          pnl_pct,
          // Recompute overall_pl since pnl_dollar changed; keep
          // realized_pl + realized_stock_pl as-is (those are independent
          // of spot).
          overall_pl: pnl_dollar + (r.realized_pl ?? 0) + (r.realized_stock_pl ?? 0),
        };
      });
    };
    return { decorate, spotByTicker, isLoading: q.isLoading };
  }, [q.data, q.isLoading]);
}
