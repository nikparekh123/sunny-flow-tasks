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
    @State private var showPercent = true

    /// Deterministic states for verification, so a screenshot of "filtered to
    /// TLT" does not depend on a simulated tap landing on the right pixel.
    ///   -filter tlt      preselect a filter
    ///   -scrollTo 900    start the pane at that offset
    private static var argFilter: SunnyTag? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-filter"), i + 1 < a.count else { return nil }
        return SunnyTag(rawValue: a[i + 1].lowercased())
    }
    private static var argScroll: CGFloat? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-scrollTo"), i + 1 < a.count,
              let v = Double(a[i + 1]) else { return nil }
        return CGFloat(v)
    }

    /// Placeholder quotes. The cards and their data land later; the shell is
    /// what this turn builds.
    private let quotes = [
        SunnyQuote(symbol: "SPY", percent: "+0.42%", last: "612.18", up: true),
        SunnyQuote(symbol: "QQQ", percent: "+0.61%", last: "544.03", up: true),
        SunnyQuote(symbol: "IWM", percent: "\u{2212}0.18%", last: "231.77", up: false),
    ]

    /// CHROME.md §3: narrowed = a filter is selected OR the query is non-empty.
    private var narrowed: Bool { !filters.isEmpty || !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            SunnyTicker(state: .closed, quotes: quotes, showPercent: $showPercent).measure("row2-ticker")
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
