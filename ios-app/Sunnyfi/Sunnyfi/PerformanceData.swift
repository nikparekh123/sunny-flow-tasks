//
//  PerformanceData.swift
//  Sunnyfi
//
//  Period rollups for the Performance screen. Computes:
//   - realized P&L for the period (closed option pairs + share sells)
//   - premium collected for the period (signed short-leg premium)
//   - per-day buckets for the bar chart
//   - return-by-source breakdown (Shares / Calls sold / Puts sold / etc.)
//   - per-stock performance list
//

import Foundation

enum PerfPeriod: String, CaseIterable, Identifiable, Hashable {
    case day = "Day", week = "Week", month = "Month", quarter = "Quarter", year = "Year"
    var id: String { rawValue }

    /// Start date for the current view (offset = 0).
    func start(now: Date) -> Date { bounds(now: now, offset: 0).start }

    /// How many bars to render — and what unit each one represents:
    ///   Day     → 20 daily bars
    ///   Week    → 13 weekly bars
    ///   Month   → 12 monthly bars
    ///   Quarter →  8 quarterly bars
    ///   Year    →  5 yearly bars
    /// Period now controls bar GRANULARITY, not just window length.
    var barCount: Int {
        switch self {
        case .day:     return 20
        case .week:    return 13
        case .month:   return 12
        case .quarter: return 8
        case .year:    return 5
        }
    }

    /// Bounds for the view at a given offset. The view always spans
    /// `barCount` units of the period's unit (days/weeks/months/etc.)
    /// — so Month shows the last 12 months as 12 monthly bars, Day
    /// shows the last 20 days as 20 daily bars, and so on. Offset
    /// shifts the window by one unit at a time (◀ / ▶ in the UI).
    ///
    /// `end` is clamped to `now` for offset = 0 so we don't claim
    /// future days as $0 realized in the current bucket.
    func bounds(now: Date, offset: Int) -> (start: Date, end: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? cal.timeZone
        cal.firstWeekday = 2

        // Pick the right calendar unit + multiplier per period.
        let (unit, mult): (Calendar.Component, Int) = {
            switch self {
            case .day:     return (.day,         1)
            case .week:    return (.weekOfYear,  1)
            case .month:   return (.month,       1)
            case .quarter: return (.month,       3)
            case .year:    return (.year,        1)
            }
        }()

        // Anchor "end" to the start of the unit-bucket that contains
        // (now + offset units), then add one bucket so the current
        // bucket is fully inside the window.
        let anchored: Date = {
            switch unit {
            case .day:        return cal.startOfDay(for: now)
            case .weekOfYear: return AppDates.startOfWeek(now)
            case .month:      return cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            case .year:       return cal.date(from: cal.dateComponents([.year], from: now)) ?? now
            default:          return cal.startOfDay(for: now)
            }
        }()
        let shifted = cal.date(byAdding: unit, value: offset * mult, to: anchored) ?? anchored
        let endBoundary = cal.date(byAdding: unit, value: mult, to: shifted) ?? shifted
        let end = offset == 0 ? min(now, endBoundary) : endBoundary.addingTimeInterval(-1)

        // Walk back `barCount` units to find the window start.
        let start = cal.date(byAdding: unit, value: -barCount * mult, to: endBoundary) ?? shifted
        return (start, end)
    }

    /// Human-readable label for a (period, offset) pair — describes
    /// the *window*, not just one anchor. e.g. "Last 12 months",
    /// "Days ending May 28 · last 20".
    func label(now: Date, offset: Int) -> String {
        let (start, end) = bounds(now: now, offset: offset)
        let df = DateFormatter()
        df.timeZone = TimeZone(identifier: "America/New_York")
        df.dateFormat = "MMM d"
        let startStr = df.string(from: start)
        let endStr   = df.string(from: end)
        switch self {
        case .day:
            return offset == 0 ? "Last \(barCount) days" : "\(startStr) – \(endStr)"
        case .week:
            return offset == 0 ? "Last \(barCount) weeks" : "\(startStr) – \(endStr)"
        case .month:
            return offset == 0 ? "Last \(barCount) months" : "\(startStr) – \(endStr)"
        case .quarter:
            return offset == 0 ? "Last \(barCount) quarters" : "\(startStr) – \(endStr)"
        case .year:
            df.dateFormat = "yyyy"
            return offset == 0 ? "Last \(barCount) years"
                               : "\(df.string(from: start)) – \(df.string(from: end))"
        }
    }
}

