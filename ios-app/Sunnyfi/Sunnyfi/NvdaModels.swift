//
//  NvdaModels.swift
//  Sunnyfi — Ink rebuild
//
//  The NVDA store's row types + the fresh derivation engine. Everything the
//  screens read is computed here from the nvda_* tables — no carry-over from
//  the old covered-call engine. Rules follow the Ink handoff §4:
//    • one card per net-open (side · kind · strike · expiry)
//    • direction is semantic: a short leg is "good" when the mark is below entry
//    • position Greeks sum per leg × 100 × sign(long +1 / short −1)
//    • missing data is nil → "—"; never a stale value shown as live
//

import Foundation

// MARK: - Row types (decoded from nvda_* tables)

struct NvOptionTrade: Codable, Sendable {
    let id: String
    let trade_date: String
    let action: String            // open | close
    let option_type: String       // call | put
    let direction: String         // long | short
    let contracts: Double
    let strike: Double
    let premium: Double
    let expiry: String
    let voided_at: String?
}

struct NvShareLot: Codable, Sendable {
    let id: String
    let qty_remaining: Double
    let cost_per_share: Double
    let voided_at: String?
    /// Consumption order. Shares called away leave oldest-first, so the gain on an
    /// assignment is measured against these lots, not against the book average.
    var fifo_order: Int? = nil
    var acquired_date: String? = nil
}

struct NvShareSell: Codable, Sendable {
    let id: String
    let trade_date: String
    let quantity: Double
    let price: Double
    let realized_pl: Double?
    let voided_at: String?
}

struct NvQuote: Codable, Sendable {
    let ticker: String
    let spot: Double?
    let day_change_pct: Double?
    let prev_close: Double?
    let captured_at: String?
}

struct NvDailyClose: Codable, Sendable {
    let ticker: String
    let date: String
    let close_price: Double?
}

struct NvOptionMarkEod: Codable, Sendable {
    let option_trade_id: String
    let date: String
    let mark: Double?
    let delta: Double?
    let theta: Double?
}

struct NvIvDaily: Codable, Sendable {
    let ticker: String
    let date: String
    let iv: Double?               // ATM/representative IV that session (decimal)
}

struct NvOptionMark: Codable, Sendable {
    let option_trade_id: String
    let mark: Double?
    let delta: Double?
    let gamma: Double?
    let theta: Double?
    let vega: Double?
    let iv: Double?
    let captured_at: String?
}

// MARK: - Derived models (what the cards render)

struct NvStrike: Identifiable, Sendable {
    let side: String              // short | long
    let kind: String              // call | put
    let strike: Double
    let expiry: String            // display, e.g. "Aug 15 '26"
    let dte: String               // "22 DTE" | "expired"
    let expired: Bool
    let ct: Double                // net open contracts
    let basis: Double             // collected (short) | paid (long)
    let current: Double           // mark × ct × 100 (cost to close | value)
    let mark: Double?
    let moneyness: String         // ITM | OTM
    let delta: Double?
    let theta: Double?
    var deltaEst: Double = 0       // signed share-equiv delta (live greek or estimate) × ct × 100
    var isNew: Bool = false        // opened within the last day → "NEW" tag
    var id: String { "\(kind)-\(side)-\(strike)-\(expiry)" }
    /// Semantic direction for the hue: a rising mark is against a short, for a long.
    var good: Bool? {
        guard let mark, ct > 0 else { return nil }
        let entry = basis / (ct * 100)
        if abs(mark - entry) / max(entry, 0.0001) < 0.0005 { return nil }
        return side == "short" ? mark <= entry : mark >= entry
    }
}

struct NvSleeve: Identifiable, Sendable {
    let name: String              // Shares | Calls sold | Calls bought | Puts sold | Puts bought
    let side: String              // long | short
    let kind: String              // call | put | shares
    let qty: Int                  // contracts (or shares)
    let basisLabel: String        // "collected" | "paid"
    let basis: Double
    var id: String { name }
}

struct NvGroup: Identifiable, Sendable {
    let label: String             // Calls sold | Calls bought | Puts bought | Puts sold
    let glyph: String             // ▲ △ ▼ ▽
    let strikes: [NvStrike]
    var id: String { label }
}

enum NvFresh: Sendable { case live, delayed, stale }

struct NvPerfSleeve: Identifiable, Sendable {
    let name: String
    let glyph: String
    let total: Int
    let basisLabel: String        // Collected | Paid
    let basis: Double
    let realized: Double
    let unrealized: Double
    let empty: Bool
    var id: String { name }
}

struct NvPerf: Sendable {
    let realized: Double          // closed P&L (options + shares)
    let lifetime: Double          // realized + still-open premium
    let perShare: Double          // short-call premium per share
    let perSharePct: Double
    let costBasis: Double
    let breakEven: Double
    let cushion: Double           // spot − break-even
    let cushionPct: Double
    let sleeves: [NvPerfSleeve]
}

// Section 3 · insights — matches the Ink design's Volatility + Protection gauge cards.
struct NvProtection: Sendable {
    let putContracts: Int
    let shares: Double
    let covered: Double            // shares floored (delta-weighted), rounded for display
    let coveredPct: Double         // 0…100, the gauge value
    let floorLow: Double           // lowest open long-put strike
    let floorHigh: Double          // highest open long-put strike (best floor)
    let uncovered: Double          // shares with no floor
    let cushion: Double            // spot − break-even, in $
    let cushionPct: Double         // % over break-even
    let empty: Bool
}
struct NvVol: Sendable {
    let score: Double              // SELLER SCORE = (IV / HV30) × IV-percentile factor (the gauge). ~0.8–1.3
    let verdict: String            // zone: rich | favorable | neutral | cheap | very cheap | building
    let iv: Double?                // ATM implied vol, % (nil until the IV feed lands)
    let ivPrev: Double?           // previous close IV, %
    let hv30: Double?             // realized (historical) vol, % — StdDev(log rets, 30d) × √252
    let ivr: Double?              // IV percentile 0…100 (rank vs the stock's own 1-yr IV history)
    let factor: Double?           // IV-percentile factor: >70 → 1.2, 30–70 → 1.0, <30 → 0.8
    let iv52Low: Double?
    let iv52High: Double?
    let spread: Double?           // implied − realized, in vol points
    let building: Bool             // true when the IV feed hasn't populated yet
}

