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

struct NvShareSell: Codable, Sendable {
    let id: String
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
    let score: Double              // seller score 0…100 (the gauge); sell zone ≥ 70
    let verdict: String            // sell | caution | hold | building
    let iv: Double?                // implied vol, % (nil until the IV feed lands)
    let hv30: Double?             // realized vol, %
    let ivr: Double?              // IV rank 0…100
    let iv52Low: Double?
    let iv52High: Double?
    let spread: Double?           // implied − realized, in vol points
    let building: Bool             // true when the IV feed hasn't populated yet
}
struct NvInsights: Sendable {
    let protection: NvProtection
    let vol: NvVol
    let fresh: NvFresh
}

// Section 4 · peers & ETFs
struct NvPeerTape: Identifiable, Sendable {
    let ticker: String
    let last: Double?
    let dayPct: Double?
    let closes: [Double]          // recent session closes, oldest→newest (≤6)
    let windowPct: Double?        // % across the window
    let good: Bool?
    var id: String { ticker }
}
struct NvPeers: Sendable {
    let tapes: [NvPeerTape]
    let fresh: NvFresh
}

// Section 5 · historical performance
struct NvHistBar: Identifiable, Sendable {
    let label: String             // "Jul 24"
    let sharesPL: Double
    let optionsPL: Double
    var total: Double { sharesPL + optionsPL }
    var id: String { label }
}
struct NvHistory: Sendable {
    let bars: [NvHistBar]         // recent sessions, oldest→newest
    let bestDay: Double
    let worstDay: Double
    let net: Double               // sum across the window
    let sessions: Int
    let fresh: NvFresh
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
        // Position delta is share-equivalents: 1 delta per share, plus the option legs.
        let delta = shares + greekSum { $0.delta }
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

        let premLifetime = netPrem("call", "short")
        var openShortPrem = 0.0
        for (k, c) in net where c > 0.0001 && k.kind == "call" && k.side == "short" { openShortPrem += (c / max(c, 1)) * openPrem("call", "short") }
        let realizedShares = sells.filter { $0.voided_at == nil }.reduce(0.0) { $0 + ($1.realized_pl ?? 0) }
        let realizedOptions = premLifetime - openShortPrem
        let realized = realizedOptions + realizedShares
        let perShare = shares > 0 ? premLifetime / shares : 0
        let breakEven = avgBuy - perShare
        let cushion = spot - breakEven

