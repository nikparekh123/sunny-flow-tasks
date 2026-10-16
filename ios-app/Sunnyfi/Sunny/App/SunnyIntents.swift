//
//  SunnyIntents.swift
//  Sunny
//
//  Shortcuts and Siri actions for the eye on the account block (Nik, 16 Oct
//  2026: travel privacy). "Hide Sunny numbers" and "Show Sunny numbers" set
//  the same stored switch the eye does, so the account block opens blurred or
//  clear; the eye still toggles it by hand at any time. Sunny never sees a
//  location: a Shortcuts automation (Leave home / Arrive home) runs these.
//  Account block only for now; blurring every figure needs a design first.
//

import AppIntents
import Foundation

/// The eye's stored switch (AccountChart's @AppStorage key).
enum SunnyPrivacy {
    static let key = "sunny.hideNumbers"
    static func set(_ hidden: Bool) { UserDefaults.standard.set(hidden, forKey: key) }
}

struct HideSunnyNumbers: AppIntent {
    static let title: LocalizedStringResource = "Hide Sunny numbers"
    static let description = IntentDescription("Blurs the account numbers on Sunny's Home, like tapping the eye.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SunnyPrivacy.set(true)
        return .result(dialog: "Sunny numbers hidden.")
    }
}

struct ShowSunnyNumbers: AppIntent {
    static let title: LocalizedStringResource = "Show Sunny numbers"
    static let description = IntentDescription("Shows the account numbers on Sunny's Home again, like tapping the eye.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SunnyPrivacy.set(false)
        return .result(dialog: "Sunny numbers showing.")
    }
}

/// Ready in Shortcuts and Siri without any setup ("Hide numbers in Sunny").
struct SunnyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: HideSunnyNumbers(),
                    phrases: ["Hide numbers in \(.applicationName)", "Hide \(.applicationName) numbers"],
                    shortTitle: "Hide numbers", systemImageName: "eye.slash")
        AppShortcut(intent: ShowSunnyNumbers(),
                    phrases: ["Show numbers in \(.applicationName)", "Show \(.applicationName) numbers"],
                    shortTitle: "Show numbers", systemImageName: "eye")
    }
}