/// Seller-score zone from the score value (docs: > 1.20 rich … < 0.80 very cheap).
enum NvSellZone {
    static func label(_ s: Double) -> String {
        s > 1.20 ? "rich" : s >= 1.00 ? "favorable" : s >= 0.90 ? "neutral" : s >= 0.80 ? "cheap" : "very cheap"
    }
    /// Law-1 hue: opportunity (sell) = flood/gain blue; cheap/skip = severe→fire.
    static func tintName(_ s: Double) -> String {
        s >= 1.00 ? "gain" : s >= 0.90 ? "dim" : s >= 0.80 ? "delayed" : "loss"
    }
}
struct NvVegaLeg: Identifiable, Sendable {
    let name: String              // Calls sold | Puts bought | …
    let kind: String              // call | put
    let side: String              // long | short
    let ct: Int
    let v: Double                 // signed $ per IV point for this sleeve
    var id: String { name }
}

struct NvVega: Sendable {
    let iv: Double                // current ATM IV, %
    let avg30: Double             // 30-day average IV, %
    let lo: Double                // scrubber floor, %
    let hi: Double                // scrubber ceiling, %
    let net: Double               // total signed $ per IV point
    let stance: String            // long vega | short vega | vega-flat
    let daysToEarnings: Int?      // next NVDA earnings, nil if unknown
    let legs: [NvVegaLeg]
    var empty: Bool { legs.isEmpty }
}

struct NvInsights: Sendable {
    let protection: NvProtection
    let vol: NvVol
    let vega: NvVega?
    let fresh: NvFresh
}

// Section 4 · peers & ETFs — 5-session tape, grouped NVDA / ETFs / Peers.
struct NvPeerDay: Identifiable, Sendable {
    let label: String             // "Jul 24"
    let close: Double
    let pct: Double               // day-over-day %
    var id: String { label }
}
struct NvPeerTape: Identifiable, Sendable {
    let ticker: String
    let name: String              // "S&P 500", "Broadcom", …
    let group: String             // "self" | "ETFs" | "Peers"
    let last: Double?
    let net: Double?              // % across the shown sessions
    let days: [NvPeerDay]
    let vsNvda: Double?           // net − NVDA net, in points
    var id: String { ticker }
}
struct NvPeers: Sendable {
    let tapes: [NvPeerTape]
    let fresh: NvFresh
}

// Section 5 · historical performance — per-session P&L split by source, by month.
struct NvHistSource: Identifiable, Sendable {
    let key: String               // shares | callsSold | callsBought | putsSold | putsBought
    let label: String
    let glyph: String             // ○ ▲ △ ▼ ▽
    let empty: Bool               // no data for this source anywhere → disabled chip
    var id: String { key }
}
struct NvHistBar: Identifiable, Sendable {
    let iso: String               // "2026-07-24" — the session date, for week grouping
    let label: String             // "24"
    let sub: String               // "Jul 24"
    let pending: Bool
    let vals: [String: Double]    // keyed by source key
    var id: String { iso }
}
struct NvHistMonth: Identifiable, Sendable {
    let label: String             // "July"
    let short: String             // "Jul"
    let bars: [NvHistBar]
    var id: String { short }
}
struct NvHistory: Sendable {
    let months: [NvHistMonth]
    let sources: [NvHistSource]
    let fresh: NvFresh
}

/// The one canonical P&L result. Every screen reads these named fields — see
/// docs/PNL_GLOSSARY.md. Do NOT reinterpret realized/unrealized elsewhere.
struct NvPnL: Sendable {
    // 1 · REALIZED (closed only)
    let realized: Double
    let realizedStock: Double
    let premiumRealized: Double      // closed/expired short premium (net buybacks)
    let longRealized: Double         // proceeds − cost on closed/expired longs
    let dividends: Double
    // 2 · UNREALIZED (open, marked)
    let unrealized: Double
    let sharesUnrealized: Double
    let openShortValue: Double        // cost to close open shorts (a liability)
    let openLongValue: Double
    let longCostBasis: Double
    // 3 · NET
    let net: Double
    // 4 · PREMIUM (calls sold + puts sold)
    let premiumUnrealized: Double
    let premiumTotal: Double
    // 5 · COST (calls bought + puts bought)
    let costRealized: Double
    let costUnrealized: Double
    let costTotal: Double
    // context
    let shares: Double
    let avgBuy: Double
    let spot: Double
}

struct NvPosition: Sendable {
    let spot: Double
    let dayChangePct: Double
    let shares: Double
    let avgBuy: Double
    let sharesPaid: Double
    let sharesValue: Double
    let sharesPL: Double
    let premiumPerShare: Double   // lifetime short-call premium / shares
    let breakEven: Double         // avgBuy − premiumPerShare (the "safeguarded to")
    let delta: Double
    let gamma: Double
    let theta: Double
    let optionsPL: Double
    let pnl: Double
    let contractsOpen: Int
    let sleeves: [NvSleeve]
    let groups: [NvGroup]
    let fresh: NvFresh
    let freshText: String
}

// MARK: - Derivation

enum NvDerive {

