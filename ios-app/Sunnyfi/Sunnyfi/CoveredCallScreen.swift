//
//  CoveredCallScreen.swift
//  Sunnyfi
//
//  Covered Call — wheel-style cycle monitoring, one tab per ticker.
//  Rebuilt to the "Covered Call v7" design: adjusted basis as a giant
//  centered hero, a month-navigable Mon/Wed/Fri win calendar, an
//  exercised/not-exercised fork, and the always-present exit readout.
//
//  Per-ticker only (no cross-ticker tally — the whole-book number lives
//  on the Performance page). Palette maps to the app's own tokens so
//  light + dark both work; the composition is v7's.
//
//  All math comes from CoveredCallData — the same engine Performance
//  renders — so the two surfaces can never disagree.
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
                        TickerBody(data: data)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 110)
                            .id(t)     // no cross-tab bleed; resets month nav per ticker
                    }
                }
            }
        }
        .background(Color.theme.page)
        .onReceive(timer) { _ in tick &+= 1 }
    }

    // MARK: Top bar — pills + last updated + refresh

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
                .foregroundStyle(isStale ? Color.theme.fg4 : Color.theme.fg3)
                .lineLimit(1)
            Button {
                guard !refreshing else { return }
                refreshing = true
                Task { await store.fetchAll(); refreshing = false }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.theme.pos)
                    .rotationEffect(.degrees(refreshing ? 360 : 0))
                    .animation(refreshing ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                          : .default, value: refreshing)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(refreshing)
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 8)
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

// MARK: - One ticker's body

private struct TickerBody: View {
    let data: CoveredCallTicker
    @State private var monthIndex: Int? = nil
    @State private var selectedSlotID: String? = nil
    @State private var historyOpen = false

    private var cycle: CoveredCallCycle? { data.current }
    private var months: [CalMonth] { data.calendar }
    private var mIdx: Int { min(monthIndex ?? defaultMonthIdx, max(months.count - 1, 0)) }

