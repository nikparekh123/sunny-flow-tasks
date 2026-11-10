/* eslint-disable @typescript-eslint/no-explicit-any */
// To do (handoff 2026-11-10-todo): Nik's own notes, one list for the app and the web, in public.todos.
// RLS (migration 20261110170000): Nik's list is shared by book S's owners (his two logins) and seen by no one else;
// any other book member (the cousin) gets a private list of his own (Nik, 10 Nov 2026: "yes give him his own private
// list"). The header shows To do to any book member; the server decides which list comes back. Writes are optimistic and go out one at a time, in order, so a quick
// check then uncheck lands in the order it was made. Every read pages past PostgREST's 1,000-row cap (done items
// stay forever, so the table only grows).
//
// DEV ONLY: in `?fx` mode there is no session: the list lives in memory, seeded from the prototype's sample with its
// dates moved so the prototype's "today" (Tue Oct 27, 2026) lands on New York's today. Supabase is never called.
import { useCallback, useMemo } from 'react';
import { useQuery, useQueryClient, type QueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { FX, useBooks } from '../lib/data';
import { ny } from '../lib/clock';
import { days, plus } from './parse';

export interface Todo {
  id: string;
  text: string;
  due: string | null;
  note: string;
  done: boolean;
  done_at: string | null;
  created_at: string;
  updated_at: string;
}
export type TodoPatch = Partial<Pick<Todo, 'text' | 'due' | 'note' | 'done'>>;

export const TODOS_KEY = ['sw', 'todos'];
const COLS = 'id,text,due,note,done,done_at,created_at,updated_at';
const tbl = () => supabase.from('todos' as never) as any;

/* ── Fixture mode: the prototype's sample, in memory ─────────────────────── */
const SAMPLE: [string, string | null, string, boolean?][] = [
  ['Download the September statements', '2026-10-26', ''],
  ['Call IBKR about the margin rate', '2026-10-27', 'Ask what the rate is over $250K'],
  ['Check the NKE ex-dividend date before Friday', '2026-10-29', ''],
  ['Move cash over for the Jan calls', '2026-10-30', 'About $12K from savings'],
  ['Read the BABA earnings preview', '2026-11-03', ''],
  ['Look at LULU again after the holidays', '2027-01-04', ''],
  ['Set up the 2026 tax lot report', null, ''],
  ['Renew the market data subscription', '2026-10-23', '', true],
  ['Update the watchlist', null, '', true],
];
let fxList: Todo[] | null = null;
const fxSeed = (): Todo[] => {
  const shift = days('2026-10-27', ny().date), t0 = Date.now() - 864e5;
  return SAMPLE.map(([text, d, note, done], i) => {
    const at = new Date(t0 + i * 1000).toISOString();
    return { id: 'fx' + (i + 1), text, due: d ? plus(d, shift) : null, note, done: !!done, done_at: done ? at : null, created_at: at, updated_at: at };
  });
};
const fxRows = () => (fxList ??= fxSeed());

/* ── Reads ───────────────────────────────────────────────────────────────── */
async function readAll(): Promise<Todo[]> {
  // A quarter second, like a real round trip, so the fixture meets the same races the live list does.
  if (FX) { await new Promise((r) => setTimeout(r, 250)); return fxRows().map((x) => ({ ...x })); }
  const all: Todo[] = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await tbl().select(COLS).order('created_at', { ascending: true }).order('id', { ascending: true }).range(from, from + 999);
    if (error) throw error;
    const rows = (data ?? []) as Todo[];
    all.push(...rows);
    if (rows.length < 1000) break;
  }
  return all;
}

/** Who this login is to the list: `on` for any book member (each has a list), `shared` for book S's owners (Nik's
    two logins share one list; anyone else's is their own). */
export function useTodoAccess(): { on: boolean; shared: boolean } {
  const { data } = useBooks();
  return { on: !!data?.length, shared: !!data?.some((m) => m.book_id === 'S' && m.role === 'owner') };
}

/* ── Writes: optimistic, then one at a time in order ─────────────────────── */
let chain: Promise<unknown> = Promise.resolve();
let pending = 0;
const noteTimers = new Map<string, ReturnType<typeof setTimeout>>();

function write(qc: QueryClient, remote: () => Promise<void>) {
  pending++;
  chain = chain.then(remote).catch((e) => { console.error('todos', e); }).finally(() => {
    pending--;
    // The server is the truth once every write has landed (a failed write comes back as it was).
    if (!pending) void qc.invalidateQueries({ queryKey: TODOS_KEY });
  });
}
/** The change on screen at once. A read in flight is cancelled first: its cancel puts back the list as it was when the
    read began, so the change is laid on after that, never under it. */
function local(qc: QueryClient, change: (xs: Todo[]) => Todo[]) {
  const apply = () => { qc.setQueryData<Todo[]>(TODOS_KEY, (xs) => change(xs ?? [])); };
  if (qc.isFetching({ queryKey: TODOS_KEY })) void qc.cancelQueries({ queryKey: TODOS_KEY }).then(apply);
  else apply();
}
const uuid = () => (typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID()
  : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = (Math.random() * 16) | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));

export function useTodos(enabled: boolean) {
  const qc = useQueryClient();
  const q = useQuery({
    queryKey: TODOS_KEY,
    enabled,
    staleTime: 15_000,
    refetchOnWindowFocus: true,
    // A read waits for the writes already queued, so it never brings back what was just changed here.
    queryFn: async () => { await chain; return readAll(); },
  });

  const add = useCallback((text: string, due: string | null) => {
    const now = new Date().toISOString();
    const row: Todo = { id: uuid(), text, due, note: '', done: false, done_at: null, created_at: now, updated_at: now };
    local(qc, (xs) => [...xs, row]);
    write(qc, async () => {
      if (FX) { fxRows().push({ ...row }); return; }
      const { error } = await tbl().insert({ id: row.id, text, due, note: '' });
      if (error) throw error;
    });
  }, [qc]);

  const set = useCallback((id: string, p: TodoPatch) => {
    const now = new Date().toISOString();
    const apply = (x: Todo): Todo => ({ ...x, ...p, updated_at: now, ...('done' in p ? { done_at: p.done ? now : null } : {}) });
    local(qc, (xs) => xs.map((x) => (x.id === id ? apply(x) : x)));
    write(qc, async () => {
      if (FX) { fxList = fxRows().map((x) => (x.id === id ? apply(x) : x)); return; }
      const { error } = await tbl().update(p).eq('id', id);
      if (error) throw error;
    });
  }, [qc]);

  /** The note shows as it is typed; it is saved once typing stops for half a second. */
  const note = useCallback((id: string, v: string) => {
    local(qc, (xs) => xs.map((x) => (x.id === id ? { ...x, note: v } : x)));
    clearTimeout(noteTimers.get(id));
    noteTimers.set(id, setTimeout(() => { noteTimers.delete(id); set(id, { note: v }); }, 500));
  }, [qc, set]);

  const remove = useCallback((id: string) => {
    clearTimeout(noteTimers.get(id));
    noteTimers.delete(id);
    local(qc, (xs) => xs.filter((x) => x.id !== id));
    write(qc, async () => {
      if (FX) { fxList = fxRows().filter((x) => x.id !== id); return; }
      const { error } = await tbl().delete().eq('id', id);
      if (error) throw error;
    });
  }, [qc]);

  const items = q.data;
  const open = useMemo(() => (items ? items.filter((x) => !x.done).length : null), [items]);
  return { items, open, ready: !!items, refetch: q.refetch, add, set, note, remove };
}