    static func position(trades: [NvOptionTrade], lots: [NvShareLot], quote: NvQuote?,
                         marks: [NvOptionMark], now: Date = Date()) -> NvPosition? {
        // A non-positive spot is bad market data (e.g. a pre-open zero trade),
        // not a real price — don't derive garbage P&L off it.
        guard let spot = quote?.spot, spot > 0 else { return nil }

        // ── shares ──
        let openLots = lots.filter { $0.voided_at == nil }
        let shares = openLots.reduce(0) { $0 + $1.qty_remaining }
        let avgBuy = shares > 0 ? openLots.reduce(0) { $0 + $1.qty_remaining * $1.cost_per_share } / shares : 0
        let sharesPaid = shares * avgBuy
        let sharesValue = shares * spot
        let sharesPL = (spot - avgBuy) * shares

        // ── option legs: net-open by (side,kind,strike,expiry) ──
        let live = trades.filter { $0.voided_at == nil }
        let markByTrade = Dictionary(marks.map { ($0.option_trade_id, $0) }, uniquingKeysWith: { a, _ in a })

        struct Key: Hashable { let side, kind: String; let strike: Double; let expiry: String }
        var net: [Key: Double] = [:]
        var openBasis: [Key: Double] = [:]
        var anyOpenId: [Key: String] = [:]
        var openedAt: [Key: String] = [:]           // most-recent open date, for the NEW tag
        for t in live {
            let k = Key(side: t.direction, kind: t.option_type, strike: t.strike, expiry: t.expiry)
            net[k, default: 0] += (t.action == "open" ? 1 : -1) * t.contracts
            if t.action == "open" {
                openBasis[k, default: 0] += t.premium * t.contracts * 100
                if anyOpenId[k] == nil { anyOpenId[k] = t.id }
                if openedAt[k] == nil || t.trade_date > openedAt[k]! { openedAt[k] = t.trade_date }
            }
        }

        var strikes: [NvStrike] = []
        for (k, ct) in net where ct > 0.0001 {
            let m = anyOpenId[k].flatMap { markByTrade[$0] }
            let expired = isExpired(k.expiry, now: now)
            let mkNow = expired ? nil : m?.mark
            let current = (mkNow ?? 0) * ct * 100
            // per-contract basis reflects the OPEN legs of this net position
            let basis = openBasis[k] ?? 0
            let itm = k.kind == "call" ? spot >= k.strike : spot <= k.strike
            // Signed share-equivalent delta for this leg — same formula as the
            // position total: live greek, or a moneyness estimate when Polygon
            // drops it, × 100 × contracts × sign. Expired legs contribute 0.
            let dEst = expired ? 0
                : (m?.delta ?? estimateDelta(kind: k.kind, strike: k.strike, spot: spot))
                  * ct * 100 * (k.side == "long" ? 1 : -1)
            strikes.append(NvStrike(
                side: k.side, kind: k.kind, strike: k.strike, expiry: displayExpiry(k.expiry),
                dte: expired ? "expired" : "\(daysTo(k.expiry, now: now)) DTE", expired: expired,
                ct: ct, basis: basis, current: current, mark: mkNow,
                moneyness: itm ? "ITM" : "OTM", delta: m?.delta, theta: m?.theta,
                deltaEst: dEst,
                isNew: !expired && openedWithinADay(openedAt[k], now: now)))
        }

        // ── position Greeks (per leg × 100 × sign) ──
        func greekSum(_ pick: (NvOptionMark) -> Double?) -> Double {
            var total = 0.0
            for (k, ct) in net where ct > 0.0001 {
                guard let id = anyOpenId[k], let m = markByTrade[id], let g = pick(m) else { continue }
                if isExpired(k.expiry, now: now) { continue }
                total += g * ct * 100 * (k.side == "long" ? 1 : -1)
            }
            return total
        }
        // Delta must NEVER drop a leg — Polygon returns null greeks for thin
        // (deep-ITM) contracts intermittently, and dropping them made the total
        // jump by thousands. When a leg has no live delta, estimate it from
        // moneyness so the sum stays stable. Share delta = 1 per share.
        var deltaTotal = shares
        for (k, ct) in net where ct > 0.0001 {
            if isExpired(k.expiry, now: now) { continue }
            let live = anyOpenId[k].flatMap { markByTrade[$0]?.delta }
            let d = live ?? estimateDelta(kind: k.kind, strike: k.strike, spot: spot)
            deltaTotal += d * ct * 100 * (k.side == "long" ? 1 : -1)
        }
        let delta = deltaTotal
        let gamma = greekSum { $0.gamma }
        let theta = greekSum { $0.theta }

        // ── options P&L (long: value − paid · short: collected − value) ──
        var optionsPL = 0.0
        for s in strikes {
            optionsPL += s.side == "long" ? (s.current - s.basis) : (s.basis - s.current)
        }
        let pnl = sharesPL + optionsPL

        // ── lifetime short-call premium / share → effective break-even ──
        let shortCallPrem = live.filter { $0.option_type == "call" && $0.direction == "short" }
            .reduce(0.0) { $0 + ($1.action == "open" ? 1 : -1) * $1.premium * $1.contracts * 100 }
        let premPerShare = shares > 0 ? shortCallPrem / shares : 0
        let breakEven = avgBuy - premPerShare

        // ── sleeves + groups ──
        let sleeves = buildSleeves(live: live)
        let groups = buildGroups(strikes: strikes)
        let contractsOpen = Int(strikes.reduce(0) { $0 + $1.ct }.rounded())

        let (fresh, freshText) = freshness(quote?.captured_at, now: now)

        return NvPosition(
            spot: spot, dayChangePct: quote?.day_change_pct ?? 0,
            shares: shares, avgBuy: avgBuy, sharesPaid: sharesPaid, sharesValue: sharesValue, sharesPL: sharesPL,
            premiumPerShare: premPerShare, breakEven: breakEven,
            delta: delta, gamma: gamma, theta: theta, optionsPL: optionsPL, pnl: pnl,
            contractsOpen: contractsOpen, sleeves: sleeves, groups: groups, fresh: fresh, freshText: freshText)
    }

    // MARK: - Section 2 · performance (delayed / EOD)

