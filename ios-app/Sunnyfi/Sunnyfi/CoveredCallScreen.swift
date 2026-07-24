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
    var isLong: Bool { self != .calls }
}

private struct PositionDetail: View {
    let data: CoveredCallTicker
    @State private var tab: PosTab = .shares
    /// Group → whether the legs list is expanded, and which leg is drilled into.
    @State private var expanded: Set<PosTab> = []
    @State private var openLeg: [PosTab: Int] = [:]
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
                Text("TOTAL MADE · LIFETIME")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.6)
                    .foregroundStyle(lime)
            }
            // Everything banked plus everything unrealized, with open
            // calls at their mark — a loss has to be unmistakable, so it
            // flips to coral rather than staying white.
            Text(fmtMoney(data.totalReturn, sign: true))
                .font(.system(size: 52, weight: .heavy)).tracking(-2.2)
                .monospacedDigit()
                .foregroundStyle(data.totalReturn < 0 ? Color(hex: 0xF0664F) : .white)
                .minimumScaleFactor(0.5).lineLimit(1)
                .padding(.top, 14)
            Text("\(fmtMoney(data.lifetimePremium, sign: true)) premium collected · \(Int(data.shares).formatted()) \(data.ticker) shares across \(data.cycleCount) cycle\(data.cycleCount == 1 ? "" : "s")")
                .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)

            if cycle != nil {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CURRENT AVERAGE").font(.system(size: 9, weight: .heavy)).tracking(1.1)
                            .foregroundStyle(.white.opacity(0.45))
                        Text(fmtMoney(data.currentAverage, decimals: 2).replacingOccurrences(of: "$", with: ""))
                            .font(.numeric(size: 24, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(lime)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("CURRENT PRICE").font(.system(size: 9, weight: .heavy)).tracking(1.1)
                            .foregroundStyle(.white.opacity(0.45))
                        Text(fmtMoney(data.currentPrice, decimals: 2).replacingOccurrences(of: "$", with: ""))
                            .font(.numeric(size: 24, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(.white)
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

    // ── YOUR POSITION — cards → aggregate → legs → leg detail ──
    private func legs(_ t: PosTab) -> [OpenLegDetail] {
        switch t {
        case .shares:    return []
        case .calls:     return data.callLegs
        case .puts:      return data.putLegs
        case .longCalls: return data.longCallLegs
        }
    }

    private var positionCard: some View {
        card {
            Text("Your position").font(.system(size: 19, weight: .heavy)).tracking(-0.5)
                .foregroundStyle(Color.theme.fg1)
            Text(posMeta).font(.system(size: 12.5)).foregroundStyle(Color.theme.fg3)
                .padding(.top, 6)

            posCards

            if tab == .shares {
                sharesView
            } else if let i = openLeg[tab], i < legs(tab).count {
                legDetailView(legs(tab)[i])
            } else {
                aggregateView
            }
        }
    }

    /// Horizontally-scrolling selector cards, one per position group.
    private var posCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(PosTab.allCases) { t in
                    let on = tab == t
                    Button {
                        withAnimation(Motion.standard) { tab = t; openLeg[t] = nil }
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(t.rawValue.uppercased())
                                .font(.system(size: 10.5, weight: .heavy)).tracking(0.3)
                                .foregroundStyle(Color.theme.fg4)
                            Text(cardValue(t))
                                .font(.numeric(size: 19, weight: .heavy)).tracking(-0.5)
                                .monospacedDigit().foregroundStyle(cardTone(t))
                                .lineLimit(1).minimumScaleFactor(0.6)
                                .padding(.top, 10)
                            Text(cardSub(t))
                                .font(.numeric(size: 11, weight: .bold)).monospacedDigit()
                                .foregroundStyle(Color.theme.fg4).padding(.top, 4)
                        }
                        .padding(13)
                        .frame(width: 134, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16)
                            .fill(on ? Color.theme.surface : Color.theme.page2))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(on ? Color.theme.fg1 : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.top, 16)
    }

    private func cardValue(_ t: PosTab) -> String {
        if t == .shares { return fmtMoney(data.shares * data.currentPrice) }
        return fmtMoney(legs(t).reduce(0) { $0 + $1.pnl }, sign: true)
    }
    private func cardTone(_ t: PosTab) -> Color {
        if t == .shares { return Color.theme.fg1 }
        return Color.signed(legs(t).reduce(0) { $0 + $1.pnl })
    }
    private func cardSub(_ t: PosTab) -> String {
        if t == .shares { return "\(Int(data.shares).formatted()) sh" }
        let n = Int(legs(t).reduce(0) { $0 + $1.contracts })
        return "\(n) contract\(n == 1 ? "" : "s")"
    }

    /// 2-column key/value grid used by every position view.
    private func kvGrid(_ rows: [(String, String, Color, String?)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading),
                            GridItem(.flexible(), alignment: .topLeading)],
                  alignment: .leading, spacing: 20) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                VStack(alignment: .leading, spacing: 7) {
                    Text(r.0).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.theme.fg3)
                    Text(r.1).font(.numeric(size: 21, weight: .heavy)).tracking(-0.5)
                        .monospacedDigit().foregroundStyle(r.2)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let s = r.3, !s.isEmpty {
                        Text(s).font(.numeric(size: 11.5, weight: .bold)).monospacedDigit()
                            .foregroundStyle(r.2 == Color.theme.fg1 ? Color.theme.fg4 : r.2)
                    }
                }
            }
        }
        .padding(.top, 22)
    }

    @ViewBuilder
    private var aggregateView: some View {
        let ls = legs(tab)
        if ls.isEmpty {
            Text("Nothing open here.").font(.system(size: 13))
                .foregroundStyle(Color.theme.fg4).padding(.top, 22)
        } else {
            let qty = ls.reduce(0.0) { $0 + $1.contracts }
            let basis = ls.reduce(0.0) { $0 + $1.basis }
            let mv = ls.reduce(0.0) { $0 + $1.marketValue }
            let pnl = ls.reduce(0.0) { $0 + $1.pnl }
            let tv = ls.reduce(0.0) { $0 + $1.timeValue }
            let th = ls.reduce(0.0) { $0 + $1.theta }
            let sold = (tab == .calls)
            kvGrid([
                ("Contracts", "\(Int(qty)) \(sold ? "sold" : "long")", Color.theme.fg1, nil),
                (sold ? "Premium in" : "Cost basis", fmtMoney(basis),
                 sold ? Color.theme.pos : Color.theme.fg1, nil),
                (sold ? "Cost to close" : "Market value", fmtMoney(mv), Color.theme.fg1, nil),
                ("Open P&L", fmtMoney(pnl, sign: true), Color.signed(pnl), nil),
                ("Time value", fmtMoney(tv), Color.theme.fg1, nil),
                ("Theta", fmtMoney(th, sign: true) + "/day", Color.signed(th), nil),
            ])

            if expanded.contains(tab) {
                Text("LEGS").font(.system(size: 10.5, weight: .heavy)).tracking(1.4)
                    .foregroundStyle(Color.theme.fg4).padding(.top, 24)
                ForEach(Array(ls.enumerated()), id: \.element.id) { i, leg in
                    legRow(leg, index: i)
                }
            } else {
                Button {
                    withAnimation(Motion.standard) { _ = expanded.insert(tab) }
                } label: {
                    HStack(spacing: 3) {
                        Text("Tap for leg details")
                            .font(.system(size: 13, weight: .heavy)).tracking(-0.1)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy))
                    }
                    .foregroundStyle(Color.theme.pos)
                }
                .buttonStyle(.plain)
                .padding(.top, 22)
            }
        }
    }

    private func legRow(_ leg: OpenLegDetail, index: Int) -> some View {
        let mny = moneyness(leg)
        return Button {
            withAnimation(Motion.standard) { openLeg[tab] = index }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(AppDates.shortMonthDay(leg.expiry)) · \(fmtStrike(leg.strike))\(leg.isCall ? "c" : "p")")
                        .font(.system(size: 15, weight: .heavy)).tracking(-0.3)
                        .foregroundStyle(Color.theme.fg1)
                    Text("×\(Int(leg.contracts)) · \(leg.dte) DTE")
                        .font(.numeric(size: 11.5, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Color.theme.fg4)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(fmtMoney(leg.pnl, sign: true))
                        .font(.numeric(size: 15, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(Color.signed(leg.pnl))
                    Text(mny.0).font(.numeric(size: 10.5, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(mny.1)
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.theme.fg4)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Color.theme.hair).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func legDetailView(_ leg: OpenLegDetail) -> some View {
        let sold = !leg.isLong
        let mny = moneyness(leg)
        Button {
            withAnimation(Motion.standard) { openLeg[tab] = nil }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .heavy))
                Text(tab.rawValue).font(.system(size: 12.5, weight: .heavy)).tracking(-0.1)
            }
            .foregroundStyle(Color.theme.fg3)
        }
        .buttonStyle(.plain)
        .padding(.top, 18)

        Text("\(AppDates.shortMonthDay(leg.expiry)) · $\(fmtStrike(leg.strike)) \(leg.isCall ? "call" : "put")")
            .font(.system(size: 20, weight: .heavy)).tracking(-0.5)
            .foregroundStyle(Color.theme.fg1).padding(.top, 12)
        Text("×\(Int(leg.contracts)) \(sold ? "sold" : "long") · \(leg.dte) day\(leg.dte == 1 ? "" : "s") to expiry")
            .font(.numeric(size: 12, weight: .bold)).monospacedDigit()
            .foregroundStyle(Color.theme.fg4).padding(.top, 6)

        kvGrid(sold ? [
            ("Contracts", "\(Int(leg.contracts)) sold", Color.theme.fg1, nil),
            ("Strike", fmtStrike(leg.strike), Color.theme.fg1, nil),
            ("Premium in", fmtMoney(leg.basis), Color.theme.pos, nil),
            ("Time value", fmtMoney(leg.timeValue), Color.theme.fg1, nil),
            ("Theta", fmtMoney(leg.theta, sign: true) + "/day", Color.signed(leg.theta), nil),
            ("Moneyness", mny.0, mny.1, nil),
            ("Open P&L", fmtMoney(leg.pnl, sign: true), Color.signed(leg.pnl), nil),
        ] : [
            ("Contracts", "\(Int(leg.contracts)) long", Color.theme.fg1, nil),
            ("Strike", fmtStrike(leg.strike), Color.theme.fg1, nil),
            ("Cost basis", fmtMoney(leg.basis), Color.theme.fg1, nil),
            ("Market value", fmtMoney(leg.marketValue), Color.theme.fg1, nil),
            ("Intrinsic", fmtMoney(leg.intrinsic), Color.theme.fg1, nil),
            ("Time value", fmtMoney(leg.timeValue), Color.theme.fg1, nil),
            ("Theta", fmtMoney(leg.theta, sign: true) + "/day", Color.signed(leg.theta), nil),
            ("Open P&L", fmtMoney(leg.pnl, sign: true), Color.signed(leg.pnl), nil),
        ])
    }

    private func moneyness(_ leg: OpenLegDetail) -> (String, Color) {
        let px = data.currentPrice
        guard px > 0 else { return ("—", Color.theme.fg3) }
        if leg.isCall {
            let m = (leg.strike - px) / px * 100
            let tone: Color = m >= 0.8 ? Color.theme.pos : (m <= -0.2 ? Color.theme.neg : Color.theme.warn)
            let lab = m >= 0.8 ? "OTM" : (m <= -0.2 ? "ITM" : "ATM")
            return ("\(lab) \(m >= 0 ? "+" : "−")\(String(format: "%.1f", abs(m)))%", tone)
        }
        return ("\(String(format: "%.0f", (px - leg.strike) / px * 100))% below", Color.theme.fg3)
    }

    private var posMeta: String {
        switch tab {
        case .shares:
            return "\(Int(data.shares).formatted()) shares · covered"
        case .calls:
            let n = Int(data.openCallContracts)
            return "\(n) contract\(n == 1 ? "" : "s") open · \(data.callLegs.count) expir\(data.callLegs.count == 1 ? "y" : "ies")"
        case .puts:
            let n = Int(data.putContracts)
            return "\(n) protective put\(n == 1 ? "" : "s")"
        case .longCalls:
            let n = Int(data.longCallLegs.reduce(0) { $0 + $1.contracts })
            return "\(n) long call\(n == 1 ? "" : "s") · LEAP overlay"
        }
    }

    private var sharesView: some View {
        let c = cycle
        return kvGrid([
            ("Shares", Int(data.shares).formatted(), Color.theme.fg1, nil),
            ("Market value", fmtMoney(data.shares * data.currentPrice), Color.theme.fg1, nil),
            ("Cost basis", fmtMoney(c?.entryPrice ?? 0, decimals: 2), Color.theme.fg1, nil),
            ("Adjusted basis", fmtMoney(c?.adjustedBasis ?? 0, decimals: 2), Color.theme.pos,
             c.map { $0.entryPrice > 0 ? String(format: "%.1f%% via premium", -$0.premiumPerShare / $0.entryPrice * 100) : "" }),
            ("Today's return", fmtMoney(data.todayPL, sign: true), Color.signed(data.todayPL), fmtPct(data.dayPct)),
            ("Total return", fmtMoney(data.totalReturn, sign: true), Color.signed(data.totalReturn),
             c.map { $0.entryPrice * $0.shares > 0 ? fmtPct(data.totalReturn / ($0.entryPrice * $0.shares) * 100) : "" }),
        ])
    }

    // ── Cushion gauge — updated v2: thin rail, tall "now" tick with the
    // label above it, strike dot labelled below, large moneyness pill.
    private func gaugeLeg(expiry: String, strike: Double, contracts: Double,
                          price: Double, foot: String, footColor: Color) -> some View {
        let m = price > 0 ? (strike - price) / price * 100 : 0
        let tone: Color = m >= 0.8 ? Color.theme.pos : (m <= -0.2 ? Color.theme.neg : Color.theme.warn)
        let label = m >= 0.8 ? "OTM" : (m <= -0.2 ? "ITM" : "ATM")
        let pxL: CGFloat = 0.40
        let kL: CGFloat = max(0.09, min(0.91, pxL + CGFloat(m / 6.5) * 0.44))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(AppDates.shortMonthDay(expiry)) · \(fmtStrike(strike)) call")
                        .font(.system(size: 15, weight: .heavy)).tracking(-0.3)
                        .foregroundStyle(Color.theme.fg1)
                    Text("×\(Int(contracts)) · \(foot)")
                        .font(.numeric(size: 11.5, weight: .bold)).monospacedDigit()
                        .foregroundStyle(footColor)
                }
                Spacer(minLength: 0)
                Text("\(label) \(m >= 0 ? "+" : "−")\(String(format: "%.1f", abs(m)))%")
                    .font(.numeric(size: 13, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(tone)
                    .padding(.horizontal, 15).padding(.vertical, 8)
                    .background(Capsule().fill(tone.opacity(0.13)))
                    .fixedSize()
            }

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    // rail + cushion zone
                    Capsule().fill(Color.theme.page2)
                        .frame(width: w, height: 3).position(x: w / 2, y: 22)
                    Capsule().fill(tone.opacity(0.45))
                        .frame(width: abs(kL - pxL) * w, height: 3)
                        .position(x: (min(pxL, kL) + abs(kL - pxL) / 2) * w, y: 22)
                    // "now" tick, label above
                    VStack(spacing: 3) {
                        Text("now \(String(format: "%.2f", price))")
                            .font(.numeric(size: 10.5, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(Color.theme.fg1).fixedSize()
                        RoundedRectangle(cornerRadius: 2).fill(Color.theme.fg1)
                            .frame(width: 3, height: 28)
                    }
                    .position(x: pxL * w, y: 24)
                    // strike dot, label below
                    VStack(spacing: 6) {
                        Circle().fill(tone).frame(width: 16, height: 16)
                        Text("$\(fmtStrike(strike))")
                            .font(.numeric(size: 11, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(tone).fixedSize()
                    }
                    .position(x: kL * w, y: 31)
                }
            }
            .frame(height: 58)
            .padding(.top, 22)
        }
        .padding(.top, 20).padding(.bottom, 30)
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
        let prem = data.premiumIncome     // premium collected (income)
        let cap = data.capitalReturn      // realized + unrealized share P&L + puts
        let total = data.totalReturn
        let denom = max(abs(prem) + abs(cap), 1)
        return card {
            Text("What the strategy earned").font(.system(size: 19, weight: .heavy)).tracking(-0.5)
                .foregroundStyle(Color.theme.fg1)
            Text("Premium is income; shares are marked at price vs your average.")
                .font(.system(size: 12.5)).foregroundStyle(Color.theme.fg3)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 6)

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
                Text("(\(fmtPct(data.totalReturnPct)))")
                    .font(.numeric(size: 12, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Color.signed(total))
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
        // One row per resolved strike, NET of buybacks (a rolled strike
        // can read negative), so it reconciles with the total above.
        let resolved = data.allRollups
            .filter { $0.status != .open }
            .sorted { $0.expiry > $1.expiry }
        let shown = showAllHistory ? resolved : Array(resolved.prefix(5))
        return card {
            Text("History").font(.system(size: 19, weight: .heavy)).tracking(-0.5)
                .foregroundStyle(Color.theme.fg1)
            Text("Each strike as it resolved, net of buybacks.")
                .font(.system(size: 12.5)).foregroundStyle(Color.theme.fg3).padding(.top, 6)

            if resolved.isEmpty {
                Text("Nothing closed yet.").font(.system(size: 13))
                    .foregroundStyle(Color.theme.fg4).padding(.top, 18)
            } else {
                ForEach(shown) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(AppDates.shortMonthDay(r.expiry)) · \(fmtStrike(r.strike)) call ×\(Int(r.contracts))")
                                .font(.system(size: 14.5, weight: .heavy)).tracking(-0.3)
                                .foregroundStyle(Color.theme.fg1)
                            Text(historySub(r.status) + (r.buyback > 0 ? " · \(fmtMoney(r.buyback)) bought back" : ""))
                                .font(.numeric(size: 11.5, weight: .bold)).monospacedDigit()
                                .foregroundStyle(Color.theme.fg4)
                        }
                        Spacer()
                        Text(fmtMoney(r.net, sign: true))
                            .font(.numeric(size: 15, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(Color.signed(r.net))
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
