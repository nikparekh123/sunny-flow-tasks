//
//  PositionsModel.swift
//  Sunny
//
//  One name's position for the Positions tab (block 31): the legs (sold this week, shares, LEAPS, OTM calls,
//  insurance puts), the premium already earned, P&L and delta at any price and date with any legs switched off,
//  the date slider's stops, the price grid, where the name makes the most, the Greeks, the three fixes, the walls
//  by chain and the Technicals lines.
//
//  Two sources, one shape. Sample mode ports SunnyPositions.dc.html m45 (Black-Scholes on the phone). On the
//  real book (Pass 2) the server prices every leg on a price-by-date grid (sunny-positions, the one book engine)
//  and this model only adds up the legs that are switched on and reads between two grid prices (Nik, 6 Nov
//  2026: the maths runs on the server; the phone only adds the numbers up and draws them).
//

import Foundation

struct PositionsModel {
    struct Leg: Identifiable, Hashable {
        let id: String           // sample: s0, s1 (sold), sh (shares), l0...; live: the server's leg key
        let group: Character     // s sold, l long
        let ty: SampleEngine.Ty
        let K: Double
        let q: Double            // contracts (sold negative) or shares
        let T: Double            // calendar days to expiry from today
        let ex: String           // "Nov 13"
        let title: String
        let kind: SampleBook.Bought.Kind?
        /// Live: the grid a fix's leg reads (a sold leg's key, or "fix-otm"), and how many of it.
        var src: String? = nil
        var mult: Double = 1
    }
    /// A date slider stop: days on, short label, phrase, long label.
    struct Stop: Hashable { let tt: Double; let short: String; let phrase: String; let long: String; var friday: Bool { short.contains(" ") } }
    /// One chain's walls: Ceiling, Floor, Accelerator and Flip (the Walls layer and Walls by expiry).
    struct Chain: Hashable { let label: String; let kind: String; let days: Int; let trading: Int; let flip: Double?; let c: Double?; let f: Double?; let a: Double? }
    struct Holding { var value = 0.0; var today = 0.0 }
    /// sc and sp hold what the sold calls and puts would cost to buy back; timeSc and timeSp only their time value (an
    /// in the money sale's intrinsic part is not left to earn: Nik, 10 Nov 2026, Positions read $14.3K of puts where
    /// Home's Time value read $16.7K in all).
    typealias Holdings = (sh: Holding, lp: Holding, oc: Holding, ip: Holding, sc: Holding, sp: Holding, timeLeaps: Double, timeOtm: Double, shareGain: Double,
                          timeSc: Double, timeSp: Double)

    let t: String
    let company: String
    let S0: Double
    let P0: Double
    let v: Double
    let legs: [Leg]
    let earned: [String: Double]          // sold leg id → premium already earned (q × 100 × (at − now))
    /// The chart's prices: today's ±12% as it opens, or the zoom's range (`zoomed`).
    private(set) var X0: Double, X1: Double
    /// The pinch zoom's steps (SunnyPositions.dc.html Z45, Nov 8): the price range either side of today. It opens on
    /// ±12% (index 2) every time.
    static let zooms: [Double] = [0.05, 0.08, 0.12, 0.18, 0.25, 0.35, 0.5]
    static let fitZoom = 2
    /// This model with the chart on today's price ± r (the design's m45(t, zi)): the P&L scale, the grid it draws,
    /// the strikes, walls and turns-short price all follow X0 and X1.
    func zoomed(_ r: Double) -> PositionsModel {
        var c = self
        c.X0 = S0 * (1 - r); c.X1 = S0 * (1 + r)
        return c
    }
    /// The widest zoom step the prices cover: every step on the sample book (priced on the phone); live, as far as
    /// the server's grid reaches (±50% when it sent the wide grid, else ±12%).
    var widestZoom: Int {
        guard let g, let lo = g.S.first, let hi = g.S.last else { return Self.zooms.count - 1 }
        let r = min(S0 - lo, hi - S0) / S0 + 1e-4
        return Self.zooms.lastIndex { $0 <= r } ?? Self.fitZoom
    }
    /// One stop per trading day to the last sold expiry. On the weekend the week that ended folds away and the
    /// slider runs Monday to Friday of next week (answer 3).
    let stops: [Stop]
    /// No "Today" stop: the weekend, the slider is next week's.
    let weekend: Bool
    /// The sold legs that ended on Friday (the weekend), folded under `endedLabel`.
    let ended: [Leg]
    let endedLabel: String
    /// Live: how each ended leg ended, from the trade log (bought back, expired, assigned).
    let endedNotes: [String: String]
    var sd: Double { S0 * v * (5.0 / 252).squareRoot() }
    var strategy: String
    /// Sample: this week's sold legs as booked (sold at, now), for what is left to earn and what is kept.
    let sold: [SampleBook.Sold]
    let chains: [Chain]
    /// The 20-day average and the month's high and low (the Technicals layer).
    let technicals: (sma: Double?, hi: Double?, lo: Double?)
    let fridayStop: Int
    private let g: Grid?
    private let liveH: Holdings?

