//
//  SearchTheme.swift
//  Sunny
//
//  Search's colours, type and screen (block 27, SunnySearch.dc.html). The
//  colours are the S tokens wherever one exists; the call and put inks, the
//  hairline and the soft fills are the design's own. Type is
//  SF Pro here ("Inter in the design is SF Pro on iOS"), tabular figures on
//  every number, every size following Dynamic Type from its text style.
//  The focus look (handoff 2026-11-25-focus): no colour on words (SX.tone),
//  a sign on a gain or loss (SX.signed), the rare red dot (SX.dot), bold only
//  at 20 pt and up (SX.focus, in every role), a flat page.
//

import SwiftUI
import UIKit

enum SX {
    static let ink = S.ink
    static let muted = S.muted
    static let up = S.green
    static let down = S.red
    static let thin = S.orangeDeep
    static let web = S.blue
    static let paper = S.paper
    /// A wall's strike, its label and a leg's line: calls and puts on words and thin lines are greys (focus §2.4,
    /// calls #BEBEBE, puts #969696); blue and brown stay on fills only.
    static let call = SF.callsWord
    static let put = SF.putsWord
    static let line = S.dynA(0x212121, 0.08, 0xFAFAFA, 0.10)
    static let fill = S.dynA(0x808080, 0.12, 0x808080, 0.24)
    static let track = S.dynA(0x212121, 0.06, 0xFAFAFA, 0.10)
    static let bar = S.dynA(0x212121, 0.16, 0xFAFAFA, 0.20)
    static let chip = S.dynA(0xFAFAFA, 0.66, 0xFAFAFA, 0.08)
    static let chipEdge = S.dynA(0x212121, 0.08, 0xFAFAFA, 0.14)
    static let upTint = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 101 / 255, green: 196 / 255, blue: 102 / 255, alpha: 0.16)
        : UIColor(red: 59 / 255, green: 135 / 255, blue: 61 / 255, alpha: 0.13) })
    /// A large area that was a green or red tint (an area on a chart): neutral grey at its own opacity (focus §2.4).
    static let areaTint = S.dynA(0x8C8C8C, 0.13, 0x8C8C8C, 0.16)
    /// The two soft glows behind the page (lowered to 32% and 24% so light text passes 4.5:1 on them).
    static let glowWarm = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 130 / 255, green: 84 / 255, blue: 30 / 255, alpha: 0.30)
        : UIColor(red: 255 / 255, green: 204 / 255, blue: 140 / 255, alpha: 0.32) })
    static let glowCool = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 40 / 255, green: 70 / 255, blue: 150 / 255, alpha: 0.36)
        : UIColor(red: 150 / 255, green: 188 / 255, blue: 255 / 255, alpha: 0.24) })
    static let fadeTop = S.dyn(0xF2F2F2, 0x171717)
    static let fadeBottom = S.dyn(0xF2F2F2, 0x171717)

    /// A tone word from the server (up, down, thin, muted, call or put) on words or numbers. Focus §2.1: never a
    /// colour; ink at 15 pt and up, grey under 15 (`size`, the role's design size); call and put words their greys.
    static func tone(_ t: String?, _ fallback: Color, size: CGFloat = 15) -> Color {
        switch t {
        case "up", "down", "thin": SF.word(size)
        case "muted": muted
        case "call": call
        case "put": put
        default: fallback
        }
    }

    /// Focus §2.2: a figure the colour called up or down carries the sign: "+$800", "−$4.3K", "−4.8%". Only a money
    /// figure or a bare percentage, never one that already has a sign or an arrow, never the privacy mask.
    static func signed(_ s: String, _ t: String?) -> String {
        guard t == "up" || t == "down", signable(s) else { return s }
        return SF.signed(t == "up" ? 1 : -1, s)
    }
    static func signed(_ v: Double, _ s: String) -> String { signable(s) ? SF.signed(v, s) : s }
    /// "$4.3K", "$800 kept", "4.8%": a money figure first, or a percentage alone.
    static func signable(_ s: String) -> Bool {
        s.range(of: #"^\$\d"#, options: .regularExpression) != nil || s.range(of: #"^\d[\d,]*(\.\d+)?%$"#, options: .regularExpression) != nil
    }
    /// Focus §2.3: a server "down" on a value that is a warning, not a loss (a word, or a number 20 pt and up that
    /// carries no sign of its own): the red dot before it. "up" never takes a dot (green is ready to act, not good).
    static func dot(_ t: String?, _ s: String, size: CGFloat) -> SF.Dot? {
        guard t == "down", !s.isEmpty, !signable(s), let c = s.first, !"▼↓↘−-".contains(c) else { return nil }
        return s.range(of: "[A-Za-z]{2,}", options: .regularExpression) != nil || size >= 20 ? .danger : nil
    }

    /// Focus §2.5 for Search's own system-font roles (SType.focus does the same for Inter): bold (600 and up) only at
    /// 20 pt and up; under 20, 600 and up is 500 at 14 pt and up, 400 under 14; 500 and lighter stay as they are.
    static func focus(_ w: Font.Weight, _ size: CGFloat) -> Font.Weight {
        guard size < 20 else { return w }
        switch w {
        case .semibold, .bold, .heavy, .black: return size >= 14 ? .medium : .regular
        default: return w
        }
    }
}

