//
//  SDLegs.swift
//  Sunny
//
//  SD on your positions (handoff 11 Nov 2026, App Explorations 139a). Every option leg held gets three short lines on
//  the right of its row: how far its strike is from today in dollars, the same distance in SD by that leg's own expiry,
//  and the odds in your favour (a sold leg expires worthless, a bought leg ends in the money). Shares get nothing.
//
//  ⚠ THE MATHS IS THE SHARED ENGINE'S, PORTED LINE FOR LINE (supabase/functions/_shared/sd-engine.ts tradingYears,
//  legSd, N, f2, pc), so the app, the web and the calculator read the same for the same strike and expiry. Change it
//  there first. Nik, 11 Nov 2026: each leg's OWN IV (from its price), not the expiry's ATM IV; orange ("needs a look",
//  sold legs only) when in the money, within 0.5 SD, or under 70% to expire worthless; a bought leg in the money stays
//  ink. Prices and odds, not the book's dollars: they stay visible with privacy on.
//

import Foundation

enum SDLegs {
    /// sd-engine.ts LegSd: in the money, the distance in dollars and in SD, the chance it ends in the money, the odds in
    /// your favour, whether it needs a look, and the three lines.
    struct Lines: Equatable {
        let itm: Bool
        let away: Double
        let sd: Double
        let pItm: Double
        let odds: Double
        let look: Bool
        let sold: Bool
        let l1: String
        let l2: String
        let l3: String
        /// Line 3 orange: a sold leg under a 70% chance to expire worthless.
        var lowOdds: Bool { sold && odds < 0.7 }
    }

    /// JavaScript's toFixed, digit for digit: rounds the double's exact decimal value, a tie going up. ("%.2f" sends an
    /// exact tie such as 1.125 to even, and x × 100 can land on a tie that is not one: 2.675 is 2.67499999…)
    static func fixed(_ x: Double, _ d: Int) -> String {
        guard x.isFinite else { return String(x) }
        let s = String(format: "%.30f", abs(x)), parts = s.split(separator: ".", omittingEmptySubsequences: false)
        let frac = Array(parts.count > 1 ? parts[1] : "")
        var digits = Array(parts[0]) + Array(frac.prefix(d))
        if frac.count > d, frac[d] >= "5" {
            var i = digits.count - 1
            while i >= 0 {
                if digits[i] == "9" { digits[i] = "0"; i -= 1 } else { digits[i] = Character(String(digits[i].wholeNumberValue! + 1)); break }
            }
            if i < 0 { digits.insert("1", at: 0) }
        }
        let cut = digits.count - d, out = String(digits[..<cut]) + (d > 0 ? "." + String(digits[cut...]) : "")
        return x < 0 ? "-" + out : out
    }
    static func f2(_ x: Double) -> String { fixed(x, 2) }
    /// sd-engine.ts pc: a percentage, one decimal, two under 0.1%; never a sign.
    static func pc(_ x: Double) -> String {
        let a = abs(x) * 100
        return (a < 0.1 ? fixed(a, 2) : fixed(a, 1)) + "%"
    }

    /// sd-engine.ts tradingYears: trading days after `today` through `ex` (weekends and `closed` days left out) over 252;
    /// on the expiry day (none left), the hours left / (6.5 × 252), at least a quarter hour. `mins`: New York minutes now.
    static func tradingYears(today: String, ex: String, closed: Set<String>, mins: Int) -> Double {
        var n = 0
        if let d0 = day(today), let d1 = day(ex), d1 > d0 {
            for d in (d0 + 1)...d1 {
                let w = ((d % 7) + 11) % 7   // 1970-01-01 (day 0) was a Thursday: 0 Sunday ... 6 Saturday
                if w != 0 && w != 6 && !closed.contains(iso(d)) { n += 1 }
            }
        }
        return n > 0 ? Double(n) / 252 : max(0.25, Double(16 * 60 - mins) / 60) / (6.5 * 252)
    }

    /// sd-engine.ts legSd. `exLabel` is the leg's expiry as its row writes it ("Oct 30", "Sep ’27").
    static func legSd(S: Double, K: Double, put: Bool, sold: Bool, iv: Double, T: Double, exLabel: String) -> Lines {
        let m = max(1e-6, iv * max(T, 1e-6).squareRoot()), x = log(K / S)
        let itm = put ? K > S : K < S
        let pItm = put ? SDFmt.N(x / m) : SDFmt.N(-x / m), sd = abs(x) / m, odds = sold ? 1 - pItm : pItm
        let look = sold && (itm || sd < 0.5 || odds < 0.7)
        return Lines(itm: itm, away: abs(K - S), sd: sd, pItm: pItm, odds: odds, look: look, sold: sold,
                     l1: itm ? "In the money" : "$\(f2(abs(K - S))) away",
                     l2: itm ? "" : "\(fixed(sd, 2)) SD by \(exLabel)",
                     l3: sold ? "\(pc(odds)) expires worthless" : "\(pc(pItm)) ends in the money")
    }

    /// One leg's lines on Positions (null for shares, or with no price or expiry): its own IV when it has one worth the
    /// name (over 3%, as the web), else the name's IV; today in New York and the market's closed days from Home.
    static func lines(S: Double, K: Double, put: Bool, sold: Bool, ownIV: Double?, nameIV: Double, ex: String, exLabel: String,
                      now: Date, closed: Set<String>) -> Lines? {
        let iv = (ownIV ?? 0) > 0.03 ? ownIV! : nameIV
        guard S > 0, K > 0, iv > 0, day(ex) != nil else { return nil }
        let t = MarketClock.ny(now)
        return legSd(S: S, K: K, put: put, sold: sold, iv: iv, T: tradingYears(today: t.date, ex: ex, closed: closed, mins: t.minutes), exLabel: exLabel)
    }

    /// VoiceOver: the three lines in words ("1.32 dollars away, 0.46 SD by November 13, 67.8 percent expires
    /// worthless, needs a look"); no minus signs.
    static func said(_ l: Lines) -> String {
        var s = l.itm ? "In the money" : "\(f2(l.away)) dollars away, \(l.l2)"
        s += ", " + l.l3.replacingOccurrences(of: "%", with: " percent")
        if l.look { s += ", needs a look" }
        return SDFmt.words(s)
    }

    // MARK: Days as integers (fast enough to run in a row's body)

    /// "2026-11-13" as days since 1970-01-01 (Howard Hinnant's days_from_civil).
    static func day(_ s: String) -> Int? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]), (1...31).contains(p[2]) else { return nil }
        let y = p[0] - (p[1] <= 2 ? 1 : 0), era = (y >= 0 ? y : y - 399) / 400, yoe = y - era * 400
        let mp = (p[1] + 9) % 12, doy = (153 * mp + 2) / 5 + p[2] - 1, doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }
    /// Days since 1970-01-01 as "2026-11-13" (civil_from_days).
    static func iso(_ z0: Int) -> String {
        let z = z0 + 719468, era = (z >= 0 ? z : z - 146096) / 146097, doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365, doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153, d = doy - (153 * mp + 2) / 5 + 1, m = mp < 10 ? mp + 3 : mp - 9
        return String(format: "%04d-%02d-%02d", yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }
}