    // MARK: Sample (the design's book)

    init?(t: String, acct: String, weekend: Bool = false) {
        let book = SampleBook.book(acct)
        guard let b = book[t], let q = SampleBook.q[t] else { return nil }
        self.t = t; company = SampleBook.company[t] ?? t; S0 = q.0; P0 = q.1; v = SampleBook.iv[t] ?? 0.35; strategy = b.strategy; sold = b.sold
        X0 = S0 * 0.88; X1 = S0 * 1.12
        g = nil; liveH = nil; endedNotes = [:]; endedLabel = "Ended Oct 30 · settled"
        chains = SampleBook.expiries.enumerated().map { e, ex in
            let w = SampleBook.walls(t, e)
            return Chain(label: ex.label, kind: ex.kind, days: ex.days, trading: ex.trading, flip: w.flip, c: w.c?.k, f: w.f?.k, a: w.a?.k)
        }
        let series = Array(SampleSeries.series(t).suffix(22))
        technicals = series.count >= 20 ? (series.suffix(20).reduce(0, +) / 20, series.max(), series.min()) : (nil, nil, nil)
        func fk(_ k: Double) -> String { k.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(k)) : String(format: "%g", k) }
        var L: [Leg] = []
        var e: [String: Double] = [:]
        for (i, s) in b.sold.enumerated() {
            L.append(Leg(id: "s\(i)", group: "s", ty: s.put ? .put : .call, K: s.k, q: -Double(s.q), T: 3, ex: "Oct 30",
                         title: "\(s.put ? "Puts" : "Calls") \(fk(s.k)) ×\(s.q), Oct 30", kind: nil))
            e["s\(i)"] = Double(s.q) * 100 * (s.at - s.now)
        }
        let f = NumberFormatter(); f.numberStyle = .decimal
        L.append(Leg(id: "sh", group: "l", ty: .shares, K: b.avg, q: Double(b.shares), T: 0, ex: "",
                     title: "Shares \(f.string(from: NSNumber(value: b.shares)) ?? "") at $\(String(format: "%.2f", b.avg))", kind: nil))
        for (i, x) in b.bought.enumerated() {
            L.append(Leg(id: "l\(i)", group: "l", ty: x.put ? .put : .call, K: x.k, q: Double(x.q), T: Double(SampleBook.longDays[x.ex] ?? 300), ex: x.ex,
                         title: "\(x.kind.rawValue) \(fk(x.k)) ×\(x.q), \(x.ex)", kind: x.kind))
        }
        self.weekend = weekend
        if weekend {
            // Saturday: the Oct 30 legs are settled (their premium is in the books, not in P&L from now); the
            // long legs are 4 days nearer their expiry.
            ended = L.filter { $0.group == "s" }
            legs = L.filter { $0.group != "s" }.map { Leg(id: $0.id, group: $0.group, ty: $0.ty, K: $0.K, q: $0.q, T: $0.ty == .shares ? 0 : $0.T - 4, ex: $0.ex, title: $0.title, kind: $0.kind) }
            earned = [:]
            stops = [Stop(tt: 2, short: "Mon", phrase: "on Mon Nov 2", long: "Mon Nov 2"), Stop(tt: 3, short: "Tue", phrase: "on Tue Nov 3", long: "Tue Nov 3"),
                     Stop(tt: 4, short: "Wed", phrase: "on Wed Nov 4", long: "Wed Nov 4"), Stop(tt: 5, short: "Thu", phrase: "on Thu Nov 5", long: "Thu Nov 5"),
                     Stop(tt: 5.9, short: "Nov 6", phrase: "at the Nov 6 close", long: "Fri Nov 6 close")]
        } else {
            ended = []
            legs = L; earned = e
            stops = [
                Stop(tt: 0, short: "Today", phrase: "today", long: "Tue Oct 27"), Stop(tt: 1, short: "Wed", phrase: "on Wednesday", long: "Wed Oct 28"),
                Stop(tt: 2, short: "Thu", phrase: "on Thursday", long: "Thu Oct 29"), Stop(tt: 2.9, short: "Oct 30", phrase: "at the Oct 30 close", long: "Fri Oct 30 close"),
                Stop(tt: 6, short: "Mon", phrase: "on Mon Nov 2", long: "Mon Nov 2"), Stop(tt: 7, short: "Tue", phrase: "on Tue Nov 3", long: "Tue Nov 3"),
                Stop(tt: 8, short: "Wed", phrase: "on Wed Nov 4", long: "Wed Nov 4"), Stop(tt: 9, short: "Thu", phrase: "on Thu Nov 5", long: "Thu Nov 5"),
                Stop(tt: 9.9, short: "Nov 6", phrase: "at the Nov 6 close", long: "Fri Nov 6 close")]
        }
        fridayStop = stops.firstIndex { $0.friday } ?? 0
    }

    // MARK: Live (the server's grid, sunny-positions)

    /// `name` is the book's entry for this name in Home's brief (company, strategy, holdings, share gain).
    init(wire w: PositionsWire, name: JSONValue) {
        t = w.t; company = name["name"].string ?? w.t; S0 = w.S0; P0 = w.P0; v = w.iv; strategy = name["strategy"].string ?? ""; sold = []
        X0 = w.X0; X1 = w.X1
        stops = w.stops.map { Stop(tt: $0.tt, short: $0.short, phrase: $0.phrase, long: $0.long) }
        weekend = (w.stops.first?.tt ?? 0) > 0
        fridayStop = min(max(0, w.fridayStop), max(0, w.stops.count - 1))
        var grid = Grid(S: w.S, tts: w.stops.map(\.tt), turnsShort: w.turnsShort)
        var L: [Leg] = [], e: [String: Double] = [:]
        for l in w.legs {
            let ty: SampleEngine.Ty = l.ty == "S" ? .shares : l.ty == "P" ? .put : .call
            let kind: SampleBook.Bought.Kind? = l.kind == "leaps" ? .leaps : l.kind == "otm" ? .otm : l.kind == "ins" ? .ins : nil
            L.append(Leg(id: l.k, group: l.q < 0 && ty != .shares ? "s" : "l", ty: ty, K: l.K, q: l.q, T: l.days,
                         ex: Self.md(l.ex), title: l.label, kind: kind))
            if l.earned != 0 { e[l.k] = l.earned }
            grid.pl[l.k] = l.pl; grid.d[l.k] = l.d; grid.th[l.k] = l.th; grid.vg[l.k] = l.vg; grid.now[l.k] = l.value
            if let p0 = l.pl0 { grid.pl0[l.k] = p0 }
        }
        // Sold first (this week's calls, then puts), then shares and the long legs, as the design lists them.
        legs = L.filter { $0.group == "s" }.sorted { ($0.T, $0.ty == .put ? 1 : 0, $0.K) < ($1.T, $1.ty == .put ? 1 : 0, $1.K) }
            + L.filter { $0.group == "l" }.sorted { ($0.ty == .shares ? 0 : 1, $0.T, $0.K) < ($1.ty == .shares ? 0 : 1, $1.T, $1.K) }
        earned = e
        if let o = w.fix.otm { grid.otm = .init(K: o.K, ex: o.ex, days: o.days, label: o.label, cost: o.cost, pl: o.pl, d: o.d) }
        g = grid
        chains = w.walls.map { Chain(label: $0.label, kind: $0.kind, days: $0.days, trading: $0.trading, flip: $0.flip, c: $0.c?.k, f: $0.f?.k, a: $0.a?.k) }
        technicals = (w.tech?.sma20, w.tech?.hi, w.tech?.lo)
        let eday = w.endedDay.map(Self.md) ?? ""
        ended = w.ended.map { Leg(id: $0.k, group: "s", ty: $0.put ? .put : .call, K: $0.K, q: -$0.q, T: 0, ex: eday, title: $0.label, kind: nil) }
        endedNotes = Dictionary(w.ended.map { ($0.k, $0.note) }, uniquingKeysWith: { a, _ in a })
        endedLabel = "Ended \(eday) · settled"
        liveH = Self.holdings(json: name)
    }

    /// One name's holdings from Home's brief (book-engine.ts holdings(): [value, today] per group; sold calls and
    /// puts [left to earn, kept]; the time value in each; the shares' gain on cost).
    static func holdings(json n: JSONValue) -> Holdings {
        let h = n["h"]
        func p(_ k: String) -> Holding { Holding(value: h[k][0].double ?? 0, today: h[k][1].double ?? 0) }
        return (p("sh"), p("lp"), p("oc"), p("ip"), p("sc"), p("sp"), h["tv"]["lp"].double ?? 0, h["tv"]["oc"].double ?? 0, n["gain"].double ?? 0,
                h["tv"]["sc"].double ?? 0, h["tv"]["sp"].double ?? 0)
    }

    private static let MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    /// "2026-11-13" → "Nov 13".
    static func md(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return iso }
        return "\(MON[p[1] - 1]) \(p[2])"
    }

    // MARK: The grid (live)

    private struct Grid {
        struct Otm { let K: Double; let ex: String; let days: Double; let label: String; let cost: Double; let pl: [[Double]]; let d: [[Double]] }
        let S: [Double]
        let tts: [Double]
        var turnsShort: [Double?]
        var pl: [String: [[Double]]] = [:], d: [String: [[Double]]] = [:], th: [String: [[Double]]] = [:], vg: [String: [[Double]]] = [:]
        var pl0: [String: [Double]] = [:]
        var now: [String: Double] = [:]
        var otm: Otm?
        init(S: [Double], tts: [Double], turnsShort: [Double?]) { self.S = S; self.tts = tts; self.turnsShort = turnsShort }

        /// The stop a date is (the slider only ever asks for its own stops, or now).
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
        /// A leg's row on a grid: its own, a sold leg's (a fix buying it back), or the fix's OTM call.
        func rows(_ key: String, _ m: KeyPath<Grid, [String: [[Double]]]>, otm o: KeyPath<Otm, [[Double]]>?) -> [[Double]]? {
            if key == "fix-otm" { return o.flatMap { otm?[keyPath: $0] } }
            return self[keyPath: m][key]
        }
    }

    // MARK: Valuation

    func value(_ l: Leg, _ S: Double, _ tt: Double, vol: Double? = nil) -> Double {
        l.ty == .shares ? l.q * S : l.q * 100 * SampleEngine.bs(S, l.K, max(0, l.T - tt) / 365, vol ?? v, put: l.ty == .put)
    }
    func legPL(_ l: Leg, _ S: Double, _ tt: Double) -> Double {
        guard let g else { return value(l, S, tt) - value(l, S0, 0) }
        if l.ty == .shares { return l.q * (S - S0) }
        let key = l.src ?? l.id
        if let r = g.row(tt) {
            guard let a = g.rows(key, \.pl, otm: \.pl), r < a.count else { return 0 }
            return g.at(a[r], S) * l.mult
        }
        if let a = g.pl0[key] { return g.at(a, S) * l.mult }
        return 0
    }
    func legDelta(_ l: Leg, _ S: Double, _ tt: Double) -> Double {
        guard let g else { return l.ty == .shares ? l.q : l.q * 100 * SampleEngine.delta(S, l.K, max(0, l.T - tt) / 365, v, put: l.ty == .put) }
        if l.ty == .shares { return l.q }
        let key = l.src ?? l.id
        if let r = g.row(tt) {
            guard let a = g.rows(key, \.d, otm: \.d), r < a.count else { return 0 }
            return g.at(a[r], S) * l.mult
        }
        if let a = g.pl0[key] { return (g.at(a, S * 1.002) - g.at(a, S * 0.998)) / (S * 0.004) * l.mult }
        return 0
    }
    /// P&L from today plus the premium already earned on the sold legs that are on; extra = a fix's legs.
    func pl(_ S: Double, _ tt: Double, off: Set<String> = [], extra: [Leg] = []) -> Double {
        let on = legs.filter { !off.contains($0.id) } + extra
        return on.reduce(0) { $0 + legPL($1, S, tt) } + earned.filter { !off.contains($0.key) }.values.reduce(0, +)
    }
    func delta(_ S: Double, _ tt: Double, off: Set<String> = [], extra: [Leg] = []) -> Double {
        (legs.filter { !off.contains($0.id) } + extra).reduce(0) { $0 + legDelta($1, S, tt) }
    }
    /// Where the name makes the most on that date: the first price above today where delta drops below zero
    /// (today's price when it already has). Live with every leg on, the server's price to the cent, the one Home
    /// says; with a leg off, read off the grid. Searched to 5% past the chart's right edge (m45's flip), so it
    /// follows the zoom: none when the chart's range ends well before it.
    func flip(_ tt: Double, off: Set<String> = []) -> Double? {
        guard let g else {
            var pos = false
            for i in 0...400 {
                let S = X0 + (X1 * 1.05 - X0) * Double(i) / 400, d = delta(S, tt, off: off)
                if d > 0 { pos = true } else if pos { return S }
            }
            return nil
        }
        if off.isEmpty, let r = g.row(tt), r < g.turnsShort.count { return g.turnsShort[r].flatMap { $0 <= X1 * 1.05 ? $0 : nil } }
        var px = S0, pd = delta(S0, tt, off: off)
        if pd < 0 { return S0 }
        for x in g.S where x > S0 && x <= X1 * 1.05 {
            let d = delta(x, tt, off: off)
            if d < 0 { return ((px + (x - px) * pd / (pd - d)) * 100).rounded(.up) / 100 }
            px = x; pd = d
        }
        return nil
    }
    /// Delta, gamma (±0.2%), theta ($ a day) and vega ($ a vol point).
    func greeks(_ S: Double, _ tt: Double, off: Set<String> = []) -> (d: Double, g: Double, th: Double, vg: Double) {
        let d = delta(S, tt, off: off)
        let gm = (delta(S * 1.002, tt, off: off) - delta(S * 0.998, tt, off: off)) / (S * 0.004)
        guard let g else {
            let th = (pl(S, tt + 0.05, off: off) - pl(S, tt, off: off)) / 0.05
            let vg = legs.filter { !off.contains($0.id) && $0.ty != .shares }.reduce(0) { $0 + value($1, S, tt, vol: v + 0.01) - value($1, S, tt) }
            return (d, gm, th, vg)
        }
        guard let r = g.row(tt) else { return (d, gm, 0, 0) }
        var th = 0.0, vg = 0.0
        for l in legs where !off.contains(l.id) {
            if let a = g.th[l.id], r < a.count { th += g.at(a[r], S) }
            if let a = g.vg[l.id], r < a.count { vg += g.at(a[r], S) }
        }
        return (d, gm, th, vg)
    }
    /// The price grid and the P&L scale across every stop, as the chart draws it: the server's prices inside the
    /// chart's range with both ends read between them (live), or 141 across it (the design's GR).
    var grid: [Double] {
        guard let g else { return (0...140).map { X0 + (X1 - X0) * Double($0) / 140 } }
        let e = (X1 - X0) * 1e-4
        return [X0] + g.S.filter { $0 > X0 + e && $0 < X1 - e } + [X1]
    }
    func scale(off: Set<String>) -> (mn: Double, mx: Double) {
        var mn = 0.0, mx = 0.0
        let xs = grid
        for s in stops { for S in xs { let p = pl(S, s.tt, off: off); mn = min(mn, p); mx = max(mx, p) } }
        return (mn * 1.1 == 0 ? -1 : mn * 1.1, mx * 1.12 == 0 ? 1 : mx * 1.12)
    }
    /// Past its best at its priced move by Friday: the logo strip's orange dot (the same test as Home).
    var shortByFriday: Bool { stops.indices.contains(fridayStop) && delta(S0 + sd, stops[fridayStop].tt) < 0 }

    // MARK: Fixes (only when short at the price and date)

    struct Fix: Identifiable { let id: String; let title: String; let cost: Double; let act: String; let extra: [Leg] }
    func fixes(_ S: Double, _ tt: Double, off: Set<String>) -> [Fix] {
        let need = max(0, -delta(S, tt, off: off))
        guard need > 0 else { return [] }
        func fk(_ k: Double) -> String { String(format: "%g", k) }
        var out: [Fix] = []
        // Release: buy back the sold call that hurts most, enough to reach zero, capped at what was sold.
        let worst = legs.filter { $0.q < 0 && $0.ty == .call && !off.contains($0.id) && legPL($0, S, tt) < 0 }
            .min { legPL($0, S, tt) < legPL($1, S, tt) }
        if let g {
            if let w = worst {
                let per = max(0.01, legDelta(w, S, tt) / (w.q * 100))
                let k0 = min(-w.q, ceil(need / (100 * per)))
                let nowPer = abs(g.now[w.id] ?? 0) / (abs(w.q) * 100)
                out.append(Fix(id: "rel", title: "Release", cost: k0 * 100 * nowPer, act: "Buy back \(Int(k0)) of the \(Int(-w.q)) \(fk(w.K)) calls, \(w.ex)",
                               extra: [Leg(id: "x", group: "l", ty: .call, K: w.K, q: k0, T: w.T, ex: w.ex, title: "", kind: nil, src: w.id, mult: k0 / w.q)]))
            }
            if let o = g.otm, let r = g.row(tt), r < o.d.count {
                let on = ceil(need / max(5, g.at(o.d[r], S)))
                out.append(Fix(id: "otm", title: "OTM calls", cost: on * o.cost,
                               act: "Buy \(Int(on)) \(o.label) \(fk(o.K)) calls, about 7.5% out. Their delta grows as \(t) rises, like the sold calls’",
                               extra: [Leg(id: "x", group: "l", ty: .call, K: o.K, q: on, T: o.days, ex: o.label, title: "", kind: nil, src: "fix-otm", mult: on)]))
            }
        } else {
            let now = { (K: Double, T: Double, put: Bool) in SampleEngine.bs(S0, K, T / 365, v, put: put) }
            if let w = worst {
                let pc = max(0.01, SampleEngine.delta(S, w.K, max(0, w.T - tt) / 365, v, put: false))
                let k0 = min(-w.q, ceil(need / (100 * pc)))
                out.append(Fix(id: "rel", title: "Release", cost: k0 * 100 * now(w.K, w.T, false),
                               act: "Buy back \(Int(k0)) of the \(Int(-w.q)) \(fk(w.K)) calls, \(w.ex)",
                               extra: [Leg(id: "x", group: "l", ty: .call, K: w.K, q: k0, T: w.T, ex: w.ex, title: "", kind: nil)]))
            }
            let step = S0 < 50 ? 0.5 : S0 < 200 ? 1 : 5, oK = (S0 * 1.075 / step).rounded() * step
            let on = ceil(need / (100 * max(0.05, SampleEngine.delta(S, oK, (325 - tt) / 365, v, put: false))))
            out.append(Fix(id: "otm", title: "OTM calls", cost: on * 100 * now(oK, 325, false),
                           act: "Buy \(Int(on)) Sep ’27 \(fk(oK)) calls, about 7.5% out. Their delta grows as \(t) rises, like the sold calls’",
                           extra: [Leg(id: "x", group: "l", ty: .call, K: oK, q: on, T: 325, ex: "Sep ’27", title: "", kind: nil)]))
        }
        let sn = ceil(need / 100) * 100
        out.append(Fix(id: "sh", title: "Shares", cost: sn * S0,
                       act: "Buy \(Int(sn)) shares at $\(String(format: "%.2f", S0)). No decay, \(Int(sn / 100)) more calls to sell",
                       extra: [Leg(id: "x", group: "l", ty: .shares, K: S0, q: sn, T: 0, ex: "", title: "", kind: nil)]))
        return out
    }

    // MARK: What you hold (Book totals and the whole-name book)

    /// Shares, LEAPS, OTM calls and insurance puts: value and today's change; sold calls and puts: left and kept.
    func holdings() -> Holdings {
        if let liveH { return liveH }
        var sh = Holding(), lp = Holding(), oc = Holding(), ip = Holding(), sc = Holding(), sp = Holding()
        var tl = 0.0, to = 0.0, gain = 0.0, tsc = 0.0, tsp = 0.0
        let mv = S0 - P0
        for l in legs {
            switch l.ty {
            case .shares:
                sh.value += l.q * S0; sh.today += l.q * mv; gain += l.q * (S0 - l.K)
            default:
                if l.q < 0 {
                    let i = Int(l.id.dropFirst()) ?? 0
                    if sold.indices.contains(i) {
                        let s = sold[i]
                        if l.ty == .call {
                            sc.value += Double(s.q) * 100 * s.now; sc.today += Double(s.q) * 100 * (s.at - s.now)
                            tsc += Double(s.q) * 100 * max(0, s.now - max(0, S0 - s.k))
                        } else {
                            sp.value += Double(s.q) * 100 * s.now; sp.today += Double(s.q) * 100 * (s.at - s.now)
                            tsp += Double(s.q) * 100 * max(0, s.now - max(0, s.k - S0))
                        }
                    }
                } else {
                    let val = l.q * 100 * SampleEngine.bs(S0, l.K, l.T / 365, v, put: l.ty == .put)
                    let tday = legDelta(l, S0, 0) * mv
                    let intrinsic = l.q * 100 * (l.ty == .put ? max(0, l.K - S0) : max(0, S0 - l.K))
                    if l.ty == .put { ip.value += val; ip.today += tday }
                    else if l.T > 400 { lp.value += val; lp.today += tday; tl += val - intrinsic }
                    else { oc.value += val; oc.today += tday; to += val - intrinsic }
                }
            }
        }
        return (sh, lp, oc, ip, sc, sp, tl, to, gain, tsc, tsp)
    }
}
