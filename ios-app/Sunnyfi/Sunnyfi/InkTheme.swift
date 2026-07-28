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
    static let dim        = inkDyn(UIColor(inkHex: 0xF5F3ED, alpha: 0.55), UIColor(inkHex: 0x8B8880))
    static let hair       = inkDyn(UIColor(inkHex: 0xF5F3ED, alpha: 0.07), UIColor(inkHex: 0xEBE9E2))
    static let invertBg   = inkDyn(UIColor(inkHex: 0xF5F3ED), UIColor(inkHex: 0x121211))
    static let invertText = inkDyn(UIColor(inkHex: 0x121211), UIColor(inkHex: 0xF5F3ED))
    /// Inside card footers and sheet docks, dim is re-derived at 70% ink so small
    /// mono labels stay legible on the raised surface (the `.ink-footzone` rule).
    static let footDim    = inkDyn(UIColor(inkHex: 0xF5F3ED, alpha: 0.70), UIColor(inkHex: 0x121211, alpha: 0.70))

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
    case r1 = 1.0, r2 = 0.68, r3 = 0.42, r4 = 0.26
}

extension View {
    /// Fade a whole element by its relevance rank. Never below r4, never hidden.
    /// (The global "fade off" accessibility switch pins everything to r1 — handled
    /// where the switch lives, not here.)
    func inkRelevance(_ r: InkRelevance) -> some View { opacity(r.rawValue) }
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
    /// Prose / labels — Inter (variable; weight drives the wght axis).
    static func display(_ size: CGFloat, _ weight: Font.Weight = .light) -> Font {
        .custom("Inter", size: size).weight(weight)
    }
    /// Editorial section / sheet headings — Newsreader (variable serif).
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Newsreader", size: size).weight(weight)
    }
    /// Every number — IBM Plex Mono. Static faces, so map the weight to the exact
    /// PostScript name (no `.weight()` on a static face).
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let face: String
        switch weight {
        case .ultraLight, .thin, .light: face = "IBMPlexMono-Light"
        case .medium, .semibold, .bold, .heavy, .black: face = "IBMPlexMono-Medium"
        default: face = "IBMPlexMono-Regular"
        }
        return .custom(face, size: size)
    }
}
