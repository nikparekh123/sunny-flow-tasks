//
//  IncomeDetailData.swift
//  Sunnyfi
//
//  View-model for the per-ticker income / buy-write detail screen —
//  the new "Income" segment of Trades (design_handoff_meta_detail,
//  "META Detail v3"). Everything here is computed from LIVE store data
//  (position legs, option trades, greeks, IV summary). No fabrication:
//  the position header, working call, and current-period yield are
//  exact; the history-backed cards (weekly bars, exercise streak)
//  render honestly sparse and fill in as the strategy accrues trades.
//
//  Strategy framing this screen serves: buy a large share lot, sell
//  at/near-the-money weekly calls, treat assignment as a WIN (clean
//  realized gain → rebuy) and non-assignment as the average ratcheting
//  lower by the premium collected. The "average after premium" is the
//  strategy's heartbeat and leads the screen.
//

import Foundation
import SwiftUI

struct IncomeDetail {
    let ticker: String
    let name: String

    // ── Position header ──
    let spot: Double
    let dayPct: Double
    let shares: Double
    let rawAvg: Double
    let effectiveAvg: Double        // rawAvg − lifetimePremium/shares
    let premiumDrop: Double         // rawAvg − effectiveAvg (>0 = basis dropped)
    let marketValue: Double
    let unrealized: Double

    // ── Working short call (nearest expiry) ──
    let call: OpenCall?

    // ── Premium yield ──
    let premThisWeek: Double
    let premThisMonth: Double
    let annualizedPct: Double
    let lifetimeHarvested: Double   // gross credits from short calls, lifetime
    let expiryCount: Int            // # short-call opens ever (proxy for "N expiries")
    let ivPct: Double?              // current_iv × 100
    let ivRank: Double?             // IVR 0–100
    /// Days of accumulated IV history (window_start → last snapshot).
    /// The rank is only trustworthy once this window is mature — a
    /// just-seeded ticker pins to rank 0/100 trivially.
    let ivWindowDays: Int?

    // ── Weekly premium series (oldest → newest, last 6 weeks) ──
    let weeks: [WeekBar]

    // ── Exercise history (newest first) + derived streak ──
    let history: [ExpiryOutcome]
    let keptStreak: Int
    let daysSinceExercise: Int?

    struct OpenCall {
        let strike: Double
        let contracts: Double
        let premiumCollected: Double    // contracts × premium × 100
        let soldWeekday: String
        let expiryWeekday: String
        let dte: Int
        let assignProb: Int?            // |delta| × 100 (nil if no greek)
        let delta: Double?
        let otmDollars: Double          // strike − spot  (>0 = OTM, safe)
        let cushionPct: Double          // (strike − spot)/spot × 100
        let ifAssigned: Double          // premium + (strike − rawAvg)×contracts×100
        let ifKeptAvg: Double           // the effective avg you keep the shares at
        let belowAvg: Bool              // strike < rawAvg → assignment locks a loss
    }

    struct WeekBar: Identifiable {
        let id: Int
        let label: String
        let premium: Double
        let assigned: Bool
        let isCurrent: Bool
    }

    struct ExpiryOutcome: Identifiable {
        let id: String
        let weekday: String
        let strike: Double
        let exercised: Bool
        let avgAfter: Double?           // kept → effective avg after
        let realized: Double?           // exercised → realized $
    }
}

extension IncomeDetail {

