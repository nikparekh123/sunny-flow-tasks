//
//  PositionsModels.swift
//  Sunny
//
//  What the Positions tab draws (handoff 2026-11-13-positions, App Explorations 154a, view only), worked out once per
//  build and kept (PositionsMemo): never in a view's body.
//
//  Sources, all live already:
//    Home's brief (BriefState.live): the names in book order, their price and prior close, company and strategy, st
//      (2 = short at the priced move by Friday: the strip's red dot), and each name's holdings `h` (Book totals).
//    Home's brief_inputs (BriefState.inputs): every leg with what it was sold or bought at, its mark and its own IV
//      (Sold, in SD; Every leg's "so far").
//    sunny-positions (BriefState.positions, PositionsModel): the name's grid (Payoff at this Friday's close, the
//      Greeks, each leg's delta).
//    sunny-chart (PositionsCharts): the name's daily closes (Price).
//    sunny-sd (SDStore): each sold leg's SD when sold (z0) and the name's Intelligence (PositionsIntel.swift).
//  The maths is PositionsEngine.swift (PE), the web's positions-engine.ts line for line.
//
//  ⚠ NIK'S GROUPING RULE (11 Nov 2026, D7 13 Nov): Long = shares only; Hedge = every call bought (LEAPS too) and every
//  put bought; Income = everything sold. Legs read strike first ("40 call · Nov 13"), never "OTM calls".
//  No em dashes in any words here.
//

import Foundation
import Observation

// MARK: - Words and numbers (README §5)

nonisolated enum PosFmt {
    /// Book money in K and M ($624, $5.9K, $13.7K, $379K, $1.2M), never a sign.
    static func money(_ x: Double) -> String {
        let a = abs(x)
        func s1(_ v: Double, _ u: String) -> String { var t = String(format: "%.1f", v); if t.hasSuffix(".0") { t.removeLast(2) }; return "$" + t + u }
        if a >= 999_500 { return s1(a / 1e6, "M") }
        if a >= 99_950 { return "$\(Int((a / 1000).rounded()))K" }
        if a >= 999.5 { return s1(a / 1000, "K") }
        return "$\(Int(a.rounded()))"
    }
    /// A count with thousands commas, no sign.
    static func count(_ x: Double) -> String { Int(abs(x).rounded()).formatted(.number.grouping(.automatic)) }
    /// A price: $38.09.
    static func price(_ x: Double) -> String { "$" + String(format: "%.2f", x) }
    /// "Short 1,968" / "Long 3,000".
    static func side(_ d: Double) -> String { (d < 0 ? "Short " : "Long ") + count(d) }
    /// The server's expLabel: "Nov 13", or "Sep ’27" more than 183 days out.
    static func expLabel(_ iso: String, daysOut: Int) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return iso }
        return daysOut <= 183 ? "\(MON[p[1] - 1]) \(p[2])" : "\(MON[p[1] - 1]) ’\(String(p[0]).suffix(2))"
    }
    static let MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let DOW = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    /// "Nov 13" from an ISO day.
    static func md(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return iso }
        return "\(MON[p[1] - 1]) \(p[2])"
    }
    /// "Fri Nov 13" from an ISO day.
    static func dmd(_ iso: String) -> String { "\(DOW[PE.weekday(iso)]) \(md(iso))" }
}

// MARK: - The whole book (title, Book totals, Sold in SD, the name strip)

struct PosBook {
    struct Name: Identifiable, Hashable {
        var id: String { t }
        let t: String; let company: String; let strategy: String
        let S0: Double; let P0: Double
        /// The strip's dot (A7): red = short at the priced move by Friday, orange = a sold leg within 0.5 SD.
        let dot: PE.Tone?
    }
    /// One piece of Book totals: what was paid (sold: collected), its value now (sold: the cost to close).
    struct Fig { var paid = 0.0, now = 0.0 }
    struct Piece: Identifiable { var id: String { label }; let label: String; let fig: Fig?; let sold: Bool }
    struct Group: Identifiable { var id: String { title }; let title: String; let pieces: [Piece] }

    let names: [Name]
    let groups: [Group]
    let sold: [PE.SoldRow]
    let within: Int
    let inTheMoney: Int
    /// In the money or within 0.5 SD: the capsule's red count.
    var hot: Int { sold.filter { $0.itm || $0.a < 0.5 }.count }
    /// The names with something sold (their sunny-sd replies carry the SD when sold).
    let soldNames: [String]

