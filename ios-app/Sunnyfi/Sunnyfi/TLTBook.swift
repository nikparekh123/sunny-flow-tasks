//
//  TLTBook.swift
//  Sunnyfi — the second book · TLT
//
//  TLT reuses NVDA's whole card grammar (position, insights, peers, history), so
//  it rides the same NvdaStore the screens already read from — here filled with
//  the handoff's TLT fixture rather than a live feed. The genuinely TLT-only
//  surfaces (hike odds, rates & range, vol & engine, voter bloc, macro calendar)
//  live alongside as their own fixtures. Swap these for the real book next week:
//  hydrate the same shapes and the screens light up unchanged.
//

import Foundation

enum TLTBook {
    static let spot: Double = 91.42
    static let high52: Double = 99.86

    // ── position: shares + option legs, same shapes as NVDA ──
    private static let groups: [NvGroup] = [
        NvGroup(label: "Calls sold", glyph: "▲", strikes: [
            NvStrike(side: "short", kind: "call", strike: 90, expiry: "Aug 21 '26", dte: "13 DTE", expired: false,
                     ct: 6, basis: 900, current: 1164, mark: 1.94, moneyness: "ITM", delta: 0.612, theta: -0.034, deltaEst: -367),
            NvStrike(side: "short", kind: "call", strike: 92, expiry: "Sep 18 '26", dte: "41 DTE", expired: false,
                     ct: 10, basis: 1700, current: 1620, mark: 1.62, moneyness: "OTM", delta: 0.442, theta: -0.021, deltaEst: -442),
            NvStrike(side: "short", kind: "call", strike: 94, expiry: "Oct 16 '26", dte: "69 DTE", expired: false,
                     ct: 5, basis: 725, current: 640, mark: 1.28, moneyness: "OTM", delta: 0.331, theta: -0.016, deltaEst: -166)]),
        NvGroup(label: "Calls bought", glyph: "△", strikes: [
            NvStrike(side: "long", kind: "call", strike: 100, expiry: "Jan 15 '27", dte: "160 DTE", expired: false,
                     ct: 10, basis: 820, current: 710, mark: 0.71, moneyness: "OTM", delta: 0.148, theta: -0.008, deltaEst: 148)]),
        NvGroup(label: "Puts bought", glyph: "▽", strikes: [
            NvStrike(side: "long", kind: "put", strike: 90, expiry: "Dec 18 '26", dte: "132 DTE", expired: false,
                     ct: 10, basis: 2750, current: 3050, mark: 3.05, moneyness: "OTM", delta: -0.412, theta: -0.011, deltaEst: -412),
            NvStrike(side: "long", kind: "put", strike: 85, expiry: "Jan 15 '27", dte: "160 DTE", expired: false,
                     ct: 15, basis: 2880, current: 2430, mark: 1.62, moneyness: "OTM", delta: -0.238, theta: -0.009, deltaEst: -357),
            NvStrike(side: "long", kind: "put", strike: 100, expiry: "Jan 15 '27", dte: "160 DTE", expired: false,
                     ct: 4, basis: 3520, current: 3740, mark: 9.35, moneyness: "ITM", delta: -0.842, theta: -0.005, deltaEst: -337)]),
    ]

    private static let sleeves: [NvSleeve] = [
        NvSleeve(name: "Calls sold", side: "short", kind: "call", qty: 21, basisLabel: "collected", basis: 3325),
        NvSleeve(name: "Calls bought", side: "long", kind: "call", qty: 10, basisLabel: "paid", basis: 820),
        NvSleeve(name: "Puts bought", side: "long", kind: "put", qty: 29, basisLabel: "paid", basis: 9150),
    ]

    private static var position: NvPosition {
        // net delta ≈ shares + Σ leg deltaEst = 3000 − 1933
        NvPosition(
            spot: spot, dayChangePct: 0.34, shares: 3000, avgBuy: 94.20, sharesPaid: 282600,
            sharesValue: 274260, sharesPL: -8340, premiumPerShare: 2.29, breakEven: 91.91,
            delta: 1067, gamma: -12, theta: 186, optionsPL: -139, pnl: -8479, contractsOpen: 60,
            sleeves: sleeves, groups: groups, fresh: .delayed, freshText: "Sample book · TLT feed pending")
    }

