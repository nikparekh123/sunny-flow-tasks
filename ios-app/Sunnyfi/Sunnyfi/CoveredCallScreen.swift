//
//  CoveredCallScreen.swift
//  Sunnyfi
//
//  Covered Call — per-ticker position detail, built to "Position Detail
//  v2". Top to bottom:
//
//    • Ticker switcher + last-updated / refresh
//    • HERO (dark) — lifetime premium harvested, cost basis → adjusted
//    • Your position — tabs: Shares / Calls sold / Puts / Long calls
//    • Where premium lands — realized premium by expiry weekday
//    • How close each call sat — strike vs share price at expiry
//    • What the strategy earned — premium + capital split, yield
//    • History — legs as they close
//
//  All math comes from CoveredCallData (same engine Performance uses).
//

import Combine
import SwiftUI

struct CoveredCallScreen: View {
    let store: PortfolioStore
    @State private var selected: String?
    @State private var refreshing = false
    @State private var tick = 0
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var tickers: [String] { CoveredCallData.tickers(store: store) }
    private var active: String? {
        if let selected, tickers.contains(selected) { return selected }
        return tickers.first
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if tickers.isEmpty {
                emptyState
            } else {
                ScrollView {
                    if let t = active, let data = CoveredCallData.build(store: store, ticker: t) {
                        PositionDetail(data: data)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 110)
                            .id(t)
                    }
                }
            }
        }
        .background(Color.theme.page)
        .onReceive(timer) { _ in tick &+= 1 }
    }

    private var topBar: some View {
        _ = tick
        return HStack(alignment: .center) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tickers, id: \.self) { t in
                        let on = active == t
                        Button {
                            withAnimation(Motion.standard) { selected = t }
                        } label: {
                            Text(t)
                                .font(.system(size: 14, weight: .bold)).tracking(0.2)
                                .foregroundStyle(on ? Color.theme.page : Color.theme.fg3)
                                .padding(.horizontal, 16).frame(minHeight: 34)
                                .background(Capsule().fill(on ? Color.theme.fg1 : Color.theme.page2))
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
            Spacer(minLength: 8)
            Text(lastUpdatedText)
                .font(.numeric(size: 11, weight: .medium)).monospacedDigit()
                .foregroundStyle(isStale ? Color.theme.fg4 : Color.theme.fg3).lineLimit(1)
            Button {
                guard !refreshing else { return }
                refreshing = true
                Task { await store.fetchAll(); refreshing = false }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.theme.pos)
                    .rotationEffect(.degrees(refreshing ? 360 : 0))
                    .animation(refreshing ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                          : .default, value: refreshing)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(refreshing)
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)
    }

    private var lastUpdatedText: String {
        guard let f = store.freshness else { return "Updated —" }
        return "Updated " + Self.hms.string(from: f)
    }
    private var isStale: Bool {
        _ = tick
        guard let f = store.freshness else { return true }
        return -f.timeIntervalSinceNow > 15 * 60
    }
    private static let hms: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No covered-call positions")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.theme.fg2)
            Text("A ticker appears here once you hold shares and sell a call against them.")
                .font(.system(size: 12.5)).foregroundStyle(Color.theme.fg3)
                .multilineTextAlignment(.center).padding(.horizontal, 44)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Position detail (one ticker)

private enum PosTab: String, CaseIterable, Identifiable {
    case shares = "Shares", calls = "Calls sold", puts = "Puts", longCalls = "Long calls"
    var id: String { rawValue }
}

private struct PositionDetail: View {
    let data: CoveredCallTicker
    @State private var tab: PosTab = .shares
    @State private var range: IncomeRange = .all
    @State private var showAllHistory = false

    private var cycle: CoveredCallCycle? { data.current }
    private let lime = Color(hex: 0xD7EE53)
    private let limeInk = Color(hex: 0x1C260A)

