import { useMemo, useState } from 'react';
import {
  closeRealizedPL,
  fmtCompact,
  fmtUSD,
  fmtUSD2,
  type LiveOption,
  type OptionTrade,
  type PositionComputed,
} from './types';

/**
 * Timeline view — Gantt-style ledger of every options trade across a
 * rolling 150-day window (past 60 days + next 90).
 *
 * Each ticker is a "group":
 *    [TICKER header row]
 *    [shares row]            — quiet teal bar covering the visible range
 *    [option row × N]        — one row per OPEN trade
 *    [ticker subtotal row]
 *
 * Each option row carries a bar from open date → (close date OR expiry).
 * After close the bar fades to gray with the realized P&L floating near
 * the close marker. Today is a vertical neon line.
 *
 * Layout uses CSS grid for the header strip; bars inside each row are
 * absolutely positioned in a single horizontal track. Horizontal scroll
 * inside the .tl-scroll wrapper.
 */

const DAY_MS = 24 * 60 * 60 * 1000;
const DAYS_PAST = 60;
const DAYS_FUTURE = 90;
const DAY_WIDTH = 14; // px per day column
const LEFT_COL = 180; // ticker / row label
const RIGHT_COL = 110;

function startOfDayUTC(d: Date): Date {
  const x = new Date(d);
  x.setUTCHours(0, 0, 0, 0);
  return x;
}
function daysBetween(aIso: string, bIso: string): number {
  const a = startOfDayUTC(new Date(aIso + 'T00:00:00Z'));
  const b = startOfDayUTC(new Date(bIso + 'T00:00:00Z'));
  return Math.round((b.getTime() - a.getTime()) / DAY_MS);
}

interface Props {
  rows: PositionComputed[];
  tradesByTicker: Map<string, OptionTrade[]>;
  liveByTicker: Map<string, LiveOption[]>;
  realizedByTicker: Map<string, number>;
  onTickerClick: (ticker: string) => void;
  onBarClick: (ticker: string, openId: string) => void;
}

interface ResolvedTrade {
  open: OptionTrade;
  closes: OptionTrade[];
  /** open contracts − Σ closes.contracts. >0 = still live. */
  remaining: number;
  /** When the FIRST close happened (if any). The bar drains here. */
  firstCloseDate: string | null;
  /** Aggregate realized P&L across all closes against this open. */
  realized: number;
  is_live: boolean;
}

function resolveTrades(trades: OptionTrade[]): ResolvedTrade[] {
  const byId = new Map<string, OptionTrade>();
  for (const t of trades) byId.set(t.id, t);

  const closesByOpen = new Map<string, OptionTrade[]>();
  for (const t of trades) {
    if (t.action === 'close' && t.closes_trade_id) {
      const arr = closesByOpen.get(t.closes_trade_id) ?? [];
      arr.push(t);
      closesByOpen.set(t.closes_trade_id, arr);
    }
  }

  const out: ResolvedTrade[] = [];
  for (const t of trades) {
    if (t.action !== 'open') continue;
    const closes = (closesByOpen.get(t.id) ?? [])
      .sort((a, b) => a.trade_date.localeCompare(b.trade_date));
    const closedContracts = closes.reduce((s, c) => s + c.contracts, 0);
    const remaining = t.contracts - closedContracts;
    const realized = closes.reduce((s, c) => s + closeRealizedPL(c, t), 0);
    out.push({
      open: t,
      closes,
      remaining,
      firstCloseDate: closes[0]?.trade_date ?? null,
      realized,
      is_live: remaining > 0,
    });
  }
  // Order: live first, then by open date desc.
  return out.sort((a, b) => {
    if (a.is_live !== b.is_live) return a.is_live ? -1 : 1;
    return b.open.trade_date.localeCompare(a.open.trade_date);
  });
}

