/**
 * Tests for A13–A17 Greeks atoms.
 *
 * Position-level contribution = per-share × remaining_contracts × 100 ×
 * side_sign (−1 short, +1 long). Stock = qty for delta, 0 elsewhere.
 */
import { describe, expect, it } from "vitest";
import type { OptionTrade, PositionRow } from "../types";
import {
  type LegGreek, type TickerQuote,
  betaWeightedDelta, portfolioDelta, portfolioGamma, portfolioTheta, portfolioVega,
} from "./greeksAtoms";

const TODAY = "2026-05-29";

let _p = 0, _t = 0;
const pos = (over: Partial<PositionRow> = {}): PositionRow => ({
  id: "p-" + ++_p,
  ticker: "AAPL",
  name: "Apple",
  sector: "Technology",
  quantity: 100,
  avg_cost: 150,
  current_price: 200,
  prev_close: 198,
  last_price_update: TODAY,
  status: "open",
  earnings_date: null,
  realized_stock_pl: 0,
  ...over,
});
const trade = (over: Partial<OptionTrade> = {}): OptionTrade => ({
  id: "t-" + ++_t,
  ticker: "AAPL",
  trade_date: "2026-05-15",
  action: "open",
  option_type: "call",
  direction: "short",
  contracts: 1,
  strike: 200,
  premium: 2,
  expiry: "2026-06-19",
  closes_trade_id: null,
  note: null,
  created_at: "2026-05-15",
  updated_at: "2026-05-15",
  closed_via: null,
  share_pnl: 0,
  ...over,
});
const g = (over: Partial<LegGreek> & { option_trade_id: string }): LegGreek => ({
  delta: null, gamma: null, theta: null, vega: null, ...over,
});

describe("A13 portfolioDelta", () => {
  it("sums shares + leg deltas with correct side sign", () => {
    const positions = [
      pos({ ticker: "AAPL", quantity: 100 }),  // +100 Δ
      pos({ ticker: "MSFT", quantity: 50 }),   // +50 Δ
    ];
    const trades = [
      // Short call: per-share delta 0.32 × 1 contract × 100 × −1 = −32
      trade({ id: "sc", ticker: "AAPL", direction: "short", option_type: "call", contracts: 1 }),
      // Long put: per-share delta −0.40 × 2 × 100 × +1 = −80
      trade({ id: "lp", ticker: "MSFT", direction: "long", option_type: "put", contracts: 2 }),
    ];
    const greeks: LegGreek[] = [
      g({ option_trade_id: "sc", delta: 0.32 }),
      g({ option_trade_id: "lp", delta: -0.40 }),
    ];
    // 100 + 50 + (−32) + (−80) = 38
    expect(portfolioDelta(positions, trades, greeks, undefined, TODAY)).toBe(38);
  });

  it("respects partial closes (remaining contracts only)", () => {
    const open = trade({ id: "o", direction: "short", contracts: 3 });
    const close = trade({ action: "close", direction: "short", contracts: 1, closes_trade_id: "o" });
    const greeks: LegGreek[] = [g({ option_trade_id: "o", delta: 0.50 })];
    // 2 remaining × 100 × 0.50 × −1 = −100
    expect(portfolioDelta([], [open, close], greeks, undefined, TODAY)).toBe(-100);
  });

  it("ticker filter narrows both stock and legs", () => {
    const positions = [
      pos({ ticker: "AAPL", quantity: 100 }),
      pos({ ticker: "MSFT", quantity: 50 }),
    ];
    const trades = [
      trade({ id: "a1", ticker: "AAPL", direction: "short", contracts: 1 }),
      trade({ id: "m1", ticker: "MSFT", direction: "short", contracts: 1 }),
    ];
    const greeks: LegGreek[] = [
      g({ option_trade_id: "a1", delta: 0.50 }),
      g({ option_trade_id: "m1", delta: 0.80 }),
    ];
    // AAPL only: 100 + (−50) = 50
    expect(portfolioDelta(positions, trades, greeks, { ticker: "AAPL" }, TODAY)).toBe(50);
  });

  it("missing greeks fall back to 0 (no contribution) — page renders before mp-refresh", () => {
    const positions = [pos({ quantity: 100 })];
    const trades = [trade({ id: "x", direction: "short", contracts: 1 })];
    const greeks: LegGreek[] = []; // empty
    // Only the stock contributes; leg contributes 0.
    expect(portfolioDelta(positions, trades, greeks, undefined, TODAY)).toBe(100);
  });

  it("optionType filter narrows legs but keeps stock", () => {
    const positions = [pos({ ticker: "AAPL", quantity: 100 })];
    const trades = [
      trade({ id: "sc", direction: "short", option_type: "call", contracts: 1 }),
      trade({ id: "sp", direction: "short", option_type: "put", contracts: 1 }),
    ];
    const greeks: LegGreek[] = [
      g({ option_trade_id: "sc", delta: 0.30 }),
      g({ option_trade_id: "sp", delta: -0.25 }),
    ];
    // Stock 100 + short call (−30) only. Short put excluded.
    expect(portfolioDelta(positions, trades, greeks, { optionType: "call" }, TODAY)).toBe(70);
  });
});

