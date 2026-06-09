//
//  TradeMutations.swift
//  Sunnyfi
//
//  Supabase write operations for the same `option_trades`, `positions`,
//  `share_sells` tables the web app writes to (see src/positions/
//  usePositions.ts). Inserting/updating here is realtime-visible on
//  sunnyfi.co — they share the same project and the web has a realtime
//  subscription on option_trades.
//
//  All methods are @MainActor and re-fetch on success so the UI updates.
//

import Foundation
import Supabase

// MARK: - DTOs (write-side)

struct NewTradeInput: Sendable {
    var ticker: String
    var tradeDate: Date
    var optionType: String   // "call" | "put"
    var direction: String    // "short" | "long"
    var contracts: Double
    var strike: Double
    var premium: Double
    var expiry: Date
    var note: String?
}

struct TradePatch: Sendable {
    let id: String
    let optionType: String?
    let direction: String?
    let contracts: Double
    let strike: Double
    let premium: Double
    let expiry: Date
    let tradeDate: Date
    let note: String?
}

// MARK: - Helpers

private extension Date {
    /// "YYYY-MM-DD" for trade_date / expiry columns.
    var isoDay: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: self)
    }
}

// MARK: - Encodable inserts/updates
// Anonymous structs we feed straight to PostgREST.

private struct OpenInsert: Encodable {
    let ticker: String
    let trade_date: String
    let action: String
    let option_type: String
    let direction: String
    let contracts: Double
    let strike: Double
    let premium: Double
    let expiry: String
    let closes_trade_id: String?
    let note: String?
}

private struct CloseInsert: Encodable {
    let ticker: String
    let trade_date: String
    let action: String
    let option_type: String
    let direction: String
    let contracts: Double
    let strike: Double
    let premium: Double
    let expiry: String
    let closes_trade_id: String
    let closed_via: String?
    let share_pnl: Double?
    let note: String?
}

private struct TradeUpdate: Encodable {
    let contracts: Double
    let strike: Double
    let premium: Double
    let expiry: String
    let trade_date: String
    let note: String?
    let option_type: String?
    let direction: String?
}

private struct PositionUpsert: Encodable {
    let ticker: String
    let quantity: Double
    let avg_cost: Double
    let status: String
}

private struct PositionPatch: Encodable {
    let quantity: Double
    let avg_cost: Double?
    let realized_stock_pl: Double?
}

private struct RealizedOnlyPatch: Encodable {
    let realized_stock_pl: Double
}

private struct ShareSellInsert: Encodable {
    let ticker: String
    let quantity: Double
    let price: Double
    let trade_date: String
    let source: String
    let realized_pl: Double
    let note: String?
}

// Phase 3 — lot-level writes
private struct ShareLotInsert: Encodable {
    let ticker: String
    let acquired_date: String
    let fifo_order: Int
    let qty_original: Double
    let qty_remaining: Double
    let cost_per_share: Double
    let source: String                  // "manual" | "assignment" | "seed"
    let linked_assignment_id: String?
}

private struct ShareLotConsumptionInsert: Encodable {
    let share_sell_id: String
    let lot_id: String
    let qty_consumed: Double
    let realized_pl: Double
}

private struct ShareLotPatch: Encodable {
    let qty_remaining: Double
}

private struct IdRow: Decodable { let id: String }
private struct LotFifoMaxRow: Decodable { let fifo_order: Int }

private struct PositionReadRow: Decodable {
    let quantity: Double
    let avg_cost: Double
    let realized_stock_pl: Double?
}

// MARK: - Store extension

extension PortfolioStore {

    private var client: SupabaseClient { SupabaseService.client }

    // ── Option trades ─────────────────────────────────────────────

    /// Insert a new opening trade (option leg).
    func addTrade(_ input: NewTradeInput) async throws {
        let row = OpenInsert(
            ticker: input.ticker.uppercased(),
            trade_date: input.tradeDate.isoDay,
            action: "open",
            option_type: input.optionType,
            direction: input.direction,
            contracts: input.contracts,
            strike: input.strike,
            premium: input.premium,
            expiry: input.expiry.isoDay,
            closes_trade_id: nil,
            note: input.note
        )
        try await client.from("option_trades").insert(row).execute()
        await fetchAfterMutation()
    }

