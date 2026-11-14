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
        /// Switched on in Every leg (Nik 13 Nov 2026: "we should be able to switch on and switch off"; "by default only
        /// keep income on and rest off"). Legs sold start on, shares and legs bought start off. An off leg drops out of
        /// the Whole TICKER book row and the Payoff with its Greeks; the Price chart keeps every strike held.
        let on: Bool
    }
    /// A strike on the Price chart (legs switched on only): its leg in full, "Sold calls 36 ×72 · Oct 30".
    struct Strike: Identifiable { let id: String; let K: Double; let put: Bool; let q: Double; let label: String
        /// The expiry ("2026-11-20") and, for a sold leg, how close it is (its Sold in SD row's tone; set by PosPrice.toned).
        var iso = ""; var tone: PE.Tone? = nil }
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
    /// Some leg is switched away from how they start (Income on, the rest off).
    let changed: Bool

    /// `flip`: the legs switched away from the start.
    static func build(_ m: PositionsModel, inputs: JSONValue?, flip: Set<String> = []) -> PosName {
        let off = Set(m.legs.filter { ($0.q < 0) == flip.contains($0.id) }.map(\.id))
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
            strikes.append(Strike(id: l.id, K: l.K, put: l.ty == .put, q: l.q,
                                  label: "\(l.q < 0 ? "Sold" : "Bought") \(kind)s \(PE.fk(l.K)) ×\(PosFmt.count(abs(l.q))) · \(exL)", iso: l.iso))
        }
        let live = legs.filter(\.on)
        return PosName(t: m.t, S0: m.S0, legs: legs, soFar: live.reduce(0) { $0 + $1.soFar }, delta: live.reduce(0) { $0 + $1.delta },
                       strikes: strikes, payoff: payoff(m, off: off), changed: !flip.isEmpty)
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

// MARK: - The Price chart (handoff 2026-11-13-positions 2 §3.4; Nik, 13 Nov 2026: "Just price chart")

/// The shared model (supabase/functions/_shared/price-chart.ts, `priceChart`) ported for the phone: always the past week
/// (the phone has no range control), phone sizes (plot 200 tall, tag rows 20, tags 18, labels at least 10% apart).
///   The week draws hours, 7 a session (10:00 to 16:00 New York, sunny-chart's `hours`, our Theta quotes; an hour with
///   no quote is read on the straight line between the day's closes), from the close before the first day; today
///   ends at the price now; then the trading days left to the Friday (the first Friday after today, P1; holidays
///   skipped) stay open. Labels name each day at its start.
///   Scale: today and the sold strikes first (at least 6% of the price, centred, × 1.24), then the line; a bought
///   strike joins when it adds under 40%, else it pins to the edge with ↑ or ↓ and no line. Pad 5%.
///   One line per strike, side and type; a tag per line on the right: the strike with C or P after it (Nik, 13 Nov
///   2026, option A) and how far from today; today's
///   price a white capsule; tags spread in rows (a group holding today's price stays pinned to it), a short connector
///   when a tag leaves its line.
struct PosPrice {
    struct Point { let x: Double; let v: Double; let d: String; let h: Int?; let now: Bool }
    struct Tag: Identifiable { let id: String; let top: CGFloat; let n: String; let s: String; let px: Bool; let sold: Bool; let put: Bool; let title: String
        /// A sold strike's closeness (the nearest of its legs); nil for bought, today or a sold leg without an SD.
        var tone: PE.Tone? = nil }
    struct Line: Identifiable { let id: String; let y: CGFloat; let sold: Bool }
    struct Conn: Identifiable { let id: Int; let y0: CGFloat; let y1: CGFloat }
    struct Label: Identifiable { let id: Int; let x: Double; let t: String; let now: Bool }
    static let CH: CGFloat = 200, PT: CGFloat = 20, TH: CGFloat = 18

    let pts: [Point]
    let up: Bool
    /// The price now against the close before the week, a fraction.
    let move: Double
    let dotX: Double, dotY: CGFloat
    let lines: [Line], tags: [Tag], conn: [Conn], xl: [Label]
    /// "Fri Nov 20".
    let fridayWords: String
    let lo: Double, hi: Double
    func y(_ v: Double) -> CGFloat { CGFloat((hi - v) / (hi - lo)) * Self.CH }

