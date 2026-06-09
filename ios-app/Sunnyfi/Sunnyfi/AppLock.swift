//
//  AppLock.swift
//  Sunnyfi
//
//  Biometric / pincode app lock. Lives between sign-in and the tab
//  root. On launch, on foreground-after-N-minutes, or on explicit
//  user lock, the app shows the gate and refuses to render content
//  until Face ID (or pincode fallback) succeeds.
//
//  Preferences stored in UserDefaults:
//   • biometricEnabled  — master toggle
//   • lockTimeoutMin    — 0 (immediate) | 1 | 5 | -1 (never)
//   • onboardingDone    — once true, skip the welcome flow
//
//  The lock state itself is not persisted — it always defaults to
//  "locked" on cold start when biometric is enabled. Same model as
//  banking apps.
//

import SwiftUI
import LocalAuthentication

@MainActor
@Observable
final class AppLock {

    enum LockTimeout: Int, CaseIterable, Identifiable {
        case immediate  = 0
        case oneMin     = 1
        case fiveMin    = 5
        case fifteenMin = 15
        case oneHour    = 60
        case never      = -1
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .immediate:  return "Immediately"
            case .oneMin:     return "After 1 minute"
            case .fiveMin:    return "After 5 minutes"
            case .fifteenMin: return "After 15 minutes"
            case .oneHour:    return "After 1 hour"
            case .never:      return "Never"
            }
        }
    }

    init() {
        // One-shot migration: early builds set the default lock timeout
        // to .immediate, which prompted Face ID every time the user
        // switched apps. Move existing .immediate users to .oneHour.
        let migratedKey = "lockTimeoutMigratedV2"
        if !UserDefaults.standard.bool(forKey: migratedKey) {
            let raw = UserDefaults.standard.object(forKey: "lockTimeoutMin") as? Int
            if raw == LockTimeout.immediate.rawValue {
                UserDefaults.standard.set(LockTimeout.oneHour.rawValue,
                                          forKey: "lockTimeoutMin")
            }
            UserDefaults.standard.set(true, forKey: migratedKey)
        }
    }

    /// Currently locked? When true the root view shows the BiometricGate
    /// instead of the tab content.
    var isLocked: Bool = true

    // MARK: - Preferences (UserDefaults-backed)

    var biometricEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "biometricEnabled") as? Bool ?? false }
        set {
            UserDefaults.standard.set(newValue, forKey: "biometricEnabled")
            if !newValue { isLocked = false }   // disabling = unlock now
        }
    }

    var lockTimeout: LockTimeout {
        get {
            let raw = UserDefaults.standard.object(forKey: "lockTimeoutMin") as? Int ?? LockTimeout.immediate.rawValue
            return LockTimeout(rawValue: raw) ?? .immediate
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "lockTimeoutMin") }
    }

    // MARK: - Scene phase tracking

    /// When the app last backgrounded — drives the "lock after X
    /// minutes of idle" math on the next foreground.
    private var lastBackgroundAt: Date?
    /// Did the user actually background the app (not just see a
    /// transient system dialog)? CRITICAL — without this we'd relock
    /// after every Face ID prompt, Control Center peek, or
    /// notification banner, all of which flip scenePhase to .inactive
    /// momentarily and would otherwise look like backgrounding.
    private var didActuallyBackground: Bool = false

    func onScenePhaseChange(_ newPhase: ScenePhase) {
        guard biometricEnabled else {
            isLocked = false
            return
        }
        switch newPhase {
        case .background:
            // True "user left the app" — start the idle timer + mark
            // that the next .active should re-evaluate the lock.
            lastBackgroundAt = Date()
            didActuallyBackground = true

        case .inactive:
            // Transient — Face ID prompt, Control Center, notification
            // banner, app switcher peek. Do NOT touch lock state.
            break

        case .active:
            // Only re-evaluate when we genuinely came back from a
            // background. Coming back from .inactive (e.g. just passed
            // Face ID) leaves isLocked alone — otherwise we'd loop.
            guard didActuallyBackground else { break }
            didActuallyBackground = false
            let elapsedMin: Double = {
                guard let t = lastBackgroundAt else { return .infinity }
                return Date().timeIntervalSince(t) / 60
            }()
            switch lockTimeout {
            case .immediate:  isLocked = true
            case .oneMin:     isLocked = elapsedMin >= 1
            case .fiveMin:    isLocked = elapsedMin >= 5
            case .fifteenMin: isLocked = elapsedMin >= 15
            case .oneHour:    isLocked = elapsedMin >= 60
            case .never:      isLocked = false
            }

        @unknown default:
            break
        }
    }

    // MARK: - Authenticate

    /// Try Face ID / Touch ID. Returns true on success, false otherwise.
    /// Caller decides what to do on failure (show pincode fallback).
    func authenticate(reason: String = "Unlock Sunnyfi") async -> Bool {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Device has no biometric set up (or it's disabled in iOS
            // Settings). Fall through to caller's pincode handling.
            return false
        }
        do {
            let ok = try await ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            if ok { isLocked = false }
            return ok
        } catch {
            return false
        }
    }

    /// What kind of biometric is configured on this device — drives
    /// the gate copy ("Face ID" vs "Touch ID" vs nothing).
    var biometricKind: BiometricKind {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID:  return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default:       return .none
        }
    }

    enum BiometricKind { case faceID, touchID, opticID, none
        var label: String {
            switch self {
            case .faceID:  return "Face ID"
            case .touchID: return "Touch ID"
            case .opticID: return "Optic ID"
            case .none:    return "Biometrics"
            }
        }
        var icon: String {
            switch self {
            case .faceID:  return "faceid"
            case .touchID: return "touchid"
            case .opticID: return "opticid"
            case .none:    return "lock.fill"
            }
        }
    }

    // MARK: - Onboarding flag

    var onboardingDone: Bool {
        get { UserDefaults.standard.bool(forKey: "onboardingDone") }
        set { UserDefaults.standard.set(newValue, forKey: "onboardingDone") }
    }
}
