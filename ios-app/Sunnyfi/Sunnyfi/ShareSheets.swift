//
//  ShareSheets.swift
//  Sunnyfi
//
//  Buy / sell shares sheets — write to `positions` and `share_sells`
//  via PortfolioStore.buyShares / .sellShares. Same tables as the web.
//

import SwiftUI

struct BuySharesSheet: View {
    let store: PortfolioStore
    let ticker: String

    @Environment(\.dismiss) private var dismiss
    @State private var qtyText: String = ""
    @State private var priceText: String = ""
    @State private var submitting: Bool = false
    @State private var errorMessage: String?

    private var qty: Double? { Double(qtyText) }
    private var price: Double? { Double(priceText) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Capsule().fill(Color.white.opacity(0.22))
                    .frame(width: 38, height: 5).padding(.top, 4)

                VStack(spacing: 4) {
                    Text("Buy shares")
                        .font(.ui(size: 19, weight: .bold))
                        .foregroundStyle(Color.theme.fg1)
                    Text("\(ticker) · add to your position")
                        .font(.ui(size: 12.5))
                        .foregroundStyle(Color.theme.fg3)
                }

                fieldRow("Quantity", placeholder: "100", text: $qtyText)
                fieldRow("Price $",  placeholder: "0.00", text: $priceText)

                if let q = qty, let p = price {
                    HStack {
                        Text("Cost")
                            .font(.ui(size: 11))
                            .foregroundStyle(Color.theme.fg3)
                        Spacer()
                        Text(fmtMoney(q * p))
                            .font(.numeric(size: 17, weight: .medium))
                            .foregroundStyle(Color.theme.fg1)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .fill(Color.theme.tintMuted)
                    )
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.ui(size: 12))
                        .foregroundStyle(Color.theme.neg)
                }

                Button {
                    Task { await submit() }
                } label: {
                    ZStack {
                        Capsule().fill(Color.theme.neon)
                        if submitting { ProgressView().tint(.black) }
                        else { Text("Buy shares")
                                .font(.ui(size: 15, weight: .bold))
                                .foregroundStyle(Color.theme.onNeon) }
                    }
                    .frame(height: 48)
                }
                .buttonStyle(.pressable)
                .disabled(qty == nil || price == nil || submitting)
                .opacity((qty == nil || price == nil) ? 0.55 : 1)

