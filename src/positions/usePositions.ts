import { useEffect, useId, useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import {
  computePutProtection,
  computePortfolio,
  type ExpenseEntry,
  type GainEntry,
  type GainSource,
  type PositionRow,
  type PutProtectionRow,
  type Sector,
  SECTORS,
} from './types';

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

export function usePositions() {
  const qc = useQueryClient();
  // Unique channel name per hook instance so multiple components calling
  // usePositions() don't collide on supabase.channel().
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

  // Gain entries (3-way: stock / call / put). One row per event.
  const { data: gainEntries = [] } = useQuery({
    queryKey: ['gain_entries'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('gain_entries' as never)
        .select('*')
        .order('gain_date', { ascending: false });
      if (error) throw error;
      return (data ?? []) as unknown as GainEntry[];
    },
  });

  // Put protection — one row per ticker (or none).
  const { data: putProtections = [] } = useQuery({
    queryKey: ['put_protection'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('put_protection' as never)
        .select('*');
      if (error) throw error;
      return (data ?? []) as unknown as PutProtectionRow[];
    },
  });

  // Expenses — outflows tracked separately from gains. Magnitudes only.
  const { data: expenseEntries = [] } = useQuery({
    queryKey: ['expenses'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('expenses' as never)
        .select('*')
        .order('expense_date', { ascending: false });
      if (error) throw error;
      return (data ?? []) as unknown as ExpenseEntry[];
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

  // Realtime: invalidate the relevant query whenever the underlying table
  // changes. Positions writes come from refresh-prices + CSV import;
  // overlays come from /strategy.
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
        { event: '*', schema: 'public', table: 'gain_entries' },
        () => qc.invalidateQueries({ queryKey: ['gain_entries'] }),
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'put_protection' },
        () => qc.invalidateQueries({ queryKey: ['put_protection'] }),
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'expenses' },
        () => qc.invalidateQueries({ queryKey: ['expenses'] }),
      )
      .subscribe();
    return () => {
      supabase.removeChannel(sub);
    };
  }, [qc, channelId]);

  const overlayByTicker = useMemo(() => {
    const m = new Map<string, StrategyBucket>();
    overlays.forEach((o) => m.set(o.ticker, o.bucket));
    return m;
  }, [overlays]);

  const gainsByTicker = useMemo(() => {
    const m = new Map<string, GainEntry[]>();
    for (const e of gainEntries) {
      const arr = m.get(e.ticker) ?? [];
      arr.push(e);
      m.set(e.ticker, arr);
    }
    return m;
  }, [gainEntries]);

  const putProtectionByTicker = useMemo(() => {
    const m = new Map<string, PutProtectionRow>();
    putProtections.forEach((p) => m.set(p.ticker, p));
    return m;
  }, [putProtections]);

  /** Map ticker → live cost incurred so far (used for P&L). */
  const putCostByTicker = useMemo(() => {
    const m = new Map<string, number>();
    putProtections.forEach((p) => {
      // Use the full premium paid as the "cost" against realized gains —
      // that's the v2 spec (Net realized = realized − put_cost).
      m.set(p.ticker, p.total_cost);
    });
    return m;
  }, [putProtections]);

  const expensesByTicker = useMemo(() => {
    const m = new Map<string, ExpenseEntry[]>();
    for (const e of expenseEntries) {
      const arr = m.get(e.ticker) ?? [];
      arr.push(e);
      m.set(e.ticker, arr);
    }
    return m;
  }, [expenseEntries]);

  const portfolio = useMemo(
    () => computePortfolio(rawPositions, gainsByTicker, putCostByTicker, expensesByTicker),
    [rawPositions, gainsByTicker, putCostByTicker, expensesByTicker],
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
      // put_cost moved to put_protection in v2 schema, so the overlay row
      // only needs bucket + put_frequency (default quarterly).
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

  // ── Gain entries mutations ─────────────────────────────────────────
  const addGain = useMutation({
    mutationFn: async (row: {
      ticker: string;
      gain_date: string;
      source: GainSource;
      amount: number;
      note?: string | null;
    }) => {
      const { error } = await supabase
        .from('gain_entries' as never)
        .insert({
          ticker: row.ticker.trim().toUpperCase(),
          gain_date: row.gain_date,
          source: row.source,
          amount: row.amount,
          note: row.note ?? null,
        } as never);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['gain_entries'] }),
  });

  const deleteGain = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from('gain_entries' as never)
        .delete()
        .eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['gain_entries'] }),
  });

  // ── Put protection mutations ───────────────────────────────────────
  const setPutProtection = useMutation({
    mutationFn: async (row: {
      ticker: string;
      total_cost: number;
      expiry: string;
      purchase_date?: string;
      contracts?: number | null;
      strike?: number | null;
    }) => {
      const today = new Date().toISOString().slice(0, 10);
      const { error } = await supabase
        .from('put_protection' as never)
        .upsert(
          {
            ticker: row.ticker,
            total_cost: row.total_cost,
            expiry: row.expiry,
            purchase_date: row.purchase_date ?? today,
            contracts: row.contracts ?? null,
            strike: row.strike ?? null,
            // Clear the cached quote on edit; the next refresh fills it in.
            current_premium: null,
            current_premium_at: null,
          } as never,
          { onConflict: 'ticker' },
        );
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['put_protection'] }),
  });

  // Pull live per-contract premiums from Polygon for every put_protection
  // row that has contracts + strike + expiry. Backed by an edge function;
  // see supabase/functions/refresh-put-quotes/index.ts.
  const refreshPutQuotes = useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.functions.invoke('refresh-put-quotes', {
        body: {},
      });
      if (error) throw error;
      return data as { updated: number; skipped: number; total: number };
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['put_protection'] }),
  });

  const clearPutProtection = useMutation({
    mutationFn: async (ticker: string) => {
      const { error } = await supabase
        .from('put_protection' as never)
        .delete()
        .eq('ticker', ticker);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['put_protection'] }),
  });

  // ── Expense mutations ──────────────────────────────────────────────
  const addExpense = useMutation({
    mutationFn: async (row: {
      ticker: string;
      expense_date: string;
      source: GainSource;
      amount: number;
      note?: string | null;
    }) => {
      const { error } = await supabase
        .from('expenses' as never)
        .insert({
          ticker: row.ticker.trim().toUpperCase(),
          expense_date: row.expense_date,
          source: row.source,
          amount: Math.abs(row.amount), // expenses are stored as magnitudes
          note: row.note ?? null,
        } as never);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['expenses'] }),
  });

  const deleteExpense = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from('expenses' as never)
        .delete()
        .eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['expenses'] }),
  });

  // ── Position status (open ↔ closed) ────────────────────────────────
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

  // ── Earnings date (single date per position) ──────────────────────
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

  return {
    positions: rawPositions,
    portfolio,
    isLoading,
    overlayByTicker,
    gainsByTicker,
    putProtectionByTicker,
    replacePositions,
    refreshPrices,
    addGain,
    deleteGain,
    addExpense,
    deleteExpense,
    expensesByTicker,
    setPutProtection,
    clearPutProtection,
    refreshPutQuotes,
    setPositionStatus,
    setEarningsDate,
  };
}

/** Convenience: expose computePutProtection from the data layer for components. */
export { computePutProtection };
