//
//  SunnyTokens.swift
//  Sunny — NORMATIVE. A faithful port of handoff/tokens.css.
//
//  ⚠ THIS FILE IS THE ONLY PLACE A LITERAL MAY APPEAR. SPEC 00: "No literal
//  values in component code. Every px, hex, shadow, and radius comes from a
//  token. If you need a value that isn't here, STOP and ask. Do not round,
//  interpolate, or eyeball."
//
//  The web handoff enforces that with handoff/lint-tokens.mjs, which only walks
//  .css/.ts/.tsx/.js/.jsx/.html/.svelte/.vue. Swift is outside its extension set,
//  so the lint cannot see this codebase. SunnyLint.swift ports the same checks.
//
//  Values are transcribed, not adapted. Where the CSS gives a fractional px
//  (--col: 174.5px, --hit-bleed: 14.25px) the fraction is kept: on a 3x screen
//  174.5pt is a whole number of pixels and rounding it would break the grid.
//

import SwiftUI

enum S {

    // MARK: grid (iPhone 393pt)
    static let screen:  CGFloat = 393
    static let margin:  CGFloat = 16
    static let gutter:  CGFloat = 12
    static let col:     CGFloat = 174.5     // (393 - 32 - 12) / 2
    static let content: CGFloat = 361

    // MARK: card sizes — column spans and ratios, NEVER a fixed height
    enum Size: String {
        case xs, s, m, l
        /// grid-column span
        var span: Int { self == .m || self == .l ? 2 : 1 }
        /// aspect-ratio
        var ratio: CGFloat {
            switch self {
            case .xs: return 2.0 / 1.0            // 174.5 × 87.25
            case .s:  return 1.0                  // 174.5 × 174.5
            case .m:  return 361.0 / 174.0        // 361 × 174
            case .l:  return 361.0 / 361.0        // 361 × 361
            }
        }
        var padding: EdgeInsets { self == .m || self == .l ? S.padCardM : S.padCard }
        var shadow: [SunnyShadow] { self == .l ? S.shadowCardL : S.shadowCard }
    }

    // MARK: card shell
    static let radiusCard:  CGFloat = 22      // every card, every size. never 16, never 20
    static let radiusPanel: CGFloat = 16
    static let radiusPill:  CGFloat = 999
    static let radiusChip:  CGFloat = 6
    static let radiusBar:   CGFloat = 4
    static let radiusPip:   CGFloat = 2

