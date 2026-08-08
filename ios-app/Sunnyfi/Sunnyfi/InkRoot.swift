//
//  InkRoot.swift
//  Sunnyfi — Ink rebuild · app shell
//
//  Ticker nav (portfolio tab only) + three tabs + floating tab bar, on the Ink
//  canvas. NVDA renders the real position; other tickers get an honest quiet
//  state. The tab bar shrinks + fades as the page scrolls.
//

import SwiftUI

private struct InkScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct InkRoot: View {
    let auth: AuthStore
    let lock: AppLock
    let prefs: NotificationPrefs

    @State private var store = NvdaStore()
    @State private var tltStore = TLTBook.store()
    @State private var tab = 0
    @State private var sym = "Nvidia"
    @State private var scrollY: CGFloat = 0
    @State private var showPlanner = false
    private let symbols = ["Nvidia", "TLT"]

    private var scrolled: Bool { scrollY < -24 }

    var body: some View {
        ZStack(alignment: .bottom) {
            Ink.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                if tab == 0 {
                    InkTickerNav(symbols: symbols, selected: $sym)   // only on the portfolio page
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            InkTabBar(selection: $tab, dimmed: scrolled)
                .padding(.bottom, 6)
        }
        .task { await store.poll(seconds: 60) }
        .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)   // Auto=system, or the Profile override
        .fullScreenCover(isPresented: $showPlanner) {
            NvdaPlannerScreen(store: store, onClose: { showPlanner = false })
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case 0:
            switch sym {
            case "Nvidia": portfolioScroll(store, isNvda: true)
            case "TLT":    portfolioScroll(tltStore, isNvda: false)
            default:       quiet("No position", "Nothing held or written in \(sym) — watchlist only.")
            }
        case 1:
            NvdaEventsScreen()
        default:
            NvdaProfileScreen(auth: auth, lock: lock, prefs: prefs)
        }
    }

    // The portfolio scroll — four handoff sections, read from whichever book is
    // selected. TLT rides the same screens on its fixture; NVDA is live and owns
    // the planner entry.
    private func portfolioScroll(_ st: NvdaStore, isNvda: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 0)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: InkScrollOffsetKey.self,
                                               value: g.frame(in: .named("inkScroll")).minY)
                    })
                NvdaPositionScreen(store: st, onPlan: { showPlanner = true }, showPlan: isNvda)
                NvdaInsightsScreen(store: st)
                NvdaPeersScreen(store: st)
                NvdaHistoryScreen(store: st)
                // TLT-only surfaces (hike odds · rates & range · vol & engine ·
                // voter bloc · macro calendar) land in the next commits.
                Color.clear.frame(height: 104)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .coordinateSpace(name: "inkScroll")
        .onPreferenceChange(InkScrollOffsetKey.self) { scrollY = $0 }
        .frame(maxWidth: .infinity)
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
