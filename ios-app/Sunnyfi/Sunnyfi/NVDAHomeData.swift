//
//  NVDAHomeData.swift
//  Sunnyfi
//
//  The Home tab, per the "NVDA Today" editorial handoff (nvda-app.jsx /
//  nvda-data.jsx). Single-position covered-call surface: hairline rows,
//  one big glance number each, a volatility verdict, a 5-session column
//  chart and a news tape. Every derived number is computed here from the
//  shared store so the story can never contradict itself.
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

enum Tone: Sendable { case pos, neg, neon, warn, fg1, fg3 }

/// One card + its detail sheet. `grp` marks the start of a swipe group
/// (Income / Position / Calendar); nil continues the previous group.
struct NVRow: Identifiable, Sendable {
    let k: String            // viz + sheet key
    let grp: String?
    let cat: String
    let num: String
    let unit: String
    let tone: Tone
    let name: String
    let sub: String
    var id: String { k }
}

/// A 5-session price-path card (NVDA and the reference tapes SMH / QQQ).
struct RefSeries: Identifiable, Sendable {
    let tk: String
    let sub: String
    let last: Double
    let days: [NVSession]    // oldest → newest, 5
    let net: Double          // compounded 5-day %
    let avg: Double          // avg absolute daily %
    let priced: Double       // options-implied day = iv/√252
    var id: String { tk }
}

struct SheetRow: Sendable { let name: String; let sub: String; let val: String; let tone: Tone }

struct NVSheet: Sendable {
    let cat: String
    let title: String
    let sub: String
    let hero: String
    let heroUnit: String
    let line: String
    let rows: [SheetRow]
    let isVol: Bool
}

struct NVSession: Identifiable, Sendable {
    let label: String        // "Fri 24"
    let close: Double
    let pct: Double
    let today: Bool
    var id: String { label }
}

struct VolZone: Sendable { let key: String; let verdict: String; let sub: String; let read: String }

struct NVDAToday: Sendable {
    let ticker: String
    let name: String

    // pulse / ticker strip
    let price: Double
    let chgPct: Double
    let chgAbs: Double
    let shares: Double
    let posValue: Double
    let todayPL: Double

    // break-even
    let basisOrig: Double
    let basisEff: Double
    let premPerShare: Double
    let overBE: Double
    let cushionPct: Double
    let sharesPL: Double
    let netPL: Double

    // premium
    let premWeek: Double
    let premMonth: Double
    let premLife: Double
    let premPrev: Double
    let vsLast: Double
    let weeks: [(String, Double)]        // last weeks with writes, oldest→newest
    let protectPct: Double

    // options book
    let strike: Double
    let expiry: String
    let dte: Int
    let contractsWritten: Int
    let contractsTotal: Int

    // sessions
    let days: [NVSession]                  // newest → oldest, up to 5
    let dayMax: Double
    let avgAbs: Double
    let week5: Double
    let pricedDay: Double

    // volatility
    let iv: Double                       // percent, e.g. 40.3
    let ivLow: Double
    let ivHigh: Double
    let hv30: Double?                    // nil when we can't compute realized vol
    let ivr: Int
    let ivWindowDays: Int                // how deep the IV-rank history goes
    let spread: Double?
    let score: Int
    let zone: VolZone

    // events
    let erMove: Double
    let erLow: Double
    let erHigh: Double
    let fedDays: Int?
    let fedWhen: String?
    let erDays: Int?

    let items: [NVRow]
    let sheets: [String: NVSheet]
    let refSeries: [RefSeries]    // NVDA + SMH + QQQ 5-session cards

