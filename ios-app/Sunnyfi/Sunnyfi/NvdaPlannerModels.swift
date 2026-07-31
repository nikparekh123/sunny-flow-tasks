//
//  NvdaPlannerModels.swift
//  Sunnyfi — Ink rebuild · Planner (rev 2)
//
//  The edge (`nvda-planner`) prices every candidate expiry's chain and supplies
//  the raw technicals for Upside Room. The APP owns the instant decision math —
//  Upside Room score + target, guardrails, target-moneyness selection, size
//  scaling, scenario — so taps update in place with no re-fetch. A re-call
//  happens only when a pricing input changes (weekend-vol).
//

import Foundation
import Supabase

// MARK: - Decoded edge state (priced chains + technicals + context)

struct PlannerState: Decodable, Sendable {
    let ok: Bool
    let asOf: String?
    let gate: PGate
    let book: PBook
    let technicals: PTech
    let refStrike: Double
    let weekendVol: Double
    let expiries: [PExpiry]
}

struct PFlag: Decodable, Sendable, Identifiable { let key, level, head, body: String; var id: String { key } }
struct PWash: Decodable, Sendable { let hit: Bool; let on: String; let amount: Double; let daysLeft: Int }

struct PGate: Decodable, Sendable {
    let spot, iv, ivPct, pctFactor, hv20, hv30, hv60, hv90: Double
    let hvTrend: String
    let hvGap, score: Double
    let scorePass, earningsPass, capacityPass, blocked: Bool
    let daysToEarnings: Int
    let earnings: String
    let wash: PWash?
    let flags: [PFlag]
}

struct PBook: Decodable, Sendable {
    let shares, buyAvg, realizedPremium, netDelta, longTheta, shortCallDelta, shortCallCt, longCallCt: Double
    let wall: Double?
    let committedShares, freeShares, capacity, basis: Double
}

struct PTech: Decodable, Sendable {
    let high52, low52, ma50, ma200, rsi14, ath: Double?
    let athDate, updatedAt: String?
}

struct PRung: Decodable, Sendable, Identifiable {
    let strike, prem, fair: Double
    let sellable: Bool
    let intrinsic, ext, extPct, edge, edgePct, edgeHi, edgeLo, edgePctHi, edgePctLo: Double
    let edgeCrosses: Bool
    let assign, delta, effective, vsBasis: Double
    let side: String
    let advCost, affected: Double
    var id: Double { strike }

    enum CodingKeys: String, CodingKey {
        case strike, prem, fair, sellable, intrinsic, ext, extPct, edge, edgePct, edgeHi, edgeLo, edgePctHi, edgePctLo, edgeCrosses, assign, delta, effective, vsBasis, side, advCost, affected
    }
    init(strike: Double, prem: Double, fair: Double, sellable: Bool, intrinsic: Double, ext: Double, extPct: Double,
         edge: Double, edgePct: Double, edgeHi: Double, edgeLo: Double, edgePctHi: Double, edgePctLo: Double,
         edgeCrosses: Bool, assign: Double, delta: Double, effective: Double, vsBasis: Double, side: String, advCost: Double, affected: Double) {
        self.strike = strike; self.prem = prem; self.fair = fair; self.sellable = sellable; self.intrinsic = intrinsic
        self.ext = ext; self.extPct = extPct; self.edge = edge; self.edgePct = edgePct; self.edgeHi = edgeHi; self.edgeLo = edgeLo
        self.edgePctHi = edgePctHi; self.edgePctLo = edgePctLo; self.edgeCrosses = edgeCrosses; self.assign = assign
        self.delta = delta; self.effective = effective; self.vsBasis = vsBasis; self.side = side; self.advCost = advCost; self.affected = affected
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Zero-premium strikes make the edge emit null (NaN) for the ratio fields;
        // default any missing/null Double to 0 so decoding never fails.
        func d(_ k: CodingKeys) -> Double { ((try? c.decodeIfPresent(Double.self, forKey: k)) ?? nil) ?? 0 }
        func b(_ k: CodingKeys) -> Bool { ((try? c.decodeIfPresent(Bool.self, forKey: k)) ?? nil) ?? false }
        strike = d(.strike); prem = d(.prem); fair = d(.fair); sellable = b(.sellable)
        intrinsic = d(.intrinsic); ext = d(.ext); extPct = d(.extPct); edge = d(.edge); edgePct = d(.edgePct)
        edgeHi = d(.edgeHi); edgeLo = d(.edgeLo); edgePctHi = d(.edgePctHi); edgePctLo = d(.edgePctLo)
        edgeCrosses = b(.edgeCrosses); assign = d(.assign); delta = d(.delta); effective = d(.effective); vsBasis = d(.vsBasis)
        side = (try? c.decode(String.self, forKey: .side)) ?? "favorable"
        advCost = d(.advCost); affected = d(.affected)
    }
}

