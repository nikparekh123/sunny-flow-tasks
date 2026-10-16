//
//  PlannerPackage.swift
//  Sunny
//
//  Handoff 25 (16 Oct 2026), block 14b · one name's package, ready to draw.
//  sunny-home builds it (writes.names[].pkg): what is held, next week's plan
//  by OUR sell rule, the design's upside buys and the pick-one fix, every leg
//  in share-equivalent delta (contracts × 100 × delta; long adds, short takes
//  away, a put's delta is negative). The app only redoes AFTER as chips
//  switch off. NOW is the Delta tile's number for the same name.
//

import SwiftUI

struct PlanPkg {
    enum Ty: String, CaseIterable { case lc, sc, lp, sp, oc }

    struct Leg: Identifiable, Hashable {
        let id: String
        let ty: Ty
        let n: Int
        let k: Double
        let exp: String
        /// Signed delta, in shares.
        let d: Double
        /// A suggestion (outlined on the chart), not a leg held now.
        let sugg: Bool
        var act: String? = nil
        var tenor: String? = nil
        var roll: String? = nil
        var mid: Double? = nil
        var stays = true
        var call: Bool { ty == .lc || ty == .sc || ty == .oc }
        var short: Bool { ty == .sc || ty == .sp }
        var tenorWord: String? { tenor == "12m" ? "12-month" : tenor == "3m" ? "3-month" : nil }
    }

    let t: String
    let px: Double
    /// 10 the week the name reports, else 0: every band edge moves up by it.
    let e: Double
    /// LEAP shares: the denominator of every %.
    let base: Double
    let now: Double
    let held: [Leg]
    let sug: [Leg]
    let fix: [Leg]
    let plannedFor: String
    let nextEarnings: String?
    let iv: Double?

    init?(_ w: Writes.Name, px: Double) {
        guard let p = w.pkg, p.base > 0 else { return nil }
        t = w.ticker; self.px = px; e = p.e; base = p.base; now = p.now
        plannedFor = w.expiry
        nextEarnings = w.nextEarnings?.date
        iv = p.iv
        held = p.held.enumerated().map { i, h in
            Leg(id: "h\(i)-\(h.ty)-\(h.k)-\(h.exp)", ty: Ty(rawValue: h.ty) ?? .lc, n: h.n, k: h.k, exp: h.exp, d: h.d,
                sugg: false, tenor: h.tenor, roll: h.roll, stays: h.stays)
        }
        let leg = { (s: Writes.Name.Pkg.Sug) in
            Leg(id: s.id, ty: Ty(rawValue: s.ty) ?? .sc, n: s.n, k: s.k, exp: s.exp, d: s.d, sugg: true,
                act: s.act, tenor: s.tenor, mid: s.mid)
        }
        sug = p.sug.map(leg)
        fix = p.fix.map(leg)
    }

    /// What is on next week: the suggestions left on, plus the fix picked
    /// (3-month by default; "none" once dropped).
    func live(off: Set<String>, pick: String?) -> [Leg] {
        let f = pick ?? "f3"
        return sug.filter { !off.contains($0.id) } + fix.filter { $0.id == f }
    }
    /// Everything still on at the plan's Friday plus `live`.
    func after(_ live: [Leg]) -> Double { held.filter(\.stays).reduce(0) { $0 + $1.d } + live.reduce(0) { $0 + $1.d } }
    func pct(_ d: Double) -> Double { base > 0 ? d / base * 100 : 0 }
    var nowPct: Double { pct(now) }
    var alert: DeltaAlert? { DeltaAlert(pct: nowPct, earningsWeek: e > 0) }

    enum Band: String {
        case netShort = "Net short", tooThin = "Too thin", gettingThin = "Getting thin"
        case onTarget = "On target", roomToSell = "Room to sell"
        var tone: Color {
            switch self {
            case .netShort: S.red
            case .onTarget: S.green
            case .roomToSell: S.ink
            case .tooThin, .gettingThin: S.orangeDeep
            }
        }
        /// The glass card's corner tint, by the band after the plan.
        var tint: Color {
            switch self {
            case .netShort: S.breatheRed
            case .onTarget: Color(red: 101 / 255, green: 196 / 255, blue: 102 / 255)
            case .roomToSell: Color(red: 142 / 255, green: 142 / 255, blue: 150 / 255)
            case .tooThin, .gettingThin: S.breatheOrange
            }
        }
    }
    func band(_ p: Double) -> Band {
        p < 0 ? .netShort : p < 15 + e ? .tooThin : p < 20 + e ? .gettingThin : p <= 30 + e ? .onTarget : .roomToSell
    }
}

/// The Planner's number formats (block 14b, Numbers): never a minus sign.
enum PP {
    /// 4.5K · 771: whole below 1,000, one decimal in K above.
    static func d(_ v: Double) -> String {
        let x = abs(v.rounded())
        return x >= 1000 ? trim1(x / 1000) + "K" : String(Int(x))
    }
    static func usd(_ v: Double) -> String {
        let x = abs(v)
        return "$" + (x >= 1000 ? trim1(x / 1000) + "K" : String(Int(x.rounded())))
    }
    private static func trim1(_ x: Double) -> String {
        let s = String(format: "%.1f", x)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
    /// A strike: 37.5 · 30 · 112.5.
    static func k(_ v: Double) -> String { F.trim((v * 100).rounded() / 100) }
    /// One decimal under 10%.
    static func pct(_ x: Double) -> String { (x >= 10 ? String(Int(x.rounded())) : String(format: "%.1f", x)) + "%" }
    /// Strike against the price; ATM shows its distance too.
    static func dist(_ k: Double, _ px: Double) -> String {
        let x = px > 0 ? abs(k - px) / px * 100 : 0
        return (x < 1 ? "ATM " : "") + pct(x)
    }
    /// Oct 23 · Jan 21 '28 (the year once the date is more than six months out).
    static func date(_ iso: String, today: String) -> String {
        let far = (Date.parse(iso) ?? 0) - (Date.parse(today) ?? 0) > 183 * 86_400
        return F.day(iso) + (far ? " '" + iso.dropFirst(2).prefix(2) : "")
    }
}

private extension Date {
    static func parse(_ iso: String) -> TimeInterval? {
        let p = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        var c = DateComponents(); c.year = p[0]; c.month = p[1]; c.day = p[2]; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)?.timeIntervalSince1970
    }
}
