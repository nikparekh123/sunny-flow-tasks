//
//  TradeSheets.swift
//  Sunnyfi
//
//  All option-trade entry sheets in one place:
//   - AddTradeSheet     → log a new IBKR mirror trade
//   - EditTradeSheet    → fix mistakes on an open trade
//   - CloseTradeSheet   → close at a user-specified close premium
//   - ResolveTradeSheet → expired / assigned outcomes
//
//  Each sheet writes to Supabase via `PortfolioStore` (see TradeMutations.swift)
//  and dismisses on success. Web + iOS share the same tables, so any insert
//  appears on sunnyfi.co within ~1s via the web's realtime subscription.
//

import SwiftUI

// MARK: - Shared helpers

private let kOptionTypes: [(label: String, value: String)] = [("Call", "call"), ("Put", "put")]
private let kSides:       [(label: String, value: String)] = [("Sold (short)", "short"), ("Bought (long)", "long")]

private struct SheetHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Capsule().fill(Color.white.opacity(0.22))
                .frame(width: 38, height: 5)
                .padding(.bottom, 14)
            Text(title)
                .font(.ui(size: 19, weight: .bold))
                .foregroundStyle(Color.theme.fg1)
            Text(subtitle)
                .font(.ui(size: 12.5))
                .foregroundStyle(Color.theme.fg3)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.ui(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Color.theme.fg3)
    }
}

private struct FieldBox<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(Color.theme.cardSolid)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .strokeBorder(Color.theme.soft, lineWidth: 0.5)
                    )
            )
    }
}

private struct PrimaryButton: View {
    let label: String
    let busy: Bool
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Capsule().fill(destructive ? Color.theme.neg : Color.theme.neon)
                if busy {
                    ProgressView().tint(.black)
                } else {
                    Text(label)
                        .font(.ui(size: 15, weight: .bold))
                        .foregroundStyle(destructive ? Color.white : Color.theme.onNeon)
                }
            }
            .frame(height: 48)
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Segmented picker

private struct SegPicker: View {
    let label: String
    let options: [(label: String, value: String)]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(text: label)
            HStack(spacing: 4) {
                ForEach(options, id: \.value) { opt in
                    Button {
                        withAnimation(Motion.standard) { selection = opt.value }
                    } label: {
                        Text(opt.label)
                            .font(.ui(size: 12.5, weight: .semibold))
                            .foregroundStyle(selection == opt.value ? Color.theme.neon : Color.theme.fg3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.md - 2)
                                    .fill(selection == opt.value ? Color.theme.tintNeon : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.md - 2)
                                            .strokeBorder(
                                                selection == opt.value ? Color.theme.neon.opacity(0.25) : Color.clear,
                                                lineWidth: 1
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(Color.theme.cardSolid)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Number stepper

private struct NumberStepper: View {
    let label: String
    @Binding var value: Double
    var step: Double = 1
    var minimum: Double = 0
    var format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(text: label)
            HStack {
                Button {
                    value = max(minimum, value - step)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 38, height: 38)
                        .foregroundStyle(Color.theme.neon)
                }
                .buttonStyle(.pressable)
                Spacer()
                Text(format(value))
                    .font(.numeric(size: 17, weight: .medium))
                    .foregroundStyle(Color.theme.fg1)
                Spacer()
                Button {
                    value += step
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 38, height: 38)
                        .foregroundStyle(Color.theme.neon)
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(Color.theme.cardSolid)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .strokeBorder(Color.theme.soft, lineWidth: 0.5)
                    )
            )
        }
    }
}

// MARK: - Decimal text field

private struct DecimalField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(text: label)
            FieldBox {
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.theme.fg4))
                    .keyboardType(.decimalPad)
                    .font(.numeric(size: 16, weight: .medium))
                    .foregroundStyle(Color.theme.fg1)
            }
        }
    }
}

private struct PlainField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var autoCaps: TextInputAutocapitalization = .characters

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(text: label)
            FieldBox {
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.theme.fg4))
                    .textInputAutocapitalization(autoCaps)
                    .autocorrectionDisabled()
                    .font(.ui(size: 16, weight: .medium))
                    .foregroundStyle(Color.theme.fg1)
            }
        }
    }
}

