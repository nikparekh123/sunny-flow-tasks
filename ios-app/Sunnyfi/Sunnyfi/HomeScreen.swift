//
//  HomeScreen.swift
//  Sunnyfi
//
//  Home tab. Layout matches the design handoff (reference/app-screens-1.jsx):
//   - Portfolio value hero in neon + eye toggle
//   - Today's change line
//   - Range bar (1D/1W/1M/…) — visual for now, chart lands later
//   - Tap-to-cycle Net Delta / Greeks metric row
//   - "Your portfolio" section with holdings list (rows tap → Company)
//
//  Swipeable event cards + weekly income strip + news rows come in a
//  later pass — those need data the Supabase tables don't have yet.
//

import SwiftUI

struct HomeScreen: View {
    let store: PortfolioStore
    let auth: AuthStore

    @State private var range: ChartRange = .oneDay
    @State private var maskValue: Bool = false
    @State private var greekIdx: Int = 0     // 0 = Δ, 1 = β·Δ, 2 = Θ, 3 = Γ, 4 = V
    @State private var path: [String] = []  // ticker strings

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ValueHero(
                        store: store,
                        masked: $maskValue
                    )

                    RangeBar(active: $range)

                    Divider().background(Color.theme.hair)

                    NetDeltaRow(
                        portfolio: store.portfolio,
                        greekIdx: $greekIdx
                    )

                    Divider().background(Color.theme.hair)

                    PortfolioSectionHeader(count: store.companies.count)

                    if store.isLoading && store.companies.isEmpty {
                        loadingState
                    } else {
                        VStack(spacing: 0) {
                            ForEach(store.companies) { c in
                                Button {
                                    path.append(c.ticker)
                                } label: {
                                    HoldingRow(company: c)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let err = store.error {
                        Text(err)
                            .font(.ui(size: 12))
                            .foregroundStyle(Color.theme.neg)
                            .padding(.top, 8)
                    }

                    // Bottom space so the floating tab bar doesn't overlap content
                    Color.clear.frame(height: 90)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
            .background(Color.theme.page)
            .refreshable { await store.refresh() }
            .navigationDestination(for: String.self) { ticker in
                CompanyScreen(ticker: ticker, store: store)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Sign out", role: .destructive) {
                            Task { await auth.signOut() }
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(Color.theme.fg2)
                    }
                }
            }
            .toolbarBackground(Color.theme.page, for: .navigationBar)
        }
    }

