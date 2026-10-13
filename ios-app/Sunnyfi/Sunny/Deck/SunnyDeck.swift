//
//  SunnyDeck.swift
//  Sunny
//
//  Block 03 · the Home deck: SunnyDeck (stack, swipe, dots) and
//  SunnyDeckCard (one card). The front card is 353 × 184, radius 24; up to
//  two cards peek above it, each 12 higher and 6% smaller. One card: slot
//  184, no peek, no dots. Two or more: slot 216, dots under. A sideways drag
//  past 40 moves one card and wraps round; vertical scroll always wins; a
//  swipe never fires a tap (400 ms). No cards: the slot is gone.
//

import SwiftUI

struct SunnyDeck: View {
    let cards: [DeckCard]
    let today: String
    let onAction: (DeckCard.Action) -> Void

    /// The cards as they were when a drag began; changes wait for the lift.
    @State private var held: [DeckCard]?
    @State private var index = 0
    @State private var lastSwipe = Date.distantPast
    @State private var dismissed: Set<String> = []

    private var live: [DeckCard] { (held ?? cards).filter { !dismissed.contains($0.id) } }

    var body: some View {
        let deck = live, n = deck.count, di = n > 0 ? index % n : 0
        Group {
            if n > 0 {
                ZStack(alignment: .top) {
                    ForEach(Array(deck.enumerated()), id: \.element.id) { i, c in
                        let r = (i - di + n) % n, b = min(r, 2)
                        SunnyDeckCard(card: c,
                                      onTap: { tap(c) },
                                      onDismiss: { dismiss(c) })
                            .scaleEffect(1 - 0.06 * CGFloat(b))
                            .offset(y: (n > 1 ? 16 : 0) - 12 * CGFloat(b))
                            .opacity(r > 2 ? 0 : 1)
                            .zIndex(Double(n - r))
                            .allowsHitTesting(r == 0)
                            .accessibilityHidden(r != 0)
                    }
                    if n > 1 {
                        HStack(spacing: 6) {
                            ForEach(Array(deck.enumerated()), id: \.element.id) { i, _ in
                                Capsule().fill(i == di ? S.ink : S.line)
                                    .frame(width: i == di ? 18 : 6, height: 6)
                                    .padding(.vertical, 10).padding(.horizontal, 2)
                                    .contentShape(Rectangle())
                                    .onTapGesture { withAnimation(S.standard(0.5)) { index = i } }
                                    .accessibilityLabel("Card \(i + 1) of \(n)")
                            }
                        }
                        .offset(y: 210 - 10)
                        .animation(.easeOut(duration: 0.3), value: di)
                    }
                }
                .frame(height: n > 1 ? 216 : 184, alignment: .top)
                .frame(maxWidth: .infinity)
                .simultaneousGesture(swipe(n))
                .accessibilityElement(children: .contain)
                .accessibilityAdjustableAction { dir in go(dir == .increment ? 1 : -1, n) }
            }
        }
        .animation(S.standard(0.5), value: n)
        .animation(S.standard(0.5), value: cards.map(\.id))
    }

    private func swipe(_ n: Int) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { _ in if held == nil { held = cards } }
            .onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                if abs(dx) > 40, abs(dx) > abs(dy) {
                    lastSwipe = Date()
                    go(dx < 0 ? 1 : -1, n)
                }
                withAnimation(S.standard(0.5)) { held = nil }
            }
    }

    private func go(_ d: Int, _ n: Int) {
        guard n > 1 else { return }
        withAnimation(S.standard(0.5)) { index = ((index % n + d) % n + n) % n }
    }

    private func tap(_ c: DeckCard) {
        guard Date().timeIntervalSince(lastSwipe) > 0.4, let a = c.action else { return }
        onAction(a)
    }

    private func dismiss(_ c: DeckCard) {
        guard let d = c.dismiss else { return }
        DeckDismissals.hide(d.key, until: d.until, today: today)
        withAnimation(S.standard(0.5)) {
            dismissed.insert(c.id)
            index = 0
        }
    }
}

// MARK: - One card

struct SunnyDeckCard: View {
    let card: DeckCard
    let onTap: () -> Void
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var fg: Color {
        switch card.tone { case .yellow: S.deckInk; case .ink, .green: .white; case .frosted: S.ink }
    }
    private var markColor: Color {
        switch card.tone {
        case .yellow: S.deckInk.opacity(0.08)
        case .ink: Color.white.opacity(0.08)
        case .green: Color.white.opacity(0.10)
        case .frosted: scheme == .dark ? Color.white.opacity(0.06) : S.deckInk.opacity(0.06)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: S.rDeck, style: .continuous)
        ZStack(alignment: .topLeading) {
            background
            // The faint mark: 200/200 800, right -18, bottom -58 (CSS box).
            Text(card.mark)
                .sType(SType(size: 200, weight: 800, line: 200, tracking: -0.07), tabular: false)
                .foregroundStyle(markColor)
                .fixedSize()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 18, y: 31)   // lands the glyphs where the CSS box puts them
                .accessibilityHidden(true)
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(card.kicker.uppercased())
                        .sType(SType(size: 13, weight: 700, line: 16, tracking: 0.06), tabular: false)
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(card.title)
                                .sType(SType(size: 30, weight: 700, line: 34, tracking: -0.02), tabular: false)
                                .frame(maxWidth: card.action == nil ? 280 : 230, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(card.sub)
                                .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        if card.action != nil { arrow }
                    }
                }
                .foregroundStyle(fg)
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(SPressStyle())
            .disabled(card.action == nil)
            if card.dismiss != nil {
                Button(action: onDismiss) {
                    SCross(half: 6).stroke(fg, lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle().inset(by: -6))
                }
                .buttonStyle(SPressStyle())
                .opacity(0.7)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 14).padding(.trailing, 14)
                .accessibilityLabel("Dismiss")
            }
        }
        .frame(height: 184)
        .clipShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.kicker). \(card.title). \(card.sub)")
        .accessibilityAddTraits(card.action != nil ? .isButton : [])
    }

    @ViewBuilder private var background: some View {
        switch card.tone {
        case .yellow: S.deckYellow
        case .ink: S.deckInk
        case .green: S.deckGreen
        case .frosted: SFrostedSurface(radius: S.rDeck)
        }
    }

    private var arrow: some View {
        let (fill, rim): (Color, Color) = {
            switch card.tone {
            case .yellow: (Color.white.opacity(0.42), Color.white.opacity(0.75))
            case .ink: (Color.white.opacity(0.14), Color.white.opacity(0.25))
            case .green: (Color.white.opacity(0.18), Color.white.opacity(0.35))
            case .frosted: scheme == .dark ? (Color.white.opacity(0.12), Color.white.opacity(0.18))
                                           : (Color.white.opacity(0.6), Color.white.opacity(0.9))
            }
        }()
        return Text("→")
            .font(SType(size: 22, weight: 700, line: 22, tracking: 0).font())
            .frame(width: 48, height: 48)
            .background(Circle().fill(fill))
            .overlay(Circle().strokeBorder(rim, lineWidth: 0.5))
            .shadow(color: .black.opacity(card.tone == .yellow ? 0.06 : 0), radius: 1.5, y: 1)
            .accessibilityHidden(true)
    }
}
