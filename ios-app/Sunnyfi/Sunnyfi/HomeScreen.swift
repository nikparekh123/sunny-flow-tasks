//
//  HomeScreen.swift
//  Sunnyfi
//
//  Home tab — full design fidelity (Phase 4 batch 1):
//   - Portfolio value hero in neon + eye toggle
//   - Price line (seeded) + range bar
//   - Net Δ tap-to-cycle Greek metric row
//   - Swipeable event card stack (derived from real positions)
//   - Weekly premium strip (real data)
//   - "Your portfolio" holdings list with tap-to-cycle %/$/Δ/MV badges
//

import SwiftUI

struct HomeScreen: View {
    let store: PortfolioStore
    let auth: AuthStore

    @State private var range: ChartRange = .oneDay
    @State private var maskValue: Bool = false
    @State private var greekIdx: Int = 0
    @State private var path: [String] = []
    /// Shared across all holding rows: 0=$, 1=%, 2=Δ, 3=diversity.
    /// Tapping any row's badge cycles this for the whole list.
    @State private var holdingBadgeMode: Int = 0

    private var eventCards: [EventCard] {
        EventCardDeriver.cards(
            companies: store.companies,
            allTrades: store.allTrades,
            allGreeks: store.allGreeks
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    heroBlock
                    metricsBlock
                    eventBlock
                    holdingsBlock
                    if let err = store.error {
                        Text(err)
                            .font(.ui(size: 12))
                            .foregroundStyle(Color.theme.neg)
                            .padding(.top, 8)
                    }
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
            // Profile icon + sign-out moved into the You tab (Account
            // screen) so the home header isn't crowded with two
            // competing identity affordances.
            .toolbarBackground(Color.theme.page, for: .navigationBar)
        }
    }

    // MARK: - Body sub-blocks
    // SwiftUI's ViewBuilder is fussy about (a) too many top-level children
    // and (b) `let` statements inside the builder. We pull each section
    // into its own @ViewBuilder var so the main `body` stays small and
    // the local lets become computed-property reads.

    @ViewBuilder
    private var heroBlock: some View {
        ValueHero(store: store, masked: $maskValue, range: range)
        PriceLineChart(
            points: ChartData.line(
                seed: 4242 + ChartData.hashString(range.rawValue),
                count: ChartData.pointCount(for: range),
                trend: 1.0
            ),
            isNegative: false,
            height: 132
        )
        RangeBar(active: $range)
    }

    @ViewBuilder
    private var metricsBlock: some View {
        Divider().background(Color.theme.hair)
        NetDeltaRow(portfolio: store.portfolio, greekIdx: $greekIdx)
        Divider().background(Color.theme.hair)
    }

    @ViewBuilder
    private var eventBlock: some View {
        // EventCardStack renders its own "Portfolio updates · n / total"
        // header so we don't repeat a SectionTitle here.
        EventCardStack(cards: eventCards) { ticker in
            path.append(ticker)
        }
    }

