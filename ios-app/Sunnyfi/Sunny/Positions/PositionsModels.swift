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
//  ⚠ NIK'S RULE (24 Nov 2026): every leg by what it is, Shares, Calls bought (LEAPS too), Calls sold, Puts bought,
//  Puts sold; never Long, Hedge or Income ("Finding Long, Hedge and Income very confusing"). Legs read strike first
//  ("40 call · Nov 13"), never "OTM calls".
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

// MARK: - The whole book (title, Your book, the name strip)

struct PosBook {
    struct Name: Identifiable, Hashable {
        var id: String { t }
        let t: String; let company: String; let strategy: String
        let S0: Double; let P0: Double
        /// The strip's red dot (handoff 2026-11-18 §2.2): a strike sold for this week within 0.5 SD or in the money.
        let dot: PE.Tone?
    }
    /// One leg of Your book (Nik, 24 Nov 2026), as sunny-home sends it (brief_inputs.parts, all time only):
    ///   Shares, Calls bought, Puts bought: value = worth now, all = gain or loss against IBKR's cost, return = all ÷ abase.
    ///   Calls sold, Puts sold: value = premium collected, all = kept so far, now (to buy back) = value less all,
    ///   captured = all ÷ value.
    /// tv: the time value left (every option part, none on shares); nl: how many legs.
    struct Part: Identifiable {
        var id: String { key }
        let key: String; let label: String
        var value = 0.0, all = 0.0, abase = 0.0
        var tv: Double? = nil
        var nl = 0
        var sold: Bool { key == "sc" || key == "sp" }
        /// Worth now; what was sold: what it costs to buy back.
        var now: Double { sold ? value - all : value }
        /// Bought and shares: the return on cost; sold: the share of the premium captured.
        var pct: Double { sold ? (value > 0 ? all / value : 0) : (abase > 0 ? all / abase : 0) }
    }
    /// The legs in Nik's order (24 Nov 2026): Shares, Calls bought, Calls sold, Puts bought, Puts sold.
    static let order: [(key: String, label: String)] = [("sh", "Shares"), ("hc", "Calls bought"), ("sc", "Calls sold"),
                                                        ("ip", "Puts bought"), ("sp", "Puts sold")]

    let names: [Name]
    /// Your book: only the legs the book holds (never None).
    let parts: [Part]
    /// Each name's own book (§2.3), the same legs from that name's parts.
    let nameParts: [String: [Part]]
    /// Every sold leg on its SD (the strip's dots and the Price chart's strike tones).
    let sold: [PE.SoldRow]
    /// The names with something sold (their sunny-sd replies carry the SD when sold).
    let soldNames: [String]

    static func build(brief: BriefLive, inputs: JSONValue?, calendar: [CalendarDay], replies: (String) -> SDReply?, now: Date) -> PosBook {
        let parts = Self.parts(inputs?["parts"]["book"] ?? .null)
        var nameParts: [String: [Part]] = [:]
        for (t, j) in (inputs?["parts"]["names"] ?? .null).object { nameParts[t] = Self.parts(j) }
        // Sold, in SD: every sold option leg from Home's legs; the SD when sold from each name's sunny-sd reply.
        let legs = soldLegs(inputs: inputs, calendar: calendar, replies: replies, now: now)
        let so = PE.soldInSd(legs)
        let names = brief.names.compactMap { n -> Name? in
            guard let t = n["t"].string else { return nil }
            let st = n["st"].double.map { Int($0) }
            return Name(t: t, company: n["name"].string ?? t, strategy: n["strategy"].string ?? "", S0: n["S0"].double ?? 0,
                        P0: n["P0"].double ?? n["S0"].double ?? 0, dot: PE.phoneDot(so.rows, t, friday: brief.friday))
        }
        var sn: [String] = []
        for l in legs where !sn.contains(l.t) { sn.append(l.t) }
        return PosBook(names: names, parts: parts, nameParts: nameParts, sold: so.rows, soldNames: sn)
    }

