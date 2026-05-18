// Strategy data layer — joins positions + strategy_overlay + gain_entries
// + watching, subscribes to all four for Realtime, exposes mutations.
//
// Source of truth is `positions` (owned by the Positions page); Strategy
// only writes to its own overlay / journal tables.

import { useEffect, useId, useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type {
  StrategyOverlayRow,
  GainEntryRow,
  WatchingRow,
  StrategyPosition,
  Bucket,
  PutFrequency,
} from './types';

interface RawPosition {
  id: string;
  ticker: string;
  name: string | null;
  sector: string;
  quantity: number;
  avg_cost: number;
  current_price: number | null;
}

export function useStrategy() {
  const qc = useQueryClient();
  // Unique channel name per hook instance — supabase's .channel(name) returns
  // the existing channel if one matches, so a shared name causes "cannot add
  // postgres_changes callbacks after subscribe()" when multiple components
  // mount useStrategy concurrently (Strategy wrapper + Dashboard + GainsLog).
  const channelId = useId();

  // ── Reads ──────────────────────────────────────────────────────────
  const positionsQ = useQuery({
    queryKey: ['strategy', 'positions'],
    queryFn: async (): Promise<RawPosition[]> => {
      const { data, error } = await supabase
        .from('positions' as never)
        .select('id, ticker, name, sector, quantity, avg_cost, current_price')
        .order('ticker');
      if (error) throw error;
      return (data ?? []) as unknown as RawPosition[];
    },
  });

  const overlaysQ = useQuery({
    queryKey: ['strategy', 'overlays'],
    queryFn: async (): Promise<StrategyOverlayRow[]> => {
      const { data, error } = await supabase
        .from('strategy_overlay' as never)
        .select('*');
      if (error) throw error;
      return (data ?? []) as unknown as StrategyOverlayRow[];
    },
  });

  const entriesQ = useQuery({
    queryKey: ['strategy', 'entries'],
    queryFn: async (): Promise<GainEntryRow[]> => {
      const { data, error } = await supabase
        .from('gain_entries' as never)
        .select('*');
      if (error) throw error;
      return (data ?? []) as unknown as GainEntryRow[];
    },
  });

  const watchingQ = useQuery({
    queryKey: ['strategy', 'watching'],
    queryFn: async (): Promise<WatchingRow[]> => {
      const { data, error } = await supabase
        .from('watching' as never)
        .select('*')
        .order('ticker');
      if (error) throw error;
      return (data ?? []) as unknown as WatchingRow[];
    },
  });

  // ── Realtime subscriptions ─────────────────────────────────────────
  useEffect(() => {
    const ch = supabase
      .channel(`strategy-realtime-${channelId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'positions' },
        () => qc.invalidateQueries({ queryKey: ['strategy', 'positions'] }),
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'strategy_overlay' },
        () => qc.invalidateQueries({ queryKey: ['strategy', 'overlays'] }),
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'gain_entries' },
        () => qc.invalidateQueries({ queryKey: ['strategy', 'entries'] }),
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'watching' },
        () => qc.invalidateQueries({ queryKey: ['strategy', 'watching'] }),
      )
      .subscribe();
    return () => {
      supabase.removeChannel(ch);
    };
  }, [qc, channelId]);

  // ── Join into the renderable shape ─────────────────────────────────
  const joined = useMemo(() => {
    const positions = positionsQ.data ?? [];
    const overlays = overlaysQ.data ?? [];
    const entries = entriesQ.data ?? [];

    const overlayByTicker = new Map<string, StrategyOverlayRow>();
    overlays.forEach((o) => overlayByTicker.set(o.ticker, o));
    const entriesByTicker = new Map<string, GainEntryRow[]>();
    entries.forEach((e) => {
      const arr = entriesByTicker.get(e.ticker) ?? [];
      arr.push(e);
      entriesByTicker.set(e.ticker, arr);
    });

    const tickersInPositions = new Set(positions.map((p) => p.ticker));

    const fromPositions: StrategyPosition[] = positions.map((p) => ({
      ticker: p.ticker,
      name: p.name,
      sector: p.sector,
      quantity: p.quantity,
      avg_cost: p.avg_cost,
      current_price: p.current_price,
      overlay: overlayByTicker.get(p.ticker) ?? null,
      entries: entriesByTicker.get(p.ticker) ?? [],
    }));

    // Closed = overlays whose ticker no longer exists in positions.
    const closed: StrategyPosition[] = overlays
      .filter((o) => !tickersInPositions.has(o.ticker))
      .map((o) => ({
        ticker: o.ticker,
        name: null,
        sector: 'Other',
        quantity: null,
        avg_cost: null,
        current_price: null,
        overlay: o,
        entries: entriesByTicker.get(o.ticker) ?? [],
      }));

    return {
      assigned: {
        income: fromPositions.filter((p) => p.overlay?.bucket === 'income'),
        invest: fromPositions.filter((p) => p.overlay?.bucket === 'invest'),
        yield:  fromPositions.filter((p) => p.overlay?.bucket === 'yield'),
      } as Record<Bucket, StrategyPosition[]>,
      unassigned: fromPositions.filter((p) => p.overlay === null),
      closed,
    };
  }, [positionsQ.data, overlaysQ.data, entriesQ.data]);

  // ── Mutations ──────────────────────────────────────────────────────
  const setStrategy = useMutation({
    mutationFn: async (args: {
      ticker: string;
      bucket: Bucket;
      put_cost: number;
      put_frequency: PutFrequency;
    }) => {
      const { error } = await supabase
        .from('strategy_overlay' as never)
        .upsert(
          {
            ticker: args.ticker,
            bucket: args.bucket,
            put_cost: args.put_cost,
            put_frequency: args.put_frequency,
          } as never,
          { onConflict: 'ticker' },
        );
      if (error) throw error;
    },
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ['strategy', 'overlays'] }),
  });

  const unassign = useMutation({
    mutationFn: async (ticker: string) => {
      const { error } = await supabase
        .from('strategy_overlay' as never)
        .delete()
        .eq('ticker', ticker);
      if (error) throw error;
    },
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ['strategy', 'overlays'] }),
  });

  const moveBucket = useMutation({
    mutationFn: async (args: { ticker: string; to: Bucket }) => {
      const { error } = await supabase
        .from('strategy_overlay' as never)
        .update({ bucket: args.to } as never)
        .eq('ticker', args.ticker);
      if (error) throw error;
    },
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ['strategy', 'overlays'] }),
  });

  // v2: each call inserts ONE gain entry. The Strategy page's old
  // "this week's options + stock" semantics map to two separate entries
  // (one call, one stock) created back-to-back.
  const logGain = useMutation({
    mutationFn: async (args: {
      ticker: string;
      gain_date: string;
      source: 'stock' | 'call' | 'put';
      amount: number;
      note?: string;
    }) => {
      const { error } = await supabase
        .from('gain_entries' as never)
        .insert(
          {
            ticker: args.ticker,
            gain_date: args.gain_date,
            source: args.source,
            amount: args.amount,
            note: args.note ?? null,
          } as never,
        );
      if (error) throw error;
    },
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ['strategy', 'entries'] }),
  });

  const deleteGain = useMutation({
    mutationFn: async (args: { id: string }) => {
      const { error } = await supabase
        .from('gain_entries' as never)
        .delete()
        .eq('id', args.id);
      if (error) throw error;
    },
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ['strategy', 'entries'] }),
  });

  const addWatch = useMutation({
    mutationFn: async (args: {
      ticker: string;
      name: string;
      sector: string;
      current_price: number;
    }) => {
      const { error } = await supabase
        .from('watching' as never)
        .upsert(
          {
            ticker: args.ticker,
            name: args.name,
            sector: args.sector,
            current_price: args.current_price,
          } as never,
          { onConflict: 'ticker' },
        );
      if (error) throw error;
    },
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ['strategy', 'watching'] }),
  });

  const removeWatch = useMutation({
    mutationFn: async (ticker: string) => {
      const { error } = await supabase
        .from('watching' as never)
        .delete()
        .eq('ticker', ticker);
      if (error) throw error;
    },
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ['strategy', 'watching'] }),
  });

  const isLoading =
    positionsQ.isLoading ||
    overlaysQ.isLoading ||
    entriesQ.isLoading ||
    watchingQ.isLoading;

  return {
    ...joined,
    watching: watchingQ.data ?? [],
    isLoading,
    setStrategy,
    unassign,
    moveBucket,
    logGain,
    deleteGain,
    addWatch,
    removeWatch,
  };
}
