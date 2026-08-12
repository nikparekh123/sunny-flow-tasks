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

    /// Margin notes on the planner sheets. On by default, but it has to stay
    /// switchable: some readers take them as noise, screenshots and exports are
    /// cleaner without them, and a script face at 0.6 opacity fails contrast, so
    /// every sheet must still work with them off. Off removes the mark entirely
    /// rather than fading it, and nothing reflows, because marks are overlaid.
    var handwriting: Bool {
        get { UserDefaults.standard.object(forKey: "prefs.handwriting") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "prefs.handwriting") }
    }

    /// Auto = follow the system; Light = always light; Dark = always
    /// dark. Each Color.theme token resolves dynamically against the
    /// active trait, so the choice flows through the whole app.
    var appearance: Appearance = {
        let raw = UserDefaults.standard.string(forKey: "prefs.appearance") ?? Appearance.dark.rawValue
        return Appearance(rawValue: raw) ?? .dark
    }() {
        // Stored + @Observable so views (the Profile segmented control, InkRoot's
        // preferredColorScheme) re-render and animate when it changes; didSet persists.
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "prefs.appearance") }
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
