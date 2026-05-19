import { useMemo, useState } from 'react';
import {
  fmtCompact,
  fmtUSD,
  type ExpenseEntry,
  type PositionComputed,
} from './types';

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
const WEEK_COUNT = 12;

function mondayOf(d: Date): Date {
  const x = new Date(d);
  const day = (x.getUTCDay() + 6) % 7;
  x.setUTCDate(x.getUTCDate() - day);
  x.setUTCHours(0, 0, 0, 0);
  return x;
}

function weekIdxOf(iso: string, todayWeek: Date): number {
  const d = new Date(iso + 'T12:00:00Z');
  const w = mondayOf(d);
  return Math.round((todayWeek.getTime() - w.getTime()) / WEEK_MS);
}

type StatusFilter = 'all' | 'with-expenses' | 'open' | 'closed';

interface Props {
  rows: PositionComputed[];
  expensesByTicker: Map<string, ExpenseEntry[]>;
  onCellClick: (ticker: string, weekIdx: number) => void;
  onTickerClick: (ticker: string) => void;
}

export function ExpensesLogMatrix({ rows, expensesByTicker, onCellClick, onTickerClick }: Props) {
  const [filter, setFilter] = useState<StatusFilter>('all');
  const todayWeek = useMemo(() => mondayOf(new Date()), []);

  const counts = useMemo(
    () => ({
      all: rows.length,
      withExpenses: rows.filter((r) => r.expenses_total !== 0).length,
      open: rows.filter((r) => r.status === 'open').length,
      closed: rows.filter((r) => r.status === 'closed').length,
    }),
    [rows],
  );

  const filtered = useMemo(() => {
    if (filter === 'with-expenses') return rows.filter((r) => r.expenses_total !== 0);
    if (filter === 'open') return rows.filter((r) => r.status === 'open');
    if (filter === 'closed') return rows.filter((r) => r.status === 'closed');
    return rows;
  }, [rows, filter]);

  const sorted = useMemo(
    () => [...filtered].sort((a, b) => b.expenses_total - a.expenses_total),
    [filtered],
  );

  const weeklyTotals = useMemo(() => {
    const totals = Array.from({ length: WEEK_COUNT }, () => ({
      stock: 0, call: 0, put: 0, total: 0, n: 0,
    }));
    sorted.forEach((r) => {
      const entries = expensesByTicker.get(r.ticker) ?? [];
      entries.forEach((g) => {
        const w = weekIdxOf(g.expense_date, todayWeek);
        if (w >= 0 && w < WEEK_COUNT) {
          totals[w][g.source] += g.amount;
          totals[w].total += g.amount;
          totals[w].n += 1;
        }
      });
    });
    return totals;
  }, [sorted, expensesByTicker, todayWeek]);

  const grand = {
    total: weeklyTotals.reduce((s, t) => s + t.total, 0),
    n: weeklyTotals.reduce((s, t) => s + t.n, 0),
  };

  return (
    <div className="gl-wrap">
      <div className="gl-toolbar">
        <div className="np-status-filter">
          <button className={filter === 'all' ? 'on' : ''} onClick={() => setFilter('all')}>
            All <span className="ct">{counts.all}</span>
          </button>
          <button className={filter === 'with-expenses' ? 'on' : ''} onClick={() => setFilter('with-expenses')}>
            Has expenses <span className="ct">{counts.withExpenses}</span>
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
              {Array.from({ length: WEEK_COUNT }, (_, i) => (
                <th key={i} className={'gl-wk ' + (i === 0 ? 'this' : '')}>
                  <div className="gl-wk-l">{i + 1}</div>
                </th>
              ))}
              <th className="gl-tot">Total</th>
            </tr>
          </thead>
          <tbody>
            {sorted.map((r) => {
              const entries = expensesByTicker.get(r.ticker) ?? [];
              const byWeek: Record<number, { stock: number; call: number; put: number; total: number }> = {};
              entries.forEach((g) => {
                const w = weekIdxOf(g.expense_date, todayWeek);
                if (w >= 0 && w < WEEK_COUNT) {
                  if (!byWeek[w]) byWeek[w] = { stock: 0, call: 0, put: 0, total: 0 };
                  byWeek[w][g.source] += g.amount;
                  byWeek[w].total += g.amount;
                }
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
                    <div className="gl-pos-sub">{r.sector}</div>
                  </td>
                  {Array.from({ length: WEEK_COUNT }, (_, i) => {
                    const c = byWeek[i];
                    return (
                      <td
                        key={i}
                        className={'gl-cell ' + (c ? 'filled ' : 'empty ') + (i === 0 ? 'this' : '')}
                        onClick={() => onCellClick(r.ticker, i)}
                        title={c ? `−${fmtUSD(c.total)} · tap to edit` : 'tap to add'}
                      >
                        {c ? (
                          <div className="gl-cell-in">
                            <div className="gl-cell-amt down">−{fmtCompact(c.total)}</div>
                            <div className="gl-cell-chips">
                              {c.stock !== 0 && <span className="gl-dot rk-s neg" />}
                              {c.call  !== 0 && <span className="gl-dot rk-c neg" />}
                              {c.put   !== 0 && <span className="gl-dot rk-p neg" />}
                            </div>
                          </div>
                        ) : (
                          <span className="gl-plus">+</span>
                        )}
                      </td>
                    );
                  })}
                  <td className="gl-tot">
                    <div className="gl-tot-amt down">
                      {r.expenses_total === 0 ? (
                        <span style={{ color: 'var(--navi-fg5)' }}>—</span>
                      ) : (
                        '−' + fmtUSD(r.expenses_total)
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
                <b>Weekly total</b>
                <div className="gl-pos-sub">{grand.n} entries</div>
              </td>
              {weeklyTotals.map((t, i) => (
                <td key={i} className={'gl-cell sum ' + (i === 0 ? 'this' : '')}>
                  {t.total !== 0 ? (
                    <div className="gl-cell-in">
                      <div className="gl-cell-amt down">−{fmtCompact(t.total)}</div>
                    </div>
                  ) : (
                    <span className="muted">—</span>
                  )}
                </td>
              ))}
              <td className="gl-tot">
                <div className="gl-tot-amt down">
                  {grand.total === 0 ? <span className="muted">—</span> : '−' + fmtUSD(grand.total)}
                </div>
              </td>
            </tr>
          </tfoot>
        </table>
      </div>
    </div>
  );
}
