// The Positions page's controls, as Web Dark v2 draws them (handoff 2026-11-13-positions, README §4): the glass
// segmented control with a sliding thumb, the round switch, the fold that opens Sold in SD and Intelligence, the
// hover pop-up, the box. Colours are the README's dark tokens. No em dashes in any words here.
import { useEffect, useState, type CSSProperties, type ReactNode } from 'react';

export const G = '#65C466', R = '#FF6961', O = '#FF9F0A', K = '#F5F5F7', MU = '#98989D', MT = '#AEAEB2', QU = '#8E8E93', Y = '#FFD60A';
export const CEIL = '#86A8F0', FLOOR = '#C8946A', TEAL = '#4CC9D0', TEAL2 = '#8FDDE2', IVL = '#D4CEFF';
export const HAIR = '1px solid rgba(255,255,255,.08)', HAIR_S = '1px solid rgba(255,255,255,.14)';
/** Green from zero up, red below (no minus sign anywhere: colour says it). */
export const cl = (v: number) => (v >= 0 ? G : R);
export const kicker: CSSProperties = { fontSize: 12, lineHeight: '16px', fontWeight: 600, letterSpacing: '.05em', textTransform: 'uppercase', color: MU };
export const tnum: CSSProperties = { fontVariantNumeric: 'tabular-nums' };

/** The one glass recipe (README §4). */
export const GLASS: CSSProperties = {
  background: 'linear-gradient(160deg,rgba(255,255,255,.10) 0%,rgba(255,255,255,.03) 38%,rgba(255,255,255,.02) 62%,rgba(255,255,255,.07) 100%)',
  WebkitBackdropFilter: 'blur(14px) saturate(180%)', backdropFilter: 'blur(14px) saturate(180%)',
  boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.16),inset 1.5px 1.5px 0 -.5px rgba(255,255,255,.28),inset -1px -1px 0 -.5px rgba(255,255,255,.08),inset 0 18px 36px -24px rgba(255,255,255,.12),0 1px 3px rgba(0,0,0,.2),0 10px 24px -6px rgba(0,0,0,.4)',
};
/** The soft window Sold in SD and Intelligence open into. */
export const SOFT: CSSProperties = {
  background: 'linear-gradient(160deg,rgba(255,255,255,.07) 0%,rgba(255,255,255,.025) 55%,rgba(255,255,255,.05) 100%)',
  boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.08),inset 1px 1px 0 -.5px rgba(255,255,255,.16)',
};
const THUMB: CSSProperties = {
  background: 'linear-gradient(160deg,rgba(255,255,255,.30) 0%,rgba(255,255,255,.14) 50%,rgba(255,255,255,.22) 100%)',
  boxShadow: 'inset 0 0 0 .5px rgba(255,255,255,.35),inset 1px 1px 0 -.5px rgba(255,255,255,.5),0 2px 8px rgba(0,0,0,.35)',
};

/** Reduce Motion, read live. */
export function useReducedMotion() {
  const q = '(prefers-reduced-motion: reduce)';
  const [rm, setRm] = useState(() => typeof window !== 'undefined' && !!window.matchMedia?.(q).matches);
  useEffect(() => {
    const mq = window.matchMedia?.(q);
    if (!mq) return;
    const f = () => setRm(mq.matches);
    mq.addEventListener('change', f);
    return () => mq.removeEventListener('change', f);
  }, []);
  return rm;
}

/** The capsule segmented control: equal segments, a glass thumb that slides with a spring; selected 600, others 500. */
export function Segmented<T extends string | number>({ items, value, onPick, label, width, size = 14, wrapStyle }:
  { items: [T, string][]; value: T; onPick: (v: T) => void; label: string; width?: number | string; size?: number; wrapStyle?: CSSProperties }) {
  const rm = useReducedMotion();
  const i = Math.max(0, items.findIndex((x) => x[0] === value)), n = items.length;
  return (
    <div role="radiogroup" aria-label={label} style={{ position: 'relative', display: 'grid', gridTemplateColumns: `repeat(${n},minmax(0,1fr))`,
      width, padding: 2, borderRadius: 999, background: 'rgba(118,118,128,.24)', ...wrapStyle }}>
      <span aria-hidden="true" style={{ position: 'absolute', top: 2, bottom: 2, left: 2, width: `calc((100% - 4px) / ${n})`, borderRadius: 999,
        transform: `translateX(${i * 100}%)`, transition: rm ? 'none' : 'transform .45s cubic-bezier(.34,1.36,.64,1)', ...THUMB }} />
      {items.map(([k, l]) => (
        <button key={String(k)} type="button" role="radio" aria-checked={k === value} className="bare" onClick={() => onPick(k)}
          style={{ position: 'relative', textAlign: 'center', padding: '6px 4px', fontSize: size, lineHeight: '18px', fontWeight: k === value ? 600 : 500,
            color: k === value ? K : MT, whiteSpace: 'nowrap', borderRadius: 999 }}>{l}</button>
      ))}
    </div>
  );
}