private struct DateField: View {
    let label: String
    @Binding var date: Date
    var displayedComponents: DatePickerComponents = .date

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(text: label)
            FieldBox {
                // Don't pin to .colorScheme(.dark) — that was forcing
                // the date picker into dark-mode rendering, which makes
                // `Color.theme.neon` resolve to LIME (the dark variant)
                // and read as unreadable yellow text on a light sheet.
                // Inherit the user's appearance instead so neon resolves
                // to deep teal on paper and lime on dark.
                DatePicker("", selection: $date, displayedComponents: displayedComponents)
                    .labelsHidden()
                    .tint(.theme.neon)
            }
        }
    }
}

// MARK: - Add Trade

/// Six possible actions a user takes when mirroring an IBKR fill.
/// Picking one tells us simultaneously: which fields to show and which
/// mutation to call.
enum TradeAction: String, CaseIterable, Identifiable {
    case sellCall = "Sell call"
    case buyCall  = "Buy call"
    case sellPut  = "Sell put"
    case buyPut   = "Buy put"
    case buyShares  = "Buy shares"
    case sellShares = "Sell shares"

    var id: String { rawValue }
    var isOption: Bool { self != .buyShares && self != .sellShares }
    var optionType: String? {
        switch self {
        case .sellCall, .buyCall: return "call"
        case .sellPut,  .buyPut:  return "put"
        default: return nil
        }
    }
    var direction: String? {
        switch self {
        case .sellCall, .sellPut: return "short"
        case .buyCall,  .buyPut:  return "long"
        default: return nil
        }
    }
    var tint: Color {
        switch self {
        case .sellCall, .sellPut, .sellShares: return .theme.pos
        case .buyCall,  .buyPut,  .buyShares:  return .theme.neg
        }
    }
}

struct AddTradeSheet: View {
    let store: PortfolioStore
    var prefillTicker: String? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var action: TradeAction = .sellCall
    @State private var ticker: String = ""

    // Option fields
    @State private var contracts: Double = 1
    @State private var strikeText: String = ""
    @State private var premiumText: String = ""
    @State private var expiry: Date = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()

    // Shares fields
    @State private var qtyText: String = ""
    @State private var priceText: String = ""

    @State private var tradeDate: Date = Date()
    @State private var submitting: Bool = false
    @State private var errorMessage: String?

    /// Strategy bucket the ticker belongs to — Income / Investment /
    /// Yield. Defaults to the existing assignment when the ticker is
    /// already known, otherwise Investment (the safest default for a
    /// new position).
    @State private var strategy: Strategy = .investment