struct PExpiry: Decodable, Sendable, Identifiable {
    let key, iso, label, dow: String
    let cal, td, we: Int
    let volDays, T: Double
    let chain: [PRung]
    var id: String { iso }
}

// MARK: - Settings (rev 2)

struct PlannerSettings: Codable, Sendable, Equatable {
    var minNetDelta: Double = 500
    var minExt: Double = 0.25
    var edgeFloor: Double = -0.40
    var weekendVol: Double = 0.3
    var edgeLookback: String = "hv30"
    // Upside Room
    var wRange: Double = 0.30
    var wAth: Double = 0.30
    var wRsi: Double = 0.20
    var wMa: Double = 0.20
    var athFullRoom: Double = 30
    var biasMax: Double = 2.5
    var biasSpan: Double = 3.5
    // Reference levels (addendum)
    var rallyPct: Double = 0.15
    var tiebreakBand: Double = 1.5

    static let `default` = PlannerSettings()

    // Guardrail option sets
    static let deltaOpts: [Double] = [0, 250, 500, 1000]
    static let extOpts: [Double] = [0.25, 0.50, 0.75, 0.95]
    static let edgeOpts: [Double] = [-0.20, -0.40, -0.60, -9]
    static let weekendOpts: [Double] = [0, 0.3, 0.5, 1]
    static let lookbackOpts: [String] = ["hv20", "hv30", "hv60", "hv90"]
    static let weightOpts: [Double] = [0, 0.15, 0.25, 0.40]
    static let athRoomOpts: [Double] = [20, 30, 40, 50]
    static let biasMaxOpts: [Double] = [1.5, 2.5, 3.5, 5]
    static let biasSpanOpts: [Double] = [2.5, 3.5, 4.5, 6]
    static let rallyOpts: [Double] = [0.10, 0.15, 0.20, 0.30]
    static let tiebreakOpts: [Double] = [1.0, 1.5, 2.0, 5.0]

    static func fmtDelta(_ v: Double) -> String { v == 0 ? "0" : "+" + Int(v).formatted(.number.grouping(.automatic)) }
    static func fmtPct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
    static func fmtEdge(_ v: Double) -> String { v <= -1 ? "off" : "−\(Int((abs(v) * 100).rounded()))%" }
    static func fmtWeekend(_ v: Double) -> String { String(format: "%.1f d", v) }
    static func fmtLookback(_ v: String) -> String { v.uppercased() }
    static func fmtRoom(_ v: Double) -> String { "\(Int(v))%" }
    static func fmtBias(_ v: Double) -> String { String(format: "%.1f", v) }

    // Guardrail summary (blocks + math rows)
    func fmt(_ key: String) -> String {
        switch key {
        case "minNetDelta": return Self.fmtDelta(minNetDelta)
        case "minExt": return Self.fmtPct(minExt)
        case "edgeFloor": return Self.fmtEdge(edgeFloor)
        case "weekendVol": return Self.fmtWeekend(weekendVol)
        default: return Self.fmtLookback(edgeLookback)
        }
    }
    static let labels: [String: String] = [
        "minNetDelta": "Min net delta after", "minExt": "Min extrinsic %", "edgeFloor": "Edge floor · % of premium",
        "weekendVol": "Weekend vol coefficient", "edgeLookback": "Edge lookback",
    ]
    static let hardKeys = ["minNetDelta", "minExt", "edgeFloor"]
    static let softKeys = ["weekendVol", "edgeLookback"]
}

// MARK: - Client engine (Upside Room, guardrails, selection, scaling, scenario)

enum PlannerEngine {
    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { Swift.max(lo, Swift.min(hi, v)) }

    // ── Upside Room ──
    struct Upside: Sendable {
        var available: Bool
        var rangePos, athProx, rsiComp, maComp: Double?    // components, 0–100
        var high52, low52, ma50, ma200, rsi14, ath, pctOffAth, dev50, dev200: Double?
        var athDate: String?
        var score: Double?
        var bandHead, bandBias: String
        var targetMoneyness, targetStrike: Double?
        var mixed: Bool
        var suppressed: [String]
        var caption: String?
    }

