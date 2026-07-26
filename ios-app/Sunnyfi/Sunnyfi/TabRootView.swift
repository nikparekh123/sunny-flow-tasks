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
    // Handoff 6 — the app is a 4-tab NVDA command center. Trades and
    // Hedge were dropped from navigation (screens kept on disk for a
    // future re-add). Order here IS the tab-bar order: Today · Covered
    // Call · Perf · You.
    case home, coveredCall, performance, account

    var label: String {
        switch self {
        // Home tab is the "Today" landing — ranked digest of the
        // N things that matter today. See design_handoff_today_homepage.
        case .home:        return "Today"
        // Wheel-style cycle monitoring. The primary positions surface.
        case .coveredCall: return "Covered Call"
        case .performance: return "Perf"
        case .account:     return "You"
        }
    }

    /// SF Symbol. Outline (non-`.fill`) variants to match the handoff's
    /// stroked tab icons; the active tab renders white on a neon circle.
    var symbol: String {
        switch self {
        case .home:        return "sun.max"
        // The wheel: buy → sell call → assigned → repeat.
        case .coveredCall: return "arrow.triangle.2.circlepath"
        case .performance: return "chart.bar"
        case .account:     return "person"
        }
    }
}

struct TabRootView: View {
    let auth: AuthStore
    let lock: AppLock
    let prefs: NotificationPrefs
    @State private var store = PortfolioStore()
    @State private var reach = Reachability()
    /// Drives the floating tab bar's scroll-shrink. Screens feed their
    /// scroll offset in via the `\.navBarChrome` environment.
    @State private var navChrome = NavBarChrome()
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

                OfflineBanner(isOnline: reach.isOnline, lastFreshness: store.freshness)
                Group {
                    switch tab {
                    // Single-ticker NVDA command center (was the generic
                    // multi-ticker TodayScreen digest, kept for reference).
                    case .home:        NVDAHomeScreen(store: store)
                    case .coveredCall: CoveredCallScreen(store: store)
                    case .performance: PerformanceScreen(store: store, auth: auth)
                    case .account:     AccountScreen(auth: auth, lock: lock, prefs: prefs, store: store)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Screens report their scroll offset here so the floating
                // tab bar can shrink to its `.mini` state while scrolling.
                .environment(\.navBarChrome, navChrome)
            }
            .background(Color.theme.page.ignoresSafeArea())

            // Floating glass tab bar (handoff 6) — a translucent pill
            // that hovers above the bottom, icon-only, active tab a
            // neon-filled circle. Shrinks to `.mini` while scrolling.
            FloatingTabBar(active: $tab, minimized: navChrome.minimized)
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
        // Full-data auto-refresh — re-pulls trades / positions / prices
        // every 2 min while the app is foregrounded. Replaces the
        // pull-to-refresh we removed: with no manual trigger, this is
        // the ONLY way new trades (synced to the DB every ~15 min by
        // IBKR) reach the open app. `.task` pauses automatically when
        // the app backgrounds and resumes on foreground, so it doesn't
        // burn network while unused. fetchAll (not load) so it bypasses
        // the cold-launch fresh-skip and always pulls.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { break }
                await store.fetchAll()
            }
        }
        // IV-summary background poll — runs on a 5-min cadence.
        // The source view (ticker_iv_summary) only changes when
        // ticker-iv-snapshot runs (once daily 20:15 UTC, or manual).
        // 5 min picks up off-schedule manual triggers cheaply.
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


// MARK: - Floating glass tab bar (handoff 6)

/// A translucent liquid-glass pill that floats above the bottom safe
/// area, hugging its four icon-only tabs. The active tab is a
/// neon-filled circle with a white icon; inactive tabs are `fg3`
/// strokes. Shrinks to a `.mini` state (scale .85, nudged down, faded)
/// while the active screen scrolls, then springs back — see
/// `NavBarChrome`.
private struct FloatingTabBar: View {
    @Binding var active: AppTab
    var minimized: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { t in
                Button {
                    withAnimation(Motion.overshoot) { active = t }
                } label: {
                    Image(systemName: t.symbol)
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(active == t ? .white : Color.theme.fg3)
                        .frame(width: 44, height: 44)
                        .background {
                            if active == t {
                                Circle().fill(Color.theme.neon)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(t.label)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // iOS 26 liquid glass, clipped to a pill.
        .glassEffect(.regular, in: .capsule)
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 1))
        .shadow(color: Color(hex: 0x18281e).opacity(0.14), radius: 12, x: 0, y: 8)
        // `.mini` while scrolling.
        .scaleEffect(minimized ? 0.85 : 1, anchor: .bottom)
        .offset(y: minimized ? 6 : 0)
        .opacity(minimized ? 0.8 : 1)
        .animation(Motion.standard, value: minimized)
        .padding(.bottom, 18)
    }
}

// MARK: - Scroll-shrink plumbing

/// Shared chrome state the floating tab bar reads. A screen's root
/// ScrollView reports its vertical offset via `.reportsNavScroll`; the
/// bar minimizes past a small threshold and auto-restores ~0.65s after
/// scrolling stops (mirrors the handoff's scrollTop>10 + 650ms tail).
@MainActor
@Observable
final class NavBarChrome {
    var minimized = false
    @ObservationIgnored private var resetTask: Task<Void, Never>?

    func report(offset: CGFloat) {
        minimized = offset > 10
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.minimized = false
        }
    }
}

extension EnvironmentValues {
    @Entry var navBarChrome: NavBarChrome? = nil
}

extension View {
    /// Attach to a screen's root ScrollView so it drives the floating
    /// tab bar's scroll-shrink. No-op if the environment chrome is absent.
    func reportsNavScroll(_ chrome: NavBarChrome?) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
            chrome?.report(offset: y)
        }
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
