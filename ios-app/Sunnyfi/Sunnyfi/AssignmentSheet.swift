//
//  AssignmentSheet.swift
//  Sunnyfi
//
//  Full-screen Assignment ticket — opened from the "Likely
//  assignment · log it →" CTA on a short call that's ITM with
//  DTE ≤ 1. Per Handoff 2 §6.
//
//  FIFO is REAL here — not a stock-avg proxy:
//   • The preview's "Cost basis · FIFO" reads the actual oldest
//     lots from `store.allShareLots` and computes the
//     weighted-avg cost basis of the specific lots that would be
//     consumed. If the user has 200 sh @ $400 + 200 sh @ $500 and
//     gets 1 call assigned (100 sh away), the projection shows
//     $400 — the cheapest lot's cost — not the position avg ($450).
//   • Confirm calls `resolveAssigned(open:date:note:)`, which
//     atomically: (1) inserts the option-close row tagged
//     `closed_via: "assigned"`, (2) inserts a `share_sells` row
//     with `source: "assignment"`, (3) writes per-lot
//     `share_lot_consumptions` and decrements `qty_remaining` on
//     each consumed lot, (4) recomputes the positions aggregate.
//     The realized P&L on the option close is the lot-derived
//     `share_pnl`, so the back-end ledger ends up correct.
//

import SwiftUI

struct AssignmentSheet: View {
    let store: PortfolioStore
    let trade: OptionTradeRow
    var onDismiss: () -> Void

    @State private var saving = false
    @State private var error: String?

    // ── Derived ─────────────────────────────────────────────────
    private var contracts: Double {
        store.remainingContracts(for: trade)
    }
    private var sharesAway: Double { contracts * 100 }
    private var strike: Double { trade.strike }
    private var premiumKept: Double {
        contracts * trade.premium * 100
    }

    /// REAL FIFO projection — walks `store.allShareLots` for this
    /// ticker oldest-first, tallies up the lots that would be
    /// consumed to cover `sharesAway`. Returns the cost-basis
    /// figures the preview needs.
    private struct FifoProjection {
        let weightedAvgCost: Double    // cost basis of consumed lots only
        let coveredQty: Double         // how many shares were actually plannable
        let shortFall: Double          // > 0 means not enough lots in DB
        let realized: Double           // (strike − avgCost) × coveredQty + premium
    }

    private var fifo: FifoProjection {
        // Oldest active lot first — matches the back-end fifoPlan
        // ordering (acquired_date asc, fifo_order asc).
        let lots = store.allShareLots
            .filter { $0.ticker == trade.ticker.uppercased() && $0.qty_remaining > 0 }
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
        let avg = consumedQty > 0 ? consumedCost / consumedQty : 0
        let realized = (strike - avg) * consumedQty + premiumKept
        return FifoProjection(
            weightedAvgCost: avg,
            coveredQty: consumedQty,
            shortFall: remaining,
            realized: realized
        )
    }

    private var stockLeg: Leg? {
        store.companies
            .first(where: { $0.ticker == trade.ticker })?
            .legs.first(where: { $0.kind == .stock })
    }
    private var proceeds: Double { strike * sharesAway }
    private var sharesLeft: Double {
        max(0, (stockLeg?.qty ?? 0) - sharesAway)
    }
    private var hasShortfall: Bool { fifo.shortFall > 0.001 }

    var body: some View {
        VStack(spacing: 0) {
            head
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    contextBlock
                    neonNote.padding(.top, 18)
                    if hasShortfall {
                        shortfallBanner.padding(.top, 12)
                    }
                    rows.padding(.top, 22)
                    summary.padding(.top, 20)
                    if let err = error {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.theme.neg)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.theme.surface.ignoresSafeArea())
    }

    // MARK: Head

