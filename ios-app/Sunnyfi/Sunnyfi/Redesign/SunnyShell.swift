//
//  SunnyShell.swift
//  Sunny — the phone, assembled. CHROME.md: five fixed rows plus one flexible.
//
//  Rows 1 and 6 come from the operating system; see the note in SunnyChrome.swift.
//

import SwiftUI

struct SunnyShell: View {
    @State private var searchOpen = false
    @State private var query = ""
    @State private var filters: Set<SunnyTag> = []
    @State private var activeZone: SunnyZone = .now
    @State private var jumpTo: SunnyZone?

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

    /* ⚠ NO TICKER STRIP. Handoff 10 DELETED row 2 — the market-state dot and the
       SPY/QQQ/IWM cluster together, not hidden, not relocated. Neither earned
       permanent space: the open/closed dot repeats what the clock already says,
       and those three are not positions Nik holds. The always-on rail replaces
       it and docks at the BOTTOM, in thumb reach, where it never competes with
       the zone bar for the top of the screen.

       Fixed rows are now 54 + 56 + 0 + 24 = 134, and the pane takes 718.
       Do not re-add either half from memory. */

    /// CHROME.md §3: narrowed = a filter is selected OR the query is non-empty.
    private var narrowed: Bool { !filters.isEmpty || !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            SunnyZoneBar(active: activeZone, narrowed: narrowed,
                         onJump: { jumpTo = $0 }, searchOpen: $searchOpen).measure("row3-zonebar")
            SunnySearchDrawer(query: $query, open: $searchOpen)
            SunnyPane(query: $query, filters: $filters, activeZone: $activeZone,
                      jumpTo: jumpTo, onJumpHandled: { jumpTo = nil },
                      startAt: Self.argScroll)
                .frame(maxHeight: .infinity)
        }
        .background(S.ground)
        .onAppear { if let t = Self.argFilter { filters = [t] } }
        .preferredColorScheme(.light)      // the token set is a light system
    }
}
