//
//  PositionsMath.swift
//  Sunny
//
//  The arithmetic behind SunnyPositions (blocks 12 and 13), as the design
//  file works it: Black-Scholes at rate 0 with puts by parity, each contract
//  at the volatility backed out of its own mark (so Today equals live P/L),
//  payoff on any day up to expiry, breakevens where the payoff crosses
//  zero, and the flat chart's geometry (fixed scale across days).
//

import Foundation
import CoreGraphics

/// One position leg, ready to price.
struct PLeg: Identifiable, Hashable {
    let id: String
    let t: String            // ticker
    let k: Double            // strike
    let q: Int               // contracts
    let a: Double            // premium opened (sold) or paid (bought), per share
    let b: Double            // mark now, per share
    let days: Double         // calendar days from now to the 4:00 PM expiry close
    let expiry: String
    let sold: Bool
    let call: Bool
    let px: Double           // the ticker's price now
    let sg: Double           // volatility backed out of the mark

    var base: Double { a * 100 * Double(q) }
    var now: Double { b * 100 * Double(q) }
    /// $ captured when sold, $ gain when bought.
    var g: Double { (sold ? a - b : b - a) * 100 * Double(q) }
    var pct: Double { base > 0 ? g / base * 100 : 0 }
    var intrinsic: Double { call ? max(0, px - k) : max(0, k - px) }
    var tv: Double { max(0, b - intrinsic) * 100 * Double(q) }
}

enum PMath {
    /// Abramowitz-Stegun normal CDF, as the design file.
    static func nd(_ x: Double) -> Double {
        let t = 1 / (1 + 0.2316419 * abs(x)), d = 0.3989423 * exp(-x * x / 2)
        let p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))))
        return x > 0 ? 1 - p : p
    }
    /// Call value, rate 0.
    static func bs(_ S: Double, _ K: Double, _ tau: Double, _ sg: Double) -> Double {
        if tau <= 0 { return max(0, S - K) }
        let v = sg * sqrt(tau), d1 = (log(S / K) + v * v / 2) / v
        return S * nd(d1) - K * nd(d1 - v)
    }
    /// Volatility that prices the call at `b` (bisection, 5% floor).
    static func iv(_ px: Double, _ k: Double, _ tau: Double, _ b: Double) -> Double {
        if b <= max(0, px - k) + 1e-4 || tau <= 0 { return 0.05 }
        var lo = 0.01, hi = 5.0
        for _ in 0..<60 { let md = (lo + hi) / 2; if bs(px, k, tau, md) > b { hi = md } else { lo = md } }
        return (lo + hi) / 2
    }
    /// A leg's value per share at price S, `el` days from now.
    static func pv(_ l: PLeg, _ S: Double, _ el: Double) -> Double {
        let tau = max(0, l.days - el) / 365
        let cv = bs(S, l.k, tau, l.sg)
        return l.call ? cv : max(0, cv - S + l.k)
    }
    /// P/L of legs at price S, `el` days from now.
    static func pl(_ L: [PLeg], _ S: Double, _ el: Double) -> Double {
        L.reduce(0) { x, l in let V = pv(l, S, el); return x + (l.sold ? l.a - V : V - l.a) * 100 * Double(l.q) }
    }
    /// Signed value (sold legs negative).
    static func value(_ L: [PLeg], _ S: Double, _ el: Double) -> Double {
        L.reduce(0) { $0 + pv($1, S, el) * 100 * Double($1.q) * ($1.sold ? -1 : 1) }
    }
    /// Delta in shares, negative when sold.
    static func delta(_ l: PLeg, _ S: Double, _ el: Double) -> Double {
        let tau = max(0, l.days - el) / 365
        var d: Double
        if tau <= 0 { d = S > l.k ? 1 : 0 } else {
            let v = l.sg * sqrt(tau); d = nd((log(S / l.k) + v * v / 2) / v)
        }
        if !l.call { d -= 1 }
        return d * 100 * Double(l.q) * (l.sold ? -1 : 1)
    }
    /// Breakeven at expiry for sold calls (above) and sold puts (below).
    static func beShortCalls(_ L: [PLeg]) -> Double {
        let minK = L.map(\.k).min()!, maxK = L.map(\.k).max()!
        let cr = L.reduce(0) { $0 + $1.base }, q = Double(L.reduce(0) { $0 + $1.q })
        var lo = minK, hi = maxK + cr / (100 * q) + 1
        let at = L.map(\.days).max() ?? 0
        for _ in 0..<50 { let md = (lo + hi) / 2; if pl(L, md, at) > 0 { lo = md } else { hi = md } }
        return (lo + hi) / 2
    }
    static func beShortPuts(_ L: [PLeg]) -> Double {
        let minK = L.map(\.k).min()!, maxK = L.map(\.k).max()!
        let cr = L.reduce(0) { $0 + $1.base }, q = Double(L.reduce(0) { $0 + $1.q })
        var lo = max(0.01, minK - cr / (100 * q) - 1), hi = maxK
        let at = L.map(\.days).max() ?? 0
        for _ in 0..<50 { let md = (lo + hi) / 2; if pl(L, md, at) > 0 { hi = md } else { lo = md } }
        return (lo + hi) / 2
    }

    /// Build priced legs from the payload. Spot: the ticker's live price.
    static func legs(_ home: HomePayload, now: Date = SClock.now()) -> [PLeg] {
        let spot = Dictionary(home.portfolio.compactMap { p in p.spot.map { (p.ticker, $0) } }, uniquingKeysWith: { a, _ in a })
        return home.legs.compactMap { l in
            guard let px = spot[l.ticker] ?? l.underlying, px > 0 else { return nil }
            let days = max(0, expiryClose(l.expiry).timeIntervalSince(now) / 86400)
            let b = l.mark ?? l.avg, call = l.type == "call"
            // Back the volatility out of the mark; a put through parity.
            let sg = iv(px, l.strike, days / 365, call ? b : b + px - l.strike)
            return PLeg(id: l.id, t: l.ticker, k: l.strike, q: l.n, a: l.avg, b: b, days: days, expiry: l.expiry,
                        sold: l.side == "sold", call: call, px: px, sg: sg)
        }
    }

    /// 4:00 PM New York on an expiry date.
    static func expiryClose(_ iso: String) -> Date { nyDate(iso, minutes: 16 * 60) }
    static func nyDate(_ iso: String, minutes: Int) -> Date {
        var c = DateComponents(); let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return Date() }
        c.year = p[0]; c.month = p[1]; c.day = p[2]; c.hour = minutes / 60; c.minute = minutes % 60
        var cal = Calendar(identifier: .gregorian); cal.timeZone = MarketClock.ny
        return cal.date(from: c) ?? Date()
    }
}

