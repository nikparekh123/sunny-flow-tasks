//
//  CompanyScreen.swift
//  Sunnyfi
//
//  Per-ticker detail (Phase 4 batch 1). Layout per design:
//   - Glass sticky header is provided by NavigationStack's default; we
//     show name + chips + price + day change at the top of content
//   - Price line chart + range bar
//   - Net Δ block with 9-day diverging bars
//   - Position / Options peek carousel
//   - Stats grid
//   - History list (real data — opens, closes, share sells for this ticker)
//   - Other positions horizontal cards
//

import SwiftUI

struct CompanyScreen: View {
    let ticker: String
    let store: PortfolioStore

    @State private var range: ChartRange = .oneDay
    @State private var showTradesSheet: Bool = false
    @State private var greekPage: Int = 0           // 0 = Δ, 1 = Γ
    @State private var selectedDeltaBar: Int? = nil

    private var company: Company? {
        store.companies.first(where: { $0.ticker == ticker })
            ?? store.closedCompanies.first(where: { $0.ticker == ticker })
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            scrollBody
            // Floating Trade button — glass capsule per design's lg-foot
            Button { showTradesSheet = true } label: {
                Text("Trade")
                    .font(.ui(size: 14, weight: .bold))
                    .tracking(0.2)
                    .foregroundStyle(Color.theme.fg1)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.pressable)
            .background(
                Capsule()
                    .strokeBorder(Color.theme.borderBright, lineWidth: 1.5)
            )
            .glassEffect(.regular.tint(Color.theme.page2.opacity(0.5)), in: .capsule)
            .padding(.trailing, 16)
            .padding(.bottom, 16)
        }
        .background(Color.theme.page.ignoresSafeArea())
        .sheet(isPresented: $showTradesSheet) {
            TickerTradesSheet(store: store, ticker: ticker)
                .presentationDetents([.large])
        }
    }

    private var scrollBody: some View {
        ScrollView {
            if let c = company {
                LazyVStack(alignment: .leading, spacing: 18) {
                    headerBlock(c)
                    netDeltaBlock(c)
                    positionBlock(c)
                    statsBlock(c)
                    historyBlock(c)
                    otherPositionsBlock(c)
                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            } else {
                ProgressView()
                    .tint(.theme.neon)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            }
        }
        .navigationTitle(ticker)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.theme.page, for: .navigationBar)
    }

    // MARK: - Body sub-blocks

    @ViewBuilder
    private func headerBlock(_ c: Company) -> some View {
        Header(company: c)
        PriceLineChart(
            points: ChartData.line(
                seed: ChartData.hashString(c.ticker) + ChartData.hashString(range.rawValue) * 7,
                count: ChartData.pointCount(for: range),
                trend: c.dayPct >= 0 ? 1.0 : -1.0
            ),
            isNegative: c.dayPct < 0,
            height: 132
        )
        RangeBarLite(active: $range)
    }

    @ViewBuilder
    private func netDeltaBlock(_ c: Company) -> some View {
        Divider().background(Color.theme.hair)
        GreeksSwipeBlock(
            company: c,
            page: $greekPage,
            selectedBar: $selectedDeltaBar
        )
    }

    @ViewBuilder
    private func positionBlock(_ c: Company) -> some View {
        Divider().background(Color.theme.hair)
        PositionDeck(company: c)
    }

    @ViewBuilder
    private func statsBlock(_ c: Company) -> some View {
        Divider().background(Color.theme.hair)
        SectionTitle("Stats")
        StatsGrid(company: c)
    }

    @ViewBuilder
    private func historyBlock(_ c: Company) -> some View {
        Divider().background(Color.theme.hair)
        HStack(alignment: .firstTextBaseline) {
            SectionTitle("History")
            Spacer()
            NavigationLink {
                CompanyFullHistoryView(ticker: c.ticker, store: store)
            } label: {
                Text("See all →")
                    .font(.ui(size: 13, weight: .semibold))
                    .foregroundStyle(Color.theme.neon)
            }
            .buttonStyle(.pressable)
        }
        HistoryList(rows: HistoryDeriver.rows(
            for: c.ticker, trades: store.allTrades, shareSells: store.allShareSells,
            limit: 20
        ))
    }

    @ViewBuilder
    private func otherPositionsBlock(_ c: Company) -> some View {
        let others = otherPositions(excluding: c.ticker)
        if !others.isEmpty {
            Divider().background(Color.theme.hair)
            SectionTitle("Other positions")
            OtherPositionsStrip(companies: others)
        }
    }

    private func otherPositions(excluding: String) -> [Company] {
        store.companies.filter { $0.ticker != excluding }.prefix(5).map { $0 }
    }
}

