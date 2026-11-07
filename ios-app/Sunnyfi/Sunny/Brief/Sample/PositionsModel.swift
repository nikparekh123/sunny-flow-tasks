//
//  PositionsModel.swift
//  Sunny
//
//  One name's position for the Positions tab (block 31), ported from SunnyPositions.dc.html m45 for sample mode:
//  the legs (sold this week, shares, LEAPS, OTM calls, insurance puts), the premium already earned, P&L and delta
//  at any price and date with any legs switched off, the date slider's stops, the price grid, where the name turns
//  short, the Greeks, and the three fixes. From Pass 2 the server sends the same per-name model.
//

import Foundation

struct PositionsModel {
    struct Leg: Identifiable, Hashable {
        let id: String           // s0, s1 (sold), sh (shares), l0... (bought)
        let group: Character     // s sold, l long
        let ty: SampleEngine.Ty
        let K: Double
        let q: Double            // contracts (sold negative) or shares
        let T: Double            // calendar days to expiry from today
        let ex: String
        let title: String
        let kind: SampleBook.Bought.Kind?
    }
    /// A date slider stop: days on, short label, phrase, long label.
    struct Stop: Hashable { let tt: Double; let short: String; let phrase: String; let long: String; var friday: Bool { short.contains(" ") } }

    let t: String
    let S0: Double
    let P0: Double
    let v: Double
    let legs: [Leg]
    let earned: [String: Double]          // sold leg id → premium already earned (q × 100 × (at − now))
    let X0: Double, X1: Double
    /// One stop per trading day to the last sold expiry. On the weekend the week that ended folds away and the
    /// slider runs Mon Nov 2 to Fri Nov 6 (answer 3), counted from Saturday.
    let stops: [Stop]
    /// The weekend: this week's sold legs ended Friday and sit under "Ended Oct 30 · settled".
    let weekend: Bool
    let ended: [Leg]
    var sd: Double { S0 * v * (5.0 / 252).squareRoot() }
    var strategy: String
    /// This week's sold legs as booked (sold at, now), for what is left to earn and what is kept.
    let sold: [SampleBook.Sold]

    init?(t: String, acct: String, weekend: Bool = false) {
        let book = SampleBook.book(acct)
        guard let b = book[t], let q = SampleBook.q[t] else { return nil }
        self.t = t; S0 = q.0; P0 = q.1; v = SampleBook.iv[t] ?? 0.35; strategy = b.strategy; sold = b.sold
        X0 = S0 * 0.88; X1 = S0 * 1.12
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
    }

    /// The 20-day average and the month's high and low (the Technicals layer), from the sample's price series.
    var technicals: (sma: Double?, hi: Double?, lo: Double?) {
        let v = Array(SampleSeries.series(t).suffix(22))
        guard v.count >= 20 else { return (nil, nil, nil) }
        return (v.suffix(20).reduce(0, +) / 20, v.max(), v.min())
    }

    // MARK: Valuation (the prototype's: no rate, one IV per name)

    func value(_ l: Leg, _ S: Double, _ tt: Double, vol: Double? = nil) -> Double {
        l.ty == .shares ? l.q * S : l.q * 100 * SampleEngine.bs(S, l.K, max(0, l.T - tt) / 365, vol ?? v, put: l.ty == .put)
    }
    func legPL(_ l: Leg, _ S: Double, _ tt: Double) -> Double { value(l, S, tt) - value(l, S0, 0) }
    func legDelta(_ l: Leg, _ S: Double, _ tt: Double) -> Double {
        l.ty == .shares ? l.q : l.q * 100 * SampleEngine.delta(S, l.K, max(0, l.T - tt) / 365, v, put: l.ty == .put)
    }
    /// P&L from today plus the premium already earned on the sold legs that are on; extra = a fix's legs.
    func pl(_ S: Double, _ tt: Double, off: Set<String> = [], extra: [Leg] = []) -> Double {
        let on = legs.filter { !off.contains($0.id) } + extra
        return on.reduce(0) { $0 + legPL($1, S, tt) } + earned.filter { !off.contains($0.key) }.values.reduce(0, +)
    }
    func delta(_ S: Double, _ tt: Double, off: Set<String> = [], extra: [Leg] = []) -> Double {
        (legs.filter { !off.contains($0.id) } + extra).reduce(0) { $0 + legDelta($1, S, tt) }
    }
    /// The first price above today where delta drops below zero on that date (400 steps across the chart).
    func flip(_ tt: Double, off: Set<String> = []) -> Double? {
        var pos = false
        for i in 0...400 {
            let S = X0 + (X1 * 1.05 - X0) * Double(i) / 400, d = delta(S, tt, off: off)
            if d > 0 { pos = true } else if pos { return S }
        }
        return nil
    }
    /// Delta, gamma (±0.2%), theta (P&L over .05 day, per day) and vega (per IV point).
    func greeks(_ S: Double, _ tt: Double, off: Set<String> = []) -> (d: Double, g: Double, th: Double, vg: Double) {
        let d = delta(S, tt, off: off)
        let g = (delta(S * 1.002, tt, off: off) - delta(S * 0.998, tt, off: off)) / (S * 0.004)
        let th = (pl(S, tt + 0.05, off: off) - pl(S, tt, off: off)) / 0.05
        let vg = legs.filter { !off.contains($0.id) && $0.ty != .shares }.reduce(0) { $0 + value($1, S, tt, vol: v + 0.01) - value($1, S, tt) }
        return (d, g, th, vg)
    }
    /// The price grid (141 points) and the P&L scale across every stop, as the chart draws it.
    var grid: [Double] { (0...140).map { X0 + (X1 - X0) * Double($0) / 140 } }
    func scale(off: Set<String>) -> (mn: Double, mx: Double) {
        var mn = 0.0, mx = 0.0
        for s in stops { for S in grid { let p = pl(S, s.tt, off: off); mn = min(mn, p); mx = max(mx, p) } }
        return (mn * 1.1 == 0 ? -1 : mn * 1.1, mx * 1.12 == 0 ? 1 : mx * 1.12)
    }
    /// Short at its priced move by Friday: the logo strip's orange dot (the same test as Home).
    var shortByFriday: Bool { delta(S0 + sd, weekend ? 5.9 : 2.9) < 0 }
    var fridayStop: Int { stops.firstIndex { $0.short.contains(" ") } ?? 0 }

