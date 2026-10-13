//
//  SunnyRefresh.swift
//  Sunny
//
//  Block 25 · SunnyRefresh. The sunrise: the first-load screen (a sun rising
//  over the horizon until the first good update, then Home fades in) and
//  pull to refresh (a deep orange disc rises as you pull, rays past
//  halfway, 110 arms it; let go and the rays spin while it fetches; done
//  says "Updated · just now" and the sun sets). The toast names a change in
//  positions; changed rows get a short surface wash.
//

import SwiftUI

// MARK: - The sun

/// A disc with eight rays. `progress` 0...1 lifts it out of the horizon;
/// `lit` is the full sunrise; `spinning` turns the rays while fetching.
struct SunnySun: View {
    var progress: CGFloat
    var lit: Bool
    var spinning: Bool
    var size: CGFloat = 72           // the ray box; the disc is half
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let bright = lit ? 1 : progress
        let rayH: CGFloat = lit ? 18 : max(0, progress - 0.5) * 28
        let rayO: Double = lit ? 1 : Double(max(0, (progress - 0.5) * 1.9))
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Capsule().fill(S.orange)
                    .frame(width: 2, height: rayH)
                    .offset(y: -(size / 2 - 2) - rayH / 2)
                    .rotationEffect(.degrees(Double(i) * 45))
                    .opacity(rayO)
            }
            .rotationEffect(.degrees(spinning ? (spin ? 360 : 0) : Double(progress) * 120))
            Circle()
                .fill(LinearGradient(colors: [mix(0xF2A93B, 0xFFE98F, bright), mix(0xE8862E, 0xF7CE46, bright)],
                                     startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1)))
                .frame(width: size / 2, height: size / 2)
                .shadow(color: S.yellow.opacity(0.15 + 0.75 * bright), radius: (4 + 56 * bright) / 2)
        }
        .frame(width: size, height: size)
        .onChange(of: spinning, initial: true) { _, on in
            // Reduce Motion: the rays hold still while fetching.
            if on && !reduce { withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { spin = true } }
            else { spin = false }
        }
    }

    private func mix(_ a: UInt32, _ b: UInt32, _ k: CGFloat) -> Color {
        let ca = UIColor(hex: a), cb = UIColor(hex: b)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, al: CGFloat = 0
        ca.getRed(&r1, green: &g1, blue: &b1, alpha: &al); cb.getRed(&r2, green: &g2, blue: &b2, alpha: &al)
        return Color(red: r1 + (r2 - r1) * k, green: g1 + (g2 - g1) * k, blue: b1 + (b2 - b1) * k)
    }
}

// MARK: - First load

/// Until the first good update: the sun rises over the horizon on a 2.6 s
/// loop with "Sunny" and "Fetching your book". No half-empty cards.
struct SunriseLoading: View {
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        ZStack {
            SBackground()
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    SunnySun(progress: up ? 1 : 0, lit: up, spinning: false, size: 96)
                        .offset(y: up ? -34 + 48 : 44 + 48)
                }
                .frame(width: 160, height: 110)
                .clipped()
                Capsule().fill(up ? S.yellow : Color(hex: 0xD7D9DD))
                    .shadow(color: S.yellow.opacity(up ? 0.7 : 0), radius: 8)
                    .frame(width: 272, height: 2)
                VStack(spacing: 10) {
                    Text("Sunny").sType(.largeTitle, tabular: false).foregroundStyle(S.ink)
                    Text("FETCHING YOUR BOOK").sType(SType(size: 11, weight: 600, line: 11, tracking: 0.04), tabular: false)
                        .foregroundStyle(S.muted)
                }
                .padding(.top, 28)
                .opacity(up || reduce ? 1 : 0)
                .offset(y: up || reduce ? 0 : 8)
            }
        }
        .onAppear {
            guard !reduce else { up = true; return }
            withAnimation(S.standard(1.4).repeatForever(autoreverses: true)) { up = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fetching your book")
    }
}

// MARK: - Pull to refresh

enum PullPhase { case idle, pulling, armed, refreshing, done }

struct PullSunrise: View {
    let pull: CGFloat
    let phase: PullPhase
    var body: some View {
        let prog = min(1, pull / 110)
        let lit = phase == .armed || phase == .refreshing || phase == .done
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                SunnySun(progress: prog, lit: lit, spinning: phase == .refreshing)
                    .scaleEffect(phase == .done ? 1.08 : 1)
                    .offset(y: 36 + (phase == .done ? -44 : lit ? -34 : 36 - 70 * prog) - 36)
            }
            .frame(width: 120, height: 92)
            .clipped()
            Capsule().fill(lit ? S.yellow : Color(hex: 0xD7D9DD).mix(with: S.orange, by: prog))
                .shadow(color: (lit ? S.yellow : S.orange).opacity(lit ? 0.7 : 0.5 * prog), radius: lit ? 8 : 5 * prog)
                .frame(width: 272, height: 2)
            Text(phase == .done ? "UPDATED · JUST NOW" : phase == .refreshing ? "FETCHING QUOTES"
                 : phase == .armed ? "RELEASE TO REFRESH" : "PULL FOR THE LATEST")
                .sType(SType(size: 11, weight: 600, line: 11, tracking: 0.04), tabular: false)
                .foregroundStyle(phase == .done ? S.green : S.muted)
                .padding(.top, 12)
        }
        .padding(.bottom, 12)
        .frame(height: 170, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

// MARK: - Toast and wash

struct SunnyToast: View {
    let text: String
    var body: some View {
        // UI Kit toast: 44 tall glass pill, a 24 pt green check, 13/600 ink.
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(S.green))
            Text(text).sType(SType(size: 13, weight: 600, line: 13, tracking: 0), tabular: false).foregroundStyle(S.ink)
        }
        .padding(.leading, 12).padding(.trailing, 16).frame(height: 44)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.14), radius: 16, y: 12)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct ChangedLegsKey: EnvironmentKey { static let defaultValue: Set<String> = [] }
extension EnvironmentValues {
    var changedLegs: Set<String> {
        get { self[ChangedLegsKey.self] }
        set { self[ChangedLegsKey.self] = newValue }
    }
}

/// A 1.2 s surface wash when a row's value changes.
struct Wash: ViewModifier {
    let on: Bool
    var radius: CGFloat = 10
    @State private var level: Double = 0
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(S.surface).opacity(level))
            .onChange(of: on) { _, v in
                guard v else { return }
                level = 1
                withAnimation(.easeOut(duration: 1.2)) { level = 0 }
            }
    }
}
