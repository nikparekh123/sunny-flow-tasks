//
//  HedgeMath.swift
//  Sunnyfi
//
//  Hedge budget math. Treats every open long put as paid insurance and
//  spreads its cost evenly across the trading days remaining until
//  expiry — so we can ask "what daily / weekly premium do I need to
//  generate selling calls just to break even on hedges?".
//
//  Decisions for v1 (per user):
//   • Trading days = Mon–Fri only. NYSE holidays ignored — close enough
//     for a budget signal and avoids a holiday table to maintain.
//   • All open long puts counted regardless of expiry — no period filter.
//   • Cost basis = net debit on the *open* row only. Partial closes
//     don't reduce cost here (those realized P&L credits show up in
//     Performance instead). The hedge book is what you currently own.
//

import Foundation

/// One open long put with its share of the daily burn.
struct HedgeLeg: Identifiable, Hashable {
    let id: String              // open trade id
    let ticker: String
    let strike: Double
    let expiry: String          // ISO YYYY-MM-DD
    let contractsRemaining: Double
    let costBasis: Double       // $ paid for the contracts still open
    let tradingDaysRemaining: Int
    /// costBasis spread over tradingDaysRemaining (≥ 1 to avoid div/0).
    var dailyBurn: Double {
        let d = max(1, tradingDaysRemaining)
        return costBasis / Double(d)
    }
    /// Expired today / past expiry — still "open" in the book but no
    /// future protection. Surfaced so the UI can flag stragglers.
    var isStranded: Bool { tradingDaysRemaining <= 0 }
}

/// Aggregate hedge book + rolled-up burn rates.
struct HedgeBudget {
    let legs: [HedgeLeg]
    /// Total $ paid for protection currently on the book.
    let totalCost: Double
    /// Σ per-leg dailyBurn — what you need to earn each trading day
    /// just to stay flat on hedges.
    let dailyBurn: Double

    var weeklyBurn:  Double { dailyBurn * 5 }
    /// ~21 trading days / month (52 wks × 5 / 12).
    var monthlyBurn: Double { dailyBurn * (52.0 * 5.0 / 12.0) }

    var openPutCount: Int { legs.count }
    var openContracts: Double { legs.reduce(0) { $0 + $1.contractsRemaining } }
    var isEmpty: Bool { legs.isEmpty }

    static let empty = HedgeBudget(legs: [], totalCost: 0, dailyBurn: 0)
}

enum HedgeMath {

    /// Mon–Fri weekday count between `from` (exclusive of today) and
    /// `to` (inclusive). EST clock. Returns 0 if `to` ≤ today. Holidays
    /// are NOT excluded — v1 keeps the math simple.
    static func tradingDaysBetween(from now: Date = Date(), toISO expiry: String) -> Int {
        guard let eastern = TimeZone(identifier: "America/New_York") else { return 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = eastern

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = eastern
        guard let target = df.date(from: String(expiry.prefix(10))) else { return 0 }

        let startOfToday = cal.startOfDay(for: now)
        guard target > startOfToday else { return 0 }

        var count = 0
        var cursor = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        while cursor <= target {
            let wd = cal.component(.weekday, from: cursor)  // Sun=1 … Sat=7
            if wd != 1 && wd != 7 { count += 1 }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return count
    }

    /// Build the hedge budget from a list of trades + a remainingContracts
    /// closure (injected so we don't need to import PortfolioStore here).
    static func budget(
        from trades: [OptionTradeRow],
        remaining: (OptionTradeRow) -> Double,
        now: Date = Date()
    ) -> HedgeBudget {
        let openLongPuts = trades.filter {
            $0.action == "open"
            && $0.direction == "long"
            && $0.option_type == "put"
            && remaining($0) > 0.0001
        }

        var legs: [HedgeLeg] = []
        legs.reserveCapacity(openLongPuts.count)
        var totalCost = 0.0
        var dailyBurn = 0.0

        for t in openLongPuts {
            let remainingCt = remaining(t)
            // Premium on the open row is per-share; ×100 per contract.
            let cost = t.premium * remainingCt * 100
            let dte  = tradingDaysBetween(from: now, toISO: t.expiry)
            let leg = HedgeLeg(
                id: t.id,
                ticker: t.ticker,
                strike: t.strike,
                expiry: t.expiry,
                contractsRemaining: remainingCt,
                costBasis: cost,
                tradingDaysRemaining: dte
            )
            legs.append(leg)
            totalCost += cost
            dailyBurn += leg.dailyBurn
        }

        // Sort by daily burn descending — most expensive insurance first.
        legs.sort { $0.dailyBurn > $1.dailyBurn }

        return HedgeBudget(legs: legs, totalCost: totalCost, dailyBurn: dailyBurn)
    }
}
