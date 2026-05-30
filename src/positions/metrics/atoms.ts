/**
 * The 12 Atoms — every metric in the app reduces to a combination of these.
 *
 * See `docs/METRICS.md` for the canonical glossary and `docs/atoms-quick-
 * reference.pdf` for the plain-English reference card.
 *
 * **Design rules:**
 *  - Pure TypeScript. No React, no Supabase, no DOM.
 *  - Each atom is a single function that takes raw data + an optional
 *    `AtomFilter` and returns a scalar (or, for A12, a function of date).
 *  - Filters are AND'd together. Omitted filters = unfiltered.
 *  - Atoms never invent math; they only sum / subtract / count the raw fields
 *    documented in METRICS.md.
 *
 * Pages **never** re-implement these. They consume them via the hook layer
 * (to be built in step 2) and label the result with one of the names from
 * the "Common combinations" table.
 */
import {
  closeRealizedPL,
  type DailyClose,
  type OptionTrade,
  type PositionRow,
  type ShareSell,
} from "../types";

// ─────────────────────────────────────────────────────────────────────────────
// Shared types
// ─────────────────────────────────────────────────────────────────────────────

/** A half-open date window: `[start, end)` in ISO `YYYY-MM-DD`. If only `start`
 *  is set, it's "from start to today"; if only `end`, "from the beginning to
 *  end". Both omitted = all-time. */
export interface DateWindow {
  start?: string;
  end?: string;
}

/** Live state of an open option leg, computed from days-until-expiry. */
export type LiveState = "today" | "in_le_7d" | "in_gt_7d" | "expired";

/** The canonical filter shape. Every atom that accepts a filter accepts this
 *  exact type. Omitted fields = no filter on that dimension. */