    static let padCard  = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    /// --pad-card-m: 17px 19px 16px — an optical bottom trim, not a mistake.
    static let padCardM = EdgeInsets(top: 17, leading: 19, bottom: 16, trailing: 19)
    static let padChip  = EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7)
    static let padPill  = EdgeInsets(top: 7, leading: 13, bottom: 7, trailing: 13)

    /// rgba(20, 23, 15, α) is the one raw colour the lint permits, because every
    /// shadow in the system is built from it.
    static func shadowInk(_ a: Double) -> Color { Color(red: 20/255, green: 23/255, blue: 15/255).opacity(a) }
    static let shadowCard  = [SunnyShadow(shadowInk(0.05), 2, 1), SunnyShadow(shadowInk(0.05), 16, 6)]
    static let shadowCardL = [SunnyShadow(shadowInk(0.07), 4, 2), SunnyShadow(shadowInk(0.08), 22, 9)]
    static let shadowFlat  = [SunnyShadow(shadowInk(0.05), 2, 1)]

    // MARK: rules — ALWAYS a child view with a height, never a border (SPEC 04)
    static let rule:      CGFloat = 1
    static let ruleHeavy: CGFloat = 2
    static let ruleColor       = hex(0xE7E9E5)
    static let ruleColorStrong = hex(0xDEE0DB)
    static let ruleColorInk    = hex(0x14170F)

    // MARK: neutrals
    static let paper  = hex(0xFFFFFF)
    static let ground = hex(0xF7F8F6)
    static let wash   = hex(0xF0F1EE)
    static let band   = hex(0xEDEFEA)
    static let ink    = hex(0x14170F)
    static let ink2   = hex(0x3C423A)
    static let ink3   = hex(0x4A5046)
    static let mute   = hex(0x5D6359)
    static let mute2  = hex(0x6B7166)
    static let faint  = hex(0x8A9086)
    static let hair   = hex(0xC2C7BE)

    // MARK: gain / loss / attention
    static let gainBar = hex(0x00A945), gain = hex(0x00722F), gainText = hex(0x00631F)
    static let gainDeep = hex(0x00541F), gainQuiet = hex(0x1C5232)
    static let gainSpan = hex(0x8FBFA1), gainWash = hex(0xDFF3E6)
    static let lossBar = hex(0xC4001A), loss = hex(0xA80016), lossText = hex(0x8E0014)
    static let lossQuiet = hex(0x6E1A22), lossTick = hex(0x8A1F14), lossWash = hex(0xFBE4E6)
    static let warn = hex(0xE08600), warnText = hex(0x7A4700), warnDeep = hex(0x5C3300)
    static let warnWash = hex(0xFBEEDC), warnChip = hex(0xF4D9AE)
    static let doGround = hex(0xFBF5E4), doLabel = hex(0x55502F), doBody = hex(0x4C4835)


    // MARK: paper — THE DIGEST CARD ONLY
    //
    // ⚠ DO NOT SPREAD THESE. tokens.css: "The long position digest uses a paper
    // treatment. NOTHING else does — do not spread these onto feed cards,
    // chrome, or chart cards." It earns its difference by being the only one.
    //
    // ⚠ AND HANDWRITING IS NEVER A FIGURE. Labels, tags, the ticker and the
    // timestamp are hand. Every number stays Inter, semibold, tabular. A
    // handwritten price reads as decorative and the card stops being
    // trustworthy at a glance. That is the one rule that outranks the rest.
    static let paperButter    = hex(0xFFFBEA)
    static let paperDot       = Color(red: 160/255, green: 140/255, blue: 80/255).opacity(0.16)
    static let paperDotSize:  CGFloat = 16
    static let paperRing      = Color(red: 160/255, green: 140/255, blue: 80/255).opacity(0.14)
    static let paperRule      = hex(0xE3D9B8)
    static let paperBullet    = hex(0xC4B78C)
    static let paperInk       = hex(0x1F1B12)
    static let paperInkStrong = hex(0x1B1710)
    static let paperInkHead   = hex(0x5A5033)
    static let paperInkMeta   = hex(0x8A7B52)
    static let paperInkDo     = hex(0x453D26)
    static let paperRuleInk   = hex(0x3B3319)
    static let paperDoGround  = Color(red: 216/255, green: 190/255, blue: 110/255).opacity(0.16)

    // Washes are ALPHA OVER THE BUTTER GROUND, never opaque fills. That is what
    // makes them read as highlighter rather than as a chip.
    static let paperMarkNew  = Color(red: 217/255, green: 162/255, blue: 90/255).opacity(0.28)
    static let paperMarkBull = Color(red: 120/255, green: 190/255, blue: 140/255).opacity(0.30)
    static let paperMarkNote = Color(red: 120/255, green: 160/255, blue: 205/255).opacity(0.26)
    static let markNewInk    = hex(0x7C4A16)
    static let markBullInk   = hex(0x0F5A2C)
    static let markNoteInk   = hex(0x2A4A6E)

    // Not in tokens.css, but named there in the DIGEST-CARD colour table.
    static let paperInkTicker = hex(0x2A2413)
    static let paperChipInk   = hex(0x7C4A16)
    static let paperChipRing  = hex(0xD9A25A)

    static let tHandHead:  CGFloat = 22
    static let tHandTag:   CGFloat = 22
    static let tHandTitle: CGFloat = 28
    static let tHandMeta:  CGFloat = 13.5
    /// Paper body, spot and chip. Bumped from 14.5 / 23 / 17 on 2026-08-23 for
    /// readability. The 1.45 multiple is unchanged.
    static let tPaperBody: CGFloat = 16
    static let tPaperSpot: CGFloat = 25
    static let tPaperChip: CGFloat = 18
    static let lhPaperBody: CGFloat = 1.45

    static let radiusMark: CGFloat = 4
    static let padMark = EdgeInsets(top: 0, leading: 6, bottom: 1, trailing: 6)

    /// Caveat ships VARIABLE (wght 400..700). SwiftUI's .weight() does not drive
    /// a bundled variable font's axes, so the axis is set explicitly, the same
    /// way InkFont handles Inter.
    static func hand(_ size: CGFloat, _ wght: CGFloat = 700) -> Font {
        handUI(size, wght).map(Font.init) ?? .system(size: size)
    }
    /// Inter with an explicit numeric weight, so 450 survives the trip.
    static func interUI(_ size: CGFloat, _ wght: CGFloat) -> UIFont? {
        guard let b = UIFont(name: "Inter", size: size) else { return nil }
        return UIFont(descriptor: b.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: "NSCTFontVariationAttribute"):
                [0x77676874: wght, 0x6F70737A: min(max(size, 14), 32)]]), size: size)
    }
    static func inter(_ size: CGFloat, _ wght: CGFloat) -> Font {
        interUI(size, wght).map(Font.init) ?? .system(size: size)
    }

    /// ⚠ CSS line-height is the TOTAL line advance; SwiftUI's .lineSpacing is
    /// the EXTRA space ON TOP of the font's own natural line height. Passing
    /// size x (multiple - 1) is the obvious move and it is wrong: at 14.5/1.45
    /// it hands SwiftUI 6.52 where the answer is 3.48, because Inter's natural
    /// advance at 14.5 is already 17.54. Measure the font, then subtract.
    static func leading(_ size: CGFloat, _ wght: CGFloat, _ multiple: CGFloat) -> CGFloat {
        guard let f = interUI(size, wght) else { return 0 }
        return max(0, size * multiple - f.lineHeight)
    }
    static func handUI(_ size: CGFloat, _ wght: CGFloat) -> UIFont? {
        guard let b = UIFont(name: "Caveat-Regular", size: size) else { return nil }
        return UIFont(descriptor: b.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: "NSCTFontVariationAttribute"):
                [0x77676874: wght]]), size: size)
    }

    /// Kalam is STATIC, and exists so the timestamp does not read as another
    /// heading. Do not merge it with Caveat.
    static func handAlt(_ size: CGFloat) -> Font {
        Font(UIFont(name: "Kalam-Light", size: size) ?? .systemFont(ofSize: size))
    }

    // MARK: type ramp — pick a step, never interpolate
    static let t10: CGFloat = 10, t11: CGFloat = 11, t12: CGFloat = 12, t13: CGFloat = 13
    static let t14: CGFloat = 14, t15: CGFloat = 15, t17: CGFloat = 17, t19: CGFloat = 19
    static let t22: CGFloat = 22, t26: CGFloat = 26, t30: CGFloat = 30
    static let t34: CGFloat = 34, t39: CGFloat = 39

    /// ⚠ NOT a Font.Weight. SwiftUI's Font.Weight has no 450 step, and routing
    /// through it silently rounds to .regular = 400. DIGEST-CARD §2: "Body is
    /// 450, not 400 and not 500. On butter at 14.5px, 400 goes thin and 500
    /// goes heavy — 450 is the one that holds." Inter is variable, so 450 is
    /// reachable; it just has to be asked for as a number. Use S.inter().
    static let wBodyN: CGFloat = 450
    static let wMidN:  CGFloat = 500
    static let wSemiN: CGFloat = 600
    static let wBoldN: CGFloat = 700

    static let wBody: Font.Weight = .regular     // 400. Do NOT use for paper body.
    static let wMid:  Font.Weight = .medium      // 500
    static let wSemi: Font.Weight = .semibold    // 600 — all figures
    static let wBold: Font.Weight = .bold        // 700 — all uppercase labels

    /// letter-spacing, in em. SwiftUI wants points, so multiply by the size.
    static let lsLabel = 0.13, lsTag = 0.08, lsTight = -0.03, lsTighter = -0.04
    static func track(_ size: CGFloat, _ em: Double) -> CGFloat { size * em }

    static let lhFigure = 1.0, lhTight = 1.25, lhBody = 1.4, lhLoose = 1.5

    // MARK: inner spacing — flex/grid gap ONLY
    static let gap1: CGFloat = 2,  gap2: CGFloat = 4,  gap3: CGFloat = 6
    static let gap4: CGFloat = 8,  gap5: CGFloat = 11, gap6: CGFloat = 12
    static let gap7: CGFloat = 16

    // MARK: chrome
    static let statusbarH: CGFloat = 54
    static let tickerH: CGFloat = 34
    static let zonebarH: CGFloat = 56
    static let searchH: CGFloat = 56          // open; 0 closed
    static let filterrowH: CGFloat = 44
    static let homeIndicatorH: CGFloat = 24
    static let frameRadius: CGFloat = 52
    static let hitMin: CGFloat = 44
    static let hitBleed: CGFloat = 14.25
    static let hitGrow: CGFloat = 20
    static let zoneLine: CGFloat = 130
    static let zoneJumpOffset: CGFloat = 46
    static let scrollDeadband: CGFloat = 4
    static let scrollReveal: CGFloat = 24

    // MARK: chrome colour
    static let dim = hex(0xD3D6D0)
    static let openDot = hex(0x34C759)
    static let tickUp = hex(0x00893A), tickDown = hex(0xC4001A)
    static let onInk = hex(0xF4F6F2)
    static let skeleton = hex(0xEDEFEB), skeletonLabel = hex(0xE4E6E1)

    // MARK: motion — nothing animates that CHROME.md §9 does not list
    static let easeOut    = UnitCurve.easeOut      // cubic-bezier(.2,0,.1,1)
    static let durRevealOpacity = 0.34, durRevealTransform = 0.42
    static let stagger = 0.034, staggerCap = 0.300
    static let revealRise: CGFloat = 7, revealScale: CGFloat = 0.994
    static let durOverlayIn = 0.26, durOverlayOut = 0.38
    static let overlayLift: CGFloat = -4
    static let durSwap = 0.34, swapMidpoint = 0.130
    static let durFilterrow = 0.3, durZone = 0.22, durDrawer = 0.22
    static let pulse = 1.05
    static let debounceQuery = 0.420, debounceFilter = 0.320, debounceClear = 0.260
    static let dot: CGFloat = 7, bullet: CGFloat = 4, barH: CGFloat = 7
    static let transition = 0.18

    // MARK: cubic-bezier, since SwiftUI has no direct equivalent for these
    static let cEaseOut   = Animation.timingCurve(0.2, 0, 0.1, 1)
    static let cEaseSettle = Animation.timingCurve(0.16, 1, 0.3, 1)
    static let cEaseSwap  = Animation.timingCurve(0.4, 0, 0.2, 1)

    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255,
              green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255)
    }
}

/// A CSS box-shadow layer. SwiftUI has no multi-shadow modifier, so the system's
/// two-layer shadows are applied as stacked `.shadow` calls in order.
struct SunnyShadow {
    let color: Color, radius: CGFloat, y: CGFloat
    init(_ c: Color, _ r: CGFloat, _ y: CGFloat) { color = c; radius = r; self.y = y }
}

extension View {
    func sunnyShadow(_ layers: [SunnyShadow]) -> some View {
        layers.reduce(AnyView(self)) { acc, l in
            AnyView(acc.shadow(color: l.color, radius: l.radius / 2, x: 0, y: l.y))
        }
    }
    /// CSS letter-spacing is per-em; SwiftUI tracking is absolute points.
    func sunnyType(_ size: CGFloat, _ weight: Font.Weight, _ em: Double = 0) -> some View {
        font(InkFont.display(size, weight)).tracking(S.track(size, em))
    }
}
