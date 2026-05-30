/**
 * Parity test: the atom-based unrealized P&L must agree with the legacy
 * `computePortfolio.total_pnl` on representative fixtures. This is what
 * lets us swap the source-of-truth without changing any displayed number.
 *
 * Once every page reads from `useUnrealizedPL`, `computePortfolio.total_pnl`
 * can be deleted — this test will be the last thing referencing it.
 */
import { describe, expect, it } from "vitest";
import {
  computePortfolio,
  type OptionTrade,
  type PositionRow,
} from "../types";
import { computeUnrealizedPL } from "./unrealizedPL";

let _seq = 0;
const pos = (over: Partial<PositionRow> = {}): PositionRow => ({
  id: "p-" + ++_seq,
  ticker: "AAPL",
  name: "Apple",
  sector: "Technology",
  quantity: 100,
  avg_cost: 150,
  current_price: 200,
  prev_close: 198,
  last_price_update: "2026-05-29",
  status: "open",
  earnings_date: null,
  realized_stock_pl: 0,
  ...over,
});

describe("useUnrealizedPL parity with computePortfolio", () => {
  it("matches on a typical multi-position fixture", () => {
    const positions: PositionRow[] = [
      pos({ ticker: "AAPL", quantity: 100, avg_cost: 150, current_price: 200 }),
      pos({ ticker: "MSFT", quantity: 50, avg_cost: 300, current_price: 400 }),
      pos({ ticker: "NVDA", quantity: 30, avg_cost: 500, current_price: 480 }),
    ];
    const legacy = computePortfolio(positions, [] as OptionTrade[]);
    const atom = computeUnrealizedPL(positions);
    expect(atom.total).toBeCloseTo(legacy.total_pnl, 6);
    expect(atom.totalPct).toBeCloseTo(legacy.total_pnl_pct, 6);
  });

  it("matches when a position has a null current_price (stale-price fallback)", () => {
    const positions: PositionRow[] = [
      pos({ ticker: "AAPL", quantity: 100, avg_cost: 150, current_price: 200 }),
      pos({ ticker: "STALE", quantity: 50, avg_cost: 100, current_price: null }),
    ];
    const legacy = computePortfolio(positions, [] as OptionTrade[]);
    const atom = computeUnrealizedPL(positions);
    expect(atom.total).toBeCloseTo(legacy.total_pnl, 6);
  });

  it("excludes closed positions in both", () => {
    const positions: PositionRow[] = [
      pos({ ticker: "AAPL", quantity: 100, avg_cost: 150, current_price: 200 }),
      pos({
        ticker: "OLD",
        quantity: 50,
        avg_cost: 100,
        current_price: 50, // would be a big loss if counted
        status: "closed",
      }),
    ];
    const legacy = computePortfolio(positions, [] as OptionTrade[]);
    const atom = computeUnrealizedPL(positions);
    expect(atom.total).toBeCloseTo(legacy.total_pnl, 6);
    // Sanity: only AAPL contributes.
    expect(atom.total).toBe(5_000);
  });

  it("byTicker map sums to total", () => {
    const positions: PositionRow[] = [
      pos({ ticker: "AAPL", quantity: 100, avg_cost: 150, current_price: 200 }),
      pos({ ticker: "MSFT", quantity: 50, avg_cost: 300, current_price: 400 }),
    ];
    const atom = computeUnrealizedPL(positions);
    const sum = Array.from(atom.byTicker.values()).reduce((s, v) => s + v, 0);
    expect(sum).toBeCloseTo(atom.total, 6);
    expect(atom.byTicker.get("AAPL")).toBe(5_000);
    expect(atom.byTicker.get("MSFT")).toBe(5_000);
  });

  it("filters by ticker", () => {
    const positions: PositionRow[] = [
      pos({ ticker: "AAPL", quantity: 100, avg_cost: 150, current_price: 200 }),
      pos({ ticker: "MSFT", quantity: 50, avg_cost: 300, current_price: 400 }),
    ];
    const onlyAAPL = computeUnrealizedPL(positions, { ticker: "AAPL" });
    expect(onlyAAPL.total).toBe(5_000);
    expect(onlyAAPL.byTicker.size).toBe(1);
  });
});
