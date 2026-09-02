//
//  SunnyfiApp.swift
//  Sunnyfi
//

import SwiftUI
// Sentry SPM package is added but the product hasn't been linked to
// the Sunnyfi target yet. Uncomment the import + init once the Sentry
// product is added under target → General → Frameworks, Libraries,
// and Embedded Content.
// import Sentry


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
        // Sentry init disabled until the SPM product is linked to the
        // target — see import comment above.
        //
        // SentrySDK.start { options in
        //     options.dsn = "https://cc6408ce3279aa2d9303d9de854a955b@o4511490640707584.ingest.us.sentry.io/4511490644443136"
        //     options.sendDefaultPii = true
        //     options.tracesSampleRate = 0.1
        //     options.experimental.enableLogs = true
        // }

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

    /* ⚠ THE SHELL NOW SITS BEHIND THE GATE, NOT BESIDE IT. While the redesign
       was a branch taken before `auth.state` was ever read, it bypassed sign-in,
       onboarding and the biometric lock entirely — which was fine for a
       simulator-only preview and is not fine for the app Nik trades from. The
       old design is deleted, so the shell is what the gate opens onto and every
       protection is back in the path.

       The switch, the escapes and the crash guard are gone with it. They existed
       to make a half-built shell safe to reach and a bad build safe to leave;
       with nothing to fall back to they would only strand him. `ios-ink-final`
       is the way back now, and it is a build, not a tap. */
    /* ⚠ VERIFICATION ONLY, AND THREE CONDITIONS DEEP. Routing the shell behind
       the gate is correct and it also means the simulator now stops at sign-in,
       which is where every screenshot check in this project happens. This skips
       it — but only in a DEBUG build, only on the simulator, and only when the
       argument is passed. It cannot compile into a device build, so it is not a
       hole in the lock. */
    private var devBypass: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("-skipAuth")
        #else
        return false
        #endif
    }

    var body: some View {
        if devBypass { return AnyView(RedesignRoot()) }
        return AnyView(gated)
    }

    @ViewBuilder private var gated: some View {
        switch auth.state {
        case .loading:
            ZStack {
                Ink.canvas.ignoresSafeArea()
                ProgressView().tint(Ink.dim)
            }
            .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)

        case .signedOut:
            SignInView(auth: auth)

        case .signedIn:
            if !lock.onboardingDone {
                OnboardingView(lock: lock, prefs: prefs, onFinish: {
                    lock.onboardingDone = true
                })
            } else if lock.biometricEnabled && lock.isLocked {
                BiometricGate(lock: lock, auth: auth)
            } else {
                RedesignRoot()
            }
        }
    }
}
