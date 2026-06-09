//
//  PortfolioStore.swift
//  Sunnyfi
//
//  @Observable store that fetches the 5 source tables in parallel and
//  joins them into `[Company]` + a `PortfolioRollup` for the UI. Swift
//  port of `useMasterPositions.ts` + a slim version of `buildCompanies.ts`.
//
//  The slim port covers what the Hello Portfolio screen needs:
//  per-leg Greeks signed by side, per-company aggregate, portfolio rollup
//  (including β·Δ). We'll grow it in Phase 4 as the Company screen needs
//  more fields (flags, IV history, etc.).
//

import Foundation
import Supabase

@MainActor
@Observable
final class PortfolioStore {
    // Outputs
    var companies: [Company] = []
    var closedCompanies: [Company] = []
    var portfolio: PortfolioRollup = .empty
    var freshness: Date?
    var isLoading: Bool = true
    var isRefreshing: Bool = false
    var error: String?
    /// True if the most recent refresh() attempt threw. Cleared on
    /// every new refresh attempt. Separate from `error` (which is a
    /// broader "something went wrong including partial-data") so the
    /// SyncIndicator can light up the stale state precisely on real
    /// refresh failures.
    var lastRefreshError: String?

    // Raw rows kept around so Trades / Performance / event-card derivers
    // don't need to re-fetch. Set inside fetchAll() before the join.
    var allTrades: [OptionTradeRow] = []
    var allShareSells: [ShareSellRow] = []
    var allGreeks: [OptionGreeksRow] = []
    var dailyCloses: [DailyCloseRow] = []
    var allShareLots: [ShareLotRow] = []
    /// History from the daily-theta-snapshot cron. Sorted oldest → newest.
    /// Powers the Hedge tab's Δ-vs-yesterday, sparkline, and prior-week strip.
    var dailyTheta: [DailyThetaSnapshotRow] = []
    /// Active rows from the health-monitor cron. Drives the global
    /// "something is broken" banner.
    var activeAlerts: [SystemAlertRow] = []
    /// Upcoming + recent macro events (FOMC, CPI, holidays) — drives
    /// the Today screen's Events bucket.
    var allMacroEvents: [MacroEventRow] = []
    /// Upcoming earnings for positions + sector peers — drives the
    /// Today screen's Earnings bucket.
    var allEarningsEvents: [EarningsEventRow] = []
    /// Per-ticker IV roll-ups from the `ticker_iv_summary` view —
    /// drives the new Seller Score IV section on the Today screen.
    var allIvSummaries: [TickerIVRow] = []
    /// True if the last fetchAll() returned CancellationError on every
    /// child task — signals a transient view-lifecycle race so load()
    /// retries once on a detached task. Internal to the store.
    private(set) var lastRunWasAllCancelled: Bool = false

    private let client = SupabaseService.client

    // MARK: - Public API

