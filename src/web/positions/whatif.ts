// The What if, per book and name (README State: "What if per name: legs switched off, trades added"). It survives
// switching names, and leaving the page, for the session (sessionStorage when the browser allows it). Nothing here
// is ever sent anywhere.
//
// 13 Nov 2026 (Nik: "by default only keep income on and rest off", for every name): Every leg starts with the legs
// sold on and the shares and legs bought off. The store keeps `flip`, the legs switched away from that start; the
// page works out what is on. Only a flip counts as a What if change (Nik picked "Only what I flip").
import { useCallback, useMemo, useSyncExternalStore } from 'react';
import type { Trade } from './model';

/** The Try a trade form, per name (the design keeps it per name too). Unset fields take the name's defaults. */
export interface Draft { side?: 's' | 'b'; ty?: 'c' | 'p'; K?: number; ex?: string; n?: number }
export interface NameWhatIf { flip: string[]; trades: Trade[]; draft: Draft }

const KEY = 'sw-whatif2';
const EMPTY: NameWhatIf = { flip: [], trades: [], draft: {} };
const store = new Map<string, NameWhatIf>();
const subs = new Set<() => void>();

try {
  const raw = sessionStorage.getItem(KEY);
  if (raw) for (const [k, v] of Object.entries(JSON.parse(raw) as Record<string, NameWhatIf>)) store.set(k, { ...EMPTY, ...v });
} catch { /* a private window: this session only */ }

const save = () => { try { sessionStorage.setItem(KEY, JSON.stringify(Object.fromEntries(store))); } catch { /* ignore */ } };
const set = (k: string, f: (w: NameWhatIf) => NameWhatIf) => {
  store.set(k, f(store.get(k) ?? EMPTY));
  save();
  subs.forEach((s) => s());
};
const subscribe = (f: () => void) => { subs.add(f); return () => { subs.delete(f); }; };

export function useWhatIf(book: string | null | undefined, t: string | null | undefined) {
  const k = `${book ?? ''}|${t ?? ''}`;
  const w = useSyncExternalStore(subscribe, () => store.get(k) ?? EMPTY);
  const toggleLeg = useCallback((leg: string) => set(k, (x) => ({ ...x, flip: x.flip.includes(leg) ? x.flip.filter((y) => y !== leg) : [...x.flip, leg] })), [k]);
  const add = useCallback((u: Omit<Trade, 'id' | 'on'>) => set(k, (x) => ({ ...x, trades: [...x.trades, { ...u, id: Date.now(), on: true }] })), [k]);
  /** Several at once (the SD card's Try in What if, 11 Nov 2026): a new id each. */
  const addMany = useCallback((us: Omit<Trade, 'id' | 'on'>[]) => set(k, (x) => {
    const t0 = Math.max(Date.now(), ...x.trades.map((u) => u.id + 1));
    return { ...x, trades: [...x.trades, ...us.map((u, i) => ({ ...u, id: t0 + i, on: true }))] };
  }), [k]);
  /** The SD calculator's sale (handoff 2026-11-11-sd-whatif-totals 1.10): one at a time per name. Takes off every SD
      row, then (unless null) adds the new ones, marked src 'sd'. */
  const setSd = useCallback((us: Omit<Trade, 'id' | 'on'>[] | null) => set(k, (x) => {
    const keep = x.trades.filter((u) => u.src !== 'sd');
    if (!us?.length) return { ...x, trades: keep };
    const t0 = Math.max(Date.now(), ...x.trades.map((u) => u.id + 1));
    return { ...x, trades: [...keep, ...us.map((u, i) => ({ ...u, src: 'sd' as const, id: t0 + i, on: true }))] };
  }), [k]);
  const toggleTrade = useCallback((id: number) => set(k, (x) => ({ ...x, trades: x.trades.map((u) => (u.id === id ? { ...u, on: !u.on } : u)) })), [k]);
  const remove = useCallback((id: number) => set(k, (x) => ({ ...x, trades: x.trades.filter((u) => u.id !== id) })), [k]);
  const setDraft = useCallback((d: Draft) => set(k, (x) => ({ ...x, draft: { ...x.draft, ...d } })), [k]);
  /** Back to the book: the legs as they start (Income on), every trade gone (the design's reset keeps the form). */
  const reset = useCallback(() => set(k, (x) => ({ ...x, flip: [], trades: [] })), [k]);
  return useMemo(() => ({ ...w, toggleLeg, add, addMany, setSd, toggleTrade, remove, setDraft, reset }), [w, toggleLeg, add, addMany, setSd, toggleTrade, remove, setDraft, reset]);
}
