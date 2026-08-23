//
//  SunnyChrome.swift
//  Sunny — rows 2 to 4 of the phone. CHROME.md is normative and measured.
//
//  ⚠ ROWS 1 AND 6 ARE THE OPERATING SYSTEM'S, NOT OURS.
//  CHROME.md §1 specifies a 54pt status bar with a drawn clock, four signal bars
//  and a battery, and §7 a 24pt home indicator. Those exist because the handoff
//  was authored as an HTML mock of a phone, where the phone had to be drawn.
//  Inside a real app the real ones are already there, one point above this view,
//  and drawing a second set would put two clocks on screen. So the safe area
//  supplies rows 1 and 6 and this file starts at row 2. Flagged for Nik rather
//  than decided quietly, because it is the one place the spec cannot be followed
//  literally.
//

import SwiftUI

// MARK: - row 2 · ticker strip, 34pt

struct SunnyTicker: View {
    let state: SunnyMarketState
    let quotes: [SunnyQuote]
    @Binding var showPercent: Bool

    var body: some View {
        HStack(spacing: S.gap7) {
            HStack(spacing: S.gap3) {
                Circle().fill(state.dot).frame(width: S.gap3, height: S.gap3)
                Text(state.label)
                    .font(InkFont.display(S.t11, S.wSemi))
                    .tracking(S.track(S.t11, 0.02))
                    .foregroundStyle(S.mute)
            }
            HStack(spacing: S.gap6) {
                Spacer(minLength: 0)
                ForEach(quotes) { q in
                    HStack(alignment: .firstTextBaseline, spacing: S.gap2) {
                        Text(q.symbol)
                            .font(InkFont.display(S.t11, S.wBold))
                            .foregroundStyle(S.ink)
                        Text(showPercent ? q.percent : q.last)
                            .font(InkFont.display(S.t11, S.wMid))
                            .foregroundStyle(q.up ? S.tickUp : S.tickDown)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .monospacedDigit()                       // tabular in BOTH modes, so no reflow
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(S.cEaseSwap.speed(1 / S.durSwap)) { showPercent.toggle() } }
        }
        .padding(.horizontal, S.margin)
        .frame(height: S.tickerH)
        .overlay(alignment: .bottom) {
            // SPEC 04: a rule is a child view with a height, never a border.
            Rectangle().fill(S.wash).frame(height: S.rule)
        }
    }
}

// MARK: - row 3 · zone bar, 56pt

struct SunnyZoneBar: View {
    let active: SunnyZone
    /// CHROME.md §3: narrowed = a filter is selected OR the query is non-empty.
    /// All three labels go --dim and lose their hit area, because jumping to a
    /// zone is meaningless while the feed is filtered.
    let narrowed: Bool
    let onJump: (SunnyZone) -> Void
    @Binding var searchOpen: Bool

    private func colour(_ z: SunnyZone) -> Color {
        narrowed ? S.dim : (z == active ? S.ink : S.faint)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: S.gap4 + 1) {                    // 9pt
                ForEach(Array(SunnyZone.allCases.enumerated()), id: \.element.id) { i, z in
                    if i > 0 {
                        Text("\u{2014}")                      // em dash. not a slash, not a bullet
                            .font(InkFont.display(S.t22, .regular))
                            .foregroundStyle(S.dim)
                    }
                    Text(z.label)
                        .font(InkFont.display(S.t22, S.wSemi))
                        .tracking(S.track(S.t22, -0.025))
                        .foregroundStyle(colour(z))
                        .animation(.easeInOut(duration: S.durZone), value: narrowed)
                        .contentShape(Rectangle())
                        .onTapGesture { if !narrowed { onJump(z) } }
                        .allowsHitTesting(!narrowed)
                }
            }
            Spacer(minLength: 0)
            SunnySearchButton(active: $searchOpen)
        }
        .padding(.horizontal, S.margin)
        .frame(height: S.zonebarH)
        .background(S.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(S.wash).frame(height: S.rule) }
    }
}

/// 44 × 44 tap box holding a 30pt disc. The negative trailing inset lands the
/// disc 16pt from the frame edge while keeping the full 44pt target.
struct SunnySearchButton: View {
    @Binding var active: Bool
    var body: some View {
        Button { withAnimation(.easeInOut(duration: S.durDrawer)) { active.toggle() } } label: {
            ZStack {
                Circle()
                    .fill(active ? S.ink : S.wash)
                    .frame(width: S.zonebarH - 26, height: S.zonebarH - 26)   // 30
                SunnyLens(size: 14, stroke: 1.6, colour: active ? S.onInk : S.mute2)
            }
            .frame(width: S.hitMin, height: S.hitMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, -7)
        .animation(.easeInOut(duration: S.transition), value: active)
    }
}

/// CHROME.md §3: circle 11 × 11 at 0,0 in a 14 × 14 box; handle 6 × 1.6 at
/// left 9 / top 9, rotated 45° about its left edge.
struct SunnyLens: View {
    let size: CGFloat
    let stroke: CGFloat
    let colour: Color
    var body: some View {
        let ring = size * (11.0 / 14.0)
        ZStack(alignment: .topLeading) {
            Circle()
                .strokeBorder(colour, lineWidth: stroke)
                .frame(width: ring, height: ring)
            Rectangle()
                .fill(colour)
                .frame(width: size * (6.0 / 14.0), height: stroke)
                .cornerRadius(S.rule)
                .rotationEffect(.degrees(45), anchor: .leading)
                .offset(x: size * (9.0 / 14.0), y: size * (9.0 / 14.0))
        }
        .frame(width: size, height: size, alignment: .topLeading)
    }
}

// MARK: - row 4 · search drawer, 0 → 56pt

struct SunnySearchDrawer: View {
    @Binding var query: String
    @Binding var open: Bool
    @FocusState private var focused: Bool

    var body: some View {
        // The inner row is ALWAYS 56 tall so nothing reflows mid-animation;
        // only the outer height moves.
        HStack(spacing: S.gap6) {
            HStack(spacing: S.gap4) {
                SunnyLens(size: 13, stroke: 1.5, colour: S.faint)
                TextField("", text: $query, prompt:
                    Text("Search widgets, tickers, events").foregroundStyle(S.faint))
                    .font(InkFont.display(S.t14, S.wMid))
                    .tracking(S.track(S.t14, -0.005))
                    .foregroundStyle(S.ink)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .submitLabel(.search)
                Button { query = "" } label: {
                    ZStack {
                        Circle().fill(S.hair).frame(width: 17, height: 17)
                        ForEach([45.0, -45.0], id: \.self) { a in
                            Rectangle().fill(S.paper)
                                .frame(width: 7, height: 1.4)
                                .rotationEffect(.degrees(a))
                        }
                    }
                }
                .buttonStyle(.plain)
                .opacity(query.isEmpty ? 0 : 1)
                .allowsHitTesting(!query.isEmpty)
                .animation(.easeInOut(duration: 0.15), value: query.isEmpty)
            }
            .frame(height: 38)
            Button {
                query = ""                                   // Cancel closes AND clears
                withAnimation(.easeInOut(duration: S.durDrawer)) { open = false }
            } label: {
                Text("Cancel")
                    .font(InkFont.display(S.t14, S.wSemi))
                    .foregroundStyle(S.ink3)
                    .frame(height: 38)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, S.margin)
        .frame(height: S.searchH)
        .frame(maxWidth: .infinity)
        .background(S.paper)
        .frame(height: open ? S.searchH : 0)                 // outer height animates
        .clipped()
        .onChange(of: open) { _, v in focused = v }          // opening focuses the input
    }
}
