//
//  SampleEngine.swift
//  Sunny
//
//  The prototype's position maths on the sample book (sample mode only), ported line for line from
//  SunnyBriefs.dc.html rv46 (Your position) so the screens can be checked against the design's numbers
//  (engine-notes.md, "Expected values"). Black-Scholes with no rate and no dividend, one IV per name, this
//  week's sold legs 3 days out, long legs by their expiry. From Pass 2 the server's engine fills the same
//  view model with each leg's own IV, a 4% rate and dividends counted (answers C4 and C5, 6 Nov 2026).
//

import Foundation

enum SampleEngine {
    // MARK: Black-Scholes as the prototype has it

    static func erf(_ x: Double) -> Double {
        let g: Double = x < 0 ? -1 : 1, a = abs(x), q = 1 / (1 + 0.3275911 * a)
        return g * (1 - (((((1.061405429 * q - 1.453152027) * q) + 1.421413741) * q - 0.284496736) * q + 0.254829592) * q * exp(-a * a))
    }
    static func N(_ x: Double) -> Double { 0.5 * (1 + erf(x / 2.squareRoot())) }
    static func bs(_ S: Double, _ K: Double, _ T: Double, _ v: Double, put: Bool) -> Double {
        if T <= 0 { return put ? max(K - S, 0) : max(S - K, 0) }
        let sq = v * T.squareRoot(), d1 = (log(S / K) + v * v / 2 * T) / sq, c = S * N(d1) - K * N(d1 - sq)
        return put ? c - S + K : c
    }
    static func delta(_ S: Double, _ K: Double, _ T: Double, _ v: Double, put: Bool) -> Double {
        let TT = max(T, 0.02 / 365), d1 = (log(S / K) + v * v / 2 * TT) / (v * TT.squareRoot())
        return N(d1) - (put ? 1 : 0)
    }

    // MARK: Legs

    enum Ty { case shares, call, put }
    struct Leg { let ty: Ty; let K: Double; let q: Double; let T: Double }

    struct Name {
        let t: String; let S0: Double; let v: Double; let sd: Double; let legs: [Leg]; let t0: Double
        func value(_ l: Leg, _ S: Double, _ tt: Double) -> Double {
            l.ty == .shares ? l.q * S : l.q * 100 * SampleEngine.bs(S, l.K, max(0, l.T - tt) / 365, v, put: l.ty == .put)
        }
        func dt(_ l: Leg, _ S: Double, _ tt: Double) -> Double {
            l.ty == .shares ? l.q : l.q * 100 * SampleEngine.delta(S, l.K, max(0, l.T - tt) / 365, v, put: l.ty == .put)
        }
        /// P&L (from now), net delta and long delta if the name moves m % and it is tt days on.
        func at(_ m: Double, _ tt: Double) -> (p: Double, n: Double, lg: Double) {
            let S = S0 * (1 + m / 100)
            var p = 0.0, n = 0.0, lg = 0.0
            for l in legs {
                p += value(l, S, tt) - value(l, S0, t0)
                let x = dt(l, S, tt); n += x
                if l.q > 0 && l.ty != .put { lg += x }
            }
            return (p, n, lg)
        }
    }

    /// The clock in the prototype: days into today (pre 0, market .3, post .5, weekend 4) and days to the
    /// close the card is about (Friday 2.9; the weekend, next Friday 9.9). Weekend leaves this week's sold legs out.
    static func clock(_ m: Moment) -> (t0: Double, th: Double, wk: Bool) {
        switch m {
        case .futures, .pre: (0, 2.9, false)
        case .bell, .open, .last20, .last5: (0.3, 2.9, false)
        case .post: (0.5, 2.9, false)
        case .weekend: (4, 9.9, true)
        }
    }

    static func names(acct: String, moment: Moment) -> [Name] {
        let (t0, _, wk) = clock(moment)
        let book = SampleBook.book(acct)
        return SampleBook.names.compactMap { t in
            guard let b = book[t], let q = SampleBook.q[t] else { return nil }
            var L = [Leg(ty: .shares, K: 0, q: Double(b.shares), T: 0)]
            if !wk { for s in b.sold { L.append(Leg(ty: s.put ? .put : .call, K: s.k, q: -Double(s.q), T: 3)) } }
            for x in b.bought { L.append(Leg(ty: x.put ? .put : .call, K: x.k, q: Double(x.q), T: Double(SampleBook.longDays[x.ex] ?? 300))) }
            let v = SampleBook.iv[t] ?? 0.35
            return Name(t: t, S0: q.0, v: v, sd: v * (5.0 / 252).squareRoot() * 100, legs: L, t0: t0)
        }
    }