    var body: some View {
        VStack(spacing: 14) {
            hero
            positionCard
            weekdayCard
            cushionCard
            returnCard
            historyCard
        }
    }

    // ── HERO ──
    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(lime).frame(width: 6, height: 6)
                Text("PREMIUM HARVESTED · LIFETIME")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.6)
                    .foregroundStyle(lime)
            }
            Text(fmtMoney(data.lifetimePremium))
                .font(.system(size: 52, weight: .heavy)).tracking(-2.2)
                .monospacedDigit().foregroundStyle(.white)
                .minimumScaleFactor(0.5).lineLimit(1)
                .padding(.top, 14)
            Text("Collected across \(data.cycleCount) cycle\(data.cycleCount == 1 ? "" : "s") on \(Int(data.shares).formatted()) \(data.ticker) shares")
                .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)

            if let c = cycle {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COST BASIS").font(.system(size: 9, weight: .heavy)).tracking(1.1)
                            .foregroundStyle(.white.opacity(0.45))
                        Text(fmtMoney(c.entryPrice, decimals: 2).replacingOccurrences(of: "$", with: ""))
                            .font(.numeric(size: 22, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    VStack(spacing: 6) {
                        Text("−\(fmtMoney(c.premiumPerShare, decimals: 2).replacingOccurrences(of: "$", with: ""))")
                            .font(.numeric(size: 11, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(limeInk)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Capsule().fill(lime))
                        Rectangle().fill(LinearGradient(colors: [.white.opacity(0.15), lime],
                                                        startPoint: .leading, endPoint: .trailing))
                            .frame(height: 2).clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("ADJUSTED").font(.system(size: 9, weight: .heavy)).tracking(1.1)
                            .foregroundStyle(.white.opacity(0.45))
                        Text(fmtMoney(c.adjustedBasis, decimals: 2).replacingOccurrences(of: "$", with: ""))
                            .font(.numeric(size: 22, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(lime)
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.09), lineWidth: 1))
                .padding(.top, 20)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26).fill(
                RadialGradient(colors: [Color(hex: 0x25392C), Color(hex: 0x16241B), Color(hex: 0x101A13)],
                               center: .init(x: 0.85, y: -0.1), startRadius: 10, endRadius: 420)
            )
        )
    }

    // ── YOUR POSITION ──
    private var positionCard: some View {
        card {
            Text("Your position").font(.system(size: 19, weight: .heavy)).tracking(-0.5)
                .foregroundStyle(Color.theme.fg1)
            Text(posMeta).font(.system(size: 12.5)).foregroundStyle(Color.theme.fg3)
                .padding(.top, 6)

            segmented(PosTab.allCases, selection: $tab) { $0.rawValue }
                .padding(.top, 16)

            switch tab {
            case .shares:    sharesTab
            case .calls:     legsTab(data.callLegs, empty: "No calls sold right now.", short: true)
            case .puts:      legsTab(data.putLegs, empty: "No protective puts open.", short: false)
            case .longCalls: legsTab(data.longCallLegs, empty: "No long calls open.", short: false)
            }
        }
    }

    private var posMeta: String {
        switch tab {
        case .shares:
            return "\(Int(data.shares).formatted()) shares · \(cycle?.lotCount ?? 0) lot\((cycle?.lotCount ?? 0) == 1 ? "" : "s")"
        case .calls:
            return "\(Int(data.openCallContracts)) contract\(Int(data.openCallContracts) == 1 ? "" : "s") open · \(data.callLegs.count) expir\(data.callLegs.count == 1 ? "y" : "ies")"
        case .puts:
            return "\(Int(data.putContracts)) protective put\(Int(data.putContracts) == 1 ? "" : "s")"
        case .longCalls:
            let n = Int(data.longCallLegs.reduce(0) { $0 + $1.contracts })
            return "\(n) long call\(n == 1 ? "" : "s")"
        }
    }

    private var sharesTab: some View {
        let c = cycle
        let rows: [(String, String, String?, Color)] = [
            ("Shares", Int(data.shares).formatted(), nil, Color.theme.fg1),
            ("Market value", fmtMoney(data.shares * data.currentPrice), nil, Color.theme.fg1),
            ("Cost basis", fmtMoney(c?.entryPrice ?? 0, decimals: 2), nil, Color.theme.fg1),
            ("Adjusted basis", fmtMoney(c?.adjustedBasis ?? 0, decimals: 2),
             c.map { "−\(String(format: "%.1f", $0.entryPrice > 0 ? $0.premiumPerShare / $0.entryPrice * 100 : 0))% via premium" }, Color.theme.pos),
            ("Today's return", fmtMoney(data.todayPL, sign: true), fmtPct(data.dayPct), Color.signed(data.todayPL)),
            ("Total return", fmtMoney(data.totalReturn, sign: true),
             c.map { $0.entryPrice * $0.shares > 0 ? fmtPct(data.totalReturn / ($0.entryPrice * $0.shares) * 100) : "" },
             Color.signed(data.totalReturn)),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading),
                                   GridItem(.flexible(), alignment: .topLeading)],
                         alignment: .leading, spacing: 20) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                VStack(alignment: .leading, spacing: 7) {
                    Text(r.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.theme.fg3)
                    Text(r.1).font(.numeric(size: 21, weight: .heavy)).tracking(-0.5)
                        .monospacedDigit().foregroundStyle(r.3)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let s = r.2, !s.isEmpty {
                        Text(s).font(.numeric(size: 11.5, weight: .bold)).monospacedDigit()
                            .foregroundStyle(r.3 == Color.theme.fg1 ? Color.theme.fg4 : r.3)
                    }
                }
            }
        }
        .padding(.top, 20)
    }

    @ViewBuilder
    private func legsTab(_ legs: [OpenLegDetail], empty: String, short: Bool) -> some View {
        if legs.isEmpty {
            Text(empty).font(.system(size: 13)).foregroundStyle(Color.theme.fg4)
                .padding(.top, 20)
        } else {
            let total = legs.reduce(0.0) { $0 + $1.contracts }
            let pnl = legs.reduce(0.0) { $0 + $1.pnl }
            // Summary strip
            HStack {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(total))").font(.system(size: 23, weight: .heavy)).tracking(-0.5)
                        .monospacedDigit().foregroundStyle(Color.theme.fg1)
                    Text(short ? "contracts · \(legs.count) strike\(legs.count == 1 ? "" : "s")" : "contracts")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.theme.fg3)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(fmtMoney(pnl, sign: true))
                        .font(.numeric(size: 16, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(Color.signed(pnl))
                    Text(short ? "PREMIUM P&L" : "OPEN P&L")
                        .font(.system(size: 9, weight: .heavy)).tracking(1)
                        .foregroundStyle(Color.theme.fg4)
                }
            }
            .padding(15)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.theme.page2))
            .padding(.top, 18)

            ForEach(legs) { leg in
                if short {
                    gaugeLeg(expiry: leg.expiry, strike: leg.strike, contracts: leg.contracts,
                             price: data.currentPrice,
                             foot: fmtMoney(leg.costPerShare * leg.contracts * 100) + " in",
                             footColor: Color.theme.pos)
                } else {
                    optionRow(leg)
                }
            }
        }
    }

    private func optionRow(_ leg: OpenLegDetail) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("\(AppDates.shortMonthDay(leg.expiry)) · \(fmtStrike(leg.strike))")
                        .font(.system(size: 15, weight: .heavy)).tracking(-0.3)
                        .foregroundStyle(Color.theme.fg1)
                    Text("×\(Int(leg.contracts))")
                        .font(.numeric(size: 10.5, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(Color.theme.fg3)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.theme.page2))
                }
                Text("cost \(String(format: "%.2f", leg.costPerShare)) → mark \(String(format: "%.2f", leg.markPerShare))")
                    .font(.numeric(size: 11.5, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Color.theme.fg4)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(fmtMoney(leg.pnl, sign: true))
                    .font(.numeric(size: 15, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(Color.signed(leg.pnl))
                Text(fmtPct(leg.pnlPct))
                    .font(.numeric(size: 11, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Color.signed(leg.pnl))
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.theme.hair).frame(height: 1) }
    }

    // ── Cushion gauge (shared by Calls-sold tab + "how close" card) ──
    private func gaugeLeg(expiry: String, strike: Double, contracts: Double,
                          price: Double, foot: String, footColor: Color) -> some View {
        let m = price > 0 ? (strike - price) / price * 100 : 0
        let tone: Color = m >= 0.8 ? Color.theme.pos : (m <= -0.2 ? Color.theme.neg : Color.theme.warn)
        let label = m >= 0.8 ? "OTM" : (m <= -0.2 ? "ITM" : "ATM")
        let pxL: CGFloat = 0.40
        let kL: CGFloat = max(0.07, min(0.93, pxL + CGFloat(m / 6.5) * 0.46))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(AppDates.shortMonthDay(expiry)) · \(fmtStrike(strike)) call")
                        .font(.system(size: 14.5, weight: .heavy)).tracking(-0.3)
                        .foregroundStyle(Color.theme.fg1)
                    Text("×\(Int(contracts)) contract\(Int(contracts) == 1 ? "" : "s")")
                        .font(.numeric(size: 11.5, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Color.theme.fg4)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(label) \(m >= 0 ? "+" : "−")\(String(format: "%.1f", abs(m)))%")
                        .font(.numeric(size: 10.5, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(tone)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(tone.opacity(0.13)))
                    Text(foot).font(.numeric(size: 12.5, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(footColor)
                }
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    Capsule().fill(Color.theme.page2)
                        .frame(width: w, height: 6).offset(y: 20)
                    Capsule().fill(tone.opacity(0.35))
                        .frame(width: abs(kL - pxL) * w, height: 6)
                        .offset(x: min(pxL, kL) * w, y: 20)
                    // price tick
                    VStack(spacing: 2) {
                        Text(String(format: "%.2f", price))
                            .font(.numeric(size: 9, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(Color.theme.fg4).fixedSize()
                        RoundedRectangle(cornerRadius: 2).fill(Color.theme.fg1)
                            .frame(width: 2.5, height: 18)
                    }
                    .offset(x: pxL * w - 14, y: 0)
                    // strike dot
                    VStack(spacing: 1) {
                        Circle().fill(tone)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(Color.theme.surface, lineWidth: 3.5))
                        Text(fmtStrike(strike))
                            .font(.numeric(size: 9.5, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(tone).fixedSize()
                    }
                    .offset(x: kL * w - 8, y: 15)
                }
            }
            .frame(height: 52)
            .padding(.top, 8)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.theme.hair).frame(height: 1) }
    }

    // ── WHERE PREMIUM LANDS ──
    private var weekdayCard: some View {
        let series = data.incomeByWeekday(range)
        let maxV = max(series.map(\.amount).max() ?? 1, 1)
        let total = series.reduce(0) { $0 + $1.amount }
        let lead = series.max { $0.amount < $1.amount }
        return card {
            Text("Where premium lands").font(.system(size: 19, weight: .heavy)).tracking(-0.5)
                .foregroundStyle(Color.theme.fg1)
            Text("Realized premium on closed calls, grouped by the expiry weekday.")
                .font(.system(size: 12.5)).foregroundStyle(Color.theme.fg3)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 6)

            segmented(IncomeRange.allCases, selection: $range) { $0.rawValue }
                .padding(.top, 16)

            HStack(alignment: .bottom, spacing: 14) {
                ForEach(series, id: \.day) { s in
                    let isLead = s.day == lead?.day && s.amount > 0
                    VStack(spacing: 9) {
                        Text(fmtMoney(s.amount))
                            .font(.numeric(size: 13, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(isLead ? Color.theme.fg1 : Color.theme.fg3)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isLead ? lime : Color.theme.page2)
                            .frame(maxWidth: 72)
                            .frame(height: max(8, CGFloat(s.amount / maxV) * 112))
                        Text(s.day).font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Color.theme.fg2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 165, alignment: .bottom)
            .padding(.top, 22)

            if total > 0, let lead, lead.amount > 0 {
                Text("\(lead.day) expiries carry \(fmtMoney(lead.amount)) of \(fmtMoney(total)) realized — \(Int((lead.amount / total * 100).rounded()))%.")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.theme.fg1)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(lime.opacity(0.35)))
                    .padding(.top, 18)
            }
        }
    }

    // ── HOW CLOSE EACH CALL SAT ──
    private var cushionCard: some View {
        card {
            Text("How close each call sat").font(.system(size: 19, weight: .heavy)).tracking(-0.5)
                .foregroundStyle(Color.theme.fg1)
            Text("Each strike against the share price at expiry. The dot's distance from the black tick is the cushion.")
                .font(.system(size: 12.5)).foregroundStyle(Color.theme.fg3)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 6)

            if data.cushions.isEmpty {
                Text("No calls yet.").font(.system(size: 13)).foregroundStyle(Color.theme.fg4)
                    .padding(.top, 18)
            } else {
                ForEach(data.cushions) { c in
                    gaugeLeg(expiry: c.expiry, strike: c.strike, contracts: c.contracts,
                             price: c.priceAtExpiry, foot: footLabel(c.status),
                             footColor: footColor(c.status))
                }
            }
        }
    }

    private func footLabel(_ s: CallLegStatus) -> String {
        switch s {
        case .open: return "open"
        case .assigned: return "assigned"
        case .rolled: return "rolled"
        case .expired: return "kept"
        }
    }
    private func footColor(_ s: CallLegStatus) -> Color {
        switch s {
        case .open: return Color.theme.fg3
        case .assigned: return Color.theme.gold
        case .rolled: return Color.theme.fg3
        case .expired: return Color.theme.pos
        }
    }

    // ── WHAT THE STRATEGY EARNED ──
    private var returnCard: some View {
        let prem = data.lifetimePremium
        let cap = data.capitalReturn
        let total = data.totalReturn
        let denom = max(abs(prem) + abs(cap), 1)
        return card {
            Text("What the strategy earned").font(.system(size: 19, weight: .heavy)).tracking(-0.5)
                .foregroundStyle(Color.theme.fg1)
            Text("Total return since the first call, split by source.")
                .font(.system(size: 12.5)).foregroundStyle(Color.theme.fg3).padding(.top, 6)

            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 3).fill(Color.theme.fg1)
                    .frame(width: max(4, CGFloat(abs(prem) / denom) * 300))
                RoundedRectangle(cornerRadius: 3).fill(lime)
                    .frame(width: max(4, CGFloat(abs(cap) / denom) * 300))
            }
            .frame(height: 24).frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.top, 20)

            splitRow(Color.theme.fg1, "Premium income", prem)
            splitRow(lime, "Capital (shares)", cap)

            HStack {
                Text("Total return").font(.system(size: 16, weight: .heavy)).tracking(-0.3)
                    .foregroundStyle(Color.theme.fg1)
                Spacer()
                Text(fmtMoney(total, sign: true))
                    .font(.numeric(size: 21, weight: .heavy)).tracking(-0.5)
                    .monospacedDigit().foregroundStyle(Color.signed(total))
            }
            .padding(.top, 16)

            HStack(alignment: .center, spacing: 16) {
                Text("\(String(format: "%.1f", data.annualizedYieldPct))%")
                    .font(.numeric(size: 36, weight: .heavy)).tracking(-1.4)
                    .monospacedDigit().foregroundStyle(Color.theme.fg1)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Spacer(minLength: 0)
                Text("Annualized premium yield on capital at risk")
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.theme.fg3)
                    .multilineTextAlignment(.trailing).frame(maxWidth: 170)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.theme.page2))
            .padding(.top, 20)
        }
    }

    private func splitRow(_ sw: Color, _ label: String, _ v: Double) -> some View {
        HStack {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4).fill(sw).frame(width: 12, height: 12)
                Text(label).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.theme.fg2)
            }
            Spacer()
            Text(fmtMoney(v, sign: true))
                .font(.numeric(size: 15, weight: .heavy)).monospacedDigit()
                .foregroundStyle(Color.signed(v))
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.theme.hair).frame(height: 1) }
    }

    // ── HISTORY ──
    private var historyCard: some View {
        let resolved = data.allLegs
            .filter { $0.status != .open }
            .sorted { $0.expiry > $1.expiry }
        let shown = showAllHistory ? resolved : Array(resolved.prefix(5))
        return card {
            Text("History").font(.system(size: 19, weight: .heavy)).tracking(-0.5)
                .foregroundStyle(Color.theme.fg1)
            Text("Legs recorded as they close.")
                .font(.system(size: 12.5)).foregroundStyle(Color.theme.fg3).padding(.top, 6)

            if resolved.isEmpty {
                Text("Nothing closed yet.").font(.system(size: 13))
                    .foregroundStyle(Color.theme.fg4).padding(.top, 18)
            } else {
                ForEach(shown) { leg in
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(AppDates.shortMonthDay(leg.expiry)) · \(fmtStrike(leg.strike)) call ×\(Int(leg.contracts))")
                                .font(.system(size: 14.5, weight: .heavy)).tracking(-0.3)
                                .foregroundStyle(Color.theme.fg1)
                            Text(historySub(leg.status))
                                .font(.numeric(size: 11.5, weight: .bold)).monospacedDigit()
                                .foregroundStyle(Color.theme.fg4)
                        }
                        Spacer()
                        Text(fmtMoney(leg.premiumPerShare * leg.contracts * 100, sign: true))
                            .font(.numeric(size: 15, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(Color.theme.pos)
                    }
                    .padding(.vertical, 16)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.theme.hair).frame(height: 1) }
                }
                if resolved.count > 5 {
                    Button {
                        withAnimation(Motion.standard) { showAllHistory.toggle() }
                    } label: {
                        Text(showAllHistory ? "Show less" : "Show more")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Color.theme.fg1)
                            .padding(.horizontal, 22).frame(minHeight: 40)
                            .background(Capsule().fill(Color.theme.page2))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                }
            }
        }
    }

    private func historySub(_ s: CallLegStatus) -> String {
        switch s {
        case .assigned: return "assigned · called away"
        case .rolled:   return "rolled"
        case .expired:  return "expired OTM · kept"
        case .open:     return "working"
        }
    }

    // ── chrome ──
    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 26).fill(Color.theme.surface))
            .shadow(color: Color(hex: 0x121E16, alpha: 0.06), radius: 16, x: 0, y: 6)
    }

    /// Pill segmented control — dark active thumb, matching v2.
    private func segmented<T: Hashable & Identifiable>(
        _ items: [T], selection: Binding<T>, label: @escaping (T) -> String
    ) -> some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                let on = selection.wrappedValue == item
                Button {
                    withAnimation(Motion.standard) { selection.wrappedValue = item }
                } label: {
                    Text(label(item))
                        .font(.system(size: 11.5, weight: .bold)).tracking(-0.1)
                        .foregroundStyle(on ? Color.theme.page : Color.theme.fg3)
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity).frame(minHeight: 36)
                        .background(Capsule().fill(on ? Color.theme.fg1 : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.theme.page2))
    }
}