    static func performance(trades: [NvOptionTrade], lots: [NvShareLot], sells: [NvShareSell],
                            quote: NvQuote?, marks: [NvOptionMark], now: Date = Date()) -> NvPerf? {
        guard let spot = quote?.spot, spot > 0 else { return nil }
        let live = trades.filter { $0.voided_at == nil }
        let openLots = lots.filter { $0.voided_at == nil }
        let shares = openLots.reduce(0) { $0 + $1.qty_remaining }
        let avgBuy = shares > 0 ? openLots.reduce(0) { $0 + $1.qty_remaining * $1.cost_per_share } / shares : 0
        let markByTrade = Dictionary(marks.map { ($0.option_trade_id, $0) }, uniquingKeysWith: { a, _ in a })

        struct Key: Hashable { let side, kind: String; let strike: Double; let expiry: String }
        var net: [Key: Double] = [:]; var anyId: [Key: String] = [:]
        for t in live {
            let k = Key(side: t.direction, kind: t.option_type, strike: t.strike, expiry: t.expiry)
            net[k, default: 0] += (t.action == "open" ? 1 : -1) * t.contracts
            if t.action == "open", anyId[k] == nil { anyId[k] = t.id }
        }
        func openPrem(_ kind: String, _ dir: String) -> Double {
            live.filter { $0.option_type == kind && $0.direction == dir && $0.action == "open" }
                .reduce(0.0) { $0 + $1.premium * $1.contracts * 100 }
        }
        func netPrem(_ kind: String, _ dir: String) -> Double {
            live.filter { $0.option_type == kind && $0.direction == dir }
                .reduce(0.0) { $0 + ($1.action == "open" ? 1 : -1) * $1.premium * $1.contracts * 100 }
        }
        func writtenCt(_ kind: String, _ dir: String) -> Int {
            Int(live.filter { $0.option_type == kind && $0.direction == dir && $0.action == "open" }.reduce(0.0) { $0 + $1.contracts }.rounded())
        }
        func netOpenCt(_ kind: String, _ dir: String) -> Int {
            Int(net.filter { $0.key.kind == kind && $0.key.side == dir && $0.value > 0.0001 }.values.reduce(0, +).rounded())
        }
        func sleeveMTM(_ kind: String, _ dir: String) -> Double {
            var s = 0.0
            for (k, c) in net where c > 0.0001 && k.kind == kind && k.side == dir {
                s += (anyId[k].flatMap { markByTrade[$0]?.mark } ?? 0) * c * 100
            }
            return s
        }
        // Realized P&L on CLOSED / expired LONG options of a kind (proceeds on
        // the sold portion − its cost; expired-worthless loses the cost). This is
        // what the Calls-bought / Puts-bought sleeves book — it was hardcoded 0.
        func longRealized(_ kind: String) -> Double {
            struct A { var openCt = 0.0, closeCt = 0.0, openPrem = 0.0, closePrem = 0.0 }
            var byKey: [Key: A] = [:]
            for t in live where t.option_type == kind && t.direction == "long" {
                let k = Key(side: "long", kind: kind, strike: t.strike, expiry: t.expiry)
                var a = byKey[k] ?? A()
                if t.action == "open" { a.openCt += t.contracts; a.openPrem += t.premium * t.contracts * 100 }
                else { a.closeCt += t.contracts; a.closePrem += t.premium * t.contracts * 100 }
                byKey[k] = a
            }
            var r = 0.0
            for (k, a) in byKey {
                let avg = a.openCt > 0 ? a.openPrem / a.openCt : 0
                let netCt = a.openCt - a.closeCt
                let expired = isExpired(k.expiry, now: now)
                r += (a.closePrem - a.closeCt * avg) + (expired ? -netCt * avg : 0)
            }
            return r
        }

        // ── the settled covered-call model (do NOT re-derive; see memory) ──
        // Banked = lifetime short-call premium collected in CASH (incl still-open
        // calls, net of buybacks; never marked) + realized share P&L. This is the
        // hero and it is positive for a roller. §1's break-even uses the same
        // per-share premium, so the two reconcile.
        let premLifetime = netPrem("call", "short")           // net short-call cash
        // premium collected on the contracts that are STILL open (per key, no double-count)
        var openShortPrem = 0.0
        for (k, c) in net where c > 0.0001 && k.kind == "call" && k.side == "short" {
            let opens = live.filter { $0.direction == "short" && $0.option_type == "call"
                && $0.strike == k.strike && $0.expiry == k.expiry && $0.action == "open" }
            let openCt = opens.reduce(0.0) { $0 + $1.contracts }
            let openPremK = opens.reduce(0.0) { $0 + $1.premium * $1.contracts * 100 }
            let perContract = openCt > 0 ? openPremK / openCt : 0
            openShortPrem += c * perContract                  // c = net-open contracts
        }
        let realizedShares = sells.filter { $0.voided_at == nil }.reduce(0.0) { $0 + ($1.realized_pl ?? 0) }
        // Assigned-call premium is EXCLUDED (captured in the share sale at strike,
        // per IBKR — same rule as NvDerive.pnl()), so the Calls-sold sleeve
        // reconciles to the Realized total. Assignment = ≈$0 short-call close with
        // a same-day share sell at the strike.
        let assignSig = Set(sells.filter { $0.voided_at == nil }.map { "\($0.trade_date)|\(Int($0.price.rounded()))" })
        var assignedCallPrem = 0.0
        do {
            struct CA { var openCt = 0.0, openPrem = 0.0, assignedCt = 0.0 }
            var byCall: [Key: CA] = [:]
            for t in live where t.option_type == "call" && t.direction == "short" {
                let k = Key(side: "short", kind: "call", strike: t.strike, expiry: t.expiry)
                var a = byCall[k] ?? CA()
                if t.action == "open" { a.openCt += t.contracts; a.openPrem += t.premium * t.contracts * 100 }
                else if t.premium < 0.01, assignSig.contains("\(t.trade_date)|\(Int(t.strike.rounded()))") { a.assignedCt += t.contracts }
                byCall[k] = a
            }
            for (_, a) in byCall { assignedCallPrem += (a.openCt > 0 ? a.openPrem / a.openCt : 0) * a.assignedCt }
        }
        let realizedClosedCalls = premLifetime - openShortPrem - assignedCallPrem   // premium on closed short calls (ex-assigned)
        let banked = premLifetime + realizedShares               // hero
        let perShare = shares > 0 ? premLifetime / shares : 0
        let breakEven = avgBuy - perShare
        let cushion = spot - breakEven

        let csCt = writtenCt("call", "short"), csColl = openPrem("call", "short")
        let cbCt = netOpenCt("call", "long"), cbPaid = openPrem("call", "long")
        let psCt = netOpenCt("put", "short")
        let pbCt = netOpenCt("put", "long"), pbPaid = openPrem("put", "long")
        let sharesPaidPerf = shares * avgBuy
        let sharesUnrealPerf = (spot - avgBuy) * shares
        let sleeves: [NvPerfSleeve] = [
            .init(name: "Shares", glyph: "○", total: Int(shares.rounded()), basisLabel: "Paid", basis: sharesPaidPerf,
                  realized: realizedShares, unrealized: sharesUnrealPerf, empty: shares == 0),
            .init(name: "Calls sold", glyph: "▲", total: csCt, basisLabel: "Collected", basis: csColl,
                  realized: realizedClosedCalls, unrealized: openShortPrem - sleeveMTM("call", "short"), empty: csCt == 0 && csColl == 0),
            .init(name: "Calls bought", glyph: "△", total: cbCt, basisLabel: "Paid", basis: cbPaid,
                  realized: longRealized("call"), unrealized: sleeveMTM("call", "long") - cbPaid,
                  empty: writtenCt("call", "long") == 0),
            .init(name: "Puts sold", glyph: "▼", total: psCt, basisLabel: "Collected", basis: openPrem("put", "short"),
                  realized: 0, unrealized: 0, empty: psCt == 0),
            .init(name: "Puts bought", glyph: "▽", total: pbCt, basisLabel: "Paid", basis: pbPaid,
                  realized: longRealized("put"), unrealized: sleeveMTM("put", "long") - pbPaid,
                  empty: writtenCt("put", "long") == 0),
        ]
        return NvPerf(realized: banked, lifetime: premLifetime, perShare: perShare,
                      perSharePct: avgBuy > 0 ? perShare / avgBuy * 100 : 0, costBasis: avgBuy, breakEven: breakEven,
                      cushion: cushion, cushionPct: breakEven > 0 ? cushion / breakEven * 100 : 0, sleeves: sleeves)
    }

