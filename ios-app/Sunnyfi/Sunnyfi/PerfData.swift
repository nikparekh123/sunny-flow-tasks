//
//  PerfData.swift
//  Sunnyfi
//
//  NVDA Performance (Perf tab) — handoff 6. Net P&L since first write,
//  gains & losses by source over Week/Month/Year, the premium-by-expiry
//  ledger, and the by-source rail. Shares P&L is real daily mark-to-market
//  from daily_closes; the short-call leg is a delta≈0.25 model per day (we
//  don't store daily option marks), while the realized totals are real.
//

import Foundation

enum PerfSource: String, CaseIterable, Sendable { case shares, calls }

struct PerfBar: Identifiable, Sendable {
    let label: String
    let sub: String
    let shares: Double
    let calls: Double
    var id: String { sub }
    func val(_ s: PerfSource) -> Double { s == .shares ? shares : calls }
}

struct PerfPeriodModel: Identifiable, Sendable {
    let id: String           // week | month | year
    let label: String
    let title: String
    let bars: [PerfBar]
    let ticks: [Int: String]?
}

/// Handoff 7 — the Gains & losses view is one calendar month at a time,
/// picked from a scrollable month rail. `bars` are that month's trading
/// sessions (real daily shares MTM + modeled short-call leg).
struct PerfMonth: Identifiable, Sendable {
    let key: String          // yyyy-MM
    let short: String        // "Jul"
    let label: String        // "July 2026"
    let bars: [PerfBar]
    let net: Double
    var id: String { key }
}

struct PerfExpiry: Identifiable, Sendable {
    let ex: String
    let strike: Double
    let qty: Int
    let prem: Double
    let cost: Double
    let net: Double
    let status: String
    let open: Bool
    var id: String { ex + "-" + String(strike) }
}

struct PerfSrc: Identifiable, Sendable {
    let key: String
    let label: String
    let colorKey: String     // neon|oi|earnings|gold|note
    let empty: Bool
    let today: Double
    let chip: String
    let flowLbl: String
    let flowVal: String
    let nowLbl: String
    let nowVal: String
    let name: String
    let sub: String
    var id: String { key }
}

struct PerfData: Sendable {
    let ticker: String
    let shares: Double
    let premLife: Double
    let sharesPL: Double
    let netPL: Double
    let premYield: Double
    let months: [PerfMonth]
    let expiries: [PerfExpiry]
    let expNet: Double
    let sources: [PerfSrc]
    let sheets: [String: NVSheet]

