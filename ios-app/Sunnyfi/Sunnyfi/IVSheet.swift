//
//  IVSheet.swift
//  Sunnyfi
//
//  Two-mode drill-down sheet:
//    • "list" mode  — portfolio-wide volatility scan, ranked by
//                     Seller Score, each row tappable + pinnable.
//    • "detail" mode — single-ticker IV detail with three blocks
//                     (Seller Score, IV Rank, IV vs HV).
//
//  Layout follows iv-components.jsx → IVSheet + TickerIVDetail and
//  the prototype's CSS in Homepage iOS - Today.html.
//

import SwiftUI

struct IVSheet: View {
    /// All summaries available (typically store.allIvSummaries).
    let summaries: [TickerIVRow]
    /// If non-nil, sheet opens directly on this ticker's detail.
    /// nil = open on the scan list.
    @State var initialTicker: String?
    @Bindable var pins: IVPinStore
    let onClose: () -> Void

    @State private var detailTicker: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let tk = detailTicker ?? initialTicker,
                   let row = summaries.first(where: { $0.ticker == tk }) {
                    TickerIVDetail(
                        row: row,
                        isPinned: pins.isPinned(tk),
                        onBack: { detailTicker = nil; initialTicker = nil },
                        onPin: { pins.toggle(tk) }
                    )
                } else {
                    IVScanList(
                        summaries: summaries,
                        pins: pins,
                        onClose: onClose,
                        onOpenTicker: { detailTicker = $0 }
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 45)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Scan list (default view)

private struct IVScanList: View {
    let summaries: [TickerIVRow]
    @Bindable var pins: IVPinStore
    let onClose: () -> Void
    let onOpenTicker: (String) -> Void

    private var ranked: [TickerIVRow] {
        summaries.sorted { lhs, rhs in
            let ls = IVMath.sellerScore(lhs) ?? -1
            let rs = IVMath.sellerScore(rhs) ?? -1
            return ls > rs
        }
    }

    private var sellZoneCount: Int {
        ranked.filter { (IVMath.sellerScore($0) ?? 0) >= 70 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Head: category + title + close
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("VOLATILITY")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(Color.theme.neon)
                    Text("Seller score")
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.78)
                        .foregroundStyle(Color.theme.fg1)
                }
                Spacer()
                Button(action: onClose) {
                    Text("✕")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.theme.fg3)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.theme.surface))
                        .overlay(Circle().stroke(Color.theme.borderBright, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            // Count line
            HStack {
                (Text("TOP NAMES · ").foregroundStyle(Color.theme.fg3) +
                 Text("\(sellZoneCount) of \(ranked.count) in the sell zone").foregroundStyle(Color.theme.neon))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2)
            }
            .padding(.top, 18)
            .padding(.bottom, 4)

            // Rows
            VStack(spacing: 0) {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { idx, row in
                    if idx > 0 {
                        Rectangle().fill(Color.theme.hair).frame(height: 1)
                    }
                    IVScanRow(
                        row: row,
                        isPinned: pins.isPinned(row.ticker),
                        onTap: { onOpenTicker(row.ticker) },
                        onPin: { pins.toggle(row.ticker) }
                    )
                }
            }
            .padding(.top, 10)
        }
    }
}

private struct IVScanRow: View {
    let row: TickerIVRow
    let isPinned: Bool
    let onTap: () -> Void
    let onPin: () -> Void

    private var score: Int? {
        guard let s = IVMath.sellerScore(row) else { return nil }
        return Int(s.rounded())
    }
    private var ivrInt: Int { Int((IVMath.ivr(row) ?? 0).rounded()) }
    private var spreadStr: String {
        guard let s = IVMath.spread(row) else { return "—" }
        let pts = Int((s * 100).rounded())
        return pts >= 0 ? "+\(pts)" : "−\(abs(pts))"
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTap) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(row.ticker)
                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.theme.fg1)
                            if let z = IVMath.scoreZone(row) {
                                let c = Color.ivChipColors(forScore: z)
                                IVVerdictChip(text: z.label, bg: c.bg, fg: c.fg)
                            }
                        }
                        HStack(spacing: 4) {
                            Text("IVR \(ivrInt)  ·  spread ")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.theme.fg3)
                            Text(spreadStr)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(toneColor(IVMath.spreadTone(row)))
                        }
                    }
                    Spacer()
                    if let s = score {
                        Text("\(s)")
                            .font(.system(size: 20, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(toneColor(IVMath.scoreTone(row)))
                    } else {
                        Text("—")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.theme.fg4)
                    }
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onPin) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isPinned ? Color.theme.neon : Color.theme.fg4)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Per-ticker detail (3 blocks)

private struct TickerIVDetail: View {
    let row: TickerIVRow
    let isPinned: Bool
    let onBack: () -> Void
    let onPin: () -> Void