    /// Update an existing open trade. Mirrors web `updateTrade`.
    func updateTrade(_ patch: TradePatch) async throws {
        let body = TradeUpdate(
            contracts: patch.contracts,
            strike: patch.strike,
            premium: patch.premium,
            expiry: patch.expiry.isoDay,
            trade_date: patch.tradeDate.isoDay,
            note: patch.note,
            option_type: patch.optionType,
            direction: patch.direction
        )
        try await client.from("option_trades").update(body).eq("id", value: patch.id).execute()
        await fetchAfterMutation()
    }

    /// Delete a trade row by id.
    func deleteTrade(id: String) async throws {
        try await client.from("option_trades").delete().eq("id", value: id).execute()
        await fetchAfterMutation()
    }

    /// Close a trade at a user-supplied close premium. `contracts` lets
    /// you close fewer than the full open size (partial close) — pass
    /// the open's full count to close it entirely.
    func closeTrade(
        open: OptionTradeRow,
        contracts: Double,
        closePremium: Double,
        closeDate: Date,
        note: String? = nil
    ) async throws {
        let row = CloseInsert(
            ticker: open.ticker,
            trade_date: closeDate.isoDay,
            action: "close",
            option_type: open.option_type,
            direction: open.direction,
            contracts: contracts,
            strike: open.strike,
            premium: closePremium,
            expiry: open.expiry,
            closes_trade_id: open.id,
            closed_via: nil,
            share_pnl: nil,
            note: note
        )
        try await client.from("option_trades").insert(row).execute()
        await fetchAfterMutation()
    }

    /// Resolve as expired worthless — kept full premium, no share moves.
    func resolveExpired(open: OptionTradeRow, date: Date, note: String? = nil) async throws {
        let row = CloseInsert(
            ticker: open.ticker,
            trade_date: date.isoDay,
            action: "close",
            option_type: open.option_type,
            direction: open.direction,
            contracts: open.contracts,
            strike: open.strike,
            premium: 0,
            expiry: open.expiry,
            closes_trade_id: open.id,
            closed_via: "expired_worthless",
            share_pnl: nil,
            note: note
        )
        try await client.from("option_trades").insert(row).execute()
        await fetchAfterMutation()
    }