export interface AtomFilter {
  ticker?: string;
  optionType?: "call" | "put";
  /** The OPEN's direction. For closes, the source open's direction (the close
   *  row inherits its direction from the open it closes). */
  direction?: "short" | "long";
  window?: DateWindow;
  /** Only meaningful for open-leg atoms (A9/A10/A11). */
  liveState?: LiveState | LiveState[];
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

const todayIsoUTC = (): string => new Date().toISOString().slice(0, 10);

/** Inclusive on `start`, exclusive on `end`. */
function inWindow(dateIso: string, w?: DateWindow): boolean {
  if (!w) return true;
  if (w.start && dateIso < w.start) return false;
  if (w.end && dateIso >= w.end) return false;
  return true;
}

function passesPositionFilter(p: PositionRow, f?: AtomFilter): boolean {
  if (!f) return true;
  if (f.ticker && p.ticker !== f.ticker) return false;
  return true;
}

function passesTradeFilter(t: OptionTrade, f?: AtomFilter): boolean {
  if (!f) return true;
  if (f.ticker && t.ticker !== f.ticker) return false;
  if (f.optionType && t.option_type !== f.optionType) return false;
  if (f.direction && t.direction !== f.direction) return false;
  if (f.window && !inWindow(t.trade_date, f.window)) return false;
  return true;
}

function passesSellFilter(s: ShareSell, f?: AtomFilter): boolean {
  if (!f) return true;
  if (f.ticker && s.ticker !== f.ticker) return false;
  if (f.window && !inWindow(s.trade_date, f.window)) return false;
  return true;
}

/** Days from today (UTC) to an ISO date. Negative = in the past. */
function daysUntil(iso: string, today: string): number {
  const a = new Date(iso + "T00:00:00Z").getTime();
  const b = new Date(today + "T00:00:00Z").getTime();
  return Math.round((a - b) / 86_400_000);
}

function liveStateOf(expiry: string, today: string): LiveState {
  const d = daysUntil(expiry, today);
  if (d < 0) return "expired";
  if (d === 0) return "today";
  if (d <= 7) return "in_le_7d";
  return "in_gt_7d";
}

function matchesLiveState(
  expiry: string,
  filter: AtomFilter["liveState"],
  today: string,
): boolean {
  if (!filter) return true;
  const state = liveStateOf(expiry, today);
  return Array.isArray(filter) ? filter.includes(state) : state === filter;
}

/** Build a map from open trade id → remaining (un-closed) contracts. */
function remainingByOpenId(trades: OptionTrade[]): Map<string, number> {
  const open = new Map<string, OptionTrade>();
  const closedQty = new Map<string, number>();
  for (const t of trades) {
    if (t.action === "open") open.set(t.id, t);
    else if (t.action === "close" && t.closes_trade_id) {
      closedQty.set(t.closes_trade_id, (closedQty.get(t.closes_trade_id) ?? 0) + t.contracts);
    }
  }
  const out = new Map<string, number>();
  for (const [id, o] of open) {
    out.set(id, Math.max(0, o.contracts - (closedQty.get(id) ?? 0)));
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// A1 — Equity Market Value
// ─────────────────────────────────────────────────────────────────────────────

/** Σ (qty × current_price) over OPEN positions. Closed rows contribute $0. */
export function equityMarketValue(positions: PositionRow[], f?: AtomFilter): number {
  let sum = 0;
  for (const p of positions) {
    if (p.status === "closed" || p.quantity <= 0) continue;
    if (!passesPositionFilter(p, f)) continue;
    const px = p.current_price ?? 0;
    sum += p.quantity * px;
  }
  return sum;
}

// ─────────────────────────────────────────────────────────────────────────────
// A2 — Equity Cost Basis
// ─────────────────────────────────────────────────────────────────────────────

/** Σ (qty × avg_cost) over OPEN positions. */
export function equityCostBasis(positions: PositionRow[], f?: AtomFilter): number {
  let sum = 0;
  for (const p of positions) {
    if (p.status === "closed" || p.quantity <= 0) continue;
    if (!passesPositionFilter(p, f)) continue;
    sum += p.quantity * p.avg_cost;
  }
  return sum;
}

// ─────────────────────────────────────────────────────────────────────────────
// A3 — Shares Realized
// ─────────────────────────────────────────────────────────────────────────────

/** Σ share_sells.realized_pl, optionally windowed by `trade_date`. */
export function sharesRealized(sells: ShareSell[], f?: AtomFilter): number {
  let sum = 0;
  for (const s of sells) {
    if (!passesSellFilter(s, f)) continue;
    sum += s.realized_pl;
  }
  return sum;
}

// ─────────────────────────────────────────────────────────────────────────────
// A4 — Premium Collected (gross cash from short opens)
// ─────────────────────────────────────────────────────────────────────────────

/** Σ (contracts × 100 × premium) for short OPENs. Always positive. */
export function premiumCollected(trades: OptionTrade[], f?: AtomFilter): number {
  let sum = 0;
  for (const t of trades) {
    if (t.action !== "open") continue;
    if (t.direction !== "short") continue;
    if (!passesTradeFilter(t, f)) continue;
    sum += t.contracts * 100 * t.premium;
  }
  return sum;
}

// ─────────────────────────────────────────────────────────────────────────────
// A5 — Premium Paid (gross cash for long opens)
// ─────────────────────────────────────────────────────────────────────────────

/** Σ (contracts × 100 × premium) for long OPENs. Always positive. */
export function premiumPaid(trades: OptionTrade[], f?: AtomFilter): number {
  let sum = 0;
  for (const t of trades) {
    if (t.action !== "open") continue;
    if (t.direction !== "long") continue;
    if (!passesTradeFilter(t, f)) continue;
    sum += t.contracts * 100 * t.premium;
  }
  return sum;
}

// ─────────────────────────────────────────────────────────────────────────────
// A6 — Buy-to-Close Debit (cash paid to close a short)
// ─────────────────────────────────────────────────────────────────────────────

/** Σ (contracts × 100 × premium) for CLOSEs of short opens. Always positive. */
export function debitCloseShort(trades: OptionTrade[], f?: AtomFilter): number {
  let sum = 0;
  for (const t of trades) {
    if (t.action !== "close") continue;
    if (t.direction !== "short") continue;
    if (!passesTradeFilter(t, f)) continue;
    sum += t.contracts * 100 * t.premium;
  }
  return sum;
}

// ─────────────────────────────────────────────────────────────────────────────
// A7 — Sell-to-Close Credit (cash received closing a long)
// ─────────────────────────────────────────────────────────────────────────────

/** Σ (contracts × 100 × premium) for CLOSEs of long opens. Always positive. */
export function creditCloseLong(trades: OptionTrade[], f?: AtomFilter): number {
  let sum = 0;
  for (const t of trades) {
    if (t.action !== "close") continue;
    if (t.direction !== "long") continue;
    if (!passesTradeFilter(t, f)) continue;
    sum += t.contracts * 100 * t.premium;
  }
  return sum;
}

// ─────────────────────────────────────────────────────────────────────────────
// A8 — Option Realized
// ─────────────────────────────────────────────────────────────────────────────

/** Σ closeRealizedPL(close, open) over matched close-pairs. Signed.
 *
 *  Window filter applies to the CLOSE's `trade_date` (when it was realized).
 *  Direction/option_type filters apply to the OPEN (the strategy you put on).
 *  Ticker filter applies to both (they always match anyway). */
export function optionRealized(trades: OptionTrade[], f?: AtomFilter): number {
  const byId = new Map<string, OptionTrade>();
  for (const t of trades) byId.set(t.id, t);
  let sum = 0;
  for (const c of trades) {
    if (c.action !== "close" || !c.closes_trade_id) continue;
    const o = byId.get(c.closes_trade_id);
    if (!o) continue;
    if (f) {
      if (f.ticker && c.ticker !== f.ticker) continue;
      if (f.optionType && o.option_type !== f.optionType) continue;
      if (f.direction && o.direction !== f.direction) continue;
      if (f.window && !inWindow(c.trade_date, f.window)) continue;
    }
    sum += closeRealizedPL(c, o);
  }
  return sum;
}

// ─────────────────────────────────────────────────────────────────────────────
// A9 — Open Short Premium (capital still outstanding on short opens)
// ─────────────────────────────────────────────────────────────────────────────

/** Σ (remaining_contracts × 100 × open premium) for still-open short legs. */
export function openShortPremium(
  trades: OptionTrade[],
  f?: AtomFilter,
  today: string = todayIsoUTC(),
): number {
  const remaining = remainingByOpenId(trades);
  let sum = 0;
  for (const t of trades) {
    if (t.action !== "open" || t.direction !== "short") continue;
    const left = remaining.get(t.id) ?? 0;
    if (left <= 0) continue;
    if (!passesTradeFilter(t, f)) continue;
    if (!matchesLiveState(t.expiry, f?.liveState, today)) continue;
    sum += left * 100 * t.premium;
  }
  return sum;
}

// ─────────────────────────────────────────────────────────────────────────────
// A10 — Open Long Premium (capital still outstanding on long opens)
// ─────────────────────────────────────────────────────────────────────────────

/** Σ (remaining_contracts × 100 × open premium) for still-open long legs. */
export function openLongPremium(
  trades: OptionTrade[],
  f?: AtomFilter,
  today: string = todayIsoUTC(),
): number {
  const remaining = remainingByOpenId(trades);
  let sum = 0;
  for (const t of trades) {
    if (t.action !== "open" || t.direction !== "long") continue;
    const left = remaining.get(t.id) ?? 0;
    if (left <= 0) continue;
    if (!passesTradeFilter(t, f)) continue;
    if (!matchesLiveState(t.expiry, f?.liveState, today)) continue;
    sum += left * 100 * t.premium;
  }
  return sum;
}

// ─────────────────────────────────────────────────────────────────────────────
// A11 — Live Leg Count
// ─────────────────────────────────────────────────────────────────────────────

/** Number of distinct still-open option legs (one leg = one open row with
 *  remaining contracts > 0). Filterable by call/put × short/long × live state
 *  × ticker. */
export function liveLegCount(
  trades: OptionTrade[],
  f?: AtomFilter,
  today: string = todayIsoUTC(),
): number {
  const remaining = remainingByOpenId(trades);
  let n = 0;
  for (const t of trades) {
    if (t.action !== "open") continue;
    const left = remaining.get(t.id) ?? 0;
    if (left <= 0) continue;
    if (!passesTradeFilter(t, f)) continue;
    if (!matchesLiveState(t.expiry, f?.liveState, today)) continue;
    n += 1;
  }
  return n;
}

// ─────────────────────────────────────────────────────────────────────────────
// A12 — Historical Portfolio Value
// ─────────────────────────────────────────────────────────────────────────────

/** Σ (today's quantity × carry-forward close-price on `date`) over open
 *  positions. "Carry-forward" = if a ticker has no close on `date`, use the
 *  most recent prior close; before its earliest close, use its earliest close;
 *  if it has no closes at all, fall back to `current_price ?? avg_cost`.
 *
 *  Returns a function so callers can call it many times with the same prebuilt
 *  index (cheaper than rebuilding for each date in a time series).
 *
 *  Note: this back-projects *today's* share count against historical prices.
 *  It's a clean mark-to-market series for *currently held* positions, not a
 *  true historical NAV (won't pick up shares since-sold). Will sharpen when
 *  share_lots (PL-B) lands. */
export function historicalPortfolioValue(
  positions: PositionRow[],
  closes: DailyClose[],
): (date: string, f?: AtomFilter) => number {
  // Per-ticker sorted close series + per-ticker fallback price.
  const byTicker = new Map<string, { date: string; close: number }[]>();
  for (const c of closes) {
    if (!byTicker.has(c.ticker)) byTicker.set(c.ticker, []);
    byTicker.get(c.ticker)!.push({ date: c.date, close: c.close_price });
  }
  for (const arr of byTicker.values()) arr.sort((a, b) => a.date.localeCompare(b.date));

  return (date: string, f?: AtomFilter): number => {
    let sum = 0;
    for (const p of positions) {
      if (p.status === "closed" || p.quantity <= 0) continue;
      if (!passesPositionFilter(p, f)) continue;
      const series = byTicker.get(p.ticker);
      const fallback = p.current_price ?? p.avg_cost ?? 0;
      let price = fallback;
      if (series && series.length > 0) {
        // Linear scan: find the last entry with date <= target.
        // Acceptable: closes are bounded and this lives inside a memoizable hook.
        let chosen = series[0].close; // earliest, used for dates before first close
        for (const e of series) {
          if (e.date <= date) chosen = e.close;
          else break;
        }
        price = chosen;
      }
      sum += p.quantity * price;
    }
    return sum;
  };
}
