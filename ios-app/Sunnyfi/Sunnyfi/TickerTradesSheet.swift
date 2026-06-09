//
//  TickerTradesSheet.swift
//  Sunnyfi
//
//  Per-ticker position management modal. Six tabs:
//    Shares · Calls sold · Calls bought · Puts sold · Puts bought · History
//
//  Shares tab → Buy / Sell sheets
//  Option tabs → list of PositionCards with Edit / Close / Resolve actions
//  History tab → realized + opens timeline
//

import SwiftUI

struct TickerTradesSheet: View {
    let store: PortfolioStore
    let ticker: String
    /// Which tab to show on first open. Defaults to Shares to preserve
    /// the historical behavior; pass `.lots` when you want the user to
    /// land directly on the lot list.
    var initialTab: Tab = .shares

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab

    @State private var presented: Sheet?

    /// Owns the planner-keyboard focus for the embedded SharesCardView
    /// — passed in as a `FocusState.Binding` so a single shared toolbar
    /// (declared below) handles "Done" dismissal.
    @FocusState private var sharedFocus: String?

    init(
        store: PortfolioStore,
        ticker: String,
        initialTab: Tab = .shares
    ) {
        self.store = store
        self.ticker = ticker
        self.initialTab = initialTab
        _tab = State(initialValue: initialTab)
    }

    enum Tab: String, Hashable {
        case shares, callsSold, callsBought, putsSold, putsBought, lots, history
        var label: String {
            switch self {
            case .shares:       return "Shares"
            case .callsSold:    return "Calls sold"
            case .callsBought:  return "Calls bought"
            case .putsSold:     return "Puts sold"
            case .putsBought:   return "Puts bought"
            case .lots:         return "Lots"
            case .history:      return "History"
            }
        }
    }

    enum Sheet: Identifiable {
        case buyShares, sellShares
        case edit(OptionTradeRow), close(OptionTradeRow), resolve(OptionTradeRow)
        case add
        var id: String {
            switch self {
            case .buyShares: return "buy"
            case .sellShares: return "sell"
            case .add: return "add"
            case .edit(let t): return "edit-\(t.id)"
            case .close(let t): return "close-\(t.id)"
            case .resolve(let t): return "resolve-\(t.id)"
            }
        }
    }

    private var company: Company? {
        store.companies.first(where: { $0.ticker == ticker })
            ?? store.closedCompanies.first(where: { $0.ticker == ticker })
    }

    private var openTradesForTicker: [OptionTradeRow] {
        store.allTrades.filter {
            $0.ticker == ticker
            && $0.action == "open"
            && store.remainingContracts(for: $0) > 0
        }
    }