    /// Resolve as assigned/exercised. Phase 3:
    /// • Short call → FIFO-consume the oldest lots at strike (records the
    ///   true per-lot realized P&L via share_lot_consumptions).
    /// • Short put  → create a NEW lot at strike (source='assignment',
    ///   linked_assignment_id = the open trade's id) so the cost basis
    ///   of acquired shares is permanently attributable.
    func resolveAssigned(open: OptionTradeRow, date: Date, note: String? = nil) async throws {
        let ticker = open.ticker.uppercased()
        let shareQty = open.contracts * 100
        let isShortCall = open.direction == "short" && open.option_type == "call"
        let isShortPut  = open.direction == "short" && open.option_type == "put"

        if isShortCall {
            // 1. FIFO plan at strike price.
            let plan = try await fifoPlan(ticker: ticker, qty: shareQty, sellPrice: open.strike)
            let planned = plan.reduce(0) { $0 + $1.qtyTake }
            guard planned >= shareQty else {
                throw NSError(domain: "Sunnyfi", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "Assignment would call away \(Int(shareQty)) sh but only \(Int(planned)) lots available."])
            }
            let totalRealized = plan.reduce(0) { $0 + $1.realized }

            // 2. Insert the option close row with the lot-derived share_pnl.
            try await client.from("option_trades").insert(CloseInsert(
                ticker: ticker, trade_date: date.isoDay, action: "close",
                option_type: open.option_type, direction: open.direction,
                contracts: open.contracts, strike: open.strike, premium: 0,
                expiry: open.expiry, closes_trade_id: open.id,
                closed_via: "assigned", share_pnl: totalRealized, note: note
            )).execute()

            // 3. Insert share_sells (assignment source) and grab its id.
            let inserted: [IdRow] = try await client.from("share_sells")
                .insert(ShareSellInsert(
                    ticker: ticker, quantity: shareQty, price: open.strike,
                    trade_date: date.isoDay, source: "assignment",
                    realized_pl: totalRealized, note: note
                ))
                .select("id")
                .execute().value
            guard let sellId = inserted.first?.id else {
                throw NSError(domain: "Sunnyfi", code: 4, userInfo: [NSLocalizedDescriptionKey: "share_sells insert returned no id"])
            }

            // 4. Per-lot consumptions + qty_remaining decrements.
            for step in plan {
                try await client.from("share_lot_consumptions")
                    .insert(ShareLotConsumptionInsert(
                        share_sell_id: sellId,
                        lot_id: step.lotId,
                        qty_consumed: step.qtyTake,
                        realized_pl: step.realized
                    )).execute()
                try await client.from("share_lots")
                    .update(ShareLotPatch(qty_remaining: step.newRemaining))
                    .eq("id", value: step.lotId)
                    .execute()
            }

            // 5. Sync positions aggregate + accumulate realized_pl.
            try await recomputePositionFromLots(ticker: ticker)
            struct PRow: Decodable { let realized_stock_pl: Double? }
            let pRows: [PRow] = try await client.from("positions")
                .select("realized_stock_pl").eq("ticker", value: ticker).limit(1).execute().value
            if let p = pRows.first {
                try await client.from("positions")
                    .update(RealizedOnlyPatch(realized_stock_pl: (p.realized_stock_pl ?? 0) + totalRealized))
                    .eq("ticker", value: ticker).execute()
            }

        } else if isShortPut {
            // 1. Insert the option close row (no share_pnl on assignment-to-buy).
            try await client.from("option_trades").insert(CloseInsert(
                ticker: ticker, trade_date: date.isoDay, action: "close",
                option_type: open.option_type, direction: open.direction,
                contracts: open.contracts, strike: open.strike, premium: 0,
                expiry: open.expiry, closes_trade_id: open.id,
                closed_via: "assigned", share_pnl: nil, note: note
            )).execute()

            // 2. New lot at strike, tagged so we can trace it back.
            try await insertLot(
                ticker: ticker,
                acquired: date,
                qty: shareQty,
                costPerShare: open.strike,
                source: "assignment",
                linkedAssignmentId: open.id
            )

            // 3. Ensure positions row exists, then sync aggregate.
            struct Row: Decodable { let quantity: Double }
            let pRows: [Row] = try await client.from("positions")
                .select("quantity").eq("ticker", value: ticker).limit(1).execute().value
            if pRows.isEmpty {
                try await client.from("positions").insert(PositionUpsert(
                    ticker: ticker, quantity: shareQty, avg_cost: open.strike, status: "open"
                )).execute()
            }
            try await recomputePositionFromLots(ticker: ticker)

        } else {
            // Long-option exercise paths still not modeled; just write
            // the close row and bail.
            try await client.from("option_trades").insert(CloseInsert(
                ticker: ticker, trade_date: date.isoDay, action: "close",
                option_type: open.option_type, direction: open.direction,
                contracts: open.contracts, strike: open.strike, premium: 0,
                expiry: open.expiry, closes_trade_id: open.id,
                closed_via: "assigned", share_pnl: nil, note: note
            )).execute()
        }

