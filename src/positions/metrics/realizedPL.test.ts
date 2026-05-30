/**
 * Tests for canonical Realized P&L = A3 + A8.
 */
import { describe, expect, it } from "vitest";
import type { OptionTrade, ShareSell } from "../types";
import { optionRealized, sharesRealized } from "./atoms";
import { computeRealizedPL } from "./realizedPL";

let _t = 0, _s = 0;
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
const sell = (over: Partial<ShareSell> = {}): ShareSell => ({
  id: "s-" + ++_s,
  ticker: "AAPL",
  quantity: 10,
  price: 200,
  trade_date: "2026-05-20",
  source: "manual",
  linked_option_close_id: null,
  realized_pl: 500,
  note: null,
  created_at: "2026-05-20",
  updated_at: "2026-05-20",
  ...over,
});

describe("computeRealizedPL", () => {
  it("total = A3 + A8 (parity)", () => {
    const open = trade({ id: "o", direction: "short", contracts: 1, premium: 2 });
    const close = trade({
      action: "close",
      direction: "short",
      contracts: 1,
      premium: 0.5,
      closes_trade_id: "o",
      trade_date: "2026-05-20",
    });
    const trades = [open, close];
    const sells = [sell({ realized_pl: 500 })];
    const r = computeRealizedPL(trades, sells);
    expect(r.shares).toBe(sharesRealized(sells));
    expect(r.options).toBe(optionRealized(trades));
    expect(r.total).toBe(r.shares + r.options);
    // Sanity: 500 + 150 = 650
    expect(r.total).toBe(650);
  });

  it("windows by close trade_date (options) and sell trade_date (shares)", () => {
    const o = trade({ id: "o", direction: "short", contracts: 1, premium: 2 });
    const c = trade({
      action: "close",
      direction: "short",
      contracts: 1,
      premium: 0.5,
      closes_trade_id: "o",
      trade_date: "2026-05-20",
    });
    const s1 = sell({ trade_date: "2026-04-01", realized_pl: 100 }); // out
    const s2 = sell({ trade_date: "2026-05-20", realized_pl: 200 }); // in
    const r = computeRealizedPL([o, c], [s1, s2], {
      window: { start: "2026-05-01", end: "2026-06-01" },
    });
    expect(r.shares).toBe(200);
    expect(r.options).toBe(150);
    expect(r.total).toBe(350);
  });

  it("optionType filter excludes share-realized entirely", () => {
    const o = trade({ id: "o", option_type: "put", direction: "short", contracts: 1, premium: 2 });
    const c = trade({
      action: "close",
      option_type: "put",
      direction: "short",
      contracts: 1,
      premium: 1,
      closes_trade_id: "o",
    });
    const s = sell({ realized_pl: 500 });
    const r = computeRealizedPL([o, c], [s], { optionType: "put" });
    expect(r.shares).toBe(0); // structurally excluded
    expect(r.options).toBe(100);
    expect(r.total).toBe(100);
  });

  it("byTicker map sums to total", () => {
    const oAAPL = trade({ id: "oa", ticker: "AAPL", direction: "short", contracts: 1, premium: 2 });
    const cAAPL = trade({
      action: "close",
      ticker: "AAPL",
      direction: "short",
      contracts: 1,
      premium: 0.5,
      closes_trade_id: "oa",
    });
    const sMSFT = sell({ ticker: "MSFT", realized_pl: 300 });
    const r = computeRealizedPL([oAAPL, cAAPL], [sMSFT]);
    const sum = Array.from(r.byTicker.values()).reduce((s, v) => s + v, 0);
    expect(sum).toBeCloseTo(r.total, 6);
    expect(r.byTicker.get("AAPL")).toBe(150);
    expect(r.byTicker.get("MSFT")).toBe(300);
  });
});
