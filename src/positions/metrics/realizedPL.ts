/**
 * **Realized P&L = A3 + A8** — pure compute.
 *
 *   shares     = sharesRealized      (A3 — gains from selling shares)
 *   options    = optionRealized      (A8 — closed option pairs)
 *   total      = shares + options
 *
 * This is the canonical "money booked" — paper gains crystallized into
 * cash. Distinct from Income (A4 − A6, which is the *premium-flow* side of
 * the options business) and from Unrealized (A1 − A2, paper marks).
 *
 * Filter notes:
 *  - `ticker` narrows both A3 (share sells) and A8 (option closes).
 *  - `window` narrows by:
 *      A3 → share_sells.trade_date
 *      A8 → option_trades.trade_date of the CLOSE row (when it was realized)
 *  - `direction` / `optionType` apply only to A8 (they're option fields).
 *    Setting them filters A8 but does NOT filter A3 — share sells have
 *    no direction or option_type, so a "puts-only realized" with
 *    `optionType:"put"` excludes share-realized entirely.
 */
import {
  type AtomFilter,
  optionRealized,
  sharesRealized,
} from "./atoms";
import type { OptionTrade, ShareSell } from "../types";

export interface RealizedPL {
  shares: number;
  options: number;
  total: number;
  /** Per-ticker total (shares + options). */
  byTicker: Map<string, number>;
}

export function computeRealizedPL(
  trades: OptionTrade[],
  sells: ShareSell[],
  filter?: AtomFilter,
): RealizedPL {
  // If the caller restricted to options-only fields (optionType / direction),
  // share-realized is structurally excluded.
  const sharesIncluded = !filter?.optionType && !filter?.direction;
  const shares = sharesIncluded ? sharesRealized(sells, filter) : 0;
  const options = optionRealized(trades, filter);
  const total = shares + options;

  // Per-ticker: single pass through both sources.
  const byTicker = new Map<string, number>();
  if (sharesIncluded) {
    for (const s of sells) {
      if (filter?.ticker && s.ticker !== filter.ticker) continue;
      if (filter?.window) {
        const { start, end } = filter.window;
        if (start && s.trade_date < start) continue;
        if (end && s.trade_date >= end) continue;
      }
      byTicker.set(s.ticker, (byTicker.get(s.ticker) ?? 0) + s.realized_pl);
    }
  }
  // For A8 per-ticker, re-walk closes paired with opens (same logic as the
  // atom uses, but accumulated by ticker).
  const byId = new Map<string, OptionTrade>();
  for (const t of trades) byId.set(t.id, t);
  for (const c of trades) {
    if (c.action !== "close" || !c.closes_trade_id) continue;
    const o = byId.get(c.closes_trade_id);
    if (!o) continue;
    if (filter?.ticker && c.ticker !== filter.ticker) continue;
    if (filter?.optionType && o.option_type !== filter.optionType) continue;
    if (filter?.direction && o.direction !== filter.direction) continue;
    if (filter?.window) {
      const { start, end } = filter.window;
      if (start && c.trade_date < start) continue;
      if (end && c.trade_date >= end) continue;
    }
    const perShare = o.direction === "short"
      ? o.premium - c.premium
      : c.premium - o.premium;
    const $ = perShare * c.contracts * 100;
    byTicker.set(c.ticker, (byTicker.get(c.ticker) ?? 0) + $);
  }

  return { shares, options, total, byTicker };
}
