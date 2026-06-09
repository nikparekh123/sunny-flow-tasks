//
//  HedgeHistory.swift
//  Sunnyfi
//
//  Time-series helpers for the Hedge tab. Reads from the
//  `daily_theta_snapshot` history loaded in PortfolioStore plus the
//  raw option_trades to compute:
//   • day-over-day Δ-change vs yesterday (phase 2 hero)
//   • 14-day sparkline series (phase 2)
//   • last-4-weeks paid-vs-collected strip (phase 3)
//
//  All math is in EST. Trading days are inferred from snapshot
//  presence — if the cron didn't run (holiday, outage), we just skip
//  those gaps rather than fabricate values.
//

import Foundation

// MARK: - Day-over-day

struct HedgeDayDelta {
    /// Today's snapshot row (or live `hedgeToday.totalBurn` if newer).
    let todayBurn: Double
    /// Most recent prior-day snapshot. Nil if history is empty.
    let priorBurn: Double?
    /// today − prior. Positive = burn rising = bad.
    var change: Double? {
        guard let p = priorBurn else { return nil }
        return todayBurn - p
    }
    /// (today − prior) / prior. Nil when prior is 0 (avoids ∞).
    var pct: Double? {
        guard let p = priorBurn, p > 0 else { return nil }
        return (todayBurn - p) / p
    }
}

// MARK: - Sparkline

/// One point in the 14-day theta sparkline.
struct SparklinePoint: Identifiable, Hashable {
    var id: String { date }
    let date: String         // YYYY-MM-DD
    let value: Double
}

// MARK: - Prior-week strip

struct PriorWeekSummary: Identifiable, Hashable {
    var id: String { weekStartISO }
    /// Monday of the week.
    let weekStartISO: String
    /// Sunday of the week.
    let weekEndISO: String
    /// Sum of daily total_burn from snapshots in this week.
    let paid: Double
    /// Sum of short-call premium credits collected in this week.
    let sold: Double
    var net: Double { sold - paid }
    /// True when sold ≥ paid — premium covered the burn that week.
    var covered: Bool { sold >= paid }
}

/// Per-day breakdown inside a single week. Used for the bar-chart
/// view of last week and the mini bars on prior-week cards.
struct DailyBreakdown: Identifiable, Hashable {
    var id: String { date }
    let date: String          // YYYY-MM-DD
    let weekdayShort: String  // "Mon", "Tue", …
    let weekdayLetter: String // "M", "T", "W", "T", "F"
    let paid: Double          // theta burn snapshot for that day
    let sold: Double          // short-call premium opened on that date
    /// True if this date has elapsed (≤ today). Future dates render
    /// with reduced opacity so the user sees "yet to come".
    let isPast: Bool
}

enum HedgeHistory {

    /// Build the day-over-day delta. Uses live `hedgeToday.totalBurn`
    /// as "today" so the hero animates as you trade; falls back to
    /// the latest snapshot row if live burn is 0 (e.g. pre-market
    /// before any greeks rows exist).
    static func dayDelta(
        liveBurn: Double,
        snapshots: [DailyThetaSnapshotRow],
        now: Date = Date()
    ) -> HedgeDayDelta {
        let today = todayDateString(now)
        // Snapshots are sorted oldest → newest. Find the most recent
        // row with date < today. If today's snapshot is in there too
        // (cron has run already), prefer the live burn over it.
        let priorSorted = snapshots
            .filter { $0.snapshot_date < today }
            .sorted { $0.snapshot_date > $1.snapshot_date }
        let prior = priorSorted.first?.total_burn
        return HedgeDayDelta(todayBurn: liveBurn, priorBurn: prior)
    }

    /// Last N trading-day snapshots ending today (inclusive when the
    /// cron has fired). Appends a synthesized "today" point from live
    /// burn so the sparkline shows current value even before the cron
    /// runs at close.
    static func sparkline(
        liveBurn: Double,
        snapshots: [DailyThetaSnapshotRow],
        days: Int = 14,
        now: Date = Date()
    ) -> [SparklinePoint] {
        let today = todayDateString(now)
        var points: [SparklinePoint] = snapshots
            .filter { $0.snapshot_date != today }
            .map { SparklinePoint(date: $0.snapshot_date, value: $0.total_burn) }
        // Add today as the rightmost point (current live value).
        points.append(SparklinePoint(date: today, value: liveBurn))
        // Trim to the last `days`.
        if points.count > days {
            points = Array(points.suffix(days))
        }
        return points
    }

