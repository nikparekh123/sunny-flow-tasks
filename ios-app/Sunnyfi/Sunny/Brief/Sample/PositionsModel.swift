//
//  PositionsModel.swift
//  Sunny
//
//  One name's grid for the Positions tab (handoff 2026-11-13-positions, App Explorations 154a): the legs, the date
//  stops, and each leg's P&L, delta, theta and vega on the server's price-by-date grid (sunny-positions, the one book
//  engine). This model only adds up the legs and reads between two grid prices (Nik, 6 Nov 2026: the maths runs on the
//  server; the phone adds the numbers up and draws them), exactly as the web's src/web/positions/model.ts Pricer does.
//  Trimmed on 13 Nov 2026 to what the new tab reads (the payoff at this Friday's close, the Greeks, each leg's delta);
//  the sample book, the zoom, the fixes and the walls by chain went with the old screen.
//

import Foundation

struct PositionsModel {
    struct Leg: Identifiable, Hashable {
        let id: String           // the server's leg key
        let ty: SampleEngine.Ty
        let K: Double
        let q: Double            // contracts (sold negative) or shares
        let T: Double            // calendar days to expiry from the grid's pricing time
        let ex: String           // "Nov 13"
        let title: String        // the server's label ("Calls 40.5 ×50, Nov 20")
        /// The expiry as the server sends it ("2026-11-13"); "" for shares.
        var iso: String = ""
    }
    /// A date stop: days on, short label, phrase, long label.
    struct Stop: Hashable { let tt: Double; let short: String; let phrase: String; let long: String; var friday: Bool { short.contains(" ") } }
    struct Holding { var value = 0.0; var today = 0.0 }
    /// sc and sp hold what the sold calls and puts would cost to buy back; timeSc and timeSp only their time value.
    typealias Holdings = (sh: Holding, lp: Holding, oc: Holding, ip: Holding, sc: Holding, sp: Holding, timeLeaps: Double, timeOtm: Double, shareGain: Double,
                          timeSc: Double, timeSp: Double, timeIp: Double, paid: Paid)
    /// What was paid for each group (Nik, 11 Nov 2026): the cost of the shares and of what was bought, the premium
    /// taken in for what was sold. book-engine.ts holdings().paid, from Home's brief.
    struct Paid { var sh = 0.0, lp = 0.0, oc = 0.0, ip = 0.0, sc = 0.0, sp = 0.0 }

    let t: String
    let company: String
    let S0: Double
    let P0: Double
    /// The name's IV (the priced move).
    let v: Double
    let legs: [Leg]
    let stops: [Stop]
    let fridayStop: Int
    var strategy: String
    private let g: Grid

    /// `name` is the book's entry for this name in Home's brief (company, strategy).
    init(wire w: PositionsWire, name: JSONValue) {
        t = w.t; company = name["name"].string ?? w.t; S0 = w.S0; P0 = w.P0; v = w.iv; strategy = name["strategy"].string ?? ""
        stops = w.stops.map { Stop(tt: $0.tt, short: $0.short, phrase: $0.phrase, long: $0.long) }
        fridayStop = min(max(0, w.fridayStop), max(0, w.stops.count - 1))
        var grid = Grid(S: w.S, tts: w.stops.map(\.tt), turnsShort: w.turnsShort)
        var L: [Leg] = []
        for l in w.legs {
            let ty: SampleEngine.Ty = l.ty == "S" ? .shares : l.ty == "P" ? .put : .call
            L.append(Leg(id: l.k, ty: ty, K: l.K, q: l.q, T: l.days, ex: Self.md(l.ex), title: l.label, iso: ty == .shares ? "" : l.ex))
            grid.pl[l.k] = l.pl; grid.d[l.k] = l.d; grid.th[l.k] = l.th; grid.vg[l.k] = l.vg
            if let p0 = l.pl0 { grid.pl0[l.k] = p0 }
        }
        legs = L
        g = grid
    }