    static func build(store: PortfolioStore, today: Date = Date()) -> PerfData? {
        let ticker = "NVDA"
        guard let cc = store.cachedCoveredCall(ticker: ticker) else { return nil }
        let shares = cc.shares
        let price = cc.currentPrice
        let basisOrig = cc.current?.entryPrice ?? 0
        let basisEff = cc.currentAverage
        let premLife = cc.lifetimePremium
        let sharesPL = (price - basisOrig) * shares
        let netPL = sharesPL + premLife
        let posValue = shares * price
        let premYield = posValue > 0 ? premLife / posValue * 100 : 0

        let hist = store.dailyCloses.filter { $0.ticker.uppercased() == ticker }
            .sorted { $0.date < $1.date }        // oldest → newest
        // add today's live price as the latest point
        let series: [(String, Double)] = hist.map { ($0.date, $0.close_price) } + [(isoToday(today), price)]

        // ── Sessions: real daily shares MTM + modeled short-call leg,
        //    grouped by calendar month for the Gains & losses month rail ──
        var sessions: [(iso: String, shares: Double, calls: Double)] = []
        for i in 1..<series.count {
            let sh = (series[i].1 - series[i - 1].1) * shares
            sessions.append((series[i].0, sh, (-sh * 0.25).rounded()))
        }
        var byMon: [String: [(iso: String, shares: Double, calls: Double)]] = [:]
        for s in sessions { byMon[String(s.iso.prefix(7)), default: []].append(s) }
        let mfmt = DateFormatter(); mfmt.dateFormat = "yyyy-MM"; mfmt.timeZone = TimeZone(identifier: "America/New_York")
        let mShort = DateFormatter(); mShort.dateFormat = "MMM"; mShort.timeZone = TimeZone(identifier: "America/New_York")
        let mLong = DateFormatter(); mLong.dateFormat = "MMMM yyyy"; mLong.timeZone = TimeZone(identifier: "America/New_York")
        let months: [PerfMonth] = byMon.keys.sorted().map { mk in
            let sess = byMon[mk]!
            let bars = sess.map { PerfBar(label: String($0.iso.suffix(2)), sub: AppDates.shortMonthDay($0.iso),
                                          shares: $0.shares, calls: $0.calls) }
            let net = sess.reduce(0.0) { $0 + $1.shares + $1.calls }
            let dt = mfmt.date(from: mk)
            return PerfMonth(key: mk, short: dt.map { mShort.string(from: $0) } ?? mk,
                             label: dt.map { mLong.string(from: $0) } ?? mk, bars: bars, net: net)
        }

        // ── expiry ledger from real rollups ──
        let expiries: [PerfExpiry] = cc.allRollups
            .sorted { $0.expiry < $1.expiry }
            .map { r in
                let open = r.status == .open
                return PerfExpiry(ex: AppDates.shortMonthDay(r.expiry), strike: r.strike, qty: contractsAsQty(r),
                           prem: max(0, r.credit), cost: max(0, r.buyback), net: r.net,
                           status: open ? "open · \(max(0, AppDates.daysUntil(r.expiry, from: today) ?? 0)) DTE" :
                               (r.status == .assigned ? "assigned" : "expired · kept"), open: open)
            }
        let expNet = expiries.reduce(0) { $0 + $1.net }

        // ── by-source rail (real) ──
        let openCallCost = cc.openCallCostToClose
        let putVal = cc.putValueTotal, putCost = cc.putCostTotal
        let longCallCost = cc.longCallLegs.reduce(0.0) { $0 + $1.basis }
        let longCallVal = cc.longCallLegs.reduce(0.0) { $0 + $1.marketValue }
        let hasLongCalls = !cc.longCallLegs.isEmpty, hasPuts = !cc.putLegs.isEmpty
        let sources: [PerfSrc] = [
            PerfSrc(key: "callsSold", label: "Calls sold", colorKey: "oi", empty: false,
                    today: premLife - openCallCost, chip: "open + closed",
                    flowLbl: "Collected", flowVal: fmtMoney(premLife), nowLbl: "Cost to close", nowVal: "−" + fmtMoney(openCallCost),
                    name: "Premium is the engine", sub: "\(expiries.count) expiries · \(String(format: "%.2f", premYield))% of value"),
            PerfSrc(key: "callsBought", label: "Calls bought", colorKey: "earnings", empty: !hasLongCalls,
                    today: hasLongCalls ? longCallVal - longCallCost : 0, chip: hasLongCalls ? "LEAP overlay" : "none open",
                    flowLbl: "Paid", flowVal: hasLongCalls ? fmtMoney(longCallCost) : "—", nowLbl: "Value today", nowVal: hasLongCalls ? fmtMoney(longCallVal) : "—",
                    name: hasLongCalls ? "Upside overlay" : "No upside overlay", sub: hasLongCalls ? "long calls above the short strike" : "nothing bought above the short strike"),
            PerfSrc(key: "putsSold", label: "Puts sold", colorKey: "gold", empty: true,
                    today: 0, chip: "none open", flowLbl: "Collected", flowVal: "—", nowLbl: "Cost to close", nowVal: "—",
                    name: "No cash-secured puts", sub: "capital sits in shares and written calls"),
            PerfSrc(key: "putsBought", label: "Puts bought", colorKey: "note", empty: !hasPuts,
                    today: hasPuts ? putVal - putCost : 0, chip: hasPuts ? "protection" : "none open",
                    flowLbl: "Paid", flowVal: hasPuts ? fmtMoney(putCost) : "—", nowLbl: "Value today", nowVal: hasPuts ? fmtMoney(putVal) : "—",
                    name: hasPuts ? "Downside protected" : "Downside is uncovered", sub: hasPuts ? "long puts under the position" : "premium is the only cushion"),
            PerfSrc(key: "shares", label: "Shares", colorKey: "neon", empty: false,
                    today: sharesPL, chip: "unrealized",
                    flowLbl: "Paid", flowVal: compact(shares * basisOrig), nowLbl: "Value today", nowVal: compact(posValue),
                    name: sharesPL >= 0 ? "Stock above cost" : "Stock is underwater", sub: "\(Int(shares).formatted(.number.grouping(.automatic))) shares · break-even \(fmtMoney(basisEff, decimals: 2))"),
        ]

        let sheets = buildSheets(ticker: ticker, shares: shares, price: price, basisOrig: basisOrig, basisEff: basisEff,
                                 premLife: premLife, sharesPL: sharesPL, netPL: netPL, premYield: premYield,
                                 expiries: expiries, expNet: expNet, sources: sources)

        return PerfData(ticker: ticker, shares: shares, premLife: premLife, sharesPL: sharesPL, netPL: netPL,
                        premYield: premYield, months: months, expiries: expiries, expNet: expNet, sources: sources, sheets: sheets)
    }