    // MARK: Fixes (only when short at the price and date)

    struct Fix: Identifiable { let id: String; let title: String; let cost: Double; let act: String; let extra: [Leg] }
    func fixes(_ S: Double, _ tt: Double, off: Set<String>) -> [Fix] {
        let need = max(0, -delta(S, tt, off: off))
        guard need > 0 else { return [] }
        var out: [Fix] = []
        let now = { (K: Double, T: Double, put: Bool) in SampleEngine.bs(S0, K, T / 365, v, put: put) }
        // Release: buy back the sold call that hurts most, enough to reach zero, capped at what was sold.
        if let worst = legs.filter({ $0.q < 0 && $0.ty == .call && !off.contains($0.id) && legPL($0, S, tt) < 0 })
            .min(by: { legPL($0, S, tt) < legPL($1, S, tt) }) {
            let pc = max(0.01, SampleEngine.delta(S, worst.K, max(0, worst.T - tt) / 365, v, put: false))
            let k0 = min(-worst.q, ceil(need / (100 * pc)))
            out.append(Fix(id: "rel", title: "Release", cost: k0 * 100 * now(worst.K, worst.T, false),
                           act: "Buy back \(Int(k0)) of the \(Int(-worst.q)) \(String(format: "%g", worst.K)) calls, \(worst.ex)",
                           extra: [Leg(id: "x", group: "l", ty: .call, K: worst.K, q: k0, T: worst.T, ex: worst.ex, title: "", kind: nil)]))
        }
        let step = S0 < 50 ? 0.5 : S0 < 200 ? 1 : 5, oK = (S0 * 1.075 / step).rounded() * step
        let on = ceil(need / (100 * max(0.05, SampleEngine.delta(S, oK, (325 - tt) / 365, v, put: false))))
        out.append(Fix(id: "otm", title: "OTM calls", cost: on * 100 * now(oK, 325, false),
                       act: "Buy \(Int(on)) Sep ’27 \(String(format: "%g", oK)) calls, about 7.5% out. Their delta grows as \(t) rises, like the sold calls’",
                       extra: [Leg(id: "x", group: "l", ty: .call, K: oK, q: on, T: 325, ex: "Sep ’27", title: "", kind: nil)]))
        let sn = ceil(need / 100) * 100
        out.append(Fix(id: "sh", title: "Shares", cost: sn * S0,
                       act: "Buy \(Int(sn)) shares at $\(String(format: "%.2f", S0)). No decay, \(Int(sn / 100)) more calls to sell",
                       extra: [Leg(id: "x", group: "l", ty: .shares, K: S0, q: sn, T: 0, ex: "", title: "", kind: nil)]))
        return out
    }

    // MARK: What you hold (Book totals and the whole-name book)

    struct Holding { var value = 0.0; var today = 0.0 }
    /// Shares, LEAPS, OTM calls and insurance puts: value and today's change; sold calls and puts: left and kept.
    func holdings() -> (sh: Holding, lp: Holding, oc: Holding, ip: Holding, sc: Holding, sp: Holding, timeLeaps: Double, timeOtm: Double, shareGain: Double) {
        var sh = Holding(), lp = Holding(), oc = Holding(), ip = Holding(), sc = Holding(), sp = Holding()
        var tl = 0.0, to = 0.0, gain = 0.0
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
                        if l.ty == .call { sc.value += Double(s.q) * 100 * s.now; sc.today += Double(s.q) * 100 * (s.at - s.now) }
                        else { sp.value += Double(s.q) * 100 * s.now; sp.today += Double(s.q) * 100 * (s.at - s.now) }
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
        return (sh, lp, oc, ip, sc, sp, tl, to, gain)
    }
}