    static func build(store: PortfolioStore, today: Date = Date()) -> NVDAToday? {
        let ticker = "NVDA"
        guard let cc = CoveredCallData.build(store: store, ticker: ticker) else { return nil }
        let company = store.companies.first { $0.ticker.uppercased() == ticker }

        let price = cc.currentPrice
        let shares = cc.shares
        let chgPct = company?.dayPct ?? cc.dayPct
        let chgAbs = price * chgPct / 100
        let todayPL = cc.todayPL
        let basisOrig = cc.current?.entryPrice ?? 0
        let basisEff = cc.currentAverage
        let premPerShare = max(0, basisOrig - basisEff)
        let overBE = price - basisEff
        let cushionPct = basisEff > 0 ? (price - basisEff) / basisEff * 100 : 0
        let sharesPL = (price - basisOrig) * shares
        let premLife = cc.lifetimePremium
        let netPL = sharesPL + premLife

        // ── premium by week (short calls, net of buybacks) ──
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "America/New_York")
        func premiumSince(_ startISO: String) -> Double {
            store.allTrades.reduce(0.0) { acc, t in
                guard t.ticker.uppercased() == ticker, t.option_type == "call",
                      t.direction == "short", t.voided_at == nil, t.trade_date >= startISO
                else { return acc }
                let v = t.premium * t.contracts * 100
                return acc + (t.action == "open" ? v : -v)
            }
        }
        let weekStart = AppDates.startOfWeek(today)
        let premWeek = premiumSince(df.string(from: weekStart))
        let premMonth = premiumSince(df.string(from: AppDates.startOfMonth(today)))

