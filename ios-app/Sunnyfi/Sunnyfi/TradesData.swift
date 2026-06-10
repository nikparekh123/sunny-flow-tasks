//
//  TradesData.swift
//  Sunnyfi
//
//  Derived data for the Positions screen. After the Handoff 2
//  rewrite, this file is intentionally lean: one struct
//  (TickerSummary) + one enum (TradesData) with three static
//  aggregators. The earlier helpers for the now-deleted swipe rail
//  / radar feed / risk badges were removed in the same pass that
//  retired their UI.
//

import Foundation
import SwiftUI

// MARK: - TickerSummary

/// Derived view of a ticker for the unified Positions card. Pulls
/// open option legs + the share leg (if held) and pre-computes the
/// per-card aggregates the UI reads off.
struct TickerSummary: Identifiable {
    var id: String { ticker }
    let ticker: String
    let name: String
    let sector: String
    let spot: Double
    let dayPct: Double
    let strategyLabel: String     // "Income" / "Investment" / "Yield"

    let openLegs: [OptionTradeRow]
    let shareLeg: Leg?            // nil = options-only

    // ── Greeks-band cells ──
    /// Signed Σ Δ across all legs (shares contribute +qty).
    let netDelta: Double
    /// Signed Σ θ across open option legs — short legs collect,
    /// long legs pay (per the dirMul convention).
    let theta: Double
    /// Σ short-side credits collected on open option legs (any
    /// kind, not just calls — drives the Premium cell).
    let premium: Double
    /// Unrealized total across all open legs (sum of each option
    /// leg's signed P&L + the stock leg's unrealized). Equals the
    /// arithmetic sum of every "Total return" row on the card —
    /// the hero is intentionally reconcilable from the visible
    /// rows. Past realized P&L is NOT included here (lives in
    /// Activity).
    let netPnL: Double

    // ── Calls-sold / covered % piece of the greeks band ──
    /// Shares held (0 if options-only).
    let shares: Double
    /// Σ remaining contracts across SHORT-CALL legs.
    let callCt: Int
    /// Σ remaining × avg fill × 100 on short-call legs — collected
    /// credit at the time the calls were sold.
    let callCredit: Double
    /// Σ remaining × current mark × 100 on short-call legs — cost
    /// to buy them back today. Drives the portfolio "($N now)" stat.
    let callValue: Double
    /// `(callCt × 100) / shares × 100`, clamped 100. Shown as the
    /// `N% covered` sub on the Calls sold cell.
    let coveredPct: Int

    // ── Today's & total return helpers for the share leg ──
    /// Σ today-only $ across all legs (delta-implied price move +
    /// theta decay). Carried for compatibility; the per-leg today
    /// figures are recomputed inside the views from raw greeks.
    let todayPnL: Double
    /// Stock-leg market value (qty × last). Zero when no shares.
    let stockMV: Double
}

// MARK: - Aggregators

enum TradesData {