export function TimelineMatrix({
  rows,
  tradesByTicker,
  liveByTicker,
  realizedByTicker,
  onTickerClick,
  onBarClick,
}: Props) {
  // Hide tickers with no positions on the timeline by default; let the user
  // toggle to see everything.
  const [showEmpty, setShowEmpty] = useState(false);

  const today = useMemo(() => startOfDayUTC(new Date()), []);
  const rangeStart = useMemo(() => new Date(today.getTime() - DAYS_PAST * DAY_MS), [today]);
  const totalDays = DAYS_PAST + DAYS_FUTURE;
  const stripWidth = totalDays * DAY_WIDTH;

  const todayIso = today.toISOString().slice(0, 10);
  const rangeStartIso = rangeStart.toISOString().slice(0, 10);

  // Filter tickers to ones with trades OR holdings.
  const visible = useMemo(() => {
    return rows.filter((r) => {
      const trades = tradesByTicker.get(r.ticker) ?? [];
      return showEmpty ? true : trades.length > 0 || r.quantity > 0;
    });
  }, [rows, tradesByTicker, showEmpty]);

  // Pre-compute date axis labels — every 7 days a tick, plus month markers.
  const tickDays: number[] = [];
  for (let i = 0; i <= totalDays; i += 7) tickDays.push(i);

  // Month boundary positions for stronger gridlines.
  const monthBoundaries: number[] = [];
  for (let i = 0; i <= totalDays; i++) {
    const d = new Date(rangeStart.getTime() + i * DAY_MS);
    if (d.getUTCDate() === 1) monthBoundaries.push(i);
  }

  const todayOffset = DAYS_PAST; // by construction

  return (
    <div className="tl-wrap">
      <div className="tl-toolbar">
        <div className="np-status-filter">
          <button className={!showEmpty ? 'on' : ''} onClick={() => setShowEmpty(false)}>
            With activity <span className="ct">{visible.length}</span>
          </button>
          <button className={showEmpty ? 'on' : ''} onClick={() => setShowEmpty(true)}>
            Show all <span className="ct">{rows.length}</span>
          </button>
        </div>
        <div className="tl-legend">
          <span><span className="tl-swatch short" /> Short open</span>
          <span><span className="tl-swatch long" /> Long open</span>
          <span><span className="tl-swatch closed" /> Closed</span>
          <span><span className="tl-swatch shares" /> Shares</span>
        </div>
      </div>

      <div className="tl-scroll">
        <div
          className="tl-canvas"
          style={{ gridTemplateColumns: `${LEFT_COL}px ${stripWidth}px ${RIGHT_COL}px` }}
        >
          {/* Date header */}
          <div className="tl-corner" />
          <div className="tl-axis">
            {/* Month markers along the top */}
            {monthBoundaries.map((d) => {
              const date = new Date(rangeStart.getTime() + d * DAY_MS);
              const month = date.toLocaleString('en-US', { month: 'short', timeZone: 'UTC' });
              return (
                <div
                  key={'m' + d}
                  className="tl-month-tick"
                  style={{ left: d * DAY_WIDTH }}
                >
                  {month} {date.getUTCFullYear() !== today.getUTCFullYear() ? `'${String(date.getUTCFullYear()).slice(2)}` : ''}
                </div>
              );
            })}
            {/* Day-week ticks below */}
            {tickDays.map((d) => {
              const date = new Date(rangeStart.getTime() + d * DAY_MS);
              return (
                <div
                  key={'t' + d}
                  className="tl-day-tick"
                  style={{ left: d * DAY_WIDTH }}
                >
                  {date.getUTCDate()}
                </div>
              );
            })}
            {/* Today vertical line */}
            <div
              className="tl-today-line"
              style={{ left: todayOffset * DAY_WIDTH + DAY_WIDTH / 2 }}
              title={`Today · ${todayIso}`}
            />
          </div>
          <div className="tl-totals-head">Realized</div>

          {/* Ticker groups */}
          {visible.map((r) => {
            const trades = tradesByTicker.get(r.ticker) ?? [];
            const resolved = resolveTrades(trades);
            const live = liveByTicker.get(r.ticker) ?? [];
            const realized = realizedByTicker.get(r.ticker) ?? 0;
            const liveCount = live.length;
            const obligation = live.reduce(
              (s, lo) =>
                s + (lo.open.option_type === 'put' && lo.open.direction === 'short'
                  ? lo.remaining_contracts * 100 * lo.open.strike
                  : 0),
              0,
            );

            return (
              <TickerGroup
                key={r.ticker}
                position={r}
                resolved={resolved}
                rangeStartIso={rangeStartIso}
                todayIso={todayIso}
                totalDays={totalDays}
                realized={realized}
                liveCount={liveCount}
                obligation={obligation}
                onTickerClick={onTickerClick}
                onBarClick={onBarClick}
              />
            );
          })}

          {visible.length === 0 && (
            <>
              <div />
              <div style={{ padding: 32, textAlign: 'center', color: 'var(--navi-fg3)', fontSize: 13 }}>
                No positions with options activity in the visible window.
              </div>
              <div />
            </>
          )}
        </div>
      </div>
    </div>
  );
}