                Button("Cancel") { dismiss() }
                    .font(.ui(size: 13.5))
                    .foregroundStyle(Color.theme.fg3)
            }
            .padding(20)
        }
        .background(Color.theme.page.ignoresSafeArea())
        .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)
    }

    @ViewBuilder
    private func fieldRow(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased())
                .font(.ui(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.theme.fg3)
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Color.theme.fg4))
                .keyboardType(.decimalPad)
                .font(.numeric(size: 16))
                .foregroundStyle(Color.theme.fg1)
                .padding(12)
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

    private func submit() async {
        guard let q = qty, let p = price else { return }
        submitting = true
        defer { submitting = false }
        do {
            try await store.buyShares(ticker: ticker, quantity: q, price: p)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SellSharesSheet: View {
    let store: PortfolioStore
    let ticker: String
    let onHand: Double

    @Environment(\.dismiss) private var dismiss
    @State private var qtyText: String = ""
    @State private var priceText: String = ""
    @State private var submitting: Bool = false
    @State private var errorMessage: String?

    private var qty: Double? { Double(qtyText) }
    private var price: Double? { Double(priceText) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Capsule().fill(Color.white.opacity(0.22))
                    .frame(width: 38, height: 5).padding(.top, 4)

                VStack(spacing: 4) {
                    Text("Sell shares")
                        .font(.ui(size: 19, weight: .bold))
                        .foregroundStyle(Color.theme.fg1)
                    Text("\(ticker) · \(Int(onHand)) sh on hand")
                        .font(.ui(size: 12.5))
                        .foregroundStyle(Color.theme.fg3)
                }

                fieldRow("Quantity", placeholder: "100", text: $qtyText)
                fieldRow("Price $",  placeholder: "0.00", text: $priceText)

                // FIFO preview — appears the moment qty + price are valid.
                if let q = qty, q > 0, let p = price, p > 0 {
                    fifoPreview(qty: q, price: p)
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.ui(size: 12))
                        .foregroundStyle(Color.theme.neg)
                }

                Button {
                    Task { await submit() }
                } label: {
                    ZStack {
                        Capsule().fill(Color.theme.neg)
                        if submitting { ProgressView().tint(.white) }
                        else { Text("Sell shares")
                                .font(.ui(size: 15, weight: .bold))
                                .foregroundStyle(Color.white) }
                    }
                    .frame(height: 48)
                }
                .buttonStyle(.pressable)
                .disabled(qty == nil || price == nil || (qty ?? 0) > onHand || submitting)
                .opacity((qty == nil || price == nil || (qty ?? 0) > onHand) ? 0.55 : 1)

                Button("Cancel") { dismiss() }
                    .font(.ui(size: 13.5))
                    .foregroundStyle(Color.theme.fg3)
            }
            .padding(20)
        }
        .background(Color.theme.page.ignoresSafeArea())
        .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)
    }

    /// Shows exactly which lots will be consumed by the proposed sell
    /// + the per-lot realized P&L + the total. Updates live as the
    /// user changes qty / price. No mutation happens here — it's a
    /// pure simulation of what `sellShares` is about to do.
    @ViewBuilder
    private func fifoPreview(qty: Double, price: Double) -> some View {
        let plan = store.fifoSimulate(ticker: ticker, qty: qty, sellPrice: price)
        let total = plan.reduce(0) { $0 + $1.realizedPL }
        let planned = plan.reduce(0) { $0 + $1.qtyConsumed }
        let coverageOK = planned >= qty

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.theme.neon)
                Text("FIFO PREVIEW")
                    .font(.ui(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Color.theme.fg2)
                Spacer()
                let icon = coverageOK ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                let tint = coverageOK ? Color.theme.neon : Color.theme.warn
                HStack(spacing: 4) {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                    Text("\(Int(planned).formatted(.number.grouping(.never)))/\(Int(qty).formatted(.number.grouping(.never))) covered")
                        .font(.numeric(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }

            if plan.isEmpty {
                Text("No lots available — share_lots may not be seeded yet.")
                    .font(.ui(size: 11))
                    .foregroundStyle(Color.theme.fg3)
            } else {
                VStack(spacing: 6) {
                    ForEach(plan.prefix(6)) { c in lotRow(c) }
                    if plan.count > 6 {
                        Text("+ \(plan.count - 6) more lot\(plan.count - 6 == 1 ? "" : "s")")
                            .font(.numeric(size: 10.5))
                            .foregroundStyle(Color.theme.fg3)
                    }
                }

                Divider().background(Color.theme.hair)

                HStack(alignment: .firstTextBaseline) {
                    Text("REALIZED")
                        .font(.ui(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.theme.fg3)
                    Spacer()
                    Text(fmtMoney(total, sign: true))
                        .font(.numeric(size: 20, weight: .bold))
                        .foregroundStyle(Color.signed(total))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.theme.tintNeon)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .strokeBorder(Color.theme.neon.opacity(0.18), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func lotRow(_ c: LotConsumption) -> some View {
        let dateShort = AppDates.shortMonthDay(c.lot.acquired_date)
        HStack {
            Text("\(Int(c.qtyConsumed).formatted(.number.grouping(.never))) sh @ $\(String(format: "%.2f", c.lot.cost_per_share))")
                .font(.numeric(size: 11.5, weight: .medium))
                .foregroundStyle(Color.theme.fg1)
            Text("· \(dateShort) #\(c.lot.fifo_order)")
                .font(.numeric(size: 10))
                .foregroundStyle(Color.theme.fg3)
            Spacer()
            Text(fmtMoney(c.realizedPL, sign: true))
                .font(.numeric(size: 11.5, weight: .medium))
                .foregroundStyle(Color.signed(c.realizedPL))
        }
    }

    @ViewBuilder
    private func fieldRow(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased())
                .font(.ui(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.theme.fg3)
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Color.theme.fg4))
                .keyboardType(.decimalPad)
                .font(.numeric(size: 16))
                .foregroundStyle(Color.theme.fg1)
                .padding(12)
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

    private func submit() async {
        guard let q = qty, let p = price else { return }
        submitting = true
        defer { submitting = false }
        do {
            try await store.sellShares(ticker: ticker, quantity: q, price: p)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
