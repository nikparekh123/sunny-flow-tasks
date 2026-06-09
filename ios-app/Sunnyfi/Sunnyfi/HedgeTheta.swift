//
//  HedgeTheta.swift
//  Sunnyfi
//
//  Real-theta math layer for the Hedge tab. Joins open long puts with
//  the latest greeks capture so the hedge cost is reported as actual
//  $/day theta (sum of |θ| × contracts × 100) rather than flat-amortized
//  cost. Classifies each leg by DTE into a calm-to-critical urgency zone
//  so the UI can surface the cliff before it arrives.
//
//  v1 scope (per user):
//   • Long puts only. Long calls have a clean toggle path for later.
//   • DTE zones use calendar days (EST). Trading-day projection lives
//     in HedgeMath.tradingDaysBetween already and we'll layer projection
//     forecasts on top in phase 2.
//   • If a leg has no greeks row yet (e.g. just opened, not refreshed),
//     it shows up in the snapshot but its daily burn is nil — the UI
//     marks it as "no theta yet" instead of pretending the cost is $0.
//

import Foundation
import SwiftUI

/// Urgency band for a single long-premium leg. Driven purely off DTE
/// today — projection-aware bands come in phase 2.
enum HedgeZone: Int, CaseIterable, Comparable {
    case calm = 0        // > 45 DTE — gentle decay
    case watch = 1       // 22–45 DTE — starting to bite
    case cliff = 2       // 8–21  DTE — decision window
    case critical = 3    // ≤ 7   DTE — brutal bleed

    /// Higher = more urgent. Used to roll up "worst zone in portfolio".
    static func < (lhs: HedgeZone, rhs: HedgeZone) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .calm:     return "CALM"
        case .watch:    return "WATCH"
        case .cliff:    return "CLIFF"
        case .critical: return "CRITICAL"
        }
    }

    /// Color used by zone chips, gauges, and per-leg borders. Pulled
    /// from Theme tokens so we stay on the Navi palette.
    var color: Color {
        switch self {
        case .calm:     return Color.theme.fg3
        case .watch:    return Color.theme.fg2
        case .cliff:    return Color.theme.warn
        case .critical: return Color.theme.neg
        }
    }

    /// 0…1 position on the calm→critical gauge. Used for the portfolio
    /// hero progress bar fill.
    var gaugeFraction: Double {
        switch self {
        case .calm:     return 0.10
        case .watch:    return 0.40
        case .cliff:    return 0.70
        case .critical: return 0.95
        }
    }
}

/// One open long put, joined to greeks, with zone + burn computed.
struct HedgeLegLive: Identifiable, Hashable {
    let id: String                  // open trade id
    let ticker: String
    let strike: Double
    let expiry: String
    let contractsRemaining: Double
    let dte: Int                    // calendar DTE in EST
    let zone: HedgeZone

    /// θ per share from the greeks row, signed (Polygon returns negative
    /// theta for long premium — we store the raw value here).
    let thetaPerShare: Double?
    /// Mark per share from greeks `last_mark`. Nil if unavailable.
    let lastMark: Double?

    /// |theta| × contractsRemaining × 100. Nil when no greeks row exists.
    /// Caller decides how to render the "missing data" state.
    var dailyBurn: Double? {
        guard let t = thetaPerShare else { return nil }
        return abs(t) * contractsRemaining * 100
    }

    /// Theta as a fraction of remaining premium (mark). Sometimes a
    /// more honest urgency signal than DTE alone: e.g. a 30-DTE put at
    /// $0.50 with $0.03 theta is bleeding 6%/day. Phase 2 may surface
    /// this directly on the leg card.
    var thetaAsPctOfMark: Double? {
        guard let t = thetaPerShare, let m = lastMark, m > 0 else { return nil }
        return abs(t) / m
    }

    /// Calendar days until this leg crosses into the next more-urgent
    /// zone. Nil if already CRITICAL. Used for the "cliff date" surface.
    var daysToNextZone: Int? {
        switch zone {
        case .calm:     return max(0, dte - 45)   // → WATCH at 45 DTE
        case .watch:    return max(0, dte - 21)   // → CLIFF at 21 DTE
        case .cliff:    return max(0, dte - 7)    // → CRITICAL at 7 DTE
        case .critical: return nil
        }
    }

    /// Next zone this leg will fall into (nil if already in the worst).
    var nextZone: HedgeZone? {
        switch zone {
        case .calm:     return .watch
        case .watch:    return .cliff
        case .cliff:    return .critical
        case .critical: return nil
        }
    }
}

/// Aggregate today-only snapshot. Day-over-day deltas + sparkline land
/// in phase 2 once daily_theta_snapshot exists.
struct HedgeTodaySnapshot {
    let legs: [HedgeLegLive]
    /// Sum of dailyBurn across legs that have greeks data. Legs without
    /// greeks contribute nothing — UI shows their count separately so
    /// the user knows the headline number is partial.
    let totalBurn: Double
    /// How many legs are still missing a greeks row (recently opened or
    /// pre-cron). Surfaces a caveat in the UI when > 0.
    let legsMissingGreeks: Int
    /// Worst (most urgent) zone in the book. Drives the hero gauge.
    let worstZone: HedgeZone
    /// Count per zone for the "8 legs · 2 in cliff" summary.
    let zoneCounts: [HedgeZone: Int]

