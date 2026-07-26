//
//  AppNavigator.swift
//  Sunnyfi
//
//  Single source of truth for "where should the app be right now" —
//  driven by push notification taps. PushAppDelegate parses the
//  payload and writes the requested tab + optional ticker sheet
//  here; TabRootView observes and reacts.
//
//  Pending writes are buffered until the user is signed in +
//  unlocked. If a push arrives while the app is on the sign-in
//  screen or biometric gate, the navigation happens automatically
//  once the user clears those gates and TabRootView mounts.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class AppNavigator {
    /// Process-wide singleton — PushAppDelegate writes here from
    /// its UNUserNotificationCenter callback, no DI needed.
    static let shared = AppNavigator()
    private init() {}

    /// Tab the next render should switch to. Cleared by the consumer
    /// once applied so subsequent unrelated re-renders don't keep
    /// snapping the tab.
    var requestedTab: AppTab?

    /// Ticker whose TickerTradesSheet should be presented. Same
    /// consumer pattern.
    var requestedTickerSheet: String?

    /// Map a push payload to an in-app navigation request. The
    /// category enum names match `NotificationPrefs.Category.rawValue`
    /// and the alert-dispatcher edge function — keep all three in
    /// sync when adding a new notification type.
    func handlePush(category: String?, ticker: String?) {
        guard let category else { return }
        switch category {
        // Theta / put alerts and assignment / short-call ITM / earnings.
        // The Hedge and Trades tabs were dropped in the handoff-6 nav, so
        // land on Covered Call (the positions surface) and open the
        // affected ticker sheet — the ticker sheet is the useful payload.
        case "theta_cliff", "theta_critical", "long_put_itm",
             "short_call_itm", "assignment", "earnings_day_before":
            requestedTab = .coveredCall
            requestedTickerSheet = ticker

        // Critical pipeline alerts already render via the global
        // SystemAlertBanner — no navigation action needed.
        case "data_pipeline_stale":
            break

        default:
            break
        }
    }

    /// Mark intents consumed after the UI has applied them.
    func consumeTabRequest()    { requestedTab = nil }
    func consumeTickerRequest() { requestedTickerSheet = nil }
}