    private static var perf: NvPerf {
        NvPerf(realized: 4120, lifetime: 6870, perShare: 2.29, perSharePct: 2.43,
               costBasis: 94.20, breakEven: 91.91, cushion: -0.49, cushionPct: -0.53, sleeves: [
            NvPerfSleeve(name: "Shares", glyph: "○", total: 3000, basisLabel: "Paid", basis: 282600, realized: 0, unrealized: -8340, empty: false),
            NvPerfSleeve(name: "Calls sold", glyph: "▲", total: 21, basisLabel: "Collected", basis: 3325, realized: 4120, unrealized: 66, empty: false),
            NvPerfSleeve(name: "Calls bought", glyph: "△", total: 10, basisLabel: "Paid", basis: 820, realized: 0, unrealized: -110, empty: false),
            NvPerfSleeve(name: "Puts bought", glyph: "▽", total: 29, basisLabel: "Paid", basis: 9150, realized: 0, unrealized: 70, empty: false),
            NvPerfSleeve(name: "Puts sold", glyph: "▼", total: 0, basisLabel: "Collected", basis: 0, realized: 0, unrealized: 0, empty: true),
        ])
    }

    // insights: seller score in the app's own convention (IV/HV30 × percentile factor)
    private static var insights: NvInsights {
        let iv = 14.2, hv = 12.1
        return NvInsights(
            protection: NvProtection(putContracts: 29, shares: 3000, covered: 2500, coveredPct: 83,
                                     floorLow: 85, floorHigh: 100, uncovered: 500,
                                     cushion: -0.49, cushionPct: -0.53, empty: false),
            vol: NvVol(score: iv / hv, verdict: NvSellZone.label(iv / hv), iv: iv, ivPrev: 13.6, hv30: hv,
                       ivr: 36, factor: 1.0, iv52Low: 9.4, iv52High: 22.6, spread: 2.1, building: false),
            vega: NvVega(iv: iv, avg30: 15.6, lo: 9, hi: 23, net: 370, stance: "long vega", daysToEarnings: 39, legs: [
                NvVegaLeg(name: "Puts bought", kind: "put", side: "long", ct: 29, v: 412),
                NvVegaLeg(name: "Calls bought", kind: "call", side: "long", ct: 10, v: 96),
                NvVegaLeg(name: "Calls sold", kind: "call", side: "short", ct: 36, v: -138),
            ]),
            fresh: .delayed)
    }

    // peers: TLT vs its rate-duration cohort
    private static func tape(_ tk: String, _ name: String, _ group: String, _ last: Double, _ pcts: [Double], nvNet: Double?) -> NvPeerTape {
        var closes = [Double](repeating: 0, count: pcts.count)
        var c = last
        for i in stride(from: pcts.count - 1, through: 0, by: -1) { closes[i] = (c * 100).rounded() / 100; c = c / (1 + pcts[i] / 100) }
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri"]
        let days = pcts.enumerated().map { i, p in NvPeerDay(label: labels[min(i, 4)], close: closes[i], pct: p) }
        let net = ((pcts.reduce(1.0) { $0 * (1 + $1 / 100) }) - 1) * 100
        let vs: Double? = (group != "self" && nvNet != nil) ? (net - nvNet!) : nil
        return NvPeerTape(ticker: tk, name: name, group: group, last: last, net: (net * 10).rounded() / 10,
                          days: days, vsNvda: vs.map { ($0 * 10).rounded() / 10 })
    }
    private static var peers: NvPeers {
        let tltNet = ((([0.62, -0.41, 0.88, -0.25, 0.34].reduce(1.0) { $0 * (1 + $1 / 100) }) - 1) * 100)
        return NvPeers(tapes: [
            tape("TLT", "20-year Treasuries", "self", 91.42, [0.62, -0.41, 0.88, -0.25, 0.34], nvNet: nil),
            tape("IEF", "7–10 year", "ETFs", 96.18, [0.34, -0.22, 0.51, -0.14, 0.19], nvNet: tltNet),
            tape("SHY", "1–3 year", "ETFs", 83.44, [0.08, -0.05, 0.12, -0.03, 0.05], nvNet: tltNet),
            tape("TLH", "10–20 year", "ETFs", 108.62, [0.51, -0.34, 0.72, -0.20, 0.27], nvNet: tltNet),
            tape("AGG", "Aggregate", "Peers", 99.05, [0.21, -0.14, 0.33, -0.09, 0.12], nvNet: tltNet),
            tape("LQD", "Investment grade", "Peers", 111.30, [0.28, -0.19, 0.42, -0.12, 0.16], nvNet: tltNet),
        ], fresh: .delayed)
    }

