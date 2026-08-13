//
//  InkDesignPreview.swift
//  Sunnyfi — DEBUG-only visual harness
//
//  Renders Sections 3–5 against a mock store so the Ink screens can be
//  screenshotted without signing in. Launch with the `-inkPreview` argument.
//  Not reachable in a normal run; safe to delete once design is confirmed.
//

#if DEBUG
import SwiftUI

enum InkPreviewData {
    static func store() -> NvdaStore {
        let s = NvdaStore()
        s.isLoading = false
        s.position = NvPosition(
            spot: 194.57, dayChangePct: -1.12, shares: 5001, avgBuy: 209.18, sharesPaid: 1046116,
            sharesValue: 973183, sharesPL: -77380, premiumPerShare: 2.12, breakEven: 207.06,
            delta: 3914, gamma: 42, theta: -285, optionsPL: 6194, pnl: -45254, contractsOpen: 70,
            sleeves: [
                NvSleeve(name: "Calls sold", side: "short", kind: "call", qty: 10, basisLabel: "collected", basis: 8310),
                NvSleeve(name: "Puts bought", side: "long", kind: "put", qty: 50, basisLabel: "paid", basis: 541989),
            ],
            groups: [
                NvGroup(label: "Calls sold", glyph: "▲", strikes: [
                    NvStrike(side: "short", kind: "call", strike: 220, expiry: "Aug 15 '26", dte: "18 DTE", expired: false,
                             ct: 10, basis: 8310, current: 2800, mark: 2.80, moneyness: "OTM", delta: 0.32, theta: -0.12, deltaEst: -320),
                    NvStrike(side: "short", kind: "call", strike: 240, expiry: "Sep 19 '26", dte: "53 DTE", expired: false,
                             ct: 5, basis: 3100, current: 1500, mark: 3.00, moneyness: "OTM", delta: 0.18, theta: -0.08, deltaEst: -90)]),
                NvGroup(label: "Puts bought", glyph: "▽", strikes: [
                    NvStrike(side: "long", kind: "put", strike: 190, expiry: "Sep 18 '26", dte: "51 DTE", expired: false,
                             ct: 5, basis: 5384, current: 4690, mark: 9.38, moneyness: "OTM", delta: -0.28, theta: -0.03, deltaEst: -140),
                    NvStrike(side: "long", kind: "put", strike: 200, expiry: "Jan 15 '27", dte: "170 DTE", expired: false,
                             ct: 10, basis: 20250, current: 22680, mark: 22.68, moneyness: "ITM", delta: -0.42, theta: -0.03, deltaEst: -420),
                    NvStrike(side: "long", kind: "put", strike: 300, expiry: "Jan 15 '27", dte: "170 DTE", expired: false,
                             ct: 3, basis: 26130, current: 30924, mark: 103.08, moneyness: "ITM", delta: -0.88, theta: -0.02, deltaEst: -264),
                    NvStrike(side: "long", kind: "put", strike: 400, expiry: "Dec 15 '28", dte: "870 DTE", expired: false,
                             ct: 31, basis: 608700, current: 629300, mark: 203.00, moneyness: "ITM", delta: -0.95, theta: -0.01, deltaEst: -2945)]),
            ],
            fresh: .live, freshText: "Updated now · streaming")
        s.insights = NvInsights(
            protection: NvProtection(putContracts: 50, shares: 5001, covered: 3200, coveredPct: 64,
                                     floorLow: 200, floorHigh: 400, uncovered: 1801,
                                     cushion: 12.40, cushionPct: 6.4, empty: false),
            vol: NvVol(score: 1.09, verdict: "favorable", iv: 48, ivPrev: 42, hv30: 42, ivr: 58, factor: 1.0,
                       iv52Low: 34, iv52High: 71, spread: 6, building: false),
            vega: NvVega(iv: 43, avg30: 46, lo: 28, hi: 74, net: 3934, stance: "long vega", daysToEarnings: 12, legs: [
                NvVegaLeg(name: "Calls sold", kind: "call", side: "short", ct: 15, v: -420),
                NvVegaLeg(name: "Calls bought", kind: "call", side: "long", ct: 5, v: 260),
                NvVegaLeg(name: "Puts bought", kind: "put", side: "long", ct: 50, v: 4094),
            ]),
            fresh: .delayed)

        s.pnl = NvPnL(realized: 23467, realizedStock: -1526, premiumRealized: 24993, longRealized: 0, dividends: 0,
                      unrealized: -51464, sharesUnrealized: -60995, openShortValue: 200, openLongValue: 704160, longCostBasis: 694629,
                      net: -27997, premiumUnrealized: 8526, premiumTotal: 33519,
                      costRealized: 21840, costUnrealized: 694629, costTotal: 716469,
                      shares: 5601, avgBuy: 208.39, spot: 197.5)
        s.perf = NvPerf(realized: 21492, lifetime: 21492, perShare: 2.12, perSharePct: 1.0,
                        costBasis: 209.18, breakEven: 207.06, cushion: -12.49, cushionPct: -6.0, sleeves: [
            NvPerfSleeve(name: "Shares", glyph: "○", total: 5001, basisLabel: "Paid", basis: 1046116, realized: 10037, unrealized: -77380, empty: false),
            NvPerfSleeve(name: "Calls sold", glyph: "▲", total: 47, basisLabel: "Collected", basis: 8310, realized: 3067, unrealized: 1200, empty: false),
            NvPerfSleeve(name: "Calls bought", glyph: "△", total: 5, basisLabel: "Paid", basis: 35600, realized: 1480, unrealized: 1400, empty: false),
            NvPerfSleeve(name: "Puts bought", glyph: "▽", total: 50, basisLabel: "Paid", basis: 541989, realized: -3210, unrealized: 20000, empty: false),
            NvPerfSleeve(name: "Puts sold", glyph: "▼", total: 0, basisLabel: "Collected", basis: 0, realized: 0, unrealized: 0, empty: true),
        ])

        func day(_ l: String, _ c: Double, _ p: Double) -> NvPeerDay { NvPeerDay(label: l, close: c, pct: p) }
        s.peers = NvPeers(tapes: [
            NvPeerTape(ticker: "NVDA", name: "NVIDIA", group: "self", last: 194.57, net: 3.2,
                       days: [day("Jul 21", 190, 1.1), day("Jul 22", 192, 1.0), day("Jul 23", 191, -0.5),
                              day("Jul 24", 193, 1.0), day("Jul 25", 194.57, 0.8)], vsNvda: nil),
            NvPeerTape(ticker: "QQQ", name: "Nasdaq 100", group: "ETFs", last: 480.10, net: 1.1,
                       days: [day("Jul 21", 475, 0.4), day("Jul 22", 477, 0.4), day("Jul 23", 476, -0.2),
                              day("Jul 24", 479, 0.6), day("Jul 25", 480.10, 0.2)], vsNvda: -2.1),
            NvPeerTape(ticker: "AVGO", name: "Broadcom", group: "Peers", last: 1650, net: 4.0,
                       days: [day("Jul 21", 1590, 1.4), day("Jul 22", 1610, 1.3), day("Jul 23", 1600, -0.6),
                              day("Jul 24", 1635, 2.2), day("Jul 25", 1650, 0.9)], vsNvda: 0.8),
        ], fresh: .live)

        func bar(_ iso: String, _ label: String, _ sub: String, _ v: [String: Double]) -> NvHistBar {
            NvHistBar(iso: iso, label: label, sub: sub, pending: false, vals: v)
        }
        s.history = NvHistory(months: [
            NvHistMonth(label: "June", short: "Jun", bars: [
                bar("2026-06-15", "15", "Jun 15", ["shares": 3100, "callsSold": 700]),
                bar("2026-06-22", "22", "Jun 22", ["shares": -2400, "putsBought": -300]),
                bar("2026-06-29", "29", "Jun 29", ["shares": 4400, "callsSold": 500]),
            ]),
            NvHistMonth(label: "July", short: "Jul", bars: [
                bar("2026-07-06", "06", "Jul 6", ["shares": 1800, "callsSold": 650]),
                bar("2026-07-13", "13", "Jul 13", ["shares": -900, "callsBought": 200]),
                bar("2026-07-21", "21", "Jul 21", ["shares": 4200, "callsSold": 800]),
                bar("2026-07-22", "22", "Jul 22", ["shares": -3100, "putsBought": -400]),
                bar("2026-07-23", "23", "Jul 23", ["shares": 5200, "callsSold": 600, "callsBought": 300]),
                bar("2026-07-24", "24", "Jul 24", ["shares": -1200]),
                bar("2026-07-25", "25", "Jul 25", ["shares": 2600, "callsSold": 900]),
            ]),
        ], sources: [
            NvHistSource(key: "shares", label: "Shares", glyph: "○", empty: false),
            NvHistSource(key: "callsSold", label: "Calls sold", glyph: "▲", empty: false),
            NvHistSource(key: "callsBought", label: "Calls bought", glyph: "△", empty: false),
            NvHistSource(key: "putsSold", label: "Puts sold", glyph: "▼", empty: true),
            NvHistSource(key: "putsBought", label: "Puts bought", glyph: "▽", empty: false),
        ], fresh: .delayed)
        return s
    }
}

