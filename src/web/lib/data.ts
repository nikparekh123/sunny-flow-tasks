/* eslint-disable @typescript-eslint/no-explicit-any */
// Every number on the Sunny web comes from the same places the phone reads (README "Data the pages need": reuse,
// do not re-derive):
//   book_members        the logins' books (RLS: own rows)               HomeStore.bookID
//   home_snapshot       one Home per book, rebuilt every 15 to 30 s     HomeStore.source
//   home_todo           what to trade, owners only, laid back over it    HomeStore.layOver
//   home_brief_log      each moment's last brief, for the moment tabs   (web, 9 Nov 2026)
//   sunny-positions     one name's grid of P&L by price and date        PositionsLive
//   sunny-chart         one name's price history and layers             TickerChartLive
// Every reader filters by book: S is Nik's book, N his cousin's.
//
// DEV ONLY: `?fx` reads saved replies from /__fx/ (vite.config.ts serves SUNNY_FX_DIR there in dev, never in a
// build), so pages can be checked on real numbers without signing in, as the phone's -fixture does.
import { useEffect, useRef } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { liveHours, regularHours } from './clock';

export type BookId = 'S' | 'N';
export type J = any;
export interface HomeRow { payload: J; built_at: string; book_id: BookId }
export interface Member { book_id: BookId; role: 'owner' | 'viewer' | string }

/* ── Fixture mode (dev only) ─────────────────────────────────────────────── */
const fxFlag = () => {
  if (!import.meta.env.DEV || typeof window === 'undefined') return false;
  const q = new URLSearchParams(window.location.search);
  try {
    if (q.has('fx')) sessionStorage.setItem('sw-fx', '1');
    if (q.get('fxm')) sessionStorage.setItem('sw-fxm', q.get('fxm')!);
    return sessionStorage.getItem('sw-fx') === '1';
  } catch { return q.has('fx'); }
};
export const FX = import.meta.env.DEV ? fxFlag() : false;
const fxMoment = () => { try { return sessionStorage.getItem('sw-fxm') ?? ''; } catch { return ''; } };
const fx = async (path: string) => {
  const r = await fetch('/__fx/' + path);
  if (!r.ok) throw new Error(`fixture ${path} ${r.status}`);
  return r.json();
};

/* ── The owners' part laid back over the snapshot (sunny-home forOwners; HomeStore.layOver) ── */
const isObj = (v: unknown): v is Record<string, any> => !!v && typeof v === 'object' && !Array.isArray(v);
function lay(a: any, b: any): any {
  if (!isObj(a) || !isObj(b)) return b;
  const x: Record<string, any> = { ...a };
  for (const [k, v] of Object.entries(b)) x[k] = k in x ? lay(x[k], v) : v;
  return x;
}
export function layOver(row: HomeRow, todo: { book_id: string; payload: J }[] | null): HomeRow {
  const o = todo?.find((r) => r.book_id === row.book_id)?.payload;
  if (!o) return row;
  let p = row.payload;
  if (o.top) p = lay(p, o.top);
  if (o.names && p?.writes?.names) {
    p = { ...p, writes: { ...p.writes, names: p.writes.names.map((n: J) => (o.names[n.ticker] ? lay(n, o.names[n.ticker]) : n)) } };
  }
  return { ...row, payload: p };
}

/* ── Books ───────────────────────────────────────────────────────────────── */
/** The login's books, owners first then by id; S opens first when held (HomeStore.bookID). */
export function useBooks() {
  return useQuery({
    queryKey: ['sw', 'books'],
    staleTime: 180_000,
    refetchInterval: 180_000,
    queryFn: async (): Promise<Member[]> => {
      if (FX) return [{ book_id: 'S', role: 'owner' }, { book_id: 'N', role: 'owner' }];
      const { data, error } = await supabase.from('book_members' as never).select('book_id,role');
      if (error) throw error;
      const ms = (data ?? []) as unknown as Member[];
      return ms.sort((a, b) => (a.role === 'owner' ? 0 : 1) - (b.role === 'owner' ? 0 : 1) || a.book_id.localeCompare(b.book_id));
    },
  });
}

/* ── Home ────────────────────────────────────────────────────────────────── */
/** How often to read Home again: the server rebuilds every 15 s in the session, every 30 s from 4:00 to 20:00,
    and every 10 minutes otherwise. */
