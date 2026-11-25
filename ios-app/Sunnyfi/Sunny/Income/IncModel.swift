//
//  IncModel.swift
//  Sunny
//
//  Income (handoff 2026-11-24 §1, handoff-2026-11-24-income SunnyIncome.dc.html): payload.income (sunny-home
//  income.ts) decoded once per build into the words Income today and the Income tab draw. Never built in a body:
//  BriefState.setIncome builds it when a new build lands.
//
//  The row for a rung (SunnyIncome ln9, README 1.2): the big kept % (red in the money or at a loss, green ready to
//  roll at 90%, grey otherwise), the title ("Roll 195 call ×2", "Hold 36 call ×72", in the money "195 call ×2"; Income
//  today adds the ticker), the action in the big number's colour ("to Nov 20 205 for 1.85", "17% to the roll",
//  "Down 0.40 a share", "In the money by 2.10") and a grey line only for a roll or in the money. In the money is
//  flagged only, never advice. A roll with no listed strike shows no strike: one is never invented.
//
//  No em dashes, no minus signs (red says negative) in any words here.
//

import SwiftUI

/// A colour role: resolved to light and dark in the views (IncC.of).
nonisolated enum IncTone: Hashable { case ink, mu, quiet, red, green }

// MARK: - A rung

nonisolated struct IncRung: Identifiable, Hashable {
    struct Next: Hashable { let ex: String; let exL: String; let K: Double?; let pr: Double?; let z: Double; let d: Double? }
    let id: String
    let t: String
    let call: Bool
    let K: Double
    let ex: String
    let exL: String
    /// Calendar days to the expiry.
    let days: Int
    let q: Int
    let at: Double
    let mk: Double?
    /// Kept % (1 - mark ÷ sold at); below 0 is a loss.
    let kp: Int?
    /// SD from the strike now; below 0 is in the money.
    let sN: Double?
    let itm: Bool
    let intr: Double
    let be: Double
    let books: [String]
    /// Ready to roll (90% kept, not in the money).
    let roll: Bool
    let next: Next?

    init?(_ j: JSONValue) {
        guard let t = j["t"].string, let K = j["K"].double, let ex = j["ex"].string else { return nil }
        self.t = t
        self.K = K
        self.ex = ex
        call = j["ty"].string == "c"
        id = j["k"].string ?? "\(t)|\(call ? "call" : "put")|\(K)|\(ex)"
        exL = j["exL"].string ?? IncFmt.md(ex)
        days = Int(j["days"].double ?? 0)
        q = Int(j["q"].double ?? 0)
        at = j["at"].double ?? 0
        mk = j["mk"].double
        kp = j["kp"].double.map { Int($0.rounded()) }
        sN = j["sN"].double
        itm = j["itm"].bool || j["st"].string == "itm"
        intr = j["intr"].double ?? 0
        be = j["be"].double ?? (call ? K + at : K - at)
        books = j["books"].array.compactMap(\.string)
        roll = !itm && (j["st"].string == "roll" || (kp ?? 0) >= 90 && j["st"].isNull)
        let n = j["next"]
        if case .object = n, let nex = n["ex"].string {
            next = Next(ex: nex, exL: n["exL"].string ?? IncFmt.md(nex), K: n["K"].double, pr: n["pr"].double,
                        z: n["z"].double ?? (call ? 0.5 : 1), d: n["d"].double)
        } else { next = nil }
    }

    /// "NKE 36 call" / "36 call".
    func name(ticker: Bool) -> String { (ticker ? t + " " : "") + IncFmt.fk(K) + (call ? " call" : " put") }
}

// MARK: - The row's words

