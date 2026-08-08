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

    /// An NvdaStore filled with the TLT fixture — the section screens read it
    /// exactly as they read the live NVDA store.
    @MainActor static func store() -> NvdaStore {
        let s = NvdaStore()
        s.isLoading = false
        s.position = position
        s.perf = perf
        s.insights = insights
        s.peers = peers
        s.history = history
        s.seedCloses([high52, high52 * 0.98, spot])   // so high52 resolves for Average-down
        return s
    }
}