    static func upside(_ t: PTech, spot: Double, _ s: PlannerSettings) -> Upside {
        var comps: [String: Double] = [:]
        let weights: [String: Double] = ["range": s.wRange, "ath": s.wAth, "rsi": s.wRsi, "ma": s.wMa]
        var u = Upside(available: false, bandHead: "off", bandBias: "bias off", mixed: false, suppressed: [], caption: nil)

        if let hi = t.high52, let lo = t.low52, hi > lo {
            u.rangePos = clamp((spot - lo) / (hi - lo) * 100, 0, 100); comps["range"] = u.rangePos
            u.high52 = hi; u.low52 = lo
        } else { u.suppressed.append("range") }

        if let ath = t.ath, ath > 0 {
            let pct = (ath - spot) / ath * 100
            u.pctOffAth = pct; u.ath = ath; u.athDate = t.athDate
            u.athProx = clamp(100 - pct * (100 / s.athFullRoom), 0, 100); comps["ath"] = u.athProx
        } else { u.suppressed.append("ath") }

        if let r = t.rsi14 { u.rsiComp = r; u.rsi14 = r; comps["rsi"] = r } else { u.suppressed.append("rsi") }

        if let m50 = t.ma50, let m200 = t.ma200, m50 > 0, m200 > 0 {
            let d50 = (spot - m50) / m50 * 100, d200 = (spot - m200) / m200 * 100
            u.ma50 = m50; u.ma200 = m200; u.dev50 = d50; u.dev200 = d200
            u.maComp = clamp(50 + (d50 * 0.5 + d200 * 0.5) * 5, 0, 100); comps["ma"] = u.maComp
        } else { u.suppressed.append("ma") }

        let present = comps.keys.sorted()
        let wSum = present.reduce(0.0) { $0 + (weights[$1] ?? 0) }
        guard !present.isEmpty, wSum > 0 else { return u }
        u.available = true
        let sc = present.reduce(0.0) { $0 + comps[$1]! * (weights[$1] ?? 0) } / wSum   // proportional redistribution
        u.score = sc
        let vals = present.map { comps[$0]! }
        u.mixed = (vals.max()! - vals.min()!) > 30
        u.caption = u.suppressed.isEmpty ? nil : "reduced inputs"
        u.bandHead = sc < 25 ? "deeply beaten down" : sc < 50 ? "below middle · meaningful room" : sc < 75 ? "neutral to firm" : "extended"
        let tm = s.biasMax - (sc / 100) * s.biasSpan
        u.targetMoneyness = tm
        u.targetStrike = spot * (1 + tm / 100)
        u.bandBias = biasLabel(tm)
        return u
    }
    static func biasLabel(_ tm: Double) -> String {
        if abs(tm) < 0.05 { return "bias at spot" }
        return "bias \(tm > 0 ? "+" : "−")\(String(format: "%.1f", abs(tm)))% \(tm > 0 ? "OTM" : "ITM")"
    }

    // ── per-row scaling (ct-dependent) ──
    static func netDeltaAfter(_ r: PRung, _ book: PBook, ct: Double) -> Double {
        (book.netDelta - book.shortCallDelta - r.delta * ct * 100).rounded()
    }
    static func pctLong(_ r: PRung, _ book: PBook, ct: Double) -> Double {
        book.shares > 0 ? netDeltaAfter(r, book, ct: ct) / book.shares : 0
    }
    static func credit(_ r: PRung, ct: Double) -> Double { r.prem * 100 * ct }

    // ── guardrails ──
    static let guardKeys = ["tick", "delta", "edge", "ext"]
    static func guardPass(_ key: String, _ r: PRung, _ s: PlannerSettings, _ book: PBook, ct: Double) -> Bool {
        switch key {
        case "tick": return r.sellable
        case "delta": return netDeltaAfter(r, book, ct: ct) >= s.minNetDelta
        case "edge": return r.edgePct >= s.edgeFloor
        default: return r.extPct >= s.minExt
        }
    }
    static func passesAll(_ r: PRung, _ s: PlannerSettings, _ book: PBook, ct: Double) -> Bool {
        guardKeys.allSatisfy { guardPass($0, r, s, book, ct: ct) }
    }
    static func failing(_ r: PRung, _ s: PlannerSettings, _ book: PBook, ct: Double) -> [String] {
        guardKeys.filter { !guardPass($0, r, s, book, ct: ct) }
    }
    static func guardLabel(_ key: String) -> String {
        ["tick": "sellable premium", "delta": "min net delta", "edge": "edge floor", "ext": "min extrinsic"][key] ?? key
    }
    /// Reading for a blocked row's failing guard: "ext 10%", "net Δ 1,892", "edge −3%".
    static func guardRead(_ key: String, _ r: PRung, _ book: PBook, ct: Double) -> String {
        switch key {
        case "tick": return "no premium"
        case "delta": return "net Δ " + Int(netDeltaAfter(r, book, ct: ct)).formatted(.number.grouping(.automatic))
        case "edge": return "edge \(r.edgePct < 0 ? "−" : "+")\(Int((abs(r.edgePct) * 100).rounded()))%"
        default: return "ext \(Int((r.extPct * 100).rounded()))%"
        }
    }

