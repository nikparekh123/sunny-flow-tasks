//
//  Formatters.swift
//  Sunnyfi
//
//  Cached `DateFormatter` / `ISO8601DateFormatter` instances for the
//  hot rendering paths. Per Apple's docs, DateFormatter is thread-safe
//  on iOS 7+, so a `static let` instance can be shared freely across
//  the main actor and detached work.
//
//  Before this file existed, helpers like `shortDate(_:)` in each
//  drill-in sheet allocated a fresh DateFormatter inside the body
//  every time a row rendered. Per-cell allocations show up clearly
//  in Instruments as a long tail of `objc_msgSend` and ICU calls
//  during scroll. Hoisting them to static is a ~zero-risk speedup
//  that the standardized popups + EventCards + ActivityFeed share.
//
//  Convention:
//   • Append timezone suffix when the format is tz-sensitive
//     (`ymdET` = "yyyy-MM-dd" parsed as ET, etc).
//   • UTC variants are explicit (`isoUTC`).
//

import Foundation

enum Fmt {

    // MARK: - Static instances

    /// "yyyy-MM-dd" parsed/formatted in America/New_York.
    /// Used for IBKR trade_date / expiry strings that arrive
    /// without an explicit tz offset.
    static let ymdET: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// "MMM d" in America/New_York (e.g. "Jul 18"). The compact
    /// expiry / event format used inside every drill-in row.
    static let monthDayET: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// "EEE" (e.g. "Wed") in America/New_York. Used by the activity
    /// feed day-label and elsewhere a 3-letter weekday is needed.
    static let weekdayET: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Standard ISO8601 with timezone. For Supabase timestamptz
    /// columns and last_synced_at on IBKR rows.
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// ISO8601 with fractional seconds. Some Postgres `now()` paths
    /// emit ".123456+00", so parsing fallbacks need this option.
    static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Helpers

    /// "yyyy-MM-dd" → "Jul 18". Returns the raw string when the
    /// input isn't parseable, so the UI shows something rather than
    /// blanking out on malformed data.
    static func shortDate(_ ymd: String) -> String {
        guard let d = ymdET.date(from: ymd) else { return ymd }
        return monthDayET.string(from: d)
    }
}
