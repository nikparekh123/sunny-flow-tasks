//
//  GammaModels.swift
//  Sunny
//
//  Handoff 32 · what the Gamma tab, To do and Δ Γ read. Two sources: the week's plan per name in the Home
//  payload (sunny-home: the sale, hedge calls, insurance puts, weekly puts, the budget, all from one hedge
//  function), and the Gamma views per name per session (gex-walls 'gamma', table gamma_view_day: the walls
//  from the tape with their labels). Watchlist names have open-interest walls only (gex_walls).
//

import Foundation
import Supabase

/// One wall from the tape (gamma.ts): its side and rank, dealer gamma (dollars per 1% move, long positive),
/// the label and confidence (1 to 3), and what the open-interest model said.
nonisolated struct GWall: Decodable, Hashable {
    let side: String
    let rank: Int
    let k: Double
    let gex: Double
    let oiGex: Double?
    let label: String
    let conf: Int
    let oiLabel: String?
    let explained: Double?
    let held: Int?
    let byExp: [String: Double]?
    var call: Bool { side == "call" }
}

/// One view of a name on one session.
nonisolated struct GammaView: Decodable, Hashable {
    let spot: Double
    let expiries: [String]
    let coverage: Double?
    let flip: Double?
    let regime: String?
    let net: Double?
    let priced: Priced?
    let walls: [GWall]
    let rolloff: Rolloff?
    let drift: Drift?
    let week: [WeekWall]?
    let prints: [String: Double]?
    let flow: Flow?
    /// How the labels have held (Weeklies view, written at the close): sessions so far and one row per label.
    let track: Track?
    nonisolated struct Track: Decodable, Hashable {
        let sessions: Int
        let rows: [Row]
        nonisolated struct Row: Decodable, Hashable { let kind: String; let label: String; let rate: Double; let base: Double; let touches: Int }
    }
    nonisolated struct Priced: Decodable, Hashable { let exp: String; let sd1: Double; let sd1Pct: Double; let sd15: Double }
    nonisolated struct Rolloff: Decodable, Hashable { let exp: String; let share: Double }
    nonisolated struct Drift: Decodable, Hashable { let from: Double; let to: Double; let pct: Double; let since: String? }
    nonisolated struct WeekWall: Decodable, Hashable { let side: String; let rank: Int; let k: Double; let gex: Double; let label: String; let exp: String? }
    nonisolated struct Flow: Decodable, Hashable { let sessions: Int; let under7: Double; let callPut: Double; let median: Double?; let small: Double? }
}

nonisolated struct GammaRow: Decodable, Hashable {
    let ticker: String
    let day: String
    let view: String
    let data: GammaView
}

/// The week's plan for one name (sunny-home `plan`).
struct NamePlan: Decodable, Hashable {
    let week: String
    let by: String
    let sd: Double?
    let earnings: Bool?
    let sell: Sell
    let hedge: Hedge?
    let insurance: Insurance?
    let puts: Puts
    let budget: Budget?
    let recheck: Recheck
    let regime: String?
    let flip: Double?
    let coverage: Double?
    let gday: String?
    /// The week's 1st and 2nd walls each side, for Δ Γ's axis and Watch this week.
    let walls: [PlanWall]?
    /// This week (13f): the premium on what the week's expiry sold, and a week of decay on everything bought.
    let wk: Wk?
    struct Wk: Decodable, Hashable { let prem: Double; let dec: Double }
    /// LEAPS under 0.70 delta: the roll down, same expiry, to about 0.75 (Nik, 26 Oct 2026, option B).
    let leaps: [LeapsRoll]?
    struct LeapsRoll: Decodable, Hashable {
        let exp: String; let n: Int; let from: From; let to: To; let debit: Double; let tv: TV; let spot: Double?
        struct From: Decodable, Hashable { let k: Double; let mark: Double; let delta: Double }
        struct To: Decodable, Hashable { let k: Double; let mid: Double; let delta: Double }
        struct TV: Decodable, Hashable { let old: Double; let new: Double }
    }
    struct PlanWall: Decodable, Hashable { let k: Double; let side: String; let label: String; let rank: Int }
    struct Sell: Decodable, Hashable {
        let n: Int; let sold: Int; let left: Int; let pick: String; let ways: [Way]; let wall: GWall?; let accel: Accel?
        /// Done for this week (sale_done): nothing more is sold this week, the hedge is sized on what is sold.
        let done: Bool?
    }
    struct Way: Decodable, Hashable, Identifiable {
        let id: String; let legs: [Leg]; let pct: Double; let premium: Double; let hedge: Int?
        struct Leg: Decodable, Hashable { let k: Double; let n: Int }
    }
    struct Accel: Decodable, Hashable { let k: Double; let conf: Int? }
    struct Hedge: Decodable, Hashable {
        let exp: String; let k: Double; let mid: Double; let delta: Double?; let label: String?; let conf: Int?; let oiOnly: Bool
        let held: Int; let add: Int; let covered: Bool; let target: Target; let low: Low?; let lowAfter: Double?
        let curve: [[Double]]?; let cost: Double; let weeks: Double?
        /// The calls needed with nothing more sold this week (shown the moment Done for this week is tapped).
        let addNow: Int?
        /// "sd" when the 1st wall (wallK) sat past twice the move, so the strike is the one nearest the target price.
        let pick: String?; let wallK: Double?
    }
    struct Target: Decodable, Hashable { let sd: Double; let px: Double?; let pct: Double? }
    struct Low: Decodable, Hashable { let px: Double; let d: Double }
    struct Insurance: Decodable, Hashable {
        let exp: String; let k: Double; let mid: Double; let delta: Double?; let label: String?; let conf: Int?; let oiOnly: Bool
        let ratio: Double; let target: Int; let held: Int; let add: Int; let cost: Double?; let weeks: Double?; let warn: Bool
        /// "sd" when the 1st put wall (wallK) sat past twice the 1.5 SD move down, so the strike is the one nearest it.
        let pick: String?; let wallK: Double?
    }
    struct Puts: Decodable, Hashable {
        let n: Int; let k: Double?; let mid: Double?; let half: Bool; let why: [String]; let cap: Int
        let wall: WallRef?; let s50: Double?
    }
    struct WallRef: Decodable, Hashable { let k: Double; let label: String; let conf: Int? }
    struct Budget: Decodable, Hashable { let pct: Double; let over: Bool; let perWeek: Double; let premium: Double }
    struct Recheck: Decodable, Hashable { let above: Double?; let below: Double? }
}

