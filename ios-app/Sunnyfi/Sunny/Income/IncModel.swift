//
//  IncModel.swift
//  Sunny
//
//  Income (handoff 2026-11-24 late §1; SunnyIncome.dc.html, SunnyIncomeCal.dc.html): payload.income (sunny-home
//  income.ts) decoded once per build into the words the Home Sundial card draws (the tab is the Sundial board).
//  Never built in a body: BriefState.setIncome builds it when a new build lands.
//
//  The row for a rung on Income today (SunnyIncome ln9, README 1.2): the big kept % (red in the money or at a loss,
//  green ready to roll at 90%, grey otherwise), the title ("Roll 195 call ×2", "Hold 36 call ×72", in the money
//  "195 call ×2", with the ticker), the action in the big number's colour ("to Nov 20 205 for 1.85", "17% to the roll",
//  "Down 0.40 a share", "In the money by 2.10") and a grey line only for a roll or in the money. In the money is
//  flagged only, never advice. A roll with no listed strike shows no strike: one is never invented.
//
//  No em dashes in any words here. Since the focus look (25 Nov 2026) red is a mark only, so a lost % on its own
//  carries a minus (U+2212) and the views draw the tones through IncC.word.
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
        // Focus (25 Nov 2026): red no longer says a loss, so a lost % carries the minus (U+2212).
        let big = kp.map { ($0 < 0 ? "\u{2212}" : "") + "\(abs($0))%" } ?? ""
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

// MARK: - A name

nonisolated struct IncName: Identifiable, Hashable {
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
    /// Where its next rung lands (the calendar's dashed day).
    let nextEx: String?
    /// A dot on its pill only when the name needs you: red in the money, green to roll.
    let dot: IncTone?
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

    var needCount: Int { itm.count + roll.count }

    static func build(_ j: JSONValue?) -> IncModel? {
        guard let j, case .object = j else { return nil }
        let today = j["today"].string ?? ""
        let rungs = j["rungs"].array.compactMap(IncRung.init)
        let byT = Dictionary(grouping: rungs, by: \.t)
        let names: [IncName] = j["names"].array.compactMap { n in
            guard let t = n["t"].string else { return nil }
            let rs = byT[t] ?? []
            let ladder = n["cad"].string == "ladder"
            let px = n["px"].double ?? 0
            var flip: IncName.Flip?
            if ladder { flip = Self.flip(t, n["flip"], px: px) }
            let dot: IncTone? = rs.contains { $0.itm } ? .red : rs.contains { $0.roll } ? .green : nil
            return IncName(t: t, co: n["co"].string ?? t, books: n["books"].array.compactMap(\.string), ladder: ladder, px: px,
                           chg: n["chg"].double, flip: flip, nextEx: n["nextEx"].string, dot: dot)
        }
        let itm = rungs.filter(\.itm).sorted { ($0.sN ?? 0) < ($1.sN ?? 0) }
        let roll = rungs.filter(\.roll).sorted { ($0.kp ?? 0) > ($1.kp ?? 0) }
        let quiet = rungs.filter { !$0.itm && !$0.roll }
        let near = quiet.filter { ($0.kp ?? -1) >= 0 }.max { ($0.kp ?? 0) < ($1.kp ?? 0) }
        return IncModel(today: today, rungs: rungs, names: names,
                        itm: itm.map { IncLine.of($0, ticker: true) }, roll: roll.map { IncLine.of($0, ticker: true) },
                        quietCount: quiet.count,
                        near: near.map { "\($0.name(ticker: true)) \($0.exL) at \($0.kp ?? 0)%" },
                        flips: names.compactMap(\.flip))
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