    private static let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private static let isoF: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static func day(_ s: String) -> Date { isoF.date(from: String(s.prefix(10))) ?? Date(timeIntervalSince1970: 0) }
    /// 1 Sunday ... 7 Saturday.
    static func dow(_ s: String) -> Int { utc.component(.weekday, from: day(s)) }
    static func add(_ s: String, _ n: Int) -> String { isoF.string(from: utc.date(byAdding: .day, value: n, to: day(s))!) }
    static let WD = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], MN = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    /// "Fri Nov 20".
    static func dayWords(_ s: String) -> String {
        let c = utc.dateComponents([.month, .day, .weekday], from: day(s))
        return "\(WD[c.weekday! - 1]) \(MN[c.month! - 1]) \(c.day!)"
    }
    /// The first Friday after today (from a Friday on, and all weekend, next Friday: Intelligence's rule, P1).
    static func friday(_ today: String) -> String { let w = dow(today) - 1; return add(today, (5 - w + 7) % 7 == 0 ? 7 : (5 - w + 7) % 7) }
    private static func dpc(_ k: Double, _ S0: Double) -> String { let p = abs(k / S0 - 1) * 100; return String(format: p < 0.1 ? "%.2f%%" : "%.1f%%", p) }

    /// Each sold strike with its Sold in SD row's tone (same side, strike and expiry; the web's toneOf in Band.tsx).
    static func toned(_ strikes: [PosName.Strike], _ sold: [PE.SoldRow]) -> [PosName.Strike] {
        strikes.map { st in
            var x = st
            if st.q < 0 { x.tone = sold.first { $0.l.put == st.put && abs($0.l.K - st.K) < 1e-6 && $0.l.ex == st.iso }?.tone }
            return x
        }
    }
    static func build(_ w: TickerWire, S0: Double, today: String, mins: Int, closed: Set<String>, strikes: [PosName.Strike]) -> PosPrice? {
        let trading = { (s: String) -> Bool in let d = dow(s); return d != 1 && d != 7 && !closed.contains(s) }
        var pairs: [(String, Double)] = zip(w.dates, w.closes).filter { $0.1 > 0 }.map { (String($0.0.prefix(10)), $0.1) }
        // Today: a session once the bell has rung, its close the price now; before the bell the line ends on the last
        // close, moved to the price now so the dot sits on it.
        let live = trading(today) && mins >= 9 * 60 + 30
        if let last = pairs.last, last.0 == today { pairs[pairs.count - 1].1 = S0 }
        else if live { pairs.append((today, S0)) }
        else if !pairs.isEmpty { pairs[pairs.count - 1].1 = S0 }
        guard pairs.count >= 2, S0 > 0 else { return nil }
        let nR = min(5, pairs.count - 1)
        let sl = Array(pairs.suffix(nR + 1)), last = sl[sl.count - 1].0
        let inDay = live && last == today && mins < 16 * 60
        let fri = friday(today)
        var FT: [String] = []
        var d0 = add(last, 1)
        while d0 <= fri { if trading(d0) { FT.append(d0) }; d0 = add(d0, 1) }
        let U = Double((nR + FT.count) * 7)

        var pts: [Point] = [Point(x: 0, v: sl[0].1, d: sl[0].0, h: 9, now: false)]
        for d in 0..<nR {
            let dayS = sl[d + 1].0, a = sl[d].1, b = sl[d + 1].1, hr = w.hours?[dayS], isToday = inDay && d == nR - 1
            let kNow = isToday ? max(0.5, min(7, Double(mins - 9 * 60) / 60)) : 7
            var known: [(Double, Double)] = [(0, a)]
            for k in 1...7 where Double(k) < kNow {
                if let hr, hr.indices.contains(k - 1), let v = hr[k - 1], v > 0 { known.append((Double(k), v)) }
            }
            known.append((kNow, b))
            let at = { (k: Double) -> Double in
                var j = 0
                while j < known.count - 2 && known[j + 1].0 < k { j += 1 }
                let (k0, v0) = known[j], (k1, v1) = known[j + 1]
                return k1 > k0 ? v0 + (v1 - v0) * (k - k0) / (k1 - k0) : v1
            }
            var k = 1
            while Double(k) < kNow {
                let q = hr.flatMap { $0.indices.contains(k - 1) ? $0[k - 1] : nil } ?? at(Double(k))
                pts.append(Point(x: (Double(d * 7) + Double(k)) / U, v: q, d: dayS, h: 9 + k, now: false))
                k += 1
            }
            pts.append(Point(x: (Double(d * 7) + kNow) / U, v: b, d: dayS, h: isToday ? nil : 16, now: isToday))
        }
        let end = pts[pts.count - 1]
        pts[pts.count - 1] = Point(x: end.x, v: S0, d: end.d, h: end.h, now: end.now)

        // The scale.
        let sK = strikes.filter { $0.q < 0 }.map(\.K), hs = pts.map(\.v)
        var a0 = min(S0, sK.min() ?? S0), b0 = max(S0, sK.max() ?? S0)
        do {
            let sp = max(b0 - a0, S0 * 0.06), md = (a0 + b0) / 2
            a0 = min(md - sp * 0.62, hs.min() ?? md); b0 = max(md + sp * 0.62, hs.max() ?? md)
        }
        do {
            let r0 = b0 - a0
            for l in strikes where l.q > 0 {
                if l.K < a0 && a0 - l.K <= r0 * 0.4 { a0 = l.K }
                if l.K > b0 && l.K - b0 <= r0 * 0.4 { b0 = l.K }
            }
            let q = (b0 - a0) * 0.05; a0 -= q; b0 += q
        }
        let Y = { (v: Double) in CGFloat((b0 - v) / (b0 - a0)) * CH }

        // One line per strike, side and type.
        struct G { let kk: String; let sd: Bool; let put: Bool; let K: Double; var ls: [String]; var tone: PE.Tone? }
        var gs: [G] = [], gi: [String: Int] = [:]
        let rank = { (t: PE.Tone?) -> Int in t == .red ? 3 : t == .orange ? 2 : t == .quiet ? 1 : 0 }
        for l in strikes {
            let kk = (l.q < 0 ? "s" : "b") + (l.put ? "P" : "C") + PE.fk(l.K), tn = l.q < 0 ? l.tone : nil
            // Legs on one strike in different expiries share a tag: it wears the closest one's colour.
            if let i = gi[kk] { gs[i].ls.append(l.label); if rank(tn) > rank(gs[i].tone) { gs[i].tone = tn } }
            else { gi[kk] = gs.count; gs.append(G(kk: kk, sd: l.q < 0, put: l.put, K: l.K, ls: [l.label], tone: tn)) }
        }
        final class T { let key: String; let y: CGFloat; let px: Bool; let out: Bool; let up: Bool; let g: G?; var cy: CGFloat = 0
            init(_ key: String, _ y: CGFloat, _ px: Bool, _ out: Bool, _ up: Bool, _ g: G?) { self.key = key; self.y = y; self.px = px; self.out = out; self.up = up; self.g = g } }
        var tg: [T] = [T("px", Y(S0), true, false, false, nil)]
        for g in gs { let yy = Y(g.K), out = yy < 0 || yy > CH; tg.append(T(g.kk, out ? (yy < 0 ? 0 : CH) : yy, false, out, yy < 0, g)) }
        tg.sort { $0.y < $1.y }
        struct Cl { var xs: [T]; var top: CGFloat = 0 }
        func place(_ c: inout Cl) {
            let top: CGFloat
            if let j = c.xs.firstIndex(where: \.px) { top = c.xs[j].y - PT / 2 - CGFloat(j) * PT }
            else { top = c.xs.enumerated().reduce(0) { $0 + $1.element.y - CGFloat($1.offset) * PT } / CGFloat(c.xs.count) - PT / 2 }
            c.top = max(0, min(CH - PT * CGFloat(c.xs.count), top))
        }
        var cl = tg.map { Cl(xs: [$0]) }
        for i in cl.indices { place(&cl[i]) }
        var merged = true, it = 0
        while merged && it < 30 {
            merged = false; it += 1
            for i in 0..<max(0, cl.count - 1) where cl[i].top + CGFloat(cl[i].xs.count) * PT > cl[i + 1].top {
                var c = Cl(xs: cl[i].xs + cl[i + 1].xs); place(&c)
                cl.replaceSubrange(i...(i + 1), with: [c]); merged = true; break
            }
        }
        for c in cl { for (i, x) in c.xs.enumerated() { x.cy = c.top + CGFloat(i) * PT + PT / 2 } }
        let tags: [Tag] = tg.map { x in
            guard let g = x.g else { return Tag(id: "px", top: x.cy - TH / 2, n: String(format: "%.2f", S0), s: "", px: true, sold: true, put: false, title: "Today \(String(format: "%.2f", S0))") }
            return Tag(id: x.key, top: x.cy - TH / 2, n: PE.fk(g.K) + (g.put ? " P" : " C"), s: dpc(g.K, S0) + (x.out ? (x.up ? " ↑" : " ↓") : ""), px: false, sold: g.sd, put: g.put,
                       title: g.ls.joined(separator: ", ") + (x.out ? ", off the chart \(x.up ? "above" : "below")" : ""), tone: g.tone)
        }
        let conn = tg.filter { !$0.px && !$0.out && abs($0.cy - $0.y) > 3 }.enumerated().map { Conn(id: $0.offset, y0: $0.element.y, y1: $0.element.cy) }
        let lines = gs.compactMap { g -> Line? in let yy = Y(g.K); return yy >= 0 && yy <= CH ? Line(id: g.kk, y: yy, sold: g.sd) : nil }

        // The days under the chart, each at its start; thinned from the right (10% apart); the last up to today white.
        var xl0: [(Double, String, Bool)] = []
        for d in 0..<nR { xl0.append((Double(d * 7) / U, WD[dow(sl[d + 1].0) - 1], false)) }
        for (j, s) in FT.enumerated() { xl0.append((Double((nR + j) * 7) / U, WD[dow(s) - 1], true)) }
        var xl: [(Double, String, Bool)] = []
        for x in xl0.reversed() where xl.isEmpty || xl[xl.count - 1].0 - x.0 >= 0.10 - 1e-9 { xl.append(x) }
        xl.reverse()
        let li = xl.lastIndex { !$0.2 } ?? -1
        let move = S0 / sl[0].1 - 1
        return PosPrice(pts: pts, up: move >= 0, move: move, dotX: pts[pts.count - 1].x, dotY: Y(S0), lines: lines, tags: tags, conn: conn,
                        xl: xl.enumerated().map { Label(id: $0.offset, x: $0.element.0, t: $0.element.1, now: $0.offset == li) },
                        fridayWords: dayWords(FT.last ?? fri), lo: a0, hi: b0)
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
