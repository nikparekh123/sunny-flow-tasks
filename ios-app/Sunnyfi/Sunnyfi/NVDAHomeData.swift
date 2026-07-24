//
//  NVDAHomeData.swift
//  Sunnyfi
//
//  The NVDA-focused Home tab. The user trades one ticker, so the landing
//  page is a single-ticker command center — pulse, effective basis,
//  premium pace, IV signal, next earnings/event — not the generic
//  multi-ticker digest. All values derive from the shared PortfolioStore
//  (reusing CoveredCallData for the position + premium math), so nothing
//  here moves on anything but real trades and the live quote.
//

import Foundation

/// A single news headline (from the `dashboard-news` edge function).
struct NewsHeadline: Decodable, Sendable, Identifiable {
    let ticker: String
    let headline: String
    let url: String?
    let publisher: String?
    let ts: String?
    var id: String { headline }
}

struct NVDAHome: Sendable {
    let ticker: String
    let name: String

    // ── Pulse ──
    let spot: Double
    let dayPct: Double
    let todayPL: Double          // $ move on the shares today
    let positionValue: Double    // shares × spot
    let shares: Double
    let unrealizedShares: Double // (spot − EFFECTIVE basis) × shares — matches the basis card

    // ── Effective basis ──
    let rawAvg: Double           // what you paid, e.g. 209.19
    let effectiveAvg: Double     // after all premium, e.g. 204.89
    let premiumPerShare: Double  // how much premium lowered the basis
    let banked: Double           // cash collected + realized shares
    let aboveBasisPct: Double    // spot vs effective basis

    // ── Premium pace ──
    let premWeek: Double
    let premMonth: Double
    let premLifetime: Double

    // ── IV signal ──
    let ivCurrent: Double?
    let ivLow: Double?
    let ivHigh: Double?

    // ── Earnings + events ──
    let earningsDate: String?
    let earningsDays: Int?
    let earningsTime: String?    // 'bmo' | 'amc' | 'tba'
    let eventName: String?
    let eventDate: String?
    let eventDays: Int?
    let eventStars: Int?

    /// Where current IV sits in its recent [low, high] band, 0…1.
    var ivPercentile: Double? {
        guard let c = ivCurrent, let lo = ivLow, let hi = ivHigh, hi > lo else { return nil }
        return min(1, max(0, (c - lo) / (hi - lo)))
    }
    /// One-word read on whether it's a good time to write calls.
    var ivVerdict: (label: String, rich: Bool)? {
        guard let p = ivPercentile else { return nil }
        if p >= 0.66 { return ("Rich — good to sell", true) }
        if p <= 0.33 { return ("Cheap — maybe wait", false) }
        return ("Middling", true)
    }

    static func build(store: PortfolioStore, today: Date = Date()) -> NVDAHome? {
        let ticker = "NVDA"
        guard let cc = CoveredCallData.build(store: store, ticker: ticker) else { return nil }
        let company = store.companies.first { $0.ticker.uppercased() == ticker }

        let spot = cc.currentPrice
        let shares = cc.shares
        let rawAvg = cc.current?.entryPrice ?? 0
        let effectiveAvg = cc.currentAverage

        // Premium collected in a trailing window — short calls only, net of
        // buybacks paid. trade_date is "YYYY-MM-DD"; ISO strings compare
        // lexicographically, so string ">=" is a genuine date filter.
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "America/New_York")
        func premiumSince(_ startISO: String) -> Double {
            store.allTrades.reduce(0.0) { acc, t in
                guard t.ticker.uppercased() == ticker, t.option_type == "call",
                      t.direction == "short", t.voided_at == nil,
                      t.trade_date >= startISO else { return acc }
                let v = t.premium * t.contracts * 100
                return acc + (t.action == "open" ? v : -v)
            }
        }
        let premWeek  = premiumSince(df.string(from: AppDates.startOfWeek(today)))
        let premMonth = premiumSince(df.string(from: AppDates.startOfMonth(today)))

        let iv = store.allIvSummaries.first { $0.ticker.uppercased() == ticker }

        let earn = store.allEarningsEvents
            .filter { $0.ticker.uppercased() == ticker }
            .min { $0.report_date < $1.report_date }

        // Soonest upcoming macro event; prefer high-importance (≥ 2 stars).
        func soonestEvent(minStars: Int) -> MacroEventRow? {
            store.allMacroEvents
                .filter { (AppDates.daysUntil($0.event_date, from: today) ?? -1) >= 0 && $0.importance >= minStars }
                .min { $0.event_date < $1.event_date }
        }
        let ev = soonestEvent(minStars: 2) ?? soonestEvent(minStars: 1)

        // The DB stores NVDA's name as "NVDA"; prefer a real company name.
        let friendlyName: String = {
            let n = company?.name ?? ""
            return (n.isEmpty || n.uppercased() == ticker) ? "NVIDIA" : n
        }()
        return NVDAHome(
            ticker: ticker,
            name: friendlyName,
            spot: spot,
            dayPct: company?.dayPct ?? cc.dayPct,
            todayPL: cc.todayPL,
            positionValue: shares * spot,
            shares: shares,
            // Measured vs the EFFECTIVE basis (raw cost less premium), so the
            // banner agrees with the "+X% above basis" card instead of
            // contradicting it with a raw-cost figure.
            unrealizedShares: (spot - effectiveAvg) * shares,
            rawAvg: rawAvg,
            effectiveAvg: effectiveAvg,
            premiumPerShare: max(0, rawAvg - effectiveAvg),
            banked: cc.realizedBanked,
            aboveBasisPct: effectiveAvg > 0 ? (spot - effectiveAvg) / effectiveAvg * 100 : 0,
            premWeek: premWeek,
            premMonth: premMonth,
            premLifetime: cc.lifetimePremium,
            ivCurrent: iv?.current_iv,
            ivLow: iv?.iv_low,
            ivHigh: iv?.iv_high,
            earningsDate: earn?.report_date,
            earningsDays: earn.flatMap { AppDates.daysUntil($0.report_date, from: today) },
            earningsTime: earn?.report_time,
            eventName: ev?.name,
            eventDate: ev?.event_date,
            eventDays: ev.flatMap { AppDates.daysUntil($0.event_date, from: today) },
            eventStars: ev?.importance
        )
    }
}