    /// Build one TickerSummary per held ticker (open option legs OR
    /// share position). Sorted by absolute net P&L desc.
    static func buildSummaries(store: PortfolioStore) -> [TickerSummary] {
        let companies = store.companies
        let allGreeks = store.allGreeks

        let openTrades: [OptionTradeRow] = store.allTrades.filter {
            $0.action == "open" && store.remainingContracts(for: $0) > 0
        }
        let openByTicker = Dictionary(grouping: openTrades, by: \.ticker)

        var seen = Set<String>()
        var result: [TickerSummary] = []
        for c in companies {
            let openLegs = openByTicker[c.ticker] ?? []
            let stockLeg = c.legs.first(where: { $0.kind == .stock && $0.qty > 0 })
            if openLegs.isEmpty && stockLeg == nil { continue }
            if seen.contains(c.ticker) { continue }
            seen.insert(c.ticker)

            // ── Greek totals + today's P&L ──
            var netDelta = stockLeg?.qty ?? 0
            var theta = 0.0
            var premium = 0.0
            var unrealEst = 0.0
            var todayPnL = 0.0
            let dayFrac = c.dayPct / 100.0

            for t in openLegs {
                let remaining = store.remainingContracts(for: t)
                // dirMul for GREEKS: short flips the holder's
                // exposure, so the position's delta/theta is the
                // negative of the contract's per-share rate.
                let greekMul: Double = t.direction == "short" ? -1 : 1
                // dirMul for P&L: opposite convention. A short
                // profits when mark drops (entry > mark → positive);
                // a long profits when mark rises (mark > entry).
                //   short: (entry - mark) × ct × 100
                //   long:  (mark - entry) × ct × 100
                // Per-leg view in OptionLegView uses this same
                // convention. The aggregator was inverted, which
                // double-subtracted every profitable option from
                // the hero P&L on tickers like LULU.
                let pnlMul: Double = t.direction == "short" ? 1 : -1
                if let g = allGreeks.first(where: { $0.option_trade_id == t.id }) {
                    if let d = g.delta {
                        let signedDelta = d * greekMul * remaining * 100
                        netDelta += signedDelta
                        todayPnL += signedDelta * c.spot * dayFrac
                    }
                    if let th = g.theta {
                        let signedTheta = th * greekMul * remaining * 100
                        theta += signedTheta
                        todayPnL += signedTheta
                    }
                    if let mark = g.last_mark {
                        unrealEst += (t.premium - mark) * pnlMul * remaining * 100
                    }
                }
                if t.direction == "short" {
                    premium += t.premium * remaining * 100
                }
            }
            if let s = stockLeg {
                unrealEst += s.unreal
                // Realized stock P&L is intentionally OMITTED here.
                // The hero now equals Σ (each leg's Total return) so
                // the number on the card head is visually
                // reconcilable: scrolling the legs and adding the
                // Total return rows gives back the hero. Lifetime
                // realized lives in the Activity tab; including it
                // here would surface a number not shown elsewhere on
                // the card.
                todayPnL += s.qty * c.spot * dayFrac
            }

            // ── Covered-call coverage + open-call-credit pieces ──
            let shortCallLegs = openLegs.filter {
                $0.option_type == "call" && $0.direction == "short"
            }
            let callCtD = shortCallLegs.reduce(0.0) { sum, t in
                sum + store.remainingContracts(for: t)
            }
            let callCt = Int(callCtD.rounded())
            let callCredit = shortCallLegs.reduce(0.0) { sum, t in
                sum + store.remainingContracts(for: t) * t.premium * 100
            }
            let callValue = shortCallLegs.reduce(0.0) { sum, t in
                let mark = allGreeks.first(where: { $0.option_trade_id == t.id })?.last_mark ?? t.premium
                return sum + store.remainingContracts(for: t) * mark * 100
            }
            let sharesHeld = stockLeg?.qty ?? 0
            let coveredPct: Int = sharesHeld > 0
                ? min(100, Int(((callCtD * 100.0 / sharesHeld) * 100.0).rounded()))
                : 0
            let stockMV: Double = (stockLeg?.qty ?? 0) * (stockLeg?.last ?? 0)

            // Prefer the live Company.name; fall back to the static
            // map when the field is blank or equals the ticker
            // (avoids "HOOD / HOOD" duplication).
            let displayName: String = {
                let n = c.name.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty && n.uppercased() != c.ticker.uppercased() { return n }
                return TickerNames.name(for: c.ticker) ?? c.ticker
            }()
            result.append(TickerSummary(
                ticker: c.ticker,
                name: displayName,
                sector: c.sector,
                spot: c.spot,
                dayPct: c.dayPct,
                strategyLabel: c.strategy.rawValue,
                openLegs: openLegs.sorted {
                    (AppDates.daysUntil($0.expiry) ?? 999) < (AppDates.daysUntil($1.expiry) ?? 999)
                },
                shareLeg: stockLeg,
                netDelta: netDelta,
                theta: theta,
                premium: premium,
                netPnL: unrealEst,
                shares: sharesHeld,
                callCt: callCt,
                callCredit: callCredit,
                callValue: callValue,
                coveredPct: coveredPct,
                todayPnL: todayPnL,
                stockMV: stockMV
            ))
        }
        result.sort { abs($0.netPnL) > abs($1.netPnL) }
        return result
    }

    /// Portfolio-level "Open call credit" — Σ remaining × avg fill ×
    /// 100 over every open short-call position. Drives the OPEN
    /// CALL CREDIT stat in the compact header AND the Collected row
    /// on the OpenCallCard.
    static func openCallCredit(store: PortfolioStore) -> Double {
        store.allTrades
            .filter {
                $0.action == "open"
                    && $0.option_type == "call"
                    && $0.direction == "short"
                    && store.remainingContracts(for: $0) > 0
            }
            .reduce(0) { sum, t in
                sum + store.remainingContracts(for: t) * t.premium * 100
            }
    }