    @ViewBuilder
    private var holdingsBlock: some View {
        PortfolioSectionHeader(count: store.companies.count, badgeMode: holdingBadgeMode)
        if store.isLoading && store.companies.isEmpty {
            loadingState
        } else if store.companies.isEmpty {
            EmptyHoldings()
        } else {
            VStack(spacing: 0) {
                ForEach(store.companies) { c in
                    Button {
                        path.append(c.ticker)
                    } label: {
                        HoldingRow(
                            company: c,
                            portfolioMV: store.portfolio.mv,
                            badgeMode: $holdingBadgeMode
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
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

// MARK: - Empty state

private struct EmptyHoldings: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28))
                .foregroundStyle(Color.theme.fg3)
            Text("No positions yet")
                .font(.ui(size: 14, weight: .semibold))
                .foregroundStyle(Color.theme.fg2)
            Text("Add a trade to start tracking Greeks and P&L.")
                .font(.ui(size: 12))
                .foregroundStyle(Color.theme.fg3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

// MARK: - Section title

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.ui(size: 18, weight: .bold))
            .foregroundStyle(Color.theme.fg1)
            .padding(.top, 6)
    }
}

// MARK: - Portfolio value hero

private struct ValueHero: View {
    let store: PortfolioStore
    @Binding var masked: Bool
    let range: ChartRange

    /// True total portfolio market value — stocks at spot + options at
    /// their current mark (longs add, shorts subtract via signed qty).
    /// Previously this added `unreal` on top, which double-counted the
    /// stock gain and silently ignored options entirely.
    private var totalValue: Double { store.portfolio.mv }

    /// Today's dollar change across every leg.
    ///   stock: qty × spot × dayPct
    ///   option: leg.delta × spot × dayPct  — leg.delta is already
    ///           multiplied by contracts × 100 × side-sign, so this
    ///           gives the position's dollar P&L for today's move.
    private var todayChange: Double {
        store.companies.reduce(0.0) { acc, c in
            let move = c.dayPct / 100.0
            return acc + c.legs.reduce(0.0) { a, leg in
                switch leg.kind {
                case .stock:        return a + leg.qty * leg.last * move
                case .call, .put:   return a + leg.delta * c.spot * move
                }
            }
        }
    }
    private var todayPct: Double { totalValue > 0 ? (todayChange / totalValue) * 100 : 0 }
    private var hasTodayData: Bool {
        store.companies.contains(where: { $0.dayPct != 0 })
    }

    /// Label that matches the selected range pill.
    private var rangeLabel: String {
        switch range {
        case .oneDay:     return "Today"
        case .oneWeek:    return "1W"
        case .oneMonth:   return "1M"
        case .threeMonth: return "3M"
        case .ytd:        return "YTD"
        case .oneYear:    return "1Y"
        case .all:        return "All"
        }
    }

    /// Range change from daily_closes × current shares (PortfolioHistory).
    /// nil if we don't have enough history rows for the held tickers, in
    /// which case we render "—".
    private var rangeChange: RangeChange? {
        if range == .oneDay {
            // Use ticker_quotes.day_change_pct for 1D (more current than
            // close-vs-close which could be 1 trading day stale).
            guard hasTodayData else { return nil }
            return RangeChange(dollars: todayChange, percent: todayPct)
        }
        return PortfolioHistory.change(
            for: range,
            companies: store.companies,
            dailyCloses: store.dailyCloses
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PORTFOLIO VALUE")
                    .font(.microLabel)
                    .tracking(1.4)
                    .foregroundStyle(Color.theme.fg2)
                Spacer()
                Button {
                    masked.toggle()
                } label: {
                    Image(systemName: masked ? "eye.slash" : "eye")
                        .foregroundStyle(Color.theme.fg2)
                        .font(.system(size: 18))
                }
                .buttonStyle(.pressable)
            }

            // Navi DS hero (.hero · 52/800 / -.035em / fg1 ink). Deep
            // near-black on paper for max contrast; neon is reserved
            // for KPI accents like the delta below.
            Group {
                if masked {
                    Text("••••••")
                        .font(.ui(size: 52, weight: .heavy))
                        .tracking(-1.8)
                        .foregroundStyle(Color.theme.fg1)
                } else {
                    Text(fmtMoney(totalValue))
                        .font(.ui(size: 52, weight: .heavy))
                        .tracking(-1.8)
                        .foregroundStyle(Color.theme.fg1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }

            HStack(spacing: 8) {
                if let chg = rangeChange {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 9))
                        .rotationEffect(.degrees(chg.dollars >= 0 ? 0 : 180))
                        .foregroundStyle(Color.signed(chg.dollars))
                    // $ value carries the signal color; % stays muted
                    // in fg3 — same rule applied across all signed
                    // dollar/percent pairs in the app.
                    HStack(spacing: 5) {
                        Text(fmtMoney(chg.dollars, sign: true))
                            .foregroundStyle(Color.signed(chg.dollars))
                        Text("(\(fmtPct(chg.percent)))")
                            .foregroundStyle(Color.theme.fg3)
                    }
                    .font(.numeric(size: 14, weight: .medium))
                } else {
                    Text("—")
                        .font(.numeric(size: 14, weight: .medium))
                        .foregroundStyle(Color.theme.fg3)
                }
                Text(rangeLabel)
                    .font(.ui(size: 12, weight: .medium))
                    .foregroundStyle(Color.theme.fg2)
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
                Button {
                    active = r
                } label: {
                    Text(r.rawValue)
                        .font(.numeric(size: 12))
                        .foregroundStyle(active == r ? Color.theme.neon : Color.theme.fg3)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background {
                            if active == r {
                                Capsule()
                                    .fill(Color.theme.tintNeon)
                                    .overlay(Capsule().strokeBorder(Color.theme.neon.opacity(0.22), lineWidth: 1))
                            }
                        }
                }
                .buttonStyle(.pressable)
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
        // Just the two the user actually scans for — Net Δ and Net Γ.
        // β·Δ / Θ / V available elsewhere (Company → Net Δ block).
        [
            ("Net Delta", fmtGreek(portfolio.delta)),
            ("Net Gamma", fmtGreek(portfolio.gamma)),
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
    /// Mirrors the holding-row badge cycle so the right-side text in the
    /// header doubles as a legend for what each row's badge represents.
    /// 0 = $ (default, shows position count), 1 = %, 2 = Δ, 3 = diversity.
    let badgeMode: Int

    private var modeLabel: String {
        switch badgeMode {
        case 1: return "Gains %"
        case 2: return "Delta"
        case 3: return "Diversity"
        default:
            let s = count == 1 ? "" : "s"
            // Verbatim interpolation — `\(Int)` via LocalizedStringKey
            // would otherwise add a thousand-separator for high counts.
            return "\(count.formatted(.number.grouping(.never))) position\(s)"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Your portfolio")
                .font(.ui(size: 18, weight: .bold))
                .foregroundStyle(Color.theme.fg1)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.theme.fg3)
            Spacer()
            Text(verbatim: modeLabel)
                .font(.numeric(size: 11))
                .foregroundStyle(badgeMode == 0 ? Color.theme.fg3 : Color.theme.neon)
                .animation(Motion.standard, value: badgeMode)
        }
        .padding(.top, 4)
    }
}

// MARK: - Holding row with tap-to-cycle badge

private struct HoldingRow: View {
    let company: Company
    let portfolioMV: Double
    /// Shared across the whole holdings list — tap on any row cycles
    /// every row's badge in unison. Owned by HomeScreen.
    @Binding var badgeMode: Int   // 0=$, 1=%, 2=Δ, 3=diversity

    private var diversityPct: Double {
        portfolioMV > 0 ? (company.agg.mv / portfolioMV) * 100 : 0
    }

    private var shareQty: Int {
        Int(company.legs.first(where: { $0.kind == .stock })?.qty ?? 0)
    }

    private var badgeValues: [(text: String, isPositive: Bool, neutral: Bool)] {
        let stockAvg = company.legs.first(where: { $0.kind == .stock })?.avg ?? 0
        let netPct = (company.spot > 0 && stockAvg > 0)
            ? ((company.spot - stockAvg) / stockAvg) * 100
            : 0
        return [
            (fmtK(company.agg.net),                  company.agg.net >= 0, false),
            (fmtPct(netPct),                         netPct >= 0,          false),
            ("Δ \(fmtGreek(company.agg.delta))",     true,                 true),
            (String(format: "%.1f%%", diversityPct), true,                 true),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(company.ticker)
                        .font(.ui(size: 20, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Color.theme.fg1)
                    Text(verbatim: "\(shareQty.formatted(.number.grouping(.never))) share\(shareQty == 1 ? "" : "s")")
                        .font(.numeric(size: 13))
                        .foregroundStyle(Color.theme.fg3)
                }

                Spacer(minLength: 8)

                let badge = badgeValues[badgeMode]
                Button {
                    badgeMode = (badgeMode + 1) % badgeValues.count
                } label: {
                    Text(badge.text)
                        .font(.numeric(size: 16, weight: .medium))
                        .foregroundStyle(badge.neutral ? Color.theme.fg2
                                         : badge.isPositive ? Color.theme.pos : Color.theme.neg)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .fill(badge.neutral ? Color.theme.tintMuted
                                      : badge.isPositive ? Color.theme.tintPos : Color.theme.tintNeg)
                        )
                }
                .buttonStyle(.pressable)
            }
            .padding(.vertical, 14)

            Rectangle()
                .fill(Color.theme.hair)
                .frame(height: 0.5)
        }
        .contentShape(Rectangle())
    }
}
