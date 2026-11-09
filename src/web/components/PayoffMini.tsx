// A small payoff line (README 1b "the payoff", the design's rail card and tile): P&L across a price range, green above
// break even and red below (one path, clipped at the zero line), filled with the page's #sunGU / #sunGD, the zero line
// rgba(255,255,255,.22), today a dashed vertical (rgba(255,255,255,.35), dash 2 3). Drawn in a 400 × 100 box stretched
// to the size given, with `pad` (12%) of the range above and below. Generic: values are evenly spaced across x.
import { useMemo, type CSSProperties } from 'react';

export interface PayoffMiniProps {
  /** P&L at evenly spaced prices, low to high. */
  values: number[];
  /** Height in px; the width fills the parent. */
  height: number;
  /** Line width in px (rail card 1.75, tile 1.5). */
  stroke?: number;
  /** Padding above and below, as a share of the range. */
  pad?: number;
  /** Where today sits across, 0 to 1 (the middle of a ±range). */
  today?: number;
  style?: CSSProperties;
}

const box: CSSProperties = { position: 'absolute', inset: 0, width: '100%', height: '100%', overflow: 'visible' };

export function payoffGeometry(values: number[], pad = 0.12) {
  const n = values.length;
  let lo = Math.min(0, ...values), hi = Math.max(0, ...values);
  const p = (hi - lo) * pad || 1;
  lo -= p; hi += p;
  const yy = (v: number) => ((hi - v) / (hi - lo)) * 100;
  const line = values.map((v, i) => (i ? 'L' : 'M') + (n > 1 ? (i * 400) / (n - 1) : 0).toFixed(1) + ' ' + yy(v).toFixed(1)).join(' ');
  const z = yy(0);
  return { line, area: `${line} L400 ${z.toFixed(1)} L0 ${z.toFixed(1)} Z`, z };
}

export default function PayoffMini({ values, height, stroke = 1.75, pad = 0.12, today = 0.5, style }: PayoffMiniProps) {
  const g = useMemo(() => payoffGeometry(values, pad), [values, pad]);
  if (!values.length) return <span style={{ position: 'relative', display: 'block', height, ...style }} />;
  const ln = (c: string): CSSProperties => ({ fill: 'none', stroke: c, strokeWidth: stroke, strokeLinejoin: 'round', vectorEffect: 'non-scaling-stroke' });
  const zs = g.z.toFixed(1), x0 = (today * 400).toFixed(1);
  return (
    <span aria-hidden="true" style={{ position: 'relative', display: 'block', height, ...style }}>
      <svg viewBox="0 0 400 100" preserveAspectRatio="none" style={{ ...box, clipPath: `inset(0 0 ${(100 - g.z).toFixed(1)}% 0)` }}>
        <path d={g.area} fill="url(#sunGU)" />
        <path d={g.line} style={ln('#65C466')} />
      </svg>
      <svg viewBox="0 0 400 100" preserveAspectRatio="none" style={{ ...box, clipPath: `inset(${zs}% 0 0 0)` }}>
        <path d={g.area} fill="url(#sunGD)" />
        <path d={g.line} style={ln('#FF6961')} />
      </svg>
      <svg viewBox="0 0 400 100" preserveAspectRatio="none" style={box}>
        <line x1="0" y1={zs} x2="400" y2={zs} style={{ stroke: 'rgba(255,255,255,.22)', strokeWidth: 1, vectorEffect: 'non-scaling-stroke' }} />
        <line x1={x0} y1="-6" x2={x0} y2="106" style={{ stroke: 'rgba(255,255,255,.35)', strokeWidth: 1, strokeDasharray: '2 3', vectorEffect: 'non-scaling-stroke' }} />
      </svg>
    </span>
  );
}