nonisolated struct IncLine: Identifiable, Hashable {
    let id: String
    let big: String
    let bigTone: IncTone
    let title: String
    let titleTone: IncTone
    let date: String
    let action: String
    let actionTone: IncTone
    let sub: String?
    let speech: String

    /// SunnyIncome ln9(r, tk): `ticker` adds the name to the title (Income today).
    static func of(_ r: IncRung, ticker: Bool) -> IncLine {
        let kk = r.name(ticker: ticker) + " ×\(r.q)"
        let kp = r.kp
        let loss = (kp ?? 0) < 0
        let big = kp.map { "\(abs($0))%" } ?? ""
        let bigTone: IncTone = r.itm || loss ? .red : r.roll ? .green : .quiet
        let title = (r.itm ? "" : r.roll ? "Roll " : "Hold ") + kk
        let titleTone: IncTone = r.itm || r.roll ? .ink : .quiet
        let action: String
        var sub: String?
        if r.itm {
            action = "In the money by \(IncFmt.f2(r.intr))"
            sub = "Breakeven \(IncFmt.f2(r.be)) · \(IncFmt.left(r.days)) · flagged, you decide"
        } else if r.roll {
            let wait = (kp ?? 100) < 95 ? "or wait for 95%" : nil
            if let n = r.next {
                // "to Nov 20 205 for 1.85": the strike and the price only when the chain lists them.
                action = "to \(n.exL)" + (n.K.map { " " + IncFmt.fk($0) } ?? "") + (n.K != nil ? n.pr.map { " for " + IncFmt.f2($0) } ?? "" : "")
                var parts: [String] = []
                if n.K != nil, let pr = n.pr {
                    let d = n.d ?? (pr - r.at)
                    parts.append(abs(d) < 0.005 ? "the same as this one" : "\(d > 0 ? "↑" : "↓") \(IncFmt.f2(abs(d))) vs this one")
                }
                parts.append("\(IncFmt.fk(n.z)) SD from today")
                if let wait { parts.append(wait) }
                sub = parts.joined(separator: " · ")
            } else {
                action = "Ready to roll"
                sub = wait.map { $0.prefix(1).uppercased() + $0.dropFirst() }
            }
        } else if let kp, kp < 0, let mk = r.mk {
            action = "Down \(IncFmt.f2(mk - r.at)) a share"
        } else if let kp {
            action = "\(90 - kp)% to the roll"
        } else {
            action = "No mark yet"
        }
        let actionTone: IncTone = r.itm ? .red : r.roll ? .green : .quiet
        let kept = kp.map { $0 < 0 ? "\(abs($0)) percent lost" : "\($0) percent kept" } ?? "no mark"
        let speech = IncSay.words("\(title), \(r.exL). \(kept). \(action)." + (sub.map { " \($0)." } ?? ""))
        return IncLine(id: r.id, big: big, bigTone: bigTone, title: title, titleTone: titleTone, date: r.exL,
                       action: action, actionTone: actionTone, sub: sub, speech: speech)
    }
}

// MARK: - A name (its card on the Income tab)

nonisolated struct IncName: Identifiable, Hashable {
    struct Chip: Hashable { let k: String; let t: String; let tone: String }   // tone: itm | roll | run | next
    struct Day: Identifiable, Hashable {
        var id: String { d }
        let d: String; let lbl: String; let today: Bool; let past: Bool; let closed: Bool; let chips: [Chip]
    }
    /// The delta line (ladder names): the big ↑% (grey, red inside 3%), the plain words, one grey line of why.
    struct Flip: Hashable { let big: String; let tone: IncTone; let a: String; let b: String }
    var id: String { t }
    let t: String
    let co: String
    let books: [String]
    let ladder: Bool
    let px: Double
    let chg: Double?
    let flip: Flip?
    let cal: [Day]
    let lines: [IncLine]
    /// A dot on its logo only when the name needs you: red in the money, green to roll.
    let dot: IncTone?
}

// MARK: - The realized-income banner

nonisolated struct IncBanner: Hashable {
    struct CP: Hashable { let c: Double; let p: Double; var total: Double { c + p } }
    struct Period: Identifiable, Hashable {
        let id: String
        /// The bar's label: "Nov 23", "Nov".
        let l: String
        /// Over the total: "Last week · Nov 16 to 20", "November so far · to Tue Nov 24".
        let cap: String
        /// Not finished: the yield says "so far".
        let cur: Bool
        let c: Double
        let p: Double
        let by: [String: CP]
        let bk: [String: CP]
        var total: Double { c + p }
    }
    let capital: Double
    let weeks: [Period]
    let months: [Period]
    /// Each ticker's shares and share average after every premium kept (nil: no shares).
    let avg: [String: Double]
    let tickers: [String]
}

// MARK: - The whole of Income