    /// Open on THIS month, not the oldest.
    private var defaultMonthIdx: Int {
        let ym = Self.ymFmt.string(from: Date())
        if let i = months.firstIndex(where: { $0.id == ym }) { return i }
        return max(months.count - 1, 0)
    }
    private static let ymFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        f.timeZone = TimeZone(identifier: "America/New_York"); return f
    }()

    /// Brand accents for the badge (falls back to the app accent).
    private static let brand: [String: Color] = [
        "META": Color(hex: 0x1877F2), "NVDA": Color(hex: 0x76B900),
        "MSFT": Color(hex: 0x00A4EF), "AVGO": Color(hex: 0xCC092F),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let c = cycle {
                badge
                pnlSnapshot
                heroBasis(c)
                rule
                winCalendar
                currentPositionSection(c)
                statsGrid(c)
                openCallSection(c)
                exitSection
                if data.put != nil { putSection }
            } else {
                Text("No open cycle — buy shares to start one.")
                    .font(.system(size: 13)).foregroundStyle(Color.theme.fg3)
                    .padding(.vertical, 24)
            }
            historySection
        }
    }

    // ── Realized P&L snapshot (per ticker) ──
    private var pnlSnapshot: some View {
        let v = data.realizedToDate
        return HStack(spacing: 9) {
            Text("REALIZED P&L").font(.system(size: 11, weight: .bold)).tracking(0.4)
                .foregroundStyle(Color.theme.fg3)
            Text(fmtMoney(v, sign: true))
                .font(.numeric(size: 22, weight: .heavy)).tracking(-0.4).monospacedDigit()
                .foregroundStyle(Color.signed(v))
            Text(fmtPct(data.realizedPct))
                .font(.numeric(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(Color.signed(v))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var rule: some View {
        Rectangle().fill(Color.theme.hair).frame(height: 1).padding(.top, 26)
    }

    // ── Badge ──
    private var badge: some View {
        let color = Self.brand[data.ticker] ?? Color.theme.neon
        return Circle().fill(color)
            .frame(width: 50, height: 50)
            .overlay(Text(String(data.ticker.prefix(1)))
                .font(.system(size: 22, weight: .heavy)).foregroundStyle(.white))
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
    }

    // ── Adjusted basis hero ──
    private func heroBasis(_ c: CoveredCallCycle) -> some View {
        let d = data.distanceToBasisPct
        let safe = d >= 0
        let diff = data.currentPrice - c.adjustedBasis
        return VStack(spacing: 0) {
            Text("Current adjusted basis")
                .font(.system(size: 16, weight: .medium)).foregroundStyle(Color.theme.fg2)
                .padding(.top, 16)
            Text(fmtMoney(c.adjustedBasis, decimals: c.adjustedBasis >= 1000 ? 0 : 2)
                    .replacingOccurrences(of: "$", with: ""))
                .font(.system(size: 66, weight: .heavy)).tracking(-3)
                .monospacedDigit()
                .foregroundStyle(safe ? Color.theme.pos : Color.theme.neg)
                .minimumScaleFactor(0.5).lineLimit(1)
                .padding(.top, 10).padding(.horizontal, 8)
            Text("\(fmtMoney(abs(diff), decimals: 2)) (\(String(format: "%.1f", abs(d)))%) \(safe ? "below" : "above") current price")
                .font(.numeric(size: 13.5, weight: .medium)).monospacedDigit()
                .foregroundStyle(Color.theme.fg3).padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
    }

    // ── Win calendar (month nav + M/W/F premium boxes + tap detail) ──
    private func effectiveSlot(_ m: CalMonth) -> CalSlot? {
        let slots = m.allSlots
        if let id = selectedSlotID, let s = slots.first(where: { $0.id == id }) { return s }
        if let open = slots.first(where: { $0.kind == .open }) { return open }
        return slots.last(where: { $0.kind == .assigned || $0.kind == .kept })
    }

    private var winCalendar: some View {
        VStack(spacing: 0) {
            if months.isEmpty {
                Text("No expiries yet")
                    .font(.system(size: 13)).foregroundStyle(Color.theme.fg4).padding(.top, 24)
            } else {
                let m = months[mIdx]
                HStack(spacing: 14) {
                    navButton("chevron.left", enabled: mIdx > 0) { monthIndex = max(0, mIdx - 1) }
                    Text(m.label).font(.system(size: 15, weight: .bold)).tracking(-0.2)
                        .foregroundStyle(Color.theme.fg1).frame(minWidth: 130)
                    navButton("chevron.right", enabled: mIdx < months.count - 1) { monthIndex = min(months.count - 1, mIdx + 1) }
                }
                .frame(maxWidth: .infinity).padding(.top, 24)

                summaryLine(m).padding(.top, 18)
                calendarGrid(m).padding(.top, 18)
                if let s = effectiveSlot(m) { slotDetail(s).padding(.top, 16) }
                legend.padding(.top, 22)
                Text("Numbers show premium collected · tap any expiry for detail")
                    .font(.system(size: 11)).foregroundStyle(Color.theme.fg4)
                    .frame(maxWidth: .infinity).padding(.top, 12)
            }
        }
    }

    /// "N assigned · N kept · N% rate · N open" for the shown month.
    private func summaryLine(_ m: CalMonth) -> some View {
        HStack(spacing: 7) {
            Text("\(m.assigned) assigned")
                .font(.numeric(size: 14, weight: .heavy)).monospacedDigit().foregroundStyle(Color.theme.fg1)
            sep; Text("\(m.kept) kept")
            sep; Text("\(Int(m.winRatePct.rounded()))% rate")
            if m.open > 0 { sep; Text("\(m.open) open") }
        }
        .font(.numeric(size: 13, weight: .medium)).monospacedDigit()
        .foregroundStyle(Color.theme.fg3)
        .frame(maxWidth: .infinity)
    }
    private var sep: some View { Text("·").foregroundStyle(Color.theme.fg4) }

    private func navButton(_ icon: String, enabled: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.theme.fg2).frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Color.theme.hair, lineWidth: 1))
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.3)
    }

    private func calendarGrid(_ m: CalMonth) -> some View {
        Grid(horizontalSpacing: 7, verticalSpacing: 7) {
            GridRow {
                Color.clear.frame(width: 16, height: 1)
                ForEach(m.weeks) { w in
                    Text(w.label).font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.theme.fg4)
                }
            }
            dayRow("M", m.weeks.map(\.mon))
            dayRow("W", m.weeks.map(\.wed))
            dayRow("F", m.weeks.map(\.fri))
        }
        .frame(maxWidth: .infinity)
    }

    private func dayRow(_ label: String, _ slots: [CalSlot]) -> some View {
        GridRow {
            Text(label).font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.theme.fg3).gridColumnAlignment(.leading)
            ForEach(slots) { s in box(s) }
        }
    }

    @ViewBuilder
    private func box(_ s: CalSlot) -> some View {
        let selected = effectiveSlot(months[mIdx])?.id == s.id
        let content = boxFill(s)
            .frame(maxWidth: 44).aspectRatio(1, contentMode: .fit)
            .overlay {
                if selected && s.isTappable {
                    Circle().strokeBorder(Color.theme.fg1, lineWidth: 2.5).padding(-3)
                }
            }
        if s.isTappable {
            Button { selectedSlotID = s.id } label: { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    /// Compact dollar amount for a calendar box: 400→".4k", 1200→"1.2k",
    /// 12000→"12k". Matches the total shown in the tap-through detail.
    private func compactAmt(_ v: Double) -> String {
        let k = v / 1000
        if k >= 10 { return String(format: "%.0fk", k) }
        if k >= 1 { return String(format: "%.1fk", k) }
        let s = String(format: "%.1f", k)
        return (s.hasPrefix("0") ? String(s.dropFirst()) : s) + "k"
    }

    @ViewBuilder
    private func boxFill(_ s: CalSlot) -> some View {
        let num = s.premiumTotal.map { compactAmt($0) } ?? ""
        switch s.kind {
        case .assigned:
            Circle().fill(Color.theme.gold)
                .overlay(Text(num).font(.numeric(size: 10.5, weight: .bold)).minimumScaleFactor(0.7).lineLimit(1).padding(.horizontal, 1).foregroundStyle(Color(hex: 0x1d1500)))
        case .kept:
            Circle().fill(Color.theme.pos)
                .overlay(Text(num).font(.numeric(size: 10.5, weight: .bold)).minimumScaleFactor(0.7).lineLimit(1).padding(.horizontal, 1).foregroundStyle(.white))
        case .open:
            Circle().fill(Color.theme.page)
                .overlay(Circle().strokeBorder(Color.theme.pos, lineWidth: 2.5))
                .overlay(Text(num).font(.numeric(size: 10.5, weight: .bold)).minimumScaleFactor(0.7).lineLimit(1).padding(.horizontal, 1).foregroundStyle(Color.theme.pos))
        case .future:
            Circle().fill(Color.clear)
                .overlay(Circle().strokeBorder(Color.theme.fg4.opacity(0.5), lineWidth: 1.5))
        case .none:
            Circle().fill(Color.theme.page2)
                .overlay(Text("–").font(.system(size: 12)).foregroundStyle(Color.theme.fg4))
        }
    }

    private func slotDetail(_ s: CalSlot) -> some View {
        let (desc, valLabel): (String, String) = {
            switch s.kind {
            case .assigned: return ("Called away · shares delivered", "premium · assigned")
            case .kept:     return ("Expired OTM · shares held", "premium kept")
            case .open:     return ("Working · expires this week", "premium in")
            case .future:   return ("Upcoming expiry · no call yet", "pending")
            case .none:     return ("No call sold this expiry", "")
            }
        }()
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(s.weekday) \(s.dateLabel) · " + (s.strike.map { "$\(fmtStrike($0)) call" } ?? "no call"))
                    .font(.numeric(size: 15, weight: .heavy)).monospacedDigit().foregroundStyle(Color.theme.fg1)
                Text(desc).font(.system(size: 12)).foregroundStyle(Color.theme.fg3)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(s.premiumTotal.map { fmtMoney($0, sign: s.kind == .assigned) } ?? "—")
                    .font(.numeric(size: 17, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(s.kind == .assigned ? Color.theme.pos : Color.theme.fg1)
                Text(valLabel.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.5)
                    .foregroundStyle(Color.theme.fg4)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.theme.page2))
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(Color.theme.pos, "kept")
            legendItem(Color.theme.gold, "assigned")
            legendRing(false, "open")
            legendRing(true, "upcoming")
        }
        .frame(maxWidth: .infinity)
    }
    private func legendItem(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 11, height: 11)
            Text(t).font(.system(size: 11.5)).foregroundStyle(Color.theme.fg3)
        }
    }
    private func legendRing(_ grey: Bool, _ t: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color.theme.page)
                .overlay(Circle().strokeBorder(grey ? Color.theme.fg4.opacity(0.5) : Color.theme.pos, lineWidth: 2))
                .frame(width: 11, height: 11)
            Text(t).font(.system(size: 11.5)).foregroundStyle(Color.theme.fg3)
        }
    }

    // ── Current position: qty cards + exercised/not-exercised fork ──
    private func currentPositionSection(_ c: CoveredCallCycle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Current position")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.theme.fg2)
                .padding(.top, 26)
            qtyCards(c).padding(.top, 16)
            if let gain = data.ifExercisedGain {
                HStack(alignment: .top, spacing: 20) {
                    forkCell("If exercised", fmtMoney(gain, sign: true),
                             sub: "\(fmtMoney(data.realizedToDate, sign: true)) realized so far",
                             tone: Color.theme.pos)
                    forkCell("If not exercised", fmtMoney(c.ifNotExercisedBasis, decimals: c.ifNotExercisedBasis >= 1000 ? 0 : 2),
                             sub: notExercisedSub(c), tone: Color.theme.fg1)
                }
                .padding(.top, 20)
            }
        }
    }

    private func qtyCards(_ c: CoveredCallCycle) -> some View {
        HStack(spacing: 10) {
            qtyCard("Shares", "\(Int(c.shares).formatted())",
                    sub: "\(c.lotCount) lot\(c.lotCount == 1 ? "" : "s")",
                    total: fmtMoney(c.shares * data.currentPrice), totalTone: Color.theme.fg1)
            qtyCard("Calls",
                    data.openCallContracts > 0 ? "\(Int(data.openCallContracts))" : "0",
                    sub: data.openCallContracts > 0 ? "avg \(fmtMoney(data.openCallAvgPremium, decimals: 2))" : "none",
                    total: data.openCallPremiumTotal > 0 ? fmtMoney(data.openCallPremiumTotal, sign: true) : "$0",
                    totalTone: data.openCallPremiumTotal > 0 ? Color.theme.pos : Color.theme.fg3)
            qtyCard("Puts",
                    data.putContracts > 0 ? "\(Int(data.putContracts))" : "0",
                    sub: data.putContracts > 0 ? "avg \(fmtMoney(data.putAvgCost, decimals: 2))" : "none",
                    total: fmtMoney(data.putValueTotal),
                    totalTone: Color.theme.fg1)
        }
    }

    private func qtyCard(_ k: String, _ v: String, sub: String, total: String, totalTone: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(k.uppercased()).font(.system(size: 10.5, weight: .bold)).tracking(0.3)
                .foregroundStyle(Color.theme.fg3)
            Text(v).font(.numeric(size: 24, weight: .heavy)).tracking(-0.7).monospacedDigit()
                .foregroundStyle(Color.theme.fg1).lineLimit(1).minimumScaleFactor(0.6)
                .padding(.top, 9)
            Text(sub).font(.numeric(size: 10.5, weight: .medium)).monospacedDigit()
                .foregroundStyle(Color.theme.fg4).padding(.top, 3)
            Text(total).font(.numeric(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(totalTone).lineLimit(1).minimumScaleFactor(0.7)
                .padding(.top, 10)
                .overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 1).padding(.top, 5) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.theme.page2))
    }

    private func notExercisedSub(_ c: CoveredCallCycle) -> String {
        let p = data.currentPrice
        guard p > 0 else { return "" }
        let pct = (p - c.ifNotExercisedBasis) / p * 100
        return "\(String(format: "%.0f", abs(pct)))% \(pct >= 0 ? "below" : "above") price"
    }

    private func forkCell(_ k: String, _ v: String, sub: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(k).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.theme.fg3)
            Text(v).font(.numeric(size: 30, weight: .heavy)).tracking(-1)
                .monospacedDigit().foregroundStyle(tone)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.numeric(size: 12.5, weight: .medium)).monospacedDigit()
                .foregroundStyle(Color.theme.fg4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ── Stats 2×2 ──
    private func statsGrid(_ c: CoveredCallCycle) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.theme.hair).frame(height: 1).padding(.top, 26)
            Grid(horizontalSpacing: 18, verticalSpacing: 24) {
                GridRow {
                    statCell("STREAK", "\(c.daysHeld) days", sub: "\(c.callCount) call\(c.callCount == 1 ? "" : "s")")
                    statCell("LAST ASSIGN", data.lastAssignment.map(AppDates.shortMonthDay) ?? "never",
                             sub: data.lastAssignment == nil ? "—" : "assigned")
                }
                GridRow {
                    statCell("PREMIUM", fmtMoney(c.premiumGross), sub: "collected this cycle", tone: Color.theme.pos)
                    statCell("PRICE", fmtMoney(data.currentPrice, decimals: 2),
                             sub: fmtPct(data.distanceToBasisPct) + " vs basis",
                             subTone: Color.signed(data.distanceToBasisPct))
                }
            }
            .padding(.top, 26)
        }
    }

    private func statCell(_ k: String, _ v: String, sub: String,
                          tone: Color = Color.theme.fg1,
                          subTone: Color = Color.theme.fg3) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(k).font(.system(size: 10, weight: .heavy)).tracking(1)
                .foregroundStyle(Color.theme.fg3)
            Text(v).font(.numeric(size: 21, weight: .heavy)).tracking(-0.4)
                .monospacedDigit().foregroundStyle(tone).lineLimit(1).minimumScaleFactor(0.7)
            Text(sub).font(.numeric(size: 12, weight: .medium)).monospacedDigit()
                .foregroundStyle(subTone).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ── Open call + floor ──
    private func openCallSection(_ c: CoveredCallCycle) -> some View {
        sectionBox("Open call") {
            if let leg = c.openLeg {
                let itm = data.currentPrice > leg.strike
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("$\(fmtStrike(leg.strike)) call ×\(Int(leg.remaining))")
                            .font(.numeric(size: 22, weight: .heavy)).tracking(-0.5).monospacedDigit()
                            .foregroundStyle(Color.theme.fg1)
                        Text("exp \(AppDates.shortMonthDay(leg.expiry)) · \(leg.dte) day\(leg.dte == 1 ? "" : "s") · \(fmtMoney(leg.premiumPerShare * leg.remaining * 100)) premium in")
                            .font(.numeric(size: 13, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Color.theme.fg3)
                    }
                    Spacer()
                    Text(itm ? "ITM" : "OTM")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(itm ? Color.theme.neg : Color.theme.pos)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Capsule().fill(itm ? Color.theme.tintNeg : Color.theme.tintPos))
                }
                .padding(.top, 14)
            } else {
                Text("No call open").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.theme.fg2).padding(.top, 14)
            }
            floorRow(c)
        }
    }

    private func floorRow(_ c: CoveredCallCycle) -> some View {
        let floor = data.floorStrike()
        let below = data.belowFloorLoss
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("FLOOR").font(.system(size: 10, weight: .heavy)).tracking(1)
                    .foregroundStyle(Color.theme.fg3)
                Text("$\(fmtStrike(floor))")
                    .font(.numeric(size: 19, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(below != nil ? Color.theme.neg : Color.theme.fg1)
                Text(c.openLeg == nil ? "minimum strike to sell next" : "profit floor if assigned")
                    .font(.system(size: 13)).foregroundStyle(Color.theme.fg3)
                Spacer(minLength: 0)
            }
            if let loss = below, let sh = cycle?.shares {
                Text("Open call is below the floor — assignment locks in \(fmtMoney(loss, decimals: 2))/share (\(fmtMoney(loss * sh, sign: true)))")
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.theme.neg)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.theme.tintNeg))
            }
        }
        .padding(.top, 18)
    }

    // ── If closed now (exit) — escalates when underwater ──
    private var exitSection: some View {
        let d = data.distanceToBasisPct
        let loud = d <= -7, warn = d <= -5
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color.theme.hair).frame(height: 1).padding(.top, 26)
            HStack {
                Text("IF CLOSED NOW").font(.system(size: 11, weight: .heavy)).tracking(1.3)
                    .foregroundStyle(loud ? Color.theme.neg : Color.theme.fg3)
                Spacer()
                if warn {
                    Text(loud ? "DOWN \(String(format: "%.1f", abs(d)))%" : "WATCH")
                        .font(.system(size: 9.5, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Color.theme.neg)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.theme.tintNeg))
                }
            }
            .padding(.top, 14)
            exitRow("Shares vs cost", data.exitSharesPL)
            exitRow("Close open call (net)", data.exitCallBuyback)
            if data.put != nil { exitRow("Put at current mark", data.exitPutPL) }
            Rectangle().fill(Color.theme.hair).frame(height: 1).padding(.vertical, 13)
            HStack {
                Text("Net").font(.system(size: 18, weight: .heavy)).foregroundStyle(Color.theme.fg1)
                Spacer()
                Text(fmtMoney(data.exitNet, sign: true))
                    .font(.numeric(size: loud ? 22 : 20, weight: .heavy)).tracking(-0.5)
                    .monospacedDigit().foregroundStyle(Color.signed(data.exitNet))
                Text("(\(fmtPct(data.exitNetPct)))")
                    .font(.numeric(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Color.signed(data.exitNet))
            }
        }
        .padding(loud || warn ? 14 : 0)
        .background(loud
            ? RoundedRectangle(cornerRadius: 14).fill(Color.theme.tintNeg)
            : RoundedRectangle(cornerRadius: 14).fill(Color.clear))
        .overlay(
            (loud || warn)
            ? RoundedRectangle(cornerRadius: 14)
                .strokeBorder(loud ? Color.theme.neg : Color.theme.warn, lineWidth: loud ? 2 : 1.5)
            : nil
        )
    }

    private func exitRow(_ k: String, _ v: Double) -> some View {
        HStack {
            Text(k).font(.system(size: 15)).foregroundStyle(Color.theme.fg2)
            Spacer()
            Text(fmtMoney(v, sign: true))
                .font(.numeric(size: 15, weight: .bold)).monospacedDigit()
                .foregroundStyle(Color.signed(v))
        }
        .padding(.top, 15)
    }

    // ── Protective put (one line) ──
    private var putSection: some View {
        Group {
            if let p = data.put {
                sectionBox("Protective put") {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("\(AppDates.shortMonthDay(p.expiry)) · $\(fmtStrike(p.strike)) put")
                                .font(.numeric(size: 18, weight: .heavy)).tracking(-0.3).monospacedDigit()
                                .foregroundStyle(Color.theme.fg1)
                            (Text("paid ").foregroundColor(Color.theme.fg3)
                             + Text(fmtMoney(p.costBasisPerShare, decimals: 2)).foregroundColor(Color.theme.fg2).bold()
                             + Text(" → now ").foregroundColor(Color.theme.fg3)
                             + Text(fmtMoney(p.currentMark, decimals: 2)).foregroundColor(Color.theme.fg2).bold())
                                .font(.numeric(size: 13, weight: .medium)).monospacedDigit()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 7) {
                            Text(fmtMoney(p.pnl, sign: true))
                                .font(.numeric(size: 21, weight: .heavy)).tracking(-0.3).monospacedDigit()
                                .foregroundStyle(p.pnl == 0 ? Color.theme.fg3 : Color.signed(p.pnl))
                            Text(p.pnl == 0 ? "flat" : fmtPct(p.pnlPct))
                                .font(.numeric(size: 12, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(p.pnl == 0 ? Color.theme.fg4 : Color.signed(p.pnl))
                        }
                    }
                    .padding(.top, 14)
                }
            }
        }
    }

    // ── History ──
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color.theme.hair).frame(height: 1).padding(.top, 26)
            Button {
                withAnimation(Motion.standard) { historyOpen.toggle() }
            } label: {
                HStack {
                    Text("HISTORY").font(.system(size: 11, weight: .heavy)).tracking(1.3)
                        .foregroundStyle(Color.theme.fg3)
                    Text("\(data.closed.count) closed cycle\(data.closed.count == 1 ? "" : "s")")
                        .font(.numeric(size: 12, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Color.theme.fg4)
                    Spacer()
                    if data.realizedToDate != 0 {
                        Text(fmtMoney(data.realizedToDate, sign: true))
                            .font(.numeric(size: 15, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(Color.signed(data.realizedToDate))
                    }
                    Image(systemName: historyOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.theme.fg4)
                }
                .padding(.top, 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if historyOpen {
                if data.closed.isEmpty {
                    Text("No closed cycles yet — a cycle closes when the call is assigned.")
                        .font(.system(size: 12)).foregroundStyle(Color.theme.fg4).padding(.vertical, 12)
                } else {
                    ForEach(data.closed) { c in historyRow(c) }
                }
            }
        }
    }

    private func historyRow(_ c: CoveredCallCycle) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(AppDates.shortMonthDay(c.cycleStartDate)) – \(c.cycleEndDate.map(AppDates.shortMonthDay) ?? "—")")
                    .font(.numeric(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(Color.theme.fg1)
                Text("\(c.daysHeld) days · \(c.callCount) call\(c.callCount == 1 ? "" : "s")\(c.assignmentStrike.map { " · assigned $\(fmtStrike($0))" } ?? "")")
                    .font(.numeric(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(Color.theme.fg4)
            }
            Spacer()
            Text(fmtMoney(c.realizedPL ?? 0, sign: true))
                .font(.numeric(size: 16, weight: .heavy)).monospacedDigit()
                .foregroundStyle(Color.signed(c.realizedPL ?? 0))
        }
        .padding(.vertical, 15)
        .overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 1) }
    }

    // ── Section scaffold ──
    @ViewBuilder
    private func sectionBox<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color.theme.hair).frame(height: 1).padding(.top, 26)
            Text(title.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(1.3)
                .foregroundStyle(Color.theme.fg3).padding(.top, 14)
            content()
        }
    }
}
