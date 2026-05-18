import { useMemo, useRef, useEffect, useState } from 'react';
import { hierarchy, treemap, treemapSquarify } from 'd3-hierarchy';
import {
  fmtUSDShort,
  aggregateBySector,
  aggregateByTicker,
  aggregateByStrategy,
  type PositionComputed,
  type StrategyBucket,
} from './types';

export type AllocView = 'sector' | 'stock' | 'strategy';

interface Props {
  rows: PositionComputed[];
  view: AllocView;
  height?: number;
  maxItems?: number;
  overlayByTicker?: Map<string, StrategyBucket>;
}

interface Datum {
  label: string;
  value: number;
  pct: number;
  isOther?: boolean;
}

// Top item gets the brand neon, rest cycle through a desaturated teal scale.
// Matches design_handoff_positions/treemap.jsx:paletteFor exactly.
const TEAL_SHADES = [
  '#326e64', '#2a5e54', '#234d46', '#1e5a50',
  '#264a44', '#1f3f3a', '#1a3530', '#162d29',
];
function paletteFor(i: number): string {
  if (i === 0) return '#d2e632';
  return TEAL_SHADES[(i - 1) % TEAL_SHADES.length];
}
function textOn(i: number): string {
  return i === 0 ? '#0a2828' : '#faf5f0';
}

const TREEMAP_W = 1000; // logical units; scales via viewBox

export function AllocationTreemap({
  rows,
  view,
  height = 600,
  maxItems = 10,
  overlayByTicker,
}: Props) {
  const wrapRef = useRef<HTMLDivElement | null>(null);
  const [width, setWidth] = useState(0);

  useEffect(() => {
    const el = wrapRef.current;
    if (!el || typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(() => setWidth(el.clientWidth));
    ro.observe(el);
    setWidth(el.clientWidth);
    return () => ro.disconnect();
  }, []);

  // Build the dataset, collapsing tail into "Other" once we exceed maxItems.
  // "Strategy" view doesn't collapse — only 4 buckets max, always shown.
  const data: Datum[] = useMemo(() => {
    if (rows.length === 0) return [];
    if (view === 'strategy') {
      return aggregateByStrategy(rows, overlayByTicker ?? new Map());
    }
    const base =
      view === 'sector' ? aggregateBySector(rows) : aggregateByTicker(rows);
    if (base.length <= maxItems) return base;
    const top = base.slice(0, maxItems - 1);
    const rest = base.slice(maxItems - 1);
    const otherVal = rest.reduce((s, d) => s + d.value, 0);
    const otherPct = rest.reduce((s, d) => s + d.pct, 0);
    return [...top, { label: 'Other', value: otherVal, pct: otherPct, isOther: true }];
  }, [rows, view, maxItems, overlayByTicker]);

  const layout = useMemo(() => {
    if (data.length === 0) return [];
    const root = hierarchy<{ children: Datum[] }>({
      children: data,
    } as never)
      .sum((d) => (d as unknown as Datum).value || 0)
      .sort((a, b) => (b.value || 0) - (a.value || 0));
    treemap<{ children: Datum[] }>()
      .size([TREEMAP_W, height])
      .padding(1)
      .tile(treemapSquarify)(root);
    return root.leaves().map((leaf, i) => ({
      ...(data[i] as Datum),
      x0: leaf.x0,
      x1: leaf.x1,
      y0: leaf.y0,
      y1: leaf.y1,
    }));
  }, [data, height]);

  if (data.length === 0) {
    return (
      <div className="np-treemap-card">
        <div
          className="np-treemap-svg-wrap"
          style={{
            border: '1px dashed var(--navi-elevated)',
            borderRadius: 8,
            justifyContent: 'center',
            alignItems: 'center',
            minHeight: height,
            color: 'var(--navi-fg3)',
            fontFamily: 'var(--navi-font-mono)',
            fontSize: 12,
          }}
        >
          no positions to chart
        </div>
        <div />
      </div>
    );
  }

  return (
    <div className="np-treemap-card">
      <div className="np-treemap-svg-wrap" ref={wrapRef} style={{ minHeight: height }}>
        <svg
          viewBox={`0 0 ${TREEMAP_W} ${height}`}
          preserveAspectRatio="xMidYMid meet"
          width={width || '100%'}
        >
          {layout.map((r, i) => {
            const w = r.x1 - r.x0;
            const h = r.y1 - r.y0;
            const isOther = r.isOther;
            const fill = isOther
              ? 'rgba(50,80,80,0.4)'
              : paletteFor(i);
            const text = isOther ? '#a8c4c0' : textOn(i);
            // Thresholds match design_handoff treemap.jsx.
            const showLabel = w > 48 && h > 24;
            const showPct = w > 70 && h > 44;
            const showValue = w > 100 && h > 64;
            return (
              <g key={i} transform={`translate(${r.x0}, ${r.y0})`}>
                <rect
                  x={1}
                  y={1}
                  width={Math.max(0, w - 2)}
                  height={Math.max(0, h - 2)}
                  fill={fill}
                  stroke="#061a10"
                  strokeWidth={1}
                  rx={2}
                  style={{ transition: 'filter 0.15s' }}
                  onMouseEnter={(e) =>
                    ((e.currentTarget as SVGRectElement).style.filter =
                      'brightness(1.08)')
                  }
                  onMouseLeave={(e) =>
                    ((e.currentTarget as SVGRectElement).style.filter = '')
                  }
                >
                  <title>
                    {r.label} — {fmtUSDShort(r.value)} ({r.pct.toFixed(2)}%)
                  </title>
                </rect>
                {showLabel && (
                  <text
                    x={12}
                    y={22}
                    fill={text}
                    style={{
                      fontFamily: 'DM Mono, monospace',
                      fontSize: 15,
                      fontWeight: 500,
                    }}
                  >
                    {r.label}
                  </text>
                )}
                {showPct && (
                  <text
                    x={12}
                    y={42}
                    fill={text}
                    opacity={0.78}
                    style={{
                      fontFamily: 'DM Mono, monospace',
                      fontSize: 13,
                    }}
                  >
                    {r.pct.toFixed(1)}%
                  </text>
                )}
                {showValue && (
                  <text
                    x={12}
                    y={60}
                    fill={text}
                    opacity={0.6}
                    style={{
                      fontFamily: 'DM Mono, monospace',
                      fontSize: 12,
                    }}
                  >
                    {fmtUSDShort(r.value)}
                  </text>
                )}
              </g>
            );
          })}
        </svg>
      </div>

      {/* Companion list */}
      <div className="np-treemap-list">
        <div className="np-treemap-list-hd">
          {view === 'stock'
            ? 'Top holdings'
            : view === 'sector'
              ? 'Top sectors'
              : 'Strategy mix'}
        </div>
        {data.slice(0, 10).map((d, i) => (
          <div
            key={d.label}
            className={'np-treemap-row' + (view === 'sector' ? ' sector' : '')}
          >
            <span className="lbl">
              <span
                className="swatch"
                style={{ background: d.isOther ? 'rgba(50,80,80,0.5)' : paletteFor(i) }}
              />
              {d.label}
            </span>
            <span className="pct">{d.pct.toFixed(1)}%</span>
          </div>
        ))}
      </div>
    </div>
  );
}