nonisolated struct IncModel {
    let today: String
    let rungs: [IncRung]
    let names: [IncName]
    /// Income today: in the money (most in first), ready to roll (most kept first).
    let itm: [IncLine]
    let roll: [IncLine]
    /// The rungs that run on their own, and the nearest to a roll ("NKE 36 call Oct 30 at 73%").
    let quietCount: Int
    let near: String?
    /// The ladder names' delta lines, for Income today.
    let flips: [IncName.Flip]
    let left: Double
    let kept: Double
    let collected: Double
    let rollCount: Int
    let itmCount: Int
    let banner: IncBanner?

    var needCount: Int { itm.count + roll.count }

    static func build(_ j: JSONValue?) -> IncModel? {
        guard let j, case .object = j else { return nil }
        let today = j["today"].string ?? ""
        let rungs = j["rungs"].array.compactMap(IncRung.init)
        let byT = Dictionary(grouping: rungs, by: \.t)
        // A card's rows: calls by expiry and strike, then puts (SunnyIncome: n.c then n.p).
        func order(_ rs: [IncRung]) -> [IncRung] {
            rs.sorted { a, b in
                if a.call != b.call { return a.call }
                if a.ex != b.ex { return a.ex < b.ex }
                return a.K < b.K
            }
        }
        let names: [IncName] = j["names"].array.compactMap { n in
            guard let t = n["t"].string else { return nil }
            let rs = order(byT[t] ?? [])
            let ladder = n["cad"].string == "ladder"
            let px = n["px"].double ?? 0
            var flip: IncName.Flip?
            if ladder { flip = Self.flip(t, n["flip"], px: px) }
            let cal: [IncName.Day] = n["cal"].array.compactMap { d in
                guard let iso = d["d"].string else { return nil }
                return IncName.Day(d: iso, lbl: d["lbl"].string ?? IncFmt.md(iso), today: d["today"].bool, past: d["past"].bool,
                                   closed: d["closed"].bool,
                                   chips: d["chips"].array.map { IncName.Chip(k: $0["k"].string ?? "", t: $0["t"].string ?? "", tone: $0["tone"].string ?? "run") })
            }
            let dot: IncTone? = rs.contains { $0.itm } ? .red : rs.contains { $0.roll } ? .green : nil
            return IncName(t: t, co: n["co"].string ?? t, books: n["books"].array.compactMap(\.string), ladder: ladder, px: px,
                           chg: n["chg"].double, flip: flip, cal: cal, lines: rs.map { IncLine.of($0, ticker: false) }, dot: dot)
        }
        let itm = rungs.filter(\.itm).sorted { ($0.sN ?? 0) < ($1.sN ?? 0) }
        let roll = rungs.filter(\.roll).sorted { ($0.kp ?? 0) > ($1.kp ?? 0) }
        let quiet = rungs.filter { !$0.itm && !$0.roll }
        let near = quiet.filter { ($0.kp ?? -1) >= 0 }.max { ($0.kp ?? 0) < ($1.kp ?? 0) }
        let tot = j["totals"]
        let col = rungs.reduce(0) { $0 + $1.at * Double($1.q) * 100 }
        let lft = rungs.reduce(0) { $0 + ($1.mk ?? $1.at) * Double($1.q) * 100 }
        return IncModel(today: today, rungs: rungs, names: names,
                        itm: itm.map { IncLine.of($0, ticker: true) }, roll: roll.map { IncLine.of($0, ticker: true) },
                        quietCount: quiet.count,
                        near: near.map { "\($0.name(ticker: true)) \($0.exL) at \($0.kp ?? 0)%" },
                        flips: names.compactMap(\.flip),
                        left: tot["left"].double ?? lft, kept: tot["kept"].double ?? (col - lft), collected: tot["collected"].double ?? col,
                        rollCount: Int(tot["roll"].double ?? Double(roll.count)), itmCount: Int(tot["itm"].double ?? Double(itm.count)),
                        banner: banner(j["banner"], today: today))
    }

    /// The delta line: how far the stock can rise before the name's book turns short (red inside 3%). The server looks
    /// up to a 40% rise; none found means the shares outweigh the calls sold that far.
    private static func flip(_ t: String, _ f: JSONValue, px: Double) -> IncName.Flip {
        if f["now"].bool {
            return .init(big: "Now", tone: .red, a: "\(t) is short now, at \(IncFmt.f2(px))",
                         b: "")
        }
        if let price = f["price"].double, let up = f["up"].double ?? (px > 0 ? (price / px - 1) * 100 : nil) {
            return .init(big: "↑" + String(format: "%.1f", up) + "%", tone: up < 3 ? .red : .quiet,
                         a: "until \(t) turns short, at \(IncFmt.f2(price))",
                         b: "")
        }
        return .init(big: "↑40%+", tone: .quiet, a: "\(t) stays long", b: "")
    }

    private static func banner(_ b: JSONValue, today: String) -> IncBanner? {
        guard case .object = b else { return nil }
        func cp(_ v: JSONValue) -> IncBanner.CP { .init(c: v[0].double ?? 0, p: v[1].double ?? 0) }
        func map(_ v: JSONValue) -> [String: IncBanner.CP] { v.object.mapValues(cp) }
        let todayLong = IncFmt.dmd(today)
        let wk = b["weeks"].array
        let weeks: [IncBanner.Period] = wk.enumerated().map { i, w in
            let range = w["range"].string ?? ""
            let cur = w["cur"].bool
            // The week under way "so far"; on a weekend the week just ended is this week. The one before is last week.
            let fromEnd = wk.count - 1 - i
            let cap: String
            if cur { cap = "This week so far · to \(todayLong)" }
            else if fromEnd == 0 { cap = "This week · \(range)" }
            else if fromEnd == 1 { cap = "Last week · \(range)" }
            else { cap = "Week of \(range)" }
            return .init(id: "w" + (w["k"].string ?? "\(i)"), l: w["l"].string ?? "", cap: cap, cur: cur,
                         c: w["c"].double ?? 0, p: w["p"].double ?? 0, by: map(w["by"]), bk: map(w["bk"]))
        }
        let months: [IncBanner.Period] = b["months"].array.enumerated().map { i, m in
            let long = m["long"].string ?? m["l"].string ?? ""
            let cur = m["cur"].bool
            let cap = cur ? "\(long) so far · to \(todayLong)" : m["from"].string.map { "\(long) · from \($0)" } ?? long
            return .init(id: "m" + (m["k"].string ?? "\(i)"), l: m["l"].string ?? "", cap: cap, cur: cur,
                         c: m["c"].double ?? 0, p: m["p"].double ?? 0, by: map(m["by"]), bk: map(m["bk"]))
        }
        var avg: [String: Double] = [:]
        for (t, s) in b["shares"].object { if let a = s["avg"].double, (s["sh"].double ?? 0) > 0 { avg[t] = a } }
        var tickers = Set(b["shares"].object.keys)
        for p in weeks + months { tickers.formUnion(p.by.keys) }
        return IncBanner(capital: b["capital"].double ?? 0, weeks: weeks, months: months, avg: avg, tickers: tickers.sorted())
    }
}

