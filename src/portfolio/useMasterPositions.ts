/**
 * useMasterPositions — single hook that powers the /portfolio page.
 *
 * Pulls the 5 source tables in parallel (positions, option_trades,
 * option_greeks, ticker_quotes, share_sells) + the strategy overlay,
 * then joins them via buildCompanies() into the Company[] shape the
 * views already consume. Replaces the sample MODEL import in
 * MasterPositions.tsx without changing any rendered shape.
 *
 * Greeks + quotes are graceful — missing rows fall back to nulls /
 * derived values so the page renders the moment positions exist, even
 * before `mp-refresh` has been invoked.
 *
 * Also exposes a `refresh()` mutation that POSTs the mp-refresh edge
 * function, then invalidates the queries so the page picks up fresh
 * Greeks + quotes within a heartbeat.
 */
import { useMemo } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import type { Company } from "./data";
import {
  buildCompanies, buildPortfolio,
  type PortfolioRollup,
  type PositionRow, type OptionTradeRow, type OptionGreeksRow,
  type TickerQuoteRow, type ShareSellRow,
} from "./buildCompanies";

const STALE_MS = 60_000;     // 1 min — Greeks refresh on 15-min cadence anyway
const QUOTE_STALE_MS = 30_000; // spot ticks faster than Greeks

interface OverlayRow { ticker: string; bucket: "income" | "invest" | "yield" }

export interface UseMasterPositionsResult {
  companies: Company[];
  portfolio: PortfolioRollup;
  isLoading: boolean;
  isFetching: boolean;
  /** Latest captured_at timestamp across the live data we read. Null if
   *  the data layer has never been refreshed yet. */
  freshness: string | null;
  /** Manually invoke the mp-refresh edge function and then invalidate
   *  the relevant queries so the page re-renders with fresh marks. */
  refresh: () => void;
  refreshing: boolean;
  refreshError: string | null;
}

export function useMasterPositions(): UseMasterPositionsResult {
  const qc = useQueryClient();

  const positionsQ = useQuery({
    queryKey: ["mp_positions"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("positions" as never)
        .select("ticker, name, sector, quantity, avg_cost, current_price, prev_close, status, earnings_date, realized_stock_pl");
      if (error) throw error;
      return (data ?? []) as unknown as PositionRow[];
    },
    staleTime: STALE_MS,
  });

  const tradesQ = useQuery({
    queryKey: ["mp_trades"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("option_trades" as never)
        .select("id, ticker, trade_date, action, option_type, direction, contracts, strike, premium, expiry, closes_trade_id");
      if (error) throw error;
      return (data ?? []) as unknown as OptionTradeRow[];
    },
    staleTime: STALE_MS,
  });

  const greeksQ = useQuery({
    queryKey: ["mp_greeks"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("option_greeks" as never)
        .select("option_trade_id, delta, gamma, theta, vega, iv, open_interest, volume, last_mark, captured_at");
      if (error) throw error;
      return (data ?? []) as unknown as Array<OptionGreeksRow & { captured_at: string }>;
    },
    staleTime: STALE_MS,
  });

  const quotesQ = useQuery({
    queryKey: ["mp_quotes"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("ticker_quotes" as never)
        .select("ticker, spot, day_change_pct, beta, captured_at");
      if (error) throw error;
      return (data ?? []) as unknown as Array<TickerQuoteRow & { captured_at: string }>;
    },
    staleTime: QUOTE_STALE_MS,
  });

  const sellsQ = useQuery({
    queryKey: ["mp_share_sells"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("share_sells" as never)
        .select("ticker, realized_pl, trade_date");
      if (error) throw error;
      return (data ?? []) as unknown as ShareSellRow[];
    },
    staleTime: STALE_MS,
  });

  const overlayQ = useQuery({
    queryKey: ["mp_strategy_overlay"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("strategy_overlay" as never)
        .select("ticker, bucket");
      if (error) throw error;
      return (data ?? []) as unknown as OverlayRow[];
    },
    staleTime: 5 * 60_000,
  });

  const refreshMut = useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.functions.invoke("mp-refresh", { body: {} });
      if (error) throw new Error(error.message ?? "mp-refresh failed");
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["mp_greeks"] });
      qc.invalidateQueries({ queryKey: ["mp_quotes"] });
    },
  });

  return useMemo(() => {
    const strategyByT = new Map<string, "income" | "invest" | "yield">();
    for (const o of overlayQ.data ?? []) strategyByT.set(o.ticker.toUpperCase(), o.bucket);

    const companies = buildCompanies({
      positions:  positionsQ.data ?? [],
      trades:     tradesQ.data ?? [],
      greeks:     greeksQ.data ?? [],
      quotes:     quotesQ.data ?? [],
      shareSells: sellsQ.data ?? [],
      strategyByT,
    });
    const portfolio = buildPortfolio(companies);

    // Freshness = the most recent captured_at we saw across Greeks +
    // quotes. Used by the header to show "updated 09:41" or to grey out
    // when stale.
    let freshness: string | null = null;
    const pickMax = (xs: Array<{ captured_at: string }>) => {
      for (const x of xs) {
        if (!freshness || x.captured_at > freshness) freshness = x.captured_at;
      }
    };
    pickMax(greeksQ.data ?? []);
    pickMax(quotesQ.data ?? []);

    const isLoading =
      positionsQ.isLoading || tradesQ.isLoading || overlayQ.isLoading;
    const isFetching =
      positionsQ.isFetching || tradesQ.isFetching || greeksQ.isFetching ||
      quotesQ.isFetching || sellsQ.isFetching || overlayQ.isFetching;

    return {
      companies, portfolio,
      isLoading, isFetching, freshness,
      refresh: () => refreshMut.mutate(),
      refreshing: refreshMut.isPending,
      refreshError: refreshMut.error?.message ?? null,
    };
  }, [
    positionsQ.data, tradesQ.data, greeksQ.data, quotesQ.data, sellsQ.data, overlayQ.data,
    positionsQ.isLoading, tradesQ.isLoading, overlayQ.isLoading,
    positionsQ.isFetching, tradesQ.isFetching, greeksQ.isFetching,
    quotesQ.isFetching, sellsQ.isFetching, overlayQ.isFetching,
    refreshMut,
  ]);
}