    // ── reference levels (addendum) ──
    struct Level: Sendable, Identifiable { let price: Double; let type: String; let label: String; let count: Double?; var id: String { "\(type)-\(price)" } }
    static func levels(_ legs: PlannerLegs, spot: Double, candidateExpiry: Date?) -> [Level] {
        var out: [Level] = []
        for l in legs.longCalls { out.append(Level(price: l.strike, type: "long", label: "LONG CALLS · \(Int(l.ct)) CT", count: l.ct)) }
        out.append(Level(price: legs.buyAvg, type: "buyavg", label: "BUY AVG", count: nil))
        out.append(Level(price: legs.buyAvg - legs.realizedPremium / Swift.max(legs.shares, 1), type: "basis", label: "BASIS AFTER PREMIUM", count: nil))
        out.append(Level(price: spot, type: "spot", label: "SPOT", count: nil))
        if let cand = candidateExpiry {
            var byStrike: [Double: Double] = [:]
            for s in legs.shortCalls where (s.expiry.map { $0 > cand } ?? false) { byStrike[s.strike, default: 0] += s.ct }
            for (k, ctn) in byStrike.sorted(by: { $0.key < $1.key }) { out.append(Level(price: k, type: "short", label: "SHORT CALLS · \(Int(ctn)) CT", count: ctn)) }
        }
        let sorted = out.sorted { $0.price < $1.price }
        var collapsed: [Level] = []
        for lv in sorted {
            if let last = collapsed.last, abs(last.price - lv.price) <= 0.25 {
                collapsed[collapsed.count - 1] = Level(price: last.price, type: last.type, label: last.label + " · " + lv.label, count: last.count)
            } else { collapsed.append(lv) }
        }
        return collapsed
    }
    struct Pairing: Sendable { let favorableCt, adverseCt, pairedCt, shareCoveredCt, netAtRally: Double }
    static func pairing(_ K: Double, _ legs: PlannerLegs, ct: Double, spot: Double, rallyPct: Double) -> Pairing {
        let fav = legs.longCalls.filter { $0.strike <= K }.reduce(0.0) { $0 + $1.ct }
        let adv = legs.longCalls.filter { $0.strike > K }.reduce(0.0) { $0 + $1.ct }
        var remaining = ct, net = 0.0; let sUp = spot * (1 + rallyPct)
        for L in legs.longCalls.sorted(by: { $0.strike < $1.strike }) {
            let take = Swift.min(remaining, L.ct); if take <= 0 { continue }
            net += (Swift.max(0, sUp - L.strike) * take * 100) - (Swift.max(0, sUp - K) * take * 100)
            remaining -= take; if remaining <= 0 { break }
        }
        return Pairing(favorableCt: fav, adverseCt: adv, pairedCt: Swift.min(fav + adv, ct), shareCoveredCt: Swift.max(0, remaining), netAtRally: net)
    }
    static func effSale(_ r: PRung) -> Double { r.strike + r.prem }
    static func cleared(_ r: PRung, _ levels: [Level]) -> Int { levels.filter { $0.price <= effSale(r) }.count }

    // ── selection: target-moneyness matching + reference-level tiebreak ──
    struct Pick: Sendable { var none: Bool; var strike: Double?; var why: String; var binding: String?; var tie: Bool }
    static func select(_ chain: [PRung], _ s: PlannerSettings, _ book: PBook, ct: Double, targetStrike: Double?, upsideScore: Double?,
                       blocked: Bool, legs: PlannerLegs?, levels: [Level], spot: Double) -> Pick {
        let candidates = chain.filter { passesAll($0, s, book, ct: ct) }
        let binding = guardKeys.map { g in (g, chain.filter { !guardPass(g, $0, s, book, ct: ct) }.count) }
            .filter { $0.1 > 0 }.max { $0.1 < $1.1 }?.0
        guard let target = targetStrike, !candidates.isEmpty else {
            if candidates.isEmpty {
                let g = binding ?? "min extrinsic"
                return Pick(none: true, strike: nil, why: "No acceptable strike this cycle. \(guardLabel(g).capitalized) binds.", binding: binding, tie: false)
            }
            let r = candidates.max { $0.extPct < $1.extPct }!
            return Pick(none: false, strike: r.strike, why: "Upside Room is off — highest extrinsic that clears the guardrails.", binding: binding, tie: false)
        }
        let dMin = candidates.map { abs($0.strike - target) }.min() ?? 0
        let near = candidates.filter { abs($0.strike - target) <= dMin * s.tiebreakBand }
        let sc = upsideScore.map { Int($0.rounded()) } ?? 0
        let tm = biasLabel(s.biasMax - (Double(sc) / 100) * s.biasSpan).replacingOccurrences(of: "bias ", with: "")
        if near.count <= 1 {
            let pick = near.first ?? candidates.min { abs($0.strike - target) < abs($1.strike - target) }!
            var why = "Upside Room \(sc) targets \(tm). \(nvStr(pick.strike)) is the closest listed strike."
            if blocked { why = "Gate is blocking. If you sell anyway: " + why.prefix(1).lowercased() + why.dropFirst() }
            return Pick(none: false, strike: pick.strike, why: why, binding: binding, tie: false)
        }
        // tiebreak: highest levels cleared, then higher pairing net, then lower strike
        let netOf: (PRung) -> Double = { r in legs.map { l in pairing(r.strike, l, ct: ct, spot: spot, rallyPct: s.rallyPct).netAtRally } ?? 0 }
        let pick = near.max { a, b in
            let ca = cleared(a, levels), cb = cleared(b, levels)
            if ca != cb { return ca < cb }
            let na = netOf(a), nb = netOf(b)
            if na != nb { return na < nb }
            return a.strike > b.strike
        }!
        let others = near.filter { $0.strike != pick.strike }.map { nvStr($0.strike) }.joined(separator: " and ")
        var why = "Upside Room \(sc) targets \(tm). \(nvStr(pick.strike)) and \(others) are both close. \(nvStr(pick.strike)) picked: assignment at $\(String(format: "%.2f", effSale(pick))) clears \(cleared(pick, levels)) of \(levels.count) levels."
        if blocked { why = "Gate is blocking. If you sell anyway: " + why.prefix(1).lowercased() + why.dropFirst() }
        return Pick(none: false, strike: pick.strike, why: why, binding: binding, tie: true)
    }

