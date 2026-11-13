//
//  PositionsTheme.swift
//  Sunny
//
//  The Positions tab's colours, type and small drawn parts (handoff 2026-11-13-positions §4; App Explorations 154a).
//  The design is dark; every colour here is a light / dark pair so light mode keeps working on the app's light tokens.
//  The dark values are the design's: ink #F5F5F7, secondary #98989D, muted on tints #AEAEB2, quiet #8E8E93, green
//  #65C466, red #FF6961, orange #FF9F0A, touched #FFD60A, ceiling #86A8F0, floor #C8946A, technicals #4CC9D0 / #8FDDE2,
//  IV label #D4CEFF, the SD ramp oklch(0.86 0.03 282) to oklch(0.42 0.085 277) in six steps.
//

import SwiftUI

enum PC {
    static let ink = S.ink
    static let mu = S.secondary                          // #98989D: labels, sub lines
    static let muT = S.secondaryOnTint                   // #AEAEB2: muted on tints
    static let quiet = S.dyn(0x6E6E73, 0x8E8E93)         // #8E8E93: quiet words, the empty dash
    static let green = S.green
    static let red = S.red
    static let orange = S.act                            // #FF9F0A
    static let touched = S.dyn(0x8A6A00, 0xFFD60A)       // touched today
    static let touchedBright = Color(.sRGB, red: 1, green: 214 / 255, blue: 10 / 255, opacity: 1)
    static let ceiling = S.dyn(0x2F5AA8, 0x86A8F0)
    static let floor = S.dyn(0x995123, 0xC8946A)
    static let teal = S.dyn(0x0B6F75, 0x4CC9D0)
    static let teal2 = S.dyn(0x0B6F75, 0x8FDDE2)
    static let tealLabel = S.dyn(0x0B6F75, 0x7FE0E5)
    static let ivLabel = S.dyn(0x5446B8, 0xD4CEFF)
    static let ivBracket = S.dynA(0x5446B8, 0.7, 0xBEB4FF, 0.7)
    static let say = S.dyn(0x3A3A3C, 0xC7C7CC)
    /// The page under a dot's ring (#060807 in the design).
    static let page = S.dyn(0xF1F2F4, 0x060807)
    /// Rules between rows (.08), the strong rule over a total (.2), a box's ring (.14).
    static let rule = S.dynA(0x1D1D1F, 0.09, 0xFFFFFF, 0.08)
    static let ruleStrong = S.dynA(0x1D1D1F, 0.2, 0xFFFFFF, 0.2)
    static let boxRing = S.dynA(0x1D1D1F, 0.14, 0xFFFFFF, 0.14)
    static let boxRingOn = S.dynA(0x1D1D1F, 0.7, 0xF5F5F7, 0.7)
    /// Soft cards: Intelligence (.04) and the Book totals cards (.05), each with a .08 edge.
    static let cardFill = S.dynA(0x1D1D1F, 0.035, 0xFFFFFF, 0.04)
    static let totalsFill = S.dynA(0xFFFFFF, 0.6, 0xFFFFFF, 0.05)
    static let cardEdge = S.dynA(0x1D1D1F, 0.08, 0xFFFFFF, 0.08)
    /// A box's detail (the web's pop-up), in place.
    static let detailFill = S.dynA(0xFFFFFF, 0.97, 0x1C1C1E, 0.97)
    static let detailEdge = S.dynA(0x1D1D1F, 0.12, 0xFFFFFF, 0.12)
    static let closeFill = S.dynA(0x767680, 0.16, 0x767680, 0.24)
    /// The lanes' tints (.06 in the design; a touch more on light).
    static let tintIV = S.dynA(0x967CE8, 0.08, 0x967CE8, 0.06)
    static let tintSD = S.dynA(0x8080DC, 0.08, 0x8080DC, 0.06)
    static let tintW = S.dynA(0x86A8F0, 0.10, 0x86A8F0, 0.06)
    static let tintT = S.dynA(0x4CC9D0, 0.10, 0x4CC9D0, 0.06)
    static let tintMv = S.dynA(0x1D1D1F, 0.03, 0xFFFFFF, 0.035)
    static let tintH = S.dynA(0x65C466, 0.10, 0x65C466, 0.06)
    /// Today's line through the lanes, and a closed-through line.
    static let today = S.dynA(0x1D1D1F, 0.85, 0xF5F5F7, 0.85)
    static let faint = S.dynA(0x1D1D1F, 0.06, 0xFFFFFF, 0.06)
    /// The name strip's circles: a .07 fill, a 1.5 pt .2 ring (the selected one 3 pt in ink).
    static let stripFill = S.dynA(0x1D1D1F, 0.05, 0xFFFFFF, 0.07)
    static let stripRing = S.dynA(0x1D1D1F, 0.2, 0xFFFFFF, 0.2)
    static let rangeBar = S.dynA(0x1D1D1F, 0.10, 0xFFFFFF, 0.10)
    static let sdBand = S.dynA(0x8080DC, 0.10, 0x8080DC, 0.08)
    static let lossLine = S.dynA(0xBC2E30, 0.45, 0xFF6961, 0.45)
    static let labelBg = S.dynA(0xF1F2F4, 0.9, 0x060807, 0.86)
    static let onInk = S.dyn(0xFFFFFF, 0x000000)
    static let dot = S.dyn(0x1D1D1F, 0xFFFFFF)
    static let dotRing = S.dynA(0xFFFFFF, 0.9, 0x000000, 0.6)

