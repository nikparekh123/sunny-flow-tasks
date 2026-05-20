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
    const byId = new Map<string, OptionTrade>();
    for (const t of trades) byId.set(t.id, t);
    const closesByOpen = new Map<string, OptionTrade[]>();
    for (const t of trades) {
      if (t.action !== 'close' || !t.closes_trade_id) continue;
      const arr = closesByOpen.get(t.closes_trade_id) ?? [];
      arr.push(t);
      closesByOpen.set(t.closes_trade_id, arr);
    }
    return (open: OptionTrade): number => {
      const closes = closesByOpen.get(open.id) ?? [];
      if (closes.length > 0) {
        return closes.reduce((s, c) => s + closeRealizedPL(c, open), 0);
      }
      const notional = open.contracts * 100 * open.premium;
      return open.direction === 'short' ? notional : -notional;
    };
  }, [trades]);

  // Column totals — sum of every cell's signed value at that column index.
  // Mirrors what the user sees in the matrix: realized for closed positions,
  // cash flow for live ones.
  const columnTotals = useMemo(() => {
    const totals = Array.from({ length: WEEK_COUNT }, () => 0);
    sorted.forEach((r) => {
      const opens = (tradesByTicker.get(r.ticker) ?? [])
        .filter((t) => t.action === 'open')
        .sort((a, b) => {
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
        if (i < WEEK_COUNT) totals[i] += slotValueForOpen(open);
      });
    });
    return totals;
  }, [sorted, tradesByTicker, WEEK_COUNT, slotValueForOpen]);

  const grandColumnTotal = columnTotals.reduce((s, v) => s + v, 0);
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
              {Array.from({ length: WEEK_COUNT }, (_, i) => (
                <th key={i} className={'gl-wk ' + (i === 0 ? 'this' : '')}>
                  <div className="gl-wk-l">{i + 1}</div>
                </th>
              ))}
              <th className="gl-tot">Realized</th>
            </tr>
          </thead>
          <tbody>
            {sorted.map((r) => {
              const trades = tradesByTicker.get(r.ticker) ?? [];
              const live = liveByTicker.get(r.ticker) ?? [];
              const realized = realizedByTicker.get(r.ticker) ?? 0;

              // One slot per POSITION (= one open trade + its matched
              // closes). When the user closes a position, the same column
              // updates to show realized P&L — no second column for the
              // close.
              //
              // Column order:
              //   1. Protective puts (long-direction puts) anchor the
              //      leftmost columns, oldest first. They're the long-
              //      running foundation of an income strategy and
              //      shouldn't shift when shorter-lived trades happen
              //      around them.
              //   2. Everything else (short calls, short puts, long calls)
              //      sorts newest first to the right.
              const isProtective = (t: OptionTrade) =>
                t.option_type === 'put' && t.direction === 'long';
              const opens = trades
                .filter((t) => t.action === 'open')
                .sort((a, b) => {
                  const aP = isProtective(a) ? 0 : 1;
                  const bP = isProtective(b) ? 0 : 1;
                  if (aP !== bP) return aP - bP;
                  // Within the protective bucket: oldest first → stable lanes.
                  // Within the other bucket: newest first.
                  return aP === 0
                    ? a.trade_date !== b.trade_date
                      ? a.trade_date.localeCompare(b.trade_date)
                      : a.created_at.localeCompare(b.created_at)
                    : b.trade_date !== a.trade_date
                      ? b.trade_date.localeCompare(a.trade_date)
                      : b.created_at.localeCompare(a.created_at);
                });
              // Build close index: open.id → list of closes against it
              const closesByOpen = new Map<string, OptionTrade[]>();
              for (const t of trades) {
                if (t.action !== 'close' || !t.closes_trade_id) continue;
                const arr = closesByOpen.get(t.closes_trade_id) ?? [];
                arr.push(t);
                closesByOpen.set(t.closes_trade_id, arr);
              }
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
                        className={'gl-cell ' + (slot ? 'filled ' : 'empty ') + (i === 0 ? 'this' : '')}
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
                <b>Column total</b>
                <div className="gl-pos-sub">{totalTradesCount} trades · realized + live</div>
              </td>
              {columnTotals.map((net, i) => (
                <td key={i} className={'gl-cell sum ' + (i === 0 ? 'this' : '')}>
                  {net !== 0 ? (
                    <div className="gl-cell-in">
                      <div className={'gl-cell-amt ' + (net < 0 ? 'down' : 'up')}>
                        {net >= 0 ? fmtCompact(net) : '−' + fmtCompact(Math.abs(net))}
                      </div>
                    </div>
                  ) : (
                    <span className="muted">—</span>
                  )}
                </td>
              ))}
              <td className="gl-tot">
                <div className={'gl-tot-amt ' + (grandColumnTotal < 0 ? 'down' : grandColumnTotal > 0 ? 'up' : '')}>
                  {grandColumnTotal >= 0
                    ? fmtUSD(grandColumnTotal)
                    : '−' + fmtUSD(Math.abs(grandColumnTotal))}
                </div>
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
