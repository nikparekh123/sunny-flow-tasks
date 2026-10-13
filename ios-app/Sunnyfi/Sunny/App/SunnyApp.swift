//
//  SunnyApp.swift
//  Sunny
//
//  The new Sunny app (handoff 18/19): one Home page for one options book.
//  Sign-in, Face ID, the app lock and push alerts work as they did in the
//  Sunnyfi app (Nik, 12 Oct 2026: "face id, lock, push alerts stay as is");
//  Settings is gone. While it is being built it installs beside the old app
//  as com.sunnyfi.app.next and takes over com.sunnyfi.app when it ships.
//

import SwiftUI

@main
struct SunnyApp: App {
    @State private var auth = AuthStore()
    @State private var lock = AppLock()
    @State private var store = HomeStore()
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(auth: auth, lock: lock, store: store)
                .task { auth.start() }
                .onChange(of: scenePhase) { _, p in lock.onScenePhaseChange(p) }
        }
    }
}

/// Sign-in → first-run choices → the lock → Home.
struct RootView: View {
    let auth: AuthStore
    let lock: AppLock
    let store: HomeStore

    /// Screens are checked on the simulator without signing in: DEBUG only,
    /// simulator only, and only with the argument. Cannot reach a device build.
    private var devBypass: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("-skipAuth")
        #else
        return false
        #endif
    }

    var body: some View {
        if devBypass {
            HomeView(store: store)
        } else {
            switch auth.state {
            case .loading:
                SunriseLoading()
            case .signedOut:
                SignInScreen(auth: auth)
            case .signedIn:
                if !lock.onboardingDone {
                    FirstRunScreen(lock: lock) { lock.onboardingDone = true }
                } else if lock.biometricEnabled && lock.isLocked {
                    LockScreen(lock: lock)
                } else {
                    HomeView(store: store)
                }
            }
        }
    }
}
