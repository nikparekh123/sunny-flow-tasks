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

export type SnapshotKind = "snapshot" | "variant";

export interface Snapshot {
  id: string;
  calcKey: string;
  /** 'snapshot' = canonical per-ticker, lives in Compare. 'variant' = per-ticker
   *  exploration card, lives only in the calc's Variants strip. */
  kind: SnapshotKind;
  name: string;
  purpose?: string;
  /** Epoch ms. The DB column is timestamptz; we convert on read. */
  createdAt: number;
  payload: Record<string, unknown>;
}

interface DbRow {
  id: string;
  calc_key: string;
  kind: SnapshotKind;
  name: string;
  purpose: string | null;
  payload: Record<string, unknown>;
  created_at: string;
}

function rowToSnap(r: DbRow): Snapshot {
  return {
    id: r.id,
    calcKey: r.calc_key,
    kind: r.kind ?? "snapshot",
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
      // Snapshots only — variants live in their own per-calc strip and
      // shouldn't pollute the global Compare / History views.
      const { data, error } = await supabase
        .from("math_snapshots" as never)
        .select("id, calc_key, kind, name, purpose, payload, created_at")
        .eq("kind", "snapshot")
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
        kind:     "snapshot",
        name:     (input.name && input.name.trim()) || "Untitled snapshot",
        purpose:  input.purpose ?? null,
        payload:  input.payload ?? {},
      };
      const { data, error } = await supabase
        .from("math_snapshots" as never)
        .insert(insert)
        .select("id, calc_key, kind, name, purpose, payload, created_at")
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

  /** Replace an existing snapshot's payload + name + timestamp in place. Used
   *  by upsert flows where the caller already found the row to overwrite. */
  const updateMut = useMutation({
    mutationFn: async (input: {
      id: string;
      name: string;
      purpose?: string;
      payload: Record<string, unknown>;
    }): Promise<Snapshot> => {
      const patch = {
        name: input.name,
        purpose: input.purpose ?? null,
        payload: input.payload,
        // Bump created_at so the upserted snapshot floats to the top of
        // History (acts like a "last edited" timestamp for compare/sort).
        created_at: new Date().toISOString(),
      };
      const { data, error } = await supabase
        .from("math_snapshots" as never)
        .update(patch)
        .eq("id", input.id)
        .select("id, calc_key, kind, name, purpose, payload, created_at")
        .single();
      if (error) throw error;
      return rowToSnap(data as DbRow);
    },
    onSuccess: (snap) => {
      qc.setQueryData<Snapshot[]>(SNAPS_KEY, (prev) =>
        // Move the updated snap to the front so the History list reflects it.
        [snap, ...(prev ?? []).filter((s) => s.id !== snap.id)],
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
    /** Replace an existing snapshot's payload (used by upsert-by-ticker save). */
    update: (input: { id: string; name: string; purpose?: string; payload: Record<string, unknown> }) =>
      updateMut.mutateAsync(input),
    remove: (id: string) => removeMut.mutate(id),
    rename: (id: string, name: string) => renameMut.mutate({ id, name }),
  };
}

// ── Variants ────────────────────────────────────────────────────
// A variant is a per-calc / per-ticker scratchpad row — the user tries 5–7
// permutations of NVDA-with-puts and each one becomes a card in the Variants
// strip beneath the calc body. Once they pick the best one, "Promote" turns
// that variant into a regular snapshot for the global Compare view.

const variantsKey = (calcKey: string, ticker: string) =>
  ["math_variants", calcKey, ticker.toUpperCase()] as const;

/** All variants for a given calc + ticker. */
export function useVariants(calcKey: string | null, ticker: string | null) {
  const qc = useQueryClient();
  const enabled = !!calcKey && !!ticker && ticker.trim().length > 0;

  const query = useQuery({
    queryKey: enabled ? variantsKey(calcKey!, ticker!) : ["math_variants", "disabled"],
    enabled,
    queryFn: async (): Promise<Snapshot[]> => {
      if (!calcKey || !ticker) return [];
      const { data, error } = await supabase
        .from("math_snapshots" as never)
        .select("id, calc_key, kind, name, purpose, payload, created_at")
        .eq("kind", "variant")
        .eq("calc_key", calcKey)
        // jsonb path filter — case-sensitive match on payload.underlying
        .eq("payload->>underlying", ticker.toUpperCase())
        .order("created_at", { ascending: false });
      if (error) throw error;
      return (data as DbRow[] | null)?.map(rowToSnap) ?? [];
    },
    staleTime: 15_000,
  });

  const createMut = useMutation({
    mutationFn: async (input: {
      calcKey: string;
      name?: string;
      payload: Record<string, unknown>;
    }): Promise<Snapshot> => {
      const { data: u } = await supabase.auth.getUser();
      if (!u.user) throw new Error("Not signed in");
      const insert = {
        user_id:  u.user.id,
        calc_key: input.calcKey,
        kind:     "variant",
        name:     (input.name && input.name.trim()) || "Variant",
        purpose:  null,
        payload:  input.payload,
      };
      const { data, error } = await supabase
        .from("math_snapshots" as never)
        .insert(insert)
        .select("id, calc_key, kind, name, purpose, payload, created_at")
        .single();
      if (error) throw error;
      return rowToSnap(data as DbRow);
    },
    onSuccess: (snap) => {
      const tk = (snap.payload as { underlying?: string }).underlying?.toUpperCase();
      if (tk) {
        qc.setQueryData<Snapshot[]>(variantsKey(snap.calcKey, tk), (prev) => [snap, ...(prev ?? [])]);
      }
    },
  });

  const removeMut = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from("math_snapshots" as never).delete().eq("id", id);
      if (error) throw error;
      return id;
    },
    onSuccess: (id) => {
      if (!enabled) return;
      qc.setQueryData<Snapshot[]>(variantsKey(calcKey!, ticker!), (prev) =>
        (prev ?? []).filter((s) => s.id !== id),
      );
    },
  });

  /** Promote a variant to a snapshot: delete any existing snapshot for this
   *  (calc, ticker), then flip the variant row's kind to 'snapshot'. The
   *  result shows up in the global Compare view. */
  const promoteMut = useMutation({
    mutationFn: async (variantId: string): Promise<Snapshot> => {
      // 1) Read the variant to know its calc_key + ticker.
      const { data: vData, error: vErr } = await supabase
        .from("math_snapshots" as never)
        .select("id, calc_key, kind, name, purpose, payload, created_at")
        .eq("id", variantId)
        .single();
      if (vErr) throw vErr;
      const variant = rowToSnap(vData as DbRow);
      const tk = (variant.payload as { underlying?: string }).underlying?.toUpperCase();

      // 2) Delete any existing snapshot for (calc, ticker) so the promotion
      //    leaves exactly one canonical row.
      if (tk) {
        await supabase
          .from("math_snapshots" as never)
          .delete()
          .eq("kind", "snapshot")
          .eq("calc_key", variant.calcKey)
          .eq("payload->>underlying", tk);
      }

      // 3) Flip the variant to snapshot.
      const { data: pData, error: pErr } = await supabase
        .from("math_snapshots" as never)
        .update({ kind: "snapshot" })
        .eq("id", variantId)
        .select("id, calc_key, kind, name, purpose, payload, created_at")
        .single();
      if (pErr) throw pErr;
      return rowToSnap(pData as DbRow);
    },
    onSuccess: (promoted) => {
      const tk = (promoted.payload as { underlying?: string }).underlying?.toUpperCase();
      if (tk) {
        // Remove from the variants list (it's no longer a variant).
        qc.setQueryData<Snapshot[]>(variantsKey(promoted.calcKey, tk), (prev) =>
          (prev ?? []).filter((s) => s.id !== promoted.id),
        );
      }
      // Bump the snapshots query so Compare sees the new snapshot.
      qc.invalidateQueries({ queryKey: SNAPS_KEY });
    },
  });

  return {
    variants: query.data ?? [],
    isLoading: query.isLoading,
    create:  (input: { calcKey: string; name?: string; payload: Record<string, unknown> }) =>
      createMut.mutateAsync(input),
    remove:  (id: string) => removeMut.mutate(id),
    promote: (variantId: string) => promoteMut.mutateAsync(variantId),
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
