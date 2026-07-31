//
//  NvdaPlannerModels.swift
//  Sunnyfi — Ink rebuild · Planner
//
//  The Planner's data layer. The MATH lives server-side in the `nvda-planner`
//  edge function (a faithful port of the shipped planner-data.jsx model); the app
//  builds the request from its own NvDerive output, calls the function on every
//  interaction, and renders the returned state. The only client-side computation
//  is the calibration log (seeded deterministically, persisted to UserDefaults,
//  exactly as the mockup seeded it to localStorage) and its running stats.
//

import Foundation
import Supabase

// MARK: - Decoded edge state

struct PlannerState: Decodable, Sendable {
    let ok: Bool
    let asOf: String?
    let gate: PGate
    let book: PBook
    let settings: PlannerSettings
    let refStrike: Double
    let expiries: [PExpiry]
    let selExpiry: String
    let chain: [PRung]
    let signals: [PSignalSet]
    let recommendation: PRec
    let selStrike: Double
    let scenario: PScenario

    func signalsFor(_ strike: Double) -> [PSignal] {
        signals.first { abs($0.strike - strike) < 1e-6 }?.signals ?? []
    }
    var selRung: PRung? { chain.first { abs($0.strike - selStrike) < 1e-6 } }
    var wallRung: PRung? { let w = book.wall ?? .greatestFiniteMagnitude; return chain.first { $0.strike >= w } ?? chain.last }
}

struct PFlag: Decodable, Sendable, Identifiable {
    let key: String; let level: String; let head: String; let body: String
    var id: String { key }
}
struct PWash: Decodable, Sendable { let hit: Bool; let on: String; let amount: Double; let daysLeft: Int }

struct PGate: Decodable, Sendable {
    let spot, iv, ivPct, pctFactor: Double
    let hv20, hv30, hv60, hv90: Double
    let hvTrend: String
    let hvGap, score: Double
    let scorePass, earningsPass, capacityPass, blocked: Bool
    let daysToEarnings: Int
    let earnings: String
    let wash: PWash?
    let flags: [PFlag]
}

struct PBook: Decodable, Sendable {
    let shares, buyAvg, realizedPremium, netDelta, longTheta, shortCallDelta: Double
    let shortCallCt, longCallCt: Double
    let wall: Double?
    let committedShares, freeShares, capacity, basis: Double
}

struct PExpiry: Decodable, Sendable, Identifiable {
    let key, iso, label, dow: String
    let cal, td, we: Int
    let volDays, T, prem, perDay, credit, assign, edge: Double
    var id: String { iso }
}

struct PRung: Decodable, Sendable, Identifiable {
    let strike, prem, fair: Double
    let sellable: Bool
    let edge, edgePct, edgeHi, edgeLo, edgePctHi, edgePctLo: Double
    let edgeCrosses: Bool
    let assign, delta, netDeltaAfter, pctLong, effective, vsBasis: Double
    let side: String
    let advCost, affected: Double
    var id: Double { strike }
}

struct PSignal: Decodable, Sendable, Identifiable {
    let k: String; let ok: Bool; let label: String
    var id: String { k }
}
struct PSignalSet: Decodable, Sendable { let strike: Double; let signals: [PSignal] }

struct PRec: Decodable, Sendable {
    let none: Bool
    let strike: Double?
    let blocked: Bool
    let why: String
}

struct PIvSource: Decodable, Sendable { let label: String; let down, up: Double; let note: String }
struct PScenStep: Decodable, Sendable, Identifiable {
    let p, s, ivUsed, opt, shortPl, sharePl, combined: Double
    var id: Double { p }
}
struct PScenario: Decodable, Sendable {
    let conv, ivSource: String
    let source: PIvSource
    let T2: Double
    let steps: [PScenStep]
    let givenUp, topPct: Double
}

// MARK: - Settings (guardrails)

struct PlannerSettings: Codable, Sendable, Equatable {
    var minNetDelta: Double = 500
    var maxAssign: Double = 0.55
    var edgeFloor: Double = -0.40
    var weekendVol: Double = 0.3
    var edgeLookback: String = "hv30"

    static let `default` = PlannerSettings()