    // MARK: - Canonical P&L (docs/PNL_GLOSSARY.md — the ONE implementation)

    static func pnl(trades: [NvOptionTrade], lots: [NvShareLot], sells: [NvShareSell],
                    quote: NvQuote?, marks: [NvOptionMark], now: Date = Date()) -> NvPnL? {
        guard let spot = quote?.spot, spot > 0 else { return nil }
        let live = trades.filter { $0.voided_at == nil }
        let openLots = lots.filter { $0.voided_at == nil }
        let shares = openLots.reduce(0) { $0 + $1.qty_remaining }
        let avgBuy = shares > 0 ? openLots.reduce(0) { $0 + $1.qty_remaining * $1.cost_per_share } / shares : 0
        let markByTrade = Dictionary(marks.map { ($0.option_trade_id, $0) }, uniquingKeysWith: { a, _ in a })
        let openSells = sells.filter { $0.voided_at == nil }
        let realizedStock = openSells.reduce(0.0) { $0 + ($1.realized_pl ?? 0) }
        // Assignment signature — a short call assigned sells shares AT the strike
        // on the trade date. Matching (date, strike) lets us tell an ASSIGNMENT
        // (premium is NOT re-realized on the option; it's already captured in the
        // stock sale at strike — IBKR's convention, see PNL_GLOSSARY) apart from an
        // EXPIRY (premium kept) or a normal buyback (premium > 0).
        let assignSig = Set(openSells.map { "\($0.trade_date)|\(Int($0.price.rounded()))" })

        struct Key: Hashable { let kind, dir: String; let strike: Double; let expiry: String }
        struct Agg { var openCt = 0.0, closeCt = 0.0, openPrem = 0.0, closePrem = 0.0, assignedCt = 0.0; var markId: String? }
        var byKey: [Key: Agg] = [:]
        for t in live {
            let k = Key(kind: t.option_type, dir: t.direction, strike: t.strike, expiry: t.expiry)
            var a = byKey[k] ?? Agg()
            if t.action == "open" { a.openCt += t.contracts; a.openPrem += t.premium * t.contracts * 100; if a.markId == nil { a.markId = t.id } }
            else {
                a.closeCt += t.contracts; a.closePrem += t.premium * t.contracts * 100
                // Assigned short call (premium ≈ 0 close + a same-day share sell at
                // the strike): its collected premium stays OUT of realized P&L.
                if t.direction == "short", t.option_type == "call", t.premium < 0.01,
                   assignSig.contains("\(t.trade_date)|\(Int(t.strike.rounded()))") {
                    a.assignedCt += t.contracts
                }
            }
            byKey[k] = a
        }

        var premiumRealized = 0.0, premiumUnrealized = 0.0, openShortValue = 0.0
        var longRealized = 0.0, costRealized = 0.0, costUnrealized = 0.0, openLongValue = 0.0, longCostBasis = 0.0
        for (k, a) in byKey {
            let netCt = a.openCt - a.closeCt
            let avg = a.openCt > 0 ? a.openPrem / a.openCt : 0        // premium/contract (×100 already in)
            let expired = isExpired(k.expiry, now: now)
            let mark = a.markId.flatMap { markByTrade[$0]?.mark } ?? 0
            if k.dir == "short" {
                // Assigned contracts' premium is excluded (− assignedCt·avg): it is
                // captured in the stock sale at strike, not double-booked here.
                premiumRealized += (a.closeCt * avg - a.closePrem) - a.assignedCt * avg + (expired ? netCt * avg : 0)
                if !expired { premiumUnrealized += netCt * avg; openShortValue += mark * netCt * 100 }
            } else {
                longRealized += (a.closePrem - a.closeCt * avg) + (expired ? -netCt * avg : 0)
                costRealized += a.closeCt * avg + (expired ? netCt * avg : 0)
                if !expired { costUnrealized += netCt * avg; openLongValue += mark * netCt * 100; longCostBasis += netCt * avg }
            }
        }

        let dividends = 0.0
        let realized = realizedStock + premiumRealized + longRealized + dividends
        let sharesUnrealized = (spot - avgBuy) * shares
        let unrealized = sharesUnrealized - openShortValue + (openLongValue - longCostBasis)
        return NvPnL(
            realized: realized, realizedStock: realizedStock, premiumRealized: premiumRealized,
            longRealized: longRealized, dividends: dividends,
            unrealized: unrealized, sharesUnrealized: sharesUnrealized, openShortValue: openShortValue,
            openLongValue: openLongValue, longCostBasis: longCostBasis,
            net: realized + unrealized,
            premiumUnrealized: premiumUnrealized, premiumTotal: premiumRealized + premiumUnrealized,
            costRealized: costRealized, costUnrealized: costUnrealized, costTotal: costRealized + costUnrealized,
            shares: shares, avgBuy: avgBuy, spot: spot)
    }

    // MARK: - Section 3 · insights (protection + volatility)