    // ── signals (six reads) ──
    static func signals(_ r: PRung, _ s: PlannerSettings, _ book: PBook, ct: Double, blocked: Bool, histAssign: Double) -> [(k: String, ok: Bool, label: String)] {
        [
            ("gate", !blocked, "Gate"),
            ("edge", r.edge > 0, "Edge at \(s.edgeLookback.uppercased())"),
            ("span", r.edgeHi > 0 && r.edgeLo > 0, "Edge across lookbacks"),
            ("pair", r.advCost == 0, "Long-call pairing"),
            ("ext", r.extPct >= s.minExt, "Extrinsic share of credit"),
            ("delta", netDeltaAfter(r, book, ct: ct) >= s.minNetDelta, "Net delta after"),
        ]
    }

    // ── scenario Black-Scholes (for the What-happens-next diff table) ──
    private static func ncdf(_ x: Double) -> Double {
        let a1 = 0.254829592, a2 = -0.284496736, a3 = 1.421413741, a4 = -1.453152027, a5 = 1.061405429, p = 0.3275911
        let s: Double = x < 0 ? -1 : 1, z = abs(x) / 2.0.squareRoot(), t = 1 / (1 + p * z)
        let y = 1 - ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * exp(-z * z)
        return 0.5 * (1 + s * y)
    }
    static func bsCall(_ S: Double, _ K: Double, _ T: Double, _ v: Double) -> Double {
        if T <= 0 || v <= 0 { return Swift.max(S - K, 0) }
        let sq = v * T.squareRoot()
        let d1 = (log(S / K) + (0.045 + v * v / 2) * T) / sq
        return S * ncdf(d1) - K * exp(-0.045 * T) * ncdf(d1 - sq)
    }

    static func nvStr(_ k: Double) -> String { k == k.rounded() ? String(Int(k)) : String(format: "%.1f", k) }
}

// MARK: - Wash-sale detector (unchanged)

enum PlannerWash {
    private static let iso: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "America/New_York"); return f }()
    private static let disp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d"; f.timeZone = TimeZone(identifier: "America/New_York"); return f }()
    private static func days(_ a: Date, _ b: Date) -> Int { Calendar(identifier: .gregorian).dateComponents([.day], from: a, to: b).day ?? 0 }

    static func detect(_ trades: [NvOptionTrade], now: Date = Date()) -> PlannerReq.Wash? {
        let shorts = trades.filter { $0.voided_at == nil && $0.option_type == "call" && $0.direction == "short" }
        guard !shorts.isEmpty else { return nil }
        struct Key: Hashable { let strike: Double; let expiry: String }
        var byLeg: [Key: [NvOptionTrade]] = [:]
        for t in shorts { byLeg[Key(strike: t.strike, expiry: t.expiry), default: []].append(t) }
        var best: (date: Date, amount: Double)?
        for (_, ts) in byLeg {
            let netCt = ts.reduce(0.0) { $0 + ($1.action == "open" ? 1 : -1) * $1.contracts }
            let closes = ts.filter { $0.action != "open" }
            guard abs(netCt) < 0.001, !closes.isEmpty else { continue }
            let realized = ts.reduce(0.0) { $0 + ($1.action == "open" ? 1 : -1) * $1.premium * $1.contracts * 100 }
            guard realized < 0 else { continue }
            guard let cd = closes.compactMap({ iso.date(from: $0.trade_date) }).max(), days(cd, now) >= 0, days(cd, now) <= 30 else { continue }
            if best == nil || cd > best!.date { best = (cd, -realized) }
        }
        guard let loss = best else { return nil }
        let replaced = shorts.contains { t in
            guard t.action == "open", let d = iso.date(from: t.trade_date) else { return false }
            return d >= loss.date && days(loss.date, d) <= 30
        }
        guard replaced else { return nil }
        return PlannerReq.Wash(hit: true, on: disp.string(from: loss.date), amount: loss.amount.rounded(), daysLeft: max(0, 30 - days(loss.date, now)))
    }
}

