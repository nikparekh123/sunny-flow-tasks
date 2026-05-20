// Positions module — shared types + math.
//
// Data model (post-rewrite):
//   - positions      : the underlying stock holdings (ticker + qty + avg cost)
//   - option_trades  : single ledger of options activity. Each row is either
//                      an OPEN (sell-to-open or buy-to-open) or a CLOSE
//                      (matched to a prior open via closes_trade_id).
//
// Realized P&L = Σ(close-pair P&L). A close-pair is `(open, close)` where
//   close.closes_trade_id = open.id. The signed P&L per close row is:
//     - long open  → close.premium − open.premium  (sell − buy)
//     - short open → open.premium − close.premium  (collected − bought-back)
//   times close.contracts × 100.

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
  /** Next earnings date as ISO 'YYYY-MM-DD', or null if none scheduled. */
  earnings_date: string | null;
}

/** Days between today (UTC) and an ISO date string. Negative = in the past. */
export function daysUntil(iso: string): number {
  const today = new Date();
  today.setUTCHours(0, 0, 0, 0);
  const target = new Date(iso + 'T00:00:00Z');
  return Math.round((target.getTime() - today.getTime()) / 86_400_000);
}

// ── Option trades ────────────────────────────────────────────────────

export type OptionType = 'call' | 'put';
export type Direction = 'long' | 'short';
export type Action = 'open' | 'close';

export interface OptionTrade {
  id: string;
  ticker: string;
  trade_date: string;          // ISO YYYY-MM-DD
  action: Action;
  option_type: OptionType;
  direction: Direction;        // the side of the OPEN; closes inherit (see helper)
  contracts: number;           // always positive
  strike: number;
  premium: number;             // per-share, always positive
  expiry: string;              // ISO YYYY-MM-DD
  closes_trade_id: string | null;
  note: string | null;
  created_at: string;
  updated_at: string;
}

/** Signed dollar value of a single trade: contracts × 100 × premium, with
 *  the sign expressing cash direction relative to the user.
 *    - open  +short = cash IN  (you sold premium)         → +premium
 *    - open  +long  = cash OUT (you bought)                → −premium
 *    - close +short = cash OUT (you bought back)           → −premium
 *    - close +long  = cash IN  (you sold what you owned)   → +premium
 */
export function tradeCashFlow(t: OptionTrade): number {
  const notional = t.contracts * 100 * t.premium;
  const isCashIn =
    (t.action === 'open' && t.direction === 'short') ||
    (t.action === 'close' && t.direction === 'long');
  return isCashIn ? notional : -notional;
}

/** Realized P&L for a single close row, given the open it points to.
 *  Returns 0 if the close is unmatched (closes_trade_id is null). */
export function closeRealizedPL(close: OptionTrade, open: OptionTrade): number {
  if (close.action !== 'close') return 0;
  const perShare =
    open.direction === 'short'
      ? open.premium - close.premium     // collected at open, paid at close
      : close.premium - open.premium;    // paid at open, collected at close
  return perShare * close.contracts * 100;
}

/** Group key for matching opens with closes by-contract. Two trades with
 *  the same key describe the same underlying contract. */
export function contractKey(t: OptionTrade): string {
  return `${t.ticker}|${t.option_type}|${t.strike}|${t.expiry}|${t.direction}`;
}

/** Aggregate live opens per ticker. An open is "live" if it still has
 *  remaining contracts after netting matched closes. */
export interface LiveOption {
  open: OptionTrade;
  remaining_contracts: number; // open.contracts − Σ matched closes
}

export function liveOptionsByTicker(trades: OptionTrade[]): Map<string, LiveOption[]> {
  const byId = new Map<string, OptionTrade>();
  for (const t of trades) byId.set(t.id, t);

  // Sum closed contracts against each open.
  const closedAgainst = new Map<string, number>();
  for (const t of trades) {
    if (t.action === 'close' && t.closes_trade_id) {
      closedAgainst.set(
        t.closes_trade_id,
        (closedAgainst.get(t.closes_trade_id) ?? 0) + t.contracts,
      );
    }
  }

  const out = new Map<string, LiveOption[]>();
  for (const t of trades) {
    if (t.action !== 'open') continue;
    const remaining = t.contracts - (closedAgainst.get(t.id) ?? 0);
    if (remaining <= 0) continue;
    const list = out.get(t.ticker) ?? [];
    list.push({ open: t, remaining_contracts: remaining });
    out.set(t.ticker, list);
  }
  return out;
}

/** Net cash from options activity per ticker — sum of every trade's
 *  signed cash flow (collected = +, paid = −). Includes BOTH live opens
 *  (their premium effect) AND closed pairs (their realized contribution).
 *
 *  Used by effective_cost so the "net cost" reflects premium you've
 *  already paid for live protective puts, not just realized P&L. */