function TickerGroup({
  position, resolved, rangeStartIso, todayIso, totalDays,
  realized, liveCount, obligation, onTickerClick, onBarClick,
}: {
  position: PositionComputed;
  resolved: ResolvedTrade[];
  rangeStartIso: string;
  todayIso: string;
  totalDays: number;
  realized: number;
  liveCount: number;
  obligation: number;
  onTickerClick: (ticker: string) => void;
  onBarClick: (ticker: string, openId: string) => void;
}) {
  const isClosedPos = position.status === 'closed';
  return (
    <>
      {/* Group header */}
      <div className="tl-group-hd-l">
        <span
          className="tl-ticker clickable"
          onClick={() => onTickerClick(position.ticker)}
        >
          {position.ticker}
        </span>
        {isClosedPos && <span className="status-pill closed">closed</span>}
        <span className="tl-group-meta">{position.sector}</span>
      </div>
      <div className="tl-group-hd-c" />
      <div className="tl-group-hd-r">
        {position.quantity > 0 && <span>{position.quantity.toLocaleString()} sh</span>}
      </div>

      {/* Shares row */}
      {position.quantity > 0 && (
        <>
          <div className="tl-row-label">
            <span className="tl-row-glyph shares">●</span>
            shares
          </div>
          <div className="tl-row-track">
            <div
              className="tl-bar tl-bar-shares"
              style={{ left: 0, width: totalDays * DAY_WIDTH }}
              title={`${position.quantity.toLocaleString()} sh @ ${fmtUSD2(position.avg_cost)}`}
            >
              <span className="tl-bar-label">
                {position.quantity.toLocaleString()} · {fmtUSD2(position.avg_cost)} basis
              </span>
            </div>
          </div>
          <div className="tl-row-right">
            {fmtCompact(position.market_value)}
          </div>
        </>
      )}

      {/* Option rows — one per open trade */}
      {resolved.map((rt) => {
        const isShort = rt.open.direction === 'short';
        const isPut = rt.open.option_type === 'put';
        const dx = (iso: string) => Math.max(0, Math.min(totalDays, daysBetween(rangeStartIso, iso)));
        const openOffset = dx(rt.open.trade_date);
        const expiryOffset = dx(rt.open.expiry);
        const closeOffset = rt.firstCloseDate ? dx(rt.firstCloseDate) : null;
        // Live segment: from open → (firstClose OR min(today, expiry))
        const liveEnd = closeOffset != null
          ? closeOffset
          : Math.min(dx(todayIso), expiryOffset);
        const liveWidth = Math.max(0, liveEnd - openOffset);
        // Gray segment: from close → expiry (only if closed)
        const grayStart = closeOffset != null ? closeOffset : null;
        const grayWidth = grayStart != null ? Math.max(0, expiryOffset - grayStart) : 0;
        // Future segment: from today → expiry (only if not closed and expiry in future)
        const futureWidth = closeOffset == null
          ? Math.max(0, expiryOffset - Math.max(openOffset, dx(todayIso)))
          : 0;
        const liveColorClass = isShort
          ? (isPut ? 'tl-bar-short-put' : 'tl-bar-short-call')
          : (isPut ? 'tl-bar-long-put' : 'tl-bar-long-call');

        const labelSign = isShort ? '−' : '+';
        const rowLabel = `${labelSign}${rt.open.contracts} ${isPut ? 'P' : 'C'} $${rt.open.strike}`;
        const realizedColor = rt.realized > 0 ? 'pos' : rt.realized < 0 ? 'neg' : '';

        return (
          <div key={rt.open.id} className="tl-row-group" style={{ display: 'contents' }}>
            <div className="tl-row-label" onClick={() => onBarClick(position.ticker, rt.open.id)}>
              <span className={'tl-row-glyph ' + (isShort ? 'short' : 'long')}>
                {isPut ? 'P' : 'C'}
              </span>
              {rowLabel}
              <span className="tl-row-sub">exp {rt.open.expiry}</span>
            </div>
            <div className="tl-row-track" onClick={() => onBarClick(position.ticker, rt.open.id)}>
              {/* Live colored segment */}
              {liveWidth > 0 && (
                <div
                  className={'tl-bar ' + liveColorClass}
                  style={{ left: openOffset * DAY_WIDTH, width: liveWidth * DAY_WIDTH }}
                  title={`Open ${rt.open.trade_date} · ${rt.open.contracts}× @ $${rt.open.premium}/sh`}
                >
                  <span className="tl-bar-marker tl-bar-marker-open">●</span>
                </div>
              )}
              {/* Gray closed-portion ghost bar */}
              {grayStart != null && grayWidth > 0 && (
                <div
                  className="tl-bar tl-bar-closed"
                  style={{ left: grayStart * DAY_WIDTH, width: grayWidth * DAY_WIDTH }}
                  title={`Closed ${rt.firstCloseDate} · realized ${rt.realized >= 0 ? '+' : '−'}${fmtUSD(Math.abs(rt.realized))}`}
                >
                  <span className="tl-bar-marker tl-bar-marker-close">●</span>
                  <span className={'tl-bar-realized ' + realizedColor}>
                    {rt.realized >= 0 ? '+' : '−'}{fmtUSD(Math.abs(rt.realized))}
                  </span>
                </div>
              )}
              {/* Future arrow indicating expiry */}
              {futureWidth > 0 && (
                <div
                  className="tl-bar tl-bar-future"
                  style={{
                    left: Math.max(openOffset, DAYS_PAST) * DAY_WIDTH,
                    width: futureWidth * DAY_WIDTH,
                  }}
                  title={`Until expiry ${rt.open.expiry}`}
                >
                  <span className="tl-bar-arrow">►</span>
                </div>
              )}
            </div>
            <div className="tl-row-right">
              {rt.is_live ? (
                <span className="tl-row-live">
                  {rt.remaining}× live
                </span>
              ) : (
                <span className={'tl-row-realized ' + realizedColor}>
                  {rt.realized >= 0 ? '+' : '−'}{fmtCompact(Math.abs(rt.realized))}
                </span>
              )}
            </div>
          </div>
        );
      })}

      {/* Ticker subtotal */}
      <div className="tl-row-subtotal-l">
        <b>{position.ticker} subtotal</b>
      </div>
      <div className="tl-row-subtotal-c">
        <span>realized {realized >= 0 ? '+' : '−'}{fmtCompact(Math.abs(realized))}</span>
        {liveCount > 0 && <span> · {liveCount} live</span>}
        {obligation > 0 && <span> · put oblig {fmtCompact(obligation)}</span>}
      </div>
      <div className="tl-row-subtotal-r" />
    </>
  );
}