    /// One name's holdings from Home's brief (book-engine.ts holdings(): [value, today] per group; the time value in
    /// each; the shares' gain on cost; what was paid).
    static func holdings(json n: JSONValue) -> Holdings {
        let h = n["h"]
        func p(_ k: String) -> Holding { Holding(value: h[k][0].double ?? 0, today: h[k][1].double ?? 0) }
        let pd = h["paid"]
        let paid = Paid(sh: pd["sh"].double ?? 0, lp: pd["lp"].double ?? 0, oc: pd["oc"].double ?? 0, ip: pd["ip"].double ?? 0,
                        sc: pd["sc"].double ?? 0, sp: pd["sp"].double ?? 0)
        return (p("sh"), p("lp"), p("oc"), p("ip"), p("sc"), p("sp"), h["tv"]["lp"].double ?? 0, h["tv"]["oc"].double ?? 0, n["gain"].double ?? 0,
                h["tv"]["sc"].double ?? 0, h["tv"]["sp"].double ?? 0, h["tv"]["ip"].double ?? 0, paid)
    }

    private static let MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    /// "2026-11-13" → "Nov 13".
    static func md(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return iso }
        return "\(MON[p[1] - 1]) \(p[2])"
    }

    // MARK: The grid

    private struct Grid {
        let S: [Double]
        let tts: [Double]
        let turnsShort: [Double?]
        var pl: [String: [[Double]]] = [:], d: [String: [[Double]]] = [:], th: [String: [[Double]]] = [:], vg: [String: [[Double]]] = [:]
        var pl0: [String: [Double]] = [:]
        init(S: [Double], tts: [Double], turnsShort: [Double?]) { self.S = S; self.tts = tts; self.turnsShort = turnsShort }

        /// The stop a date is (only the grid's own stops, or now, are asked for).
        func row(_ tt: Double) -> Int? { tts.firstIndex { abs($0 - tt) < 1e-4 } }
        /// A value between two grid prices, read on the straight line between them (held at the ends). The wide grid
        /// is not evenly spaced (0.24% steps inside ±12%, then 0.5% and 1%), so the two prices are found by halving.
        func at(_ a: [Double], _ x: Double) -> Double {
            guard a.count == S.count, S.count > 1, let lo = S.first, let hi = S.last, hi > lo else { return a.first ?? 0 }
            if x <= lo { return a[0] }
            if x >= hi { return a[S.count - 1] }
            var i = 0, j = S.count - 1
            while j - i > 1 { let k = (i + j) / 2; if S[k] <= x { i = k } else { j = k } }
            let w = S[j] > S[i] ? (x - S[i]) / (S[j] - S[i]) : 0
            return a[i] + (a[j] - a[i]) * w
        }
    }

    // MARK: Valuation (the web's Pricer)

    /// A leg's P&L from today's mark at a price and date.
    func legPL(_ l: Leg, _ S: Double, _ tt: Double) -> Double {
        if l.ty == .shares { return l.q * (S - S0) }
        if let r = g.row(tt) {
            guard let a = g.pl[l.id], r < a.count else { return 0 }
            return g.at(a[r], S)
        }
        if let a = g.pl0[l.id] { return g.at(a, S) }
        return 0
    }
    /// A leg's delta in shares at a price and date.
    func legDelta(_ l: Leg, _ S: Double, _ tt: Double) -> Double {
        if l.ty == .shares { return l.q }
        if let r = g.row(tt) {
            guard let a = g.d[l.id], r < a.count else { return 0 }
            return g.at(a[r], S)
        }
        if let a = g.pl0[l.id] { return (g.at(a, S * 1.002) - g.at(a, S * 0.998)) / (S * 0.004) }
        return 0
    }
    func delta(_ S: Double, _ tt: Double) -> Double { legs.reduce(0) { $0 + legDelta($1, S, tt) } }
    /// Delta, gamma (±0.2%), theta ($ a day) and vega ($ a vol point), every leg.
    func greeks(_ S: Double, _ tt: Double) -> (d: Double, g: Double, th: Double, vg: Double) {
        let d = delta(S, tt)
        let gm = (delta(S * 1.002, tt) - delta(S * 0.998, tt)) / (S * 0.004)
        guard let r = g.row(tt) else { return (d, gm, 0, 0) }
        var th = 0.0, vg = 0.0
        for l in legs {
            if let a = g.th[l.id], r < a.count { th += g.at(a[r], S) }
            if let a = g.vg[l.id], r < a.count { vg += g.at(a[r], S) }
        }
        return (d, gm, th, vg)
    }
    /// The server's turns-short price at a stop (every leg on), nil when none.
    func turnsShort(at i: Int) -> Double? { g.turnsShort.indices.contains(i) ? g.turnsShort[i] : nil }
    /// The top of the server's price grid (±50% on the wide grid).
    var gridTop: Double? { g.S.last }
}
