// The Positions rail's pieces (README 1b, the design's aside): the view switch, a Rails card, a tile and its hover
// readout. Every value is the design's own; the numbers come from rail/model.ts.
import { useLayoutEffect, useRef, useState, type CSSProperties, type KeyboardEvent } from 'react';
import { createPortal } from 'react-dom';
import PayoffMini from '../../components/PayoffMini';
import { C, count, level, money, pct, price } from '../../lib/format';
import type { RailView } from '../../lib/state';
import type { RailName } from './model';

const MU = '#98989D';
const dotColor = (st: number) => (st >= 2 ? C.red : st === 1 ? C.orange : 'transparent');
const readInk = (c: RailName['readColor']) => (c === 'red' ? C.red : c === 'orange' ? C.orange : C.ink);
const upDown = (x: number) => (x >= 0 ? C.green : C.red);

/* Hover rules the inline styles cannot carry (the design's style-hover). */
export const RAIL_CSS = '.sw .sw-rail-see:hover{color:#F5F5F7!important}.sw .sw-rail-tile:hover{background:#2C2C2E!important}';

/* ── The view switch: a glass segmented control, two icon segments, a thumb that springs between them ── */
export function ViewSwitch({ view, set }: { view: RailView; set: (v: RailView) => void }) {
  const tiles = view === 'tiles';
  const refs = useRef<(HTMLButtonElement | null)[]>([]);
  const key = (e: KeyboardEvent) => {
    if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(e.key)) return;
    e.preventDefault();
    const next: RailView = tiles ? 'rails' : 'tiles';
    set(next);
    refs.current[next === 'tiles' ? 1 : 0]?.focus();
  };
  const seg = (on: boolean): CSSProperties => ({ position: 'relative', height: 26, display: 'flex', alignItems: 'center', justifyContent: 'center', color: on ? '#F5F5F7' : MU });
  return (
    <div role="radiogroup" aria-label="Positions view" onKeyDown={key}
      style={{ position: 'relative', display: 'grid', gridTemplateColumns: 'repeat(2,36px)', padding: 2, borderRadius: 999, background: 'rgba(118,118,128,.24)' }}>
      <span aria-hidden="true" style={{ position: 'absolute', top: 2, left: 2, width: 36, height: 26, borderRadius: 999, background: 'rgba(255,255,255,.20)',
        boxShadow: 'inset 0 0 0 .5px rgba(255,255,255,.22),inset 0 1px 0 rgba(255,255,255,.3),0 2px 8px rgba(0,0,0,.35)',
        transform: `translateX(${tiles ? 36 : 0}px)`, transition: 'transform .42s cubic-bezier(.34,1.36,.64,1)' }} />
      <button ref={(el) => { refs.current[0] = el; }} type="button" role="radio" aria-checked={!tiles} aria-label="Rail" title="Rail" tabIndex={tiles ? -1 : 0}
        className="bare" onClick={() => set('rails')} style={seg(!tiles)}>
        <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true" style={{ fill: 'currentColor' }}>
          <rect x="1" y="1.5" width="12" height="4.6" rx="1.6" /><rect x="1" y="7.9" width="12" height="4.6" rx="1.6" />
        </svg>
      </button>
      <button ref={(el) => { refs.current[1] = el; }} type="button" role="radio" aria-checked={tiles} aria-label="Tiles" title="Tiles" tabIndex={tiles ? 0 : -1}
        className="bare" onClick={() => set('tiles')} style={seg(tiles)}>
        <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true" style={{ fill: 'currentColor' }}>
          <rect x="1" y="1" width="5.2" height="5.2" rx="1.5" /><rect x="7.8" y="1" width="5.2" height="5.2" rx="1.5" />
          <rect x="1" y="7.8" width="5.2" height="5.2" rx="1.5" /><rect x="7.8" y="7.8" width="5.2" height="5.2" rx="1.5" />
        </svg>
      </button>
    </div>
  );
}

/* ── Rails: one card per name ── */
const num = (l: string, v: string, c: string, sub?: string, end = false) => (
  <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0, alignItems: end ? 'flex-end' : undefined }}>
    <span style={{ fontSize: 10, color: MU }}>{l}</span>
    <span style={{ fontSize: 13, fontWeight: 600, color: c, whiteSpace: l === 'Delta' ? 'nowrap' : undefined }}>{v}</span>
    {sub != null && <span style={{ fontSize: 10, color: MU }}>{sub}</span>}
  </span>
);

