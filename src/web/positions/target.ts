// The Payoff target (round 168, handoff 2026-11-18 QUESTIONS A6): one price per book and name, kept on the server in
// public.payoff_targets (book_id, ticker, price, set_at; RLS: the book's members read, its owners write) so the phone
// can read it; only the web sets it. A save that cannot reach the server (signed out, a viewer, the dev fixtures, a
// network error) keeps the target on this page for the session and says nothing: the chart shows it either way.
import { useCallback } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { FX, type BookId } from '../lib/data';

/** Targets set here that the server has not taken (a failed save), by "book|ticker"; null is a clear. */
const local = new Map<string, number | null>();
const keyOf = (book: BookId | null | undefined, t: string | null | undefined) => ['sw', 'target', book ?? '', t ?? ''];

async function signedIn() {
  if (FX) return false;
  try { const { data } = await supabase.auth.getSession(); return !!data.session; } catch { return false; }
}

async function read(book: BookId, t: string): Promise<number | null> {
  const k = `${book}|${t}`;
  if (local.has(k)) return local.get(k) ?? null;
  if (!(await signedIn())) return null;
  try {
    const { data, error } = await supabase.from('payoff_targets' as never).select('price').eq('book_id', book).eq('ticker', t).maybeSingle();
    if (error) return null;
    const p = Number((data as { price?: number | string } | null)?.price);
    return p > 0 ? p : null;
  } catch { return null; }
}

/** True when the server took it. */
async function save(book: BookId, t: string, v: number | null): Promise<boolean> {
  if (!(await signedIn())) return false;
  try {
    const q = supabase.from('payoff_targets' as never);
    const { error } = v == null
      ? await q.delete().eq('book_id', book).eq('ticker', t)
      : await q.upsert({ book_id: book, ticker: t, price: v, set_at: new Date().toISOString() } as never, { onConflict: 'book_id,ticker' });
    return !error;
  } catch { return false; }
}

/** The name's target and a setter (null clears). The chart moves at once; the save follows. */
export function useTarget(book: BookId | null | undefined, t: string | null | undefined) {
  const qc = useQueryClient();
  const q = useQuery({
    queryKey: keyOf(book, t),
    enabled: !!book && !!t,
    staleTime: 60_000,
    gcTime: 30 * 60_000,
    queryFn: () => read(book!, t!),
  });
  const set = useCallback((v: number | null) => {
    if (!book || !t) return;
    const k = `${book}|${t}`;
    local.set(k, v);
    qc.setQueryData(keyOf(book, t), v);
    void save(book, t, v).then((ok) => { if (ok) local.delete(k); });
  }, [book, t, qc]);
  return { tg: (q.data as number | null | undefined) ?? null, set };
}