    static let order = ["minNetDelta", "maxAssign", "edgeFloor", "weekendVol", "edgeLookback"]
    static let labels: [String: String] = [
        "minNetDelta": "Min net delta after", "maxAssign": "Max assign %",
        "edgeFloor": "Edge floor · % of premium", "weekendVol": "Weekend vol coefficient",
        "edgeLookback": "Edge lookback",
    ]
    // Option sets, in display order (mirrors settingsOptions in planner-data.jsx).
    static let deltaOpts: [Double] = [0, 250, 500, 1000]
    static let assignOpts: [Double] = [0.35, 0.45, 0.55, 0.70]
    static let edgeOpts: [Double] = [-0.20, -0.40, -0.60, -9]
    static let weekendOpts: [Double] = [0, 0.3, 0.5, 1]
    static let lookbackOpts: [String] = ["hv20", "hv30", "hv60", "hv90"]

    static func fmtDelta(_ v: Double) -> String { v == 0 ? "0" : "+" + Int(v).formatted(.number.grouping(.automatic)) }
    static func fmtAssign(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
    static func fmtEdge(_ v: Double) -> String { v <= -1 ? "off" : "−\(Int((abs(v) * 100).rounded()))%" }
    static func fmtWeekend(_ v: Double) -> String { String(format: "%.1f d", v) }
    static func fmtLookback(_ v: String) -> String { v.uppercased() }

    func summaryFmt(_ key: String) -> String {
        switch key {
        case "minNetDelta": return Self.fmtDelta(minNetDelta)
        case "maxAssign": return Self.fmtAssign(maxAssign)
        case "edgeFloor": return Self.fmtEdge(edgeFloor)
        case "weekendVol": return Self.fmtWeekend(weekendVol)
        default: return Self.fmtLookback(edgeLookback)
        }
    }
}

// MARK: - Request

struct PlannerReq: Encodable, Sendable {
    struct Leg: Encodable, Sendable { let strike: Double; let ct: Double; var expiry: String? = nil }
    struct Book: Encodable, Sendable {
        let shares, buyAvg, realizedPremium, netDelta, longTheta, shortCallDelta, shortCallCt: Double
        let openShortCalls: [Leg]; let longCalls: [Leg]
    }
    struct Vol: Encodable, Sendable { let iv, ivPct, hv20, hv30, hv60, hv90: Double }
    struct Earn: Encodable, Sendable { let date, label: String }
    struct Wash: Encodable, Sendable { let hit: Bool; let on: String; let amount: Double; let daysLeft: Int }
    struct Scen: Encodable, Sendable { let conv, ivSource: String }

    let book: Book
    let vol: Vol
    let earnings: Earn
    var wash: Wash? = nil
    let settings: PlannerSettings
    var refStrike: Double? = nil
    var selExpiry: String? = nil
    var selStrike: Double? = nil
    let scenario: Scen
    let histAssign: Double
    let spot: Double
}

// MARK: - Calibration log (client-side, deterministic seed, UserDefaults-persisted)

struct PlannerCycle: Codable, Sendable, Identifiable {
    let id: String
    let ts: Double            // epoch ms (parity with the mockup)
    let expiry: String
    let strike: Double
    let ct: Double
    let mid: Double
    var fill: Double
    let pAssign: Double
    var assigned: Bool
    let impliedMove: Double
    let realizedMove: Double
    var settled: Bool
}

enum PlannerLog {
    static let key = "nvda-planner-log-v1"
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let minN = 20
    static let cadence = 126

    static func load() -> [PlannerCycle] {
        if let d = UserDefaults.standard.data(forKey: key),
           let rows = try? JSONDecoder().decode([PlannerCycle].self, from: d) { return rows }
        let seed = seedLog()
        save(seed)
        return seed
    }
    static func save(_ rows: [PlannerCycle]) {
        if let d = try? JSONEncoder().encode(rows) { UserDefaults.standard.set(d, forKey: key) }
    }

    // Deterministic LCG, identical constants to planner-data.jsx seedLog().
    private final class Rng { var s: UInt64; init(_ seed: UInt64) { s = seed }
        func next() -> Double { s = (s &* 1103515245 &+ 12345) & 0x7fffffff; return Double(s) / Double(0x7fffffff) } }

