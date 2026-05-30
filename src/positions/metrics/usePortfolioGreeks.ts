/**
 * React hook over A13–A17 Greeks atoms. Pages outside the Portfolio
 * page (Dashboard, Income, Positions hero) should consume from here
 * rather than reaching into Polygon or the master tables themselves.
 *
 * Data source: the same React Query keys (`mp_*`) that
 * `useMasterPositions` populates, so opening /portfolio in another tab
 * primes this hook for free.
 */
import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import type { OptionTrade, PositionRow } from "../types";
import {
  type AtomFilter,
} from "./atoms";
import {
  type LegGreek, type TickerQuote,
  betaWeightedDelta, portfolioDelta, portfolioGamma, portfolioTheta, portfolioVega,
} from "./greeksAtoms";

export interface PortfolioGreeks {
  delta: number;
  gamma: number;
  theta: number;
  vega: number;
  betaWeightedDelta: number;
}

export interface UsePortfolioGreeksResult extends PortfolioGreeks {
  isLoading: boolean;
}

export function usePortfolioGreeks(filter?: AtomFilter): UsePortfolioGreeksResult {
  const positionsQ = useQuery({
    queryKey: ["mp_positions"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("positions" as never)
        .select("ticker, status, quantity, avg_cost, current_price, prev_close, last_price_update, name, sector, earnings_date, realized_stock_pl, id");
      if (error) throw error;
      return (data ?? []) as unknown as PositionRow[];
    },
    staleTime: 60_000,
  });
  const tradesQ = useQuery({
    queryKey: ["mp_trades"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("option_trades" as never)
        .select("*");
      if (error) throw error;
      return (data ?? []) as unknown as OptionTrade[];
    },
    staleTime: 60_000,
  });
  const greeksQ = useQuery({
    queryKey: ["mp_greeks"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("option_greeks" as never)
        .select("option_trade_id, delta, gamma, theta, vega");
      if (error) throw error;
      return (data ?? []) as unknown as LegGreek[];
    },
    staleTime: 60_000,
  });
  const quotesQ = useQuery({
    queryKey: ["mp_quotes"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("ticker_quotes" as never)
        .select("ticker, beta");
      if (error) throw error;
      return (data ?? []) as unknown as TickerQuote[];
    },
    staleTime: 30_000,
  });

  return useMemo(() => {
    const positions = positionsQ.data ?? [];
    const trades    = tradesQ.data ?? [];
    const greeks    = greeksQ.data ?? [];
    const quotes    = quotesQ.data ?? [];
    return {
      delta: portfolioDelta(positions, trades, greeks, filter),
      gamma: portfolioGamma(trades, greeks, filter),
      theta: portfolioTheta(trades, greeks, filter),
      vega:  portfolioVega(trades, greeks, filter),
      betaWeightedDelta: betaWeightedDelta(positions, trades, greeks, quotes, filter),
      isLoading: positionsQ.isLoading || tradesQ.isLoading,
    };
  }, [
    positionsQ.data, tradesQ.data, greeksQ.data, quotesQ.data,
    positionsQ.isLoading, tradesQ.isLoading, filter,
  ]);
}
