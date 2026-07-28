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
        s.insights = NvInsights(
            protection: NvProtection(putContracts: 50, shares: 5001, covered: 3200, coveredPct: 64,
                                     floorLow: 200, floorHigh: 400, uncovered: 1801,
                                     cushion: 12.40, cushionPct: 6.4, empty: false),
            vol: NvVol(score: 63, verdict: "caution", iv: 48, hv30: 42, ivr: 58,
                       iv52Low: 34, iv52High: 71, spread: 6, building: false),
            fresh: .delayed)

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

        func bar(_ label: String, _ sub: String, _ v: [String: Double]) -> NvHistBar {
            NvHistBar(label: label, sub: sub, pending: false, vals: v)
        }
        s.history = NvHistory(months: [
            NvHistMonth(label: "July", short: "Jul", bars: [
                bar("21", "Jul 21", ["shares": 4200, "callsSold": 800]),
                bar("22", "Jul 22", ["shares": -3100, "putsBought": -400]),
                bar("23", "Jul 23", ["shares": 5200, "callsSold": 600, "callsBought": 300]),
                bar("24", "Jul 24", ["shares": -1200]),
                bar("25", "Jul 25", ["shares": 2600, "callsSold": 900]),
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
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    NvdaInsightsScreen(store: store)
                    Rectangle().fill(Ink.hair).frame(height: 1).padding(.horizontal, 16).padding(.vertical, 10)
                    NvdaPeersScreen(store: store)
                    Rectangle().fill(Ink.hair).frame(height: 1).padding(.horizontal, 16).padding(.vertical, 10)
                    NvdaHistoryScreen(store: store)
                    Color.clear.frame(height: 60)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