    /// Current cost-to-close all open short-call positions — Σ
    /// remaining × last_mark × 100. Drives the Value-now row on the
    /// OpenCallCard. Falls back to entry premium on cold-cache so
    /// the figure never reads as $0 due to a missing greek.
    static func openCallCreditNow(store: PortfolioStore) -> Double {
        let greeks = store.allGreeks
        return store.allTrades
            .filter {
                $0.action == "open"
                    && $0.option_type == "call"
                    && $0.direction == "short"
                    && store.remainingContracts(for: $0) > 0
            }
            .reduce(0) { sum, t in
                let mark = greeks.first(where: { $0.option_trade_id == t.id })?.last_mark ?? t.premium
                return sum + store.remainingContracts(for: t) * mark * 100
            }
    }

    /// Total premium PAID across all open long puts (the "Paid"
    /// row on the Open Puts Bought card). Σ remaining × avg fill
    /// × 100. The book's running insurance bill.
    static func openPutsPaid(store: PortfolioStore) -> Double {
        store.allTrades
            .filter {
                $0.action == "open"
                    && $0.option_type == "put"
                    && $0.direction == "long"
                    && store.remainingContracts(for: $0) > 0
            }
            .reduce(0) { sum, t in
                sum + store.remainingContracts(for: t) * t.premium * 100
            }
    }

    /// Current mark-to-market value of all open long puts — what
    /// you'd realize if you sold them right now. Drives the "Value
    /// now" row. Falls back to entry premium on cold-cache to
    /// avoid a $0 read.
    static func openPutsValueNow(store: PortfolioStore) -> Double {
        let greeks = store.allGreeks
        return store.allTrades
            .filter {
                $0.action == "open"
                    && $0.option_type == "put"
                    && $0.direction == "long"
                    && store.remainingContracts(for: $0) > 0
            }
            .reduce(0) { sum, t in
                let mark = greeks.first(where: { $0.option_trade_id == t.id })?.last_mark ?? t.premium
                return sum + store.remainingContracts(for: t) * mark * 100
            }
    }

    /// Time-value (extrinsic) portion of the open long-put book.
    /// For each long put: intrinsic = max(0, strike − spot);
    /// time value per share = max(0, mark − intrinsic). Summed
    /// × |remaining| × 100. For a put BUYER this represents the
    /// dollar amount still at risk to decay — the "burn rate" if
    /// nothing happens before expiry.
    static func openPutsTimeValue(store: PortfolioStore) -> Double {
        let greeks = store.allGreeks
        let spotByTicker = Dictionary(
            uniqueKeysWithValues: store.companies.map { ($0.ticker, $0.spot) }
        )
        return store.allTrades
            .filter {
                $0.action == "open"
                    && $0.option_type == "put"
                    && $0.direction == "long"
                    && store.remainingContracts(for: $0) > 0
            }
            .reduce(0) { sum, t in
                let mark = greeks.first(where: { $0.option_trade_id == t.id })?.last_mark ?? t.premium
                let spot = spotByTicker[t.ticker] ?? 0
                let intrinsic = max(0, t.strike - spot)
                let timeValuePerShare = max(0, mark - intrinsic)
                return sum + store.remainingContracts(for: t) * timeValuePerShare * 100
            }
    }

    /// Time-value (extrinsic) portion of the open call credit. For
    /// each open short call: time value per share = max(0, mark −
    /// intrinsic), where intrinsic = max(0, spot − strike). Summed
    /// × |remaining contracts| × 100 across the portfolio. This is
    /// the dollar amount of premium that's still subject to decay —
    /// the part that goes to zero at expiry, leaving only intrinsic
    /// behind.
    static func openCallCreditTimeValue(store: PortfolioStore) -> Double {
        let greeks = store.allGreeks
        let spotByTicker = Dictionary(
            uniqueKeysWithValues: store.companies.map { ($0.ticker, $0.spot) }
        )
        return store.allTrades
            .filter {
                $0.action == "open"
                    && $0.option_type == "call"
                    && $0.direction == "short"
                    && store.remainingContracts(for: $0) > 0
            }
            .reduce(0) { sum, t in
                let mark = greeks.first(where: { $0.option_trade_id == t.id })?.last_mark ?? t.premium
                let spot = spotByTicker[t.ticker] ?? 0
                let intrinsic = max(0, spot - t.strike)
                let timeValuePerShare = max(0, mark - intrinsic)
                return sum + store.remainingContracts(for: t) * timeValuePerShare * 100
            }
    }

    // MARK: - Open Shares totals

