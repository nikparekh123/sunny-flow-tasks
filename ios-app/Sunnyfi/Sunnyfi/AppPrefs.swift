//
//  AppPrefs.swift
//  Sunnyfi
//
//  UI-only preferences: mask P&L, appearance mode, background
//  refresh. UserDefaults-backed. Read directly via the @Observable
//  singleton so any view re-renders on change.
//
//  Notification + biometric prefs live in NotificationPrefs +
//  AppLock — they're domain-specific and pre-date this file.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class AppPrefs {
    static let shared = AppPrefs()
    private init() {}

    enum Appearance: String, CaseIterable, Identifiable {
        case auto = "Auto", light = "Light", dark = "Dark"
        var id: String { rawValue }
        var colorScheme: ColorScheme? {
            switch self {
            case .auto:  return nil
            case .light: return .light
            case .dark:  return .dark
            }
        }
    }

    /// Hide every monetary value app-wide. Mirrored from the
    /// existing eye toggle on the home hero so the gesture works
    /// from either surface.
    var hidePnL: Bool {
        get { UserDefaults.standard.bool(forKey: "prefs.hidePnL") }
        set { UserDefaults.standard.set(newValue, forKey: "prefs.hidePnL") }
    }

    /// Auto = follow the system; Light = always light; Dark = always
    /// dark. Each Color.theme token resolves dynamically against the
    /// active trait, so the choice flows through the whole app.
    var appearance: Appearance {
        get {
            let raw = UserDefaults.standard.string(forKey: "prefs.appearance") ?? Appearance.dark.rawValue
            return Appearance(rawValue: raw) ?? .dark
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "prefs.appearance") }
    }

    /// Whether iOS should silently pull market data while the app is
    /// backgrounded. Off = stay on the foreground/cron-only schedule.
    var backgroundRefresh: Bool {
        get { UserDefaults.standard.object(forKey: "prefs.backgroundRefresh") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "prefs.backgroundRefresh") }
    }

    /// Admin override: show the bottom-right Trade pill for entering
    /// trades manually. Default OFF — IBKR Flex sync is the primary
    /// source of truth. Flip ON only when IBKR is down or for an
    /// out-of-broker fill that needs to be reconciled by hand.
    /// (Renamed from "Trade entry" to "Manual entry (use sparingly)"
    /// in the UI to discourage casual use.)
    var manualEntryEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "prefs.manualEntryEnabled") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "prefs.manualEntryEnabled") }
    }
}
