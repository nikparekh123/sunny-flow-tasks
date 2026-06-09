//
//  TradeSheet.swift
//  Sunnyfi
//
//  "Log a fill" full-screen ticket — replaces the prior TradeForkSheet.
//  Per Handoff 2 §8:
//   • ✕ to close (top-left, not a back arrow); no "MIRROR IBKR"
//     decoration.
//   • Native iOS segmented controls for Buy/Sell + Call/Put (Picker
//     with .segmented style).
//   • Ticker chosen via a horizontally-scrolling pill row — never a
//     dropdown.
//   • Contracts is a TYPED FIELD with NO +/− stepper.
//   • Rows: Strike / Fill price / Estimated credit-or-cost. `$` is
//     glued to the number (part of the value text, right-aligned).
//     Empty values render in `fg5` as a placeholder.
//   • Summary strip: Max profit / Breakeven / If exercised.
//   • Always-visible iOS-native-styled number pad docked at the
//     bottom (borderless, big accent digits, `.` bottom-left, `←`
//     bottom-right, no key cells, white background).
//   • Review button pinned in a fixed footer ABOVE the number pad.
//
//  Pre-fill: pass a `TradePreset` to open the ticket with the right
//  side / kind / strike / contracts already set — that's how the
//  swipe-left Close action on a leg routes here.
//

import SwiftUI

// MARK: - Pre-fill

/// Lets callers (e.g. swipe-close on a leg) open the sheet with the
/// ticket pre-populated. `closingTradeId` is non-nil when this ticket
/// is closing an existing leg — the writer uses it to set
/// `option_trades.closes_trade_id` so realized P&L lines up.
struct TradePreset {
    var instrument: TradeSheet.Instrument
    var ticker: String?
    var side: TradeSheet.Side
    var optionType: TradeSheet.OptType = .call
    var contracts: String = "1"
    var qty: String = ""            // shares
    var strike: String = ""
    var price: String = ""          // shares fill price
    var fill: String = ""           // option fill price (for prefill in edit)
    var expiryISO: String? = nil    // pre-fills the expiry date row
    var closingTradeId: String?     // option close: link back to original
    /// When set, this ticket EDITS the referenced option trade row
    /// instead of writing a new one. `save()` calls `updateTrade(_:)`
    /// with a patch instead of `addTrade(_:)`. Mutually exclusive
    /// with `closingTradeId`.
    var editingTradeId: String? = nil
    /// When true, the ticker pills row is hidden and the chosen
    /// ticker is treated as locked. Used by close + edit paths.
    var lockTicker: Bool = false

    static func openOption(ticker: String? = nil) -> TradePreset {
        TradePreset(instrument: .option, ticker: ticker, side: .sell)
    }
    static func openShares(ticker: String? = nil) -> TradePreset {
        TradePreset(instrument: .shares, ticker: ticker, side: .buy)
    }

    /// Pre-fill from an option trade we're closing — flips the side,
    /// keeps strike/contracts/type.
    static func closingOption(_ t: OptionTradeRow, remaining: Double) -> TradePreset {
        TradePreset(
            instrument: .option,
            ticker: t.ticker,
            side: t.direction == "short" ? .buy : .sell,
            optionType: t.option_type == "call" ? .call : .put,
            contracts: "\(Int(remaining))",
            strike: fmtStrike(t.strike),
            closingTradeId: t.id,
            lockTicker: true
        )
    }

    /// Pre-fill from a share position we're closing — sell the held qty.
    static func closingShares(ticker: String, qty: Double) -> TradePreset {
        TradePreset(
            instrument: .shares,
            ticker: ticker,
            side: .sell,
            qty: "\(Int(qty))",
            lockTicker: true
        )
    }

    /// "Expired worthless" close — same close preset as a swipe-
    /// close BUT with the fill price already set to $0.00. User
    /// just reviews + confirms instead of typing zero themselves.
    /// Realized P&L on the close = original premium × ct × 100 for
    /// shorts (kept the credit) / −original premium × ct × 100 for
    /// longs (lost the debit).
    static func expiredWorthless(_ t: OptionTradeRow, remaining: Double) -> TradePreset {
        var p = closingOption(t, remaining: remaining)
        p.fill = "0.00"
        return p
    }

    /// Pre-fill ALL fields from an existing option trade row so the
    /// user can patch a mistake (wrong strike, expiry, fill, etc.).
    /// Side maps from the original direction; type from option_type.
    static func editingOption(_ t: OptionTradeRow) -> TradePreset {
        TradePreset(
            instrument: .option,
            ticker: t.ticker,
            side: t.direction == "short" ? .sell : .buy,
            optionType: t.option_type == "call" ? .call : .put,
            contracts: "\(Int(t.contracts))",
            strike: fmtStrike(t.strike),
            fill: String(format: "%.2f", t.premium),
            expiryISO: t.expiry,
            editingTradeId: t.id,
            lockTicker: true
        )
    }
}

// MARK: - TradeSheet

struct TradeSheet: View {
    let store: PortfolioStore
    var preset: TradePreset
    var onDismiss: () -> Void

