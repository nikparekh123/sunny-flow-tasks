//
//  HedgeBudgetCard.swift
//  Sunnyfi
//
//  Planner-tab hero: how much call premium have I collected this
//  week / month vs the hedge cost I need to cover. Centered around a
//  progress bar so the gap (or surplus) is visible at a glance.
//
//  Period toggle scales both numerator and denominator together:
//   • WEEK  → 5-trading-day burn  vs  short-call credits since Monday
//   • MONTH → ~21-day burn        vs  short-call credits since the 1st
//
//  Expanding shows the per-put breakdown (sorted by daily burn).
//

import SwiftUI

struct HedgeBudgetCard: View {
    let store: PortfolioStore

    enum Period: String, CaseIterable, Identifiable {
        case week = "WEEK", month = "MONTH"
        var id: String { rawValue }
        var label: String { rawValue.lowercased() }   // "week" / "month"
    }

    @State private var period: Period = .week
    @State private var expanded: Bool = false

    // ── Derived ──
    private var budget: HedgeBudget { store.hedgeBudget }

    /// Hedge cost target for the chosen period.
    private var target: Double {
        switch period {
        case .week:  return budget.weeklyBurn
        case .month: return budget.monthlyBurn
        }
    }

    /// Short-call credits collected since the start of the period.
    private var collected: Double {
        let start: Date
        switch period {
        case .week:  start = AppDates.startOfWeek(Date())
        case .month: start = AppDates.startOfMonth(Date())
        }
        return store.shortCallPremiumCollected(since: start)
    }

    /// 0…1 for the fill width. Caps at 1; the surplus shows as a
    /// separate label rather than overflowing the bar.
    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(1.0, collected / target)
    }
    private var pctInt: Int {
        guard target > 0 else { return 0 }
        return Int((collected / target * 100).rounded())
    }
    private var gap: Double      { max(0, target - collected) }
    private var surplus: Double  { max(0, collected - target) }
    private var isCovered: Bool  { target > 0 && collected >= target }

    // ── Body ──
    var body: some View {
        if budget.isEmpty {
            emptyState
        } else {
            populated
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HEDGE BUDGET")
                .font(.ui(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color.theme.fg3)
            Text("No open long puts — book is unhedged.")
                .font(.ui(size: 13, weight: .medium))
                .foregroundStyle(Color.theme.fg2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.theme.cardSolid)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .strokeBorder(Color.theme.soft, lineWidth: 1)
                )
        )
    }

    private var populated: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            hero
            progressBar
            gapLine
            if expanded {
                divider
                legsList
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.theme.cardSolid)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .strokeBorder(
                            isCovered ? Color.theme.pos.opacity(0.35) : Color.theme.neg.opacity(0.30),
                            lineWidth: 1
                        )
                )
        )
        .animation(Motion.standard, value: expanded)
        .animation(Motion.standard, value: period)
    }

    // ── Header: title left, period toggle middle, expand chevron right ──
    private var header: some View {
        HStack(spacing: 10) {
            Text("HEDGE BUDGET")
                .font(.ui(size: 10, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Color.theme.fg2)
            Spacer()
            periodToggle
            Button {
                withAnimation(Motion.standard) { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.theme.fg3)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
    }

    private var periodToggle: some View {
        HStack(spacing: 2) {
            ForEach(Period.allCases) { p in
                let active = p == period
                Button {
                    withAnimation(Motion.standard) { period = p }
                } label: {
                    Text(p.rawValue)
                        .font(.ui(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(active ? Color.theme.onNeon : Color.theme.fg2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(active ? Color.theme.neon : Color.clear)
                        )
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.theme.soft, lineWidth: 1)
        )
    }

    // ── Hero numbers: collected / target ──
    private var hero: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(fmtMoney(collected))
                    .font(.numeric(size: 28, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(isCovered ? Color.theme.pos : Color.theme.neon)
                Text("calls sold · \(period.label)")
                    .font(.ui(size: 10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Color.theme.fg3)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(fmtMoney(target))
                    .font(.numeric(size: 20, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.theme.fg1)
                Text("hedge target")
                    .font(.ui(size: 10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Color.theme.fg3)
            }
        }
    }

    // ── Progress bar ──
    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.theme.soft.opacity(0.4))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: isCovered
                                    ? [Color.theme.pos, Color.theme.pos.opacity(0.7)]
                                    : [Color.theme.neon, Color.theme.neonDark],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, geo.size.width * progress))
                        .animation(Motion.easeOut, value: progress)
                }
            }
            .frame(height: 10)

            HStack {
                Text("\(pctInt)% covered")
                    .font(.numeric(size: 11, weight: .bold))
                    .foregroundStyle(isCovered ? Color.theme.pos : Color.theme.neon)
                Spacer()
                Text("\(Int(budget.openPutCount)) open put\(budget.openPutCount == 1 ? "" : "s") · \(fmtMoney(budget.totalCost)) at risk")
                    .font(.numeric(size: 11, weight: .medium))
                    .foregroundStyle(Color.theme.fg3)
            }
        }
    }

    // ── One-line gap message ──
    @ViewBuilder
    private var gapLine: some View {
        if isCovered {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.theme.pos)
                Text("Hedges covered. \(fmtMoney(surplus)) banked on top.")
                    .font(.ui(size: 12, weight: .semibold))
                    .foregroundStyle(Color.theme.fg2)
                Spacer()
            }
        } else if target > 0 {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.theme.warn)
                Text("\(fmtMoney(gap)) short to break even on \(period.label)'s burn.")
                    .font(.ui(size: 12, weight: .semibold))
                    .foregroundStyle(Color.theme.fg2)
                Spacer()
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.theme.soft.opacity(0.6))
            .frame(height: 1)
    }

    // ── Expanded per-put breakdown ──
    private var legsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OPEN PUTS — sorted by daily burn")
                .font(.ui(size: 9.5, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Color.theme.fg3)
            ForEach(budget.legs) { leg in
                legRow(leg)
            }
        }
    }

    @ViewBuilder
    private func legRow(_ leg: HedgeLeg) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(leg.ticker) $\(fmtStrike(leg.strike))p")
                    .font(.ui(size: 13, weight: .bold))
                    .foregroundStyle(Color.theme.fg1)
                Text("\(AppDates.shortMonthDay(leg.expiry)) · \(Int(leg.contractsRemaining)) ct")
                    .font(.numeric(size: 10, weight: .medium))
                    .foregroundStyle(Color.theme.fg3)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(fmtMoney(leg.costBasis))
                    .font(.numeric(size: 13, weight: .semibold))
                    .foregroundStyle(Color.theme.fg2)
                Text(leg.isStranded ? "expired" : "\(leg.tradingDaysRemaining)d")
                    .font(.numeric(size: 10, weight: .medium))
                    .foregroundStyle(leg.isStranded ? Color.theme.warn : Color.theme.fg3)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(fmtMoney(leg.dailyBurn))
                    .font(.numeric(size: 13, weight: .bold))
                    .foregroundStyle(Color.theme.neon)
                Text("/ day")
                    .font(.ui(size: 9, weight: .semibold))
                    .foregroundStyle(Color.theme.fg3)
            }
            .frame(width: 70, alignment: .trailing)
        }
    }
}
