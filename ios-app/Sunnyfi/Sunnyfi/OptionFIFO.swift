//
//  OptionFIFO.swift
//  Sunnyfi
//
//  Pooled FIFO matching of option closes to opens.
//
//  WHY THIS EXISTS (2026-06-12 incident):
//  The DB links each close to exactly ONE open via closes_trade_id.
//  That FK model cannot represent reality:
//    • A 14-contract close can span two opens (a 5-lot and a 10-lot)
//      from the same day — one FK can't point at both.
//    • The ibkr-flex-sync edge function links every close to the
//      OLDEST matching open (LIMIT 1), so multi-open chains end up
//      with one over-closed open and the rest looking forever-open.
//    • Closes whose opens predate the sync window arrive with a NULL
//      link and were silently dropped from Perf's realized P/L.
//  After the June backfill this produced phantom "still open"
//  positions (META $630 calls that were fully bought back on Jun 2)
//  and double-ish Perf numbers.
//
//  THE FIX: ignore the FK for math. Pool all trades by contract key
//  (ticker, option_type, direction, strike, expiry) and run FIFO:
//  closes consume opens oldest-first, regardless of what
//  closes_trade_id claims. 15 opened + 15 closed = flat, however
//  the links lie. closes_trade_id remains as a display/debug hint
//  only.
//
//  This is also durable against the nightly Daily Flex backfill
//  re-upserting rows with re-derived (still naive) links — the app
//  no longer cares.
//

import Foundation

enum OptionFIFO {

    /// Pooling key — one chain per distinct contract + side.
    struct Key: Hashable {
        let ticker: String
        let optionType: String
        let direction: String
        let strike: Double
        let expiry: String
    }

    struct Ledger {
        /// Open trade id → contracts still active after pooled FIFO
        /// consumption. Missing id ⇒ the open wasn't seen (shouldn't
        /// happen; treat as fully open).
        var remainingByOpenID: [String: Double] = [:]
        /// Close trade id → FIFO-weighted average entry premium of
        /// the opens this close consumed. Missing id ⇒ the close
        /// found no opens at all in its chain (true orphan); Perf
        /// skips it, same as the old behavior for NULL links.
        var entryPremiumByCloseID: [String: Double] = [:]
    }

    static func key(_ t: OptionTradeRow) -> Key {
        Key(
            ticker: t.ticker.uppercased(),
            optionType: t.option_type,
            direction: t.direction,
            strike: t.strike,
            expiry: t.expiry
        )
    }

    /// Build the full ledger for a trade set. O(n log n) per chain;
    /// portfolio-scale inputs (hundreds of rows) take well under a
    /// millisecond. Callers that run per-frame should memoize —
    /// see PortfolioStore.fifoLedger().
    static func build(trades: [OptionTradeRow]) -> Ledger {
        var ledger = Ledger()
        let grouped = Dictionary(grouping: trades, by: key)

        for (_, rows) in grouped {
            // Chronological, id as tiebreaker so same-day fills have
            // a stable order on every device.
            let opens = rows
                .filter { $0.action == "open" }
                .sorted { ($0.trade_date, $0.id) < ($1.trade_date, $1.id) }
            let closes = rows
                .filter { $0.action == "close" }
                .sorted { ($0.trade_date, $0.id) < ($1.trade_date, $1.id) }

            // Mutable open slots with remaining capacity.
            var slots = opens.map { (id: $0.id, premium: $0.premium, left: $0.contracts) }
            var cursor = 0

            for c in closes {
                var need = c.contracts
                var costAccum = 0.0
                var allocated = 0.0

                while need > 0 && cursor < slots.count {
                    let take = min(need, slots[cursor].left)
                    if take > 0 {
                        slots[cursor].left -= take
                        costAccum += take * slots[cursor].premium
                        allocated += take
                        need -= take
                    }
                    if slots[cursor].left <= 0 { cursor += 1 }
                }

                if allocated > 0 {
                    // Any over-close remainder (more closed than ever
                    // opened — bad data) is valued at the close's own
                    // premium so it contributes zero P/L instead of
                    // phantom gains.
                    let entry = (costAccum + need * c.premium) / c.contracts
                    ledger.entryPremiumByCloseID[c.id] = entry
                }
                // allocated == 0 → true orphan; leave absent.
            }

            for slot in slots {
                ledger.remainingByOpenID[slot.id] = max(0, slot.left)
            }
        }

        return ledger
    }
}
