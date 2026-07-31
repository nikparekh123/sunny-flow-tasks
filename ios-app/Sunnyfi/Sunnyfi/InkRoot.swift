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
    @State private var tab = 0
    @State private var sym = "Nvidia"
    @State private var scrollY: CGFloat = 0
    @State private var showPlanner = false
    private let symbols = ["Nvidia", "Google", "Tesla"]

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

    /// "Plan the next sale" — the entry card into the full-screen Planner.
    private var plannerOpen: some View {
        Button { showPlanner = true } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Plan the next sale").font(InkFont.serif(17)).tracking(17 * -0.01).foregroundStyle(Ink.text)
                    Text("NVDA · NEXT SHORT CALL · GATE → STRIKE → COMMIT")
                        .font(InkFont.mono(8.5)).tracking(8.5 * 0.12).foregroundStyle(Ink.dim)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .regular)).foregroundStyle(Ink.dim)
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            .background(RoundedRectangle(cornerRadius: Ink.radiusCard).fill(Ink.surface))
            .overlay(alignment: .leading) { Rectangle().fill(Ink.text).frame(width: 2) }
            .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard).strokeBorder(Ink.hair, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Ink.radiusCard))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case 0:
            if sym == "Nvidia" {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0)
                            .background(GeometryReader { g in
                                Color.clear.preference(key: InkScrollOffsetKey.self,
                                                       value: g.frame(in: .named("inkScroll")).minY)
                            })
                        NvdaPositionScreen(store: store)
                        plannerOpen.padding(.top, 4).padding(.bottom, 8)
                        NvdaPerformanceScreen(store: store)
                        NvdaInsightsScreen(store: store)
                        NvdaPeersScreen(store: store)
                        NvdaHistoryScreen(store: store)
                        Color.clear.frame(height: 104)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .coordinateSpace(name: "inkScroll")
                .onPreferenceChange(InkScrollOffsetKey.self) { scrollY = $0 }
                .frame(maxWidth: .infinity)
            } else {
                quiet("No position", "Nothing held or written in \(sym) — watchlist only.")
            }
        case 1:
            NvdaEventsScreen()
        default:
            NvdaProfileScreen(auth: auth, lock: lock, prefs: prefs)
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
