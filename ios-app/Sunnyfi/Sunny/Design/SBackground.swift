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

    @ViewBuilder private func glows3(w: CGFloat, h: CGFloat) -> some View {
        glow(S.auroraGreen, size: 300, center: CGPoint(x: -80 + 150, y: 120 + 150))
        glow(S.auroraBlue, size: 340, center: CGPoint(x: w + 100 - 170, y: 460 + 170))
        glow(S.auroraYellow, size: 360, center: CGPoint(x: 40 + 180, y: h + 140 - 180))
    }

    private func glow(_ a: (color: Color, light: Double, dark: Double), size: CGFloat, center: CGPoint) -> some View {
        let d = size * 1.35
        return Circle()
            .fill(RadialGradient(colors: [a.color.opacity(scheme == .dark ? a.dark : a.light), a.color.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: d / 2 * 0.7))
            .frame(width: d, height: d)
            .position(center)
    }
}