enum FlowSource: String, CaseIterable, Hashable {
    case shares       = "Shares"
    case callsSold    = "Calls sold"
    case putsSold     = "Puts sold"
    case callsBought  = "Calls bought"
    case putsBought   = "Puts bought"
}

struct FlowEntry: Identifiable, Hashable {
    let id = UUID()
    let source: FlowSource
    /// Closed-pair P&L (or share-sell realized) attributed to this
    /// source within the selected period. **Realized-only** — open
    /// positions contribute nothing because they aren't a P&L event yet.
    let realized: Double
    /// Backwards-compat alias — what the row displays.
    var value: Double { realized }
    /// % share of the period's total *absolute* realized activity. Just
    /// a contribution ratio, never negative, never > 100.
    let pctOfTotal: Int
    var isPositive: Bool { realized >= 0 }
}

struct StockPerf: Identifiable, Hashable {
    let id = UUID()
    let ticker: String
    /// Realized in the period (closed-pair P&L + share sells).
    let realized: Double
    /// Live mark-to-market unrealized (across open option legs + stock).
    let unrealized: Double
    /// Total return = realized + unrealized.
    var value: Double { realized + unrealized }
    /// Return as a % of position cost basis (avg_cost × shares). 0 if no shares.
    let pct: Double
    /// Realized-only ROI — `realized / lifetime cost basis × 100`. Cost
    /// basis = Σ(qty_original × cost_per_share) across every share lot
    /// ever bought for this ticker, so closed positions (where shares
    /// = 0 today) still report a meaningful ROI. Nil for tickers with
    /// no share lots — pure options-only — where there's no natural
    /// denominator.
    let realizedROI: Double?
    /// Stock average cost.
    let avgPrice: Double
    /// Net price = avg cost minus per-share lifetime premium received.
    /// Reflects effective basis for covered-call strategies.
    let netPrice: Double
    /// True when this is a fully-closed position (no shares + no open option legs).
    let closed: Bool
}

struct PeriodSummary {
    let realized: Double      // closed-pair P&L in the period
    /// Sum of credits received from short opens within the period.
    /// This is the gross income side — completely separate from realized
    /// P&L on closes. Surfaced side-by-side with `realized` so the user
    /// can reconcile against Trades' YTD figure.
    let grossCredits: Double
    let title: String
    let netLine: String
    let flow: [FlowEntry]
    let bars: [BarPoint]
    /// Per-source bar series — used when user taps a Return-by-source row
    /// to filter the chart to just that source's daily contribution.
    let barsBySource: [FlowSource: [BarPoint]]
    let stocks: [StockPerf]
}

enum PerformanceData {