    static func build(brief: BriefLive, inputs: JSONValue?, calendar: [CalendarDay], replies: (String) -> SDReply?, now: Date) -> PosBook {
        // Book totals: every name's holdings from Home's brief (book-engine holdings(), the web's totals.ts).
        let hs = brief.names.map { PositionsModel.holdings(json: $0) }
        func sum(_ f: (PositionsModel.Holdings) -> Fig?) -> Fig? {
            hs.compactMap(f).reduce(nil) { a, x in Fig(paid: (a?.paid ?? 0) + x.paid, now: (a?.now ?? 0) + x.now) }
        }
        let held = { (paid: Double, now: Double) in paid != 0 || now != 0 }
        let groups = [
            Group(title: "Long", pieces: [Piece(label: "Shares", fig: sum { held($0.paid.sh, $0.sh.value) ? Fig(paid: $0.paid.sh, now: $0.sh.value) : nil }, sold: false)]),
            Group(title: "Hedge", pieces: [
                Piece(label: "Calls", fig: sum { held($0.paid.lp + $0.paid.oc, $0.lp.value + $0.oc.value) ? Fig(paid: $0.paid.lp + $0.paid.oc, now: $0.lp.value + $0.oc.value) : nil }, sold: false),
                Piece(label: "Puts", fig: sum { held($0.paid.ip, $0.ip.value) ? Fig(paid: $0.paid.ip, now: $0.ip.value) : nil }, sold: false)]),
            Group(title: "Income", pieces: [
                Piece(label: "Calls", fig: sum { held($0.paid.sc, $0.sc.value) ? Fig(paid: $0.paid.sc, now: $0.sc.value) : nil }, sold: true),
                Piece(label: "Puts", fig: sum { held($0.paid.sp, $0.sp.value) ? Fig(paid: $0.paid.sp, now: $0.sp.value) : nil }, sold: true)]),
        ]
        // Sold, in SD: every sold option leg from Home's legs; the SD when sold from each name's sunny-sd reply.
        let legs = soldLegs(inputs: inputs, calendar: calendar, replies: replies, now: now)
        let so = PE.soldInSd(legs)
        let names = brief.names.compactMap { n -> Name? in
            guard let t = n["t"].string else { return nil }
            let st = n["st"].double.map { Int($0) }
            return Name(t: t, company: n["name"].string ?? t, strategy: n["strategy"].string ?? "", S0: n["S0"].double ?? 0,
                        P0: n["P0"].double ?? n["S0"].double ?? 0, dot: PE.nameDot(st, so.rows, t))
        }
        var sn: [String] = []
        for l in legs where !sn.contains(l.t) { sn.append(l.t) }
        return PosBook(names: names, groups: groups, sold: so.rows, within: so.within, inTheMoney: so.inTheMoney, soldNames: sn)
    }

    /// Every sold leg of the book (the web's soldLegs): strike, count, sold at, the mark, the leg's own IV, the
    /// trading and calendar days to its expiry from now, and z0 when the name's reply is in.
    static func soldLegs(inputs: JSONValue?, calendar: [CalendarDay], replies: (String) -> SDReply?, now: Date) -> [PE.SoldIn] {
        guard let inp = inputs, case .object = inp else { return [] }
        let t0 = MarketClock.ny(now), closed = Set(calendar.filter { $0.kind == "closed" }.map(\.date))
        let built = inp["built_at"].string.flatMap { SXClient.parseDate($0) } ?? now
        let gone = max(0, now.timeIntervalSince(built) / 86_400)
        var out: [PE.SoldIn] = []
        for n in inp["names"].array {
            let t = n["t"].string ?? "", S = n["S0"].double ?? 0
            guard S > 0 else { continue }
            let reply = replies(t)
            for l in n["legs"].array {
                guard l["ty"].string != "S", let q = l["q"].double, q < 0, let ex = l["ex"].string, !ex.isEmpty, let K = l["K"].double else { continue }
                let put = l["ty"].string == "P", cd = max(0, (l["days"].double ?? 0) - gone)
                let iv = (l["iv"].double ?? 0) > 0.03 ? l["iv"].double! : n["iv"].double ?? 0
                let z0 = reply?.sold.first { $0.put == put && abs($0.K - K) < 1e-6 && $0.ex == ex }?.z0
                out.append(PE.SoldIn(t: t, S: S, put: put, K: K, n: -q, ex: ex, exLabel: PosFmt.expLabel(ex, daysOut: Int(cd.rounded())),
                                     entry: l["at"].double, mark: l["now"].double, iv: iv,
                                     td: PE.tradingDays(t0.date, ex, closed: closed, mins: Double(t0.minutes)), cd: cd, z0: z0))
            }
        }
        return out
    }
}

// MARK: - One name: the header, Every leg and the Payoff at this Friday's close