        let csCt = writtenCt("call", "short"), csColl = openPrem("call", "short")
        let cbCt = netOpenCt("call", "long"), cbPaid = openPrem("call", "long")
        let psCt = netOpenCt("put", "short")
        let pbCt = netOpenCt("put", "long"), pbPaid = openPrem("put", "long")
        let sleeves: [NvPerfSleeve] = [
            .init(name: "Calls sold", glyph: "▲", total: csCt, basisLabel: "Collected", basis: csColl,
                  realized: realizedOptions, unrealized: openShortPrem - sleeveMTM("call", "short"), empty: csCt == 0 && csColl == 0),
            .init(name: "Calls bought", glyph: "△", total: cbCt, basisLabel: "Paid", basis: cbPaid,
                  realized: 0, unrealized: sleeveMTM("call", "long") - cbPaid, empty: cbCt == 0),
            .init(name: "Puts sold", glyph: "▼", total: psCt, basisLabel: "Collected", basis: openPrem("put", "short"),
                  realized: 0, unrealized: 0, empty: psCt == 0),
            .init(name: "Puts bought", glyph: "▽", total: pbCt, basisLabel: "Paid", basis: pbPaid,
                  realized: 0, unrealized: sleeveMTM("put", "long") - pbPaid, empty: pbCt == 0),
        ]
        return NvPerf(realized: realized, lifetime: premLifetime, perShare: perShare,
                      perSharePct: avgBuy > 0 ? perShare / avgBuy * 100 : 0, costBasis: avgBuy, breakEven: breakEven,
                      cushion: cushion, cushionPct: breakEven > 0 ? cushion / breakEven * 100 : 0, sleeves: sleeves)
    }

    // MARK: - Section 3 · insights (protection + volatility)

    static func insights(trades: [NvOptionTrade], lots: [NvShareLot], marks: [NvOptionMark],
                         quote: NvQuote?, closes: [NvDailyClose], now: Date = Date()) -> NvInsights {
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
        let hv = realizedVol(nvCloses).map { $0 * 100 }
        let ivs = live.compactMap { markByTrade[$0.id]?.iv }.filter { $0 > 0 }.sorted()
        let iv: Double? = ivs.isEmpty ? nil : ivs[ivs.count / 2] * 100
        let spread: Double? = (iv != nil && hv != nil) ? iv! - hv! : nil
        // No IVR / 52w IV history yet → score can't be computed honestly.
        let vol = NvVol(score: 0, verdict: "building", iv: iv, hv30: hv, ivr: nil,
                        iv52Low: nil, iv52High: nil, spread: spread, building: true)

        return NvInsights(protection: protection, vol: vol, fresh: freshness(quote?.captured_at, now: now).0)
    }

    // MARK: - Section 4 · peers & ETFs (5-session tape)

    static func peers(quotes: [NvQuote], closes: [NvDailyClose], now: Date = Date()) -> NvPeers {
        let order = ["NVDA", "QQQ", "SPY", "SMH", "AVGO", "AMD", "ARM", "INTC"]
        let qByT = Dictionary(quotes.map { ($0.ticker, $0) }, uniquingKeysWith: { a, _ in a })
        var closesByT: [String: [Double]] = [:]
        for c in closes.sorted(by: { $0.date < $1.date }) {
            if let p = c.close_price { closesByT[c.ticker, default: []].append(p) }
        }
        let tapes: [NvPeerTape] = order.map { tk in
            let q = qByT[tk]
            let cs = Array((closesByT[tk] ?? []).suffix(6))
            let win: Double? = (cs.first ?? 0) > 0 && cs.count >= 2 ? (cs.last! / cs.first! - 1) * 100 : nil
            let day = q?.day_change_pct
            return NvPeerTape(ticker: tk, last: q?.spot, dayPct: day, closes: cs, windowPct: win,
                              good: day == nil ? nil : day! >= 0)
        }
        return NvPeers(tapes: tapes, fresh: freshness(qByT["NVDA"]?.captured_at, now: now).0)
    }

    // MARK: - Section 5 · historical performance (per-session, by source)

    static func history(eod: [NvOptionMarkEod], closes: [NvDailyClose], trades: [NvOptionTrade],
                        lots: [NvShareLot], now: Date = Date()) -> NvHistory {
        let shares = lots.filter { $0.voided_at == nil }.reduce(0) { $0 + $1.qty_remaining }
        let live = trades.filter { $0.voided_at == nil }
        let signById = Dictionary(live.map { ($0.id, $0.direction == "short" ? -1.0 : 1.0) }, uniquingKeysWith: { a, _ in a })
        let ctById = Dictionary(live.map { ($0.id, $0.contracts) }, uniquingKeysWith: { a, _ in a })

        let closeByDate = Dictionary(
            closes.filter { $0.ticker == "NVDA" }.compactMap { c in c.close_price.map { (c.date, $0) } },
            uniquingKeysWith: { a, _ in a })
        var marksByDate: [String: [String: Double]] = [:]
        for m in eod { if let mk = m.mark { marksByDate[m.date, default: [:]][m.option_trade_id] = mk } }

        let dates = Array(Set(closeByDate.keys).union(marksByDate.keys)).sorted()
        var bars: [NvHistBar] = []
        var prevClose: Double?
        var prevMarks: [String: Double] = [:]
        for d in dates {
            var sharesPL = 0.0
            if let c = closeByDate[d] { if let p = prevClose { sharesPL = (c - p) * shares }; prevClose = c }
            var optPL = 0.0
            if let m = marksByDate[d] {
                for (id, mk) in m {
                    if let pm = prevMarks[id] {
                        optPL += (mk - pm) * (ctById[id] ?? 1) * 100 * (signById[id] ?? 1)
                    }
                    prevMarks[id] = mk
                }
            }
            bars.append(NvHistBar(label: shortDate(d), sharesPL: sharesPL, optionsPL: optPL))
        }
        // drop the leading reference-only session(s) that have no prior to diff against
        let trimmed = Array(bars.drop(while: { $0.sharesPL == 0 && $0.optionsPL == 0 }))
        let recent = Array(trimmed.suffix(12))
        let totals = recent.map { $0.total }
        return NvHistory(bars: recent, bestDay: totals.max() ?? 0, worstDay: totals.min() ?? 0,
                         net: totals.reduce(0, +), sessions: recent.count, fresh: recent.isEmpty ? .stale : .delayed)
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
