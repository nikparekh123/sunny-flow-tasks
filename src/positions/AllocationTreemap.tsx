import { useMemo, useRef, useEffect, useState } from 'react';
import { hierarchy, treemap, treemapSquarify } from 'd3-hierarchy';
import { fmtUSDShort, fmtPct, type PositionComputed } from './types';

// Stable color per sector; "by stock" view colors each ticker by its sector.
const SECTOR_COLORS: Record<string, string> = {
  'Technology': '#5a8ac8',
  'Healthcare': '#a8d4a0',
  'Financials': '#c8a05a',
  'Consumer Discretionary': '#c85a7a',
  'Consumer Staples': '#7aa878',
  'Energy': '#e87060',
  'Industrials': '#3d8a7c',
  'Materials': '#468278',
  'Utilities': '#a090e0',
  'Real Estate': '#6ec0d8',
  'Communication Services': '#e0c060',
  'Other': '#8abdb6',
};
const SECTOR_FALLBACK = '#8abdb6';

export type AllocView = 'sector' | 'stock';

interface Props {
  rows: PositionComputed[];
  view: AllocView;
  onViewChange: (v: AllocView) => void;
  height?: number;
  maxItems?: number;
}

interface Datum {
  label: string;
  value: number;
  pct: number;
  color: string;
}