    static func seedLog(now: Date = Date()) -> [PlannerCycle] {
        let r = Rng(90210)
        var out: [PlannerCycle] = []
        let cal = Calendar(identifier: .gregorian)
        for i in stride(from: 23, through: 0, by: -1) {
            let d = cal.date(byAdding: .day, value: -(i * 2 + 1), to: now) ?? now
            let strike = 195 + Double(Int(r.next() * 12)) * 2.5
            let pAssign = min(0.72, max(0.04, r.next() * 0.6 + 0.06))
            let mid = (0.8 + r.next() * 4.2)
            let slip = -(0.02 + r.next() * 0.09)
            let impliedMove = (1.6 + r.next() * 2.4)
            let realizedMove = impliedMove * (0.45 + r.next() * 1.25)
            let comps = cal.dateComponents([.month], from: d)
            out.append(PlannerCycle(
                id: "s\(i)", ts: d.timeIntervalSince1970 * 1000,
                expiry: "\(months[(comps.month ?? 1) - 1]) \(cal.component(.day, from: d))",
                strike: strike, ct: Double(8 + Int(r.next() * 6)),
                mid: (mid * 100).rounded() / 100, fill: ((mid + slip) * 100).rounded() / 100,
                pAssign: (pAssign * 1000).rounded() / 1000,
                assigned: r.next() < pAssign,
                impliedMove: (impliedMove * 100).rounded() / 100,
                realizedMove: (realizedMove * 100).rounded() / 100,
                settled: true))
        }
        return out
    }
}

struct PlannerCalBucket: Identifiable, Sendable {
    let d: Int; let label: String; let n: Int; let ok: Bool; let pred, act: Double
    var id: Int { d }
}
struct PlannerCalStats: Sendable {
    let n: Int
    let avgSlip, avgCt, paid, recover, assignRate, annual, hitRate: Double
    let buckets: [PlannerCalBucket]
    var qualify: Int { buckets.filter { $0.ok }.count }
}

extension Array where Element == PlannerCycle {
    var calStats: PlannerCalStats {
        let done = filter { $0.settled }
        var buckets: [PlannerCalBucket] = []
        for d in 0..<10 {
            let inB = done.filter { Int(($0.pAssign * 10).rounded(.down)) == d }
            guard !inB.isEmpty else { continue }
            buckets.append(PlannerCalBucket(
                d: d, label: "\(d * 10)–\(d * 10 + 10)%", n: inB.count, ok: inB.count >= PlannerLog.minN,
                pred: inB.reduce(0) { $0 + $1.pAssign } / Double(inB.count),
                act: Double(inB.filter { $0.assigned }.count) / Double(inB.count)))
        }
        let slips = done.map { $0.fill - $0.mid }
        let avgSlip = slips.isEmpty ? 0 : slips.reduce(0, +) / Double(slips.count)
        let avgCt = done.isEmpty ? 0 : done.reduce(0) { $0 + $1.ct } / Double(done.count)
        let hits = done.filter { $0.realizedMove < $0.impliedMove }.count
        let paid = done.reduce(0.0) { $0 + ($1.mid - $1.fill) * 100 * $1.ct }
        let recover = done.reduce(0.0) { $0 + Swift.max(0, ($1.mid - $1.fill) - 0.02) * 100 * $1.ct }
        let assignRate = done.isEmpty ? 0 : Double(done.filter { $0.assigned }.count) / Double(done.count)
        return PlannerCalStats(
            n: done.count, avgSlip: avgSlip, avgCt: avgCt, paid: paid, recover: recover,
            assignRate: assignRate, annual: avgSlip * 100 * avgCt * Double(PlannerLog.cadence),
            hitRate: done.isEmpty ? 0 : Double(hits) / Double(done.count), buckets: buckets)
    }
}
/// Normal-approximation 95% half-width, matching the mockup's `ci(p, n)`.
func plannerCI(_ p: Double, _ n: Int) -> Double { n == 0 ? 0 : 1.96 * (p * (1 - p) / Double(n)).squareRoot() }

// MARK: - Store

@MainActor
@Observable
final class PlannerStore {
    var state: PlannerState?
    var isLoading = true
    var lastError: String?
    var log: [PlannerCycle] = PlannerLog.load()

    // Local UI selections (drive re-calls to the edge function).
    var settings = PlannerSettings.default
    var selExpiry: String? = nil
    var selStrike: Double? = nil
    var refStrike: Double? = nil
    var conv = "expiry"
    var ivSource = "nvda"
    var guardsOpen = false

