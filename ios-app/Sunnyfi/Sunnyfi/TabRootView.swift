//
//  TabRootView.swift
//  Sunnyfi
//
//  Authenticated root. Owns the shared PortfolioStore and renders the
//  three-tab layout (Home + Trades stub + Performance stub) with a
//  custom Liquid-Glass tab bar matching the design handoff. The tab
//  bar floats above the content — the design's defining trait — so
//  each screen pads its bottom for the nav.
//

import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case home, trades, hedge, performance, account

    var label: String {
        switch self {
        // Home tab is now the "Today" landing — ranked digest of the
        // N things that matter today. See design_handoff_today_homepage.
        case .home:        return "Today"
        case .trades:      return "Trades"
        case .hedge:       return "Hedge"
        // 5-tab layout — "Performance" shortens to "Perf" so the
        // labels don't crowd. Per package 4 of the design handoff.
        case .performance: return "Perf"
        case .account:     return "You"
        }
    }

    var symbol: String {
        switch self {
        case .home:        return "sun.max.fill"
        case .trades:      return "chart.line.uptrend.xyaxis"
        // Shield = "protect the book". Hedge tab is the awareness
        // surface — not transactional like Trades.
        case .hedge:       return "shield.lefthalf.filled"
        case .performance: return "chart.bar.fill"
        case .account:     return "person.fill"
        }
    }
}

struct TabRootView: View {
    let auth: AuthStore
    let lock: AppLock
    let prefs: NotificationPrefs
    @State private var store = PortfolioStore()
    @State private var reach = Reachability()
    // Today landing rebuilt per design_handoff_today_homepage — the
    // app now opens to it. Hedge is still rebuilding (hidden in the
    // tab bar) but the Home/Today tab is live.
    @State private var tab: AppTab = .home
    /// Ticker for the top-level TickerTradesSheet — driven by push
    /// deep-link taps (AppNavigator) or any in-app trigger that
    /// wants to surface the per-ticker modal from anywhere.
    @State private var pushTickerSheet: String?
    /// Process singleton — reading its observable properties here
    /// re-runs the body on push intents.
    private let navigator = AppNavigator.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            // Active tab content fills the screen; bottom padding leaves
            // room for the floating nav.
            VStack(spacing: 0) {
                // Passive sync heartbeat — a tiny orange/red dot
                // appears in the top-left ONLY when the IBKR feed
                // is stale or has failed. Fresh = hidden. Not
                // tappable. Replaces the prior orbit SyncIndicator
                // + ephemeral logo header per the stabilization
                // pass (no manual sync entry points).
                HStack(alignment: .center) {
                    StatusDot(store: store)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 6)

                SystemAlertBanner(alerts: store.activeAlerts)
                OfflineBanner(isOnline: reach.isOnline, lastFreshness: store.freshness)
                Group {
                    switch tab {
                    case .home:        TodayScreen(store: store)
                    case .trades:      TradesScreen(store: store, auth: auth)
                    case .hedge:       HedgeScreen(store: store, auth: auth)
                    case .performance: PerformanceScreen(store: store, auth: auth)
                    case .account:     AccountScreen(auth: auth, lock: lock, prefs: prefs, store: store)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.theme.page.ignoresSafeArea())

            // Docked tab bar — full-width, solid surface, top hairline.
            // Replaces the prior floating glass capsule per Handoff 2
            // §9. Sits flush against the bottom safe area; the safe-area
            // inset handles home-indicator clearance automatically.
            DockedTabBar(active: $tab)
        }
        .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)
        .task {
            await store.load()
            // If the user previously granted notification permission,
            // re-trigger registration so we capture any token rotation
            // since last launch. iOS rate-limits this internally, so
            // calling on every cold start is fine.
            await prefs.refreshSystemPermission()
            if prefs.systemPermission == .authorized || prefs.systemPermission == .provisional {
                PushAppDelegate.registrar.requestSystemRegistration()
            }
        }
        // Alert-only background poll — cleared system_alerts disappear
        // from the banner within ~30s without the user having to pull-
        // to-refresh. Lightweight: one query (~50ms), no Polygon, no
        // edge function. Loop owns its lifetime via .task — SwiftUI
        // tears it down automatically when TabRootView unmounts (or
        // when the app backgrounds; .task pauses on .inactive).
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await store.refreshAlertsOnly()
            }
        }
        // IV-summary background poll — same pattern as the alert poll
        // but on a 5-min cadence. The source view (ticker_iv_summary)
        // only changes when ticker-iv-snapshot runs (once daily
        // 20:15 UTC, or manual). 5 min picks up off-schedule manual
        // triggers without burning bandwidth.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { break }
                await store.refreshIvSummariesOnly()
            }
        }
        // ── Push deep-link routing ──
        // When the user taps a notification, AppNavigator.shared fills
        // these fields. We react here so the routing lives in one
        // place rather than each screen.
        .onChange(of: navigator.requestedTab) { _, newTab in
            guard let newTab else { return }
            withAnimation(Motion.overshoot) { tab = newTab }
            navigator.consumeTabRequest()
        }
        .onChange(of: navigator.requestedTickerSheet) { _, newTicker in
            guard let newTicker else { return }
            pushTickerSheet = newTicker
            navigator.consumeTickerRequest()
        }
        .onAppear {
            // If a tap arrived while the app was on sign-in / locked,
            // the navigator already has the intent buffered. Apply it
            // now that TabRootView is mounting.
            if let pendingTab = navigator.requestedTab {
                tab = pendingTab
                navigator.consumeTabRequest()
            }
            if let pendingTicker = navigator.requestedTickerSheet {
                pushTickerSheet = pendingTicker
                navigator.consumeTickerRequest()
            }
        }
        .sheet(item: Binding(
            get: { pushTickerSheet.map(TickerWrapper.init) },
            set: { pushTickerSheet = $0?.ticker }
        )) { wrap in
            TickerTradesSheet(store: store, ticker: wrap.ticker, initialTab: .shares)
        }
    }
}