    static func insights(trades: [NvOptionTrade], lots: [NvShareLot], marks: [NvOptionMark],
                         quote: NvQuote?, closes: [NvDailyClose], ivDaily: [NvIvDaily] = [],
                         now: Date = Date()) -> NvInsights {
        let spot = quote?.spot ?? 0
        let live = trades.filter { $0.voided_at == nil }
        let openLots = lots.filter { $0.voided_at == nil }
        let shares = openLots.reduce(0) { $0 + $1.qty_remaining }
        let avgBuy = shares > 0 ? openLots.reduce(0) { $0 + $1.qty_remaining * $1.cost_per_share } / shares : 0
        let markByTrade = Dictionary(marks.map { ($0.option_trade_id, $0) }, uniquingKeysWith: { a, _ in a })

        // effective break-even = cost − lifetime short-call premium / share (same as §1)
        let shortCallPrem = live.filter { $0.option_type == "call" && $0.direction == "short" }
            .reduce(0.0) { $0 + ($1.action == "open" ? 1 : -1) * $1.premium * $1.contracts * 100 }
        let breakEven = avgBuy - (shares > 0 ? shortCallPrem / shares : 0)
        let cushion = spot > 0 ? spot - breakEven : 0
        let cushionPct = breakEven > 0 ? cushion / breakEven * 100 : 0

        // ── protection: net-open LONG puts, delta-weighted coverage ──
        struct PKey: Hashable { let strike: Double; let expiry: String }
        var net: [PKey: Double] = [:]; var anyId: [PKey: String] = [:]
        for t in live where t.option_type == "put" && t.direction == "long" {
            let k = PKey(strike: t.strike, expiry: t.expiry)
            net[k, default: 0] += (t.action == "open" ? 1 : -1) * t.contracts
            if t.action == "open", anyId[k] == nil { anyId[k] = t.id }
        }
        var covered = 0.0, ct = 0.0, floors: [Double] = []
        for (k, c) in net where c > 0.0001 && !isExpired(k.expiry, now: now) {
            ct += c; floors.append(k.strike)
            if let d = anyId[k].flatMap({ markByTrade[$0]?.delta }) { covered += -d * c * 100 }
        }
        let coveredR = covered.rounded()
        let protection = NvProtection(
            putContracts: Int(ct.rounded()), shares: shares, covered: coveredR,
            coveredPct: shares > 0 ? min(100, covered / shares * 100) : 0,
            floorLow: floors.min() ?? 0, floorHigh: floors.max() ?? 0,
            uncovered: max(0, shares - coveredR), cushion: cushion, cushionPct: cushionPct,
            empty: ct < 0.5)

        // ── volatility · seller score. Needs the IV feed (IVR + 52w) to be live;
        //    until then we surface realized vol + an IV proxy and flag "building". ──
        let nvCloses = closes.filter { $0.ticker == "NVDA" }
            .compactMap { c in c.close_price.map { (c.date, $0) } }
            .sorted { $0.0 < $1.0 }.map { $0.1 }
        // ── SELLER SCORE = (IV / HV30) × IV-percentile factor ──
        // HV30: StdDev(daily log returns over the last 30 trading days) × √252.
        // Cap to the trailing 31 closes so it's a true 30-day window, not
        // "however many closes we happen to hold" (per docs/PNL spec).
        let hv = realizedVol(Array(nvCloses.suffix(31))).map { $0 * 100 }
        // Current ATM IV: prefer today's daily snapshot (the backend writes ATM
        // call+put avg IV, refreshed every 30 min); else fall back to the median
        // IV of the open legs so the card still reads before the feed lands.
        let today = Self.isoDay(now)
        let ivHist = ivDaily.compactMap { $0.iv }.filter { $0 > 0 }.map { $0 * 100 }
        let todaySnapIV = ivDaily.first(where: { $0.date == today })?.iv.map { $0 * 100 }
        let legIVs = live.compactMap { markByTrade[$0.id]?.iv }.filter { $0 > 0 }.sorted()
        let legMedianIV = legIVs.isEmpty ? nil : legIVs[legIVs.count / 2] * 100
        let iv: Double? = todaySnapIV ?? legMedianIV
        let spread: Double? = (iv != nil && hv != nil) ? iv! - hv! : nil
        // IV percentile — rank of current IV in the stock's own history. Needs a
        // meaningful window (≥ ~1 month); until the 1-yr backfill lands the factor
        // stays neutral (1.0) and the percentile reads "—".
        let ivPercentile: Double? = {
            guard let cur = iv, ivHist.count >= 20 else { return nil }
            let below = ivHist.filter { $0 < cur }.count
            return Double(below) / Double(ivHist.count) * 100
        }()
        let factor: Double = ivPercentile.map { $0 > 70 ? 1.2 : ($0 < 30 ? 0.8 : 1.0) } ?? 1.0
        let ratio: Double? = (iv != nil && (hv ?? 0) > 0) ? iv! / hv! : nil
        let sellerScore: Double? = ratio.map { $0 * factor }
        let building = iv == nil || hv == nil
        let verdict = building ? "building" : NvSellZone.label(sellerScore ?? 0)
        let ivPrev: Double? = ivDaily
            .filter { $0.date < today }
            .max(by: { $0.date < $1.date })
            .flatMap { d in d.iv.map { $0 * 100 } }
        let vol = NvVol(score: sellerScore ?? 0, verdict: verdict, iv: iv, ivPrev: ivPrev, hv30: hv,
                        ivr: ivPercentile, factor: ivPercentile != nil ? factor : nil,
                        iv52Low: nil, iv52High: nil, spread: spread, building: building)

        // ── vega: signed $ per IV point, aggregated by sleeve; the card lets you
        //    scrub IV and reads each leg's linear impact (vega × points). ──
        struct VKey: Hashable { let side, kind: String; let strike: Double; let expiry: String }
        var vnet: [VKey: Double] = [:]; var vAnyId: [VKey: String] = [:]
        for t in live {
            let k = VKey(side: t.direction, kind: t.option_type, strike: t.strike, expiry: t.expiry)
            vnet[k, default: 0] += (t.action == "open" ? 1 : -1) * t.contracts
            if t.action == "open", vAnyId[k] == nil { vAnyId[k] = t.id }
        }
        let vegaNames: [(kind: String, side: String, name: String)] = [
            ("call", "short", "Calls sold"), ("call", "long", "Calls bought"),
            ("put", "short", "Puts sold"), ("put", "long", "Puts bought"),
        ]
        var vLegs: [NvVegaLeg] = []; var vTotal = 0.0
        for m in vegaNames {
            var lct = 0.0, lv = 0.0
            for (k, c) in vnet where c > 0.0001 && k.kind == m.kind && k.side == m.side && !isExpired(k.expiry, now: now) {
                let vg = vAnyId[k].flatMap { markByTrade[$0]?.vega } ?? 0
                lct += c
                lv += vg * 100 * c * (m.side == "long" ? 1 : -1)   // $ per 1 IV point, signed
            }
            if lct > 0.0001 { vLegs.append(NvVegaLeg(name: m.name, kind: m.kind, side: m.side, ct: Int(lct.rounded()), v: lv)); vTotal += lv }
        }
        let vega: NvVega? = {
            guard !vLegs.isEmpty, let ivNow = iv else { return nil }
            let last30 = Array(ivHist.suffix(30))
            let avg30 = last30.isEmpty ? ivNow : last30.reduce(0, +) / Double(last30.count)
            let allIV = ivHist + [ivNow, avg30]
            let lo = max(1, ((allIV.min() ?? ivNow - 10) - 3).rounded(.down))
            let hi = ((allIV.max() ?? ivNow + 10) + 3).rounded(.up)
            let stance = abs(vTotal) < 1 ? "vega-flat" : (vTotal >= 0 ? "long vega" : "short vega")
            return NvVega(iv: ivNow, avg30: avg30, lo: lo, hi: hi, net: vTotal, stance: stance,
                          daysToEarnings: nil, legs: vLegs)
        }()

        return NvInsights(protection: protection, vol: vol, vega: vega, fresh: freshness(quote?.captured_at, now: now).0)
    }

