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
            async let quotes: [NvQuote] = client.from("nvda_quote")
                .select("ticker,spot,day_change_pct,prev_close,captured_at")
                .eq("ticker", value: "NVDA")
                .execute().value
            async let marks: [NvOptionMark] = client.from("nvda_option_marks")
                .select("option_trade_id,mark,delta,gamma,theta,vega,iv,captured_at")
                .execute().value

            let (t, l, q, m) = try await (trades, lots, quotes, marks)
            position = NvDerive.position(trades: t, lots: l, quote: q.first, marks: m)
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
