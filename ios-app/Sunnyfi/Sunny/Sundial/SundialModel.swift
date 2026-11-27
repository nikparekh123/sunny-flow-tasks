//
//  SundialModel.swift
//  Sunny
//
//  The Sundial board's data (handoff 2026-11-27 README §4): one call to the `sundial` edge function per account and
//  name, {"mode":"board","account": a | b | ab, "name": all | a ticker}, with the signed-in user's token. The server
//  works out every number, total, sort order and state; the app only lays it out (README Step 0.3). The name chips
//  refetch, so the client never adds anything up.
//  Sundial 1.0 covers Nicolay's NVDA and SpaceX only (Nik, 27 Nov 2026): Sunny's account (a) comes back empty.
//

import SwiftUI
import Observation
import Supabase
import Auth

// MARK: - What the server sends

nonisolated struct SDBoard: Decodable, Equatable, Sendable {
    let asOf: String?
    let account: String?
    let book: String?
    let name: String?
    let day: String?
    let open: Bool?
    let final: Bool?
    let closeAt: String?
    let finalAt: String?
    let month: Month?
    let names: [Name]?
    let toSell: Sell?
    let drops: [Drop]?
    let close: Close?
    let working: Working?
    let expiring: Expiring?
    let banked: Banked?
    /// Every chip's view in the same reply (server 2026-11-27.4), so a chip switches without asking again.
    let views: [String: SDBoard]?

    struct Month: Decodable, Equatable, Sendable { let label: String?; let amount: Double? }
    struct Name: Decodable, Equatable, Sendable { let t: String; let name: String? }
    struct Keep: Decodable, Equatable, Sendable { let qty: Int; let total: Int }
    struct Leg: Decodable, Equatable, Sendable {
        let qty: Int; let expiry: String; let strike: Double; let type: String
        let sd: Double?; let price: Double?; let credit: Double?; let keep: Keep?
        /// When a Done leg was sold (today's IBKR trade).
        let at: String?
    }
    /// What a To sell card was worked out at (Nik, 27 Nov): before the final time the live price, every minute; after it the plan's lock.
    struct Basis: Decodable, Equatable, Sendable { let price: Double; let at: String; let locked: Bool }
    /// `legs` are still to sell (New); `done` were sold today on the plan's expiry (Nik 27 Nov: keep them on the card, marked Done).
    struct SellCard: Decodable, Equatable, Sendable { let t: String; let credit: Double; let reason: String?; let safe: String?; let basis: Basis?; let legs: [Leg]; let done: [Leg]?; let doneCredit: Double? }
    struct Sell: Decodable, Equatable, Sendable { let total: Double; let done: Double?; let cards: [SellCard] }
    struct Drop: Decodable, Equatable, Sendable { let t: String; let at: String?; let price: Double?; let line: String?; let credit: Double; let legs: [Leg] }
    struct CloseCard: Decodable, Equatable, Sendable {
        let t: String; let qty: Int; let expiry: String; let strike: Double; let type: String?
        let soldAt: Double; let now: Double; let keptPct: Int; let buyBack: Double
        let deadline: String?; let due: Bool?; let day: Int?; let of: Int?
    }
    struct Close: Decodable, Equatable, Sendable { let total: Double; let cards: [CloseCard] }
    struct WorkLeg: Decodable, Equatable, Sendable {
        let qty: Int; let strike: Double; let type: String; let expiry: String
        let daysLeft: Int?; let keptPct: Int; let sd: Double?; let itm: Bool?; let toGo: Double?
    }
    struct WorkGroup: Decodable, Equatable, Sendable { let t: String; let total: Double; let legs: [WorkLeg] }
    struct Working: Decodable, Equatable, Sendable { let total: Double; let groups: [WorkGroup] }
    struct Line: Decodable, Equatable, Sendable { let lo: Double; let hi: Double }
    struct ExpCard: Decodable, Equatable, Sendable {
        let t: String; let qty: Int; let strike: Double; let type: String; let expiry: String
        let price: Double; let distance: Double; let sd: Double?; let itm: Bool?
        let outcome: String?; let buyBack: Double?; let line: Line?
    }
    struct Expiring: Decodable, Equatable, Sendable { let total: Double; let cards: [ExpCard] }
    struct BankLeg: Decodable, Equatable, Sendable { let qty: Int; let strike: Double; let type: String; let expiry: String; let how: String; let kept: Double }
    struct BankGroup: Decodable, Equatable, Sendable { let t: String; let total: Double; let legs: [BankLeg] }
    struct Banked: Decodable, Equatable, Sendable { let total: Double; let groups: [BankGroup] }

    /// A ticker's name as the server writes it (names[].name; the ticker itself since 27 Nov, Nik).
    func label(_ t: String) -> String { names?.first { $0.t == t }?.name ?? t }
}