    /// A colour role from the model.
    static func of(_ t: PTone) -> Color {
        switch t {
        case .ink: ink
        case .mu: mu
        case .muT: muT
        case .quiet: quiet
        case .green: green
        case .red: red
        case .orange: orange
        case .touched: touched
        case .ceiling: ceiling
        case .floor: floor
        case .teal: teal
        case .teal2: teal2
        case .sd(let i): ramp[max(0, min(ramp.count - 1, i))]
        }
    }
    static func tone(_ t: PE.Tone) -> Color { t == .red ? red : t == .orange ? orange : muT }

    /// oklch to sRGB (CSS Color 4), for the SD ramp and the IV strip.
    static func oklch(_ L: Double, _ C: Double, _ h: Double) -> Color {
        let hr = h * .pi / 180, a = C * cos(hr), b = C * sin(hr)
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b, m_ = L - 0.1055613458 * a - 0.0638541728 * b, s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let lin = [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s, -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                   -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s]
        let g = lin.map { x -> Double in let v = max(0, min(1, x)); return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055 }
        return Color(.sRGB, red: g[0], green: g[1], blue: g[2], opacity: 1)
    }
    /// The SD ramp, nearest level first (PE.LV): 0.25, 0.5, 0.75, 1, 1.5, 2.
    static let ramp: [Color] = [oklch(0.86, 0.03, 282), oklch(0.77, 0.055, 281), oklch(0.68, 0.08, 280), oklch(0.59, 0.095, 279), oklch(0.50, 0.095, 278), oklch(0.42, 0.085, 277)]
    /// The IV strip: brighter is richer (0 to 1 across the strikes shown).
    static func iv(_ r: Double) -> Color { oklch(0.3 + 0.42 * r, 0.05 + 0.12 * r, 282) }
}

/// The design's type: Inter at size/line, weight, tracking as a fraction of the size.
enum PT {
    static func t(_ size: CGFloat, _ line: CGFloat, _ w: CGFloat = 400, tr: CGFloat = 0) -> SType { SType(size: size, weight: w, line: line, tracking: tr) }
    static let title = t(34, 40, 700, tr: -0.03)
    static let section = t(20, 26, 700)
    static let kicker = t(11, 14, 600, tr: 0.05)
}

/// The glass recipe (README §4): a 160° white sheen and a light edge. Light mode: the app's white tile.
struct PosGlass: ViewModifier {
    let radius: CGFloat
    var on = false
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                if on { shape.fill(scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.07)) }
                else if scheme == .dark {
                    shape.fill(LinearGradient(stops: [.init(color: .white.opacity(0.10), location: 0), .init(color: .white.opacity(0.03), location: 0.5),
                                                      .init(color: .white.opacity(0.07), location: 1)],
                                              startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1)))
                } else { shape.fill(Color.white.opacity(0.7)) }
            }
            .overlay { shape.strokeBorder(scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08), lineWidth: 1) }
            // The top-left highlight: a light inner edge that fades out toward the middle.
            .overlay {
                shape.inset(by: 1).strokeBorder(LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.28 : 0.9), .clear],
                                                               startPoint: .topLeading, endPoint: UnitPoint(x: 0.35, y: 0.6)), lineWidth: 1)
            }
    }
}

