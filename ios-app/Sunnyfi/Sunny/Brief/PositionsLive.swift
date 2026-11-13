//
//  PositionsLive.swift
//  Sunny
//
//  Positions on the real book (handoff 6 Nov 2026, Pass 2). When the tab opens a name, the phone asks
//  sunny-positions for it with the signed-in user's token (RLS: members of the book only) and gets every leg's
//  P&L, delta, theta and vega on a price-by-date grid (±12%, and out to ±50%). PositionsSource decodes each reply
//  once, off the main thread, and keeps one model per name and build (never built in a view's body).
//

import Foundation
import Observation
import Supabase

/// What sunny-positions sends (book-engine.ts positionsGrid), as far as the Positions tab reads it: the grid's prices
/// and date stops, each leg's P&L, delta, theta and vega on them, and the turns-short price per stop. The rest of the
/// reply (the fix's OTM call, the walls by chain, the Technicals lines, the legs that ended) is left undecoded.
nonisolated struct PositionsWire: Decodable, Sendable {
    nonisolated struct StopW: Decodable, Sendable { let tt: Double; let short: String; let phrase: String; let long: String }
    nonisolated struct LegW: Decodable, Sendable {
        let k: String; let kind: String; let ty: String; let K: Double; let q: Double; let ex: String; let days: Double; let label: String
        let earned: Double; let value: Double; let pl: [[Double]]; let d: [[Double]]; let th: [[Double]]; let vg: [[Double]]; let pl0: [Double]?
    }

    let t: String; let S0: Double; let P0: Double; let iv: Double
    let S: [Double]; let stops: [StopW]; let legs: [LegW]; let turnsShort: [Double?]; let fridayStop: Int
}

@MainActor @Observable
final class PositionsSource {
    /// The model per book and name, and the build it was priced on.
    private(set) var models: [String: (built: String, m: PositionsModel)] = [:]
    private(set) var errors: [String: String] = [:]
    private var inFlight: Set<String> = []

    func model(_ book: String, _ t: String) -> PositionsModel? { models["\(book)|\(t)"]?.m }
    func error(_ book: String, _ t: String) -> String? { errors["\(book)|\(t)"] }

    /// Asks for a name when it is missing or priced on an older build. `name` is Home's brief entry for it.
    func load(book: String, t: String, built: String, name: JSONValue) {
        let key = "\(book)|\(t)"
        if models[key]?.built == built || inFlight.contains(key) { return }
        inFlight.insert(key)
        Task {
            defer { inFlight.remove(key) }
            do {
                let w = try await Self.fetch(book: book, t: t)
                models[key] = (built, PositionsModel(wire: w, name: name))
                errors[key] = nil
            } catch {
                if models[key] == nil { errors[key] = "Could not load \(t) just now. It tries again with the next update." }
            }
        }
    }

    /// The network on the main actor (it only waits there); the decode runs off it.
    private static func fetch(book: String, t: String) async throws -> PositionsWire {
        var data: Data
        #if DEBUG && targetEnvironment(simulator)
        // Screens checked without signing in: `-positionsDir <dir>` reads <dir>/<book>-<t>.json, saved replies.
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-positionsDir"), i + 1 < a.count {
            data = try Data(contentsOf: URL(fileURLWithPath: a[i + 1]).appendingPathComponent("\(book)-\(t).json"))
            return try await decode(data)
        }
        #endif
        var r = URLRequest(url: URL(string: Secrets.supabaseURL + "/functions/v1/sunny-positions")!, timeoutInterval: 30)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        let token = try await SupabaseService.client.auth.session.accessToken
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // `wide` (Nov 8): prices out to ±50% as well, so the payoff's "Makes the most" reaches past ±12%.
        r.httpBody = try JSONSerialization.data(withJSONObject: ["book": book, "t": t, "wide": true] as [String: Any])
        let (d, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        data = d
        return try await decode(data)
    }

    nonisolated private static func decode(_ data: Data) async throws -> PositionsWire {
        try await Task.detached(priority: .userInitiated) { try JSONDecoder().decode(PositionsWire.self, from: data) }.value
    }
}