    private var canSubmit: Bool {
        guard !ticker.isEmpty, !submitting else { return false }
        if action.isOption {
            return Double(strikeText) != nil && Double(premiumText) != nil && contracts > 0
        } else {
            return Double(qtyText) != nil && Double(priceText) != nil && (Double(qtyText) ?? 0) > 0
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SheetHeader(title: "Add trade", subtitle: "Mirror your IBKR fill here")

                ActionPicker(action: $action)
                TickerPicker(store: store, ticker: $ticker)
                // Strategy is a per-ticker bucket, not per-trade. Only
                // show the picker when the user is adding the very
                // first trade for a brand-new symbol; for tickers
                // already in the book the existing bucket is reused.
                if isNewTicker {
                    StrategyPicker(strategy: $strategy)
                }

                if action.isOption {
                    NumberStepper(label: "Contracts", value: $contracts, step: 1, minimum: 1) {
                        "×\(Int($0))"
                    }
                    HStack(spacing: 12) {
                        DecimalField(label: "Strike $", placeholder: "0.00", text: $strikeText)
                        DecimalField(label: "Premium $", placeholder: "0.00", text: $premiumText)
                    }
                    DateField(label: "Expiry", date: $expiry)

                    // FIFO assignment preview — live as the user fills
                    // in ticker / strike / contracts for a short call.
                    if action == .sellCall,
                       !ticker.isEmpty,
                       let strike = Double(strikeText),
                       contracts > 0 {
                        SellCallAssignmentPreview(
                            store: store,
                            ticker: ticker,
                            strike: strike,
                            contracts: contracts,
                            premiumPerContract: Double(premiumText) ?? 0
                        )
                    }
                } else {
                    HStack(spacing: 12) {
                        DecimalField(label: "Quantity", placeholder: "100", text: $qtyText)
                        DecimalField(label: "Price $",  placeholder: "0.00", text: $priceText)
                    }
                }

                DateField(label: "Trade date", date: $tradeDate)

                if let err = errorMessage {
                    Text(err)
                        .font(.ui(size: 12))
                        .foregroundStyle(Color.theme.neg)
                        .multilineTextAlignment(.center)
                }

                PrimaryButton(label: action.rawValue, busy: submitting) {
                    Task { await submit() }
                }
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.55)

                Button("Cancel") { dismiss() }
                    .font(.ui(size: 13.5))
                    .foregroundStyle(Color.theme.fg3)
                    .padding(.top, 2)
            }
            .padding(20)
        }
        .background(Color.theme.page.ignoresSafeArea())
        .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)
        .onAppear {
            if let t = prefillTicker, ticker.isEmpty { ticker = t }
            syncStrategyFromStore()
        }
        // When the user picks a ticker that already has a strategy
        // assigned, default the picker to that. The user can still
        // change it (and we'll write the new value on submit).
        .onChange(of: ticker) { _, _ in syncStrategyFromStore() }
    }

    /// True when the typed ticker doesn't yet exist in the book (open
    /// or closed). Drives whether the strategy picker is shown.
    private var isNewTicker: Bool {
        let tk = ticker.trimmingCharacters(in: .whitespaces).uppercased()
        guard !tk.isEmpty else { return false }
        let known = store.companies.contains(where: { $0.ticker == tk })
                 || store.closedCompanies.contains(where: { $0.ticker == tk })
        return !known
    }

    /// Re-default the strategy picker when the ticker changes. If the
    /// ticker is already known with a strategy → use that. Otherwise
    /// default to Investment.
    private func syncStrategyFromStore() {
        let tk = ticker.trimmingCharacters(in: .whitespaces).uppercased()
        guard !tk.isEmpty else { return }
        if let existing = store.companies.first(where: { $0.ticker == tk })?.strategy {
            strategy = existing
        } else if let existingClosed = store.closedCompanies.first(where: { $0.ticker == tk })?.strategy {
            strategy = existingClosed
        } else {
            strategy = .investment
        }
    }

    private func submit() async {
        submitting = true
        defer { submitting = false }
        do {
            // Persist strategy first — cheap upsert that runs in parallel
            // with the trade write doesn't materially help, sequential
            // is clearer.
            try await store.setStrategy(ticker: ticker, strategy: strategy)
            switch action {
            case .sellCall, .buyCall, .sellPut, .buyPut:
                try await store.addTrade(NewTradeInput(
                    ticker: ticker,
                    tradeDate: tradeDate,
                    optionType: action.optionType ?? "call",
                    direction: action.direction ?? "short",
                    contracts: contracts,
                    strike: Double(strikeText) ?? 0,
                    premium: Double(premiumText) ?? 0,
                    expiry: expiry,
                    note: nil
                ))
            case .buyShares:
                try await store.buyShares(
                    ticker: ticker,
                    quantity: Double(qtyText) ?? 0,
                    price: Double(priceText) ?? 0
                )
            case .sellShares:
                try await store.sellShares(
                    ticker: ticker,
                    quantity: Double(qtyText) ?? 0,
                    price: Double(priceText) ?? 0
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Ticker picker (avoids typos by sourcing from existing book)

private struct TickerPicker: View {
    let store: PortfolioStore
    @Binding var ticker: String

    @State private var showSheet: Bool = false

    /// Union of tickers we already know about (current holdings + history).
    private var knownTickers: [String] {
        var set = Set<String>()
        for c in store.companies { set.insert(c.ticker) }
        for c in store.closedCompanies { set.insert(c.ticker) }
        for t in store.allTrades { set.insert(t.ticker) }
        return set.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(text: "Ticker")
            Button { showSheet = true } label: {
                HStack {
                    if ticker.isEmpty {
                        Text("Pick a ticker")
                            .foregroundStyle(Color.theme.fg3)
                    } else {
                        Text(ticker)
                            .font(.numeric(size: 18, weight: .bold))
                            .foregroundStyle(Color.theme.fg1)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundStyle(Color.theme.fg3)
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .fill(Color.theme.cardSolid)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg)
                                .strokeBorder(Color.theme.soft, lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.pressable)
        }
        .sheet(isPresented: $showSheet) {
            TickerPickerSheet(known: knownTickers, selected: $ticker)
                .presentationDetents([.medium, .large])
        }
    }
}

private struct TickerPickerSheet: View {
    let known: [String]
    @Binding var selected: String

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return q.isEmpty ? known : known.filter { $0.contains(q) }
    }

    private var queryIsNewTicker: Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return !q.isEmpty && !known.contains(q)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Grabber + title
            VStack(spacing: 8) {
                Capsule().fill(Color.white.opacity(0.22))
                    .frame(width: 38, height: 5)
                Text("Choose ticker")
                    .font(.ui(size: 17, weight: .bold))
                    .foregroundStyle(Color.theme.fg1)
            }
            .padding(.top, 8)
            .padding(.bottom, 14)

            // Search / new ticker entry
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.theme.fg3)
                TextField(
                    "",
                    text: $query,
                    prompt: Text("Type to search or add new").foregroundStyle(Color.theme.fg3)
                )
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .foregroundStyle(Color.theme.fg1)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(Color.theme.cardSolid)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .strokeBorder(Color.theme.soft, lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 20)

            // "Add new" affordance — only if query doesn't match any known
            if queryIsNewTicker {
                Button {
                    selected = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.theme.neon)
                        Text("Add new ticker: \(query.uppercased())")
                            .font(.ui(size: 14, weight: .semibold))
                            .foregroundStyle(Color.theme.fg1)
                        Spacer()
                    }
                    .padding(14)
                }
                .buttonStyle(.pressableRow)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }

            // List of known tickers
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered, id: \.self) { tk in
                        Button {
                            selected = tk
                            dismiss()
                        } label: {
                            HStack {
                                Text(tk)
                                    .font(.numeric(size: 16, weight: .bold))
                                    .foregroundStyle(Color.theme.fg1)
                                Spacer()
                                if selected == tk {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.theme.neon)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressableRow)
                        Rectangle().fill(Color.theme.hair).frame(height: 0.5).padding(.leading, 20)
                    }
                }
                .padding(.top, 8)
            }
        }
        .background(Color.theme.page.ignoresSafeArea())
        .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)
    }
}