        await fetchAfterMutation()
    }

    // ── Shares ─────────────────────────────────────────────────────

    /// Buy shares — inserts a new lot row + keeps `positions` aggregate
    /// in sync. Phase 3: lots are the source of truth for cost basis.
    func buyShares(ticker: String, quantity: Double, price: Double, acquired: Date = Date()) async throws {
        let tk = ticker.uppercased()
        try await insertLot(ticker: tk, acquired: acquired, qty: quantity, costPerShare: price)
        // Ensure positions row exists (first-time buy).
        struct Row: Decodable { let quantity: Double }
        let rows: [Row] = try await client
            .from("positions")
            .select("quantity")
            .eq("ticker", value: tk)
            .limit(1)
            .execute().value
        if rows.isEmpty {
            try await client.from("positions").insert(PositionUpsert(
                ticker: tk, quantity: quantity, avg_cost: price, status: "open"
            )).execute()
        }
        try await recomputePositionFromLots(ticker: tk)
        await fetchAfterMutation()
    }

    /// Upsert the strategy bucket (Income / Investment / Yield) for a
    /// ticker. Used by the add-trade form and the company edit screen.
    func setStrategy(ticker: String, strategy: Strategy) async throws {
        struct Row: Encodable { let ticker: String; let bucket: String }
        // Use the DB short-form bucket value, not the display
        // `rawValue`. The CHECK constraint
        // `strategy_overlay_bucket_check` only accepts
        // `income | invest | yield`.
        try await client.from("strategy_overlay")
            .upsert(Row(ticker: ticker.uppercased(), bucket: strategy.dbBucket),
                    onConflict: "ticker")
            .execute()
    }

    /// Sell shares — FIFO consume oldest lots, insert share_sells row,
    /// insert per-lot share_lot_consumptions rows, decrement each lot's
    /// qty_remaining, recompute positions aggregate.
    func sellShares(ticker: String, quantity: Double, price: Double) async throws {
        let tk = ticker.uppercased()
        let plan = try await fifoPlan(ticker: tk, qty: quantity, sellPrice: price)
        let planned = plan.reduce(0) { $0 + $1.qtyTake }
        guard planned >= quantity else {
            throw NSError(domain: "Sunnyfi", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "Sell \(Int(quantity)) sh exceeds available \(Int(planned))."])
        }

        let totalRealized = plan.reduce(0) { $0 + $1.realized }
        let today = Date()

        // 1. Insert the share_sells row and grab its id back.
        let inserted: [IdRow] = try await client.from("share_sells")
            .insert(ShareSellInsert(
                ticker: tk, quantity: quantity, price: price,
                trade_date: today.isoDay,
                source: "manual",
                realized_pl: totalRealized,
                note: nil
            ))
            .select("id")
            .execute().value
        guard let sellId = inserted.first?.id else {
            throw NSError(domain: "Sunnyfi", code: 3, userInfo: [NSLocalizedDescriptionKey: "share_sells insert returned no id"])
        }

        // 2. Per-lot consumptions + UPDATE qty_remaining on each lot touched.
        for step in plan {
            try await client.from("share_lot_consumptions")
                .insert(ShareLotConsumptionInsert(
                    share_sell_id: sellId,
                    lot_id: step.lotId,
                    qty_consumed: step.qtyTake,
                    realized_pl: step.realized
                ))
                .execute()
            try await client.from("share_lots")
                .update(ShareLotPatch(qty_remaining: step.newRemaining))
                .eq("id", value: step.lotId)
                .execute()
        }

        // 3. Sync the aggregate cache (positions.quantity + avg_cost).
        try await recomputePositionFromLots(ticker: tk)

        // realized_stock_pl accumulates as a separate (non-clobbering) patch.
        struct PRow: Decodable { let realized_stock_pl: Double? }
        let pRows: [PRow] = try await client
            .from("positions").select("realized_stock_pl").eq("ticker", value: tk).limit(1).execute().value
        if let p = pRows.first {
            try await client.from("positions")
                .update(RealizedOnlyPatch(realized_stock_pl: (p.realized_stock_pl ?? 0) + totalRealized))
                .eq("ticker", value: tk)
                .execute()
        }

        await fetchAfterMutation()
    }

    // ── Lookup helpers (used by Trades / Company screens) ──────────

    /// Sum of contracts already closed against the given open id.
    func closedContracts(forOpenID id: String) -> Double {
        allTrades
            .filter { $0.action == "close" && $0.closes_trade_id == id }
            .reduce(0) { $0 + $1.contracts }
    }

    /// Contracts still active on this open (after partial closes).
    func remainingContracts(for open: OptionTradeRow) -> Double {
        max(0, open.contracts - closedContracts(forOpenID: open.id))
    }

    /// Cost-of-protection rollup — every open long put, its daily burn,
    /// and the weekly target you'd need to generate in call premium to
    /// stay flat on hedges. See HedgeMath for the math.
    var hedgeBudget: HedgeBudget {
        HedgeMath.budget(from: allTrades, remaining: { self.remainingContracts(for: $0) })
    }

    /// Theta-aware "today" snapshot for the Hedge tab — joins open
    /// long puts to the latest greeks capture, classifies by DTE zone,
    /// reports the real $/day burn. See HedgeTheta.
    var hedgeToday: HedgeTodaySnapshot {
        HedgeTheta.snapshot(
            from: allTrades,
            greeks: allGreeks,
            remaining: { self.remainingContracts(for: $0) }
        )
    }

    /// Gross credits from short-call opens whose trade_date falls in
    /// [windowStart, now]. Used by the Planner's hedge progress bar to
    /// show how much premium income is offsetting the hedge burn this
    /// week / month. Net of buy-to-close within the same window: a
    /// roll counts as gross open minus the close debit so a same-week
    /// roll doesn't double-count.
    func shortCallPremiumCollected(since windowStart: Date) -> Double {
        let calls = allTrades.filter {
            $0.option_type == "call" && $0.direction == "short"
            && (AppDates.parseISODay($0.trade_date) ?? .distantPast) >= windowStart
        }
        var sum = 0.0
        for t in calls {
            // Opens add credits, closes subtract debits.
            let signed = t.action == "open" ? 1.0 : -1.0
            sum += signed * t.premium * t.contracts * 100
        }
        return max(0, sum)
    }

    // ── Phase 3 (FIFO) — simulation helpers ────────────────────────

    /// Lots for a ticker, FIFO-ordered (oldest first by acquired_date
    /// then fifo_order). Only lots with `qty_remaining > 0`.
    func fifoLots(for ticker: String) -> [ShareLotRow] {
        allShareLots
            .filter { $0.ticker == ticker && $0.qty_remaining > 0 }
            .sorted { lhs, rhs in
                if lhs.acquired_date != rhs.acquired_date { return lhs.acquired_date < rhs.acquired_date }
                return lhs.fifo_order < rhs.fifo_order
            }
    }

    /// Simulate consuming `qty` shares from `ticker` at `sellPrice`. Walks
    /// the FIFO lots and returns one `LotConsumption` per lot touched.
    /// If `qty` exceeds available, returns what we can fill (caller
    /// should warn the user).
    func fifoSimulate(ticker: String, qty: Double, sellPrice: Double) -> [LotConsumption] {
        var out: [LotConsumption] = []
        var remaining = qty
        for lot in fifoLots(for: ticker) {
            guard remaining > 0 else { break }
            let take = min(lot.qty_remaining, remaining)
            let pl = (sellPrice - lot.cost_per_share) * take
            out.append(LotConsumption(id: lot.id, lot: lot, qtyConsumed: take, realizedPL: pl))
            remaining -= take
        }
        return out
    }

    /// Aggregate the consumption — weighted-avg cost basis + total
    /// realized P&L across all lots touched.
    func fifoSummary(ticker: String, qty: Double, sellPrice: Double) -> (lots: Int, qty: Double, weightedAvg: Double, realized: Double) {
        let cs = fifoSimulate(ticker: ticker, qty: qty, sellPrice: sellPrice)
        let q = cs.reduce(0) { $0 + $1.qtyConsumed }
        let totalCost = cs.reduce(0) { $0 + $1.qtyConsumed * $1.lot.cost_per_share }
        let weighted = q > 0 ? totalCost / q : 0
        let realized = cs.reduce(0) { $0 + $1.realizedPL }
        return (cs.count, q, weighted, realized)
    }

    /// Spot price for a ticker (live quote if available; else 0).
    func spot(for ticker: String) -> Double {
        companies.first(where: { $0.ticker == ticker })?.spot ?? 0
    }

    /// Latest option mark for an open trade, if option_greeks has a row.
    /// Falls back to the entry premium so P&L collapses to 0 when there's
    /// no live data yet.
    func currentMark(for trade: OptionTradeRow) -> Double {
        allGreeks.first(where: { $0.option_trade_id == trade.id })?.last_mark ?? trade.premium
    }

    /// Unrealized P&L on the still-active contracts of an open trade.
    /// Formula: (mark − entry) × contracts × 100 × (long ? +1 : −1).
    /// • Short put bought back cheaper → positive P&L.
    /// • Long call worth more than paid → positive P&L.
    /// • Color of this value tracks the sign, not the side.
    func unrealizedPL(for trade: OptionTradeRow) -> Double {
        let active = remainingContracts(for: trade)
        guard active > 0 else { return 0 }
        let mark = currentMark(for: trade)
        let sideMultiplier: Double = trade.direction == "long" ? 1 : -1
        return (mark - trade.premium) * active * 100 * sideMultiplier
    }

    // ── Phase 3 lot operations (low-level) ─────────────────────────

    /// Insert one new lot for `ticker`. Auto-derives fifo_order = max+1
    /// for the (ticker, acquired_date) bucket so a same-day buy is
    /// always ordered after previous same-day lots.
    private func insertLot(
        ticker: String,
        acquired: Date,
        qty: Double,
        costPerShare: Double,
        source: String = "manual",
        linkedAssignmentId: String? = nil
    ) async throws {
        let tk = ticker.uppercased()
        let dayStr = acquired.isoDay
        // Max fifo_order for that ticker+date today (0 if none).
        struct Row: Decodable { let max: Int? }
        // Use a small subquery via the RPC-like .from + select aggregate.
        // PostgREST doesn't support MAX in selects directly; pull rows and compute.
        let existing: [LotFifoMaxRow] = try await client
            .from("share_lots")
            .select("fifo_order")
            .eq("ticker", value: tk)
            .eq("acquired_date", value: dayStr)
            .order("fifo_order", ascending: false)
            .limit(1)
            .execute()
            .value
        let nextOrder = (existing.first?.fifo_order ?? 0) + 1

        try await client.from("share_lots").insert(ShareLotInsert(
            ticker: tk,
            acquired_date: dayStr,
            fifo_order: nextOrder,
            qty_original: qty,
            qty_remaining: qty,
            cost_per_share: costPerShare,
            source: source,
            linked_assignment_id: linkedAssignmentId
        )).execute()
    }

    /// FIFO walk: oldest active lots first. Returns the consumption plan
    /// the caller will then write to share_lot_consumptions + apply via
    /// per-lot UPDATEs. Computes against fresh DB rows, not the cached
    /// `allShareLots`, so mutations stay correct under concurrent edits.
    private func fifoPlan(
        ticker: String,
        qty: Double,
        sellPrice: Double
    ) async throws -> [(lotId: String, costPerShare: Double, qtyTake: Double, newRemaining: Double, realized: Double)] {
        struct Row: Decodable {
            let id: String
            let qty_remaining: Double
            let cost_per_share: Double
        }
        let lots: [Row] = try await client
            .from("share_lots")
            .select("id, qty_remaining, cost_per_share, acquired_date, fifo_order")
            .eq("ticker", value: ticker.uppercased())
            .gt("qty_remaining", value: 0)
            .order("acquired_date", ascending: true)
            .order("fifo_order", ascending: true)
            .execute()
            .value

        var plan: [(String, Double, Double, Double, Double)] = []
        var remaining = qty
        for l in lots {
            guard remaining > 0 else { break }
            let take = min(l.qty_remaining, remaining)
            let newRem = l.qty_remaining - take
            let pl = (sellPrice - l.cost_per_share) * take
            plan.append((l.id, l.cost_per_share, take, newRem, pl))
            remaining -= take
        }
        return plan
    }

    /// Sum lot.qty_remaining and weighted-avg cost for a ticker, then
    /// UPDATE positions so the aggregate cache stays in sync with the lots.
    /// Called after every lot mutation.
    private func recomputePositionFromLots(ticker: String) async throws {
        let tk = ticker.uppercased()
        struct Row: Decodable {
            let qty_remaining: Double
            let cost_per_share: Double
        }
        let rows: [Row] = try await client
            .from("share_lots")
            .select("qty_remaining, cost_per_share")
            .eq("ticker", value: tk)
            .execute()
            .value
        let totalQty = rows.reduce(0) { $0 + $1.qty_remaining }
        let totalCost = rows.reduce(0) { $0 + $1.qty_remaining * $1.cost_per_share }
        let avg = totalQty > 0 ? totalCost / totalQty : 0
        try await client.from("positions")
            .update(PositionPatch(quantity: totalQty, avg_cost: avg, realized_stock_pl: nil))
            .eq("ticker", value: tk)
            .execute()
    }

    // ── Common refresh ─────────────────────────────────────────────

    /// After a write, re-pull the data so the UI shows the new row.
    /// We skip the `mp-refresh` edge-function bounce (which fetches new
    /// quotes/Greeks) since the new row already exists in the DB — a
    /// plain table re-fetch is enough.
    private func fetchAfterMutation() async {
        await fetchAll()
    }
}
