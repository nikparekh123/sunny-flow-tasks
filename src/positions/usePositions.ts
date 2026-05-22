import { useEffect, useId, useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import {
  computePortfolio,
  liveOptionsByTicker,
  realizedPLByTicker,
  type Action,
  type ClosedVia,
  type DailyClose,
  type Direction,
  type OptionTrade,
  type OptionType,
  type PositionRow,
  type Sector,
  type ShareSell,
  type TickerSignals,
  SECTORS,
} from './types';

const VALID_SECTORS = new Set<string>(SECTORS);

export interface PositionInput {
  ticker: string;
  sector: string;
  quantity: number;
  avg_cost: number;
  /** Optional CSV-supplied strategy bucket. Upserts into strategy_overlay. */
  strategy?: StrategyBucket;
  /** Optional CSV-supplied position status. Governs the SHARES status
   *  on positions.status. Defaults to 'open'. Options are closed via
   *  the in-app close-trade flow, not this column. */
  status?: 'open' | 'closed';
}

export type StrategyBucket = 'income' | 'invest' | 'yield';

export interface OverlayLite {
  ticker: string;
  bucket: StrategyBucket;
}

export function usePositions() {
  const qc = useQueryClient();
  const channelId = useId();

  const { data: rawPositions = [], isLoading } = useQuery({
    queryKey: ['positions'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('positions' as never)
        .select('*')
        .order('ticker');
      if (error) throw error;
      return (data ?? []) as unknown as PositionRow[];
    },
  });

  // Single source of options activity. Replaces gain_entries / expenses /
  // put_protection. Each row is either an open or a close.
  const { data: trades = [] } = useQuery({
    queryKey: ['option_trades'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('option_trades' as never)
        .select('*')
        .order('trade_date', { ascending: false });
      if (error) throw error;
      return (data ?? []) as unknown as OptionTrade[];
    },
  });

  // Historical close prices per ticker per trading day — populated by
  // the pg_cron 'capture-daily-close' job 30 min after market close.
  // Used by the Resolve flow to auto-detect ITM vs OTM at expiry.
  const { data: dailyCloses = [] } = useQuery({
    queryKey: ['daily_closes'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('daily_closes' as never)
        .select('*');
      if (error) throw error;
      return (data ?? []) as unknown as DailyClose[];
    },
  });

  // Share-sale audit log (manual sells + assignment-driven sells).
  // Surfaced in the trades matrix as entries in the closed zone.
  const { data: shareSells = [] } = useQuery({
    queryKey: ['share_sells'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('share_sells' as never)
        .select('*')
        .order('trade_date', { ascending: false });
      if (error) throw error;
      return (data ?? []) as unknown as ShareSell[];
    },
  });

  // Daily technical indicators — populated by the refresh-signals edge
  // function (post-market-close cron). Read-only on the client.
  const { data: signalsRaw = [] } = useQuery({
    queryKey: ['ticker_signals'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('ticker_signals' as never)
        .select('*');
      if (error) throw error;
      return (data ?? []) as unknown as TickerSignals[];
    },
  });

  const { data: overlays = [] } = useQuery({
    queryKey: ['strategy_overlay_lite'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('strategy_overlay' as never)
        .select('ticker, bucket');
      if (error) throw error;
      return (data ?? []) as unknown as OverlayLite[];
    },
  });

  // Realtime invalidations.
  useEffect(() => {
    const sub = supabase
      .channel(`positions-realtime-${channelId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'positions' },
        () => qc.invalidateQueries({ queryKey: ['positions'] }),
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'strategy_overlay' },
        () => qc.invalidateQueries({ queryKey: ['strategy_overlay_lite'] }),
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'option_trades' },
        () => qc.invalidateQueries({ queryKey: ['option_trades'] }),
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'share_sells' },
        () => qc.invalidateQueries({ queryKey: ['share_sells'] }),
      )
      .subscribe();
    return () => { supabase.removeChannel(sub); };
  }, [qc, channelId]);

  // ── Derived maps ─────────────────────────────────────────────────
  const tradesByTicker = useMemo(() => {
    const m = new Map<string, OptionTrade[]>();
    for (const t of trades) {
      const arr = m.get(t.ticker) ?? [];
      arr.push(t);
      m.set(t.ticker, arr);
    }
    return m;
  }, [trades]);

  const liveByTicker = useMemo(() => liveOptionsByTicker(trades), [trades]);
  const realizedByTicker = useMemo(() => realizedPLByTicker(trades), [trades]);

  const shareSellsByTicker = useMemo(() => {
    const m = new Map<string, ShareSell[]>();
    for (const s of shareSells) {
      const arr = m.get(s.ticker) ?? [];
      arr.push(s);
      m.set(s.ticker, arr);
    }
    return m;
  }, [shareSells]);

  // Lookup: closePriceAt(ticker, isoDate) → close on that day or null.
  // Falls back to null when the snapshot doesn't exist (e.g., expiries
  // older than the day we started capturing, or weekend/holiday dates).
  const closeByTickerDate = useMemo(() => {
    const m = new Map<string, number>();
    for (const c of dailyCloses) m.set(`${c.ticker}|${c.date}`, c.close_price);
    return m;
  }, [dailyCloses]);
  const closePriceAt = (ticker: string, isoDate: string): number | null =>
    closeByTickerDate.get(`${ticker}|${isoDate}`) ?? null;

  const signalsByTicker = useMemo(() => {
    const m = new Map<string, TickerSignals>();
    for (const s of signalsRaw) m.set(s.ticker, s);
    return m;
  }, [signalsRaw]);

  const overlayByTicker = useMemo(() => {
    const m = new Map<string, StrategyBucket>();
    overlays.forEach((o) => m.set(o.ticker, o.bucket));
    return m;
  }, [overlays]);

  const portfolio = useMemo(
    () => computePortfolio(rawPositions, trades),
    [rawPositions, trades],
  );

  // ── CSV upsert (was destructive DELETE+INSERT). ─────────────────
  // New behaviour:
  //   • UPSERT by ticker — existing rows get qty / avg_cost updated.
  //   • REJECT if any CSV row reduces a ticker's share count (shares
  //     are sold via the Sell-Shares flow, not by lowering the CSV
  //     number, so realized_stock_pl gets accumulated properly).
  //   • Tickers in the DB but not in the CSV are LEFT ALONE.
  //   • realized_stock_pl is NOT in the upsert payload, so it survives
  //     each re-upload.
  const replacePositions = useMutation({
    mutationFn: async (rows: PositionInput[]) => {
      const cleaned = rows
        .map((r) => ({
          ticker: r.ticker.trim().toUpperCase(),
          sector: (VALID_SECTORS.has(r.sector) ? r.sector : 'Other') as Sector,
          quantity: Number(r.quantity),
          avg_cost: Number(r.avg_cost),
          strategy: r.strategy,
          status: r.status ?? 'open',
        }))
        .filter(
          (r) =>
            r.ticker &&
            !isNaN(r.quantity) &&
            r.quantity > 0 &&
            !isNaN(r.avg_cost) &&
            r.avg_cost >= 0,
        );

      if (cleaned.length === 0) return { upserted: 0, overlaysWritten: 0 };

      // Reduction guard — refuse any row where CSV qty < current qty.
      const { data: existingRows, error: readErr } = await supabase
        .from('positions' as never)
        .select('ticker, quantity');
      if (readErr) throw readErr;
      const existingQty = new Map<string, number>();
      for (const e of (existingRows ?? []) as Array<{ ticker: string; quantity: number }>) {
        existingQty.set(e.ticker, e.quantity);
      }
      const reductions: Array<{ ticker: string; from: number; to: number }> = [];
      for (const r of cleaned) {
        const cur = existingQty.get(r.ticker);
        if (cur != null && r.quantity < cur) {
          reductions.push({ ticker: r.ticker, from: cur, to: r.quantity });
        }
      }
      if (reductions.length > 0) {
        const detail = reductions
          .map((r) => `${r.ticker} (${r.from} → ${r.to})`)
          .join(', ');
        throw new Error(
          `CSV would reduce share count for: ${detail}. Use Sell Shares in-app to record the sale first, then re-upload.`,
        );
      }

      // Strip the strategy field — strategy_overlay is updated separately.
      const positionsToUpsert = cleaned.map(({ strategy: _s, ...rest }) => {
        void _s;
        return rest;
      });
      const { error: upsertErr } = await supabase
        .from('positions' as never)
        .upsert(positionsToUpsert as never, { onConflict: 'ticker' });
      if (upsertErr) throw upsertErr;

      const overlayRows = cleaned
        .filter((r) => r.strategy)
        .map((r) => ({
          ticker: r.ticker,
          bucket: r.strategy!,
          put_frequency: 'quarterly',
        }));
      if (overlayRows.length > 0) {
        const { error: ovError } = await supabase
          .from('strategy_overlay' as never)
          .upsert(overlayRows as never, { onConflict: 'ticker' });
        if (ovError) throw ovError;
      }

      return { upserted: cleaned.length, overlaysWritten: overlayRows.length };
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['positions'] });
      qc.invalidateQueries({ queryKey: ['strategy_overlay_lite'] });
    },
  });

  const refreshPrices = useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.functions.invoke('refresh-prices', {
        body: {},
      });
      if (error) throw error;
      return data as {
        updated: number;
        total: number;
        missing: string[];
        timestamp: string;
      };
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['positions'] }),
  });

  // ── Option-trade mutations ────────────────────────────────────────
  const addTrade = useMutation({
    mutationFn: async (row: {
      ticker: string;
      trade_date: string;
      action: Action;
      option_type: OptionType;
      direction: Direction;
      contracts: number;
      strike: number;
      premium: number;
      expiry: string;
      closes_trade_id?: string | null;
      note?: string | null;
    }) => {
      const { error } = await supabase
        .from('option_trades' as never)
        .insert({
          ticker: row.ticker.trim().toUpperCase(),
          trade_date: row.trade_date,
          action: row.action,
          option_type: row.option_type,
          direction: row.direction,
          contracts: row.contracts,
          strike: row.strike,
          premium: row.premium,
          expiry: row.expiry,
          closes_trade_id: row.closes_trade_id ?? null,
          note: row.note ?? null,
        } as never);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['option_trades'] }),
  });

  const deleteTrade = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from('option_trades' as never)
        .delete()
        .eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['option_trades'] }),
  });

  // Update an existing open trade. Only mutable fields are accepted —
  // direction and option_type are fixed because matched closes rely on
  // them. Realized P&L is derived, so any change here re-flows
  // automatically.
  const updateTrade = useMutation({
    mutationFn: async (args: {
      id: string;
      contracts: number;
      strike: number;
      premium: number;
      expiry: string;
      trade_date: string;
      note?: string | null;
    }) => {
      const { error } = await supabase
        .from('option_trades' as never)
        .update({
          contracts: args.contracts,
          strike: args.strike,
          premium: args.premium,
          expiry: args.expiry,
          trade_date: args.trade_date,
          note: args.note ?? null,
        } as never)
        .eq('id', args.id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['option_trades'] }),
  });

  // ── Position lifecycle ────────────────────────────────────────────
  const setPositionStatus = useMutation({
    mutationFn: async (args: { ticker: string; status: 'open' | 'closed' }) => {
      const { error } = await supabase
        .from('positions' as never)
        .update({ status: args.status } as never)
        .eq('ticker', args.ticker);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['positions'] }),
  });

  const setEarningsDate = useMutation({
    mutationFn: async (args: { ticker: string; earnings_date: string | null }) => {
      const { error } = await supabase
        .from('positions' as never)
        .update({ earnings_date: args.earnings_date } as never)
        .eq('ticker', args.ticker);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['positions'] }),
  });

  const deletePosition = useMutation({
    mutationFn: async (ticker: string) => {
      const t = ticker.trim().toUpperCase();
      const tables = ['option_trades', 'share_sells', 'positions'] as const;
      for (const table of tables) {
        const { error } = await supabase
          .from(table as never)
          .delete()
          .eq('ticker', t);
        if (error) throw new Error(`${table}: ${error.message}`);
      }
      return { ticker: t };
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['positions'] });
      qc.invalidateQueries({ queryKey: ['option_trades'] });
      qc.invalidateQueries({ queryKey: ['share_sells'] });
    },
  });

  // ── Manual share sale ────────────────────────────────────────────
  // Decrements positions.quantity, accumulates realized_stock_pl,
  // logs an entry in share_sells. avg_cost unchanged (selling doesn't
  // adjust basis).
  const sellShares = useMutation({
    mutationFn: async (args: {
      ticker: string;
      quantity: number;
      price: number;
      trade_date: string;
      note?: string | null;
    }) => {
      const t = args.ticker.trim().toUpperCase();
      // 1. Fetch current position state.
      const { data: posRow, error: readErr } = await supabase
        .from('positions' as never)
        .select('quantity, avg_cost, realized_stock_pl')
        .eq('ticker', t)
        .single();
      if (readErr) throw new Error(`positions read: ${readErr.message}`);
      const pos = posRow as { quantity: number; avg_cost: number; realized_stock_pl: number };
      if (args.quantity > pos.quantity) {
        throw new Error(`Can't sell ${args.quantity} sh — only ${pos.quantity} on hand.`);
      }
      const realized = (args.price - pos.avg_cost) * args.quantity;

      // 2. Insert share_sells audit row.
      const { error: insErr } = await supabase
        .from('share_sells' as never)
        .insert({
          ticker: t,
          quantity: args.quantity,
          price: args.price,
          trade_date: args.trade_date,
          source: 'manual',
          realized_pl: realized,
          note: args.note ?? null,
        } as never);
      if (insErr) throw new Error(`share_sells insert: ${insErr.message}`);

      // 3. Update position: qty down, realized accumulator up.
      const { error: updErr } = await supabase
        .from('positions' as never)
        .update({
          quantity: pos.quantity - args.quantity,
          realized_stock_pl: (pos.realized_stock_pl ?? 0) + realized,
        } as never)
        .eq('ticker', t);
      if (updErr) throw new Error(`positions update: ${updErr.message}`);

      return { ticker: t, realized };
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['positions'] });
      qc.invalidateQueries({ queryKey: ['share_sells'] });
    },
  });

  // ── Resolve an expired option open ───────────────────────────────
  // Three flavors:
  //   • expired      → log close at $0 with closed_via='expired_worthless'
  //   • rolled       → log close at buyback premium + new open referencing rolled_from
  //   • assigned     → log close at $0 with share_pnl snapshot, AND
  //                    insert share_sells row (short call) OR adjust
  //                    qty + avg_cost (short put)
  const resolveExpired = useMutation({
    mutationFn: async (
      args:
        | {
            kind: 'expired';
            open: OptionTrade;
            trade_date: string;
            note?: string | null;
          }
        | {
            kind: 'rolled';
            open: OptionTrade;
            close_premium: number;
            close_date: string;
            new_strike: number;
            new_premium: number;
            new_expiry: string;
            new_open_date: string;
            note?: string | null;
          }
        | {
            kind: 'assigned';
            open: OptionTrade;
            trade_date: string;
            note?: string | null;
          },
    ) => {
      const open = args.open;
      const ticker = open.ticker;

      if (args.kind === 'expired') {
        const { error } = await supabase
          .from('option_trades' as never)
          .insert({
            ticker,
            trade_date: args.trade_date,
            action: 'close',
            option_type: open.option_type,
            direction: open.direction,
            contracts: open.contracts,
            strike: open.strike,
            premium: 0,
            expiry: open.expiry,
            closes_trade_id: open.id,
            closed_via: 'expired_worthless',
            note: args.note ?? null,
          } as never);
        if (error) throw new Error(error.message);
        return { ticker, kind: 'expired' as const };
      }

      if (args.kind === 'rolled') {
        // Close the old open.
        const { error: closeErr } = await supabase
          .from('option_trades' as never)
          .insert({
            ticker,
            trade_date: args.close_date,
            action: 'close',
            option_type: open.option_type,
            direction: open.direction,
            contracts: open.contracts,
            strike: open.strike,
            premium: args.close_premium,
            expiry: open.expiry,
            closes_trade_id: open.id,
            closed_via: 'rolled',
            note: args.note ?? null,
          } as never);
        if (closeErr) throw new Error(`close insert: ${closeErr.message}`);

        // Open the new one, same side/type, new expiry+strike+premium.
        const { error: openErr } = await supabase
          .from('option_trades' as never)
          .insert({
            ticker,
            trade_date: args.new_open_date,
            action: 'open',
            option_type: open.option_type,
            direction: open.direction,
            contracts: open.contracts,
            strike: args.new_strike,
            premium: args.new_premium,
            expiry: args.new_expiry,
            rolled_from: open.id,
            note: args.note ?? null,
          } as never);
        if (openErr) throw new Error(`new open insert: ${openErr.message}`);
        return { ticker, kind: 'rolled' as const };
      }

      // kind === 'assigned'
      // Need current position for avg_cost (short call) / weighted-avg (short put).
      const { data: posRow, error: readErr } = await supabase
        .from('positions' as never)
        .select('quantity, avg_cost, realized_stock_pl')
        .eq('ticker', ticker)
        .single();
      if (readErr) throw new Error(`positions read: ${readErr.message}`);
      const pos = posRow as { quantity: number; avg_cost: number; realized_stock_pl: number };

      const shareQty = open.contracts * 100;
      const isShortCall = open.direction === 'short' && open.option_type === 'call';
      const isShortPut  = open.direction === 'short' && open.option_type === 'put';

      // Compute snapshot share_pnl & insert the close row.
      const sharePnl = isShortCall
        ? (open.strike - pos.avg_cost) * shareQty
        : 0; // short put assignment doesn't realize P&L; just changes basis

      const { data: closeIns, error: closeErr } = await supabase
        .from('option_trades' as never)
        .insert({
          ticker,
          trade_date: args.trade_date,
          action: 'close',
          option_type: open.option_type,
          direction: open.direction,
          contracts: open.contracts,
          strike: open.strike,
          premium: 0,
          expiry: open.expiry,
          closes_trade_id: open.id,
          closed_via: 'assigned',
          share_pnl: sharePnl,
          note: args.note ?? null,
        } as never)
        .select('id')
        .single();
      if (closeErr) throw new Error(`close insert: ${closeErr.message}`);
      const closeId = (closeIns as { id: string })?.id ?? null;

      if (isShortCall) {
        // Shares sold at strike — decrement qty, accumulate realized,
        // log a share_sells row.
        if (shareQty > pos.quantity) {
          throw new Error(
            `Assignment would sell ${shareQty} sh but only ${pos.quantity} on hand.`,
          );
        }
        const { error: sellErr } = await supabase
          .from('share_sells' as never)
          .insert({
            ticker,
            quantity: shareQty,
            price: open.strike,
            trade_date: args.trade_date,
            source: 'assignment',
            linked_option_close_id: closeId,
            realized_pl: sharePnl,
            note: args.note ?? null,
          } as never);
        if (sellErr) throw new Error(`share_sells insert: ${sellErr.message}`);

        const { error: updErr } = await supabase
          .from('positions' as never)
          .update({
            quantity: pos.quantity - shareQty,
            realized_stock_pl: (pos.realized_stock_pl ?? 0) + sharePnl,
          } as never)
          .eq('ticker', ticker);
        if (updErr) throw new Error(`positions update: ${updErr.message}`);
      } else if (isShortPut) {
        // Shares bought at strike — increment qty, recompute weighted avg.
        const newQty = pos.quantity + shareQty;
        const newAvg =
          newQty > 0
            ? (pos.quantity * pos.avg_cost + shareQty * open.strike) / newQty
            : open.strike;
        const { error: updErr } = await supabase
          .from('positions' as never)
          .update({ quantity: newQty, avg_cost: newAvg } as never)
          .eq('ticker', ticker);
        if (updErr) throw new Error(`positions update: ${updErr.message}`);
      }
      // (Long-option exercise paths intentionally not handled — out of
      //  scope per current design.)

      return { ticker, kind: 'assigned' as const, sharePnl };
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['positions'] });
      qc.invalidateQueries({ queryKey: ['option_trades'] });
      qc.invalidateQueries({ queryKey: ['share_sells'] });
    },
  });
  // Reference the unused enum to silence the linter — it's used for the
  // closed_via field literal values when callers pass them as string
  // literals.
  void (null as unknown as ClosedVia);

  return {
    positions: rawPositions,
    portfolio,
    isLoading,
    overlayByTicker,
    trades,
    tradesByTicker,
    liveByTicker,
    realizedByTicker,
    signalsByTicker,
    shareSells,
    shareSellsByTicker,
    closePriceAt,
    replacePositions,
    refreshPrices,
    addTrade,
    deleteTrade,
    updateTrade,
    sellShares,
    resolveExpired,
    setPositionStatus,
    setEarningsDate,
    deletePosition,
  };
}
