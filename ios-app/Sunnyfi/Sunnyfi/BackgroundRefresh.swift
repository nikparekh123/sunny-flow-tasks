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
    }

    /// Ask the system to fire the task again in ≥ 15 min. iOS treats
    /// this as a hint, not a guarantee.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BackgroundRefresh] submit failed: \(error)")
        }
    }

    /// Called by the system. We have ~30s of wall time — spin up a
    /// PortfolioStore, run one refresh, then re-schedule.
    private static func handle(task: BGAppRefreshTask) {
        let store = PortfolioStore()
        let work = Task {
            // Refresh server-side data + re-fetch into the in-memory store.
            // The result is discarded — the next foreground launch will
            // surface the updated freshness pill.
            await store.refresh()
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