// MARK: - Action picker (6 buttons, 2-col grid)

private struct ActionPicker: View {
    @Binding var action: TradeAction

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(text: "Action")
            let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(TradeAction.allCases) { a in
                    let isActive = action == a
                    Button {
                        action = a
                    } label: {
                        Text(a.rawValue)
                            .font(.ui(size: 13, weight: .semibold))
                            .foregroundStyle(isActive ? Color.theme.onNeon : a.tint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.lg)
                                    .fill(isActive ? a.tint : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.lg)
                                            .strokeBorder(a.tint.opacity(isActive ? 1 : 0.4), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }
}

/// Three-way Income / Investment / Yield picker for the strategy
/// bucket. Saved into `strategy_overlay` on submit. Surfaced in the
/// add-trade flow so a brand-new ticker can be tagged at creation,
/// and pre-populates from the existing assignment when one exists.
private struct StrategyPicker: View {
    @Binding var strategy: Strategy

    private let order: [Strategy] = [.income, .investment, .yield]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(text: "Strategy")
            HStack(spacing: 8) {
                ForEach(order, id: \.rawValue) { s in
                    let isActive = strategy == s
                    Button {
                        strategy = s
                    } label: {
                        Text(s.rawValue)
                            .font(.ui(size: 13, weight: .semibold))
                            .foregroundStyle(isActive ? Color.theme.onNeon : Color.theme.fg2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.lg)
                                    .fill(isActive ? Color.theme.neon : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.lg)
                                            .strokeBorder(
                                                isActive ? Color.theme.neon : Color.theme.soft,
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

// MARK: - Edit Trade

struct EditTradeSheet: View {
    let store: PortfolioStore
    let trade: OptionTradeRow

    @Environment(\.dismiss) private var dismiss

    @State private var optionType: String
    @State private var direction: String
    @State private var contracts: Double
    @State private var strikeText: String
    @State private var premiumText: String
    @State private var tradeDate: Date
    @State private var expiry: Date

    @State private var submitting: Bool = false
    @State private var errorMessage: String?

    init(store: PortfolioStore, trade: OptionTradeRow) {
        self.store = store
        self.trade = trade
        _optionType = State(initialValue: trade.option_type)
        _direction = State(initialValue: trade.direction)
        _contracts = State(initialValue: trade.contracts)
        _strikeText = State(initialValue: String(trade.strike))
        _premiumText = State(initialValue: String(trade.premium))
        _tradeDate = State(initialValue: AppDates.parseISODay(trade.trade_date) ?? Date())
        _expiry = State(initialValue: AppDates.parseISODay(trade.expiry) ?? Date())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SheetHeader(title: "Edit trade", subtitle: "\(trade.ticker) · existing leg")

                SegPicker(label: "Type", options: kOptionTypes, selection: $optionType)
                SegPicker(label: "Side", options: kSides, selection: $direction)

                NumberStepper(label: "Contracts", value: $contracts, step: 1, minimum: 1) {
                    "×\(Int($0))"
                }

                HStack(spacing: 12) {
                    DecimalField(label: "Strike $", placeholder: "0", text: $strikeText)
                    DecimalField(label: "Premium $", placeholder: "0", text: $premiumText)
                }

                DateField(label: "Trade date", date: $tradeDate)
                DateField(label: "Expiry", date: $expiry)

                if let err = errorMessage {
                    Text(err)
                        .font(.ui(size: 12))
                        .foregroundStyle(Color.theme.neg)
                }

                PrimaryButton(label: "Save changes", busy: submitting) {
                    Task { await save() }
                }

                Button("Delete trade") {
                    Task { await deleteRow() }
                }
                .font(.ui(size: 13))
                .foregroundStyle(Color.theme.neg)
                .padding(.top, 6)

                Button("Cancel") { dismiss() }
                    .font(.ui(size: 13.5))
                    .foregroundStyle(Color.theme.fg3)
            }
            .padding(20)
        }
        .background(Color.theme.page.ignoresSafeArea())
        .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)
    }

    private func save() async {
        submitting = true
        defer { submitting = false }
        do {
            try await store.updateTrade(TradePatch(
                id: trade.id,
                optionType: optionType,
                direction: direction,
                contracts: contracts,
                strike: Double(strikeText) ?? trade.strike,
                premium: Double(premiumText) ?? trade.premium,
                expiry: expiry,
                tradeDate: tradeDate,
                note: nil
            ))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteRow() async {
        submitting = true
        defer { submitting = false }
        do {
            try await store.deleteTrade(id: trade.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Close Trade

struct CloseTradeSheet: View {
    let store: PortfolioStore
    let trade: OptionTradeRow

    @Environment(\.dismiss) private var dismiss
    @State private var contracts: Double = 0
    @State private var closePremiumText: String = ""
    @State private var closeDate: Date = Date()
    @State private var submitting: Bool = false
    @State private var errorMessage: String?

    init(store: PortfolioStore, trade: OptionTradeRow) {
        self.store = store
        self.trade = trade
        // Default to closing the remaining (still-active) contracts —
        // user can scale down for a partial close.
        _contracts = State(initialValue: store.remainingContracts(for: trade))
    }

    private var maxContracts: Double { store.remainingContracts(for: trade) }
    private var canSubmit: Bool {
        contracts > 0 && contracts <= maxContracts && Double(closePremiumText) != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SheetHeader(
                    title: "Close trade",
                    subtitle: "\(trade.ticker) $\(fmtStrike(trade.strike)) \(trade.option_type) · \(Int(maxContracts)) open"
                )

                NumberStepper(label: "Contracts to close", value: $contracts, step: 1, minimum: 1) {
                    "×\(Int($0))"
                }

                DecimalField(label: "Close premium $ per contract", placeholder: "0.00", text: $closePremiumText)
                DateField(label: "Close date", date: $closeDate)

                if contracts > maxContracts {
                    Text("Only \(Int(maxContracts)) contract\(Int(maxContracts) == 1 ? "" : "s") still open.")
                        .font(.ui(size: 12))
                        .foregroundStyle(Color.theme.warn)
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.ui(size: 12))
                        .foregroundStyle(Color.theme.neg)
                }

                PrimaryButton(
                    label: contracts >= maxContracts ? "Close full position" : "Close ×\(Int(contracts))",
                    busy: submitting,
                    destructive: true
                ) {
                    Task { await submit() }
                }
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.55)

                Button("Cancel") { dismiss() }
                    .font(.ui(size: 13.5))
                    .foregroundStyle(Color.theme.fg3)
            }
            .padding(20)
        }
        .background(Color.theme.page.ignoresSafeArea())
        .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)
    }

    private func submit() async {
        submitting = true
        defer { submitting = false }
        do {
            try await store.closeTrade(
                open: trade,
                contracts: min(contracts, maxContracts),
                closePremium: Double(closePremiumText) ?? 0,
                closeDate: closeDate
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Resolve Trade (expired / assigned)

struct ResolveTradeSheet: View {
    let store: PortfolioStore
    let trade: OptionTradeRow

    @Environment(\.dismiss) private var dismiss
    @State private var outcome: Outcome = .expired
    @State private var date: Date = Date()
    @State private var submitting: Bool = false
    @State private var errorMessage: String?

    enum Outcome { case expired, assigned }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeader(
                    title: "Resolve trade",
                    subtitle: "\(trade.ticker) $\(fmtStrike(trade.strike)) \(trade.option_type) · ×\(Int(trade.contracts))"
                )
                .frame(maxWidth: .infinity)

                VStack(spacing: 10) {
                    optionRow(.expired,
                              title: "Expired worthless",
                              detail: "Keep the full premium. No shares move.")
                    optionRow(.assigned,
                              title: trade.direction == "short" ? "Assigned" : "Exercised",
                              detail: assignedDetail)
                }

                DateField(label: "Date", date: $date)

                if let err = errorMessage {
                    Text(err)
                        .font(.ui(size: 12))
                        .foregroundStyle(Color.theme.neg)
                }

                PrimaryButton(
                    label: outcome == .expired ? "Confirm expiry" : "Confirm assignment",
                    busy: submitting
                ) {
                    Task { await submit() }
                }

                Button("Cancel") { dismiss() }
                    .font(.ui(size: 13.5))
                    .foregroundStyle(Color.theme.fg3)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .background(Color.theme.page.ignoresSafeArea())
        .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)
    }

    private var assignedDetail: String {
        let sh = Int(trade.contracts * 100)
        let k = fmtStrike(trade.strike)
        if trade.direction == "short" {
            return trade.option_type == "call"
                ? "\(sh) shares called away at $\(k)"
                : "Assigned \(sh) shares at $\(k)"
        } else {
            return trade.option_type == "call"
                ? "Exercise → buy \(sh) shares at $\(k)"
                : "Exercise → sell \(sh) shares at $\(k)"
        }
    }

    @ViewBuilder
    private func optionRow(_ o: Outcome, title: String, detail: String) -> some View {
        Button {
            withAnimation(Motion.standard) { outcome = o }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .strokeBorder(outcome == o ? Color.theme.neon : Color.theme.fg3, lineWidth: 1.5)
                    .background(
                        Circle().fill(outcome == o ? Color.theme.neon : Color.clear).scaleEffect(0.6)
                    )
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.ui(size: 14, weight: .bold))
                        .foregroundStyle(Color.theme.fg1)
                    Text(detail)
                        .font(.numeric(size: 11.5))
                        .foregroundStyle(Color.theme.fg3)
                }
                Spacer()
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(outcome == o ? Color.theme.tintNeon : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .strokeBorder(outcome == o ? Color.theme.neon : Color.theme.soft, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.pressable)
    }

    private func submit() async {
        submitting = true
        defer { submitting = false }
        do {
            switch outcome {
            case .expired:
                try await store.resolveExpired(open: trade, date: date)
            case .assigned:
                try await store.resolveAssigned(open: trade, date: date)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - FIFO assignment preview (sell-call entry)

/// Inline insight that appears as the user fills in a "Sell call" trade.
/// Walks the FIFO share lots for the ticker, surfaces which specific
/// lots would be called away if the call gets exercised, and shows the
/// projected booking math: premium received + shares P&L = total.
///
/// Pure read view — never mutates anything. If `share_lots` is empty
/// (migration not run yet) the view falls back to `positions.avg_cost`
/// so the projection still shows something useful.
struct SellCallAssignmentPreview: View {
    let store: PortfolioStore
    let ticker: String
    let strike: Double
    let contracts: Double
    let premiumPerContract: Double

    private var sharesNeeded: Double { contracts * 100 }
    private var premiumReceived: Double { premiumPerContract * contracts * 100 }

    /// FIFO simulation at the strike price — those lots being "sold at strike".
    private var consumption: [LotConsumption] {
        store.fifoSimulate(ticker: ticker.uppercased(), qty: sharesNeeded, sellPrice: strike)
    }

    private var sharesAvailable: Double {
        consumption.reduce(0) { $0 + $1.qtyConsumed }
    }
    private var sharesPnL: Double {
        consumption.reduce(0) { $0 + $1.realizedPL }
    }
    private var weightedAvg: Double {
        let q = sharesAvailable
        guard q > 0 else { return 0 }
        let totalCost = consumption.reduce(0) { $0 + $1.qtyConsumed * $1.lot.cost_per_share }
        return totalCost / q
    }
    private var totalBooked: Double { premiumReceived + sharesPnL }
    private var coverageOK: Bool { sharesAvailable >= sharesNeeded }

    var body: some View {
        if consumption.isEmpty {
            // No lots in the DB — either migration not yet applied or
            // genuinely no shares of this ticker. Either way, no projection.
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                header

                // Hero — total booked if exercised. Per-lot detail
                // intentionally hidden; users can drill into the
                // dedicated "Lots" tab of the ticker modal if they
                // want the lot-by-lot breakdown.
                VStack(alignment: .leading, spacing: 2) {
                    Text(fmtMoney(totalBooked, sign: true))
                        .font(.numeric(size: 26, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(Color.signed(totalBooked))
                    Text("if exercised")
                        .font(.ui(size: 9.5, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Color.theme.fg3)
                        .padding(.bottom, 4)
                    Text("premium \(fmtMoney(premiumReceived, sign: true)) · shares \(fmtMoney(sharesPnL, sign: true)) (avg $\(String(format: "%.2f", weightedAvg)))")
                        .font(.numeric(size: 11.5))
                        .foregroundStyle(Color.theme.fg3)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(Color.theme.tintNeon)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .strokeBorder(Color.theme.neon.opacity(0.20), lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.theme.neon)
            Text("IF EXERCISED · FIFO PROJECTION")
                .font(.ui(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Color.theme.fg2)
            Spacer()
            let icon = coverageOK ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
            let tint = coverageOK ? Color.theme.neon : Color.theme.warn
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text("\(Int(sharesAvailable).formatted(.number.grouping(.never)))/\(Int(sharesNeeded).formatted(.number.grouping(.never))) covered")
                    .font(.numeric(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
    }

    @ViewBuilder
    private func lotRow(_ c: LotConsumption) -> some View {
        let dateShort = AppDates.shortMonthDay(c.lot.acquired_date)
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Int(c.qtyConsumed).formatted(.number.grouping(.never))) sh @ $\(String(format: "%.2f", c.lot.cost_per_share))")
                    .font(.numeric(size: 12, weight: .medium))
                    .foregroundStyle(Color.theme.fg1)
                Text("acquired \(dateShort) · lot #\(c.lot.fifo_order)")
                    .font(.numeric(size: 10))
                    .foregroundStyle(Color.theme.fg3)
            }
            Spacer()
            Text(fmtMoney(c.realizedPL, sign: true))
                .font(.numeric(size: 12, weight: .medium))
                .foregroundStyle(Color.signed(c.realizedPL))
        }
    }
}