    // MARK: Money as the prototype writes it

    /// Money in K and M, the design's `money()` (8 Nov 2026, README 11.5): $624, $5.9K, $13.7K, $379K, $1.2M,
    /// no trailing .0 ($2K). Stock prices, strikes, index levels, dividends a share and the account value stay exact.
    static func fK(_ x: Double) -> String {
        let a = abs(x)
        func s1(_ v: Double, _ u: String) -> String {
            var t = String(format: "%.1f", v); if t.hasSuffix(".0") { t.removeLast(2) }
            return "$" + t + u
        }
        if a >= 999_500 { return s1(a / 1e6, "M") }
        if a >= 99_950 { return "$\(Int((a / 1000).rounded()))K" }
        if a >= 999.5 { return s1(a / 1000, "K") }
        return "$\(Int(a.rounded()))"
    }
    static func fn(_ x: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: abs(x).rounded())) ?? "0"
    }
    static func f1(_ x: Double) -> String { String(format: "%.1f", (x * 10).rounded() / 10) }
}

/// Your position, built (block 30). The same shape the server will send from Pass 2.
struct YourPositionModel {
    struct Row: Identifiable { let id: String; let name: String; let line: String; let lineColor: String; let right: String; let rightColor: String; let at: String; let st: Int }
    var subtitle: String
    var sentence: [BriefSpan]
    var grid: [Double]                 // % moves, −10 to +10 in .25
    var friday: [Double]               // P&L by Friday at each move
    var today: [Double]                // P&L today at each move
    var shortAt: Double?               // the move where the whole book turns short (orange line), inside +10%
    var stats: [(value: String, label: String, color: String)]
    var cover: String
    var assign: String?
    var count: String
    var countColor: String
    var rows: [Row]
    var aria: String