    // MARK: - Section 4 · peers & ETFs (5-session tape)

    static func peers(quotes: [NvQuote], closes: [NvDailyClose], now: Date = Date()) -> NvPeers {
        let meta: [(tk: String, name: String, group: String)] = [
            ("NVDA", "NVIDIA", "self"), ("QQQ", "Nasdaq 100", "ETFs"), ("SPY", "S&P 500", "ETFs"),
            ("SMH", "Semis", "ETFs"), ("AVGO", "Broadcom", "Peers"), ("AMD", "AMD", "Peers"),
            ("ARM", "Arm", "Peers"), ("INTC", "Intel", "Peers"),
        ]
        let qByT = Dictionary(quotes.map { ($0.ticker, $0) }, uniquingKeysWith: { a, _ in a })
        var closesByT: [String: [(String, Double)]] = [:]
        for c in closes.sorted(by: { $0.date < $1.date }) {
            if let p = c.close_price { closesByT[c.ticker, default: []].append((c.date, p)) }
        }
        func build(_ tk: String) -> (days: [NvPeerDay], net: Double?) {
            let cs = Array((closesByT[tk] ?? []).suffix(6))   // up to 6 → 5 day-changes
            guard cs.count >= 2 else { return ([], nil) }
            var days: [NvPeerDay] = []
            for i in 1..<cs.count where cs[i - 1].1 > 0 {
                days.append(NvPeerDay(label: shortDate(cs[i].0), close: cs[i].1,
                                      pct: (cs[i].1 / cs[i - 1].1 - 1) * 100))
            }
            let net = cs.first!.1 > 0 ? (cs.last!.1 / cs.first!.1 - 1) * 100 : nil
            return (days, net)
        }
        let nvdaNet = build("NVDA").net
        let tapes: [NvPeerTape] = meta.map { m in
            let q = qByT[m.tk]; let b = build(m.tk)
            let vs: Double? = (b.net != nil && nvdaNet != nil && m.group != "self") ? b.net! - nvdaNet! : nil
            return NvPeerTape(ticker: m.tk, name: m.name, group: m.group, last: q?.spot,
                              net: b.net, days: b.days, vsNvda: vs)
        }
        return NvPeers(tapes: tapes, fresh: freshness(qByT["NVDA"]?.captured_at, now: now).0)
    }

    // MARK: - Section 5 · historical performance (per-session, by source)

    // REALIZED P&L per session (not unrealized marks) — reconciles with §2:
    //   Σ callsSold  = net short-call premium (= §2 lifetime premium)
    //   Σ shares     = realized share sells (= §2 realized shares)
    // Short legs book cash on open(+)/buyback(−); long legs book realized only
    // when CLOSED (proceeds − avg open cost) — an open hedge is unrealized, so it
    // never shows here. Bucketed by the trade's own date.
    static func history(trades: [NvOptionTrade], sells: [NvShareSell], now: Date = Date()) -> NvHistory {
        let live = trades.filter { $0.voided_at == nil }
        func bucket(_ kind: String, _ dir: String) -> String {
            kind == "call" ? (dir == "short" ? "callsSold" : "callsBought")
                           : (dir == "short" ? "putsSold" : "putsBought")
        }
        struct Key: Hashable { let kind, dir: String; let strike: Double; let expiry: String }
        var openCt: [Key: Double] = [:]; var openPrem: [Key: Double] = [:]
        for t in live where t.action == "open" {
            let k = Key(kind: t.option_type, dir: t.direction, strike: t.strike, expiry: t.expiry)
            openCt[k, default: 0] += t.contracts
            openPrem[k, default: 0] += t.premium * t.contracts * 100
        }
        func avgOpenPerContract(_ k: Key) -> Double { (openCt[k] ?? 0) > 0 ? openPrem[k]! / openCt[k]! : 0 }

        let keys = ["shares", "callsSold", "callsBought", "putsSold", "putsBought"]
        var byDate: [String: [String: Double]] = [:]
        var seen: Set<String> = []
        func add(_ date: String, _ src: String, _ v: Double) {
            guard v != 0 else { return }
            byDate[date, default: [:]][src, default: 0] += v
            seen.insert(src)
        }
        for t in live {
            let src = bucket(t.option_type, t.direction)
            let amt = t.premium * t.contracts * 100
            if t.direction == "short" {
                add(t.trade_date, src, t.action == "open" ? amt : -amt)     // collect on open, pay to buy back
            } else if t.action == "close" {
                let k = Key(kind: t.option_type, dir: t.direction, strike: t.strike, expiry: t.expiry)
                add(t.trade_date, src, amt - avgOpenPerContract(k) * t.contracts)   // proceeds − cost
            }
        }
        for s in sells where s.voided_at == nil { add(s.trade_date, "shares", s.realized_pl ?? 0) }

        // group by calendar month
        var monthsMap: [String: [NvHistBar]] = [:]
        var order: [String] = []
        for date in byDate.keys.sorted() {
            let mk = String(date.prefix(7))                // "2026-07"
            if monthsMap[mk] == nil { order.append(mk) }
            var vals = Dictionary(uniqueKeysWithValues: keys.map { ($0, 0.0) })
            for (src, v) in byDate[date]! { vals[src] = v }
            monthsMap[mk, default: []].append(NvHistBar(
                iso: date, label: dayNum(date), sub: shortDate(date), pending: false, vals: vals))
        }
        let months = order.map { mk in
            NvHistMonth(label: monthLong(mk), short: monthShort(mk), bars: monthsMap[mk] ?? [])
        }
        let sources: [NvHistSource] = [
            .init(key: "shares", label: "Shares", glyph: "○", empty: !seen.contains("shares")),
            .init(key: "callsSold", label: "Calls sold", glyph: "▲", empty: !seen.contains("callsSold")),
            .init(key: "callsBought", label: "Calls bought", glyph: "△", empty: !seen.contains("callsBought")),
            .init(key: "putsSold", label: "Puts sold", glyph: "▼", empty: !seen.contains("putsSold")),
            .init(key: "putsBought", label: "Puts bought", glyph: "▽", empty: !seen.contains("putsBought")),
        ]
        return NvHistory(months: months, sources: sources, fresh: months.isEmpty ? .stale : .delayed)
    }