    /// Legs in CLIFF or CRITICAL, sorted most-urgent first. Within the
    /// same zone, sooner-expiring legs come first.
    var cliffLegs: [HedgeLegLive] {
        legs
            .filter { $0.zone >= .cliff }
            .sorted { lhs, rhs in
                if lhs.zone != rhs.zone { return lhs.zone > rhs.zone }
                return lhs.dte < rhs.dte
            }
    }

    /// Legs grouped by ticker, ticker order = highest daily burn first.
    /// Tickers with no greeks fall to the bottom (sorted alphabetically
    /// so the order is stable across renders).
    var byTicker: [(ticker: String, legs: [HedgeLegLive])] {
        let groups = Dictionary(grouping: legs, by: \.ticker)
        return groups
            .map { (ticker: $0.key, legs: $0.value.sorted { $0.dte < $1.dte }) }
            .sorted { lhs, rhs in
                let lb = lhs.legs.compactMap(\.dailyBurn).reduce(0, +)
                let rb = rhs.legs.compactMap(\.dailyBurn).reduce(0, +)
                if lb != rb { return lb > rb }
                return lhs.ticker < rhs.ticker
            }
    }

    var isEmpty: Bool { legs.isEmpty }

    static let empty = HedgeTodaySnapshot(
        legs: [],
        totalBurn: 0,
        legsMissingGreeks: 0,
        worstZone: .calm,
        zoneCounts: [:]
    )
}

enum HedgeTheta {

    /// DTE → zone classifier. Pure function so it's trivially unit-
    /// testable and can be reused for projection markers later.
    static func zone(forDTE dte: Int) -> HedgeZone {
        if dte <= 7  { return .critical }
        if dte <= 21 { return .cliff }
        if dte <= 45 { return .watch }
        return .calm
    }

    /// Build today's snapshot from raw store state. Greeks lookup is by
    /// `option_trade_id`. Filters to action=open, direction=long,
    /// option_type=put, remainingContracts > 0 — matching the user's
    /// "hedge book = long puts only" scope.
    static func snapshot(
        from trades: [OptionTradeRow],
        greeks: [OptionGreeksRow],
        remaining: (OptionTradeRow) -> Double,
        now: Date = Date()
    ) -> HedgeTodaySnapshot {
        let openLongPuts = trades.filter {
            $0.action == "open"
            && $0.direction == "long"
            && $0.option_type == "put"
            && remaining($0) > 0.0001
        }

        // Index greeks by trade id for O(1) lookup. If multiple rows
        // somehow exist for the same trade we keep the *latest* by
        // captured_at — the cron upserts so this is defensive only.
        var greeksByTrade: [String: OptionGreeksRow] = [:]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter()
        isoFallback.formatOptions = [.withInternetDateTime]
        for row in greeks {
            if let existing = greeksByTrade[row.option_trade_id] {
                let lhs = (existing.captured_at.flatMap { iso.date(from: $0) ?? isoFallback.date(from: $0) }) ?? .distantPast
                let rhs = (row.captured_at.flatMap      { iso.date(from: $0) ?? isoFallback.date(from: $0) }) ?? .distantPast
                if rhs > lhs { greeksByTrade[row.option_trade_id] = row }
            } else {
                greeksByTrade[row.option_trade_id] = row
            }
        }

        var legs: [HedgeLegLive] = []
        legs.reserveCapacity(openLongPuts.count)
        var totalBurn = 0.0
        var missingGreeks = 0
        var counts: [HedgeZone: Int] = [:]
        var worst: HedgeZone = .calm

        for t in openLongPuts {
            let dte = AppDates.daysUntil(t.expiry, from: now) ?? 0
            // Past-expiry legs (dte ≤ 0) collapse into CRITICAL — they
            // shouldn't be in the book but we don't want to crash if
            // an expired open row slips through.
            let z = zone(forDTE: max(0, dte))
            let g = greeksByTrade[t.id]
            let leg = HedgeLegLive(
                id: t.id,
                ticker: t.ticker,
                strike: t.strike,
                expiry: t.expiry,
                contractsRemaining: remaining(t),
                dte: max(0, dte),
                zone: z,
                thetaPerShare: g?.theta,
                lastMark: g?.last_mark
            )
            legs.append(leg)
            if let b = leg.dailyBurn { totalBurn += b } else { missingGreeks += 1 }
            counts[z, default: 0] += 1
            if z > worst { worst = z }
        }

        return HedgeTodaySnapshot(
            legs: legs,
            totalBurn: totalBurn,
            legsMissingGreeks: missingGreeks,
            worstZone: worst,
            zoneCounts: counts
        )
    }
}