export function RailCard({ n, mask, go }: { n: RailName; mask: (s: string) => string; go: () => void }) {
  const kp = n.kept ? Math.round(n.kept.pct) : 0;
  return (
    <button type="button" className="bare soft-rail" onClick={go} aria-label={n.t + (n.read ? ', ' + n.read : '')}
      style={{ display: 'flex', flexDirection: 'column', gap: 12, padding: '16px 16px 14px', borderRadius: 20 }}>
      <span style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <span style={{ flex: 'none', position: 'relative', width: 34, height: 34, borderRadius: '50%', background: 'rgba(255,255,255,.09)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 9, fontWeight: 700 }}>
          {n.t}
          {n.st > 0 && <span style={{ position: 'absolute', right: -2, top: -2, width: 10, height: 10, borderRadius: '50%', background: dotColor(n.st), boxShadow: '0 0 0 2px #0B0D0C' }} />}
        </span>
        <span style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
          <span style={{ fontSize: 16, fontWeight: 600 }}>{n.t}</span>
          <span style={{ fontSize: 12, color: MU, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{n.sub}</span>
        </span>
        <span style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end' }}>
          <span style={{ fontSize: 15, fontWeight: 500 }}>{price(n.px)}</span>
          <span style={{ fontSize: 12, fontWeight: 600, color: upDown(n.mv) }}>{(n.mv >= 0 ? '▲ ' : '▼ ') + pct(n.mv)}</span>
        </span>
      </span>
      {n.read && <span style={{ fontSize: 13, lineHeight: '18px', fontWeight: 600, color: readInk(n.readColor) }}>{n.read}</span>}
      <span style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        <PayoffMini values={n.pay} height={46} stroke={1.75} />
        <span style={{ display: 'flex', justifyContent: 'space-between', fontSize: 10, color: MU }}>
          <span>↓10%</span><span>P&amp;L by Friday · today</span><span>↑10%</span>
        </span>
      </span>
      <span style={{ display: 'grid', fontVariantNumeric: 'tabular-nums', gridTemplateColumns: 'repeat(4,minmax(0,1fr))', gap: 8, paddingTop: 10, borderTop: '1px solid rgba(255,255,255,.08)' }}>
        {num('Delta', (n.delta < 0 ? 'Short ' : 'Long ') + count(n.delta), n.delta < 0 ? C.red : C.ink)}
        {num('Theta a day', mask(money(n.theta)), upDown(n.theta))}
        {n.kept ? num('Calls kept', Math.abs(kp) + '%', kp < 0 ? C.red : C.ink, mask(money(n.kept.left)) + ' left') : num('Calls kept', 'None', C.ink, 'to sell')}
        {num('So far', mask(money(n.soFar)), upDown(n.soFar), undefined, true)}
      </span>
      <span style={{ display: 'flex', justifyContent: 'space-between', gap: 8, fontSize: 12 }}>
        <span style={{ color: MU }}>{n.next}</span>
        {n.todo && <span style={{ fontWeight: 600, color: C.orange }}>{n.todo}</span>}
        <span style={{ color: MU }}>Open ›</span>
      </span>
    </button>
  );
}

/* ── Tiles: price card small with the payoff, and a G2 readout of the read on hover (Nik, D3) ── */
export interface TipAt { n: RailName; x: number; top: number; bottom: number }

export function RailTile({ n, go, tip }: { n: RailName; go: () => void; tip: (t: TipAt | null) => void }) {
  const show = (el: HTMLElement) => { const r = el.getBoundingClientRect(); tip({ n, x: r.left + r.width / 2, top: r.top, bottom: r.bottom }); };
  const c = upDown(n.mv);
  return (
    <button type="button" className="bare sw-rail-tile" onClick={go} aria-label={n.t + (n.read ? ' · ' + n.read : '')}
      onMouseEnter={(e) => show(e.currentTarget)} onMouseLeave={() => tip(null)} onFocus={(e) => show(e.currentTarget)} onBlur={() => tip(null)}
      style={{ height: 130, minWidth: 0, display: 'flex', flexDirection: 'column', padding: 12, borderRadius: 20, background: '#1D1D1F', transition: 'background .2s' }}>
      <span style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 6 }}>
        <span style={{ fontSize: 15, lineHeight: '18px', fontWeight: 500, color: '#FFFFFF' }}>{n.t}</span>
        {n.st > 0 && <span style={{ flex: 'none', width: 8, height: 8, borderRadius: '50%', background: dotColor(n.st) }} />}
      </span>
      <span style={{ marginTop: 6, fontSize: 15, lineHeight: '18px', fontWeight: 700, color: c }}>{level(n.px, 2)}</span>
      <span style={{ marginTop: 2, fontSize: 15, lineHeight: '18px', fontWeight: 700, color: c }}>{pct(n.mv)}</span>
      <span style={{ marginTop: 'auto', display: 'block' }}>
        <PayoffMini values={n.pay} height={34} stroke={1.5} />
      </span>
    </button>
  );
}

/** The hover readout: the design's tooltip glass (G2, radius 12, padding 8 12): the company, then the read. Drawn
    fixed on the page so the rail's own scroll box never clips it; it sits above the tile, below it near the header. */
export function TileTip({ at }: { at: TipAt | null }) {
  const ref = useRef<HTMLSpanElement>(null);
  const [host, setHost] = useState<Element | null>(null);
  useLayoutEffect(() => { setHost(document.querySelector('.sw') ?? document.body); }, []);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el || !at) return;
    const w = el.offsetWidth, h = el.offsetHeight, vw = document.documentElement.clientWidth;
    const below = at.top - h - 8 < 72;
    el.style.left = Math.max(8, Math.min(vw - w - 8, at.x - w / 2)) + 'px';
    el.style.top = (below ? at.bottom + 8 : at.top - h - 8) + 'px';
    el.style.opacity = '1';
  }, [at]);
  if (!host || !at || !at.n.read) return null;
  return createPortal(
    <span ref={ref} role="tooltip" className="g2"
      style={{ position: 'fixed', left: 0, top: 0, zIndex: 20, opacity: 0, pointerEvents: 'none', borderRadius: 12, padding: '8px 12px',
        display: 'flex', flexDirection: 'column', gap: 1, whiteSpace: 'nowrap', fontFamily: "'Inter', system-ui, -apple-system, sans-serif", color: C.ink }}>
      <span style={{ fontSize: 12, color: MU }}>{at.n.t} · {at.n.company}</span>
      <span style={{ fontSize: 15, fontWeight: 600, color: readInk(at.n.readColor) }}>{at.n.read}</span>
    </span>,
    host,
  );
}
