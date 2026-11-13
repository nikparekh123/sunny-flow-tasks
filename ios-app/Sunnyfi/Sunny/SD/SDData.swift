//
//  SDData.swift
//  Sunny
//
//  What sunny-sd sends for one name (the SD calculator's server, sd-engine.ts calc(), since 11 Nov 2026), as the
//  Positions tab reads it for Intelligence (handoff 2026-11-13-positions, App Explorations 154a): the price, the rule's
//  range, the default counts, the book's sold legs (with the SD each sat at when sold), up to six expiries (each with
//  its 1 SD, the rule's call and put, the chain's IV by strike and the gamma walls), and the name's technicals, today's
//  session, its recent closes and its next earnings and ex-dividend dates.
//
//  The fields added on 13 Nov 2026 (tech, day, closes, events, exps[].ivK / ivKsrc / gamma, sold[].z0 / fill) are
//  optional: an older reply decodes, and a lane whose data is absent shows one quiet line, never a stand-in.
//
//  SDStore keeps one reply per book and name for about a minute.
//

import Foundation
import Observation
import Supabase

/// What sunny-sd sends (v 1).
nonisolated struct SDReply: Decodable, Sendable {
    nonisolated struct Cfg: Decodable, Sendable { let cLo: Double; let cHi: Double; let pLo: Double; let pHi: Double }
    nonisolated struct Counts: Decodable, Sendable { let calls: Int; let puts: Int }
    /// A sold leg in the book: be is the breakeven at the price it was sold for (nil when unknown); got what was got a
    /// share and iv its own IV; z0 the signed SD the strike sat at when sold and fill what it was sold on (13 Nov 2026:
    /// the fill's underlying, IV and trading days; `approx` when backfilled from that day's stored marks).
    nonisolated struct Sold: Decodable, Sendable, Hashable {
        nonisolated struct Fill: Decodable, Sendable, Hashable { let S: Double?; let iv: Double?; let td: Double?; let approx: Bool?; let d: String? }
        let put: Bool; let K: Double; let n: Double; let ex: String; let be: Double?
        var got: Double? = nil
        var iv: Double? = nil
        var z0: Double? = nil
        var fill: Fill? = nil
    }
    /// How many calls are covered (README 1.4): the shares, and the OTM calls bought with their expiries.
    nonisolated struct Cover: Decodable, Sendable {
        nonisolated struct Otm: Decodable, Sendable { let ex: String; let n: Double }
        let shares: Double; let otm: [Otm]
    }
    /// One strike: k SD out, the listed strike, ln(K / S), its real distance in SD, the premium a share, breakeven,
    /// the chance it ends in the money, no usable quote (≈), a thin market (!), the 5-year won rate.
    nonisolated struct Row: Decodable, Sendable, Hashable {
        let k: Double; let K: Double; let pct: Double; let kA: Double?; let pr: Double; let be: Double; let itm: Double
        let est: Bool; let liq: Bool; let won: Double?
    }
    /// The rule's pick: the SD per side, and its rows (carrying the strike it moved to).
    nonisolated struct Sug: Decodable, Sendable {
        let kc: Double; let kp: Double
        let call: Row; let put: Row
        enum CodingKeys: String, CodingKey { case kc, kp, call = "C", put = "P" }
    }
    /// A signal card of the rule (Why): only its key and value are read here (the IV verdict, "Rich" / "Cheap").
    nonisolated struct Sig: Decodable, Sendable { let key: String; let v: String }
    /// The gamma walls at this expiry (gamma_view_day, else gex_walls): each wall's strike, kind, gamma and how sure
    /// (1 to 3, nil from the open-interest walls), the flip.
    nonisolated struct Gamma: Decodable, Sendable {
        nonisolated struct Wall: Decodable, Sendable { let K: Double; let kind: String; let gex: Double; let conf: Int? }
        let day: String?; let flip: Double?; let regime: String?; let src: String?; let walls: [Wall]
    }
    nonisolated struct Exp: Decodable, Sendable {
        let ex: String; let label: String; let long: String?; let td: Double?; let cd: Double; let T: Double?; let iv: Double; let m: Double
        let earn: Bool?; let band: [Double]?; let sug: Sug; let sig: [Sig]?
        /// The chain's mid IV per strike ([K, iv]) and where it came from (option_chain_next, else this reply's chain).
        var ivK: [[Double]]? = nil
        var ivKsrc: String? = nil
        var gamma: Gamma? = nil
    }
    /// The name's technicals (ticker-technicals): the averages, RSI, HV20, the IV's rank and its year's range, and the
    /// support and resistance zones (swing pivots, a band of half an ATR, strength = how often the price turned there).
    nonisolated struct Tech: Decodable, Sendable {
        nonisolated struct Zone: Decodable, Sendable, Hashable { let kind: String; let lo: Double; let hi: Double; let mid: Double; let strength: Double }
        let sma20: Double?; let sma50: Double?; let sma100: Double?; let sma200: Double?; let rsi14: Double?; let hv20: Double?
        let ivRank: Double?; let ivLow52: Double?; let ivHigh52: Double?
        let zones: [Zone]?
    }
    /// Today's session: the prior close, the high and low so far, the last price; after 4:00 PM ET closedToday and the
    /// close (closeStored once the 4:30 PM daily close is in).
    nonisolated struct Day: Decodable, Sendable { let d: String?; let prev: Double; let high: Double; let low: Double; let last: Double; let closedToday: Bool; let close: Double?; let closeStored: Bool? }
    nonisolated struct Close: Decodable, Sendable { let d: String; let c: Double }
    /// The next earnings (and whether its date is an estimate), the next declared ex-dividend date and amount, and
    /// the estimated one when none is declared.
    nonisolated struct Events: Decodable, Sendable {
        let earnings: String?; let earnTime: String?; let earnEst: Bool?; let exDiv: String?; let divAmt: Double?; let exDivEst: String?
    }

    let ok: Bool?
    let t: String
    let name: String?
    let strategy: String?
    /// Today's price (the reply's S).
    let price: Double
    let prev: Double?
    let today: String?
    let cfg: Cfg
    let counts: Counts
    let sold: [Sold]
    let exps: [Exp]
    let cover: Cover?
    let tech: Tech?
    let day: Day?
    let closes: [Close]?
    let events: Events?
    enum CodingKeys: String, CodingKey { case ok, t, name, strategy, price = "S", prev, today, cfg, counts, sold, exps, cover, tech, day, closes, events }
}