    private var ctx: PlannerContext?
    private var gen = 0
    private let client = SupabaseService.client

    /// NVDA Q2 FY27 print — the calendar anchor for the earnings gate.
    static let earnings = (date: "2026-08-26", label: "Aug 26")

    struct PlannerContext: Sendable {
        let book: PlannerReq.Book
        let vol: PlannerReq.Vol
        let wash: PlannerReq.Wash?
        let spot: Double
    }

    /// Build the request context from the store's already-derived position, then run.
    func load(from store: NvdaStore) async {
        if ctx == nil { ctx = buildContext(from: store) }
        guard ctx != nil else { isLoading = false; lastError = "position not ready"; return }
        await run()
    }

    func apply() { Task { await run() } }

    private func run() async {
        guard let ctx else { return }
        gen += 1; let g = gen
        isLoading = true
        let req = PlannerReq(
            book: ctx.book, vol: ctx.vol,
            earnings: .init(date: Self.earnings.date, label: Self.earnings.label),
            wash: ctx.wash, settings: settings,
            refStrike: refStrike, selExpiry: selExpiry, selStrike: selStrike,
            scenario: .init(conv: conv, ivSource: ivSource),
            histAssign: log.calStats.assignRate, spot: ctx.spot)
        do {
            let data = try await client.functions.invoke("nvda-planner", options: FunctionInvokeOptions(body: req)) as Data
            let decoded = try JSONDecoder().decode(PlannerState.self, from: data)
            guard g == gen else { return }               // a newer request superseded this one
            if decoded.ok { state = decoded; lastError = nil } else { lastError = "planner unavailable" }
            isLoading = false
        } catch {
            guard g == gen else { return }
            lastError = String(describing: error)
            isLoading = false
        }
    }

    private func buildContext(from store: NvdaStore) -> PlannerContext? {
        guard let pos = store.position, let pnl = store.pnl, let ins = store.insights else { return nil }
        let strikes = pos.groups.flatMap { $0.strikes }
        let openShorts = strikes.filter { $0.side == "short" && $0.kind == "call" && !$0.expired }
        let openLongCalls = strikes.filter { $0.side == "long" && $0.kind == "call" && !$0.expired }
        let longLegs = strikes.filter { $0.side == "long" && !$0.expired }

        let shortCallDelta = openShorts.reduce(0.0) { $0 + $1.deltaEst }
        let longTheta = longLegs.reduce(0.0) { $0 + abs($1.theta ?? 0) * $1.ct * 100 }

        let book = PlannerReq.Book(
            shares: pos.shares, buyAvg: pos.avgBuy, realizedPremium: pnl.premiumRealized,
            netDelta: pos.delta, longTheta: longTheta, shortCallDelta: shortCallDelta,
            shortCallCt: openShorts.reduce(0) { $0 + $1.ct },
            openShortCalls: openShorts.map { .init(strike: $0.strike, ct: $0.ct) },
            longCalls: openLongCalls.map { .init(strike: $0.strike, ct: $0.ct, expiry: $0.expiry) })

        let vol = PlannerReq.Vol(
            iv: ins.vol.iv ?? 0, ivPct: ins.vol.ivr ?? 50,
            hv20: store.hv(20) ?? (ins.vol.hv30 ?? 0), hv30: ins.vol.hv30 ?? 0,
            hv60: store.hv(60) ?? (ins.vol.hv30 ?? 0), hv90: store.hv(90) ?? (ins.vol.hv30 ?? 0))

        return PlannerContext(book: book, vol: vol, wash: nil, spot: pos.spot)
    }

    // MARK: interactions (mutate a selection, then re-call)

    func pickExpiry(_ iso: String) { selExpiry = iso; selStrike = nil; apply() }
    func pickStrike(_ k: Double) { selStrike = k; apply() }
    func setRef(_ k: Double) { refStrike = k; apply() }
    func setConv(_ c: String) { conv = c; apply() }
    func toggleSource() { ivSource = ivSource == "nvda" ? "generic" : "nvda"; apply() }
    func setSetting(_ mutate: (inout PlannerSettings) -> Void) { mutate(&settings); apply() }
    func resetSettings() { settings = .default; apply() }
}
