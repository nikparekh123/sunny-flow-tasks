/**
 * Tests for computeProtection — A5 − A7 parity + per-ticker.
 */
import { describe, expect, it } from "vitest";
import type { OptionTrade } from "../types";
import { creditCloseLong, premiumPaid } from "./atoms";
import { computeProtection } from "./protection";

let _t = 0;
const trade = (over: Partial<OptionTrade> = {}): OptionTrade => ({
  id: "t-" + ++_t,
  ticker: "AAPL",
  trade_date: "2026-05-15",
  action: "open",
  option_type: "put",
  direction: "long",
  contracts: 1,
  strike: 180,
  premium: 3,
  expiry: "2026-06-19",
  closes_trade_id: null,
  note: null,
  created_at: "2026-05-15",
  updated_at: "2026-05-15",
  closed_via: null,
  share_pnl: 0,
  ...over,
});

describe("computeProtection (A5 − A7)", () => {
  it("netCost = A5 − A7 parity", () => {
    const trades = [
      trade({ direction: "long", action: "open", contracts: 2, premium: 3 }), // paid 600
      trade({ direction: "long", action: "close", contracts: 1, premium: 1 }), // credit 100
    ];
    const p = computeProtection(trades);
    expect(p.paid).toBe(premiumPaid(trades));
    expect(p.closeCredit).toBe(creditCloseLong(trades));
    expect(p.netCost).toBe(p.paid - p.closeCredit);
    expect(p.netCost).toBe(500);
  });

  it("ignores short opens/closes (long-side only)", () => {
    const trades = [
      trade({ direction: "long", action: "open", contracts: 1, premium: 2 }), // 200 paid
      trade({ direction: "short", action: "open", contracts: 1, premium: 5 }), // ignore
      trade({ direction: "short", action: "close", contracts: 1, premium: 3 }), // ignore
    ];
    const p = computeProtection(trades);
    expect(p.paid).toBe(200);
    expect(p.closeCredit).toBe(0);
    expect(p.netCost).toBe(200);
  });

  it("windows + ticker filter", () => {
    const trades = [
      trade({ ticker: "AAPL", trade_date: "2026-05-10", action: "open", contracts: 1, premium: 2 }), // 200
      trade({ ticker: "AAPL", trade_date: "2026-04-10", action: "open", contracts: 1, premium: 5 }), // out of window
      trade({ ticker: "MSFT", trade_date: "2026-05-10", action: "open", contracts: 1, premium: 3 }), // 300
    ];
    const aaplWindow = computeProtection(trades, {
      ticker: "AAPL",
      window: { start: "2026-05-01" },
    });
    expect(aaplWindow.netCost).toBe(200);
  });

  it("byTicker sums to netCost", () => {
    const trades = [
      trade({ ticker: "AAPL", action: "open", contracts: 1, premium: 2 }),
      trade({ ticker: "AAPL", action: "close", contracts: 1, premium: 0.5 }),
      trade({ ticker: "MSFT", action: "open", contracts: 1, premium: 3 }),
    ];
    const p = computeProtection(trades);
    const sum = Array.from(p.byTicker.values()).reduce((s, v) => s + v, 0);
    expect(sum).toBeCloseTo(p.netCost, 6);
    expect(p.byTicker.get("AAPL")).toBe(150); // 200 − 50
    expect(p.byTicker.get("MSFT")).toBe(300);
  });
});
