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

  // Realtime: re-fetch whenever positions change (refresh-prices writes,
  // CSV import, etc.)
  useEffect(() => {
    const sub = supabase
      .channel('positions-realtime')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'positions' },
        () => qc.invalidateQueries({ queryKey: ['positions'] }),
      )
      .subscribe();
    return () => {
      supabase.removeChannel(sub);
    };
  }, [qc]);

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

      const { error: insError } = await supabase
        .from('positions' as never)
        .insert(cleaned as never);
      if (insError) throw insError;

      return { inserted: cleaned.length };
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['positions'] }),
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
    replacePositions,
    refreshPrices,
  };
}
