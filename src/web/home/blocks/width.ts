// The page's content width (handoff 2026-11-24 §3, Current Web `nar3`): the width inside the page frame, not the
// window. Home's tables fit themselves to it: under 1320 px of content the main column shares its row with the
// Income rail, so All 11 sectors puts Weight under the sector's name, and Every name folds its Sector column away.
// One ResizeObserver on the page frame (.sw-page) serves every reader.
import { useSyncExternalStore } from 'react';

/** Under this content width Home's tables take their narrow layout. */
export const TABLES_WIDE = 1320;

let width = 0;
let frame: Element | null = null;
let ro: ResizeObserver | null = null;
const subs = new Set<() => void>();

const inner = (el: Element) => {
  const cs = getComputedStyle(el);
  return Math.round(el.clientWidth - (parseFloat(cs.paddingLeft) || 0) - (parseFloat(cs.paddingRight) || 0));
};

function attach() {
  if (typeof document === 'undefined') return;
  const el = document.querySelector('.sw-page');
  if (!el || el === frame) return;
  ro?.disconnect();
  frame = el;
  width = inner(el);
  if (typeof ResizeObserver === 'undefined') return;
  ro = new ResizeObserver((es) => {
    const w = Math.round(es[0]?.contentRect.width ?? inner(el));
    if (w !== width) { width = w; subs.forEach((f) => f()); }
  });
  ro.observe(el);
}

const subscribe = (cb: () => void) => {
  subs.add(cb);
  attach();
  return () => {
    subs.delete(cb);
    if (!subs.size) { ro?.disconnect(); ro = null; frame = null; }
  };
};
const snapshot = () => { if (!frame || !frame.isConnected) attach(); return width; };

/** The page's content width in px (0 before the page frame is on screen). */
export const useContentWidth = () => useSyncExternalStore(subscribe, snapshot, () => 0);

/** True when Home's tables have room for every column (1320 px of content or more, or not measured yet). */
export function useWideTables() {
  const w = useContentWidth();
  return w === 0 || w >= TABLES_WIDE;
}
