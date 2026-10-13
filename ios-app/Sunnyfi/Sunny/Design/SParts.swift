//
//  SParts.swift
//  Sunny
//
//  The base parts every block is built from (README Build order, Step 3):
//  card, glass card, frosted deck surface, pill, section title, number.
//  Blocks use these and the S tokens only.
//

import SwiftUI

// MARK: - Card

/// A solid paper card: radius 20, 1 pt line, padding 20, full width inside
/// the page's 20 pt margins (353 on a 393 phone).
struct SCard<Content: View>: View {
    var padding: CGFloat = S.padCard
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: S.rCard, style: .continuous).fill(S.paper))
            .overlay(RoundedRectangle(cornerRadius: S.rCard, style: .continuous).strokeBorder(S.line, lineWidth: 1))
    }
}

/// A Liquid Glass card (README Rules, Glass cards): Positions · All, its empty
/// state, the Inventory ticker card, the Theta and Delta pair. Never a card
/// with a dense table; at most one per section outside that pair.
struct SGlassCard<Content: View>: View {
    var padding: CGFloat = S.padCard
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: S.rCard))
            .shadow(color: .black.opacity(0.04), radius: 1.5, y: 1)
            .shadow(color: .black.opacity(0.10), radius: 12, y: 10)
    }
}

/// Frosted solid (tokens.md, deck cards): the glass sheen, lit rim and
/// shadow on an opaque fill, because other deck cards stack behind it.
/// The design's glassSh, light | dark: a 1 px white ring (.7 | .16), the
/// top-left edge lit (1 | .28), the bottom-right faint (.55 | .08), a soft
/// glow inside the top (.9 | .12), a hairline outside (light only) and the
/// drop shadow (.04/.1 | .2/.4).
struct SFrostedSurface: View {
    var radius: CGFloat = S.rDeck
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape.fill(LinearGradient(stops: [
                .init(color: S.frost[0], location: 0),
                .init(color: S.frost[1], location: 0.55),
                .init(color: S.frost[2], location: 1),
            ], startPoint: UnitPoint(x: 0.1, y: 0), endPoint: UnitPoint(x: 0.9, y: 1)))
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(dark ? 0.12 : 0.9), .white.opacity(0)],
                                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.14))))
            .overlay(shape.strokeBorder(.white.opacity(dark ? 0.16 : 0.7), lineWidth: 1))
            .overlay(shape.strokeBorder(LinearGradient(stops: [
                    .init(color: .white.opacity(dark ? 0.28 : 1), location: 0),
                    .init(color: .white.opacity(0), location: 0.5),
                    .init(color: .white.opacity(dark ? 0.08 : 0.55), location: 1),
                ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .overlay(shape.stroke(Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255).opacity(dark ? 0 : 0.06), lineWidth: 1))
            .shadow(color: .black.opacity(dark ? 0.2 : 0.04), radius: 1.5, y: 1)
            .shadow(color: .black.opacity(dark ? 0.32 : 0.08), radius: 12, y: 10)
    }
}

// MARK: - Pill

/// A filter pill (UI Kit §08): Inter 600 12, radius 30, selected = ink fill.
struct SPill: View {
    let title: String
    let selected: Bool
    var height: CGFloat = 32
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .sType(.label, tabular: false)
                .foregroundStyle(selected ? S.paper : S.ink)
                .padding(.horizontal, 14)
                .frame(height: height)
                .background(Capsule().fill(selected ? S.ink : S.surface))
                .contentShape(Rectangle())
        }
        .buttonStyle(SPressStyle())
        .animation(S.standard(S.tap), value: selected)
    }
}

/// Press feedback: a 0.97 scale, 0.18 s (tokens.md S.dur.tap).
struct SPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: S.tap), value: configuration.isPressed)
    }
}

// MARK: - Section title (block 08)

struct SSectionTitle: View {
    let title: String
    var body: some View {
        Text(title).sType(.sectionHead, tabular: false).foregroundStyle(S.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Number

/// A number that counts up from 0 the first time it is seen (0.85 s ease-out)
/// and afterwards rolls its digits to each new value (.numericText, ~0.4 s).
/// No colour flash on the tick. Reduce Motion: set at once.
struct SNumber: View {
    let value: Double
    let format: (Double) -> String
    var countUp: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown: Double = 0
    @State private var counting = false
    @State private var seen = false

    var body: some View {
        Group {
            if counting {
                SCounting(value: shown, format: format)
            } else {
                Text(format(shown)).contentTransition(.numericText(value: shown))
            }
        }
        .onAppear {
            guard !seen else { return }
            seen = true
            if reduce || !countUp { shown = value; return }
            counting = true
            shown = 0
            withAnimation(.easeOut(duration: S.count)) { shown = value } completion: { counting = false }
        }
        .onChange(of: value) { _, v in
            if reduce || counting { shown = v; return }
            withAnimation(.smooth(duration: S.roll)) { shown = v }
        }
    }
}

/// Interpolates the value frame by frame for the first count-up.
private struct SCounting: View, Animatable {
    var value: Double
    let format: (Double) -> String
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { Text(format(value)) }
}

// MARK: - Enter once

extension View {
    /// Cards and totals fade in with a small rise the first time they appear,
    /// staggered ~70 ms (README Motion). Never on refresh.
    func sEnter(_ index: Int = 0) -> some View { modifier(SEnter(index: index)) }
}

private struct SEnter: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 12)
            .onAppear {
                guard !shown else { return }
                withAnimation(reduce ? .easeOut(duration: 0.2)
                              : S.standard(0.5).delay(Double(index) * S.stagger)) { shown = true }
            }
    }
}
