//
//  MacroEvents.swift
//  Sunnyfi
//
//  Hardcoded calendar of upcoming macro events (FOMC, CPI, NFP, etc.).
//  Edit this list directly — events within 5 days of "today" surface
//  as an Update card on Home.
//
//  Format per event:
//    MacroEvent(date: "YYYY-MM-DD", time: "HH:MM ET", name: "FOMC", summary: "Rate decision + presser")
//

import Foundation

struct MacroEvent: Sendable, Identifiable {
    let id = UUID()
    let date: String        // "YYYY-MM-DD" — interpreted as Eastern time
    let time: String        // free-form, e.g. "08:30 ET" or "All day"
    let name: String        // "FOMC", "CPI", "NFP", "ECB"…
    let summary: String     // one-line "what to expect"
}

enum MacroEvents {

    /// ───────────────────────────────────────────────────────────
    ///  Add upcoming events here. Past dates are auto-filtered out.
    ///  Tip: keep dates sorted ascending so the closest fires first.
    /// ───────────────────────────────────────────────────────────
    static let upcoming: [MacroEvent] = [
        // Examples — replace with the real upcoming calendar:
        // MacroEvent(date: "2026-06-04", time: "08:30 ET", name: "CPI",  summary: "May headline CPI · core expected +0.3% m/m"),
        // MacroEvent(date: "2026-06-06", time: "08:30 ET", name: "NFP",  summary: "May payrolls · consensus +185k"),
        // MacroEvent(date: "2026-06-12", time: "14:00 ET", name: "FOMC", summary: "Rate decision + 14:30 presser · dot-plot revision"),
    ]

    /// Returns events whose `date` is between today and `daysAhead` from
    /// now (Eastern time). Past events are dropped.
    static func upcomingWithin(_ daysAhead: Int, from now: Date = Date()) -> [MacroEvent] {
        upcoming.compactMap { e in
            guard let dte = AppDates.daysUntil(e.date, from: now) else { return nil }
            return (dte >= 0 && dte <= daysAhead) ? e : nil
        }
    }
}
