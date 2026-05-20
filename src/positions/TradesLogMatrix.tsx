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
 * Trades matrix — each column is a SINGLE TRADE on that ticker, ordered
 * by trade_date (newest first). Date-agnostic: column 1 is the most
 * recent trade on the ticker, column 2 is the one before that, etc.
 *
 * Each cell shows the trade's signed cash flow + an "open"/"close"
 * label so the user can scan what just happened without thinking
 * about which week it was.
 *
 * Realized column on the right = Σ realized P&L for the ticker.
 */

type StatusFilter = 'all' | 'active' | 'open' | 'closed';

// How many trade columns to render. We compute the max trade count across
// visible tickers and cap it here so the table can't blow out indefinitely.
const MAX_COLUMNS = 30;

interface Props {
  rows: PositionComputed[];
  tradesByTicker: Map<string, OptionTrade[]>;
  liveByTicker: Map<string, LiveOption[]>;
  realizedByTicker: Map<string, number>;
  onTickerClick: (ticker: string) => void;
  onCellClick: (ticker: string, weekIdx: number) => void;
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

  // Sort tickers by realized P&L desc (matches Timeline).
  const sorted = useMemo(
    () =>
      [...filtered].sort(
        (a, b) => (realizedByTicker.get(b.ticker) ?? 0) - (realizedByTicker.get(a.ticker) ?? 0),
      ),
    [filtered, realizedByTicker],
  );

  // Build a per-ticker trade list (newest first) + look up the open trade
  // for each close so we can compute realized P&L per cell.
  const tradeListsByTicker = useMemo(() => {
    const m = new Map<string, Array<{ trade: OptionTrade; open: OptionTrade | null }>>();
    for (const r of sorted) {
      const trades = (tradesByTicker.get(r.ticker) ?? []).slice();
      const byId = new Map(trades.map((t) => [t.id, t]));
      const sortedTrades = trades.sort((a, b) => b.trade_date.localeCompare(a.trade_date));
      const enriched = sortedTrades.map((t) => ({
        trade: t,
        open: t.action === 'close' && t.closes_trade_id ? byId.get(t.closes_trade_id) ?? null : null,
      }));
      m.set(r.ticker, enriched);
    }
    return m;
  }, [sorted, tradesByTicker]);

  // Decide how many trade columns to render: the largest trade count across
  // any visible ticker, capped at MAX_COLUMNS. Minimum 1 so the header
  // always has at least one column.
  const colCount = useMemo(() => {
    let max = 1;
    for (const list of tradeListsByTicker.values()) {
      if (list.length > max) max = list.length;
    }
    return Math.min(max, MAX_COLUMNS);
  }, [tradeListsByTicker]);

  // Grand realized across the visible set.
  const grandRealized = useMemo(
    () => sorted.reduce((s, r) => s + (realizedByTicker.get(r.ticker) ?? 0), 0),
    [sorted, realizedByTicker],
  );
  const totalTrades = useMemo(
    () => Array.from(tradeListsByTicker.values()).reduce((s, l) => s + l.length, 0),
    [tradeListsByTicker],
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
      </div>

      <div className="gl-scroll">
        <table className="gl-table">
          <thead>
            <tr>
              <th className="gl-pos">Position</th>
              {Array.from({ length: colCount }, (_, i) => (
                <th key={i} className={'gl-wk ' + (i === 0 ? 'this' : '')}>
                  <div className="gl-wk-l">#{i + 1}</div>
                </th>
              ))}
              <th className="gl-tot">Realized</th>
            </tr>
          </thead>
          <tbody>
            {sorted.map((r) => {
              const list = tradeListsByTicker.get(r.ticker) ?? [];
              const live = liveByTicker.get(r.ticker) ?? [];
              const realized = realizedByTicker.get(r.ticker) ?? 0;

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

                  {Array.from({ length: colCount }, (_, i) => {
                    const entry = list[i];
                    if (!entry) {
                      return (
                        <td key={i} className={'gl-cell empty ' + (i === 0 ? 'this' : '')} />
                      );
                    }
                    const t = entry.trade;
                    const isCashIn =
                      (t.action === 'open' && t.direction === 'short') ||
                      (t.action === 'close' && t.direction === 'long');
                    const notional = t.contracts * 100 * t.premium;
                    const signed = isCashIn ? notional : -notional;
                    const realizedHere = t.action === 'close' && entry.open
                      ? closeRealizedPL(t, entry.open)
                      : 0;
                    const amtCls = signed > 0 ? 'up' : signed < 0 ? 'down' : '';
                    return (
                      <td
                        key={i}
                        className={'gl-cell filled ' + (i === 0 ? 'this' : '')}
                        onClick={() => onCellClick(r.ticker, i)}
                        title={`${t.action} ${t.direction} ${t.option_type} ${t.contracts}× $${t.strike} @ $${t.premium}/sh · ${t.trade_date}`}
                      >
                        <div className="gl-cell-in">
                          <div className={'gl-cell-amt ' + amtCls}>
                            {signed >= 0 ? fmtCompact(signed) : '−' + fmtCompact(Math.abs(signed))}
                          </div>
                          <div className="gl-cell-action">
                            {t.action === 'open' ? 'open' : 'close'}
                            <span className="gl-cell-type">
                              {t.option_type === 'put' ? 'P' : 'C'}
                            </span>
                            {realizedHere !== 0 && (
                              <span className={'gl-cell-realized ' + (realizedHere > 0 ? 'up' : 'down')}>
                                {realizedHere > 0 ? '+' : '−'}{fmtCompact(Math.abs(realizedHere))}
                              </span>
                            )}
                          </div>
                        </div>
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
                <td colSpan={colCount + 2} style={{ textAlign: 'center', padding: 32, color: 'var(--navi-fg3)' }}>
                  No positions match this filter
                </td>
              </tr>
            )}
          </tbody>
          <tfoot>
            <tr className="gl-foot">
              <td className="gl-pos">
                <b>Portfolio</b>
                <div className="gl-pos-sub">{totalTrades} trades</div>
              </td>
              <td colSpan={colCount} />
              <td className="gl-tot">
                <div className={'gl-tot-amt ' + (grandRealized < 0 ? 'down' : grandRealized > 0 ? 'up' : '')}>
                  {grandRealized === 0 ? '$0' : grandRealized >= 0 ? fmtUSD(grandRealized) : '−' + fmtUSD(Math.abs(grandRealized))}
                </div>
              </td>
            </tr>
          </tfoot>
        </table>
      </div>
    </div>
  );
}