// MARK: - Calibration log (kept for the plan card's "vs your rate")

struct PlannerCycle: Codable, Sendable, Identifiable {
    let id: String; let ts: Double; let expiry: String; let strike, ct, mid: Double; var fill: Double
    let pAssign: Double; var assigned: Bool; let impliedMove, realizedMove: Double; var settled: Bool
}
enum PlannerLog {
    static let key = "nvda-planner-log-v1"
    static func load() -> [PlannerCycle] {
        if let d = UserDefaults.standard.data(forKey: key), let rows = try? JSONDecoder().decode([PlannerCycle].self, from: d) { return rows }
        let seed = seedLog(); save(seed); return seed
    }
    static func save(_ rows: [PlannerCycle]) { if let d = try? JSONEncoder().encode(rows) { UserDefaults.standard.set(d, forKey: key) } }
    private final class Rng { var s: UInt64; init(_ seed: UInt64) { s = seed }
        func next() -> Double { s = (s &* 1103515245 &+ 12345) & 0x7fffffff; return Double(s) / Double(0x7fffffff) } }
    static func seedLog(now: Date = Date()) -> [PlannerCycle] {
        let r = Rng(90210); var out: [PlannerCycle] = []; let cal = Calendar(identifier: .gregorian)
        for i in stride(from: 23, through: 0, by: -1) {
            let d = cal.date(byAdding: .day, value: -(i * 2 + 1), to: now) ?? now
            let strike = 195 + Double(Int(r.next() * 12)) * 2.5
            let pAssign = min(0.72, max(0.04, r.next() * 0.6 + 0.06))
            let mid = 0.8 + r.next() * 4.2, slip = -(0.02 + r.next() * 0.09)
            let im = 1.6 + r.next() * 2.4, rm = im * (0.45 + r.next() * 1.25)
            out.append(PlannerCycle(id: "s\(i)", ts: d.timeIntervalSince1970 * 1000, expiry: "", strike: strike,
                ct: Double(8 + Int(r.next() * 6)), mid: (mid * 100).rounded() / 100, fill: ((mid + slip) * 100).rounded() / 100,
                pAssign: (pAssign * 1000).rounded() / 1000, assigned: r.next() < pAssign,
                impliedMove: (im * 100).rounded() / 100, realizedMove: (rm * 100).rounded() / 100, settled: true))
        }
        return out
    }
    static func assignRate(_ rows: [PlannerCycle]) -> Double {
        let done = rows.filter { $0.settled }
        return done.isEmpty ? 0.25 : Double(done.filter { $0.assigned }.count) / Double(done.count)
    }
}

// MARK: - Persistence rows

