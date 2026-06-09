//
//  PnLProgressBar.swift
//  Sunnyfi
//
//  Center-pivot P&L bar. The hero of the position card.
//
//  Layout:
//
//     $0  ── max profit ──  entry $4.20  ── max loss ──  $8.40
//     │··················●···························│
//                      mark
//
//  • Centre of the track = entry premium (per contract). $0 P&L.
//  • Left edge = mark hit $0 (option worthless).
//  • Right edge = mark hit 2× entry (symmetric mirror).
//  • Dot = current mark on that scale.
//
//  Color rules (so the "good" side glows green for the trader regardless
//  of whether the leg is short or long):
//
//                   left half        right half
//      Short        🟢 profit         🔴 loss
//      Long         🔴 loss           🟢 profit
//
//  Used by PositionCardView. Also reusable for the shares progress bar
//  inside the "If assigned" tall card (Phase 2).
//

import SwiftUI

struct PnLProgressBar: View {
    /// Per-contract entry premium (positive). For shares this is avg cost.
    let entryValue: Double
    /// Per-contract current mark (positive). For shares this is current spot.
    let currentValue: Double
    /// True for short legs (sold) or short share positions. Determines
    /// which side of the bar reads as "profit territory".
    let isShort: Bool

    // MARK: - Styling knobs

    var trackHeight: CGFloat = 10
    var dotSize: CGFloat = 18
    /// Toggle the edge labels + capture caption off when embedding the
    /// bar inside a denser layout (e.g. the assignment insight card).
    var showLabels: Bool = true

    // MARK: - Geometry

    /// Position of the dot on [0, 1] across the track width.
    /// 0 = left edge (mark hit $0), 0.5 = centre (mark = entry), 1 = right edge.
    private var dotPosition: Double {
        guard entryValue > 0 else { return 0.5 }
        // Symmetric scale: [0, 2× entry]
        let raw = currentValue / (entryValue * 2)
        return min(1, max(0, raw))
    }

    /// Live signed P&L per contract (positive = profit). For shorts
    /// profit = entry − mark; for longs profit = mark − entry.
    private var pnlPerContract: Double {
        let raw = currentValue - entryValue
        return isShort ? -raw : raw
    }

    private var pctOfMax: Double {
        guard entryValue > 0 else { return 0 }
        return pnlPerContract / entryValue   // [-1, +1]-ish (capped visually)
    }

    private var isProfit: Bool { pnlPerContract >= 0 }

    private var leftHalfColor: Color  { isShort ? .theme.pos : .theme.neg }
    private var rightHalfColor: Color { isShort ? .theme.neg : .theme.pos }
    private var dotColor: Color       { isProfit ? .theme.pos : .theme.neg }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showLabels { edgeLabels }
            bar
            if showLabels { captureCaption }
        }
    }

    // MARK: - Edge labels

    private var edgeLabels: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("MAX " + (isShort ? "PROFIT" : "LOSS"))
                .font(.ui(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(leftHalfColor.opacity(0.85))
            Spacer()
            Text("ENTRY $\(fmt(entryValue))")
                .font(.numeric(size: 10, weight: .semibold))
                .foregroundStyle(Color.theme.fg2)
            Spacer()
            Text("MAX " + (isShort ? "LOSS" : "PROFIT"))
                .font(.ui(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(rightHalfColor.opacity(0.85))
        }
    }

    // MARK: - Bar + dot

    private var bar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let centerX = w / 2
            let dotX = CGFloat(dotPosition) * w
            ZStack {
                // Track: two halves, each fading away from the centre
                // so the "good" side glows softly toward the edge.
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [leftHalfColor.opacity(0.55),
                                 leftHalfColor.opacity(0.15)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    LinearGradient(
                        colors: [rightHalfColor.opacity(0.15),
                                 rightHalfColor.opacity(0.55)],
                        startPoint: .leading, endPoint: .trailing
                    )
                }
                .frame(height: trackHeight)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )

                // Centre notch — small tall mark sitting just under the dot row
                Rectangle()
                    .fill(Color.theme.fg2.opacity(0.5))
                    .frame(width: 2, height: trackHeight + 8)
                    .position(x: centerX, y: trackHeight / 2)

                // Dot — neon-rimmed, color-coded by current P&L side
                ZStack {
                    Circle().fill(Color.theme.page)
                        .frame(width: dotSize + 4, height: dotSize + 4)
                    Circle().fill(dotColor)
                        .frame(width: dotSize, height: dotSize)
                        .overlay(Circle().strokeBorder(Color.theme.fg1.opacity(0.45), lineWidth: 1))
                        .shadow(color: dotColor.opacity(0.6), radius: 4)
                }
                .position(x: dotX, y: trackHeight / 2)
                .animation(.spring(response: 0.55, dampingFraction: 0.78), value: dotPosition)
            }
        }
        .frame(height: dotSize + 6)
    }

    // MARK: - Caption

    private var captureCaption: some View {
        let pctSign = pctOfMax > 0 ? "+" : pctOfMax < 0 ? "−" : ""
        let pctVal = abs(pctOfMax * 100).rounded()
        let markText = "mark $\(fmt(currentValue))"
        let summary = "\(pctSign)\(Int(pctVal))%"
        return HStack {
            Text(markText)
                .font(.numeric(size: 11, weight: .semibold))
                .foregroundStyle(Color.theme.fg2)
            Spacer()
            Text(summary)
                .font(.numeric(size: 11, weight: .semibold))
                .foregroundStyle(isProfit ? Color.theme.pos : Color.theme.neg)
        }
    }

    private func fmt(_ v: Double) -> String {
        // Per-contract values are small (single-digit dollars usually).
        // Use 2 decimals if entry is a price.
        String(format: v >= 100 ? "%.0f" : "%.2f", v)
    }
}