    /// Build summaries for the last `weekCount` complete weeks ending
    /// *before* the current week. Weeks are Mon → Sun in EST.
    static func priorWeeks(
        weekCount: Int = 4,
        snapshots: [DailyThetaSnapshotRow],
        trades: [OptionTradeRow],
        now: Date = Date()
    ) -> [PriorWeekSummary] {
        guard let eastern = TimeZone(identifier: "America/New_York") else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = eastern
        cal.firstWeekday = 2 // Monday

        // Monday of the CURRENT week — anchor.
        let nowMidnight = cal.startOfDay(for: now)
        let weekdayComps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: nowMidnight)
        guard let currentMon = cal.date(from: weekdayComps) else { return [] }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = eastern

        var out: [PriorWeekSummary] = []
        for i in 1...weekCount {
            guard
                let monday = cal.date(byAdding: .day, value: -7 * i, to: currentMon),
                let sunday = cal.date(byAdding: .day, value: 6, to: monday)
            else { continue }
            let monStr = df.string(from: monday)
            let sunStr = df.string(from: sunday)
            let paid = snapshots
                .filter { $0.snapshot_date >= monStr && $0.snapshot_date <= sunStr }
                .reduce(0) { $0 + $1.total_burn }
            // Short-call credits opened during this window. Same logic
            // as PortfolioStore.shortCallPremiumCollected, but
            // window-bounded.
            let sold = trades
                .filter { t in
                    let d = String(t.trade_date.prefix(10))
                    return d >= monStr && d <= sunStr
                        && t.option_type == "call"
                        && t.direction == "short"
                }
                .reduce(0.0) { acc, t in
                    let signed = t.action == "open" ? 1.0 : -1.0
                    return acc + signed * t.premium * t.contracts * 100
                }
            out.append(PriorWeekSummary(
                weekStartISO: monStr,
                weekEndISO: sunStr,
                paid: paid,
                sold: max(0, sold)
            ))
        }
        return out
    }

    /// Today's date string in EST, YYYY-MM-DD.
    private static func todayDateString(_ now: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "America/New_York")
        return df.string(from: now)
    }

    /// Build per-day breakdown for the trading week starting at
    /// `weekStart` (Monday EST). Returns 5 entries (Mon → Fri).
    /// `liveBurn` is used for *today* if today falls within the week
    /// and the snapshot isn't in yet — gives a live view of the
    /// in-progress week.
    static func dailyBreakdown(
        weekStart: Date,
        snapshots: [DailyThetaSnapshotRow],
        trades: [OptionTradeRow],
        liveBurn: Double = 0,
        now: Date = Date()
    ) -> [DailyBreakdown] {
        guard let eastern = TimeZone(identifier: "America/New_York") else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = eastern

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = eastern
        let weekdayFull = DateFormatter()
        weekdayFull.dateFormat = "EEE"
        weekdayFull.timeZone = eastern
        let weekdayLetter = DateFormatter()
        weekdayLetter.dateFormat = "EEEEE"   // single-letter (M/T/W/T/F)
        weekdayLetter.timeZone = eastern

        let today = todayDateString(now)
        var out: [DailyBreakdown] = []
        for i in 0..<5 {
            guard let day = cal.date(byAdding: .day, value: i, to: weekStart) else { continue }
            let iso = df.string(from: day)

            // Theta paid for that day. Prefer snapshot; if it's today
            // and no snapshot exists yet, fall back to live burn.
            var paid = snapshots.first(where: { $0.snapshot_date == iso })?.total_burn ?? 0
            if iso == today && paid == 0 && liveBurn > 0 {
                paid = liveBurn
            }

            // Short-call premium opened on that date.
            let sold = trades
                .filter { t in
                    let d = String(t.trade_date.prefix(10))
                    return d == iso
                        && t.option_type == "call"
                        && t.direction == "short"
                }
                .reduce(0.0) { acc, t in
                    let signed = t.action == "open" ? 1.0 : -1.0
                    return acc + signed * t.premium * t.contracts * 100
                }

            out.append(DailyBreakdown(
                date: iso,
                weekdayShort: weekdayFull.string(from: day),
                weekdayLetter: weekdayLetter.string(from: day),
                paid: paid,
                sold: max(0, sold),
                isPast: iso <= today
            ))
        }
        return out
    }

    /// Monday of the most recent COMPLETED week (i.e. last week). Used
    /// as the default focus of the WEEK view.
    static func lastWeekMonday(now: Date = Date()) -> Date? {
        guard let eastern = TimeZone(identifier: "America/New_York") else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = eastern
        cal.firstWeekday = 2 // Monday

        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: cal.startOfDay(for: now))
        guard let currentMonday = cal.date(from: comps) else { return nil }
        return cal.date(byAdding: .day, value: -7, to: currentMonday)
    }

    /// Monday of the current (in-progress) week.
    static func thisWeekMonday(now: Date = Date()) -> Date? {
        guard let eastern = TimeZone(identifier: "America/New_York") else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = eastern
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: cal.startOfDay(for: now))
        return cal.date(from: comps)
    }
}