    static func compute(
        period: PerfPeriod,
        offset: Int = 0,
        companies: [Company],
        allTrades: [OptionTradeRow],
        shareSells: [ShareSellRow],
        allGreeks: [OptionGreeksRow] = [],
        now: Date = Date()
    ) -> PeriodSummary {

        let (start, windowEnd) = period.bounds(now: now, offset: offset)
        let cal = Calendar(identifier: .gregorian)

        // ── Gross credit / debit per source (informational only) ──
        var grossCredits = 0.0   // sum of credits from short opens in period
        var callsBoughtDebit = 0.0
        var putsBoughtDebit = 0.0
        // Realized P&L per source (closed-pair from option_trades, share sells).
        var realizedBySource: [FlowSource: Double] = [:]

        // ── Realized totals ───────────────────────────────────────
        var realizedFromCloses = 0.0
        var realizedFromShares = 0.0

        // ── Buckets for bar chart ─────────────────────────────────
        var dayBuckets: [Date: Double] = [:]
        // Per-source daily buckets for the "tap a source row to filter
        // the chart" interaction.
        var dayBySource: [FlowSource: [Date: Double]] = [:]

        // Opens in period contribute ONLY to the gross-credit informational
        // figure. They do NOT touch the bar chart or the flow rows because
        // an open position is not a realized P&L event — it's just a
        // position waiting to be resolved.
        for t in allTrades where t.action == "open" && t.direction == "short" {
            guard let d = AppDates.parseISODay(t.trade_date), d >= start, d <= windowEnd else { continue }
            grossCredits += t.premium * t.contracts * 100
        }
        // (Bought-option debits tracked separately purely so we could
        //  surface them if asked, but we no longer include them anywhere
        //  user-facing.)
        _ = callsBoughtDebit
        _ = putsBoughtDebit

        // Closes — realized P&L per source. This drives both the chart
        // bars (period bucketed) and the Return-by-source rows.
        for c in allTrades where c.action == "close" {
            guard let d = AppDates.parseISODay(c.trade_date), d >= start, d <= windowEnd else { continue }
            guard let open = allTrades.first(where: { $0.id == (c.closes_trade_id ?? "") }) else { continue }
            let sign: Double = open.direction == "short" ? 1 : -1
            let realized = (open.premium - c.premium) * c.contracts * 100 * sign
            realizedFromCloses += realized
            let day = cal.startOfDay(for: d)
            dayBuckets[day, default: 0] += realized

            // Attribute to source = open's (type, direction)
            let source: FlowSource
            switch (open.option_type, open.direction) {
            case ("call", "short"): source = .callsSold
            case ("put",  "short"): source = .putsSold
            case ("call", "long"):  source = .callsBought
            case ("put",  "long"):  source = .putsBought
            default: continue
            }
            realizedBySource[source, default: 0] += realized
            dayBySource[source, default: [:]][day, default: 0] += realized
        }

        // Share sells in period — realized only.
        for s in shareSells {
            guard let d = AppDates.parseISODay(s.trade_date), d >= start, d <= windowEnd else { continue }
            realizedFromShares += s.realized_pl
            let day = cal.startOfDay(for: d)
            dayBuckets[day, default: 0] += s.realized_pl
            dayBySource[.shares, default: [:]][day, default: 0] += s.realized_pl
            realizedBySource[.shares, default: 0] += s.realized_pl
        }

        let realized = realizedFromCloses + realizedFromShares

        // ── Flow breakdown — realized only per source ─────────────
        // No unrealized component. A bought put with the underlying
        // moving against you is not a "loss" until it actually gets
        // closed. Until then the source's value here is $0.
        var rawEntries: [(FlowSource, Double)] = []
        for src in FlowSource.allCases {
            let r = realizedBySource[src] ?? 0
            if r != 0 { rawEntries.append((src, r)) }
        }
        let totalMag = max(rawEntries.map { abs($0.1) }.reduce(0, +), 1)
        let flow: [FlowEntry] = rawEntries
            .map { (src, r) -> FlowEntry in
                FlowEntry(
                    source: src,
                    realized: r,
                    pctOfTotal: Int((abs(r) / totalMag) * 100)
                )
            }
            .sorted { abs($0.value) > abs($1.value) }

        // ── Bars: bucket realized into `barCount` evenly-spaced bins ──
        let n = period.barCount
        let totalSpan = max(windowEnd.timeIntervalSince(start), 1)
        let bucketSpan = totalSpan / Double(n)
        var bucketSums = [Double](repeating: 0, count: n)
        for (d, v) in dayBuckets {
            let offset = d.timeIntervalSince(start)
            let idx = max(0, min(n - 1, Int(offset / bucketSpan)))
            bucketSums[idx] += v
        }
        // Drop empty buckets — closing a position is sporadic by
        // nature, so leaving zero-value buckets in the chart creates
        // visually awkward gaps. We renumber x positions densely.
        let bars: [BarPoint] = bucketSums.enumerated()
            .filter { abs($0.element) >= 0.5 }
            .enumerated()
            .map { densI, pair in
                BarPoint(
                    id: pair.offset, x: densI, value: pair.element,
                    label: barLabel(
                        period: period,
                        bucketIndex: pair.offset,
                        bucketSpan: bucketSpan,
                        start: start
                    )
                )
            }

        // ── Per-source bars (same bucketing + same zero filter) ──
        var barsBySource: [FlowSource: [BarPoint]] = [:]
        for src in FlowSource.allCases {
            var sums = [Double](repeating: 0, count: n)
            for (d, v) in (dayBySource[src] ?? [:]) {
                let offset = d.timeIntervalSince(start)
                let idx = max(0, min(n - 1, Int(offset / bucketSpan)))
                sums[idx] += v
            }
            barsBySource[src] = sums.enumerated()
                .filter { abs($0.element) >= 0.5 }
                .enumerated()
                .map { densI, pair in
                    BarPoint(
                        id: pair.offset, x: densI, value: pair.element,
                        label: barLabel(
                            period: period,
                            bucketIndex: pair.offset,
                            bucketSpan: bucketSpan,
                            start: start
                        )
                    )
                }
        }

        // ── Per-stock performance — realized in period + LIVE unrealized ──
        var realizedByTicker: [String: Double] = [:]
        for c in allTrades where c.action == "close" {
            guard let d = AppDates.parseISODay(c.trade_date), d >= start, d <= windowEnd else { continue }
            guard let open = allTrades.first(where: { $0.id == (c.closes_trade_id ?? "") }) else { continue }
            let sign: Double = open.direction == "short" ? 1 : -1
            let realized = (open.premium - c.premium) * c.contracts * 100 * sign
            realizedByTicker[c.ticker, default: 0] += realized
        }
        for s in shareSells {
            guard let d = AppDates.parseISODay(s.trade_date), d >= start, d <= windowEnd else { continue }
            realizedByTicker[s.ticker, default: 0] += s.realized_pl
        }

        // Union of all tickers we want to show: anyone with companies
        // entry (current holdings or closed) OR realized activity in period.
        var tickerSet = Set(companies.map(\.ticker))
        tickerSet.formUnion(realizedByTicker.keys)

        // Lifetime premium received per ticker — used to compute net price.
        var lifetimePremiumByTicker: [String: Double] = [:]
        for t in allTrades where t.action == "open" && t.direction == "short" {
            lifetimePremiumByTicker[t.ticker, default: 0] += t.premium * t.contracts * 100
        }

        let stocks: [StockPerf] = tickerSet.map { ticker -> StockPerf in
            let comp = companies.first { $0.ticker == ticker }
            let realized = realizedByTicker[ticker] ?? 0
            let unrealized = comp?.agg.unreal ?? 0
            let stockLeg = comp?.legs.first(where: { $0.kind == .stock })
            let shares = stockLeg?.qty ?? 0
            let avg = stockLeg?.avg ?? 0
            let totalPremium = lifetimePremiumByTicker[ticker] ?? 0
            let net = shares > 0 ? avg - (totalPremium / shares) : avg
            // % return = total return / basis (basis = shares × avg cost)
            let basis = max(shares * avg, 1)
            let total = realized + unrealized
            let pct = total / basis * 100
            // Treat as "closed" when no current shares AND no open option legs.
            let hasOpenLegs = (comp?.legs.contains(where: { $0.kind != .stock }) ?? false)
            let isClosed = shares == 0 && !hasOpenLegs
            return StockPerf(
                ticker: ticker,
                realized: realized,
                unrealized: unrealized,
                pct: pct,
                realizedROI: nil,  // legacy compute path — ROI lives in lifetimeStocks
                avgPrice: avg,
                netPrice: net,
                closed: isClosed
            )
        }
        .sorted { abs($0.value) > abs($1.value) }

        // ── Title strings ─────────────────────────────────────────
        let titleFmt = DateFormatter()
        switch period {
        case .day:     titleFmt.dateFormat = "EEEE · MMM d"
        case .week:    titleFmt.dateFormat = "'This week'"
        case .month:   titleFmt.dateFormat = "MMMM yyyy"
        case .quarter: titleFmt.dateFormat = "'Q'q yyyy"
        case .year:    titleFmt.dateFormat = "yyyy"
        }
        let title = titleFmt.string(from: start)
        let netLine = "Net \(fmtMoney(realized, sign: true)) · \(period.rawValue.lowercased())"

        return PeriodSummary(
            realized: realized,
            grossCredits: grossCredits,
            title: title,
            netLine: netLine,
            flow: flow,
            bars: bars,
            barsBySource: barsBySource,
            stocks: stocks
        )
    }

