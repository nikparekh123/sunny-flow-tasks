//
//  WeeklyIncome.swift
//  Sunnyfi
//
//  "Premium this week" hero on Home — sums signed premium from open
//  short legs whose `trade_date` is in the current calendar week. Bars
//  on the right show last 7 days of premium activity.
//

import SwiftUI

struct WeeklyIncome {
    let thisWeek: Double
    let lastWeek: Double
    let legCount: Int
    let bars: [Double]  // 7 values, most recent last

    static func compute(from trades: [OptionTradeRow], now: Date = Date()) -> WeeklyIncome {
        let cal = Calendar(identifier: .gregorian)
        let weekStart = AppDates.startOfWeek(now)
        let lastWeekStart = cal.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart

        var thisWk = 0.0
        var lastWk = 0.0
        var legs = 0
        var perDay = [Double](repeating: 0, count: 7)
        let dayStart = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? now

        for t in trades where t.action == "open" {
            guard let d = AppDates.parseISODay(t.trade_date) else { continue }
            // Signed premium: short = credit, long = debit
            let signedPremium = t.premium * t.contracts * 100 * (t.direction == "short" ? 1 : -1)

            if d >= weekStart {
                thisWk += signedPremium
                legs += 1
            } else if d >= lastWeekStart && d < weekStart {
                lastWk += signedPremium
            }

            let dayDelta = cal.dateComponents([.day], from: dayStart, to: d).day ?? -1
            if (0...6).contains(dayDelta) {
                perDay[dayDelta] += abs(signedPremium)
            }
        }

        return WeeklyIncome(thisWeek: thisWk, lastWeek: lastWk, legCount: legs, bars: perDay)
    }
}

struct WeeklyIncomeStrip: View {
    let income: WeeklyIncome

    private var maxBar: Double { max(income.bars.max() ?? 1, 1) }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PREMIUM THIS WEEK")
                    .font(.microLabel)
                    .tracking(1.4)
                    .foregroundStyle(Color.theme.fg3)
                Text(fmtMoney(income.thisWeek, sign: true))
                    .font(.numeric(size: 22, weight: .medium))
                    .tracking(-0.6)
                    .foregroundStyle(Color.theme.pos)
                let diff = income.thisWeek - income.lastWeek
                Text("\(income.legCount) leg\(income.legCount == 1 ? "" : "s") · \(diff >= 0 ? "+" : "−")\(fmtMoney(abs(diff))) vs last week")
                    .font(.ui(size: 11))
                    .foregroundStyle(Color.theme.fg3)
            }

            Spacer()

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(income.bars.enumerated()), id: \.offset) { i, v in
                    let h = max(4, (v / maxBar) * 46)
                    Capsule()
                        .fill(i == income.bars.count - 1 ? Color.theme.neon : Color.theme.pos.opacity(0.35))
                        .frame(width: 8, height: h)
                }
            }
            .frame(height: 46)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(Color.theme.tintNeon)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl)
                        .strokeBorder(Color.theme.neon.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
