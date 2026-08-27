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

// MARK: - what a ring is saying

/// ⚠ THE RING IS THE EVENT CHANNEL AND NOTHING ELSE. Active is not here: it left
/// the ring for the interior, which is what freed the ring to carry two events
/// at once without a precedence rule.
enum SunnyEvent {
    case none
    /// A card is waiting to be read. Amber, because on the awareness card
    /// `--warn` already means *changed since you last read* — the card layer and
    /// the strip finally say the same thing in the same colour. Blue was only
    /// ever chosen as "not red".
    case unread
    /// A short leg is in the money: something could be assigned. Violet, because
    /// GREEN AND RED CANNOT MEAN IT — an assignment is neither a gain nor a loss,
    /// and violet carries no P&L meaning anywhere in the deck.
    case assign
    case both

    var live: Bool { if case .none = self { return false }; return true }
}

// MARK: - one column

/// ⚠ THE RING IS A BACKGROUND UNDER A COVER DISC, not an inset stroke. A conic
/// gradient cannot be a stroke, and the rotating case has to use the same
/// construction as the static ones or the two read as different objects. The
/// cover's inset IS the ring thickness: 1 at rest, 1.5 for every event.
private struct SunnyCircle: View {
    let caption: String
    let active: Bool
    let event: SunnyEvent
    /// `New` is not a name, so it is not a circle. Shape says *different kind of
    /// destination* before colour does, which is what retired the divider.
    var square = false
    let tap: () -> Void
    @ViewBuilder let glyph: (Bool) -> AnyView

    @State private var spin = false

    private var inset: CGFloat { event.live ? S.ringEvent : S.ringRest }

    private var shape: AnyShape {
        square ? AnyShape(RoundedRectangle(cornerRadius: S.radiusNew, style: .continuous))
               : AnyShape(Circle())
    }

    @ViewBuilder private var ring: some View {
        switch event {
        case .none:   shape.fill(S.shellHair)
        case .unread: shape.fill(S.warn).sunnyShadow(S.glowEventAmber)
        case .assign: shape.fill(S.assign).sunnyShadow(S.glowEventAssign)
        case .both:
            /* Two events, one ring, and the motion is the second reading. The
               glow takes the violet: it is the rarer and the more consequential
               of the two, and a two-hue glow is a smudge. */
            shape.fill(AngularGradient(
                stops: [.init(color: S.warn, location: 0), .init(color: S.warn, location: 0.5),
                        .init(color: S.assign, location: 0.5), .init(color: S.assign, location: 1)],
                center: .center))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: S.spinRing).repeatForever(autoreverses: false),
                           value: spin)
                .sunnyShadow(S.glowEventAssign)
                .onAppear { spin = true }
        }
    }

    var body: some View {
        VStack(spacing: S.shellCircleGap) {
            ZStack {
                ring
                /* ⚠ THE INTERIOR IS WHERE YOU ARE, and it is the only filled
                   object the strip can hold. SHELL-PAGED §9 rejected a solid
                   black `New` disc for exactly that weight; this is tolerable
                   only because EXACTLY ONE COLUMN IS EVER FILLED and it moves
                   with you. If a second filled state is ever proposed, this one
                   goes back on the table. */
                shape.fill(active ? S.ink : S.ground).padding(inset)
                glyph(active)
            }
            .frame(width: S.shellCircle, height: S.shellCircle)
            Text(caption)
                .font(S.inter(S.tShellCaption, S.wSemiN))
                .tracking(S.track(S.tShellCaption, -0.01))
                .foregroundStyle(active ? S.ink : S.shellCountClear)
                .monospacedDigit()
                .lineLimit(1)
                .sunnyLineBox(S.tShellCaption * 1.25)
        }
        .frame(width: S.shellCircle)
        /* The column must measure 85 (60 + 10 + 15): 116 − 18 − 13 = 85 exactly,
           and anything taller clips against the scroller rather than scrolling,
           because a horizontal scroller has no vertical axis to give. */
        .measure("strip-col")
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .animation(.easeInOut(duration: S.durRing), value: active)
    }
}

// MARK: - the strip, 88pt

struct SunnyStrip: View {
    /* ⚠ THE WHOLE NAV, NOT ITS PIECES. The order the strip runs in is the order
       the swipe walks, so both read one value. Passing book/flagged separately
       let the two derive it twice, which is how they would come to disagree —
       and the strip is the whole navigation, so nothing may disagree with it. */
    let nav: SunnyNav
    private var pending: Set<String> { nav.pending }
    private var flagged: Set<String> { nav.flagged }
    private var due: Int { nav.due }
    @Binding var page: SunnyPage
    /// Which way the pane should slide. A tap two circles to the right slides
    /// the same way a swipe would, so the strip and the swipe never disagree
    /// about which direction the book runs in.
    @Binding var dir: Int

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
                /* ⚠ `New` SPEAKS FOR THE READING QUEUE ONLY. It wears the same
                   amber a name wears for unread, because it is the same fact
                   counted differently: cards are waiting. It NEVER wears violet —
                   assignment is a property of a name, and a count of flagged
                   names behind the strip would be a summary of a summary. */
                SunnyCircle(caption: "New",
                            active: page == .new,
                            event: due > 0 ? .unread : .none,
                            square: true,
                            tap: { go(.new) }) { on in
                    AnyView(
                        Text("\(due)")
                            .font(S.inter(S.tShellCount, S.wBoldN))
                            .tracking(S.track(S.tShellCount, -0.03))
                            .foregroundStyle(on ? S.onInk
                                               : due > 0 ? S.ink : S.shellCountClear)
                            .monospacedDigit()
                    )
                }

                ForEach(nav.ordered) { b in
                    SunnyCircle(caption: "\(b.weight)%",
                                active: page == .name(b.ticker),
                                event: event(b.ticker),
                                tap: { go(.name(b.ticker)) }) { on in
                        AnyView(
                            Text(b.ticker)
                                .font(S.inter(S.tShellTicker, S.wBoldN))
                                .tracking(S.track(S.tShellTicker, 0.01))
                                .foregroundStyle(on ? S.onInk : S.mute)
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

    private func event(_ t: String) -> SunnyEvent {
        switch (pending.contains(t), flagged.contains(t)) {
        case (true, true):   return .both
        case (true, false):  return .unread
        case (false, true):  return .assign
        default:             return .none
        }
    }

    private func go(_ p: SunnyPage) {
        guard p != page else { return }
        let ps = nav.pages
        if let a = ps.firstIndex(of: page), let b = ps.firstIndex(of: p) {
            dir = b > a ? 1 : -1
        }
        page = p
    }
}
