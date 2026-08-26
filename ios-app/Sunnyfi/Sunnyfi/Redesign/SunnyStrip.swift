//
//  SunnyStrip.swift
//  Sunny — the whole navigation. SHELL-PAGED.md §0-§4 is normative.
//
//  ⚠ THE STRIP IS THE WHOLE NAVIGATION. No filter pills, no search field, no
//  bottom rail, no tabs. One horizontal strip of circles: New first, then one
//  circle per position. Tapping a circle REPLACES the pane contents — it does
//  not scroll to a section. There is nothing else to tap.
//
//  A scroll-to-section strip was built and rejected: with no filter the strip
//  carries the whole "where am I" job, and scrolling makes every page one long
//  page, so the answer is ambiguous again.
//
//  ⚠ IT DOCKS AT THE BOTTOM. It is a flex sibling AFTER the pane, not an
//  absolute overlay, so it takes its own 117 of the frame: 54 + 665 + 117 + 24.
//  At the top of a 393 × 860 phone the only control on screen sat outside thumb
//  reach, and it is the thing pressed most.
//
//  ⚠ TICKERS, NOT LOGOS. Companies have marks and funds have an issuer badge, so
//  a logo strip reads half-finished and depends on artwork arriving. TLT held
//  its ticker while NKE carried a wordmark and the strip looked broken. The
//  circle carries the ticker; the page heading carries the company name.
//

import SwiftUI

/// Which page the pane is showing. There is no third kind — a card either has a
/// clock on it and is on `new`, or it belongs to a name.
enum SunnyPage: Hashable {
    case new
    case name(String)

    var key: String {
        switch self {
        case .new: return "NEW"
        case .name(let t): return t
        }
    }
}

// MARK: - one circle

/// ⚠ ONE RING, AND THE CAPTION. Blue says *this name has something to read*;
/// ink says *this is the page you are on*. There is no halo any more — a
/// ground-coloured spacer plus an outer ring read as a target reticle at 60px.
/// Where a name is both active and unread, the blue wins on the ring and the ink
/// caption still says where you are.
private struct SunnyCircle: View {
    let caption: String
    let active: Bool
    let news: Bool
    let tap: () -> Void
    @ViewBuilder let glyph: () -> AnyView

    private var innerRing: (Color, CGFloat) {
        if news   { return (S.update, S.shellRingLive) }
        if active { return (S.ink,    S.shellRingLive) }
        return (S.shellHair, S.shellRingRest)
    }

    var body: some View {
        VStack(spacing: S.shellCircleGap) {
            ZStack {
                /* ⚠ THE DISC IS FILLED, AND IT HAS TO BE. CSS draws a box-shadow
                   from the border box whether or not the background is painted,
                   so the glow is a full 44pt circular bloom. SwiftUI's .shadow
                   traces the rendered pixels, so a transparent circle casts
                   nothing at all. Filling it with the strip's own ground is
                   invisible and gives the glow something to come off. */
                Circle().fill(S.ground).sunnyShadow(news ? S.shellGlow : [])
                glyph()
            }
            .frame(width: S.shellCircle, height: S.shellCircle)
            /* The inner ring is `inset 0 0 0 Npx` in CSS — drawn INSIDE the
               element's edge, which is exactly what strokeBorder does and what
               stroke does not. */
            .overlay(Circle().strokeBorder(innerRing.0, lineWidth: innerRing.1))
            /* ⚠ NO HALO. It was a ground-coloured spacer plus an outer ink
               ring, and at 60px that read as a target reticle rather than a
               selection. Active is the ink ring above and the ink caption
               below, with nothing orbiting it. */
            Text(caption)
                .font(S.inter(S.tShellCaption, S.wSemiN))
                .tracking(S.track(S.tShellCaption, -0.01))
                .foregroundStyle(active ? S.ink : S.shellCountClear)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(width: S.shellCircle)
        /* The column must measure 85 (60 + 10 + 15): 116 − 18 − 13 = 85 exactly,
           and anything taller clips against the scroller rather than scrolling,
           because a horizontal scroller has no vertical axis to give. */
        .measure("strip-col")
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .animation(.easeInOut(duration: S.durRing), value: active)
        .animation(.easeInOut(duration: S.durRing), value: news)
    }
}

// MARK: - the strip, 88pt

struct SunnyStrip: View {
    let book: [SunnyNav.Name]
    /// Names with a dated card still sitting on New. Blue ring, blue glow.
    let pending: Set<String>
    /// How many dated cards are unread, whatever name they file under.
    let due: Int
    @Binding var page: SunnyPage

    var body: some View {
        /* ⚠ A HAIRLINE, NOT A SHADOW. A shadow says the strip floats over the
           pane; it does not — it is a sibling AFTER the pane and takes its own
           117 of the frame. The rule is full bleed and never compresses. */
        VStack(spacing: 0) {
            Rectangle().fill(S.shellHair)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            scroller
        }
        .frame(height: S.shellStripH)
        .background(S.ground)
        .measure("strip")
    }

    private var scroller: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: S.shellStripGap) {
                SunnyCircle(caption: "New",
                            active: page == .new,
                            news: due > 0,
                            tap: { go(.new) }) {
                    /* ⚠ NOT A SOLID BLACK DISC. A filled circle is the heaviest
                       object the strip can hold and it outweighed the positions
                       the strip exists to show. New uses the SAME vocabulary as
                       the names — empty circle, thin ring, figure in ink — and
                       earns the blue ring only when something is actually due,
                       which is precisely what "new" means. */
                    AnyView(
                        Text("\(due)")
                            .font(S.inter(S.tShellCount, S.wBoldN))
                            .tracking(S.track(S.tShellCount, -0.03))
                            .foregroundStyle(due > 0 ? S.update : S.shellCountClear)
                            .monospacedDigit()
                    )
                }

                /* A rule between New and the positions, lifted so it centres on
                   the circles rather than on the whole column — the captions
                   below are not part of what it separates. */
                Rectangle().fill(S.shellHair)
                    .frame(width: 1, height: S.shellDividerH)
                    .offset(y: (S.shellCircle - S.shellDividerH) / 2)

                ForEach(book) { b in
                    SunnyCircle(caption: "\(b.weight)%",
                                active: page == .name(b.ticker),
                                news: pending.contains(b.ticker),
                                tap: { go(.name(b.ticker)) }) {
                        AnyView(
                            Text(b.ticker)
                                .font(S.inter(S.tShellTicker, S.wBoldN))
                                .tracking(S.track(S.tShellTicker, 0.01))
                                .foregroundStyle(S.mute)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        )
                    }
                }
            }
            .padding(.horizontal, S.margin)
            .padding(.top, S.shellStripPadTop)
            /* ⚠ 13 IS LOAD-BEARING. The circle column measures 85 (60 + 10 + 15)
               and 116 − 18 − 13 = 85 exactly. At 14 the strip scrolled 1px
               vertically, which on a horizontal scroller reads as a jitter. */
            .padding(.bottom, S.shellStripPadBottom)
        }
        .scrollIndicators(.hidden)
        .frame(height: S.shellStripScrollH)
    }

    private func go(_ p: SunnyPage) {
        guard p != page else { return }
        page = p
    }
}
