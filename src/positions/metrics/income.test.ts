/**
 * Tests for the canonical Income = A4 − A6.
 *
 * Includes a parity check vs the raw atoms — useful as a regression net
 * if either A4 or A6 ever drifts (e.g. someone adds a new short-side
 * flow type and forgets to update both).
 */
import { describe, expect, it } from "vitest";
import type { OptionTrade } from "../types";
import { debitCloseShort, premiumCollected } from "./atoms";
import { computeIncome } from "./income";

let _seq = 0;
const t = (over: Partial<OptionTrade> = {}): OptionTrade => ({
  id: "t-" + ++_seq,
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

describe("computeIncome", () => {
  it("net = A4 − A6 (parity)", () => {
    const trades = [
      t({ direction: "short", action: "open", contracts: 2, premium: 3 }),
      t({ direction: "short", action: "open", option_type: "put", contracts: 1, premium: 4 }),
      t({ direction: "short", action: "close", contracts: 1, premium: 1 }),
    ];
    const inc = computeIncome(trades);
    expect(inc.collected).toBe(premiumCollected(trades));
    expect(inc.debit).toBe(debitCloseShort(trades));
    expect(inc.net).toBe(inc.collected - inc.debit);
  });

  it("ignores long opens/closes (canonical: options short-side only)", () => {
    const trades = [
      t({ direction: "short", action: "open", contracts: 1, premium: 2 }), // +200
      t({ direction: "long", action: "open", contracts: 1, premium: 5 }), // skip
      t({ direction: "long", action: "close", contracts: 1, premium: 6 }), // skip
    ];
    const inc = computeIncome(trades);
    expect(inc.collected).toBe(200);
    expect(inc.debit).toBe(0);
    expect(inc.net).toBe(200);
  });

  it("windows by trade_date", () => {
    const trades = [
      t({ trade_date: "2026-04-15", action: "open", contracts: 1, premium: 2 }), // +200, out of window
      t({ trade_date: "2026-05-15", action: "open", contracts: 1, premium: 3 }), // +300
      t({ trade_date: "2026-05-20", action: "close", contracts: 1, premium: 1 }), // −100
    ];
    const inc = computeIncome(trades, {
      window: { start: "2026-05-01", end: "2026-06-01" },
    });
    expect(inc.collected).toBe(300);
    expect(inc.debit).toBe(100);
    expect(inc.net).toBe(200);
  });

  it("filters by option_type (e.g. puts-only income)", () => {
    const trades = [
      t({ option_type: "call", action: "open", contracts: 1, premium: 2 }),
      t({ option_type: "put", action: "open", contracts: 1, premium: 3 }),
    ];
    expect(computeIncome(trades, { optionType: "put" }).net).toBe(300);
    expect(computeIncome(trades, { optionType: "call" }).net).toBe(200);
  });

  it("byTicker map sums to net", () => {
    const trades = [
      t({ ticker: "AAPL", action: "open", contracts: 1, premium: 2 }), // +200
      t({ ticker: "AAPL", action: "close", contracts: 1, premium: 0.5 }), // −50
      t({ ticker: "MSFT", action: "open", contracts: 1, premium: 4 }), // +400
    ];
    const inc = computeIncome(trades);
    const sum = Array.from(inc.byTicker.values()).reduce((s, v) => s + v, 0);
    expect(sum).toBeCloseTo(inc.net, 6);
    expect(inc.byTicker.get("AAPL")).toBe(150);
    expect(inc.byTicker.get("MSFT")).toBe(400);
  });

  it("ticker filter narrows both collected and debit", () => {
    const trades = [
      t({ ticker: "AAPL", action: "open", contracts: 1, premium: 2 }),
      t({ ticker: "MSFT", action: "open", contracts: 1, premium: 4 }),
    ];
    const aapl = computeIncome(trades, { ticker: "AAPL" });
    expect(aapl.net).toBe(200);
    expect(aapl.byTicker.size).toBe(1);
  });
});
