import { useEffect, useId, useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import {
  computePortfolio,
  liveOptionsByTicker,
  realizedPLByTicker,
  type Action,
  type Direction,
  type OptionTrade,
  type OptionType,
  type PositionRow,
  type Sector,
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

  const overlayByTicker = useMemo(() => {
    const m = new Map<string, StrategyBucket>();
    overlays.forEach((o) => m.set(o.ticker, o.bucket));
    return m;
  }, [overlays]);

  const portfolio = useMemo(
    () => computePortfolio(rawPositions, trades),
    [rawPositions, trades],
  );

  // ── Position mutations (mostly unchanged) ───────────────────────
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

      const { error: delError } = await supabase
        .from('positions' as never)
        .delete()
        .gt('quantity', -1);
      if (delError) throw delError;

      if (cleaned.length === 0) return { inserted: 0 };

      // Strip the strategy field — it goes to strategy_overlay separately.
      const positionsToInsert = cleaned.map(({ strategy: _s, ...rest }) => {
        void _s;
        return rest;
      });
      const { error: insError } = await supabase
        .from('positions' as never)
        .insert(positionsToInsert as never);
      if (insError) throw insError;

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

      return { inserted: cleaned.length, overlaysWritten: overlayRows.length };
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
      const tables = ['option_trades', 'positions'] as const;
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
    },
  });

  return {
    positions: rawPositions,
    portfolio,
    isLoading,
    overlayByTicker,
    trades,
    tradesByTicker,
    liveByTicker,
    realizedByTicker,
    replacePositions,
    refreshPrices,
    addTrade,
    deleteTrade,
    setPositionStatus,
    setEarningsDate,
    deletePosition,
  };
}
