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
 * Unified weekly trade matrix.
 *
 * One row per position, one column per week. Each cell shows the NET cash
 * flow that week for that ticker (premium collected − premium paid) plus
 * coloured dots indicating which option types traded that week (C / P).
 *
 * Click a cell → opens the write modal pre-filled for that ticker. If the
 * ticker has live opens, the modal lands on the Close tab; otherwise on
 * the Open tab. Tickering the name opens the insight (read) view.
 */

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
const WEEK_OPTIONS = [12, 26, 52, 104] as const;
// First N columns are dedicated to LIVE opens (per row). Anything beyond
// is the closed/history zone.
const LIVE_COLS = 3;
type Weeks = typeof WEEK_OPTIONS[number];
const LS_TRADES_WEEKS = 'np:tradesWeeks';
function readWeeksLS(): Weeks {
  if (typeof window === 'undefined') return 52;
  const v = parseInt(window.localStorage.getItem(LS_TRADES_WEEKS) ?? '', 10);
  return (WEEK_OPTIONS as readonly number[]).includes(v) ? (v as Weeks) : 52;
}

function mondayOf(d: Date): Date {
  const x = new Date(d);
  const day = (x.getUTCDay() + 6) % 7;
  x.setUTCDate(x.getUTCDate() - day);
  x.setUTCHours(0, 0, 0, 0);
  return x;
}
function weekIdxOf(iso: string, todayWeek: Date): number {
  const d = new Date(iso + 'T12:00:00Z');
  return Math.round((todayWeek.getTime() - mondayOf(d).getTime()) / WEEK_MS);
}

type StatusFilter = 'all' | 'active' | 'open' | 'closed';

interface Props {
  rows: PositionComputed[];
  tradesByTicker: Map<string, OptionTrade[]>;
  liveByTicker: Map<string, LiveOption[]>;
  realizedByTicker: Map<string, number>;
  onTickerClick: (ticker: string) => void;
  /** Cell click. The page decides which tab to open based on live state. */
  onCellClick: (ticker: string, weekIdx: number) => void;
}

interface CellAggregate {
  collected_call: number;
  collected_put: number;
  paid_call: number;
  paid_put: number;
  trade_count: number;
}

