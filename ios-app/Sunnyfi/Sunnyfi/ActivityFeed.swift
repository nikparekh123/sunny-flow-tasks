//
//  ActivityFeed.swift
//  Sunnyfi
//
//  Combined trade activity — option opens, option closes, share
//  purchases (from share_lots), and share sales. Grouped per-day
//  in EST, newest day first. The Trades screen exposes a date
//  picker to either show every day or filter to one specific date.
//

import Foundation
import SwiftUI

enum ActivityKind: String {
    case optionOpen   = "Opened"
    case optionClose  = "Closed"
    case shareBuy     = "Bought"
    case shareSell    = "Sold"
    case assignment   = "Assigned"
    case seed         = "Seed"
}

/// Lifecycle state per row — drives the OPEN / CLOSED filter pills
/// and the small chip in each row of the Activity list.
enum ActivityStatus: String {
    case open   = "OPEN"     // position is still active in your book
    case closed = "CLOSED"   // realized P&L event — position is gone

    var tint: Color {
        switch self {
        case .open:   return Color.theme.neon
        case .closed: return Color.theme.fg3
        }
    }
}

struct ActivityRow: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let ticker: String
    let kind: ActivityKind
    /// OPEN if the underlying position is still active in your book,
    /// CLOSED if this row represents a realized P&L event (or the
    /// original open has been fully closed since).
    let status: ActivityStatus
    /// Line 1 — the asset itself, e.g. "META $647 call" or "META 200 shares".
    let asset: String
    /// Line 2 — the action context, e.g. "10 calls sold for Jun 19".
    let action: String
    /// Signed dollar value of the event for the right-column.
    /// • Option open: +credit (short) or −debit (long)
    /// • Option close: realized P&L
    /// • Share buy: −cost basis
    /// • Share sell: realized P&L
    let valueText: String
    let isPositive: Bool

    static func == (lhs: ActivityRow, rhs: ActivityRow) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ActivityDayGroup: Identifiable, Hashable {
    /// EST calendar day represented by this group (start-of-day Date).
    let day: Date
    /// Display label e.g. "Today · Jun 1" / "Yesterday · May 31" / "Wed · May 29".
    let label: String
    let rows: [ActivityRow]
    var id: Date { day }
}

enum ActivityFeed {