struct PlannerSettingsRow: Codable, Sendable {
    let min_net_delta, min_ext, edge_floor, weekend_vol: Double
    let edge_lookback: String
    let w_range, w_ath, w_rsi, w_ma, ath_full_room, bias_max, bias_span, rally_pct, tiebreak_band: Double
    init(_ s: PlannerSettings) {
        min_net_delta = s.minNetDelta; min_ext = s.minExt; edge_floor = s.edgeFloor; weekend_vol = s.weekendVol
        edge_lookback = s.edgeLookback; w_range = s.wRange; w_ath = s.wAth; w_rsi = s.wRsi; w_ma = s.wMa
        ath_full_room = s.athFullRoom; bias_max = s.biasMax; bias_span = s.biasSpan
        rally_pct = s.rallyPct; tiebreak_band = s.tiebreakBand
    }
    // Optional decode: rally/tiebreak columns may be absent on older rows.
    enum CodingKeys: String, CodingKey { case min_net_delta, min_ext, edge_floor, weekend_vol, edge_lookback, w_range, w_ath, w_rsi, w_ma, ath_full_room, bias_max, bias_span, rally_pct, tiebreak_band }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        min_net_delta = try c.decode(Double.self, forKey: .min_net_delta)
        min_ext = try c.decode(Double.self, forKey: .min_ext)
        edge_floor = try c.decode(Double.self, forKey: .edge_floor)
        weekend_vol = try c.decode(Double.self, forKey: .weekend_vol)
        edge_lookback = try c.decode(String.self, forKey: .edge_lookback)
        w_range = try c.decode(Double.self, forKey: .w_range)
        w_ath = try c.decode(Double.self, forKey: .w_ath)
        w_rsi = try c.decode(Double.self, forKey: .w_rsi)
        w_ma = try c.decode(Double.self, forKey: .w_ma)
        ath_full_room = try c.decode(Double.self, forKey: .ath_full_room)
        bias_max = try c.decode(Double.self, forKey: .bias_max)
        bias_span = try c.decode(Double.self, forKey: .bias_span)
        rally_pct = try c.decodeIfPresent(Double.self, forKey: .rally_pct) ?? 0.15
        tiebreak_band = try c.decodeIfPresent(Double.self, forKey: .tiebreak_band) ?? 1.5
    }
    var settings: PlannerSettings {
        PlannerSettings(minNetDelta: min_net_delta, minExt: min_ext, edgeFloor: edge_floor, weekendVol: weekend_vol,
            edgeLookback: edge_lookback, wRange: w_range, wAth: w_ath, wRsi: w_rsi, wMa: w_ma,
            athFullRoom: ath_full_room, biasMax: bias_max, biasSpan: bias_span, rallyPct: rally_pct, tiebreakBand: tiebreak_band)
    }
}

struct PlannerIntentRow: Codable, Sendable {
    let id, ts: String
    let expiry: String?
    let strike, ct, mid, fill, p_assign: Double?
    let assigned: Bool?
    let implied_move, realized_move: Double?
    let settled: Bool
    private static let isoPlain = ISO8601DateFormatter()
    var cycle: PlannerCycle {
        let epoch = Self.isoPlain.date(from: ts)?.timeIntervalSince1970 ?? 0
        return PlannerCycle(id: id, ts: epoch * 1000, expiry: expiry ?? "", strike: strike ?? 0, ct: ct ?? 0,
            mid: mid ?? 0, fill: fill ?? 0, pAssign: p_assign ?? 0, assigned: assigned ?? false,
            impliedMove: implied_move ?? 0, realizedMove: realized_move ?? 0, settled: settled)
    }
}

// MARK: - Request

struct PlannerReq: Encodable, Sendable {
    struct Leg: Encodable, Sendable { let strike: Double; let ct: Double }
    struct Book: Encodable, Sendable {
        let shares, buyAvg, realizedPremium, netDelta, longTheta, shortCallDelta, shortCallCt: Double
        let openShortCalls: [Leg]; let longCalls: [Leg]
    }
    struct Vol: Encodable, Sendable { let iv, ivPct, hv20, hv30, hv60, hv90: Double }
    struct Earn: Encodable, Sendable { let date, label: String }
    struct Wash: Encodable, Sendable { let hit: Bool; let on: String; let amount: Double; let daysLeft: Int }
    let book: Book; let vol: Vol; let earnings: Earn
    var wash: Wash? = nil
    let weekendVol: Double
    let spot: Double
}

// MARK: - Book legs (for reference levels — kept client-side from NvDerive)

struct PlannerLegs: Sendable {
    let longCalls: [(strike: Double, ct: Double)]              // grouped by strike, ascending
    let shortCalls: [(strike: Double, ct: Double, expiry: Date?)]
    let buyAvg, realizedPremium, shares: Double
}

// MARK: - Store

@MainActor
@Observable
final class PlannerStore {
    var state: PlannerState?
    var isLoading = true
    var lastError: String?
    var log: [PlannerCycle] = PlannerLog.load()

    // Client-side selections (no re-fetch)
    var settings = PlannerSettings.default
    var ct: Double = 1
    var selExpiry: String? = nil
    var selStrike: Double? = nil
    var when = "expiry"
    var step = 0
    var legs: PlannerLegs?

    private var ctx: Ctx?
    private var gen = 0
    private let client = SupabaseService.client
    static let earnings = (date: "2026-08-26", label: "Aug 26")

    struct Ctx: Sendable { let book: PlannerReq.Book; let vol: PlannerReq.Vol; let wash: PlannerReq.Wash?; let spot: Double }

    var histAssign: Double { PlannerLog.assignRate(log) }

    /// Parse an NvStrike display expiry ("Aug 15 '26") to a Date for level filtering.
    private static let expiryFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d yy"; f.timeZone = TimeZone(identifier: "America/New_York"); return f }()
    static func parseExpiry(_ s: String) -> Date? {
        let cleaned = s.replacingOccurrences(of: "\u{2019}", with: "").replacingOccurrences(of: "'", with: "")
        return expiryFmt.date(from: cleaned)
    }
    /// The selected candidate expiry as a Date (for short-call level filtering).
    var selExpiryDate: Date? { selExpiryObj.map { Self.isoDate($0.iso) } }