    /// The legs held, in Nik's order, from one parts object ({sh, hc, ip, sc, sp}); a part not held is left out.
    static func parts(_ j: JSONValue) -> [Part] {
        order.compactMap { k, label in
            let x = j[k]
            guard case .object = x else { return nil }
            return Part(key: k, label: label, value: x["value"].double ?? 0, all: x["all"].double ?? 0, abase: x["abase"].double ?? 0,
                        tv: x["tv"].double, nl: Int((x["nl"].double ?? 0).rounded()))
        }
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
        /// "40.5 call" or "NKE shares"; "50 sold", "15 bought", "3,000".
        let contract: String
        let qty: String
        /// The line under the contract (handoff 2026-11-18, as the web): "Nov 20 (2 days) · Calls sold · −72";
        /// shares "Shares · +3,000".
        let sub: String
        /// What the leg brought in (sold) or paid out (bought) at its average: at × count × 100. Shares 0.
        let cashIn: Double, cashOut: Double
        /// (mark − entry) × q × mul; shares q × (price − cost).
        let soFar: Double
        /// q × 100 × Δ (shares q), from the grid at today's price.
        let delta: Double
        /// Switched on in Every leg (Nik 13 Nov 2026: "we should be able to switch on and switch off"; 24 Nov 2026: "keep
        /// all of them on"). Every leg starts on. An off leg drops out of
        /// the Whole TICKER book row and the Payoff with its Greeks; the Price chart keeps every strike held.
        let on: Bool
    }
    /// A strike on the Price chart (legs switched on only): its leg in full, "Calls sold 36 ×72 · Oct 30".
    struct Strike: Identifiable { let id: String; let K: Double; let put: Bool; let q: Double; let label: String
        /// The expiry ("2026-11-20") and, for a sold leg, how close it is (its Sold in SD row's tone; set by PosPrice.toned).
        var iso = ""; var tone: PE.Tone? = nil }
    struct Payoff {
        /// ±range of the price, 121 points: the P&L from today's marks at the stop's date.
        let xs: [Double]; let ys: [Double]
        /// The range either side (0.12 = ±12%) and the P&L scale, held across every date on the slider.
        let range: Double; let yLo: Double; let yHi: Double
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
    /// The Whole TICKER book row's At (legs switched on, shares left out): premium in from what was sold, paid out
    /// for what was bought, each at its average.
    let cashIn: Double, cashOut: Double
    let strikes: [Strike]
    let payoff: Payoff?
    /// Some leg is switched off (every leg starts on).
    let changed: Bool
    /// The Payoff's date slider (handoff 2026-11-17 round 168b, 2026-11-18; Nik, 20 Nov 2026, option 1: the full picture
    /// past the first expiry): the server's stops from today (or Monday over a weekend) to the day the LAST sold legs
    /// expire, the first expiry of any leg when nothing is sold. Past an expiry the legs that ended there are worth what
    /// they were at that close and the rest keep their time value: the "do nothing" path.
    let dates: [DateStop]
    /// Where the slider opens: the nearest sold expiry (where it ended before 20 Nov), as the Friday stop did.
    var dateOpen = 0
    struct DateStop: Hashable {
        /// The stop's index in the model; "Fri Nov 20", "Wed Nov 18"; calendar days from today.
        let i: Int; let full: String; let tick: String; let days: Int; let friday: Bool
        /// "Wed Nov 18" (the stop's day, also for Today) and its weekday ("Wed").
        let date: String; let wd: String
        /// The legs that expire at this stop ("Calls and puts sold, puts bought expire").
        let ends: String
    }
    /// The slider's last stop.
    var dateEnd: Int { max(0, dates.count - 1) }

    /// The legs switched off: every leg starts on (Nik, 24 Nov 2026), `flip` holds the ones switched off.
    static func offs(_ m: PositionsModel, flip: Set<String>) -> Set<String> {
        Set(m.legs.filter { flip.contains($0.id) }.map(\.id))
    }

