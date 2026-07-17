//
//  CoveredCallScreen.swift
//  Sunnyfi
//
//  Covered Call — wheel-style cycle monitoring, one tab per ticker.
//  A monitoring surface: dense, numbers-forward, no decorative charts.
//
//  Layout (top → bottom):
//    • Header      — Last updated HH:MM:SS + manual refresh (grays when
//                    the data is older than the 15-min refresh cadence)
//    • Tally       — sticky, always visible, aggregates every ticker
//    • Tab bar     — one tab per ticker, data-driven
//    • Tab body    — that ticker only; nothing bleeds across tabs
//
//  All math comes from CoveredCallData so this screen and Performance
//  can never disagree.
//

import Combine
import SwiftUI

struct CoveredCallScreen: View {
    let store: PortfolioStore
    @State private var selected: String?
    @State private var refreshing = false
    /// Re-renders the "last updated" label so it grays out on time.
    @State private var tick = 0
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var tickers: [String] { CoveredCallData.tickers(store: store) }
    private var active: String? {
        if let selected, tickers.contains(selected) { return selected }
        return tickers.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if tickers.isEmpty {
                emptyState
            } else {
                tally
                tabBar
                Divider().overlay(Color.theme.hair)
                ScrollView {
                    if let t = active, let data = CoveredCallData.build(store: store, ticker: t) {
                        TickerBody(data: data)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 110)
                            .id(t)          // no cross-tab bleed
                    }
                }
            }
        }
        .background(Color.theme.page)
        .onReceive(timer) { _ in tick &+= 1 }
    }

    // MARK: Header — last updated + refresh

    private var header: some View {
        _ = tick
        return HStack(alignment: .center) {
            Text("Covered Call")
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.6)
                .foregroundStyle(Color.theme.fg1)
            Spacer()
            Text(lastUpdatedText)
                .font(.numeric(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(isStale ? Color.theme.fg4 : Color.theme.fg2)
            Button {
                guard !refreshing else { return }
                refreshing = true
                Task { await store.fetchAll(); refreshing = false }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.theme.neon)
                    .rotationEffect(.degrees(refreshing ? 360 : 0))
                    .animation(refreshing
                        ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                        : .default, value: refreshing)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(refreshing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var lastUpdatedText: String {
        guard let f = store.freshness else { return "Last updated: —" }
        return "Last updated: " + Self.hms.string(from: f)
    }
    /// Marks refresh on a 15-min cron; older than that = gray.
    private var isStale: Bool {
        _ = tick
        guard let f = store.freshness else { return true }
        return -f.timeIntervalSinceNow > 15 * 60
    }
    private static let hms: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    // MARK: Tally — sticky, aggregates every ticker

    private var tally: some View {
        let t = CoveredCallData.tally(store: store, tickers: tickers)
        return HStack(alignment: .top, spacing: 0) {
            tallyCell("SHARES + CALLS", t.sharesAndCalls,
                      sub: "unrealized + realized")
            Rectangle().fill(Color.theme.hair).frame(width: 0.5, height: 40)
            tallyCell("PUTS", t.putsPL,
                      sub: t.putsCost > 0 ? fmtPct(t.putsPct) : "none")
            Rectangle().fill(Color.theme.hair).frame(width: 0.5, height: 40)
            tallyCell("NET", t.net, sub: "combined", loud: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.theme.hair).frame(height: 0.5) }
    }

    private func tallyCell(_ k: String, _ v: Double, sub: String, loud: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(k).font(.system(size: 8.5, weight: .bold)).tracking(0.9)
                .foregroundStyle(Color.theme.fg3)
            Text(fmtMoney(v, sign: true))
                .font(.numeric(size: loud ? 19 : 17, weight: .heavy))
                .tracking(-0.4).monospacedDigit()
                .foregroundStyle(Color.signed(v))
            Text(sub).font(.numeric(size: 9.5, weight: .medium)).monospacedDigit()
                .foregroundStyle(Color.theme.fg4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 2)
    }

    // MARK: Ticker tabs

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(tickers, id: \.self) { t in
                    let on = active == t
                    Button {
                        withAnimation(Motion.standard) { selected = t }
                    } label: {
                        Text(t)
                            .font(.system(size: 13, weight: on ? .bold : .semibold))
                            .tracking(0.3)
                            .foregroundStyle(on ? Color.theme.onNeon : Color.theme.fg2)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 34)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No covered-call positions")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.theme.fg2)
            Text("A ticker appears here once you hold shares and sell a call against them.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.theme.fg3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - One ticker's body

private struct TickerBody: View {
    let data: CoveredCallTicker
    @State private var historyOpen = false

    private var cycle: CoveredCallCycle? { data.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let c = cycle {
                headerRow(c)
                basisHero(c)
                secondaryRow(c)
                nextCallPanel(c)
                exitPanel
                if data.put != nil { putPanel }
            } else {
                noCycle
            }
            history
        }
    }

    // ── Header: ticker, shares, dot row ──
    private func headerRow(_ c: CoveredCallCycle) -> some View {
        HStack(alignment: .center) {
            Text(data.ticker)
                .font(.system(size: 20, weight: .heavy)).tracking(-0.4)
                .foregroundStyle(Color.theme.fg1)
            Text("\(Int(c.shares).formatted()) sh")
                .font(.numeric(size: 12, weight: .medium)).monospacedDigit()
                .foregroundStyle(Color.theme.fg3)
            Spacer()
            dotRow(c)
        }
    }

    /// Filled = expired worthless · hollow = rolled · red = assigned.
    /// Only the current cycle's calls — assignment resets the row.
    private func dotRow(_ c: CoveredCallCycle) -> some View {
        HStack(spacing: 4) {
            ForEach(c.legs) { leg in
                Group {
                    switch leg.status {
                    case .expired:  Circle().fill(Color.theme.pos)
                    case .rolled:   Circle().strokeBorder(Color.theme.fg3, lineWidth: 1.5)
                    case .assigned: Circle().fill(Color.theme.neg)
                    case .open:     Circle().strokeBorder(Color.theme.neon, lineWidth: 1.5)
                    }
                }
                .frame(width: 7, height: 7)
            }
        }
    }

    // ── Adjusted basis (the primary metric) ──
    private func basisHero(_ c: CoveredCallCycle) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ADJUSTED BASIS")
                .font(.system(size: 8.5, weight: .bold)).tracking(0.9)
                .foregroundStyle(Color.theme.fg3)
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(fmtMoney(c.adjustedBasis, decimals: 2))
                    .font(.numeric(size: 34, weight: .heavy)).tracking(-1.1)
                    .monospacedDigit()
                    .foregroundStyle(Color.theme.fg1)
                Text(fmtMoney(c.entryPrice, decimals: 2))
                    .font(.numeric(size: 13, weight: .medium)).monospacedDigit()
                    .strikethrough(true, color: Color.theme.fg4)
                    .foregroundStyle(Color.theme.fg3)
            }
        }
    }

    // ── Streak / last assignment / premium / price ──
    private func secondaryRow(_ c: CoveredCallCycle) -> some View {
        HStack(alignment: .top, spacing: 0) {
            statCell("STREAK", "\(c.daysHeld) days",
                     sub: "\(c.callCount) call\(c.callCount == 1 ? "" : "s")")
            statCell("LAST ASSIGN", data.lastAssignment.map(AppDates.shortMonthDay) ?? "never",
                     sub: data.lastAssignment == nil ? "—" : "")
            statCell("PREMIUM", fmtMoney(c.premiumCollected),
                     sub: "this cycle", tone: Color.theme.pos)
            statCell("PRICE", fmtMoney(data.currentPrice, decimals: 2),
                     sub: fmtPct(data.distanceToBasisPct) + " vs basis",
                     subTone: Color.signed(data.distanceToBasisPct))
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 0.5) }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.theme.hair).frame(height: 0.5) }
    }

    private func statCell(_ k: String, _ v: String, sub: String,
                          tone: Color = Color.theme.fg1,
                          subTone: Color = Color.theme.fg4) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k).font(.system(size: 8, weight: .bold)).tracking(0.7)
                .foregroundStyle(Color.theme.fg3)
            Text(v).font(.numeric(size: 13.5, weight: .bold)).monospacedDigit()
                .foregroundStyle(tone).lineLimit(1).minimumScaleFactor(0.75)
            Text(sub).font(.numeric(size: 9, weight: .medium)).monospacedDigit()
                .foregroundStyle(subTone).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ── Next call + floor ──
    private func nextCallPanel(_ c: CoveredCallCycle) -> some View {
        let floor = data.floorStrike()
        let below = data.belowFloorLoss
        return VStack(alignment: .leading, spacing: 10) {
            Text("NEXT CALL").font(.system(size: 8.5, weight: .bold)).tracking(0.9)
                .foregroundStyle(Color.theme.fg3)

            if let leg = c.openLeg {
                let itm = data.currentPrice > leg.strike
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("$\(fmtStrike(leg.strike))")
                        .font(.numeric(size: 19, weight: .heavy)).tracking(-0.4)
                        .monospacedDigit().foregroundStyle(Color.theme.fg1)
                    Text(AppDates.shortMonthDay(leg.expiry))
                        .font(.numeric(size: 12, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Color.theme.fg2)
                    Text("\(leg.dte)d")
                        .font(.numeric(size: 12, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Color.theme.warn)
                    Spacer()
                    Text(itm ? "ITM" : "OTM")
                        .font(.system(size: 9, weight: .bold)).tracking(0.6)
                        .foregroundStyle(itm ? Color.theme.neg : Color.theme.pos)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(itm ? Color.theme.tintNeg : Color.theme.tintPos))
                }
                Text("\(fmtMoney(leg.premiumTotal)) premium · \(Int(leg.remaining)) contract\(leg.remaining == 1 ? "" : "s")")
                    .font(.numeric(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Color.theme.fg3)
            } else {
                Text("No call open")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.theme.fg2)
            }

            // Floor strike
            HStack(spacing: 8) {
                Text("FLOOR")
                    .font(.system(size: 8, weight: .bold)).tracking(0.7)
                    .foregroundStyle(Color.theme.fg3)
                Text("$\(fmtStrike(floor))")
                    .font(.numeric(size: 14, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(below != nil ? Color.theme.neg : Color.theme.fg1)
                Text(c.openLeg == nil
                     ? "minimum strike to sell next"
                     : "assignment profitable at or above")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.theme.fg3)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)

            if let loss = below {
                Text("Open call is below the floor — assignment locks in \(fmtMoney(loss, decimals: 2))/share (\(fmtMoney(loss * c.shares, sign: true)) total)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.theme.neg)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.theme.tintNeg))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl).fill(Color.theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Color.theme.hair, lineWidth: 0.5))
    }

    // ── Exit panel — always visible, escalates when underwater ──
    private var exitPanel: some View {
        let d = data.distanceToBasisPct
        let loud = d <= -7
        let warn = d <= -5
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("IF CLOSED NOW")
                    .font(.system(size: 8.5, weight: .bold)).tracking(0.9)
                    .foregroundStyle(loud ? Color.theme.neg : Color.theme.fg3)
                Spacer()
                if warn {
                    Text(loud ? "DOWN \(String(format: "%.1f", abs(d)))%" : "WATCH")
                        .font(.system(size: 9, weight: .bold)).tracking(0.6)
                        .foregroundStyle(Color.theme.neg)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.theme.tintNeg))
                }
            }
            exitRow("Shares vs adjusted basis", data.exitSharesPL)
            exitRow("Buy back open call", data.exitCallBuyback)
            if data.put != nil { exitRow("Put at current mark", data.exitPutPL) }
            Rectangle().fill(Color.theme.hair).frame(height: 0.5)
            HStack {
                Text("Net")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Color.theme.fg1)
                Spacer()
                Text(fmtMoney(data.exitNet, sign: true))
                    .font(.numeric(size: loud ? 20 : 16, weight: .heavy)).tracking(-0.4)
                    .monospacedDigit()
                    .foregroundStyle(Color.signed(data.exitNet))
                Text("(\(fmtPct(data.exitNetPct)))")
                    .font(.numeric(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Color.signed(data.exitNet))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl)
            .fill(loud ? Color.theme.tintNeg : Color.theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl)
            .strokeBorder(loud ? Color.theme.neg : warn ? Color.theme.warn : Color.theme.hair,
                          lineWidth: loud ? 2 : warn ? 1.5 : 0.5))
    }

    private func exitRow(_ k: String, _ v: Double) -> some View {
        HStack {
            Text(k).font(.system(size: 11.5)).foregroundStyle(Color.theme.fg2)
            Spacer()
            Text(fmtMoney(v, sign: true))
                .font(.numeric(size: 12.5, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Color.signed(v))
        }
    }

    // ── Put: one compact line ──
    private var putPanel: some View {
        Group {
            if let p = data.put {
                Text("Put \(AppDates.shortMonthDay(p.expiry)) $\(fmtStrike(p.strike)): paid \(fmtMoney(p.costBasisPerShare, decimals: 2)), now \(fmtMoney(p.currentMark, decimals: 2)), \(p.pnl < 0 ? "down" : "up") \(fmtMoney(abs(p.pnl))) (\(fmtPct(p.pnlPct)))")
                    .font(.numeric(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Color.theme.fg3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Color.theme.surface))
            }
        }
    }

    private var noCycle: some View {
        Text("No open cycle — buy shares to start one.")
            .font(.system(size: 13)).foregroundStyle(Color.theme.fg3)
            .padding(.vertical, 20)
    }

    // ── History: collapsed closed cycles ──
    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.standard) { historyOpen.toggle() }
            } label: {
                HStack {
                    Text("HISTORY")
                        .font(.system(size: 8.5, weight: .bold)).tracking(0.9)
                        .foregroundStyle(Color.theme.fg3)
                    Text("\(data.closed.count) closed cycle\(data.closed.count == 1 ? "" : "s")")
                        .font(.numeric(size: 10, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Color.theme.fg4)
                    Spacer()
                    if data.realizedToDate != 0 {
                        Text(fmtMoney(data.realizedToDate, sign: true))
                            .font(.numeric(size: 12, weight: .bold)).monospacedDigit()
                            .foregroundStyle(Color.signed(data.realizedToDate))
                    }
                    Image(systemName: historyOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.theme.fg3)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if historyOpen {
                if data.closed.isEmpty {
                    Text("No closed cycles yet — a cycle closes when the call is assigned.")
                        .font(.system(size: 11.5)).foregroundStyle(Color.theme.fg4)
                        .padding(.bottom, 10)
                } else {
                    ForEach(data.closed) { c in historyRow(c) }
                }
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 0.5) }
    }

    private func historyRow(_ c: CoveredCallCycle) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(AppDates.shortMonthDay(c.cycleStartDate)) → \(c.cycleEndDate.map(AppDates.shortMonthDay) ?? "—")")
                    .font(.numeric(size: 12, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Color.theme.fg1)
                Text("\(c.daysHeld) days · \(c.callCount) call\(c.callCount == 1 ? "" : "s") · \(fmtMoney(c.premiumCollected)) premium")
                    .font(.numeric(size: 10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Color.theme.fg3)
            }
            Spacer()
            Text(fmtMoney(c.realizedPL ?? 0, sign: true))
                .font(.numeric(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(Color.signed(c.realizedPL ?? 0))
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 0.5) }
    }
}

// Strike formatting uses the app-wide `fmtStrike` in Formatting.swift —
// whole strikes read clean (625), fractional keep their cents (607.50).
