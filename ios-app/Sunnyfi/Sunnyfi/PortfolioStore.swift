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

    private let client = SupabaseService.client

    // MARK: - Public API

    /// Initial load — runs all 6 queries in parallel, then joins.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        await fetchAll()
    }

    /// Pull-to-refresh — invokes the mp-refresh edge function, then re-fetches.
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            _ = try await client.functions.invoke(
                "mp-refresh",
                options: FunctionInvokeOptions(body: [String: String]())
            )
        } catch {
            // Refresh failure isn't fatal — we'll just re-render with whatever
            // data is already in the tables.
            self.error = "Refresh failed: \(error.localizedDescription)"
        }
        await fetchAll()
    }

    // MARK: - Fetch + join

    private func fetchAll() async {
        // Sequential for now — keeps cancellation behaviour simple and lets
        // us see exactly which query fails first. Six round-trips × ~100ms
        // is fine for the smoke test; we'll parallelize in Phase 4.
        let c = client
        var errs: [String] = []

        let p: [PositionRow] = await Self.fetch("positions", into: &errs) {
            try await c.from("positions")
                .select("ticker, name, sector, quantity, avg_cost, current_price, prev_close, status, earnings_date, realized_stock_pl")
                .execute().value
        }
        let t: [OptionTradeRow] = await Self.fetch("option_trades", into: &errs) {
            try await c.from("option_trades")
                .select("id, ticker, trade_date, action, option_type, direction, contracts, strike, premium, expiry, closes_trade_id")
                .execute().value
        }
        let g: [OptionGreeksRow] = await Self.fetch("option_greeks", into: &errs) {
            try await c.from("option_greeks")
                .select("option_trade_id, delta, gamma, theta, vega, iv, open_interest, volume, last_mark, captured_at")
                .execute().value
        }
        let q: [TickerQuoteRow] = await Self.fetch("ticker_quotes", into: &errs) {
            try await c.from("ticker_quotes")
                .select("ticker, spot, day_change_pct, beta, captured_at")
                .execute().value
        }
        let s: [ShareSellRow] = await Self.fetch("share_sells", into: &errs) {
            try await c.from("share_sells")
                .select("ticker, realized_pl, trade_date")
                .execute().value
        }
        let o: [StrategyOverlayRow] = await Self.fetch("strategy_overlay", into: &errs) {
            try await c.from("strategy_overlay")
                .select("ticker, bucket")
                .execute().value
        }

        if !errs.isEmpty {
            self.error = errs.joined(separator: "\n\n")
        } else {
            self.error = nil
        }

        let built = Self.buildCompanies(
            positions: p, trades: t, greeks: g,
            quotes: q, shareSells: s, overlay: o
        )
        self.companies = built.open
        self.closedCompanies = built.closed
        self.portfolio = Self.buildPortfolio(built.open)
        self.freshness = Self.latestCapture(greeks: g, quotes: q)
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

            // Option legs — apply contract × 100 multiplier + sign by direction
            for trade in openLegsByTicker[ticker] ?? [] {
                let g = greeksByTradeID[trade.id]
                let side: LegSide = trade.direction == "long" ? .long : .short
                let sign: Double = side == .short ? -1 : 1
                let multiplier = trade.contracts * 100 * sign
                let mark = g?.last_mark ?? trade.premium
                let qty = trade.contracts * sign
                let unreal = (mark - trade.premium) * trade.contracts * 100 * (side == .long ? 1 : -1)

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
                if l.kind == .stock { agg.mv += l.qty * l.last }
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
