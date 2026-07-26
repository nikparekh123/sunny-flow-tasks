//
//  PositionData.swift
//  Sunnyfi
//
//  NVDA Position (Covered Call tab) — handoff 6. Data engine: rich-black
//  premium-harvested hero, the position rail, premium-by-week, what it
//  earned, history, and the sheet copy. Derives from CoveredCallData so it
//  can never disagree with the rest of the app.
//

import Foundation

struct PosWeek: Identifiable, Sendable {
    let w: String
    let v: Double
    let note: String
    var id: String { w }
}

struct PosCardModel: Identifiable, Sendable {
    let k: String            // shares | calls | uncov
    let cat: String
    let num: String
    let unit: String
    let tone: Tone
    let name: String
    let sub: String
    let viz: String          // basis | cover | segs
    var id: String { k }
}

struct PosSleeve: Identifiable, Sendable {
    let k: String
    let name: String
    let qty: Int
    let tag: String
    let tone: Tone           // pos/neg/warn → pill color; fg3 = muted
    let hasLegs: Bool
    var id: String { k }
}

struct PosData: Sendable {
    let ticker: String
    let price: Double
    let chgPct: Double
    let shares: Double
    let posValue: Double
    let basisOrig: Double
    let basisEff: Double
    let premPerShare: Double
    let overBE: Double
    let sharesPL: Double
    let netPL: Double
    let premLife: Double
    let premYield: Double
    let contractsTotal: Int
    let contractsWritten: Int
    let uncovered: Int
    let coveredPct: Int
    let strike: Double
    let strikeDist: Double
    let expiry: String
    let dte: Int
    let creditOpen: Double
    let iv: Double
    let assignGain: Double
    let protectPct: Double
    let weeks: [PosWeek]
    let bigWeekLabel: String
    let bigWeekVal: Double
    let bigWeekPct: Int
    let cards: [PosCardModel]
    let sleeves: [PosSleeve]
    let hist: [PosWeek]
    let sheets: [String: NVSheet]

