//
//  DownsideProtectionSheet.swift
//  Sunnyfi
//
//  Drill-in opened from the "Net cost" row on Open puts bought.
//  Standardized popup shape from design_handoff_standardized_popups.
//
//  Headline question this view answers: "How far do my shares have
//  to drop before each protective put starts paying?"
//
//  Patch block:
//    PROTECTION mini-label + status tag (e.g. "8.4% avg cushion")
//    Hero: net hedge cost (out-of-pocket)
//    ZoneGauge — left "EXPOSED", right "FULLY HEDGED" — value is
//    the share of share-book notional that has a put under it (capped
//    at 100%).
//    3 stats: Hedge cost · Puts P/L · Net cost
//
//  By-position:
//    One MiniTrack per open long put. fill = (strike / spot), so a
//    higher fill means the put is closer to ATM (more actively
//    protective). Tone = neg when cushion < 5%, pos otherwise.
//

import SwiftUI

struct DownsideProtectionSheet: View {
    let store: PortfolioStore
    let onClose: () -> Void

    // ── Derived ────────────────────────────────────────────────────
    private var rows: [TradesData.ProtectionRow] {
        TradesData.protectionRows(store: store)
    }
    private var putPaid: Double { TradesData.openPutsPaid(store: store) }
    private var putGain: Double { TradesData.putGain(store: store) }
    private var netCost: Double { TradesData.netCost(store: store) }
    private var sharesValue: Double { TradesData.openSharesValue(store: store) }

    /// Σ (contracts × 100 × strike) — the notional dollar value of
    /// shares that fall under at least one put's strike. Capped at
    /// total share value for the gauge fill.
    private var protectedNotional: Double {
        rows.reduce(0) { $0 + $1.contracts * 100 * $1.strike }
    }
    private var coveragePct: Double {
        guard sharesValue > 0 else { return 0 }
        return min(100, (protectedNotional / sharesValue) * 100)
    }
    /// Contracts-weighted average cushion for the status tag.
    private var avgCushion: Double {
        let total = rows.reduce(0.0) { $0 + $1.contracts }
        guard total > 0 else { return 0 }
        let weighted = rows.reduce(0.0) { $0 + $1.cushionPct * $1.contracts }
        return weighted / total
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SheetHead(
                    tag: "DOWNSIDE PROTECTION",
                    title: "How far is the floor?",
                    subcopy: subCopy
                )
                .padding(.top, 8)
                .padding(.bottom, 18)

                patch
                    .padding(.bottom, 22)

                if rows.isEmpty {
                    emptyState
                } else {
                    putsGroup
                }

                Spacer(minLength: 18)
                SheetDoneButton(onTap: onClose)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(Color.theme.elevated.ignoresSafeArea())
    }

    private var subCopy: String {
        if rows.isEmpty {
            return "No protective puts on the book. The share position is fully exposed to a drawdown."
        }
        return String(format:
            "Your protective puts kick in once the underlying drops past their strike. Average cushion across open puts is %.1f%%.",
            avgCushion
        )
    }

    // MARK: - Patch

    private var patch: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("PROTECTION COVERAGE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.theme.fg3)
                Spacer()
                if !rows.isEmpty {
                    PatchTag(
                        text: String(format: "%.1f%% avg cushion", avgCushion),
                        tone: avgCushion < 5 ? .neg : .neutral
                    )
                }
            }
            Text(plainMoney(netCost))
                .font(.system(size: 30, weight: .semibold))
                .monospacedDigit()
                .tracking(-0.9)
                .foregroundStyle(Color.theme.fg1)
            Text("out of pocket on the hedge")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.theme.fg3)

            ZoneGauge(value: coveragePct,
                      leftLabel: "Exposed",
                      rightLabel: "Fully hedged")
                .padding(.top, 2)

            PatchStatsRow(stats: [
                .init(label: "Hedge cost", value: "\u{2212}" + plainMoney(putPaid), tone: .neg),
                .init(label: "Puts P/L",   value: signedMoney(putGain),
                      tone: putGain >= 0 ? .pos : .neg),
                .init(label: "Net cost",   value: "\u{2212}" + plainMoney(netCost), tone: .neg),
            ])
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.theme.page2)
        )
    }

    // MARK: - By-position

    private var putsGroup: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("BY POSITION · TIGHTEST CUSHION FIRST")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Color.theme.fg3)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                    if idx > 0 {
                        Rectangle().fill(Color.theme.hair).frame(height: 1)
                    }
                    row(for: r)
                        .padding(.vertical, 13)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for r: TradesData.ProtectionRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.ticker)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.theme.fg1)
                    Text("\(Int(r.contracts)) ct · $\(strikeFmt(r.strike)) put · spot $\(strikeFmt(r.spot)) · exp \(shortDate(r.expiry))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.theme.fg3)
                }
                Spacer()
                Text(cushionLabel(for: r))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(r.cushionPct < 5 ? Color.theme.neg : Color.theme.fg1)
            }
            // Strike-to-spot mini track. fill = strike / spot capped
            // at 100%; the visual "fills up" as spot collapses toward
            // the strike (i.e. as the cushion shrinks).
            MiniTrack(
                fillPct: min(100, (r.strike / r.spot) * 100),
                markPct: min(100, (r.strike / r.spot) * 100),
                tone: r.cushionPct < 5 ? .neg : .pos
            )
            .padding(.top, 8)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No open protective puts.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.theme.fg2)
            Text("Buy a long put to set a floor under your shares — the row will appear here.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.theme.fg3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.theme.page2)
        )
    }

    // MARK: - Format

    private func cushionLabel(for r: TradesData.ProtectionRow) -> String {
        let sign = r.cushionPct >= 0 ? "" : "\u{2212}"
        return String(format: "%@%.1f%%", sign, abs(r.cushionPct))
    }
    private func plainMoney(_ v: Double) -> String {
        let abs = Int(Swift.abs(v).rounded())
        return "$" + abs.formatted(.number.grouping(.automatic))
    }
    private func signedMoney(_ v: Double) -> String {
        let abs = Int(Swift.abs(v).rounded())
        let formatted = abs.formatted(.number.grouping(.automatic))
        if v > 0 { return "+$\(formatted)" }
        if v < 0 { return "\u{2212}$\(formatted)" }
        return "$\(formatted)"
    }
    private func strikeFmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", v)
            : String(format: "%.2f", v)
    }
    /// Backed by static formatters in `Fmt` (Formatters.swift).
    private func shortDate(_ ymd: String) -> String { Fmt.shortDate(ymd) }
}
