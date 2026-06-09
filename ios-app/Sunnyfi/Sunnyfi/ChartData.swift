//
//  ChartData.swift
//  Sunnyfi
//
//  Seeded chart series for the price/value line charts and the Net Δ
//  bar chart. Ports the `chartPoints` / `barSeries` generators from
//  `reference/app-frame.jsx`. Used until we wire real historical data —
//  every series is deterministic (same input → same shape).
//
//  In Phase 4d-ish we'll back the series with a `portfolio_snapshots`
//  table (15-min cadence, mp-refresh writes a row) — at that point this
//  file becomes the *fallback* generator instead of the only source.
//

import Foundation

struct SeriesPoint: Identifiable, Sendable {
    let id: Int
    let x: Double      // 0…1 across the range
    let y: Double      // 0…1 normalized value
}

struct BarPoint: Identifiable, Sendable {
    let id: Int
    let x: Int         // bucket index
    /// Signed value (dollars for real-data charts, [-1, 1] for synthetic).
    /// DeltaBarChart auto-scales the Y axis to fit.
    let value: Double
    /// Short label under the bar (e.g. "May 28", "Wk 22", "Jun"). Nil
    /// → no axis label rendered for this bar. Populated by the
    /// compute layer per period unit.
    var label: String? = nil
    var up: Bool { value >= 0 }
}

enum ChartData {

    // MARK: - Seeded random walk (line charts)

    /// Pseudo-random walk in [0.14, 0.86] — same algo as `chartPoints`
    /// in reference/app-frame.jsx so visuals match the design.
    static func line(seed: Int, count: Int, trend: Double = 1.0) -> [SeriesPoint] {
        var s = (UInt64(abs(seed)) % 2_147_483_647)
        if s == 0 { s = 1 }
        func rnd() -> Double {
            s = (s &* 48271) % 2_147_483_647
            return Double(s) / 2_147_483_647.0
        }

        var v = 0.5
        var out: [SeriesPoint] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            v += (rnd() - 0.5) * 0.16 + trend * 0.010
            v = max(0.14, min(0.86, v))
            let x = count > 1 ? Double(i) / Double(count - 1) : 0
            out.append(SeriesPoint(id: i, x: x, y: v))
        }
        return out
    }

    // MARK: - Diverging bars (Net Δ / Γ history)

    /// Up/down magnitude pairs, biased by `upProb`. Same algo as
    /// `barSeries` in reference/app-frame.jsx.
    static func bars(seed: Int, count: Int, upProb: Double = 0.74) -> [BarPoint] {
        var s = (UInt64(abs(seed)) % 2_147_483_647)
        if s == 0 { s = 1 }
        func rnd() -> Double {
            s = (s &* 48271) % 2_147_483_647
            return Double(s) / 2_147_483_647.0
        }

        var out: [BarPoint] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let up = rnd() < upProb
            let mag = 0.25 + rnd() * 0.75
            out.append(BarPoint(id: i, x: i, value: up ? mag : -mag))
        }
        return out
    }

    // MARK: - Range → point count

    /// How many points per range — tuned so 1D looks intraday-detailed
    /// and 1Y looks weekly. Values are intentionally not perfectly
    /// proportional to wall time; they're chosen to look right.
    static func pointCount(for range: ChartRange) -> Int {
        switch range {
        case .oneDay:     return 13
        case .oneWeek:    return 7
        case .oneMonth:   return 22
        case .threeMonth: return 60
        case .ytd:        return 110
        case .oneYear:    return 52
        case .all:        return 130
        }
    }

    // MARK: - Stable seeds

    /// Hash a string to a non-negative int. Used to seed per-ticker
    /// charts so each ticker has its own consistent shape.
    static func hashString(_ s: String) -> Int {
        var h: Int = 0
        for ch in s.unicodeScalars {
            h = (h &* 31) &+ Int(ch.value)
        }
        return abs(h) + 1
    }
}
