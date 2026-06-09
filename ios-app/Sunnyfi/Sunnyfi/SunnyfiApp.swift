//
//  SunnyfiApp.swift
//  Sunnyfi
//

import SwiftUI
import Sentry


@main
struct SunnyfiApp: App {
    @State private var auth  = AuthStore()
    @State private var lock  = AppLock()
    @State private var prefs = NotificationPrefs()
    @Environment(\.scenePhase) private var scenePhase
    // Routes UIApplicationDelegate callbacks (APNs device-token) into
    // SwiftUI land via PushAppDelegate.
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var appDelegate

    init() {
        // Sentry — error/crash analytics. Trace + profile sampling are
        // intentionally low so we don't burn the free-tier event quota
        // on routine activity. Bump them up while diagnosing a specific
        // issue, then drop back.
        SentrySDK.start { options in
            options.dsn = "https://cc6408ce3279aa2d9303d9de854a955b@o4511490640707584.ingest.us.sentry.io/4511490644443136"
            options.sendDefaultPii = true
            options.tracesSampleRate = 0.1
            // Profiling disabled by default — re-enable with a sample
            // rate when chasing a specific performance regression.
            options.experimental.enableLogs = true
        }

        // Register the BG task handler at process launch (before
        // application(_:didFinishLaunchingWithOptions:) returns, per
        // Apple's docs). Safe if the Info.plist entry isn't there —
        // it logs + no-ops.
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView(auth: auth, lock: lock, prefs: prefs)
                .task { auth.start() }
                .onChange(of: scenePhase) { _, newPhase in
                    lock.onScenePhaseChange(newPhase)
                    if newPhase == .background {
                        // Each time we background, queue another BG fetch.
                        BackgroundRefresh.schedule()
                    }
                }
        }
    }
}

private struct RootView: View {
    let auth:  AuthStore
    let lock:  AppLock
    let prefs: NotificationPrefs

    var body: some View {
        switch auth.state {
        case .loading:
            ZStack {
                Color.theme.page.ignoresSafeArea()
                ProgressView().tint(.theme.neon)
            }
            .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)

        case .signedOut:
            SignInView(auth: auth)

        case .signedIn:
            // Three-layer gate once signed in:
            //   1. Onboarding (first-launch only)
            //   2. Biometric lock (if enabled + currently locked)
            //   3. Tab root
            if !lock.onboardingDone {
                OnboardingView(lock: lock, prefs: prefs, onFinish: {
                    lock.onboardingDone = true
                })
            } else if lock.biometricEnabled && lock.isLocked {
                BiometricGate(lock: lock, auth: auth)
            } else {
                TabRootView(auth: auth, lock: lock, prefs: prefs)
            }
        }
    }
}
