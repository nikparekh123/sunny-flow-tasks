/**
 * Math — snapshot store (localStorage).
 *
 * Snapshots are the unit of save/history/compare/share. For now each snapshot
 * carries metadata only (name, calc key, timestamp) — the payload field is a
 * loose record that real calculators will populate when they wire up.
 */
import { useEffect, useState } from "react";

const LS_KEY = "sunnyfi.math.snapshots.v1";

export interface Snapshot {
  id: string;
  calcKey: string;       // matches CalcMeta.key
  name: string;          // user-facing name (or "untitled snapshot")
  purpose?: string;
  createdAt: number;     // epoch ms
  /** Calc-specific inputs/result. Empty until a real calc is wired in. */
  payload: Record<string, unknown>;
}

function safeRead(): Snapshot[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(LS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed as Snapshot[];
  } catch {
    return [];
  }
}

function safeWrite(snaps: Snapshot[]): void {
  if (typeof window === "undefined") return;
  try { window.localStorage.setItem(LS_KEY, JSON.stringify(snaps)); } catch { /* private mode */ }
}

function uid(): string {
  return Math.random().toString(36).slice(2, 10) + Date.now().toString(36).slice(-4);
}

export function useSnapshots() {
  const [snaps, setSnaps] = useState<Snapshot[]>(() => safeRead());

  // Cross-tab sync — a save in another tab should reflect here.
  useEffect(() => {
    const onStorage = (e: StorageEvent) => {
      if (e.key === LS_KEY) setSnaps(safeRead());
    };
    window.addEventListener("storage", onStorage);
    return () => window.removeEventListener("storage", onStorage);
  }, []);

  const create = (input: { calcKey: string; name?: string; purpose?: string; payload?: Record<string, unknown> }): Snapshot => {
    const snap: Snapshot = {
      id: uid(),
      calcKey: input.calcKey,
      name: (input.name && input.name.trim()) || "Untitled snapshot",
      purpose: input.purpose,
      createdAt: Date.now(),
      payload: input.payload ?? {},
    };
    const next = [snap, ...snaps];
    safeWrite(next);
    setSnaps(next);
    return snap;
  };

  const remove = (id: string) => {
    const next = snaps.filter((s) => s.id !== id);
    safeWrite(next);
    setSnaps(next);
  };

  const rename = (id: string, name: string) => {
    const next = snaps.map((s) => (s.id === id ? { ...s, name } : s));
    safeWrite(next);
    setSnaps(next);
  };

  return { snaps, create, remove, rename };
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
