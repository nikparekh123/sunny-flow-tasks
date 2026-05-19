import { useEffect, useId, useMemo } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import {
  daysUntil,
  type BeatStatus,
  type EarningsEvent,
  type FeedRow,
  type Sentiment,
  type TickerOrigin,
  type TickerPeer,
} from './types';

interface PositionLite {
  ticker: string;
  sector: string | null;
  quantity: number;
  current_price: number | null;
  avg_cost: number;
  status: 'open' | 'closed';
}

interface WatchingLite {
  ticker: string;
  sector: string | null;
}

interface PutProtectionLite {
  ticker: string;
  expiry: string;
}

/** Central data hook for the earnings module. Returns:
 *  - upcomingFeed: rows ready to render in the landing feed (owned + watching + peers)
 *  - eventsByTicker: every event grouped per ticker (for the ticker hub)
 *  - peersByTicker:  ticker → list of peer tickers
 *  - mutations: addEvent / updateEvent / deleteEvent / addPeer / removePeer
 */
export function useEarnings() {
  const qc = useQueryClient();
  const channelId = useId();

  // ── Raw data fetches ────────────────────────────────────────────────
  const { data: events = [], isLoading: eventsLoading } = useQuery({
    queryKey: ['earnings_events'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('earnings_events' as never)
        .select('*')
        .order('earnings_date', { ascending: false });
      if (error) throw error;
      return (data ?? []) as unknown as EarningsEvent[];
    },
  });

  const { data: peers = [] } = useQuery({
    queryKey: ['ticker_peers'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('ticker_peers' as never)
        .select('*')
        .order('ticker');
      if (error) throw error;
      return (data ?? []) as unknown as TickerPeer[];
    },
  });

  // We only need a thin slice of positions / watching / put_protection here.
  // We don't import usePositions to avoid pulling in the full portfolio compute.
  const { data: positions = [] } = useQuery({
    queryKey: ['earnings:positions_lite'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('positions' as never)
        .select('ticker, sector, quantity, current_price, avg_cost, status');
      if (error) throw error;
      return (data ?? []) as unknown as PositionLite[];
    },
  });

  const { data: watchingRows = [] } = useQuery({
    queryKey: ['earnings:watching_lite'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('watching' as never)
        .select('ticker, sector');
      if (error) throw error;
      return (data ?? []) as unknown as WatchingLite[];
    },
  });

  const { data: puts = [] } = useQuery({
    queryKey: ['earnings:puts_lite'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('put_protection' as never)
        .select('ticker, expiry');
      if (error) throw error;
      return (data ?? []) as unknown as PutProtectionLite[];
    },
  });

  // ── Realtime ───────────────────────────────────────────────────────
  useEffect(() => {
    const sub = supabase
      .channel(`earnings-realtime-${channelId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'earnings_events' },
        () => qc.invalidateQueries({ queryKey: ['earnings_events'] }),
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'ticker_peers' },
        () => qc.invalidateQueries({ queryKey: ['ticker_peers'] }),
      )
      .subscribe();
    return () => { supabase.removeChannel(sub); };
  }, [qc, channelId]);

  // ── Derived: indices ──────────────────────────────────────────────
  const eventsByTicker = useMemo(() => {
    const m = new Map<string, EarningsEvent[]>();
    for (const e of events) {
      const arr = m.get(e.ticker) ?? [];
      arr.push(e);
      m.set(e.ticker, arr);
    }
    // Ensure descending date inside each list (events query already ordered,
    // but the grouping doesn't guarantee per-ticker ordering globally).
    m.forEach((arr) => arr.sort((a, b) => b.earnings_date.localeCompare(a.earnings_date)));
    return m;
  }, [events]);

  const peersByTicker = useMemo(() => {
    const m = new Map<string, string[]>();
    for (const p of peers) {
      const arr = m.get(p.ticker) ?? [];
      arr.push(p.peer);
      m.set(p.ticker, arr);
    }
    return m;
  }, [peers]);

  const putExpiryByTicker = useMemo(() => {
    const m = new Map<string, string>();
    for (const p of puts) m.set(p.ticker, p.expiry);
    return m;
  }, [puts]);

  const totalMarketValue = useMemo(
    () =>
      positions.reduce(
        (s, p) =>
          p.status === 'closed' ? s : s + p.quantity * (p.current_price ?? p.avg_cost),
        0,
      ),
    [positions],
  );

  /** Pick the next upcoming event for a ticker — earliest date >= today.
   *  Falls back to most recent past event if no upcoming exists, so the
   *  card still shows the last known cadence. */
  const nextEventFor = (ticker: string): EarningsEvent | null => {
    const list = eventsByTicker.get(ticker);
    if (!list || list.length === 0) return null;
    const upcoming = list
      .filter((e) => daysUntil(e.earnings_date) >= 0)
      .sort((a, b) => a.earnings_date.localeCompare(b.earnings_date));
    if (upcoming.length > 0) return upcoming[0];
    return list[0]; // most recent past
  };

  // ── Upcoming feed assembly ────────────────────────────────────────
  const upcomingFeed = useMemo<FeedRow[]>(() => {
    // Build a map ticker → origin. Owned wins over watching wins over peer.
    const origin = new Map<string, { origin: TickerOrigin; sector: string | null; peer_of?: string }>();

    for (const p of positions) {
      if (p.status === 'closed') continue;
      origin.set(p.ticker, { origin: 'owned', sector: p.sector });
    }
    for (const w of watchingRows) {
      if (!origin.has(w.ticker)) origin.set(w.ticker, { origin: 'watching', sector: w.sector });
    }
    // Peers — pulled from owned + watching tickers
    for (const [t, list] of peersByTicker) {
      if (!origin.has(t)) continue;          // only follow peers of tickers we care about
      for (const peer of list) {
        if (!origin.has(peer)) origin.set(peer, { origin: 'peer', sector: null, peer_of: t });
      }
    }

    const out: FeedRow[] = [];
    for (const [ticker, meta] of origin) {
      const event = nextEventFor(ticker);
      const days = event ? daysUntil(event.earnings_date) : null;
      const ownedRow = meta.origin === 'owned' ? positions.find((p) => p.ticker === ticker) : null;
      const mv = ownedRow ? ownedRow.quantity * (ownedRow.current_price ?? ownedRow.avg_cost) : undefined;
      out.push({
        ticker,
        origin: meta.origin,
        sector: meta.sector,
        peer_of: meta.peer_of,
        market_value: mv,
        portfolio_pct:
          mv != null && totalMarketValue > 0 ? (mv / totalMarketValue) * 100 : undefined,
        put_expiry: meta.origin === 'owned' ? putExpiryByTicker.get(ticker) ?? null : null,
        event,
        days_to_earnings: days,
      });
    }

    // Drop events more than 30 days out; keep ones within window + tickers with no event yet
    // (so the user can add a date). Sort by days_to_earnings ascending; nulls last.
    return out
      .filter((r) => r.days_to_earnings == null || (r.days_to_earnings >= 0 && r.days_to_earnings <= 30) || r.origin === 'owned')
      .sort((a, b) => {
        if (a.days_to_earnings == null && b.days_to_earnings == null) return a.ticker.localeCompare(b.ticker);
        if (a.days_to_earnings == null) return 1;
        if (b.days_to_earnings == null) return -1;
        return a.days_to_earnings - b.days_to_earnings;
      });
  }, [positions, watchingRows, peersByTicker, putExpiryByTicker, eventsByTicker, totalMarketValue]);

  // ── Mutations ─────────────────────────────────────────────────────
  const upsertEvent = useMutation({
    mutationFn: async (row: {
      id?: string;
      ticker: string;
      earnings_date: string;
      fiscal_period?: string | null;
      summary?: string | null;
      beat_status?: BeatStatus | null;
      sentiment?: Sentiment | null;
      rev_reported?: number | null;
      eps_reported?: number | null;
      guidance_note?: string | null;
      source_url?: string | null;
    }) => {
      const { error } = await supabase
        .from('earnings_events' as never)
        .upsert({
          ...(row.id ? { id: row.id } : {}),
          ticker: row.ticker.trim().toUpperCase(),
          earnings_date: row.earnings_date,
          fiscal_period: row.fiscal_period ?? null,
          summary: row.summary ?? null,
          beat_status: row.beat_status ?? null,
          sentiment: row.sentiment ?? null,
          rev_reported: row.rev_reported ?? null,
          eps_reported: row.eps_reported ?? null,
          guidance_note: row.guidance_note ?? null,
          source_url: row.source_url ?? null,
        } as never, { onConflict: 'ticker,earnings_date' });
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['earnings_events'] }),
  });

  const deleteEvent = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from('earnings_events' as never)
        .delete()
        .eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['earnings_events'] }),
  });

  const addPeer = useMutation({
    mutationFn: async (args: { ticker: string; peer: string }) => {
      const t = args.ticker.trim().toUpperCase();
      const p = args.peer.trim().toUpperCase();
      if (!t || !p || t === p) throw new Error('Invalid peer');
      const { error } = await supabase
        .from('ticker_peers' as never)
        .insert({ ticker: t, peer: p } as never);
      if (error && !/duplicate key/i.test(error.message)) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['ticker_peers'] }),
  });

  const removePeer = useMutation({
    mutationFn: async (args: { ticker: string; peer: string }) => {
      const { error } = await supabase
        .from('ticker_peers' as never)
        .delete()
        .eq('ticker', args.ticker)
        .eq('peer', args.peer);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['ticker_peers'] }),
  });

  return {
    events,
    eventsByTicker,
    peers,
    peersByTicker,
    upcomingFeed,
    isLoading: eventsLoading,
    upsertEvent,
    deleteEvent,
    addPeer,
    removePeer,
  };
}