    // ── helpers ──
    private static func contractsAsQty(_ r: ExpiryRollup) -> Int { Int(r.contracts.rounded()) }
    private static func periodTitle(_ bars: [PerfBar]) -> String {
        guard let f = bars.first, let l = bars.last else { return "" }
        return "\(f.sub) – \(l.sub)"
    }
    private static func isoToday(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "America/New_York")
        return f.string(from: d)
    }
    private static func compact(_ v: Double) -> String {
        if abs(v) >= 1_000_000 { return String(format: "$%.2fM", v / 1_000_000) }
        if abs(v) >= 1_000 { return String(format: "$%.0fK", v / 1_000) }
        return fmtMoney(v)
    }

    private static func buildSheets(
        ticker: String, shares: Double, price: Double, basisOrig: Double, basisEff: Double, premLife: Double,
        sharesPL: Double, netPL: Double, premYield: Double, expiries: [PerfExpiry], expNet: Double, sources: [PerfSrc]
    ) -> [String: NVSheet] {
        var s: [String: NVSheet] = [:]
        let shN = Int(shares.rounded()).formatted(.number.grouping(.automatic))

        s["callsSold"] = NVSheet(cat: "Calls sold", title: "Premium collected", sub: "\(ticker) · lifetime",
            hero: fmtMoney(premLife, sign: true), heroUnit: "\(expiries.count) expiries · \(String(format: "%.2f", premYield))% of value",
            line: "Every dollar written lowers break-even. Cost basis \(fmtMoney(basisOrig, decimals: 2)) → \(fmtMoney(basisEff, decimals: 2)).",
            rows: expiries.map { SheetRow(name: "\($0.ex) · \(fmtStrike($0.strike))c ×\($0.qty)", sub: $0.status, val: fmtMoney($0.net, sign: true), tone: $0.net >= 0 ? .pos : .neg) }
                + [SheetRow(name: "Net premium", sub: "realized + open", val: fmtMoney(premLife, sign: true), tone: .neon)], isVol: false)

        s["shares"] = NVSheet(cat: "Shares", title: "Stock mark-to-market", sub: "\(shN) shares",
            hero: fmtMoney(sharesPL, sign: true), heroUnit: "unrealized vs \(fmtMoney(basisOrig, decimals: 2))",
            line: "Unrealized on the stock alone. Premium covers it \(String(format: "%.1f", abs(sharesPL) > 0 ? premLife / abs(sharesPL) : 0))× over, so the position is net positive.",
            rows: [
                SheetRow(name: "Shares", sub: "held", val: shN, tone: .fg1),
                SheetRow(name: "Original cost", sub: "per share", val: fmtMoney(basisOrig, decimals: 2), tone: .fg1),
                SheetRow(name: "Last price", sub: "live", val: fmtMoney(price, decimals: 2), tone: .fg1),
                SheetRow(name: "Unrealized", sub: "vs original cost", val: fmtMoney(sharesPL, sign: true), tone: .neg),
                SheetRow(name: "Net with premium", sub: "both legs", val: fmtMoney(netPL, sign: true), tone: .neon),
            ], isVol: false)

        for e in expiries {
            s["exp-\(e.ex)"] = NVSheet(cat: "Expiry", title: "\(e.ex) · \(fmtStrike(e.strike))c", sub: "\(e.qty) contracts",
                hero: fmtMoney(e.net, sign: true), heroUnit: e.status,
                line: e.open ? "Still open. Closing here costs \(fmtMoney(e.cost)), leaving \(fmtMoney(e.net)) of the credit."
                             : "\(e.status.capitalized) — booked \(fmtMoney(e.net, sign: true)).",
                rows: [
                    SheetRow(name: "Credit taken", sub: "at write", val: fmtMoney(e.prem, sign: true), tone: .pos),
                    SheetRow(name: "Cost to close", sub: e.open ? "current mark" : "closed", val: e.cost > 0 ? "−" + fmtMoney(e.cost) : "—", tone: e.cost > 0 ? .neg : .fg3),
                    SheetRow(name: "Net", sub: "this expiry", val: fmtMoney(e.net, sign: true), tone: .neon),
                    SheetRow(name: "Strike", sub: "vs \(fmtMoney(price, decimals: 2))", val: fmtStrike(e.strike), tone: .fg1),
                    SheetRow(name: "Contracts", sub: "sold", val: "\(e.qty)", tone: .fg1),
                ], isVol: false)
        }

        for src in sources where src.key != "callsSold" && src.key != "shares" {
            s[src.key] = NVSheet(cat: src.label, title: src.name, sub: "\(ticker)",
                hero: src.empty ? "—" : fmtMoney(src.today, sign: true), heroUnit: src.chip,
                line: src.sub,
                rows: [
                    SheetRow(name: src.flowLbl, sub: "lifetime", val: src.flowVal, tone: src.empty ? .fg3 : .pos),
                    SheetRow(name: src.nowLbl, sub: "today", val: src.nowVal, tone: src.empty ? .fg3 : .fg1),
                ], isVol: false)
        }
        return s
    }
}
