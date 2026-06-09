//
//  NotificationPrefs.swift
//  Sunnyfi
//
//  Local toggles for each notification category. Stored in
//  UserDefaults so they survive launches. When the user signs in
//  on a new device, defaults below apply.
//
//  These mirror the proposed tiers from the pre-launch checklist:
//   • Critical — always on, can't be toggled off here
//   • Awareness — defaults on, individually toggleable
//   • Macro — defaults off, individually toggleable
//
//  The category set is the contract between the iOS app and the
//  edge function that fans out alerts (Wave C). When adding a new
//  notification type, register the case here AND in the edge
//  dispatcher.
//

import Foundation
import SwiftUI
import UserNotifications

@MainActor
@Observable
final class NotificationPrefs {

    enum Category: String, CaseIterable, Identifiable {
        // Critical — always on (no toggle).
        case assignment           = "assignment"
        case dataPipelineStale    = "data_pipeline_stale"

        // Awareness — defaults on.
        case thetaCliff           = "theta_cliff"
        case thetaCritical        = "theta_critical"
        case shortCallITM         = "short_call_itm"
        case longPutITM           = "long_put_itm"
        case earningsDayBefore    = "earnings_day_before"
        case dailyRecap           = "daily_recap"

        // Macro — defaults off.
        case cpi                  = "cpi"
        case fomc                 = "fomc"
        case ppi                  = "ppi"
        case jobs                 = "jobs"
        case bigSpyMove           = "big_spy_move"

        var id: String { rawValue }
        var tier: Tier {
            switch self {
            case .assignment, .dataPipelineStale: return .critical
            case .thetaCliff, .thetaCritical, .shortCallITM,
                 .longPutITM, .earningsDayBefore, .dailyRecap: return .awareness
            case .cpi, .fomc, .ppi, .jobs, .bigSpyMove: return .macro
            }
        }
        var label: String {
            switch self {
            case .assignment:        return "Position assigned"
            case .dataPipelineStale: return "Data pipeline issue"
            case .thetaCliff:        return "Leg enters cliff zone (21 DTE)"
            case .thetaCritical:     return "Leg enters critical zone (7 DTE)"
            case .shortCallITM:      return "Short call goes ITM"
            case .longPutITM:        return "Long put goes ITM"
            case .earningsDayBefore: return "Earnings — day before"
            case .dailyRecap:        return "Daily P&L recap"
            case .cpi:               return "CPI release"
            case .fomc:              return "FOMC meeting"
            case .ppi:               return "PPI release"
            case .jobs:              return "Jobs report"
            case .bigSpyMove:        return "Big SPY move (>2%)"
            }
        }
    }

    enum Tier: String { case critical, awareness, macro
        var label: String { rawValue.capitalized }
    }

    /// System permission state (cached at sign-in / app foreground).
    var systemPermission: UNAuthorizationStatus = .notDetermined

    init() {
        Task { await refreshSystemPermission() }
    }

    // MARK: - Per-category toggle

    func isEnabled(_ cat: Category) -> Bool {
        // Critical tier is always on regardless of the stored value.
        if cat.tier == .critical { return true }
        // Defaults: awareness on, macro off — but only when the key
        // hasn't been touched. Once user sets it, that wins.
        if UserDefaults.standard.object(forKey: prefKey(cat)) == nil {
            return cat.tier == .awareness
        }
        return UserDefaults.standard.bool(forKey: prefKey(cat))
    }

    func setEnabled(_ enabled: Bool, for cat: Category) {
        guard cat.tier != .critical else { return }
        UserDefaults.standard.set(enabled, forKey: prefKey(cat))
    }

    private func prefKey(_ cat: Category) -> String {
        "notif.\(cat.rawValue)"
    }

    // MARK: - System permission

    /// Pull current authorization status from UNUserNotificationCenter.
    func refreshSystemPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.systemPermission = settings.authorizationStatus
    }

    /// Ask iOS for permission. Returns the new state.
    func requestPermission() async -> UNAuthorizationStatus {
        do {
            _ = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            print("[NotificationPrefs] auth request failed: \(error)")
        }
        await refreshSystemPermission()
        return systemPermission
    }
}