/** The round switch: 40×24, on #65C466, the knob slides .2s. */
export function Switch({ on, label, onToggle }: { on: boolean; label: string; onToggle: () => void }) {
  return (
    <button type="button" role="switch" aria-checked={on} aria-label={label} className="switch" onClick={onToggle}><span /></button>
  );
}

/** Opens and closes the way the README §3.10 says: the height glides (grid rows 0fr to 1fr, .55s), the content fades
    in .12s later; closing .45s, opacity .2s. Reduce Motion: no motion at all. */
export function Fold({ open, children, pad }: { open: boolean; children: ReactNode; pad?: CSSProperties }) {
  const rm = useReducedMotion();
  const t = rm ? 'none' : open ? 'grid-template-rows .55s cubic-bezier(.22,1,.36,1), opacity .4s ease .12s, visibility 0s'
    : 'grid-template-rows .45s cubic-bezier(.4,0,.2,1), opacity .2s ease, visibility 0s linear .45s';
  return (
    <div style={{ display: 'grid', gridTemplateRows: open ? '1fr' : '0fr', opacity: open ? 1 : 0, visibility: open ? 'visible' : 'hidden', transition: t }}>
      <div style={{ minHeight: 0, overflow: 'hidden', display: 'flex', flexDirection: 'column', ...pad }}>{children}</div>
    </div>
  );
}
/** The capsule that folds away as its window opens (the reverse timing). */
export function FoldAway({ open, children }: { open: boolean; children: ReactNode }) {
  const rm = useReducedMotion();
  const t = rm ? 'none' : open ? 'grid-template-rows .4s cubic-bezier(.4,0,.2,1), opacity .15s ease, visibility 0s linear .4s'
    : 'grid-template-rows .4s cubic-bezier(.22,1,.36,1) .12s, opacity .3s ease .25s, visibility 0s';
  return (
    <div style={{ display: 'grid', gridTemplateRows: open ? '0fr' : '1fr', opacity: open ? 0 : 1, visibility: open ? 'hidden' : 'visible', transition: t }}>
      <div style={{ minHeight: 0, overflow: 'hidden', display: 'flex', flexDirection: 'column', padding: '2px 0 30px', marginBottom: -30 }}>{children}</div>
    </div>
  );
}

/** The chevron that turns 180° when its sheet is open (.3s). */
export function Chevron({ open }: { open: boolean }) {
  return (
    <svg width="14" height="14" viewBox="0 0 20 20" fill="none" stroke={MT} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"
      style={{ flex: 'none', transform: open ? 'rotate(180deg)' : 'none', transition: 'transform .3s cubic-bezier(.22,1,.36,1)' }}><path d="M5 8l5 5 5-5" /></svg>
  );
}

/** A pop-up's contents: a dot, a title, the value, rows of exact numbers, a short line. */
export interface Pop { t: string; v: string; dc: string; rows: { l: string; v: string; c?: string }[]; say: string }
/** A hover (or keyboard focus) target on a lane at x (0 to 1 of the track) with its pop-up above it. The pop-up keeps
    inside the lane: from the left edge near the left, from the right edge near the right. */
export function Hover({ id, x, w = 22, top = 0, bottom = 0, pop, on, set, aria }:
  { id: string; x: number; w?: number | string; top?: number; bottom?: number; pop: Pop; on: boolean; set: (id: string | null) => void; aria: string }) {
  const tx = x < 0.2 ? 'translateX(-24px)' : x > 0.8 ? 'translateX(calc(-100% + 24px))' : 'translateX(-50%)';
  return (
    <span tabIndex={0} role="button" aria-label={aria} onMouseEnter={() => set(id)} onMouseLeave={() => set(null)} onFocus={() => set(id)} onBlur={() => set(null)}
      className="swp-hv" style={{ position: 'absolute', top, bottom, left: `${(x * 100).toFixed(2)}%`, width: w, marginLeft: typeof w === 'number' ? -w / 2 : undefined, zIndex: on ? 6 : 3, cursor: 'default', outline: 'none' }}>
      {on && (
        <span role="tooltip" style={{ position: 'absolute', bottom: 'calc(100% + 6px)', left: '50%', transform: tx, width: 252, padding: '12px 14px', borderRadius: 14,
          background: 'rgba(28,28,30,.97)', boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.12),0 12px 32px rgba(0,0,0,.55)', display: 'flex', flexDirection: 'column', gap: 8,
          pointerEvents: 'none', textAlign: 'left', whiteSpace: 'normal' }}>
          <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={{ flex: 'none', width: 8, height: 8, borderRadius: '50%', background: pop.dc }} />
            <span style={{ fontSize: 13, lineHeight: '18px', color: MT }}>{pop.t}</span>
            <span style={{ marginLeft: 'auto', fontSize: 17, lineHeight: '22px', fontWeight: 600, color: K, ...tnum }}>{pop.v}</span>
          </span>
          {pop.rows.length > 0 && (
            <span style={{ display: 'flex', flexDirection: 'column', gap: 4, paddingTop: 8, borderTop: '1px solid rgba(255,255,255,.10)' }}>
              {pop.rows.map((r, i) => (
                <span key={i} style={{ display: 'flex', justifyContent: 'space-between', gap: 12, fontSize: 13, lineHeight: '18px' }}>
                  <span style={{ color: MU }}>{r.l}</span><span style={{ fontWeight: 500, color: r.c ?? K, whiteSpace: 'nowrap', ...tnum }}>{r.v}</span>
                </span>
              ))}
            </span>
          )}
          {pop.say && <span style={{ fontSize: 13, lineHeight: '18px', color: '#C7C7CC', textWrap: 'pretty' }}>{pop.say}</span>}
        </span>
      )}
    </span>
  );
}