// MARK: - Phase 4: stress test

/// One position's contribution to a stress-test scenario.
struct StressLeg: Identifiable {
    let id = UUID()
    let ticker: String
    let label: String          // "META 1500 sh", "META $650p ×15", …
    let category: StressCategory
    /// Position P&L on the scenario (positive = win, negative = loss).
    let pnl: Double
}

enum StressCategory: String, CaseIterable {
    case longPut    = "Long puts"
    case longCall   = "Long calls"
    case shortCall  = "Short calls"
    case shortPut   = "Short puts"
    case shares     = "Shares"

    /// Display ordering — what feels intuitive top-down.
    var order: Int {
        switch self {
        case .shares:    return 0
        case .longPut:   return 1
        case .longCall:  return 2
        case .shortCall: return 3
        case .shortPut:  return 4
        }
    }
}

struct StressResult {
    /// Slider value: -0.10 … +0.10 (i.e. -10% → +10% SPY move).
    let scenarioPct: Double
    let legs: [StressLeg]
    var total: Double { legs.reduce(0) { $0 + $1.pnl } }
    var byCategory: [(StressCategory, Double)] {
        let grouped = Dictionary(grouping: legs, by: \.category)
            .mapValues { $0.reduce(0) { $0 + $1.pnl } }
        return StressCategory.allCases
            .compactMap { c in grouped[c].map { (c, $0) } }
            .sorted { $0.0.order < $1.0.order }
    }
}

enum HedgeStress {

    /// Estimate portfolio P&L for a single SPY % move using each
    /// position's option Δ (Greek) or share notional. Assumes β = 1
    /// per ticker (each name moves with SPY 1:1). v1 simplification —
    /// per-ticker beta can swap in later by reading Company.beta.
    ///
    /// Maths:
    ///   share leg:   qty × spot × pct
    ///   long  call:  delta × spot × pct × contracts × 100
    ///   short call:  − delta × spot × pct × contracts × 100
    ///   long  put :  delta × spot × pct × contracts × 100   (Δ<0)
    ///   short put :  − delta × spot × pct × contracts × 100
    ///
    /// Greeks aren't fetched for stocks — we use Company.beta but
    /// floor to 1.0 when missing/zero so a fresh ticker doesn't show
    /// $0 impact misleadingly. The stress card surfaces the β=1
    /// assumption right in the copy.
    static func simulate(
        scenarioPct: Double,
        companies: [Company]
    ) -> StressResult {
        var legs: [StressLeg] = []
        for c in companies {
            let beta = c.beta > 0 ? c.beta : 1.0
            let effectivePct = scenarioPct * beta
            for leg in c.legs {
                let pnl = pnlFor(leg: leg, spot: c.spot, pct: effectivePct)
                guard abs(pnl) > 0.005 else { continue }
                let cat = category(for: leg)
                let label = labelFor(ticker: c.ticker, leg: leg)
                legs.append(StressLeg(ticker: c.ticker, label: label, category: cat, pnl: pnl))
            }
        }
        // Largest absolute impact first within each category — but the
        // grouping in `byCategory` handles per-category ordering; here
        // we just keep insertion order for the raw list.
        return StressResult(scenarioPct: scenarioPct, legs: legs)
    }

    private static func pnlFor(leg: Leg, spot: Double, pct: Double) -> Double {
        switch leg.kind {
        case .stock:
            return leg.qty * spot * pct
        case .call, .put:
            // qty is signed (short legs come through negative). The
            // delta-based P&L gives us the correct sign automatically.
            return leg.delta * spot * pct * leg.qty * 100
        }
    }

    private static func category(for leg: Leg) -> StressCategory {
        switch leg.kind {
        case .stock: return .shares
        case .call:  return leg.qty >= 0 ? .longCall : .shortCall
        case .put:   return leg.qty >= 0 ? .longPut  : .shortPut
        }
    }

    private static func labelFor(ticker: String, leg: Leg) -> String {
        switch leg.kind {
        case .stock:
            return "\(ticker) · \(Int(leg.qty)) sh"
        case .call:
            let qtyAbs = Int(abs(leg.qty))
            let strike = leg.strike.map { "$\(Int($0))c" } ?? "call"
            return "\(ticker) \(strike) ×\(qtyAbs)\(leg.qty < 0 ? " short" : "")"
        case .put:
            let qtyAbs = Int(abs(leg.qty))
            let strike = leg.strike.map { "$\(Int($0))p" } ?? "put"
            return "\(ticker) \(strike) ×\(qtyAbs)\(leg.qty < 0 ? " short" : "")"
        }
    }
}