// MARK: - Words

nonisolated enum IncFmt {
    private static let MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let DOW = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// "2.10"
    static func f2(_ x: Double) -> String { String(format: "%.2f", x) }
    /// A strike as JS String(+x.toFixed(2)): "36", "36.5", "167.5", "0.25".
    static func fk(_ x: Double) -> String {
        var s = String(format: "%.2f", x)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
        return s
    }
    /// Book money in K and M ($624, $5.9K, $13.7K, $379K, $1.2M), never a sign; "$•••" with privacy on.
    static func money(_ x: Double, _ privacy: Bool) -> String {
        if privacy { return "$•••" }
        let a = abs(x)
        func s1(_ v: Double, _ u: String) -> String { var t = String(format: "%.1f", v); if t.hasSuffix(".0") { t.removeLast(2) }; return "$" + t + u }
        if a >= 999_500 { return s1(a / 1e6, "M") }
        if a >= 99_950 { return "$\(Int((a / 1000).rounded()))K" }
        if a >= 999.5 { return s1(a / 1000, "K") }
        return "$\(Int(a.rounded()))"
    }
    /// Whole dollars with commas ("$6,666"), never a sign; "$•••" with privacy on.
    static func dollars(_ x: Double, _ privacy: Bool) -> String {
        if privacy { return "$•••" }
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: abs(x).rounded())) ?? "0")
    }
    /// "3 days left", "1 day left", "last day".
    static func left(_ days: Int) -> String { days <= 0 ? "last day" : days == 1 ? "1 day left" : "\(days) days left" }
    /// "2026-11-27" → "Nov 27".
    static func md(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return iso }
        return "\(MON[p[1] - 1]) \(p[2])"
    }
    /// "2026-11-24" → "Tue Nov 24".
    static func dmd(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return iso }
        var c = DateComponents(); c.year = p[0]; c.month = p[1]; c.day = p[2]; c.hour = 12
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        guard let d = cal.date(from: c) else { return md(iso) }
        return "\(DOW[cal.component(.weekday, from: d) - 1]) \(md(iso))"
    }
}

/// VoiceOver words: arrows, ×, short months and days said in full.
nonisolated enum IncSay {
    private static let full: [String: String] = [
        "Jan": "January", "Feb": "February", "Mar": "March", "Apr": "April", "Jun": "June", "Jul": "July", "Aug": "August",
        "Sep": "September", "Oct": "October", "Nov": "November", "Dec": "December",
        "Mon": "Monday", "Tue": "Tuesday", "Wed": "Wednesday", "Thu": "Thursday", "Fri": "Friday"]
    private static let shortRE = try! NSRegularExpression(pattern: #"\b(Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Oct|Nov|Dec|Mon|Tue|Wed|Thu|Fri)\b"#)
    static func words(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "×", with: " times ").replacingOccurrences(of: "↑", with: "up ")
            .replacingOccurrences(of: "↓", with: "down ").replacingOccurrences(of: "$•••", with: "hidden")
            .replacingOccurrences(of: "  ", with: " ")
        let ns = t as NSString
        for m in shortRE.matches(in: t, range: NSRange(location: 0, length: ns.length)).reversed() {
            if let r = Range(m.range, in: t), let w = full[ns.substring(with: m.range)] { t.replaceSubrange(r, with: w) }
        }
        return t
    }
}
