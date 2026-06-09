//
//  IVTracker.swift
//  Sunnyfi
//
//  Top "Tracking IV" chip rail — sits above the Headline, below the
//  regular Pinned cards rail. Horizontal-scrolling chips of tickers
//  the user has pinned for IV tracking (separate from the regular
//  pin set — see IVPinStore).
//
//  Layout follows iv-components.jsx → IVTracker + the prototype's
//  CSS (.iv-trkzone / .iv-trkchip).
//

import SwiftUI

struct IVTrackerRail: View {
    /// Pinned tickers, in user's pin order.
    let tickers: [String]
    /// Look up summary by ticker — empty rows render with "—".
    let summary: [String: TickerIVRow]
    /// Tap a chip → open the per-ticker detail sheet for that ticker.
    let onOpenTicker: (String) -> Void

    var body: some View {
        if tickers.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 9) {
                // Mini-label: outline pin + "TRACKING IV · N"
                HStack(spacing: 7) {
                    Image(systemName: "pin")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.theme.fg3)
                    Text("TRACKING IV · \(tickers.count)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.theme.fg3)
                }
                .padding(.horizontal, 22)

                // Horizontal chip rail
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tickers, id: \.self) { tk in
                            IVTrackerChip(
                                ticker: tk,
                                row: summary[tk],
                                onTap: { onOpenTicker(tk) }
                            )
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 4)
                }
            }
        }
    }
}

private struct IVTrackerChip: View {
    let ticker: String
    let row: TickerIVRow?
    let onTap: () -> Void

    private var score: Int? {
        guard let r = row, let s = IVMath.sellerScore(r) else { return nil }
        return Int(s.rounded())
    }
    private var tone: TodayTone {
        guard let r = row else { return .neutral }
        return IVMath.scoreTone(r)
    }
    private var dotColor: Color {
        guard let r = row, let z = IVMath.scoreZone(r) else { return Color.theme.dusk }
        switch z {
        case .sell:    return Color.theme.neon
        case .caution: return Color.theme.ivAmber
        default:       return Color.theme.dusk
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 9) {
                Text(ticker)
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .tracking(-0.13)
                    .foregroundStyle(Color.theme.fg2)
                if let s = score {
                    Text("\(s)")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .tracking(-0.28)
                        .foregroundStyle(scoreColor(tone))
                } else {
                    Text("—")
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.theme.fg4)
                }
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .frame(minHeight: 34)
            .background(
                Capsule().fill(Color.theme.surface)
            )
            .overlay(
                Capsule().stroke(Color.theme.borderBright, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private func scoreColor(_ t: TodayTone) -> Color {
    switch t {
    case .pos:     return .theme.pos
    case .neg:     return .theme.neg
    case .neon:    return .theme.neon
    case .warn:    return .theme.warn
    case .neutral: return .theme.fg1
    }
}