export function netOptionsCashByTicker(trades: OptionTrade[]): Map<string, number> {
  const out = new Map<string, number>();
  for (const t of trades) {
    const isCashIn =
      (t.action === 'open' && t.direction === 'short') ||
      (t.action === 'close' && t.direction === 'long');
    const notional = t.contracts * 100 * t.premium;
    const signed = isCashIn ? notional : -notional;
    out.set(t.ticker, (out.get(t.ticker) ?? 0) + signed);
  }
  return out;
}

/** Total realized P&L from all closed pairs per ticker. */
export function realizedPLByTicker(trades: OptionTrade[]): Map<string, number> {
  const byId = new Map<string, OptionTrade>();
  for (const t of trades) byId.set(t.id, t);

  const out = new Map<string, number>();
  for (const t of trades) {
    if (t.action !== 'close' || !t.closes_trade_id) continue;
    const open = byId.get(t.closes_trade_id);
    if (!open) continue;
    const pl = closeRealizedPL(t, open);
    out.set(t.ticker, (out.get(t.ticker) ?? 0) + pl);
  }
  return out;
}

/** Outstanding short-put obligation per ticker: Σ(remaining contracts × 100
 *  × strike) for live short puts. Approximates "capital at risk" / "put
 *  protection cost" for the strategy cards. */
export function openShortPutObligation(trades: OptionTrade[]): Map<string, number> {
  const live = liveOptionsByTicker(trades);
  const out = new Map<string, number>();
  for (const [ticker, list] of live) {
    let sum = 0;
    for (const lo of list) {
      if (lo.open.option_type === 'put' && lo.open.direction === 'short') {
        sum += lo.remaining_contracts * 100 * lo.open.strike;
      }
    }
    if (sum > 0) out.set(ticker, sum);
  }
  return out;
}

// ── PositionComputed ──────────────────────────────────────────────────

export interface PositionComputed extends PositionRow {
  market_value: number;
  cost_basis: number;
  pnl_dollar: number;
  pnl_pct: number;
  day_change: number;
  pct_portfolio: number;
  /** Σ realized P&L from closed option pairs on this ticker. */
  realized_pl: number;
  /** Live open option positions (remaining contracts > 0) for this ticker. */
  live_options: LiveOption[];
  /** Net cash from options activity (premium collected − premium paid)
   *  including live opens. Drives effective_cost. */
  net_options_cash: number;
  /** unrealized P&L + realized_pl. "Is this position making money?" */
  overall_pl: number;
  /** Per-share effective basis. avg_cost − net_options_cash / quantity.
   *  Lower than avg_cost = options activity has paid down your basis
   *  (net premium received). Higher than avg_cost = you've paid more in
   *  premium (e.g. for protective puts) than you've taken back in. */
  effective_cost: number;
}

export function computeRow(
  p: PositionRow,
  total_market_value: number,
  realized_pl: number,
  net_options_cash: number,
  live_options: LiveOption[],
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
  // Effective cost subtracts NET cash from options (not just realized).
  // Premium paid for live protective puts shows up here as a higher
  // effective cost; premium collected on live short opens lowers it.
  const effective_cost =
    p.quantity > 0 ? p.avg_cost - net_options_cash / p.quantity : p.avg_cost;
  return {
    ...p,
    market_value, cost_basis, pnl_dollar, pnl_pct, day_change, pct_portfolio,
    realized_pl,
    net_options_cash,
    live_options,
    overall_pl: pnl_dollar + realized_pl,
    effective_cost,
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
  /** Σ realized P&L across all positions. */
  realized_pl: number;
  /** Σ outstanding short-put obligation across all positions. */
  open_put_obligation: number;
  open_count: number;
  closed_count: number;
}

export function computePortfolio(
  positions: PositionRow[],
  trades: OptionTrade[],
): PortfolioTotals {
  const tmv = positions.reduce(
    (s, p) => p.status === 'closed' ? s : s + p.quantity * (p.current_price ?? p.avg_cost),
    0,
  );
  const realizedByTicker = realizedPLByTicker(trades);
  const netCashByTicker = netOptionsCashByTicker(trades);
  const liveByTicker = liveOptionsByTicker(trades);
  const obligationByTicker = openShortPutObligation(trades);

  const rows = positions.map((p) => {
    const realized = realizedByTicker.get(p.ticker) ?? 0;
    const netCash = netCashByTicker.get(p.ticker) ?? 0;
    const live = liveByTicker.get(p.ticker) ?? [];
    return computeRow(p, tmv, realized, netCash, live);
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
  const realized_pl = rows.reduce((s, r) => s + r.realized_pl, 0);
  const open_put_obligation = Array.from(obligationByTicker.values()).reduce((s, v) => s + v, 0);
  return {
    rows,
    total_market_value: tmv,
    total_cost_basis,
    total_pnl,
    total_pnl_pct,
    total_day_change,
    last_price_update,
    realized_pl,
    open_put_obligation,
    open_count: positions.filter((p) => p.status === 'open').length,
    closed_count: positions.filter((p) => p.status === 'closed').length,
  };
}

// ── Formatters (unchanged from prior version) ─────────────────────────

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

// ── Allocation aggregations (used by treemap) ─────────────────────────

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
