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

/* ⚠ ROW 2 IS GONE. `SunnyTicker` lived here: a market-state dot and the
   SPY/QQQ/IWM cluster with tap-to-swap between percent and last price.
   Handoff 10 deleted the whole strip, and cards/text-rail.md §4 carries the
   reasoning so it is not relitigated: the open/closed dot repeats the clock,
   and those three indices are not positions Nik holds. Neither half was
   relocated — if either returns it returns as a FACT in the bottom rail, in
   that spec's language, spending that spec's width budget.

   Gone with it: SunnyQuote's use here, the percent/price toggle, and the swap
   animation. Fixed rows dropped 168 -> 134 and the pane grew 684 -> 718. */

// MARK: - row 2 · filter strip, 44pt, always on screen

/* ⚠ THE ZONE BAR IS GONE. `SunnyZoneBar` lived here: Now — New — Next at 22/600
   with an em-dash separator, a --dim narrowed state, and tap-to-jump. SHELL.md
   deletes the whole row. Three zones sorted by recency could not answer the one
   question the feed is asked — "where is my TLT card" — because the answer
   changed with the news. Featured plus a section per name always can.

   Gone with it: SunnyZone's jump target, `activeZone` tracking, the --zone-line
   scroll maths, and the narrowed state that dimmed all three labels while a
   filter was on. Do not re-add any of it from memory.

   What replaced it is this strip, and it is NOT the old filter row moved up:
   SHELL.md §4 puts the search icon FIRST, on the left, on Nik's instruction,
   and the strip NEVER HIDES. An earlier build collapsed it on scroll-down
   behind a 12px deadband; that came out. Filters are the way out of a long
   feed, so they must never be somewhere you scroll back up to find. */

struct SunnyFilterStrip: View {
    let tags: [SunnyTag]
    @Binding var selected: Set<SunnyTag>
    @Binding var searchOpen: Bool
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: S.stripGap) {
            SunnySearchButton(active: $searchOpen)
                .padding(.leading, S.searchLead)

            ScrollView(.horizontal) {
                HStack(spacing: S.pillGap) {
                    ForEach(tags) { tag in
                        SunnyFilterLabel(text: tag.label, on: selected.contains(tag),
                                         colourOn: S.ink, colourOff: S.mute) {
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
            .mask {
                /* ⚠ THE FADE IS A FIXED TRAILING BAND, NOT A PERCENTAGE.
                   It used to be a LinearGradient whose stops were computed as a
                   fraction of --content (361) — but the thing it masks is the
                   pill scroller, which is ~319pt on a 402pt phone, not 361. The
                   fade therefore began at 80% of the WRONG width and started
                   dissolving about 40pt earlier than it should, which is why CEG
                   read as clipped while actually fitting with room to spare.

                   An HStack of [opaque, flexible] + [gradient, exactly 72] is
                   exact at any port width and cannot drift again. */
                HStack(spacing: 0) {
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: S.railFadeW)
                }
            }

            /* ⚠ CLEAR TAKES NO WIDTH UNTIL IT EXISTS. SHELL.md §4 hides it with
               `opacity: 0` and `pointer-events: none`, which in CSS flex still
               RESERVES its box — and that box plus its 16pt gap is ~51pt of the
               row, held permanently for a control that is invisible most of the
               time. On a 402pt screen that was the difference between six
               tickers fitting and CEG dissolving into the fade at the frame
               edge, which reads as a rendering fault rather than as "there is
               more this way".

               So it is absent, not transparent. The row reflows once, when the
               first filter is selected — and at that moment the strip is
               already changing, so the move reads as part of the same event. */
            if !selected.isEmpty {
                SunnyFilterLabel(text: "Clear", on: false,
                                 colourOn: S.faint, colourOff: S.faint, weight: S.wSemi) {
                    selected.removeAll(); onChange()      // resets filters only, not the query
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, S.margin)
        .frame(height: S.filterrowH)
        .frame(maxWidth: .infinity)
        .background(S.ground)
        .animation(.easeInOut(duration: S.transition), value: selected.isEmpty)
        .measure("row2-filterstrip")
    }
}

/// 44 × 44 tap box holding a 30pt disc.
struct SunnySearchButton: View {
    @Binding var active: Bool
    var body: some View {
        Button { withAnimation(.easeInOut(duration: S.durDrawer)) { active.toggle() } } label: {
            ZStack {
                Circle()
                    .fill(active ? S.ink : S.wash)
                    .frame(width: S.searchDisc, height: S.searchDisc)
                SunnyLens(size: 14, stroke: 1.6, colour: active ? S.onInk : S.mute2)
            }
            .frame(width: S.hitMin, height: S.hitMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
