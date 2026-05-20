import { useMemo, useState } from 'react';
import {
  fmtCompact,
  fmtUSD,
  type OptionTrade,
  type PositionComputed,
} from './types';

/**
 * P&L by Position — Tesla-Energy-style mirrored bar chart.
 *
 * Layout mirrors the AllocationTreemap card it sits next to: 1fr + 240px
 * grid, no outline, matching padding / radius / surface — so toggling
 * between the four allocation views feels cohesive.
 *
 *   ┌───────────────────────────────────┬────────────────┐
 *   │                                   │ [Contribs|Cov] │
 *   │  ▇                                │                │
 *   │  ▇  ▇                             │  ●NVDA $2.1k   │
 *   │  ─────────────── 0 ─────────────  │  ●META $1.3k   │
 *   │              ▆                    │  ●META −$6.9k  │
 *   │              ▆                    │                │
 *   │  NVDA META ADBE META              │                │
 *   │  Net P&L: −$2,775                 │                │
 *   └───────────────────────────────────┴────────────────┘
 *
 * Each ticker bar = `overall_pl` (mark + realized). Sorted signed-desc
 * so winners cluster left, losers right.
 */

interface Props {
  rows: PositionComputed[];
  tradesByTicker: Map<string, OptionTrade[]>;
  onTickerClick?: (ticker: string) => void;
}

interface Item {
  ticker: string;
  sector: string;
  pl: number;
}

type SidePanel = 'contrib' | 'coverage';

