//
//  SunnyShell.swift
//  Sunny — the phone, assembled. SHELL-PAGED.md is normative.
//
//  Rows, top to bottom, and their sum is the acceptance test:
//
//      54  status bar     the OS's here — a real app inherits it
//     665  pane           the only flexible row
//     117  strip          the whole navigation, DOCKED AT THE BOTTOM
//      24  home indicator the OS's
//     ---
//     860
//
//  ⚠ THE FILTER STRIP, THE SEARCH FIELD, FEATURED / MISC AND THE BOTTOM RAIL ARE
//  ALL RETIRED (26 Aug 2026). SHELL.md is history and SunnyChrome.swift is
//  deleted. Do not rebuild any part of either from that file or a screenshot.
//
//  ⚠ AND THE RAIL WENT WITH THEM, WHICH REVERSES AN EARLIER INSTRUCTION. Nik's
//  line on the previous shell was "the text rail at the bottom will stay as is",
//  and it did. SHELL-PAGED.md §9 drops it: two navigations for one app, and the
//  strip already names every destination. RailStore stays — it is where the book
//  comes from — but nothing renders SunnyRail any more. If the facts are wanted
//  back they need a home in the new shell, not the old dock.
//
//  ⚠ THE STRIP IS THE WHOLE NAVIGATION. Tapping a circle REPLACES the pane; it
//  does not scroll to a section. A card exists in exactly one place at a time.
//
//  ⚠ AND IT SITS AT THE BOTTOM (26 Aug 2026), as a flex sibling AFTER the pane
//  rather than an absolute overlay. It is the only control on screen and the one
//  pressed most; at the top of a 393 × 860 phone it was outside thumb reach. The
//  circles went 44 → 60 in the same change — --hit-min is a floor, not a target.
//

import SwiftUI

struct SunnyShell: View {
    @State private var page: SunnyPage = .new
    /// Pushed up from the pane, which owns the stores and is therefore the only
    /// thing that knows the book, what is unread and how much is due.
    @State private var nav = SunnyNav()

    /// Deterministic states for verification, so a screenshot of "the TLT page"
    /// does not depend on a simulated tap landing on the right pixel.
    ///   -page TLT       open that name's page instead of New
    ///   -scrollTo 900   start the pane at that offset
    private static var argPage: SunnyPage? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-page"), i + 1 < a.count else { return nil }
        let k = a[i + 1].uppercased()
        return k == "NEW" ? .new : .name(k)
    }
    /// ⚠ VERIFICATION ONLY, AND IT CALLS `step` ITSELF rather than a copy of it.
    /// The touch bridge is dead, so a swipe cannot be driven; this drives the
    /// thing the swipe calls. What it does NOT prove is the gesture recogniser —
    /// that the drag survives the pane's vertical scroller and clears the
    /// dominance test. Only a finger proves that.
    ///   -swipe 2   step forward twice after the nav loads
    ///   -swipe -1  step back once
    private static var argSwipe: Int? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-swipe"), i + 1 < a.count else { return nil }
        return Int(a[i + 1])
    }
    private static var argScroll: CGFloat? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-scrollTo"), i + 1 < a.count,
              let v = Double(a[i + 1]) else { return nil }
        return CGFloat(v)
    }

    var body: some View {
        VStack(spacing: 0) {
            SunnyPane(page: $page, onNav: { nav = $0 }, startAt: Self.argScroll)
                .frame(maxHeight: .infinity)
                /* ⚠ SIMULTANEOUS, AND HORIZONTAL-DOMINANT ONLY. The pane is a
                   vertical scroller; an exclusive gesture would swallow its
                   scrolling, and one without the dominance test fires on the
                   diagonal drift at the start of every flick. `minimumDistance`
                   alone is not enough — a vertical flick clears 20 in both axes
                   long before it clears the ratio.

                   ⚠ AND IT MOVES THE PAGE, NOT A CAROUSEL. The pages are not
                   laid out side by side and never will be: SHELL-PAGED §0 rule
                   1 is that a page REPLACES the pane, and a rubber-banding
                   filmstrip would make the strip's circles look like an index
                   into one long scroll again. */
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { g in
                            let dx = g.translation.width, dy = g.translation.height
                            guard abs(dx) > 60, abs(dx) > abs(dy) * 1.6 else { return }
                            step(dx < 0 ? 1 : -1)
                        })
            SunnyStrip(nav: nav, page: $page)
                .overlay(alignment: .top) {
                    if Self.argSwipe != nil {
                        Text("PAGE \(page.key)").font(.system(size: 9)).opacity(0.001)
                    }
                }
        }
        .background(S.ground)
        .onAppear { if let p = Self.argPage { page = p } }
        .onChange(of: nav.pages.count) { _, n in
            guard let by = Self.argSwipe, n > 1 else { return }
            for _ in 0 ..< abs(by) { step(by > 0 ? 1 : -1) }
            print("SWIPE \(by) -> \(page.key)   order " + nav.pages.map(\.key).joined(separator: ","))
        }
        .preferredColorScheme(.light)      // the token set is a light system
    }

    /* ⚠ IT WALKS `nav.pages`, WHICH IS THE STRIP'S OWN ORDER — New, then the
       flagged names, then the rest. Swiping from New lands on the first circle
       after it, which is what the strip is showing.

       ⚠ AND IT STOPS AT BOTH ENDS RATHER THAN WRAPPING. Wrapping puts New one
       swipe left of the last name, so a swipe past the end silently teleports
       across the whole strip; a page that does not move says *that was the end*
       without having to be told. */
    private func step(_ by: Int) {
        let ps = nav.pages
        guard let i = ps.firstIndex(of: page) else { return }
        let j = i + by
        guard ps.indices.contains(j) else { return }
        withAnimation(S.easeSettle(S.durRevealTransform)) { page = ps[j] }
    }
}
