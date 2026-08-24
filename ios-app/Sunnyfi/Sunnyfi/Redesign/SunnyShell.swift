//
//  SunnyShell.swift
//  Sunny — the phone, assembled. SHELL.md is normative.
//
//  Rows, top to bottom, and their sum is the acceptance test:
//
//      54  status bar        the OS's here — see SunnyChrome.swift
//      44  filter strip      never hides
//       0  search drawer     0 closed, 56 open; it COSTS the pane, never overlays
//     690  pane              the only flexible row
//      48  rail              an overlay, so it takes no row of its own
//      24  home indicator    the OS's
//     ---
//     860
//
//  ⚠ THE ZONE BAR IS GONE, and with it Now / New / Next, the jump targets and
//  the narrowed state that dimmed all three while a filter was on. SHELL.md
//  replaced the whole row with the filter strip, moved the search icon to the
//  LEFT on Nik's instruction, and made the strip permanent.
//
//  ⚠ THE RAIL STAYS AN OVERLAY. SHELL.md §1 puts it in flow and derives a 690
//  pane from that; cards/text-rail.md keeps it absolute inside the pane wrapper.
//  Nik's instruction is that the rail stays as it is, so the overlay wins and
//  the pane clears the dock itself. The two only differ when the dock slides
//  away: in flow that leaves a 48pt white gap where the feed should show.
//

import SwiftUI

struct SunnyShell: View {
    @State private var searchOpen = false
    @State private var query = ""
    @State private var filters: Set<SunnyTag> = []
    /// Derived from the cards the pane actually holds, never declared ahead of
    /// them — a filter that can only return blanks is indistinguishable from a
    /// broken one.
    @State private var tags: [SunnyTag] = []

    /// Deterministic states for verification, so a screenshot of "filtered to
    /// TLT" does not depend on a simulated tap landing on the right pixel.
    ///   -filter tlt      preselect a filter
    ///   -scrollTo 900    start the pane at that offset
    private static var argFilter: SunnyTag? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-filter"), i + 1 < a.count else { return nil }
        return SunnyTag(a[i + 1])
    }
    private static var argScroll: CGFloat? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-scrollTo"), i + 1 < a.count,
              let v = Double(a[i + 1]) else { return nil }
        return CGFloat(v)
    }

    var body: some View {
        VStack(spacing: 0) {
            SunnyFilterStrip(tags: tags, selected: $filters,
                             searchOpen: $searchOpen, onChange: {})
            SunnySearchDrawer(query: $query, open: $searchOpen)
            SunnyPane(query: $query, filters: $filters,
                      onTags: { tags = $0 }, startAt: Self.argScroll)
                .frame(maxHeight: .infinity)
        }
        .background(S.ground)
        .onAppear { if let t = Self.argFilter { filters = [t] } }
        .preferredColorScheme(.light)      // the token set is a light system
    }
}
