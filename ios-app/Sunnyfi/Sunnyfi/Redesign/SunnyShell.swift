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
    /// ⚠ THE STORES LIVE HERE NOW, not inside the pane. A pager lays the pages
    /// side by side, so more than one pane exists at once — see PaneModel.
    @State private var model = PaneModel()
    private var nav: SunnyNav { model.nav }
    /* ⚠ THE SCROLLER'S PAGE IS THE SOURCE OF TRUTH, and `page` follows it. A
       paging scroller owns the position while a finger is on it; a second value
       driving it would fight the drag mid-gesture. */
    @State private var scrolled: String?

    /// Deterministic states for verification, so a screenshot of "the TLT page"
    /// does not depend on a simulated drag landing on the right pixel.
    ///   -page TLT     open that name's page instead of New
    ///   -scrollTo 900 start the pane at that offset
    ///   -swipe 2      move two pages forward once the book has loaded
    private static var argPage: SunnyPage? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-page"), i + 1 < a.count else { return nil }
        let k = a[i + 1].uppercased()
        return k == "NEW" ? .new : .name(k)
    }
    private static var argScroll: CGFloat? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-scrollTo"), i + 1 < a.count,
              let v = Double(a[i + 1]) else { return nil }
        return CGFloat(v)
    }
    /// ⚠ VERIFICATION ONLY. The touch bridge is dead, so a real drag cannot be
    /// driven; this moves the page the way a completed swipe would and leaves
    /// the scroller to follow. What it does NOT prove is the paging scroller's
    /// own feel under a finger.
    private static var argSwipe: Int? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-swipe"), i + 1 < a.count else { return nil }
        return Int(a[i + 1])
    }

    var body: some View {
        VStack(spacing: 0) {
            pager.frame(maxHeight: .infinity)
            SunnyStrip(nav: nav, page: $page)
        }
        .background(S.ground)
        .task { await model.loadAll() }
        .onAppear { if let p = Self.argPage { page = p; scrolled = p.key } }
        .preferredColorScheme(.light)      // the token set is a light system
    }

    /* ⚠ THE PAGES ARE LAID OUT SIDE BY SIDE AND THE FINGER MOVES THEM. Nik asked
       three times for the swipe to feel native, and it could not while the pane
       was one view swapping its contents: a transition can only start when the
       finger has already left the glass, so the page never tracked the drag and
       every version of it read as fake however it was eased.

       This is the platform's own paged scroller — it tracks, it rubber-bands at
       both ends, it takes a flick's velocity — and it costs what the pane was
       structured to avoid: more than one pane alive at once. `PaneModel` is the
       answer to that. The stores are shared, so a second pane is view
       construction and not a second fetch, and `LazyHStack` only builds the
       pages either side of the one being looked at.

       ⚠ AND THERE IS NO DRAG GESTURE ANY MORE. The hand-rolled one had to guess
       at a 60pt threshold and a 1.6x dominance ratio to avoid eating the
       vertical scroll. The paging scroller resolves that itself, the way every
       other iOS pager does. */
    private var pager: some View {
        GeometryReader { g in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(nav.pages, id: \.key) { p in
                        SunnyPane(page: p, m: model, startAt: Self.argScroll)
                            .frame(width: g.size.width)
                            .id(p.key)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolled)
            .scrollIndicators(.hidden)
            /* The strip and the pager are two views of one position, so each
               follows the other. `guard` on equality keeps that from looping. */
            .onChange(of: scrolled) { _, k in
                guard let k, k != page.key else { return }
                page = k == SunnyPage.new.key ? .new : .name(k)
            }
            .onChange(of: page) { _, p in
                guard scrolled != p.key else { return }
                withAnimation(S.easeOut(S.durPage)) { scrolled = p.key }
            }
            .onChange(of: nav.pages.count) { _, _ in
                if scrolled == nil { scrolled = page.key }
                guard let by = Self.argSwipe else { return }
                for _ in 0 ..< abs(by) { step(by > 0 ? 1 : -1) }
                print("SWIPE \(by) -> \(page.key)   order " + nav.pages.map(\.key).joined(separator: ","))
            }
        }
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
        page = ps[j]
    }
}
