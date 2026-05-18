import { useMemo, useState } from 'react';
import {
  fmtUSD,
  fmtUSD2,
  fmtPct,
  fmtQty,
  type PositionComputed,
} from './types';

type SortKey =
  | 'ticker'
  | 'sector'
  | 'quantity'
  | 'avg_cost'
  | 'current_price'
  | 'market_value'
  | 'pnl_dollar'
  | 'pnl_pct'
  | 'pct_portfolio';

type Bucket = 'income' | 'invest' | 'yield';

interface Props {
  rows: PositionComputed[];
  onUpload?: () => void;
  loading?: boolean;
  overlayByTicker?: Map<string, Bucket>;
}

const BUCKET_LABEL: Record<Bucket, string> = {
  income: 'Income',
  invest: 'Invest',
  yield: 'Yield',
};

export function PositionsTable({ rows, onUpload, loading, overlayByTicker }: Props) {
  const [sortKey, setSortKey] = useState<SortKey>('market_value');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');

  const sorted = useMemo(() => {
    const out = [...rows].sort((a, b) => {
      const av = (a as unknown as Record<string, number | string>)[sortKey];
      const bv = (b as unknown as Record<string, number | string>)[sortKey];
      let cmp: number;
      if (typeof av === 'number' && typeof bv === 'number') {
        cmp = av - bv;
      } else {
        cmp = String(av ?? '').localeCompare(String(bv ?? ''));
      }
      return sortDir === 'asc' ? cmp : -cmp;
    });
    return out;
  }, [rows, sortKey, sortDir]);

  const onSort = (k: SortKey) => {
    if (k === sortKey) {
      setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortKey(k);
      setSortDir(k === 'ticker' || k === 'sector' ? 'asc' : 'desc');
    }
  };

  const ind = (k: SortKey) =>
    sortKey === k ? <span className="sort">{sortDir === 'asc' ? '↑' : '↓'}</span> : null;

  if (rows.length === 0 && !loading) {
    return <EmptyTable onUpload={onUpload} />;
  }

  const maxPct = Math.max(...rows.map((r) => r.pct_portfolio), 1);

  return (
    <div className="np-table-wrap">
      <table className="np-table">
        <thead>
          <tr>
            <th onClick={() => onSort('ticker')}>Ticker{ind('ticker')}</th>
            <th onClick={() => onSort('sector')}>Sector{ind('sector')}</th>
            <th onClick={() => onSort('quantity')}>Qty{ind('quantity')}</th>
            <th onClick={() => onSort('avg_cost')}>Avg cost{ind('avg_cost')}</th>
            <th onClick={() => onSort('current_price')}>Price{ind('current_price')}</th>
            <th onClick={() => onSort('market_value')}>
              Mkt value{ind('market_value')}
            </th>
            <th onClick={() => onSort('pnl_dollar')}>P&amp;L $ {ind('pnl_dollar')}</th>
            <th onClick={() => onSort('pnl_pct')}>P&amp;L %{ind('pnl_pct')}</th>
            <th onClick={() => onSort('pct_portfolio')}>
              % port{ind('pct_portfolio')}
            </th>
            <th>Strategy</th>
          </tr>
        </thead>
        <tbody>
          {sorted.map((r) => (
            <tr key={r.id} data-ticker={r.ticker}>
              <td className="ticker">{r.ticker}</td>
              <td className="sector-cell">{r.sector}</td>
              <td className="num">{fmtQty(r.quantity)}</td>
              <td className="num">{fmtUSD2(r.avg_cost)}</td>
              <td className="num">
                {r.current_price != null ? fmtUSD2(r.current_price) : '—'}
              </td>
              <td className="num strong">{fmtUSD(r.market_value)}</td>
              <td
                className={
                  'num ' +
                  (r.pnl_dollar < 0 ? 'down' : r.pnl_dollar > 0 ? 'up' : '')
                }
              >
                {fmtUSD(r.pnl_dollar)}
              </td>
              <td
                className={
                  'num ' +
                  (r.pnl_pct < 0 ? 'down' : r.pnl_pct > 0 ? 'up' : '')
                }
              >
                {fmtPct(r.pnl_pct)}
              </td>
              <td className="num">
                <span
                  className="pct-bar"
                  style={{
                    width: (r.pct_portfolio / maxPct) * 36 + 'px',
                    background: '#326e64',
                  }}
                />
                {r.pct_portfolio.toFixed(1)}%
              </td>
              <td>
                <StrategyBadge bucket={overlayByTicker?.get(r.ticker)} />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function StrategyBadge({ bucket }: { bucket?: Bucket }) {
  if (!bucket) {
    return <span className="np-strategy-badge none">— not in strategy</span>;
  }
  return (
    <a
      href={`/strategy?ticker=${encodeURIComponent('')}`}
      onClick={(e) => {
        e.preventDefault();
        const row = (e.currentTarget.closest('tr')) as HTMLElement | null;
        const t = row?.dataset.ticker;
        if (t) window.location.assign(`/strategy?ticker=${encodeURIComponent(t)}`);
      }}
      className={`np-strategy-badge ${bucket}`}
    >
      {BUCKET_LABEL[bucket]} ↗
    </a>
  );
}

function EmptyTable({ onUpload }: { onUpload?: () => void }) {
  return (
    <div className="np-empty">
      <p>No positions yet — upload a CSV to get started.</p>
      {onUpload && (
        <button className="np-btn neon" onClick={onUpload}>
          ↑ Upload positions
        </button>
      )}
    </div>
  );
}