// MARK: - Header

private struct Header: View {
    let company: Company

    /// Picks the most readable display name. Priority:
    /// 1. `positions.name` if it differs from the ticker
    /// 2. Our TickerNames lookup ("Adobe" for ADBE etc.)
    /// 3. The ticker itself as last resort
    /// The ticker is already shown center-top in the nav bar, so the
    /// big hero line should always prefer a name when one's available.
    private var displayName: String {
        if !company.name.isEmpty && company.name.uppercased() != company.ticker.uppercased() {
            return company.name
        }
        return TickerNames.name(for: company.ticker) ?? company.ticker
    }

    /// Clean Robinhood-style header — big company name on top, then
    /// price + today's change. No duplicate ticker tag (nav already has
    /// it) and no sector/strategy chips (those moved to the Stats row).
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayName)
                .font(.ui(size: 32, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Color.theme.fg1)

            Text(fmtMoney(company.spot, decimals: 2))
                .font(.numeric(size: 32, weight: .semibold))
                .tracking(-1.0)
                .foregroundStyle(Color.theme.fg1)
                .padding(.top, 4)

            let absDollar = company.spot * (company.dayPct / 100)
            HStack(spacing: 6) {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 9))
                    .rotationEffect(.degrees(company.dayPct >= 0 ? 0 : 180))
                    .foregroundStyle(Color.signed(company.dayPct))
                HStack(spacing: 5) {
                    Text(fmtMoney(absDollar, sign: true, decimals: 2))
                        .foregroundStyle(Color.signed(company.dayPct))
                    Text("(\(fmtPct(company.dayPct)))")
                        .foregroundStyle(Color.theme.fg3)
                }
                .font(.numeric(size: 14, weight: .medium))
                Text("Today")
                    .font(.ui(size: 12, weight: .medium))
                    .foregroundStyle(Color.theme.fg2)
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Range bar (slim)