/** One outlined box beside a lane: a label (with a dot or an icon), one number, a short line. */
export interface BoxQ { k: string; l: string; v: string; s?: string; vc?: string; sc?: string; dot?: string; icon?: ReactNode; aria?: string; span?: boolean }
export function Box({ q }: { q: BoxQ }) {
  return (
    <div role="group" aria-label={q.aria ?? `${q.l}, ${q.v}${q.s ? ', ' + q.s : ''}`} style={{ gridColumn: q.span ? '1 / -1' : 'auto', minWidth: 0, padding: '10px 10px 10px 11px', borderRadius: 12,
      boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.14)', display: 'flex', flexDirection: 'column', gap: 2 }}>
      <span style={{ display: 'flex', alignItems: 'center', gap: 5, minWidth: 0 }}>
        {q.icon}
        {q.dot && <span style={{ flex: 'none', width: 6, height: 6, borderRadius: '50%', background: q.dot }} />}
        <span style={{ fontSize: 12, lineHeight: '16px', color: MU, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{q.l}</span>
      </span>
      <span style={{ fontSize: 17, lineHeight: '22px', fontWeight: 600, color: q.vc ?? K, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', ...tnum }}>{q.v}</span>
      <span style={{ fontSize: 12, lineHeight: '16px', color: q.sc ?? QU, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', ...tnum }}>{q.s || '\u00a0'}</span>
    </div>
  );
}

/** The walls' icons (README §3.9.5): ceiling ⇥, floor ⇤, accelerator «, flip ◐. */
export function WallIcon({ kind, size, color }: { kind: 'ceiling' | 'floor' | 'accelerator' | 'flip'; size: number; color: string }) {
  if (kind === 'flip') return (
    <svg width={size} height={size} viewBox="0 0 20 20" fill="none" stroke={color} strokeWidth="2" aria-hidden="true" style={{ flex: 'none' }}>
      <circle cx="10" cy="10" r="7" /><path d="M10 3a7 7 0 0 0 0 14z" fill={color} stroke="none" /></svg>
  );
  return (
    <svg width={size} height={size} viewBox="0 0 20 20" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" style={{ flex: 'none' }}>
      {kind === 'ceiling' && <><path d="M2.5 10h9.5M8.5 6l4 4-4 4" /><path d="M16.5 3v14" strokeWidth="2.6" /></>}
      {kind === 'floor' && <><path d="M17.5 10H8M11.5 6l-4 4 4 4" /><path d="M3.5 3v14" strokeWidth="2.6" /></>}
      {kind === 'accelerator' && <path d="M9.5 5l-5 5 5 5M16 5l-5 5 5 5" />}
    </svg>
  );
}

/** The page's styles the inline ones cannot say: hovers, the focus ring over the outline, hidden scrollbars, the
    read's fade-in. */
export function PosStyles() {
  return (
    <style>{`.sw .swp-row:hover{background:rgba(255,255,255,.03)}
.sw .swp-cell:hover{filter:brightness(1.25)}
.sw .swp-add:hover{background:#FFFFFF!important}
.sw .swp-hv:focus-visible{outline:2px solid #86A8F0;outline-offset:2px;border-radius:6px}
.sw .swp-scroll{scrollbar-width:none}.sw .swp-scroll::-webkit-scrollbar{display:none}
@keyframes swpFade{from{opacity:0;transform:translateY(3px)}to{opacity:1;transform:none}}
.sw .swp-fade{animation:swpFade .4s cubic-bezier(.22,1,.36,1) both}`}</style>
  );
}
