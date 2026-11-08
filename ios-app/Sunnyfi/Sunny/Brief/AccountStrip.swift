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

struct AccountStrip: View {
    let accounts: [BriefAccount]
    let selected: BriefAccount
    let pick: (BriefAccount) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduce
    @GestureState private var drag: CGFloat = 0
    /// Bumped on each switch made from this strip (tap, swipe, arrow key, VoiceOver): the selection haptic.
    @State private var picks = 0

    private var index: Int { accounts.firstIndex(of: selected) ?? 0 }

    var body: some View {
        GeometryReader { g in
            let mid = g.size.width / 2
            ZStack {
                ForEach(Array(accounts.enumerated()), id: \.element) { i, a in
                    let on = a == selected
                    Button { choose(a) } label: {
                        Text(a.name)
                            .sFont(14, on ? .semibold : .medium)
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
        .gesture(
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