    enum Instrument: Hashable { case option, shares }
    enum Side: String, CaseIterable, Identifiable, Hashable {
        case buy = "Buy", sell = "Sell"
        var id: String { rawValue }
    }
    enum OptType: String, CaseIterable, Identifiable, Hashable {
        case call = "Call", put = "Put"
        var id: String { rawValue }
    }

    @State private var ticker: String?
    @State private var side: Side
    @State private var optType: OptType
    @State private var contracts: String
    @State private var qty: String        // shares
    @State private var strike: String
    @State private var fill: String       // option premium
    @State private var price: String      // shares fill price
    @State private var focus: Focus?
    @State private var saving = false
    @State private var error: String?
    @State private var confirming = false
    /// Expiry for option opens — defaults to TODAY so the user
    /// always sets a real expiry (no silent +30d nudge that could
    /// land on the wrong contract). User taps the native inline
    /// DatePicker to move it forward. Ignored for shares and for
    /// option closes (close path uses the original trade's expiry).
    @State private var expiryDate: Date = Date()

    private enum Focus: Hashable {
        case contracts, qty, strike, fill, price
    }

    init(store: PortfolioStore, preset: TradePreset, onDismiss: @escaping () -> Void) {
        self.store = store
        self.preset = preset
        self.onDismiss = onDismiss
        _ticker    = State(initialValue: preset.ticker)
        _side      = State(initialValue: preset.side)
        _optType   = State(initialValue: preset.optionType)
        _contracts = State(initialValue: preset.contracts)
        _qty       = State(initialValue: preset.qty)
        _strike    = State(initialValue: preset.strike)
        _fill      = State(initialValue: preset.fill)
        _price     = State(initialValue: preset.price)
        // Seed the expiry date row from the preset when editing;
        // otherwise default to today. The user always sets the
        // expiry explicitly via the DatePicker — no silent future
        // offset that could land on the wrong contract.
        if let iso = preset.expiryISO, let d = AppDates.parseISODay(iso) {
            _expiryDate = State(initialValue: d)
        } else {
            _expiryDate = State(initialValue: Date())
        }
        // Pre-focus the most-likely-to-edit field for the user's flow.
        _focus     = State(initialValue: preset.instrument == .shares ? .price : .fill)
    }

    // ── Derived ──
    private var K: Double { Double(strike) ?? 0 }
    private var P: Double { Double(fill) ?? 0 }
    private var Ct: Int { max(1, Int(contracts) ?? 1) }
    private var Q: Double { Double(qty) ?? 0 }
    private var Pr: Double { Double(price) ?? 0 }
    private var perContract: Int { Ct * 100 }
    private var grossOption: Double { P * Double(perContract) }
    private var grossShares: Double { Q * Pr }
    private var isCredit: Bool { side == .sell }
    /// Ready to write. Opens require P > 0 (you can't buy/sell an
    /// option for $0). CLOSES allow P == 0 — that's exactly the
    /// case where the leg expired worthless and the user is
    /// logging the close at zero.
    private var optionReady: Bool {
        guard ticker != nil, K > 0 else { return false }
        if preset.closingTradeId != nil {
            return P >= 0   // expired-worthless = legitimate $0 close
        }
        return P > 0
    }
    private var sharesReady: Bool { ticker != nil && Q > 0 && Pr > 0 }

