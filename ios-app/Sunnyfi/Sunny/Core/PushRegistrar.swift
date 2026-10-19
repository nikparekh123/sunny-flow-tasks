//
//  PushRegistrar.swift
//  Sunny (carried over from the Sunnyfi app unchanged, handoff 18)
//
//  Bridges iOS APNs registration and the Supabase `push_devices`
//  table. Lifecycle:
//   1. User grants notification permission (in onboarding / Settings)
//   2. We call `UIApplication.shared.registerForRemoteNotifications()`
//   3. iOS gives us a device token via the AppDelegate callback
//   4. We POST it to push_devices so the apns-deliver worker can
//      reach this device
//
//  Because Sunnyfi is SwiftUI-only, the device-token callbacks are
//  routed through an UIApplicationDelegateAdaptor bound in
//  SunnyfiApp.swift. See `PushAppDelegate` below.
//

import Foundation
import SwiftUI
import UIKit
import UserNotifications
import Supabase

@MainActor
@Observable
final class PushRegistrar {
    /// Last device token we successfully registered with Supabase.
    var lastToken: String?
    var lastError: String?

    /// Bundle id we report to push_devices, read from the app itself.
    ///
    /// This was hard-coded to "com.sunnyfi.Sunnyfi" and the app's real bundle
    /// is com.sunnyfi.app, so every one of the 13 registered devices carried a
    /// bundle id that does not exist. It mattered twice over: apns-deliver
    /// filters push_devices by it, AND the same string is sent to Apple as the
    /// apns-topic, where it must be the true bundle id or APNs answers
    /// TopicDisallowed. Set it correctly for Apple and the device lookup found
    /// nothing; set it to match the rows and Apple refused the push.
    ///
    /// Reading it from Bundle.main means it cannot drift from the target again.
    private let bundleId = Bundle.main.bundleIdentifier ?? "com.sunnyfi.app"

    /// Which APNs server the worker must use for this device's token: the one
    /// the app is SIGNED for, read from its provisioning profile. A Release
    /// build installed with a development profile (how Nik's phone is set up
    /// since the 13 Oct 2026 launch) gets sandbox tokens; "not DEBUG" had
    /// reported it as production, and Apple would reject every alert. App
    /// Store builds carry no embedded profile and are production.
    private var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let key = text.range(of: "<key>aps-environment</key>") else { return "production" }
        return text[key.upperBound...].prefix(80).contains("development") ? "sandbox" : "production"
        #endif
    }

    /// Called from the AppDelegate when iOS hands us the token bytes.
    /// Converts to hex and uploads to push_devices.
    func handleAPNsToken(_ data: Data) async {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        lastToken = hex
        await upsertToSupabase(token: hex)
    }

    func handleAPNsError(_ error: Error) {
        lastError = error.localizedDescription
        print("[PushRegistrar] APNs registration failed: \(error)")
    }

    private func upsertToSupabase(token: String) async {
        let row = PushDeviceRow(
            token: token,
            environment: environment,
            bundle_id: bundleId,
            device_label: Self.deviceLabel(),
            last_seen_at: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await SupabaseService.client
                .from("push_devices")
                .upsert(row, onConflict: "token")
                .execute()
            print("[PushRegistrar] registered token \(token.prefix(12))…")
        } catch {
            lastError = String(describing: error)
            print("[PushRegistrar] upsert failed: \(error)")
        }
    }

    /// Human-readable device tag for the admin debugging view.
    private static func deviceLabel() -> String {
        let device = UIDevice.current
        return "\(device.model) · iOS \(device.systemVersion)"
    }
}

/// Encodable shape that matches `push_devices` columns.
private struct PushDeviceRow: Encodable {
    let token: String
    let environment: String
    let bundle_id: String
    let device_label: String
    let last_seen_at: String
}

// MARK: - UIApplicationDelegateAdaptor bridge

/// SwiftUI apps don't have an AppDelegate by default. We register a
/// minimal one solely to receive the APNs device-token callback
/// (and the registration-failed counterpart). Bound in
/// `SunnyfiApp` via `@UIApplicationDelegateAdaptor`.
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    /// Shared registrar instance. SwiftUI views read from this via
    /// the binding installed in SunnyfiApp.
    static let registrar = PushRegistrar()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Set the notification delegate so taps on a notification
        // route through us (for deep-linking later).
        UNUserNotificationCenter.current().delegate = self
        // Re-register on every launch once alerts are allowed (Apple's advice):
        // keeps push_devices fresh and survives the takeover of com.sunnyfi.app,
        // where first-run setup (the only other registration point) is skipped.
        UNUserNotificationCenter.current().getNotificationSettings { s in
            guard s.authorizationStatus == .authorized || s.authorizationStatus == .provisional else { return }
            Self.registrar.requestSystemRegistration()
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            await Self.registrar.handleAPNsToken(deviceToken)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            Self.registrar.handleAPNsError(error)
        }
    }
}

extension PushAppDelegate: UNUserNotificationCenterDelegate {
    /// Show banner+badge+sound while the app is foregrounded.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
                                -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }

    /// User tapped a notification. A push that carries a deep link (the
    /// 4:16 PM Aftershock push: sunny://aftershock) opens that page once
    /// Home is up; any other push just opens the app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let link = response.notification.request.content.userInfo["deep_link"] as? String
        await MainActor.run { PushInbox.shared.link = link }
    }
}

/// The deep link of the last tapped push, until Home has opened it.
@MainActor
@Observable
final class PushInbox {
    static let shared = PushInbox()
    var link: String?
}

// MARK: - Public entry point

extension PushRegistrar {
    /// Call once you have notification permission (after onboarding
    /// grant or via Settings toggle). Triggers the APNs token request;
    /// the AppDelegate will receive the bytes shortly after.
    func requestSystemRegistration() {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}
