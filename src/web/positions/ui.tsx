// The Positions page's controls, each exactly as the design draws it (Web Dark v2.dc.html, after its dark pass):
// a capsule segmented control with a glass selected segment, the round switch, the outlined layer chip.
import type { CSSProperties, ReactNode } from 'react';

export const G = '#65C466', R = '#FF6961', O = '#FF9F0A', K = '#F5F5F7', MU = '#98989D';
export const HAIR = '1px solid rgba(255,255,255,.08)', HAIR_S = '1px solid rgba(255,255,255,.14)';
/** The design's cl(): green from zero up, red below. */
export const cl = (v: number) => (v >= 0 ? G : R);
/** The glass selected segment (README segment-on). */
const SG = 'inset 0 0 0 .5px rgba(255,255,255,.22),inset 0 1px 0 rgba(255,255,255,.3),0 2px 8px rgba(0,0,0,.35)';
const segOn = (on: boolean): CSSProperties => ({
  fontWeight: on ? 600 : 500, color: on ? '#FFFFFF' : K, background: on ? 'rgba(255,255,255,.20)' : 'transparent', boxShadow: on ? SG : 'none',
});
export const kicker: CSSProperties = { fontSize: 12, fontWeight: 600, letterSpacing: '.05em', textTransform: 'uppercase', color: MU };

/** A capsule track of segments (Sell | Buy, Call | Put, All | Sold | Long). */
export function Seg<T extends string>({ items, value, onPick, label }: { items: [T, string][]; value: T; onPick: (v: T) => void; label: string }) {
  return (
    <div role="radiogroup" aria-label={label} style={{ display: 'flex', gap: 2, padding: 2, borderRadius: 999, background: 'rgba(118,118,128,.24)' }}>
      {items.map(([k, l]) => (
        <button key={k} type="button" role="radio" aria-checked={k === value} className="bare" onClick={() => onPick(k)}
          style={{ padding: '6px 14px', borderRadius: 999, fontSize: 14, lineHeight: '18px', whiteSpace: 'nowrap',
            transition: 'background .25s cubic-bezier(.22,1,.36,1)', ...segOn(k === value) }}>{l}</button>
      ))}
    </div>
  );
}

/** The By date control's segment (13px, radius 14, padding 7 0) with the dot on an expiry the name holds. */
export function DateSeg({ on, label, held, onPick }: { on: boolean; label: string; held: boolean; onPick: () => void }) {
  return (
    <button type="button" role="radio" aria-checked={on} className="bare" onClick={onPick}
      style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 5, padding: '7px 0', borderRadius: 14, fontSize: 13,
        whiteSpace: 'nowrap', transition: 'background .25s', ...segOn(on) }}>
      {label}
      {held && <span style={{ width: 5, height: 5, borderRadius: '50%', background: on ? '#FFFFFF' : K }} />}
    </button>
  );
}

/** The outlined layer chip (Walls, Technicals): one at a time. */
export function Chip({ on, children, onPick }: { on: boolean; children: ReactNode; onPick: () => void }) {
  return (
    <button type="button" aria-pressed={on} className="bare swp-chip" onClick={onPick}
      style={{ padding: '6px 14px', borderRadius: 999, fontSize: 14, lineHeight: '18px', outline: '1px solid rgba(255,255,255,.14)', outlineOffset: -1,
        whiteSpace: 'nowrap', ...segOn(on) }}>{children}</button>
  );
}

/** The round switch: 40×24, on #65C466, knob 20 at 19 / 2. */
export function Switch({ on, label, onToggle }: { on: boolean; label: string; onToggle: () => void }) {
  return (
    <button type="button" role="switch" aria-checked={on} aria-label={label} className="bare" onClick={onToggle}
      style={{ position: 'relative', flex: 'none', width: 40, height: 24, borderRadius: 12, background: on ? '#65C466' : 'rgba(120,120,128,.32)', transition: 'background .2s' }}>
      <span style={{ position: 'absolute', top: 2, left: on ? 19 : 2, width: 20, height: 20, borderRadius: '50%', background: '#FFFFFF',
        boxShadow: '0 2px 4px rgba(0,0,0,.35)', transition: 'left .2s cubic-bezier(.22,1,.36,1)' }} />
    </button>
  );
}

/** The hovers the design draws with style-hover, and the focus ring over the chips' own outline. */
export function PosStyles() {
  return (
    <style>{`.sw .swp-chip:focus-visible{outline:2px solid #86A8F0!important;outline-offset:2px!important}
.sw .swp-add:hover{background:#FFFFFF!important}
.sw .swp-cell:hover{filter:brightness(1.25)}`}</style>
  );
}