// MARK: - Money and % as Positions writes them

enum PF {
    /// $860 · $1.2K · $22K (no decimal from $10K), no sign.
    static func usd(_ v: Double) -> String {
        let x = abs(v)
        if x >= 10_000 { return "$\(Int((x / 1000).rounded()))K" }
        if x >= 1_000 { return "$" + F.trim(x / 1000) + "K" }
        return "$\(Int(x.rounded()))"
    }
    /// 1.2K · 860 (delta in shares), no sign.
    static func count(_ v: Double) -> String {
        let x = abs(v)
        if x >= 10_000 { return "\(Int((x / 1000).rounded()))K" }
        if x >= 1_000 { return F.trim(x / 1000) + "K" }
        return "\(Int(x.rounded()))"
    }
    /// 42.1% · 100%
    static func pct(_ v: Double) -> String {
        let x = abs(v)
        return x >= 99.95 ? "\(Int(x.rounded()))%" : String(format: "%.1f%%", x)
    }
    static func strike(_ k: Double) -> String { F.trim(k) == String(Int(k)) ? String(Int(k)) : String(k) }
}

// MARK: - The time strip

/// One stop on the time strip: `el` days from now.
struct TimeSlot: Hashable {
    let el: Double
    let date: String          // yyyy-MM-dd, New York
    let minutes: Int?         // minutes after midnight (sold strip), nil = now / a day
    let open: Bool
    let noon: Bool
}