    // MARK: helpers

    /// Annualised realised volatility from a close series (needs ≥6 closes).
    private static func realizedVol(_ closes: [Double]) -> Double? {
        guard closes.count >= 6 else { return nil }
        var rets: [Double] = []
        for i in 1..<closes.count where closes[i - 1] > 0 { rets.append(log(closes[i] / closes[i - 1])) }
        guard rets.count >= 5 else { return nil }
        let mean = rets.reduce(0, +) / Double(rets.count)
        let varc = rets.reduce(0) { $0 + pow($1 - mean, 2) } / Double(rets.count - 1)
        return sqrt(varc) * sqrt(252)
    }

    private static let shortDisp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; f.timeZone = TimeZone(identifier: "America/New_York"); return f
    }()
    private static func shortDate(_ ymd: String) -> String {
        iso.date(from: ymd).map { shortDisp.string(from: $0) } ?? ymd
    }
    private static func dayNum(_ ymd: String) -> String {
        String(Int(ymd.split(separator: "-").last ?? "0") ?? 0)
    }
    private static let monthNames = ["", "January", "February", "March", "April", "May", "June",
                                     "July", "August", "September", "October", "November", "December"]
    private static func monthLong(_ ym: String) -> String {   // "2026-07" → "July"
        let m = Int(ym.split(separator: "-").last ?? "0") ?? 0
        return monthNames.indices.contains(m) ? monthNames[m] : ym
    }
    private static func monthShort(_ ym: String) -> String {
        String(monthLong(ym).prefix(3))
    }

    private static func buildSleeves(live: [NvOptionTrade]) -> [NvSleeve] {
        func net(_ kind: String, _ dir: String) -> (ct: Double, basis: Double) {
            let rows = live.filter { $0.option_type == kind && $0.direction == dir }
            let ct = rows.reduce(0.0) { $0 + ($1.action == "open" ? 1 : -1) * $1.contracts }
            let basis = rows.filter { $0.action == "open" }.reduce(0.0) { $0 + $1.premium * $1.contracts * 100 }
            return (ct, basis)
        }
        var out: [NvSleeve] = []
        let cs = net("call", "short"); if cs.ct > 0 { out.append(.init(name: "Calls sold", side: "short", kind: "call", qty: Int(cs.ct.rounded()), basisLabel: "collected", basis: cs.basis)) }
        let cb = net("call", "long");  if cb.ct > 0 { out.append(.init(name: "Calls bought", side: "long", kind: "call", qty: Int(cb.ct.rounded()), basisLabel: "paid", basis: cb.basis)) }
        let ps = net("put", "short");  if ps.ct > 0 { out.append(.init(name: "Puts sold", side: "short", kind: "put", qty: Int(ps.ct.rounded()), basisLabel: "collected", basis: ps.basis)) }
        let pb = net("put", "long");   if pb.ct > 0 { out.append(.init(name: "Puts bought", side: "long", kind: "put", qty: Int(pb.ct.rounded()), basisLabel: "paid", basis: pb.basis)) }
        return out
    }

    private static func buildGroups(strikes: [NvStrike]) -> [NvGroup] {
        let order: [(label: String, side: String, kind: String, glyph: String)] = [
            ("Calls sold", "short", "call", "▲"), ("Calls bought", "long", "call", "△"),
            ("Puts sold", "short", "put", "▼"),  ("Puts bought", "long", "put", "▽"),
        ]
        return order.compactMap { g in
            let items = strikes.filter { $0.side == g.side && $0.kind == g.kind }.sorted { $0.strike < $1.strike }
            return items.isEmpty ? nil : NvGroup(label: g.label, glyph: g.glyph, strikes: items)
        }
    }

    private static let iso: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "America/New_York"); return f
    }()
    private static let disp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d ''yy"; f.timeZone = TimeZone(identifier: "America/New_York"); return f
    }()

    /// True when the leg was opened today or yesterday (the "NEW" tag lifetime).
    private static func openedWithinADay(_ date: String?, now: Date) -> Bool {
        guard let date, let d = iso.date(from: date) else { return false }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: now)).day ?? 99
        return days >= 0 && days <= 1
    }
    /// Rough delta from moneyness — ONLY a fallback when Polygon returns no live
    /// greek, so a leg is never dropped from the position delta (keeps it stable).
    private static func estimateDelta(kind: String, strike: Double, spot: Double) -> Double {
        guard spot > 0, strike > 0 else { return 0 }
        let m = (spot - strike) / strike                 // call moneyness; + = ITM call
        if kind == "call" { return min(0.99, max(0.01, 0.5 + m * 4)) }
        return max(-0.99, min(-0.01, -0.5 + m * 4))      // put: negative, deep-ITM → ≈ −1
    }
    static func isoDay(_ d: Date) -> String { iso.string(from: d) }
    private static func isExpired(_ expiry: String, now: Date) -> Bool { daysTo(expiry, now: now) < 0 }
    private static func daysTo(_ expiry: String, now: Date) -> Int {
        guard let e = iso.date(from: expiry) else { return 0 }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: e)).day ?? 0
    }
    private static func displayExpiry(_ expiry: String) -> String {
        iso.date(from: expiry).map { disp.string(from: $0) } ?? expiry
    }

    private static func freshness(_ capturedAt: String?, now: Date) -> (NvFresh, String) {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let s = capturedAt, let d = f.date(from: s) ?? ISO8601DateFormatter().date(from: s) else {
            return (.stale, "Stale · no data yet")
        }
        let age = now.timeIntervalSince(d)
        if age < 120 { return (.live, "Updated now · streaming") }
        if age < 1200 { return (.delayed, "Updated \(Int(age / 60)) min ago") }
        return (.stale, "Stale · next at market open")
    }
}
