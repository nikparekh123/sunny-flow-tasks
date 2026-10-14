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
    /// Built once per size, weight and tnum, then reused: a variable-font
    /// descriptor per Text on every redraw was the app's biggest cost
    /// (Planner audit, 14 Oct 2026).
    func uiFont(tabular: Bool = false) -> UIFont {
        let key = "\(size)|\(weight)|\(tabular)"
        Self.lock.lock(); defer { Self.lock.unlock() }
        if let f = Self.cache[key] { return f }
        let f = make(tabular: tabular)
        Self.cache[key] = f
        return f
    }
    nonisolated(unsafe) private static var cache: [String: UIFont] = [:]
    private static let lock = NSLock()

    private func make(tabular: Bool) -> UIFont {
        guard let base = UIFont(name: "Inter", size: size) else {
            return .systemFont(ofSize: size, weight: UIFont.Weight(rawValue: (weight - 400) / 500))
        }
        var attrs: [UIFontDescriptor.AttributeName: Any] = [
            // opsz stays at 14, the text cut, at every size: the design's
            // web Inter has no optical-size axis, so its big titles and
            // numbers are the text cut too (the display cut set ~4% narrower).
            UIFontDescriptor.AttributeName(rawValue: "NSCTFontVariationAttribute"):
                [0x77676874: weight, 0x6F70737A: 14],
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

// MARK: - CSS text-wrap

/// CSS `text-wrap: balance` and `pretty`, which SwiftUI does not have. The
/// breaks are worked out here and set as line breaks, so the text renders
/// exactly as wrapped. Balance: the narrowest width that keeps the same
/// number of lines (the deck titles). Pretty: never one word alone on the
/// last line.
enum SWrap {
    enum Mode { case balance, pretty }

    static func lines(_ s: String, _ t: SType, width: CGFloat, _ mode: Mode) -> String {
        lines(s, font: t.uiFont(), kern: t.tracking * t.size, width: width, mode)
    }

    static func lines(_ s: String, font: UIFont, kern: CGFloat, width: CGFloat, _ mode: Mode) -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .kern: kern]
        let measure = { (x: String) -> CGFloat in ceil(NSAttributedString(string: x, attributes: attrs).size().width) }
        let words = s.split(separator: " ").map(String.init)
        guard words.count > 1, measure(s) > width else { return s }
        func greedy(_ w: CGFloat) -> [[String]] {
            var out: [[String]] = [], line: [String] = []
            for word in words {
                if line.isEmpty || measure((line + [word]).joined(separator: " ")) <= w { line.append(word) }
                else { out.append(line); line = [word] }
            }
            if !line.isEmpty { out.append(line) }
            return out
        }
        var best = greedy(width)
        switch mode {
        case .balance:
            var lo: CGFloat = 0, hi = width
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if greedy(mid).count <= best.count { hi = mid } else { lo = mid }
            }
            best = greedy(hi)
        case .pretty:
            if best.count > 1, best[best.count - 1].count == 1, best[best.count - 2].count >= 2 {
                let moved = best[best.count - 2].removeLast()
                best[best.count - 1].insert(moved, at: 0)
            }
        }
        return best.map { $0.joined(separator: " ") }.joined(separator: "\n")
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
