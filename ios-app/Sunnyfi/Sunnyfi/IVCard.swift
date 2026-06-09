//
//  IVCard.swift
//  Sunnyfi
//
//  The in-list Volatility card. Lives inside the Today screen's
//  ranked list as one extra row, leading with the Seller Score for
//  the day's "best to sell calls" ticker.
//
//  Tapping opens the IV drill-down sheet. The pin glyph toggles
//  IVPinStore.
//
//  Layout follows iv-components.jsx → IVMergedRow + the prototype's
//  CSS (.iv-merged-row / .mrg-* / Homepage iOS - Today.html).
//

import SwiftUI

// MARK: - Verdict chip

/// Small uppercase action tag (SELL / CAUTION / NEUTRAL / etc.).
/// Color encodes the call — see Color.ivChipColors(forScore:).
struct IVVerdictChip: View {
    let text: String
    let bg: Color
    let fg: Color

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(bg))
            .fixedSize()
    }
}

// MARK: - IVMergedRow (the card in the Today list)

/// One row in the ranked list, rendered in the same editorial idiom
/// as the other Today rows (hairline top border, full-row tap, pin
/// glyph far right). Leads with the Seller Score.
struct IVMergedRow: View {
    let row: TickerIVRow
    let isPinned: Bool
    let onOpen: () -> Void
    let onPin: () -> Void

    private var score: Double? { IVMath.sellerScore(row) }
    private var ivr: Double? { IVMath.ivr(row) }
    private var spread: Double? { IVMath.spread(row) }
    private var zone: IVMath.ScoreZone? { IVMath.scoreZone(row) }
    private var tone: TodayTone { IVMath.scoreTone(row) }

    private var scoreInt: Int { Int((score ?? 0).rounded()) }
    private var ivrInt: Int { Int((ivr ?? 0).rounded()) }
    private var spreadStr: String {
        guard let s = spread else { return "—" }
        let pts = Int((s * 100).rounded())
        return pts >= 0 ? "+\(pts)" : "−\(abs(pts))"
    }
    private var ivPctStr: String {
        guard let v = row.current_iv else { return "—" }
        return "\(Int((v * 100).rounded()))%"
    }
    private var hvPctStr: String {
        guard let v = row.current_hv30 else { return "—" }
        return "\(Int((v * 100).rounded()))%"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 11) {
                    // Top row: category eyebrow + verdict chip
                    HStack {
                        Text("Volatility · \(row.ticker)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1.6)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.theme.fg3)
                        Spacer()
                        if let z = zone {
                            let c = Color.ivChipColors(forScore: z)
                            IVVerdictChip(text: z.label, bg: c.bg, fg: c.fg)
                        }
                    }

                    // Number line: big Seller Score + unit + driver
                    HStack(alignment: .lastTextBaseline, spacing: 9) {
                        Text("\(scoreInt)")
                            .font(.system(size: 36, weight: .semibold))
                            .monospacedDigit()
                            .tracking(-1.08)        // -.03em × 36
                            .foregroundStyle(toneColor(tone))
                            .lineLimit(1)
                        Text("seller score")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(0.8)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.theme.fg3)
                        Spacer()
                        // Drivers: IVR + spread (spread colored)
                        HStack(spacing: 4) {
                            Text("IVR \(ivrInt)  ·")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .tracking(0.2)
                                .foregroundStyle(Color.theme.fg2)
                            Text(spreadStr)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .tracking(0.2)
                                .foregroundStyle(toneColor(IVMath.spreadTone(row)))
                        }
                    }

                    // Compact zone gauge
                    MiniGauge(value: score ?? 0)

                    // Scale line: IV/HV + "sell zone ≥ 70"
                    HStack {
                        Text("IV \(ivPctStr) · HV \(hvPctStr)")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .tracking(0.4)
                            .foregroundStyle(Color.theme.fg4)
                        Spacer()
                        Text("sell zone ≥ 70")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .tracking(0.4)
                            .foregroundStyle(Color.theme.fg4)
                    }
                }
                .padding(.vertical, 18)
                .padding(.trailing, 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onPin) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isPinned ? Color.theme.neon : Color.theme.fg4)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .padding(.trailing, -4)
        }
    }
}

// MARK: - Local tone helper (mirrors TodayScreen's private toneColor)

private func toneColor(_ t: TodayTone) -> Color {
    switch t {
    case .pos:     return .theme.pos
    case .neg:     return .theme.neg
    case .neon:    return .theme.neon
    case .warn:    return .theme.warn
    case .neutral: return .theme.fg1
    }
}
