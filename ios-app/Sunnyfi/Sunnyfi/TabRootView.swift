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
    case home, trades, performance

    var label: String {
        switch self {
        case .home:        return "Home"
        case .trades:      return "Trades"
        case .performance: return "Performance"
        }
    }

    var symbol: String {
        switch self {
        case .home:        return "house.fill"
        case .trades:      return "chart.line.uptrend.xyaxis"
        case .performance: return "chart.bar.fill"
        }
    }
}

struct TabRootView: View {
    let auth: AuthStore
    @State private var store = PortfolioStore()
    @State private var tab: AppTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            // Active tab content fills the screen; bottom padding leaves
            // room for the floating nav.
            Group {
                switch tab {
                case .home:        HomeScreen(store: store, auth: auth)
                case .trades:      StubScreen(title: "Trades")
                case .performance: StubScreen(title: "Performance")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.theme.page.ignoresSafeArea())

            LiquidGlassTabBar(active: $tab)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
        .task { await store.load() }
    }
}

// MARK: - Floating tab bar

private struct LiquidGlassTabBar: View {
    @Binding var active: AppTab
    @Namespace private var pillNS

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { t in
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                        active = t
                    }
                } label: {
                    tabButton(for: t)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(height: 64)
        .glassEffect(.regular.tint(Color.theme.page2.opacity(0.4)), in: .capsule)
    }

    @ViewBuilder
    private func tabButton(for t: AppTab) -> some View {
        let isActive = active == t
        ZStack {
            if isActive {
                Capsule()
                    .fill(Color.theme.tintNeon)
                    .overlay(
                        Capsule().strokeBorder(Color.theme.neon.opacity(0.28), lineWidth: 1)
                    )
                    .matchedGeometryEffect(id: "activePill", in: pillNS)
            }
            VStack(spacing: 4) {
                Image(systemName: t.symbol)
                    .font(.system(size: 18, weight: .semibold))
                Text(t.label)
                    .font(.ui(size: 10, weight: .semibold))
            }
            .foregroundStyle(isActive ? Color.theme.neon : Color.theme.fg3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
