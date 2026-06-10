//
//  ZoneGauges.swift
//  Sunnyfi
//
//  Shared visualization primitives for the three standardized
//  drill-in popups (Hedge funding · Downside protection · Break-even).
//  Mirrors the IVR view's gauge family — same 5-segment heat ramp,
//  same marker treatment — but exposes left/right scale labels so
//  each sheet can phrase its own framing ("unfunded → fully funded",
//  "out of pocket → fully offset", "underwater → in profit").
//
//  Two components:
//
//   • ZoneGauge   — full-width 5-segment glance gauge with marker
//                   and uppercase left/right scale labels. Sits at
//                   the top of every "Patch" block.
//
//   • MiniTrack   — narrow horizontal track for per-position rows.
//                   Used by the Downside Protection and Break-even
//                   sheets to show "protected zone width" and
//                   "recovery progress" respectively.
//
//  Pixel specs are sourced from design_handoff_standardized_popups
//  /src/popups.css (.zg-* and .pl-track classes).
//

import SwiftUI

// MARK: - Zone segment color ramp

private enum ZoneColor {
    // Match the IVR view's segment colors so the visual family is
    // identical. left → right is "cold → hot" / "bad → good".
    static let z1 = Color(.sRGB, red: 36/255,  green: 56/255,  blue: 46/255,  opacity: 0.10)
    static let z2 = Color(.sRGB, red: 36/255,  green: 56/255,  blue: 46/255,  opacity: 0.13)
    static let z3 = Color(.sRGB, red: 36/255,  green: 56/255,  blue: 46/255,  opacity: 0.18)
    static let z4 = Color(.sRGB, red: 12/255,  green: 106/255, blue: 78/255,  opacity: 0.32)
    static let z5 = Color(.sRGB, red: 12/255,  green: 106/255, blue: 78/255,  opacity: 0.55)
}

// MARK: - ZoneGauge

/// 5 equal segments + a vertical marker showing the current value.
/// Scale labels below in uppercase mono for the visual rhythm the
/// design wants ("UNFUNDED ... FULLY FUNDED").
struct ZoneGauge: View {
    /// 0..100 — clamped on render.
    let value: Double
    let leftLabel: String
    let rightLabel: String

    private var clamped: Double { min(98, max(2, value)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    // 5 segments, 3pt gap, 9pt tall, 2pt radius per popups.css
                    HStack(spacing: 3) {
                        Rectangle().fill(ZoneColor.z1)
                        Rectangle().fill(ZoneColor.z2)
                        Rectangle().fill(ZoneColor.z3)
                        Rectangle().fill(ZoneColor.z4)
                        Rectangle().fill(ZoneColor.z5)
                    }
                    .frame(height: 9)
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                    // Marker — 3pt × 19pt, fg1, 2pt elevated outer ring
                    let mx = w * (clamped / 100)
                    Rectangle()
                        .fill(Color.theme.fg1)
                        .frame(width: 3, height: 19)
                        .overlay(
                            Rectangle().stroke(Color.theme.elevated, lineWidth: 2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .offset(x: mx - 1.5, y: -5)
                }
            }
            .frame(height: 14)

            // Scale labels — uppercase mono per popups.css
            HStack {
                Text(leftLabel.uppercased())
                    .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Color.theme.fg4)
                Spacer()
                Text(rightLabel.uppercased())
                    .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Color.theme.fg4)
            }
        }
    }
}

// MARK: - MiniTrack

/// Narrow horizontal track for per-position rows. Used by:
///   • Downside Protection — fill = protected zone width, mark = strike,
///     end = "now" price
///   • Break-even          — fill = recovery toward cost, mark = current,
///     end = cost basis
///
/// Spec from .pl-track in popups.css:
///   • 7pt height, 3pt radius, page2 background, margin-top 13pt
///   • Fill: tone-colored @ 50% opacity, radius 3 0 0 3 (rounded left)
///   • Mark: 3pt × 15pt, full tone color, radius 2, top offset -4pt
///   • End: 3pt × 15pt anchored right, fg1 bg with 2pt elevated ring
struct MiniTrack: View {
    /// 0..100. The colored fill stretches from the left to this %.
    let fillPct: Double
    /// 0..100. Vertical marker bar. Usually == fillPct but kept
    /// separate so callers can decouple if needed.
    let markPct: Double
    /// Drives fill + mark color.
    let tone: Tone

    enum Tone {
        case pos, neg
        var color: Color {
            switch self {
            case .pos: return .theme.pos
            case .neg: return .theme.neg
            }
        }
    }

    private var clampedFill: Double { min(100, max(0, fillPct)) }
    private var clampedMark: Double { min(100, max(0, markPct)) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                // Track background
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.theme.page2)
                    .frame(height: 7)
                // Fill — leading rounded only
                RoundedCorners(radius: 3, corners: [.topLeft, .bottomLeft])
                    .fill(tone.color.opacity(0.5))
                    .frame(width: w * (clampedFill / 100), height: 7)
                // Mark — vertical bar at fillPct
                Rectangle()
                    .fill(tone.color)
                    .frame(width: 3, height: 15)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .offset(x: w * (clampedMark / 100) - 1.5, y: -4)
                // End marker — fg1 with elevated outer ring, anchored right
                Rectangle()
                    .fill(Color.theme.fg1)
                    .frame(width: 3, height: 15)
                    .overlay(
                        Rectangle().stroke(Color.theme.elevated, lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .offset(x: w - 1.5, y: -4)
            }
        }
        .frame(height: 15)
    }
}

// MARK: - One-sided rounded rectangle

/// SwiftUI doesn't ship a stock "round only the leading edge" shape
/// at the iOS 26 level we target. This wraps Path + UIBezierPath so
/// the MiniTrack fill can have a left-rounded edge while staying flush
/// against the (possibly cut-off) right edge.
private struct RoundedCorners: Shape {
    let radius: CGFloat
    let corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