    static func build(_ m: PositionsModel, inputs: JSONValue?, flip: Set<String> = []) -> PosName {
        let off = offs(m, flip: flip)
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
        let today = MarketClock.ny(SClock.now()).date
        /// "+3,000", "−72": the count signed (Nik, 17 Nov 2026: the one place a count carries a sign).
        let signed = { (q: Double) in (q < 0 ? "−" : "+") + PosFmt.count(q) }
        /// "(3 days)", "(1 day)", "(today)": calendar days to the expiry.
        let left = { (iso: String) -> String in
            let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
            guard let a = f.date(from: today), let b = f.date(from: iso) else { return "" }
            let d = Int(((b.timeIntervalSince(a)) / 86400).rounded())
            return d <= 0 ? "(today)" : d == 1 ? "(1 day)" : "(\(d) days)"
        }
        for l in ordered {
            let exL = l.title.components(separatedBy: ", ").last ?? l.ex
            if l.ty == .shares {
                legs.append(Leg(id: l.id, contract: "\(m.t) shares", qty: PosFmt.count(l.q),
                                sub: "Shares · \(signed(l.q))", cashIn: 0, cashOut: 0, soFar: l.q * (m.S0 - l.K), delta: l.q,
                                on: !off.contains(l.id)))
                continue
            }
            let kind = l.ty == .put ? "put" : "call"
            let now = mark[l.id], entry = at[l.id]
            let sf = entry != nil && now != nil ? (now! - entry!) * l.q * 100 : 0
            let name = "\(l.ty == .put ? "Puts" : "Calls") \(l.q < 0 ? "sold" : "bought")"
            let cash = (entry ?? 0) * abs(l.q) * 100
            legs.append(Leg(id: l.id, contract: "\(PE.fk(l.K)) \(kind)",
                            qty: "\(PosFmt.count(l.q)) \(l.q < 0 ? "sold" : "bought")",
                            sub: "\(exL) \(left(l.iso)) · \(name) · \(signed(l.q))",
                            cashIn: l.q < 0 ? cash : 0, cashOut: l.q > 0 ? cash : 0,
                            soFar: sf, delta: m.legDelta(l, m.S0, 0), on: !off.contains(l.id)))
            strikes.append(Strike(id: l.id, K: l.K, put: l.ty == .put, q: l.q,
                                  label: "\(name) \(PE.fk(l.K)) ×\(PosFmt.count(abs(l.q))) · \(exL)", iso: l.iso))
        }
        let live = legs.filter(\.on)
        let dates = dateStops(m)
        let open = openStop(m, dates.count)
        return PosName(t: m.t, S0: m.S0, legs: legs, soFar: live.reduce(0) { $0 + $1.soFar }, delta: live.reduce(0) { $0 + $1.delta },
                       cashIn: live.reduce(0) { $0 + $1.cashIn }, cashOut: live.reduce(0) { $0 + $1.cashOut },
                       strikes: strikes, payoff: payoff(m, off: off, stop: dates.isEmpty ? m.fridayStop : dates[open].i, range: 0.12, hold: dates.map(\.i)),
                       changed: !flip.isEmpty, dates: dates, dateOpen: open)
    }

    /// The stop nearest `T` (calendar days on).
    private static func stopNear(_ m: PositionsModel, _ T: Double) -> Int? {
        m.stops.indices.min { abs(m.stops[$0].tt - T) < abs(m.stops[$1].tt - T) }
    }
    /// Where the slider opens: the stop nearest the nearest sold expiry (any leg's when nothing is sold), on the slider.
    static func openStop(_ m: PositionsModel, _ count: Int) -> Int {
        let opts = m.legs.filter { $0.ty != .shares }, sold = opts.filter { $0.q < 0 }
        guard count > 0, let T = (sold.isEmpty ? opts : sold).map(\.T).min(), let i = stopNear(m, T) else { return max(0, count - 1) }
        return min(i, count - 1)
    }

    /// The slider's stops: from the first to the stop nearest the last expiry of any leg.
    static func dateStops(_ m: PositionsModel) -> [DateStop] {
        guard !m.stops.isEmpty else { return [] }
        let opts = m.legs.filter { $0.ty != .shares }
        // To the last expiry of any leg (Nik, 25 Nov 2026: "Can we show till the last expiry?"); the server's stops run
        // daily to the last sold expiry, then Fridays for two months, then each monthly and every leg's own expiry.
        let endT = opts.map(\.T).max()
        var end = m.fridayStop
        if let T = endT { end = stopNear(m, T) ?? m.fridayStop }
        let mins = Double(MarketClock.ny(SClock.now()).minutes)
        let names = { (ls: [PositionsModel.Leg]) in Set(ls.map { $0.ty == .put ? "puts" : "calls" }).sorted().joined(separator: " and ") }
        return (0...end).map { i in
            let s = m.stops[i]
            let days = max(0, Int((s.tt + (mins - 960) / 1440).rounded()))
            let full = s.tt < 0.01 && i == 0 ? "Today" : s.long.replacingOccurrences(of: " close", with: "")
            let at = opts.filter { abs($0.T - s.tt) < 0.6 }
            let so = at.filter { $0.q < 0 }, bo = at.filter { $0.q > 0 }
            let ends = [so.isEmpty ? "" : "\(names(so)) sold", bo.isEmpty ? "" : "\(names(bo)) bought"]
                .filter { !$0.isEmpty }.joined(separator: ", ")
            let date = s.long.replacingOccurrences(of: " close", with: "")
            return DateStop(i: i, full: full, tick: i == 0 ? "Today" : s.short, days: days, friday: s.friday,
                            date: date, wd: String(date.prefix(3)), ends: ends.isEmpty ? "" : String(ends.prefix(1)).uppercased() + String(ends.dropFirst()) + " expire")
        }
    }

