// A card inside a section (Web Dark v2, `b.isCards`): open on the page, a 1px hair-strong rule on top and 16 px
// under it, the title 17/600 with its sub line 13 on the right, then the blocks 14 apart in the design's order:
// Big number, Stats, Line, Map, Text, Rows, Bars. Cards sit two to a row (gap 36 44); a wide one takes the row.
import type { CSSProperties, ReactNode } from 'react';
import { C, named } from '../../lib/format';
import { tileColors, type Span } from './util';

const INK88 = 'rgba(245,245,247,.88)';

export function Grid({ children }: { children: ReactNode }) {
  return (
    <div className="tnum" style={{ display: 'grid', gridTemplateColumns: 'repeat(2,minmax(0,1fr))', gap: '36px 44px', alignItems: 'start' }}>
      {children}
    </div>
  );
}

export function Card({ title, sub, wide, children, aria }: { title: ReactNode; sub?: ReactNode; wide?: boolean; children?: ReactNode; aria?: string }) {
  return (
    <div aria-label={aria} style={{ gridColumn: wide ? '1 / -1' : 'span 1', minWidth: 0, paddingTop: 16, borderTop: '1px solid rgba(255,255,255,.14)', display: 'flex', flexDirection: 'column', gap: 14 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 12 }}>
        <span style={{ fontSize: 17, fontWeight: 600 }}>{title}</span>
        {sub ? <span style={{ fontSize: 13, color: C.ink2, textAlign: 'right' }}>{sub}</span> : null}
      </div>
      {children}
    </div>
  );
}

/** Big number: 40/44/700, its sub line 14/20 grey. */
export function Big({ v, c, sub }: { v: string; c?: string; sub?: ReactNode }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
      <span style={{ fontSize: 40, lineHeight: '44px', fontWeight: 700, letterSpacing: '-.025em', color: c ?? C.ink }}>{v}</span>
      {sub ? <span style={{ fontSize: 14, lineHeight: '20px', color: C.ink2 }}>{sub}</span> : null}
    </div>
  );
}

export interface Stat { l?: string; v: string; u?: string; c?: string }
/** Stats: three across, label 12 grey, value 22/28/600, a unit line 12 grey. */
export function Stats({ stats }: { stats: Stat[] }) {
  return (
    <div className="tnum" style={{ display: 'grid', gridTemplateColumns: 'repeat(3,minmax(0,1fr))', gap: 12 }}>
      {stats.map((x, i) => (
        <span key={i} style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
          {x.l ? <span style={{ fontSize: 12, color: C.ink2 }}>{x.l}</span> : null}
          <span style={{ fontSize: 22, lineHeight: '28px', fontWeight: 600, color: x.c ?? C.ink }}>{x.v}</span>
          {x.u ? <span style={{ fontSize: 12, color: C.ink2 }}>{x.u}</span> : null}
        </span>
      ))}
    </div>
  );
}

/** Line: a white line over a soft glow, a dashed zero line, 130 tall; its caption 12/17 grey under it.
    `pts` are y positions 0 (top) to 100 (bottom) across the width; `z` the zero line's y. */
export function Line({ pts, z, h = 130, cap }: { pts: number[]; z: number; h?: number; cap?: ReactNode }) {
  const d = pts.map((y, i) => (i ? 'L' : 'M') + (i / Math.max(1, pts.length - 1) * 400).toFixed(1) + ' ' + y.toFixed(1)).join(' ');
  return (
    <>
      <div style={{ position: 'relative', height: h }}>
        <svg viewBox="0 0 400 100" preserveAspectRatio="none" aria-hidden="true" style={{ position: 'absolute', left: 0, top: 8, width: '100%', height: 'calc(100% - 16px)', overflow: 'visible' }}>
          <line x1="0" y1={z.toFixed(1)} x2="400" y2={z.toFixed(1)} style={{ stroke: 'rgba(255,255,255,.24)', strokeWidth: 1, strokeDasharray: '3 4' }} vectorEffect="non-scaling-stroke" />
          <path d={d} style={{ fill: 'none', stroke: 'rgba(245,245,247,.14)', strokeWidth: 8 }} vectorEffect="non-scaling-stroke" />
          <path d={d} style={{ fill: 'none', stroke: '#F5F5F7', strokeWidth: 2 }} vectorEffect="non-scaling-stroke" />
        </svg>
      </div>
      {cap ? <Caption>{cap}</Caption> : null}
    </>
  );
}

export function Caption({ children }: { children: ReactNode }) {
  return <span style={{ fontSize: 12, lineHeight: '17px', color: C.ink2 }}>{children}</span>;
}

