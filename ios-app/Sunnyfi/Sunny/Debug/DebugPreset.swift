//
//  DebugPreset.swift
//  Sunny
//
//  The audit harness (handoff 18, Step 5): every gallery state can be set
//  from launch arguments on the simulator, so each one is screenshotted
//  beside its Build Blocks tile. DEBUG and simulator only; a device or
//  release build compiles all of it away and reads the real clock.
//
//    -now 2026-11-25T17:30        New York time for the clock
//    -preset key=value,key=value  a component's starting state
//    -gallery <block>             one block alone, as a gallery tile
//

import Foundation

enum SClock {
    /// The time the app believes it is.
    static func now() -> Date { override ?? Date() }

    static let override: Date? = {
        #if DEBUG && targetEnvironment(simulator)
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-now"), i + 1 < a.count else { return nil }
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "America/New_York"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f.date(from: a[i + 1])
        #else
        return nil
        #endif
    }()
}

enum DebugPreset {
    static let values: [String: String] = {
        #if DEBUG && targetEnvironment(simulator)
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-preset"), i + 1 < a.count else { return [:] }
        var out: [String: String] = [:]
        for kv in a[i + 1].split(separator: ",") {
            let p = kv.split(separator: "=", maxSplits: 1).map(String.init)
            out[p[0]] = p.count > 1 ? p[1] : "1"
        }
        return out
        #else
        return [:]
        #endif
    }()

    static let gallery: String? = {
        #if DEBUG && targetEnvironment(simulator)
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-gallery"), i + 1 < a.count else { return nil }
        return a[i + 1]
        #else
        return nil
        #endif
    }()

    static func string(_ k: String) -> String? { values[k] }
    static func bool(_ k: String) -> Bool { values[k].map { $0 == "1" || $0 == "true" } ?? false }
    static func int(_ k: String) -> Int? { values[k].flatMap { Int($0) } }
    static func double(_ k: String) -> Double? { values[k].flatMap { Double($0) } }
    static func set(_ k: String) -> Set<String> { Set((values[k] ?? "").split(separator: "+").map(String.init)) }
}
