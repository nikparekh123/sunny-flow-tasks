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
    /// Open lots oldest first — the order shares actually leave in.
    private(set) var shareLotsFIFO: [NvShareLot] = []

    /// Which per-ticker store to read. The nvda_* and tlt_* tables are the same shape
    /// by design — one mirror per ticker off the same legacy book — so the only thing
    /// that differs is the prefix. Duplicating this class for TLT would mean every fix
    /// landing twice, and the second one getting forgotten.
    let prefix: String
    init(prefix: String = "nvda") { self.prefix = prefix }
    /// The underlying this store is about. The tables are prefixed lowercase,
    /// the ticker columns inside them are uppercase.
    private var ticker: String { prefix.uppercased() }
    private func tbl(_ name: String) -> String { "\(prefix)_\(name)" }


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
            async let trades: [NvOptionTrade] = client.from(tbl("option_trades"))
                .select("id,trade_date,action,option_type,direction,contracts,strike,premium,expiry,voided_at")
                .is("voided_at", value: nil)
                .execute().value
            async let lots: [NvShareLot] = client.from(tbl("share_lots"))
                .select("id,qty_remaining,cost_per_share,voided_at,fifo_order,acquired_date")
                .is("voided_at", value: nil)
                .order("fifo_order", ascending: true)
                .execute().value
            async let sells: [NvShareSell] = client.from(tbl("share_sells"))
                .select("id,trade_date,quantity,price,realized_pl,voided_at")
                .is("voided_at", value: nil)
                .execute().value
            async let quotes: [NvQuote] = client.from(tbl("quote"))
                .select("ticker,spot,day_change_pct,prev_close,captured_at")
                .execute().value
            async let marks: [NvOptionMark] = client.from(tbl("option_marks"))
                .select("option_trade_id,mark,delta,gamma,theta,vega,iv,captured_at")
                .execute().value
            // The close is the ONLY value while the market is shut. Before the open the
            // live feed has no marks, and a missing mark was read as a mark of ZERO —
            // so 75 long puts that had not moved reported the whole $87K premium as a
            // loss, and the hero fell $50K overnight on nothing at all.
            //
            // nvda_eod()/tlt_eod() already snapshot per-leg marks at the close, dated
            // on the New York market date. The table was written nightly and never
            // read. One row per leg for the most recent session is enough.
            async let marksEod: [NvOptionMarkEod] = client.from(tbl("option_marks_eod"))
                .select("option_trade_id,date,mark,delta,theta")
                .order("date", ascending: false)
                .limit(600)
                .execute().value
            async let closes: [NvDailyClose] = client.from(tbl("daily_closes"))
                .select("ticker,date,close_price")
                .order("date", ascending: false)
                .limit(120)
                .execute().value
            // A dedicated NVDA-only pull, a year deep — the shared `closes` above is
            // capped at 120 rows across every peer ticker, far too few NVDA sessions
            // for a real 52-week high or a stable HV window.
            async let nvCloseRows: [NvDailyClose] = client.from(tbl("daily_closes"))
                .select("ticker,date,close_price")
                .eq("ticker", value: ticker)
                .order("date", ascending: false)
                .limit(300)
                .execute().value

            let (t, l, sl, q, mLive, c, nvc) = try await (trades, lots, sells, quotes, marks, closes, nvCloseRows)
            // Captured, not swallowed: an RLS or decode failure returned [] here and
            // looked exactly like an empty table.
            var eodErr = ""
            var mEod: [NvOptionMarkEod] = []
            do { mEod = try await marksEod } catch { eodErr = String(describing: error).prefix(120).description }
            // Chosen HERE rather than inside NvDerive: every derivation then sees one
            // marks list and none of the P&L maths has to know the close exists.
            let m = NvDerive.marksForSession(live: mLive, eod: mEod)
            let nvda = q.first { $0.ticker == ticker }
            nvCloses = nvc
                .compactMap { row in row.close_price.map { (row.date, $0) } }
                .sorted { $0.0 < $1.0 }.map { $0.1 }
            // Peers/insights read a merged series: the deep NVDA history plus the
            // shared peer closes (deduped of the shared feed's shallow NVDA rows).
            let mergedCloses = c.filter { $0.ticker != ticker } + nvc
            // pnl FIRST: New average is buy average − realized/share, and realized
            // has exactly one definition, which lives in NvDerive.pnl.
            let pnlNow = NvDerive.pnl(trades: t, lots: l, sells: sl, quote: nvda, marks: m)
            position  = NvDerive.position(trades: t, lots: l, quote: nvda, marks: m,
                                          realized: pnlNow?.realized ?? 0)
            // Kept in consumption order: an assignment takes the oldest lots, so the
            // gain it books is measured against those, not the book average.
            shareLotsFIFO = l.sorted { ($0.fifo_order ?? .max) < ($1.fifo_order ?? .max) }
            // Daily IV snapshot — non-fatal: if the table isn't there yet, [] (no 2nd gauge arc).
            let ivDaily: [NvIvDaily] = prefix == "nvda"
                ? ((try? await client.from(tbl("iv_daily"))
                    .select("ticker,date,iv").eq("ticker", value: ticker)
                    .order("date", ascending: false).limit(252).execute().value) ?? [])
                : []

            pnl       = pnlNow
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
