//
//  SunnyFeed.swift
//  Sunny — rows 5 and 6. CHROME.md §5, §6, §8, §9 and CARDS.md are normative.
//

import SwiftUI

// MARK: - the card slot

/// CARDS.md: the shell ships with two --wash bars inside. Populating a card
/// means replacing ONLY those two bars. The shell itself is not to be touched.
///
/// ⚠ NEVER set opacity, transform or transition here. The reveal animation
/// writes all three from outside; a value in the shell will fight it and flicker.
struct SunnyCardSlot: View {
    let card: SunnyCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(S.wash).frame(width: 34, height: S.barH)
            Spacer(minLength: 0)                      // justify-content: space-between
            RoundedRectangle(cornerRadius: S.radiusBar)
                .fill(S.wash).frame(height: S.barH)
        }
        .padding(card.size.padding)
        .frame(maxWidth: .infinity)
        // Column span + aspect-ratio, never a fixed width or height (SPEC 01).
        .aspectRatio(card.size.ratio, contentMode: .fit)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(card.size.shadow)
        .measure("card-" + card.size.rawValue)
    }
}

// MARK: - row 5a · filter row, 44pt, sticky

struct SunnyFilterRow: View {
    @Binding var selected: Set<SunnyTag>
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: S.gap7) {
            ScrollView(.horizontal) {
                HStack(spacing: S.hitGrow) {
                    ForEach(SunnyTag.allCases) { tag in
                        SunnyFilterLabel(
                            text: tag.label,
                            on: selected.contains(tag),
                            colourOn: S.ink, colourOff: S.mute
                        ) {
                            // Multi-select, OR-matched. Tapping the only selected
                            // label clears it.
                            if selected.contains(tag) { selected.remove(tag) } else { selected.insert(tag) }
                            onChange()
                        }
                    }
                }
                .frame(height: S.filterrowH)
            }
            .scrollIndicators(.hidden)
            SunnyFilterLabel(text: "Clear", on: false,
                             colourOn: S.faint, colourOff: S.faint, weight: S.wSemi) {
                selected.removeAll(); onChange()          // resets filters only, not the query
            }
            .opacity(selected.isEmpty ? 0 : 1)
            .allowsHitTesting(!selected.isEmpty)
            .animation(.easeInOut(duration: S.transition), value: selected.isEmpty)
        }
        .padding(.horizontal, S.margin)
        .frame(height: S.filterrowH)
        .background(S.ground)
        .measure("row5-filterrow")
    }
}

/// ⚠ DO NOT RE-DERIVE THIS. CHROME.md §5: the 44pt target is DECOUPLED from the
/// text box by an overlay that overflows the row without participating in
/// layout, so the text keeps its 16pt rhythm while every label still gets
/// 44 × 44 of hit area, expanding symmetrically. Solving it with padding or a
/// minimum width instead pushes the text off the grid.
struct SunnyFilterLabel: View {
    let text: String
    let on: Bool
    let colourOn: Color
    let colourOff: Color
    var weight: Font.Weight? = nil
    let action: () -> Void

    var body: some View {
        Text(text)
            .font(InkFont.display(S.t13, weight ?? (on ? S.wBold : S.wMid)))
            .tracking(S.track(S.t13, -0.005))
            .foregroundStyle(on ? colourOn : colourOff)
            .fixedSize()
            .overlay {
                GeometryReader { g in
                    Color.clear
                        .frame(width: max(g.size.width + S.hitGrow, S.hitMin),
                               height: g.size.height + S.hitBleed * 2)
                        .contentShape(Rectangle())
                        .position(x: g.size.width / 2, y: g.size.height / 2)
                        .onTapGesture(perform: action)
                }
            }
    }
}

// MARK: - row 5b · the pane

struct SunnyPane: View {
    @Binding var query: String
    @Binding var filters: Set<SunnyTag>
    @Binding var activeZone: SunnyZone
    let jumpTo: SunnyZone?
    let onJumpHandled: () -> Void

    @State private var rowHidden = false
    @State private var lastY: CGFloat = 0
    @State private var loading = false
    @State private var revealToken = UUID()
    @State private var debounce: Task<Void, Never>?
    @State private var sectionTops: [SunnyZone: CGFloat] = [:]

    private func visible(_ z: SunnyZone) -> [SunnyCard] {
        SunnyDeck.cards(z).filter { $0.matches(query: query, filters: filters) }
    }

