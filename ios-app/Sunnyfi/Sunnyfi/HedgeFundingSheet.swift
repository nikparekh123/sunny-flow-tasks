//
//  HedgeFundingSheet.swift
//  Sunnyfi
//
//  Bottom-sheet drill-in opened from the "Funds hedge" row on the
//  Open call credit card. Explains the cross-book funding picture:
//  how much of the protective-put bill the call-credit book pays
//  for, broken down by leg.
//
//  Layout follows design_handoff_hedge_rows / b-sheets.jsx →
//  HedgeFundingSheet. Two states:
//
//   • Under-funded (call credit < put paid):
//       big "73%" + sub "$11,990 of $16,450 / $4,460 to go"
//       meter fills to fundedPct%
//   • Over-funded (call credit ≥ put paid):
//       big "+$X" in positive tone + sub "fully funded · surplus"
//       meter fills to 100%
//
//  Lists below the total box:
//   • HEDGE COST · PUTS BOUGHT — one row per long-put leg
//   • FUNDED BY · CALL CREDIT — one row per ticker with calls sold
//

import SwiftUI

struct HedgeFundingSheet: View {
    let callCredit: Double
    let putPaid: Double
    let fundedPct: Int
    let hedgeSurplus: Double
    let netCost: Double
    let putRows: [TradesData.HedgePutRow]
    let creditRows: [TradesData.HedgeCreditRow]
    let onClose: () -> Void

    private var fullyFunded: Bool { hedgeSurplus >= 0 }
    private var meterFill: Double { fullyFunded ? 1.0 : Double(fundedPct) / 100.0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                head
                    .padding(.top, 8)
                    .padding(.bottom, 18)

                totalBox
                    .padding(.bottom, 11)

                meter
                    .padding(.bottom, 22)

                putsGroup
                    .padding(.bottom, 22)

                creditGroup

                Spacer(minLength: 18)
                Button("Done", action: onClose)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(Color.theme.neon)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        Capsule()
                            .strokeBorder(Color.theme.borderBright, lineWidth: 1)
                    )
                    .padding(.top, 8)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(Color.theme.elevated.ignoresSafeArea())
    }

    // MARK: - Sections

    private var head: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("HEDGE FUNDING")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(Color.theme.neon)
            Text("Call credit → puts")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.78)
                .foregroundStyle(Color.theme.fg1)
                .lineLimit(2)
            Text(subCopy)
                .font(.system(size: 12.5))
                .lineSpacing(4)
                .foregroundStyle(Color.theme.fg3)
                .padding(.top, 4)
        }
    }

    private var subCopy: String {
        let intro = "Premium collected on your open short calls offsets what you paid for protective puts."
        if fullyFunded {
            return intro + " Call income covers the entire hedge."
        }
        return intro + " \(fundedPct)% of the hedge is funded by call income — the rest is out of pocket."
    }

    private var totalBox: some View {
        HStack(alignment: .center) {
            // Big value: % (under-funded) or +$surplus (over-funded)
            if fullyFunded {
                Text(signedMoney(hedgeSurplus))
                    .font(.system(size: 28, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.theme.pos)
                    .tracking(-0.84)
            } else {
                Text("\(fundedPct)%")
                    .font(.system(size: 28, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.theme.fg1)
                    .tracking(-0.84)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(plainMoney(callCredit)) of \(plainMoney(putPaid))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.theme.fg3)
                Text(fullyFunded ? "fully funded · surplus" : "\(plainMoney(netCost)) to go")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.theme.fg3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.theme.page2)
        )
    }

    private var meter: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.theme.page2)
                    .frame(height: 8)
                Capsule()
                    .fill(Color.theme.neon)
                    .frame(width: geo.size.width * meterFill, height: 8)
                    .animation(.easeOut(duration: 0.45), value: meterFill)
            }
        }
        .frame(height: 8)
    }

    private var putsGroup: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("HEDGE COST · PUTS BOUGHT")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Color.theme.fg3)
            VStack(spacing: 0) {
                ForEach(Array(putRows.enumerated()), id: \.element.id) { idx, r in
                    if idx > 0 {
                        Rectangle().fill(Color.theme.hair).frame(height: 1)
                    }
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.ticker)
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.theme.fg1)
                            Text("\(Int(r.contracts)) ct · $\(strikeFmt(r.strike)) put · exp \(shortDate(r.expiry))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.theme.fg3)
                        }
                        Spacer()
                        Text("\u{2212}\(plainMoney(r.paid))")
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.theme.neg)
                    }
                    .padding(.vertical, 13)
                }
            }
        }
    }

    private var creditGroup: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("FUNDED BY · CALL CREDIT")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Color.theme.fg3)
            VStack(spacing: 0) {
                ForEach(Array(creditRows.enumerated()), id: \.element.id) { idx, r in
                    if idx > 0 {
                        Rectangle().fill(Color.theme.hair).frame(height: 1)
                    }
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.ticker)
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.theme.fg1)
                            Text("\(Int(r.contracts)) ct sold · collected")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.theme.fg3)
                        }
                        Spacer()
                        Text("+\(plainMoney(r.collected))")
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.theme.pos)
                    }
                    .padding(.vertical, 13)
                }
            }
        }
    }

    // MARK: - Format helpers

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

    /// Compact expiry like "Jul 18". Falls back to the raw string
    /// if the input isn't yyyy-MM-dd.
    private func shortDate(_ ymd: String) -> String {
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"
        inFmt.timeZone = TimeZone(identifier: "America/New_York")
        guard let d = inFmt.date(from: ymd) else { return ymd }
        let outFmt = DateFormatter()
        outFmt.dateFormat = "MMM d"
        outFmt.timeZone = TimeZone(identifier: "America/New_York")
        return outFmt.string(from: d)
    }
}
