//
//  IVGauges.swift
//  Sunnyfi
//
//  Three primitive visualizations used by the IV section:
//    • IVRGauge   — 5-segment zone bar 0–100 with marker + value label
//                   (used on the per-ticker detail's Seller Score block)
//    • MiniGauge  — compact 5-segment bar without label, for the
//                   in-list IVMergedRow
//    • RangeTrack — 52-week IV low/high track with current marker
//                   (used on the IV Rank block in the detail view)
//
//  All sizes / colors mirror the React prototype in
//  design_handoff_iv_volatility/iv-components.jsx + Homepage iOS - Today.html.
//

import SwiftUI

// MARK: - Zone color ramp (cheap → rich heat)
//
// Match the design's gauge segment colors exactly. Tuned for the
// warm-paper canvas (#f2eee5). The five segments left-to-right are:
// hold / light / neutral / sell / caution.

private enum GaugeColor {
    // Full-saturation segments for the detail view (IVRGauge)
    static let hold     = Color(.sRGB, red: 36/255,  green: 56/255,  blue: 46/255,  opacity: 0.10)
    static let light    = Color(.sRGB, red: 36/255,  green: 56/255,  blue: 46/255,  opacity: 0.13)
    static let neutral  = Color(.sRGB, red: 36/255,  green: 56/255,  blue: 46/255,  opacity: 0.18)
    static let sell     = Color(.sRGB, red: 12/255,  green: 106/255, blue: 78/255,  opacity: 0.32)
    static let caution  = Color(.sRGB, red: 132/255, green: 97/255,  blue: 20/255,  opacity: 0.34)
}

// MARK: - IVRGauge (detail view)

/// Five equal segments + a vertical marker showing the current value.
/// Optional dashed threshold tick (used for the "sell ≥ 70" marker).
struct IVRGauge: View {
    /// 0–100 — clamped on render.
    let value: Double
    /// Optional 0–100 — renders a dashed vertical tick (e.g. 70 for
    /// the Seller Score threshold).
    let threshold: Double?
    /// When true, shows the small value label floating above the
    /// marker. Default true (matches the detail-view spec).
    var showValueLabel: Bool = true

    private var clamped: Double { min(100, max(0, value)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    // 5 segments, 2pt gap, 9pt tall, 2pt radius
                    HStack(spacing: 2) {
                        Rectangle().fill(GaugeColor.hold)
                        Rectangle().fill(GaugeColor.light)
                        Rectangle().fill(GaugeColor.neutral)
                        Rectangle().fill(GaugeColor.sell)
                        Rectangle().fill(GaugeColor.caution)
                    }
                    .frame(height: 9)
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                    // Optional dashed threshold tick — 2pt wide × 15pt tall
                    if let t = threshold {
                        let x = w * (t / 100)
                        DashedTick()
                            .frame(width: 2, height: 15)
                            .offset(x: x - 1, y: -3)
                    }

                    // Marker — 3pt × 19pt with 2pt elevated stroke ring
                    let mx = w * (clamped / 100)
                    Rectangle()
                        .fill(Color.theme.fg1)
                        .frame(width: 3, height: 19)
                        .overlay(
                            Rectangle()
                                .stroke(Color.theme.elevated, lineWidth: 2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .offset(x: mx - 1.5, y: -5)
                        .overlay(alignment: .top) {
                            if showValueLabel {
                                Text("\(Int(clamped.rounded()))")
                                    .font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.theme.fg1)
                                    .fixedSize()
                                    .offset(x: mx - 1.5, y: -25)
                            }
                        }
                }
            }
            .frame(height: showValueLabel ? 24 : 14)

            // Scale ticks below
            HStack {
                ForEach([0, 20, 40, 60, 80, 100], id: \.self) { v in
                    Text("\(v)")
                        .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Color.theme.fg4)
                    if v != 100 { Spacer() }
                }
            }
        }
    }
}

private struct DashedTick: View {
    var body: some View {
        // 2pt-on, 2pt-off vertical dashed pattern via repeated bars.
        VStack(spacing: 2) {
            ForEach(0..<3) { _ in
                Rectangle()
                    .fill(Color.theme.fg4.opacity(0.8))
                    .frame(height: 3)
            }
        }
    }
}

// MARK: - MiniGauge (in-list IVMergedRow)

/// Compact 5-segment bar without label. 7pt tall, 2pt gap. Same
/// color ramp as IVRGauge.
struct MiniGauge: View {
    /// 0–100 — clamped on render.
    let value: Double
    private var clamped: Double { min(100, max(0, value)) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                HStack(spacing: 2) {
                    Rectangle().fill(GaugeColor.hold.opacity(0.8))
                    Rectangle().fill(GaugeColor.light.opacity(0.8))
                    Rectangle().fill(GaugeColor.neutral.opacity(0.8))
                    Rectangle().fill(GaugeColor.sell.opacity(0.8))
                    Rectangle().fill(GaugeColor.caution.opacity(0.8))
                }
                .frame(height: 7)
                .clipShape(RoundedRectangle(cornerRadius: 2))

                let mx = w * (clamped / 100)
                Rectangle()
                    .fill(Color.theme.fg1)
                    .frame(width: 3, height: 13)
                    .overlay(
                        Rectangle()
                            .stroke(Color.theme.page, lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .offset(x: mx - 1.5, y: -3)
            }
        }
        .frame(height: 13)
    }
}

// MARK: - RangeTrack (52w IV low/high)

/// Used on the IV Rank block in the detail view. Shows the lo→hi
/// span with a fill from lo to current, then a marker at current.
struct RangeTrack: View {
    /// All three are in decimal IV (0.42 = 42%).
    let low: Double
    let high: Double
    let current: Double

    private var pct: Double {
        guard high > low else { return 0 }
        return min(100, max(0, (current - low) / (high - low) * 100))
    }

    private func pctStr(_ d: Double) -> String { "\(Int((d * 100).rounded()))%" }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.theme.page2)
                        .frame(height: 6)
                    // Fill lo → current
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.theme.tintNeon)
                        .frame(width: w * (pct / 100), height: 6)
                    // Marker
                    Rectangle()
                        .fill(Color.theme.neon)
                        .frame(width: 3, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .offset(x: w * (pct / 100) - 1.5, y: -4)
                }
            }
            .frame(height: 14)

            // Scale: lo · now · hi
            HStack {
                Text("\(pctStr(low)) low")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(Color.theme.fg4)
                Spacer()
                Text("\(pctStr(current)) now")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(Color.theme.neon)
                Spacer()
                Text("\(pctStr(high)) high")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(Color.theme.fg4)
            }
        }
    }
}
