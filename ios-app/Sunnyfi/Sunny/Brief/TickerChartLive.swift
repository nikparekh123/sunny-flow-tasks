//
//  TickerChartLive.swift
//  Sunny
//
//  The ticker chart on real data (block 33, handoff 6 Nov 2026, Pass 2): sunny-chart sends five years of daily
//  closes from Yahoo, the price and the previous close, and the three layers (the book's legs in this name, the
//  nearest weekly's walls, the technical lines). The phone only draws it. Decoded off the main thread.
//

import Foundation
import Supabase

nonisolated struct TickerWire: Decodable, Sendable {
    nonisolated struct Line: Decodable, Sendable { let k: Double; let label: String; let solid: Bool? }
    nonisolated struct Tech: Decodable, Sendable { let sma20: Double?; let sma50: Double?; let hi52: Double?; let lo52: Double? }
    let t: String
    let name: String
    let price: Double
    let prev: Double
    let dates: [String]
    let closes: [Double]
    let positions: [Line]
    let walls: [Line]
    let tech: Tech

    /// The Technicals layer as lines: the 20- and 50-day averages, the year's high and low.
    var techLines: [(k: Double, label: String, solid: Bool)] {
        [(tech.sma20, "20-day"), (tech.sma50, "50-day"), (tech.hi52, "Year high"), (tech.lo52, "Year low")]
            .compactMap { v, l in v.map { ($0, l, false) } }
    }
    /// Closes since the first session of the latest year (YTD).
    var ytdCount: Int {
        guard let y = dates.last?.prefix(4) else { return closes.count }
        return dates.filter { $0.hasPrefix(y) }.count
    }
}

enum TickerChartClient {
    static func fetch(t: String, book: String?) async throws -> TickerWire {
        #if DEBUG && targetEnvironment(simulator)
        // Screens checked without signing in: `-chartDir <dir>` reads <dir>/<book>-<t>.json, saved replies.
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-chartDir"), i + 1 < a.count {
            let data = try Data(contentsOf: URL(fileURLWithPath: a[i + 1]).appendingPathComponent("\(book ?? "S")-\(t).json"))
            return try await decode(data)
        }
        #endif
        var r = URLRequest(url: URL(string: Secrets.supabaseURL + "/functions/v1/sunny-chart")!, timeoutInterval: 30)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        let token = try await SupabaseService.client.auth.session.accessToken
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["t": t]
        if let book { body["book"] = book }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (d, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try await decode(d)
    }

    nonisolated private static func decode(_ data: Data) async throws -> TickerWire {
        try await Task.detached(priority: .userInitiated) { try JSONDecoder().decode(TickerWire.self, from: data) }.value
    }
}