    // history: a couple of months of session P&L at TLT scale
    private static func bar(_ iso: String, _ sub: String, _ v: [String: Double]) -> NvHistBar {
        NvHistBar(iso: iso, label: String(iso.suffix(2)), sub: sub, pending: false, vals: v)
    }
    private static var history: NvHistory {
        NvHistory(months: [
            NvHistMonth(label: "June", short: "Jun", bars: [
                bar("2026-06-15", "Jun 15", ["shares": 900, "callsSold": 240]),
                bar("2026-06-22", "Jun 22", ["shares": -600, "putsBought": -80]),
                bar("2026-06-29", "Jun 29", ["shares": 1100, "callsSold": 180]),
            ]),
            NvHistMonth(label: "July", short: "Jul", bars: [
                bar("2026-07-06", "Jul 6", ["shares": 520, "callsSold": 200]),
                bar("2026-07-13", "Jul 13", ["shares": -320, "callsBought": 60]),
                bar("2026-07-20", "Jul 20", ["shares": 780, "callsSold": 210]),
                bar("2026-07-27", "Jul 27", ["shares": -240, "putsBought": -50]),
            ]),
        ], sources: [
            NvHistSource(key: "shares", label: "Shares", glyph: "○", empty: false),
            NvHistSource(key: "callsSold", label: "Calls sold", glyph: "▲", empty: false),
            NvHistSource(key: "callsBought", label: "Calls bought", glyph: "△", empty: false),
            NvHistSource(key: "putsSold", label: "Puts sold", glyph: "▼", empty: true),
            NvHistSource(key: "putsBought", label: "Puts bought", glyph: "▽", empty: false),
        ], fresh: .delayed)
    }

    // ── TLT-only insight fixtures (the three bond cards) ──
    struct Hike { let meeting: String; let odds: Int; let trend: String
        let series: [Double]; let next: [(d: String, p: Int)]; let rule: String }
    struct Rates { let y10: Double; let y30: Double; let cycleHigh: Double; let sma25: Double
        let exit: Double; let assign: Double; let rule: String }
    struct Engine { let iv: Double; let hv20: Double; let move: Int
        let sold: String; let price: Double; let premium: Int; let expires: String; let restrike: String
        var spread: Double { (iv - hv20 * 10).rounded() / 10 }
        var verdict: String { spread >= 4 ? "Sell hard" : spread >= 1 ? "Sell normal" : "Ease off" } }

    static let hike = Hike(
        meeting: "Sep 16", odds: 31, trend: "rising · 3 weeks",
        series: [17, 18, 18, 16, 19, 21, 20, 22, 21, 23, 22, 24, 26, 25, 27, 26, 28, 27, 29, 28, 30, 29, 28, 30, 31, 30, 32, 31, 30, 31],
        next: [(d: "Oct 28", p: 44), (d: "Dec 9", p: 52)],
        rule: "Crosses 50% and I stop selling calls into FOMC week — the hike wing goes live.")
    static let rates = Rates(
        y10: 4.58, y30: 5.12, cycleHigh: 4.62, sma25: 92.6, exit: 78, assign: 92,
        rule: "A September hike and a close under 78 ends it — stop buying floors, wind the sleeve down.")
    static let engine = Engine(
        iv: 13.8, hv20: 11.7, move: 92, sold: "−7 · Aug 10 '26 · 83 C", price: 0.41, premium: 287,
        expires: "Monday · settles before CPI",
        restrike: "Tuesday · CPI week, so it is a conscious decision")

    // The next scheduled evidence the September question is judged against.
    static let evidence = (label: "CPI", inDays: 4)

    // ── macro calendar (the long-end's scheduled events) ──
    struct MacroLast { let label: String; let what: String; let move: Double }
    struct MacroDate: Identifiable { let d: String; let label: String; let tag: String; let last: MacroLast?
        var inDays: Int = 0; var id: String { d + label } }
    struct MacroClass: Identifiable { let key: String; let name: String; let cat: String; let last: MacroLast
        var dates: [MacroDate]; var id: String { key } }

