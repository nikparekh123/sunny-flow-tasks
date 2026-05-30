/**
 * **Protection cost** = A5 − A7 — pure compute.
 *
 *   paid          = premiumPaid       (A5 — long opens, cash out)
 *   closeCredit   = creditCloseLong   (A7 — long closes, cash back)
 *   netCost       = paid − closeCredit
 *
 * This is the long-leg side of the option book — what we spent on
 * protection (long puts, long calls) net of what we got back from closing
 * those positions. Negative netCost = we made money on the protection
 * book. Positive netCost = it cost us (as is usually the case for
 * insurance).
 *
 * Distinct from Income (short-side, A4 − A6) and from Realized P&L (A3 +
 * A8 — already includes A8 = paired option close P&L, of which A5/A7
 * activity is one input).
 */
import {
  type AtomFilter,
  creditCloseLong,
  premiumPaid,
} from "./atoms";
import type { OptionTrade } from "../types";

export interface Protection {
  paid: number;
  closeCredit: number;
  netCost: number;
  /** Per-ticker net cost. */
  byTicker: Map<string, number>;
}

export function computeProtection(
  trades: OptionTrade[],
  filter?: AtomFilter,
): Protection {
  const paid = premiumPaid(trades, filter);
  const closeCredit = creditCloseLong(trades, filter);
  const netCost = paid - closeCredit;

  const paidByTicker = new Map<string, number>();
  const creditByTicker = new Map<string, number>();
  for (const t of trades) {
    if (t.direction !== "long") continue;
    if (filter?.ticker && t.ticker !== filter.ticker) continue;
    if (filter?.optionType && t.option_type !== filter.optionType) continue;
    if (filter?.window) {
      const { start, end } = filter.window;
      if (start && t.trade_date < start) continue;
      if (end && t.trade_date >= end) continue;
    }
    const $ = t.contracts * 100 * t.premium;
    if (t.action === "open") {
      paidByTicker.set(t.ticker, (paidByTicker.get(t.ticker) ?? 0) + $);
    } else {
      creditByTicker.set(t.ticker, (creditByTicker.get(t.ticker) ?? 0) + $);
    }
  }
  const byTicker = new Map<string, number>();
  const tickers = new Set([...paidByTicker.keys(), ...creditByTicker.keys()]);
  for (const t of tickers) {
    byTicker.set(
      t,
      (paidByTicker.get(t) ?? 0) - (creditByTicker.get(t) ?? 0),
    );
  }

  return { paid, closeCredit, netCost, byTicker };
}
