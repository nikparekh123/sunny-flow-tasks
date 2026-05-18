import { useEffect, useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { computePortfolio, type PositionRow, type Sector, SECTORS } from './types';

const VALID_SECTORS = new Set<string>(SECTORS);

export interface PositionInput {
  ticker: string;
  sector: string;
  quantity: number;
  avg_cost: number;
  /** Optional CSV-supplied strategy bucket. When present, the import upserts
   *  it into strategy_overlay (with default put_cost/put_frequency the user
   *  can later edit in /strategy). */
  strategy?: StrategyBucket;
}

export type StrategyBucket = 'income' | 'invest' | 'yield';

export interface OverlayLite {
  ticker: string;
  bucket: StrategyBucket;
}

export interface WatchingRow {
  id: string;
  ticker: string;
  name: string | null;
  sector: string;
  current_price: number | null;
}

export function usePositions() {
  const qc = useQueryClient();

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

  // Overlays — just the bucket per ticker, for the Strategy badge column.
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

  // Watching — tickers tracked but not yet bought.
  const { data: watching = [] } = useQuery({
    queryKey: ['watching'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('watching' as never)
        .select('*')
        .order('ticker');
      if (error) throw error;
      return (data ?? []) as unknown as WatchingRow[];
    },
  });

  // Realtime: invalidate the relevant query whenever the underlying table
  // changes. Positions writes come from refresh-prices + CSV import;
  // overlays come from /strategy; watching is owned by this page.
  useEffect(() => {
    const sub = supabase
      .channel('positions-realtime')
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
        { event: '*', schema: 'public', table: 'watching' },
        () => qc.invalidateQueries({ queryKey: ['watching'] }),
      )
      .subscribe();
    return () => {
      supabase.removeChannel(sub);
    };
  }, [qc]);

  const overlayByTicker = useMemo(() => {
    const m = new Map<string, StrategyBucket>();
    overlays.forEach((o) => m.set(o.ticker, o.bucket));
    return m;
  }, [overlays]);

  const addWatching = useMutation({
    mutationFn: async (row: { ticker: string; name?: string; sector?: string; current_price?: number }) => {
      const { error } = await supabase
        .from('watching' as never)
        .insert({
          ticker: row.ticker.trim().toUpperCase(),
          name: row.name ?? null,
          sector: row.sector ?? 'Other',
          current_price: row.current_price ?? null,
        } as never);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['watching'] }),
  });

  const removeWatching = useMutation({
    mutationFn: async (ticker: string) => {
      const { error } = await supabase
        .from('watching' as never)
        .delete()
        .eq('ticker', ticker);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['watching'] }),
  });

  const portfolio = useMemo(
    () => computePortfolio(rawPositions),
    [rawPositions],
  );

  // Replace all rows with the contents of a CSV. Wipe + insert in one txn-ish
  // pair of calls. (Supabase JS doesn't expose an explicit transaction so we
  // delete-then-insert; on insert error we'd need to handle restore — for now
  // we just surface the error.)
  const replacePositions = useMutation({
    mutationFn: async (rows: PositionInput[]) => {
      const cleaned = rows
        .map((r) => ({
          ticker: r.ticker.trim().toUpperCase(),
          sector: (VALID_SECTORS.has(r.sector) ? r.sector : 'Other') as Sector,
          quantity: Number(r.quantity),
          avg_cost: Number(r.avg_cost),
          strategy: r.strategy,
        }))
        .filter(
          (r) =>
            r.ticker &&
            !isNaN(r.quantity) &&
            r.quantity > 0 &&
            !isNaN(r.avg_cost) &&
            r.avg_cost >= 0,
        );

      // Wipe existing rows.
      const { error: delError } = await supabase
        .from('positions' as never)
        .delete()
        .gt('quantity', -1); // matches all rows (quantity is non-negative)
      if (delError) throw delError;

      if (cleaned.length === 0) return { inserted: 0 };

      // Insert positions (without the strategy field — that lives on overlay).
      const positionsToInsert = cleaned.map(({ strategy: _s, ...rest }) => {
        void _s;
        return rest;
      });
      const { error: insError } = await supabase
        .from('positions' as never)
        .insert(positionsToInsert as never);
      if (insError) throw insError;

      // Upsert strategy overlays for rows that included a strategy column.
      // Defaults for put_cost/put_frequency keep the row valid; user can
      // tune them later in /strategy.
      const overlayRows = cleaned
        .filter((r) => r.strategy)
        .map((r) => ({
          ticker: r.ticker,
          bucket: r.strategy!,
          put_cost: 0,
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

  return {
    positions: rawPositions,
    portfolio,
    isLoading,
    overlayByTicker,
    watching,
    replacePositions,
    refreshPrices,
    addWatching,
    removeWatching,
  };
}
