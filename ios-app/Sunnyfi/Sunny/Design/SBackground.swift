//
//  SBackground.swift
//  Sunny
//
//  The screen behind everything: S.screen's gradient and the three aurora
//  glows, fixed while the page scrolls. Sizes and places as the design
//  draws them on a 393 phone: 300 at left -80 / top 120, 340 at right -100 /
//  top 460, 360 at left 40 / bottom -140, each scaled 1.35, fading out at
//  70% of the radius.
//

import SwiftUI

struct SBackground: View {
    @Environment(\.colorScheme) private var scheme
    /// The aurora glows. Off on the Positions tab: the design draws it on the plain gradient in both themes, and
    /// its secondary text over the green glow fell to 4.1:1 in dark (Pass 4).
    var glows = true

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                S.screen
                if glows { glows3(w: w, h: h) }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The design's exact blobs (Nik's glass spec, 8 Nov 2026): green at (70, 270) to radius 200, blue at
    /// (width − 70, 630) to 227, yellow at (220, height − 40) to 240, each a RadialGradient from its colour to clear.
    @ViewBuilder private func glows3(w: CGFloat, h: CGFloat) -> some View {
        glow(S.auroraGreen, radius: 200, center: CGPoint(x: 70, y: 270))
        glow(S.auroraBlue, radius: 227, center: CGPoint(x: w - 70, y: 630))
        glow(S.auroraYellow, radius: 240, center: CGPoint(x: 220, y: h - 40))
    }

    private func glow(_ a: (color: Color, light: Double, dark: Double), radius: CGFloat, center: CGPoint) -> some View {
        Circle()
            .fill(RadialGradient(colors: [a.color.opacity(scheme == .dark ? a.dark : a.light), a.color.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: radius))
            .frame(width: radius * 2, height: radius * 2)
            .position(center)
    }
}
