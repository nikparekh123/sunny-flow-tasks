import { useMemo, useState, Fragment } from 'react';
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
type GroupKey = Bucket | 'unassigned';

interface Props {
  rows: PositionComputed[];
  onUpload?: () => void;
  loading?: boolean;
  overlayByTicker?: Map<string, Bucket>;
}

const GROUP_ORDER: GroupKey[] = ['income', 'invest', 'yield', 'unassigned'];

const GROUP_META: Record<GroupKey, { name: string; tone: string; accent: string }> = {
  income:     { name: 'Income',      tone: 'income',     accent: '#d2e632' },
  invest:     { name: 'Investment',  tone: 'invest',     accent: '#8ab4d4' },
  yield:      { name: 'Yield',       tone: 'yield',      accent: '#a8d4a0' },
  unassigned: { name: 'Unassigned',  tone: 'unassigned', accent: '#e0c060' },
};

export function PositionsTable({
  rows,
  onUpload,
  loading,
  overlayByTicker,
}: Props) {
  const [sortKey, setSortKey] = useState<SortKey>('market_value');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');

  // Group by strategy bucket, then sort within each group.
  const grouped = useMemo(() => {
    const map: Record<GroupKey, PositionComputed[]> = {
      income: [],
      invest: [],
      yield: [],
      unassigned: [],
    };
    for (const r of rows) {
      const b = overlayByTicker?.get(r.ticker) ?? 'unassigned';
      map[b].push(r);
    }
    const sortInPlace = (arr: PositionComputed[]) => {
      arr.sort((a, b) => {
        const av = (a as unknown as Record<string, number | string>)[sortKey];
        const bv = (b as unknown as Record<string, number | string>)[sortKey];
        let cmp: number;
        if (typeof av === 'number' && typeof bv === 'number') cmp = av - bv;
        else cmp = String(av ?? '').localeCompare(String(bv ?? ''));
        return sortDir === 'asc' ? cmp : -cmp;
      });
    };
    GROUP_ORDER.forEach((k) => sortInPlace(map[k]));
    return map;
  }, [rows, overlayByTicker, sortKey, sortDir]);

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

  if (rows.length === 0 && !loading) return <EmptyTable onUpload={onUpload} />;

  const maxPct = Math.max(...rows.map((r) => r.pct_portfolio), 1);
  const visibleGroups = GROUP_ORDER.filter((k) => grouped[k].length > 0);

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
            <th onClick={() => onSort('market_value')}>Mkt value{ind('market_value')}</th>
            <th onClick={() => onSort('pnl_dollar')}>P&amp;L $ {ind('pnl_dollar')}</th>
            <th onClick={() => onSort('pnl_pct')}>P&amp;L %{ind('pnl_pct')}</th>
            <th onClick={() => onSort('pct_portfolio')}>% port{ind('pct_portfolio')}</th>
          </tr>
        </thead>
        <tbody>
          {visibleGroups.map((g) => {
            const rowsInGroup = grouped[g];
            const meta = GROUP_META[g];
            const subtotal = rowsInGroup.reduce(
              (acc, r) => ({
                mv: acc.mv + r.market_value,
                cost: acc.cost + r.cost_basis,
                pl: acc.pl + r.pnl_dollar,
                pct: acc.pct + r.pct_portfolio,
              }),
              { mv: 0, cost: 0, pl: 0, pct: 0 },
            );
            const subPct = subtotal.cost === 0 ? 0 : (subtotal.pl / subtotal.cost) * 100;
            return (
              <Fragment key={g}>
                <tr className={`np-group-hd np-group-${meta.tone}`}>
                  <td colSpan={9}>
                    <span className="np-group-dot" style={{ background: meta.accent }} />
                    <span className="np-group-name">{meta.name}</span>
                    <span className="np-group-count">· {rowsInGroup.length} positions</span>
                  </td>
                </tr>
                {rowsInGroup.map((r) => (
                  <tr key={r.id} data-ticker={r.ticker}>
                    <td className="ticker">{r.ticker}</td>
                    <td className="sector-cell">{r.sector}</td>
                    <td className="num">{fmtQty(r.quantity)}</td>
                    <td className="num">{fmtUSD2(r.avg_cost)}</td>
                    <td className="num">
                      {r.current_price != null ? fmtUSD2(r.current_price) : '—'}
                    </td>
                    <td className="num strong">{fmtUSD(r.market_value)}</td>
                    <td className={'num ' + (r.pnl_dollar < 0 ? 'down' : r.pnl_dollar > 0 ? 'up' : '')}>
                      {fmtUSD(r.pnl_dollar)}
                    </td>
                    <td className={'num ' + (r.pnl_pct < 0 ? 'down' : r.pnl_pct > 0 ? 'up' : '')}>
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
                  </tr>
                ))}
                <tr className={`np-group-foot np-group-${meta.tone}`}>
                  <td colSpan={5}>
                    <b>{meta.name} subtotal</b>
                  </td>
                  <td className="num strong">{fmtUSD(subtotal.mv)}</td>
                  <td className={'num ' + (subtotal.pl < 0 ? 'down' : subtotal.pl > 0 ? 'up' : '')}>
                    {fmtUSD(subtotal.pl)}
                  </td>
                  <td className={'num ' + (subPct < 0 ? 'down' : subPct > 0 ? 'up' : '')}>
                    {fmtPct(subPct)}
                  </td>
                  <td className="num">{subtotal.pct.toFixed(1)}%</td>
                </tr>
              </Fragment>
            );
          })}
        </tbody>
      </table>
    </div>
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
