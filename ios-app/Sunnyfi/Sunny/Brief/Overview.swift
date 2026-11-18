//
//  Overview.swift
//  Sunny
//
//  The Overview page: the account strip on top, then both books together (OverviewTogether, handoff 2026-11-18 §4,
//  round 165a; it replaces the six checks and Coming in). It lies over Home and Positions when the strip lands on it.
//  Every switch on the strip moves the same way (§1.2): the page's content fades up from .15 and slides 28 pt from
//  the side it comes from (.4 s and .5 s); its background stays put. Reduce Motion: the fade only.
//  No em dashes in any words here.
//

import SwiftUI

struct OverviewScreen: View {
    @Environment(BriefState.self) private var brief
    @Environment(\.accessibilityReduceMotion) private var reduce
    @AppStorage(BriefPrivacy.key) private var privacy = false
    @State private var pos = ScrollPosition()
    @State private var faded = true
    @State private var slid = true

    var body: some View {
        content
            // Per-screen loading (18 Nov 2026): the pair of books comes with each update only while Overview is on show.
            .onAppear { HomeStore.need(.together, true) }
            .onDisappear { HomeStore.need(.together, false) }
    }

    private var content: some View {
        ZStack(alignment: .top) {
            SBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AccountStrip(accounts: brief.accounts, selected: brief.account) { a in
                        // The strip animates its own names (S.switchMove); HomeView takes Overview away.
                        brief.pick(a)
                    }
                    Group {
                        if let g = brief.liveTogether {
                            OverviewTogether(t: g, privacy: privacy)
                        } else {
                            ProgressView().controlSize(.regular).frame(maxWidth: .infinity).padding(.top, 80)
                        }
                    }
                    .padding(.horizontal, S.margin)
                    // The page starts 10 under the strip; the strip draws `lift` higher, so the page pulls up by it (as Home).
                    .padding(.top, 10 - AccountStrip.lift)
                    .opacity(faded ? 0.15 : 1)
                    .offset(x: slid && !reduce ? 28 * brief.switchDir : 0)
                }
                .padding(.bottom, 128)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
            .scrollPosition($pos)
            .task {
                // The switch's move, two frames after the first draw (the design's double requestAnimationFrame).
                try? await Task.sleep(for: .milliseconds(34))
                withAnimation(S.switchFade) { faded = false }
                withAnimation(S.moving(S.switchMove, reduce)) { slid = false }
                // DEBUG audits: `-scroll 900` opens Overview scrolled that far, so the page is shot in slices.
                if let y = BriefDebug.scroll { try? await Task.sleep(for: .milliseconds(600)); pos.scrollTo(y: y) }
            }
        }
    }
}
