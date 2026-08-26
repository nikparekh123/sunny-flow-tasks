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
            SunnyStrip(book: nav.book, pending: nav.pending, due: nav.due, page: $page)
        }
        .background(S.ground)
        .onAppear { if let p = Self.argPage { page = p } }
        .preferredColorScheme(.light)      // the token set is a light system
    }
}