/// Identifiable wrapper so a String can drive `.sheet(item:)`.
private struct TickerWrapper: Identifiable {
    let ticker: String
    var id: String { ticker }
}


// MARK: - Docked tab bar

/// Full-width, surface-filled, top-hairline tab bar — replaces the
/// floating glass capsule per Handoff 2 §9. No background blur, no
/// rounded corners; sits flush against the bottom safe area. The
/// active tab tints with `--neon`; inactive tabs read in `fg3`.
private struct DockedTabBar: View {
    @Binding var active: AppTab

    /// Tabs we actually render. Hedge is still rebuilding so it's
    /// suppressed (enum case kept for push deep-links). Home is now
    /// the live Today landing tab — visible and default.
    private var visibleTabs: [AppTab] {
        AppTab.allCases.filter { $0 != .hedge }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { t in
                Button {
                    withAnimation(Motion.overshoot) { active = t }
                } label: {
                    tabButton(for: t)
                }
                .buttonStyle(.pressable)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 4)        // safe-area inset handles the rest
        // iOS 26 liquid glass — translucent material that picks up
        // and softly blurs whatever's scrolling behind it, instead of
        // the prior opaque white slab. Matches the SegmentedToggle's
        // glassEffect treatment so the bar feels native to the OS.
        .background {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect)
                .ignoresSafeArea(edges: .bottom)
                .overlay(
                    Color.theme.borderBright.opacity(0.35)
                        .frame(height: 0.5),
                    alignment: .top
                )
        }
    }

    @ViewBuilder
    private func tabButton(for t: AppTab) -> some View {
        let isActive = active == t
        VStack(spacing: 3) {
            Image(systemName: t.symbol)
                .font(.system(size: 22, weight: .medium))
            Text(t.label)
                .font(.ui(size: 10, weight: isActive ? .semibold : .regular))
        }
        .foregroundStyle(isActive ? Color.theme.neon : Color.theme.fg3)
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
    }
}

// MARK: - Stub screens

private struct StubScreen: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.ui(size: 30, weight: .bold))
                .foregroundStyle(Color.theme.fg1)
            Text("Coming in v2 — focused on Home + Company first.")
                .font(.ui(size: 13))
                .foregroundStyle(Color.theme.fg3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
