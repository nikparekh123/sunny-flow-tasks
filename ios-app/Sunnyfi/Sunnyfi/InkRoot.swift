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
            InkTabBar(selection: $tab).padding(.bottom, 6)
        }
        .task { await store.poll(seconds: 60) }
        .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)   // Auto=system, or the Profile override
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case 0:
            if sym == "Nvidia" {
                ScrollView {
                    VStack(spacing: 6) {
                        NvdaPositionScreen(store: store)
                        sectionRule
                        NvdaPerformanceScreen(store: store)
                        sectionRule
                        NvdaInsightsScreen(store: store)
                        sectionRule
                        NvdaPeersScreen(store: store)
                        sectionRule
                        NvdaHistoryScreen(store: store)
                        Color.clear.frame(height: 120)   // clear the floating tab bar
                    }
                }
            } else {
                quiet("No position", "Nothing held or written in \(sym) — watchlist only.")
            }
        case 1:
            NvdaEventsScreen(store: store)
        default:
            NvdaProfileScreen(auth: auth, lock: lock, prefs: prefs)
        }
    }

    private var sectionRule: some View {
        Rectangle().fill(Ink.hair).frame(height: 1).padding(.horizontal, 16).padding(.vertical, 10)
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