    static func build(store: PortfolioStore, today: Date = Date()) -> PosData? {
        let ticker = "NVDA"
        guard let cc = CoveredCallData.build(store: store, ticker: ticker) else { return nil }
        let company = store.companies.first { $0.ticker.uppercased() == ticker }

        let price = cc.currentPrice
        let chgPct = company?.dayPct ?? cc.dayPct
        let shares = cc.shares
        let posValue = shares * price
        let basisOrig = cc.current?.entryPrice ?? 0
        let basisEff = cc.currentAverage
        let premPerShare = max(0, basisOrig - basisEff)
        let overBE = price - basisEff
        let sharesPL = (price - basisOrig) * shares
        let premLife = cc.lifetimePremium
        let netPL = sharesPL + premLife
        let premYield = posValue > 0 ? premLife / posValue * 100 : 0
        let contractsTotal = Int((shares / 100).rounded(.down))
        let openCalls = cc.callLegs.sorted { $0.expiry < $1.expiry }
        let contractsWritten = Int(openCalls.reduce(0) { $0 + $1.contracts }.rounded())
        let uncovered = max(0, contractsTotal - contractsWritten)
        let coveredPct = contractsTotal > 0 ? Int((Double(contractsWritten) / Double(contractsTotal) * 100).rounded()) : 0
        let working = openCalls.first
        let strike = working?.strike ?? 0
        let expiry = working?.expiry ?? ""
        let dte = expiry.isEmpty ? 0 : max(0, AppDates.daysUntil(expiry, from: today) ?? 0)
        let creditOpen = cc.openCallPremiumTotal
        let iv = (store.allIvSummaries.first { $0.ticker.uppercased() == ticker }?.current_iv ?? 0) * 100
        let strikeDist = price > 0 && strike > 0 ? (strike - price) / price * 100 : 0
        let assignGain = strike > 0 ? strike - basisEff : 0
        let protectPct = price > 0 ? premPerShare / price * 100 : 0

        // ── premium by week (short calls, net) with a status note ──
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "America/New_York")
        let weekStart = AppDates.startOfWeek(today)
        let cal = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; c.firstWeekday = 2; return c }()
        func weekPremium(_ a: String, _ b: String) -> Double {
            store.allTrades.reduce(0.0) { acc, t in
                guard t.ticker.uppercased() == ticker, t.option_type == "call", t.direction == "short",
                      t.voided_at == nil, t.trade_date >= a, t.trade_date < b else { return acc }
                let val = t.premium * t.contracts * 100
                return acc + (t.action == "open" ? val : -val)
            }
        }
        // Show the last 8 weeks; fold everything older into a "Prior" bucket so
        // the cumulative harvest lands exactly on lifetime premium (and the
        // "big week %" is of the true total) — reconciles with the hero.
        var weeks: [PosWeek] = []
        for back in stride(from: 7, through: 0, by: -1) {
            guard let ws = cal.date(byAdding: .day, value: -7 * back, to: weekStart),
                  let we = cal.date(byAdding: .day, value: 7, to: ws) else { continue }
            let v = weekPremium(df.string(from: ws), df.string(from: we))
            let note = v <= 0 ? "no writes" : (back == 0 && dte > 0 ? "open · \(dte) DTE" : "expired · kept")
            weeks.append(PosWeek(w: AppDates.shortMonthDay(df.string(from: ws)), v: v, note: note))
        }
        let recentSum = weeks.reduce(0) { $0 + $1.v }
        let prior = premLife - recentSum
        if prior > 1 { weeks.insert(PosWeek(w: "Prior", v: prior, note: "earlier weeks"), at: 0) }
        let writeWeeks = weeks.filter { $0.v > 0 && $0.w != "Prior" }
        let bigWeek = writeWeeks.max(by: { $0.v < $1.v }) ?? PosWeek(w: "—", v: 0, note: "")
        let bigWeekPct = premLife > 0 ? Int((bigWeek.v / premLife * 100).rounded()) : 0

        let cards: [PosCardModel] = [
            PosCardModel(k: "shares", cat: "Stock", num: Int(shares).formatted(.number.grouping(.automatic)), unit: "shares held",
                         tone: .fg1, name: "Long NVDA", sub: "\(compact(posValue)) market value", viz: "basis"),
            PosCardModel(k: "calls", cat: "Calls written", num: "\(contractsWritten)", unit: "of \(contractsTotal) contracts",
                         tone: .pos, name: strike > 0 ? "\(fmtStrike(strike))c · \(AppDates.shortMonthDay(expiry))" : "None written",
                         sub: creditOpen > 0 ? "\(fmtMoney(creditOpen, sign: true)) credit open" : "no open calls", viz: "cover"),
            PosCardModel(k: "uncov", cat: "Unwritten", num: "\(uncovered)", unit: "contracts free",
                         tone: .fg1, name: "Room to write", sub: "\((uncovered * 100).formatted(.number.grouping(.automatic))) shares uncovered", viz: "segs"),
        ]

        let sleeves: [PosSleeve] = [
            PosSleeve(k: "csold", name: "Calls sold", qty: contractsWritten,
                      tag: strike > 0 ? "OTM +\(String(format: "%.1f", strikeDist))%" : "—", tone: .pos, hasLegs: !cc.callLegs.isEmpty),
            PosSleeve(k: "pbought", name: "Puts bought", qty: Int(cc.putLegs.reduce(0) { $0 + $1.contracts }.rounded()),
                      tag: "hedge", tone: .fg3, hasLegs: !cc.putLegs.isEmpty),
            PosSleeve(k: "cbought", name: "Calls bought", qty: Int(cc.longCallLegs.reduce(0) { $0 + $1.contracts }.rounded()),
                      tag: "LEAP", tone: .fg3, hasLegs: !cc.longCallLegs.isEmpty),
        ]
        let hist = writeWeeks.reversed().map { PosWeek(w: "Week of \($0.w)", v: $0.v, note: $0.note) }

        let sheets = buildSheets(ticker: ticker, price: price, shares: shares, basisOrig: basisOrig, basisEff: basisEff,
                                 premPerShare: premPerShare, overBE: overBE, sharesPL: sharesPL, netPL: netPL,
                                 premLife: premLife, premYield: premYield, contractsWritten: contractsWritten,
                                 contractsTotal: contractsTotal, uncovered: uncovered, coveredPct: coveredPct,
                                 strike: strike, strikeDist: strikeDist, expiry: expiry, dte: dte, creditOpen: creditOpen,
                                 iv: iv, assignGain: assignGain, protectPct: protectPct, weeks: weeks,
                                 bigWeekLabel: bigWeek.w, bigWeekVal: bigWeek.v, bigWeekPct: bigWeekPct)

        return PosData(ticker: ticker, price: price, chgPct: chgPct, shares: shares, posValue: posValue,
                       basisOrig: basisOrig, basisEff: basisEff, premPerShare: premPerShare, overBE: overBE,
                       sharesPL: sharesPL, netPL: netPL, premLife: premLife, premYield: premYield,
                       contractsTotal: contractsTotal, contractsWritten: contractsWritten, uncovered: uncovered,
                       coveredPct: coveredPct, strike: strike, strikeDist: strikeDist, expiry: expiry, dte: dte,
                       creditOpen: creditOpen, iv: iv, assignGain: assignGain, protectPct: protectPct, weeks: weeks,
                       bigWeekLabel: bigWeek.w, bigWeekVal: bigWeek.v, bigWeekPct: bigWeekPct, cards: cards,
                       sleeves: sleeves, hist: hist, sheets: sheets)
    }

    private static func compact(_ v: Double) -> String {
        if abs(v) >= 1_000_000 { return String(format: "$%.2fM", v / 1_000_000) }
        if abs(v) >= 1_000 { return String(format: "$%.0fK", v / 1_000) }
        return fmtMoney(v)
    }

    private static func buildSheets(
        ticker: String, price: Double, shares: Double, basisOrig: Double, basisEff: Double, premPerShare: Double,
        overBE: Double, sharesPL: Double, netPL: Double, premLife: Double, premYield: Double, contractsWritten: Int,
        contractsTotal: Int, uncovered: Int, coveredPct: Int, strike: Double, strikeDist: Double, expiry: String,
        dte: Int, creditOpen: Double, iv: Double, assignGain: Double, protectPct: Double, weeks: [PosWeek],
        bigWeekLabel: String, bigWeekVal: Double, bigWeekPct: Int
    ) -> [String: NVSheet] {
        let shN = Int(shares.rounded()).formatted(.number.grouping(.automatic))
        var s: [String: NVSheet] = [:]

        s["shares"] = NVSheet(cat: "Stock", title: "Long NVDA", sub: "\(shN) shares",
            hero: compact(shares * price), heroUnit: "market value · \(fmtMoney(price, decimals: 2)) last",
            line: "Premium has moved the line you must clear down to \(fmtMoney(basisEff, decimals: 2)). The stock is \(fmtMoney(overBE, decimals: 2)) above it.",
            rows: [
                SheetRow(name: "Original cost", sub: "\(shN) sh", val: fmtMoney(basisOrig, decimals: 2), tone: .fg1),
                SheetRow(name: "Premium collected", sub: "−" + fmtMoney(premPerShare, decimals: 2) + "/sh", val: "−" + fmtMoney(premLife), tone: .pos),
                SheetRow(name: "Break-even now", sub: "effective basis", val: fmtMoney(basisEff, decimals: 2), tone: .neon),
                SheetRow(name: "Shares P&L", sub: "vs original cost", val: fmtMoney(sharesPL, sign: true), tone: .neg),
                SheetRow(name: "Net P&L", sub: "premium included", val: fmtMoney(netPL, sign: true), tone: .pos),
            ], isVol: false)

        s["calls"] = NVSheet(cat: "Calls written", title: strike > 0 ? "\(fmtStrike(strike))c · \(AppDates.shortMonthDay(expiry))" : "No open calls",
            sub: "\(contractsWritten) contracts · \(dte) DTE",
            hero: fmtMoney(creditOpen, sign: true), heroUnit: "credit open · \(String(format: "%.1f", strikeDist))% out of the money",
            line: strike > 0 ? "Assignment at \(fmtStrike(strike)) pays \(fmtMoney(assignGain, decimals: 2)) a share over break-even. Roll up before the strike is threatened, not after." : "No calls are open right now.",
            rows: [
                SheetRow(name: "Contracts", sub: "sold", val: "\(contractsWritten) of \(contractsTotal)", tone: .fg1),
                SheetRow(name: "Strike", sub: String(format: "%.1f", strikeDist) + "% above spot", val: fmtStrike(strike), tone: .fg1),
                SheetRow(name: "Credit taken", sub: "open", val: fmtMoney(creditOpen, sign: true), tone: .pos),
                SheetRow(name: "Days to expiry", sub: AppDates.shortMonthDay(expiry), val: "\(dte)d", tone: .fg1),
                SheetRow(name: "If assigned", sub: "vs break-even", val: fmtMoney(assignGain, sign: true, decimals: 2) + "/sh", tone: .pos),
            ], isVol: false)

        s["uncov"] = NVSheet(cat: "Unwritten", title: "Room to write", sub: "\(uncovered) contracts free",
            hero: "\(uncovered)×", heroUnit: "\((uncovered * 100).formatted(.number.grouping(.automatic))) shares uncovered",
            line: "IV sits at \(String(format: "%.1f", iv))% — write the free lots when it's rich vs realized.",
            rows: [
                SheetRow(name: "Shares held", sub: "total", val: shN, tone: .fg1),
                SheetRow(name: "Covered", sub: "\(coveredPct)% of the lot", val: "\(contractsWritten)00 sh", tone: .fg1),
                SheetRow(name: "Uncovered", sub: "free to write", val: "\((uncovered * 100).formatted(.number.grouping(.automatic))) sh", tone: .neon),
                SheetRow(name: "Implied vol", sub: "front month", val: String(format: "%.1f%%", iv), tone: .fg1),
            ], isVol: false)

        s["earned"] = NVSheet(cat: "Return", title: "What the position earned", sub: "since the first write",
            hero: fmtMoney(netPL, sign: true), heroUnit: "net · premium \(String(format: "%.2f", premYield))% of value",
            line: "Premium is carrying the position: \(fmtMoney(premLife)) collected against \(fmtMoney(abs(sharesPL))) of unrealized share loss.",
            rows: [
                SheetRow(name: "Premium income", sub: "lifetime", val: fmtMoney(premLife, sign: true), tone: .pos),
                SheetRow(name: "Shares", sub: "unrealized", val: fmtMoney(sharesPL, sign: true), tone: .neg),
                SheetRow(name: "Net", sub: "both legs", val: fmtMoney(netPL, sign: true), tone: .neon),
                SheetRow(name: "Premium yield", sub: "on position value", val: String(format: "%.2f%%", premYield), tone: .fg1),
                SheetRow(name: "Cushion", sub: "off the share price", val: String(format: "%.1f%%", protectPct), tone: .pos),
            ], isVol: false)

        var premRows: [SheetRow] = weeks.reversed().map {
            SheetRow(name: "Week of \($0.w)", sub: $0.note, val: $0.v > 0 ? fmtMoney($0.v, sign: true) : "—", tone: $0.v > 0 ? .pos : .fg3)
        }
        premRows.append(SheetRow(name: "Lifetime", sub: String(format: "%.1f", protectPct) + "% downside protection", val: fmtMoney(premLife, sign: true), tone: .neon))
        s["prem"] = NVSheet(cat: "Premium", title: "Where premium lands", sub: "by write week · \(ticker)",
            hero: fmtMoney(premLife, sign: true), heroUnit: "lifetime · \(String(format: "%.1f", protectPct))% cushion",
            line: bigWeekVal > 0 ? "Week of \(bigWeekLabel) carried \(fmtMoney(bigWeekVal)) of \(fmtMoney(premLife)) — \(bigWeekPct)% of everything collected." : "Premium collected across your write weeks.",
            rows: premRows, isVol: false)
        return s
    }
}