struct InkDesignPreview: View {
    @State private var store = InkPreviewData.store()
    var body: some View {
        ZStack {
            Ink.canvas.ignoresSafeArea()
            if ProcessInfo.processInfo.arguments.contains("-inkEvents") {
                NvdaEventsScreen()
            } else if ProcessInfo.processInfo.arguments.contains("-inkHist") {
                ScrollView { NvdaHistoryScreen(store: store) }
            } else if ProcessInfo.processInfo.arguments.contains("-inkIns") {
                ScrollView { NvdaInsightsScreen(store: store) }
            } else if ProcessInfo.processInfo.arguments.contains("-inkPeers") {
                ScrollView { NvdaPeersScreen(store: store) }
            } else if ProcessInfo.processInfo.arguments.contains("-inkAvg") {
                NvdaAvgDownPreviewHarness(store: store)
            } else if ProcessInfo.processInfo.arguments.contains("-inkSleeve") {
                NvdaSleevePreviewHarness(store: store)
            } else if ProcessInfo.processInfo.arguments.contains("-inkTLT") {
                let tlt = TLTBook.store()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        TLTEventsScreen()
                        TLTVoterBlocScreen()
                        TLTInsightsScreen()
                        NvdaPositionScreen(store: tlt, showPlan: false)
                        NvdaPeersScreen(store: tlt)
                        NvdaHistoryScreen(store: tlt)
                        Color.clear.frame(height: 60)
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        NvdaPositionScreen(store: store)
                        NvdaInsightsScreen(store: store)
                        NvdaPeersScreen(store: store)
                        NvdaHistoryScreen(store: store)
                        Color.clear.frame(height: 60)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
