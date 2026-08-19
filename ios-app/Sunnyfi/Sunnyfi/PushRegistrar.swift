//
//  PushRegistrar.swift
//  Sunnyfi
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

    /// Are we a debug/simulator build (sandbox APNs) or a TestFlight /
    /// App Store build (production APNs)? Affects which APNs server
    /// the worker has to use for this device.
    private var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
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

    /// User tapped a notification. The Ink rebuild is a single NVDA
    /// surface, so a tap just brings the app to the foreground on the
    /// portfolio — there's no multi-ticker tab to route to. (Deep-link
    /// routing into a specific section can be re-added here once the
    /// Ink nav model needs it.)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        // no-op: opening the app is the whole action for now
    }
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