    private var loadingState: some View {
        HStack {
            Spacer()
            ProgressView().tint(.theme.neon)
            Spacer()
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Portfolio value hero

private struct ValueHero: View {
    let store: PortfolioStore
    @Binding var masked: Bool

    private var totalValue: Double { store.portfolio.mv + store.portfolio.unreal }
    private var todayChange: Double {
        // Sum of (spot - prev_close) × qty for the stock legs — i.e. dollar
        // P&L attributable to today's spot move. Approx for the hero line.
        store.companies.reduce(0.0) { acc, c in
            acc + c.legs.filter { $0.kind == .stock }.reduce(0.0) { a, leg in
                a + (leg.last * (c.dayPct / 100.0)) * leg.qty
            }
        }
    }
    private var todayPct: Double {
        totalValue > 0 ? (todayChange / totalValue) * 100 : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PORTFOLIO VALUE")
                    .font(.microLabel)
                    .tracking(1.4)
                    .foregroundStyle(Color.theme.fg3)
                Spacer()
                Button {
                    masked.toggle()
                } label: {
                    Image(systemName: masked ? "eye.slash" : "eye")
                        .foregroundStyle(Color.theme.fg3)
                        .font(.system(size: 18))
                }
            }

            Group {
                if masked {
                    Text("••••••")
                        .font(.numeric(size: 40, weight: .medium))
                        .tracking(-1.5)
                        .foregroundStyle(Color.theme.neon)
                } else {
                    Text(fmtMoney(totalValue))
                        .font(.numeric(size: 40, weight: .medium))
                        .tracking(-1.5)
                        .foregroundStyle(Color.theme.neon)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: todayChange >= 0 ? "triangle.fill" : "triangle.fill")
                    .font(.system(size: 9))
                    .rotationEffect(.degrees(todayChange >= 0 ? 0 : 180))
                    .foregroundStyle(Color.signed(todayChange))
                Text("\(fmtMoney(todayChange, sign: true)) (\(fmtPct(todayPct)))")
                    .font(.numeric(size: 13))
                    .foregroundStyle(Color.signed(todayChange))
                Text("Today")
                    .font(.ui(size: 12))
                    .foregroundStyle(Color.theme.fg3)
            }
        }
    }
}

// MARK: - Range bar

enum ChartRange: String, CaseIterable, Identifiable {
    case oneDay = "1D", oneWeek = "1W", oneMonth = "1M", threeMonth = "3M"
    case ytd = "YTD", oneYear = "1Y", all = "ALL"
    var id: String { rawValue }
}

private struct RangeBar: View {
    @Binding var active: ChartRange

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ChartRange.allCases) { r in
                let isActive = active == r
                Button {
                    active = r
                } label: {
                    Text(r.rawValue)
                        .font(.numeric(size: 12))
                        .foregroundStyle(isActive ? Color.theme.neon : Color.theme.fg3)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background {
                            if isActive {
                                Capsule()
                                    .fill(Color.theme.tintNeon)
                                    .overlay(Capsule().strokeBorder(Color.theme.neon.opacity(0.22), lineWidth: 1))
                            }
                        }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Net Delta tap-to-cycle row

private struct NetDeltaRow: View {
    let portfolio: PortfolioRollup
    @Binding var greekIdx: Int

    private var entries: [(label: String, value: String)] {
        [
            ("Net Delta",        fmtGreek(portfolio.delta)),
            ("β-weighted Delta", fmtGreek(portfolio.betaWeightedDelta)),
            ("Net Theta",        fmtGreek(portfolio.theta)),
            ("Net Gamma",        fmtGreek(portfolio.gamma)),
            ("Net Vega",         fmtGreek(portfolio.vega)),
        ]
    }

    var body: some View {
        let cur = entries[greekIdx % entries.count]
        Button {
            greekIdx = (greekIdx + 1) % entries.count
        } label: {
            HStack {
                Text(cur.label)
                    .font(.ui(size: 15, weight: .medium))
                    .foregroundStyle(Color.theme.fg2)
                Spacer()
                Text(cur.value)
                    .font(.numeric(size: 15))
                    .foregroundStyle(Color.theme.fg2)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Portfolio section header

private struct PortfolioSectionHeader: View {
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Your portfolio")
                .font(.ui(size: 18, weight: .bold))
                .foregroundStyle(Color.theme.fg1)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.theme.fg3)
            Spacer()
            Text("\(count) position\(count == 1 ? "" : "s")")
                .font(.numeric(size: 11))
                .foregroundStyle(Color.theme.fg3)
        }
        .padding(.top, 4)
    }
}

// MARK: - Holding row

private struct HoldingRow: View {
    let company: Company

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(company.ticker)
                        .font(.ui(size: 16, weight: .bold))
                        .foregroundStyle(Color.theme.fg1)
                    Text("\(company.sector) · \(company.strategy.rawValue)")
                        .font(.ui(size: 11, weight: .medium))
                        .foregroundStyle(Color.theme.fg3)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // Compact P&L badge — could grow into a tappable cycle
                // (%/$/Δ) like the design later.
                Text(fmtK(company.agg.net))
                    .font(.numeric(size: 13))
                    .foregroundStyle(Color.signed(company.agg.net))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(company.agg.net >= 0 ? Color.theme.tintPos : Color.theme.tintNeg)
                    )
            }
            .padding(.vertical, 12)

            Rectangle()
                .fill(Color.theme.hair)
                .frame(height: 0.5)
        }
        .contentShape(Rectangle())
    }
}
