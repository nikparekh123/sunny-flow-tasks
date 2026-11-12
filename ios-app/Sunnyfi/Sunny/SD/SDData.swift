//
//  SDData.swift
//  Sunny
//
//  The SD calculator's data (handoff 11 Nov 2026, README 1, Explorations 137a): sunny-sd sends one name's price, the
//  rules' range, the default counts, the book's sold legs and up to six expiries, each with its 1 SD, its ±1 SD band,
//  the suggestion, every SD row (0 to 2.0 by 0.25) for calls and puts, and the signals that moved the suggestion.
//  The phone only picks: the expiry, the call and put SD (the suggestion until a tile is tapped) and how many of each
//  to sell, and works out what the sale does (Held, + New, = Both: SDSale, the same engine as the web) for the pick.
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
    /// A sold leg in the book: be is the breakeven at the price it was sold for (nil when unknown); got what was got a
    /// share and iv its own IV (sunny-sd since 11 Nov 2026, for the sale: absent from older replies).
    nonisolated struct Sold: Decodable, Sendable, Hashable {
        let put: Bool; let K: Double; let n: Double; let ex: String; let be: Double?
        var got: Double? = nil
        var iv: Double? = nil
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
    /// The 5-year moves: how many, whether the IV was mostly estimated, and the moves as 401 quantiles (q, since 11 Nov
    /// 2026) for the sale's chance of profit.
    nonisolated struct Hist: Decodable, Sendable { let n: Int?; let est: Bool?; var q: [Double]? = nil }
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
    /// The cover, the rate and the dividend yield (sunny-sd since 11 Nov 2026; absent from older replies).
    let cover: Cover?
    let r: Double?
    let q: Double?
    enum CodingKeys: String, CodingKey { case t, name, strategy, price = "S", prev, move, open, today, cfg, counts, sold, exps, held, cover, r, q }
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

/// One expiry with the call and put picked: the suggestion until a tile is tapped.
struct SDPair {
    let exp: SDReply.Exp
    let ei: Int
    let kc: Double
    let kp: Double
    let call: SDReply.Row
    let put: SDReply.Row

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
    /// What is picked: the expiry (nil = the first), the call and put SD (nil = the suggestion), and how many calls and
    /// puts to sell (README 1.4, D3: they start at 0, never the suggested count; nil reads 0). A new expiry puts the
    /// strikes back to the suggestion and keeps the counts, as the design's; a new name starts over.
    struct Pick: Codable, Equatable {
        var ex: String? = nil; var kc: Double? = nil; var kp: Double? = nil; var nc: Int? = nil; var np: Int? = nil
        var calls: Int { max(0, nc ?? 0) }
        var puts: Int { max(0, np ?? 0) }
    }

    private(set) var replies: [String: SDReply] = [:]
    private(set) var failed: Set<String> = []
    @ObservationIgnored private var fetchedAt: [String: Date] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []
    /// Bumped on each reply, so the sale's memo knows a fresh reply from the one it was worked out on.
    @ObservationIgnored private var replyVer: [String: Int] = [:]

    private(set) var level: Level = .closed
    private(set) var book = "S"
    private(set) var t = ""
    private(set) var pick = Pick()
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
                replyVer[key, default: 0] += 1
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
        level = .half
        load(book: book, t: t)
    }
    /// The name on Positions changed while the sheet is up: it follows.
    func follow(book: String, t: String) {
        guard level != .closed, book != self.book || t != self.t else { return }
        open(book: book, t: t)
    }
    func close() { level = .closed }

    /// The grabber: half to full, full to half.
    func grab() { level = level == .full ? .half : .full }
    func setLevel(_ l: Level) { level = l }

    func choose(ex: String) {
        guard ex != pick.ex else { return }
        pick = Pick(ex: ex, nc: pick.nc, np: pick.np)
        keepPin()
    }
    func choose(call k: Double) { pick.kc = k; keepPin() }
    func setCount(calls n: Int) { pick.nc = max(0, min(999, n)); keepPin() }
    func setCount(puts n: Int) { pick.np = max(0, min(999, n)); keepPin() }
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

    // MARK: What the sale does (143a)

    /// The sheet's How many hints, the Held, + New and = Both lanes, the Calls and Puts cards and the footer for what is
    /// picked, worked out once per pick (and per reply) and kept: SDSale runs a few thousand payoffs, never in a body.
    @ObservationIgnored private var saleMemo: (key: String, model: SDSaleModel)?
    func sale(_ r: SDReply, _ p: SDPair, privacy: Bool) -> SDSaleModel {
        let k = Self.key(book, t)
        let key = "\(k)|\(replyVer[k] ?? 0)|\(p.exp.ex)|\(p.call.K)|\(p.put.K)|\(pick.calls)|\(pick.puts)|\(privacy)"
        if let m = saleMemo, m.key == key { return m.model }
        let m = SDSaleModel(r, p, nc: pick.calls, np: pick.puts, privacy: privacy)
        saleMemo = (key, m)
        return m
    }

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

// MARK: - What the sale does, ready to draw

/// One pick's How many hints, the Held, + New and = Both lanes, the Calls and Puts cards and the footer (README 1.4 and
/// 1.6 to 1.8; SunnySD.dc.html sale() and lanes() as the app draws them: labels above each bar, collisions to a second
/// row at 20% apart for strikes and 30% for breakevens (35% in Both), labels held 16 to 84% across). Positions across
/// are percentages of the bar's width; heights are points. Built by SDStore.sale, once per pick.
struct SDSaleModel {
    /// Colour roles, resolved by the view in light or dark: green / red are the bars' and the arrows' text tones (the
    /// design's gT / rT), not the bars.
    enum Tone { case ink, mu, muT, green, red, orange }
    struct Span { let t: String; let w: CGFloat; let tone: Tone }
    /// A strike above a Held or New bar: its pill (outlined and dashed when held, filled when new) and its stem.
    struct Pill: Identifiable { let id: String; let x: Double; let lx: Double; let y: CGFloat; let stemTop: CGFloat; let stemH: CGFloat; let label: String; let put: Bool; let new: Bool }
    /// A breakeven: its notch on the bar and its label. `held`: Held's breakeven drawn above Both's bar (dashed, muted,
    /// a HELD chip). `ch` is the change against Held in Both, `chK` its direction (1 further out, -1 closer).
    struct BE: Identifiable {
        let id: String; let x: Double; let lx: Double; let notchTop: CGFloat; let notchH: CGFloat; let held: Bool
        let y: CGFloat; let v: String; let vSize: CGFloat; let s: String; let ch: String?; let chK: Int
    }
    struct Zone: Identifiable { let id: Int; let a: Double; let b: Double; let pos: Bool }
    struct Lane: Identifiable {
        let id: String
        /// "Held", "New", "Both"; the sign before the chip ("", "+", "=").
        let name: String; let op: String
        /// The chance of profit (nil when the lane has nothing), the line after it, Both's change against Held.
        let cop: String?; let sub: String; let ch: String?; let chK: Int
        let zones: [Zone]; let diff: [Zone]; let pills: [Pill]; let bes: [BE]; let dot: Bool
        /// The bar's top and thickness and the bar area's height.
        let bt: CGFloat; let thk: CGFloat; let H: CGFloat
        let said: String
    }
    struct LegLine: Identifiable { let id: Int; let K: String; let pr: String; let mv: String }
    struct Col { let held: Bool; let legs: [LegLine]; let empty: String; let be: String?; let beS: String }
    struct Card: Identifiable {
        let id: String; let put: Bool; let title: String; let cols: [Col]
        let bV: String; let bS: String; let from: String?; let ch: String?; let chK: Int
        let said: String
    }

    let callHint: String
    let callHintOver: Bool
    let putHint: String
    let head: [Span]
    let title: String
    /// Held and New both have something: the legend's stripes, Both's change pill.
    let both: Bool
    let todayX: Double
    let todayT: String
    let lanes: [Lane]
    let cards: [Card]
    let gone: String?
    let foot: String

    init(_ r: SDReply, _ p: SDPair, nc: Int, np: Int, privacy: Bool) {
        let e = p.exp, S = r.price, m = e.m, exS = e.label, t = r.t
        let q401 = e.hist?.q ?? []
        // Without the 5-year moves (a reply from before 11 Nov 2026), the normal curve at today's IV.
        let cdf: (Double) -> Double = q401.isEmpty ? { SDSale.N($0) } : SDSale.cdfOf(q401)
        let bookMoney = { (x: Double) in BriefWords.plain(SDFmt.money(x), privacy: privacy) }
        let f2 = SDFmt.f2, fk = SDFmt.fk, pc = SDFmt.pc
        func cnt(_ a: Int, _ b: Int) -> String {
            [a > 0 ? SDFmt.count(a, "call") : nil, b > 0 ? SDFmt.count(b, "put") : nil].compactMap { $0 }.joined(separator: " and ")
        }
        func n(_ ls: [SDReply.Sold]) -> Int { Int(ls.reduce(0) { $0 + $1.n }.rounded()) }

        // Held = what is sold for this expiry or later, at what was got for it (1.9); a leg with no price on record
        // cannot be priced and is left out.
        let heldSold = r.sold.filter { $0.ex >= e.ex && $0.got != nil }
        let e0 = SDLegs.day(e.ex) ?? 0
        let held = heldSold.map { l in
            SDSale.Leg(put: l.put, K: l.K, n: l.n, got: l.got ?? 0, t: Double((SDLegs.day(l.ex) ?? e0) - e0) / 365, iv: l.iv ?? e.iv)
        }
        let scA = heldSold.filter { !$0.put }, spA = heldSold.filter { $0.put }, hC = n(scA), hP = n(spA)
        let rc = p.call, rp = p.put
        let K = SDSale.sale(S: S, m: m, r: r.r ?? 0.04, q: r.q ?? 0, cdf: cdf, held: held,
                            call: nc > 0 ? .init(K: rc.K, n: Double(nc), pr: rc.pr) : nil,
                            put: np > 0 ? .init(K: rp.K, n: Double(np), pr: rp.pr) : nil)
        let hasN = nc > 0 || np > 0, hasH = hC > 0 || hP > 0, both = hasN && hasH
        self.both = both
        let sdv = { (x: Double) in abs(log(x / S) / m) }
        let mvS = { (x: Double?) -> String in x.map { SDFmt.dir($0 / S - 1) + " · " + f2(sdv($0)) + " SD" } ?? "" }
        let xp = { (v: Double) in (v - K.A) / (K.B - K.A) * 100 }
        let sgd = { (v: Double, put: Bool) in (put ? -1 : 1) * log(v / S) / m }
        let premN = K.n.prem, premH = K.h.prem

        // How many (1.4): calls covered by the shares less what is already sold to that expiry, then by the OTM calls
        // bought that last to it; puts by what they would cost if assigned.
        if let cv = r.cover {
            let sh = Int((cv.shares / 100).rounded(.down))
            let sold = n(r.sold.filter { !$0.put && $0.ex >= e.ex })
            let otm = Int(cv.otm.filter { $0.ex >= e.ex }.reduce(0) { $0 + $1.n }.rounded())
            let byS = max(0, sh - sold), byO = max(0, otm - max(0, sold - sh)), total = byS + byO
            func parts(_ a: Int, _ b: Int) -> String {
                [a > 0 ? "\(a) by shares" : nil, b > 0 ? "\(b) by OTM calls" : nil].compactMap { $0 }.joined(separator: ", ")
            }
            if nc == 0 { callHint = total > 0 ? "Up to \(total) covered: " + parts(byS, byO) : "Nothing left to cover"; callHintOver = false }
            else if nc <= byS { callHint = "Covered by your shares"; callHintOver = false }
            else if nc <= total { callHint = "Covered: " + parts(byS, nc - byS); callHintOver = false }
            else { callHint = "\(nc - total) not covered · you can cover \(total)"; callHintOver = true }
        } else { callHint = ""; callHintOver = false }
        putHint = np > 0 ? SDFmt.money(rp.K * 100 * Double(np)) + " if assigned at " + fk(rp.K) : SDFmt.money(rp.K * 100) + " a put if assigned"

        // Both against Held, per side (lanes() sideCh): in SD, further out is green, closer is red.
        let dP = K.b.cop - K.h.cop, same = abs(dP) < 0.0005, ptsT = SDLegs.fixed(abs(dP) * 100, 1) + " pts"
        struct Ch { let k: Int; let t: String; let sh: String?; let from: Double?; let vsHeld: Bool }
        func sideCh(_ put: Bool) -> Ch? {
            guard let bB = K.b.be(put: put) else { return nil }
            if !hasN { return Ch(k: 0, t: "Same as Held until you add calls or puts", sh: nil, from: nil, vsHeld: true) }
            if !hasH { return Ch(k: 0, t: "Same as New: nothing held for \(exS) or later", sh: nil, from: nil, vsHeld: false) }
            let bH = K.h.be(put: put), refT = bH != nil ? "Held" : "New alone"
            guard let ref = bH ?? K.n.be(put: put) else { return Ch(k: 0, t: "Same as New", sh: nil, from: nil, vsHeld: false) }
            let dd = sgd(bB, put) - sgd(ref, put)
            if abs(dd) < 0.005 { return Ch(k: 0, t: "Same as \(refT), \(f2(ref))", sh: nil, from: ref, vsHeld: bH != nil) }
            let sh = f2(abs(dd)) + (dd > 0 ? " SD further out" : " SD closer")
            return Ch(k: dd > 0 ? 1 : -1, t: sh + " than " + refT, sh: sh, from: ref, vsHeld: bH != nil)
        }
        let chC = sideCh(false), chP = sideCh(true)

        // The sentence (1.6).
        var hd: [Span] = []
        if both {
            hd.append(Span(t: SDFmt.money(premN) + " more in, chance of profit ", w: 600, tone: .ink))
            hd.append(Span(t: same ? "the same" : (dP >= 0 ? "up " : "down ") + ptsT, w: 600, tone: same ? .ink : dP >= 0 ? .green : .red))
            hd.append(Span(t: ". ", w: 600, tone: .ink))
            let parts = [(false, chC), (true, chP)].compactMap { put, q in q.flatMap { $0.k != 0 ? (put, $0) : nil } }
            if parts.isEmpty { hd.append(Span(t: "The breakevens stay where they are.", w: 400, tone: .muT)) }
            else {
                hd.append(Span(t: "Breakeven: ", w: 400, tone: .muT))
                for (i, x) in parts.enumerated() {
                    hd.append(Span(t: (x.0 ? "puts " : "calls ") + (x.1.vsHeld ? x.1.sh ?? x.1.t : x.1.t), w: 600, tone: x.1.k > 0 ? .green : .red))
                    hd.append(Span(t: i < parts.count - 1 ? ", " : ".", w: 400, tone: .muT))
                }
            }
        } else if hasN {
            // New only (Nik, 11 Nov 2026): Both is New.
            hd.append(Span(t: SDFmt.money(premN) + " in, " + pc(K.n.cop) + " chance of profit.", w: 600, tone: .ink))
        } else if hasH {
            hd.append(Span(t: "What you hold: " + pc(K.h.cop) + " chance of profit. ", w: 600, tone: .ink))
            hd.append(Span(t: "Add calls or puts above to see what they change.", w: 400, tone: .muT))
        } else {
            hd.append(Span(t: "Nothing sold for \(exS) or later. ", w: 600, tone: .ink))
            hd.append(Span(t: "Add calls or puts above.", w: 400, tone: .muT))
        }
        head = hd
        title = "Chance of profit and breakeven by \(exS)"
        todayX = xp(S)
        todayT = "$" + f2(S) + " today"

        // The lanes, as the app lays them out.
        let gP = 20.0, gB = 30.0, gB2 = 35.0
        let clamp = { (x: Double) in max(16, min(84, x)) }
        func lay(_ xs: [Double], _ gap: Double) -> [Int] {
            var rows: [[Double]] = []
            return xs.map { x in
                var r = rows.firstIndex { $0.allSatisfy { abs(x - $0) >= gap } }
                if r == nil { if rows.count < 2 { rows.append([]); r = rows.count - 1 } else { r = 1 } }
                rows[r!].append(x)
                return r!
            }
        }
        func posAt(_ L: SDSale.Lane, _ x: Double) -> Bool { L.segs.first { x >= $0.a && x <= $0.b }?.pos ?? false }
        var diff: [Zone] = []
        if both {
            let q = ([K.A] + K.h.cr + K.b.cr + [K.B]).sorted()
            for i in 1..<q.count where q[i] - q[i - 1] >= 1e-6 {
                let md = (q[i - 1] + q[i]) / 2
                if posAt(K.h, md) != posAt(K.b, md) { diff.append(Zone(id: diff.count, a: xp(q[i - 1]), b: xp(q[i]), pos: false)) }
            }
        }
        typealias PillIn = (key: String, K0: Double, label: String, put: Bool, new: Bool)
        let pillsH: [PillIn] = scA.enumerated().map { ("hc\($0.offset)", $0.element.K, fk($0.element.K) + " ×\(Int($0.element.n))", false, false) }
            + spA.enumerated().map { ("hp\($0.offset)", $0.element.K, fk($0.element.K) + " ×\(Int($0.element.n))", true, false) }
        let pillsN: [PillIn] = (nc > 0 ? [("nc", rc.K, fk(rc.K) + " ×\(nc)", false, true)] : []) + (np > 0 ? [("np", rp.K, fk(rp.K) + " ×\(np)", true, true)] : [])
        func beSaid(_ x: Double) -> String { "\(f2(x)), \(SDFmt.dir(x / S - 1)), \(f2(sdv(x))) SD" }
        var lanes: [Lane] = []
        for (li, k) in ["h", "n", "b"].enumerated() {
            let L = k == "h" ? K.h : k == "n" ? K.n : K.b, isB = k == "b"
            let on = k == "h" ? hasH : k == "n" ? hasN : hasH || hasN, thk: CGFloat = isB ? 14 : 10
            let pin = (on && !isB ? (k == "h" ? pillsH : pillsN) : []).filter { $0.K0 > K.A && $0.K0 < K.B }.sorted { xp($0.K0) < xp($1.K0) }
            let pr = lay(pin.map { xp($0.K0) }, gP), tR = pr.isEmpty ? 0 : pr.max()! + 1
            let gl = isB && both ? K.h.cr.sorted() : [], gr = lay(gl.map(xp), gP), gR = gr.isEmpty ? 0 : gr.max()! + 1
            let bt: CGFloat = tR > 0 ? CGFloat(tR) * 22 + 8 : gR > 0 ? CGFloat(gR) * 34 + 6 : 6
            let beTop = bt + thk + 8, rowH: CGFloat = isB ? 52 : 38
            let bl = on ? L.cr.sorted() : [], br = lay(bl.map(xp), isB ? gB2 : gB), bR = br.isEmpty ? 0 : br.max()! + 1
            let pills = pin.enumerated().map { i, q -> Pill in
                let y = CGFloat(tR - 1 - pr[i]) * 22, x = xp(q.K0)
                return Pill(id: q.key, x: x, lx: clamp(x), y: y, stemTop: y + 18, stemH: bt + thk - y - 18, label: q.label, put: q.put, new: q.new)
            }
            var bes: [BE] = gl.enumerated().map { i, x in
                BE(id: "g\(i)", x: xp(x), lx: clamp(xp(x)), notchTop: bt - 3, notchH: thk + 6, held: true, y: CGFloat(gR - 1 - gr[i]) * 34,
                   v: f2(x), vSize: 12, s: mvS(x), ch: nil, chK: 0)
            }
            bes += bl.enumerated().map { i, x in
                let q = x < S ? chP : chC, hc = isB && both && (q?.k ?? 0) != 0
                return BE(id: "b\(i)", x: xp(x), lx: clamp(xp(x)), notchTop: bt - 4, notchH: thk + 8, held: false, y: beTop + CGFloat(br[i]) * rowH,
                          v: f2(x), vSize: isB ? 15 : 13, s: mvS(x), ch: hc ? q?.sh : nil, chK: hc ? q?.k ?? 0 : 0)
            }
            let sub = k == "h" ? (hasH ? bookMoney(premH) + " got · " + cnt(hC, hP) : "Nothing held for \(exS) or later")
                : k == "n" ? (hasN ? SDFmt.money(premN) + " · " + cnt(nc, np) : "Add calls or puts above")
                : both ? bookMoney(premN + premH) + " in all" : hasN ? "Same as New" : hasH ? "Same as Held" : "Nothing yet"
            let ch: String? = isB && both ? (same ? "Same as Held" : (dP >= 0 ? "↑ " : "↓ ") + ptsT + " vs Held") : nil
            let name = isB ? "Both" : k == "h" ? "Held" : "New"
            var said = name + (on ? ", \(pc(L.cop)) chance of profit" : "") + ", " + sub
            if let ch { said += ", " + ch }
            if on && !bl.isEmpty { said += ". Breakeven " + bl.map(beSaid).joined(separator: "; ") }
            if isB && both && !gl.isEmpty { said += ". Held's breakeven " + gl.map(beSaid).joined(separator: "; ") }
            lanes.append(Lane(id: k, name: name, op: k == "n" ? "+" : isB ? "=" : "", cop: on ? pc(L.cop) : nil, sub: sub, ch: ch,
                              chK: same ? 0 : dP >= 0 ? 1 : -1,
                              zones: on ? L.segs.enumerated().map { Zone(id: $0.offset, a: xp($0.element.a), b: xp($0.element.b), pos: $0.element.pos) } : [],
                              diff: isB ? diff : [], pills: pills, bes: bes, dot: isB && on, bt: bt, thk: thk, H: on ? beTop + CGFloat(bR) * rowH : bt + thk + 6,
                              said: SDFmt.words(said)))
            _ = li
        }
        self.lanes = lanes

        // The Calls and Puts cards (1.7).
        func won(_ Kx: Double, put: Bool, row: SDReply.Row?) -> String {
            let w = row?.won ?? (q401.isEmpty ? nil : { let z = log(Kx / S) / m; return put ? 1 - cdf(z) : cdf(z) }())
            return w.map { " · " + pc($0) + "\u{00A0}won" } ?? ""
        }
        var cards: [Card] = []
        for put in [false, true] {
            let nq = put ? np : nc, rw = put ? rp : rc, hl = put ? spA : scA, side = put ? "puts" : "calls"
            if nq == 0 && hl.isEmpty { continue }
            let bH = K.h.be(put: put), bN = K.n.be(put: put), bB = K.b.be(put: put), q = put ? chP : chC
            let hCol = Col(held: true, legs: hl.enumerated().map { i, l in
                LegLine(id: i, K: fk(l.K) + " ×\(Int(l.n))",
                        pr: "Got $" + f2(l.got ?? 0) + " · " + bookMoney((l.got ?? 0) * l.n * 100) + (l.ex != e.ex ? " · " + PositionsModel.md(l.ex) : ""),
                        mv: SDFmt.dir(l.K / S - 1) + won(l.K, put: put, row: nil))
            }, empty: "No \(side) held for \(exS) or later", be: hl.isEmpty ? nil : bH.map(f2) ?? "Beyond 6 SD", beS: mvS(bH))
            let nCol = Col(held: false, legs: nq > 0 ? [LegLine(id: 0, K: fk(rw.K) + " ×\(nq)", pr: "$" + f2(rw.pr) + " · " + SDFmt.money(rw.pr * Double(nq) * 100),
                                                               mv: SDFmt.dir(rw.K / S - 1) + won(rw.K, put: put, row: rw))] : [],
                           empty: "No new \(side) yet", be: nq > 0 ? bN.map(f2) ?? "Beyond 6 SD" : nil, beS: mvS(bN))
            let bV = bB.map(f2) ?? "Beyond 6 SD"
            var said = "\(put ? "Puts" : "Calls"). Held: " + (hl.isEmpty ? hCol.empty : hCol.legs.map { "\($0.K), \($0.pr), \($0.mv)" }.joined(separator: "; ") + ", breakeven \(hCol.be ?? "")")
            said += ". New: " + (nq == 0 ? nCol.empty : nCol.legs.map { "\($0.K), \($0.pr), \($0.mv)" }.joined(separator: "; ") + ", breakeven \(nCol.be ?? "")")
            said += ". Both, breakeven \(bV), \(mvS(bB))" + (q.map { ". " + $0.t } ?? "")
            cards.append(Card(id: put ? "p" : "c", put: put, title: put ? "Puts" : "Calls", cols: [hCol, nCol], bV: bV, bS: mvS(bB),
                              from: (q?.k ?? 0) != 0 ? q?.from.map(f2) : nil, ch: q?.t, chK: q?.k ?? 0, said: SDFmt.words(said)))
        }
        self.cards = cards

        // The footer (1.8): sold legs that end before the expiry are left out.
        let gone = r.sold.filter { $0.ex < e.ex }
        if gone.isEmpty { self.gone = nil } else {
            let a = n(gone.filter { !$0.put }), b = n(gone.filter { $0.put })
            var dates: [String] = []
            for x in gone.map(\.ex).sorted() where !dates.contains(PositionsModel.md(x)) { dates.append(PositionsModel.md(x)) }
            self.gone = cnt(a, b) + (a + b == 1 ? " ends " : " end ") + dates.joined(separator: " and ") + ", before \(exS), so they are left out."
        }
        let td = Int((e.td ?? (e.T ?? e.cd / 365) * 252).rounded())
        let tail = " Held, New and Both count only what is sold, from what you got for it; legs that end before \(exS) are left out."
        foot = (q401.isEmpty ? "Chances from today’s IV, on the normal curve." : "Chances from 5 years of \(t) moves over the same \(SDFmt.count(td, "trading day")), scaled to today’s IV.") + tail
    }
}
