//
//  SType.swift
//  Sunny
//
//  The S type scale (UI Kit §02, tokens.md "Type"): Inter only, every number
//  in tabular figures. Each style is weight · size/line height · tracking.
//
//  ⚠ INTER SHIPS AS ONE VARIABLE FONT. A weight is the `wght` axis, set on the
//  font descriptor; SwiftUI's `.weight()` cannot reach it on a custom font.
//  ⚠ CSS LINE HEIGHT IS THE WHOLE LINE BOX, with the glyphs centred in it.
//  SwiftUI's `lineSpacing` is extra space between lines only, a fixed frame
//  truncates a wrapped title, and `.lineHeight(.exact)` sat the glyphs low
//  in tight boxes (button labels off centre). So: natural line + leading
//  between lines + the difference split evenly above and below.
//

import SwiftUI
import UIKit

struct SType {
    let size: CGFloat
    let weight: CGFloat          // the wght axis, 100...900
    let line: CGFloat            // CSS line height, in points
    let tracking: CGFloat        // fraction of the size (-0.02 = -2%)

    static let display      = SType(size: 40, weight: 800, line: 40, tracking: -0.02)
    static let largeTitle   = SType(size: 34, weight: 800, line: 40, tracking: -0.02)
    static let largeNumber  = SType(size: 34, weight: 800, line: 34, tracking: -0.02)  // Summary Card Small number
    static let sectionHead  = SType(size: 28, weight: 800, line: 32, tracking: -0.02)    // Book · Risk · Income · Results (block 08)
    static let deckTitle    = SType(size: 30, weight: 700, line: 34, tracking: -0.02)
    static let sheetNumber  = SType(size: 28, weight: 800, line: 30, tracking: 0)
    static let sectionTitle = SType(size: 20, weight: 700, line: 24, tracking: 0)
    static let bodyLarge    = SType(size: 18, weight: 400, line: 24, tracking: 0)
    static let headline     = SType(size: 17, weight: 700, line: 22, tracking: 0)
    static let price        = SType(size: 15, weight: 700, line: 15, tracking: 0)
    static let change       = SType(size: 15, weight: 700, line: 15, tracking: 0)
    static let cardTitle    = SType(size: 15, weight: 600, line: 15, tracking: 0)
    static let ticker       = SType(size: 15, weight: 500, line: 15, tracking: 0)
    static let body         = SType(size: 15, weight: 400, line: 20, tracking: 0)
    static let bodyLight    = SType(size: 15, weight: 300, line: 15, tracking: 0)
    static let kicker       = SType(size: 13, weight: 700, line: 16, tracking: 0)
    static let note         = SType(size: 13, weight: 400, line: 18, tracking: 0)
    static let meta         = SType(size: 13, weight: 400, line: 13, tracking: 0)
    static let label        = SType(size: 12, weight: 600, line: 12, tracking: 0)
    static let micro        = SType(size: 11, weight: 600, line: 11, tracking: 0.04)
    static let receiptHero  = SType(size: 44, weight: 700, line: 48, tracking: 0)
    static let receiptTitle = SType(size: 24, weight: 700, line: 28, tracking: 0)
    static let receiptRow   = SType(size: 14, weight: 500, line: 18, tracking: 0)

    /// The same style at another size (the deck's 200pt corner mark).
    func sized(_ s: CGFloat, line l: CGFloat? = nil) -> SType {
        SType(size: s, weight: weight, line: l ?? s, tracking: tracking)
    }
    func weighted(_ w: CGFloat) -> SType { SType(size: size, weight: w, line: line, tracking: tracking) }

    // MARK: fonts

    /// Inter at this size and weight; `tabular` turns on tnum for numbers.
    func uiFont(tabular: Bool = false) -> UIFont {
        guard let base = UIFont(name: "Inter", size: size) else {
            return .systemFont(ofSize: size, weight: UIFont.Weight(rawValue: (weight - 400) / 500))
        }
        var attrs: [UIFontDescriptor.AttributeName: Any] = [
            UIFontDescriptor.AttributeName(rawValue: "NSCTFontVariationAttribute"):
                [0x77676874: weight, 0x6F70737A: min(max(size, 14), 32)],
        ]
        if tabular {
            attrs[.featureSettings] = [[UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                                         UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector]]
        }
        return UIFont(descriptor: base.fontDescriptor.addingAttributes(attrs), size: size)
    }
    func font(tabular: Bool = false) -> Font { Font(uiFont(tabular: tabular)) }

    /// Extra space between lines so the line box equals `line`.
    var lineSpacing: CGFloat { max(0, line - uiFont().lineHeight) }
    /// A box tighter than the font's own line (Display 40/40).
    var tight: Bool { line < uiFont().lineHeight - 0.5 }
}

extension View {
    /// Apply a type style. Numbers default to tabular figures (README, Type).
    func sType(_ t: SType, tabular: Bool = true) -> some View {
        modifier(STypeModifier(t: t, tabular: tabular))
    }
}

private struct STypeModifier: ViewModifier {
    let t: SType
    let tabular: Bool
    func body(content: Content) -> some View {
        // CSS centres the glyphs in the line box: half the difference above,
        // half below, even when the box is tighter than the font. So the
        // font keeps its natural line, extra lines get the leading, and the
        // box is trimmed or grown evenly top and bottom (negative padding
        // for a tight box, which never clips a wrapped line).
        let natural = t.uiFont().lineHeight
        content
            .font(t.font(tabular: tabular))
            .tracking(t.tracking * t.size)
            .lineSpacing(max(0, t.line - natural))
            .padding(.vertical, (t.line - natural) / 2)
    }
}

// MARK: - Receipt mono

/// The printed receipt's face (UI Kit §27: IBM Plex Mono on the paper and the
/// desk label). Inter everywhere else. Only Regular and Medium ship in the
/// app, so the receipt's 600 and 700 set in Medium.
struct SMono {
    let size: CGFloat
    var weight: CGFloat = 400
    var line: CGFloat? = nil
    var tracking: CGFloat = 0           // em

    func uiFont(tabular: Bool = true) -> UIFont {
        let face = weight >= 500 ? "IBMPlexMono-Medium" : "IBMPlexMono-Regular"
        return UIFont(name: face, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: weight >= 500 ? .semibold : .regular)
    }
}

extension View {
    func sMono(_ size: CGFloat, _ weight: CGFloat = 400, line: CGFloat? = nil, tracking: CGFloat = 0) -> some View {
        let m = SMono(size: size, weight: weight, line: line, tracking: tracking)
        let f = m.uiFont()
        let lh = line ?? f.lineHeight
        return self.font(Font(f))
            .tracking(tracking * size)
            .lineSpacing(max(0, lh - f.lineHeight))
            .padding(.vertical, (lh - f.lineHeight) / 2)
    }
}