    /// Tickers eligible for the Income screen — anything with a live
    /// share lot (the buy-write book). Sorted by market value desc so
    /// the biggest position leads.
    static func eligibleTickers(store: PortfolioStore) -> [String] {
        store.companies
            .compactMap { c -> (String, Double)? in
                guard let stk = c.legs.first(where: { $0.kind == .stock && $0.qty > 0 })
                else { return nil }
                return (c.ticker, stk.qty * c.spot)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    static func compute(store: PortfolioStore, ticker: String, now: Date = Date()) -> IncomeDetail? {
        guard let c = store.companies.first(where: { $0.ticker == ticker }) else { return nil }
        let stockLeg = c.legs.first(where: { $0.kind == .stock && $0.qty > 0 })
        let shares = stockLeg?.qty ?? 0
        let rawAvg = stockLeg?.avg ?? 0

        let lifetimePrem = TradesData.lifetimePremiumHarvested(for: ticker, store: store)
        let premPerShare = shares > 0 ? lifetimePrem / shares : 0
        let effectiveAvg = rawAvg - premPerShare
        let marketValue = shares * c.spot
        let unrealized = stockLeg?.unreal ?? (shares * (c.spot - rawAvg))

        let displayName: String = {
            let n = c.name.trimmingCharacters(in: .whitespaces)
            if !n.isEmpty && n.uppercased() != ticker.uppercased() { return n }
            return TickerNames.name(for: ticker) ?? ticker
        }()

        // ── Working short call: soonest-expiry open short call ──
        let openShortCalls = store.allTrades.filter {
            $0.ticker == ticker
                && $0.action == "open"
                && $0.option_type == "call"
                && $0.direction == "short"
                && $0.voided_at == nil
                && store.remainingContracts(for: $0) > 0
        }
        let workingLeg = openShortCalls
            .sorted {
                let a = AppDates.daysUntil($0.expiry) ?? 9999
                let b = AppDates.daysUntil($1.expiry) ?? 9999
                if a != b { return a < b }
                return store.remainingContracts(for: $0) > store.remainingContracts(for: $1)
            }
            .first

        let call: OpenCall? = workingLeg.map { t in
            let remaining = store.remainingContracts(for: t)
            let premiumCollected = remaining * t.premium * 100
            let greekDelta = store.allGreeks.first(where: { $0.option_trade_id == t.id })?.delta
            let assignedShares = remaining * 100
            let ifAssigned = premiumCollected + (t.strike - rawAvg) * assignedShares
            return OpenCall(
                strike: t.strike,
                contracts: remaining,
                premiumCollected: premiumCollected,
                soldWeekday: AppDates.weekdayShort(t.trade_date),
                expiryWeekday: AppDates.weekdayShort(t.expiry),
                dte: max(0, AppDates.daysUntil(t.expiry) ?? 0),
                assignProb: greekDelta.map { Int((abs($0) * 100).rounded()) },
                delta: greekDelta,
                otmDollars: t.strike - c.spot,
                cushionPct: c.spot > 0 ? (t.strike - c.spot) / c.spot * 100 : 0,
                ifAssigned: ifAssigned,
                ifKeptAvg: effectiveAvg,
                belowAvg: t.strike < rawAvg
            )
        }

        // ── Yield: short-call credits, this-week / this-month ──
        let cal = calendarEST()
        let weekStart = AppDates.startOfWeek(now)
        let monthStart = AppDates.startOfMonth(now)
        let allShortCallOpens = store.allTrades.filter {
            $0.ticker == ticker
                && $0.action == "open"
                && $0.option_type == "call"
                && $0.direction == "short"
                && $0.voided_at == nil
        }
        func credit(_ t: OptionTradeRow) -> Double { t.contracts * t.premium * 100 }
        var premThisWeek = 0.0, premThisMonth = 0.0, lifetimeHarvested = 0.0
        for t in allShortCallOpens {
            let d = AppDates.parseISODay(t.trade_date)
            let dollars = credit(t)
            lifetimeHarvested += dollars
            if let d {
                if d >= weekStart { premThisWeek += dollars }
                if d >= monthStart { premThisMonth += dollars }
            }
        }
        let basis = shares * rawAvg
        let annualizedPct = basis > 0 ? premThisMonth * 12 / basis * 100 : 0

        let ivRow = store.allIvSummaries.first(where: { $0.ticker == ticker })
        let ivPct = ivRow?.current_iv.map { $0 * 100 }
        let ivRank = ivRow.flatMap { IVMath.ivr($0) }
        let ivWindowDays: Int? = {
            if let ws = ivRow?.window_start, let ls = ivRow?.last_snapshot_date,
               let lsDate = AppDates.parseISODay(ls),
               let span = AppDates.daysBetween(ws, lsDate) { return span }
            return ivRow?.iv_window_days
        }()

        // ── Weekly premium series (last 6 weeks) ──
        let assignmentRows = store.allTrades.filter {
            $0.ticker == ticker && ($0.source == "assignment")
        }
        var weeks: [IncomeDetail.WeekBar] = []
        for i in 0..<6 {
            let start = cal.date(byAdding: .day, value: -7 * (5 - i), to: weekStart) ?? weekStart
            let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
            let prem = allShortCallOpens.reduce(0.0) { sum, t in
                guard let d = AppDates.parseISODay(t.trade_date), d >= start, d < end else { return sum }
                return sum + credit(t)
            }
            let assigned = assignmentRows.contains { r in
                guard let d = AppDates.parseISODay(r.trade_date) else { return false }
                return d >= start && d < end
            }
            weeks.append(.init(
                id: i,
                label: i == 5 ? "now" : "W\(i + 1)",
                premium: prem,
                assigned: assigned,
                isCurrent: i == 5
            ))
        }

        // ── Exercise history (best-effort, real data) ──
        // A resolved short call (remaining == 0, expiry in the past) is
        // "kept" (expired OTM) unless an assignment row landed near its
        // expiry, in which case it was "exercised" (called away — a win).
        var history: [IncomeDetail.ExpiryOutcome] = []
        var lastExercisedExpiry: String? = nil
        let resolved = store.allTrades.filter {
            $0.ticker == ticker
                && $0.action == "open"
                && $0.option_type == "call"
                && $0.direction == "short"
                && $0.voided_at == nil
                && store.remainingContracts(for: $0) == 0
                && (AppDates.daysUntil($0.expiry) ?? 1) <= 0
        }
        .sorted {
            (AppDates.parseISODay($0.expiry) ?? .distantPast)
                > (AppDates.parseISODay($1.expiry) ?? .distantPast)
        }
        for t in resolved.prefix(8) {
            let exercised = assignmentRows.contains { r in
                guard let re = AppDates.parseISODay(r.trade_date),
                      let ex = AppDates.parseISODay(t.expiry) else { return false }
                return abs(re.timeIntervalSince(ex)) <= 3 * 86_400   // within 3 days of expiry
            }
            let realized: Double? = exercised
                ? credit(t) + (t.strike - rawAvg) * t.contracts * 100
                : nil
            if exercised, lastExercisedExpiry == nil { lastExercisedExpiry = t.expiry }
            history.append(.init(
                id: t.id,
                weekday: AppDates.weekdayShort(t.expiry),
                strike: t.strike,
                exercised: exercised,
                avgAfter: exercised ? nil : effectiveAvg,
                realized: realized
            ))
        }
        var keptStreak = 0
        for h in history { if h.exercised { break }; keptStreak += 1 }
        let daysSinceExercise: Int? = lastExercisedExpiry
            .flatMap { AppDates.daysBetween($0, now) }

        return IncomeDetail(
            ticker: ticker,
            name: displayName,
            spot: c.spot,
            dayPct: c.dayPct,
            shares: shares,
            rawAvg: rawAvg,
            effectiveAvg: effectiveAvg,
            premiumDrop: max(0, rawAvg - effectiveAvg),
            marketValue: marketValue,
            unrealized: unrealized,
            call: call,
            premThisWeek: premThisWeek,
            premThisMonth: premThisMonth,
            annualizedPct: annualizedPct,
            lifetimeHarvested: lifetimeHarvested,
            expiryCount: allShortCallOpens.count,
            ivPct: ivPct,
            ivRank: ivRank,
            ivWindowDays: ivWindowDays,
            weeks: weeks,
            history: history,
            keptStreak: keptStreak,
            daysSinceExercise: daysSinceExercise
        )
    }

    private static func calendarEST() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        cal.firstWeekday = 2
        return cal
    }
}