// MARK: - The store (one board per account and name, kept for the session)

@MainActor
@Observable
final class SundialStore {
    static let shared = SundialStore()
    private(set) var boards: [String: SDBoard] = [:]
    private(set) var failed: Set<String> = []

    static func key(_ acct: String, _ name: String) -> String { acct + "|" + name }
    func board(_ acct: String, _ name: String) -> SDBoard? { boards[Self.key(acct, name)] }

    func load(_ acct: String, _ name: String) async {
        let k = Self.key(acct, name)
        do {
            // One reply carries every chip's view (Nik 27 Nov: the page was slow): fill them all, so a chip switches at once.
            let b = try await Self.fetch(acct, "all")
            if let vs = b.views, !vs.isEmpty {
                for (n, v) in vs { let kk = Self.key(acct, n); if boards[kk] != v { boards[kk] = v } }
            } else {
                let kk = Self.key(acct, "all"); if boards[kk] != b { boards[kk] = b }
            }
            failed.remove(k)
        } catch {
            if !(error is CancellationError) { failed.insert(k) }
        }
    }

    private static func fetch(_ acct: String, _ name: String) async throws -> SDBoard {
        #if DEBUG && targetEnvironment(simulator)
        // Screens checked without signing in: `-sundialDir <dir>` reads <dir>/<acct>-<name>.json (or board-<acct>.json), saved replies.
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-sundialDir"), i + 1 < a.count {
            let dir = URL(fileURLWithPath: a[i + 1])
            let tries = ["\(acct)-\(name).json", "board-\(acct)-\(name).json", "board-\(acct).json"].map { dir.appendingPathComponent($0) }
            let url = tries.first { FileManager.default.fileExists(atPath: $0.path) } ?? tries[2]
            return try await decode(try Data(contentsOf: url))
        }
        #endif
        var r = URLRequest(url: URL(string: Secrets.supabaseURL + "/functions/v1/sundial")!, timeoutInterval: 30)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        let token = try await SupabaseService.client.auth.session.accessToken
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["mode": "board", "account": acct, "name": name])
        let (d, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try await decode(d)
    }

    nonisolated private static func decode(_ data: Data) async throws -> SDBoard {
        try await Task.detached(priority: .userInitiated) { try JSONDecoder().decode(SDBoard.self, from: data) }.value
    }
}

// MARK: - Words and figures (README §2.2: one way everywhere)

enum SDF {
    /// The board's account for the strip's: Sunny a, Nicolay b, Together ab.
    static func account(_ a: BriefAccount) -> String {
        switch a { case .sunny: "a"; case .nicolay: "b"; case .together: "ab" }
    }

    /// Whole K on totals: "$3K", "$970".
    static func kT(_ x: Double) -> String {
        let a = abs(x)
        return a >= 1000 ? "$\(Int((a / 1000).rounded()))K" : "$\(Int(a.rounded()))"
    }
    /// One decimal on card heroes: "$2.3K", "$13.1K", "$770".
    static func kC(_ x: Double) -> String {
        let a = abs(x)
        guard a >= 1000 else { return "$\(Int(a.rounded()))" }
        let s = String(format: "%.1f", a / 1000)
        return "$" + (s.hasSuffix(".0") ? String(s.dropLast(2)) : s) + "K"
    }
    /// A gain or loss with its sign (focus §2.2): "+$2.3K", "−$13.1K".
    static func signedT(_ x: Double) -> String { SF.signed(x.rounded() == 0 ? 0 : x, kT(x)) }
    static func signedC(_ x: Double) -> String { SF.signed(x.rounded() == 0 ? 0 : x, kC(x)) }

