// The What if, per book and name (README State: "What if per name: legs switched off, trades added"). It survives
// switching names, and leaving the page, for the session (sessionStorage when the browser allows it). Nothing here
// is ever sent anywhere.
//
// 24 Nov 2026 (Nik: "keep all of them on"): every leg starts on. The store keeps `flip`, the legs switched off; the
// page works out what is on. Only a flip counts as a What if change (Nik picked "Only what I flip").
//
// 24 Nov 2026 (handoff 2026-11-24 §4, Every leg is SunnyBook): Every leg's chips are kept here too (`cf`, the chips
// switched off: "ex:2026-11-27", "kind:C", "role:income"). Each chip is its own switch and changes only itself; a leg
// counts when its own switch and each of its chips are on. Back to the book clears the chips with the rest.
import { useCallback, useMemo, useSyncExternalStore } from 'react';
import type { Trade } from './model';

/** The Try a trade form, per name (the design keeps it per name too). Unset fields take the name's defaults. */
export interface Draft { side?: 's' | 'b'; ty?: 'c' | 'p'; K?: number; ex?: string; n?: number }
export interface NameWhatIf { flip: string[]; trades: Trade[]; draft: Draft; cf: string[] }

const KEY = 'sw-whatif3';
const EMPTY: NameWhatIf = { flip: [], trades: [], draft: {}, cf: [] };
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
  /** Back to the book: the legs as they start (every leg on), every trade gone, every chip on (the design's reset keeps
      the form). */
  const reset = useCallback(() => set(k, (x) => ({ ...x, flip: [], trades: [], cf: [] })), [k]);
  /** Several legs' own switches at once (a group's switch, Switch on all): `flip` says, per leg, whether it should sit
      flipped from where it starts; `on` sets the What if trades in `ids`. */
  const setMany = useCallback((flips: { k: string; flip: boolean }[], ids: number[], on: boolean) => set(k, (x) => {
    const f = new Set(x.flip);
    for (const e of flips) { if (e.flip) f.add(e.k); else f.delete(e.k); }
    return { ...x, flip: [...f], trades: x.trades.map((u) => (ids.includes(u.id) ? { ...u, on } : u)) };
  }), [k]);
  /** One chip on or off; `all` replaces every chip (Switch off all, Reset). */
  const toggleChip = useCallback((id: string) => set(k, (x) => ({ ...x, cf: (x.cf ?? []).includes(id) ? x.cf.filter((y) => y !== id) : [...(x.cf ?? []), id] })), [k]);
  const setChips = useCallback((all: string[]) => set(k, (x) => ({ ...x, cf: all })), [k]);
  return useMemo(() => ({ ...w, cf: w.cf ?? [], toggleLeg, add, addMany, setSd, toggleTrade, remove, setDraft, reset, setMany, toggleChip, setChips }),
    [w, toggleLeg, add, addMany, setSd, toggleTrade, remove, setDraft, reset, setMany, toggleChip, setChips]);
}
