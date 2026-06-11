//
//  Perf.swift
//  Sunnyfi
//
//  Tiny wrapper around OSSignposter so we can profile cold-launch
//  fan-out and hot-path rebuild cost in Instruments without
//  scattering imports + boilerplate across the codebase.
//
//  In Instruments → "os_signpost" track, intervals appear as
//  bracketed spans and events as ticks. Filter by the
//  "com.sunnyfi.perf" subsystem to isolate ours.
//
//  Free in release builds (signposts compile down to no-ops when
//  no Instruments tool is recording). No need to gate by DEBUG.
//

import Foundation
import os

enum Perf {
    /// Shared signposter. Subsystem = bundle, category = "perf" so all
    /// Sunnyfi marks group cleanly in Instruments.
    static let signposter = OSSignposter(
        subsystem: "com.sunnyfi.perf",
        category: "perf"
    )

    /// Async interval: brackets `work()` with begin/end signposts
    /// under `name`. Returns whatever `work()` returns.
    @discardableResult
    static func interval<T>(
        _ name: StaticString,
        _ work: () async throws -> T
    ) async rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await work()
    }

    /// Sync variant — for tight CPU-bound code (build*, derive*).
    @discardableResult
    static func intervalSync<T>(
        _ name: StaticString,
        _ work: () throws -> T
    ) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try work()
    }

    /// Manual begin — for cases where the work spans control flow
    /// that can't be wrapped in a closure (mid-function spans).
    /// Always pair with `end(_:_:)`.
    static func begin(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    static func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    /// Single-point event with an optional message. Lightweight enough
    /// to put inside a View body — use sparingly though, since SwiftUI
    /// rebuilds can fire dozens of times per gesture.
    static func event(_ name: StaticString, _ message: String = "") {
        if message.isEmpty {
            signposter.emitEvent(name)
        } else {
            signposter.emitEvent(name, "\(message)")
        }
    }
}