const homeEvery = () => (regularHours() ? 15_000 : liveHours() ? 30_000 : 300_000);

export function useHome(book: BookId | null | undefined) {
  return useQuery({
    queryKey: ['sw', 'home', book],
    enabled: !!book,
    staleTime: 10_000,
    refetchInterval: homeEvery,
    refetchOnWindowFocus: true,
    queryFn: async (): Promise<HomeRow> => {
      if (FX) {
        const row: HomeRow = await fx(`home-${book}.json`);
        let out = row;
        if (book === 'S') { try { out = layOver(row, [{ book_id: 'S', ...(await fx('todo-S.json')) }]); } catch { /* none */ } }
        const m = fxMoment();
        if (m) {
          try {
            const pin = await fx(`pinned/${book}-${m}.json`);
            out = { ...out, payload: { ...out.payload, brief: pin.brief ?? out.payload.brief, overview: pin.overview ?? out.payload.overview } };
          } catch { /* keep the saved moment */ }
        }
        return out;
      }
      const [snap, todo] = await Promise.all([
        supabase.from('home_snapshot' as never).select('payload,built_at,book_id').eq('book_id', book).single(),
        supabase.from('home_todo' as never).select('book_id,payload').eq('book_id', book),
      ]);
      if (snap.error) throw snap.error;
      return layOver(snap.data as unknown as HomeRow, (todo.data ?? null) as any);
    },
  });
}

/* ── The moment tabs' briefs ─────────────────────────────────────────────── */
export type Tab = 'pre' | 'open' | 'post' | 'weekend';
export const TAB_OF: Record<string, Tab> = { futures: 'pre', pre: 'pre', bell: 'open', open: 'open', last20: 'open', last5: 'open', post: 'post', weekend: 'weekend' };
export interface BriefLogRow { tab: Tab; audience: 'all' | 'owners'; moment: string; built_for: string; doc: J; built_at: string }

/** The last brief of each tab for this book: the owners' copy when this login owns the book, else the open one. */
export function useBriefLog(book: BookId | null | undefined) {
  return useQuery({
    queryKey: ['sw', 'brieflog', book],
    enabled: !!book,
    staleTime: 60_000,
    refetchInterval: 300_000,
    queryFn: async (): Promise<Partial<Record<Tab, BriefLogRow>>> => {
      let rows: BriefLogRow[] = [];
      if (FX) {
        const tabs: [Tab, string][] = [['pre', 'pre'], ['open', 'open'], ['post', 'post'], ['weekend', 'weekend']];
        for (const [tab, m] of tabs) {
          try { const pin = await fx(`pinned/${book}-${m}.json`); rows.push({ tab, audience: 'owners', moment: m, built_for: pin.brief?.doc?.built_for, doc: pin.brief?.doc, built_at: pin.built_at }); } catch { /* missing */ }
        }
      } else {
        const { data, error } = await supabase.from('home_brief_log' as never).select('tab,audience,moment,built_for,doc,built_at').eq('book_id', book);
        if (error) throw error;
        rows = (data ?? []) as unknown as BriefLogRow[];
      }
      const out: Partial<Record<Tab, BriefLogRow>> = {};
      for (const r of rows) if (r.doc && (!out[r.tab] || r.audience === 'owners')) out[r.tab] = r;
      return out;
    },
  });
}

/* ── Edge functions (the user's token; RLS and each function check the book) ── */
async function callFn(name: string, body: Record<string, unknown>): Promise<J> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new Error('signed out');
  const r = await fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`${name} ${r.status}`);
  return r.json();
}

/** One name's Positions grid: P&L and delta by price and date (wide: out to ±50% for the zoom). */
const positionsKey = (book: BookId | null | undefined, t: string | null | undefined) => ['sw', 'positions', book, t];
const fetchPositions = (book: BookId, t: string) => (FX ? fx(`grids/${book}-${t}.json`) : callFn('sunny-positions', { book, t, wide: true }));

/** The name on screen. Its grid is asked again when Home rebuilds (`built`), as PositionsLive does; a name already
    read (or read ahead, below) shows at once from what is kept and refreshes behind it. */
