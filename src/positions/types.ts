export const SECTORS = [
  'Technology',
  'Healthcare',
  'Financials',
  'Consumer Discretionary',
  'Consumer Staples',
  'Energy',
  'Industrials',
  'Materials',
  'Utilities',
  'Real Estate',
  'Communication Services',
  'Other',
] as const;

export type Sector = (typeof SECTORS)[number];

export interface PositionRow {
  id: string;
  ticker: string;
  sector: Sector;
  quantity: number;
  avg_cost: number;
  last_price: number | null;
  prev_close: number | null;
  last_updated: string | null;
}

export interface PositionComputed extends PositionRow {
  market_value: number;
  cost_basis: number;
  pnl_dollar: number;
  pnl_pct: number;
  day_change: number;
  pct_portfolio: number;
}

export function computeRow(p: PositionRow, total_market_value: number): PositionComputed {
  const last = p.last_price ?? p.avg_cost;
  const market_value = p.quantity * last;
  const cost_basis = p.quantity * p.avg_cost;
  const pnl_dollar = market_value - cost_basis;
  const pnl_pct = cost_basis === 0 ? 0 : (pnl_dollar / cost_basis) * 100;
  const day_change = p.prev_close != null && p.last_price != null
    ? p.quantity * (p.last_price - p.prev_close)
    : 0;
  const pct_portfolio =
    total_market_value === 0 ? 0 : (market_value / total_market_value) * 100;
  return { ...p, market_value, cost_basis, pnl_dollar, pnl_pct, day_change, pct_portfolio };
}

export interface PortfolioTotals {
  rows: PositionComputed[];
  total_market_value: number;
  total_cost_basis: number;
  total_pnl: number;
  total_pnl_pct: number;
  total_day_change: number;
  last_updated: string | null;
}

export function computePortfolio(positions: PositionRow[]): PortfolioTotals {
  const tmv = positions.reduce(
    (s, p) => s + p.quantity * (p.last_price ?? p.avg_cost),
    0,
  );
  const rows = positions.map((p) => computeRow(p, tmv));
  const total_cost_basis = rows.reduce((s, r) => s + r.cost_basis, 0);
  const total_pnl = tmv - total_cost_basis;
  const total_pnl_pct =
    total_cost_basis === 0 ? 0 : (total_pnl / total_cost_basis) * 100;
  const total_day_change = rows.reduce((s, r) => s + r.day_change, 0);
  const last_updated =
    positions.reduce<string | null>((acc, p) => {
      if (!p.last_updated) return acc;
      if (!acc) return p.last_updated;
      return p.last_updated > acc ? p.last_updated : acc;
    }, null);
  return {
    rows,
    total_market_value: tmv,
    total_cost_basis,
    total_pnl,
    total_pnl_pct,
    total_day_change,
    last_updated,
  };
}

// ─── Formatters ─────────────────────────────────────────────────────────────
const MINUS = '−';
export const fmtUSD = (n: number): string => {
  const s = n < 0 ? MINUS : '';
  return (
    s +
    '$' +
    Math.abs(n).toLocaleString('en-US', {
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
    })
  );
};
export const fmtUSD2 = (n: number): string => {
  const s = n < 0 ? MINUS : '';
  return (
    s +
    '$' +
    Math.abs(n).toLocaleString('en-US', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })
  );
};
export const fmtUSDShort = (n: number): string => {
  const s = n < 0 ? MINUS : '';
  const abs = Math.abs(n);
  if (abs >= 1_000_000_000) return `${s}$${(abs / 1_000_000_000).toFixed(2)}B`;
  if (abs >= 1_000_000) return `${s}$${(abs / 1_000_000).toFixed(2)}M`;
  if (abs >= 1_000) return `${s}$${(abs / 1_000).toFixed(1)}k`;
  return `${s}$${abs.toFixed(0)}`;
};
export const fmtPct = (n: number): string => {
  const s = n < 0 ? MINUS : n > 0 ? '+' : '';
  return s + Math.abs(n).toFixed(2) + '%';
};
export const fmtQty = (n: number): string => n.toLocaleString('en-US');
export const fmtNum = (n: number, d = 2): string => {
  const s = n < 0 ? MINUS : '';
  return (
    s +
    Math.abs(n).toLocaleString('en-US', {
      minimumFractionDigits: d,
      maximumFractionDigits: d,
    })
  );
};

export function aggregateBySector(rows: PositionComputed[]) {
  const map = new Map<string, number>();
  rows.forEach((r) =>
    map.set(r.sector, (map.get(r.sector) || 0) + r.market_value),
  );
  const total = Array.from(map.values()).reduce((s, v) => s + v, 0);
  return Array.from(map.entries())
    .map(([label, value]) => ({
      label,
      value,
      pct: total === 0 ? 0 : (value / total) * 100,
    }))
    .sort((a, b) => b.value - a.value);
}

export function aggregateByTicker(rows: PositionComputed[]) {
  const total = rows.reduce((s, r) => s + r.market_value, 0);
  return rows
    .map((r) => ({
      label: r.ticker,
      value: r.market_value,
      pct: total === 0 ? 0 : (r.market_value / total) * 100,
    }))
    .sort((a, b) => b.value - a.value);
}
