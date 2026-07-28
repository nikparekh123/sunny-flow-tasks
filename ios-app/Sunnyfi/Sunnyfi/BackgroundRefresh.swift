//
//  BackgroundRefresh.swift
//  Sunnyfi
//
//  Wraps BGTaskScheduler so iOS can opportunistically pull fresh
//  market data while the app is closed. We ask for a 15-min cadence
//  to match the server-side cron; iOS schedules it when it thinks
//  is best (battery / network / usage patterns).
//
//  Setup required outside this file:
//   • Add 'com.sunnyfi.app.refresh' to Info.plist key
//     `BGTaskSchedulerPermittedIdentifiers` (array)
//   • Enable the Background Modes capability in Signing & Capabilities
//     and tick "Background fetch" + "Background processing"
//
//  Without those, BGTaskScheduler.shared.register() throws at launch.
//  We log + swallow so the rest of the app still runs in dev builds
//  that haven't been configured.
//

import BackgroundTasks
import Foundation
import Supabase
import SwiftUI

enum BackgroundRefresh {
    static let taskIdentifier = "com.sunnyfi.app.refresh"

    /// Call from `SunnyfiApp.init` or `.task` once. Registers the
    /// handler with the system. The handler does NOT have a strong
    /// reference to the store; resolve it from a fresh PortfolioStore
    /// instance inside the task (the app may be killed between
    /// scheduling and firing).
    @MainActor
    static func register() {
        // BGTaskScheduler isn't available in the iOS Simulator — calling
        // it spams the console with "BGTaskScheduler is not available on
        // this platform." errors that aren't actionable. Skip silently
        // in sim; the server-side cron handles refresh anyway.
        #if targetEnvironment(simulator)
        return
        #else
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task: task)
        }
        if !registered {
            // Most common cause: Info.plist `BGTaskSchedulerPermittedIdentifiers`
            // doesn't include the id. Not fatal — we log and the cron-driven
            // server-side refresh keeps working.
            print("[BackgroundRefresh] register() returned false — check Info.plist")
        }
        // Schedule the first run.
        schedule()
        #endif
    }

    /// Ask the system to fire the task again in ≥ 15 min. iOS treats
    /// this as a hint, not a guarantee.
    static func schedule() {
        #if targetEnvironment(simulator)
        return  // BGTaskScheduler unavailable on simulators
        #else
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BackgroundRefresh] submit failed: \(error)")
        }
        #endif
    }

    /// Called by the system. We have ~30s of wall time — nudge the NVDA
    /// marks feed so fresh spot + greeks are waiting on the next launch,
    /// then re-schedule.
    private static func handle(task: BGAppRefreshTask) {
        let work = Task {
            // Trigger the server-side 60s feed once. The result is discarded —
            // the next foreground launch re-fetches into NvdaStore.
            _ = try? await SupabaseService.client.functions
                .invoke("nvda-marks", options: FunctionInvokeOptions(body: [String: String]())) as Data
        }
        task.expirationHandler = {
            // System reclaiming time — cancel the in-flight refresh.
            work.cancel()
        }
        Task {
            _ = await work.value
            schedule()                    // queue the next one
            task.setTaskCompleted(success: true)
        }
    }
}
