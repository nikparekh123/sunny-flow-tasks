/**
 * Math — snapshot store.
 *
 * Snapshots are the unit of save/history/compare/share, persisted to Supabase
 * (table: public.math_snapshots) and scoped to the logged-in user via RLS.
 *
 * Live (in-progress) inputs are kept in localStorage per calc — those don't
 * round-trip the network on every keystroke. Only the Save flow writes to DB.
 */
import { useEffect, useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export interface Snapshot {
  id: string;
  calcKey: string;
  name: string;
  purpose?: string;
  /** Epoch ms. The DB column is timestamptz; we convert on read. */
  createdAt: number;
  payload: Record<string, unknown>;
}

interface DbRow {
  id: string;
  calc_key: string;
  name: string;
  purpose: string | null;
  payload: Record<string, unknown>;
  created_at: string;
}

function rowToSnap(r: DbRow): Snapshot {
  return {
    id: r.id,
    calcKey: r.calc_key,
    name: r.name,
    purpose: r.purpose ?? undefined,
    createdAt: new Date(r.created_at).getTime(),
    payload: r.payload ?? {},
  };
}

const SNAPS_KEY = ["math_snapshots"] as const;

export function useSnapshots() {
  const qc = useQueryClient();

  const query = useQuery({
    queryKey: SNAPS_KEY,
    queryFn: async (): Promise<Snapshot[]> => {
      const { data, error } = await supabase
        .from("math_snapshots" as never)
        .select("id, calc_key, name, purpose, payload, created_at")
        .order("created_at", { ascending: false });
      if (error) throw error;
      return (data as DbRow[] | null)?.map(rowToSnap) ?? [];
    },
    // Snapshots are user-edited; stale-while-revalidate keeps the UI snappy
    // after a create/delete (we also invalidate explicitly).
    staleTime: 30_000,
  });

  const createMut = useMutation({
    mutationFn: async (input: {
      calcKey: string;
      name?: string;
      purpose?: string;
      payload?: Record<string, unknown>;
    }): Promise<Snapshot> => {
      const { data: u } = await supabase.auth.getUser();
      if (!u.user) throw new Error("Not signed in");
      const insert = {
        user_id:  u.user.id,
        calc_key: input.calcKey,
        name:     (input.name && input.name.trim()) || "Untitled snapshot",
        purpose:  input.purpose ?? null,
        payload:  input.payload ?? {},
      };
      const { data, error } = await supabase
        .from("math_snapshots" as never)
        .insert(insert)
        .select("id, calc_key, name, purpose, payload, created_at")
        .single();
      if (error) throw error;
      return rowToSnap(data as DbRow);
    },
    onSuccess: (snap) => {
      // Optimistic prepend so the History list updates instantly.
      qc.setQueryData<Snapshot[]>(SNAPS_KEY, (prev) => [snap, ...(prev ?? [])]);
    },
  });

  const removeMut = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from("math_snapshots" as never).delete().eq("id", id);
      if (error) throw error;
      return id;
    },
    onSuccess: (id) => {
      qc.setQueryData<Snapshot[]>(SNAPS_KEY, (prev) =>
        (prev ?? []).filter((s) => s.id !== id),
      );
    },
  });

  const renameMut = useMutation({
    mutationFn: async ({ id, name }: { id: string; name: string }) => {
      const { error } = await supabase
        .from("math_snapshots" as never)
        .update({ name })
        .eq("id", id);
      if (error) throw error;
      return { id, name };
    },
    onSuccess: ({ id, name }) => {
      qc.setQueryData<Snapshot[]>(SNAPS_KEY, (prev) =>
        (prev ?? []).map((s) => (s.id === id ? { ...s, name } : s)),
      );
    },
  });

  return {
    snaps: query.data ?? [],
    isLoading: query.isLoading,
    isFetching: query.isFetching,
    error: query.error as Error | null,
    /** Create returns a promise so callers can await the assigned id. */
    create: (input: { calcKey: string; name?: string; purpose?: string; payload?: Record<string, unknown> }) =>
      createMut.mutateAsync(input),
    remove: (id: string) => removeMut.mutate(id),
    rename: (id: string, name: string) => renameMut.mutate({ id, name }),
  };
}

// ── Per-calc live state (localStorage — transient, not synced to DB) ─────
function liveKey(calcKey: string): string {
  return `calc.${calcKey}.live`;
}

export function readLiveState<T>(calcKey: string, fallback: T): T {
  if (typeof window === "undefined") return fallback;
  try {
    const raw = window.localStorage.getItem(liveKey(calcKey));
    if (!raw) return fallback;
    return { ...fallback, ...JSON.parse(raw) } as T;
  } catch {
    return fallback;
  }
}

export function useLiveState<T extends Record<string, unknown>>(
  calcKey: string | null,
  initial: T,
): [T, (next: T | ((prev: T) => T)) => void] {
  const [state, setState] = useState<T>(() =>
    calcKey ? readLiveState<T>(calcKey, initial) : initial,
  );

  useEffect(() => {
    if (!calcKey) return;
    setState(readLiveState<T>(calcKey, initial));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [calcKey]);

  const set = (next: T | ((prev: T) => T)) => {
    setState((prev) => {
      const v = typeof next === "function" ? (next as (p: T) => T)(prev) : next;
      if (calcKey) {
        try { window.localStorage.setItem(liveKey(calcKey), JSON.stringify(v)); } catch { /* private mode */ }
      }
      return v;
    });
  };

  return [state, set];
}

/** Format a relative time string (e.g. "2m ago", "1h ago", "Mon"). */
export function relTime(ts: number, now: number = Date.now()): string {
  const dMs = now - ts;
  const m = Math.round(dMs / 60_000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  const h = Math.round(m / 60);
  if (h < 24) return `${h}h ago`;
  const days = Math.round(h / 24);
  if (days < 7) {
    return new Date(ts).toLocaleDateString(undefined, { weekday: "short" });
  }
  return new Date(ts).toLocaleDateString(undefined, { month: "short", day: "numeric" });
}