    /// Per-stock rollup over **all time** — independent of the active
    /// period picker. Used by the "By position · Lifetime" section so
    /// those numbers always show something meaningful even when the
    /// current period has no closed activity.
    ///
    /// Realized aggregates every closed option pair + share sell ever
    /// recorded. Unrealized is the live mark-to-market on whatever's
    /// currently open. Net price still nets lifetime premium against
    /// average cost.
    /// X-axis label for one bar bucket. The format follows the period
    /// unit so a "Month" chart shows "May / Jun / Jul", a "Day" chart
    /// shows "May 28 / May 29 / May 30", etc. Returns the date at the
    /// bucket's center so labels read intuitively even when buckets
    /// don't perfectly align to calendar boundaries.
    private static func barLabel(period: PerfPeriod, bucketIndex: Int, bucketSpan: TimeInterval, start: Date) -> String {
        let center = start.addingTimeInterval(bucketSpan * (Double(bucketIndex) + 0.5))
        let df = DateFormatter()
        df.timeZone = TimeZone(identifier: "America/New_York")
        switch period {
        case .day:     df.dateFormat = "MMM d"
        case .week:    df.dateFormat = "MMM d"
        case .month:   df.dateFormat = "MMM"
        case .quarter:
            let q = (Calendar.current.component(.month, from: center) - 1) / 3 + 1
            return "Q\(q)"
        case .year:    df.dateFormat = "yyyy"
        }
        return df.string(from: center)
    }

