//
//  InkTheme.swift
//  Sunnyfi — Ink design system (greenfield rebuild)
//
//  The token layer. Two laws govern every screen:
//    Law 1 — colour is data. Hue appears ONLY on data, never on chrome, nav,
//            buttons, headlines or borders. Selection is inversion, not a hue.
//            The three data hues are named by MEANING (loss/gain/delayed) so no
//            one ever writes "fire" to mean a loss.
//    Law 2 — opacity is relevance. Low-priority content fades (r1…r4), never hides.
//
//  Both themes ship; the app follows the system appearance (light by day, dark by
//  night) with a Profile override. Values are 1:1 with the Ink `tokens.css`.
//

import SwiftUI
import UIKit

private extension UIColor {
    convenience init(inkHex hex: UInt, alpha: CGFloat = 1) {
        self.init(
            red:   CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue:  CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}

/// A colour that resolves to its dark or light value from the active trait
/// collection — so it follows the system appearance automatically.
private func inkDyn(_ dark: UIColor, _ light: UIColor) -> Color {
    Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
}

enum Ink {

    // MARK: - Chrome (monochrome — Law 1: never a hue)
    static let canvas     = inkDyn(UIColor(inkHex: 0x121211), UIColor(inkHex: 0xF5F3ED))
    static let surface    = inkDyn(UIColor(inkHex: 0x1A1A19), UIColor(inkHex: 0xFFFFFF))
    static let text       = inkDyn(UIColor(inkHex: 0xF5F3ED), UIColor(inkHex: 0x121211))
    // Legibility beats hierarchy. The design's dim/relevance ladder was pitched for
    // a large bright display; on a phone in daylight the lower rungs were unreadable
    // and reported as such three times. Rank is still carried by size, weight and
    // position — opacity is no longer asked to do it alone. Light mode also moves
    // from 0x8B8880 to a properly dark grey, which was the worst of it.
    static let dim        = inkDyn(UIColor(inkHex: 0xDCD9D2), UIColor(inkHex: 0x3A3835))
    static let hair       = inkDyn(UIColor(inkHex: 0xF5F3ED, alpha: 0.07), UIColor(inkHex: 0xEBE9E2))
    static let invertBg   = inkDyn(UIColor(inkHex: 0xF5F3ED), UIColor(inkHex: 0x121211))
    static let invertText = inkDyn(UIColor(inkHex: 0x121211), UIColor(inkHex: 0xF5F3ED))
    /// Captions on an inverted surface. Solid, never alpha — fading near-black text
    /// on a cream card is what turned labels into grey mush.
    static let invertDim  = inkDyn(UIColor(inkHex: 0x2E2C29), UIColor(inkHex: 0xDCD9D2))
    /// Card footers / sheet docks lift dim to 84% (the `.cardfoot` override) so the
    /// small mono labels stay legible on the raised surface.
    static let footDim    = inkDyn(UIColor(inkHex: 0xE6E3DC), UIColor(inkHex: 0x2A2825))

    // MARK: - Data hues (Law 1 — ONLY on a number, bar fill or data band)
    /// Moving AGAINST you — loss, cost to close, debit. (peril "fire")
    static let loss       = inkDyn(UIColor(inkHex: 0xFF6B3D), UIColor(inkHex: 0xE85320))
    /// Moving FOR you — gain, credit received. (peril "flood")
    static let gain       = inkDyn(UIColor(inkHex: 0x3E9FE0), UIColor(inkHex: 0x2B7FC4))
    /// Delayed data — freshness stamp dot only. (peril "severe")
    static let delayed    = inkDyn(UIColor(inkHex: 0xE8C547), UIColor(inkHex: 0xC9A227))
    // Unused upstream hues — kept for token parity; do not invent uses.
    static let hurricane  = inkDyn(UIColor(inkHex: 0x7C6BFF), UIColor(inkHex: 0x6A58E8))
    static let winter     = inkDyn(UIColor(inkHex: 0x9AD8E8), UIColor(inkHex: 0x4FA8C4))
    static let quake      = inkDyn(UIColor(inkHex: 0xB08D57), UIColor(inkHex: 0x9A7845))

    /// The semantic direction mapping used on every signed figure:
    /// `good == true` → gain (blue), `false` → loss (orange), `nil` → flat (dim `·`).
    static func signed(_ good: Bool?) -> Color { good == nil ? dim : (good! ? gain : loss) }

    // MARK: - Radii
    static let radiusCard: CGFloat = 20
    static let radiusElement: CGFloat = 12
}

// MARK: - Relevance (Law 2 — opacity is relevance)

enum InkRelevance: Double {
    // The NVDA·TLT pages' relevance ladder (the app lifts the DS defaults of
    // .68/.42/.26 to near-opaque — "we removed the transparency").
    case r1 = 1.0, r2 = 0.99, r3 = 0.97, r4 = 0.94
}

extension View {
    /// Fade a whole element by its relevance rank. Never below r4, never hidden.
    /// (The global "fade off" accessibility switch pins everything to r1 — handled
    /// where the switch lives, not here.)
    /// Relevance no longer fades text. Rank is carried by size, weight and
    /// position; opacity made the lower rungs unreadable on a phone. The ladder
    /// stays so call sites keep compiling and intent stays documented.
    func inkRelevance(_ r: InkRelevance) -> some View { opacity(1.0) }
}

// MARK: - Motion (DS easing only — no bounce/spring)

enum InkMotion {
    static func ease(_ duration: Double) -> Animation { .timingCurve(0.4, 0, 0.2, 1, duration: duration) }
    static let fast   = ease(0.16)   // selection / hover
    static let mid    = ease(0.25)   // relevance change, bar height
    static let countUp = 0.82        // figure roll (ease-out cubic, in the count-up view)
    static let barGrow = 0.90        // bar grow-in
    static let pulse   = 2.5         // live-dot pulse period
}

// MARK: - Type — Inter (prose) · Newsreader (serif headings) · IBM Plex Mono (every number)
//
// RULE: every number is mono; prose is Inter; editorial headings are Newsreader.
// The .ttf files still need bundling via UIAppFonts — until then Font.custom falls
// back to the system face at the correct size/weight, so nothing breaks.

enum InkFont {
    // Inter and Newsreader ship as VARIABLE fonts (wght + opsz axes). SwiftUI's
    // `.custom(...).weight()` does not drive a bundled variable font's axes, so we
    // build the UIFont with explicit variation values — otherwise everything renders
    // at the 400 default (CSS uses 300 for prose, 500 for nav, etc.). CSS
    // `font-optical-sizing: auto` == opsz follows the point size, so we mirror that.
    private static let wghtAxis = 0x77676874   // 'wght'
    private static let opszAxis = 0x6F70737A   // 'opsz'

    private static func wghtValue(_ w: Font.Weight) -> CGFloat {
        switch w {
        case .ultraLight: return 100; case .thin: return 200; case .light: return 300
        case .medium: return 500; case .semibold: return 600; case .bold: return 700
        case .heavy: return 800; case .black: return 900; default: return 400
        }
    }
    private static func variable(_ name: String, _ size: CGFloat, wght: CGFloat, opszRange: ClosedRange<CGFloat>) -> Font {
        guard let base = UIFont(name: name, size: size) else { return .system(size: size) }
        let opsz = min(max(size, opszRange.lowerBound), opszRange.upperBound)
        let desc = base.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: "NSCTFontVariationAttribute"): [wghtAxis: wght, opszAxis: opsz],
        ])
        return Font(UIFont(descriptor: desc, size: size))
    }

    /// Prose / labels — Inter (opsz 14–32). Default weight 300, matching the design.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .light) -> Font {
        variable("Inter", size, wght: wghtValue(weight), opszRange: 14...32)
    }
    /// Editorial headings — Newsreader (opsz 6–72), the PostScript face resolves the family.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        variable("Newsreader16pt-Regular", size, wght: wghtValue(weight), opszRange: 6...72)
    }
    /// Every number — IBM Plex Mono. Static faces, so map the weight to the exact
    /// PostScript name (no `.weight()` on a static face). Default is LIGHT (300) —
    /// the design's mono chrome (eyebrows, counts, bands, stamps) is all 300; only
    /// Band3 values (400) and net figures (500) go heavier and pass a weight.
    /// Default weight is REGULAR, not the design's 300. Small uppercase mono at
    /// weight 300 renders as thin grey strokes however dark the colour is — measured
    /// glyph cores at #2E2C29 still read as washed out, because most of each glyph
    /// is partial coverage. Density, not darkness, is what makes small type legible.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let face: String
        switch weight {
        case .ultraLight, .thin, .light: face = "IBMPlexMono-Light"
        case .medium, .semibold, .bold, .heavy, .black: face = "IBMPlexMono-Medium"
        default: face = "IBMPlexMono-Regular"
        }
        // fixedSize, not size: `.custom(_:size:)` scales with Dynamic Type while
        // display() and serif() go through UIFont and do not. Ink cards are fixed
        // geometry (348x496, a 120 foot), so a figure that grows inside a box that
        // cannot is guaranteed to truncate — on a large text setting the strike on a
        // planner card collapsed to an ellipsis. Numbers hold their size; prose was
        // already doing so.
        return .custom(face, fixedSize: size)
    }
}