    /// Σ shares × avgCost across every open long-stock leg. The raw
    /// equity outlay before any option-premium offset.
    static func openSharesCost(store: PortfolioStore) -> Double {
        store.companies.reduce(0) { sum, c in
            guard let stk = c.legs.first(where: { $0.kind == .stock && $0.qty > 0 })
            else { return sum }
            return sum + stk.qty * stk.avg
        }
    }

    /// Σ shares × last across every open long-stock leg. Current
    /// market value of the share book.
    static func openSharesValue(store: PortfolioStore) -> Double {
        store.companies.reduce(0) { sum, c in
            guard let stk = c.legs.first(where: { $0.kind == .stock && $0.qty > 0 })
            else { return sum }
            return sum + stk.qty * stk.last
        }
    }

    /// Σ today's $ move across every open long-stock leg (qty × spot × dayPct).
    /// Drives the "Today" row on Open Shares card.
    static func openSharesTodayPnL(store: PortfolioStore) -> Double {
        store.companies.reduce(0) { sum, c in
            guard let stk = c.legs.first(where: { $0.kind == .stock && $0.qty > 0 })
            else { return sum }
            return sum + stk.qty * c.spot * (c.dayPct / 100.0)
        }
    }

    // MARK: - Hedge / cross-book derivations

    /// Lifetime net premium harvested across the entire option book.
    /// Walks every NON-voided option trade row (open AND close) and
    /// computes net dollars in vs out — i.e. the realized + still-
    /// unrealized credit you've ever pulled in from selling premium,
    /// minus what you've spent buying it.
    ///
    /// Sign convention (so positive = "money harvested"):
    ///   action=open  · direction=short → +premium·ct·100   (collected at open)
    ///   action=open  · direction=long  → −premium·ct·100   (paid at open)
    ///   action=close · direction=short → −premium·ct·100   (paid to buy back)
    ///   action=close · direction=long  → +premium·ct·100   (received on sell-close)
    ///
    /// Excludes lifecycle codes that flow through assignment / exercise
    /// (premium == 0 in those rows by convention), so they're a no-op
    /// in the sum.
    ///
    /// This is the "all premium ever harvested" definition used by
    /// effectiveBasis on the Open Shares card — drives basis BELOW
    /// raw cost when net premium is positive.
    static func lifetimePremiumHarvested(store: PortfolioStore) -> Double {
        store.allTrades
            .filter { $0.voided_at == nil }
            .reduce(0) { sum, t in
                let dollars = t.contracts * t.premium * 100
                let signed: Double
                switch (t.action, t.direction) {
                case ("open",  "short"): signed =  dollars   // credit
                case ("open",  "long"):  signed = -dollars   // debit
                case ("close", "short"): signed = -dollars   // buy back
                case ("close", "long"):  signed =  dollars   // sell to close
                default:                 signed =  0         // lifecycle / unknown
                }
                return sum + signed
            }
    }

    /// % of put-paid that the open call credit covers. Capped 100.
    /// Returns 0 when putPaid is 0 (the "no puts" state hides the row).
    static func fundedPct(store: PortfolioStore) -> Int {
        let credit = openCallCredit(store: store)
        let paid = openPutsPaid(store: store)
        guard paid > 0 else { return 0 }
        return min(100, Int((credit / paid * 100).rounded()))
    }

    /// hedgeSurplus = callCredit − putPaid. Positive = over-funded
    /// (the call book pays for the entire put book + extra). Drives
    /// the "Hedge fully funded · +$X" copy variant.
    static func hedgeSurplus(store: PortfolioStore) -> Double {
        openCallCredit(store: store) - openPutsPaid(store: store)
    }

    /// netCost = putPaid − callCredit. The out-of-pocket cost of the
    /// hedge when under-funded. Drives "Net cost" on the Open Puts
    /// Bought card and "$X to go" on the funding sheet.
    static func netCost(store: PortfolioStore) -> Double {
        openPutsPaid(store: store) - openCallCredit(store: store)
    }

    /// netCostBookPct = netCost / sharesValue × 100. The sub-text
    /// on Net cost: "(0.22% of book)".
    static func netCostBookPct(store: PortfolioStore) -> Double {
        let sv = openSharesValue(store: store)
        guard sv > 0 else { return 0 }
        return netCost(store: store) / sv * 100
    }

