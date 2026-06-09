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
        // Hedge-related — all of these are theta / put alerts; the
        // user wants to land on the Hedge tab and see the affected
        // ticker.
        case "theta_cliff", "theta_critical", "long_put_itm":
            requestedTab = .hedge
            requestedTickerSheet = ticker

        // Trades-related — assignment / short-call ITM / earnings
        // map to the active-positions surface.
        case "short_call_itm", "assignment", "earnings_day_before":
            requestedTab = .trades
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