    static func lifetimeStocks(
        companies: [Company],
        allTrades: [OptionTradeRow],
        shareSells: [ShareSellRow],
        shareLots: [ShareLotRow] = []
    ) -> [StockPerf] {
        var realizedByTicker: [String: Double] = [:]
        for c in allTrades where c.action == "close" {
            guard let open = allTrades.first(where: { $0.id == (c.closes_trade_id ?? "") }) else { continue }
            let sign: Double = open.direction == "short" ? 1 : -1
            let realized = (open.premium - c.premium) * c.contracts * 100 * sign
            realizedByTicker[c.ticker, default: 0] += realized
        }
        for s in shareSells {
            realizedByTicker[s.ticker, default: 0] += s.realized_pl
        }

        var tickerSet = Set(companies.map(\.ticker))
        tickerSet.formUnion(realizedByTicker.keys)

        var lifetimePremiumByTicker: [String: Double] = [:]
        for t in allTrades where t.action == "open" && t.direction == "short" {
            lifetimePremiumByTicker[t.ticker, default: 0] += t.premium * t.contracts * 100
        }

        // Lifetime cost basis per ticker — Σ(qty_original × cost_per_share)
        // across every share lot ever bought, including the ones that
        // have since been fully sold (qty_remaining = 0). Drives the
        // realized ROI %.
        var lifetimeCostBasis: [String: Double] = [:]
        for lot in shareLots {
            lifetimeCostBasis[lot.ticker, default: 0] += lot.qty_original * lot.cost_per_share
        }

        return tickerSet.map { ticker -> StockPerf in
            let comp = companies.first { $0.ticker == ticker }
            let realized = realizedByTicker[ticker] ?? 0
            let unrealized = comp?.agg.unreal ?? 0
            let stockLeg = comp?.legs.first(where: { $0.kind == .stock })
            let shares = stockLeg?.qty ?? 0
            let avg = stockLeg?.avg ?? 0
            let totalPremium = lifetimePremiumByTicker[ticker] ?? 0
            let net = shares > 0 ? avg - (totalPremium / shares) : avg
            let basis = max(shares * avg, 1)
            let total = realized + unrealized
            let pct = total / basis * 100
            let hasOpenLegs = (comp?.legs.contains(where: { $0.kind != .stock }) ?? false)
            let isClosed = shares == 0 && !hasOpenLegs

            // ROI % = realized / lifetime cost basis. Nil when the
            // ticker has no share lots (pure options-only trade) —
            // no honest denominator to use.
            let lifetimeBasis = lifetimeCostBasis[ticker] ?? 0
            let roi: Double? = lifetimeBasis > 0
                ? (realized / lifetimeBasis) * 100
                : nil

            return StockPerf(
                ticker: ticker,
                realized: realized,
                unrealized: unrealized,
                pct: pct,
                realizedROI: roi,
                avgPrice: avg,
                netPrice: net,
                closed: isClosed
            )
        }
        .sorted { abs($0.value) > abs($1.value) }
    }

    // MARK: - Source-stacked chart bars (new Performance page)
    //
    // Bars carry per-source signed realized P&L for the bucket. Used by
    // the new Gains & Losses chart — render each bucket as a stacked
    // bar (positive segments grow up from zero, negatives down). Empty
    // buckets (no realized events) are SKIPPED — the bar row reads as
    // contiguous event days rather than a calendar with gaps.