export function PnLByPosition({ rows, tradesByTicker, onTickerClick }: Props) {
  const [tab, setTab] = useState<SidePanel>('contrib');

  const items = useMemo<Item[]>(
    () =>
      rows
        .map((r) => ({ ticker: r.ticker, sector: r.sector, pl: r.overall_pl }))
        .filter((x) => Math.abs(x.pl) >= 1)
        .sort((a, b) => b.pl - a.pl),
    [rows],
  );

  const gains = useMemo(() => items.filter((x) => x.pl > 0), [items]);
  const losses = useMemo(() => items.filter((x) => x.pl < 0), [items]);
  const totalGain = useMemo(() => gains.reduce((s, x) => s + x.pl, 0), [gains]);
  const totalLoss = useMemo(() => losses.reduce((s, x) => s + x.pl, 0), [losses]);
  const net = totalGain + totalLoss;

  const putCostPaid = useMemo(() => {
    let total = 0;
    for (const list of tradesByTicker.values()) {
      for (const t of list) {
        if (
          t.action === 'open' &&
          t.option_type === 'put' &&
          t.direction === 'long'
        ) {
          total += t.contracts * 100 * t.premium;
        }
      }
    }
    return total;
  }, [tradesByTicker]);

  const realized = useMemo(
    () => rows.reduce((s, r) => s + r.realized_pl, 0),
    [rows],
  );
  const coveragePct = putCostPaid > 0 ? (realized / putCostPaid) * 100 : 0;

  const maxAbs = useMemo(
    () => (items.length > 0 ? Math.max(...items.map((x) => Math.abs(x.pl))) : 0),
    [items],
  );

  if (items.length === 0) {
    return (
      <div className="np-treemap-card">
        <div
          className="np-treemap-svg-wrap"
          style={{
            color: 'var(--navi-fg3)',
            justifyContent: 'center',
            alignItems: 'center',
            fontFamily: 'var(--navi-font-mono)',
            fontSize: 12,
          }}
        >
          no P&amp;L to chart yet
        </div>
        <div />
      </div>
    );
  }

  return (
    <div className="np-treemap-card pnl-card">
      {/* LEFT: chart + net summary */}
      <div className="pnl-chart-col">
        <div className="pnl-chart-hd">
          <div className="pnl-chart-stat">
            <span className="pnl-chart-stat-k">↑ Gains</span>
            <span className="pnl-chart-stat-v up">{fmtUSD(totalGain)}</span>
          </div>
          <div className="pnl-chart-stat">
            <span className="pnl-chart-stat-k">↓ Losses</span>
            <span className="pnl-chart-stat-v down">
              {totalLoss < 0
                ? '−' + fmtUSD(Math.abs(totalLoss))
                : fmtUSD(totalLoss)}
            </span>
          </div>
          <div className="pnl-chart-stat right">
            <span className="pnl-chart-stat-k">Net P&amp;L</span>
            <span className={'pnl-chart-stat-v ' + (net >= 0 ? 'up' : 'down')}>
              {net >= 0 ? fmtUSD(net) : '−' + fmtUSD(Math.abs(net))}
            </span>
          </div>
        </div>
        <PnLBars items={items} maxAbs={maxAbs} onTickerClick={onTickerClick} />
      </div>

      {/* RIGHT: tabbed side panel */}
      <div className="pnl-side">
        <div className="pnl-tabs">
          <button
            className={tab === 'contrib' ? 'on' : ''}
            onClick={() => setTab('contrib')}
          >
            Contributors
          </button>
          <button
            className={tab === 'coverage' ? 'on' : ''}
            onClick={() => setTab('coverage')}
            disabled={putCostPaid === 0}
            title={putCostPaid === 0 ? 'No protective puts open' : ''}
          >
            Put coverage
          </button>
        </div>

        {tab === 'contrib' && (
          <div className="pnl-contrib">
            {gains.length > 0 && (
              <>
                <div className="np-treemap-list-hd">↑ Gain</div>
                {gains.slice(0, 5).map((g) => (
                  <ContribRow
                    key={g.ticker}
                    ticker={g.ticker}
                    value={g.pl}
                    pct={totalGain > 0 ? (g.pl / totalGain) * 100 : 0}
                    positive
                    onClick={() => onTickerClick?.(g.ticker)}
                  />
                ))}
              </>
            )}
            {losses.length > 0 && (
              <>
                <div className="np-treemap-list-hd" style={{ marginTop: 14 }}>
                  ↓ Loss
                </div>
                {losses.slice(0, 5).map((l) => (
                  <ContribRow
                    key={l.ticker}
                    ticker={l.ticker}
                    value={l.pl}
                    pct={totalLoss < 0 ? (l.pl / totalLoss) * 100 : 0}
                    onClick={() => onTickerClick?.(l.ticker)}
                  />
                ))}
              </>
            )}
          </div>
        )}

        {tab === 'coverage' && (
          <PutCostCoverage
            putCost={putCostPaid}
            realized={realized}
            pct={coveragePct}
          />
        )}
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────

function PnLBars({
  items,
  maxAbs,
  onTickerClick,
}: {
  items: Item[];
  maxAbs: number;
  onTickerClick?: (ticker: string) => void;
}) {
  const W = 1000;
  const H = 420;
  const PAD_TOP = 14;
  const PAD_BOTTOM = 32;
  const AXIS_W = 48;
  const usableH = H - PAD_TOP - PAD_BOTTOM;
  const zeroY = PAD_TOP + usableH / 2;
  const halfH = usableH / 2;
  const barAreaW = W - AXIS_W;
  const slotW = items.length > 0 ? barAreaW / items.length : 0;
  const barW = Math.min(48, Math.max(8, slotW * 0.6));

  return (
    <svg
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="xMidYMid meet"
      className="pnl-svg"
    >
      <line
        x1={0}
        x2={barAreaW}
        y1={PAD_TOP + halfH * 0.5}
        y2={PAD_TOP + halfH * 0.5}
        stroke="rgba(30,90,80,.30)"
      />
      <line
        x1={0}
        x2={barAreaW}
        y1={PAD_TOP + halfH * 1.5}
        y2={PAD_TOP + halfH * 1.5}
        stroke="rgba(30,90,80,.30)"
      />
      <line
        x1={0}
        x2={barAreaW}
        y1={zeroY}
        y2={zeroY}
        stroke="var(--navi-border-bright)"
        strokeDasharray="4 4"
        opacity="0.6"
      />

      {/* Right-side axis labels */}
      <text
        x={W - 4}
        y={PAD_TOP + 10}
        textAnchor="end"
        fill="var(--navi-fg3)"
        fontSize="11"
        fontFamily="var(--navi-font-mono)"
      >
        {fmtCompact(maxAbs)}
      </text>
      <text
        x={W - 4}
        y={PAD_TOP + halfH * 0.5 + 4}
        textAnchor="end"
        fill="var(--navi-fg4)"
        fontSize="10"
        fontFamily="var(--navi-font-mono)"
      >
        {fmtCompact(maxAbs / 2)}
      </text>
      <text
        x={W - 4}
        y={zeroY + 3}
        textAnchor="end"
        fill="var(--navi-fg3)"
        fontSize="11"
        fontFamily="var(--navi-font-mono)"
      >
        0
      </text>
      <text
        x={W - 4}
        y={PAD_TOP + halfH * 1.5 + 4}
        textAnchor="end"
        fill="var(--navi-fg4)"
        fontSize="10"
        fontFamily="var(--navi-font-mono)"
      >
        −{fmtCompact(maxAbs / 2)}
      </text>
      <text
        x={W - 4}
        y={PAD_TOP + usableH + 4}
        textAnchor="end"
        fill="var(--navi-fg3)"
        fontSize="11"
        fontFamily="var(--navi-font-mono)"
      >
        −{fmtCompact(maxAbs)}
      </text>

      {items.map((it, i) => {
        const cx = i * slotW + slotW / 2;
        const barHeight = maxAbs > 0 ? (Math.abs(it.pl) / maxAbs) * halfH : 0;
        const y = it.pl >= 0 ? zeroY - barHeight : zeroY;
        const fill =
          it.pl >= 0 ? 'var(--navi-positive)' : 'var(--navi-negative)';
        return (
          <g
            key={it.ticker}
            style={{ cursor: onTickerClick ? 'pointer' : 'default' }}
            onClick={() => onTickerClick?.(it.ticker)}
          >
            <title>
              {it.ticker} · {it.pl >= 0 ? '+' : '−'}
              {fmtUSD(Math.abs(it.pl))}
            </title>
            <rect
              x={cx - barW / 2}
              y={y}
              width={barW}
              height={Math.max(2, barHeight)}
              fill={fill}
              rx="3"
            />
            <text
              x={cx}
              y={H - 10}
              textAnchor="middle"
              fill="var(--navi-fg2)"
              fontSize="11"
              fontFamily="var(--navi-font-sans)"
              fontWeight="500"
            >
              {it.ticker}
            </text>
          </g>
        );
      })}
    </svg>
  );
}

function ContribRow({
  ticker,
  value,
  pct,
  positive,
  onClick,
}: {
  ticker: string;
  value: number;
  pct: number;
  positive?: boolean;
  onClick?: () => void;
}) {
  return (
    <button
      type="button"
      className="np-treemap-row pnl-contrib-row"
      onClick={onClick}
      disabled={!onClick}
    >
      <span className="lbl">
        <span
          className="swatch"
          style={{
            background: positive
              ? 'var(--navi-positive)'
              : 'var(--navi-negative)',
          }}
        />
        {ticker}
      </span>
      <span className="pct">
        <span className={'pnl-contrib-val ' + (positive ? 'up' : 'down')}>
          {value >= 0 ? fmtUSD(value) : '−' + fmtUSD(Math.abs(value))}
        </span>
        <span className="pnl-contrib-pct">{Math.abs(pct).toFixed(0)}%</span>
      </span>
    </button>
  );
}

function PutCostCoverage({
  putCost,
  realized,
  pct,
}: {
  putCost: number;
  realized: number;
  pct: number;
}) {
  const max = Math.max(putCost, Math.abs(realized), 1);
  const putH = (putCost / max) * 100;
  const realH = (Math.abs(realized) / max) * 100;
  return (
    <div className="pnl-coverage">
      <div className="pnl-coverage-pct-big">
        {pct.toFixed(0)}%
        <span className="pnl-coverage-pct-sub">Covered</span>
      </div>
      <div className="pnl-coverage-body">
        <div className="pnl-cov-col">
          <div className="pnl-cov-bar-wrap">
            <div className="pnl-cov-bar gold" style={{ height: `${putH}%` }} />
          </div>
          <div className="pnl-cov-val">{fmtUSD(putCost)}</div>
          <div className="pnl-cov-label gold">Put cost paid</div>
        </div>
        <div className="pnl-cov-col">
          <div className="pnl-cov-bar-wrap">
            <div className="pnl-cov-bar blue" style={{ height: `${realH}%` }} />
          </div>
          <div className="pnl-cov-val">
            {realized >= 0
              ? fmtUSD(realized)
              : '−' + fmtUSD(Math.abs(realized))}
          </div>
          <div className="pnl-cov-label blue">Realized</div>
        </div>
      </div>
    </div>
  );
}
