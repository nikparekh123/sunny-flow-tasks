//
//  NvdaStore.swift
//  Sunnyfi — Ink rebuild
//
//  Reads the nvda_* store (authenticated) and hands the rows to NvDerive.
//  A 60s poll matches the server feed; the position updates in place. (A
//  Supabase Realtime subscription can replace the poll later for instant push.)
//

import Foundation
import Supabase

@MainActor
@Observable
final class NvdaStore {
    var position: NvPosition?
    var pnl: NvPnL?            // canonical glossary P&L (docs/PNL_GLOSSARY.md)
    var perf: NvPerf?
    var insights: NvInsights?
    var peers: NvPeers?
    var history: NvHistory?
    var isLoading = true
    var lastError: String?

    /// NVDA daily closes, oldest→newest — kept so the Planner can compute HV over
    /// arbitrary windows (HV20/60/90) with the same estimator as the Seller Score.
    private(set) var nvCloses: [Double] = []

    /// True 52-week high: the max close over the trailing ~252 trading sessions.
    /// Drives the Average-down card's "below the high". nil until closes load.
    var high52: Double? { Array(nvCloses.suffix(252)).max() }

    /// Seed the close series directly — fixtures/preview only (the TLT book, etc.).
    func seedCloses(_ c: [Double]) { nvCloses = c.sorted() }

    /// Annualised realized vol over the last `window` trading days, in percent.
    /// Same estimator as NvDerive.realizedVol (sample stdev of log returns × √252).
    func hv(_ window: Int) -> Double? {
        let w = Array(nvCloses.suffix(window + 1))
        guard w.count >= 6 else { return nil }
        var rets: [Double] = []
        for i in 1..<w.count where w[i - 1] > 0 { rets.append(log(w[i] / w[i - 1])) }
        guard rets.count >= 5 else { return nil }
        let mean = rets.reduce(0, +) / Double(rets.count)
        let varc = rets.reduce(0) { $0 + pow($1 - mean, 2) } / Double(rets.count - 1)
        return sqrt(varc) * sqrt(252) * 100
    }

    private let client = SupabaseService.client

    func fetch() async {
        do {
            async let trades: [NvOptionTrade] = client.from("nvda_option_trades")
                .select("id,trade_date,action,option_type,direction,contracts,strike,premium,expiry,voided_at")
                .is("voided_at", value: nil)
                .execute().value
            async let lots: [NvShareLot] = client.from("nvda_share_lots")
                .select("id,qty_remaining,cost_per_share,voided_at")
                .is("voided_at", value: nil)
                .execute().value
            async let sells: [NvShareSell] = client.from("nvda_share_sells")
                .select("id,trade_date,quantity,price,realized_pl,voided_at")
                .is("voided_at", value: nil)
                .execute().value
            async let quotes: [NvQuote] = client.from("nvda_quote")
                .select("ticker,spot,day_change_pct,prev_close,captured_at")
                .execute().value
            async let marks: [NvOptionMark] = client.from("nvda_option_marks")
                .select("option_trade_id,mark,delta,gamma,theta,vega,iv,captured_at")
                .execute().value
            async let closes: [NvDailyClose] = client.from("nvda_daily_closes")
                .select("ticker,date,close_price")
                .order("date", ascending: false)
                .limit(120)
                .execute().value
            // A dedicated NVDA-only pull, a year deep — the shared `closes` above is
            // capped at 120 rows across every peer ticker, far too few NVDA sessions
            // for a real 52-week high or a stable HV window.
            async let nvCloseRows: [NvDailyClose] = client.from("nvda_daily_closes")
                .select("ticker,date,close_price")
                .eq("ticker", value: "NVDA")
                .order("date", ascending: false)
                .limit(300)
                .execute().value

            let (t, l, sl, q, m, c, nvc) = try await (trades, lots, sells, quotes, marks, closes, nvCloseRows)
            let nvda = q.first { $0.ticker == "NVDA" }
            nvCloses = nvc
                .compactMap { row in row.close_price.map { (row.date, $0) } }
                .sorted { $0.0 < $1.0 }.map { $0.1 }
            // Peers/insights read a merged series: the deep NVDA history plus the
            // shared peer closes (deduped of the shared feed's shallow NVDA rows).
            let mergedCloses = c.filter { $0.ticker != "NVDA" } + nvc
            position  = NvDerive.position(trades: t, lots: l, quote: nvda, marks: m)
            // Daily IV snapshot — non-fatal: if the table isn't there yet, [] (no 2nd gauge arc).
            let ivDaily: [NvIvDaily] = (try? await client.from("nvda_iv_daily")
                .select("ticker,date,iv").eq("ticker", value: "NVDA")
                .order("date", ascending: false).limit(10).execute().value) ?? []

            pnl       = NvDerive.pnl(trades: t, lots: l, sells: sl, quote: nvda, marks: m)
            perf      = NvDerive.performance(trades: t, lots: l, sells: sl, quote: nvda, marks: m)
            insights  = NvDerive.insights(trades: t, lots: l, marks: m, quote: nvda, closes: mergedCloses, ivDaily: ivDaily)
            peers     = NvDerive.peers(quotes: q, closes: mergedCloses)
            history   = NvDerive.history(trades: t, sells: sl)
            isLoading = false
            lastError = nil
        } catch {
            lastError = String(describing: error)
            isLoading = false
        }
    }

    /// Poll the store on the feed's cadence until the task is cancelled.
    func poll(seconds: UInt64 = 60) async {
        await fetch()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double(seconds)))
            guard !Task.isCancelled else { break }
            await fetch()
        }
    }
}