enum TimeStrip {
    /// Sold: now, then every 15 minutes 9:30 to 4:00 on each trading day to
    /// the expiry close. Bought: now, then one a day to the expiry.
    static func slots(until expiry: String, long: Bool, calendar: [CalendarDay], now: Date = SClock.now()) -> [TimeSlot] {
        let t = MarketClock.ny(now)
        var out = [TimeSlot(el: 0, date: t.date, minutes: nil, open: false, noon: false)]
        let end = PMath.expiryClose(expiry)
        if long {
            // One stop a day, then the expiry itself as the last stop. Counting
            // days with ceil ran a partial day one past it (Jan 22 for a Jan 21 expiry).
            let full = max(0, end.timeIntervalSince(now) / 86400)
            var i = 1
            while true {
                let d = MarketClock.addDays(t.date, i).iso
                if d >= expiry {
                    out.append(TimeSlot(el: full, date: expiry, minutes: nil, open: false, noon: false))
                    return out
                }
                out.append(TimeSlot(el: Double(i), date: d, minutes: nil, open: false, noon: false))
                i += 1
            }
        }
        var day = t.date, wd = t.weekday
        while day <= expiry {
            if MarketClock.isTradingDay(day, weekday: wd, calendar) {
                let close = MarketClock.closeMinutes(day, calendar)
                var m = 9 * 60 + 30
                while m <= close {
                    let at = PMath.nyDate(day, minutes: m)
                    if at > now { out.append(TimeSlot(el: at.timeIntervalSince(now) / 86400, date: day, minutes: m,
                                                      open: m == 9 * 60 + 30, noon: m == 12 * 60)) }
                    m += 15
                }
            }
            let nx = MarketClock.addDays(day, 1); day = nx.iso; wd = nx.weekday
        }
        return out
    }
}

// MARK: - Flat chart geometry

struct PayoffChart {
    struct Seg { var pts: [CGPoint]; var loss: Bool }
    var posArea = [CGPoint](), negArea = [CGPoint]()
    var segs = [Seg]()
    var markers = [CGFloat]()             // x where the loss leaves the floor
    var zy: CGFloat = 0, nx: CGFloat = 0
    var be = [(x: CGFloat, price: Double, falling: Bool)]()
    var yTicks = [(y: CGFloat, v: Double)]()
    var xTicks = [(x: CGFloat, v: Double, step: Double)]()
    var strikes = [(x: CGFloat, label: String, center: CGFloat, id: String)]()
    var dot: (x: CGFloat, y: CGFloat, gain: Bool)?
    var plNow: Double = 0
}

enum PayoffGeom {
    static let T: CGFloat = 30, B: CGFloat = 152, H: CGFloat = 176

    /// The fixed y range across every stop, so moving the day never rescales.
    static func range(_ L: [PLeg], stops: [Double], lo: Double, hi: Double) -> (Double, Double) {
        var yMax = -Double.infinity, yMin = Double.infinity
        for e in stops { for i in 0...40 {
            let S = lo + (hi - lo) * Double(i) / 40, v = PMath.pl(L, S, e)
            yMax = max(yMax, v); yMin = min(yMin, v)
        } }
        return (yMax, yMin)
    }

