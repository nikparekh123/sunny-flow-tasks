//
//  InkChrome.swift
//  Sunnyfi — Ink design system (greenfield rebuild)
//
//  Layout chrome: the ticker nav, section head, horizontal snap rail + groups,
//  the floating glass tab bar (inverted selection, never hued), the bottom-sheet
//  shell, and the staggered card-entrance motion. All monochrome (Law 1).
//

import SwiftUI

// MARK: - Card entrance (translateY(10) + fade, 450ms, staggered ≤5)

struct InkEntrance: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .opacity((shown || reduce) ? 1 : 0)
            .offset(y: (shown || reduce) ? 0 : 10)
            .onAppear { withAnimation(InkMotion.ease(0.45).delay(Double(min(index, 4)) * 0.055)) { shown = true } }
    }
}
extension View { func inkEntrance(_ i: Int = 0) -> some View { modifier(InkEntrance(index: i)) } }

// MARK: - Ticker nav (top)

struct InkTickerNav: View {
    let symbols: [String]
    @Binding var selected: String
    var body: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(symbols, id: \.self) { s in
                        Button { selected = s } label: {
                            Text(s).font(InkFont.display(15, .medium)).foregroundStyle(Ink.text)
                                .inkRelevance(s == selected ? .r1 : .r3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Circle().fill(Ink.text).frame(width: 6, height: 6).inkPulse()
                Text("LIVE").font(InkFont.mono(9.5)).tracking(9.5 * 0.18).foregroundStyle(Ink.dim)
            }
            .fixedSize()
        }
        .padding(EdgeInsets(top: 22, leading: 16, bottom: 18, trailing: 16))
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.hair).frame(height: 1) }
    }
}

// MARK: - Section head (Newsreader heading + right-aligned count column)

struct InkSectionHead: View {
    let title: String
    var count: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(InkFont.serif(29)).tracking(29 * -0.01)
                .foregroundStyle(Ink.text).lineLimit(1).fixedSize()
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Text(count).font(InkFont.mono(10.5)).tracking(10.5 * 0.16).foregroundStyle(Ink.dim)
                if let action {
                    Button { onAction?() } label: {
                        Text(action).font(InkFont.mono(10.5)).tracking(10.5 * 0.16)
                            .foregroundStyle(Ink.text).underline(true, color: Ink.hair)
                    }
                    .buttonStyle(.plain)
                }
            }
            .fixedSize()
        }
        .padding(EdgeInsets(top: 26, leading: 16, bottom: 20, trailing: 16))
    }
}

// MARK: - Card rail + group

struct InkRail<Content: View>: View {
    var slip: Bool = false            // a rail containing roll slips reserves 60px bottom
    var compact: Bool = false
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) { content }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, slip ? 60 : 8)
                .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }
}

/// A labelled column of cards inside a rail (the label is sticky-left in the
/// reference; here it scrolls with its group — refine later).
struct InkGroup<Content: View>: View {
    var label: String
    var glyph: String? = nil
    var count: Int? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                if let glyph { Text(glyph).font(InkFont.mono(11)).foregroundStyle(Ink.text) }
                Text(label.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.2).foregroundStyle(Ink.dim)
                if let count {
                    Text("\(count)").font(InkFont.mono(9.5)).tracking(9.5 * 0.1).foregroundStyle(Ink.text)
                }
            }
            HStack(alignment: .top, spacing: 10) { content }
        }
    }
}

// MARK: - Floating glass tab bar (selection is inversion, never a hue)

struct InkTabBar: View {
    @Binding var selection: Int      // 0 portfolio · 1 events · 2 profile
    private let icons = ["briefcase", "clock.arrow.circlepath", "person"]
    var body: some View {
        HStack(spacing: 18) {
            ForEach(0..<3, id: \.self) { i in
                Button { selection = i } label: {
                    Image(systemName: icons[i]).font(.system(size: 18, weight: .regular))
                        .frame(width: 38, height: 38)
                        .foregroundStyle(selection == i ? Ink.invertText : Ink.dim)
                        .background { if selection == i { Circle().fill(Ink.invertBg) } }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Ink.hair, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 11, x: 0, y: 6)
        .animation(InkMotion.fast, value: selection)
    }
}

// MARK: - Bottom-sheet shell (present via .sheet { InkSheet { … } })

struct InkSheet<Head: View, Content: View, Dock: View>: View {
    @ViewBuilder var head: Head
    @ViewBuilder var content: Content
    @ViewBuilder var dock: Dock

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Ink.hair).frame(width: 38, height: 4).padding(.top, 10).padding(.bottom, 8)
            head
                .padding(EdgeInsets(top: 8, leading: 22, bottom: 20, trailing: 22))
                .overlay(alignment: .bottom) { Rectangle().fill(Ink.hair).frame(height: 1) }
            ScrollView { content }.scrollIndicators(.hidden)
            dock
                .padding(EdgeInsets(top: 18, leading: 22, bottom: 30, trailing: 22))
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.surface)
        .presentationDetents([.fraction(0.88)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Ink.surface)
        .presentationCornerRadius(Ink.radiusCard)
    }
}