/// The Gamma rows for one name: the latest session's views, and the sessions before it for the week's history.
nonisolated struct GammaName: Hashable {
    let ticker: String
    let day: String
    let views: [String: GammaView]
    /// view -> [(day, view)], newest first, the latest session included.
    let history: [String: [(String, GammaView)]]
    static func == (a: GammaName, b: GammaName) -> Bool { a.ticker == b.ticker && a.day == b.day }
    func hash(into h: inout Hasher) { h.combine(ticker); h.combine(day) }
}

enum GammaData {
    /// Names already read, kept 5 minutes: swiping back to a name is instant (Nik, 26 Oct 2026: swipes jerked).
    private static var cache: [String: (at: Date, g: GammaName?)] = [:]
    static func cached(_ t: String) -> GammaName? { cache[t]?.g }

    /// The last two weeks of views for a name, grouped, decoded off the main thread. A DEBUG simulator run with
    /// `-gammaFixture <path>` reads a saved copy (the same JSON array, every name).
    @MainActor static func load(_ t: String, today: String) async throws -> GammaName? {
        if let c = cache[t], Date().timeIntervalSince(c.at) < 300 { return c.g }
        let data: Data
        #if DEBUG && targetEnvironment(simulator)
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-gammaFixture"), i + 1 < a.count {
            let url = URL(fileURLWithPath: a[i + 1])
            let g = try await Task.detached(priority: .userInitiated) { () throws -> GammaName? in
                group(t, try decoder().decode([GammaRow].self, from: Data(contentsOf: url)).filter { $0.ticker == t })
            }.value
            cache[t] = (Date(), g)
            return g
        }
        #endif
        let res = try await SupabaseService.client.from("gamma_view_day")
            .select("ticker,day,view,data")
            .eq("ticker", value: t).gte("day", value: WallsData.addDays(today, -16))
            .order("day", ascending: false).order("view", ascending: true)
            .execute()
        data = res.data
        let g = try await Task.detached(priority: .userInitiated) { () throws -> GammaName? in
            group(t, try decoder().decode([GammaRow].self, from: data))
        }.value
        cache[t] = (Date(), g)
        return g
    }
    nonisolated static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }
    nonisolated static func group(_ t: String, _ rows: [GammaRow]) -> GammaName? {
        guard let last = rows.map(\.day).max() else { return nil }
        var views: [String: GammaView] = [:], hist: [String: [(String, GammaView)]] = [:]
        for r in rows.sorted(by: { $0.day > $1.day }) {
            if r.day == last { views[r.view] = r.data }
            hist[r.view, default: []].append((r.day, r.data))
        }
        return GammaName(ticker: t, day: last, views: views, history: hist)
    }
}
