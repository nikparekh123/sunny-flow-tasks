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

            let (t, l, sl, q, m, c) = try await (trades, lots, sells, quotes, marks, closes)
            let nvda = q.first { $0.ticker == "NVDA" }
            position  = NvDerive.position(trades: t, lots: l, quote: nvda, marks: m)
            // Daily IV snapshot — non-fatal: if the table isn't there yet, [] (no 2nd gauge arc).
            let ivDaily: [NvIvDaily] = (try? await client.from("nvda_iv_daily")
                .select("ticker,date,iv").eq("ticker", value: "NVDA")
                .order("date", ascending: false).limit(10).execute().value) ?? []

            pnl       = NvDerive.pnl(trades: t, lots: l, sells: sl, quote: nvda, marks: m)
            perf      = NvDerive.performance(trades: t, lots: l, sells: sl, quote: nvda, marks: m)
            insights  = NvDerive.insights(trades: t, lots: l, marks: m, quote: nvda, closes: c, ivDaily: ivDaily)
            peers     = NvDerive.peers(quotes: q, closes: c)
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
