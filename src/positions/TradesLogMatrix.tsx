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

  // Weekly totals across visible rows.
  const weeklyTotals = useMemo(() => {
    const totals = Array.from({ length: WEEK_COUNT }, () => ({
      collected: 0, paid: 0, n: 0,
    }));
    sorted.forEach((r) => {
      const trades = tradesByTicker.get(r.ticker) ?? [];
      trades.forEach((t) => {
        const w = weekIdxOf(t.trade_date, todayWeek);
        if (w < 0 || w >= WEEK_COUNT) return;
        const notional = t.contracts * 100 * t.premium;
        const isCashIn =
          (t.action === 'open' && t.direction === 'short') ||
          (t.action === 'close' && t.direction === 'long');
        if (isCashIn) totals[w].collected += notional;
        else          totals[w].paid      += notional;
        totals[w].n += 1;
      });
    });
    return totals;
  }, [sorted, tradesByTicker, todayWeek, WEEK_COUNT]);

  const grand = {
    collected: weeklyTotals.reduce((s, t) => s + t.collected, 0),
    paid:      weeklyTotals.reduce((s, t) => s + t.paid, 0),
    n:         weeklyTotals.reduce((s, t) => s + t.n, 0),
  };
  const grandNet = grand.collected - grand.paid;

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

              // Per-week aggregate for this ticker.
              const byWeek: Record<number, CellAggregate> = {};
              const byId = new Map<string, OptionTrade>();
              for (const t of trades) byId.set(t.id, t);
              trades.forEach((t) => {
                const w = weekIdxOf(t.trade_date, todayWeek);
                if (w < 0 || w >= WEEK_COUNT) return;
                if (!byWeek[w]) byWeek[w] = {
                  collected_call: 0, collected_put: 0,
                  paid_call: 0, paid_put: 0, trade_count: 0,
                };
                const notional = t.contracts * 100 * t.premium;
                const isCashIn =
                  (t.action === 'open' && t.direction === 'short') ||
                  (t.action === 'close' && t.direction === 'long');
                const bucket = isCashIn
                  ? (t.option_type === 'call' ? 'collected_call' : 'collected_put')
                  : (t.option_type === 'call' ? 'paid_call' : 'paid_put');
                byWeek[w][bucket] += notional;
                byWeek[w].trade_count += 1;
              });

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
                    const c = byWeek[i];
                    const net = c ? (c.collected_call + c.collected_put - c.paid_call - c.paid_put) : 0;
                    return (
                      <td
                        key={i}
                        className={'gl-cell ' + (c ? 'filled ' : 'empty ') + (i === 0 ? 'this' : '')}
                        onClick={() => onCellClick(r.ticker, i)}
                        title={c
                          ? `${c.trade_count} trade${c.trade_count === 1 ? '' : 's'} · net ${fmtUSD(net)}`
                          : 'tap to open a new position'
                        }
                      >
                        {c ? (
                          <div className="gl-cell-in">
                            <div className={'gl-cell-amt ' + (net < 0 ? 'down' : net > 0 ? 'up' : '')}>
                              {net >= 0 ? fmtCompact(net) : '−' + fmtCompact(Math.abs(net))}
                            </div>
                            <div className="gl-cell-chips">
                              {(c.collected_call > 0 || c.paid_call > 0) && (
                                <span className={'gl-dot rk-c' + (c.collected_call < c.paid_call ? ' neg' : '')} />
                              )}
                              {(c.collected_put > 0 || c.paid_put > 0) && (
                                <span className={'gl-dot rk-p' + (c.collected_put < c.paid_put ? ' neg' : '')} />
                              )}
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
                <b>Weekly net</b>
                <div className="gl-pos-sub">{grand.n} trades</div>
              </td>
              {weeklyTotals.map((t, i) => {
                const net = t.collected - t.paid;
                return (
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
                );
              })}
              <td className="gl-tot">
                <div className={'gl-tot-amt ' + (grandNet < 0 ? 'down' : grandNet > 0 ? 'up' : '')}>
                  {grandNet >= 0 ? fmtUSD(grandNet) : '−' + fmtUSD(Math.abs(grandNet))}
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
