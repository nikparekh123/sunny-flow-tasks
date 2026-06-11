//
//  StatusDot.swift
//  Sunnyfi
//
//  Minimal data-freshness indicator. Replaces SyncIndicator (the
//  orbit-ring + label + tap-to-sync control). Per the stabilization
//  pass, the app no longer exposes any user-driven sync — IBKR runs
//  on a 30-min cron during the trading window and the app reads
//  whatever's there. The dot is purely a passive heartbeat: it
//  surfaces ONLY when something looks off, and it isn't tappable.
//
//  States:
//   • Fresh  — dot is hidden entirely (no visual noise).
//   • Stale  — small ORANGE dot. Last successful sync is older
//              than 35 min during the trading window, or the
//              first attempt of the current slot failed and we're
//              waiting on the 15-min retry.
//   • Failed — small RED dot. The retry slot also failed, or
//              we've gone 90+ min without a fresh sync inside
//              the window. A row exists in `ibkr_sync_alerts` on
//              the backend.
//
//  Outside the trading window (after 16:30 ET, weekends, holidays),
//  the dot stays hidden — staleness isn't meaningful when the cron
//  isn't supposed to be running anyway.
//

import Combine
import SwiftUI

struct StatusDot: View {

    enum Level {
        case fresh   // hidden
        case stale   // orange
        case failed  // red
    }

    let store: PortfolioStore

    /// Bumped every 30s so the dot updates without the store needing
    /// to re-emit. Light cadence — staleness is in minutes, not
    /// seconds.
    @State private var tick: Int = 0
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var level: Level {
        _ = tick
        // Hard-failed marker from the store wins over everything.
        if store.lastRefreshError != nil { return .failed }
        // Off-window staleness isn't actionable — keep silent.
        guard inTradingWindow else { return .fresh }
        guard let last = store.freshness else { return .failed }
        let mins = -last.timeIntervalSinceNow / 60.0
        if mins > 90 { return .failed }
        if mins > 35 { return .stale }
        return .fresh
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(level == .fresh ? 0 : 1)
            .animation(.easeOut(duration: 0.25), value: level)
            .frame(minWidth: 12, minHeight: 12, alignment: .leading)
            .accessibilityHidden(level == .fresh)
            .accessibilityLabel(level == .failed ? "Sync failed" : "Sync stale")
            .onReceive(timer) { _ in tick &+= 1 }
    }

    private var color: Color {
        switch level {
        case .fresh:  return .clear
        case .stale:  return Color(red: 232/255, green: 144/255, blue: 60/255)  // orange
        case .failed: return .theme.neg                                          // red
        }
    }

    /// Weekday, 10:00–16:30 America/New_York. Matches the new cron.
    private var inTradingWindow: Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let now = Date()
        let weekday = cal.component(.weekday, from: now)   // 1 = Sun
        guard weekday >= 2 && weekday <= 6 else { return false }
        let h = cal.component(.hour, from: now)
        let m = cal.component(.minute, from: now)
        let mins = h * 60 + m
        return mins >= (10 * 60) && mins <= (16 * 60 + 30)
    }
}