    /// Days from the book's "today" (Aug 8 2026, matching the published calendar).
    private static func daysTo(_ iso: String) -> Int {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = cal.timeZone
        let today = cal.date(from: DateComponents(year: 2026, month: 8, day: 8)) ?? Date()
        guard let d = f.date(from: iso) else { return 0 }
        return cal.dateComponents([.day], from: cal.startOfDay(for: today), to: cal.startOfDay(for: d)).day ?? 0
    }

    static let macro: [MacroClass] = {
        var m: [MacroClass] = [
            MacroClass(key: "fomc", name: "FOMC", cat: "Rate decisions",
                       last: MacroLast(label: "Jul 29", what: "Held · no cut signalled", move: 0.8), dates: [
                MacroDate(d: "2026-09-16", label: "Sep 15–16", tag: "SEP · projections", last: nil),
                MacroDate(d: "2026-10-28", label: "Oct 27–28", tag: "statement only", last: MacroLast(label: "Sep 16", what: "Projections revised up", move: -0.9)),
                MacroDate(d: "2026-12-09", label: "Dec 8–9", tag: "SEP · projections", last: MacroLast(label: "Oct 28", what: "Statement held, no dots", move: 0.3)),
            ]),
            MacroClass(key: "prints", name: "Inflation prints", cat: "CPI and PCE",
                       last: MacroLast(label: "Jul 15", what: "Core hotter by 0.1", move: -1.4), dates: [
                MacroDate(d: "2026-08-12", label: "Aug 12", tag: "CPI · July", last: nil),
                MacroDate(d: "2026-08-28", label: "Aug 28", tag: "Core PCE · July", last: MacroLast(label: "Jun 26", what: "Core PCE in line", move: 0.5)),
                MacroDate(d: "2026-09-10", label: "Sep 10", tag: "CPI · August", last: nil),
                MacroDate(d: "2026-10-13", label: "Oct 13", tag: "CPI · September", last: MacroLast(label: "Jul 15", what: "Core hotter by 0.1", move: -1.4)),
            ]),
            MacroClass(key: "auctions", name: "Auctions", cat: "Long-end supply",
                       last: MacroLast(label: "Jul 10", what: "30-year tailed 1.2bp", move: -0.6), dates: [
                MacroDate(d: "2026-08-13", label: "Aug 13", tag: "30-year · reopening", last: nil),
                MacroDate(d: "2026-08-19", label: "Aug 19", tag: "20-year · new issue", last: MacroLast(label: "Jul 22", what: "20-year stopped through", move: 0.4)),
                MacroDate(d: "2026-08-20", label: "Aug 20", tag: "30-year TIPS", last: MacroLast(label: "Jun 18", what: "TIPS bid thin, breakevens widened", move: -0.2)),
                MacroDate(d: "2026-09-10", label: "Sep 10", tag: "30-year · new issue", last: MacroLast(label: "Aug 13", what: "30-year reopening tailed", move: -0.6)),
            ]),
            MacroClass(key: "refunding", name: "Refunding", cat: "Quarterly announcement",
                       last: MacroLast(label: "Aug 5", what: "Coupon sizes unchanged", move: 1.1), dates: [
                MacroDate(d: "2026-11-04", label: "Nov 4", tag: "Q4 refunding", last: nil),
                MacroDate(d: "2027-02-03", label: "Feb 3 '27", tag: "Q1 refunding", last: MacroLast(label: "Nov 4", what: "Q4 sizes unchanged", move: 1.1)),
            ]),
        ]
        for i in m.indices { for j in m[i].dates.indices { m[i].dates[j].inDays = daysTo(m[i].dates[j].d) } }
        return m
    }()

    /// An NvdaStore filled with the TLT fixture — the section screens read it
    /// exactly as they read the live NVDA store.
    /// Reads the real book. The tlt_mirror cron forwards ticker='TLT' out of the legacy
    /// tables into tlt_*, so this is the same store NVDA uses pointed at a different
    /// prefix. Fills arrive split across executions — five contracts as 1+3+1 — and the
    /// store pools them by strike and expiry, which is why this cannot just list rows.
    @MainActor static func store() -> NvdaStore {
        let s = NvdaStore(prefix: "tlt")
        Task { await s.fetch() }
        return s
    }
}
