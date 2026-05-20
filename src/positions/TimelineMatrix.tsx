import { useMemo, useState } from 'react';
import {
  closeRealizedPL,
  fmtCompact,
  fmtUSD,
  type LiveOption,
  type OptionTrade,
  type PositionComputed,
} from './types';

/**
 * Timeline view — same row layout as the Trades matrix.
 *
 * One row per ticker (no group headers, no subtotal rows, no shares row).
 * Inside the row's day strip every option contract is rendered as a thin
 * Gantt-style bar, absolutely positioned and stacked vertically so multiple
 * contracts on the same ticker sit at different y-offsets without
 * overlapping.
 *
 * Same toolbar (filter pills + timeframe selector), same `Realized` column
 * on the right, same `Portfolio` footer row across the bottom — Timeline
 * reads as a different view of the same table.
 */

const DAY_MS = 24 * 60 * 60 * 1000;
const DAY_OPTIONS = [60, 120, 180, 365] as const;
type Days = typeof DAY_OPTIONS[number];
const LS_DAYS = 'np:timelineDays';
function readDaysLS(): Days {
  if (typeof window === 'undefined') return 120;
  const v = parseInt(window.localStorage.getItem(LS_DAYS) ?? '', 10);
  return (DAY_OPTIONS as readonly number[]).includes(v) ? (v as Days) : 120;
}
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

  const sorted = useMemo(
    () =>
      [...filtered].sort(
        (a, b) => (realizedByTicker.get(b.ticker) ?? 0) - (realizedByTicker.get(a.ticker) ?? 0),
      ),
    [filtered, realizedByTicker],
  );

  const tickInterval = days <= 60 ? 3 : days <= 120 ? 7 : days <= 180 ? 14 : 30;
  const dx = (iso: string) =>
    Math.max(0, Math.min(totalDays, daysBetween(rangeStartIso, iso)));
  const todayDx = DAYS_PAST;

  return (
    <div className="gl-wrap">
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
              // Vertical slots inside the row. Max 4 visible; if more
              // contracts exist they all share the bottom slot.
              const MAX_SLOTS = 4;
              const slotCount = Math.min(MAX_SLOTS, Math.max(1, resolved.length));

              return (
                <tr
                  key={r.ticker}
                  className={r.status === 'closed' ? 'closed-row' : ''}
                  onClick={() => onTickerClick(r.ticker)}
                >
                  <td className="gl-pos">
                    <span className="ticker clickable">{r.ticker}</span>
                    {r.status === 'closed' && <span className="status-pill closed">closed</span>}
                    <div className="gl-pos-sub">
                      {r.sector}
                      {live.length > 0 && <span className="gl-live-count"> · {live.length} live</span>}
                    </div>
                  </td>

                  <td colSpan={totalDays} className="tl-track-cell">
                    <div className="tl-track">
                      {resolved.map((rt, idx) => {
                        const slot = Math.min(idx, slotCount - 1);
                        const isShort = rt.open.direction === 'short';
                        const isPut = rt.open.option_type === 'put';
                        const openOffset = dx(rt.open.trade_date);
                        const expiryOffset = dx(rt.open.expiry);
                        const closeOffset = rt.firstCloseDate ? dx(rt.firstCloseDate) : null;
                        const liveEnd = closeOffset != null
                          ? closeOffset
                          : Math.min(todayDx, expiryOffset);
                        const liveWidth = Math.max(0, liveEnd - openOffset);
                        const grayWidth = closeOffset != null ? Math.max(0, expiryOffset - closeOffset) : 0;
                        const futureWidth = closeOffset == null
                          ? Math.max(0, expiryOffset - Math.max(openOffset, todayDx))
                          : 0;
                        const liveColorClass = isShort
                          ? (isPut ? 'tl-bar-short-put' : 'tl-bar-short-call')
                          : (isPut ? 'tl-bar-long-put' : 'tl-bar-long-call');
                        const realizedColor = rt.realized > 0 ? 'up' : rt.realized < 0 ? 'down' : '';
                        // Position by slot — each slot is 6px tall with 2px gap.
                        const slotTopPercent = (slot / slotCount) * 100;
                        const slotHeightPercent = 100 / slotCount;
                        const onClick = (e: React.MouseEvent) => {
                          e.stopPropagation();
                          onBarClick(r.ticker, rt.open.id);
                        };

                        return (
                          <div
                            key={rt.open.id}
                            className="tl-slot"
                            style={{
                              top: `${slotTopPercent}%`,
                              height: `${slotHeightPercent}%`,
                            }}
                          >
                            {liveWidth > 0 && (
                              <div
                                className={'tl-bar ' + liveColorClass}
                                style={{
                                  left: `${(openOffset / totalDays) * 100}%`,
                                  width: `${(liveWidth / totalDays) * 100}%`,
                                }}
                                title={`Open ${rt.open.trade_date} · ${rt.open.contracts}× ${isPut ? 'P' : 'C'} $${rt.open.strike} @ $${rt.open.premium}/sh`}
                                onClick={onClick}
                              />
                            )}
                            {closeOffset != null && grayWidth > 0 && (
                              <div
                                className="tl-bar tl-bar-closed"
                                style={{
                                  left: `${(closeOffset / totalDays) * 100}%`,
                                  width: `${(grayWidth / totalDays) * 100}%`,
                                }}
                                title={`Closed ${rt.firstCloseDate} · realized ${rt.realized >= 0 ? '+' : '−'}${fmtUSD(Math.abs(rt.realized))}`}
                                onClick={onClick}
                              >
                                <span className={'tl-bar-realized ' + realizedColor}>
                                  {rt.realized >= 0 ? '+' : '−'}{fmtCompact(Math.abs(rt.realized))}
                                </span>
                              </div>
                            )}
                            {futureWidth > 0 && (
                              <div
                                className={'tl-bar tl-bar-future ' + (isShort ? 'tl-future-short' : 'tl-future-long')}
                                style={{
                                  left: `${(Math.max(openOffset, todayDx) / totalDays) * 100}%`,
                                  width: `${(futureWidth / totalDays) * 100}%`,
                                }}
                                title={`Until expiry ${rt.open.expiry}`}
                                onClick={onClick}
                              />
                            )}
                          </div>
                        );
                      })}
                      <TodayLine percent={(todayDx / totalDays) * 100} />
                    </div>
                  </td>

                  <td className="gl-tot">
                    <div className={'gl-tot-amt ' + (realized < 0 ? 'down' : realized > 0 ? 'up' : '')}>
                      {realized === 0 ? (
                        <span style={{ color: 'var(--navi-fg5)' }}>—</span>
                      ) : realized >= 0 ? (
                        fmtUSD(realized)
                      ) : (
                        '−' + fmtUSD(Math.abs(realized))
                      )}
                    </div>
                  </td>
                </tr>
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

          {sorted.length > 0 && (() => {
            let grandRealized = 0;
            let grandLive = 0;
            for (const r of sorted) {
              grandRealized += realizedByTicker.get(r.ticker) ?? 0;
              const live = liveByTicker.get(r.ticker) ?? [];
              grandLive += live.length;
            }
            return (
              <tfoot>
                <tr className="gl-foot">
                  <td className="gl-pos">
                    <b>Portfolio</b>
                    <div className="gl-pos-sub">{sorted.length} positions · {grandLive} live</div>
                  </td>
                  <td colSpan={totalDays} className="tl-foot-spacer" />
                  <td className="gl-tot">
                    <div className={'gl-tot-amt ' + (grandRealized < 0 ? 'down' : grandRealized > 0 ? 'up' : '')}>
                      {grandRealized === 0 ? '$0' : grandRealized > 0 ? fmtUSD(grandRealized) : '−' + fmtUSD(Math.abs(grandRealized))}
                    </div>
                  </td>
                </tr>
              </tfoot>
            );
          })()}
        </table>
      </div>
    </div>
  );
}

/** Today's vertical neon line drawn inside the track. */
function TodayLine({ percent }: { percent: number }) {
  return (
    <div
      className="tl-today-line"
      style={{ left: `${percent}%` }}
      title="Today"
    />
  );
}
