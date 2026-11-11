//
//  SDData.swift
//  Sunny
//
//  The SD calculator's data (handoff 11 Nov 2026, README 1, Explorations 137a): sunny-sd sends one name's price, the
//  rules' range, the default counts, the book's sold legs and up to six expiries, each with its 1 SD, its ±1 SD band,
//  the suggestion, every SD row (0 to 2.0 by 0.25) for calls and puts, and the signals that moved the suggestion.
//  The phone only picks: the expiry, the call and put SD (the suggestion until a tile is tapped), and works out the
//  pair (chance of profit, the total) exactly as the design's card136 does.
//
//  SDStore keeps one reply per book and name for about a minute, the sheet's state (closed, half, full), what is picked,
//  and the pins (remembered on the phone, per book and name): a pin keeps the band and the two strikes on the
//  Positions chart after the sheet closes, recalculated on each fresh reply.
//

import Foundation
import Observation
import Supabase

/// What sunny-sd sends (v 1).
nonisolated struct SDReply: Decodable, Sendable {
    nonisolated struct Cfg: Decodable, Sendable { let cLo: Double; let cHi: Double; let pLo: Double; let pHi: Double }
    nonisolated struct Counts: Decodable, Sendable { let calls: Int; let puts: Int }
    /// A sold leg in the book: be is the breakeven at the price it was sold for (nil when unknown).
    nonisolated struct Sold: Decodable, Sendable, Hashable { let put: Bool; let K: Double; let n: Double; let ex: String; let be: Double? }
    /// One strike: k SD out, the listed strike, ln(K / S), its real distance in SD, the premium a share, breakeven,
    /// the chance it ends in the money, no usable quote (≈), a thin market (!), the 5-year won rate.
    nonisolated struct Row: Decodable, Sendable, Hashable {
        let k: Double; let K: Double; let pct: Double; let kA: Double?; let pr: Double; let be: Double; let itm: Double
        let est: Bool; let liq: Bool; let won: Double?
    }
    /// The suggestion: the SD per side, and its rows (carrying the strike support or resistance moved it to).
    nonisolated struct Sug: Decodable, Sendable {
        let kc: Double; let kp: Double; let mvC: Bool?; let mvP: Bool?; let capC: Bool?; let capP: Bool?
        let call: Row; let put: Row
        enum CodingKeys: String, CodingKey { case kc, kp, mvC, mvP, capC, capP, call = "C", put = "P" }
    }
    nonisolated struct Rows: Decodable, Sendable { let c: [Row]; let p: [Row] }
    /// A signal card: kicker, value and its tone, tag and its tone, the sub line, and what it did ([kind, text]).
    nonisolated struct Sig: Decodable, Sendable {
        let key: String; let k: String; let v: String; let vTone: String?; let tag: String?; let tagTone: String?; let s: String?; let fx: [[String]]?
    }
    nonisolated struct Hist: Decodable, Sendable { let n: Int?; let est: Bool? }
    /// What you hold (Nik 11 Nov): one expiry's sold calls and sold puts as a pair, at the sale prices. tot is the
    /// premium taken in, in dollars; up and dn the breakevens, sdUp and sdDn how far each is in SD; cop the chance.
    nonisolated struct Held: Decodable, Sendable, Equatable {
        nonisolated struct Side: Decodable, Sendable, Equatable { let K: Double; let n: Int }
        let ex: String; let label: String; let calls: [Side]; let puts: [Side]
        let tot: Double; let up: Double; let dn: Double; let sdUp: Double; let sdDn: Double; let cop: Double
    }
    nonisolated struct Exp: Decodable, Sendable {
        let ex: String; let label: String; let long: String?; let td: Double?; let cd: Double; let T: Double?; let iv: Double; let m: Double
        let earn: Bool?; let band: [Double]; let sug: Sug; let rows: Rows; let sig: [Sig]; let hist: Hist?
    }

    let t: String
    let name: String?
    let strategy: String?
    /// Today's price (the reply's S).
    let price: Double
    let prev: Double?
    /// Today's move, a signed fraction.
    let move: Double?
    let open: Bool?
    let today: String?
    let cfg: Cfg
    let counts: Counts
    let sold: [Sold]
    let exps: [Exp]
    /// Absent from replies before 11 Nov 2026 (sunny-sd v2).
    let held: [Held]?
    enum CodingKeys: String, CodingKey { case t, name, strategy, price = "S", prev, move, open, today, cfg, counts, sold, exps, held }
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

/// A pair of sold calls and sold puts on one expiry, any number of strikes (Nik 11 Nov): only one side can end in the
/// money, so all the premium cushions it. At an expiry price X it makes sum(n x premium) minus each call's
/// n x max(0, X - K) and each put's n x max(0, K - X); the breakevens are where that crosses zero either side of its
/// peak. The same sums as heldPair in _shared/sd-engine.ts. Nil when a side is empty or it never makes money.
struct SDPairNums: Equatable {
    struct Leg: Equatable { let K: Double; let n: Double; let at: Double }
    /// up is nil with no calls, dn with no puts: that side has no breakeven.
    let up: Double?, dn: Double?, tot: Double, sdUp: Double?, sdDn: Double?, cop: Double

    static func of(calls: [Leg], puts: [Leg], S: Double, m: Double) -> SDPairNums? {
        guard !(calls.isEmpty && puts.isEmpty), S > 0, m > 0 else { return nil }
        let all = calls + puts, T = all.reduce(0) { $0 + $1.n * $1.at }
        func pl(_ X: Double) -> Double {
            T - calls.reduce(0) { $0 + $1.n * max(0, X - $1.K) } - puts.reduce(0) { $0 + $1.n * max(0, $1.K - X) }
        }
        let top = all.map(\.K).reduce(all[0].K) { pl($1) > pl($0) ? $1 : $0 }
        guard pl(top) > 0 else { return nil }
        func root(_ lo0: Double, _ hi0: Double, up: Bool) -> Double {
            var lo = lo0, hi = hi0
            for _ in 0..<200 { let md = (lo + hi) / 2; if (pl(md) > 0) == up { lo = md } else { hi = md } }
            return (lo + hi) / 2
        }
        var up: Double? = nil, dn: Double? = nil
        if !calls.isEmpty { var hi = top * 2; while pl(hi) > 0 { hi *= 2 }; up = root(top, hi, up: true) }
        if !puts.isEmpty { guard pl(0) <= 0 else { return nil }; dn = root(0, top, up: false) }
        return SDPairNums(up: up, dn: dn, tot: T * 100, sdUp: up.map { log($0 / S) / m }, sdDn: dn.map { log(S / $0) / m },
                          cop: (up.map { SDFmt.N(log($0 / S) / m) } ?? 1) - (dn.map { SDFmt.N(log($0 / S) / m) } ?? 0))
    }
}

/// One expiry with the call and put picked, and the pair worked out as card136 does it.
struct SDPair {
    let exp: SDReply.Exp
    let ei: Int
    let kc: Double
    let kp: Double
    let call: SDReply.Row
    let put: SDReply.Row
    /// Both premiums a share, the upper and lower breakevens, the chance of profit.
    let tot: Double
    let up: Double
    let dn: Double
    let cop: Double
    /// How far each breakeven is from today, in SD by this expiry.
    let sdUp: Double
    let sdDn: Double

    /// The row for k SD: the suggestion's own row (the moved strike) when k is the suggestion, else rows[k × 4].
    static func row(_ e: SDReply.Exp, _ k: Double, put: Bool) -> SDReply.Row {
        if abs(k - (put ? e.sug.kp : e.sug.kc)) < 1e-6 { return put ? e.sug.put : e.sug.call }
        let rs = put ? e.rows.p : e.rows.c, i = Int((k * 4).rounded())
        return rs.indices.contains(i) ? rs[i] : (put ? e.sug.put : e.sug.call)
    }

    init?(_ r: SDReply, _ p: SDStore.Pick) {
        guard !r.exps.isEmpty else { return nil }
        let ei = p.ex.flatMap { x in r.exps.firstIndex { $0.ex == x } } ?? 0
        let e = r.exps[ei]
        self.exp = e; self.ei = ei
        kc = p.kc ?? e.sug.kc; kp = p.kp ?? e.sug.kp
        call = Self.row(e, kc, put: false); put = Self.row(e, kp, put: true)
        tot = call.pr + put.pr
        // Only one side can end in the money, so all the premium cushions it, spread over that side's real count
        // (Nik 11 Nov). With no calls or no puts it falls back to one of each.
        let nc = Double(r.counts.calls), np = Double(r.counts.puts), all = nc * call.pr + np * put.pr
        let real = nc > 0 && np > 0
        up = call.K + (real ? all / nc : tot); dn = put.K - (real ? all / np : tot)
        let S = r.price, m = e.m
        cop = m > 0 && dn > 0 && S > 0 ? SDFmt.N(log(up / S) / m) - SDFmt.N(log(dn / S) / m) : 0
        sdUp = m > 0 && S > 0 ? log(up / S) / m : 0
        sdDn = m > 0 && S > 0 && dn > 0 ? log(S / dn) / m : 0
    }
}

/// What the Positions chart draws while the sheet is open or pinned (README 1.9): the ±1 SD band, the two picked
/// strikes labelled with the expiry, every sold leg with its breakeven, and each held pair's two breakevens.
struct SDLines: Equatable {
    let lo: Double
    let hi: Double
    let callK: Double
    let putK: Double
    let ex: String
    let sold: [SDReply.Sold]
    /// What you hold: each pair's breakevens, "Nov 20 pair · BE 117.56" (Nik 11 Nov, option 3).
    var pair: [Pair] = []
    struct Pair: Equatable { let K: Double; let label: String }
}

@MainActor @Observable
final class SDStore {
    static let shared = SDStore()

    enum Level { case closed, half, full }
    enum Side { case calls, puts }
    /// What is picked: the expiry (nil = the first), the call and put SD (nil = the suggestion). A pin keeps the same.
    /// nc and np: how many calls and puts to sell now (Nik, 11 Nov 2026), nil = the rest of the counts after what is
    /// held on that expiry. A new expiry starts them over.
    struct Pick: Codable, Equatable { var ex: String? = nil; var kc: Double? = nil; var kp: Double? = nil; var nc: Int? = nil; var np: Int? = nil }

    private(set) var replies: [String: SDReply] = [:]
    private(set) var failed: Set<String> = []
    @ObservationIgnored private var fetchedAt: [String: Date] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []

    private(set) var level: Level = .closed
    private(set) var book = "S"
    private(set) var t = ""
    private(set) var pick = Pick()
    var side: Side = .calls
    private(set) var pins: [String: Pick] = [:]

    private static let pinsKey = "sd.pins"

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.pinsKey), let p = try? JSONDecoder().decode([String: Pick].self, from: d) { pins = p }
    }

    static func key(_ book: String, _ t: String) -> String { "\(book)|\(t)" }
    func reply(_ book: String, _ t: String) -> SDReply? { replies[Self.key(book, t)] }
    func hasFailed(_ book: String, _ t: String) -> Bool { failed.contains(Self.key(book, t)) }
    func isPinned(_ book: String, _ t: String) -> Bool { pins[Self.key(book, t)] != nil }
    var isOpen: Bool { level != .closed }
    /// The sheet is up on this name.
    func isOpen(on t: String) -> Bool { level != .closed && self.t == t }

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
                // A pinned expiry that has passed goes, and so does the sheet's.
                if let x = pins[key]?.ex, !r.exps.contains(where: { $0.ex == x }) { pins[key] = nil; savePins() }
                if self.book == book, self.t == t, let x = pick.ex, !r.exps.contains(where: { $0.ex == x }) { pick = Pick() }
            } catch {
                if replies[key] == nil { failed.insert(key) }
            }
        }
    }

    // MARK: The sheet

    /// The SD chip: the sheet rises to half on this name, picked as it was pinned (else the first expiry and the suggestion).
    func open(book: String, t: String) {
        self.book = book; self.t = t
        pick = pins[Self.key(book, t)] ?? Pick()
        side = .calls
        level = .half
        load(book: book, t: t)
    }
    /// The name on Positions changed while the sheet is up: it follows.
    func follow(book: String, t: String) {
        guard level != .closed, book != self.book || t != self.t else { return }
        open(book: book, t: t)
    }
    func close() { level = .closed }

    /// Try in What if (Nik, 11 Nov 2026): the picked call and put on the rest of the counts, sent to the Positions
    /// chart as a fix to preview. One per name; a new press replaces it.
    struct Trial: Equatable {
        struct Side: Equatable { let put: Bool; let K: Double; let n: Int; let pr: Double }
        let book: String; let t: String; let ex: String; let label: String; let days: Double; let iv: Double; let sides: [Side]
        var credit: Double { sides.reduce(0) { $0 + $1.pr * Double($1.n) * 100 } }
        var act: String {
            "Sell " + sides.map { "\($0.n) \(label) \(SDFmt.fk($0.K)) \($0.put ? ($0.n == 1 ? "put" : "puts") : ($0.n == 1 ? "call" : "calls"))" }.joined(separator: " and ")
        }
    }
    private(set) var trials: [String: Trial] = [:]
    func trial(book: String, t: String) -> Trial? { trials[Self.key(book, t)] }
    func tryIt(_ x: Trial) { trials[Self.key(x.book, x.t)] = x; level = .closed }
    /// The grabber: half to full, full to half.
    func grab() { level = level == .full ? .half : .full }
    func setLevel(_ l: Level) { level = l }

    func choose(ex: String) {
        guard ex != pick.ex else { return }
        pick = Pick(ex: ex)
        keepPin()
    }
    func choose(call k: Double) { pick.kc = k; keepPin() }
    func setCount(calls n: Int) { pick.nc = max(0, n); keepPin() }
    func setCount(puts n: Int) { pick.np = max(0, n); keepPin() }
    func choose(put k: Double) { pick.kp = k; keepPin() }

    /// The pin in the header: on keeps what is picked (its expiry fixed) on the chart; off lets it go.
    func togglePin() {
        let key = Self.key(book, t)
        if pins[key] != nil { pins[key] = nil }
        else {
            var p = pick
            if p.ex == nil { p.ex = replies[key]?.exps.first?.ex }
            pins[key] = p
        }
        savePins()
    }
    /// While pinned, what is picked is what stays on the chart.
    private func keepPin() {
        let key = Self.key(book, t)
        guard pins[key] != nil else { return }
        var p = pick
        if p.ex == nil { p.ex = replies[key]?.exps.first?.ex }
        pins[key] = p
        savePins()
    }
    private func savePins() {
        if let d = try? JSONEncoder().encode(pins) { UserDefaults.standard.set(d, forKey: Self.pinsKey) }
    }

    /// The chart's SD lines for this name: the sheet's pick while it is up on it, else the pin's; nil when neither.
    func lines(book: String, t: String) -> SDLines? {
        let open = isOpen(on: t) && self.book == book
        guard let p = open ? pick : pins[Self.key(book, t)], let r = reply(book, t), let pr = SDPair(r, p) else { return nil }
        let e = pr.exp
        return SDLines(lo: e.band.first ?? r.price, hi: e.band.count > 1 ? e.band[1] : r.price, callK: pr.call.K, putK: pr.put.K, ex: e.label, sold: r.sold,
                       pair: (r.held ?? []).flatMap { h in [h.dn, h.up].map { SDLines.Pair(K: $0, label: "\(h.label) pair · BE \(SDFmt.f2($0))") } })
    }

    /// The half sheet shows 600 pt (README 1.1). On a phone too short to keep the 190 pt chart above it, less.
    static func halfVisible(height: CGFloat, top: CGFloat) -> CGFloat { max(440, min(600, height - top - 193)) }

    // MARK: SD on your positions (139a)

    /// Each option leg's own IV, from its price (Home's `legs`, marked every minute; the same IV sunny-home's
    /// brief_inputs price the leg on), by name, side, sold or bought, strike and expiry. Set on each Home build.
    private(set) var ownIV: [String: Double] = [:]
    func setLegs(_ legs: [Leg]) {
        var m: [String: Double] = [:]
        for l in legs { if let iv = l.iv { m[Self.ivKey(l.ticker, put: l.type == "put", sold: l.side == "sold", K: l.strike, ex: l.expiry)] = iv } }
        if m != ownIV { ownIV = m }
    }
    static func ivKey(_ t: String, put: Bool, sold: Bool, K: Double, ex: String) -> String {
        "\(t)|\(put ? "P" : "C")|\(sold ? "S" : "B")|\(SDFmt.fk(K))|\(ex)"
    }
}