export function TradesLogMatrix({
  rows,
  tradesByTicker,
  liveByTicker,
  realizedByTicker,
  onTickerClick,
  onCellClick,
}: Props) {
  const [filter, setFilter] = useState<StatusFilter>('all');
  const [weeks, setWeeksState] = useState<Weeks>(() => readWeeksLS());
  const setWeeks = (w: Weeks) => {
    setWeeksState(w);
    try { window.localStorage.setItem(LS_TRADES_WEEKS, String(w)); } catch { /* private */ }
  };
  const WEEK_COUNT = weeks;
  const todayWeek = useMemo(() => mondayOf(new Date()), []);

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

  // Sort by realized P&L desc — most-productive tickers float to the top.
  const sorted = useMemo(
    () =>
      [...filtered].sort(
        (a, b) => (realizedByTicker.get(b.ticker) ?? 0) - (realizedByTicker.get(a.ticker) ?? 0),
      ),
    [filtered, realizedByTicker],
  );

  // Helper used by both the column totals (footer) and per-row rendering:
  // returns the slot's signed value (cash flow for live positions,
  // realized P&L for closed pairs).
  const isProtectiveTrade = (t: OptionTrade) =>
    t.option_type === 'put' && t.direction === 'long';
  const slotValueForOpen = useMemo(() => {
    // closes_trade_id index, built once across every ticker's trades.
    const closesByOpen = new Map<string, OptionTrade[]>();
    for (const list of tradesByTicker.values()) {
      for (const t of list) {
        if (t.action !== 'close' || !t.closes_trade_id) continue;
        const arr = closesByOpen.get(t.closes_trade_id) ?? [];
        arr.push(t);
        closesByOpen.set(t.closes_trade_id, arr);
      }
    }
    return (open: OptionTrade): number => {
      const closes = closesByOpen.get(open.id) ?? [];
      if (closes.length > 0) {
        return closes.reduce((s, c) => s + closeRealizedPL(c, open), 0);
      }
      const notional = open.contracts * 100 * open.premium;
      return open.direction === 'short' ? notional : -notional;
    };
  }, [tradesByTicker]);

  // Per-ticker protective-put cost (absolute cash spent buying long puts).
  // This is the "burn" the income strategy has to cover. Used as the
  // denominator everywhere — right column ("realized as % of put cost")
  // and footer ("collected as % of put cost").
  const putCostByTicker = useMemo(() => {
    const m = new Map<string, number>();
    for (const [ticker, list] of tradesByTicker) {
      let cost = 0;
      for (const t of list) {
        if (t.action === 'open' && t.option_type === 'put' && t.direction === 'long') {
          cost += t.contracts * 100 * t.premium;
        }
      }
      m.set(ticker, cost);
    }
    return m;
  }, [tradesByTicker]);

  // Column-wise put cost (long-put opens) and "slot net" (everything else).
  // Uses the SAME live-first sort that the body uses, so each footer cell
  // is literally the sum of the cells above it.
  const { columnPutCost, columnSlotNet } = useMemo(() => {
    const putCost = Array.from({ length: WEEK_COUNT }, () => 0);
    const slotNet = Array.from({ length: WEEK_COUNT }, () => 0);

    // Close index across all trades (same as the row builder uses).
    const closesByOpenGlobal = new Map<string, OptionTrade[]>();
    for (const list of tradesByTicker.values()) {
      for (const t of list) {
        if (t.action !== 'close' || !t.closes_trade_id) continue;
        const arr = closesByOpenGlobal.get(t.closes_trade_id) ?? [];
        arr.push(t);
        closesByOpenGlobal.set(t.closes_trade_id, arr);
      }
    }
    const isFullyClosed = (open: OptionTrade): boolean => {
      const closes = closesByOpenGlobal.get(open.id) ?? [];
      return closes.reduce((s, c) => s + c.contracts, 0) >= open.contracts;
    };
    const mostRecentCloseDate = (open: OptionTrade): string => {
      const closes = closesByOpenGlobal.get(open.id) ?? [];
      if (closes.length === 0) return '';
      return closes.map((c) => c.trade_date).sort().reverse()[0];
    };

    sorted.forEach((r) => {
      const opens = (tradesByTicker.get(r.ticker) ?? [])
        .filter((t) => t.action === 'open')
        .sort((a, b) => {
          const aClosed = isFullyClosed(a) ? 1 : 0;
          const bClosed = isFullyClosed(b) ? 1 : 0;
          if (aClosed !== bClosed) return aClosed - bClosed;
          if (aClosed === 1) {
            const ad = mostRecentCloseDate(a);
            const bd = mostRecentCloseDate(b);
            if (ad !== bd) return bd.localeCompare(ad);
            return b.created_at.localeCompare(a.created_at);
          }
          const aP = isProtectiveTrade(a) ? 0 : 1;
          const bP = isProtectiveTrade(b) ? 0 : 1;
          if (aP !== bP) return aP - bP;
          return aP === 0
            ? a.trade_date !== b.trade_date
              ? a.trade_date.localeCompare(b.trade_date)
              : a.created_at.localeCompare(b.created_at)
            : b.trade_date !== a.trade_date
              ? b.trade_date.localeCompare(a.trade_date)
              : b.created_at.localeCompare(a.created_at);
        });
      opens.forEach((open, i) => {
        if (i >= WEEK_COUNT) return;
        if (isProtectiveTrade(open) && !isFullyClosed(open)) {
          putCost[i] += open.contracts * 100 * open.premium;
        } else {
          slotNet[i] += slotValueForOpen(open);
        }
      });
    });
    return { columnPutCost: putCost, columnSlotNet: slotNet };
  }, [sorted, tradesByTicker, WEEK_COUNT, slotValueForOpen]);

  const grandPutCost = useMemo(
    () => Array.from(putCostByTicker.values()).reduce((s, v) => s + v, 0),
    [putCostByTicker],
  );
  const weeklyBurn = WEEK_COUNT > 0 ? grandPutCost / WEEK_COUNT : 0;
  const grandRealized = useMemo(
    () => sorted.reduce((s, r) => s + (realizedByTicker.get(r.ticker) ?? 0), 0),
    [sorted, realizedByTicker],
  );
  const totalTradesCount = useMemo(
    () =>
      sorted.reduce((s, r) => s + (tradesByTicker.get(r.ticker)?.length ?? 0), 0),
    [sorted, tradesByTicker],
  );

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
          {WEEK_OPTIONS.map((w) => (
            <button
              key={w}
              className={weeks === w ? 'on' : ''}
              onClick={() => setWeeks(w)}
              title={`Show ${w} weeks`}
            >
              {w}w
            </button>
          ))}
        </div>
      </div>

      <div className="gl-scroll">
        <table className="gl-table">
          <thead>
            <tr>
              <th className="gl-pos">Position</th>
              {Array.from({ length: WEEK_COUNT }, (_, i) => {
                const zone = i < LIVE_COLS ? 'live-zone' : 'closed-zone';
                return (
                  <th key={i} className={`gl-wk ${zone} ` + (i === 0 ? 'this' : '')}>
                    <div className="gl-wk-l">{i + 1}</div>
                    {i < LIVE_COLS && <div className="gl-wk-sub">live</div>}
                  </th>
                );
              })}
              <th className="gl-tot">Realized</th>
            </tr>
          </thead>
          <tbody>
            {sorted.map((r) => {
              const trades = tradesByTicker.get(r.ticker) ?? [];
              const live = liveByTicker.get(r.ticker) ?? [];
              const realized = realizedByTicker.get(r.ticker) ?? 0;

              // Build close index FIRST so the sort can decide live vs
              // fully-closed.
              const closesByOpen = new Map<string, OptionTrade[]>();
              for (const t of trades) {
                if (t.action !== 'close' || !t.closes_trade_id) continue;
                const arr = closesByOpen.get(t.closes_trade_id) ?? [];
                arr.push(t);
                closesByOpen.set(t.closes_trade_id, arr);
              }
              const isFullyClosed = (open: OptionTrade): boolean => {
                const closes = closesByOpen.get(open.id) ?? [];
                const closedQty = closes.reduce((s, c) => s + c.contracts, 0);
                return closedQty >= open.contracts;
              };

              // One slot per POSITION (= one open trade + its matched
              // closes). The closing flow doesn't add a new column; the
              // same column flips state.
              //
              // Column order (per row):
              //   1. LIVE opens first (leftmost). Within live:
              //        – protective puts oldest first (stable lanes)
              //        – everything else newest first
              //   2. CLOSED opens after, most-recently-closed first.
              //
              // This keeps live work anchored in cols 1..N (where N =
              // LIVE_COLS by convention) and pushes history rightward.
              const isProtective = (t: OptionTrade) =>
                t.option_type === 'put' && t.direction === 'long';
              const mostRecentCloseDate = (open: OptionTrade): string => {
                const closes = closesByOpen.get(open.id) ?? [];
                if (closes.length === 0) return '';
                return closes
                  .map((c) => c.trade_date)
                  .sort()
                  .reverse()[0];
              };
              const opens = trades
                .filter((t) => t.action === 'open')
                .sort((a, b) => {
                  const aClosed = isFullyClosed(a) ? 1 : 0;
                  const bClosed = isFullyClosed(b) ? 1 : 0;
                  if (aClosed !== bClosed) return aClosed - bClosed; // live first
                  if (aClosed === 1) {
                    // Both closed → most-recently-closed first
                    const ad = mostRecentCloseDate(a);
                    const bd = mostRecentCloseDate(b);
                    if (ad !== bd) return bd.localeCompare(ad);
                    return b.created_at.localeCompare(a.created_at);
                  }
                  // Both live → existing protective-put rule, then dates
                  const aP = isProtective(a) ? 0 : 1;
                  const bP = isProtective(b) ? 0 : 1;
                  if (aP !== bP) return aP - bP;
                  return aP === 0
                    ? a.trade_date !== b.trade_date
                      ? a.trade_date.localeCompare(b.trade_date)
                      : a.created_at.localeCompare(b.created_at)
                    : b.trade_date !== a.trade_date
                      ? b.trade_date.localeCompare(a.trade_date)
                      : b.created_at.localeCompare(a.created_at);
                });
              const slotFor = (idx: number) => {
                const open = opens[idx];
                if (!open) return null;
                const closes = closesByOpen.get(open.id) ?? [];
                const closedContracts = closes.reduce((s, c) => s + c.contracts, 0);
                const isFullyClosed = closedContracts >= open.contracts;
                const isPartial = closes.length > 0 && !isFullyClosed;
                if (closes.length > 0) {
                  // Realized P&L summed across matched closes.
                  const realized = closes.reduce((s, c) => s + closeRealizedPL(c, open), 0);
                  return { trade: open, signed: realized, isFullyClosed, isPartial };
                }
                // Live (no closes yet): show the open's signed cash flow.
                const notional = open.contracts * 100 * open.premium;
                const isCashIn = open.direction === 'short';
                return { trade: open, signed: isCashIn ? notional : -notional, isFullyClosed: false, isPartial: false };
              };

              return (
                <tr key={r.ticker} className={r.status === 'closed' ? 'closed-row' : ''}>
                  <td className="gl-pos">
                    <span
                      className="ticker clickable"
                      onClick={() => onTickerClick(r.ticker)}
                    >
                      {r.ticker}
                    </span>
                    {r.status === 'closed' && <span className="status-pill closed">closed</span>}
                    <div className="gl-pos-sub">
                      {r.sector}
                      {live.length > 0 && <span className="gl-live-count"> · {live.length} live</span>}
                    </div>
                  </td>

                  {Array.from({ length: WEEK_COUNT }, (_, i) => {
                    const slot = slotFor(i);
                    const stateLabel = !slot
                      ? ''
                      : slot.isFullyClosed
                        ? 'closed'
                        : slot.isPartial
                          ? 'partial'
                          : 'live';
                    return (
                      <td
                        key={i}
                        className={
                          'gl-cell ' +
                          (slot ? 'filled ' : 'empty ') +
                          (i < LIVE_COLS ? 'live-zone ' : 'closed-zone ') +
                          (i === 0 ? 'this' : '')
                        }
                        onClick={() => onCellClick(r.ticker, i)}
                        title={slot
                          ? `${slot.trade.direction} ${slot.trade.option_type} ${slot.trade.contracts}× $${slot.trade.strike} · opened ${slot.trade.trade_date} · ${stateLabel} · ${fmtUSD(slot.signed)}`
                          : 'tap to open a new position'
                        }
                      >
                        {slot ? (
                          <div className="gl-cell-in">
                            <div className={'gl-cell-amt ' + (slot.signed < 0 ? 'down' : slot.signed > 0 ? 'up' : '')}>
                              {slot.signed >= 0 ? fmtCompact(slot.signed) : '−' + fmtCompact(Math.abs(slot.signed))}
                            </div>
                            <div className="gl-cell-chips">
                              <span
                                className={
                                  'gl-dot rk-' + (slot.trade.option_type === 'put' ? 'p' : 'c') +
                                  (slot.signed < 0 ? ' neg' : '')
                                }
                              />
                              <span className={'gl-cell-state ' + stateLabel}>{stateLabel}</span>
                            </div>
                          </div>
                        ) : (
                          <span className="gl-plus">+</span>
                        )}
                      </td>
                    );
                  })}

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
                    {(() => {
                      const putCost = putCostByTicker.get(r.ticker) ?? 0;
                      if (putCost <= 0) return null;
                      const pct = (realized / putCost) * 100;
                      return (
                        <div className="gl-tot-sub">
                          {pct >= 0 ? '+' : ''}{pct.toFixed(0)}% of {fmtCompact(putCost)}
                        </div>
                      );
                    })()}
                  </td>
                </tr>
              );
            })}
            {sorted.length === 0 && (
              <tr>
                <td colSpan={WEEK_COUNT + 2} style={{ textAlign: 'center', padding: 32, color: 'var(--navi-fg3)' }}>
                  No positions match this filter
                </td>
              </tr>
            )}
          </tbody>
          <tfoot>
            <tr className="gl-foot">
              <td className="gl-pos">
                <b>Total</b>
                <div className="gl-pos-sub">{totalTradesCount} trades · realized + live</div>
              </td>
              {Array.from({ length: WEEK_COUNT }, (_, i) => {
                const putCost = columnPutCost[i];
                const slotNet = columnSlotNet[i];
                if (putCost > 0) {
                  // Protective-put column — show cost (neg) and weekly burn.
                  return (
                    <td key={i} className={'gl-cell sum ' + (i < LIVE_COLS ? 'live-zone ' : 'closed-zone ') + (i === 0 ? 'this' : '')}>
                      <div className="gl-cell-in">
                        <div className="gl-cell-amt down">
                          −{fmtCompact(putCost)}
                        </div>
                        <div className="gl-cell-chips">
                          <span className="gl-cell-state">
                            {fmtCompact(putCost / WEEK_COUNT)}/wk
                          </span>
                        </div>
                      </div>
                    </td>
                  );
                }
                if (slotNet !== 0) {
                  // Sum of the cells above (realized + live cash flow).
                  const pct = grandPutCost > 0 ? (slotNet / grandPutCost) * 100 : 0;
                  const isPos = slotNet >= 0;
                  return (
                    <td key={i} className={'gl-cell sum ' + (i < LIVE_COLS ? 'live-zone ' : 'closed-zone ') + (i === 0 ? 'this' : '')}>
                      <div className="gl-cell-in">
                        <div className={'gl-cell-amt ' + (isPos ? 'up' : 'down')}>
                          {isPos ? fmtCompact(slotNet) : '−' + fmtCompact(Math.abs(slotNet))}
                        </div>
                        <div className="gl-cell-chips">
                          <span className="gl-cell-state">
                            {isPos ? '' : '−'}{Math.abs(pct).toFixed(0)}%
                          </span>
                        </div>
                      </div>
                    </td>
                  );
                }
                return (
                  <td key={i} className={'gl-cell sum ' + (i < LIVE_COLS ? 'live-zone ' : 'closed-zone ') + (i === 0 ? 'this' : '')}>
                    <span className="muted">—</span>
                  </td>
                );
              })}
              <td className="gl-tot">
                <div className={'gl-tot-amt ' + (grandRealized < 0 ? 'down' : grandRealized > 0 ? 'up' : '')}>
                  {grandRealized >= 0
                    ? fmtUSD(grandRealized)
                    : '−' + fmtUSD(Math.abs(grandRealized))}
                </div>
                {grandPutCost > 0 && (
                  <div className="gl-tot-sub">
                    {((grandRealized / grandPutCost) * 100).toFixed(0)}% of {fmtCompact(grandPutCost)} · {fmtCompact(weeklyBurn)}/wk
                  </div>
                )}
              </td>
            </tr>
          </tfoot>
        </table>
      </div>
    </div>
  );
}

// Silence unused-import lint when nothing imports closeRealizedPL directly.
void {} as unknown as typeof closeRealizedPL;
