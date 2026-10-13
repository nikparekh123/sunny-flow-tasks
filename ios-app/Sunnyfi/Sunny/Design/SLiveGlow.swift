//
//  SLiveGlow.swift
//  Sunny
//
//  Block 24 · SunnyLiveGlow: a soft sun (a moon in dark) in the top right of
//  a live card that pulses each time its numbers update. 140 across, centred
//  60 outside the corner, clipped by the card, under the content.
//  Pulse: from nothing at 60% size, to full in 0.6 s (size over 0.9 s),
//  settles to 45% from 1 s over 2.4 s, then fades out over 90 s from 3.5 s.
//  Every live card pulses on the same update. Reduce Motion: fades only.
//

import SwiftUI

private struct LivePulseKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    /// Bumped on every good live update; cards pulse on it.
    var livePulse: Int {
        get { self[LivePulseKey.self] }
        set { self[LivePulseKey.self] = newValue }
    }
}

struct SGlowLayer: View {
    @Environment(\.livePulse) private var pulse
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 1
    @State private var run: Task<Void, Never>?

    var body: some View {
        GeometryReader { g in
            Circle()
                .fill(RadialGradient(colors: [scheme == .dark ? S.glowMoon : S.glowSun, .clear],
                                     center: .center, startRadius: 0, endRadius: 70 * 0.68))   // clear at 68% of the radius
                .frame(width: 140, height: 140)
                .scaleEffect(scale)
                .opacity(opacity)
                .position(x: g.size.width + 60 - 70, y: -60 + 70)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: pulse) { _, _ in fire() }
        .onDisappear { run?.cancel() }
    }

    private func fire() {
        run?.cancel()
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { opacity = 0; scale = reduce ? 1 : 0.6 }
        run = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(S.standard(0.6)) { opacity = 1 }
            if !reduce { withAnimation(S.standard(0.9)) { scale = 1 } }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(S.standard(2.4)) { opacity = 0.45 }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: 90)) { opacity = 0 }
        }
    }
}

extension View {
    /// A solid paper card surface: radius, 1 pt line, and the live glow
    /// under the content when `glow` is on.
    func sCardSurface(radius: CGFloat = S.rCard, glow: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background {
                ZStack {
                    shape.fill(S.paper)
                    if glow { SGlowLayer() }
                }
                .clipShape(shape)
            }
            .overlay(shape.strokeBorder(S.line, lineWidth: 1))
    }

    /// The live glow alone, for a card that draws its own surface (glass).
    func sunnyGlow(radius: CGFloat = S.rCard) -> some View {
        background { SGlowLayer().clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous)) }
    }
}