    /// effectiveBasis = sharesCost − lifetimePremiumHarvested.
    /// Lifetime-premium variant per design's option B: subtracts every
    /// dollar of net premium ever harvested. With Sunnyfi's covered-
    /// call strategy this typically reads BELOW raw cost basis — the
    /// motivating number that says "my real cost on these shares is
    /// less than I paid because I've been collecting premium against
    /// them".
    static func effectiveBasis(store: PortfolioStore) -> Double {
        openSharesCost(store: store) - lifetimePremiumHarvested(store: store)
    }

    /// (effectiveBasis − sharesCost) / sharesCost × 100. Negative
    /// when basis has dropped below cost (good); positive when above
    /// (rare — only when net premium is negative for the lifetime).
    static func effectiveBasisPct(store: PortfolioStore) -> Double {
        let cost = openSharesCost(store: store)
        guard cost > 0 else { return 0 }
        return (effectiveBasis(store: store) - cost) / cost * 100
    }

    /// True when the book holds at least one open long put. The
    /// Funds hedge row + the entire Open Puts Bought card hide when
    /// false; the Hedge funding sheet never opens.
    static func hasPuts(store: PortfolioStore) -> Bool {
        openPutsPaid(store: store) > 0
    }

    // MARK: - Hedge funding sheet rows

    /// One row per held long-put leg, sorted by paid desc. Drives the
    /// "Hedge cost · puts bought" group in HedgeFundingSheet.
    struct HedgePutRow: Identifiable, Sendable {
        let id: String
        let ticker: String
        let strike: Double
        let expiry: String
        let contracts: Double
        let paid: Double            // contracts × premium × 100
    }

    static func hedgePutRows(store: PortfolioStore) -> [HedgePutRow] {
        store.allTrades
            .filter {
                $0.action == "open"
                    && $0.option_type == "put"
                    && $0.direction == "long"
                    && store.remainingContracts(for: $0) > 0
            }
            .map { t -> HedgePutRow in
                let ct = store.remainingContracts(for: t)
                return HedgePutRow(
                    id: t.id,
                    ticker: t.ticker,
                    strike: t.strike,
                    expiry: t.expiry,
                    contracts: ct,
                    paid: ct * t.premium * 100
                )
            }
            .sorted { $0.paid > $1.paid }
    }

    /// One row per ticker holding open short calls, sorted by collected
    /// desc. Drives the "Funded by · call credit" group in
    /// HedgeFundingSheet. Aggregated per-ticker (not per-leg) because
    /// the design treats the call-credit side as a single line per
    /// underlying.
    struct HedgeCreditRow: Identifiable, Sendable {
        let id: String              // ticker symbol (stable, unique)
        let ticker: String
        let contracts: Double
        let collected: Double
    }

    static func hedgeCreditRows(store: PortfolioStore) -> [HedgeCreditRow] {
        let calls = store.allTrades.filter {
            $0.action == "open"
                && $0.option_type == "call"
                && $0.direction == "short"
                && store.remainingContracts(for: $0) > 0
        }
        let byTicker = Dictionary(grouping: calls, by: \.ticker)
        return byTicker.map { (ticker, trades) -> HedgeCreditRow in
            let totalCt = trades.reduce(0.0) { $0 + store.remainingContracts(for: $1) }
            let totalCollected = trades.reduce(0.0) { $0 + store.remainingContracts(for: $1) * $1.premium * 100 }
            return HedgeCreditRow(
                id: ticker,
                ticker: ticker,
                contracts: totalCt,
                collected: totalCollected
            )
        }
        .sorted { $0.collected > $1.collected }
    }

    // MARK: - Per-ticker lifetime premium

    /// Lifetime net premium harvested for a SINGLE ticker — used by
    /// the Break-even sheet to compute per-lot effective basis.
    /// Same 4-case sign convention as the portfolio-wide helper:
    ///   open  · short  → +premium·ct·100   (collected)
    ///   open  · long   → −premium·ct·100   (paid)
    ///   close · short  → −premium·ct·100   (paid to buy back)
    ///   close · long   → +premium·ct·100   (sold to close)
    static func lifetimePremiumHarvested(for ticker: String, store: PortfolioStore) -> Double {
        store.allTrades
            .filter { $0.voided_at == nil && $0.ticker == ticker }
            .reduce(0) { sum, t in
                let dollars = t.contracts * t.premium * 100
                let signed: Double
                switch (t.action, t.direction) {
                case ("open",  "short"): signed =  dollars
                case ("open",  "long"):  signed = -dollars
                case ("close", "short"): signed = -dollars
                case ("close", "long"):  signed =  dollars
                default:                 signed =  0
                }
                return sum + signed
            }
    }

    // MARK: - Downside protection rows