export function usePositions(book: BookId | null | undefined, t: string | null | undefined, built?: string) {
  const q = useQuery({
    queryKey: positionsKey(book, t),
    enabled: !!book && !!t,
    staleTime: 15_000,
    gcTime: 30 * 60_000,
    queryFn: () => fetchPositions(book!, t!),
  });
  const seen = useRef<string | undefined>(built);
  useEffect(() => {
    if (!built || seen.current === built) return;
    seen.current = built;
    if (book && t) void q.refetch();
  }, [built]); // eslint-disable-line react-hooks/exhaustive-deps
  return q;
}

/* ── Reading ahead (Nik, 9 Nov 2026: switching must be smooth, "do a lazy load") ── */
interface Ahead { key: unknown[]; fn: () => Promise<J>; stale: number }
const idle = (f: () => void) => {
  const w = window as unknown as { requestIdleCallback?: (cb: () => void, o?: { timeout: number }) => number };
  if (w.requestIdleCallback) w.requestIdleCallback(f, { timeout: 1500 }); else setTimeout(f, 300);
};

/** Reads `jobs` ahead one at a time, each when the page is idle, starting `delay` ms after the page is up, so a click
    shows the next page at once from what is kept. Anything already kept is skipped; nothing is read while the tab is
    hidden. `id` names the list, so a new list starts again and the old one stops. */
function useReadAhead(id: string, jobs: Ahead[], start: boolean, delay: number) {
  const qc = useQueryClient();
  const list = useRef(jobs);
  list.current = jobs;
  useEffect(() => {
    if (!start || !id) return;
    let live = true;
    const next = (i: number) => {
      const js = list.current;
      if (!live || i >= js.length) return;
      const j = js[i];
      if (document.hidden || qc.getQueryData(j.key)) { idle(() => next(i + 1)); return; }
      qc.prefetchQuery({ queryKey: j.key, queryFn: j.fn, staleTime: j.stale, gcTime: 30 * 60_000 }).finally(() => idle(() => next(i + 1)));
    };
    const tm = setTimeout(() => idle(() => next(0)), delay);
    return () => { live = false; clearTimeout(tm); };
  }, [id, start, delay]); // eslint-disable-line react-hooks/exhaustive-deps
}

const gridJob = (book: BookId, t: string): Ahead => ({ key: positionsKey(book, t), fn: () => fetchPositions(book, t), stale: 15_000 });

/** Positions: every other name's grid, nearest in the strip first, so a click on the strip shows the next name at once. */
export function usePrefetchPositions(book: BookId | null | undefined, names: string[], start: boolean) {
  const jobs = book ? names.map((t) => gridJob(book, t)) : [];
  useReadAhead(book ? book + ':' + names.join(',') : '', jobs, start, 600);
}

/** Home: what its clicks open, read once Home has drawn. The rail's names on Positions (the grid of each, in the
    rail's order), then the ticker page of each name held. */
export function usePrefetchFromHome(book: BookId | null | undefined, names: string[], start: boolean) {
  const jobs = book ? [...names.map((t) => gridJob(book, t)), ...names.map((t) => tickerJob(t, book))] : [];
  useReadAhead(book ? book + ':' + names.join(',') : '', jobs, start, 1500);
}

/** One ticker page read ahead on a hover or a keyboard focus (the watchlist and sector maps, too many to read all). */
export function usePrefetchTicker(book: BookId | null | undefined) {
  const qc = useQueryClient();
  return (t: string) => {
    if (!t || !book) return;
    const j = tickerJob(t, book);
    if (!qc.getQueryData(j.key)) void qc.prefetchQuery({ queryKey: j.key, queryFn: j.fn, staleTime: j.stale });
  };
}

/** One name's price history with its layers (positions, walls, technicals, targets). */
const tickerKey = (t: string | null | undefined, book?: BookId | null) => ['sw', 'ticker', t, book ?? ''];
const fetchTicker = (t: string, book?: BookId | null) => (FX ? fx(`charts/${book ?? 'S'}-${t}.json`) : callFn('sunny-chart', book ? { t, book } : { t }));
const tickerJob = (t: string, book: BookId): Ahead => ({ key: tickerKey(t, book), fn: () => fetchTicker(t, book), stale: 60_000 });

export function useTicker(t: string | null | undefined, book?: BookId | null) {
  return useQuery({
    queryKey: tickerKey(t, book),
    enabled: !!t,
    staleTime: 60_000,
    gcTime: 30 * 60_000,
    queryFn: () => fetchTicker(t!, book),
  });
}
