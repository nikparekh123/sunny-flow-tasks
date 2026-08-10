//
//  PlannerPagesKit.swift
//  The vocabulary every planner page is built from.
//
//  One layout law, stated once here so seven pages cannot drift apart:
//  content stacks DOWN from the top, and the page's one number sits BOTTOM
//  LEFT with its unit on its baseline. Content grows downward; the number
//  never moves. That single rule is what makes seven different pages read as
//  one instrument — so nothing here centres anything, and no page is allowed
//  to place its own hero.
//
//  Design source: docs/design/planner_pages/ (vendored bundle, README.md has
//  the token tables). Deviating from it needs a design decision, not a code one.
//

import SwiftUI

// MARK: - Tokens

enum PP {
    /// Two light pages — the one you audit (conviction) and the one you act on
    /// (what to sell). Everything else is ink. The ground is a property of the
    /// page, so a page cannot half-adopt it.
    enum Ground { case paper, ink }

    // Surfaces. The paper ground is a gradient, not a flat fill; flattening it
    // is the most common way this design gets quietly degraded.
    static let inkBG    = Color(red: 0.043, green: 0.043, blue: 0.039)   // #0B0B0A
    static let paperTop = Color(red: 1.000, green: 1.000, blue: 1.000)   // #FFFFFF
    static let paperMid = Color(red: 0.969, green: 0.969, blue: 0.957)   // #F7F7F4
    static let paperBot = Color(red: 0.945, green: 0.945, blue: 0.929)   // #F1F1ED

    static let inkText   = Color(red: 0.957, green: 0.957, blue: 0.949)  // #F4F4F2
    static let paperText = Color(red: 0.047, green: 0.047, blue: 0.043)  // #0C0C0B

    static func text(_ g: Ground) -> Color { g == .ink ? inkText : paperText }
    /// Law 2 — opacity is relevance. Secondary text sits at 55–62%, never lower:
    /// nothing is hidden, lower-priority information is faded.
    static func dim(_ g: Ground) -> Color {
        g == .ink ? inkText.opacity(0.55) : paperText.opacity(0.62)
    }
    static func hairline(_ g: Ground) -> Color { text(g).opacity(0.18) }

    @ViewBuilder static func background(_ g: Ground) -> some View {
        ZStack {
            switch g {
            case .ink: inkBG
            case .paper:
                LinearGradient(colors: [paperTop, paperMid, paperBot],
                               startPoint: .top, endPoint: .bottom)
            }
            // The page glow: radial, off-centre high and right. Faint enough to
            // read as depth rather than as a shape, and the reason the dark pages
            // in the mock are not flat black.
            GeometryReader { geo in
                RadialGradient(
                    colors: [g == .ink ? .white.opacity(0.05) : .black.opacity(0.03), .clear],
                    center: UnitPoint(x: 0.82, y: 0.06),
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.68)
            }
        }
    }

    /// Law 1 — colour is data. These are the ONLY hues in the planner: one per
    /// conviction family, plus the payoff chart's loss region. No hue on chrome,
    /// buttons, headers or type; selection is inversion, never a colour change.
    static let familyHue: [String: Color] = [
        "trend":    Color(red: 0.122, green: 0.435, blue: 0.290),   // #1F6F4A
        "catalyst": Color(red: 0.753, green: 0.541, blue: 0.086),   // #C08A16
        "stretch":  Color(red: 0.753, green: 0.314, blue: 0.227),   // #C0503A
        "record":   Color(red: 0.231, green: 0.298, blue: 0.659),   // #3B4CA8
        "relative": Color(red: 0.118, green: 0.486, blue: 0.525),   // #1E7C86
        "grade":    Color(red: 0.478, green: 0.294, blue: 0.710),   // #7A4BB5
        "macro":    Color(red: 0.541, green: 0.353, blue: 0.169),   // #8A5A2B
        // The ninth family. It scores today — SMH-relative sector health — and
        // was missing a disc entirely in the first design pass.
        "sector":   Color(red: 0.678, green: 0.400, blue: 0.639),   // #AD66A3
        "peers":    Color(red: 0.557, green: 0.557, blue: 0.533),   // #8E8E88
    ]
    static let lossHue = Color(red: 0.753, green: 0.314, blue: 0.227)

    // Geometry, from the README's table.
    static let pagePadTop: CGFloat = 56
    static let pagePadX: CGFloat = 26
    static let pagePadBottom: CGFloat = 44
    static let headBaseGap: CGFloat = 20

    // Type. Mono carries every number and every label; the display face carries
    // prose. These route to the app's BUNDLED Ink faces — IBM Plex Mono and Inter,
    // already in the target with UIAppFonts — rather than to .system. Using
    // .system was the whole of the "font looks different" gap: same sizes, same
    // tracking, wrong typeface on every glyph.
    //
    // The design's README names Archivo for display. Ink names Inter, and Inter is
    // what this app ships and every other screen already uses, so the planner
    // matches the app rather than importing a ninth typeface for one deck.
    static func mono(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        InkFont.mono(size, w)
    }
    static func disp(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        InkFont.display(size, w)
    }
}

// MARK: - The layout law

/// Every page is exactly one screen, head at the top, base pinned to the bottom.
/// Extra height on a taller device goes to the gap between them — never to the
/// number's position.
struct PPPage<Head: View, Base: View>: View {
    let ground: PP.Ground
    @ViewBuilder var head: Head
    @ViewBuilder var base: Base