        // Build a per-week series for the last 5 weeks (Monday-anchored).
        var weeks: [(String, Double)] = []
        let cal = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; c.firstWeekday = 2; return c }()
        for back in stride(from: 4, through: 0, by: -1) {
            guard let ws = cal.date(byAdding: .day, value: -7 * back, to: weekStart),
                  let we = cal.date(byAdding: .day, value: 7, to: ws) else { continue }
            let a = df.string(from: ws), b = df.string(from: we)
            let v = store.allTrades.reduce(0.0) { acc, t in
                guard t.ticker.uppercased() == ticker, t.option_type == "call",
                      t.direction == "short", t.voided_at == nil,
                      t.trade_date >= a, t.trade_date < b else { return acc }
                let val = t.premium * t.contracts * 100
                return acc + (t.action == "open" ? val : -val)
            }
            let lbl = AppDates.shortMonthDay(a)
            weeks.append((lbl, v))
        }
        let writeWeeks = weeks.filter { $0.1 > 0 }
        let premPrev = writeWeeks.count >= 2 ? writeWeeks[writeWeeks.count - 2].1 : 0
        let vsLast = premPrev > 0 ? premWeek / premPrev : 0
        let protectPct = price > 0 ? premPerShare / price * 100 : 0

        // ── options book: soonest-expiry open short call ──
        let openCalls = cc.callLegs.sorted { $0.expiry < $1.expiry }
        let working = openCalls.first
        let strike = working?.strike ?? 0
        let expiry = working?.expiry ?? ""
        let dte = expiry.isEmpty ? 0 : max(0, AppDates.daysUntil(expiry, from: today) ?? 0)
        let contractsWritten = Int(cc.callLegs.reduce(0) { $0 + $1.contracts }.rounded())
        let contractsTotal = Int((shares / 100).rounded(.down))

        // ── last 5 sessions ──
        let hist = store.dailyCloses.filter { $0.ticker.uppercased() == ticker }
            .sorted { $0.date > $1.date }
        var days: [NVSession] = [NVSession(label: sessionLabel(df.string(from: today), df: df), close: price, pct: chgPct, today: true)]
        for i in 0..<min(4, max(0, hist.count - 1)) {
            let c = hist[i].close_price, prev = hist[i + 1].close_price
            let pct = prev > 0 ? (c / prev - 1) * 100 : 0
            days.append(NVSession(label: sessionLabel(hist[i].date, df: df), close: c, pct: pct, today: false))
        }
        let dayMax = max(days.map { abs($0.pct) }.max() ?? 1, 0.1)
        let avgAbs = days.isEmpty ? 0 : days.map { abs($0.pct) }.reduce(0, +) / Double(days.count)
        let fiveAgo = hist.indices.contains(3) ? hist[3].close_price : (hist.last?.close_price ?? price)
        let week5 = fiveAgo > 0 ? (price / fiveAgo - 1) * 100 : 0

        // ── volatility ──
        let iv0 = (store.allIvSummaries.first { $0.ticker.uppercased() == ticker })
        let iv = (iv0?.current_iv ?? 0) * 100
        let ivLow = (iv0?.iv_low ?? 0) * 100
        let ivHigh = (iv0?.iv_high ?? 0) * 100
        let ivWindowDays = iv0?.iv_window_days ?? 0
        // HV30 computed in-app from daily closes — the stored feed value is
        // unreliable (often 0). Annualized stdev of up to 30 daily log
        // returns (oldest→newest), with today's spot as the latest point.
        let closesAsc = hist.reversed().map(\.close_price) + [price]
        let hvApp = realizedVol(closesAsc)
        let hvFeed = (iv0?.current_hv30).map { $0 * 100 }.flatMap { $0 > 0 ? $0 : nil }
        let hv30: Double? = hvApp ?? hvFeed
        let ivr = ivHigh > ivLow ? Int((((iv - ivLow) / (ivHigh - ivLow)) * 100).rounded()) : 0
        let spread: Double? = hv30.map { iv - $0 }
        let pricedDay = iv > 0 ? iv / (252.0).squareRoot() : 0
        // The verdict leans on the REAL signal we can compute today: the
        // implied-minus-realized spread. IV rank is only ~ivWindowDays deep,
        // so it's a secondary nudge. spread normalized −20…+30 → 0…100.
        let nSpread = spread.map { max(0, min(100, (($0 + 20) / 50) * 100)) }
        let score: Int = nSpread.map { Int(($0 * 0.65 + Double(ivr) * 0.35).rounded()) } ?? ivr
        let zone = zoneFor(score: score, iv: iv, hv30: hv30, spread: spread)

        // ── expected move for the working expiry (1-SD, IV-implied) ──
        let erMove = iv > 0 && dte > 0 ? (iv / 100 * (Double(dte) / 365).squareRoot() * 100) : max(6, iv / 5)
        let erLow = price * (1 - erMove / 100)
        let erHigh = price * (1 + erMove / 100)

        // ── events ──
        func soonestMacro(_ needle: [String]) -> MacroEventRow? {
            store.allMacroEvents
                .filter { m in (AppDates.daysUntil(m.event_date, from: today) ?? -1) >= 0
                    && needle.contains { m.name.lowercased().contains($0) } }
                .min { $0.event_date < $1.event_date }
        }
        let fed = soonestMacro(["fed", "fomc", "rate decision"])
        let fedDays = fed.flatMap { AppDates.daysUntil($0.event_date, from: today) }
        let fedWhen = fed.map { AppDates.shortMonthDay($0.event_date) }
        let earn = store.allEarningsEvents.filter { $0.ticker.uppercased() == ticker }
            .min { $0.report_date < $1.report_date }
        let erDays = earn.flatMap { AppDates.daysUntil($0.report_date, from: today) }

        // ── the five things, grouped Income → Position → Calendar ──
        let kNum = fmtK(premWeek).replacingOccurrences(of: "+$", with: "").replacingOccurrences(of: "$", with: "")
        var items: [NVRow] = [
            NVRow(k: "prem", grp: "Income", cat: "Premium", num: kNum, unit: "this week", tone: .pos,
                  name: "Premium by week",
                  sub: vsLast > 0 ? "vs \(fmtMoney(premPrev).replacingOccurrences(of: "+", with: "")) last week" : "\(fmtMoney(premLife)) lifetime"),
            NVRow(k: "prot", grp: "Position", cat: "Protection", num: String(format: "%.1f%%", protectPct), unit: "cushion", tone: .pos,
                  name: "Downside protection", sub: "\(fmtMoney(premPerShare, decimals: 2))/sh off your cost"),
            NVRow(k: "basis", grp: nil, cat: "Break-even", num: fmtMoney(overBE, sign: true, decimals: 2), unit: "per share",
                  tone: overBE >= 0 ? .pos : .neg, name: overBE >= 0 ? "Above break-even" : "Below break-even",
                  sub: "break-even \(fmtMoney(basisEff, decimals: 2))"),
        ]
        if let fd = fedDays, let fw = fedWhen {
            items.append(NVRow(k: "fed", grp: "Calendar", cat: "Events", num: "\(fd)d", unit: "until Fed", tone: .fg1,
                               name: "Fed rate decision", sub: "\(fw) · the next real vol in the name"))
        }
        if strike > 0 {
            let erLabel = erDays.map { $0 <= 0 ? "confirmed" : "~\(Int((Double($0) / 7).rounded()))w" } ?? "~4w"
            items.append(NVRow(k: "er", grp: fedDays == nil ? "Calendar" : nil, cat: "Earnings",
                               num: erDays == nil ? "~4w" : erLabel, unit: "until ER", tone: .warn,
                               name: erDays == nil ? "Earnings not scheduled" : "Earnings ahead",
                               sub: "±\(String(format: "%.0f", erMove))% move · \(fmtStrike(strike))c inside it"))
        }

        // ── 5-session reference cards: NVDA (position) + SMH + QQQ ──
        let refSeries: [RefSeries] = [
            makeSeries(store: store, ticker: ticker, sub: "your position", today: today),
            makeSeries(store: store, ticker: "SMH", sub: "semis etf", today: today),
            makeSeries(store: store, ticker: "QQQ", sub: "nasdaq 100", today: today),
        ].compactMap { $0 }

        let sheets = buildSheets(ticker: ticker, price: price, chgPct: chgPct, chgAbs: chgAbs, todayPL: todayPL,
                                 shares: shares, basisOrig: basisOrig, basisEff: basisEff, premPerShare: premPerShare,
                                 overBE: overBE, cushionPct: cushionPct, netPL: netPL, premWeek: premWeek,
                                 premLife: premLife, premPrev: premPrev, vsLast: vsLast, weeks: weeks,
                                 protectPct: protectPct, strike: strike, expiry: expiry, iv: iv, ivLow: ivLow,
                                 ivHigh: ivHigh, hv30: hv30, ivr: ivr, ivWindowDays: ivWindowDays, spread: spread, zone: zone, week5: week5,
                                 avgAbs: avgAbs, erMove: erMove, erLow: erLow, erHigh: erHigh, fedDays: fedDays,
                                 fedWhen: fedWhen)

        return NVDAToday(
            ticker: ticker, name: friendlyName(company?.name, ticker: ticker),
            price: price, chgPct: chgPct, chgAbs: chgAbs, shares: shares, posValue: shares * price, todayPL: todayPL,
            basisOrig: basisOrig, basisEff: basisEff, premPerShare: premPerShare, overBE: overBE, cushionPct: cushionPct,
            sharesPL: sharesPL, netPL: netPL, premWeek: premWeek, premMonth: premMonth, premLife: premLife,
            premPrev: premPrev, vsLast: vsLast, weeks: writeWeeks.isEmpty ? weeks : writeWeeks, protectPct: protectPct,
            strike: strike, expiry: expiry, dte: dte, contractsWritten: contractsWritten, contractsTotal: contractsTotal,
            days: days, dayMax: dayMax, avgAbs: avgAbs, week5: week5, pricedDay: pricedDay,
            iv: iv, ivLow: ivLow, ivHigh: ivHigh, hv30: hv30, ivr: ivr, ivWindowDays: ivWindowDays, spread: spread, score: score, zone: zone,
            erMove: erMove, erLow: erLow, erHigh: erHigh, fedDays: fedDays, fedWhen: fedWhen, erDays: erDays,
            items: items, sheets: sheets, refSeries: refSeries)
    }

    // ── helpers ──
    private static func friendlyName(_ n: String?, ticker: String) -> String {
        let s = n ?? ""
        return (s.isEmpty || s.uppercased() == ticker) ? "NVIDIA" : s
    }

    /// A 5-session price-path from real daily closes. nil if we don't have
    /// at least 5 sessions for the ticker (so unwired refs simply drop out).
    private static func makeSeries(store: PortfolioStore, ticker: String, sub: String, today: Date) -> RefSeries? {
        let hist = store.dailyCloses.filter { $0.ticker.uppercased() == ticker.uppercased() }
            .sorted { $0.date > $1.date }
        guard hist.count >= 5 else { return nil }
        let recent = Array(hist.prefix(5))                       // newest → oldest
        let ordered = recent.reversed().map { $0 }               // oldest → newest
        var days: [NVSession] = []
        for i in ordered.indices {
            let c = ordered[i].close_price
            let prev = i > 0 ? ordered[i - 1].close_price
                             : (hist.count > 5 ? hist[5].close_price : c)
            let pct = prev > 0 ? (c / prev - 1) * 100 : 0
            let df = DateFormatter(); df.dateFormat = "EEE"
            df.timeZone = TimeZone(identifier: "America/New_York")
            days.append(NVSession(label: AppDates.weekdayShort(ordered[i].date),
                                  close: c, pct: pct, today: i == ordered.count - 1))
        }
        let last = ordered.last?.close_price ?? 0
        let net = days.reduce(1.0) { $0 * (1 + $1.pct / 100) } - 1
        let avg = days.isEmpty ? 0 : days.map { abs($0.pct) }.reduce(0, +) / Double(days.count)
        let iv = (store.allIvSummaries.first { $0.ticker.uppercased() == ticker.uppercased() }?.current_iv ?? 0) * 100
        let priced = iv > 0 ? iv / (252.0).squareRoot() : 0
        return RefSeries(tk: ticker.uppercased(), sub: sub, last: last, days: days,
                         net: net * 100, avg: avg, priced: priced)
    }
    private static func sessionLabel(_ iso: String, df: DateFormatter) -> String {
        "\(AppDates.weekdayShort(iso)) \(String(iso.suffix(2)))"
    }
    private static func zoneFor(score: Int, iv: Double, hv30: Double?, spread: Double?) -> VolZone {
        let edge = (hv30 != nil && spread != nil)
            ? String(format: " IV %.0f%% vs realized %.0f%% (%@%.0f).", iv, iv - spread!, spread! >= 0 ? "+" : "−", abs(spread!))
            : ""
        if score >= 75 { return VolZone(key: "caution", verdict: "Caution", sub: "vol is extreme",
            read: "Premiums are fat because something is coming. Check the catalyst before you size up.\(edge)") }
        if score >= 55 { return VolZone(key: "sell", verdict: "Write", sub: "vol is rich",
            read: "Options are pricing more movement than the stock has delivered — the sweet spot to sell into.\(edge)") }
        if score >= 35 { return VolZone(key: "neutral", verdict: "Neutral", sub: "no edge either way",
            read: "Fair pricing. Write only if the income is needed, and stay wide of the strike.\(edge)") }
        return VolZone(key: "hold", verdict: "Hold", sub: "vol is cheap",
            read: "The stock is moving about as much as options imply, so writing here undercompensates you.\(edge)")
    }
    private static func fmtDec(_ v: Double) -> String { String(format: "%.1f", v) }

    /// HV30 — annualized stdev of up to 30 daily log returns from a
    /// close series (oldest→newest). nil when the series is too short.
    private static func realizedVol(_ closes: [Double]) -> Double? {
        guard closes.count >= 8 else { return nil }
        let recent = Array(closes.suffix(31))       // ≤ 31 closes → ≤ 30 returns
        var rets: [Double] = []
        for i in 1..<recent.count where recent[i - 1] > 0 && recent[i] > 0 {
            rets.append(Foundation.log(recent[i] / recent[i - 1]))
        }
        guard rets.count >= 5 else { return nil }
        let mean = rets.reduce(0, +) / Double(rets.count)
        let variance = rets.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(rets.count - 1)
        return variance.squareRoot() * (252.0).squareRoot() * 100
    }

    // Detail sheets — real, derivable rows only (no fabricated ticks/probabilities).
    private static func buildSheets(
        ticker: String, price: Double, chgPct: Double, chgAbs: Double, todayPL: Double, shares: Double,
        basisOrig: Double, basisEff: Double, premPerShare: Double, overBE: Double, cushionPct: Double, netPL: Double,
        premWeek: Double, premLife: Double, premPrev: Double, vsLast: Double, weeks: [(String, Double)],
        protectPct: Double, strike: Double, expiry: String, iv: Double, ivLow: Double, ivHigh: Double,
        hv30: Double?, ivr: Int, ivWindowDays: Int, spread: Double?, zone: VolZone, week5: Double, avgAbs: Double,
        erMove: Double, erLow: Double, erHigh: Double, fedDays: Int?, fedWhen: String?
    ) -> [String: NVSheet] {
        let shN = Int(shares.rounded()).formatted(.number.grouping(.automatic))
        var s: [String: NVSheet] = [:]

        // The rank window is only as deep as the daily IV snapshot has run.
        let rankWin = ivWindowDays >= 220 ? "52-week" : "\(ivWindowDays)-day"
        var volRows: [SheetRow] = [
            SheetRow(name: "Implied vol", sub: "front month", val: String(format: "%.1f%%", iv), tone: .fg1),
        ]
        if let hv = hv30 {
            volRows.append(SheetRow(name: "Realized vol", sub: "30-day actual", val: String(format: "%.0f%%", hv), tone: .fg1))
            if let sp = spread { volRows.append(SheetRow(name: "Implied − realized", sub: "seller edge (the real signal)", val: (sp >= 0 ? "+" : "−") + String(format: "%.0f", abs(sp)), tone: sp >= 0 ? .pos : .neg)) }
        }
        volRows.append(SheetRow(name: "IV rank", sub: "\(rankWin) range", val: "\(ivr)/100", tone: .fg3))
        volRows.append(SheetRow(name: "IV range", sub: "\(rankWin) low · high", val: String(format: "%.0f–%.0f%%", ivLow, ivHigh), tone: .fg3))
        s["vol"] = NVSheet(cat: "Volatility", title: "Should you write?", sub: "\(ticker) · 30-day options",
            hero: String(format: "%.1f%%", iv), heroUnit: hv30 != nil ? "implied vol · realized \(String(format: "%.0f", iv - (spread ?? 0)))%" : "implied vol · rank \(ivr)/100",
            line: zone.read, rows: volRows, isVol: true)

        var premRows: [SheetRow] = weeks.reversed().map {
            SheetRow(name: "Week of \($0.0)", sub: $0.1 > 0 ? "calls written" : "no writes",
                     val: $0.1 > 0 ? fmtMoney($0.1, sign: true) : "—", tone: $0.1 > 0 ? .pos : .fg3)
        }
        premRows.append(SheetRow(name: "Lifetime", sub: String(format: "%.1f%% downside protection", protectPct), val: fmtMoney(premLife, sign: true), tone: .neon))
        s["prem"] = NVSheet(cat: "Premium", title: "Income collected", sub: "This week · \(ticker)",
            hero: fmtMoney(premWeek, sign: true), heroUnit: vsLast > 0 ? "\(fmtDec(vsLast))× last week" : "lifetime \(fmtMoney(premLife))",
            line: vsLast > 0 ? "This week is \(fmtDec(vsLast))× the \(fmtMoney(premPrev)) collected last week. Lifetime premium now buys \(String(format: "%.1f", protectPct))% of downside protection on the position."
                             : "Lifetime premium now buys \(String(format: "%.1f", protectPct))% of downside protection on the position.",
            rows: premRows, isVol: false)

        s["prot"] = NVSheet(cat: "Protection", title: "How far premium carries you", sub: "Lifetime premium · \(ticker)",
            hero: String(format: "%.1f%%", protectPct), heroUnit: "cushion · \(fmtMoney(premPerShare, decimals: 2)) a share",
            line: "Premium is the buffer between the market and a loss. Every dollar collected moves your break-even lower — currently \(fmtMoney(basisEff, decimals: 2)), \(String(format: "%.1f", protectPct))% under the original cost.",
            rows: [
                SheetRow(name: "Original cost", sub: "\(shN) sh", val: fmtMoney(basisOrig, decimals: 2), tone: .fg1),
                SheetRow(name: "Premium per share", sub: "lifetime", val: "−" + fmtMoney(premPerShare, decimals: 2), tone: .pos),
                SheetRow(name: "Break-even now", sub: "effective basis", val: fmtMoney(basisEff, decimals: 2), tone: .neon),
                SheetRow(name: "Cushion", sub: "of the share price", val: String(format: "%.1f%%", protectPct), tone: .pos),
            ], isVol: false)

        s["basis"] = NVSheet(cat: "Break-even", title: "Where break-even sits", sub: "\(shN) shares",
            hero: fmtMoney(basisEff, decimals: 2), heroUnit: "break-even · was \(fmtMoney(basisOrig, decimals: 2))",
            line: "Premium lowers the line you have to clear. The stock is \(fmtMoney(overBE, decimals: 2)) above it — worth \(fmtMoney(netPL, sign: true)) on the whole position.",
            rows: [
                SheetRow(name: "Original cost", sub: "\(shN) sh", val: fmtMoney(basisOrig, decimals: 2), tone: .fg1),
                SheetRow(name: "Premium collected", sub: "−" + fmtMoney(premPerShare, decimals: 2) + "/sh", val: "−" + fmtMoney(premLife), tone: .pos),
                SheetRow(name: "Effective basis", sub: "post-premium", val: fmtMoney(basisEff, decimals: 2), tone: .neon),
                SheetRow(name: "Last price", sub: "live", val: fmtMoney(price, decimals: 2), tone: .fg1),
                SheetRow(name: "Cushion", sub: "price vs effective basis", val: String(format: "+%.1f%%", cushionPct), tone: .pos),
                strike > 0 ? SheetRow(name: "Assigned at \(fmtStrike(strike))", sub: "gain per share", val: fmtMoney(strike - basisEff, sign: true, decimals: 2), tone: .pos) : nil,
            ].compactMap { $0 }, isVol: false)

        s["day"] = NVSheet(cat: "Tape", title: "Today's session", sub: "\(ticker)",
            hero: fmtMoney(price, decimals: 2), heroUnit: "\(fmtPct(chgPct)) · " + fmtMoney(chgAbs, sign: true, decimals: 2),
            line: "Five-session net \(String(format: "%.1f", week5))%, averaging \(String(format: "%.1f", avgAbs))% a day.",
            rows: [
                SheetRow(name: "Last price", sub: "live", val: fmtMoney(price, decimals: 2), tone: .fg1),
                SheetRow(name: "Day change", sub: "since prior close", val: fmtPct(chgPct), tone: chgPct >= 0 ? .pos : .neg),
                SheetRow(name: "Position P&L", sub: "\(shN) sh today", val: fmtMoney(todayPL, sign: true), tone: todayPL >= 0 ? .pos : .neg),
            ], isVol: false)

        if let fd = fedDays, let fw = fedWhen {
            s["fed"] = NVSheet(cat: "Events", title: "Fed rate decision", sub: fw,
                hero: "\(fd)d", heroUnit: "until the print",
                line: "The chance to write is the vol bid into the print — not the decision itself.",
                rows: [
                    SheetRow(name: "Fed rate decision", sub: fw, val: "\(fd)d", tone: .fg1),
                    strike > 0 ? SheetRow(name: "Your strike", sub: "\(fmtStrike(strike)) · \(AppDates.shortMonthDay(expiry))", val: "open", tone: .neon) : nil,
                ].compactMap { $0 }, isVol: false)
        }

        if strike > 0 {
            s["er"] = NVSheet(cat: "Earnings", title: "Next earnings", sub: "date unconfirmed",
                hero: String(format: "±%.0f%%", erMove), heroUnit: "expected move · \(fmtMoney(erLow, decimals: 0))–\(fmtMoney(erHigh, decimals: 0))",
                line: "The \(fmtStrike(strike)) strike sits inside the expected move, so an in-line print can still take the shares. Roll up or close before the date is confirmed.",
                rows: [
                    SheetRow(name: "Expected move", sub: "options-implied", val: String(format: "±%.0f%%", erMove), tone: .fg1),
                    SheetRow(name: "Implied range", sub: "post-print", val: "\(fmtMoney(erLow, decimals: 0))–\(fmtMoney(erHigh, decimals: 0))", tone: .fg1),
                    SheetRow(name: "Your strike", sub: "\(fmtStrike(strike)) · \(AppDates.shortMonthDay(expiry))", val: "inside range", tone: .warn),
                    SheetRow(name: "Assignment gain", sub: "vs effective basis", val: fmtMoney(strike - basisEff, sign: true, decimals: 2) + "/sh", tone: .pos),
                ], isVol: false)
        }
        return s
    }
}