export interface MapTile { k: string; t: string; m: string; p: number; g: number; aria: string; go?: () => void }
/** Map: flex tiles sized by weight, radius 6, the ticker 13/600 over the move 12, the text in the tile's colour. */
export function MapTiles({ tiles, h = 160 }: { tiles: MapTile[]; h?: number }) {
  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 3, height: h, alignContent: 'stretch' }}>
      {tiles.map((x) => {
        const { bg, fg } = tileColors(x.p);
        return (
          <button key={x.k} type="button" className="bare swb-tile" onClick={x.go} aria-label={x.aria} title={x.aria}
            style={{ cursor: x.go ? 'pointer' : 'default', flex: `${x.g} 1 0`, minWidth: 58, borderRadius: 6, background: bg, color: fg, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 1 }}>
            <span style={{ fontSize: 13, fontWeight: 600 }}>{x.t}</span>
            <span style={{ fontSize: 12 }}>{x.m}</span>
          </button>
        );
      })}
    </div>
  );
}

/** Words with their runs: a bold run in 600, a coloured run in its colour. */
export function Words({ runs, mask, boldWeight = 600 }: { runs: Span[]; mask: (s: string) => string; boldWeight?: number }) {
  return (
    <>
      {runs.map((r, i) => (r.b || r.c
        ? <span key={i} style={{ fontWeight: r.b ? boldWeight : undefined, color: r.c ? named(r.c, undefined) : undefined }}>{mask(r.t)}</span>
        : <span key={i}>{mask(r.t)}</span>))}
    </>
  );
}

/** Text: 15/23 at .88. */
export function Text({ children, style }: { children: ReactNode; style?: CSSProperties }) {
  return <p style={{ margin: 0, fontSize: 15, lineHeight: '23px', color: INK88, textWrap: 'pretty', ...style } as CSSProperties}>{children}</p>;
}

export interface Row { k?: string; l: ReactNode; s?: ReactNode; sc?: string; v?: ReactNode; c?: string; go?: () => void; aria?: string }
/** Rows: label 15/20 over its sub 13/17, the value 15/600 on the right; 1px hair between rows. */
export function Rows({ rows }: { rows: Row[] }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column' }}>
      {rows.map((r, i) => {
        const style: CSSProperties = { boxSizing: 'border-box', width: '100%', display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto', gap: 12, alignItems: 'center', padding: '10px 0', borderTop: i ? '1px solid rgba(255,255,255,.08)' : 'none' };
        const inner = (
          <>
            <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
              <span style={{ fontSize: 15, lineHeight: '20px' }}>{r.l}</span>
              {r.s ? <span style={{ fontSize: 13, lineHeight: '17px', color: r.sc ?? C.ink2 }}>{r.s}</span> : null}
            </span>
            <span style={{ fontSize: 15, fontWeight: 600, color: r.c ?? C.ink, whiteSpace: 'nowrap' }}>{r.v}</span>
          </>
        );
        return r.go
          ? <button key={r.k ?? i} type="button" className="bare tnum" onClick={r.go} aria-label={r.aria} style={{ ...style, cursor: 'pointer' }}>{inner}</button>
          : <div key={r.k ?? i} className="tnum" style={style}>{inner}</div>;
      })}
    </div>
  );
}

export interface Bar { k: string; l: string; v: string; h: number; cur?: boolean; vc?: string }
/** Bars: 122 tall, the value 12 over each bar (700 on the current one), the label 12 grey under it; the current
    bar in ink, the rest white at .16, radius 5. Heights are to scale on one baseline, the tallest 78. */
export function Bars({ bars }: { bars: Bar[] }) {
  const mx = Math.max(0, ...bars.map((b) => Math.abs(b.h))) || 1;
  return (
    <div style={{ display: 'flex', alignItems: 'flex-end', gap: 12, height: 122 }}>
      {bars.map((x) => (
        <div key={x.k} style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'flex-end', gap: 5 }}>
          <span className="tnum" style={{ fontSize: 12, fontWeight: x.cur ? 700 : 400, color: x.vc ?? C.ink }}>{x.v}</span>
          <div style={{ width: '100%', height: Math.round(Math.abs(x.h) / mx * 78), borderRadius: 5, background: x.cur ? '#F5F5F7' : 'rgba(255,255,255,.16)' }} />
          <span style={{ fontSize: 12, color: C.ink2, whiteSpace: 'nowrap' }}>{x.l}</span>
        </div>
      ))}
    </div>
  );
}

/** "Open N more · ..." and its fold: 14/500 ink over a 1px underline. */
export function More({ label, open, onToggle }: { label: string; open: boolean; onToggle: () => void }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
      <button type="button" className="bare" onClick={onToggle} aria-expanded={open}
        style={{ fontSize: 14, fontWeight: 500, color: C.ink, borderBottom: '1px solid rgba(255,255,255,.3)', paddingBottom: 1, alignSelf: 'flex-start' }}>
        {label}
      </button>
    </div>
  );
}