describe("A14 portfolioGamma / A15 portfolioTheta / A16 portfolioVega", () => {
  it("stock contributes 0 to gamma/theta/vega", () => {
    // No legs at all ⇒ zero for all three (stock has no Γ/Θ/V).
    expect(portfolioGamma([], [], undefined, TODAY)).toBe(0);
    expect(portfolioTheta([], [], undefined, TODAY)).toBe(0);
    expect(portfolioVega ([], [], undefined, TODAY)).toBe(0);
  });

  it("short option flips sign on all four greeks", () => {
    const open = trade({ id: "sc", direction: "short", contracts: 1 });
    const greeks: LegGreek[] = [g({ option_trade_id: "sc", delta: 0.50, gamma: 0.08, theta: -0.40, vega: 0.30 })];
    // Each: per-share × 1 × 100 × −1
    expect(portfolioDelta([], [open], greeks, undefined, TODAY)).toBe(-50);
    expect(portfolioGamma([open], greeks, undefined, TODAY)).toBe(-8);
    expect(portfolioTheta([open], greeks, undefined, TODAY)).toBe(40);  // short theta is positive (collecting)
    expect(portfolioVega ([open], greeks, undefined, TODAY)).toBe(-30);
  });
});

describe("A17 betaWeightedDelta", () => {
  it("multiplies per-ticker delta by ticker beta", () => {
    const positions = [
      pos({ ticker: "AAPL", quantity: 100 }),  // Δ +100
      pos({ ticker: "MSFT", quantity: 50 }),   // Δ +50
    ];
    const trades: OptionTrade[] = [];
    const greeks: LegGreek[] = [];
    const quotes: TickerQuote[] = [
      { ticker: "AAPL", beta: 1.20 },
      { ticker: "MSFT", beta: 0.90 },
    ];
    // 100 × 1.20 + 50 × 0.90 = 120 + 45 = 165
    expect(betaWeightedDelta(positions, trades, greeks, quotes, undefined, TODAY)).toBe(165);
  });

  it("missing beta defaults to 1.0 (treat as market-following)", () => {
    const positions = [pos({ ticker: "AAPL", quantity: 100 })];
    const quotes: TickerQuote[] = []; // no beta data
    expect(betaWeightedDelta(positions, [], [], quotes, undefined, TODAY)).toBe(100);
  });

  it("includes option legs in the per-ticker delta before β-weighting", () => {
    const positions = [pos({ ticker: "AAPL", quantity: 100 })];
    const trades = [trade({ id: "sc", ticker: "AAPL", direction: "short", contracts: 1 })];
    const greeks: LegGreek[] = [g({ option_trade_id: "sc", delta: 0.30 })];
    const quotes: TickerQuote[] = [{ ticker: "AAPL", beta: 1.20 }];
    // AAPL delta = 100 + (−30) = 70 → 70 × 1.20 = 84
    expect(betaWeightedDelta(positions, trades, greeks, quotes, undefined, TODAY)).toBe(84);
  });
});