    var body: some View {
        VStack(spacing: 0) {
            tkHead
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if preset.instrument == .option {
                        optionBody
                    } else {
                        sharesBody
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }
            footer
            // Keypad hides during the Review-then-Confirm step so
            // the summary + Confirm button get the bottom of the
            // screen. Animated in/out for continuity.
            if !confirming {
                IOSNumberPad(onKey: pressKey)
                    .transition(.move(edge: .bottom))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.theme.surface.ignoresSafeArea())
        .animation(.easeOut(duration: 0.2), value: confirming)
        .onAppear {
            // Pre-fill seed: when the sheet opens with a ticker
            // already chosen (e.g. user was on the ADBE filter and
            // tapped Trade → Option), seed strike/price from the
            // live spot the same way `pickTicker(_:)` would on a
            // manual pick. Only fills empty fields so user typed
            // values are never overwritten.
            if let t = ticker { seedFromTicker(t) }
        }
    }

    /// Strike seeded at nearest $5 to spot (typical first-cut ATM
    /// strike); shares price seeded at spot. Mirrors `pickTicker`.
    private func seedFromTicker(_ t: String) {
        guard let c = store.companies.first(where: { $0.ticker == t }) else { return }
        if strike.isEmpty, c.spot > 0 {
            let rounded = (c.spot / 5).rounded() * 5
            strike = String(Int(rounded))
        }
        if price.isEmpty, c.spot > 0 {
            price = String(format: "%.2f", c.spot)
        }
    }

    // MARK: Head

    private var tkHead: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.theme.fg2)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.theme.surface))
                    .overlay(Circle().strokeBorder(Color.theme.borderBright, lineWidth: 1))
            }
            Text(preset.instrument == .option ? "Option" : "Shares")
                .font(.system(size: 20, weight: .heavy))
                .tracking(-0.6)
                .foregroundStyle(Color.theme.fg1)
                .padding(.leading, 4)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: Option body

    @ViewBuilder
    private var optionBody: some View {
        if preset.closingTradeId != nil {
            // CLOSE flow — side / type / strike / ticker are all
            // determined by the original leg.
            closingHeaderOption.padding(.top, 4)
        } else if preset.editingTradeId != nil {
            // EDIT flow — ticker is locked, but the user can still
            // change side / type / strike / expiry / fill (that's
            // the whole point of editing). Header + pickers, no
            // ticker pills.
            editingHeaderOption.padding(.top, 4)
            HStack(spacing: 10) {
                Picker("Side", selection: $side) {
                    ForEach(Side.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Type", selection: $optType) {
                    ForEach(OptType.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .padding(.top, 14)
        } else {
            // OPEN flow — pick side, type, ticker.
            HStack(spacing: 10) {
                Picker("Side", selection: $side) {
                    ForEach(Side.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Type", selection: $optType) {
                    ForEach(OptType.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            // Ticker pills only when no ticker is pre-selected.
            // When the user opens Trade from a single-ticker filter
            // (e.g. on the FIG pill), the ticker is already chosen
            // and the pill row would just be visual noise.
            if preset.ticker == nil {
                TickerPillBar(
                    tickers: heldTickers,
                    current: ticker,
                    onPick: { pickTicker($0) }
                )
                .padding(.top, 14)
            }
            if let _ = ticker { contextLineOption.padding(.top, 12) }
        }

        rowsOption.padding(.top, 16)
        summaryOption.padding(.top, 18)
        if let err = error {
            Text(err)
                .font(.system(size: 11))
                .foregroundStyle(Color.theme.neg)
                .padding(.top, 10)
        }
    }

    /// "Editing META $630 Call" — replaces the open-flow context
    /// line when this ticket was routed in via swipe-edit. No
    /// expiry suffix since the expiry IS one of the editable
    /// fields below.
    private var editingHeaderOption: some View {
        let strikeText = strike.isEmpty ? "—" : "$\(strike)"
        return HStack {
            Text("Editing \(ticker ?? "—") \(strikeText) \(optType.rawValue)")
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
                .tracking(-0.34)
                .foregroundStyle(Color.theme.fg1)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
    }

    /// "Closing META $630 Call for July 4th" — replaces the
    /// open-flow context line when this ticket was routed in via
    /// swipe-close. The expiry text comes from the original trade's
    /// row rather than the open-flow's default+30-day placeholder.
    private var closingHeaderOption: some View {
        let strikeText = strike.isEmpty ? "—" : "$\(strike)"
        let dateText = closingExpiryLongOrdinal
        return HStack {
            Text("Closing \(ticker ?? "—") \(strikeText) \(optType.rawValue) for \(dateText)")
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
                .tracking(-0.34)              // -.02em × 17
                .foregroundStyle(Color.theme.fg1)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
    }

    /// "July 4th" — full month + ordinal day. Pulled from the
    /// ORIGINAL trade's expiry (via `preset.closingTradeId` lookup
    /// against the store) so the displayed date matches what the
    /// close row will actually carry into the DB.
    private var closingExpiryLongOrdinal: String {
        guard let id = preset.closingTradeId,
              let t = store.allTrades.first(where: { $0.id == id }),
              let d = AppDates.parseISODay(t.expiry)
        else { return "—" }

        let mf = DateFormatter()
        mf.dateFormat = "MMMM"
        mf.timeZone = TimeZone(identifier: "America/New_York")
        let month = mf.string(from: d)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let day = cal.component(.day, from: d)

        let ordinal = NumberFormatter()
        ordinal.numberStyle = .ordinal
        let dayStr = ordinal.string(from: NSNumber(value: day)) ?? "\(day)"

        return "\(month) \(dayStr)"
    }

    private var contextLineOption: some View {
        let verb = side == .sell ? "Sell" : "Buy"
        let strikeText = strike.isEmpty ? "—" : "$\(strike)"
        let date = expiryDateFormatted
        let spot = ticker.flatMap { t in
            store.companies.first(where: { $0.ticker == t })?.spot
        } ?? 0
        return HStack(spacing: 6) {
            Text("\(verb) \(ticker ?? "—") \(strikeText) \(optType.rawValue)")
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.theme.fg1)
            Text("· \(date) · spot \(spot > 0 ? fmtMoney(spot, decimals: 2) : "—")")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Color.theme.fg3)
            Spacer(minLength: 0)
        }
    }

    /// "Jul 2" — formats whatever date the user has currently
    /// picked in the Expiry row, so the context line above the
    /// keypad rows always matches what will actually be saved.
    private var expiryDateFormatted: String {
        expiryDate.formatted(.dateTime.month(.abbreviated).day())
    }

    @ViewBuilder
    private var rowsOption: some View {
        VStack(spacing: 0) {
            // Contracts — typed field, NO stepper.
            keypadRow(label: "Contracts",
                      display: contracts.isEmpty ? "1" : contracts,
                      empty: contracts.isEmpty,
                      focused: focus == .contracts,
                      isFirst: true,
                      tap: { focus = .contracts })
            strikeRow
            // Expiry only on open/edit flows. On a close the writer
            // uses the original trade's expiry (already in the
            // header "Closing X for Aug 21st") — the picker can't
            // change anything on a close so showing it was just
            // confusing and contradicted the title.
            if preset.closingTradeId == nil {
                expiryRow
            }
            keypadRow(label: "Fill price",
                      display: "$\(fill.isEmpty ? "0.00" : fill)",
                      empty: fill.isEmpty,
                      focused: focus == .fill,
                      tap: { focus = .fill })
            // Estimated row depends on flow:
            //   • Closing → "Estimated profit" + signed P&L from
            //     entry → close at the typed fill price.
            //   • Opening (sell) → "Estimated credit" (collected).
            //   • Opening (buy)  → "Estimated cost" (spent).
            if let profit = closingProfit {
                staticRow(label: "Estimated profit",
                          display: fmtMoney(profit, sign: true),
                          empty: P == 0)
            } else {
                staticRow(label: isCredit ? "Estimated credit" : "Estimated cost",
                          display: fmtUSD(grossOption),
                          empty: grossOption == 0)
            }
        }
    }

    /// P&L from closing the linked original trade at the typed fill
    /// price. Returns nil when this ticket isn't a close (so the
    /// open-flow keeps its `Estimated credit / cost` row).
    ///
    ///   Short close: profit = (entry premium − close premium) × ct × 100
    ///   Long  close: profit = (close premium − entry premium) × ct × 100
    private var closingProfit: Double? {
        guard let id = preset.closingTradeId,
              let original = store.allTrades.first(where: { $0.id == id })
        else { return nil }
        let entry = original.premium
        let exit  = P
        let perCt = Double(perContract)
        if original.direction == "short" {
            return (entry - exit) * perCt
        } else {
            return (exit - entry) * perCt
        }
    }

    /// Strike row — keypad-driven like the others, plus a small
    /// "↑X% / ↓X% from spot" suffix next to the value so the user
    /// can see at a glance how far OTM (or ITM) their strike sits.
    /// Suffix uses neutral `fg3` so it doesn't compete with the
    /// dollar value and doesn't get confusingly sign-colored (a
    /// "red" strike below spot would mislead a put seller — the
    /// distance is informational, not directional).
    @ViewBuilder
    private var strikeRow: some View {
        Button(action: {
            if confirming {
                withAnimation(.easeOut(duration: 0.2)) { confirming = false }
            }
            focus = .strike
        }) {
            HStack(spacing: 4) {
                Text("Strike price")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.theme.labelMuted)
                Spacer()
                // % goes BEFORE the dollar value so the focus cursor
                // sits next to the number you're editing, not next
                // to the suffix. Reads as "↓6.67%  $587 |".
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let pct = strikeFromSpotPct, !strike.isEmpty {
                        Text(fmtPct(pct))
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.theme.fg3)
                    }
                    Text("$\(strike.isEmpty ? "0" : strike)")
                        .font(.system(size: 16, weight: .medium))
                        .monospacedDigit()
                        .tracking(-0.16)
                        .foregroundStyle(valueColor(empty: strike.isEmpty,
                                                    focused: focus == .strike))
                }
                if focus == .strike {
                    BlinkingCursor()
                        .padding(.leading, 2)   // native-iOS-cursor tight, just enough to not kiss the last digit
                }
            }
            .padding(.vertical, 14)
            .overlay(alignment: .top) {
                Color.theme.borderBright.opacity(0.5).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// `(K − spot) / spot × 100`. Positive = strike is ABOVE spot
    /// (call seller's friend, put seller's risk); negative = strike
    /// is BELOW. nil when ticker or strike isn't set yet.
    private var strikeFromSpotPct: Double? {
        guard K > 0, let t = ticker,
              let spot = store.companies.first(where: { $0.ticker == t })?.spot,
              spot > 0
        else { return nil }
        return (K - spot) / spot * 100
    }

    /// Expiry row — same `.prow` chrome as the keypad rows but uses
    /// a native SwiftUI `DatePicker(.compact)` for input. Tapping it
    /// opens iOS's calendar popover.
    private var expiryRow: some View {
        HStack(spacing: 4) {
            Text("Expiry")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.theme.labelMuted)
            Spacer()
            DatePicker(
                "",
                selection: $expiryDate,
                in: Date()...,                  // no past dates
                displayedComponents: .date
            )
            .labelsHidden()
            .tint(Color.theme.neon)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            Color.theme.borderBright.opacity(0.5).frame(height: 1)
        }
    }

    @ViewBuilder
    private var summaryOption: some View {
        if preset.closingTradeId != nil {
            summaryOptionClosing
        } else {
            summaryOptionOpening
        }
    }

    /// Open-flow summary — what a NEW position can theoretically do.
    /// Max profit / Breakeven / If exercised.
    private var summaryOptionOpening: some View {
        let stockAvg = store.companies.first(where: { $0.ticker == ticker })?
            .legs.first(where: { $0.kind == .stock })?.avg ?? 0
        let shares = store.companies.first(where: { $0.ticker == ticker })?
            .legs.first(where: { $0.kind == .stock })?.qty ?? 0
        let covered = isCredit && optType == .call && shares >= Double(perContract) && perContract > 0

        let maxProfit: Double?
        let breakeven: Double
        switch (side, optType) {
        case (.sell, .call):
            if covered {
                maxProfit = (K - stockAvg) * Double(perContract) + grossOption
                breakeven = stockAvg - P
            } else {
                maxProfit = grossOption
                breakeven = K + P
            }
        case (.buy, .call):
            maxProfit = nil
            breakeven = K + P
        case (.sell, .put):
            maxProfit = grossOption
            breakeven = K - P
        case (.buy, .put):
            maxProfit = (K - P) * Double(perContract)
            breakeven = K - P
        }

        // If-exercised cell: when this is a SELL CALL with enough
        // FIFO lots to cover the assignment, show the actual profit
        // (FIFO-derived). Otherwise fall back to the strike text +
        // "N sh delivered/assigned/buy/sell" sub.
        let exVerb: String = {
            switch (side, optType) {
            case (.sell, .call): return "delivered"
            case (.sell, .put):  return "assigned"
            case (.buy,  .call): return "you buy"
            case (.buy,  .put):  return "you sell"
            }
        }()
        let (ifExLabel, ifExValue, ifExSub): (String, String, String?) = {
            if let profit = ifExercisedFifoProfit {
                // Sub-line carries the strike + share count so the
                // user still sees the mechanics behind the dollar.
                let sub = perContract > 0
                    ? "\(perContract) sh @ $\(fmtStrike(K))"
                    : nil
                return ("If exercised", fmtMoney(profit, sign: true), sub)
            } else {
                return ("If exercised",
                        K > 0 ? "$\(fmtStrike(K))" : "—",
                        perContract > 0 ? "\(perContract) sh \(exVerb)" : nil)
            }
        }()

        return summaryStrip([
            ("Max profit",   maxProfit.map { fmtMoney($0, sign: true) } ?? "Unlimited", nil),
            ("Breakeven",    breakeven > 0 ? fmtMoney(breakeven, decimals: 2) : "—",    nil),
            (ifExLabel,      ifExValue,                                                ifExSub),
        ])
    }

    /// FIFO-derived profit on a SELL CALL if it gets exercised.
    /// Walks `store.allShareLots` oldest-first to find the lots
    /// that would be drawn down to deliver the shares; returns
    /// `(strike − weighted FIFO cost) × shares + premium`.
    /// Returns nil for non-(sell, call) combos or when the user
    /// doesn't have enough lots to cover the assignment (uncovered
    /// case has no single useful number — you'd have to spot-buy
    /// shares to deliver, which is path-dependent).
    private var ifExercisedFifoProfit: Double? {
        guard side == .sell, optType == .call,
              K > 0, P >= 0, perContract > 0,
              let t = ticker
        else { return nil }

        let sharesAway = Double(perContract)
        let lots = store.allShareLots
            .filter { $0.ticker == t.uppercased() && $0.qty_remaining > 0 }
            .sorted { lhs, rhs in
                if lhs.acquired_date != rhs.acquired_date {
                    return lhs.acquired_date < rhs.acquired_date
                }
                return lhs.fifo_order < rhs.fifo_order
            }

        var remaining = sharesAway
        var consumedQty = 0.0
        var consumedCost = 0.0
        for l in lots {
            guard remaining > 0 else { break }
            let take = Swift.min(l.qty_remaining, remaining)
            consumedQty += take
            consumedCost += take * l.cost_per_share
            remaining -= take
        }
        // Need to cover the full assignment from existing lots —
        // otherwise the profit isn't a clean number.
        guard consumedQty >= sharesAway - 0.001 else { return nil }

        let avg = consumedCost / consumedQty
        let premiumCollected = P * sharesAway
        return (K - avg) * sharesAway + premiumCollected
    }

    /// Close-flow summary — different lens. The user already opened
    /// the position; the relevant questions are "how much am I
    /// keeping?", "how much of my max did I capture?", and "how
    /// long did I hold this?". Replaces Max profit / Breakeven /
    /// If exercised with Original / Captured / Days held.
    @ViewBuilder
    private var summaryOptionClosing: some View {
        if let id = preset.closingTradeId,
           let original = store.allTrades.first(where: { $0.id == id }) {
            let originalGross = original.premium * Double(perContract)
            let profit = closingProfit ?? 0
            let captured = originalGross > 0
                ? (profit / originalGross) * 100
                : 0
            let daysHeld = AppDates.daysBetween(original.trade_date, Date()) ?? 0

            // Label depends on which side of the original you took.
            let originalLabel = original.direction == "short" ? "Credit" : "Cost"

            summaryStrip([
                (originalLabel, fmtMoney(originalGross, sign: false), nil),
                ("Captured",    fmtPct(captured),                     nil),
                ("Days held",   "\(daysHeld)",                        daysHeld == 1 ? "day" : "days"),
            ])
        }
    }

    // MARK: Shares body

    @ViewBuilder
    private var sharesBody: some View {
        if preset.closingTradeId != nil || preset.lockTicker {
            // CLOSE flow — side is sell, ticker is set. Show only
            // the closing header. (Shares edits route through
            // TickerTradesSheet, not this sheet, so there's no
            // shares-edit branch.)
            closingHeaderShares.padding(.top, 4)
        } else {
            // OPEN flow — pick side + ticker.
            Picker("Side", selection: $side) {
                ForEach(Side.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            TickerPillBar(
                tickers: heldTickers,
                current: ticker,
                onPick: { pickTicker($0) }
            )
            .padding(.top, 14)
            if let _ = ticker { contextLineShares.padding(.top, 12) }
        }

        rowsShares.padding(.top, 16)
        if ticker != nil { summaryShares.padding(.top, 18) }
        if let err = error {
            Text(err)
                .font(.system(size: 11))
                .foregroundStyle(Color.theme.neg)
                .padding(.top, 10)
        }
    }

    /// "Closing META shares" — no expiry, since shares don't have one.
    private var closingHeaderShares: some View {
        HStack {
            Text("Closing \(ticker ?? "—") shares")
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
                .tracking(-0.34)
                .foregroundStyle(Color.theme.fg1)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
    }

    private var contextLineShares: some View {
        let verb = side == .buy ? "Buy" : "Sell"
        let spot = ticker.flatMap { t in
            store.companies.first(where: { $0.ticker == t })?.spot
        } ?? 0
        return HStack(spacing: 6) {
            Text("\(verb) \(ticker ?? "—") shares")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.theme.fg1)
            Text("· spot \(spot > 0 ? fmtMoney(spot, decimals: 2) : "—")")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Color.theme.fg3)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var rowsShares: some View {
        VStack(spacing: 0) {
            keypadRow(label: "Shares",
                      display: qty.isEmpty ? "0" : qty,
                      empty: qty.isEmpty,
                      focused: focus == .qty,
                      isFirst: true,
                      tap: { focus = .qty })
            keypadRow(label: "Fill price",
                      display: "$\(price.isEmpty ? "0.00" : price)",
                      empty: price.isEmpty,
                      focused: focus == .price,
                      tap: { focus = .price })
            staticRow(label: side == .buy ? "Estimated cost" : "Estimated proceeds",
                      display: fmtUSD(grossShares),
                      empty: grossShares == 0)
        }
    }

    @ViewBuilder
    private var summaryShares: some View {
        let stockLeg = store.companies.first(where: { $0.ticker == ticker })?
            .legs.first(where: { $0.kind == .stock })
        let held = stockLeg?.qty ?? 0
        let avg = stockLeg?.avg ?? 0
        let last = stockLeg?.last ?? 0

        let isBuy = side == .buy
        let newPos = isBuy ? held + Q : max(0, held - Q)
        let unrealAfter = isBuy
            ? (last - Pr) * Q
            : (Pr - avg) * Q
        let unrealLabel = isBuy ? "Unreal at \(fmtMoney(last, decimals: 2))" : "Realized"

        summaryStrip([
            (isBuy ? "New position" : "Remaining",
             "\(Int(newPos).formatted(.number)) sh", nil),
            ("Avg cost", avg > 0 ? fmtMoney(avg, decimals: 2) : "—", nil),
            (unrealLabel, fmtMoney(unrealAfter, sign: true), nil),
        ])
    }

    // MARK: Shared rows

    /// `.prow.tap` — sans 14pt fg-muted label + mono 16pt right value.
    /// Focused state: the value goes neon AND a blinking cursor
    /// sits to the right so the user can always see which row
    /// they're typing into.
    /// Tapping during the confirm step bounces back to edit mode
    /// (and re-focuses this row), so they don't have to hunt for
    /// a Back button to change a number.
    @ViewBuilder
    private func keypadRow(label: String,
                           display: String,
                           empty: Bool,
                           focused: Bool,
                           isFirst: Bool = false,
                           tap: @escaping () -> Void) -> some View {
        Button(action: {
            if confirming {
                withAnimation(.easeOut(duration: 0.2)) { confirming = false }
            }
            tap()
        }) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.theme.labelMuted)
                Spacer()
                Text(display)
                    .font(.system(size: 16, weight: .medium))
                    .monospacedDigit()
                    .tracking(-0.16)
                    .foregroundStyle(valueColor(empty: empty, focused: focused))
                if focused {
                    BlinkingCursor()
                        .padding(.leading, 2)   // native-iOS-cursor tight, just enough to not kiss the last digit
                        .transition(.opacity)
                }
            }
            .padding(.vertical, 14)
            .overlay(alignment: .top) {
                if !isFirst {
                    Color.theme.borderBright.opacity(0.5).frame(height: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Color rule for the value text:
    ///   • Focused → always neon (even when empty / placeholder),
    ///     so the user can see at a glance which row they're
    ///     typing into.
    ///   • Empty + unfocused → fg5 (very light grey placeholder).
    ///   • Otherwise → fg1 (black).
    private func valueColor(empty: Bool, focused: Bool) -> Color {
        if focused { return Color.theme.neon }
        return empty ? Color.theme.fg5 : Color.theme.fg1
    }

    @ViewBuilder
    private func staticRow(label: String, display: String, empty: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.theme.labelMuted)
            Spacer()
            Text(display)
                .font(.system(size: 16, weight: .medium))
                .monospacedDigit()
                .tracking(-0.16)
                .foregroundStyle(empty ? Color.theme.fg5 : Color.theme.fg1)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            Color.theme.borderBright.opacity(0.5).frame(height: 1)
        }
    }

    @ViewBuilder
    private func summaryStrip(_ cells: [(String, String, String?)]) -> some View {
        HStack(spacing: 10) {
            ForEach(cells.indices, id: \.self) { i in
                let (k, v, sub) = cells[i]
                VStack(spacing: 0) {
                    Text(k.uppercased())
                        .font(.system(size: 9, weight: .regular))
                        .tracking(0.7)
                        .foregroundStyle(Color.theme.fg3)
                    Text(v)
                        .font(.system(size: 16, weight: .medium))
                        .monospacedDigit()
                        .tracking(-0.16)
                        .foregroundStyle(Color.theme.fg1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 6)
                    if let sub {
                        Text(sub)
                            .font(.system(size: 8))
                            .tracking(0.2)
                            .foregroundStyle(Color.theme.fg3)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 2)
        .overlay(alignment: .top) {
            Color.theme.borderBright.frame(height: 1.5)
        }
    }

    // MARK: Footer (Review)

    /// Two-step primary action: first tap = Review (collapses the
    /// keypad + freezes input), second tap = Confirm (actually
    /// fires the save). Tapping any row in between bounces the
    /// user back to edit mode.
    private var footer: some View {
        let ready = preset.instrument == .option ? optionReady : sharesReady
        let label: String = {
            if saving { return "Saving…" }
            return confirming ? "Confirm" : "Review"
        }()
        return VStack(spacing: 0) {
            Button(action: {
                if confirming {
                    Task { await save() }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        focus = nil
                        confirming = true
                    }
                }
            }) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.theme.onNeon)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(Color.theme.neon))
                    .opacity(ready ? 1.0 : 0.4)
            }
            .buttonStyle(.pressable)
            .disabled(!ready || saving)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(Color.theme.surface)
    }

    // MARK: Ticker picking

    private var heldTickers: [String] {
        store.companies.map(\.ticker).sorted()
    }

    private func pickTicker(_ t: String) {
        ticker = t
        guard let c = store.companies.first(where: { $0.ticker == t }) else { return }
        if strike.isEmpty, c.spot > 0 {
            let rounded = (c.spot / 5).rounded() * 5
            strike = String(Int(rounded))
        }
        if price.isEmpty, c.spot > 0 {
            price = String(format: "%.2f", c.spot)
        }
    }

    // MARK: Key handling

    private func pressKey(_ k: KeypadKey) {
        guard let f = focus else { return }
        // Reach the right binding for the focused field, then apply
        // the key. Direct property writes work because all the field
        // backing stores are @State, which expose their wrapped
        // value as a mutable l-value through SwiftUI's projection.
        switch f {
        case .contracts: apply(k, to: $contracts, integerOnly: true)
        case .qty:       apply(k, to: $qty,       integerOnly: true)
        case .strike:    apply(k, to: $strike)
        case .fill:      apply(k, to: $fill)
        case .price:     apply(k, to: $price)
        }
    }

    private func apply(_ k: KeypadKey, to binding: Binding<String>, integerOnly: Bool = false) {
        var cur = binding.wrappedValue
        switch k {
        case .digit(let d):
            if cur == "0" { cur = "" }
            cur += d
        case .dot:
            if integerOnly { return }
            if !cur.contains(".") { cur = cur.isEmpty ? "0." : cur + "." }
        case .delete:
            if !cur.isEmpty { cur.removeLast() }
        }
        binding.wrappedValue = cur
    }

    // MARK: Persistence

    /// Branches on whether this ticket is opening or closing. When
    /// `preset.closingTradeId` is set (swipe-left Close routed
    /// here), an option ticket writes a `close` row linked to the
    /// original `option_trades.id` via `closes_trade_id` —
    /// otherwise it writes a fresh `open`. Shares always route
    /// through `buyShares` / `sellShares` regardless of close
    /// status (the writer handles the FIFO bookkeeping).
    private func save() async {
        do {
            saving = true; error = nil
            if preset.instrument == .option {
                // Closes allow P == 0 (expired worthless); opens/
                // edits still require a positive fill.
                let allowZeroFill = preset.closingTradeId != nil
                let fillOK = allowZeroFill ? P >= 0 : P > 0
                guard let t = ticker, K > 0, fillOK else { return }
                if let editingId = preset.editingTradeId {
                    // Editing path — PATCH the existing trade row
                    // in place via updateTrade. Side / type /
                    // strike / expiry / fill / contracts can all
                    // change; ticker stays the original's.
                    try await store.updateTrade(TradePatch(
                        id: editingId,
                        optionType: optType.rawValue.lowercased(),
                        direction: side == .sell ? "short" : "long",
                        contracts: Double(Ct),
                        strike: K,
                        premium: P,
                        expiry: expiryDate,
                        tradeDate: Date(),
                        note: nil
                    ))
                } else if let closingId = preset.closingTradeId,
                   let original = store.allTrades.first(where: { $0.id == closingId }) {
                    // Closing path — writes action=close + closes_trade_id.
                    try await store.closeTrade(
                        open: original,
                        contracts: Double(Ct),
                        closePremium: P,
                        closeDate: Date(),
                        note: nil
                    )
                } else {
                    // Opening path — writes action=open.
                    try await store.addTrade(NewTradeInput(
                        ticker: t,
                        tradeDate: Date(),
                        optionType: optType.rawValue.lowercased(),
                        direction: side == .sell ? "short" : "long",
                        contracts: Double(Ct),
                        strike: K,
                        premium: P,
                        expiry: expiryDate,
                        note: nil
                    ))
                }
            } else {
                guard let t = ticker, Q > 0, Pr > 0 else { return }
                if side == .buy {
                    try await store.buyShares(ticker: t, quantity: Q, price: Pr)
                } else {
                    try await store.sellShares(ticker: t, quantity: Q, price: Pr)
                }
            }
            onDismiss()
        } catch {
            self.error = (error as NSError).localizedDescription
        }
        saving = false
    }
}

// MARK: - Ticker pill bar

/// Horizontally-scrolling row of ticker pills. Active = neon fill,
/// white ink. Per Handoff 2 §8 — pills not a dropdown.
struct TickerPillBar: View {
    let tickers: [String]
    let current: String?
    let onPick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(tickers, id: \.self) { t in
                    let on = t == current
                    Button { onPick(t) } label: {
                        Text(t)
                            .font(.system(size: 12, weight: on ? .semibold : .medium))
                            .tracking(0.4)
                            .foregroundStyle(on ? Color.theme.onNeon : Color.theme.fg2)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 9)
                            .frame(minHeight: 38)
                            .background(
                                Capsule()
                                    .fill(on ? Color.theme.neon : Color.theme.surface)
                                    .overlay(
                                        Capsule().strokeBorder(
                                            on ? Color.clear : Color.theme.borderBright,
                                            lineWidth: 1
                                        )
                                    )
                            )
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }
}

// MARK: - Always-visible iOS-native-styled number pad

enum KeypadKey {
    case digit(String), dot, delete
}

/// Always-on number pad — borderless, big accent digits, white bg,
/// no key cells. `.` bottom-left, `←` (delete) bottom-right. Per
/// Handoff 2 §8.
struct IOSNumberPad: View {
    let onKey: (KeypadKey) -> Void

    private let rows: [[KeypadKey]] = [
        [.digit("1"), .digit("2"), .digit("3")],
        [.digit("4"), .digit("5"), .digit("6")],
        [.digit("7"), .digit("8"), .digit("9")],
        [.dot,        .digit("0"), .delete],
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(rows[r].indices, id: \.self) { c in
                        keyButton(rows[r][c])
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(
            Color.theme.surface
                .overlay(
                    Color.theme.borderBright.opacity(0.5).frame(height: 1),
                    alignment: .top
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder
    private func keyButton(_ key: KeypadKey) -> some View {
        Button { onKey(key) } label: {
            Group {
                switch key {
                case .digit(let d):
                    Text(d)
                        .font(.system(size: 30, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(Color.theme.neon)
                case .dot:
                    Text(".")
                        .font(.system(size: 30, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(Color.theme.neon)
                case .delete:
                    Image(systemName: "delete.left")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Color.theme.neon)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Blinking cursor

/// Slim neon caret that blinks at iOS-text-field rhythm (~530ms
/// on, ~530ms off). Used as the focus indicator on the active
/// keypad row so the user always knows which field is taking
/// input. Height matches the 16pt value text closely so it reads
/// as part of the same line, not a separate UI element.
struct BlinkingCursor: View {
    @State private var on = true

    var body: some View {
        Rectangle()
            .fill(Color.theme.neon)
            .frame(width: 2, height: 18)
            .opacity(on ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.53).repeatForever(autoreverses: true)) {
                    on = false
                }
            }
    }
}

// MARK: - Local format helper

private func fmtUSD(_ v: Double) -> String {
    let abs = Swift.abs(v)
    return "$" + abs.formatted(.number
        .precision(.fractionLength(2))
        .grouping(.automatic))
}