    /// What has expired by a stop (Nik, 20 Nov 2026, option 1; the web's goneWords): "Nov 20: 20 calls sold and 10 puts
    /// sold expired", "Nov 20 and Nov 27: ...", "Nov 20 to Dec 4, 3 expiries: ...". Legs switched off drop out; empty
    /// before the first expiry.
    static func gone(_ m: PositionsModel, off: Set<String>, stop: Int) -> String {
        guard m.stops.indices.contains(stop) else { return "" }
        let tt = m.stops[stop].tt
        let past = m.legs.filter { $0.ty != .shares && !off.contains($0.id) && !$0.iso.isEmpty && $0.T < tt - 0.5 }
        let days = Array(Set(past.map(\.iso))).sorted()
        guard let first = days.first, let last = days.last else { return "" }
        let md = { (iso: String) in PositionsModel.md(iso) }
        let kinds: [(SampleEngine.Ty, Bool, String)] = [(.call, true, "calls sold"), (.put, true, "puts sold"), (.call, false, "calls bought"), (.put, false, "puts bought")]
        let parts = kinds.compactMap { ty, sold, w -> String? in
            let n = past.filter { $0.ty == ty && ($0.q < 0) == sold }.reduce(0) { $0 + abs($1.q) }
            return n > 0 ? "\(PosFmt.count(n)) \(w)" : nil
        }
        let what = parts.count < 2 ? parts.joined() : parts.dropLast().joined(separator: ", ") + " and " + parts.last!
        let when = days.count == 1 ? md(first) : days.count == 2 ? "\(md(first)) and \(md(last))" : "\(md(first)) to \(md(last)), \(days.count) expiries"
        return "\(when): \(what) expired"
    }

    /// README §3.5 at a stop's date: Σ q × mul × (value then − mark now) from the server's grid (no premium already
    /// earned: the web's Pricer), ±range of the price, the priced move, where it peaks, the Greeks then. The P&L scale
    /// is the widest over every stop in `hold`, so the curve moves against a fixed scale as the date slides (168).
    /// Legs switched off drop out (the web's What if set).
    /// `extra`: legs tried from Intelligence (handoff 2026-11-24 §4), priced on the phone at the chain's IV for their own
    /// strike and expiry; they add to the curve, where it peaks and the Greeks.
    static func payoff(_ m: PositionsModel, off: Set<String>, stop: Int, range r: Double, hold: [Int], extra: [PosTryLeg] = []) -> Payoff? {
        guard m.stops.indices.contains(stop), m.S0 > 0 else { return nil }
        let st = m.stops[stop], tt = st.tt, S0 = m.S0
        let plAt = { (x: Double, t: Double) in
            m.legs.reduce(0) { off.contains($1.id) ? $0 : $0 + m.legPL($1, x, t) } + extra.reduce(0) { $0 + $1.pl(x, t) }
        }
        let pl = { (x: Double) in plAt(x, tt) }
        let xs = (0...120).map { S0 * (1 - r + 2 * r * Double($0) / 120) }
        let ys = xs.map(pl)
        var lo = min(0, ys.min() ?? 0), hi = max(0, ys.max() ?? 0)
        for i in hold where i != stop && m.stops.indices.contains(i) {
            let t = m.stops[i].tt
            for x in stride(from: 0, through: 120, by: 4).map({ xs[$0] }) { let v = plAt(x, t); lo = min(lo, v); hi = max(hi, v) }
        }
        let peak = shortAt(m, stop, off: off, extra: extra)
        let g = greeks(m, S0, tt, off: off, extra: extra)
        let today = stop == 0 && tt < 0.01
        let byT = today ? "today" : "by " + st.long.replacingOccurrences(of: " close", with: "")
        let top = Int(PE.jsRound(min(50, ((m.gridTop ?? S0 * 1.5) / S0 - 1) * 100)))
        return Payoff(xs: xs, ys: ys, range: r, yLo: lo, yHi: hi, v0: pl(S0), byT: byT, dateLabel: st.short == "Today" ? "today" : st.short,
                      peak: peak, peakPast: peak.map { $0 <= S0 * 1.0005 } ?? false, top: top,
                      mv: m.v > 0 ? m.v * (max(tt, 1) / 365).squareRoot() : 0, d: g.d, th: g.th, g: g.g, vg: g.vg)
    }

