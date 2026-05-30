/**
 * **Income = A4 − A6** — pure compute.
 *
 *   collected = premiumCollected (short opens, $ in)
 *   debit     = debitCloseShort  (short closes, $ out)
 *   net       = collected − debit       ← canonical "Net premium kept"
 *
 * This is the locked definition from `docs/METRICS.md`: rent on an asset
 * after expenses, options-only. Share-realized P&L (A3) is NOT income —
 * it belongs in Realized P&L (A3 + A8). Long-leg flows (A5, A7) are out
 * of scope here.
 *
 * Pure file (no React, no Supabase). The React hook `useIncome()` wraps
 * this.
 */
import {
  type AtomFilter,
  debitCloseShort,
  premiumCollected,
} from "./atoms";
import type { OptionTrade } from "../types";

export interface Income {
  collected: number;
  debit: number;
  net: number;
  /** Per-ticker net income. Tickers with zero activity in the window are omitted. */
  byTicker: Map<string, number>;
}

export function computeIncome(trades: OptionTrade[], filter?: AtomFilter): Income {
  const collected = premiumCollected(trades, filter);
  const debit = debitCloseShort(trades, filter);
  const net = collected - debit;

  // Per-ticker single pass — avoids re-filtering twice per ticker.
  const collectedByTicker = new Map<string, number>();
  const debitByTicker = new Map<string, number>();
  for (const t of trades) {
    if (t.direction !== "short") continue;
    if (filter?.ticker && t.ticker !== filter.ticker) continue;
    if (filter?.optionType && t.option_type !== filter.optionType) continue;
    if (filter?.window) {
      const { start, end } = filter.window;
      if (start && t.trade_date < start) continue;
      if (end && t.trade_date >= end) continue;
    }
    const $ = t.contracts * 100 * t.premium;
    if (t.action === "open") {
      collectedByTicker.set(t.ticker, (collectedByTicker.get(t.ticker) ?? 0) + $);
    } else {
      debitByTicker.set(t.ticker, (debitByTicker.get(t.ticker) ?? 0) + $);
    }
  }
  const byTicker = new Map<string, number>();
  const tickers = new Set([
    ...collectedByTicker.keys(),
    ...debitByTicker.keys(),
  ]);
  for (const t of tickers) {
    byTicker.set(
      t,
      (collectedByTicker.get(t) ?? 0) - (debitByTicker.get(t) ?? 0),
    );
  }

  return { collected, debit, net, byTicker };
}
