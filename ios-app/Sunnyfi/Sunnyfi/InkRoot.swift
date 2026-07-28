//
//  InkRoot.swift
//  Sunnyfi — Ink rebuild · app shell
//
//  Ticker nav + three tabs (portfolio / events / profile) + floating tab bar,
//  on the Ink canvas. NVDA renders the real position; other tickers get an
//  honest quiet state. Sections 2–5, events, planner and profile fill in next.
//

import SwiftUI

struct InkRoot: View {
    let auth: AuthStore
    let lock: AppLock
    let prefs: NotificationPrefs

    @State private var store = NvdaStore()
    @State private var tab = 0
    @State private var sym = "Nvidia"
    private let symbols = ["Nvidia", "Google", "Tesla"]

    var body: some View {
        ZStack(alignment: .bottom) {
            Ink.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                InkTickerNav(symbols: symbols, selected: $sym)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity)   // clamp to screen so a wide rail can't shift the shell left
            InkTabBar(selection: $tab).padding(.bottom, 6)
        }
        .task { await store.poll(seconds: 60) }
        .preferredColorScheme(nil)   // follow system (design device defaults dark; no Profile override yet)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case 0:
            if sym == "Nvidia" {
                // One vertical scroll of the five sections — the design has NO
                // dividers between them; each section's head (26px top) is the gap.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        NvdaPositionScreen(store: store)
                        NvdaPerformanceScreen(store: store)
                        NvdaInsightsScreen(store: store)
                        NvdaPeersScreen(store: store)
                        NvdaHistoryScreen(store: store)
                        Color.clear.frame(height: 104)   // design tailpad, clears the floating tab bar
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
            } else {
                quiet("No position", "Nothing held or written in \(sym) — watchlist only.")
            }
        case 1:
            NvdaEventsScreen()
        default:
            NvdaProfileScreen()
        }
    }

    private func quiet(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(InkFont.mono(10)).tracking(10 * 0.16).foregroundStyle(Ink.dim)
            Text(body).font(InkFont.display(13, .light)).foregroundStyle(Ink.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16).padding(.top, 120)
    }
}
