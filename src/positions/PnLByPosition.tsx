import { useMemo } from 'react';
import {
  fmtCompact,
  fmtUSD,
  type OptionTrade,
  type PositionComputed,
} from './types';

/**
 * P&L by Position — Tesla-Energy-style chart.
 *
 *   ↑ Gains              ↓ Losses                  (header stats)
 *   $4.1k                −$6.9k
 *
 *   ▇ ▇ ▇                                         (mirrored bars by ticker)
 *           ▇   ▇   ▇
 *   ─────────────────────────  0
 *                       ▆ ▆ ▆
 *                       ▆ ▆ ▆
 *   NVDA META AAPL  ADBE META
 *
 *   Net P&L: −$2.7k
 *
 *   ↑ Gain contributors    ↓ Loss contributors
 *   ●  NVDA  $2,140  51%   ●  META  −$6.9k  100%
 *   ...
 *
 *   Put cost coverage      8% Covered
 *   ┃ gold ┃ blue
 *
 * Each ticker bar = its `overall_pl` (mark + realized) so a position
 * with stock loss but realized options gain shows the net. Sorted by
 * signed P&L descending so winners cluster left, losers cluster right.
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

export function PnLByPosition({ rows, tradesByTicker, onTickerClick }: Props) {
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

  // Gross put cost (long-put open premiums) across the whole portfolio.
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
  const coveragePct =
    putCostPaid > 0 ? (realized / putCostPaid) * 100 : 0;

  const maxAbs = useMemo(
    () => (items.length > 0 ? Math.max(...items.map((x) => Math.abs(x.pl))) : 0),
    [items],
  );

  if (items.length === 0) {
    return (
      <div className="pnl-wrap">
        <div className="pnl-empty">
          No P&amp;L to chart yet — positions need price data or closed trades.
        </div>
      </div>
    );
  }

  return (
    <div className="pnl-wrap">
      {/* Header stats */}
      <div className="pnl-hd">
        <div className="pnl-stat">
          <div className="pnl-stat-k">↑ Gains</div>
          <div className="pnl-stat-v up">{fmtUSD(totalGain)}</div>
        </div>
        <div className="pnl-stat">
          <div className="pnl-stat-k">↓ Losses</div>
          <div className="pnl-stat-v down">
            {totalLoss < 0 ? '−' + fmtUSD(Math.abs(totalLoss)) : fmtUSD(totalLoss)}
          </div>
        </div>
      </div>

      {/* Mirrored bar chart */}
      <PnLBars items={items} maxAbs={maxAbs} onTickerClick={onTickerClick} />

      {/* Net summary */}
      <div className="pnl-net">
        <span className="pnl-net-k">Net P&amp;L</span>
        <span className={'pnl-net-v ' + (net >= 0 ? 'up' : 'down')}>
          {net >= 0 ? fmtUSD(net) : '−' + fmtUSD(Math.abs(net))}
        </span>
      </div>

      {/* Contributor rows */}
      <div className="pnl-cols">
        {gains.length > 0 && (
          <div className="pnl-section">
            <div className="pnl-section-hd">↑ Gain contributors</div>
            {gains.slice(0, 6).map((g) => (
              <ContribRow
                key={g.ticker}
                ticker={g.ticker}
                sector={g.sector}
                value={g.pl}
                pct={totalGain > 0 ? (g.pl / totalGain) * 100 : 0}
                positive
                onClick={() => onTickerClick?.(g.ticker)}
              />
            ))}
          </div>
        )}
        {losses.length > 0 && (
          <div className="pnl-section">
            <div className="pnl-section-hd">↓ Loss contributors</div>
            {losses.slice(0, 6).map((l) => (
              <ContribRow
                key={l.ticker}
                ticker={l.ticker}
                sector={l.sector}
                value={l.pl}
                pct={totalLoss < 0 ? (l.pl / totalLoss) * 100 : 0}
                onClick={() => onTickerClick?.(l.ticker)}
              />
            ))}
          </div>
        )}
      </div>

      {/* Put-cost coverage (solar-offset style) */}
      {putCostPaid > 0 && (
        <PutCostCoverage
          putCost={putCostPaid}
          realized={realized}
          pct={coveragePct}
        />
      )}
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
  const H = 300;
  const PAD_TOP = 14;
  const PAD_BOTTOM = 28;
  const AXIS_W = 44;
  const usableH = H - PAD_TOP - PAD_BOTTOM;
  const zeroY = PAD_TOP + usableH / 2;
  const halfH = usableH / 2;
  const barAreaW = W - AXIS_W;
  const slotW = items.length > 0 ? barAreaW / items.length : 0;
  const barW = Math.min(36, Math.max(8, slotW * 0.6));

  return (
    <div className="pnl-chart-wrap">
      <svg
        viewBox={`0 0 ${W} ${H}`}
        preserveAspectRatio="none"
        className="pnl-svg"
      >
        {/* Half-gridlines (faint) */}
        <line
          x1={0}
          x2={barAreaW}
          y1={PAD_TOP + halfH * 0.5}
          y2={PAD_TOP + halfH * 0.5}
          stroke="rgba(255,255,255,.06)"
        />
        <line
          x1={0}
          x2={barAreaW}
          y1={PAD_TOP + halfH * 1.5}
          y2={PAD_TOP + halfH * 1.5}
          stroke="rgba(255,255,255,.06)"
        />
        {/* Zero line */}
        <line
          x1={0}
          x2={barAreaW}
          y1={zeroY}
          y2={zeroY}
          stroke="rgba(255,255,255,.20)"
          strokeDasharray="4 4"
        />

        {/* Right-side axis labels */}
        <text
          x={W - 4}
          y={PAD_TOP + 10}
          textAnchor="end"
          fill="rgba(255,255,255,.55)"
          fontSize="11"
          fontFamily="var(--navi-font-mono)"
        >
          {fmtCompact(maxAbs)}
        </text>
        <text
          x={W - 4}
          y={PAD_TOP + halfH * 0.5 + 4}
          textAnchor="end"
          fill="rgba(255,255,255,.30)"
          fontSize="10"
          fontFamily="var(--navi-font-mono)"
        >
          {fmtCompact(maxAbs / 2)}
        </text>
        <text
          x={W - 4}
          y={zeroY + 3}
          textAnchor="end"
          fill="rgba(255,255,255,.55)"
          fontSize="11"
          fontFamily="var(--navi-font-mono)"
        >
          0
        </text>
        <text
          x={W - 4}
          y={PAD_TOP + halfH * 1.5 + 4}
          textAnchor="end"
          fill="rgba(255,255,255,.30)"
          fontSize="10"
          fontFamily="var(--navi-font-mono)"
        >
          −{fmtCompact(maxAbs / 2)}
        </text>
        <text
          x={W - 4}
          y={PAD_TOP + usableH + 4}
          textAnchor="end"
          fill="rgba(255,255,255,.55)"
          fontSize="11"
          fontFamily="var(--navi-font-mono)"
        >
          −{fmtCompact(maxAbs)}
        </text>

        {/* Bars */}
        {items.map((it, i) => {
          const cx = i * slotW + slotW / 2;
          const barHeight = maxAbs > 0
            ? (Math.abs(it.pl) / maxAbs) * halfH
            : 0;
          const y = it.pl >= 0 ? zeroY - barHeight : zeroY;
          const fill = it.pl >= 0 ? 'var(--navi-positive)' : 'var(--navi-negative)';
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
                y={H - 8}
                textAnchor="middle"
                fill="rgba(255,255,255,.55)"
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
    </div>
  );
}

function ContribRow({
  ticker,
  sector,
  value,
  pct,
  positive,
  onClick,
}: {
  ticker: string;
  sector: string;
  value: number;
  pct: number;
  positive?: boolean;
  onClick?: () => void;
}) {
  return (
    <button
      type="button"
      className="pnl-row"
      onClick={onClick}
      disabled={!onClick}
    >
      <span className={'pnl-dot ' + (positive ? 'up' : 'down')} />
      <span className="pnl-row-tk">{ticker}</span>
      <span className="pnl-row-sec">{sector}</span>
      <span className={'pnl-row-val ' + (positive ? 'up' : 'down')}>
        {value >= 0 ? fmtUSD(value) : '−' + fmtUSD(Math.abs(value))}
      </span>
      <span className="pnl-row-pct">{Math.abs(pct).toFixed(0)}%</span>
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
  // Two vertical bars side-by-side, normalised so the taller is full height.
  const max = Math.max(putCost, Math.abs(realized), 1);
  const putH = (putCost / max) * 100;
  const realH = (Math.abs(realized) / max) * 100;

  return (
    <div className="pnl-coverage">
      <div className="pnl-coverage-hd">
        <span className="pnl-coverage-title">Put cost coverage</span>
        <span className="pnl-coverage-pct">{pct.toFixed(0)}% Covered</span>
      </div>
      <div className="pnl-coverage-body">
        <div className="pnl-cov-col">
          <div className="pnl-cov-bar-wrap">
            <div
              className="pnl-cov-bar gold"
              style={{ height: `${putH}%` }}
            />
          </div>
          <div className="pnl-cov-val">{fmtUSD(putCost)}</div>
          <div className="pnl-cov-label gold">Put cost paid</div>
        </div>
        <div className="pnl-cov-spacer">
          <div className="pnl-cov-dashes" />
        </div>
        <div className="pnl-cov-col">
          <div className="pnl-cov-bar-wrap">
            <div
              className="pnl-cov-bar blue"
              style={{ height: `${realH}%` }}
            />
          </div>
          <div className="pnl-cov-val">
            {realized >= 0 ? fmtUSD(realized) : '−' + fmtUSD(Math.abs(realized))}
          </div>
          <div className="pnl-cov-label blue">Realized</div>
        </div>
      </div>
    </div>
  );
}