    var body: some View {
        // The wrapper is NON-scrolling and exists only so the overlay can anchor
        // to the visible pane. CHROME.md §6: an absolute child of a scrolling
        // element rides scrollTop and vanishes the moment the user scrolls.
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // The filter row's slot in the flow, preserved so cards
                        // never shift when the row hides.
                        Color.clear.frame(height: S.filterrowH)
                        ForEach(SunnyZone.allCases) { zone in
                            SunnySection(zone: zone, cards: visible(zone), token: revealToken)
                                .id(zone)
                                .background {
                                    GeometryReader { g in
                                        Color.clear.onAppear {
                                            sectionTops[zone] = g.frame(in: .named("content")).minY
                                        }
                                    }
                                }
                        }
                        Color.clear.frame(height: 28)          // tail spacer
                    }
                    .coordinateSpace(.named("content"))
                }
                .scrollIndicators(.hidden)
                .onChange(of: jumpTo) { _, z in
                    guard let z else { return }
                    withAnimation(.easeInOut) { proxy.scrollTo(z, anchor: .top) }
                    onJumpHandled()
                }
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                    // CHROME.md §5: 4px dead-band suppresses jitter; always shown
                    // below --scroll-reveal.
                    if y < S.scrollReveal { rowHidden = false }
                    else if y > lastY + S.scrollDeadband { rowHidden = true }
                    else if y < lastY - S.scrollDeadband { rowHidden = false }
                    lastY = y
                    let line = y + S.zoneLine
                    for z in SunnyZone.allCases where (sectionTops[z] ?? .infinity) <= line { activeZone = z }
                }
            }
            .background(S.ground)

            SunnyFilterRow(selected: $filters) { applyChange(S.debounceFilter) }
                .offset(y: rowHidden ? -S.filterrowH : 0)
                .opacity(rowHidden ? 0 : 1)
                .allowsHitTesting(!rowHidden)
                .animation(S.cEaseOut.speed(1 / S.durFilterrow), value: rowHidden)

            if loading {
                SunnySkeleton()
                    .padding(.top, S.filterrowH)      // keeps the row live during load
                    .transition(.opacity.combined(with: .offset(y: S.overlayLift)))
            }
        }
        .onChange(of: query) { _, _ in applyChange(S.debounceQuery) }
    }

    /// Every trigger cancels the previous timer (CHROME.md §8).
    private func applyChange(_ delay: Double) {
        debounce?.cancel()
        withAnimation(.easeInOut(duration: S.durOverlayIn)) { loading = true }
        debounce = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: S.durOverlayOut)) { loading = false }
                revealToken = UUID()
            }
        }
    }
}

// MARK: - a zone

struct SunnySection: View {
    let zone: SunnyZone
    let cards: [SunnyCard]
    let token: UUID

    /// Pack into rows: a span-2 card sits alone, span-1 cards pair up.
    private var rows: [[SunnyCard]] {
        var out: [[SunnyCard]] = [], pending: [SunnyCard] = []
        for c in cards {
            if c.size.span == 2 {
                if !pending.isEmpty { out.append(pending); pending = [] }
                out.append([c])
            } else {
                pending.append(c)
                if pending.count == 2 { out.append(pending); pending = [] }
            }
        }
        if !pending.isEmpty { out.append(pending) }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            if cards.isEmpty {
                // Zones never collapse and never reorder. The section keeps its padding.
                Text("Nothing in this zone for that filter.")
                    .font(InkFont.display(S.t13, S.wMid))
                    .foregroundStyle(S.mute2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 20, leading: 2, bottom: 4, trailing: 2))
            } else {
                // Pinned to the content token so the two columns divide exactly.
                // Left to flex, SwiftUI's rounding landed each column at 174.67
                // against a spec of 174.50 — half a pixel at 3x, but SPEC 11
                // asks for 174.5 and the grid IS 361 wide by definition.
                VStack(spacing: S.gutter) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { ri, row in
                        HStack(spacing: S.gutter) {
                            ForEach(row) { c in SunnyCardSlot(card: c)
                                .frame(width: c.size.span == 2 ? S.content : S.col)
                                .sunnyReveal(index: ri, token: token) }
                            // A lone span-1 card keeps its column; it must not stretch.
                            if row.count == 1 && row[0].size.span == 1 { Color.clear.frame(maxWidth: .infinity) }
                        }
                    }
                }
                .frame(width: S.content)
            }
        }
        .padding(zone.padding)
    }
}

/// CHROME.md §9. Stagger counts VISIBLE cards only and caps at 300ms so a long
/// list does not feel slow.
extension View {
    func sunnyReveal(index: Int, token: UUID) -> some View {
        modifier(SunnyReveal(index: index, token: token))
    }
}

struct SunnyReveal: ViewModifier, Animatable {
    let index: Int
    let token: UUID
    @State private var shown = false

    func body(content: Content) -> some View {
        let delay = min(Double(index) * S.stagger, S.staggerCap)
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : S.revealScale)
            .offset(y: shown ? 0 : S.revealRise)
            .onAppear { fire(delay) }
            .onChange(of: token) { _, _ in shown = false; fire(delay) }
    }

    private func fire(_ delay: Double) {
        withAnimation(S.cEaseOut.speed(1 / S.durRevealOpacity).delay(delay)) { shown = true }
    }
}

// MARK: - §8 loading skeleton

struct SunnySkeleton: View {
    @State private var pulse = false
    /// The rhythm mirrors the real deck: S S / M / S S / XS.
    private let blocks: [(CGFloat, Double, Bool)] = [
        (104, 0.06, true), (148, 0.20, false), (104, 0.26, true), (72, 0.40, false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: S.gap4) {
            RoundedRectangle(cornerRadius: S.radiusPip)
                .fill(S.skeletonLabel).frame(width: 96, height: 11)
                .opacity(pulse ? 1 : 0.45)
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                if b.2 {
                    HStack(spacing: S.gap4) {
                        ForEach(0..<2, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: S.gap3)
                                .fill(S.skeleton).frame(height: b.0)
                        }
                    }
                    .opacity(pulse ? 1 : 0.45)
                } else {
                    RoundedRectangle(cornerRadius: S.gap3)
                        .fill(S.skeleton).frame(height: b.0)
                        .opacity(pulse ? 1 : 0.45)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: S.gap4, leading: S.margin, bottom: 0, trailing: S.margin))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(S.ground)
        .onAppear {
            withAnimation(.easeInOut(duration: S.pulse).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
