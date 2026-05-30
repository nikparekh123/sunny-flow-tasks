/**
 * Regression net for unrealized P&L. The legacy `computePortfolio.total_pnl`
 * field has been deleted (M9) — these tests now reproduce the canonical
 * per-row formula (`market_value − cost_basis`, with stale-price fallback to
 * avg_cost) inline so the atom calc can't drift silently.
 */
import { describe, expect, it } from "vitest";
import type { PositionRow } from "../types";
import { computeUnrealizedPL } from "./unrealizedPL";

/** Inline canonical: Σ qty × (current_price ?? avg_cost) − Σ qty × avg_cost
 *  over open positions with qty > 0. */
function expectedUnrealized(positions: PositionRow[]): number {
  let mv = 0, cb = 0;
  for (const p of positions) {
    if (p.status === "closed" || p.quantity <= 0) continue;
    mv += p.quantity * (p.current_price ?? p.avg_cost);
    cb += p.quantity * p.avg_cost;
  }
  return mv - cb;
}

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

describe("computeUnrealizedPL — canonical regression net", () => {
  it("matches inline canonical on a typical multi-position fixture", () => {
    const positions: PositionRow[] = [
      pos({ ticker: "AAPL", quantity: 100, avg_cost: 150, current_price: 200 }),
      pos({ ticker: "MSFT", quantity: 50, avg_cost: 300, current_price: 400 }),
      pos({ ticker: "NVDA", quantity: 30, avg_cost: 500, current_price: 480 }),
    ];
    const atom = computeUnrealizedPL(positions);
    expect(atom.total).toBeCloseTo(expectedUnrealized(positions), 6);
    // Sanity: 5,000 + 5,000 + (-600) = 9,400
    expect(atom.total).toBe(9_400);
  });

  it("falls back to avg_cost when current_price is null", () => {
    const positions: PositionRow[] = [
      pos({ ticker: "AAPL", quantity: 100, avg_cost: 150, current_price: 200 }),
      pos({ ticker: "STALE", quantity: 50, avg_cost: 100, current_price: null }),
    ];
    const atom = computeUnrealizedPL(positions);
    expect(atom.total).toBeCloseTo(expectedUnrealized(positions), 6);
    // Stale contributes $0 unrealized, AAPL contributes 5,000.
    expect(atom.total).toBe(5_000);
  });

  it("excludes closed positions", () => {
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
    const atom = computeUnrealizedPL(positions);
    expect(atom.total).toBeCloseTo(expectedUnrealized(positions), 6);
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