enum SDClient {
    static func fetch(t: String, book: String) async throws -> SDReply {
        #if DEBUG && targetEnvironment(simulator)
        // Screens checked without signing in: `-sdDir <dir>` reads <dir>/<book>-<t>.json, saved replies.
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-sdDir"), i + 1 < a.count {
            let data = try Data(contentsOf: URL(fileURLWithPath: a[i + 1]).appendingPathComponent("\(book)-\(t).json"))
            return try await decode(data)
        }
        #endif
        var r = URLRequest(url: URL(string: Secrets.supabaseURL + "/functions/v1/sunny-sd")!, timeoutInterval: 30)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        let token = try await SupabaseService.client.auth.session.accessToken
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["t": t, "book": book])
        let (d, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try await decode(d)
    }

    nonisolated private static func decode(_ data: Data) async throws -> SDReply {
        try await Task.detached(priority: .userInitiated) { try JSONDecoder().decode(SDReply.self, from: data) }.value
    }
}

/// One sunny-sd reply per book and name, asked again after about a minute.
@MainActor @Observable
final class SDStore {
    static let shared = SDStore()

    private(set) var replies: [String: SDReply] = [:]
    private(set) var failed: Set<String> = []
    /// Bumped on each reply: the Positions tab's memo knows a fresh reply from the one it was worked out on.
    private(set) var version = 0
    @ObservationIgnored private var fetchedAt: [String: Date] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []

    static func key(_ book: String, _ t: String) -> String { "\(book)|\(t)" }
    func reply(_ book: String, _ t: String) -> SDReply? { replies[Self.key(book, t)] }
    func hasFailed(_ book: String, _ t: String) -> Bool { failed.contains(Self.key(book, t)) }

    /// Asks sunny-sd for a name unless a reply under a minute old is in (about a second on the server).
    func load(book: String, t: String, maxAge: TimeInterval = 60) {
        guard !t.isEmpty else { return }
        let key = Self.key(book, t)
        if let at = fetchedAt[key], Date().timeIntervalSince(at) < maxAge, replies[key] != nil { return }
        if inFlight.contains(key) { return }
        inFlight.insert(key)
        Task {
            defer { inFlight.remove(key) }
            do {
                let r = try await SDClient.fetch(t: t, book: book)
                replies[key] = r
                fetchedAt[key] = Date()
                failed.remove(key)
                version += 1
            } catch {
                if replies[key] == nil { failed.insert(key); version += 1 }
            }
        }
    }
}
