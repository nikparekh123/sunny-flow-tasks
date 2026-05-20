import { Fragment, useMemo, useState } from 'react';
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
 * Timeline view — same shell as the Trades matrix (gl-table classes,
 * same toolbar with filter pills + timeframe selector), but each row is
 * a single contract drawn as a Gantt-style bar over daily columns
 * instead of weekly aggregate cells.
 *
 * Visual model per ticker:
 *   [group header row — ticker, sector, share count]
 *   [shares row — quiet teal bar covering the whole range]
 *   [option row × N — one row per OPEN trade, with bar from open → close]
 *   [subtotal row — realized, live count, put obligation]
 *
 * Day columns are rendered as actual <th>/<td> cells with day-of-month
 * tickmarks. Bars are absolutely positioned inside a colSpan wrapper
 * cell so they can stretch across days without breaking the table grid.
 */

const DAY_MS = 24 * 60 * 60 * 1000;
const DAY_OPTIONS = [60, 120, 180, 365] as const; // total visible days (past+future)
type Days = typeof DAY_OPTIONS[number];
const LS_DAYS = 'np:timelineDays';
function readDaysLS(): Days {
  if (typeof window === 'undefined') return 120;
  const v = parseInt(window.localStorage.getItem(LS_DAYS) ?? '', 10);
  return (DAY_OPTIONS as readonly number[]).includes(v) ? (v as Days) : 120;
}
/** Ratio of past:future days within the visible window. ~40% past, 60% future
 *  is a sensible default for an options trader watching upcoming expiries. */
function splitDays(total: Days): { past: number; future: number } {
  const past = Math.round(total * 0.4);
  return { past, future: total - past };
}

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

type StatusFilter = 'all' | 'active' | 'open' | 'closed';

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
  remaining: number;
  firstCloseDate: string | null;
  realized: number;
  is_live: boolean;
}

