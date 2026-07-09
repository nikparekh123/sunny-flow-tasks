//
//  IncomeDetailView.swift
//  Sunnyfi
//
//  The "Income" segment of Trades — a per-ticker live monitoring view
//  for the buy-write strategy (design_handoff_meta_detail, v3). Opened
//  from the ticker switcher at the top; shows, in order:
//
//    1. Position header — shares, avg, and the "average after premium"
//       heartbeat + unrealized (the anchor).
//    2. "What changed" brief — a one-line intelligence read generated
//       from live IV / moneyness / DTE / kept-streak.
//    3. Open call · working — the assignment fork (assign vs keep).
//    4. Premium yield — this week / month / annualized + weekly bars.
//    5. Exercise streak — kept/called-away history.
//
//  Coexists with the classic Positions segment until the strategy is
//  fully proven, then Positions retires. All numbers are LIVE (see
//  IncomeDetailData); history cards render sparse until trades accrue.
//

import SwiftUI

struct IncomeStrategyView: View {
    let store: PortfolioStore
    @State private var selected: String?

    private var tickers: [String] { IncomeDetail.eligibleTickers(store: store) }

    private var activeTicker: String? {
        if let selected, tickers.contains(selected) { return selected }
        return tickers.first
    }

    var body: some View {
        Group {
            if tickers.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        switcher
                        if let t = activeTicker,
                           let detail = IncomeDetail.compute(store: store, ticker: t) {
                            IncomeDetailBody(detail: detail)
                        }
                        Color.clear.frame(height: 120)   // clear tab bar
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }
            }
        }
    }

    private var switcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tickers, id: \.self) { t in
                    let on = activeTicker == t
                    Button {
                        withAnimation(Motion.standard) { selected = t }
                    } label: {
                        Text(t)
                            .font(.system(size: 15, weight: .bold))
                            .tracking(-0.1)
                            .foregroundStyle(on ? Color.theme.onNeon : Color.theme.fg2)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 42)
                            .background(
                                Capsule()
                                    .fill(on ? Color.theme.neon : Color.theme.surface)
                                    .overlay(Capsule().strokeBorder(
                                        on ? Color.clear : Color.theme.borderBright, lineWidth: 1))
                            )
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No share positions yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.theme.fg2)
            Text("The Income view tracks your buy-write book. It appears once you hold shares.")
                .font(.system(size: 13))
                .foregroundStyle(Color.theme.fg3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Body (one ticker)

private struct IncomeDetailBody: View {
    let detail: IncomeDetail

    var body: some View {
        VStack(spacing: 14) {
            positionHeader
            briefCard
            if let call = detail.call { openCallCard(call) }
            yieldCard
            streakCard
        }
    }

    // MARK: 1 · Position header (the heartbeat — on page, no card)

    private var positionHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                Text(detail.ticker)
                    .font(.system(size: 34, weight: .heavy))
                    .tracking(-1.3)
                    .foregroundStyle(Color.theme.fg1)
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(fmtMoney(detail.spot, decimals: 2))
                        .font(.numeric(size: 18, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.theme.fg1)
                    Text(fmtPct(detail.dayPct) + " today")
                        .font(.numeric(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.signed(detail.dayPct))
                }
            }

            // avg after premium — the strategy's heartbeat
            HStack(alignment: .center, spacing: 10) {
                Text(fmtMoney(detail.rawAvg, decimals: 2))
                    .font(.numeric(size: 14, weight: .medium))
                    .monospacedDigit()
                    .strikethrough(true, color: Color.theme.fg4)
                    .foregroundStyle(Color.theme.fg3)
                Text("→").font(.system(size: 13)).foregroundStyle(Color.theme.fg4)
                Text(fmtMoney(detail.effectiveAvg, decimals: 2))
                    .font(.numeric(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.theme.pos)
                Text("AVG AFTER\nPREMIUM")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.theme.fg4)
                    .lineSpacing(1)
                Spacer(minLength: 0)
                if detail.premiumDrop > 0.005 {
                    Text("▼ " + fmtMoney(detail.premiumDrop, decimals: 2))
                        .font(.numeric(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.theme.pos)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Color.theme.tintPos))
                }
            }
            .padding(.top, 18)

            Text(sharesLine)
                .font(.numeric(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.theme.fg4)
                .padding(.top, 12)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sharesLine: AttributedString {
        var s = AttributedString("\(Int(detail.shares).formatted()) shares · \(fmtMoney(detail.marketValue)) value · ")
        var pnl = AttributedString(fmtMoney(detail.unrealized, sign: true) + " unrealized")
        pnl.foregroundColor = Color.signed(detail.unrealized)
        s.append(pnl)
        return s
    }

    // MARK: 2 · "What changed" brief

    private var briefCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(Color.theme.gold).frame(width: 6, height: 6)
                Text("WHAT CHANGED")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(Color.theme.gold)
            }
            Text(briefText)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(Color.theme.fg2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .incomeCard()
    }

    private var briefText: String {
        var parts: [String] = []
        if let iv = detail.ivPct {
            if let rank = detail.ivRank {
                let rich = rank >= 60 ? " — premium is running rich" : rank <= 25 ? " — premium is thin" : ""
                parts.append("Implied vol is \(Int(iv.rounded()))% (rank \(Int(rank.rounded())))\(rich).")
            } else {
                parts.append("Implied vol is \(Int(iv.rounded()))%.")
            }
        }
        if let call = detail.call {
            if call.otmDollars > 0 {
                parts.append("Your $\(fmt0(call.strike)) call is \(fmtMoney(call.otmDollars, decimals: 2)) out-of-the-money with \(call.dte) day\(call.dte == 1 ? "" : "s") left — on track to keep the shares and ratchet your average lower.")
            } else if call.otmDollars < 0 {
                parts.append("Your $\(fmt0(call.strike)) call is \(fmtMoney(-call.otmDollars, decimals: 2)) in-the-money with \(call.dte) day\(call.dte == 1 ? "" : "s") left — assignment looks likely. If it's above your average, that's a clean win.")
            } else {
                parts.append("Your $\(fmt0(call.strike)) call is right at the money with \(call.dte) day\(call.dte == 1 ? "" : "s") left — a coin-flip into expiry.")
            }
        } else {
            parts.append("No call is working right now — sell one to start collecting premium against these shares.")
        }
        return parts.joined(separator: " ")
    }

    // MARK: 3 · Open call · working (the assignment fork)

    private func openCallCard(_ call: IncomeDetail.OpenCall) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OPEN CALL · WORKING")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Color.theme.gold)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("$\(fmt0(call.strike)) call ×\(Int(call.contracts))")
                        .font(.system(size: 22, weight: .heavy))
                        .tracking(-0.5)
                        .monospacedDigit()
                        .foregroundStyle(Color.theme.fg1)
                    Text("sold \(call.soldWeekday) · \(fmtMoney(call.premiumCollected)) premium banked")
                        .font(.numeric(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.theme.fg3)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(call.dte)d")
                        .font(.numeric(size: 20, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.theme.gold)
                    Text("\(call.expiryWeekday.uppercased()) EXP")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Color.theme.fg4)
                }
            }
            .padding(.top, 16)

            moneynessTrack(call)
                .padding(.top, 22)

            // assignment fork
            HStack(spacing: 0) {
                forkCell(
                    prob: call.assignProb,
                    probLabel: "ASSIGN",
                    title: "If assigned",
                    value: fmtMoney(call.ifAssigned, sign: true),
                    valueColor: Color.signed(call.ifAssigned)
                )
                Rectangle().fill(Color.theme.hair).frame(width: 0.5, height: 54)
                forkCell(
                    prob: call.assignProb.map { 100 - $0 },
                    probLabel: "KEEP",
                    title: "If it expires",
                    value: fmtMoney(call.ifKeptAvg, decimals: 2),
                    valueColor: Color.theme.fg1
                )
            }
            .padding(.top, 20)
            .padding(.top, 2)
        }
        .incomeCard()
    }

    private func forkCell(prob: Int?, probLabel: String, title: String,
                          value: String, valueColor: Color) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(prob.map { "\($0)%" } ?? "—")
                    .font(.numeric(size: 17, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.theme.fg2)
                Text(probLabel)
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.theme.fg4)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.theme.fg1)
                Text(value)
                    .font(.numeric(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private func moneynessTrack(_ call: IncomeDetail.OpenCall) -> some View {
        let spot = detail.spot
        let strike = call.strike
        let lo = min(spot, strike) * 0.985
        let hi = max(spot, strike) * 1.015
        let span = max(hi - lo, 0.01)
        let priceFrac = min(1, max(0, (spot - lo) / span))
        let strikeFrac = min(1, max(0, (strike - lo) / span))
        let otm = call.otmDollars > 0
        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                labeled("PRICE", fmtMoney(spot, decimals: 2), .leading)
                Spacer()
                labeled("STRIKE", fmtMoney(strike, decimals: 2), .trailing)
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.theme.page2).frame(height: 8)
                    // cushion between price and strike
                    Capsule().fill(otm ? Color.theme.tintPos : Color.theme.tintNeg)
                        .frame(width: abs(strikeFrac - priceFrac) * w, height: 8)
                        .offset(x: min(priceFrac, strikeFrac) * w)
                    marker(color: Color.theme.fg1).offset(x: priceFrac * w - 1.5)
                    marker(color: Color.theme.neon).offset(x: strikeFrac * w - 1.5)
                }
            }
            .frame(height: 18)
            Text(cushionCaption(call))
                .font(.numeric(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(otm ? Color.theme.pos : Color.theme.neg)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func cushionCaption(_ call: IncomeDetail.OpenCall) -> String {
        if call.otmDollars > 0 {
            return "\(fmtMoney(call.otmDollars, decimals: 2)) OTM · \(String(format: "%.1f", abs(call.cushionPct)))% cushion to assignment"
        } else if call.otmDollars < 0 {
            return "\(fmtMoney(-call.otmDollars, decimals: 2)) ITM · assignment likely"
        }
        return "At the money"
    }

    private func marker(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 3, height: 18)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.theme.surface, lineWidth: 2.5))
    }

    // MARK: 4 · Premium yield

    private var yieldCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PREMIUM YIELD · \(detail.ticker)")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Color.theme.fg3)

            HStack(alignment: .firstTextBaseline, spacing: 22) {
                yieldStat(fmtMoney(detail.premThisWeek), "this week", Color.theme.fg1)
                yieldStat(fmtMoney(detail.premThisMonth), "this month", Color.theme.fg1)
                yieldStat("\(Int(detail.annualizedPct.rounded()))%", "annualized", Color.theme.neon)
            }
            .padding(.top, 18)

            weeklyBars.padding(.top, 24)

            // footer: harvested + IV
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("HARVESTED")
                        .font(.system(size: 9, weight: .bold)).tracking(1)
                        .foregroundStyle(Color.theme.fg3)
                    Text(fmtK(detail.lifetimeHarvested).replacingOccurrences(of: "+", with: ""))
                        .font(.numeric(size: 18, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Color.theme.fg1)
                    Text("\(detail.expiryCount) call\(detail.expiryCount == 1 ? "" : "s") sold")
                        .font(.numeric(size: 10.5, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Color.theme.fg3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Color.theme.hair).frame(width: 0.5, height: 52)
                VStack(alignment: .leading, spacing: 8) {
                    Text("IMPLIED VOL")
                        .font(.system(size: 9, weight: .bold)).tracking(1)
                        .foregroundStyle(Color.theme.fg3)
                    Text(detail.ivPct.map { "\(Int($0.rounded()))%" } ?? "—")
                        .font(.numeric(size: 18, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Color.theme.gold)
                    Text(detail.ivRank.map { "rank \(Int($0.rounded()))" } ?? "no history yet")
                        .font(.numeric(size: 10.5, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Color.theme.fg3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 20)
            .overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 0.5) }
        }
        .incomeCard()
    }

    private func yieldStat(_ v: String, _ k: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(v).font(.numeric(size: 24, weight: .bold)).tracking(-0.6)
                .monospacedDigit().foregroundStyle(color)
            Text(k).font(.numeric(size: 10, weight: .medium)).foregroundStyle(Color.theme.fg3)
        }
    }

    private var weeklyBars: some View {
        let maxPrem = max(detail.weeks.map(\.premium).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 9) {
            ForEach(detail.weeks) { w in
                VStack(spacing: 7) {
                    Circle()
                        .fill(w.assigned ? Color.theme.gold : Color.clear)
                        .frame(width: 5, height: 5)
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(w.isCurrent ? Color.theme.neon
                              : w.assigned ? Color.theme.neon.opacity(0.5)
                              : Color.theme.pos.opacity(0.35))
                        .frame(height: max(6, CGFloat(w.premium / maxPrem) * 70))
                    Text(w.label)
                        .font(.system(size: 9, weight: w.isCurrent ? .bold : .medium))
                        .foregroundStyle(w.isCurrent ? Color.theme.neon : Color.theme.fg4)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 108)
    }

    // MARK: 5 · Exercise streak

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("EXERCISE STREAK · \(detail.ticker)")
                    .font(.system(size: 10, weight: .bold)).tracking(1.6)
                    .foregroundStyle(Color.theme.fg3)
                Spacer()
                Text("\(detail.history.count) expir\(detail.history.count == 1 ? "y" : "ies")")
                    .font(.numeric(size: 10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Color.theme.fg4)
            }

            if detail.history.isEmpty {
                Text("No resolved expiries yet. Each call that expires or gets called away logs here — kept drops your average, called-away books a realized win.")
                    .font(.system(size: 13)).lineSpacing(3)
                    .foregroundStyle(Color.theme.fg3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            } else {
                streakStrip.padding(.top, 18)
                Text(streakCaption)
                    .font(.numeric(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Color.theme.fg3)
                    .padding(.top, 14)
                VStack(spacing: 0) {
                    ForEach(detail.history) { h in logRow(h) }
                }
                .padding(.top, 8)
            }
        }
        .incomeCard()
    }

    private var streakStrip: some View {
        // oldest → newest
        let ordered = Array(detail.history.reversed())
        return HStack(spacing: 3) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { idx, h in
                RoundedRectangle(cornerRadius: 4)
                    .fill(h.exercised ? Color.theme.gold : Color.theme.tintPos)
                    .frame(height: 24)
                    .overlay {
                        if idx == ordered.count - 1 {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.theme.pos, lineWidth: 2)
                        }
                    }
            }
        }
    }

    private var streakCaption: AttributedString {
        var s = AttributedString("")
        if let days = detail.daysSinceExercise {
            var d = AttributedString("\(days) day\(days == 1 ? "" : "s")")
            d.foregroundColor = Color.theme.pos
            s.append(d); s.append(AttributedString(" since last called away · "))
        }
        var k = AttributedString("kept \(detail.keptStreak) in a row")
        k.foregroundColor = Color.theme.pos
        s.append(k)
        return s
    }

    private func logRow(_ h: IncomeDetail.ExpiryOutcome) -> some View {
        HStack(spacing: 13) {
            Text(h.exercised ? "Called away" : "Kept")
                .font(.system(size: 9, weight: .bold)).tracking(0.6)
                .foregroundStyle(h.exercised ? Color.theme.gold : Color.theme.pos)
                .frame(width: 88)
                .padding(.vertical, 6)
                .background(Capsule().fill(h.exercised ? Color.theme.tintWarn : Color.theme.tintPos))
            VStack(alignment: .leading, spacing: 5) {
                Text("\(h.weekday) · $\(fmt0(h.strike)) call")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.theme.fg1)
                Text(h.exercised ? "called away — realized win" : "expired OTM — shares held")
                    .font(.numeric(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Color.theme.fg3)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                if h.exercised {
                    Text(fmtMoney(h.realized ?? 0, sign: true))
                        .font(.numeric(size: 15, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Color.signed(h.realized ?? 0))
                    Text("REALIZED").font(.system(size: 8.5, weight: .semibold))
                        .tracking(0.5).foregroundStyle(Color.theme.fg4)
                } else {
                    Text(fmtMoney(h.avgAfter ?? 0, decimals: 2))
                        .font(.numeric(size: 15, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Color.theme.fg1)
                    Text("AVG AFTER").font(.system(size: 8.5, weight: .semibold))
                        .tracking(0.5).foregroundStyle(Color.theme.fg4)
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 0.5) }
    }

    // MARK: helpers

    private func labeled(_ k: String, _ v: String, _ align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 5) {
            Text(k).font(.system(size: 10, weight: .medium)).tracking(0.3)
                .foregroundStyle(Color.theme.fg3)
            Text(v).font(.numeric(size: 13, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Color.theme.fg2)
        }
    }

    private func fmt0(_ v: Double) -> String {
        Int(v.rounded()).formatted(.number.grouping(.automatic))
    }
}

// MARK: - Card chrome

private extension View {
    /// White (light) / teal (dark) rounded card with a hairline and a
    /// soft shadow — the income screen's card surface.
    func incomeCard() -> some View {
        self
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Color.theme.hair, lineWidth: 0.5))
                    .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 6)
            )
    }
}