    private var head: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.theme.fg2)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.theme.surface))
                    .overlay(Circle().strokeBorder(Color.theme.borderBright, lineWidth: 1))
            }
            Text("Assignment")
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

    // MARK: Context block

    private var contextBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(trade.ticker) $\(fmtStrike(strike)) Call assigned")
                .font(.system(size: 22, weight: .heavy))
                .monospacedDigit()
                .tracking(-0.7)
                .foregroundStyle(Color.theme.fg1)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text("\(Int(contracts)) contract\(Int(contracts) == 1 ? "" : "s") · in the money · \(expiryPhrase)")
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.theme.neg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Honest sub-line: "expires today" for DTE 0, "expires
    /// tomorrow" for DTE 1, else the actual date. (The assignment
    /// CTA only triggers for DTE ≤ 1, but the prototype lock-in to
    /// "expires today" was misleading on DTE 1.)
    private var expiryPhrase: String {
        let dte = AppDates.daysUntil(trade.expiry) ?? 999
        if dte == 0 { return "expires today" }
        if dte == 1 { return "expires tomorrow" }
        return "expires \(AppDates.shortMonthDay(trade.expiry))"
    }

    // MARK: Neon ✦ note

    private var neonNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("✦")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.theme.neon)
            Text("\(Int(sharesAway).formatted(.number)) shares called away at $\(fmtStrike(strike)) — sold FIFO from your lowest-cost lots.")
                .font(.system(size: 13))
                .foregroundStyle(Color.theme.fg2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Color.theme.tintNeon)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(Color.theme.neon.opacity(0.28), lineWidth: 1)
                )
        )
    }

    /// Red banner — fires when the user's lot ledger has fewer
    /// shares than the assignment would call away. Prevents a
    /// confusing "Confirm" that would fail mid-write.
    private var shortfallBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.theme.neg)
            Text("Only \(Int(fifo.coveredQty).formatted(.number)) of \(Int(sharesAway).formatted(.number)) shares available in lots. Confirm will fail — log more lots first.")
                .font(.system(size: 12))
                .foregroundStyle(Color.theme.neg)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Color.theme.tintNeg)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(Color.theme.neg.opacity(0.4), lineWidth: 1)
                )
        )
    }

    // MARK: Rows

    @ViewBuilder
    private var rows: some View {
        VStack(spacing: 0) {
            row(label: "Shares called away",
                value: Int(sharesAway).formatted(.number),
                isFirst: true)
            row(label: "Sale price · strike",
                value: "$\(fmtStrike(strike))")
            row(label: "Cost basis · FIFO",
                value: fifo.weightedAvgCost > 0
                    ? fmtMoney(fifo.weightedAvgCost, decimals: 2)
                    : "—")
            row(label: "Premium kept",
                value: fmtMoney(premiumKept, sign: true))
        }
    }

    @ViewBuilder
    private func row(label: String, value: String, isFirst: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.theme.labelMuted)
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .medium))
                .monospacedDigit()
                .tracking(-0.16)
                .foregroundStyle(Color.theme.fg1)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .top) {
            if !isFirst {
                Color.theme.borderBright.opacity(0.5).frame(height: 1)
            }
        }
    }

    // MARK: Summary strip

    @ViewBuilder
    private var summary: some View {
        HStack(spacing: 10) {
            sumCell("Proceeds", fmtMoney(proceeds))
            sumCell("Realized", fmtMoney(fifo.realized, sign: true))
            sumCell("Shares left", Int(sharesLeft).formatted(.number))
        }
        .padding(.top, 16)
        .padding(.bottom, 2)
        .overlay(alignment: .top) {
            Color.theme.borderBright.frame(height: 1.5)
        }
    }

    @ViewBuilder
    private func sumCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .regular))
                .tracking(0.7)
                .foregroundStyle(Color.theme.fg3)
            Text(value)
                .font(.system(size: 16, weight: .medium))
                .monospacedDigit()
                .tracking(-0.16)
                .foregroundStyle(Color.theme.fg1)
                .padding(.top, 6)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        Button(action: { Task { await confirm() } }) {
            Text(saving ? "Confirming…" : "Confirm assignment")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.theme.onNeon)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(Color.theme.neon))
                .opacity(hasShortfall ? 0.4 : 1.0)
        }
        .buttonStyle(.pressable)
        .disabled(saving || hasShortfall)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Color.theme.surface
                .overlay(
                    Color.theme.borderBright.opacity(0.5).frame(height: 1),
                    alignment: .top
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: Confirm

    /// Atomic assignment via the proper writer:
    ///   1. Insert the option `close` row tagged
    ///      `closed_via: "assigned"`, with `share_pnl` set to the
    ///      lot-derived realized total.
    ///   2. Insert a `share_sells` row at the strike, source
    ///      `"assignment"`.
    ///   3. Insert per-lot `share_lot_consumptions` + decrement
    ///      `qty_remaining` on each consumed lot.
    ///   4. Recompute the positions aggregate.
    ///
    /// Errors bubble up to the inline banner — most commonly
    /// "Assignment would call away N sh but only M lots
    /// available", which the shortfall banner already guards.
    private func confirm() async {
        do {
            saving = true; error = nil
            try await store.resolveAssigned(open: trade, date: Date(), note: nil)
            onDismiss()
        } catch {
            self.error = (error as NSError).localizedDescription
        }
        saving = false
    }
}