    static func sample(acct: String, moment: Moment) -> YourPositionModel {
        let E = SampleEngine.self
        let (t0, th, wk) = E.clock(moment)
        let NB = E.names(acct: acct, moment: moment)
        var M: [Double] = []; var m = -10.0
        while m <= 10.001 { M.append((m * 100).rounded() / 100); m += 0.25 }
        func bk(_ m: Double, _ tt: Double) -> (p: Double, n: Double, d: Double) {
            NB.reduce((0.0, 0.0, 0.0)) { a, x in let r = x.at(m, tt); return (a.0 + r.p, a.1 + r.n, a.2 + r.n * x.S0 * (1 + m / 100) / 100) }
        }
        let F = M.map { bk($0, th) }, Nw = M.map { bk($0, t0) }
        let fm = M.indices.first { M[$0] > 0 && F[$0].n < 0 }.map { M[$0] }
        let now = bk(0, t0)
        let names: [String: String] = ["BABA": "Alibaba", "LULU": "Lululemon", "NKE": "Nike", "NFLX": "Netflix", "UBER": "Uber", "FIS": "FIS", "PEP": "PepsiCo"]

        struct R { let t: String; let fp: Double?; let st: Int; let frac: Double; let n: Double }
        var rs: [R] = NB.map { x in
            let r = x.at(x.sd, th), thin = r.n >= 0 && r.n < 0.25 * r.lg, short = r.n < 0
            var fp: Double? = nil; var mm = 0.0
            while mm <= x.sd * 3 { if x.at(mm, th).n < 0 { fp = x.S0 * (1 + mm / 100); break }; mm += 0.05 }
            return R(t: x.t, fp: fp, st: short ? 2 : thin ? 1 : 0, frac: r.lg != 0 ? r.n / r.lg : 1, n: r.n)
        }
        rs.sort { $0.st != $1.st ? $0.st > $1.st : $0.frac < $1.frac }
        let byT = Dictionary(uniqueKeysWithValues: NB.map { ($0.t, $0) })
        let rows: [Row] = rs.map { r in
            let x = byT[r.t]!, nm = names[r.t] ?? r.t
            let line = r.fp.map { "Makes the most at $" + String(format: "%.2f", $0) + " by " + (wk ? "next Friday" : "Friday") }
                ?? (r.st == 1 ? "Thin by Friday, still gains as it rises" : "Keeps making more past ↑" + E.f1(x.sd * 3) + "%")
            return Row(id: r.t, name: nm, line: line, lineColor: r.fp != nil ? (r.st == 2 ? "red" : "orange") : "secondary",
                       right: r.st == 2 ? "Short " + E.fn(r.n) + " Δ" : r.st == 1 ? "Thin" : "Long " + E.fn(r.n) + " Δ",
                       rightColor: r.st == 2 ? "red" : r.st == 1 ? "orange" : "ink", at: "at ↑" + E.f1(x.sd) + "%", st: r.st)
        }
        let nS = rows.filter { $0.st == 2 }.count, nT = rows.filter { $0.st == 1 }.count
        let first = rs.first { $0.st > 0 }
        var story: [BriefSpan]
        if wk {
            story = [BriefSpan("This week’s calls ended Friday, so you are "), BriefSpan("long only", b: true),
                     BriefSpan(" until Monday’s sales: a 1% rise makes you "), BriefSpan(E.fK(now.d), b: true, c: "green"),
                     BriefSpan(". Selling again caps how much a rise can make.")]
        } else {
            story = [BriefSpan("Long now: a 1% rise makes you "), BriefSpan(E.fK(now.d), b: true, c: "green"), BriefSpan(". ")]
            if let fm {
                story += [BriefSpan("Your book makes the most if the market rises "), BriefSpan(E.f1(fm) + "%", b: true, c: "orange"),
                          BriefSpan(" by Friday" + (first.map { ". " + (names[$0.t] ?? $0.t) + " gets there first." } ?? "."))]
            } else {
                story += [BriefSpan("Your book keeps making more even if the market rises 10% by Friday")]
                if let f = first {
                    story += [BriefSpan(", but "), BriefSpan(names[f.t] ?? f.t, b: true, c: f.st == 2 ? "red" : "orange"),
                              BriefSpan(f.st == 2 && f.fp != nil ? " makes the most at $" + String(format: "%.2f", f.fp!) + "." : " runs thin.")]
                } else { story += [BriefSpan(".")] }
            }
        }
        let i0 = M.firstIndex(of: 0)!, pv = F[i0].p, up5 = F[M.firstIndex(of: 5)!].p, dn5 = F[M.firstIndex(of: -5)!].p
        let col = { (v: Double) in v < 0 ? "red" : "green" }
        let book = SampleBook.book(acct)
        var shT = 0, cvT = 0
        for t in SampleBook.names { if let b = book[t] { shT += b.shares; if let I = b.bought.first(where: { $0.kind == .ins }) { cvT += min(b.shares, I.q * 100) } } }
        let cover = "Insurance puts cover \(E.fn(Double(cvT))) of your \(E.fn(Double(shT))) shares, \(Int((Double(cvT) / Double(max(1, shT)) * 100).rounded()))%. Shares have no floor below that."
        let exw = SampleBook.names.filter { t in (SampleBook.dividends[t]?.days ?? 99) <= 7 && (book[t]?.sold.contains { !$0.put } ?? false) }
        let assign = exw.isEmpty ? nil : "Ex-dividend this week: " + exw.map { (names[$0] ?? $0) + " " + (SampleBook.dividends[$0]?.ex ?? "") }.joined(separator: ", ")
            + ". Calls in the money with less time value than the dividend can be assigned the day before."
        let sub: String = switch moment {
        case .futures, .pre: "Before the bell · by Friday’s close"
        case .bell, .open, .last20, .last5: "Now · by Friday’s close"
        case .post: "At the close · by Friday"
        case .weekend: "Calls ended Friday · to next Friday"
        }
        return YourPositionModel(
            subtitle: sub, sentence: story, grid: M, friday: F.map(\.p), today: Nw.map(\.p), shortAt: fm,
            stats: [(E.fK(up5), "if up 5%", col(up5)), (E.fK(pv), wk ? "flat to next Fri" : "flat to Friday", col(pv)), (E.fK(dn5), "if down 5%", col(dn5))],
            cover: cover, assign: assign,
            count: nS + nT > 0 ? [nS > 0 ? "\(nS) " + (nS == 1 ? "past its best" : "past their best") : nil, nT > 0 ? "\(nT) thin" : nil].compactMap { $0 }.joined(separator: ", ") + " at a priced move" : "Every name long at a priced move",
            countColor: nS > 0 ? "red" : nT > 0 ? "orange" : "secondary", rows: rows,
            aria: "Your position, P&L by \(wk ? "next Friday" : "Friday") if the market moves 10% down to 10% up. " + (fm.map { "Makes the most at a \(E.f1($0))% rise." } ?? "Keeps making more all the way up."))
    }
}