    func load(from store: NvdaStore) async {
        await loadPersisted()
        if ctx == nil { ctx = await buildContext(from: store) }
        guard ctx != nil else { isLoading = false; lastError = "position not ready"; return }
        await run()
    }

    private func run() async {
        guard let ctx else { return }
        gen += 1; let g = gen
        isLoading = true
        let req = PlannerReq(book: ctx.book, vol: ctx.vol, earnings: .init(date: Self.earnings.date, label: Self.earnings.label),
                             wash: ctx.wash, weekendVol: settings.weekendVol, spot: ctx.spot)
        do {
            let data = try await client.functions.invoke("nvda-planner", options: FunctionInvokeOptions(body: req), decode: { data, _ in data })
            let decoded = try JSONDecoder().decode(PlannerState.self, from: data)
            guard g == gen else { return }
            if decoded.ok {
                state = decoded; lastError = nil
                if ct <= 1 { ct = max(1, decoded.book.capacity) }        // default to full capacity on first load
            } else { lastError = "planner unavailable" }
            isLoading = false
        } catch { guard g == gen else { return }; lastError = String(describing: error); isLoading = false }
    }

    /// Only weekend-vol changes pricing → re-fetch. Everything else recomputes client-side.
    func setSetting(_ mutate: (inout PlannerSettings) -> Void) {
        let before = settings.weekendVol
        mutate(&settings)
        saveSettings()
        if settings.weekendVol != before { Task { await run() } }
    }
    func resetSettings() {
        let before = settings.weekendVol
        settings = .default; saveSettings()
        if settings.weekendVol != before { Task { await run() } }
    }

    // ── selection helpers (client-side) ──
    var selExpiryObj: PExpiry? { state?.expiries.first { $0.iso == selExpiry } ?? state?.expiries.first }
    func rung(_ strike: Double?) -> PRung? { guard let strike else { return nil }; return selExpiryObj?.chain.first { abs($0.strike - strike) < 1e-6 } }
    var selRung: PRung? { rung(selStrike) }

    static func isoDate(_ iso: String) -> Date {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return Date() }
        return Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(identifier: "America/New_York"), year: p[0], month: p[1], day: p[2])) ?? Date()
    }

    // ── persistence ──
    private func loadPersisted() async {
        if let rows: [PlannerSettingsRow] = try? await client.from("planner_settings").select().limit(1).execute().value, let r = rows.first {
            settings = r.settings
        }
        if let rows: [PlannerIntentRow] = try? await client.from("planner_intents").select().order("ts", ascending: false).execute().value, !rows.isEmpty {
            log = rows.map { $0.cycle }
        }
    }
    private func saveSettings() {
        let row = PlannerSettingsRow(settings)
        Task { try? await client.from("planner_settings").upsert(row, onConflict: "user_id").execute() }
    }

    private func fetchWash() async -> PlannerReq.Wash? {
        guard let trades: [NvOptionTrade] = try? await client.from("nvda_option_trades")
            .select("id,trade_date,action,option_type,direction,contracts,strike,premium,expiry,voided_at")
            .is("voided_at", value: nil).execute().value else { return nil }
        return PlannerWash.detect(trades)
    }

    private func buildContext(from store: NvdaStore) async -> Ctx? {
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
            longCalls: openLongCalls.map { .init(strike: $0.strike, ct: $0.ct) })

        // Reference-level inputs: long calls grouped by strike; shorts with a parsed expiry.
        var longByStrike: [Double: Double] = [:]
        for s in openLongCalls { longByStrike[s.strike, default: 0] += s.ct }
        legs = PlannerLegs(
            longCalls: longByStrike.sorted { $0.key < $1.key }.map { (strike: $0.key, ct: $0.value) },
            shortCalls: openShorts.map { (strike: $0.strike, ct: $0.ct, expiry: Self.parseExpiry($0.expiry)) },
            buyAvg: pos.avgBuy, realizedPremium: pnl.premiumRealized, shares: pos.shares)
        let vol = PlannerReq.Vol(iv: ins.vol.iv ?? 0, ivPct: ins.vol.ivr ?? 50,
            hv20: store.hv(20) ?? (ins.vol.hv30 ?? 0), hv30: ins.vol.hv30 ?? 0,
            hv60: store.hv(60) ?? (ins.vol.hv30 ?? 0), hv90: store.hv(90) ?? (ins.vol.hv30 ?? 0))
        let wash = await fetchWash()
        return Ctx(book: book, vol: vol, wash: wash, spot: pos.spot)
    }
}