struct PosName {
    struct Leg: Identifiable {
        let id: String
        /// Long, Hedge or Income (Nik's rule).
        let group: String
        /// "40.5 call · Nov 20" or "NKE shares"; "50 sold", "15 bought", "3,000".
        let contract: String
        let qty: String
        /// (mark − entry) × q × mul; shares q × (price − cost).
        let soFar: Double
        /// q × 100 × Δ (shares q), from the grid at today's price.
        let delta: Double
        /// Switched on in Every leg (Nik 13 Nov 2026: "we should be able to switch on and switch off"). An off leg
        /// drops out of the Whole TICKER book row, the Price chart's strikes and the Payoff with its Greeks.
        let on: Bool
    }
    /// A strike on the Price chart: sold solid, bought dotted.
    struct Strike: Identifiable { let id: String; let K: Double; let sold: Bool; let label: String }
    struct Payoff {
        /// ±12% of the price, 121 points: the P&L from today's marks at this Friday's close.
        let xs: [Double]; let ys: [Double]
        let v0: Double
        /// "by Fri Nov 13" (or "today").
        let byT: String
        /// The date as the Greeks' labels write it ("Nov 13").
        let dateLabel: String
        /// Where the P&L peaks (the turns-short price, the server's to the cent), past its best already, or none.
        let peak: Double?
        let peakPast: Bool
        /// How far the grid reaches up, in % (the "Keeps making more past ↑50%" line).
        let top: Int
        /// The priced move by then, as a log move.
        let mv: Double
        let d: Double, th: Double, g: Double, vg: Double
    }

    let t: String
    let S0: Double
    let legs: [Leg]
    let soFar: Double
    let delta: Double
    let strikes: [Strike]
    let payoff: Payoff?
    /// Some leg is switched off.
    let changed: Bool

    static func build(_ m: PositionsModel, inputs: JSONValue?, off: Set<String> = []) -> PosName {
        let src = inputs?["names"].array.first { $0["t"].string == m.t }
        var at: [String: Double] = [:], mark: [String: Double] = [:]
        for l in src?["legs"].array ?? [] {
            guard let k = l["k"].string else { continue }
            if let a = l["at"].double { at[k] = a }
            if let n = l["now"].double { mark[k] = n }
        }
        let role = { (l: PositionsModel.Leg) -> Int in l.ty == .shares ? 0 : l.q < 0 ? 2 : 1 }
        let ordered = m.legs.enumerated().sorted { p, q in
            let a = p.element, b = q.element
            if role(a) != role(b) { return role(a) < role(b) }
            if a.iso != b.iso { return a.iso < b.iso }
            if (a.ty == .put) != (b.ty == .put) { return b.ty == .put }
            if a.K != b.K { return a.K < b.K }
            return p.offset < q.offset
        }.map(\.element)
        var legs: [Leg] = [], strikes: [Strike] = []
        for l in ordered {
            let exL = l.title.components(separatedBy: ", ").last ?? l.ex
            if l.ty == .shares {
                legs.append(Leg(id: l.id, group: "Long", contract: "\(m.t) shares", qty: PosFmt.count(l.q), soFar: l.q * (m.S0 - l.K), delta: l.q,
                                on: !off.contains(l.id)))
                continue
            }
            let kind = l.ty == .put ? "put" : "call"
            let now = mark[l.id], entry = at[l.id]
            let sf = entry != nil && now != nil ? (now! - entry!) * l.q * 100 : 0
            legs.append(Leg(id: l.id, group: l.q < 0 ? "Income" : "Hedge", contract: "\(PE.fk(l.K)) \(kind) · \(exL)",
                            qty: "\(PosFmt.count(l.q)) \(l.q < 0 ? "sold" : "bought")", soFar: sf, delta: m.legDelta(l, m.S0, 0),
                            on: !off.contains(l.id)))
            if off.contains(l.id) { continue }
            strikes.append(Strike(id: l.id, K: l.K, sold: l.q < 0, label: "\(PE.fk(l.K)) \(kind) · \(exL) · \(l.q < 0 ? "sold" : "bought") \(PosFmt.count(l.q))"))
        }
        let live = legs.filter(\.on)
        return PosName(t: m.t, S0: m.S0, legs: legs, soFar: live.reduce(0) { $0 + $1.soFar }, delta: live.reduce(0) { $0 + $1.delta },
                       strikes: strikes, payoff: payoff(m, off: off), changed: live.count < legs.count)
    }