/// A soft card: a faint fill and a .08 edge.
struct PosSoftCard: ViewModifier {
    let radius: CGFloat
    var fill: Color = PC.cardFill
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background(shape.fill(fill)).overlay(shape.strokeBorder(PC.cardEdge, lineWidth: 1))
    }
}

/// The wall icons on a 20 pt box (Lanes.tsx WallIcon): ceiling ⇥, floor ⇤, flip ◐, accelerator «.
struct WallGlyph: View {
    enum Kind { case ceiling, floor, flip, accelerator }
    let kind: Kind
    var size: CGFloat = 12
    var body: some View {
        Canvas { ctx, sz in
            let k = sz.width / 20
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
            let style = StrokeStyle(lineWidth: 2 * k, lineCap: .round, lineJoin: .round)
            let ink = GraphicsContext.Shading.foreground
            switch kind {
            case .ceiling, .floor:
                let r = kind == .floor
                let X = { (x: CGFloat) in r ? 20 - x : x }
                var a = Path(); a.move(to: p(X(2.5), 10)); a.addLine(to: p(X(12), 10))
                a.move(to: p(X(8.5), 6)); a.addLine(to: p(X(12.5), 10)); a.addLine(to: p(X(8.5), 14))
                ctx.stroke(a, with: ink, style: style)
                var b = Path(); b.move(to: p(X(16.5), 3)); b.addLine(to: p(X(16.5), 17))
                ctx.stroke(b, with: ink, style: StrokeStyle(lineWidth: 2.6 * k, lineCap: .round))
            case .flip:
                ctx.stroke(Path(ellipseIn: CGRect(x: 3 * k, y: 3 * k, width: 14 * k, height: 14 * k)), with: ink, lineWidth: 2 * k)
                var h = Path(); h.addArc(center: p(10, 10), radius: 7 * k, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false); h.closeSubpath()
                ctx.fill(h, with: ink)
            case .accelerator:
                var a = Path()
                a.move(to: p(9.5, 5)); a.addLine(to: p(4.5, 10)); a.addLine(to: p(9.5, 15))
                a.move(to: p(16, 5)); a.addLine(to: p(11, 10)); a.addLine(to: p(16, 15))
                ctx.stroke(a, with: ink, style: style)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Stripes at 135° (2 pt on, 3 pt off) in a colour: resistance and the averages still ahead.
struct PosHatch: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 5 * 2.squareRoot()
            var p = Path(), x = -size.height
            while x < size.width + size.height {
                p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            ctx.stroke(p, with: .color(color), lineWidth: 2 / 2.squareRoot() * 1.4)
        }
        .accessibilityHidden(true)
    }
}

/// VoiceOver words for the tab: book money "hidden" with privacy on, short months and days in full, "×" as "times".
enum PosSay {
    static func money(_ v: Double, _ privacy: Bool) -> String { privacy ? "hidden" : BriefWords.speech(PosFmt.money(v)) }
    static func signed(_ v: Double, _ privacy: Bool) -> String { privacy ? "hidden" : "\(v < 0 ? "down" : "up") \(BriefWords.speech(PosFmt.money(v)))" }
    private static let full: [String: String] = [
        "Jan": "January", "Feb": "February", "Mar": "March", "Apr": "April", "Jun": "June", "Jul": "July", "Aug": "August",
        "Sep": "September", "Oct": "October", "Nov": "November", "Dec": "December",
        "Mon": "Monday", "Tue": "Tuesday", "Wed": "Wednesday", "Thu": "Thursday", "Fri": "Friday", "Sat": "Saturday", "Sun": "Sunday"]
    private static let shortRE = try! NSRegularExpression(pattern: #"\b(Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Oct|Nov|Dec|Mon|Tue|Wed|Thu|Fri|Sat|Sun)\b"#)
    private static let yearRE = try! NSRegularExpression(pattern: #"[’'](\d{2})\b"#)
    /// Words on screen as VoiceOver should say them (arrows, %, Δ and the mask through BriefWords.speech).
    static func words(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "×", with: " times ").replacingOccurrences(of: "→", with: " to ").replacingOccurrences(of: "±", with: "plus or minus ")
        t = yearRE.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "20$1")
        let ns = t as NSString
        for m in shortRE.matches(in: t, range: NSRange(location: 0, length: ns.length)).reversed() {
            if let r = Range(m.range, in: t), let w = full[ns.substring(with: m.range)] { t.replaceSubrange(r, with: w) }
        }
        return BriefWords.speech(t)
    }
}