export function AllocationTreemap({
  rows,
  view,
  onViewChange,
  height = 600,
  maxItems = 8,
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

  const data: Datum[] = useMemo(() => {
    if (rows.length === 0) return [];
    if (view === 'sector') {
      const map = new Map<string, number>();
      rows.forEach((r) =>
        map.set(r.sector, (map.get(r.sector) || 0) + r.market_value),
      );
      const total = Array.from(map.values()).reduce((s, v) => s + v, 0);
      return Array.from(map.entries())
        .map(([label, value]) => ({
          label,
          value,
          pct: total === 0 ? 0 : (value / total) * 100,
          color: SECTOR_COLORS[label] ?? SECTOR_FALLBACK,
        }))
        .sort((a, b) => b.value - a.value);
    }
    const total = rows.reduce((s, r) => s + r.market_value, 0);
    return rows
      .map((r) => ({
        label: r.ticker,
        value: r.market_value,
        pct: total === 0 ? 0 : (r.market_value / total) * 100,
        color: SECTOR_COLORS[r.sector] ?? SECTOR_FALLBACK,
      }))
      .sort((a, b) => b.value - a.value);
  }, [rows, view]);

  const layout = useMemo(() => {
    if (data.length === 0 || width === 0) return [];
    const root = hierarchy<{ children: Datum[] }>({
      children: data,
    } as never)
      .sum((d) => (d as unknown as Datum).value || 0)
      .sort((a, b) => (b.value || 0) - (a.value || 0));
    treemap<{ children: Datum[] }>()
      .size([width, height])
      .padding(1)
      .tile(treemapSquarify)(root);
    return root.leaves().map((leaf, i) => ({
      ...(data[i] ?? leaf.data as unknown as Datum),
      x0: leaf.x0,
      x1: leaf.x1,
      y0: leaf.y0,
      y1: leaf.y1,
    }));
  }, [data, width, height]);

  return (
    <div
      style={{
        display: 'grid',
        gridTemplateColumns: 'minmax(0, 1fr) 320px',
        gap: 24,
      }}
      className="positions-alloc"
    >
      {/* Treemap */}
      <div ref={wrapRef}>
        {/* Toggle row */}
        <AllocToggle view={view} onChange={onViewChange} />
        <div style={{ height, width: '100%', position: 'relative' }}>
          {data.length === 0 ? (
            <EmptyTreemap />
          ) : (
            <svg
              width={width || '100%'}
              height={height}
              style={{ display: 'block' }}
            >
              {layout.map((d, i) => {
                const w = d.x1 - d.x0;
                const h = d.y1 - d.y0;
                const showLabel = w > 80 && h > 36;
                const showPct = w > 80 && h > 60;
                const showVal = w > 100 && h > 84;
                return (
                  <g key={i} transform={`translate(${d.x0}, ${d.y0})`}>
                    <rect
                      width={w}
                      height={h}
                      fill={d.color}
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
                        {d.label} — {fmtUSDShort(d.value)} ({d.pct.toFixed(2)}%)
                      </title>
                    </rect>
                    {showLabel && (
                      <text
                        x={12}
                        y={24}
                        fill="#0a2828"
                        style={{
                          fontFamily: 'var(--owl-font-mono)',
                          fontSize: 15,
                          fontWeight: 500,
                        }}
                      >
                        {d.label}
                      </text>
                    )}
                    {showPct && (
                      <text
                        x={12}
                        y={42}
                        fill="#0a2828"
                        style={{
                          fontFamily: 'var(--owl-font-mono)',
                          fontSize: 13,
                          opacity: 0.78,
                        }}
                      >
                        {d.pct.toFixed(1)}%
                      </text>
                    )}
                    {showVal && (
                      <text
                        x={12}
                        y={60}
                        fill="#0a2828"
                        style={{
                          fontFamily: 'var(--owl-font-mono)',
                          fontSize: 12,
                          opacity: 0.6,
                        }}
                      >
                        {fmtUSDShort(d.value)}
                      </text>
                    )}
                  </g>
                );
              })}
            </svg>
          )}
        </div>
      </div>

      {/* Companion list */}
      <CompanionList items={data.slice(0, maxItems)} view={view} />
    </div>
  );
}

function AllocToggle({
  view,
  onChange,
}: {
  view: AllocView;
  onChange: (v: AllocView) => void;
}) {
  return (
    <div className="flex items-center justify-between mb-3">
      <h2
        style={{
          fontSize: 24,
          fontWeight: 500,
          letterSpacing: '-0.3px',
          color: 'var(--owl-text-primary)',
        }}
      >
        Allocation
      </h2>
      <div
        style={{
          display: 'inline-flex',
          border: '1px solid var(--owl-elevated)',
        }}
      >
        <ToggleButton on={view === 'sector'} onClick={() => onChange('sector')}>
          by sector
        </ToggleButton>
        <ToggleButton on={view === 'stock'} onClick={() => onChange('stock')}>
          by stock
        </ToggleButton>
      </div>
    </div>
  );
}

function ToggleButton({
  on,
  onClick,
  children,
}: {
  on?: boolean;
  onClick?: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      style={{
        background: on ? 'var(--owl-tint-neon)' : 'transparent',
        color: on ? 'var(--owl-neon)' : 'var(--owl-text-muted)',
        border: 'none',
        padding: '7px 14px',
        fontFamily: 'var(--owl-font-sans)',
        fontSize: 12,
        fontWeight: 500,
        letterSpacing: '0.5px',
        cursor: 'pointer',
        textTransform: 'lowercase',
      }}
    >
      {children}
    </button>
  );
}

function CompanionList({ items, view }: { items: Datum[]; view: AllocView }) {
  return (
    <div style={{ paddingTop: 4 }}>
      <div
        style={{
          fontSize: 10,
          fontWeight: 500,
          letterSpacing: '1.5px',
          textTransform: 'uppercase',
          color: 'var(--owl-text-muted)',
          marginBottom: 12,
        }}
      >
        Top {items.length} by {view}
      </div>
      <div>
        {items.map((d, i) => (
          <div
            key={d.label}
            style={{
              display: 'grid',
              gridTemplateColumns: '24px 12px minmax(0, 1fr) 60px 80px',
              alignItems: 'center',
              gap: 10,
              height: 44,
              borderBottom:
                i === items.length - 1
                  ? 'none'
                  : '1px solid var(--owl-elevated)',
            }}
          >
            <span
              style={{
                fontFamily: 'var(--owl-font-mono)',
                fontSize: 11,
                color: 'var(--owl-text-muted)',
                textAlign: 'right',
              }}
            >
              {String(i + 1).padStart(2, '0')}
            </span>
            <span
              style={{ width: 10, height: 10, background: d.color }}
              aria-hidden
            />
            <span
              style={{
                fontSize: 13,
                color: 'var(--owl-text-primary)',
                whiteSpace: 'nowrap',
                overflow: 'hidden',
                textOverflow: 'ellipsis',
              }}
            >
              {d.label}
            </span>
            <span
              style={{
                fontFamily: 'var(--owl-font-mono)',
                fontSize: 12,
                color: 'var(--owl-text-secondary)',
                textAlign: 'right',
              }}
            >
              {d.pct.toFixed(2)}%
            </span>
            <span
              style={{
                fontFamily: 'var(--owl-font-mono)',
                fontSize: 13,
                color: 'var(--owl-text-primary)',
                textAlign: 'right',
              }}
            >
              {fmtUSDShort(d.value)}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

function EmptyTreemap() {
  return (
    <div
      style={{
        height: '100%',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        border: '1px dashed var(--owl-elevated)',
      }}
    >
      <span
        style={{
          fontSize: 12,
          color: 'var(--owl-text-muted)',
          fontFamily: 'var(--owl-font-mono)',
          letterSpacing: '0.5px',
        }}
      >
        no positions to chart
      </span>
    </div>
  );
}