    /// One row per open long put — used by the Downside Protection
    /// sheet. cushionPct is positive when OTM (spot above strike for
    /// a put — the cushion before the floor starts paying).
    struct ProtectionRow: Identifiable, Sendable {
        let id: String              // option_trade_id
        let ticker: String
        let strike: Double
        let spot: Double
        let contracts: Double
        let expiry: String
        let paid: Double            // contracts × premium × 100
        let cushionPct: Double      // (spot − strike) / spot × 100
    }

    static func protectionRows(store: PortfolioStore) -> [ProtectionRow] {
        let spotByTicker = Dictionary(
            uniqueKeysWithValues: store.companies.map { ($0.ticker, $0.spot) }
        )
        return store.allTrades
            .filter {
                $0.action == "open"
                    && $0.option_type == "put"
                    && $0.direction == "long"
                    && store.remainingContracts(for: $0) > 0
            }
            .compactMap { t -> ProtectionRow? in
                guard let spot = spotByTicker[t.ticker], spot > 0 else { return nil }
                let ct = store.remainingContracts(for: t)
                let cushion = (spot - t.strike) / spot * 100
                return ProtectionRow(
                    id: t.id,
                    ticker: t.ticker,
                    strike: t.strike,
                    spot: spot,
                    contracts: ct,
                    expiry: t.expiry,
                    paid: ct * t.premium * 100,
                    cushionPct: cushion
                )
            }
            // Tightest cushion first — most-actively-protective puts at top.
            .sorted { $0.cushionPct < $1.cushionPct }
    }

    // MARK: - Break-even rows (effective basis math)

    /// One row per held equity lot. effectiveAvg uses LIFETIME
    /// premium harvested per ticker (matches the Effective basis
    /// row on the Open shares card), so gainPct/needPct reflect
    /// the user's real break-even after all option income on that
    /// ticker.
    struct BreakevenRow: Identifiable, Sendable {
        let id: String              // ticker (stable, unique)
        let ticker: String
        let shares: Double
        let avg: Double             // raw cost per share
        let last: Double            // current price
        let premiumPerShare: Double // lifetime premium / shares
        var effectiveAvg: Double { avg - premiumPerShare }
        var underwater: Bool { last < effectiveAvg }
        /// (last − effectiveAvg) / effectiveAvg × 100. Sign matches
        /// "is current above or below the real break-even".
        var gainPct: Double {
            guard effectiveAvg > 0 else { return 0 }
            return (last - effectiveAvg) / effectiveAvg * 100
        }
        /// Recovery move needed from current price to hit effective
        /// break-even. Positive when underwater; 0 or negative
        /// otherwise (we only show this row when underwater anyway).
        var needPct: Double {
            guard last > 0 else { return 0 }
            return (effectiveAvg - last) / last * 100
        }
    }

    static func breakevenRows(store: PortfolioStore) -> [BreakevenRow] {
        store.companies.compactMap { c -> BreakevenRow? in
            guard let stk = c.legs.first(where: { $0.kind == .stock && $0.qty > 0 })
            else { return nil }
            let lifetime = lifetimePremiumHarvested(for: c.ticker, store: store)
            let perShare = stk.qty > 0 ? lifetime / stk.qty : 0
            return BreakevenRow(
                id: c.ticker,
                ticker: c.ticker,
                shares: stk.qty,
                avg: stk.avg,
                last: stk.last,
                premiumPerShare: perShare
            )
        }
        // Underwater group first. Within each group: largest move
        // first (worst lot at top of underwater group; smallest
        // gain first within in-profit).
        .sorted { a, b in
            if a.underwater != b.underwater { return a.underwater }
            if a.underwater {
                return a.needPct > b.needPct       // worst recovery first
            } else {
                return a.gainPct < b.gainPct       // smallest gain first
            }
        }
    }

    // MARK: - Patch-tile stat helpers

    /// Current mark-to-market gain/loss on the OPEN long-put book.
    /// putValue − putPaid. Drives the "Puts P/L" tile on the
    /// Hedge Funding patch. Negative when hedges have decayed
    /// without underlying movement; positive when they're paying off.
    static func putGain(store: PortfolioStore) -> Double {
        openPutsValueNow(store: store) - openPutsPaid(store: store)
    }

    /// True when ≥ 1 share lot exists at all (any held positions
    /// with qty > 0). The Break-even sheet renders an empty state
    /// when this is false.
    static func hasShares(store: PortfolioStore) -> Bool {
        openSharesCost(store: store) > 0
    }
}