    static func sourceBars(
        scope: ChartScope,
        offset: Int,
        allTrades: [OptionTradeRow],
        shareSells: [ShareSellRow],
        now: Date = Date()
    ) -> ChartDataset {
        let cal = Calendar(identifier: .gregorian)
        let (start, end) = scope.bounds(now: now, offset: offset)

        // bucketKey → date that anchors the bucket (day or month start)
        // bucketKey → [source → signed realized $]
        var buckets: [Date: [FlowSource: Double]] = [:]
        let bucketOf: (Date) -> Date = { d in
            switch scope {
            case .week, .month: return cal.startOfDay(for: d)
            case .year:
                let comps = cal.dateComponents([.year, .month], from: d)
                return cal.date(from: comps) ?? d
            }
        }

        // Closed options — realized = (open.premium - close.premium) × ct × 100 × sign.
        for c in allTrades where c.action == "close" {
            guard let d = AppDates.parseISODay(c.trade_date),
                  d >= start, d <= end,
                  let open = allTrades.first(where: { $0.id == (c.closes_trade_id ?? "") })
            else { continue }
            let sign: Double = open.direction == "short" ? 1 : -1
            let realized = (open.premium - c.premium) * c.contracts * 100 * sign
            let src: FlowSource
            switch (open.option_type, open.direction) {
            case ("call", "short"): src = .callsSold
            case ("put",  "short"): src = .putsSold
            case ("call", "long"):  src = .callsBought
            case ("put",  "long"):  src = .putsBought
            default: continue
            }
            buckets[bucketOf(d), default: [:]][src, default: 0] += realized
        }

        // Share sells — realized P&L straight from the row.
        for s in shareSells {
            guard let d = AppDates.parseISODay(s.trade_date), d >= start, d <= end else { continue }
            buckets[bucketOf(d), default: [:]][.shares, default: 0] += s.realized_pl
        }

        // Sort by date ascending, drop empty buckets, build SourceBars
        // with each bar's POSITION in the period (day-of-week/month,
        // month-of-year). The chart uses this to place bars at calendar
        // positions on a fixed x-domain — so bar width stays constant
        // regardless of how many days actually had events.
        let sortedKeys = buckets.keys.sorted()
        let bars: [SourceBar] = sortedKeys.map { date in
            SourceBar(
                id: ChartDataset.barID(scope: scope, date: date),
                position: scope.position(for: date, periodStart: start),
                label: scope.barLabel(for: date),
                sub: scope.barSub(for: date),
                date: date,
                vals: buckets[date] ?? [:]
            )
        }

        return ChartDataset(
            period: scope.periodLabel(start: start, end: end),
            bars: bars,
            maxPosition: scope.maxPosition(start: start)
        )
    }
}

// MARK: - Chart scope + bar models

/// Time scope for the new Performance chart. Each maps to a window
/// (week / month / year) and a bucket granularity (daily for W/M,
/// monthly for Y). Skips empty buckets — bar count varies with how
/// active the window was.
enum ChartScope: String, CaseIterable, Identifiable, Hashable {
    case week = "Week", month = "Month", year = "Year"
    var id: String { rawValue }

    /// Window bounds (inclusive). offset=0 = current; -1 = previous; etc.
    func bounds(now: Date, offset: Int) -> (start: Date, end: Date) {
        let eastern = TimeZone(identifier: "America/New_York") ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = eastern
        cal.firstWeekday = 2  // Monday — markets convention
        let today = cal.startOfDay(for: now)
        switch self {
        case .week:
            // Monday of (current week + offset).
            let weekday = cal.component(.weekday, from: today)
            let daysFromMon = (weekday + 5) % 7   // 0=Mon..6=Sun
            let mondayThis = cal.date(byAdding: .day, value: -daysFromMon, to: today) ?? today
            let monday = cal.date(byAdding: .weekOfYear, value: offset, to: mondayThis) ?? mondayThis
            let sunday = cal.date(byAdding: .day, value: 6, to: monday) ?? monday
            return (monday, cal.date(byAdding: .day, value: 1, to: sunday)?.addingTimeInterval(-1) ?? sunday)
        case .month:
            let comps = cal.dateComponents([.year, .month], from: today)
            let firstOfThis = cal.date(from: comps) ?? today
            let first = cal.date(byAdding: .month, value: offset, to: firstOfThis) ?? firstOfThis
            let last = cal.date(byAdding: DateComponents(month: 1, second: -1), to: first) ?? first
            return (first, last)
        case .year:
            let yr = cal.component(.year, from: today) + offset
            let first = cal.date(from: DateComponents(year: yr, month: 1, day: 1)) ?? today
            let last = cal.date(from: DateComponents(year: yr, month: 12, day: 31)) ?? today
            return (first, last)
        }
    }