    /// README §3.5 at this Friday's close: Σ q × mul × (value then − mark now) from the server's grid (no premium already
    /// earned: the web's Pricer), ±12% of the price, the priced move, where it peaks, the Greeks then.
    /// Legs switched off drop out (the web's What if set).
    private static func payoff(_ m: PositionsModel, off: Set<String>) -> Payoff? {
        guard m.stops.indices.contains(m.fridayStop), m.S0 > 0 else { return nil }
        let st = m.stops[m.fridayStop], tt = st.tt, S0 = m.S0
        let pl = { (x: Double) in m.legs.reduce(0) { off.contains($1.id) ? $0 : $0 + m.legPL($1, x, tt) } }
        let xs = (0...120).map { S0 * (1 - 0.12 + 0.24 * Double($0) / 120) }
        let peak = m.shortAt(m.fridayStop, off: off)
        let g = m.greeks(S0, tt, off: off)
        let today = m.fridayStop == 0 && tt < 0.01
        let byT = today ? "today" : "by " + st.long.replacingOccurrences(of: " close", with: "")
        let top = Int(PE.jsRound(min(50, ((m.gridTop ?? S0 * 1.5) / S0 - 1) * 100)))
        return Payoff(xs: xs, ys: xs.map(pl), v0: pl(S0), byT: byT, dateLabel: st.short == "Today" ? "today" : st.short,
                      peak: peak, peakPast: peak.map { $0 <= S0 * 1.0005 } ?? false, top: top,
                      mv: m.v > 0 ? m.v * (max(tt, 1) / 365).squareRoot() : 0, d: g.d, th: g.th, g: g.g, vg: g.vg)
    }
}

// MARK: - The Price chart (sunny-chart's daily closes)

struct PosPrice {
    /// The past 3 months of closes (63 sessions) with today's price at the end.
    let pts: [Double]
    /// The change across them, a fraction.
    let chg: Double

    static func build(_ w: TickerWire, S0: Double, today: String) -> PosPrice? {
        var pairs = Array(zip(w.dates, w.closes)).filter { $0.1 > 0 }
        if let last = pairs.last, last.0 == today { pairs.removeLast() }
        var pts = pairs.suffix(63).map(\.1)
        if S0 > 0 { pts.append(S0) }
        guard pts.count >= 2, let f = pts.first, f > 0 else { return nil }
        return PosPrice(pts: pts, chg: pts[pts.count - 1] / f - 1)
    }
}

// MARK: - The name's daily closes for Price

@MainActor @Observable
final class PositionsCharts {
    static let shared = PositionsCharts()
    private(set) var charts: [String: TickerWire] = [:]
    private(set) var failed: Set<String> = []
    @ObservationIgnored private var fetchedAt: [String: Date] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []

    func chart(_ book: String, _ t: String) -> TickerWire? { charts["\(book)|\(t)"] }
    func hasFailed(_ book: String, _ t: String) -> Bool { failed.contains("\(book)|\(t)") }

    /// Asks sunny-chart for a name once every ten minutes at most (daily closes).
    func load(book: String, t: String) {
        let key = "\(book)|\(t)"
        guard !t.isEmpty, !inFlight.contains(key) else { return }
        if let at = fetchedAt[key], Date().timeIntervalSince(at) < 600, charts[key] != nil { return }
        inFlight.insert(key)
        Task {
            defer { inFlight.remove(key) }
            do {
                charts[key] = try await TickerChartClient.fetch(t: t, book: book)
                fetchedAt[key] = Date()
                failed.remove(key)
            } catch {
                if charts[key] == nil { failed.insert(key) }
            }
        }
    }
}

// MARK: - The memo (one model per input, never rebuilt in a body)

/// Holds the last model per input: a body re-run with the same build, reply and name is a lookup.
final class PositionsMemo {
    private var bookKey = "", bookV: PosBook?
    private var nameKey = "", nameV: PosName?
    private var priceKey = "", priceV: PosPrice?
    private var intelKey = "", intelV: PosIntel?

    func book(key: String, _ make: () -> PosBook) -> PosBook {
        if key == bookKey, let v = bookV { return v }
        let v = make(); bookKey = key; bookV = v; return v
    }
    func name(key: String, _ make: () -> PosName) -> PosName {
        if key == nameKey, let v = nameV { return v }
        let v = make(); nameKey = key; nameV = v; return v
    }
    func price(key: String, _ make: () -> PosPrice?) -> PosPrice? {
        if key == priceKey { return priceV }
        let v = make(); priceKey = key; priceV = v; return v
    }
    func intel(key: String, _ make: () -> PosIntel?) -> PosIntel? {
        if key == intelKey { return intelV }
        let v = make(); intelKey = key; intelV = v; return v
    }
}
