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
  | 'last_price'
  | 'market_value'
  | 'pnl_dollar'
  | 'day_change';

interface Props {
  rows: PositionComputed[];
  onUpload?: () => void;
}

export function PositionsTable({ rows, onUpload }: Props) {
  const [sortKey, setSortKey] = useState<SortKey>('market_value');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');
  const [filter, setFilter] = useState('');

  const filtered = useMemo(() => {
    const q = filter.trim().toLowerCase();
    let out = q
      ? rows.filter(
          (r) =>
            r.ticker.toLowerCase().includes(q) ||
            r.sector.toLowerCase().includes(q),
        )
      : rows;
    out = [...out].sort((a, b) => {
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
  }, [rows, filter, sortKey, sortDir]);

  const onSort = (k: SortKey) => {
    if (k === sortKey) {
      setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortKey(k);
      setSortDir(k === 'ticker' || k === 'sector' ? 'asc' : 'desc');
    }
  };

  if (rows.length === 0) {
    return <EmptyTable onUpload={onUpload} />;
  }

  return (
    <div>
      {/* Header */}
      <div className="flex items-end justify-between mb-4">
        <h2
          style={{
            fontSize: 24,
            fontWeight: 500,
            letterSpacing: '-0.3px',
            color: 'var(--owl-text-primary)',
          }}
        >
          Positions ({rows.length})
        </h2>
        <input
          type="text"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          placeholder="Filter…"
          style={{
            width: 240,
            background: 'transparent',
            border: 'none',
            borderBottom: '1px solid var(--owl-line)',
            color: 'var(--owl-text-primary)',
            fontFamily: 'var(--owl-font-sans)',
            fontSize: 13,
            padding: '6px 0',
            outline: 'none',
          }}
        />
      </div>

      <div style={{ overflowX: 'auto' }}>
        <table
          style={{
            width: '100%',
            borderCollapse: 'collapse',
            borderTop: '1px solid var(--owl-elevated)',
            borderBottom: '1px solid var(--owl-elevated)',
          }}
        >
          <thead>
            <tr>
              <Th k="ticker" label="Ticker" sortKey={sortKey} sortDir={sortDir} onSort={onSort} align="left" />
              <Th k="sector" label="Sector" sortKey={sortKey} sortDir={sortDir} onSort={onSort} align="left" />
              <Th k="quantity" label="Qty" sortKey={sortKey} sortDir={sortDir} onSort={onSort} align="right" />
              <Th k="avg_cost" label="Avg cost" sortKey={sortKey} sortDir={sortDir} onSort={onSort} align="right" />
              <Th k="last_price" label="Last" sortKey={sortKey} sortDir={sortDir} onSort={onSort} align="right" />
              <Th k="market_value" label="Market value" sortKey={sortKey} sortDir={sortDir} onSort={onSort} align="right" />
              <Th k="pnl_dollar" label="P&L" sortKey={sortKey} sortDir={sortDir} onSort={onSort} align="right" />
              <Th k="day_change" label="Day" sortKey={sortKey} sortDir={sortDir} onSort={onSort} align="right" />
            </tr>
          </thead>
          <tbody>
            {filtered.map((r) => (
              <Row key={r.id} r={r} />
            ))}
          </tbody>
        </table>
      </div>
      {filtered.length === 0 && filter && (
        <div
          style={{
            padding: '32px 0',
            textAlign: 'center',
            color: 'var(--owl-text-muted)',
            fontSize: 13,
          }}
        >
          No matches for "{filter}".
        </div>
      )}
    </div>
  );
}

function Th({
  k,
  label,
  sortKey,
  sortDir,
  onSort,
  align,
}: {
  k: SortKey;
  label: string;
  sortKey: SortKey;
  sortDir: 'asc' | 'desc';
  onSort: (k: SortKey) => void;
  align: 'left' | 'right';
}) {
  const active = sortKey === k;
  return (
    <th
      onClick={() => onSort(k)}
      style={{
        textAlign: align,
        padding: '14px 12px',
        fontSize: 10,
        fontWeight: 600,
        letterSpacing: '1.2px',
        textTransform: 'uppercase',
        color: active ? 'var(--owl-text-primary)' : 'var(--owl-text-muted)',
        borderBottom: '1px solid var(--owl-elevated)',
        cursor: 'pointer',
        userSelect: 'none',
        whiteSpace: 'nowrap',
      }}
    >
      {label}
      {active && (
        <span style={{ marginLeft: 4, opacity: 0.8 }}>
          {sortDir === 'asc' ? '▲' : '▼'}
        </span>
      )}
    </th>
  );
}

function Row({ r }: { r: PositionComputed }) {
  const pnlColor =
    r.pnl_dollar >= 0 ? 'var(--owl-positive)' : 'var(--owl-negative)';
  const dayColor =
    r.day_change >= 0 ? 'var(--owl-positive)' : 'var(--owl-negative)';
  return (
    <tr
      style={{ transition: 'background 0.1s' }}
      onMouseEnter={(e) =>
        ((e.currentTarget as HTMLTableRowElement).style.background =
          'rgba(15,51,51,0.4)')
      }
      onMouseLeave={(e) =>
        ((e.currentTarget as HTMLTableRowElement).style.background = '')
      }
    >
      <Td>
        <span
          style={{
            fontFamily: 'var(--owl-font-mono)',
            fontSize: 14,
            fontWeight: 500,
            color: 'var(--owl-text-primary)',
          }}
        >
          {r.ticker}
        </span>
      </Td>
      <Td>
        <span style={{ fontSize: 12, color: 'var(--owl-text-secondary)' }}>
          {r.sector}
        </span>
      </Td>
      <TdNum>{fmtQty(r.quantity)}</TdNum>
      <TdNum>{fmtUSD2(r.avg_cost)}</TdNum>
      <TdNum>
        {r.last_price != null ? (
          fmtUSD2(r.last_price)
        ) : (
          <span style={{ color: 'var(--owl-text-label)' }}>—</span>
        )}
      </TdNum>
      <TdNum>{fmtUSD(r.market_value)}</TdNum>
      <TdNum color={pnlColor}>
        <div style={{ fontSize: 13 }}>{fmtUSD(r.pnl_dollar)}</div>
        <div style={{ fontSize: 11, opacity: 0.8 }}>{fmtPct(r.pnl_pct)}</div>
      </TdNum>
      <TdNum color={dayColor}>
        {r.last_price != null && r.prev_close != null ? (
          fmtUSD(r.day_change)
        ) : (
          <span style={{ color: 'var(--owl-text-label)' }}>—</span>
        )}
      </TdNum>
    </tr>
  );
}

function Td({ children }: { children: React.ReactNode }) {
  return (
    <td
      style={{
        padding: '12px',
        borderBottom: '1px solid var(--owl-line)',
      }}
    >
      {children}
    </td>
  );
}
function TdNum({
  children,
  color,
}: {
  children: React.ReactNode;
  color?: string;
}) {
  return (
    <td
      style={{
        padding: '12px',
        textAlign: 'right',
        fontFamily: 'var(--owl-font-mono)',
        fontSize: 13,
        color: color ?? 'var(--owl-text-primary)',
        borderBottom: '1px solid var(--owl-line)',
        whiteSpace: 'nowrap',
      }}
    >
      {children}
    </td>
  );
}

function EmptyTable({ onUpload }: { onUpload?: () => void }) {
  return (
    <div
      style={{
        padding: '64px 32px',
        textAlign: 'center',
        border: '1px dashed var(--owl-elevated)',
      }}
    >
      <p
        style={{
          fontSize: 14,
          color: 'var(--owl-text-muted)',
          marginBottom: 16,
        }}
      >
        No positions yet — upload a CSV to get started.
      </p>
      {onUpload && (
        <button
          onClick={onUpload}
          style={{
            background: 'var(--owl-tint-neon)',
            color: 'var(--owl-neon)',
            border: 'none',
            padding: '10px 18px',
            fontSize: 12,
            fontWeight: 500,
            letterSpacing: '0.5px',
            cursor: 'pointer',
          }}
        >
          ↑ Upload positions
        </button>
      )}
    </div>
  );
}