function resolveTrades(trades: OptionTrade[]): ResolvedTrade[] {
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
  const [filter, setFilter] = useState<StatusFilter>('all');
  const [days, setDaysState] = useState<Days>(() => readDaysLS());
  const setDays = (d: Days) => {
    setDaysState(d);
    try { window.localStorage.setItem(LS_DAYS, String(d)); } catch { /* private */ }
  };
  const { past: DAYS_PAST, future: DAYS_FUTURE } = splitDays(days);
  const totalDays = DAYS_PAST + DAYS_FUTURE;

  const today = useMemo(() => startOfDayUTC(new Date()), []);
  const rangeStart = useMemo(() => new Date(today.getTime() - DAYS_PAST * DAY_MS), [today, DAYS_PAST]);
  const rangeStartIso = rangeStart.toISOString().slice(0, 10);
  const todayIso = today.toISOString().slice(0, 10);

  const counts = useMemo(
    () => ({
      all: rows.length,
      active: rows.filter((r) => (tradesByTicker.get(r.ticker)?.length ?? 0) > 0).length,
      open: rows.filter((r) => r.status === 'open').length,
      closed: rows.filter((r) => r.status === 'closed').length,
    }),
    [rows, tradesByTicker],
  );

  const filtered = useMemo(() => {
    if (filter === 'active') return rows.filter((r) => (tradesByTicker.get(r.ticker)?.length ?? 0) > 0);
    if (filter === 'open')   return rows.filter((r) => r.status === 'open');
    if (filter === 'closed') return rows.filter((r) => r.status === 'closed');
    return rows;
  }, [rows, filter, tradesByTicker]);

  // Same sort as Trades matrix: realized desc.
  const sorted = useMemo(
    () =>
      [...filtered].sort(
        (a, b) => (realizedByTicker.get(b.ticker) ?? 0) - (realizedByTicker.get(a.ticker) ?? 0),
      ),
    [filtered, realizedByTicker],
  );

  // For each day index, label which to render. We show the day-of-month
  // every 3 days at 60d zoom, less frequently at wider zooms.
  const tickInterval = days <= 60 ? 3 : days <= 120 ? 7 : days <= 180 ? 14 : 30;

  // Convert an ISO date to a day-index inside the visible window.
  const dx = (iso: string) =>
    Math.max(0, Math.min(totalDays, daysBetween(rangeStartIso, iso)));
  const todayDx = DAYS_PAST;

  return (
    <div className="gl-wrap">
      {/* Toolbar — same shell as Trades matrix */}
      <div className="gl-toolbar">
        <div className="np-status-filter">
          <button className={filter === 'all' ? 'on' : ''} onClick={() => setFilter('all')}>
            All <span className="ct">{counts.all}</span>
          </button>
          <button className={filter === 'active' ? 'on' : ''} onClick={() => setFilter('active')}>
            Has trades <span className="ct">{counts.active}</span>
          </button>
          <button className={filter === 'open' ? 'on' : ''} onClick={() => setFilter('open')}>
            Open <span className="ct">{counts.open}</span>
          </button>
          <button className={filter === 'closed' ? 'on' : ''} onClick={() => setFilter('closed')}>
            Closed <span className="ct">{counts.closed}</span>
          </button>
        </div>
        <div className="gl-timeframe">
          {DAY_OPTIONS.map((d) => (
            <button
              key={d}
              className={days === d ? 'on' : ''}
              onClick={() => setDays(d)}
              title={`Show ${d} days`}
            >
              {d}d
            </button>
          ))}
        </div>
      </div>

      <div className="gl-scroll">
        <table className="gl-table tl-table">
          <thead>
            <tr>
              <th className="gl-pos">Position</th>
              {Array.from({ length: totalDays }, (_, i) => {
                const d = new Date(rangeStart.getTime() + i * DAY_MS);
                const dayOfMonth = d.getUTCDate();
                const showTick = i % tickInterval === 0;
                const isToday = i === todayDx;
                const isMonthStart = dayOfMonth === 1;
                return (
                  <th
                    key={i}
                    className={
                      'gl-wk tl-day-th' +
                      (isToday ? ' today' : '') +
                      (isMonthStart ? ' month-start' : '')
                    }
                    title={d.toISOString().slice(0, 10)}
                  >
                    {showTick && (
                      <div className="tl-day-tick">
                        {isMonthStart
                          ? d.toLocaleString('en-US', { month: 'short', timeZone: 'UTC' })
                          : dayOfMonth}
                      </div>
                    )}
                  </th>
                );
              })}
              <th className="gl-tot">Realized</th>
            </tr>
          </thead>
          <tbody>
            {sorted.map((r) => {
              const trades = tradesByTicker.get(r.ticker) ?? [];
              const resolved = resolveTrades(trades);
              const live = liveByTicker.get(r.ticker) ?? [];
              const realized = realizedByTicker.get(r.ticker) ?? 0;
              const obligation = live.reduce(
                (s, lo) =>
                  s + (lo.open.option_type === 'put' && lo.open.direction === 'short'
                    ? lo.remaining_contracts * 100 * lo.open.strike
                    : 0),
                0,
              );
              const isClosedPos = r.status === 'closed';

              return (
                <Fragment key={r.ticker}>
                  {/* Group header */}
                  <tr className="tl-group-row">
                    <td colSpan={totalDays + 2}>
                      <span
                        className="ticker clickable"
                        onClick={() => onTickerClick(r.ticker)}
                      >
                        {r.ticker}
                      </span>
                      {isClosedPos && <span className="status-pill closed">closed</span>}
                      <span className="tl-group-meta">
                        {r.sector}
                        {r.quantity > 0 && ` · ${r.quantity.toLocaleString()} sh @ ${fmtUSD2(r.avg_cost)}`}
                      </span>
                    </td>
                  </tr>

                  {/* Shares row */}
                  {r.quantity > 0 && (
                    <tr className="tl-track-row tl-shares">
                      <td className="gl-pos">
                        <span className="tl-row-glyph shares">S</span>
                        shares
                      </td>
                      <td colSpan={totalDays} className="tl-track-cell">
                        <div className="tl-track">
                          <div
                            className="tl-bar tl-bar-shares"
                            style={{
                              left: `calc(${(0 / totalDays) * 100}%)`,
                              width: `calc(${(totalDays / totalDays) * 100}%)`,
                            }}
                            title={`${r.quantity.toLocaleString()} sh @ ${fmtUSD2(r.avg_cost)}`}
                          >
                            <span className="tl-bar-label">
                              {r.quantity.toLocaleString()} · basis {fmtUSD2(r.avg_cost)}
                            </span>
                          </div>
                          <TodayLine percent={(todayDx / totalDays) * 100} />
                        </div>
                      </td>
                      <td className="gl-tot">
                        <div className="gl-tot-amt">{fmtCompact(r.market_value)}</div>
                      </td>
                    </tr>
                  )}

                  {/* Option rows */}
                  {resolved.map((rt) => {
                    const isShort = rt.open.direction === 'short';
                    const isPut = rt.open.option_type === 'put';
                    const openOffset = dx(rt.open.trade_date);
                    const expiryOffset = dx(rt.open.expiry);
                    const closeOffset = rt.firstCloseDate ? dx(rt.firstCloseDate) : null;
                    const liveEnd = closeOffset != null
                      ? closeOffset
                      : Math.min(todayDx, expiryOffset);
                    const liveWidth = Math.max(0, liveEnd - openOffset);
                    const grayStart = closeOffset;
                    const grayWidth = grayStart != null ? Math.max(0, expiryOffset - grayStart) : 0;
                    const futureWidth = closeOffset == null
                      ? Math.max(0, expiryOffset - Math.max(openOffset, todayDx))
                      : 0;
                    const liveColorClass = isShort
                      ? (isPut ? 'tl-bar-short-put' : 'tl-bar-short-call')
                      : (isPut ? 'tl-bar-long-put' : 'tl-bar-long-call');
                    const labelSign = isShort ? '−' : '+';
                    const realizedColor = rt.realized > 0 ? 'up' : rt.realized < 0 ? 'down' : '';

                    return (
                      <tr
                        key={rt.open.id}
                        className="tl-track-row"
                        onClick={() => onBarClick(r.ticker, rt.open.id)}
                      >
                        <td className="gl-pos">
                          <span className={'tl-row-glyph ' + (isShort ? 'short' : 'long')}>
                            {isPut ? 'P' : 'C'}
                          </span>
                          {labelSign}{rt.open.contracts} ${rt.open.strike}
                          <span className="tl-row-sub"> · exp {rt.open.expiry}</span>
                        </td>
                        <td colSpan={totalDays} className="tl-track-cell">
                          <div className="tl-track">
                            {liveWidth > 0 && (
                              <div
                                className={'tl-bar ' + liveColorClass}
                                style={{
                                  left: `${(openOffset / totalDays) * 100}%`,
                                  width: `${(liveWidth / totalDays) * 100}%`,
                                }}
                                title={`Open ${rt.open.trade_date} · ${rt.open.contracts}× @ $${rt.open.premium}/sh`}
                              />
                            )}
                            {grayStart != null && grayWidth > 0 && (
                              <div
                                className="tl-bar tl-bar-closed"
                                style={{
                                  left: `${(grayStart / totalDays) * 100}%`,
                                  width: `${(grayWidth / totalDays) * 100}%`,
                                }}
                                title={`Closed ${rt.firstCloseDate} · realized ${rt.realized >= 0 ? '+' : '−'}${fmtUSD(Math.abs(rt.realized))}`}
                              >
                                <span className={'tl-bar-realized ' + realizedColor}>
                                  {rt.realized >= 0 ? '+' : '−'}{fmtCompact(Math.abs(rt.realized))}
                                </span>
                              </div>
                            )}
                            {futureWidth > 0 && (
                              <div
                                className="tl-bar tl-bar-future"
                                style={{
                                  left: `${(Math.max(openOffset, todayDx) / totalDays) * 100}%`,
                                  width: `${(futureWidth / totalDays) * 100}%`,
                                }}
                                title={`Until expiry ${rt.open.expiry}`}
                              >
                                <span className="tl-bar-arrow">►</span>
                              </div>
                            )}
                            <TodayLine percent={(todayDx / totalDays) * 100} />
                          </div>
                        </td>
                        <td className="gl-tot">
                          {rt.is_live ? (
                            <div className="gl-tot-amt" style={{ color: 'var(--navi-fg2)' }}>
                              {rt.remaining}× live
                            </div>
                          ) : (
                            <div className={'gl-tot-amt ' + realizedColor}>
                              {rt.realized >= 0 ? '+' : '−'}{fmtCompact(Math.abs(rt.realized))}
                            </div>
                          )}
                        </td>
                      </tr>
                    );
                  })}

                  {/* Subtotal */}
                  <tr className="tl-subtotal-row">
                    <td colSpan={totalDays + 2}>
                      <b>{r.ticker} subtotal</b>
                      <span className="tl-subtotal-sep"> · </span>
                      <span className={realized < 0 ? 'down' : 'up'}>
                        realized {realized >= 0 ? '+' : '−'}{fmtCompact(Math.abs(realized))}
                      </span>
                      {live.length > 0 && (
                        <>
                          <span className="tl-subtotal-sep"> · </span>
                          <span>{live.length} live</span>
                        </>
                      )}
                      {obligation > 0 && (
                        <>
                          <span className="tl-subtotal-sep"> · </span>
                          <span>put oblig {fmtCompact(obligation)}</span>
                        </>
                      )}
                    </td>
                  </tr>
                </Fragment>
              );
            })}

            {sorted.length === 0 && (
              <tr>
                <td colSpan={totalDays + 2} style={{ textAlign: 'center', padding: 32, color: 'var(--navi-fg3)' }}>
                  No positions match this filter
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

/** Today's vertical neon line drawn inside a track. Absolutely positioned
 *  so each row can show its own copy without z-index gymnastics. */
function TodayLine({ percent }: { percent: number }) {
  return (
    <div
      className="tl-today-line"
      style={{ left: `${percent}%` }}
      title="Today"
    />
  );
}