    /// Build the per-day activity feed. Source rows:
    ///   • Option opens   — every open trade
    ///   • Option closes  — every close trade with its parent open
    ///   • Share buys     — every share lot (except `seed` lots which
    ///                      represent the initial balance, not a buy)
    ///   • Share sells    — every share-sell row
    ///
    /// `dateFilter` optionally narrows to a single EST calendar day.
    static func dailyGroups(
        trades: [OptionTradeRow],
        shareSells: [ShareSellRow],
        shareLots: [ShareLotRow],
        dateFilter: Date? = nil,
        now: Date = Date()
    ) -> [ActivityDayGroup] {
        var rows: [ActivityRow] = []

        // Sum closed contracts per open id so we can tag option-open
        // rows OPEN (some remaining) vs CLOSED (fully closed).
        var closedByOpenID: [String: Double] = [:]
        for t in trades where t.action == "close" {
            if let oid = t.closes_trade_id {
                closedByOpenID[oid, default: 0] += t.contracts
            }
        }

        // ── Option opens ──
        for t in trades where t.action == "open" {
            guard let d = AppDates.parseISODay(t.trade_date) else { continue }
            let kind = t.option_type == "call" ? "call" : "put"
            let kindPlural = t.option_type == "call" ? "calls" : "puts"
            let verb = t.direction == "short" ? "sold" : "bought"
            let asset = "\(t.ticker) $\(fmtStrike(t.strike)) \(kind)"
            let action = "\(Int(t.contracts)) \(kindPlural) \(verb) for \(AppDates.shortMonthDay(t.expiry))"
            let signed = t.premium * t.contracts * 100 * (t.direction == "short" ? 1 : -1)
            let closed = closedByOpenID[t.id] ?? 0
            let status: ActivityStatus = (t.contracts - closed > 0.0001) ? .open : .closed
            rows.append(ActivityRow(
                date: d, ticker: t.ticker, kind: .optionOpen, status: status,
                asset: asset, action: action,
                valueText: fmtMoney(signed, sign: true),
                isPositive: signed >= 0
            ))
        }

        // ── Option closes ── (always realized → CLOSED)
        for c in trades where c.action == "close" {
            guard let d = AppDates.parseISODay(c.trade_date) else { continue }
            let kind = c.option_type == "call" ? "call" : "put"
            let kindPlural = c.option_type == "call" ? "calls" : "puts"
            let open = trades.first(where: { $0.id == (c.closes_trade_id ?? "") })
            let realized: Double = {
                guard let o = open else { return 0 }
                let sign: Double = o.direction == "short" ? 1 : -1
                return (o.premium - c.premium) * c.contracts * 100 * sign
            }()
            let asset = "\(c.ticker) $\(fmtStrike(c.strike)) \(kind)"
            let action = "\(Int(c.contracts)) \(kindPlural) closed"
            rows.append(ActivityRow(
                date: d, ticker: c.ticker, kind: .optionClose, status: .closed,
                asset: asset, action: action,
                valueText: fmtMoney(realized, sign: true),
                isPositive: realized >= 0
            ))
        }

        // ── Share buys (from share_lots) ──
        // Skip `seed` lots — they represent the starting balance, not
        // a real purchase event. Assignment lots map to a separate
        // kind so the user can see why those shares appeared.
        for lot in shareLots where lot.source != "seed" {
            guard let d = AppDates.parseISODay(lot.acquired_date) else { continue }
            let isAssignment = lot.source == "assignment"
            let cost = -(lot.qty_original * lot.cost_per_share)
            let asset = "\(lot.ticker) shares"
            let action = isAssignment
                ? "\(Int(lot.qty_original)) sh assigned @ \(fmtMoney(lot.cost_per_share, decimals: 2))"
                : "\(Int(lot.qty_original)) sh bought @ \(fmtMoney(lot.cost_per_share, decimals: 2))"
            // OPEN if any of this lot is still on hand. Fully-consumed
            // lots (qty_remaining = 0) flip to CLOSED.
            let status: ActivityStatus = lot.qty_remaining > 0.0001 ? .open : .closed
            rows.append(ActivityRow(
                date: d, ticker: lot.ticker,
                kind: isAssignment ? .assignment : .shareBuy,
                status: status,
                asset: asset, action: action,
                valueText: fmtMoney(cost, sign: true),
                isPositive: false
            ))
        }

        // ── Share sells ── (always realized → CLOSED)
        for s in shareSells {
            guard let d = AppDates.parseISODay(s.trade_date) else { continue }
            rows.append(ActivityRow(
                date: d, ticker: s.ticker, kind: .shareSell, status: .closed,
                asset: "\(s.ticker) shares",
                action: "Sold",
                valueText: fmtMoney(s.realized_pl, sign: true),
                isPositive: s.realized_pl >= 0
            ))
        }

        // Apply date filter (if any) — compare EST calendar days.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? cal.timeZone
        let filtered: [ActivityRow] = {
            guard let target = dateFilter else { return rows }
            let targetDay = cal.startOfDay(for: target)
            return rows.filter { cal.startOfDay(for: $0.date) == targetDay }
        }()

        // Group by EST start-of-day.
        let grouped = Dictionary(grouping: filtered) { row in
            cal.startOfDay(for: row.date)
        }
        return grouped
            .map { (day, dayRows) in
                ActivityDayGroup(
                    day: day,
                    label: dayLabel(day, now: now),
                    rows: dayRows.sorted { $0.date > $1.date }
                )
            }
            // Newest day first.
            .sorted { $0.day > $1.day }
    }

    /// "Today · Jun 1" / "Yesterday · May 31" / "Wed · May 29".
    private static func dayLabel(_ day: Date, now: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? cal.timeZone
        let today = cal.startOfDay(for: now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "MMM d"
        dateFmt.timeZone = cal.timeZone

        if day == today      { return "Today · \(dateFmt.string(from: day))" }
        if day == yesterday  { return "Yesterday · \(dateFmt.string(from: day))" }

        let weekdayFmt = DateFormatter()
        weekdayFmt.dateFormat = "EEE"
        weekdayFmt.timeZone = cal.timeZone
        return "\(weekdayFmt.string(from: day)) · \(dateFmt.string(from: day))"
    }
}
