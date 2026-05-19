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
export type PositionStatus = 'open' | 'closed';
export type GainSource = 'stock' | 'call' | 'put';

export interface PositionRow {
  id: string;
  ticker: string;
  name: string | null;
  sector: Sector;
  quantity: number;
  avg_cost: number;
  current_price: number | null;
  prev_close: number | null;
  last_price_update: string | null;
  status: PositionStatus;
}

export interface GainEntry {
  id: string;
  ticker: string;
  gain_date: string;        // ISO yyyy-mm-dd
  source: GainSource;
  amount: number;           // signed USD
  note: string | null;
  created_at: string;
}

/** An expense entry (outflow). Same Stock/Call/Put split as gains, but
 *  amount is always stored as a positive magnitude. The UI shows it
 *  as negative because it lives in the expenses table. */
export interface ExpenseEntry {
  id: string;
  ticker: string;
  expense_date: string;     // ISO yyyy-mm-dd
  source: GainSource;       // same source enum
  amount: number;           // magnitude, always >= 0
  note: string | null;
  created_at: string;
}

export interface PutProtectionRow {
  id: string;
  ticker: string;
  total_cost: number;
  expiry: string;
  purchase_date: string;
  created_at: string;
  updated_at: string;
}

export interface PutProtectionCalc {
  has: boolean;
  total_cost: number;
  expiry: string | null;
  purchase_date: string | null;
  total_days: number;
  days_to_expiry: number;
  days_elapsed: number;
  cost_per_day: number;
  cost_incurred: number;
  cost_remaining: number;
  expired: boolean;
}

export function computePutProtection(pp: PutProtectionRow | undefined): PutProtectionCalc {
  if (!pp) {
    return {
      has: false, total_cost: 0, expiry: null, purchase_date: null,
      total_days: 0, days_to_expiry: 0, days_elapsed: 0,
      cost_per_day: 0, cost_incurred: 0, cost_remaining: 0, expired: false,
    };
  }
  const today = new Date();
  const expiry = new Date(pp.expiry + 'T16:00:00Z');
  const purchase = new Date(pp.purchase_date + 'T12:00:00Z');
  const total_days = Math.max(1, Math.round((expiry.getTime() - purchase.getTime()) / 86_400_000));
  const days_to_expiry = Math.max(0, Math.ceil((expiry.getTime() - today.getTime()) / 86_400_000));
  const days_elapsed = Math.max(0, total_days - days_to_expiry);
  const cost_per_day = pp.total_cost / total_days;
  const cost_incurred = Math.min(pp.total_cost, cost_per_day * days_elapsed);
  const cost_remaining = Math.max(0, pp.total_cost - cost_incurred);
  return {
    has: true,
    total_cost: pp.total_cost,
    expiry: pp.expiry,
    purchase_date: pp.purchase_date,
    total_days,
    days_to_expiry,
    days_elapsed,
    cost_per_day,
    cost_incurred,
    cost_remaining,
    expired: days_to_expiry <= 0,
  };
}

export interface GainAggregate {
  stock: number;
  call: number;
  put: number;
  total: number;
}

export function aggregateGains(entries: GainEntry[]): GainAggregate {
  const out: GainAggregate = { stock: 0, call: 0, put: 0, total: 0 };
  for (const e of entries) {
    out[e.source] += e.amount;
    out.total += e.amount;
  }
  return out;
}

/** Same shape as GainAggregate but for expenses (all positive magnitudes). */
export function aggregateExpenses(entries: ExpenseEntry[]): GainAggregate {
  const out: GainAggregate = { stock: 0, call: 0, put: 0, total: 0 };
  for (const e of entries) {
    out[e.source] += e.amount;
    out.total += e.amount;
  }
  return out;
}

export interface PositionComputed extends PositionRow {
  market_value: number;
  cost_basis: number;
  pnl_dollar: number;
  pnl_pct: number;
  day_change: number;
  pct_portfolio: number;
  /** Realized gain aggregate from this ticker's gain_entries. */
  realized: GainAggregate;
  realized_total: number;
  /** Expense aggregate from this ticker's expenses (magnitudes). */
  expenses: GainAggregate;
  expenses_total: number;
  put_cost: number;
  /** realized_total − expenses_total − put_cost. */
  net_realized: number;
  /** unrealized P&L + net_realized. The "is this position making money?" answer. */
  overall_pl: number;
}

export function computeRow(
  p: PositionRow,
  total_market_value: number,
  realized: GainAggregate = { stock: 0, call: 0, put: 0, total: 0 },
  expenses: GainAggregate = { stock: 0, call: 0, put: 0, total: 0 },
  put_cost: number = 0,
): PositionComputed {
  const isClosed = p.status === 'closed';
  const last = p.current_price ?? p.avg_cost;
  const market_value = isClosed ? 0 : p.quantity * last;
  const cost_basis = isClosed ? 0 : p.quantity * p.avg_cost;
  const pnl_dollar = isClosed ? 0 : market_value - cost_basis;
  const pnl_pct = cost_basis === 0 ? 0 : (pnl_dollar / cost_basis) * 100;
  const day_change = p.prev_close != null && p.current_price != null && !isClosed
    ? p.quantity * (p.current_price - p.prev_close)
    : 0;
  const pct_portfolio =
    total_market_value === 0 ? 0 : (market_value / total_market_value) * 100;
  const net_realized = realized.total - expenses.total - put_cost;
  return {
    ...p,
    market_value, cost_basis, pnl_dollar, pnl_pct, day_change, pct_portfolio,
    realized, realized_total: realized.total,
    expenses, expenses_total: expenses.total,
    put_cost,
    net_realized,
    overall_pl: pnl_dollar + net_realized,
  };
}

