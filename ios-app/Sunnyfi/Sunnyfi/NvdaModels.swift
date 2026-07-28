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
}

struct NvQuote: Codable, Sendable {
    let ticker: String
    let spot: Double?
    let day_change_pct: Double?
    let prev_close: Double?
    let captured_at: String?
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
        guard let spot = quote?.spot else { return nil }

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
        for t in live {
            let k = Key(side: t.direction, kind: t.option_type, strike: t.strike, expiry: t.expiry)
            net[k, default: 0] += (t.action == "open" ? 1 : -1) * t.contracts
            if t.action == "open" {
                openBasis[k, default: 0] += t.premium * t.contracts * 100
                if anyOpenId[k] == nil { anyOpenId[k] = t.id }
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
            strikes.append(NvStrike(
                side: k.side, kind: k.kind, strike: k.strike, expiry: displayExpiry(k.expiry),
                dte: expired ? "expired" : "\(daysTo(k.expiry, now: now)) DTE", expired: expired,
                ct: ct, basis: basis, current: current, mark: mkNow,
                moneyness: itm ? "ITM" : "OTM", delta: m?.delta, theta: m?.theta))
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
        let delta = greekSum { $0.delta }
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

    // MARK: helpers

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
