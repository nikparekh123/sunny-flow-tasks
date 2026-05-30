/**
 * Tests for computeLiveLegs — agreement with A9 / A10 / A11 + per-ticker maps.
 */
import { describe, expect, it } from "vitest";
import type { OptionTrade } from "../types";
import {
  liveLegCount,
  openLongPremium,
  openShortPremium,
} from "./atoms";
import { computeLiveLegs } from "./liveLegs";

const TODAY = "2026-05-29";

let _t = 0;
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

describe("computeLiveLegs — parity with A9/A10/A11", () => {
  it("scalars match the atoms", () => {
    const trades = [
      trade({ direction: "short", option_type: "call", contracts: 2, premium: 3 }),
      trade({ direction: "short", option_type: "put", contracts: 1, premium: 5 }),
      trade({ direction: "long", option_type: "put", contracts: 1, premium: 4 }),
    ];
    const live = computeLiveLegs(trades, undefined, TODAY);
    expect(live.total).toBe(liveLegCount(trades, undefined, TODAY));
    expect(live.shortPremium).toBe(openShortPremium(trades, undefined, TODAY));
    expect(live.longPremium).toBe(openLongPremium(trades, undefined, TODAY));
    expect(live.calls).toBe(1);
    expect(live.puts).toBe(2);
    expect(live.shorts).toBe(2);
    expect(live.longs).toBe(1);
  });

  it("byTicker count + premium splits", () => {
    const trades = [
      trade({ id: "a1", ticker: "AAPL", direction: "short", contracts: 1, premium: 2 }), // sp=200
      trade({ id: "a2", ticker: "AAPL", direction: "long", contracts: 1, premium: 5 }),  // lp=500
      trade({ id: "m1", ticker: "MSFT", direction: "short", contracts: 2, premium: 3 }), // sp=600
    ];
    const live = computeLiveLegs(trades, undefined, TODAY);
    expect(live.byTicker.get("AAPL")).toBe(2);
    expect(live.byTicker.get("MSFT")).toBe(1);
    expect(live.shortPremByTicker.get("AAPL")).toBe(200);
    expect(live.longPremByTicker.get("AAPL")).toBe(500);
    expect(live.shortPremByTicker.get("MSFT")).toBe(600);
    // Map sums to scalars
    const sumShort = Array.from(live.shortPremByTicker.values()).reduce((s, v) => s + v, 0);
    expect(sumShort).toBe(live.shortPremium);
  });

  it("respects partial closes", () => {
    const open = trade({ id: "o", direction: "short", contracts: 3, premium: 2 });
    const close = trade({
      action: "close",
      direction: "short",
      contracts: 1,
      premium: 1,
      closes_trade_id: "o",
    });
    const live = computeLiveLegs([open, close], undefined, TODAY);
    // 1 leg still open (only 1 of 3 contracts closed; leg counts as 1)
    expect(live.total).toBe(1);
    // 2 contracts × 100 × $2 = $400 outstanding
    expect(live.shortPremium).toBe(400);
  });

  it("ticker filter", () => {
    const trades = [
      trade({ ticker: "AAPL", direction: "short", contracts: 1, premium: 2 }),
      trade({ ticker: "MSFT", direction: "short", contracts: 1, premium: 3 }),
    ];
    const aapl = computeLiveLegs(trades, { ticker: "AAPL" }, TODAY);
    expect(aapl.total).toBe(1);
    expect(aapl.shortPremium).toBe(200);
    expect(aapl.byTicker.size).toBe(1);
  });
});
