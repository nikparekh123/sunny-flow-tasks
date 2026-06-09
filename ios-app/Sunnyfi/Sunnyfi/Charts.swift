//
//  Charts.swift
//  Sunnyfi
//
//  Reusable Swift Charts views. Three charts ship in Phase 4b:
//   - PriceLineChart: thin neon line over a dashed baseline (Home hero
//     + Company header)
//   - DeltaBarChart: diverging bars (Company → Net Δ block)
//
//  Visuals match the design's hand-rolled SVG — same dashed baseline,
//  neon stroke, end-dot, plus a smooth draw-on animation by relying on
//  Swift Charts' built-in `.animation` on the data.
//

import SwiftUI
import Charts

// MARK: - Price / value line

struct PriceLineChart: View {
    let points: [SeriesPoint]
    let isNegative: Bool
    var height: CGFloat = 132

    private var stroke: Color { isNegative ? .theme.neg : .theme.neon }
    private var baselineY: Double { points.first?.y ?? 0.5 }
    private var lastPoint: SeriesPoint? { points.last }

    var body: some View {
        Chart {
            // Dashed baseline at the starting value — matches the design
            // (gives the eye a reference for above-water / below-water).
            RuleMark(y: .value("Base", baselineY))
                .foregroundStyle(Color.theme.fg5.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))

            ForEach(points) { p in
                LineMark(
                    x: .value("t", p.x),
                    y: .value("v", p.y)
                )
                .foregroundStyle(stroke)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }

            // End-dot — small filled circle at the latest point.
            if let last = lastPoint {
                PointMark(
                    x: .value("t", last.x),
                    y: .value("v", last.y)
                )
                .foregroundStyle(stroke)
                .symbolSize(40)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...1)
        .chartYScale(domain: 0.08...0.92)   // a touch of headroom above/below
        .frame(height: height)
        // No animation on data change — until we have real historical data,
        // morphing between seeded shapes looks weird. Snap-in instead.
    }
}

// MARK: - Net Δ / Γ diverging bars

/// Hand-rolled diverging bar chart. Each column is a VStack: a
/// top-half region (positive bars grow upward, anchored at the BOTTOM
/// of the region — i.e. touching the zero line) + the zero rule +
/// bottom-half region (negative bars grow downward, anchored at the
/// TOP of the region — also touching the zero line).
///
/// Optional `selection` binding makes bars tappable. When something is
/// selected the other bars dim; the tapped bar keeps its full color and
/// gains a neon outline so it pops unambiguously.
struct DeltaBarChart: View {
    let bars: [BarPoint]
    var height: CGFloat = 84
    /// nil = nothing selected. Tap a bar to set its index; tap it again to clear.
    var selection: Binding<Int?>? = nil

    private var maxAbs: Double {
        max(bars.map { abs($0.value) }.max() ?? 1, 1)
    }

    private var hasSelection: Bool { selection?.wrappedValue != nil }
    private func isSelected(_ i: Int) -> Bool { selection?.wrappedValue == i }
    private func toggleSelect(_ i: Int) {
        guard let sel = selection else { return }
        sel.wrappedValue = sel.wrappedValue == i ? nil : i
    }

    /// Any bar with a label triggers the bottom axis row.
    private var hasLabels: Bool { bars.contains(where: { $0.label != nil }) }
    private var labelStripHeight: CGFloat { hasLabels ? 16 : 0 }

    /// Show at most ~5 labels evenly distributed. With 20 daily bars
    /// every label crowds; with 12 monthly bars they roughly all fit.
    /// Returns a set of bar-array INDICES (positional, not BarPoint.x)
    /// at which to render the date string. Other slots stay blank so
    /// the visible labels still align to their bars.
    private var visibleLabelIndices: Set<Int> {
        guard hasLabels, !bars.isEmpty else { return [] }
        // Cap at 5 labels — one per ~70pt at iPhone width is the
        // legibility ceiling for 10pt Work Sans.
        let target = min(5, bars.count)
        if target <= 1 { return [0] }
        let stride = Double(bars.count - 1) / Double(target - 1)
        var picks: Set<Int> = []
        for i in 0..<target {
            picks.insert(Int((Double(i) * stride).rounded()))
        }
        return picks
    }

    var body: some View {
        let barArea = height - labelStripHeight
        let half = (barArea - 5) / 2
        let visible = visibleLabelIndices

        VStack(spacing: 4) {
            HStack(spacing: 3) {                      // tight, original feel
                ForEach(bars) { b in
                    BarColumn(
                        bar: b,
                        half: half,
                        maxAbs: maxAbs,
                        selected: isSelected(b.x),
                        dimmed: hasSelection && !isSelected(b.x),
                        onTap: { if b.value != 0 { toggleSelect(b.x) } }
                    )
                }
            }
            .frame(height: half * 2 + 1, alignment: .center)
            .overlay(
                Rectangle()
                    .fill(Color.theme.fg5.opacity(0.7))
                    .frame(height: 1)
            )

            if hasLabels {
                HStack(spacing: 3) {
                    ForEach(Array(bars.enumerated()), id: \.element.id) { idx, b in
                        Text(visible.contains(idx) ? (b.label ?? "") : "")
                            .font(.ui(size: 10, weight: .semibold))
                            .foregroundStyle(Color.theme.fg3)
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .frame(height: 12)
            }
        }
        .frame(height: height)
    }
}

private struct BarColumn: View {
    let bar: BarPoint
    let half: CGFloat
    let maxAbs: Double
    let selected: Bool
    let dimmed: Bool
    let onTap: () -> Void

    var body: some View {
        let v = bar.value
        let isUp = v > 0
        let isDown = v < 0
        let baseColor = isUp ? Color.theme.pos : isDown ? Color.theme.neg : Color.clear
        let fill: Color = selected ? baseColor : (dimmed ? baseColor.opacity(0.32) : baseColor)
        let h: CGFloat = (v == 0)
            ? 0
            : max(2, CGFloat(abs(v) / maxAbs) * half)

        VStack(spacing: 0) {
            // Top half — bar anchored to the BOTTOM so it touches the zero line.
            ZStack(alignment: .bottom) {
                Color.clear
                if isUp {
                    barRect(fill: fill, height: h)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: half)

            // Bottom half — bar anchored to the TOP so it touches the zero line.
            ZStack(alignment: .top) {
                Color.clear
                if isDown {
                    barRect(fill: fill, height: h)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: half)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    @ViewBuilder
    private func barRect(fill: Color, height: CGFloat) -> some View {
        // Original boxy bar — slightly rounded corners only. Capsules
        // looked too pill-y for the dense Performance bar count.
        RoundedRectangle(cornerRadius: 2)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(selected ? Color.theme.neon : Color.clear, lineWidth: 1.5)
            )
            .frame(height: height)
    }
}
