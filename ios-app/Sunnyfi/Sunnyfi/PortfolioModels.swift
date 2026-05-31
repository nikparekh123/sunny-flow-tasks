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

// MARK: - Joined / computed shapes

enum LegKind: Sendable { case stock, call, put }
enum LegSide: Sendable { case long, short }
enum Strategy: String, Sendable {
    case income      = "Income"
    case investment  = "Investment"
    case `yield`     = "Yield"
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
