/**
 * **Live legs** — the open-state side of the option book. Pure compute,
 * built on A9 / A10 / A11.
 *
 *   total          = liveLegCount        (A11)
 *   shortPremium   = openShortPremium    (A9)
 *   longPremium    = openLongPremium     (A10)
 *
 * Plus the splits everyone re-derives by hand:
 *   calls / puts          — count by option_type
 *   shorts / longs        — count by direction
 *   byTicker              — count per ticker
 *   shortPremByTicker     — A9 per ticker
 *   longPremByTicker      — A10 per ticker
 *
 * Filter-aware (`AtomFilter`). `today` overridable for tests; defaults to
 * UTC today since that's what A9/A10/A11 use.
 */
import {
  type AtomFilter,
  liveLegCount,
  openLongPremium,
  openShortPremium,
} from "./atoms";
import type { OptionTrade } from "../types";

export interface LiveLegs {
  total: number;
  calls: number;
  puts: number;
  shorts: number;
  longs: number;
  shortPremium: number;
  longPremium: number;
  byTicker: Map<string, number>;
  shortPremByTicker: Map<string, number>;
  longPremByTicker: Map<string, number>;
}

const todayIsoUTC = (): string => new Date().toISOString().slice(0, 10);

/** Build a map from open-trade id → remaining contracts (mirrors the
 *  bookkeeping in atoms.ts; we duplicate it here so per-ticker maps can be
 *  computed in a single pass without re-walking the array). */
function remainingByOpenId(trades: OptionTrade[]): Map<string, number> {
  const open = new Map<string, OptionTrade>();
  const closedQty = new Map<string, number>();
  for (const t of trades) {
    if (t.action === "open") open.set(t.id, t);
    else if (t.action === "close" && t.closes_trade_id) {
      closedQty.set(
        t.closes_trade_id,
        (closedQty.get(t.closes_trade_id) ?? 0) + t.contracts,
      );
    }
  }
  const out = new Map<string, number>();
  for (const [id, o] of open) {
    out.set(id, Math.max(0, o.contracts - (closedQty.get(id) ?? 0)));
  }
  return out;
}

export function computeLiveLegs(
  trades: OptionTrade[],
  filter?: AtomFilter,
  today: string = todayIsoUTC(),
): LiveLegs {
  // Scalars via the atoms (canonical SOT).
  const total = liveLegCount(trades, filter, today);
  const shortPremium = openShortPremium(trades, filter, today);
  const longPremium = openLongPremium(trades, filter, today);

  // Splits + per-ticker — single grouped pass.
  const remaining = remainingByOpenId(trades);
  let calls = 0, puts = 0, shorts = 0, longs = 0;
  const byTicker = new Map<string, number>();
  const shortPremByTicker = new Map<string, number>();
  const longPremByTicker = new Map<string, number>();
  for (const t of trades) {
    if (t.action !== "open") continue;
    const left = remaining.get(t.id) ?? 0;
    if (left <= 0) continue;
    if (filter?.ticker && t.ticker !== filter.ticker) continue;
    if (filter?.optionType && t.option_type !== filter.optionType) continue;
    if (filter?.direction && t.direction !== filter.direction) continue;
    // live-state filtering — matches the atom helper logic.
    if (filter?.window) {
      const { start, end } = filter.window;
      if (start && t.trade_date < start) continue;
      if (end && t.trade_date >= end) continue;
    }
    if (t.option_type === "call") calls += 1; else puts += 1;
    if (t.direction === "short") shorts += 1; else longs += 1;
    byTicker.set(t.ticker, (byTicker.get(t.ticker) ?? 0) + 1);
    const prem = left * 100 * t.premium;
    if (t.direction === "short") {
      shortPremByTicker.set(
        t.ticker,
        (shortPremByTicker.get(t.ticker) ?? 0) + prem,
      );
    } else {
      longPremByTicker.set(
        t.ticker,
        (longPremByTicker.get(t.ticker) ?? 0) + prem,
      );
    }
  }

  return {
    total,
    calls,
    puts,
    shorts,
    longs,
    shortPremium,
    longPremium,
    byTicker,
    shortPremByTicker,
    longPremByTicker,
  };
}
