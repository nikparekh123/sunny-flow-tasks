//
//  IncomeDetailView.swift
//  Sunnyfi
//
//  The "Income" segment of Trades — a per-ticker live monitoring view
//  for the buy-write strategy. Recreates design_handoff_meta_detail
//  "META Detail v3.html" (the primary design) 1:1 in SwiftUI, using the
//  app's own tokens. Order, top → bottom:
//
//    • Ticker switcher (share book)
//    1. Position header — shares, avg, and the "average after premium"
//       heartbeat + unrealized (on the page, no card).
//    2. "What changed" brief — one-line intelligence read.
//    3. Open call · working — moneyness track + 3 stats
//       (Assign odds / Premium in / If kept).
//    4. Premium yield — this week / month / annualized + weekly bars.
//    5. Exercise streak — kept / exercised history.
//
//  Coexists with the classic Positions segment until the strategy is
//  proven, then Positions retires. All numbers are LIVE (see
//  IncomeDetailData); history cards render sparse until trades accrue.
//
//  Spec constants (from the v3 handoff): content inset 20, inter-card
//  gap 16, card radius 26, card padding 22, two-layer soft shadow.
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
                    VStack(spacing: 16) {
                        switcher
                        if let t = activeTicker,
                           let detail = IncomeDetail.compute(store: store, ticker: t) {
                            IncomeDetailBody(detail: detail)
                        }
                        Color.clear.frame(height: 120)   // clear tab bar
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
        }
    }

    // Horizontally scrollable pill strip — matches v3 `.tk`: 42pt min
    // height, card fill + hair border (fg3 text) unselected; accent
    // fill + white + soft shadow selected.
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
                            .tracking(-0.15)
                            .foregroundStyle(on ? Color.theme.onNeon : Color.theme.fg3)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 42)
                            .background(
                                Capsule()
                                    .fill(on ? Color.theme.neon : Color.theme.surface)
                                    .overlay(Capsule().strokeBorder(
                                        on ? Color.clear : Color.theme.hair, lineWidth: 1))
                            )
                            .shadow(color: on ? Color.theme.neon.opacity(0.26) : .clear,
                                    radius: 6, x: 0, y: 3)
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
        VStack(spacing: 16) {
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
                    .tracking(-1.36)                      // -.04em × 34
                    .foregroundStyle(Color.theme.fg1)
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(fmtMoney(detail.spot, decimals: 2))
                        .font(.numeric(size: 18, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.theme.fg1)
                    Text(dayChangeText)
                        .font(.numeric(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.signed(detail.dayPct))
                }
            }

            // avg after premium — the strategy's heartbeat. Clustered
            // left (raw → arrow → eff → label → drop) per v3 `.pos-avg`.
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
                if detail.premiumDrop > 0.005 {
                    Text("▼ " + fmtMoney(detail.premiumDrop, decimals: 2))
                        .font(.numeric(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.theme.pos)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Color.theme.tintPos))
                }
                Spacer(minLength: 0)
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

    private var dayChangeText: String {
        let g = detail.dayPct < 0 ? "▼ " : detail.dayPct > 0 ? "▲ " : ""
        return g + String(format: "%.1f", abs(detail.dayPct)) + "% today"
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

    /// Generated from live IV / moneyness / DTE, with colored emphasis
    /// per v3 (gold for vol, pos for the OTM figure, ink for the call).
    private var briefText: AttributedString {
        func em(_ t: String, _ c: Color) -> AttributedString {
            var a = AttributedString(t); a.foregroundColor = c
            a.font = .system(size: 15, weight: .semibold); return a
        }
        var out = AttributedString("")
        if let iv = detail.ivPct {
            out.append(AttributedString("Implied vol is "))
            out.append(em("\(Int(iv.rounded()))%", Color.theme.gold))
            if let rank = detail.ivRank, ivRankMature {
                out.append(AttributedString(" (rank \(Int(rank.rounded())))"))
                if rank >= 60 { out.append(AttributedString(" — premium is running rich")) }
                else if rank <= 25 { out.append(AttributedString(" — premium is thin")) }
            } else {
                out.append(AttributedString(" — its range is still building, so no rank yet"))
            }
            out.append(AttributedString(". "))
        }
        if let call = detail.call {
            out.append(AttributedString("Your "))
            out.append(em("$\(fmtStrike(call.strike)) call", Color.theme.fg1))
            if call.otmDollars > 0 {
                out.append(AttributedString(" is "))
                out.append(em(fmtMoney(call.otmDollars, decimals: 2) + " out-of-the-money", Color.theme.pos))
                out.append(AttributedString(" with \(call.dte) day\(call.dte == 1 ? "" : "s") left — on track to keep the shares and ratchet your average lower."))
            } else if call.otmDollars < 0 {
                out.append(AttributedString(" is "))
                out.append(em(fmtMoney(-call.otmDollars, decimals: 2) + " in-the-money", Color.theme.neg))
                out.append(AttributedString(" with \(call.dte) day\(call.dte == 1 ? "" : "s") left — assignment looks likely. Above your average, that's a clean win."))
            } else {
                out.append(AttributedString(" is right at the money with \(call.dte) day\(call.dte == 1 ? "" : "s") left — a coin-flip into expiry."))
            }
        } else {
            out.append(AttributedString("No call is working right now — sell one to start collecting premium against these shares."))
        }
        return out
    }

    // MARK: 3 · Open call · working

    private func openCallCard(_ call: IncomeDetail.OpenCall) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OPEN CALL · WORKING")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Color.theme.gold)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("$\(fmtStrike(call.strike)) call ×\(Int(call.contracts))")
                        .font(.system(size: 22, weight: .heavy))
                        .tracking(-0.66)
                        .monospacedDigit()
                        .foregroundStyle(Color.theme.fg1)
                    Text("sold \(call.soldWeekday) · \(fmtMoney(call.premiumCollected)) premium banked")
                        .font(.numeric(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.theme.fg3)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(call.dte)d")
                        .font(.numeric(size: 20, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.theme.gold)
                    Text("\(call.expiryWeekday.uppercased()) EXPIRY")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Color.theme.fg4)
                }
            }
            .padding(.top, 16)

            moneynessTrack(call)
                .padding(.top, 24)

            // 3 stats (v3 `.call-stats`) — Assign odds / Premium in / If kept
            HStack(alignment: .top, spacing: 4) {
                stat("ASSIGN ODDS",
                     call.assignProb.map { "\($0)%" } ?? "—",
                     Color.theme.gold,
                     call.delta.map { String(format: "%.2f", abs($0)) + "Δ" } ?? "no greek yet")
                stat("PREMIUM IN",
                     fmtMoney(call.premiumCollected),
                     Color.theme.pos,
                     fmtMoney(call.contracts > 0 ? call.premiumCollected / (call.contracts * 100) : 0, decimals: 2) + " / sh")
                stat("IF KEPT",
                     fmtMoney(call.ifKeptAvg, decimals: 2),
                     Color.theme.fg1,
                     "new avg")
            }
            .padding(.top, 22)
            .overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 0.5) }
        }
        .incomeCard()
    }

    private func stat(_ k: String, _ v: String, _ vColor: Color, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(k).font(.system(size: 9, weight: .semibold)).tracking(1)
                .foregroundStyle(Color.theme.fg3)
            Text(v).font(.numeric(size: 19, weight: .bold)).tracking(-0.57)
                .monospacedDigit().foregroundStyle(vColor)
            Text(s).font(.numeric(size: 10, weight: .medium)).monospacedDigit()
                .foregroundStyle(Color.theme.fg4)
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Capsule().fill(otm ? Color.theme.pos.opacity(0.22) : Color.theme.neg.opacity(0.22))
                        .frame(width: abs(strikeFrac - priceFrac) * w, height: 8)
                        .offset(x: min(priceFrac, strikeFrac) * w)
                    moneyMarker(color: Color.theme.fg1, frac: priceFrac, w: w)
                    moneyMarker(color: Color.theme.neon, frac: strikeFrac, w: w)
                }
            }
            .frame(height: 20)
            Text(cushionCaption(call))
                .font(.numeric(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(otm ? Color.theme.pos : Color.theme.neg)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func cushionCaption(_ call: IncomeDetail.OpenCall) -> String {
        if call.otmDollars > 0 {
            return "\(fmtMoney(call.otmDollars, decimals: 2)) out-of-the-money · \(String(format: "%.1f", abs(call.cushionPct)))% cushion to assignment"
        } else if call.otmDollars < 0 {
            return "\(fmtMoney(-call.otmDollars, decimals: 2)) in-the-money · assignment likely"
        }
        return "At the money"
    }

    /// Price / strike marker on the moneyness track — a thin colored
    /// bar with a card-colored halo so it pops against the cushion
    /// (v3 `box-shadow: 0 0 0 3px var(--card)`). The halo is drawn
    /// BEHIND the bar, not as an inset border, so the fill stays visible.
    private func moneyMarker(color: Color, frac: CGFloat, w: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(Color.theme.surface)
                .frame(width: 9, height: 20)
            RoundedRectangle(cornerRadius: 2).fill(color)
                .frame(width: 3, height: 18)
        }
        .offset(x: frac * w - 4.5)
    }

    // MARK: 4 · Premium yield

    private var yieldCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PREMIUM YIELD · \(detail.ticker)")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(Color.theme.fg3)
                Spacer()
                HStack(spacing: 6) {
                    PulsingDot()
                    Text("live").font(.numeric(size: 10, weight: .medium))
                        .foregroundStyle(Color.theme.fg4)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 22) {
                yieldStat(fmtMoney(detail.premThisWeek), "this week", Color.theme.fg1)
                yieldStat(fmtMoney(detail.premThisMonth), "this month", Color.theme.fg1)
                yieldStat("\(Int(detail.annualizedPct.rounded()))%", "annualized", Color.theme.neon)
            }
            .padding(.top, 18)

            weeklyBars.padding(.top, 24)
            weeklyLegend.padding(.top, 20)

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
                    Text(ivSubText)
                        .font(.numeric(size: 10.5, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Color.theme.fg3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 22)
            .overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 0.5) }
        }
        .incomeCard()
    }

    /// The IV rank is only trustworthy once ~40+ days of IV history
    /// have accumulated — before that a ticker pins to rank 0/100
    /// trivially (current == window high/low). We keep the IV *level*
    /// (it's a live read) but suppress the rank + rich/thin verdict.
    private var ivRankMature: Bool {
        detail.ivRank != nil && (detail.ivWindowDays ?? 0) >= 40
    }

    private var ivSubText: String {
        guard let rank = detail.ivRank, ivRankMature else { return "range building" }
        let tail = rank >= 60 ? " · running rich" : rank <= 25 ? " · thin" : ""
        return "rank \(Int(rank.rounded()))\(tail)"
    }

    private func yieldStat(_ v: String, _ k: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(v).font(.numeric(size: 24, weight: .bold)).tracking(-0.84)
                .monospacedDigit().foregroundStyle(color)
            Text(k).font(.numeric(size: 10, weight: .medium)).foregroundStyle(Color.theme.fg3)
        }
    }

    // Weekly bars — v3: normal weeks grey (page-2), "now" = accent,
    // "assigned" = accent @ 50%. Height 30 + ratio×44. Bar width ≤ 30.
    // Gold dot atop assigned weeks.
    private var weeklyBars: some View {
        let maxPrem = max(detail.weeks.map(\.premium).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 9) {
            ForEach(detail.weeks) { w in
                VStack(spacing: 7) {
                    Circle()
                        .fill(w.assigned ? Color.theme.gold : Color.clear)
                        .frame(width: 5, height: 5)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(w.isCurrent ? Color.theme.neon
                              : w.assigned ? Color.theme.neon.opacity(0.5)
                              : Color.theme.page2)
                        .frame(maxWidth: 30)
                        .frame(height: 30 + CGFloat(w.premium / maxPrem) * 44)
                    Text(w.label)
                        .font(.system(size: 9, weight: w.isCurrent ? .bold : .medium))
                        .foregroundStyle(w.isCurrent ? Color.theme.neon : Color.theme.fg4)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var weeklyLegend: some View {
        HStack(spacing: 16) {
            legendItem(Color.theme.neon, "premium / week")
            legendItem(Color.theme.gold, "assigned that week")
        }
    }

    private func legendItem(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(t).font(.numeric(size: 10, weight: .medium)).foregroundStyle(Color.theme.fg3)
        }
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
                Text("No resolved expiries yet. Each call that expires or gets exercised logs here — kept drops your average, exercised books a realized win.")
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
        let ordered = Array(detail.history.reversed())   // oldest → newest
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
            s.append(d); s.append(AttributedString(" since last exercise · "))
        }
        var k = AttributedString("kept \(detail.keptStreak) in a row")
        k.foregroundColor = Color.theme.pos
        s.append(k)
        return s
    }

    private func logRow(_ h: IncomeDetail.ExpiryOutcome) -> some View {
        HStack(spacing: 13) {
            Text(h.exercised ? "Exercised" : "Kept")
                .font(.system(size: 9, weight: .bold)).tracking(0.7)
                .foregroundStyle(h.exercised ? Color.theme.gold : Color.theme.pos)
                .frame(width: 82)
                .padding(.vertical, 6)
                .background(Capsule().fill(h.exercised ? Color.theme.tintWarn : Color.theme.tintPos))
            VStack(alignment: .leading, spacing: 5) {
                Text("\(h.weekday) · $\(fmtStrike(h.strike)) call")
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

    /// Strike display — whole strikes read clean ("625"), fractional
    /// strikes keep their cents ("607.50"). Rounding to a whole number
    /// misreported 607.50 as "608".
    private func fmtStrike(_ v: Double) -> String {
        if v == v.rounded() {
            return Int(v).formatted(.number.grouping(.automatic))
        }
        return v.formatted(.number.precision(.fractionLength(2)).grouping(.automatic))
    }
}

// MARK: - Live dot (pulsing)

/// 7pt lime dot with a soft expanding pulse ring — the v3 `.live-dot`.
private struct PulsingDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(Color.theme.lime)
            .frame(width: 7, height: 7)
            .overlay(
                Circle().stroke(Color.theme.lime, lineWidth: 1.5)
                    .scaleEffect(on ? 2.6 : 1)
                    .opacity(on ? 0 : 0.5)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 2.4).repeatForever(autoreverses: false)) {
                    on = true
                }
            }
    }
}

// MARK: - Card chrome

private extension View {
    /// v3 card surface: radius 26, padding 22, two-layer soft shadow.
    func incomeCard() -> some View {
        self
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 26)
                        .strokeBorder(Color.theme.hair, lineWidth: 0.5))
                    .shadow(color: Color(hex: 0x16251d, alpha: 0.05), radius: 2, x: 0, y: 1)
                    .shadow(color: Color(hex: 0x16251d, alpha: 0.10), radius: 17, x: 0, y: 6)
            )
    }
}
