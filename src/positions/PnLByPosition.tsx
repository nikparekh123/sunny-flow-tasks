import { useMemo, useState } from 'react';
import { createPortal } from 'react-dom';
import {
  closeRealizedPL,
  fmtCompact,
  fmtUSD,
  type OptionTrade,
  type PositionComputed,
} from './types';

/**
 * P&L by Position — multi-view performance card.
 *
 *   Overall  | Stock | Options
 *                       └─ All | Short calls | Long calls | Short puts | Long puts
 *
 *   Overall/Stock  → per-ticker mirrored bars (overall_pl or pnl_dollar)
 *   Options        → DAILY stacked bars (Tesla style). Each bar is a
 *                    close date; segments stacked by ticker. Positive
 *                    realized goes up, negative goes down.
 *
 *   Side panel: tabbed [Contributors | Put coverage].
 *
 * Color rule (per user):
 *   • Profits = neon + secondary greens (cycle by ticker rank)
 *   • Losses  = red shades
 */

interface Props {
  rows: PositionComputed[];
  tradesByTicker: Map<string, OptionTrade[]>;
  onTickerClick?: (ticker: string) => void;
}

type View = 'overall' | 'stock' | 'options';
type OptionDir = 'all' | 'short-call' | 'long-call' | 'short-put' | 'long-put';

interface Item {
  ticker: string;
  sector: string;
  pl: number;
}

interface CloseEvent {
  date: string;   // ISO YYYY-MM-DD
  ticker: string;
  value: number;  // signed realized P&L
}

// Profit palette — neon first, then "the other greens" (per user).
const POS_PALETTE = ['#d2e632', '#a8d4a0', '#6dd1c5', '#326e64', '#a8c4c0'];
// Loss palette — varying reds.
const NEG_PALETTE = ['#e87060', '#c85a4e', '#a64a40', '#7d3b33', '#5a2a24'];

function paletteColor(positive: boolean, rank: number): string {
  const p = positive ? POS_PALETTE : NEG_PALETTE;
  return p[Math.max(0, rank) % p.length];
}