    var body: some View {
        VStack(alignment: .leading, spacing: PP.headBaseGap) {
            VStack(alignment: .leading, spacing: 14) { head }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) { base }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.top, PP.pagePadTop)
        .padding(.horizontal, PP.pagePadX)
        .padding(.bottom, PP.pagePadBottom)
        // The design's 56pt top padding assumes a device frame with no status bar.
        // On a real phone that put the date under the clock and the close control.
        .safeAreaPadding(.top)
        .background(PP.background(ground).ignoresSafeArea())
        .foregroundStyle(PP.text(ground))
    }
}

// MARK: - Primitives

/// The hero. Value and unit share a baseline, which is why this is an HStack
/// with .lastTextBaseline and not a VStack with manual offsets.
struct PPNum: View {
    let value: String
    var unit: String? = nil
    var size: CGFloat = 110
    var hue: Color? = nil
    let ground: PP.Ground

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(value)
                .font(PP.disp(size, .semibold))
                .tracking(size * -0.055)
                .monospacedDigit()
                .lineLimit(1)
                // 110pt with negative tracking overflows a 390pt screen at four
                // glyphs. Shrinking is the only acceptable failure here: wrapping
                // turned 220 into "22" over "0", which reads as a different number.
                .minimumScaleFactor(0.45)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(hue ?? PP.text(ground))
            if let unit {
                Text(unit)
                    .font(PP.disp(24))
                    .foregroundStyle(PP.dim(ground))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        // line-height .86 in the design: the hero is meant to sit tight to its
        // own box so the unit reads as attached to it, not as a caption.
        .padding(.bottom, 2)
    }
}

struct PPKicker: View {
    let text: String
    let ground: PP.Ground
    var body: some View {
        Text(text.uppercased())
            .font(PP.mono(11))
            .tracking(11 * 0.2)
            .foregroundStyle(PP.dim(ground))
    }
}

/// The one sentence that says what the number means.
struct PPSay: View {
    let text: String
    let ground: PP.Ground
    var body: some View {
        Text(text)
            .font(PP.disp(16, .medium))
            .lineSpacing(16 * 0.3)
            .foregroundStyle(PP.text(ground))
            .padding(.top, 16)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Everything the sentence had to leave out. Faded, never dropped.
struct PPFine: View {
    let text: String
    let ground: PP.Ground
    var topPad: CGFloat = 9
    var body: some View {
        Text(text)
            .font(PP.disp(13))
            .lineSpacing(13 * 0.5)
            .foregroundStyle(PP.dim(ground))
            .padding(.top, topPad)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The trail under a hero: 72 → 78 → 91, last value at full strength.
/// Renders whatever it is given — on a young series that is one value, which is
/// honest. It must never pad itself to three.
struct PPTrail: View {
    let values: [String]
    let ground: PP.Ground
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 7) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                if i > 0 {
                    Text("→").font(PP.mono(11.5)).foregroundStyle(PP.dim(ground).opacity(0.45))
                }
                Text(v)
                    .font(PP.mono(11.5))
                    .foregroundStyle(i == values.count - 1 ? PP.text(ground) : PP.dim(ground))
            }
        }
        .padding(.top, 14)
    }
}

// MARK: - The stack

/// Vertical paging, one page per gesture, with the right-edge dot rail.
///
/// This was a rotated TabView — the usual trick for making a horizontal pager
/// go vertical. It sized itself off UIScreen.main.bounds, which is not the
/// container it actually lives in when presented as a sheet, so the pages
/// rendered as a small rotated panel floating in black. ScrollView's own paging
/// needs no rotation and no screen measurements: it fills whatever it is given.
///
/// The design specifies no custom animation, so the transition is the
/// platform's scroll physics, untouched.
struct PPStack<Content: View>: View {
    let count: Int
    @Binding var index: Int
    @ViewBuilder var content: Content

    /// scrollPosition speaks in optional ids; the pages speak in an index.
    private var scrolled: Binding<Int?> {
        Binding(get: { index }, set: { if let v = $0 { index = v } })
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) { content }
                .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: scrolled)
        .ignoresSafeArea()
        .overlay(alignment: .trailing) {
            PPDots(count: count, index: $index).padding(.trailing, 9)
        }
    }
}

/// 6px dots, the active one grown to 18. Blend mode difference so one rail reads
/// on both the paper and the ink pages without knowing which it is over.
struct PPDots: View {
    let count: Int
    @Binding var index: Int
    var body: some View {
        VStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { n in
                Capsule()
                    .fill(.white)
                    .frame(width: 6, height: n == index ? 18 : 6)
                    .opacity(n == index ? 0.95 : 0.32)
                    .onTapGesture { withAnimation { index = n } }
            }
        }
        .blendMode(.difference)
        .animation(.easeOut(duration: 0.2), value: index)
    }
}

extension View {
    /// One page of the stack: fills the scroll container exactly, and carries the
    /// id scrollPosition reports back. Both are required — without the frame the
    /// page collapses to its content and paging lands mid-page.
    func pp_page(_ n: Int) -> some View {
        self.containerRelativeFrame([.horizontal, .vertical])
            .id(n)
    }
}