    /// The Greeks at a price and date: the grid's legs that are on, plus the tried legs.
    static func greeks(_ m: PositionsModel, _ x: Double, _ tt: Double, off: Set<String>, extra: [PosTryLeg]) -> (d: Double, g: Double, th: Double, vg: Double) {
        var g = m.greeks(x, tt, off: off)
        for e in extra { let q = e.greeks(x, tt); g.d += q.d; g.g += q.g; g.th += q.th; g.vg += q.vg }
        return g
    }
    /// Where the book turns short at a stop: the grid's (to the cent) without tried legs; with them, the first price
    /// above today where the net delta drops below zero (steps of 0.2%, read between them), as far as +50%.
    static func shortAt(_ m: PositionsModel, _ stop: Int, off: Set<String>, extra: [PosTryLeg]) -> Double? {
        guard !extra.isEmpty else { return m.shortAt(stop, off: off) }
        guard m.stops.indices.contains(stop), m.S0 > 0 else { return nil }
        let tt = m.stops[stop].tt, S0 = m.S0, top = min(S0 * 1.5, m.gridTop ?? S0 * 1.5)
        let dAt = { (x: Double) in m.delta(x, tt, off: off) + extra.reduce(0) { $0 + $1.greeks(x, tt).d } }
        var px = S0, pd = dAt(px)
        if pd < 0 { return S0 }
        var x = S0 * 1.002
        while x <= top + 1e-9 {
            let dx = dAt(x)
            if dx < 0 { return ((px + (x - px) * pd / (pd - dx)) * 100 - 1e-9).rounded(.up) / 100 }
            px = x; pd = dx; x *= 1.002
        }
        return nil
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
        var tone: PE.Tone? = nil
        /// 162a: the strike ("36"), "0.46 SD" or "ITM" (an arrow when off the chart; nil without an IV), that SD's colour
        /// (sold strikes only: red under 0.5 SD or in the money, orange to 1 SD, quiet past), and "+2" when a side's
        /// farther sold strikes this week fold into it (164, phone).
        var k = ""; var sd: String? = nil; var zTone: PE.Tone? = nil; var fold = 0 }
    /// 162a: each line's type, its name at the right end ("Call sold 36", "Put bought 33"), where the name sits (16 above
    /// or 2 below the line) and whether it fits.
    struct Line: Identifiable { let id: String; let y: CGFloat; let sold: Bool; var put = false; var name = ""; var lt: CGFloat = -16; var shown = true }
    struct Conn: Identifiable { let id: Int; let y0: CGFloat; let y1: CGFloat }
    /// `c` (164): a cone day under its drop line, in its strike's type colour (true = put), bold.
    struct Label: Identifiable { let id: Int; let x: Double; let t: String; let now: Bool; var put: Bool? = nil }
    /// 162a: one of the nearest sold call and put for the card under the chart: "↑2.0% · 0.46 SD" or "in the money by
    /// $1.20"; the trading days until the cone reaches it (nil: in the money or outside it), that weekday, Friday's.
    struct Near: Identifiable { let id: String; let put: Bool; let name: String; let itm: Bool; let d: String; let tone: PE.Tone
        let reach: Double?; let day: String?; let fri: String }
    /// 162a: the room between the nearest sold call above and sold put below, px.
    struct Room { let top: CGFloat; let bottom: CGFloat; let up: Bool; let dn: Bool }
    /// 164: the cone on the scale before it widened (yb); x 0 to 1. Fills are top and bottom edges on X.
    struct Cone { let X: [Double]; let YU: [CGFloat]; let YD: [CGFloat]
        let fG: ([CGFloat], [CGFloat])?; let fU: ([CGFloat], [CGFloat])?; let fD: ([CGFloat], [CGFloat])?
        let lo: Double; let hi: Double
        let dots: [(id: String, x: Double, y: CGFloat, put: Bool)]; let drops: [(id: String, x: Double, y: CGFloat, put: Bool, day: String)] }
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
    // 162a and 164: this week's 1 SD move, the switch can show (an IV and a day left), it is on, the scale before the
    // cone widened it (the price line and the cone ride one transform from it: y = yb × sy + ty), room, nearest, cone.
    var m0 = 0.0, coneOk = false, coneOn = false
    var lo0 = 0.0, hi0 = 1.0
    func yb(_ v: Double) -> CGFloat { CGFloat((hi0 - v) / (hi0 - lo0)) * Self.CH }
    var tfTy: CGFloat { CGFloat((hi - hi0) / (hi - lo)) * Self.CH }
    var tfSy: CGFloat { CGFloat((hi0 - lo0) / (hi - lo)) }
    var room: Room? = nil
    var near: [Near] = []
    var cone: Cone? = nil

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
    /// `iv`: this week's IV (the name's, Home's brief_inputs); `cone`: the 1 SD layer on (round 164).
    static func build(_ w: TickerWire, S0: Double, today: String, mins: Int, closed: Set<String>, strikes all: [PosName.Strike],
                      iv: Double? = nil, cone wantCone: Bool = false) -> PosPrice? {
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

        // 164 (phone): a side with several strikes sold for this week draws only the nearest; the rest fold into its tag.
        var folds: [String: Int] = [:]
        var strikes = all
        for put in [false, true] {
            let wk = all.filter { $0.q < 0 && $0.put == put && !$0.iso.isEmpty && $0.iso <= fri }
            let ks = Set(wk.map(\.K))
            guard ks.count > 1, let keep = ks.min(by: { abs(log($0 / S0)) < abs(log($1 / S0)) }) else { continue }
            strikes.removeAll { $0.q < 0 && $0.put == put && !$0.iso.isEmpty && $0.iso <= fri && $0.K != keep }
            folds["s" + (put ? "P" : "C") + PE.fk(keep)] = ks.count - 1
        }
        let FD = FT.count

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
        // 162a: this week's 1 SD move. 164: with the cone on, the scale widens to take in its ends at the Friday close.
        let m0 = (iv ?? 0) > 0 ? iv! * (Double(max(1, FD)) / 252).squareRoot() : 0
        let coneOk = FD >= 1 && m0 > 0, coneOn = coneOk && wantCone
        let A0 = a0, B0 = b0
        if coneOn { let cu = S0 * exp(m0), cd = S0 * exp(-m0), q = (cu - cd) * 0.08; a0 = min(a0, cd - q); b0 = max(b0, cu + q) }
        let Y = { (v: Double) in CGFloat((b0 - v) / (b0 - a0)) * CH }
        let YB = { (v: Double) in CGFloat((B0 - v) / (B0 - A0)) * CH }

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
        // 162a: SD on this week's move, in the money, its colour, the name.
        let zOf = { (K: Double) -> Double? in m0 > 0 ? abs(log(K / S0)) / m0 : nil }
        let itmOf = { (g: G) -> Bool in g.put ? S0 < g.K : S0 > g.K }
        let zTone = { (g: G) -> PE.Tone in let z = zOf(g.K) ?? .infinity; return itmOf(g) || z < 0.5 ? .red : z < 1 ? .orange : .quiet }
        let nameOf = { (g: G) -> String in "\(g.put ? "Put" : "Call") \(g.sd ? "sold" : "bought") \(PE.fk(g.K))" }
        let tags: [Tag] = tg.map { x in
            guard let g = x.g else { return Tag(id: "px", top: x.cy - TH / 2, n: String(format: "%.2f", S0), s: "", px: true, sold: true, put: false, title: "Today \(String(format: "%.2f", S0))", k: String(format: "%.2f", S0)) }
            let z = zOf(g.K), it = g.sd && itmOf(g), arw = x.out ? (x.up ? " ↑" : " ↓") : ""
            return Tag(id: x.key, top: x.cy - TH / 2, n: PE.fk(g.K) + (g.put ? " P" : " C"), s: dpc(g.K, S0) + arw, px: false, sold: g.sd, put: g.put,
                       title: g.ls.joined(separator: ", ") + (z.map { _ in it ? ", in the money" : ", \(String(format: "%.2f", z!)) SD \(g.K >= S0 ? "above" : "below")" } ?? "")
                        + (x.out ? ", off the chart \(x.up ? "above" : "below")" : ""), tone: g.tone,
                       k: PE.fk(g.K), sd: z.map { (it ? "ITM" : String(format: "%.2f SD", $0)) + arw }, zTone: g.sd && z != nil ? zTone(g) : nil, fold: folds[g.kk] ?? 0)
        }
        let conn = tg.filter { !$0.px && !$0.out && abs($0.cy - $0.y) > 3 }.enumerated().map { Conn(id: $0.offset, y0: $0.element.y, y1: $0.element.cy) }
        var lines = gs.compactMap { g -> Line? in let yy = Y(g.K); return yy >= 0 && yy <= CH ? Line(id: g.kk, y: yy, sold: g.sd, put: g.put, name: nameOf(g)) : nil }
        // 162a: each name sits above its line, else below, else it is left off; never over another name or out of the plot.
        do {
            var bx: [(CGFloat, CGFloat)] = []
            let ok = { (a: CGFloat, b: CGFloat) in a >= 0 && b <= CH && bx.allSatisfy { b <= $0.0 || a >= $0.1 } }
            for i in lines.indices.sorted(by: { lines[$0].y < lines[$1].y }) {
                let L = lines[i]
                if ok(L.y - 16, L.y - 2) { lines[i].lt = -16; bx.append((L.y - 16, L.y - 2)) }
                else if ok(L.y + 2, L.y + 16) { lines[i].lt = 2; bx.append((L.y + 2, L.y + 16)) }
                else { lines[i].shown = false }
            }
        }
        // 162a: the nearest sold call and put (in the money first, then SD) and the room between the nearest sold strikes.
        let nG = gs.filter(\.sd)
        let dist = { (g: G) -> Double in zOf(g.K) ?? abs(log(g.K / S0)) }
        let rankN = { (a: G, b: G) -> Bool in itmOf(a) != itmOf(b) ? itmOf(a) : dist(a) < dist(b) }
        let nC1 = nG.filter { !$0.put }.sorted(by: rankN).first, nP1 = nG.filter(\.put).sorted(by: rankN).first
        let reachOf = { (g: G) -> Double? in guard coneOk, !itmOf(g), let z = zOf(g.K), z < 1 else { return nil }; return Double(FD) * z * z }
        let dayOf = { (r: Double) -> String in WD[dow(FT[min(FD, max(1, Int(ceil(r - 1e-9)))) - 1]) - 1] }
        let friW = WD[dow(FD > 0 ? FT[FD - 1] : fri) - 1]
        let near: [Near] = m0 > 0 ? [nC1, nP1].compactMap { $0 }.sorted(by: rankN).map { g in
            let z = zOf(g.K)!, it = itmOf(g), r = reachOf(g)
            return Near(id: "n" + g.kk, put: g.put, name: nameOf(g), itm: it,
                        d: it ? "in the money by \(String(format: "$%.2f", abs(S0 - g.K)))" : "\(g.K >= S0 ? "↑" : "↓")\(dpc(g.K, S0)) · \(String(format: "%.2f", z)) SD",
                        tone: zTone(g), reach: r, day: r.map(dayOf), fri: friW)
        } : []
        let sc0 = nG.filter { !$0.put }.min { $0.K < $1.K }, sp0 = nG.filter(\.put).max { $0.K < $1.K }
        let thisWeek = strikes.contains { $0.q < 0 && !$0.iso.isEmpty && $0.iso <= fri }
        let cY = { (v: CGFloat) in max(0, min(CH, v)) }
        var room: Room?
        if (sc0 != nil || sp0 != nil) && thisWeek {
            let top = sc0.map { cY(Y($0.K)) } ?? 0, bottom = max(top, sp0.map { cY(Y($0.K)) } ?? CH)
            room = Room(top: top, bottom: bottom, up: sc0 != nil && top > 0, dn: sp0 != nil && bottom < CH)
        }
        // 164: the cone, from today's dot to the Friday close, on the scale before it widened.
        var coneOut: Cone?
        let endX = pts[pts.count - 1].x
        if coneOk {
            let NQ = 24, lim = { (v: CGFloat) in max(-4 * CH, min(5 * CH, v)) }
            var X: [Double] = [], YU: [CGFloat] = [], YD: [CGFloat] = []
            for n in 0...NQ { let f = Double(n) / Double(NQ), mj = m0 * f.squareRoot(); X.append(endX + (1 - endX) * f); YU.append(lim(YB(S0 * exp(mj)))); YD.append(lim(YB(S0 * exp(-mj)))) }
            var fG: ([CGFloat], [CGFloat])?, fU: ([CGFloat], [CGFloat])?, fD: ([CGFloat], [CGFloat])?
            if sc0 != nil || sp0 != nil {
                let tP = sc0.map { YB($0.K) } ?? -1e6, bP = sp0.map { YB($0.K) } ?? 1e6
                let gT = YU.map { max($0, tP) }
                fG = (gT, YD.enumerated().map { max(gT[$0.offset], min($0.element, bP)) })
                if sc0 != nil { fU = (YU, YU.enumerated().map { max($0.element, min(YD[$0.offset], tP)) }) }
                if sp0 != nil { fD = (YD.enumerated().map { min($0.element, max(YU[$0.offset], bP)) }, YD) }
            }
            var dots: [(id: String, x: Double, y: CGFloat, put: Bool)] = [], drops: [(id: String, x: Double, y: CGFloat, put: Bool, day: String)] = []
            for g in nG {
                guard let r = reachOf(g) else { continue }
                let yy = Y(g.K); guard yy >= 0 && yy <= CH else { continue }
                let x = endX + (1 - endX) * (r / Double(FD))
                dots.append((id: "cd" + g.kk, x: x, y: yy, put: g.put))
                if g.kk == nC1?.kk || g.kk == nP1?.kk { drops.append((id: "dr" + g.kk, x: x, y: yy, put: g.put, day: dayOf(r))) }
            }
            coneOut = Cone(X: X, YU: YU, YD: YD, fG: fG, fU: fU, fD: fD, lo: S0 * exp(-m0), hi: S0 * exp(m0), dots: dots, drops: drops)
        }

        // The labels under the chart: Last week and This week (Nik, 17 Nov 2026), and with the cone on the day it first
        // reaches the nearest sold strike a side, under its drop line, in the strike's colour.
        var bd = -1
        for d in 0..<nR where dow(sl[d + 1].0) < dow(sl[d].0) { bd = d }
        var xls: [Label] = []
        if bd > 0 { xls.append(Label(id: 0, x: 0, t: "Last week", now: false)) }
        xls.append(Label(id: 1, x: Double(max(0, bd) * 7) / U, t: "This week", now: true))
        if coneOn, let c = coneOut {
            var last: (x: Double, t: String)?
            for q in c.drops.sorted(by: { $0.x < $1.x }) {
                if let l = last, l.t == q.day || q.x - l.x < 0.10 { continue }
                xls.append(Label(id: 2 + xls.count, x: q.x, t: q.day, now: false, put: q.put)); last = (q.x, q.day)
            }
        }
        let move = S0 / sl[0].1 - 1
        var out = PosPrice(pts: pts, up: move >= 0, move: move, dotX: pts[pts.count - 1].x, dotY: Y(S0), lines: lines, tags: tags, conn: conn,
                           xl: xls, fridayWords: dayWords(FT.last ?? fri), lo: a0, hi: b0)
        out.m0 = m0; out.coneOk = coneOk; out.coneOn = coneOn; out.lo0 = A0; out.hi0 = B0
        out.room = room; out.near = near; out.cone = coneOut
        return out
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
    private var payKey = "", payV: PosName.Payoff?
    private var everyKey = "", everyV: PosEvery?
    private var strikesKey = "", strikesV: PosStrikes?
    private var triesKey = "", triesV: [PosTryLeg] = []

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
    func payoff(key: String, _ make: () -> PosName.Payoff?) -> PosName.Payoff? {
        if key == payKey { return payV }
        let v = make(); payKey = key; payV = v; return v
    }
    func every(key: String, _ make: () -> PosEvery) -> PosEvery {
        if key == everyKey, let v = everyV { return v }
        let v = make(); everyKey = key; everyV = v; return v
    }
    func strikes(key: String, _ make: () -> PosStrikes?) -> PosStrikes? {
        if key == strikesKey { return strikesV }
        let v = make(); strikesKey = key; strikesV = v; return v
    }
    func tries(key: String, _ make: () -> [PosTryLeg]) -> [PosTryLeg] {
        if key == triesKey { return triesV }
        let v = make(); triesKey = key; triesV = v; return v
    }
}
