//
//  BreakevenSheet.swift
//  Sunnyfi
//
//  Drill-in opened from the "Effective basis" row on Open shares.
//  Standardized popup shape from design_handoff_standardized_popups.
//
//  Per the locked design decision, break-even math uses the EFFECTIVE
//  (lifetime-adjusted) basis — raw cost minus lifetime premium
//  harvested on that ticker. That matches the figure shown on the
//  Open shares card itself, so the two views agree.
//
//  Patch block:
//    BREAK-EVEN mini-label + status tag (e.g. "+2.3% over basis")
//    Hero: portfolio effective basis $
//    ZoneGauge — left "UNDERWATER", right "IN PROFIT" — value is
//    portfolio gain over effective basis (clamped 0..100 around 50%
//    midpoint).
//    3 stats: Cost · Collected · Effective basis
//
//  By-position:
//    One row per share lot with a MiniTrack. fill = current price
//    relative to effective basis (capped at 100%). Tone neg when
//    underwater, pos when in profit.
//

import SwiftUI

struct BreakevenSheet: View {
    let store: PortfolioStore
    let onClose: () -> Void

    // ── Derived ────────────────────────────────────────────────────
    private var rows: [TradesData.BreakevenRow] {
        TradesData.breakevenRows(store: store)
    }
    private var cost: Double { TradesData.openSharesCost(store: store) }
    private var valueNow: Double { TradesData.openSharesValue(store: store) }
    private var effectiveBasis: Double { TradesData.effectiveBasis(store: store) }
    private var effectiveBasisPct: Double { TradesData.effectiveBasisPct(store: store) }
    private var lifetimeCollected: Double { TradesData.lifetimePremiumHarvested(store: store) }

    /// Portfolio gain over effective basis (% of effective basis).
    private var portfolioGainPct: Double {
        guard effectiveBasis > 0 else { return 0 }
        return (valueNow - effectiveBasis) / effectiveBasis * 100
    }
    /// Map portfolioGainPct into a 0..100 gauge value with 50%
    /// representing exactly break-even. ±25% saturates the ends.
    private var gaugeValue: Double {
        let raw = 50 + portfolioGainPct * 2
        return min(100, max(0, raw))
    }
    private var inProfit: Bool { portfolioGainPct >= 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SheetHead(
                    tag: "BREAK-EVEN",
                    title: "Real cost after premium",
                    subcopy: subCopy
                )
                .padding(.top, 8)
                .padding(.bottom, 18)

                patch
                    .padding(.bottom, 22)

                if rows.isEmpty {
                    emptyState
                } else {
                    rowsGroup
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
        let intro = "Lifetime option premium subtracted from share cost — the price the market actually has to recover to."
        if rows.isEmpty { return intro + " No open share lots yet." }
        let signed = String(format: "%@%.2f%%",
                            portfolioGainPct >= 0 ? "+" : "\u{2212}",
                            abs(portfolioGainPct))
        return intro + " Portfolio is \(signed) vs effective basis."
    }

    // MARK: - Patch

    private var patch: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("EFFECTIVE BASIS")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.theme.fg3)
                Spacer()
                if !rows.isEmpty {
                    PatchTag(
                        text: tagText,
                        tone: inProfit ? .pos : .neg
                    )
                }
            }
            Text(plainMoney(effectiveBasis))
                .font(.system(size: 30, weight: .semibold))
                .monospacedDigit()
                .tracking(-0.9)
                .foregroundStyle(Color.theme.fg1)
            Text(String(format: "%@%.2f%% vs raw cost",
                        effectiveBasisPct >= 0 ? "+" : "\u{2212}",
                        abs(effectiveBasisPct)))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.theme.fg3)

            ZoneGauge(value: gaugeValue,
                      leftLabel: "Underwater",
                      rightLabel: "In profit")
                .padding(.top, 2)

            PatchStatsRow(stats: [
                .init(label: "Cost",      value: plainMoney(cost),              tone: .neutral),
                .init(label: "Collected", value: "+" + plainMoney(lifetimeCollected), tone: .pos),
                .init(label: "Effective", value: plainMoney(effectiveBasis),    tone: .neutral),
            ])
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.theme.page2)
        )
    }

    private var tagText: String {
        let sign = portfolioGainPct >= 0 ? "+" : "\u{2212}"
        return String(format: "%@%.1f%% vs basis", sign, abs(portfolioGainPct))
    }

    // MARK: - By-position

    private var rowsGroup: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("BY LOT · WORST RECOVERY FIRST")
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
    private func row(for r: TradesData.BreakevenRow) -> some View {
        // Track fill: current price as % of effective basis, capped
        // at 100%. Underwater → fills toward effective basis from
        // below. In profit → already pinned at 100%.
        let pct = r.effectiveAvg > 0 ? min(100, (r.last / r.effectiveAvg) * 100) : 0
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.ticker)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.theme.fg1)
                    Text(secondaryLine(for: r))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.theme.fg3)
                }
                Spacer()
                Text(amountLabel(for: r))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(r.underwater ? Color.theme.neg : Color.theme.pos)
            }
            MiniTrack(
                fillPct: pct,
                markPct: pct,
                tone: r.underwater ? .neg : .pos
            )
            .padding(.top, 8)
        }
    }

    private func secondaryLine(for r: TradesData.BreakevenRow) -> String {
        let qty = Int(r.shares.rounded())
        return "\(qty) sh · cost $\(strikeFmt(r.avg)) · eff $\(strikeFmt(r.effectiveAvg)) · last $\(strikeFmt(r.last))"
    }
    private func amountLabel(for r: TradesData.BreakevenRow) -> String {
        if r.underwater {
            return String(format: "needs +%.1f%%", r.needPct)
        }
        return String(format: "+%.1f%%", r.gainPct)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No open share lots.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.theme.fg2)
            Text("Once you hold shares, each lot's break-even appears here against the lifetime-adjusted basis.")
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

    private func plainMoney(_ v: Double) -> String {
        let abs = Int(Swift.abs(v).rounded())
        return "$" + abs.formatted(.number.grouping(.automatic))
    }
    private func strikeFmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", v)
            : String(format: "%.2f", v)
    }
}
