//
//  SDKit.swift
//  Sunny
//
//  The SD calculator's colours (SunnySD.dc.html pal136, light / dark, README 1.8) and formats (card136: money $624,
//  $5.9K, $1.2M; strikes as 40, 42.5, 40.85; prices two decimals; % one decimal, two under 0.1; never a minus sign).
//

import SwiftUI

/// pal136, where it is not already one of the app's tokens.
enum SDPal {
    static let ink = S.ink                                         // #1D1D1F / #F5F5F7
    static let mu = S.secondary                                    // #6E6E73 / #98989D
    static let muT = S.dyn(0x5C5C61, 0xAEAEB2)                     // kickers, sub lines
    static let cd = S.sheetFill                                    // the sheet, text on a filled tile
    static let G = S.green                                         // #327133 / #65C466
    static let RD = S.red                                          // #BC2E30 / #FF6961
    static let OR = S.orangeDeep                                   // #A34B00 / #F2A93B
    /// Call blue and put brown (README 1.8).
    static let CL = S.dyn(0x2E5ECA, 0x6FA0F6)
    static let PT = S.dyn(0x9A5B1F, 0xD49A5A)
    static let tile = S.dynA(0x767680, 0.08, 0x767680, 0.18)       // strike tiles
    static let trk = S.dynA(0x767680, 0.12, 0x767680, 0.24)        // expiry chips, the bars' track, the X
    static let ring = S.dynA(0x3C3C43, 0.3, 0xEBEBF5, 0.3)         // signal outlines, the grabber, count fields, today's line
    static let cdMu = S.dynA(0xFFFFFF, 0.72, 0x000000, 0.6)        // muted text on an ink tile
    static let rule = S.dynA(0x1D1D1F, 0.08, 0xFFFFFF, 0.10)       // 1 pt rules
    /// What the sale does (143a, lanes() TH): the panel's ring, the Calls and Puts cards, the bars' profit and loss,
    /// green and red text, their pills, and the grey pill.
    static let panelRing = S.dynA(0xE3E5E8, 1, 0xFFFFFF, 0.14)
    static let cardBg = S.dynA(0xF5F5F7, 1, 0xFFFFFF, 0.06)
    static let zG = S.dyn(0x34C759, 0x30D158)
    static let zR = S.dyn(0xFF3B30, 0xFF453A)
    static let gT = S.dyn(0x1F7A36, 0x30D158)
    static let rT = S.dyn(0xC4281C, 0xFF6961)
    static let gB = S.dynA(0x34C759, 0.14, 0x30D158, 0.14)
    static let rB = S.dynA(0xFF3B30, 0.12, 0xFF453A, 0.16)
    static let nB = S.dynA(0x767680, 0.12, 0x767680, 0.24)
    /// The ±1 SD band on the Positions chart (137a).
    static let band = S.dynA(0x767680, 0.10, 0x767680, 0.20)
    /// The solid strip behind the status bar while the half sheet holds the chart up (README 1.9): the page's own top.
    static let strip = S.dyn(0xEEF2F0, 0x0A0F0C)
    /// The page dimmed behind the full sheet (New Home iPhone Preview: rgba(0,0,0,.3)).
    static let dim = Color.black.opacity(0.3)
    static func side(_ put: Bool) -> Color { put ? PT : CL }
}

