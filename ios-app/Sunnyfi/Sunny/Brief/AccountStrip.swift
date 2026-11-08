//
//  AccountStrip.swift
//  Sunny
//
//  The account strip (blocks 29 and 33): Overview · Sunny · Nicolay across the top, 72 pt tall. The
//  selected name sits centred in a glass capsule (30 tall, 12 pt sides, radius 15, 14/18 semibold ink);
//  the others 104 pt apart, medium, secondary, fading out at the edges (mask 24% to 76%). Swipe past
//  30 pt or tap a name to switch. Arrow keys and VoiceOver's adjustable action move between accounts.
//

import SwiftUI

struct AccountStrip: View {
    let accounts: [BriefAccount]
    let selected: BriefAccount
    let pick: (BriefAccount) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduce
    @GestureState private var drag: CGFloat = 0

    private var index: Int { accounts.firstIndex(of: selected) ?? 0 }

    var body: some View {
        GeometryReader { g in
            let mid = g.size.width / 2
            ZStack {
                ForEach(Array(accounts.enumerated()), id: \.element) { i, a in
                    let on = a == selected
                    Button { pick(a) } label: {
                        Text(a.name)
                            .font(.system(size: 14, weight: on ? .semibold : .medium))
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
            .animation(reduce ? nil : .timingCurve(0.3, 1.4, 0.5, 1, duration: 0.45), value: selected)
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
                    let to = min(max(index + (dx < 0 ? 1 : -1), 0), accounts.count - 1)
                    if to != index { pick(accounts[to]) }
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Account")
        .accessibilityValue(selected.name)
        .accessibilityAddTraits(.isHeader)
        .accessibilityAdjustableAction { d in
            let to = d == .increment ? index + 1 : index - 1
            if accounts.indices.contains(to) { pick(accounts[to]) }
        }
    }
}
