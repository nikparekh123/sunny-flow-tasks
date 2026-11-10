// To do in the web header (handoff 2026-11-10-todo, "Web · header" and "Web · the popover"): "7 to do" left of the
// privacy eye, quiet on purpose (#636366, under 4.5:1 by design, do not "fix" it), "To do" alone when nothing is
// open. It opens a menu-glass popover with the list. Nik's list is his alone (shared by his two logins); the cousin
// gets a private list of his own, without "Shared by both accounts" (10 Nov 2026).
//
// The popover is drawn into the page frame (.sw) through a portal, outside the header, so its blur reaches the page.
// The design's header is 48 tall with a 32 gap; the built one is 64 with 36, so the spec's relations are kept on it:
// the popover sits 8 under the header (top 72), its bottom 24 above the window (max-height 100% - 96), and the
// button 20 from the eye (margin-right -16).
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type RefObject } from 'react';
import { createPortal } from 'react-dom';
import { useNY } from '../lib/clock';
import { useHome } from '../lib/data';
import { useWeb } from '../lib/state';
import { TodoList } from './TodoList';
import { useTodoAccess, useTodos } from './useTodos';

const HEADER_H = 64;

type Api = ReturnType<typeof useTodos>;

function Popover({ api, n, shared, btn, kbd, onClose }: { api: Api; n: number; shared: boolean; btn: RefObject<HTMLButtonElement>; kbd: boolean; onClose: (focusButton: boolean) => void }) {
  const box = useRef<HTMLDivElement>(null);
  const esc = useRef<(() => boolean) | null>(null);
  const today = useNY(60_000).date;
  const { book } = useWeb();
  const home = useHome(book).data?.payload;
  // A5: bold only the book's names and its watchlist.
  const known = useMemo(() => new Set<string>([
    ...((home?.brief?.names ?? []) as { t?: string }[]).map((x) => x.t ?? ''),
    ...((home?.watchlist ?? []) as { ticker?: string }[]).map((x) => x.ticker ?? ''),
  ].filter(Boolean)), [home]);

  // Read the list again each time it opens (the phone may have changed it).
  const { refetch } = api;
  useEffect(() => { void refetch(); }, [refetch]);

  useEffect(() => {
    // Escape closes an open date picker first, then the popover.
    const key = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      e.stopPropagation();
      if (esc.current?.()) return;
      onClose(true);
    };
    // A click outside closes it: below the header the clear layer takes the click; in the header it goes on through.
    const down = (e: MouseEvent) => {
      const t = e.target as Element | null;
      if (!t || box.current?.contains(t) || btn.current?.contains(t) || t.closest?.('[data-todo-scrim]')) return;
      onClose(false);
    };
    window.addEventListener('keydown', key, true);
    document.addEventListener('mousedown', down, true);
    return () => { window.removeEventListener('keydown', key, true); document.removeEventListener('mousedown', down, true); };
  }, [onClose, btn]);

  return (
    <>
      <button type="button" className="bare" data-todo-scrim="" aria-label="Close To do" onClick={() => onClose(false)}
        style={{ position: 'fixed', inset: `${HEADER_H}px 0 0 0`, zIndex: 28, cursor: 'default' }} />
      <div ref={box} role="dialog" aria-label="To do" className="g2 noscroll"
        style={{ position: 'fixed', top: HEADER_H + 8, right: 'max(48px, calc((100% - 1440px) / 2 + 48px))', zIndex: 29, width: 400, maxWidth: 'calc(100% - 32px)',
          maxHeight: `calc(100% - ${HEADER_H + 32}px)`, overflowY: 'auto', overscrollBehavior: 'contain', padding: '16px 18px 12px', borderRadius: 16,
          display: 'flex', flexDirection: 'column', gap: 12 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 8 }}>
          <span style={{ fontSize: 17, lineHeight: '22px', fontWeight: 600 }}>To do</span>
          <span style={{ fontSize: 12, lineHeight: '16px', color: '#98989D' }}>{shared ? 'Shared by both accounts · ' : ''}{n ? n + ' open' : 'Nothing open'}</span>
        </div>
        <TodoList items={api.items ?? []} today={today} known={known} add={api.add} set={api.set} note={api.note} remove={api.remove} escRef={esc} focusAdd={kbd} />
      </div>
    </>
  );
}

/** The header's "N to do" and its popover, for any book member (each sees only their own list). */
export function TodoButton() {
  const { on: owner, shared } = useTodoAccess();
  const api = useTodos(owner);
  const [open, setOpen] = useState(false);
  // Opened from the keyboard (Enter or Space: a click with no pointer): the caret goes to the add field.
  const [kbd, setKbd] = useState(false);
  const btn = useRef<HTMLButtonElement>(null);
  const [host, setHost] = useState<Element | null>(null);
  const show = owner && api.ready;
  useLayoutEffect(() => { if (show) setHost(btn.current?.closest('.sw') ?? null); }, [show]);
  useEffect(() => { if (!show) setOpen(false); }, [show]);
  const close = useCallback((focusButton: boolean) => { setOpen(false); if (focusButton) btn.current?.focus(); }, []);
  if (!show) return null;
  const n = api.open ?? 0;
  return (
    <>
      <button ref={btn} type="button" className="bare sw-todo" onClick={(e) => { setKbd(e.detail === 0); setOpen((o) => !o); }} aria-haspopup="dialog" aria-expanded={open}
        aria-label={n ? `To do, ${n} open` : 'To do, nothing open'}
        style={{ flex: 'none', marginRight: -16, padding: '8px 0', fontSize: 13, lineHeight: '16px', fontWeight: 400, color: open ? '#F5F5F7' : '#636366',
          whiteSpace: 'nowrap', fontVariantNumeric: 'tabular-nums', transition: 'color .2s' }}>
        {n ? <><span style={{ fontWeight: 600 }}>{n}</span> to do</> : 'To do'}
      </button>
      {open && host && createPortal(<Popover api={api} n={n} shared={shared} btn={btn} kbd={kbd} onClose={close} />, host)}
      <style>{`.sw .sw-todo:hover{color:#F5F5F7!important}.sw .td-mo:hover{background:rgba(118,118,128,.16)}`
        + `.sw .td-in{all:unset;box-sizing:border-box;font-family:inherit}.sw input.td-in:focus-visible{outline:none}`}</style>
    </>
  );
}