    /// A strike: "140", "162.50".
    static func strike(_ k: Double) -> String { k.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(k)) : String(format: "%.2f", k) }
    static func money2(_ x: Double) -> String { "$" + String(format: "%.2f", x) }
    /// SD with no trailing zeros: "0.75", "1", "1.3".
    static func sd(_ x: Double) -> String {
        var s = String(format: "%.2f", x)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
        return s
    }
    static func kind(_ n: Int, _ type: String) -> String {
        type == "put" ? (n == 1 ? "put" : "puts") : (n == 1 ? "call" : "calls")
    }
    /// Line 1 of a contract: "10 $162.50 calls".
    static func contract(_ n: Int, _ k: Double, _ type: String) -> String { "\(n) $\(strike(k)) \(kind(n, type))" }

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    /// "2026-12-02" → "Dec 2".
    static func md(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m) else { return iso }
        return "\(months[m - 1]) \(d)"
    }
    /// "15:45" → "3:45 PM".
    static func t12(_ hm: String?) -> String {
        guard let hm, let (h, m) = hmParts(hm) else { return "" }
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12):\(String(format: "%02d", m)) \(h >= 12 ? "PM" : "AM")"
    }
    static func hmParts(_ hm: String) -> (Int, Int)? {
        let p = hm.split(separator: ":")
        guard p.count >= 2, let h = Int(p[0]), let m = Int(p[1]) else { return nil }
        return (h, m)
    }
    /// Trading days left (Nik, 27 Nov 2026): "1 day", "3 days".
    static func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }
    /// "Updated 8:45 AM ($149.36)": when the card was last worked out and the stock price it used (Nik, 27 Nov: short).
    static func basis(_ b: SDBoard.Basis) -> String {
        "Updated \(parse(b.at).map { time($0) } ?? "") (\(money2(b.price)))"
    }

    // New York's clock

    static let ny = TimeZone(identifier: "America/New_York")!
    private static let whoFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = ny
        f.dateFormat = "EEE MMM d · h:mm a"
        return f
    }()
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = ny
        f.dateFormat = "h:mm a"
        return f
    }()
    static func whoLine(_ d: Date) -> String { whoFmt.string(from: d) }
    static func time(_ d: Date) -> String { timeFmt.string(from: d) }
    static func parse(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }
    /// Today's New York date at "16:00".
    static func todayAt(_ hm: String?, _ now: Date = .now) -> Date? {
        guard let hm, let (h, m) = hmParts(hm) else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = ny
        var c = cal.dateComponents([.year, .month, .day], from: now)
        c.hour = h; c.minute = m; c.second = 0
        return cal.date(from: c)
    }
    /// Minutes past midnight in New York.
    static func nyMinutes(_ d: Date = .now) -> Int {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = ny
        let c = cal.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

// MARK: - The board's colours (SunnyIncomeBoard T, dark and light)

enum SDC {
    static let ink = S.ink
    static let ink2 = S.dyn(0x212121, 0xAAAAAA)
    static let dim = S.dyn(0x6E6E6E, 0xAAAAAA)
    static let mu = S.secondary
    static let red = S.red
    static let green = S.green
    static let orange = S.dyn(0xD08A2C, 0xE8A33D)
    static let fill = Color(hex: 0x8C8C8C)
    static let box = S.dyn(0xFAFAFA, 0x212121)
    static let trk = S.dynA(0x212121, 0.10, 0xFAFAFA, 0.14)
    static let l8 = S.dynA(0x212121, 0.08, 0xFAFAFA, 0.08)
    static let l12 = S.dynA(0x212121, 0.12, 0xFAFAFA, 0.12)
    static let dash = S.dynA(0x212121, 0.28, 0xFAFAFA, 0.24)
    static let ring = S.dynA(0x212121, 0.08, 0xFAFAFA, 0.08)
    /// To sell: the brightest card (dark #313131 with a 14% ring, light white with a soft shadow); the plan dimmer.
    static let sell = S.dyn(0xFFFFFF, 0x313131)
    static let sellRing = S.dynA(0x212121, 0.06, 0xFAFAFA, 0.14)
    static let plan = S.dyn(0xF7F7F7, 0x232323)
    static let planDash = S.dynA(0x212121, 0.30, 0xFAFAFA, 0.26)
    static let dropRing = S.dynA(0x212121, 1, 0xFAFAFA, 0.42)
    static let chipOff = S.dynA(0x212121, 0.20, 0xFAFAFA, 0.20)
    /// A stack's edges under its top card.
    static let e1 = S.dyn(0xF4F4F4, 0x1D1D1D)
    static let e2 = S.dyn(0xEEEEEE, 0x1A1A1A)
}