    private func legs(type: String, direction: String) -> [OptionTradeRow] {
        openTradesForTicker.filter { $0.option_type == type && $0.direction == direction }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Capsule().fill(Color.white.opacity(0.22))
                    .frame(width: 38, height: 5).padding(.top, 4)

                Text("\(ticker) trades")
                    .font(.ui(size: 17, weight: .bold))
                    .foregroundStyle(Color.theme.fg1)

                TabGrid(tab: $tab, counts: counts)

                Group {
                    switch tab {
                    case .shares: sharesTab
                    case .callsSold: optionList(legs(type: "call", direction: "short"), kind: "Calls sold")
                    case .callsBought: optionList(legs(type: "call", direction: "long"), kind: "Calls bought")
                    case .putsSold: optionList(legs(type: "put", direction: "short"), kind: "Puts sold")
                    case .putsBought: optionList(legs(type: "put", direction: "long"), kind: "Puts bought")
                    case .lots: lotsTab
                    case .history: historyTab
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
        .background(Color.theme.page.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        // Single shared keyboard toolbar — covers both planner fields
        // (strike, premium) via the parent-owned sharedFocus state.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { sharedFocus = nil }
                    .font(.ui(size: 15, weight: .semibold))
                    .foregroundStyle(Color.theme.neon)
            }
        }
        .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)
        .sheet(item: $presented) { which in
            switch which {
            case .buyShares:
                BuySharesSheet(store: store, ticker: ticker)
                    .presentationDetents([.medium, .large])
            case .sellShares:
                SellSharesSheet(store: store, ticker: ticker,
                                onHand: company?.legs.first(where: { $0.kind == .stock })?.qty ?? 0)
                    .presentationDetents([.medium, .large])
            case .add:
                AddTradeSheet(store: store, prefillTicker: ticker)
                    .presentationDetents([.large])
            case .edit(let t):
                EditTradeSheet(store: store, trade: t)
                    .presentationDetents([.large])
            case .close(let t):
                CloseTradeSheet(store: store, trade: t)
                    .presentationDetents([.medium, .large])
            case .resolve(let t):
                ResolveTradeSheet(store: store, trade: t)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var counts: [Tab: Int] {
        [
            .shares: Int(company?.legs.first(where: { $0.kind == .stock })?.qty ?? 0),
            .callsSold:   legs(type: "call", direction: "short").count,
            .callsBought: legs(type: "call", direction: "long").count,
            .putsSold:    legs(type: "put",  direction: "short").count,
            .putsBought:  legs(type: "put",  direction: "long").count,
            .lots:        store.fifoLots(for: ticker).count,
            .history: 0,
        ]
    }

    // MARK: - Shares tab

    @ViewBuilder
    private var sharesTab: some View {
        SharesCardView(
            ticker: ticker,
            store: store,
            onBuy:  { presented = .buyShares },
            onSell: { presented = .sellShares },
            sharedFocus: $sharedFocus
        )
    }

    // MARK: - Option lists

    @ViewBuilder
    private func optionList(_ trades: [OptionTradeRow], kind: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(kind.uppercased()) · this name")
                    .font(.ui(size: 9.5, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Color.theme.fg3)
                Spacer()
                Button {
                    presented = .add
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add")
                    }
                    .font(.ui(size: 12, weight: .semibold))
                    .foregroundStyle(Color.theme.neon)
                }
                .buttonStyle(.pressable)
            }

            if trades.isEmpty {
                VStack {
                    Text("No \(kind.lowercased()) on \(ticker).")
                        .font(.ui(size: 13))
                        .foregroundStyle(Color.theme.fg3)
                }
                .frame(maxWidth: .infinity)
                .padding(26)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xl)
                        .strokeBorder(Color.theme.hair, lineWidth: 0.5)
                )
            } else {
                ForEach(trades, id: \.id) { t in
                    PositionCardView(
                        trade: t,
                        store: store,
                        onEdit: { presented = .edit(t) },
                        onClose: { presented = .close(t) },
                        onResolve: { presented = .resolve(t) }
                    )
                }
            }
        }
    }

    // MARK: - Lots tab

    @ViewBuilder
    private var lotsTab: some View {
        let lots = store.fifoLots(for: ticker)
        let spot = store.spot(for: ticker)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LOTS · FIFO ORDER")
                    .font(.ui(size: 9.5, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Color.theme.fg3)
                Spacer()
                if !lots.isEmpty {
                    let totalQty = lots.reduce(0) { $0 + $1.qty_remaining }
                    Text("\(Int(totalQty).formatted(.number.grouping(.never))) sh in \(lots.count) lot\(lots.count == 1 ? "" : "s")")
                        .font(.numeric(size: 11))
                        .foregroundStyle(Color.theme.fg3)
                }
            }

            if lots.isEmpty {
                Text("No lots on file. Either no shares held or share_lots not yet seeded.")
                    .font(.ui(size: 13))
                    .foregroundStyle(Color.theme.fg3)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(lots) { lot in
                        lotRowCard(lot, spot: spot)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lotRowCard(_ lot: ShareLotRow, spot: Double) -> some View {
        let dateShort = AppDates.shortMonthDay(lot.acquired_date)
        let unrealized = (spot - lot.cost_per_share) * lot.qty_remaining
        let pctChange = lot.cost_per_share > 0
            ? (spot - lot.cost_per_share) / lot.cost_per_share * 100 : 0

        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Lot #\(lot.fifo_order)")
                        .font(.ui(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.theme.fg3)
                    if lot.source == "assignment" {
                        Text("ASSIGNED")
                            .font(.ui(size: 9, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(Color.theme.neon)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.theme.tintNeon))
                    } else if lot.source == "seed" {
                        Text("IMPORTED")
                            .font(.ui(size: 9, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(Color.theme.fg3)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.theme.tintMuted))
                    }
                }
                Text("\(Int(lot.qty_remaining).formatted(.number.grouping(.never))) sh @ $\(String(format: "%.2f", lot.cost_per_share))")
                    .font(.numeric(size: 14, weight: .semibold))
                    .foregroundStyle(Color.theme.fg1)
                Text("acquired \(dateShort)")
                    .font(.numeric(size: 10.5))
                    .foregroundStyle(Color.theme.fg3)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(fmtMoney(unrealized, sign: true))
                    .font(.numeric(size: 14, weight: .medium))
                    .foregroundStyle(Color.signed(unrealized))
                Text(fmtPct(pctChange))
                    .font(.numeric(size: 10.5))
                    .foregroundStyle(Color.theme.fg3)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.theme.cardSolid)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .strokeBorder(Color.theme.hair, lineWidth: 0.5)
                )
        )
    }

    // MARK: - History tab

    @ViewBuilder
    private var historyTab: some View {
        let rows = HistoryDeriver.rows(for: ticker, trades: store.allTrades, shareSells: store.allShareSells)
        VStack(alignment: .leading, spacing: 12) {
            Text("ALL TRADES · \(ticker)")
                .font(.ui(size: 9.5, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Color.theme.fg3)

            if rows.isEmpty {
                Text("No history yet.")
                    .font(.ui(size: 13))
                    .foregroundStyle(Color.theme.fg3)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { r in
                        HStack {
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
}

// MARK: - Tab grid (2 rows × 3 cols)

private struct TabGrid: View {
    @Binding var tab: TickerTradesSheet.Tab
    let counts: [TickerTradesSheet.Tab: Int]

    private let order: [TickerTradesSheet.Tab] = [.shares, .callsSold, .callsBought, .putsSold, .putsBought, .lots, .history]

    var body: some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(order, id: \.self) { t in
                let isActive = tab == t
                let count = counts[t] ?? 0
                Button {
                    withAnimation(Motion.standard) { tab = t }
                } label: {
                    HStack(spacing: 5) {
                        Text(t.label)
                            .font(.ui(size: 11, weight: .semibold))
                        if t != .history && count > 0 {
                            Text("\(count)")
                                .font(.numeric(size: 10))
                                .opacity(0.7)
                        }
                    }
                    .foregroundStyle(isActive ? Color.theme.onNeon : Color.theme.fg2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .fill(isActive ? Color.theme.neon : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.lg)
                                    .strokeBorder(isActive ? Color.theme.neon : Color.theme.soft, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.pressable)
            }
        }
    }
}

// MARK: - Position card

/// Per-leg card. The center-pivot **P&L progress bar** is the visual
/// hero — full-width at the top of the stats. For short calls with
/// shares to cover and for any short put, a tall "If assigned" block
/// shows below the stats with the booked-credit math.
struct PositionCardView: View {
    let trade: OptionTradeRow
    let store: PortfolioStore
    let onEdit: () -> Void
    let onClose: () -> Void
    let onResolve: () -> Void

    // ── Derived data (everything pulled live from store) ───────────
    private var remainingContracts: Double { store.remainingContracts(for: trade) }
    private var spot:                Double { store.spot(for: trade.ticker) }
    private var currentMark:         Double { store.currentMark(for: trade) }
    private var unrealizedPL:        Double { store.unrealizedPL(for: trade) }

    private var stockLeg: Leg? {
        store.companies.first(where: { $0.ticker == trade.ticker })?
            .legs.first(where: { $0.kind == .stock })
    }
    private var sharesHeld:    Double { stockLeg?.qty ?? 0 }
    private var stockAvgCost:  Double { stockLeg?.avg ?? 0 }
    private var sharesNeeded:  Double { remainingContracts * 100 }
    private var isCoveredCall: Bool {
        trade.direction == "short" && trade.option_type == "call" && sharesNeeded > 0 && sharesHeld > 0
    }
    private var isShortPut: Bool {
        trade.direction == "short" && trade.option_type == "put"
    }
    private var showAssignmentBlock: Bool { isCoveredCall || isShortPut }

    private var dte: Int? { AppDates.daysUntil(trade.expiry) }

    private var isITM: Bool {
        guard spot > 0 else { return false }
        return trade.option_type == "call" ? spot >= trade.strike : spot <= trade.strike
    }

    private var canResolve: Bool { (dte ?? 999) <= 0 && isITM }

    /// "ITM 0.83%" / "OTM 1.41%" — chip embeds the percentage distance
    /// between spot and strike (normalized against strike). At a glance
    /// the user knows how far the option is from rolling in/out.
    private var moneynessChip: (label: String, fg: Color, bg: Color)? {
        guard spot > 0, trade.strike > 0 else { return nil }
        let pct = abs(spot - trade.strike) / trade.strike * 100
        let pctStr = String(format: "%.2f%%", pct)
        if isITM { return ("ITM \(pctStr)", .theme.neon, .theme.tintNeon) }
        return ("OTM \(pctStr)", .theme.fg2, .theme.tintMuted)
    }

    private var dteText: String {
        guard let n = dte else { return "—" }
        if n < 0 { return "expired \(-n)d ago" }
        if n == 0 { return "today" }
        if n == 1 { return "tomorrow" }
        return "in \(n)d"
    }

    /// Long-form expiry like "expires in 2 days" — used inside the new
    /// design's expiry line so the eye can read it as a sentence
    /// fragment rather than parsing "in 2d".
    private var dteSentence: String {
        guard let n = dte else { return "" }
        if n < 0 { return "expired \(-n) day\(-n == 1 ? "" : "s") ago" }
        if n == 0 { return "expires today" }
        if n == 1 { return "expires tomorrow" }
        return "expires in \(n) days"
    }

    /// "June 20th" — full month name + ordinal day.
    private var expiryLong: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "America/New_York")
        guard let date = df.date(from: trade.expiry) else { return trade.expiry }
        let monthFmt = DateFormatter()
        monthFmt.dateFormat = "MMMM"
        monthFmt.timeZone = df.timeZone
        let dayNumFmt = NumberFormatter()
        dayNumFmt.numberStyle = .ordinal
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = df.timeZone ?? .current
        let day = cal.component(.day, from: date)
        let ordinal = dayNumFmt.string(from: NSNumber(value: day)) ?? "\(day)"
        return "\(monthFmt.string(from: date)) \(ordinal)"
    }

    /// Company display name from store, falling back to the static
    /// TickerNames map and finally the bare ticker.
    private var displayName: String {
        if let n = store.companies.first(where: { $0.ticker == trade.ticker })?.name, !n.isEmpty {
            return n
        }
        return TickerNames.name(for: trade.ticker) ?? trade.ticker
    }

    /// Total open option legs on this ticker — used by the header
    /// "N legs" count, regardless of any active filter.
    private var totalOpenLegsForTicker: Int {
        store.allTrades.filter {
            $0.ticker == trade.ticker
            && $0.action == "open"
            && store.remainingContracts(for: $0) > 0
        }.count
    }

    /// "Sold" for short / "Bought" for long.
    private var sideLabel: String {
        trade.direction == "short" ? "Sold" : "Bought"
    }

    /// Per-leg net Δ — Δ per share × direction × contracts × 100.
    private var legDelta: Double? {
        guard let perShareDelta = store.allGreeks.first(where: { $0.option_trade_id == trade.id })?.delta
        else { return nil }
        let directionMul: Double = trade.direction == "short" ? -1 : 1
        return perShareDelta * directionMul * remainingContracts * 100
    }

    // MARK: - Sub-views

    // MARK: - Ticker header (top of card)

    /// "META  $600.47" + "Meta Platforms · 4 legs" + divider.
    @ViewBuilder
    private var tickerHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(trade.ticker)
                    .font(.ui(size: 24, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(Color.theme.fg1)
                Text(spot > 0 ? fmtMoney(spot, decimals: 2) : "—")
                    .font(.numeric(size: 14, weight: .medium))
                    .foregroundStyle(Color.theme.fg2)
                Spacer()
            }
            let n = totalOpenLegsForTicker
            Text("\(displayName) · \(n) leg\(n == 1 ? "" : "s")")
                .font(.numeric(size: 13))
                .foregroundStyle(Color.theme.fg3)
        }
    }

    // MARK: - Identity row (strike · Call · Sold + OTM/ITM pill)

    @ViewBuilder
    private var identityRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("$\(fmtStrike(trade.strike)) \(trade.option_type.capitalized) · \(sideLabel)")
                .font(.ui(size: 22, weight: .heavy))
                .tracking(-0.4)
                .foregroundStyle(Color.theme.fg1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer(minLength: 0)

            if let chip = moneynessChip {
                Text(chip.label)
                    .font(.numeric(size: 11))
                    .tracking(0.4)
                    .foregroundStyle(chip.fg)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(chip.bg)
                            .overlay(Capsule().strokeBorder(Color.theme.borderBright, lineWidth: 1))
                    )
            }
        }
    }

    /// Sentence-cased expiry line: "for June 20th · expires in 2 days".
    /// Date + the bolded portion of the duration sit in fg1; the
    /// connective words ("for", "expires in", "·") sit in fg3.
    @ViewBuilder
    private var expiryLine: some View {
        let n = dte ?? 0
        // (leading-connective, bold-portion) split — leading reads as
        // a verb phrase, bold reads as the key value.
        let (durLead, durBold): (String, String) = {
            if n < 0 { return ("expired ", "\(-n) day\(-n == 1 ? "" : "s") ago") }
            if n == 0 { return ("expires ", "today") }
            if n == 1 { return ("expires ", "tomorrow") }
            return ("expires in ", "\(n) days")
        }()

        HStack(spacing: 4) {
            (Text("for ").foregroundStyle(Color.theme.fg3)
             + Text(expiryLong).foregroundStyle(Color.theme.fg1).fontWeight(.semibold)
             + Text(" · ").foregroundStyle(Color.theme.fg3)
             + Text(durLead).foregroundStyle(Color.theme.fg3)
             + Text(durBold).foregroundStyle(Color.theme.fg1).fontWeight(.semibold))
                .font(.ui(size: 14))
            Spacer(minLength: 0)
        }
    }

    /// "5 contracts @ $3.15" left + "NET Δ +62" right.
    @ViewBuilder
    private var contractsLine: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(Int(remainingContracts)) contracts @ $\(String(format: "%.2f", trade.premium))")
                .font(.numeric(size: 13))
                .foregroundStyle(Color.theme.fg2)
            Spacer()
            HStack(spacing: 6) {
                Text("NET Δ")
                    .font(.ui(size: 11, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.theme.fg3)
                Text(legDelta.map { fmtGreek($0) } ?? "—")
                    .font(.numeric(size: 13, weight: .semibold))
                    .foregroundStyle(Color.theme.fg1)
            }
        }
    }

    // MARK: - Hero (HTML .lc-hero) — unrealized number + colored P&L track

    /// Inset block — centered:
    ///   +$810  +51% (pill)
    ///   Unrealized · mark $1.53
    ///   [gauge bar with handle]
    ///   $1,575 collected
    @ViewBuilder
    private var legHero: some View {
        let positionSize = trade.premium * remainingContracts * 100
        let unreal = unrealizedPL
        let pctOfMax: Double = positionSize > 0 ? unreal / positionSize : 0
        let toneVal: Color = unreal >= 0 ? Color.theme.pos : Color.theme.neg
        let collectedLabel: String = trade.direction == "short" ? "collected" : "spent"

        VStack(alignment: .center, spacing: 14) {
            // Big unrealized + % pill, side by side, centered.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(fmtMoney(unreal, sign: true))
                    .font(.ui(size: 34, weight: .heavy))
                    .tracking(-1.0)
                    .foregroundStyle(toneVal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(String(format: "%+.0f%%", pctOfMax * 100))
                    .font(.numeric(size: 12, weight: .semibold))
                    .foregroundStyle(Color.theme.fg3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.theme.tintMuted))
            }

            // "Unrealized · mark $1.53"
            Text("Unrealized · mark $\(String(format: "%.2f", currentMark))")
                .font(.numeric(size: 12))
                .foregroundStyle(Color.theme.fg3)

            // Gauge bar — handle moves left as P&L improves.
            LegPnLTrack(
                entryPremium: trade.premium,
                currentMark: currentMark,
                isShort: trade.direction == "short",
                positionSize: positionSize
            )

            // "$1,575 collected" centered — replaces the prior 3-spread
            // (+$X / entry $Y / uncapped) endpoint labels.
            (Text(fmtMoney(positionSize))
                .foregroundStyle(Color.theme.fg1).fontWeight(.semibold)
             + Text(" \(collectedLabel)")
                .foregroundStyle(Color.theme.fg3))
                .font(.numeric(size: 13))
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.theme.page2)
        )
    }

    // MARK: - Mini stat line (HTML .lc-mini)

    /// Tiny mono inline list: CREDIT/DEBIT, SPOT, NET Δ — replaces the
    /// previous 3-cell card so the hero number above isn't competing
    /// with a same-weight stat block.
    @ViewBuilder
    private var miniLine: some View {
        let sizeLabel = trade.direction == "short" ? "Credit" : "Debit"
        let positionSize = trade.premium * remainingContracts * 100
        // Per-leg net Δ — direction-signed delta-per-share × contracts × 100.
        let perShareDelta = store.allGreeks.first(where: { $0.option_trade_id == trade.id })?.delta
        let directionMul: Double = trade.direction == "short" ? -1 : 1
        let legDelta: Double? = perShareDelta.map { $0 * directionMul * remainingContracts * 100 }
        // Label-above-value so a multi-thousand number like "$1,170"
        // can never wrap mid-digit at narrow widths.
        HStack(alignment: .top, spacing: 0) {
            miniCell(label: sizeLabel, value: fmtMoney(positionSize))
            miniCell(label: "Spot",    value: spot > 0 ? fmtMoney(spot, decimals: 2) : "—")
            miniCell(label: "Net Δ",   value: legDelta.map { fmtGreek($0) } ?? "—")
        }
    }

    @ViewBuilder
    private func miniCell(label: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(label.uppercased())
                .font(.ui(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.theme.fg3)
            Text(value)
                .font(.numeric(size: 15, weight: .medium))
                .foregroundStyle(Color.theme.fg1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    /// Flat insight section — sits directly on the card surface below
    /// the dashed divider. Eyebrow row + two-column FIFO/PROFIT stats.
    /// The card-level chrome already provides containment, so no inset
    /// card here.
    @ViewBuilder
    private var assignmentBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            insightEyebrow
            if isCoveredCall {
                coveredCallStats
            } else if isShortPut {
                shortPutStats
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Eyebrow: ✦ INSIGHT · IF ASSIGNED IN 2D · 500 SH COVERED
    /// All neon, all caps, mono tracking.
    @ViewBuilder
    private var insightEyebrow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.theme.neon)
            Text(eyebrowText)
                .font(.ui(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color.theme.neon)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
    }

    /// "INSIGHT · IF ASSIGNED · 500 SHARES" — short, no DTE noise (the
    /// expiry is right above on the card) and no COVERED suffix
    /// (coverage state already implied by the FIFO AVG basis below).
    private var eyebrowText: String {
        if isCoveredCall {
            return "INSIGHT · IF ASSIGNED · \(Int(sharesNeeded)) SHARES"
        }
        if isShortPut {
            return "INSIGHT · IF ASSIGNED · \(Int(sharesNeeded)) SHARES"
        }
        return "INSIGHT · IF ASSIGNED"
    }

    /// Two-column FIFO AVG + PROFIT stat block (HTML body of .lc-insight).
    @ViewBuilder
    private var coveredCallStats: some View {
        let plan = store.fifoSimulate(ticker: trade.ticker, qty: sharesNeeded, sellPrice: trade.strike)
        let fifoConsumedQty = plan.reduce(0) { $0 + $1.qtyConsumed }
        let fifoTotalCost   = plan.reduce(0) { $0 + $1.qtyConsumed * $1.lot.cost_per_share }
        let fifoBasis: Double = fifoConsumedQty > 0
            ? fifoTotalCost / fifoConsumedQty
            : stockAvgCost
        let sharesPnL: Double = plan.isEmpty
            ? (trade.strike - stockAvgCost) * min(sharesHeld, sharesNeeded)
            : plan.reduce(0) { $0 + $1.realizedPL }
        let premiumReceived = trade.premium * remainingContracts * 100
        let totalBooked = premiumReceived + sharesPnL

        HStack(alignment: .top, spacing: 0) {
            insightStat(label: "FIFO AVG",
                        value: "$\(String(format: "%.2f", fifoBasis))",
                        tone: Color.theme.fg1)
            insightStat(label: "PROFIT",
                        value: fmtMoney(totalBooked, sign: true),
                        tone: Color.signed(totalBooked),
                        caption: "if exercised")
        }
    }

    @ViewBuilder
    private var shortPutStats: some View {
        let netBasisPerShare = trade.strike - trade.premium
        let instantPaper = (spot - netBasisPerShare) * sharesNeeded

        HStack(alignment: .top, spacing: 0) {
            insightStat(label: "NET BASIS",
                        value: "$\(String(format: "%.2f", netBasisPerShare))",
                        tone: Color.theme.fg1)
            insightStat(label: "PAPER",
                        value: fmtMoney(instantPaper, sign: true),
                        tone: Color.signed(instantPaper))
        }
    }

    @ViewBuilder
    private func insightStat(label: String, value: String, tone: Color, caption: String? = nil) -> some View {
        // Mono numbers, medium weight — keeps the stat block readable
        // without competing with the unrealized hero above.
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.ui(size: 10, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.theme.fg3)
            Text(value)
                .font(.numeric(size: 26, weight: .medium))
                .tracking(-0.4)
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.ui(size: 10))
                    .foregroundStyle(Color.theme.fg3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // (removed: legacy insight helpers — replaced by inline insightLine + assignmentBlock above)

    /// Edit · Close · (Resolve if expired+ITM)
    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 8) {
            actionButton("Edit", action: onEdit)
            actionButton("Close", action: onClose)
            if canResolve {
                actionButton("Resolve", action: onResolve, accent: true)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            tickerHeader
            Rectangle()
                .fill(Color.theme.borderBright)
                .frame(height: 1)
                .padding(.vertical, -4)

            identityRow
            expiryLine
            contractsLine

            legHero

            if showAssignmentBlock {
                // Dashed divider per the new design — softer break
                // between the live P&L and the if-assigned projection.
                DashedHairline()
                    .padding(.vertical, -2)
                assignmentBlock
            }

            actionRow
        }
        .padding(20)
        .background(
            // Light-mode: warm surface + soft elevation shadow.
            // Dark-mode: original teal-black gradient + neon glow.
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
                        .strokeBorder(Color.theme.borderBright, lineWidth: 1)
                )
                .shadow(color: Color.cardGrad.glow, radius: 12, x: 0, y: 0)
        )
    }

    @ViewBuilder
    private func actionButton(_ label: String, action: @escaping () -> Void, accent: Bool = false) -> some View {
        // Capsule-shaped, uppercase-tracked, hairline border —
        // matches the redesigned card's EDIT / CLOSE buttons.
        Button(action: action) {
            Text(label.uppercased())
                .font(.ui(size: 13, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(accent ? Color.theme.neon : Color.theme.fg2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(accent ? Color.theme.tintNeon : Color.clear)
                        .overlay(
                            Capsule().strokeBorder(
                                accent ? Color.theme.neon.opacity(0.4) : Color.theme.borderBright,
                                lineWidth: 1
                            )
                        )
                )
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Long-shares card (Phase 3 / 4)

/// Shares position card. Same visual language as the option PositionCardView
/// (gradient + neon outline + center-pivot progress bar) plus a FIFO
/// insight inset driven by a **calls-to-sell stepper** — adjust the stepper
/// and the lot list + realized P&L recompute live.
///
/// Default stepper value = total currently-open short call contracts for
/// the ticker (so the card immediately shows "if all my existing calls
/// get exercised, this is what books"). User can change it freely.
struct SharesCardView: View {
    let ticker: String
    let store: PortfolioStore
    let onBuy: () -> Void
    let onSell: () -> Void
    /// Called when the user taps "View lots →". Parent opens the
    /// per-ticker modal with the Lots tab pre-selected.
    var onShowLots: () -> Void = {}

    @State private var callsToSell: Double = 0
    @State private var didInit: Bool = false
    /// Free-form OTM strike per contract. Empty → defaults to spot.
    @State private var strikeText: String = ""
    /// Premium per contract you'd receive. Empty → 0 (no premium component).
    @State private var premiumText: String = ""

    /// Shared focus binding owned by the parent screen — a single
    /// `@FocusState` at the parent means one keyboard toolbar across
    /// all SharesCardView instances (instead of N stacked Done
    /// buttons). The value is a unique ticker-scoped String per field.
    @FocusState.Binding var sharedFocus: String?

    /// Per-field IDs — unique across all cards in the planner stack.
    private var strikeFieldID: String  { "\(ticker).strike" }
    private var premiumFieldID: String { "\(ticker).premium" }

    // ── Derived values ─────────────────────────────────────────────
    private var stockLeg: Leg? {
        store.companies.first(where: { $0.ticker == ticker })?
            .legs.first(where: { $0.kind == .stock })
    }
    private var sharesHeld: Double { stockLeg?.qty ?? 0 }
    private var avgCost:    Double { stockLeg?.avg ?? 0 }
    private var spot:       Double { store.spot(for: ticker) }
    private var marketValue: Double { sharesHeld * spot }
    private var unrealizedPL: Double { (spot - avgCost) * sharesHeld }
    private var pctUnreal: Double {
        sharesHeld > 0 && avgCost > 0 ? (spot - avgCost) / avgCost * 100 : 0
    }

    /// Lifetime premium received from short opens (matches
    /// PerformanceData's convention). Used for the "net price" math.
    private var lifetimePremium: Double {
        store.allTrades
            .filter { $0.ticker == ticker && $0.action == "open" && $0.direction == "short" }
            .reduce(0) { $0 + $1.premium * $1.contracts * 100 }
    }
    /// Effective basis = avg − cumulative-premium-per-share.
    private var netPrice: Double {
        sharesHeld > 0 ? avgCost - (lifetimePremium / sharesHeld) : avgCost
    }

    /// Open short call contracts already written against this ticker.
    /// These shares are spoken for, so the planner subtracts them from
    /// available coverage before suggesting how many more can be sold.
    private var openShortCallContracts: Double {
        let openShorts = store.allTrades.filter {
            $0.ticker == ticker
            && $0.action == "open"
            && $0.direction == "short"
            && $0.option_type == "call"
            && store.remainingContracts(for: $0) > 0
        }
        return openShorts.reduce(0.0) { $0 + store.remainingContracts(for: $1) }
    }

    /// Total physical coverage capacity (shares ÷ 100, floored).
    private var totalCoverageCapacity: Double { max(0, floor(sharesHeld / 100)) }

    /// Default calls in the stepper = "1 more" if there's room, else 0.
    /// The planner now represents *new* calls to write rather than total
    /// exposure, so the default no longer pre-fills with the existing
    /// short stack.
    private var defaultCalls: Double {
        maxCallsAllowed >= 1 ? 1 : 0
    }

    /// Hard ceiling = remaining uncovered share blocks. Shares already
    /// covering open short calls don't count — so on HOOD with 1500
    /// shares and 10 calls already sold, the planner caps at 5 more.
    private var maxCallsAllowed: Double {
        max(0, totalCoverageCapacity - openShortCallContracts)
    }
    private var atMaxCoverage: Bool { callsToSell >= maxCallsAllowed }

    private var sharesToSell: Double { callsToSell * 100 }
    /// Strike user typed, fallback to spot. Used as the assumed exercise
    /// price when simulating FIFO consumption.
    private var effectiveStrike: Double {
        let parsed = Double(strikeText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: ""))
        return (parsed ?? 0) > 0 ? parsed! : spot
    }
    /// Premium per contract user typed. Empty → 0.
    private var effectivePremium: Double {
        Double(premiumText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")) ?? 0
    }
    /// Total premium credit you'd pocket today (premium × contracts × 100).
    private var premiumCredit: Double { effectivePremium * callsToSell * 100 }
    private var consumption: [LotConsumption] {
        store.fifoSimulate(ticker: ticker, qty: sharesToSell, sellPrice: effectiveStrike)
    }
    /// Realized P&L from being called away at strike (FIFO).
    private var sharesRealizedPL: Double { consumption.reduce(0) { $0 + $1.realizedPL } }
    /// Combined: premium received + shares P&L if exercised at strike.
    private var realizedPL: Double { sharesRealizedPL + premiumCredit }
    private var weightedAvgFIFO: Double {
        let q = consumption.reduce(0) { $0 + $1.qtyConsumed }
        guard q > 0 else { return 0 }
        let total = consumption.reduce(0) { $0 + $1.qtyConsumed * $1.lot.cost_per_share }
        return total / q
    }
    private var coverageOK: Bool {
        consumption.reduce(0) { $0 + $1.qtyConsumed } >= sharesToSell
    }

    // ── Body — Navi-light planner redesign ─────────────────────────
    //
    // Top:    ticker header (ticker + spot + "N LOTS ›" pill) + hairline
    // Stats:  3-col POSITION / AVG COST / UNREALIZED — UNREALIZED $ is
    //         colored, %% is muted (same rule as everywhere else)
    // Inset:  page-2 surface combining the calls-to-sell stepper with
    //         the STRIKE/PREMIUM inputs and the FIFO AVG / PROFIT
    //         outcome stats
    // Action: capsule BUY / SELL pills matching the position card
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            tickerHeader
            Rectangle()
                .fill(Color.theme.borderBright)
                .frame(height: 1)
                .padding(.vertical, -4)

            statsRow

            plannerInset

            actionRow
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(
                    LinearGradient(
                        colors: [Color.cardGrad.top, Color.cardGrad.bot],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl)
                        .strokeBorder(Color.theme.borderBright, lineWidth: 1)
                )
                .shadow(color: Color.cardGrad.glow, radius: 12, x: 0, y: 0)
        )
        .onAppear {
            if !didInit { callsToSell = defaultCalls; didInit = true }
        }
        // Keyboard dismissal is handled at the parent ScrollView via
        // `.scrollDismissesKeyboard(.interactively)` — attaching a
        // `.toolbar` here would aggregate one Done button per card
        // (13× tickers in the planner stack = 13 Done buttons).
    }

    // ── Ticker header ─────────────────────────────────────────────
    // "META  $600.00" + "N LOTS ›" pill button right. Mirrors the
    // PositionCardView header so both card families share a top row.
    @ViewBuilder
    private var tickerHeader: some View {
        let lotCount = store.fifoLots(for: ticker).count
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(ticker)
                .font(.ui(size: 24, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(Color.theme.fg1)
            Text(spot > 0 ? fmtMoney(spot, decimals: 2) : "—")
                .font(.numeric(size: 14, weight: .medium))
                .foregroundStyle(Color.theme.fg2)
            Spacer()
            Button(action: onShowLots) {
                HStack(spacing: 4) {
                    Text("\(lotCount) LOT\(lotCount == 1 ? "" : "S")")
                        .font(.ui(size: 10, weight: .bold))
                        .tracking(1.0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Color.theme.neon)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color.theme.tintNeon)
                        .overlay(Capsule().strokeBorder(Color.theme.neon.opacity(0.3), lineWidth: 1))
                )
            }
            .buttonStyle(.pressable)
        }
    }

    // ── Stats row — POSITION / AVG COST / UNREALIZED ─────────────
    // Three left-aligned columns, no vertical dividers. UNREALIZED
    // follows the app-wide rule: $ value carries the signal color,
    // % drops to fg3 muted.
    @ViewBuilder
    private var statsRow: some View {
        HStack(alignment: .top, spacing: 8) {
            statCell(label: "POSITION",
                     value: Int(sharesHeld).formatted(.number.grouping(.automatic)),
                     valueTone: Color.theme.fg1)

            statCell(label: "AVG COST",
                     value: fmtMoney(avgCost, decimals: 2),
                     valueTone: Color.theme.fg1,
                     caption: "net $\(String(format: "%.2f", netPrice))")

            statCell(label: "UNREALIZED",
                     value: fmtMoney(unrealizedPL, sign: true),
                     valueTone: Color.signed(unrealizedPL),
                     caption: fmtPct(pctUnreal))
        }
    }

    @ViewBuilder
    private func statCell(label: String, value: String, valueTone: Color,
                          caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.ui(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color.theme.fg3)
            // Smaller + lighter weight so 3 stacked numbers don't crowd
            // each other at iPhone widths. Mono so the $-aligned digits
            // line up across columns.
            Text(value)
                .font(.numeric(size: 17, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(valueTone)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.numeric(size: 11))
                    .foregroundStyle(Color.theme.fg3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ── Planner inset — unified page-2 surface ───────────────────
    //
    // Big stepper at the top (− outlined circle, count + "remaining"
    // caption centered, + filled neon circle), then STRIKE / PREMIUM
    // inputs, then FIFO AVG / PROFIT outcome stats. Matches the new
    // design pixel-for-pixel. When the user can't cover any calls we
    // fall back to a warning state instead of the stepper.
    @ViewBuilder
    private var plannerInset: some View {
        VStack(alignment: .leading, spacing: 22) {
            if maxCallsAllowed < 1 {
                coverageEmptyState
            } else {
                plannerStepper
            }

            // Strike + Premium inputs — only relevant when the user
            // actually has coverage to simulate.
            if maxCallsAllowed >= 1 {
                HStack(spacing: 12) {
                    plannerInputField(
                        label: "STRIKE",
                        placeholder: String(format: "%.2f", spot),
                        text: $strikeText,
                        fieldID: strikeFieldID
                    )
                    plannerInputField(
                        label: "PREMIUM / CONTRACT",
                        placeholder: "0.00",
                        text: $premiumText,
                        fieldID: premiumFieldID
                    )
                }

                // FIFO AVG / PROFIT outcome stats.
                plannerOutcomeStats
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.theme.page2)
        )
    }

    // Stepper row: outlined − on the left, big count + "N remaining"
    // caption centered, filled neon + on the right.
    @ViewBuilder
    private var plannerStepper: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                callsToSell = max(1, callsToSell - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.theme.fg2)
                    .frame(width: 54, height: 54)
                    .background(
                        Circle()
                            .fill(Color.theme.surface)
                            .overlay(Circle().strokeBorder(Color.theme.borderBright, lineWidth: 1))
                    )
            }
            .buttonStyle(.pressable)
            .disabled(callsToSell <= 1)
            .opacity(callsToSell <= 1 ? 0.5 : 1)

            VStack(spacing: 4) {
                Text("\(Int(callsToSell))")
                    .font(.ui(size: 32, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundStyle(Color.theme.fg1)
                if atMaxCoverage && maxCallsAllowed >= 1 {
                    Text("MAX COVERAGE")
                        .font(.ui(size: 10, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(Color.theme.warn)
                } else {
                    Text("\(Int(maxCallsAllowed - callsToSell)) remaining")
                        .font(.numeric(size: 12))
                        .foregroundStyle(Color.theme.fg3)
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                if callsToSell < maxCallsAllowed { callsToSell += 1 }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.theme.onNeon)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Color.theme.neon))
            }
            .buttonStyle(.pressable)
            .disabled(atMaxCoverage)
            .opacity(atMaxCoverage ? 0.5 : 1)
        }
    }

    // FIFO AVG + PROFIT stat columns — big heavy numbers in
    // ink/signed-color, "if exercised" caption muted under PROFIT.
    @ViewBuilder
    private var plannerOutcomeStats: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("FIFO AVG")
                    .font(.ui(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.theme.fg3)
                Text(consumption.isEmpty
                     ? "—"
                     : "$\(String(format: "%.2f", weightedAvgFIFO))")
                    .font(.ui(size: 28, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundStyle(Color.theme.fg1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("PROFIT")
                    .font(.ui(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.theme.fg3)
                Text(consumption.isEmpty
                     ? "—"
                     : fmtMoney(realizedPL, sign: true))
                    .font(.ui(size: 28, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundStyle(consumption.isEmpty ? Color.theme.fg4 : Color.signed(realizedPL))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !consumption.isEmpty {
                    Text("if exercised")
                        .font(.numeric(size: 12))
                        .foregroundStyle(Color.theme.fg3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Coverage-blocked state — replaces the stepper when the user
    // can't write any new calls (no shares, or all blocks already
    // covered).
    @ViewBuilder
    private var coverageEmptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.theme.warn)
            Text(totalCoverageCapacity < 1
                 ? "Need 100+ shares to cover one call (\(Int(sharesHeld)) on hand)."
                 : "All \(Int(totalCoverageCapacity)) share-blocks already covered by \(Int(openShortCallContracts)) open short calls.")
                .font(.ui(size: 13, weight: .medium))
                .foregroundStyle(Color.theme.fg2)
            Spacer()
        }
        .padding(.vertical, 6)
    }

    /// Compact labeled text field used for the STRIKE / PREMIUM inputs
    /// in the planner. Decimal keyboard, $-prefixed. Inset surface uses
    /// `page2` so it reads as a recessed slot in both light and dark.
    /// A "Done" toolbar above the keyboard dismisses focus — decimal
    /// pad has no Return key, so without it the keyboard gets stuck.
    @ViewBuilder
    private func plannerInputField(label: String, placeholder: String, text: Binding<String>, fieldID: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.ui(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color.theme.fg3)
            HStack(spacing: 2) {
                Text("$")
                    .font(.numeric(size: 14, weight: .semibold))
                    .foregroundStyle(Color.theme.fg3)
                TextField(placeholder, text: text)
                    .keyboardType(.decimalPad)
                    .focused($sharedFocus, equals: fieldID)
                    .font(.numeric(size: 14, weight: .semibold))
                    .foregroundStyle(Color.theme.fg1)
                    .tint(Color.theme.neon)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.theme.page2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                sharedFocus == fieldID ? Color.theme.neon.opacity(0.5) : Color.theme.borderBright,
                                lineWidth: 1
                            )
                    )
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ── Actions — BUY / SELL capsule pills matching the position card.
    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 12) {
            plannerActionButton(label: "Buy", action: onBuy)
            plannerActionButton(label: "Sell", action: onSell)
        }
    }

    @ViewBuilder
    private func plannerActionButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(.ui(size: 13, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.theme.neon)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(Color.clear)
                        .overlay(
                            Capsule().strokeBorder(Color.theme.borderBright, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Dashed hairline divider
//
// 1px horizontal dashed line in the muted divider color. Used inside
// position cards to separate the live P&L from the if-assigned
// projection — softer than a solid hairline.

struct DashedHairline: View {
    var color: Color = Color.theme.fg5
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0.5))
                p.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
        .frame(height: 1)
    }
}

// MARK: - Leg P&L gauge track
//
// HTML .lc-track — max-profit → entry → max-loss spectrum with an
// entry pivot line (35%) and a handle (dot) at the current mark's
// position. Always rendered as green-on-left/red-on-right; for both
// short and long, the handle is left of entry when in profit and
// right of entry when in loss. Endpoint labels swap so the side that
// represents profit on this leg shows the bounded value.

private struct LegPnLTrack: View {
    let entryPremium: Double      // entry price per share
    let currentMark: Double       // live mark per share
    let isShort: Bool
    let positionSize: Double      // entry premium × ct × 100

    /// Entry pivot is fixed at the center of the bar — the handle moves
    /// symmetrically left (into profit) or right (into loss) from there.
    private let entryX: Double = 0.5

    /// Profit/loss per share, sign-corrected for direction.
    private var pnlPerShare: Double {
        let raw = currentMark - entryPremium
        return isShort ? -raw : raw
    }
    /// Normalized P&L: +1.0 = handle at max-profit edge, -1.0 = max-loss.
    /// Clamped to [-1, +1] so even deep losses stay on the bar.
    private var pnlNorm: Double {
        guard entryPremium > 0 else { return 0 }
        let v = pnlPerShare / entryPremium
        return max(-1.0, min(1.0, v))
    }
    /// Handle position on [0,1]. Symmetric around the 0.5 entry pivot.
    private var handleX: Double {
        return entryX + (-pnlNorm) * 0.5    // negative because right = loss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The track
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.theme.pos,                location: 0.00),
                                    .init(color: Color.theme.pos.opacity(0.60),  location: 0.45),
                                    .init(color: Color.theme.warn.opacity(0.80), location: 0.55),
                                    .init(color: Color.theme.neg,                location: 1.00)
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )

                    // Entry pivot vertical line.
                    Rectangle()
                        .fill(Color.theme.fg1)
                        .frame(width: 2, height: 26)
                        .position(x: CGFloat(entryX) * w, y: 7)

                    // Handle — colored by current P&L side.
                    ZStack {
                        Circle()
                            .fill(Color.theme.surface)
                            .frame(width: 30, height: 30)
                        Circle()
                            .fill(pnlPerShare >= 0 ? Color.theme.pos : Color.theme.neg)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.theme.surface, lineWidth: 3)
                            )
                            .shadow(color: (pnlPerShare >= 0 ? Color.theme.pos : Color.theme.neg).opacity(0.4),
                                    radius: 5, x: 0, y: 2)
                    }
                    .position(x: CGFloat(handleX) * w, y: 7)
                    .animation(.spring(response: 0.55, dampingFraction: 0.78), value: handleX)
                }
            }
            .frame(height: 14)
        }
    }
}