    private var ivr: Int { Int((IVMath.ivr(row) ?? 0).rounded()) }
    private var score: Int { Int((IVMath.sellerScore(row) ?? 0).rounded()) }
    private var spreadPts: Int { Int(((IVMath.spread(row) ?? 0) * 100).rounded()) }
    private var spreadStr: String { spreadPts >= 0 ? "+\(spreadPts)" : "−\(abs(spreadPts))" }
    private var windowDays: Int { row.iv_window_days ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Back button
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("All names")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(0.3)
                }
                .foregroundStyle(Color.theme.neon)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)

            // Head: category + ticker + track button
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("VOLATILITY · \(windowDays)d window")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(Color.theme.neon)
                    Text(row.ticker)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.theme.fg1)
                }
                Spacer()
                Button(action: onPin) {
                    HStack(spacing: 6) {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 11, weight: .semibold))
                        Text(isPinned ? "Tracking" : "Track")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .tracking(0.4)
                    }
                    .foregroundStyle(isPinned ? .white : Color.theme.neon)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 38)
                    .background(
                        Capsule().fill(isPinned ? Color.theme.neon : Color.theme.tintNeon)
                    )
                    .overlay(
                        Capsule().stroke(Color.theme.neon.opacity(isPinned ? 1 : 0.32), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            // Block 1: Seller Score
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("SELLER SCORE")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(Color.theme.fg3)
                    Spacer()
                    if let z = IVMath.scoreZone(row) {
                        let c = Color.ivChipColors(forScore: z)
                        IVVerdictChip(text: z.label, bg: c.bg, fg: c.fg)
                    }
                }
                HStack(alignment: .lastTextBaseline, spacing: 9) {
                    Text("\(score)")
                        .font(.system(size: 46, weight: .semibold))
                        .monospacedDigit()
                        .tracking(-1.61)
                        .foregroundStyle(toneColor(IVMath.scoreTone(row)))
                    Text("/ 100")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.theme.fg3)
                }
                .padding(.top, 13)
                .padding(.bottom, 14)

                IVRGauge(value: Double(score), threshold: 70)
                    .padding(.bottom, 14)

                HStack(spacing: 4) {
                    Text("IVR \(ivr)  ·  spread ")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Color.theme.fg2)
                    Text(spreadStr)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(toneColor(IVMath.spreadTone(row)))
                }

                if let z = IVMath.scoreZone(row) {
                    Text(z.reading)
                        .font(.system(size: 12.5))
                        .lineSpacing(4)
                        .foregroundStyle(Color.theme.fg2)
                        .padding(.top, 14)
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 22)

            Rectangle().fill(Color.theme.hair).frame(height: 1)

            // Block 2: IV Rank
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("IV RANK")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(Color.theme.fg3)
                    Spacer()
                    if let z = IVMath.ivrZone(row) {
                        let c = Color.ivChipColors(forIVR: z)
                        IVVerdictChip(text: z.label, bg: c.bg, fg: c.fg)
                    }
                }
                HStack(alignment: .lastTextBaseline, spacing: 9) {
                    Text("\(ivr)")
                        .font(.system(size: 46, weight: .semibold))
                        .monospacedDigit()
                        .tracking(-1.61)
                        .foregroundStyle(toneColor(IVMath.ivrTone(row)))
                    Text("\(windowDays)d range")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.theme.fg3)
                }
                .padding(.top, 13)
                .padding(.bottom, 14)

                if let lo = row.iv_low, let hi = row.iv_high, let cur = row.current_iv {
                    RangeTrack(low: lo, high: hi, current: cur)
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 22)

            Rectangle().fill(Color.theme.hair).frame(height: 1)

            // Block 3: IV vs HV spread
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("IV VS HV SPREAD")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(Color.theme.fg3)
                    Spacer()
                    if let z = IVMath.spreadZone(row) {
                        let c = Color.ivChipColors(forSpread: z)
                        IVVerdictChip(text: z.label, bg: c.bg, fg: c.fg)
                    }
                }
                .padding(.bottom, 14)

                HStack(spacing: 10) {
                    IVStatCell(
                        value: "\(Int(((row.current_iv ?? 0) * 100).rounded()))%",
                        label: "Implied",
                        tone: .neutral
                    )
                    IVStatCell(
                        value: "\(Int(((row.current_hv30 ?? 0) * 100).rounded()))%",
                        label: "Realized",
                        tone: .neutral
                    )
                    IVStatCell(
                        value: spreadStr,
                        label: "Spread",
                        tone: IVMath.spreadTone(row)
                    )
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 22)
        }
    }
}

private struct IVStatCell: View {
    let value: String
    let label: String
    let tone: TodayTone

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .tracking(-0.44)
                .foregroundStyle(toneColor(tone))
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.theme.fg3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 13)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.theme.page2)
        )
    }
}

// MARK: - Local tone helper (mirror)

private func toneColor(_ t: TodayTone) -> Color {
    switch t {
    case .pos:     return .theme.pos
    case .neg:     return .theme.neg
    case .neon:    return .theme.neon
    case .warn:    return .theme.warn
    case .neutral: return .theme.fg1
    }
}
