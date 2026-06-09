//
//  PortfolioHistory.swift
//  Sunnyfi
//
//  Per-range portfolio % change, computed from `daily_closes` × current
//  share holdings. Approximation: uses today's share counts (doesn't
//  replay transactions over the window). Good enough for the dashboard
//  hero — a precise replay would need cost-basis snapshots.
//

import Foundation

enum HistoryRange {
    /// Approximate trading-day offsets for each chart range.
    static func tradingDaysBack(_ r: ChartRange) -> Int {
        switch r {
        case .oneDay:     return 1
        case .oneWeek:    return 5
        case .oneMonth:   return 22
        case .threeMonth: return 66
        case .ytd:        return -1   // special-cased below
        case .oneYear:    return 252
        case .all:        return 9999
        }
    }
}

struct RangeChange {
    let dollars: Double
    let percent: Double
}

enum PortfolioHistory {

    /// Per-range portfolio dollar/% change vs N trading days back.
    /// Returns nil if we don't have enough daily_closes for every held ticker.
    static func change(
        for range: ChartRange,
        companies: [Company],
        dailyCloses: [DailyCloseRow],
        now: Date = Date()
    ) -> RangeChange? {

        // Only stock-share moves are tracked here — options pricing isn't
        // historical (no option_quotes table). Shares dominate portfolio
        // value for this app, so this is a useful approximation.
        let stockHoldings: [(ticker: String, qty: Double)] = companies.compactMap { c in
            guard let stock = c.legs.first(where: { $0.kind == .stock }), stock.qty > 0 else { return nil }
            return (c.ticker, stock.qty)
        }
        guard !stockHoldings.isEmpty else { return nil }

        // Index closes by ticker, newest first.
        var byTicker: [String: [DailyCloseRow]] = [:]
        for row in dailyCloses {
            byTicker[row.ticker, default: []].append(row)
        }
        for k in byTicker.keys {
            byTicker[k]?.sort { $0.date > $1.date }
        }

        // "Now" close = most-recent close per ticker.
        var nowValue = 0.0
        var thenValue = 0.0

        for (ticker, qty) in stockHoldings {
            guard let rows = byTicker[ticker], !rows.isEmpty else { return nil }
            nowValue += rows[0].close_price * qty

            // For the "back" date, pick a target index or YTD-specific row.
            let backRow: DailyCloseRow? = {
                if range == .ytd {
                    let cal = Calendar(identifier: .gregorian)
                    let yearStartIso: String = {
                        let f = DateFormatter()
                        f.dateFormat = "yyyy-MM-dd"
                        f.timeZone = TimeZone(identifier: "UTC")
                        let comps = cal.dateComponents([.year], from: now)
                        return f.string(from: cal.date(from: comps) ?? now)
                    }()
                    // Last close on/before year start.
                    return rows.first(where: { $0.date <= yearStartIso }) ?? rows.last
                } else {
                    let idx = min(rows.count - 1, HistoryRange.tradingDaysBack(range))
                    return rows[idx]
                }
            }()
            guard let bk = backRow else { return nil }
            thenValue += bk.close_price * qty
        }

        guard thenValue > 0 else { return nil }
        let dollars = nowValue - thenValue
        let pct = (dollars / thenValue) * 100
        return RangeChange(dollars: dollars, percent: pct)
    }
}
