//
//  AccountStrip.swift
//  Sunny
//
//  The account strip (blocks 29 and 33): Overview · Sunny · Nicolay across the top, 72 pt tall. The
//  selected name sits centred in a glass capsule (30 tall, 12 pt sides, radius 15, 14/18 semibold ink);
//  the others 104 pt apart, medium, secondary, fading out at the edges (mask 24% to 76%). Swipe past
//  30 pt or tap a name to switch. Arrow keys (once the strip has keyboard focus) and VoiceOver's
//  adjustable action move between accounts.
//
//  Motion: the names slide with S.switchMove, in step with the page's switch; Reduce Motion cross-fades
//  them in place. A switch made here gives the selection haptic.
//

import SwiftUI
import UIKit

struct AccountStrip: View {
    let accounts: [BriefAccount]
    let selected: BriefAccount
    let pick: (BriefAccount) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduce
    @GestureState private var drag: CGFloat = 0
    /// Bumped on each switch made from this strip (tap, swipe, arrow key, VoiceOver): the selection haptic.
    @State private var picks = 0

    private var index: Int { accounts.firstIndex(of: selected) ?? 0 }

    /// The window's top inset (62 pt on a 402 pt phone).
    @MainActor private static var safeTop: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets.top ?? 0
    }
    /// Where the strip rests: y 44, or the safe area top on a phone with less.
    @MainActor static var restY: CGFloat { min(safeTop, 44) }
    /// How far the strip sits above the safe area (18 pt on a 402 pt phone).
    @MainActor static var lift: CGFloat { max(0, safeTop - 44) }

    var body: some View {
        GeometryReader { g in
            let mid = g.size.width / 2
            ZStack {
                ForEach(Array(accounts.enumerated()), id: \.element) { i, a in
                    let on = a == selected
                    Button { choose(a) } label: {
                        Text(a.name)
                            .sType(SType(size: 14, weight: on ? 600 : 500, line: 18, tracking: -0.005), tabular: false)
                            .foregroundStyle(on ? S.ink : S.secondaryOnPage)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background {
                                if on { Capsule().fill(.clear).glassEffect(.regular, in: .capsule) }
                            }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .position(x: mid + CGFloat(i - index) * 104 + drag * 0.35, y: 36)
                    .accessibilityHidden(true)
                }
            }
            // Reduce Motion: a new set of names fades in where they end up (no slide).
            .id(reduce ? selected.rawValue : "names")
            .transition(.opacity)
            .animation(reduce ? S.fade : S.switchMove, value: selected)
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.24),
                                       .init(color: .black, location: 0.76), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            }
        }
        .frame(height: 72)
        .contentShape(Rectangle())
        // Scrolling away it is clipped at its resting top, never drawn under the clock (block 29: moves up 72, clipped).
        .mask {
            GeometryReader { g in
                let cut = min(g.size.height, max(0, Self.restY - g.frame(in: .global).minY))
                Rectangle().padding(.top, cut)
            }
        }
        // Block 29: the strip starts at y 44 (min(safe area top, 44)), the status bar over it. Each page's scroll view
        // starts under the safe area, so the strip draws `lift` higher and keeps its 72 pt slot: what a page puts
        // under it stays put (Home pulls its chart up by `lift` to sit 4 under the strip, as the design does).
        .padding(.top, -Self.lift)
        .padding(.bottom, Self.lift)
        // Simultaneous: a swipe that starts on a name's button, or inside the page's scroll view, still switches
        // (Audit 6: with `.gesture` the strip took taps but never a swipe).
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .updating($drag) { v, s, _ in s = v.translation.width }
                .onEnded { v in
                    let dx = v.translation.width
                    guard abs(dx) > 30 else { return }
                    step(dx < 0 ? 1 : -1)
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Account")
        .accessibilityValue("\(selected.name), \(index + 1) of \(accounts.count)")
        .accessibilityAdjustableAction { d in step(d == .increment ? 1 : -1) }
        // Keyboard focus only (Tab with a hardware keyboard), so a tap never focuses the strip.
        .focusable(interactions: .activate)
        .onKeyPress(.leftArrow) { step(-1) ? .handled : .ignored }
        .onKeyPress(.rightArrow) { step(1) ? .handled : .ignored }
        .sensoryFeedback(.selection, trigger: picks)
    }

    /// The next (+1) or previous (-1) account; false at either end.
    @discardableResult private func step(_ d: Int) -> Bool {
        let to = index + d
        guard accounts.indices.contains(to) else { return false }
        choose(accounts[to])
        return true
    }
    private func choose(_ a: BriefAccount) {
        guard a != selected else { return }
        picks += 1
        pick(a)
    }
}
