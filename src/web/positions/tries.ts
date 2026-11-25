// Try in Payoff (handoff 2026-11-24 §4; the prototype's localStorage sunny.try186): a strike tried from Intelligence
// is kept per book and name on the server in public.payoff_tries (book_id, ticker, id, side 's'|'b', ty 'c'|'p',
// strike, expiry, n, on_, set_at; RLS: the book's members read, its owners write), so the phone and the web show the
// same legs. The web lists them in What if as legs "from Intelligence" with a switch and ✕, and in Payoff and Every
// leg. The switch writes on_, the ✕ deletes the row. The page moves at once; the save follows, and a save the server
// does not take (a viewer, signed out) keeps the change on this page for the session and says nothing.
// DEV ONLY: with ?fx the rows live in sessionStorage (sw-tries-fx, { "book|TICKER": Try[] }) so the page can be checked.
import { useCallback, useMemo } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { FX, type BookId } from '../lib/data';

export interface Try { id: string; side: 's' | 'b'; ty: 'c' | 'p'; K: number; ex: string; n: number; on: boolean }

const FXK = 'sw-tries-fx';
const keyOf = (book: BookId | null | undefined, t: string | null | undefined) => ['sw', 'tries', book ?? '', t ?? ''];
const fxAll = (): Record<string, Try[]> => { try { return JSON.parse(sessionStorage.getItem(FXK) || '{}'); } catch { return {}; } };
const fxPut = (k: string, v: Try[]) => { try { const m = fxAll(); if (v.length) m[k] = v; else delete m[k]; sessionStorage.setItem(FXK, JSON.stringify(m)); } catch { /* private window */ } };

/** A stable number for a try's text id, so it can sit in the page's trades (negative: never a What if trade's id). */
export const tryNum = (id: string) => { let h = 2166136261; for (let i = 0; i < id.length; i++) { h ^= id.charCodeAt(i); h = Math.imul(h, 16777619); } return -1 - ((h >>> 0) % 2_000_000_000); };

const rowOf = (r: Record<string, unknown>): Try | null => {
  const K = Number(r.strike), n = Number(r.n), ex = String(r.expiry ?? '').slice(0, 10);
  const side = r.side === 'b' ? 'b' : r.side === 's' ? 's' : null, ty = r.ty === 'p' ? 'p' : r.ty === 'c' ? 'c' : null;
  if (!side || !ty || !(K > 0) || !(n > 0) || !/^\d{4}-\d\d-\d\d$/.test(ex)) return null;
  return { id: String(r.id), side, ty, K, ex, n, on: r.on_ !== false };
};

/** Changes the server has not taken yet (or refused), by "book|ticker": they win over a read until a save lands. */
const local = new Map<string, Try[]>();

async function read(book: BookId, t: string): Promise<Try[]> {
  if (FX) return fxAll()[`${book}|${t}`] ?? [];
  const k = `${book}|${t}`;
  if (local.has(k)) return local.get(k)!;
  try {
    const { data, error } = await supabase.from('payoff_tries' as never).select('id,side,ty,strike,expiry,n,on_,set_at').eq('book_id', book).eq('ticker', t).order('set_at', { ascending: true });
    if (error) return [];
    return ((data ?? []) as Record<string, unknown>[]).map(rowOf).filter((x): x is Try => !!x);
  } catch { return []; }
}

/** True when the server took it. */
async function save(book: BookId, t: string, op: { on?: { ids: string[]; v: boolean }; drop?: string[] }): Promise<boolean> {
  if (FX) return true;
  try {
    if (op.on?.ids.length) {
      const { error } = await supabase.from('payoff_tries' as never).update({ on_: op.on.v } as never).eq('book_id', book).eq('ticker', t).in('id', op.on.ids);
      if (error) return false;
    }
    if (op.drop?.length) {
      const { error } = await supabase.from('payoff_tries' as never).delete().eq('book_id', book).eq('ticker', t).in('id', op.drop);
      if (error) return false;
    }
    return true;
  } catch { return false; }
}

/** The name's tried strikes, and their switch and ✕. Read every minute, so a try made on the phone shows here. */
export function useTries(book: BookId | null | undefined, t: string | null | undefined) {
  const qc = useQueryClient();
  const key = useMemo(() => keyOf(book, t), [book, t]);
  const q = useQuery({
    queryKey: key,
    enabled: !!book && !!t,
    staleTime: 30_000,
    gcTime: 30 * 60_000,
    refetchInterval: 60_000,
    refetchOnWindowFocus: true,
    queryFn: () => read(book!, t!),
  });
  const list = useMemo(() => (q.data as Try[] | undefined) ?? [], [q.data]);
  const apply = useCallback((f: (xs: Try[]) => Try[]) => {
    const next = f((qc.getQueryData(key) as Try[] | undefined) ?? []);
    qc.setQueryData(key, next);
    if (book && t) { if (FX) fxPut(`${book}|${t}`, next); else local.set(`${book}|${t}`, next); }
  }, [qc, key, book, t]);
  const done = useCallback((ok: boolean) => { if (ok && book && t) local.delete(`${book}|${t}`); }, [book, t]);
  /** Every try in `ids` on (v true) or off. */
  const setOn = useCallback((ids: string[], v: boolean) => {
    if (!book || !t || !ids.length) return;
    apply((xs) => xs.map((x) => (ids.includes(x.id) ? { ...x, on: v } : x)));
    void save(book, t, { on: { ids, v } }).then(done);
  }, [apply, done, book, t]);
  const toggle = useCallback((id: string) => {
    const x = list.find((y) => y.id === id);
    if (x) setOn([id], !x.on);
  }, [list, setOn]);
  const remove = useCallback((ids: string[]) => {
    if (!book || !t || !ids.length) return;
    apply((xs) => xs.filter((x) => !ids.includes(x.id)));
    void save(book, t, { drop: ids }).then(done);
  }, [apply, done, book, t]);
  return { list, setOn, toggle, remove };
}
