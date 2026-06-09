//
//  PortfolioModels.swift
//  Sunnyfi
//
//  Swift port of the Supabase row shapes + the joined `Company` shape
//  the UI consumes. Mirrors src/portfolio/buildCompanies.ts.
//

import Foundation

// MARK: - Raw Supabase row shapes

struct PositionRow: Decodable, Sendable {
    let ticker: String
    let name: String?
    let sector: String?
    let quantity: Double
    let avg_cost: Double
    let current_price: Double?
    let prev_close: Double?
    let status: String   // "open" | "closed"
    let earnings_date: String?
    let realized_stock_pl: Double?
}

struct OptionTradeRow: Decodable, Sendable {
    let id: String
    let ticker: String
    let trade_date: String
    let action: String        // "open" | "close"
    let option_type: String   // "call" | "put"
    let direction: String     // "long" | "short"
    let contracts: Double
    let strike: Double
    let premium: Double
    let expiry: String
    let closes_trade_id: String?
    /// IBKR Flex sync columns. Optional to keep older API responses
    /// (and seed/manual rows) decoding cleanly.
    let source: String?            // "manual" | "ibkr_flex" | "assignment" | "seed"
    let ibkr_trade_id: String?
    let last_synced_at: String?    // ISO8601, only set when source='ibkr_flex'
    let voided_at: String?         // ISO8601, set if IBKR cancelled
}

struct OptionGreeksRow: Decodable, Sendable {
    let option_trade_id: String
    let delta: Double?
    let gamma: Double?
    let theta: Double?
    let vega: Double?
    let iv: Double?
    let open_interest: Double?
    let volume: Double?
    let last_mark: Double?
    let captured_at: String?
}

// (OptionIvChangeRow removed — the day-over-day IV bucket it
// powered is gone. IV now flows through `ticker_iv_summary` /
// TickerIVRow. The `option_iv_daily_change` view in Supabase is
// dormant; safe to drop or leave.)

/// One row per trading day captured by the daily-theta-snapshot cron.
/// Powers the Hedge tab's day-over-day Δ-change, the 14-day sparkline,
/// and the prior-week paid-vs-collected history.
struct DailyThetaSnapshotRow: Decodable, Sendable, Hashable {
    let snapshot_date: String           // "YYYY-MM-DD" (EST date)
    let total_burn: Double
    let long_put_count: Int
    /// Per-ticker burn breakdown. Optional in case older rows had nothing.
    let per_ticker: [String: Double]?
}

/// Active "something is broken" row written by the health-monitor
/// cron. The iOS app subscribes and shows a non-dismissible top banner
/// whenever any row with `resolved_at == nil` exists.
struct SystemAlertRow: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let code: String
    let severity: String       // "info" | "warn" | "critical"
    let title: String
    let detail: String?
    let created_at: String
    let resolved_at: String?

    var isActive: Bool { resolved_at == nil }
    var isCritical: Bool { severity == "critical" }
}

struct TickerQuoteRow: Decodable, Sendable {
    let ticker: String
    let spot: Double?
    let day_change_pct: Double?
    let beta: Double?
    let captured_at: String?
}

struct ShareSellRow: Decodable, Sendable {
    let ticker: String
    let realized_pl: Double
    let trade_date: String
}

struct StrategyOverlayRow: Decodable, Sendable {
    let ticker: String
    let bucket: String        // "income" | "invest" | "yield"
}

struct DailyCloseRow: Decodable, Sendable {
    let ticker: String
    let date: String          // YYYY-MM-DD
    let close_price: Double
}

// MARK: - Phase 3: share lots (FIFO)

struct ShareLotRow: Decodable, Sendable, Identifiable {
    let id: String
    let ticker: String
    let acquired_date: String      // YYYY-MM-DD
    let fifo_order: Int
    let qty_original: Double
    let qty_remaining: Double
    let cost_per_share: Double
    let source: String             // "manual" | "ibkr_flex" | "assignment" | "seed"
    let linked_assignment_id: String?
    let ibkr_trade_id: String?
    let last_synced_at: String?    // ISO8601, only set when source='ibkr_flex'
    let voided_at: String?         // ISO8601, set if IBKR cancelled
}

/// Simulated FIFO consumption — one entry per lot that would be drawn
/// down, with the qty and realized P&L at the given sell price.
struct LotConsumption: Sendable, Identifiable {
    let id: String
    let lot: ShareLotRow
    let qtyConsumed: Double
    let realizedPL: Double
}

// MARK: - Joined / computed shapes

enum LegKind: Sendable { case stock, call, put }
enum LegSide: Sendable { case long, short }
enum Strategy: String, Sendable {
    case income      = "Income"
    case investment  = "Investment"
    case `yield`     = "Yield"

    /// Lowercase short-form value expected by the Postgres
    /// `strategy_overlay.bucket` CHECK constraint
    /// (`income | invest | yield`). Note `invest`, not "investment" —
    /// the DB column was created with the short form and the constraint
    /// rejects anything else. PortfolioStore.mapStrategy() decodes this
    /// shape back to the enum on read.
    var dbBucket: String {
        switch self {
        case .income:     return "income"
        case .investment: return "invest"
        case .yield:      return "yield"
        }
    }
}

struct Leg: Identifiable, Sendable {
    let id = UUID()
    let kind: LegKind
    let side: LegSide?
    let qty: Double            // shares or signed contracts
    let avg: Double
    let last: Double
    let unreal: Double
    let real: Double
    let delta: Double
    let gamma: Double
    let theta: Double
    let vega: Double
    let strike: Double?
    let expiry: String?
    let dte: Int?
    let iv: Double?
    let oi: Double?
}

struct Aggregate: Sendable {
    var delta: Double = 0
    var gamma: Double = 0
    var theta: Double = 0
    var vega: Double = 0
    var unreal: Double = 0
    var real: Double = 0
    var mv: Double = 0
    var net: Double { unreal + real }
}

struct Company: Identifiable, Sendable {
    var id: String { ticker }
    let ticker: String
    let name: String
    let sector: String
    let strategy: Strategy
    let spot: Double
    let dayPct: Double
    let beta: Double
    let earningsDate: String?
    let legs: [Leg]
    let agg: Aggregate
    let closed: Bool
}

struct PortfolioRollup: Sendable {
    var delta: Double = 0
    var gamma: Double = 0
    var theta: Double = 0
    var vega: Double = 0
    var unreal: Double = 0
    var real: Double = 0
    var mv: Double = 0
    var betaWeightedDelta: Double = 0
    var openCount: Int = 0
    var optionLegCount: Int = 0
    var net: Double { unreal + real }

    static let empty = PortfolioRollup()
}