// MARK: - Type

/// One role from the block's type table: size / line height in points, weight, the text style it scales with,
/// and tracking as a fraction of the size.
struct SXType {
    let size: CGFloat, line: CGFloat, weight: Font.Weight, style: UIFont.TextStyle, tracking: CGFloat

    static let title    = SXType(size: 34, line: 40, weight: .heavy, style: .largeTitle, tracking: -0.025)
    static let group    = SXType(size: 20, line: 24, weight: .bold, style: .title3, tracking: 0)
    static let say      = SXType(size: 24, line: 31, weight: .medium, style: .title2, tracking: -0.012)
    static let lead     = SXType(size: 22, line: 28, weight: .semibold, style: .title2, tracking: -0.01)
    static let recent   = SXType(size: 19, line: 26, weight: .medium, style: .title3, tracking: -0.01)
    static let recentBig = SXType(size: 36, line: 42, weight: .bold, style: .largeTitle, tracking: -0.03)
    static let trio     = SXType(size: 28, line: 34, weight: .bold, style: .title1, tracking: -0.025)
    static let trioSmall = SXType(size: 22, line: 28, weight: .bold, style: .title2, tracking: -0.02)
    static let working  = SXType(size: 20, line: 26, weight: .semibold, style: .title3, tracking: 0)
    static let body     = SXType(size: 17, line: 26, weight: .regular, style: .body, tracking: 0)
    static let panelSay = SXType(size: 17, line: 25, weight: .regular, style: .body, tracking: 0)
    static let row      = SXType(size: 17, line: 23, weight: .regular, style: .body, tracking: 0)
    static let field    = SXType(size: 17, line: 22, weight: .regular, style: .body, tracking: 0)
    static let headline = SXType(size: 17, line: 22, weight: .semibold, style: .body, tracking: 0)
    static let question = SXType(size: 15, line: 20, weight: .semibold, style: .subheadline, tracking: 0)
    static let small    = SXType(size: 15, line: 20, weight: .regular, style: .subheadline, tracking: 0)
    static let panelRow = SXType(size: 15, line: 20, weight: .regular, style: .subheadline, tracking: 0)
    static let note     = SXType(size: 15, line: 22, weight: .regular, style: .subheadline, tracking: 0)
    static let tableLabel = SXType(size: 14, line: 19, weight: .regular, style: .subheadline, tracking: 0)
    static let label    = SXType(size: 13, line: 18, weight: .semibold, style: .footnote, tracking: 0)
    static let time     = SXType(size: 13, line: 16, weight: .medium, style: .footnote, tracking: 0)
    static let source   = SXType(size: 12, line: 16, weight: .medium, style: .caption1, tracking: 0)
    static let tiny     = SXType(size: 12, line: 16, weight: .semibold, style: .caption1, tracking: 0)

    func weighted(_ w: Font.Weight) -> SXType { SXType(size: size, line: line, weight: w, style: style, tracking: tracking) }
    func sized(_ s: CGFloat, line l: CGFloat) -> SXType { SXType(size: s, line: l, weight: weight, style: style, tracking: tracking) }
}

extension View {
    /// The role's font, scaled for the reader's text size, with the design's line height and tracking.
    func sx(_ t: SXType) -> some View { modifier(SXTypeMod(t: t)) }
}

private struct SXTypeMod: ViewModifier {
    let t: SXType
    @Environment(\.dynamicTypeSize) private var dts
    func body(content: Content) -> some View {
        let k = SXScale.factor(t.style, dts)
        let size = t.size * k, line = t.line * k
        // SF Pro's own line is about 1.19 of its size; the rest of the design's line goes between lines and,
        // split in two, above and below, as CSS centres the glyphs in the line box.
        let extra = max(0, line - size * 1.19)
        content
            .font(.system(size: size, weight: SX.focus(t.weight, t.size)))
            .monospacedDigit()
            .tracking(t.tracking * size)
            .lineSpacing(extra)
            .padding(.vertical, extra / 2)
    }
}

enum SXScale {
    static func factor(_ style: UIFont.TextStyle, _ dts: DynamicTypeSize) -> CGFloat {
        let tc = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dts))
        return UIFontMetrics(forTextStyle: style).scaledValue(for: 100, compatibleWith: tc) / 100
    }
    static func font(_ t: SXType, _ dts: DynamicTypeSize) -> Font {
        .system(size: t.size * factor(t.style, dts), weight: SX.focus(t.weight, t.size))
    }
}

// MARK: - Screen

/// Search's screen: the app's flat page (focus §1.3: the warm and cool glows are gone, every page is flat).
struct SXBackground: View {
    var body: some View {
        S.screen
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Solid panels and recents cards: paper with the design's hairline and soft drop.
struct SXPaper: ViewModifier {
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .background(SX.paper, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(SX.line.opacity(0.75), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 1.5, y: 1)
            .shadow(color: .black.opacity(0.08), radius: 10, y: 8)
    }
}

/// A chip: Try asking, follow-ups, Go deeper.
struct SXChip: ViewModifier {
    var height: CGFloat = 44
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .frame(height: height)
            .background(SX.chip, in: .capsule)
            .overlay(Capsule().strokeBorder(SX.chipEdge, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
    }
}