    static func build(_ L: [PLeg], el: Double, lo: Double, hi: Double, yr: (Double, Double), W: CGFloat,
                      unbounded: Bool, label: (PLeg) -> String) -> PayoffChart {
        var c = PayoffChart()
        let (yMax, yMin) = yr
        var yHi: Double, yLo: Double
        if unbounded {
            let credit = L.filter(\.sold).reduce(0) { $0 + $1.base }
            let ref = max(abs(yMax), abs(PMath.pl(L, L[0].px, el)), credit, 1)
            yHi = max(yMax, 0.15 * ref) * 1.18
            yLo = max(yMin * 1.12, (yMax > 0 ? -1.05 : -2.2) * ref)
        } else {
            yHi = max(yMax, 0.15 * abs(min(yMin, 0)), 1) * 1.18
            yLo = min(yMin, -0.15 * yHi) * 1.12
        }
        let X = { (S: Double) -> CGFloat in CGFloat((S - lo) / (hi - lo)) * W }
        let Yr = { (v: Double) -> CGFloat in max(T - 2, T + CGFloat((yHi - v) / (yHi - yLo)) * (B - T)) }
        c.zy = Yr(0)
        let N = 110
        var out: [(CGPoint, Double)] = []
        var prev: Double?
        for i in 0...N {
            let S = lo + (hi - lo) * Double(i) / Double(N), v = PMath.pl(L, S, el)
            if let pv = prev, (pv > 0) != (v > 0), pv != v {
                let S0 = lo + (hi - lo) * Double(i - 1) / Double(N)
                let s = S0 + (S - S0) * (pv / (pv - v))
                out.append((CGPoint(x: X(s), y: c.zy), 0))
                c.be.append((X(s), s, pv > 0))
            }
            out.append((CGPoint(x: X(S), y: Yr(v)), v)); prev = v
        }
        // Lines: green above zero, red below, cut at the floor with a marker.
        var cur: PayoffChart.Seg?
        for i in 1..<out.count {
            var p = out[i - 1].0, q = out[i].0
            if p.y > B && q.y > B { if let s = cur { c.segs.append(s); cur = nil }; continue }
            let loss = (out[i - 1].1 + out[i].1) / 2 < 0
            if p.y > B { let t = (B - p.y) / (q.y - p.y); p = CGPoint(x: p.x + (q.x - p.x) * t, y: B); c.markers.append(p.x) }
            if q.y > B { let t = (B - p.y) / (q.y - p.y); q = CGPoint(x: p.x + (q.x - p.x) * t, y: B); c.markers.append(q.x) }
            if var s = cur, s.loss == loss, let last = s.pts.last, abs(last.x - p.x) < 0.01, abs(last.y - p.y) < 0.01 {
                s.pts.append(q); cur = s
            } else {
                if let s = cur { c.segs.append(s) }
                cur = PayoffChart.Seg(pts: [p, q], loss: loss)
            }
        }
        if let s = cur { c.segs.append(s) }
        c.posArea = [CGPoint(x: out[0].0.x, y: c.zy)] + out.map { CGPoint(x: $0.0.x, y: min($0.0.y, c.zy)) } + [CGPoint(x: out.last!.0.x, y: c.zy)]
        c.negArea = [CGPoint(x: out[0].0.x, y: c.zy)] + out.map { CGPoint(x: $0.0.x, y: min(B, max($0.0.y, c.zy))) } + [CGPoint(x: out.last!.0.x, y: c.zy)]
        c.be = c.be.filter { $0.price > lo && $0.price < hi }
        c.nx = X(L[0].px)
        c.plNow = PMath.pl(L, L[0].px, el)
        // P/L ticks on the right; price ticks under.
        let nice = { (v: Double) -> Double in
            let p = pow(10, floor(log10(max(v, 1e-9)))), f = v / p
            return (f < 1.5 ? 1 : f < 3 ? 2 : f < 4 ? 2.5 : f < 7.5 ? 5 : 10) * p
        }
        let ys = nice(max(yHi, -yLo) * 0.5)
        c.yTicks = [ys, 0, -ys].filter { $0 == 0 || (Yr($0) > T + 4 && Yr($0) < B - 4) }.map { (Yr($0), $0) }
        let xs = nice((hi - lo) / 3.4)
        var v = ceil(lo / xs) * xs
        while v <= hi + 1e-9 { let x = X(v); if x > 14 && x < W - 14 { c.xTicks.append((x, v, xs)) }; v += xs }
        // Strike labels; ones that would touch merge into a range.
        var u: [(l: PLeg, x: CGFloat, lbl: String)] = []
        for l in L where !u.contains(where: { $0.l.k == l.k && $0.l.sold == l.sold }) { u.append((l, X(l.k), label(l))) }
        u.sort { $0.x < $1.x }
        let est = { (s: String) -> CGFloat in CGFloat(s.count) * 6.4 + 6 }
        let suf = { (s: String) -> String in String(s.drop { $0.isNumber || $0 == "." }) }
        var cl = u.map { [$0] }
        let lab = { (m: [(l: PLeg, x: CGFloat, lbl: String)]) -> String in
            if m.count == 1 { return m[0].lbl }
            let a = m[0], z = m[m.count - 1], sf = suf(a.lbl)
            return m.allSatisfy { suf($0.lbl) == sf } ? "\(PF.strike(a.l.k))–\(PF.strike(z.l.k))\(sf)" : "\(a.lbl)–\(z.lbl)"
        }
        let cx = { (m: [(l: PLeg, x: CGFloat, lbl: String)]) -> CGFloat in (m[0].x + m[m.count - 1].x) / 2 }
        var moved = true
        while moved && cl.count > 1 {
            moved = false
            for i in 1..<cl.count where cx(cl[i]) - cx(cl[i - 1]) < (est(lab(cl[i])) + est(lab(cl[i - 1]))) / 2 + 4 {
                cl[i - 1] += cl[i]; cl.remove(at: i); moved = true; break
            }
        }
        for m in cl {
            let t = lab(m), w = est(t), ctr = max(w / 2, min(W - w / 2, cx(m)))
            for (j, q) in m.enumerated() { c.strikes.append((q.x, j == 0 ? t : "", ctr, q.l.id)) }
        }
        if L.count == 1, let l = L.first, l.k > lo, l.k < hi {
            let pv = PMath.pl(L, l.k, el), y = Yr(pv)
            if y <= B { c.dot = (X(l.k), y, pv >= 0) }
        }
        return c
    }
}
