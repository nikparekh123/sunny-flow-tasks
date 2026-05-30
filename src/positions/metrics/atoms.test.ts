/**
 * Unit tests for the 12 atoms. One block per atom, covering:
 *  - the base sum,
 *  - each filter dimension that applies,
 *  - the "edge case I'd actually trip over" (closed positions, partial closes,
 *    expiry boundaries, missing close prices, etc.).
 *
 * Fixtures are intentionally tiny so the expected values can be computed in
 * your head from the comments.
 */
import { describe, expect, it } from "vitest";
import type {
  DailyClose,
  OptionTrade,
  PositionRow,
  ShareSell,
} from "../types";
import {
  creditCloseLong,
  debitCloseShort,
  equityCostBasis,
  equityMarketValue,
  historicalPortfolioValue,
  liveLegCount,
  openLongPremium,
  openShortPremium,
  optionRealized,
  premiumCollected,
  premiumPaid,
  sharesRealized,
} from "./atoms";

// ─── shared fixtures ─────────────────────────────────────────────────────────

const TODAY = "2026-05-29";

let _posSeq = 0;
const pos = (over: Partial<PositionRow> = {}): PositionRow => ({
  id: "p-" + ++_posSeq,
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

let _sellSeq = 0;
const sell = (over: Partial<ShareSell> = {}): ShareSell => ({
  id: "s-" + ++_sellSeq,
  ticker: "AAPL",
  quantity: 10,
  price: 200,
  trade_date: "2026-05-15",
  source: "manual",
  linked_option_close_id: null,
  realized_pl: 500,
  note: null,
  created_at: TODAY,
  updated_at: TODAY,
  ...over,
});

let _tradeSeq = 0;
const trade = (over: Partial<OptionTrade> = {}): OptionTrade => ({
  id: "t-" + ++_tradeSeq,
  ticker: "AAPL",
  trade_date: "2026-05-01",
  action: "open",
  option_type: "call",
  direction: "short",
  contracts: 1,
  strike: 200,
  premium: 2,
  expiry: "2026-06-19",
  closes_trade_id: null,
  note: null,
  created_at: TODAY,
  updated_at: TODAY,
  closed_via: null,
  share_pnl: 0,
  ...over,
});

const dc = (
  ticker: string,
  date: string,
  close_price: number,
): DailyClose => ({ ticker, date, close_price, captured_at: TODAY });

// ─── A1 — equityMarketValue ──────────────────────────────────────────────────

describe("A1 equityMarketValue", () => {
  it("sums qty × current_price over open positions", () => {
    const positions = [
      pos({ ticker: "AAPL", quantity: 100, current_price: 200 }), // 20,000
      pos({ ticker: "MSFT", quantity: 50, current_price: 400 }), // 20,000
    ];
    expect(equityMarketValue(positions)).toBe(40_000);
  });

  it("excludes closed positions and qty <= 0", () => {
    const positions = [
      pos({ ticker: "AAPL", quantity: 100, current_price: 200 }),
      pos({ ticker: "MSFT", quantity: 50, current_price: 400, status: "closed" }),
      pos({ ticker: "NVDA", quantity: 0, current_price: 100 }),
    ];
    expect(equityMarketValue(positions)).toBe(20_000);
  });

  it("filters by ticker", () => {
    const positions = [
      pos({ ticker: "AAPL", quantity: 100, current_price: 200 }),
      pos({ ticker: "MSFT", quantity: 50, current_price: 400 }),
    ];
    expect(equityMarketValue(positions, { ticker: "MSFT" })).toBe(20_000);
  });

  it("falls back to avg_cost when current_price is null (stale-price safety)", () => {
    // qty 100, avg_cost 150 → 15,000 (so unrealized = MV − cost = 0)
    const positions = [pos({ current_price: null, quantity: 100, avg_cost: 150 })];
    expect(equityMarketValue(positions)).toBe(15_000);
  });
});

// ─── A2 — equityCostBasis ────────────────────────────────────────────────────

describe("A2 equityCostBasis", () => {
  it("sums qty × avg_cost over open positions", () => {
    const positions = [
      pos({ quantity: 100, avg_cost: 150 }), // 15,000
      pos({ ticker: "MSFT", quantity: 50, avg_cost: 300 }), // 15,000
    ];
    expect(equityCostBasis(positions)).toBe(30_000);
  });

  it("excludes closed positions", () => {
    const positions = [
      pos({ quantity: 100, avg_cost: 150 }),
      pos({ quantity: 50, avg_cost: 300, status: "closed" }),
    ];
    expect(equityCostBasis(positions)).toBe(15_000);
  });

  it("filters by ticker", () => {
    const positions = [
      pos({ ticker: "AAPL", quantity: 100, avg_cost: 150 }),
      pos({ ticker: "MSFT", quantity: 50, avg_cost: 300 }),
    ];
    expect(equityCostBasis(positions, { ticker: "AAPL" })).toBe(15_000);
  });
});

// ─── A3 — sharesRealized ─────────────────────────────────────────────────────

describe("A3 sharesRealized", () => {
  it("sums realized_pl across share sells", () => {
    const sells = [sell({ realized_pl: 500 }), sell({ realized_pl: -150 })];
    expect(sharesRealized(sells)).toBe(350);
  });

  it("windows by trade_date (inclusive start, exclusive end)", () => {
    const sells = [
      sell({ trade_date: "2026-04-01", realized_pl: 100 }),
      sell({ trade_date: "2026-05-01", realized_pl: 200 }),
      sell({ trade_date: "2026-06-01", realized_pl: 400 }),
    ];
    expect(
      sharesRealized(sells, { window: { start: "2026-05-01", end: "2026-06-01" } }),
    ).toBe(200);
  });

  it("filters by ticker", () => {
    const sells = [
      sell({ ticker: "AAPL", realized_pl: 100 }),
      sell({ ticker: "MSFT", realized_pl: 200 }),
    ];
    expect(sharesRealized(sells, { ticker: "MSFT" })).toBe(200);
  });
});

// ─── A4 — premiumCollected ───────────────────────────────────────────────────

describe("A4 premiumCollected", () => {
  it("sums contracts × 100 × premium for short opens only", () => {
    const trades = [
      trade({ direction: "short", contracts: 2, premium: 3 }), // 600
      trade({ direction: "long", contracts: 1, premium: 5 }), // skip
      trade({ direction: "short", action: "close", contracts: 1, premium: 1 }), // skip
    ];
    expect(premiumCollected(trades)).toBe(600);
  });

  it("filters by option_type and ticker", () => {
    const trades = [
      trade({ option_type: "call", contracts: 1, premium: 2 }), // 200
      trade({ option_type: "put", contracts: 1, premium: 3 }), // 300
      trade({ ticker: "MSFT", option_type: "call", contracts: 1, premium: 4 }), // 400
    ];
    expect(premiumCollected(trades, { optionType: "put" })).toBe(300);
    expect(premiumCollected(trades, { ticker: "AAPL" })).toBe(500);
  });

  it("windows by trade_date", () => {
    const trades = [
      trade({ trade_date: "2026-04-15", contracts: 1, premium: 1 }),
      trade({ trade_date: "2026-05-15", contracts: 1, premium: 2 }),
    ];
    expect(premiumCollected(trades, { window: { start: "2026-05-01" } })).toBe(200);
  });
});

// ─── A5 — premiumPaid ────────────────────────────────────────────────────────

describe("A5 premiumPaid", () => {
  it("sums contracts × 100 × premium for long opens only", () => {
    const trades = [
      trade({ direction: "long", contracts: 2, premium: 3 }), // 600
      trade({ direction: "short", contracts: 1, premium: 5 }), // skip
    ];
    expect(premiumPaid(trades)).toBe(600);
  });
});

// ─── A6 — debitCloseShort ────────────────────────────────────────────────────

describe("A6 debitCloseShort", () => {
  it("sums contracts × 100 × premium for closes of shorts", () => {
    const trades = [
      trade({ action: "close", direction: "short", contracts: 2, premium: 1 }), // 200
      trade({ action: "close", direction: "long", contracts: 1, premium: 5 }), // skip
      trade({ action: "open", direction: "short", contracts: 1, premium: 4 }), // skip
    ];
    expect(debitCloseShort(trades)).toBe(200);
  });
});

// ─── A7 — creditCloseLong ────────────────────────────────────────────────────

describe("A7 creditCloseLong", () => {
  it("sums contracts × 100 × premium for closes of longs", () => {
    const trades = [
      trade({ action: "close", direction: "long", contracts: 2, premium: 4 }), // 800
      trade({ action: "close", direction: "short", contracts: 1, premium: 1 }), // skip
    ];
    expect(creditCloseLong(trades)).toBe(800);
  });
});

// ─── A8 — optionRealized ─────────────────────────────────────────────────────

describe("A8 optionRealized", () => {
  it("signs short-open close correctly (kept premium > 0)", () => {
    // Sold for $2, bought back for $0.50, 1 contract → +$150
    const open = trade({
      id: "open-1",
      direction: "short",
      contracts: 1,
      premium: 2,
    });
    const close = trade({
      action: "close",
      direction: "short",
      contracts: 1,
      premium: 0.5,
      closes_trade_id: "open-1",
      trade_date: "2026-05-20",
    });
    expect(optionRealized([open, close])).toBe(150);
  });

  it("signs long-open close correctly (premium gain > 0)", () => {
    // Bought for $1, sold for $3, 2 contracts → +$400
    const open = trade({
      id: "open-2",
      direction: "long",
      contracts: 2,
      premium: 1,
    });
    const close = trade({
      action: "close",
      direction: "long",
      contracts: 2,
      premium: 3,
      closes_trade_id: "open-2",
    });
    expect(optionRealized([open, close])).toBe(400);
  });

  it("windows by close trade_date, filters direction from the OPEN", () => {
    const o1 = trade({ id: "o1", direction: "short", contracts: 1, premium: 2 });
    const c1 = trade({
      action: "close",
      direction: "short",
      contracts: 1,
      premium: 0.5,
      closes_trade_id: "o1",
      trade_date: "2026-05-20",
    });
    const o2 = trade({ id: "o2", direction: "long", contracts: 1, premium: 1 });
    const c2 = trade({
      action: "close",
      direction: "long",
      contracts: 1,
      premium: 2,
      closes_trade_id: "o2",
      trade_date: "2026-04-20",
    });
    const all = [o1, c1, o2, c2];
    expect(optionRealized(all, { direction: "short" })).toBe(150);
    expect(
      optionRealized(all, { window: { start: "2026-05-01" } }),
    ).toBe(150);
  });

  it("ignores closes with no matching open", () => {
    const orphan = trade({
      action: "close",
      direction: "short",
      contracts: 1,
      premium: 1,
      closes_trade_id: "nope",
    });
    expect(optionRealized([orphan])).toBe(0);
  });
});

// ─── A9 — openShortPremium ───────────────────────────────────────────────────

describe("A9 openShortPremium", () => {
  it("accounts for partial closes", () => {
    // Sold 3 contracts at $2 → $600 gross; closed 1 → $400 still open.
    const open = trade({
      id: "op",
      direction: "short",
      contracts: 3,
      premium: 2,
    });
    const close = trade({
      action: "close",
      direction: "short",
      contracts: 1,
      premium: 1,
      closes_trade_id: "op",
    });
    expect(openShortPremium([open, close], undefined, TODAY)).toBe(400);
  });

  it("filters by live state", () => {
    const todayLeg = trade({
      id: "leg-today",
      direction: "short",
      contracts: 1,
      premium: 2,
      expiry: TODAY,
    });
    const farLeg = trade({
      id: "leg-far",
      direction: "short",
      contracts: 1,
      premium: 3,
      expiry: "2026-07-19",
    });
    expect(
      openShortPremium([todayLeg, farLeg], { liveState: "today" }, TODAY),
    ).toBe(200);
    expect(
      openShortPremium([todayLeg, farLeg], { liveState: "in_gt_7d" }, TODAY),
    ).toBe(300);
    expect(
      openShortPremium(
        [todayLeg, farLeg],
        { liveState: ["today", "in_gt_7d"] },
        TODAY,
      ),
    ).toBe(500);
  });

  it("excludes long opens", () => {
    const longOpen = trade({ direction: "long", contracts: 1, premium: 5 });
    expect(openShortPremium([longOpen], undefined, TODAY)).toBe(0);
  });
});

// ─── A10 — openLongPremium ───────────────────────────────────────────────────

describe("A10 openLongPremium", () => {
  it("sums remaining contracts × 100 × premium for long opens", () => {
    const open = trade({
      id: "lo",
      direction: "long",
      contracts: 2,
      premium: 3,
    });
    expect(openLongPremium([open], undefined, TODAY)).toBe(600);
  });
});

// ─── A11 — liveLegCount ──────────────────────────────────────────────────────

describe("A11 liveLegCount", () => {
  it("counts open legs with remaining contracts > 0", () => {
    const a = trade({ id: "a", contracts: 1 });
    const b = trade({ id: "b", contracts: 1 });
    const closeB = trade({
      id: "b-close",
      action: "close",
      contracts: 1,
      closes_trade_id: "b",
    });
    expect(liveLegCount([a, b, closeB], undefined, TODAY)).toBe(1);
  });

  it("filters by call/put + direction", () => {
    const sc = trade({ id: "sc", option_type: "call", direction: "short" });
    const sp = trade({ id: "sp", option_type: "put", direction: "short" });
    const lc = trade({ id: "lc", option_type: "call", direction: "long" });
    const all = [sc, sp, lc];
    expect(liveLegCount(all, { direction: "short" }, TODAY)).toBe(2);
    expect(
      liveLegCount(all, { optionType: "call", direction: "long" }, TODAY),
    ).toBe(1);
  });

  it("respects expiry boundaries (today / ≤7d / >7d / expired)", () => {
    const exp = trade({ id: "exp", expiry: "2026-05-20" }); // past
    const tdy = trade({ id: "tdy", expiry: TODAY });
    const wk = trade({ id: "wk", expiry: "2026-06-03" }); // +5d
    const far = trade({ id: "far", expiry: "2026-08-01" });
    const all = [exp, tdy, wk, far];
    expect(liveLegCount(all, { liveState: "expired" }, TODAY)).toBe(1);
    expect(liveLegCount(all, { liveState: "today" }, TODAY)).toBe(1);
    expect(liveLegCount(all, { liveState: "in_le_7d" }, TODAY)).toBe(1);
    expect(liveLegCount(all, { liveState: "in_gt_7d" }, TODAY)).toBe(1);
  });
});

// ─── A12 — historicalPortfolioValue ──────────────────────────────────────────

describe("A12 historicalPortfolioValue", () => {
  const positions = [
    pos({ ticker: "AAPL", quantity: 100, current_price: 200, avg_cost: 150 }),
    pos({ ticker: "MSFT", quantity: 50, current_price: 400, avg_cost: 300 }),
  ];
  const closes: DailyClose[] = [
    dc("AAPL", "2026-05-20", 180),
    dc("AAPL", "2026-05-22", 190),
    dc("MSFT", "2026-05-22", 380),
  ];

  it("uses the close on the exact date if present", () => {
    const fn = historicalPortfolioValue(positions, closes);
    // AAPL 100 × 190 + MSFT 50 × 380 = 19,000 + 19,000 = 38,000
    expect(fn("2026-05-22")).toBe(38_000);
  });

  it("carries forward the most recent prior close", () => {
    const fn = historicalPortfolioValue(positions, closes);
    // 2026-05-21: AAPL has 2026-05-20 (180); MSFT has none yet → falls back to
    // earliest close (380). 100*180 + 50*380 = 18,000 + 19,000 = 37,000
    expect(fn("2026-05-21")).toBe(37_000);
  });

  it("uses the earliest close for dates before the first close", () => {
    const fn = historicalPortfolioValue(positions, closes);
    // 2026-01-01: AAPL earliest = 180, MSFT earliest = 380
    expect(fn("2026-01-01")).toBe(100 * 180 + 50 * 380);
  });

  it("falls back to current_price when a ticker has no closes at all", () => {
    const fn = historicalPortfolioValue(positions, []);
    // AAPL 100 × 200 + MSFT 50 × 400 = 20,000 + 20,000 = 40,000
    expect(fn("2026-05-22")).toBe(40_000);
  });

  it("filters by ticker", () => {
    const fn = historicalPortfolioValue(positions, closes);
    expect(fn("2026-05-22", { ticker: "AAPL" })).toBe(100 * 190);
  });
});