    /// Short label that goes UNDER each bar on the x-axis.
    func barLabel(for date: Date) -> String {
        let df = DateFormatter()
        df.timeZone = TimeZone(identifier: "America/New_York")
        switch self {
        case .week:  df.dateFormat = "EEE"      // Mon, Tue, ...
        case .month: df.dateFormat = "d"        // 1, 12, 27
        case .year:  df.dateFormat = "MMM"      // Jan, Feb, ...
        }
        return df.string(from: date)
    }

    /// Long-form readout sub-label shown when the bar is selected.
    func barSub(for date: Date) -> String {
        let df = DateFormatter()
        df.timeZone = TimeZone(identifier: "America/New_York")
        switch self {
        case .week, .month: df.dateFormat = "EEE, MMM d"
        case .year:         df.dateFormat = "MMMM yyyy"
        }
        return df.string(from: date)
    }

    /// 1-based position of the date within the period.
    ///   Week  → 1…7   (Mon=1, Sun=7)
    ///   Month → 1…N   (day-of-month)
    ///   Year  → 1…12  (month-of-year)
    func position(for date: Date, periodStart: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        cal.firstWeekday = 2
        switch self {
        case .week:
            let days = cal.dateComponents([.day], from: periodStart, to: date).day ?? 0
            return max(1, min(7, days + 1))
        case .month:
            return cal.component(.day, from: date)
        case .year:
            return cal.component(.month, from: date)
        }
    }

    /// Fixed maximum position for this scope — drives the chart's
    /// x-domain so bar width stays constant whether 1 or 30 days fired.
    func maxPosition(start: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        switch self {
        case .week:  return 7
        case .month:
            // Days in the *current* month, for accurate axis spacing.
            return cal.range(of: .day, in: .month, for: start)?.count ?? 31
        case .year:  return 12
        }
    }

    /// "May 8 – 14, 2026" / "April 2026" / "2026" — shown above chart.
    func periodLabel(start: Date, end: Date) -> String {
        let df = DateFormatter()
        df.timeZone = TimeZone(identifier: "America/New_York")
        switch self {
        case .week:
            df.dateFormat = "MMM d"
            let yf = DateFormatter(); yf.dateFormat = "yyyy"
            yf.timeZone = df.timeZone
            let s = df.string(from: start)
            df.dateFormat = "d, yyyy"
            return "\(s) – \(df.string(from: end))"
        case .month:
            df.dateFormat = "MMMM yyyy"
            return df.string(from: start)
        case .year:
            df.dateFormat = "yyyy"
            return df.string(from: start)
        }
    }
}

/// One stacked bar in the diverging chart. `vals` carries the signed
/// realized P&L per source; positive sum = green stack growing up,
/// negative sum = red stack growing down.
struct SourceBar: Identifiable, Hashable {
    let id: String
    /// 1-based position within the period (day-of-week / day-of-month
    /// / month-of-year). Drives the x-axis placement so bars sit at
    /// their actual calendar slots and bar width stays constant
    /// regardless of how many days had events.
    let position: Int
    let label: String
    let sub: String
    let date: Date
    var vals: [FlowSource: Double]

    /// Sum of positive contributions (ignoring filtered-out sources).
    func gain(active: Set<FlowSource>) -> Double {
        vals.filter { active.contains($0.key) && $0.value > 0 }.reduce(0) { $0 + $1.value }
    }
    /// Sum of negative contributions (returned as a negative number).
    func loss(active: Set<FlowSource>) -> Double {
        vals.filter { active.contains($0.key) && $0.value < 0 }.reduce(0) { $0 + $1.value }
    }
    func net(active: Set<FlowSource>) -> Double { gain(active: active) + loss(active: active) }
}

struct ChartDataset: Hashable {
    let period: String     // "April 2026" — shown in the period nav row
    let bars: [SourceBar]
    /// Max x-axis position for this scope (7 / 28-31 / 12). Drives the
    /// fixed x-domain so empty days/months reserve their slots.
    let maxPosition: Int

    static func barID(scope: ChartScope, date: Date) -> String {
        let df = DateFormatter()
        df.timeZone = TimeZone(identifier: "America/New_York")
        df.dateFormat = "yyyy-MM-dd"
        return "\(scope.rawValue)-\(df.string(from: date))"
    }
}
