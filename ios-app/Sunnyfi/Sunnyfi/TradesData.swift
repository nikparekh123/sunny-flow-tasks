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
}