export interface PortfolioTotals {
  rows: PositionComputed[];
  total_market_value: number;
  total_cost_basis: number;
  total_pnl: number;
  total_pnl_pct: number;
  total_day_change: number;
  last_price_update: string | null;
  /** Sum of all realized gains across positions, split by source. */
  realized: GainAggregate;
  realized_total: number;
  /** Sum of expense magnitudes across positions, split by source. */
  expenses: GainAggregate;
  expenses_total: number;
  total_put_cost: number;
  net_realized: number;
  open_count: number;
  closed_count: number;
}

export function computePortfolio(
  positions: PositionRow[],
  gainsByTicker: Map<string, GainEntry[]> = new Map(),
  putCostByTicker: Map<string, number> = new Map(),
  expensesByTicker: Map<string, ExpenseEntry[]> = new Map(),
): PortfolioTotals {
  const tmv = positions.reduce(
    (s, p) => p.status === 'closed' ? s : s + p.quantity * (p.current_price ?? p.avg_cost),
    0,
  );
  const rows = positions.map((p) => {
    const entries = gainsByTicker.get(p.ticker) ?? [];
    const realized = aggregateGains(entries);
    const expenses = aggregateExpenses(expensesByTicker.get(p.ticker) ?? []);
    const put_cost = putCostByTicker.get(p.ticker) ?? 0;
    return computeRow(p, tmv, realized, expenses, put_cost);
  });
  const total_cost_basis = rows.reduce((s, r) => s + r.cost_basis, 0);
  const total_pnl = tmv - total_cost_basis;
  const total_pnl_pct =
    total_cost_basis === 0 ? 0 : (total_pnl / total_cost_basis) * 100;
  const total_day_change = rows.reduce((s, r) => s + r.day_change, 0);
  const last_price_update =
    positions.reduce<string | null>((acc, p) => {
      if (!p.last_price_update) return acc;
      if (!acc) return p.last_price_update;
      return p.last_price_update > acc ? p.last_price_update : acc;
    }, null);
  const realized: GainAggregate = rows.reduce(
    (acc, r) => ({
      stock: acc.stock + r.realized.stock,
      call: acc.call + r.realized.call,
      put: acc.put + r.realized.put,
      total: acc.total + r.realized.total,
    }),
    { stock: 0, call: 0, put: 0, total: 0 },
  );
  const expenses: GainAggregate = rows.reduce(
    (acc, r) => ({
      stock: acc.stock + r.expenses.stock,
      call: acc.call + r.expenses.call,
      put: acc.put + r.expenses.put,
      total: acc.total + r.expenses.total,
    }),
    { stock: 0, call: 0, put: 0, total: 0 },
  );
  const total_put_cost = rows.reduce((s, r) => s + r.put_cost, 0);
  return {
    rows,
    total_market_value: tmv,
    total_cost_basis,
    total_pnl,
    total_pnl_pct,
    total_day_change,
    last_price_update,
    realized,
    realized_total: realized.total,
    expenses,
    expenses_total: expenses.total,
    total_put_cost,
    net_realized: realized.total - expenses.total - total_put_cost,
    open_count: positions.filter((p) => p.status === 'open').length,
    closed_count: positions.filter((p) => p.status === 'closed').length,
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
/** Compact dollars: $980 / $3.2k / $1.5M. */
export const fmtCompact = (n: number): string => {
  const sign = n < 0 ? MINUS : '';
  const abs = Math.abs(n);
  if (abs >= 1_000_000) return sign + '$' + (abs / 1_000_000).toFixed(2) + 'M';
  if (abs >= 1_000) return sign + '$' + (abs / 1_000).toFixed(abs >= 10_000 ? 0 : 1) + 'k';
  return sign + '$' + abs.toFixed(0);
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

// Allocation rollup by strategy bucket. Anything without an overlay falls
// into "Unassigned" so the chart still adds to 100%.
export type StrategyBucket = 'income' | 'invest' | 'yield';
const STRATEGY_LABEL: Record<string, string> = {
  income: 'Income',
  invest: 'Investment',
  yield: 'Yield',
  unassigned: 'Unassigned',
};
export function aggregateByStrategy(
  rows: PositionComputed[],
  overlayByTicker: Map<string, StrategyBucket>,
) {
  const map = new Map<string, number>();
  rows.forEach((r) => {
    const b = overlayByTicker.get(r.ticker) ?? 'unassigned';
    map.set(b, (map.get(b) || 0) + r.market_value);
  });
  const total = Array.from(map.values()).reduce((s, v) => s + v, 0);
  // Stable order: income → invest → yield → unassigned
  const order = ['income', 'invest', 'yield', 'unassigned'];
  return order
    .filter((k) => map.has(k))
    .map((k) => {
      const value = map.get(k) ?? 0;
      return {
        label: STRATEGY_LABEL[k] ?? k,
        value,
        pct: total === 0 ? 0 : (value / total) * 100,
      };
    });
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