    /// Initial load — runs all 10 queries in parallel, then joins.
    /// If every fetch was cancelled (almost always a view-lifecycle
    /// race, never a real failure), we retry once on a detached task
    /// to escape whatever cancelled us.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        await fetchAll()
        if lastRunWasAllCancelled {
            // Unstructured detached task — survives view re-renders
            // and scene-phase blips. Bounded by the app's lifetime.
            _ = await Task.detached { @MainActor [weak self] in
                await self?.fetchAll()
            }.value
        }
    }

    /// Lightweight poll — re-fetches only `ticker_iv_summary` so new
    /// daily IV snapshots show up in the app without a full pull-to-
    /// refresh. Source updates once a day after market close (20:15
    /// UTC weekdays) so this is checked on a slower cadence than
    /// alerts. Mirrors refreshAlertsOnly's silent-failure pattern.
    func refreshIvSummariesOnly() async {
        let result = await Self.tryFetch {
            try await client.from("ticker_iv_summary")
                .select("ticker, current_iv, current_hv30, iv_low, iv_high, iv_window_days, last_snapshot_date, window_start")
                .execute().value as [TickerIVRow]
        }
        if case .success(let rows) = result {
            // Preserve the DEBUG mock fallback only when the real
            // view comes back empty — same rule as fetchAll().
            #if DEBUG
            if rows.isEmpty {
                if self.allIvSummaries.isEmpty {
                    self.allIvSummaries = IVMockData.rows
                }
            } else {
                self.allIvSummaries = rows
            }
            #else
            self.allIvSummaries = rows
            #endif
        }
    }

    /// Lightweight poll — re-fetches only `system_alerts` (the tiny
    /// banner-source table) without touching any of the other 10
    /// queries in fetchAll(). Used by AlertPoller so cleared alerts
    /// disappear from the app without a full pull-to-refresh.
    func refreshAlertsOnly() async {
        let result = await Self.tryFetch {
            try await client.from("system_alerts")
                .select("id, code, severity, title, detail, created_at, resolved_at")
                .is("resolved_at", value: nil)
                .order("created_at", ascending: false)
                .execute().value as [SystemAlertRow]
        }
        if case .success(let alerts) = result {
            self.activeAlerts = alerts
        }
        // Failures are silent — we'll catch them on the next poll or
        // on the next fetchAll(). No UI surfacing for this background loop.
    }

    /// Pull-to-refresh — invokes the mp-refresh edge function, then re-fetches.
    func refresh() async {
        isRefreshing = true
        lastRefreshError = nil       // clear at the start of every attempt
        defer { isRefreshing = false }
        do {
            _ = try await client.functions.invoke(
                "mp-refresh",
                options: FunctionInvokeOptions(body: [String: String]())
            )
        } catch {
            // Refresh failure isn't fatal — we'll just re-render with whatever
            // data is already in the tables. But the SyncIndicator reads
            // lastRefreshError to flip to the stale visual.
            lastRefreshError = error.localizedDescription
            self.error = "Refresh failed: \(error.localizedDescription)"
        }
        await fetchAll()
    }

    // MARK: - Fetch + join

    func fetchAll() async {
        // All 10 queries fire in parallel. Each is wrapped in its own
        // Result so a single table failing doesn't take the whole load
        // down — we surface partial-data state via `self.error`.
        let c = client

        async let pTask  = Self.tryFetch { try await c.from("positions")
            .select("ticker, name, sector, quantity, avg_cost, current_price, prev_close, status, earnings_date, realized_stock_pl")
            .execute().value as [PositionRow] }
        async let tTask  = Self.tryFetch { try await c.from("option_trades")
            .select("id, ticker, trade_date, action, option_type, direction, contracts, strike, premium, expiry, closes_trade_id, source, ibkr_trade_id, last_synced_at, voided_at")
            .is("voided_at", value: nil)
            .execute().value as [OptionTradeRow] }
        async let gTask  = Self.tryFetch { try await c.from("option_greeks_latest")
            .select("option_trade_id, delta, gamma, theta, vega, iv, open_interest, volume, last_mark, captured_at")
            .execute().value as [OptionGreeksRow] }
        async let qTask  = Self.tryFetch { try await c.from("ticker_quotes_latest")
            .select("ticker, spot, day_change_pct, beta, captured_at")
            .execute().value as [TickerQuoteRow] }
        async let sTask  = Self.tryFetch { try await c.from("share_sells")
            .select("ticker, realized_pl, trade_date")
            .execute().value as [ShareSellRow] }
        async let oTask  = Self.tryFetch { try await c.from("strategy_overlay")
            .select("ticker, bucket")
            .execute().value as [StrategyOverlayRow] }
        async let dcTask = Self.tryFetch { try await c.from("daily_closes")
            .select("ticker, date, close_price")
            .order("date", ascending: false)
            .limit(2000)
            .execute().value as [DailyCloseRow] }
        async let slTask = Self.tryFetch { try await c.from("share_lots")
            .select("id, ticker, acquired_date, fifo_order, qty_original, qty_remaining, cost_per_share, source, linked_assignment_id, ibkr_trade_id, last_synced_at, voided_at")
            .is("voided_at", value: nil)
            .gt("qty_remaining", value: 0)
            .order("acquired_date", ascending: true)
            .order("fifo_order", ascending: true)
            .execute().value as [ShareLotRow] }
        // Last 60 daily theta snapshots — plenty for a 14-day sparkline
        // plus 4 weeks of prior-week aggregation, with headroom for
        // gaps (holidays, missed cron runs).
        async let dtsTask = Self.tryFetch { try await c.from("daily_theta_snapshot")
            .select("snapshot_date, total_burn, long_put_count, per_ticker")
            .order("snapshot_date", ascending: false)
            .limit(60)
            .execute().value as [DailyThetaSnapshotRow] }
        // Active alerts from the health-monitor cron — drives the global banner.
        async let alertsTask = Self.tryFetch { try await c.from("system_alerts")
            .select("id, code, severity, title, detail, created_at, resolved_at")
            .is("resolved_at", value: nil)
            .order("created_at", ascending: false)
            .execute().value as [SystemAlertRow] }
        // Macro events for the Today screen — drives the Events bucket.
        // Pull a generous window so v1 ranking has options to pick from
        // (next 90 days). The query is cheap (few dozen rows).
        async let meTask = Self.tryFetch { try await c.from("macro_events")
            .select("id, event_date, event_time, country, name, category, importance, forecast, previous, actual, is_holiday, early_close, summary")
            .gte("event_date", value: Self.isoDateToday())
            .lte("event_date", value: Self.isoDate(daysFromNow: 90))
            .order("event_date", ascending: true)
            .execute().value as [MacroEventRow] }
        // Earnings events for the Today screen — drives the Earnings bucket.
        async let eeTask = Self.tryFetch { try await c.from("earnings_events")
            .select("id, ticker, company_name, report_date, report_time, eps_forecast, revenue_forecast, market_cap, scope_tag, peer_of_tickers, sector_etf")
            .gte("report_date", value: Self.isoDateToday())
            .lte("report_date", value: Self.isoDate(daysFromNow: 60))
            .order("report_date", ascending: true)
            .execute().value as [EarningsEventRow] }
        // Per-ticker IV roll-up — current/low/high/window from the
        // `ticker_iv_summary` view. Drives the new Seller Score IV
        // section. Empty result is fine if no snapshots yet (the
        // daily cron will populate over time).
        async let ivSumTask = Self.tryFetch { try await c.from("ticker_iv_summary")
            .select("ticker, current_iv, current_hv30, iv_low, iv_high, iv_window_days, last_snapshot_date, window_start")
            .execute().value as [TickerIVRow] }

        let p   = await pTask
        let t   = await tTask
        let g   = await gTask
        let q   = await qTask
        let s   = await sTask
        let o   = await oTask
        let dc  = await dcTask
        let sl  = await slTask
        let dts = await dtsTask
        let alerts = await alertsTask
        let me  = await meTask
        let ee  = await eeTask
        let ivs = await ivSumTask

        // Collect any errors so the UI can surface the failed-table list.
        var errs: [String] = []
        func unwrap<T>(_ r: Result<T, Error>, _ label: String, default fallback: T) -> T {
            switch r {
            case .success(let v): return v
            case .failure(let e):
                errs.append("\(label): \(e.localizedDescription)")
                return fallback
            }
        }
        let positions = unwrap(p,   "positions",            default: [])
        let trades    = unwrap(t,   "option_trades",        default: [])
        let greeks    = unwrap(g,   "option_greeks_latest", default: [])
        let quotes    = unwrap(q,   "ticker_quotes_latest", default: [])
        let sells     = unwrap(s,   "share_sells",          default: [])
        let overlay   = unwrap(o,   "strategy_overlay",     default: [])
        let closes    = unwrap(dc,  "daily_closes",         default: [])
        let lots      = unwrap(sl,  "share_lots",           default: [])
        let theta     = unwrap(dts, "daily_theta_snapshot", default: [])
        let liveAlerts = unwrap(alerts, "system_alerts",    default: [])
        let macroEvents = unwrap(me, "macro_events",        default: [])
        let earningsEvents = unwrap(ee, "earnings_events",  default: [])
        let ivSummaries = unwrap(ivs, "ticker_iv_summary",  default: [])

        // Filter cancellations — they're internal SwiftUI lifecycle
        // mechanics, never something the user can act on. If those
        // are the *only* errors we'd otherwise show, hide them; the
        // retry in load() picks up the real data.
        let cancellations = errs.filter {  $0.contains("CancellationError") }.count
        let actionable    = errs.filter { !$0.contains("CancellationError") }
        self.error = actionable.isEmpty ? nil : actionable.joined(separator: "\n\n")
        // Stash whether THIS run was a total cancellation cascade so
        // load() can decide to retry.
        let allCancelled = (cancellations == errs.count) && cancellations > 0
        self.lastRunWasAllCancelled = allCancelled

        // Don't wipe existing good data when this fetch was a total
        // cancellation cascade — load()'s detached retry will land
        // real data on the next call. Without this guard, a transient
        // view-lifecycle blip flashed the UI to "$0 / no sync yet"
        // for a few seconds (the user's repeated complaint).
        if allCancelled && !self.companies.isEmpty {
            return
        }

        // Stronger guard for non-cancellation errors: if the critical
        // tables (positions, option_trades, greeks, quotes) ALL came
        // back empty AND we hit at least one error, the fetch is
        // effectively useless — keep what we had. This covers transient
        // network failures where everything 5xx'd or timed out.
        let fetchedAnyCritical =
            !positions.isEmpty || !trades.isEmpty
            || !greeks.isEmpty || !quotes.isEmpty
        if !fetchedAnyCritical && !errs.isEmpty && !self.companies.isEmpty {
            return
        }

        self.allTrades = trades
        self.allShareSells = sells
        self.allGreeks = greeks
        self.dailyCloses = closes
        self.allShareLots = lots
        // Server returns newest → oldest; flip so [0] is the earliest
        // and the sparkline/history utilities can walk forward.
        self.dailyTheta = theta.reversed()
        self.activeAlerts = liveAlerts
        self.allMacroEvents = macroEvents
        self.allEarningsEvents = earningsEvents
        // TEMPORARY: fall back to mock IV rows so the IV section can
        // be designed/audited before the daily ticker-iv-snapshot
        // cron has populated real data. Remove this fallback once
        // ticker_iv_summary returns rows.
        #if DEBUG
        self.allIvSummaries = ivSummaries.isEmpty ? IVMockData.rows : ivSummaries
        #else
        self.allIvSummaries = ivSummaries
        #endif

        let built = Self.buildCompanies(
            positions: positions, trades: trades, greeks: greeks,
            quotes: quotes, shareSells: sells, overlay: overlay
        )
        self.companies = built.open
        self.closedCompanies = built.closed
        self.portfolio = Self.buildPortfolio(built.open)
        // Only overwrite the freshness timestamp when we actually
        // received fresh greeks/quotes — otherwise we'd reset it to
        // nil ("no sync yet") on a partial-data fetch.
        if let newFreshness = Self.latestCapture(greeks: greeks, quotes: quotes) {
            self.freshness = newFreshness
        }
    }

    // MARK: - Per-query helper

    /// Try the fetch; on failure append a labelled, type-rich error to
    /// `errs` and return an empty array. Using `String(describing:)`
    /// instead of `.localizedDescription` so wrapped errors (URLError,
    /// PostgrestError, etc.) show their real type — `localizedDescription`
    /// flattens them to a meaningless "The operation couldn't be completed."
    private static func fetch<T>(
        _ name: String,
        into errs: inout [String],
        _ body: () async throws -> [T]
    ) async -> [T] where T: Decodable {
        do {
            return try await body()
        } catch {
            let detail = String(describing: error)
            let line = "[\(name)] \(detail)"
            print("[PortfolioStore] \(line)")
            errs.append(line)
            return []
        }
    }

    /// Concurrent-safe variant: returns `Result` so we can run many
    /// fetches in parallel via `async let` and collect errors afterwards
    /// without sharing a mutable `inout errs` across tasks (which
    /// the old `fetch(...)` couldn't do safely under Swift concurrency).
    private static func tryFetch<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async -> Result<T, Error> {
        do {
            return .success(try await body())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Pure join (no IO)

    /// Slim port of src/portfolio/buildCompanies.ts — enough for the
    /// portfolio Greeks + per-company aggregate. Full flag computation
    /// lands in Phase 4 when the Company screen needs it.
    private static func buildCompanies(
        positions: [PositionRow],
        trades: [OptionTradeRow],
        greeks: [OptionGreeksRow],
        quotes: [TickerQuoteRow],
        shareSells: [ShareSellRow],
        overlay: [StrategyOverlayRow]
    ) -> (open: [Company], closed: [Company]) {

        let strategyByTicker: [String: Strategy] = Dictionary(uniqueKeysWithValues:
            overlay.map { ($0.ticker.uppercased(), Self.mapStrategy($0.bucket)) }
        )
        let greeksByTradeID: [String: OptionGreeksRow] = Dictionary(uniqueKeysWithValues:
            greeks.map { ($0.option_trade_id, $0) }
        )
        let quoteByTicker: [String: TickerQuoteRow] = Dictionary(uniqueKeysWithValues:
            quotes.map { ($0.ticker.uppercased(), $0) }
        )

        // Realized P&L per ticker — share sells + closed-option premium roll-ups.
        // For the smoke test we only need the share-sell side; option realization
        // lands when we port the full join in Phase 4.
        var realizedByTicker: [String: Double] = [:]
        for s in shareSells {
            realizedByTicker[s.ticker.uppercased(), default: 0] += s.realized_pl
        }

        var open: [Company] = []
        var closed: [Company] = []

        // Group trades by ticker — only "open" actions form live legs.
        let openLegsByTicker = Dictionary(grouping: trades.filter { $0.action == "open" && $0.closes_trade_id == nil }) {
            $0.ticker.uppercased()
        }

        // Universe = every ticker that appears in positions OR has open option trades.
        var universe = Set(positions.map { $0.ticker.uppercased() })
        universe.formUnion(openLegsByTicker.keys)

        for ticker in universe {
            let pos = positions.first { $0.ticker.uppercased() == ticker }
            let quote = quoteByTicker[ticker]
            let spot = quote?.spot ?? pos?.current_price ?? 0
            let beta = quote?.beta ?? 1.0
            let dayPct = quote?.day_change_pct ?? 0

            var legs: [Leg] = []

            // Stock leg (if shares > 0)
            if let pos, pos.quantity != 0, pos.status == "open" {
                let last = spot > 0 ? spot : pos.current_price ?? pos.avg_cost
                let unreal = (last - pos.avg_cost) * pos.quantity
                legs.append(Leg(
                    kind: .stock, side: nil, qty: pos.quantity,
                    avg: pos.avg_cost, last: last,
                    unreal: unreal, real: pos.realized_stock_pl ?? 0,
                    delta: pos.quantity, gamma: 0, theta: 0, vega: 0,
                    strike: nil, expiry: nil, dte: nil, iv: nil, oi: nil
                ))
            }

            // Sum of contracts already closed per open id (for partial-close support).
            var closedByOpenId: [String: Double] = [:]
            for tr in trades where tr.action == "close" {
                if let oid = tr.closes_trade_id {
                    closedByOpenId[oid, default: 0] += tr.contracts
                }
            }

            // Option legs — apply contract × 100 multiplier + sign by direction.
            // Effective contracts = open.contracts − already-closed; if 0, skip.
            for trade in openLegsByTicker[ticker] ?? [] {
                let closedSoFar = closedByOpenId[trade.id] ?? 0
                let active = max(0, trade.contracts - closedSoFar)
                if active <= 0 { continue }

                let g = greeksByTradeID[trade.id]
                let side: LegSide = trade.direction == "long" ? .long : .short
                let sign: Double = side == .short ? -1 : 1
                let multiplier = active * 100 * sign
                let mark = g?.last_mark ?? trade.premium
                let qty = active * sign
                let unreal = (mark - trade.premium) * active * 100 * (side == .long ? 1 : -1)

                legs.append(Leg(
                    kind: trade.option_type == "call" ? .call : .put,
                    side: side,
                    qty: qty,
                    avg: trade.premium,
                    last: mark,
                    unreal: unreal,
                    real: 0,
                    delta: (g?.delta ?? 0) * multiplier,
                    gamma: (g?.gamma ?? 0) * multiplier,
                    theta: (g?.theta ?? 0) * multiplier * -1,   // theta convention
                    vega:  (g?.vega  ?? 0) * multiplier,
                    strike: trade.strike,
                    expiry: trade.expiry,
                    dte: Self.daysUntil(trade.expiry),
                    iv: g?.iv,
                    oi: g?.open_interest
                ))
            }

            // Per-company aggregate
            var agg = Aggregate()
            for l in legs {
                agg.delta  += l.delta
                agg.gamma  += l.gamma
                agg.theta  += l.theta
                agg.vega   += l.vega
                agg.unreal += l.unreal
                agg.real   += l.real
                // Market value of the leg, signed so short legs subtract
                // (they're liabilities — money owed to close).
                // • Stock: qty × spot
                // • Option: qty × mark × 100 (qty is already signed by
                //   direction, so short call/put automatically goes negative)
                switch l.kind {
                case .stock:        agg.mv += l.qty * l.last
                case .call, .put:   agg.mv += l.qty * l.last * 100
                }
            }
            agg.real += realizedByTicker[ticker] ?? 0

            let strategy = strategyByTicker[ticker] ?? .investment
            let isClosed = (pos?.status == "closed") || (legs.isEmpty && (pos?.quantity ?? 0) == 0)

            let company = Company(
                ticker: ticker,
                name: pos?.name ?? ticker,
                sector: pos?.sector ?? "—",
                strategy: strategy,
                spot: spot,
                dayPct: dayPct,
                beta: beta,
                earningsDate: pos?.earnings_date,
                legs: legs,
                agg: agg,
                closed: isClosed
            )
            if isClosed { closed.append(company) } else { open.append(company) }
        }

        // Sort by ticker for stable display
        open.sort   { $0.ticker < $1.ticker }
        closed.sort { $0.ticker < $1.ticker }
        return (open, closed)
    }

    private static func buildPortfolio(_ companies: [Company]) -> PortfolioRollup {
        var p = PortfolioRollup()
        for c in companies {
            p.delta  += c.agg.delta
            p.gamma  += c.agg.gamma
            p.theta  += c.agg.theta
            p.vega   += c.agg.vega
            p.unreal += c.agg.unreal
            p.real   += c.agg.real
            p.mv     += c.agg.mv
            p.betaWeightedDelta += c.agg.delta * c.beta
            p.openCount += 1
            p.optionLegCount += c.legs.filter { $0.kind != .stock }.count
        }
        return p
    }

    // MARK: - Helpers

    private static func mapStrategy(_ bucket: String) -> Strategy {
        switch bucket {
        case "income":  return .income
        case "invest":  return .investment
        case "yield":   return .yield
        default:        return .investment
        }
    }

    private static func daysUntil(_ iso: String) -> Int? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")
        guard let target = df.date(from: iso) else { return nil }
        let now = Calendar.current.startOfDay(for: Date())
        let comps = Calendar.current.dateComponents([.day], from: now, to: target)
        return comps.day
    }

    /// "YYYY-MM-DD" for today in America/New_York. Used to bound
    /// macro_events / earnings_events fetches to upcoming-only.
    static func isoDateToday() -> String {
        let df = DateFormatter()
        df.timeZone = TimeZone(identifier: "America/New_York")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }

    /// "YYYY-MM-DD" for N calendar days from now in America/New_York.
    static func isoDate(daysFromNow: Int) -> String {
        let df = DateFormatter()
        df.timeZone = TimeZone(identifier: "America/New_York")
        df.dateFormat = "yyyy-MM-dd"
        let d = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
        return df.string(from: d)
    }

    private static func latestCapture(greeks: [OptionGreeksRow], quotes: [TickerQuoteRow]) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]

        let strings = greeks.compactMap(\.captured_at) + quotes.compactMap(\.captured_at)
        let dates = strings.compactMap { s -> Date? in
            iso.date(from: s) ?? fallback.date(from: s)
        }
        return dates.max()
    }
}