private struct RangeBarLite: View {
    @Binding var active: ChartRange
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ChartRange.allCases) { r in
                Button {
                    withAnimation(Motion.overshoot) { active = r }
                } label: {
                    Text(r.rawValue)
                        .font(.numeric(size: 12))
                        .foregroundStyle(active == r ? Color.theme.neon : Color.theme.fg3)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background {
                            if active == r {
                                Capsule().fill(Color.theme.tintNeon)
                                    .overlay(Capsule().strokeBorder(Color.theme.neon.opacity(0.22), lineWidth: 1))
                                    .matchedGeometryEffect(id: "rangePillLite", in: ns)
                            }
                        }
                }
                .buttonStyle(.pressable)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Net Delta block with 9-day bars

/// Swipeable Greeks card — page 0 = Net Δ, page 1 = Net Γ. The
/// 9-day diverging bars under each page are tappable; tapping any
/// bar shows that day's value in the caption (same interaction as
/// the Trades and Performance bar charts).
private struct GreeksSwipeBlock: View {
    let company: Company
    @Binding var page: Int
    @Binding var selectedBar: Int?

    private struct Variant {
        let title: String
        let value: String
        let bars: [BarPoint]
    }

    private var deltaVariant: Variant {
        Variant(
            title: "NET DELTA",
            value: fmtGreek(company.agg.delta),
            bars: ChartData.bars(seed: ChartData.hashString(company.ticker) + 5, count: 9, upProb: 0.78)
        )
    }
    private var gammaVariant: Variant {
        Variant(
            title: "NET GAMMA",
            value: fmtGreek(company.agg.gamma),
            bars: ChartData.bars(seed: ChartData.hashString(company.ticker) + 9, count: 9, upProb: 0.55)
        )
    }
    private var variants: [Variant] { [deltaVariant, gammaVariant] }

    private func dayLabel(for index: Int) -> String {
        let n = 8 - index
        if n == 0 { return "today" }
        if n == 1 { return "yesterday" }
        return "\(n)d ago"
    }

    private var caption: String {
        let current = variants[page]
        if let i = selectedBar, current.bars.indices.contains(i) {
            let v = current.bars[i].value
            // Approximate scaling — the 9-day bars are synthetic random
            // walks in [-1, 1] until we wire real per-day Greek history.
            // Multiply by the current aggregate to give a sensible label.
            let scaled = v * abs(company.agg.delta) * 0.18
            return "\(dayLabel(for: i)) · \(fmtGreek(scaled))"
        }
        return "Last 9 days"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabView(selection: $page) {
                ForEach(variants.indices, id: \.self) { i in
                    variantCard(variants[i])
                        .padding(.horizontal, 2)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 240)
            .onChange(of: page) { _, _ in
                // Clear bar selection when switching between Δ and Γ so
                // we don't show a stale caption for the other variant.
                selectedBar = nil
            }

            // Dots indicator
            HStack(spacing: 5) {
                ForEach(variants.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Color.theme.neon : Color.theme.fg4)
                        .frame(width: i == page ? 14 : 5, height: 5)
                        .animation(.easeInOut(duration: 0.2), value: page)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func variantCard(_ v: Variant) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v.title)
                .font(.ui(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Color.theme.fg2)
                .padding(.bottom, 9)
            Rectangle().fill(Color.theme.hair).frame(height: 0.5)
            Text(caption)
                .font(.numeric(size: 12, weight: selectedBar == nil ? .regular : .semibold))
                .foregroundStyle(selectedBar == nil ? Color.theme.fg3 : Color.theme.fg1)
                .padding(.top, 10)
            Text(v.value)
                .font(.numeric(size: 28, weight: .semibold))
                .tracking(-1.0)
                .foregroundStyle(Color.theme.neon)
                .padding(.top, 4)

            DeltaBarChart(bars: v.bars, height: 84, selection: $selectedBar)
                .padding(.top, 10)

            HStack {
                Text("9d ago"); Spacer(); Text("today")
            }
            .font(.numeric(size: 10))
            .foregroundStyle(Color.theme.fg4)
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(Color.theme.cardSolid)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl)
                        .strokeBorder(Color.theme.hair, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Swipeable position deck — Shares → Calls → Puts

/// One page per asset type. Above the dots a summary line shows the
/// active page's P&L so the user gets a per-section number at a glance.
private struct PositionDeck: View {
    let company: Company

    @State private var page: Int = 0

    private var callLegs: [Leg] { company.legs.filter { $0.kind == .call } }
    private var putLegs:  [Leg] { company.legs.filter { $0.kind == .put  } }
    private var stockLeg: Leg?  { company.legs.first(where: { $0.kind == .stock }) }

    private var pages: [PageDescriptor] {
        var out: [PageDescriptor] = []
        if let s = stockLeg, s.qty > 0 {
            out.append(.init(kind: .shares, label: "Shares", pnl: s.unreal))
        }
        if !callLegs.isEmpty {
            out.append(.init(kind: .calls, label: "Calls",
                             pnl: callLegs.reduce(0) { $0 + $1.unreal }))
        }
        if !putLegs.isEmpty {
            out.append(.init(kind: .puts, label: "Puts",
                             pnl: putLegs.reduce(0) { $0 + $1.unreal }))
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            SectionTitle("Your position")
                .padding(.bottom, 8)

            if pages.isEmpty {
                Text("No active position.")
                    .font(.ui(size: 13))
                    .foregroundStyle(Color.theme.fg3)
                    .padding(.vertical, 18)
            } else {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { i, p in
                        deckPage(p)
                            .padding(.horizontal, 2)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 240)

                // Summary line above the dots — current page label + P&L.
                if pages.indices.contains(page) {
                    let cur = pages[page]
                    HStack(spacing: 6) {
                        Text(cur.label.uppercased())
                            .font(.ui(size: 10, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(Color.theme.fg2)
                        Text("·")
                            .foregroundStyle(Color.theme.fg4)
                        Text(fmtMoney(cur.pnl, sign: true))
                            .font(.numeric(size: 13, weight: .semibold))
                            .foregroundStyle(Color.signed(cur.pnl))
                    }
                    .padding(.top, 6)
                }

                HStack(spacing: 5) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Color.theme.neon : Color.theme.fg4)
                            .frame(width: i == page ? 14 : 5, height: 5)
                            .animation(.easeInOut(duration: 0.2), value: page)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private func deckPage(_ p: PageDescriptor) -> some View {
        switch p.kind {
        case .shares:
            PositionCard(company: company)
        case .calls:
            OptionLegsCard(legs: callLegs, label: "Calls", isCall: true)
        case .puts:
            OptionLegsCard(legs: putLegs, label: "Puts", isCall: false)
        }
    }

    private struct PageDescriptor {
        let kind: PageKind
        let label: String
        let pnl: Double
    }
    private enum PageKind { case shares, calls, puts }
}

/// One card hosting every leg of a given type. Each leg gets a compact
/// row (strike + side/qty/expiry + per-leg unrealized).
private struct OptionLegsCard: View {
    let legs: [Leg]
    let label: String
    let isCall: Bool

    private var totalUnreal: Double {
        legs.reduce(0) { $0 + $1.unreal }
    }
    private var totalPremium: Double {
        legs.reduce(0) { acc, leg in
            let sign: Double = leg.side == .short ? 1 : -1
            return acc + leg.avg * abs(leg.qty) * 100 * sign
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(label.uppercased())
                    .font(.ui(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(isCall ? Color.theme.pos : Color.theme.neg)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(isCall ? Color.theme.tintPos : Color.theme.tintNeg))
                Text("\(legs.count) leg\(legs.count == 1 ? "" : "s")")
                    .font(.numeric(size: 13))
                    .foregroundStyle(Color.theme.fg2)
                Spacer()
                Text(fmtMoney(totalUnreal, sign: true))
                    .font(.numeric(size: 15, weight: .semibold))
                    .foregroundStyle(Color.signed(totalUnreal))
            }

            Rectangle().fill(Color.theme.hair).frame(height: 0.5)

            VStack(spacing: 8) {
                ForEach(legs) { leg in
                    legRow(leg)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Text("Premium collected")
                    .font(.ui(size: 11))
                    .foregroundStyle(Color.theme.fg3)
                Spacer()
                Text(fmtMoney(totalPremium, sign: true))
                    .font(.numeric(size: 13))
                    .foregroundStyle(Color.signed(totalPremium))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(cardBackground)
    }

    @ViewBuilder
    private func legRow(_ leg: Leg) -> some View {
        let strike = "$\(fmtStrike(leg.strike ?? 0))"
        let side = (leg.side == .short ? "short" : "long")
        let qty = Int(abs(leg.qty))
        let exp = leg.expiry.map { AppDates.shortMonthDay($0) } ?? "—"
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(strike) \(isCall ? "call" : "put")")
                    .font(.numeric(size: 14, weight: .semibold))
                    .foregroundStyle(Color.theme.fg1)
                Text("\(side) · ×\(qty) · exp \(exp)")
                    .font(.numeric(size: 11))
                    .foregroundStyle(Color.theme.fg3)
            }
            Spacer()
            Text(fmtMoney(leg.unreal, sign: true))
                .font(.numeric(size: 13))
                .foregroundStyle(Color.signed(leg.unreal))
        }
    }
}

/// "Your shares" card — six metrics in a 3-cell stat row with bigger
/// type that matches the rest of the app's positions/Trades cards.
private struct PositionCard: View {
    let company: Company

    private var stock: Leg? { company.legs.first(where: { $0.kind == .stock }) }

    private let cardMinHeight: CGFloat = 180

    var body: some View {
        let s = stock
        let shares = Int(s?.qty ?? 0)
        let mv = company.agg.mv
        let avg = s?.avg ?? 0
        let todayReturn = (s?.last ?? 0) * (company.dayPct / 100) * (s?.qty ?? 0)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("SHARES")
                    .font(.ui(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.theme.fg2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.theme.tintMuted))
                Text(shares.formatted(.number.grouping(.never)) + " shares")
                    .font(.numeric(size: 17, weight: .bold))
                    .foregroundStyle(Color.theme.fg1)
                Spacer()
                Text(fmtMoney(mv))
                    .font(.numeric(size: 15, weight: .semibold))
                    .foregroundStyle(Color.theme.fg1)
            }

            HStack(spacing: 0) {
                statCell(label: "AVG COST",     value: fmtMoney(avg, decimals: 2),                 tone: .theme.fg1)
                Divider().frame(height: 32).background(Color.theme.hair)
                statCell(label: "TODAY",        value: fmtMoney(todayReturn, sign: true),          tone: Color.signed(todayReturn))
                Divider().frame(height: 32).background(Color.theme.hair)
                statCell(label: "OPEN P&L",     value: fmtMoney(company.agg.unreal, sign: true),   tone: Color.signed(company.agg.unreal))
            }

            HStack {
                Text("β \(String(format: "%.2f", company.beta))")
                    .font(.numeric(size: 12))
                    .foregroundStyle(Color.theme.fg3)
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .topLeading)
        .background(cardBackground)
    }

    @ViewBuilder
    private func statCell(label: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.ui(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.theme.fg3)
            Text(value)
                .font(.numeric(size: 15, weight: .medium))
                .foregroundStyle(tone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// One card per option leg. Same vertical metric layout + height as
/// PositionCard so the stack reads as a series of aligned cards.
private struct OptionLegCard: View {
    let leg: Leg
    let ticker: String

    private let cardMinHeight: CGFloat = 180

    private var isCall: Bool { leg.kind == .call }
    private var isPut: Bool  { leg.kind == .put }
    private var sideLabel: String { (leg.side == .short ? "SHORT" : "LONG") }
    private var qty: Int { Int(abs(leg.qty)) }
    private var expShort: String { leg.expiry.map { AppDates.shortMonthDay($0) } ?? "—" }
    private var dteText: String {
        guard let n = leg.dte else { return "—" }
        if n < 0 { return "expired \(-n)d ago" }
        if n == 0 { return "today" }
        if n == 1 { return "tomorrow" }
        return "in \(n)d"
    }
    private var totalPremium: Double {
        let sign: Double = leg.side == .short ? 1 : -1
        return leg.avg * Double(qty) * 100 * sign
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(isCall ? "CALL" : "PUT")
                    .font(.ui(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(isCall ? Color.theme.pos : Color.theme.neg)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(isCall ? Color.theme.tintPos : Color.theme.tintNeg))
                Text("$\(fmtStrike(leg.strike ?? 0)) \(isCall ? "call" : "put")")
                    .font(.numeric(size: 17, weight: .bold))
                    .foregroundStyle(Color.theme.fg1)
                Spacer()
                Text("\(sideLabel) ×\(qty)")
                    .font(.ui(size: 11, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(leg.side == .short ? Color.theme.pos : Color.theme.neg)
            }

            HStack(spacing: 0) {
                statCell(label: "PREMIUM",    value: fmtMoney(totalPremium, sign: true), tone: Color.signed(totalPremium))
                Divider().frame(height: 32).background(Color.theme.hair)
                statCell(label: "UNREALIZED", value: fmtMoney(leg.unreal, sign: true), tone: Color.signed(leg.unreal))
                Divider().frame(height: 32).background(Color.theme.hair)
                statCell(label: "EXPIRY",     value: expShort, tone: Color.theme.fg1, caption: dteText)
            }

            HStack(spacing: 14) {
                Text("Δ \(fmtGreek(leg.delta))")
                Text("Θ \(fmtGreek(leg.theta))")
                if leg.iv != nil { Text("IV \(String(format: "%.1f%%", (leg.iv ?? 0) * 100))") }
                Spacer()
            }
            .font(.numeric(size: 12))
            .foregroundStyle(Color.theme.fg3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .topLeading)
        .background(cardBackground)
    }

    @ViewBuilder
    private func statCell(label: String, value: String, tone: Color, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.ui(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.theme.fg3)
            Text(value)
                .font(.numeric(size: 15, weight: .medium))
                .foregroundStyle(tone)
            if let c = caption {
                Text(c)
                    .font(.numeric(size: 10))
                    .foregroundStyle(Color.theme.fg4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// Shared card background — same gradient + neon outline as the
/// position cards on Trades, so everything reads as a single family.
private var cardBackground: some View {
    RoundedRectangle(cornerRadius: Radius.xl)
        .fill(
            LinearGradient(
                colors: [Color.cardGrad.top, Color.cardGrad.bot],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(Color.theme.neon.opacity(0.25), lineWidth: 1.2)
        )
}

// MARK: - Stats grid

/// Stats laid out as 3 explicit rows × 2 cells. Each row is its own
/// HStack with a fixed `equal-split` shape — guarantees label baselines
/// line up across columns regardless of value length (which was the
/// source of the wonkiness in the previous LazyVGrid version).
private struct StatsGrid: View {
    let company: Company

    private var avgCost: Double {
        company.legs.first(where: { $0.kind == .stock })?.avg ?? 0
    }
    private var prevClose: Double {
        company.dayPct == 0 ? company.spot : company.spot / (1 + company.dayPct / 100)
    }

    var body: some View {
        VStack(spacing: 20) {
            statRow(
                ("Spot",       fmtMoney(company.spot, decimals: 2)),
                ("Prev close", fmtMoney(prevClose, decimals: 2))
            )
            statRow(
                ("Day %",      fmtPct(company.dayPct)),
                ("β",          String(format: "%.2f", company.beta))
            )
            statRow(
                ("Avg cost",   avgCost > 0 ? fmtMoney(avgCost, decimals: 2) : "—"),
                ("Strategy",   company.strategy.rawValue)
            )
        }
    }

    @ViewBuilder
    private func statRow(_ left: (String, String), _ right: (String, String)) -> some View {
        HStack(alignment: .top, spacing: 16) {
            statCell(label: left.0, value: left.1)
            statCell(label: right.0, value: right.1)
        }
    }

    @ViewBuilder
    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.ui(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.theme.fg3)
            Text(value)
                .font(.numeric(size: 17, weight: .medium))
                .foregroundStyle(Color.theme.fg1)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - History — real rows from option_trades + share_sells

struct HistoryRow: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    /// Line 1 — asset only, e.g. "$257 call" or "ADBE shares".
    let asset: String
    /// Line 2 — what happened + when, e.g. "1 call closed on May 28".
    let action: String
    let value: Double
    let tone: Tone
    enum Tone { case pos, neg, mut }

    static func == (lhs: HistoryRow, rhs: HistoryRow) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum HistoryDeriver {
    /// `limit: nil` returns every row (used by the "See all" full page);
    /// passing 20 keeps the section preview small.
    static func rows(
        for ticker: String,
        trades: [OptionTradeRow],
        shareSells: [ShareSellRow],
        limit: Int? = 20
    ) -> [HistoryRow] {
        var out: [HistoryRow] = []

        for t in trades where t.ticker == ticker {
            guard let d = AppDates.parseISODay(t.trade_date) else { continue }
            let kind = t.option_type
            let kindPlural = t.option_type == "call" ? "calls" : "puts"
            let dateStr = AppDates.shortMonthDay(t.trade_date)

            if t.action == "open" {
                let verb = t.direction == "short" ? "sold" : "bought"
                let value = t.premium * t.contracts * 100 * (t.direction == "short" ? 1 : -1)
                out.append(HistoryRow(
                    date: d,
                    asset: "$\(fmtStrike(t.strike)) \(kind)",
                    action: "\(Int(t.contracts)) \(kindPlural) \(verb) on \(dateStr)",
                    value: value,
                    tone: value >= 0 ? .pos : .neg
                ))
            } else {
                let open = trades.first(where: { $0.id == (t.closes_trade_id ?? "") })
                let realized: Double = {
                    guard let o = open else { return 0 }
                    let sign: Double = o.direction == "short" ? 1 : -1
                    return (o.premium - t.premium) * t.contracts * 100 * sign
                }()
                out.append(HistoryRow(
                    date: d,
                    asset: "$\(fmtStrike(t.strike)) \(kind)",
                    action: "\(Int(t.contracts)) \(kindPlural) closed on \(dateStr)",
                    value: realized,
                    tone: realized >= 0 ? .pos : .neg
                ))
            }
        }

        for s in shareSells where s.ticker == ticker {
            guard let d = AppDates.parseISODay(s.trade_date) else { continue }
            out.append(HistoryRow(
                date: d,
                asset: "\(ticker) shares",
                action: "Sold on \(AppDates.shortMonthDay(s.trade_date))",
                value: s.realized_pl,
                tone: s.realized_pl >= 0 ? .pos : .neg
            ))
        }

        let sorted = out.sorted { $0.date > $1.date }
        if let limit = limit { return sorted.prefix(limit).map { $0 } }
        return sorted
    }
}

/// Full history page, pushed from the "See all →" link on Company.
struct CompanyFullHistoryView: View {
    let ticker: String
    let store: PortfolioStore

    var body: some View {
        let rows = HistoryDeriver.rows(
            for: ticker,
            trades: store.allTrades,
            shareSells: store.allShareSells,
            limit: nil
        )
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(rows.count) event\(rows.count == 1 ? "" : "s")")
                        .font(.numeric(size: 12))
                        .foregroundStyle(Color.theme.fg3)
                    Spacer()
                }
                .padding(.bottom, 6)
                HistoryList(rows: rows)
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .background(Color.theme.page.ignoresSafeArea())
        .navigationTitle("\(ticker) history")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.theme.page, for: .navigationBar)
    }
}

private struct HistoryList: View {
    let rows: [HistoryRow]

    var body: some View {
        if rows.isEmpty {
            Text("No history yet.")
                .font(.ui(size: 13))
                .foregroundStyle(Color.theme.fg3)
                .padding(.vertical, 16)
        } else {
            VStack(spacing: 0) {
                ForEach(rows) { r in
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.asset)
                                .font(.ui(size: 16, weight: .bold))
                                .foregroundStyle(Color.theme.fg1)
                                .lineLimit(1)
                            Text(r.action)
                                .font(.numeric(size: 13))
                                .foregroundStyle(Color.theme.fg3)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(fmtMoney(r.value, sign: true))
                            .font(.numeric(size: 16, weight: .medium))
                            .foregroundStyle(r.tone == .pos ? Color.theme.pos : r.tone == .neg ? Color.theme.neg : Color.theme.fg3)
                    }
                    .padding(.vertical, 14)
                    Rectangle().fill(Color.theme.hair).frame(height: 0.5)
                }
            }
        }
    }
}

// MARK: - Other positions

private struct OtherPositionsStrip: View {
    let companies: [Company]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 11) {
                ForEach(companies) { c in
                    NavigationLink(value: c.ticker) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(c.name.components(separatedBy: " ").first ?? c.ticker)
                                .font(.ui(size: 12.5, weight: .semibold))
                                .foregroundStyle(Color.theme.fg2)
                            Spacer()
                            Text(c.ticker)
                                .font(.numeric(size: 15, weight: .bold))
                                .foregroundStyle(Color.theme.fg1)
                            Text(fmtPct(c.dayPct))
                                .font(.numeric(size: 12))
                                .foregroundStyle(Color.signed(c.dayPct))
                                .padding(.top, 3)
                        }
                        .frame(width: 120, height: 100, alignment: .leading)
                        .padding(13)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.xl)
                                .fill(Color.theme.cardSolid)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.xl)
                                        .strokeBorder(Color.theme.hair, lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
