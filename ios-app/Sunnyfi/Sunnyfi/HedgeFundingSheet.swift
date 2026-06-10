//
//  HedgeFundingSheet.swift
//  Sunnyfi
//
//  Drill-in opened from the "Funds hedge" row on Open call credit.
//  Standardized popup shape from design_handoff_standardized_popups:
//
//    HEAD-TAG · big title · subcopy
//    Patch block:
//       mini-label + status tag
//       hero value
//       ZoneGauge (UNFUNDED → FULLY FUNDED)
//       3 stats (Call income / Hedge cost / Puts P/L)
//    By-position groups (calls collected · puts bought)
//    Done capsule
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
    /// Mark-to-market on the open put book (putValue − putPaid). Drives
    /// the third stat tile. Defaults to 0 so older callers don't break.
    var putGain: Double = 0
    let onClose: () -> Void

    private var fullyFunded: Bool { hedgeSurplus >= 0 }
    /// Gauge value: clamp fundedPct, push to 100 when surplus.
    private var gaugeValue: Double {
        fullyFunded ? 100 : Double(fundedPct)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SheetHead(
                    tag: "HEDGE FUNDING",
                    title: "Call credit → puts",
                    subcopy: subCopy
                )
                .padding(.top, 8)
                .padding(.bottom, 18)

                patch
                    .padding(.bottom, 22)

                putsGroup
                    .padding(.bottom, 22)

                creditGroup

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
        let intro = "Premium collected on open short calls offsets the cost of protective puts."
        if fullyFunded {
            return intro + " Call income covers the entire hedge."
        }
        return intro + " \(fundedPct)% of the hedge is funded by call income — the rest is out of pocket."
    }

    // MARK: - Patch

    private var patch: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("FUNDING STATUS")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.theme.fg3)
                Spacer()
                PatchTag(
                    text: fullyFunded ? "fully funded" : "\(fundedPct)% funded",
                    tone: fullyFunded ? .pos : .neutral
                )
            }
            // Hero — under-funded: "% of put bill"; over-funded: "+$surplus"
            if fullyFunded {
                Text(signedMoney(hedgeSurplus))
                    .font(.system(size: 30, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-0.9)
                    .foregroundStyle(Color.theme.pos)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(plainMoney(callCredit))
                        .font(.system(size: 30, weight: .semibold))
                        .monospacedDigit()
                        .tracking(-0.9)
                        .foregroundStyle(Color.theme.fg1)
                    Text("of \(plainMoney(putPaid))")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.theme.fg3)
                }
            }
            ZoneGauge(value: gaugeValue,
                      leftLabel: "Unfunded",
                      rightLabel: "Fully funded")
                .padding(.top, 2)
            PatchStatsRow(stats: [
                .init(label: "Call income", value: plainMoney(callCredit), tone: .pos),
                .init(label: "Hedge cost",  value: "\u{2212}" + plainMoney(putPaid), tone: .neg),
                .init(label: "Puts P/L",    value: signedMoney(putGain),
                      tone: putGain >= 0 ? .pos : .neg),
            ])
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.theme.page2)
        )
    }

    // MARK: - By-position groups

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

    // MARK: - Format helpers (file-local — duplicated from sibling sheets
    //          on purpose: keeps each popup self-contained)

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

// MARK: - Shared sheet primitives

/// HEAD-TAG + big title + subcopy. Used at the top of every
/// standardized popup. Title carries the design's -0.9pt tracking.
struct SheetHead: View {
    let tag: String
    let title: String
    let subcopy: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(tag)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(Color.theme.neon)
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.78)
                .foregroundStyle(Color.theme.fg1)
                .lineLimit(2)
            Text(subcopy)
                .font(.system(size: 12.5))
                .lineSpacing(4)
                .foregroundStyle(Color.theme.fg3)
                .padding(.top, 4)
        }
    }
}

/// Neon-outlined Done capsule. Lives in every sheet's footer.
struct SheetDoneButton: View {
    let onTap: () -> Void
    var body: some View {
        Button("Done", action: onTap)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .tracking(0.4)
            .foregroundStyle(Color.theme.neon)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                Capsule()
                    .strokeBorder(Color.theme.borderBright, lineWidth: 1)
            )
    }
}

/// Small pill tag rendered to the right of the patch mini-label.
/// Tone drives color treatment.
struct PatchTag: View {
    enum Tone { case pos, neg, neutral }
    let text: String
    let tone: Tone

    private var fg: Color {
        switch tone {
        case .pos: return Color.theme.pos
        case .neg: return Color.theme.neg
        case .neutral: return Color.theme.fg2
        }
    }
    private var bg: Color {
        switch tone {
        case .pos: return Color.theme.pos.opacity(0.14)
        case .neg: return Color.theme.neg.opacity(0.14)
        case .neutral: return Color.theme.page
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.4)
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(bg))
    }
}

/// 3 evenly-divided stat tiles below the gauge. Tone colors each value.
struct PatchStatsRow: View {
    struct Stat: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let tone: Tone
        enum Tone { case pos, neg, neutral }
    }
    let stats: [Stat]

    private func color(for t: Stat.Tone) -> Color {
        switch t {
        case .pos: return Color.theme.pos
        case .neg: return Color.theme.neg
        case .neutral: return Color.theme.fg1
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { idx, s in
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.label.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(Color.theme.fg3)
                    Text(s.value)
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(color(for: s.tone))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if idx < stats.count - 1 {
                    Rectangle()
                        .fill(Color.theme.hair)
                        .frame(width: 1, height: 28)
                        .padding(.horizontal, 8)
                }
            }
        }
    }
}