/// card136's formats.
enum SDFmt {
    /// The design's normal CDF (Abramowitz and Stegun 26.2.17), the same digits as sd135 (one copy, in SDSale).
    static func N(_ x: Double) -> Double { SDSale.N(x) }
    /// Two decimals as JavaScript's toFixed writes them (the web and sunny-sd round the same), never "-0.00".
    static func f2(_ x: Double) -> String { SDLegs.f2(abs(x) < 0.005 ? 0 : x) }
    /// A strike: 40, 42.5, 40.85.
    static func fk(_ x: Double) -> String {
        if x.truncatingRemainder(dividingBy: 1) == 0 { return String(Int(x)) }
        return Int((x * 100).rounded()) % 10 != 0 ? String(format: "%.2f", x) : String(format: "%.1f", x)
    }
    /// A size as a percentage, one decimal (two under 0.1%), no sign.
    static func pc(_ x: Double) -> String { SDLegs.pc(x) }
    /// ↑ or ↓ then the size.
    static func dir(_ x: Double) -> String { (x >= 0 ? "↑\u{00A0}" : "↓\u{00A0}") + pc(x) }
    /// "ATM", "0.25", "0.5", "1.0" (the table's SD column).
    static func sdNum(_ k: Double) -> String {
        k == 0 ? "ATM" : k.truncatingRemainder(dividingBy: 1) != 0 ? "\(k)" : String(format: "%.1f", k)
    }
    /// "ATM", "0.25 SD", "1.0 SD" (the tiles).
    static func sdl(_ k: Double) -> String { k < 0 ? "ITM" : k == 0 ? "ATM" : sdNum(k) + " SD" }
    /// "0.5 to 1.25 SD", "ATM to 1 SD" (the rows' range, D2).
    static func range(_ lo: Double, _ hi: Double) -> String {
        func g(_ v: Double) -> String { v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : "\(v)" }
        return (lo < 0 ? "ITM" : lo == 0 ? "ATM" : g(lo)) + " to " + g(hi) + " SD"
    }
    /// Money: $624, $5.9K, $1.2M.
    static func money(_ x: Double) -> String { SampleEngine.fK(x) }
    /// "1 call", "59 calls".
    static func count(_ n: Int, _ w: String) -> String { "\(n) \(w)\(n == 1 ? "" : "s")" }

    /// VoiceOver: a size as words ("up 3.4 percent"), never a minus sign.
    static func saidMove(_ x: Double) -> String { "\(x >= 0 ? "up" : "down") \(pc(x).dropLast()) percent" }
    /// VoiceOver: a percentage ("61.2 percent").
    static func saidPct(_ x: Double) -> String { "\(pc(x).dropLast()) percent" }
    /// VoiceOver: an SD ("at the money", "0.5 SD").
    static func saidSD(_ k: Double) -> String { k == 0 ? "at the money" : sdNum(k) + " SD" }

    private static let full: [String: String] = [
        "Jan": "January", "Feb": "February", "Mar": "March", "Apr": "April", "Jun": "June", "Jul": "July", "Aug": "August",
        "Sep": "September", "Oct": "October", "Nov": "November", "Dec": "December",
        "Mon": "Monday", "Tue": "Tuesday", "Wed": "Wednesday", "Thu": "Thursday", "Fri": "Friday", "Sat": "Saturday", "Sun": "Sunday"]
    private static let shortRE = try! NSRegularExpression(pattern: #"\b(Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Oct|Nov|Dec|Mon|Tue|Wed|Thu|Fri|Sat|Sun)\b"#)
    /// Words on screen as VoiceOver should say them: short months and days in full, arrows as up and down, % as
    /// percent, ± as plus or minus, ≈ as about, → as a pause (BriefWords.speech for the rest).
    static func words(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "±", with: " plus or minus ").replacingOccurrences(of: "≈", with: " about ")
            .replacingOccurrences(of: "→", with: ", ")
        let ns = t as NSString
        for m in shortRE.matches(in: t, range: NSRange(location: 0, length: ns.length)).reversed() {
            if let r = Range(m.range, in: t), let w = full[ns.substring(with: m.range)] { t.replaceSubrange(r, with: w) }
        }
        return BriefWords.speech(t)
    }
}

/// The pin (SunnySD.dc.html, 24 pt box: M9 3h6l-1 6 3 3v2H7v-2l3-3z, M12 14v7), stroked at the size it is given.
struct SDPinGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * s, y: r.minY + y * s) }
        var path = Path()
        path.move(to: p(9, 3)); path.addLine(to: p(15, 3)); path.addLine(to: p(14, 9)); path.addLine(to: p(17, 12))
        path.addLine(to: p(17, 14)); path.addLine(to: p(7, 14)); path.addLine(to: p(7, 12)); path.addLine(to: p(10, 9))
        path.closeSubpath()
        path.move(to: p(12, 14)); path.addLine(to: p(12, 21))
        return path
    }
}