export function PnLByPosition({ rows, tradesByTicker, onTickerClick }: Props) {
  const [view, setView] = useState<View>('overall');
  const [optDir, setOptDir] = useState<OptionDir>('all');

  // Quick lookup so the hover card can show the full row (P&L breakdown,
  // notional, % of book, effective basis, …) without scanning the array
  // on every mouse move.
  const rowsByTicker = useMemo(() => {
    const m = new Map<string, PositionComputed>();
    for (const r of rows) m.set(r.ticker, r);
    return m;
  }, [rows]);

  // ── Per-ticker items for Overall / Stock views ──────────────────
  const itemsOverall = useMemo<Item[]>(
    () =>
      rows
        .map((r) => ({ ticker: r.ticker, sector: r.sector, pl: r.overall_pl }))
        .filter((x) => Math.abs(x.pl) >= 1)
        .sort((a, b) => b.pl - a.pl),
    [rows],
  );
  const itemsStock = useMemo<Item[]>(
    () =>
      rows
        .map((r) => ({ ticker: r.ticker, sector: r.sector, pl: r.pnl_dollar }))
        .filter((x) => Math.abs(x.pl) >= 1)
        .sort((a, b) => b.pl - a.pl),
    [rows],
  );

  // ── Close events for Options view ──────────────────────────────
  const closeEvents = useMemo<CloseEvent[]>(() => {
    const openById = new Map<string, OptionTrade>();
    for (const list of tradesByTicker.values()) {
      for (const t of list) if (t.action === 'open') openById.set(t.id, t);
    }
    const out: CloseEvent[] = [];
    for (const list of tradesByTicker.values()) {
      for (const t of list) {
        if (t.action !== 'close' || !t.closes_trade_id) continue;
        const open = openById.get(t.closes_trade_id);
        if (!open) continue;
        const sig = `${open.direction}-${open.option_type}` as OptionDir;
        if (optDir !== 'all' && sig !== optDir) continue;
        out.push({
          date: t.trade_date,
          ticker: t.ticker,
          value: closeRealizedPL(t, open),
        });
      }
    }
    return out;
  }, [tradesByTicker, optDir]);

  // Ticker → rank (by total |realized| in current filter) for color.
  const tickerRank = useMemo(() => {
    const totals = new Map<string, number>();
    for (const c of closeEvents) {
      totals.set(c.ticker, (totals.get(c.ticker) ?? 0) + Math.abs(c.value));
    }
    const order = [...totals.entries()].sort((a, b) => b[1] - a[1]).map(([t]) => t);
    const m = new Map<string, number>();
    order.forEach((t, i) => m.set(t, i));
    return m;
  }, [closeEvents]);

  // Per-view items shown in chart column for Overall / Stock.
  const items = view === 'stock' ? itemsStock : itemsOverall;
  const gains = items.filter((x) => x.pl > 0);
  const losses = items.filter((x) => x.pl < 0);
  const totalGain = gains.reduce((s, x) => s + x.pl, 0);
  const totalLoss = losses.reduce((s, x) => s + x.pl, 0);
  const net = totalGain + totalLoss;
  const maxAbs =
    items.length > 0 ? Math.max(...items.map((x) => Math.abs(x.pl))) : 0;

  // For Options view, recompute header sums based on closeEvents.
  const optGains = closeEvents.filter((c) => c.value > 0);
  const optLosses = closeEvents.filter((c) => c.value < 0);
  const optTotalGain = optGains.reduce((s, c) => s + c.value, 0);
  const optTotalLoss = optLosses.reduce((s, c) => s + c.value, 0);
  const optNet = optTotalGain + optTotalLoss;

  // ── Put + Stock burden + weekly burn ───────────────────────────
  // Total burden = put cost on active long puts + current unrealized
  // stock loss (net, if portfolio mark is negative). Short premium
  // realized needs to cover BOTH to break even by the time puts expire.
  const protection = useMemo(() => {
    const today = new Date();
    today.setUTCHours(0, 0, 0, 0);

    // Index of fully-closed opens so we ignore them.
    const closedQty = new Map<string, number>();
    const openQty = new Map<string, number>();
    for (const list of tradesByTicker.values()) {
      for (const t of list) {
        if (t.action === 'open') openQty.set(t.id, t.contracts);
        if (t.action === 'close' && t.closes_trade_id) {
          closedQty.set(
            t.closes_trade_id,
            (closedQty.get(t.closes_trade_id) ?? 0) + t.contracts,
          );
        }
      }
    }
    const closedIds = new Set<string>();
    for (const [id, q] of closedQty) {
      if (q >= (openQty.get(id) ?? Infinity)) closedIds.add(id);
    }

    let activeCost = 0;
    let weightedWeeks = 0;
    for (const list of tradesByTicker.values()) {
      for (const t of list) {
        if (
          t.action !== 'open' ||
          t.option_type !== 'put' ||
          t.direction !== 'long' ||
          closedIds.has(t.id)
        ) continue;
        const cost = t.contracts * 100 * t.premium;
        const exp = new Date(t.expiry + 'T00:00:00Z');
        // Clamp to at least 1 week so we don't divide by ~0 on an
        // expiring-tomorrow put.
        const daysLeft = Math.max(
          7,
          (exp.getTime() - today.getTime()) / 86_400_000,
        );
        const weeksLeft = daysLeft / 7;
        activeCost += cost;
        weightedWeeks += cost * weeksLeft;
      }
    }
    // Cost-weighted average weeks to expiry — single horizon used by
    // BOTH burn rows so the math is internally consistent
    // (put + stock = total, all divided by the same denominator).
    const avgWeeks = activeCost > 0 ? weightedWeeks / activeCost : 0;
    const weeklyBurn = avgWeeks > 0 ? activeCost / avgWeeks : 0;
    return { activeCost, avgWeeks, weeklyBurn };
  }, [tradesByTicker]);

  // Total put cost paid (active + already closed) — for the headline
  // "ever spent on protection" feel, the active number is more useful;
  // we keep the active value since closed puts no longer need to be
  // covered.
  const putCostPaid = protection.activeCost;

  const realized = useMemo(
    () => rows.reduce((s, r) => s + r.realized_pl, 0),
    [rows],
  );

  // Net unrealized stock mark across the portfolio. If negative, that's
  // the stock loss component we need to cover too. Refreshes whenever
  // current_price changes.
  const stockLoss = useMemo(() => {
    const netMark = rows.reduce((s, r) => s + r.pnl_dollar, 0);
    return Math.max(0, -netMark);
  }, [rows]);

  const totalBurden = putCostPaid + stockLoss;
  const totalWeeklyBurn =
    protection.avgWeeks > 0 ? totalBurden / protection.avgWeeks : 0;
  const coveragePct =
    totalBurden > 0 ? (realized / totalBurden) * 100 : 0;

  // Headline stats based on active view
  const headG = view === 'options' ? optTotalGain : totalGain;
  const headL = view === 'options' ? optTotalLoss : totalLoss;
  const headN = view === 'options' ? optNet : net;

  // Overall view — split portfolio P&L into realized (closed options + share
  // sells / assignments) and unrealized (current stock mark vs cost basis),
  // then bucket each by sign so the 6 cells in the header are honest.
  const overallSplit = useMemo(() => {
    let realG = 0, realL = 0, unrealG = 0, unrealL = 0;
    for (const r of rows) {
      const realized = (r.realized_pl ?? 0) + (r.realized_stock_pl ?? 0);
      const unrealized = r.pnl_dollar ?? 0;
      if (realized > 0) realG += realized; else if (realized < 0) realL += realized;
      if (unrealized > 0) unrealG += unrealized; else if (unrealized < 0) unrealL += unrealized;
    }
    return {
      realG, realL, realNet: realG + realL,
      unrealG, unrealL, unrealNet: unrealG + unrealL,
    };
  }, [rows]);

  // Empty state guard
  const empty =
    view === 'options'
      ? closeEvents.length === 0
      : items.length === 0;

  return (
    <div className="np-treemap-card pnl-card">
      {/* LEFT: view toggles + chart */}
      <div className="pnl-chart-col">
        <div className="pnl-view-bar">
          <div className="pnl-view-toggle">
            <button
              className={view === 'overall' ? 'on' : ''}
              onClick={() => setView('overall')}
            >
              Overall
            </button>
            <button
              className={view === 'stock' ? 'on' : ''}
              onClick={() => setView('stock')}
            >
              Stock
            </button>
            <button
              className={view === 'options' ? 'on' : ''}
              onClick={() => setView('options')}
            >
              Options
            </button>
          </div>
          {view === 'options' && (
            <div className="pnl-subfilter">
              {([
                ['all', 'All'],
                ['short-call', 'Short calls'],
                ['long-call', 'Long calls'],
                ['short-put', 'Short puts'],
                ['long-put', 'Long puts'],
              ] as const).map(([k, label]) => (
                <button
                  key={k}
                  className={optDir === k ? 'on' : ''}
                  onClick={() => setOptDir(k)}
                >
                  {label}
                </button>
              ))}
            </div>
          )}
        </div>

        {view === 'overall' ? (
          <div className="pnl-chart-hd split">
            <PnlSplitBlock
              label="Realized"
              gains={overallSplit.realG}
              losses={overallSplit.realL}
              net={overallSplit.realNet}
            />
            <PnlSplitBlock
              label="Unrealized"
              gains={overallSplit.unrealG}
              losses={overallSplit.unrealL}
              net={overallSplit.unrealNet}
            />
          </div>
        ) : (
          <div className="pnl-chart-hd">
            <div className="pnl-chart-stat">
              <span className="pnl-chart-stat-k">↑ Gains</span>
              <span className="pnl-chart-stat-v up">{fmtUSD(headG)}</span>
            </div>
            <div className="pnl-chart-stat">
              <span className="pnl-chart-stat-k">↓ Losses</span>
              <span className="pnl-chart-stat-v down">
                {headL < 0 ? '−' + fmtUSD(Math.abs(headL)) : fmtUSD(headL)}
              </span>
            </div>
            <div className="pnl-chart-stat right">
              <span className="pnl-chart-stat-k">Net</span>
              <span className={'pnl-chart-stat-v ' + (headN >= 0 ? 'up' : 'down')}>
                {headN >= 0 ? fmtUSD(headN) : '−' + fmtUSD(Math.abs(headN))}
              </span>
            </div>
          </div>
        )}

        {empty ? (
          <div className="pnl-empty-area">
            {view === 'options'
              ? 'No closed option trades match this filter.'
              : 'No positions with P&L yet.'}
          </div>
        ) : view === 'options' ? (
          <OptionsDailyBars
            events={closeEvents}
            tickerRank={tickerRank}
            rowsByTicker={rowsByTicker}
          />
        ) : (
          <PerTickerBars
            items={items}
            maxAbs={maxAbs}
            onTickerClick={onTickerClick}
            rowsByTicker={rowsByTicker}
            view={view}
          />
        )}
      </div>

      {/* RIGHT: Put protection box */}
      <aside className="pnl-side">
        <div className="pnl-protection-box">
          <div className="pnl-protection-hd">Put protection</div>
          {putCostPaid > 0 ? (
            <PutCostCoverage
              putCost={putCostPaid}
              stockLoss={stockLoss}
              realized={realized}
              pct={coveragePct}
              putBurn={protection.weeklyBurn}
              totalBurn={totalWeeklyBurn}
            />
          ) : (
            <div className="pnl-protection-empty">
              No protective puts open.
            </div>
          )}
        </div>
      </aside>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────

function PerTickerBars({
  items,
  maxAbs,
  onTickerClick,
  rowsByTicker,
  view,
}: {
  items: Item[];
  maxAbs: number;
  onTickerClick?: (ticker: string) => void;
  rowsByTicker: Map<string, PositionComputed>;
  view: 'overall' | 'stock';
}) {
  const W = 1000;
  const H = 380;
  const PAD_TOP = 14;
  const PAD_BOTTOM = 32;
  const AXIS_W = 48;
  const usableH = H - PAD_TOP - PAD_BOTTOM;
  const zeroY = PAD_TOP + usableH / 2;
  const halfH = usableH / 2;
  const barAreaW = W - AXIS_W;
  const slotW = items.length > 0 ? barAreaW / items.length : 0;
  const barW = Math.min(48, Math.max(8, slotW * 0.6));

  // Hover card — track ticker + cursor position. Position is in viewport
  // (clientX/Y) so the card lives in a portal and ignores any container's
  // overflow:hidden / transform contexts.
  const [hover, setHover] = useState<{ ticker: string; x: number; y: number } | null>(null);

  return (
    <>
      <svg
        viewBox={`0 0 ${W} ${H}`}
        preserveAspectRatio="xMidYMid meet"
        className="pnl-svg"
        onMouseLeave={() => setHover(null)}
      >
        <ChartGrid
          barAreaW={barAreaW}
          W={W}
          PAD_TOP={PAD_TOP}
          usableH={usableH}
          zeroY={zeroY}
          halfH={halfH}
          maxAbs={maxAbs}
        />
        {items.map((it, i) => {
          const cx = i * slotW + slotW / 2;
          const barHeight = maxAbs > 0 ? (Math.abs(it.pl) / maxAbs) * halfH : 0;
          const y = it.pl >= 0 ? zeroY - barHeight : zeroY;
          const fill = it.pl >= 0 ? 'var(--navi-neon)' : 'var(--navi-negative)';
          return (
            <g
              key={it.ticker}
              style={{ cursor: onTickerClick ? 'pointer' : 'default' }}
              onClick={() => onTickerClick?.(it.ticker)}
              onMouseEnter={(e) => setHover({ ticker: it.ticker, x: e.clientX, y: e.clientY })}
              onMouseMove={(e) => setHover({ ticker: it.ticker, x: e.clientX, y: e.clientY })}
            >
              <rect
                x={cx - barW / 2}
                y={y}
                width={barW}
                height={Math.max(2, barHeight)}
                fill={fill}
                rx="3"
              />
              {/* Invisible wider hit area so hover doesn't strobe on thin bars */}
              <rect
                x={cx - slotW / 2}
                y={PAD_TOP}
                width={slotW}
                height={usableH}
                fill="transparent"
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
      {hover && rowsByTicker.get(hover.ticker) && (
        <PositionHoverCard
          row={rowsByTicker.get(hover.ticker)!}
          x={hover.x}
          y={hover.y}
          view={view}
        />
      )}
    </>
  );
}

function OptionsDailyBars({
  events,
  tickerRank,
  rowsByTicker,
}: {
  events: CloseEvent[];
  tickerRank: Map<string, number>;
  rowsByTicker: Map<string, PositionComputed>;
}) {
  // Daily-bar hover — date + ticker + that day's signed P&L. Carries enough
  // ID to look up the row for richer details in the card.
  const [hover, setHover] = useState<{ ticker: string; date: string; value: number; x: number; y: number } | null>(null);
  const W = 1000;
  const H = 380;
  const PAD_TOP = 14;
  const PAD_BOTTOM = 32;
  const AXIS_W = 48;
  const usableH = H - PAD_TOP - PAD_BOTTOM;
  const zeroY = PAD_TOP + usableH / 2;
  const halfH = usableH / 2;
  const chartW = W - AXIS_W;

  // Group by date
  const byDate = useMemo(() => {
    const m = new Map<string, CloseEvent[]>();
    for (const e of events) {
      const arr = m.get(e.date) ?? [];
      arr.push(e);
      m.set(e.date, arr);
    }
    return m;
  }, [events]);

  const dates = useMemo(() => [...byDate.keys()].sort(), [byDate]);
  const dayMs = 86_400_000;
  const minMs = dates.length > 0 ? new Date(dates[0]).getTime() : 0;
  const maxMs =
    dates.length > 0 ? new Date(dates[dates.length - 1]).getTime() : 0;
  const span = Math.max(1, Math.round((maxMs - minMs) / dayMs)) + 2;

  // Y scale: max |pos sum| or |neg sum| across days
  const maxAbs = useMemo(() => {
    let m = 0;
    for (const arr of byDate.values()) {
      let pos = 0,
        neg = 0;
      for (const e of arr) {
        if (e.value > 0) pos += e.value;
        else neg += Math.abs(e.value);
      }
      m = Math.max(m, pos, neg);
    }
    return m;
  }, [byDate]);

  // X coord helper
  const xFor = (iso: string): number => {
    if (dates.length === 1) return chartW / 2;
    const t = new Date(iso).getTime();
    const dayIdx = Math.round((t - minMs) / dayMs) + 1;
    return (dayIdx / span) * chartW;
  };
  const barW = Math.min(18, Math.max(4, (chartW / span) * 0.65));

  // X-axis tick labels — show ~5 evenly-spaced dates
  const tickIndices = useMemo(() => {
    const n = Math.min(5, dates.length);
    if (n === 0) return [];
    if (n === 1) return [0];
    return Array.from({ length: n }, (_, i) =>
      Math.round((i * (dates.length - 1)) / (n - 1)),
    );
  }, [dates]);

  return (
    <>
    <svg
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="xMidYMid meet"
      className="pnl-svg"
      onMouseLeave={() => setHover(null)}
    >
      <ChartGrid
        barAreaW={chartW}
        W={W}
        PAD_TOP={PAD_TOP}
        usableH={usableH}
        zeroY={zeroY}
        halfH={halfH}
        maxAbs={maxAbs}
      />

      {/* Stacked daily bars */}
      {[...byDate.entries()].map(([date, list]) => {
        const cx = xFor(date);
        const pos = list
          .filter((e) => e.value > 0)
          .sort(
            (a, b) =>
              (tickerRank.get(a.ticker) ?? 99) -
              (tickerRank.get(b.ticker) ?? 99),
          );
        const neg = list
          .filter((e) => e.value < 0)
          .sort(
            (a, b) =>
              (tickerRank.get(a.ticker) ?? 99) -
              (tickerRank.get(b.ticker) ?? 99),
          );

        let posY = zeroY;
        let negY = zeroY;
        const rects: React.ReactNode[] = [];
        pos.forEach((e, i) => {
          const h = maxAbs > 0 ? (e.value / maxAbs) * halfH : 0;
          posY -= h;
          rects.push(
            <rect
              key={`${date}-p-${i}`}
              x={cx - barW / 2}
              y={posY}
              width={barW}
              height={Math.max(1, h)}
              fill={paletteColor(true, tickerRank.get(e.ticker) ?? 99)}
              rx="1"
              onMouseEnter={(ev) => setHover({ ticker: e.ticker, date, value: e.value, x: ev.clientX, y: ev.clientY })}
              onMouseMove={(ev) => setHover({ ticker: e.ticker, date, value: e.value, x: ev.clientX, y: ev.clientY })}
              style={{ cursor: 'pointer' }}
            />,
          );
        });
        neg.forEach((e, i) => {
          const h = maxAbs > 0 ? (Math.abs(e.value) / maxAbs) * halfH : 0;
          rects.push(
            <rect
              key={`${date}-n-${i}`}
              x={cx - barW / 2}
              y={negY}
              width={barW}
              height={Math.max(1, h)}
              fill={paletteColor(false, tickerRank.get(e.ticker) ?? 99)}
              rx="1"
              onMouseEnter={(ev) => setHover({ ticker: e.ticker, date, value: e.value, x: ev.clientX, y: ev.clientY })}
              onMouseMove={(ev) => setHover({ ticker: e.ticker, date, value: e.value, x: ev.clientX, y: ev.clientY })}
              style={{ cursor: 'pointer' }}
            />,
          );
          negY += h;
        });
        return <g key={date}>{rects}</g>;
      })}

      {/* X-axis date ticks */}
      {tickIndices.map((di) => {
        const date = dates[di];
        const cx = xFor(date);
        const label = new Date(date).toLocaleDateString('en-US', {
          month: 'short',
          day: 'numeric',
          timeZone: 'UTC',
        });
        return (
          <text
            key={date}
            x={cx}
            y={H - 10}
            textAnchor="middle"
            fill="var(--navi-fg2)"
            fontSize="11"
            fontFamily="var(--navi-font-mono)"
          >
            {label}
          </text>
        );
      })}
    </svg>
    {hover && (
      <DailyEventHoverCard
        ticker={hover.ticker}
        date={hover.date}
        value={hover.value}
        row={rowsByTicker.get(hover.ticker)}
        x={hover.x}
        y={hover.y}
      />
    )}
    </>
  );
}

function ChartGrid({
  barAreaW,
  W,
  PAD_TOP,
  usableH,
  zeroY,
  halfH,
  maxAbs,
}: {
  barAreaW: number;
  W: number;
  PAD_TOP: number;
  usableH: number;
  zeroY: number;
  halfH: number;
  maxAbs: number;
}) {
  return (
    <>
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
    </>
  );
}

function PutCostCoverage({
  putCost,
  stockLoss,
  realized,
  pct,
  putBurn,
  totalBurn,
}: {
  putCost: number;
  stockLoss: number;
  realized: number;
  pct: number;
  putBurn: number;
  totalBurn: number;
}) {
  const totalBurden = putCost + stockLoss;
  const max = Math.max(totalBurden, Math.abs(realized), 1);
  // Bar heights as % of bar-wrap height (which is bounded by CSS).
  const putH = (putCost / max) * 100;
  const lossH = (stockLoss / max) * 100;
  const realH = (Math.abs(realized) / max) * 100;
  return (
    <div className="pnl-coverage">
      <div className="pnl-coverage-pct-big">
        {pct.toFixed(0)}%
        <span className="pnl-coverage-pct-sub">Covered</span>
      </div>

      <div className="pnl-coverage-body">
        {/* Left: stacked burden (put cost + stock loss) */}
        <div className="pnl-cov-col">
          <div className="pnl-cov-bar-wrap">
            <div className="pnl-cov-stack">
              {stockLoss > 0 && (
                <div
                  className="pnl-cov-seg loss"
                  style={{ height: `${lossH}%` }}
                  title={`Stock loss · ${fmtUSD(stockLoss)}`}
                />
              )}
              <div
                className="pnl-cov-seg cost"
                style={{ height: `${putH}%` }}
                title={`Put cost · ${fmtUSD(putCost)}`}
              />
            </div>
          </div>
          <div className="pnl-cov-val">{fmtUSD(totalBurden)}</div>
          <div className="pnl-cov-mini-labels">
            <span className="pnl-cov-mini cost">
              {fmtCompact(putCost)} puts
            </span>
            {stockLoss > 0 && (
              <span className="pnl-cov-mini loss">
                {fmtCompact(stockLoss)} stock
              </span>
            )}
          </div>
        </div>

        {/* Right: realized (same scale, so the gap is visible) */}
        <div className="pnl-cov-col">
          <div className="pnl-cov-bar-wrap">
            <div
              className="pnl-cov-bar realized"
              style={{ height: `${realH}%` }}
            />
          </div>
          <div className="pnl-cov-val">
            {realized >= 0
              ? fmtUSD(realized)
              : '−' + fmtUSD(Math.abs(realized))}
          </div>
          <div className="pnl-cov-mini-labels">
            <span className="pnl-cov-mini realized">Realized</span>
          </div>
        </div>
      </div>

      {/* Weekly burn rates */}
      <div className="pnl-burn">
        <div className="pnl-burn-row">
          <span className="pnl-burn-dot cost" />
          <span className="pnl-burn-k">Put cost burn</span>
          <span className="pnl-burn-v">{fmtCompact(putBurn)}/wk</span>
        </div>
        <div className="pnl-burn-row">
          <span className="pnl-burn-dot total" />
          <span className="pnl-burn-k">Total to cover</span>
          <span className="pnl-burn-v">{fmtCompact(totalBurn)}/wk</span>
        </div>
      </div>
    </div>
  );
}

// ── Header sub-block: one of {Realized, Unrealized} with 3 stats ─────
function PnlSplitBlock({
  label, gains, losses, net,
}: {
  label: string;
  gains: number;
  losses: number;
  net: number;
}) {
  const lossStr = losses < 0 ? '−' + fmtUSD(Math.abs(losses)) : fmtUSD(losses);
  const netStr  = net   < 0 ? '−' + fmtUSD(Math.abs(net))    : fmtUSD(net);
  return (
    <div className="pnl-split-block">
      <div className="pnl-split-hd">{label}</div>
      <div className="pnl-split-row">
        <div className="pnl-chart-stat">
          <span className="pnl-chart-stat-k">↑ Gains</span>
          <span className="pnl-chart-stat-v up">{fmtUSD(gains)}</span>
        </div>
        <div className="pnl-chart-stat">
          <span className="pnl-chart-stat-k">↓ Losses</span>
          <span className="pnl-chart-stat-v down">{lossStr}</span>
        </div>
        <div className="pnl-chart-stat">
          <span className="pnl-chart-stat-k">Net</span>
          <span className={'pnl-chart-stat-v ' + (net >= 0 ? 'up' : 'down')}>{netStr}</span>
        </div>
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Hover cards — portaled to document.body so they escape the chart
// card's overflow:hidden and any transformed ancestors. Position is
// clamped to keep the card on-screen near the cursor.

function clampedPos(x: number, y: number, w: number, h: number): { left: number; top: number } {
  const pad = 8;
  // Default offset: bottom-right of cursor, flip if it would overflow.
  let left = x + 14;
  let top = y + 16;
  if (typeof window !== 'undefined') {
    if (left + w + pad > window.innerWidth) left = x - w - 14;
    if (top + h + pad > window.innerHeight) top = y - h - 16;
    if (left < pad) left = pad;
    if (top < pad) top = pad;
  }
  return { left, top };
}

/** Per-ticker P&L card — shown on hover in Overall / Stock views.
 *  Surfaces the full P&L breakdown that the chart's single bar collapses,
 *  plus position context (shares, market value, % of book, effective basis). */
function PositionHoverCard({
  row, x, y, view,
}: {
  row: PositionComputed;
  x: number;
  y: number;
  view: 'overall' | 'stock';
}) {
  const headlinePL = view === 'stock' ? row.pnl_dollar : row.overall_pl;
  const tone = headlinePL >= 0 ? 'pos' : 'neg';
  const sign = headlinePL >= 0 ? '+' : '−';
  const realized = (row.realized_pl ?? 0) + (row.realized_stock_pl ?? 0);
  const unrealized = row.pnl_dollar ?? 0;
  const pos = clampedPos(x, y, 280, 280);
  return createPortal(
    <div className="pnl-hover-card" style={{ left: pos.left, top: pos.top }}>
      <div className="pnl-hc-hd">
        <span className="pnl-hc-ticker">{row.ticker}</span>
        <span className="pnl-hc-sector">{row.sector || '—'}</span>
      </div>
      <div className={`pnl-hc-hero ${tone}`}>
        {sign}{fmtUSD(Math.abs(headlinePL))}
        <span className="pnl-hc-hero-sub">
          {view === 'stock' ? 'stock P&L (unrealized)' : 'overall P&L'}
        </span>
      </div>
      <div className="pnl-hc-rows">
        <Row k="Stock unrealized" v={`${unrealized >= 0 ? '+' : '−'}${fmtUSD(Math.abs(unrealized))}`} tone={unrealized >= 0 ? 'pos' : 'neg'} />
        <Row k="Realized P&L" v={`${realized >= 0 ? '+' : '−'}${fmtUSD(Math.abs(realized))}`} tone={realized >= 0 ? 'pos' : 'neg'} />
        {row.pnl_pct != null && isFinite(row.pnl_pct) && (
          <Row k="Stock %" v={`${row.pnl_pct >= 0 ? '+' : ''}${row.pnl_pct.toFixed(2)}%`} tone={row.pnl_pct >= 0 ? 'pos' : 'neg'} />
        )}
      </div>
      <div className="pnl-hc-rows muted">
        <Row k="Market value" v={fmtUSD(row.market_value)} />
        <Row k="% of book" v={`${row.pct_portfolio.toFixed(1)}%`} />
        <Row k="Avg cost" v={`$${row.avg_cost.toFixed(2)}`} />
        <Row k="Effective cost" v={`$${row.effective_cost.toFixed(2)}`} />
      </div>
    </div>,
    document.body,
  );
}

/** Daily-event hover card for the Options view. Stacked-segment hover
 *  surfaces date + ticker + that day's signed P&L, plus a quick
 *  position-context block from the row. */
function DailyEventHoverCard({
  ticker, date, value, row, x, y,
}: {
  ticker: string;
  date: string;
  value: number;
  row: PositionComputed | undefined;
  x: number;
  y: number;
}) {
  const tone = value >= 0 ? 'pos' : 'neg';
  const sign = value >= 0 ? '+' : '−';
  const dateLabel = new Date(date + 'T00:00:00Z').toLocaleDateString('en-US', {
    weekday: 'short', month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC',
  });
  const pos = clampedPos(x, y, 240, 200);
  return createPortal(
    <div className="pnl-hover-card" style={{ left: pos.left, top: pos.top }}>
      <div className="pnl-hc-hd">
        <span className="pnl-hc-ticker">{ticker}</span>
        <span className="pnl-hc-sector">{dateLabel}</span>
      </div>
      <div className={`pnl-hc-hero ${tone}`}>
        {sign}{fmtUSD(Math.abs(value))}
        <span className="pnl-hc-hero-sub">realized this day</span>
      </div>
      {row && (
        <div className="pnl-hc-rows muted">
          <Row k="Position" v={`${row.quantity} sh · ${fmtUSD(row.market_value)}`} />
          <Row k="% of book" v={`${row.pct_portfolio.toFixed(1)}%`} />
          <Row k="Realized P&L" v={`${row.realized_pl >= 0 ? '+' : '−'}${fmtUSD(Math.abs(row.realized_pl))}`} tone={row.realized_pl >= 0 ? 'pos' : 'neg'} />
        </div>
      )}
    </div>,
    document.body,
  );
}

function Row({ k, v, tone }: { k: string; v: string; tone?: 'pos' | 'neg' }) {
  return (
    <div className="pnl-hc-row">
      <span className="pnl-hc-k">{k}</span>
      <span className={`pnl-hc-v ${tone ?? ''}`}>{v}</span>
    </div>
  );
}
