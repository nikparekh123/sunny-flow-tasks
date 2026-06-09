//
//  Dates.swift
//  Sunnyfi
//
//  Helpers for the ISO date strings Supabase returns (`YYYY-MM-DD` for
//  trade_date / expiry / earnings_date, plus full ISO for captured_at).
//

import Foundation

enum AppDates {
    /// Parse a `trade_date` / `expiry` string. Most rows are plain
    /// "YYYY-MM-DD"; some may arrive as full ISO timestamps like
    /// "2026-05-31T00:00:00+00:00". Accept both. **Returned as EST
    /// midnight** — Sunnyfi treats market dates as EST everywhere
    /// (trade dates, expiries, etc.) so parsing as UTC midnight
    /// caused off-by-one bugs when later compared to "today in EST".
    static func parseISODay(_ s: String) -> Date? {
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = TimeZone(identifier: "America/New_York")
        if let d = day.date(from: String(s.prefix(10))) { return d }
        return ISO8601DateFormatter().date(from: s)
    }

    /// Days until an ISO day, computed in **US Eastern time** (the market
    /// clock). Crucial because UTC midnight is ahead of EST midnight by
    /// 4-5h: a UTC-naive comparison can report an expiry as "today" when
    /// the market still sees it as "tomorrow", or vice versa.
    /// Negative if the day is in the past.
    static func daysUntil(_ iso: String, from now: Date = Date()) -> Int? {
        guard let eastern = TimeZone(identifier: "America/New_York") else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = eastern

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = eastern
        guard let target = df.date(from: iso) else { return nil }

        let startOfToday = cal.startOfDay(for: now)
        return cal.dateComponents([.day], from: startOfToday, to: target).day
    }

    /// Calendar days between an ISO day (e.g. a trade_date) and a
    /// Date. Returns the absolute number so the "Days held" summary
    /// on the close ticket always reads non-negative. EST-anchored
    /// for consistency with the other helpers here.
    static func daysBetween(_ iso: String, _ now: Date) -> Int? {
        guard let eastern = TimeZone(identifier: "America/New_York") else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = eastern

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = eastern
        guard let start = df.date(from: iso) else { return nil }

        let startDay = cal.startOfDay(for: start)
        let endDay   = cal.startOfDay(for: now)
        guard let days = cal.dateComponents([.day], from: startDay, to: endDay).day else {
            return nil
        }
        return abs(days)
    }

    /// "Jun 19" style — short month + day. Formatted in EST to match
    /// how parseISODay anchors the Date.
    static func shortMonthDay(_ iso: String) -> String {
        guard let d = parseISODay(iso) else { return iso }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return f.string(from: d)
    }

    /// "Mon" / "Fri" — weekday abbreviation. EST-anchored.
    static func weekdayShort(_ iso: String) -> String {
        guard let d = parseISODay(iso) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return f.string(from: d)
    }

    /// Start of the week (Monday) containing the given date — EST.
    static func startOfWeek(_ date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        cal.firstWeekday = 2 // Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }

    /// Start of the calendar month containing the given date (EST).
    static func startOfMonth(_ date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? date
    }
}
