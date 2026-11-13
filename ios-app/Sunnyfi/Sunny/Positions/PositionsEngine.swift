//
//  PositionsEngine.swift
//  Sunny
//
//  The Positions engine on the phone (handoff 2026-11-13-positions, README §3; App Explorations 154a).
//
//  ⚠ PORTED LINE FOR LINE FROM supabase/functions/_shared/positions-engine.ts (with sd-engine.ts N, fk and cover),
//  the one calculation block the web Positions page runs, so the phone says the same numbers. Change it there first,
//  then here, then run the harness (scratchpad pos/harness: the TS and this file on the same saved inputs).
//  Checked 13 Nov 2026 on the live S and N books: Sold in SD, the Held lanes, touched and closed, Move, IV tone,
//  the read, the price scale, the cover check and the trading days all match the TS.
//
//  Pure functions, Foundation only (no SwiftUI, no clock), so swiftc can run it beside the TS. Dates are ISO days
//  ("2026-11-13"). No em dashes in any words here (Nik).
//

import Foundation

nonisolated enum PE {

    // MARK: Notation (README §3)

    /// The design's normal CDF (Abramowitz-Stegun 26.2.17), sd-engine.ts N.
    static func N(_ x: Double) -> Double {
        let t = 1 / (1 + 0.2316419 * abs(x)), d = 0.3989422804014327 * exp(-x * x / 2)
        let q = d * t * (0.31938153 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))))
        return x > 0 ? 1 - q : q
    }

    /// JS `Math.round`: halves go up (toward +∞), never away from zero.
    static func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

    /// JS `String(n)` for a number that came from `+x.toFixed(d)`: no trailing zeros, no trailing dot.
    static func num(_ x: Double, _ d: Int = 2) -> String {
        var s = String(format: "%.\(d)f", x)
        if s.contains(".") { while s.hasSuffix("0") { s.removeLast() }; if s.hasSuffix(".") { s.removeLast() } }
        return s == "-0" ? "0" : s
    }

    /// JS `String(n)`: integers without a decimal point, other numbers in their shortest form.
    static func jsNum(_ x: Double) -> String { x == x.rounded() && abs(x) < 1e15 ? String(Int(x)) : "\(x)" }

    /// A strike as the design writes it (sd-engine fk): "40", "42.5", "40.85".
    static func fk(_ x: Double) -> String {
        if x.truncatingRemainder(dividingBy: 1) == 0 { return x == x.rounded() && abs(x) < 1e15 ? String(Int(x)) : String(x) }
        return Int(jsRound(x * 100)) % 10 != 0 ? String(format: "%.2f", x) : String(format: "%.1f", x)
    }

    /// One SD as a log move: IV × √(td ÷ 252).
    static func sdMove(_ iv: Double, _ td: Double) -> Double { iv > 0 && td > 0 ? iv * (td / 252).squareRoot() : 0 }
    /// The price k SD from S0 (k < 0 below).
    static func atSd(_ S0: Double, _ k: Double, _ m: Double) -> Double { S0 * exp(k * m) }
    /// How many SD a price is from S0 (signed; 0 when m is 0).
    static func zOf(_ x: Double, _ S0: Double, _ m: Double) -> Double { m > 0 && x > 0 && S0 > 0 ? log(x / S0) / m : 0 }
    /// $2.80 (a price, two decimals, no sign).
    static func f2(_ x: Double) -> String { "$" + String(format: "%.2f", abs(x)) }
    /// 2.7% from a fraction: one decimal, two under 0.1%, no sign.
    static func pcx(_ x: Double) -> String {
        let a = abs(x) * 100
        return (a > 0 && a < 0.1 ? String(format: "%.2f", a) : String(format: "%.1f", a)) + "%"
    }
    /// ↑2.7% or ↓2.7% from a fraction (never a minus sign).
    static func arrowPct(_ x: Double) -> String { (x >= 0 ? "↑" : "↓") + pcx(x) }
    /// An SD level with the fewest digits: 0.25, 0.5, 1, 1.25 (README §5).
    static func sdK(_ k: Double) -> String { num(k, 2) }

    /// Black-Scholes with no rates or dividends (README §3), T in years = cd ÷ 365. p value a share, d delta, g gamma,
    /// t theta a calendar day, vg vega a vol point. At or past expiry: intrinsic, delta 0 or ±1.
    struct BS { let p: Double; let d: Double; let g: Double; let t: Double; let vg: Double }
    static func bs(put: Bool, S: Double, K: Double, T: Double, iv: Double) -> BS {
        if !(T > 1e-6) || !(iv > 0) {
            return BS(p: max(0, put ? K - S : S - K), d: put ? (S < K ? -1 : 0) : (S > K ? 1 : 0), g: 0, t: 0, vg: 0)
        }
        let sq = iv * T.squareRoot(), d1 = (log(S / K) + 0.5 * iv * iv * T) / sq, d2 = d1 - sq
        let n1 = exp(-d1 * d1 / 2) / (2 * Double.pi).squareRoot()
        return BS(p: put ? K * N(-d2) - S * N(-d1) : S * N(d1) - K * N(d2),
                  d: put ? N(d1) - 1 : N(d1),
                  g: n1 / (S * sq),
                  t: -S * n1 * iv / (2 * T.squareRoot()) / 365,
                  vg: S * n1 * T.squareRoot() / 100)
    }

    // MARK: The SD ramp (README §4)

    /// The SD levels the lanes draw, nearest first; the view holds the six ramp colours in the same order.
    static let LV: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2]
    /// The index of the ramp level nearest |k| (positions-engine sdColour).
    static func sdLevel(_ k: Double) -> Int {
        let a = abs(k)
        var bi = 0
        for (i, v) in LV.enumerated() where abs(v - a) < abs(LV[bi] - a) { bi = i }
        return bi
    }

    // MARK: Days

    /// Days since 1970-01-01 for an ISO day (proleptic Gregorian), and back.
    static func dayNum(_ iso: String) -> Int? {
        let p = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        var y = p[0]; let m = p[1], d = p[2]
        y -= m <= 2 ? 1 : 0
        let era = (y >= 0 ? y : y - 399) / 400, yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }
    static func isoOf(_ n: Int) -> String {
        let z = n + 719468, era = (z >= 0 ? z : z - 146096) / 146097, doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365, doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153, d = doy - (153 * mp + 2) / 5 + 1, m = mp + (mp < 10 ? 3 : -9)
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
    static func addDays(_ iso: String, _ n: Int) -> String { dayNum(iso).map { isoOf($0 + n) } ?? iso }
    /// 0 Sunday ... 6 Saturday (JS getUTCDay).
    static func weekday(_ iso: String) -> Int { dayNum(iso).map { (($0 % 7) + 11) % 7 } ?? 0 }

    /// Trading days after `today` through `ex` (weekends and `closed` days left out). On the expiry day, the share of the
    /// session left (at least a quarter hour), so an expiring leg still has an SD. `mins`: New York minutes now.
    static func tradingDays(_ today: String, _ ex: String, closed: Set<String>, mins: Double) -> Double {
        guard let a = dayNum(today), let b = dayNum(ex) else { return 0 }
        var n = 0.0
        if b > a { for k in (a + 1)...b { let s = isoOf(k), w = weekday(s); if w != 0 && w != 6 && !closed.contains(s) { n += 1 } } }
        return n > 0 ? n : ex == today ? max(0.25, (16 * 60 - mins) / 60) / 6.5 : 0
    }

    // MARK: §3.3 Sold, in SD

    /// One sold option leg, as the book holds it. `entry` is the premium a share it was sold at, `mark` today's mark,
    /// `iv` the IV it is priced on (the leg's own), `td`/`cd` trading and calendar days to its expiry, `z0` the signed SD
    /// it sat at when sold (saved at the fill; nil when not saved: no hollow dot, never back-solved).
    struct SoldIn {
        var t: String; var S: Double; var put: Bool; var K: Double; var n: Double; var ex: String; var exLabel: String
        var entry: Double?; var mark: Double?; var iv: Double; var td: Double; var cd: Double; var z0: Double? = nil
    }
    enum Tone: String { case red, orange, quiet }
    struct SoldRow: Identifiable {
        let l: SoldIn
        var id: String { key }
        let key: String
        /// SD now, signed (puts below today read negative), and its size.
        let z: Double, a: Double
        let itm: Bool
        /// The size of the SD when sold, and whether the price came closer since (nil: not saved).
        let a0: Double?, closer: Bool?
        /// |N(d1)| for calls, |N(d1) − 1| for puts.
        let delta: Double
        /// Kept = 1 − mark ÷ entry (negative: lost). Nil without an entry or a mark.
        let kept: Double?
        /// The per-share breakeven with the whole premium for this name and expiry on this leg, its SD, whether the
        /// price is already past it.
        let be: Double?, zb: Double?, past: Bool
        /// Shown only under 0.5 SD or in the money.
        let showBE: Bool
        let tone: Tone
        /// Sort key: in the money first (-1), then SD now, nearest first.
        let rank: Double
        /// Where to draw on the track, 0 to 1 (2.2 SD each side of today; pinned at the edges).
        let x: Double, xb: Double?, x0: Double?
    }

    /// The track's half width in SD.
    static let TRACK_SD = 2.2
    /// A signed SD on the track, 0 to 1, pinned at ±2.2 SD.
    static func trackX(_ z: Double) -> Double { 0.5 + max(-TRACK_SD, min(TRACK_SD, z)) / TRACK_SD / 2 }
    /// Red under 0.5 SD, orange 0.5 to 1 SD, quiet past 1 SD; in the money red (filled).
    static func toneOf(_ a: Double, _ itm: Bool) -> Tone { itm || a < 0.5 ? .red : a < 1 ? .orange : .quiet }

    /// Every sold leg on one SD axis, one row per leg (never added across strikes), in the money first, then SD now,
    /// nearest first.
    static func soldInSd(_ legs: [SoldIn]) -> (rows: [SoldRow], within: Int, inTheMoney: Int) {
        var tot: [String: Double] = [:]
        for l in legs { if let e = l.entry { tot[l.t + "|" + l.ex, default: 0] += l.n * 100 * e } }
        let rows: [SoldRow] = legs.filter { $0.S > 0 && $0.K > 0 && $0.n > 0 }.map { l in
            let m = sdMove(l.iv, l.td), z = zOf(l.K, l.S, m), a = abs(z)
            let itm = l.put ? l.S < l.K : l.S > l.K
            let delta = abs(bs(put: l.put, S: l.S, K: l.K, T: l.cd / 365, iv: l.iv).d)
            let all = tot[l.t + "|" + l.ex]
            let be: Double? = all != nil && l.entry != nil ? (l.put ? l.K - all! / (l.n * 100) : l.K + all! / (l.n * 100)) : nil
            let zb: Double? = be.flatMap { $0 > 0 ? zOf($0, l.S, m) : nil }
            let past = be.map { l.put ? l.S <= $0 : l.S >= $0 } ?? false
            let z0 = l.z0.flatMap { $0.isFinite ? $0 : nil }
            let a0 = z0.map(abs)
            let out = { (zz: Double) in l.put ? -zz : zz }
            let kept: Double? = l.entry != nil && l.entry! > 0 && l.mark != nil ? 1 - l.mark! / l.entry! : nil
            return SoldRow(l: l, key: "\(l.t)|\(l.put ? "p" : "c")|\(jsNum(l.K))|\(l.ex)", z: z, a: a, itm: itm,
                           a0: a0, closer: z0.map { out(z) < out($0) - 0.005 }, delta: delta, kept: kept, be: be, zb: zb, past: past,
                           showBE: be != nil && (itm || a < 0.5), tone: toneOf(a, itm), rank: itm ? -1 : a,
                           x: trackX(z), xb: zb.map(trackX), x0: z0.map(trackX))
        }
        // Stable, as JS sort is: rank, then the ticker, then the order given.
        let sorted = rows.enumerated().sorted { p, q in
            if p.element.rank != q.element.rank { return p.element.rank < q.element.rank }
            if p.element.l.t != q.element.l.t { return p.element.l.t < q.element.l.t }
            return p.offset < q.offset
        }.map(\.element)
        return (sorted, sorted.filter { !$0.itm && $0.a < 0.5 }.count, sorted.filter(\.itm).count)
    }

    /// The name strip's dot (A7): red when the name is short at the priced move by Friday (Home's brief.names st = 2),
    /// orange when one of its sold legs is in the money or within 0.5 SD, else none.
    static func nameDot(_ st: Int?, _ rows: [SoldRow], _ t: String) -> Tone? {
        if st == 2 { return .red }
        return rows.contains { $0.l.t == t && ($0.itm || $0.a < 0.5) } ? .orange : nil
    }

    // MARK: §3.9.5 The lanes' maths: Held

    /// A short option at the chosen expiry: contracts and the premium a share.
    struct ShortLeg: Equatable { let put: Bool; let K: Double; let n: Double; let p: Double }

    /// P&L at expiry for a set of short legs: Σ n × 100 × (premium − intrinsic).
    static func plAtExpiry(_ set: [ShortLeg], _ x: Double) -> Double {
        set.reduce(0) { $0 + $1.n * 100 * ($1.p - max(0, $1.put ? $1.K - x : x - $1.K)) }
    }

    struct BE: Equatable { let dn: Double?; let up: Double?; let none: Bool }
    /// The breakevens (the 13 Nov audit's zone rule): the P&L on S0 × e^(z·m), z from −4 to 4 (801 points); the
    /// stretches where the set makes money; the one that holds S0, or the nearest one when the price is outside it.
    /// dn/up nil = past 4 SD on that side; none = the set never makes money.
    static func breakevens(_ set: [ShortLeg], _ S0: Double, _ m: Double) -> BE {
        if set.isEmpty || !(m > 0) || !(S0 > 0) { return BE(dn: nil, up: nil, none: true) }
        let GX = (0...800).map { S0 * exp((-4 + (8 * Double($0)) / 800) * m) }, ys = GX.map { plAtExpiry(set, $0) }
        let cx = { (i: Int) in GX[i - 1] + (GX[i] - GX[i - 1]) * ys[i - 1] / (ys[i - 1] - ys[i]) }
        var iv: [(Double?, Double?)] = []
        var lo: Double? = nil
        for i in 0..<GX.count {
            let p = ys[i] > 0, q = i > 0 && ys[i - 1] > 0
            if p && !q { lo = i == 0 ? nil : cx(i) }
            if !p && q { iv.append((lo, cx(i))) }
        }
        if ys[GX.count - 1] > 0 { iv.append((lo, nil)) }
        if iv.isEmpty { return BE(dn: nil, up: nil, none: true) }
        let dz = { (c: (Double?, Double?)) -> Double in
            let (a, b) = c
            if (a == nil || a! <= S0) && (b == nil || b! >= S0) { return 0 }
            return min(a == nil ? .infinity : abs(a! - S0), b == nil ? .infinity : abs(b! - S0))
        }
        // reduce((p, c) => dz(c) < dz(p) ? c : p): the first of the nearest.
        var best = iv[0]
        for c in iv.dropFirst() where dz(c) < dz(best) { best = c }
        return BE(dn: best.0, up: best.1, none: false)
    }

    /// Chance of profit = N(z(up)) − N(z(dn)), lognormal with no drift; z = ±9 for a side with no breakeven, 0 when
    /// nothing makes money.
    static func chanceOfProfit(_ r: BE, _ S0: Double, _ m: Double) -> Double {
        if r.none { return 0 }
        return N(r.up == nil ? 9 : zOf(r.up!, S0, m)) - N(r.dn == nil ? -9 : zOf(r.dn!, S0, m))
    }

    struct Lane: Equatable {
        let has: Bool
        /// The breakevens of the whole set (the cross when both sides are in it).
        let dn: Double?, up: Double?, none: Bool
        /// Chance of profit, 0 to 1.
        let cp: Double
        /// The premium in, $.
        let inc: Double
        let calls: Double, puts: Double
        /// Each side alone (only when the set has both sides): calls' breakeven up, puts' breakeven down.
        let callsAlone: Double?, putsAlone: Double?
        /// The strikes, for the rings.
        let strikes: [Double]
        static let empty = Lane(has: false, dn: nil, up: nil, none: true, cp: 0, inc: 0, calls: 0, puts: 0, callsAlone: nil, putsAlone: nil, strikes: [])
    }
    static func lane(_ set: [ShortLeg], _ S0: Double, _ m: Double) -> Lane {
        if set.isEmpty { return .empty }
        let r = breakevens(set, S0, m), cs = set.filter { !$0.put }, ps = set.filter(\.put), both = !cs.isEmpty && !ps.isEmpty
        var ks: [Double] = []
        for l in set where !ks.contains(l.K) { ks.append(l.K) }
        return Lane(has: true, dn: r.dn, up: r.up, none: r.none, cp: chanceOfProfit(r, S0, m),
                    inc: set.reduce(0) { $0 + $1.n * 100 * $1.p },
                    calls: cs.reduce(0) { $0 + $1.n }, puts: ps.reduce(0) { $0 + $1.n },
                    callsAlone: both ? breakevens(cs, S0, m).up : nil, putsAlone: both ? breakevens(ps, S0, m).dn : nil,
                    strikes: ks)
    }
    /// The cross adds |z(cross)| − |z(alone)| in SD.
    static func crossAdds(_ cross: Double, _ alone: Double, _ S0: Double, _ m: Double) -> Double {
        abs(zOf(cross, S0, m)) - abs(zOf(alone, S0, m))
    }

    // MARK: §3.9.3 Touched and closed through

    /// Today's session (the server's `day`): the prior close, today's high and low, the last price, and the official
    /// close once confirmed after 4:00 PM ET.
    struct Day: Equatable { let prev: Double; let high: Double; let low: Double; let last: Double; let closedToday: Bool; let close: Double? }
    enum LevelState: String { case idle, touch, up, dn }
    /// Idle, touched today (today's high or low reached it), or closed through (the prior close and the official close
    /// sit on opposite sides). An intraday cross stays "touched" until the close. No session: idle.
    static func levelState(_ L: Double?, _ day: Day?) -> LevelState {
        guard let L, L.isFinite, let day else { return .idle }
        if day.closedToday, let c = day.close, (day.prev - L) * (c - L) < 0 { return c > L ? .up : .dn }
        return L >= min(day.low, day.high) && L <= max(day.low, day.high) ? .touch : .idle
    }

    // MARK: Move: last week, this week, the pace

    struct Close: Equatable { let d: String; let c: Double }
    /// The Monday of the week `today` falls in (Saturday and Sunday belong to the week just ended).
    static func mondayOf(_ today: String) -> String { let w = weekday(today); return addDays(today, w == 0 ? -6 : 1 - w) }

    struct Move: Equatable {
        struct LW: Equatable { let from: Double; let to: Double; let fromD: String; let toD: String; let r: Double; let lo: Double; let hi: Double }
        struct TW: Equatable { let from: Double; let r: Double; let sd: Double }
        struct Pace: Equatable { let r5: Double; let r20: Double?; let flat: Bool; let to: Double; let capped: Bool }
        /// Last week: Friday's close to Friday's close, the range of closes behind it.
        let lw: LW?
        /// This week so far: last Friday's close to now, and that move in weekly SD.
        let tw: TW?
        /// The 5-day pace carried to the expiry: S0 × (1 + r5 ÷ 5 × td), held inside ±1.5 SD. Flat under 0.5%.
        let pace: Pace?
    }
    /// `closes`: daily closes (any order); only sessions before `today` count, S0 is today's price.
    static func moveOf(_ closes: [Close], _ S0: Double, _ today: String, _ iv: Double, _ td: Double, _ m: Double) -> Move {
        let P = closes.filter { $0.d < today && $0.c > 0 }.enumerated().sorted { $0.element.d != $1.element.d ? $0.element.d < $1.element.d : $0.offset < $1.offset }.map(\.element)
        if P.isEmpty || !(S0 > 0) { return Move(lw: nil, tw: nil, pace: nil) }
        let mon = mondayOf(today), lastBefore = { (d: String) in P.last { $0.d < d } }
        let w1 = lastBefore(mon), w0 = w1 != nil ? lastBefore(addDays(mon, -7)) : nil
        let wk = w0 != nil && w1 != nil ? P.filter { $0.d >= w0!.d && $0.d <= w1!.d }.map(\.c) : []
        let wsd = iv > 0 ? iv * (5.0 / 252).squareRoot() : 0
        let lw: Move.LW? = w0 != nil && w1 != nil
            ? .init(from: w0!.c, to: w1!.c, fromD: w0!.d, toD: w1!.d, r: w1!.c / w0!.c - 1, lo: wk.min() ?? .infinity, hi: wk.max() ?? -.infinity) : nil
        let tw: Move.TW? = w1.map { .init(from: $0.c, r: S0 / $0.c - 1, sd: wsd > 0 ? abs(log(S0 / $0.c)) / wsd : 0) }
        var pace: Move.Pace? = nil
        if P.count >= 5 {
            let r5 = S0 / P[P.count - 5].c - 1, r20: Double? = P.count >= 20 ? S0 / P[P.count - 20].c - 1 : nil
            let pj0 = S0 * (1 + (r5 / 5) * td), lo = atSd(S0, -1.5, m), hi = atSd(S0, 1.5, m)
            let to = m > 0 ? max(lo, min(hi, pj0)) : pj0
            pace = .init(r5: r5, r20: r20, flat: abs(r5) < 0.005, to: to, capped: abs(to - pj0) > 0.005)
        }
        return Move(lw: lw, tw: tw, pace: pace)
    }

    // MARK: IV: rank and the tone

    enum IVTone: String { case rich, cheap, fair }
    struct IVRead: Equatable { let rank: Double?; let ratio: Double?; let tone: IVTone? }
    /// IV rank = (IV − 52-week low) ÷ (high − low) × 100, else the server's rank. Rich if rank ≥ 70 or IV ≥ 1.3 × HV20;
    /// cheap if rank ≤ 20 or IV ≤ HV20; else fair. Nil without the history.
    static func ivTone(_ iv: Double, low52: Double?, high52: Double?, rank r0: Double?, hv20: Double?, has: Bool = true) -> IVRead {
        guard has else { return IVRead(rank: nil, ratio: nil, tone: nil) }
        let rank: Double? = low52 != nil && high52 != nil && high52! > low52!
            ? max(0, min(100, jsRound(((iv - low52!) / (high52! - low52!)) * 100))) : r0.map(jsRound)
        let ratio: Double? = hv20.flatMap { $0 > 0 ? iv / $0 : nil }
        if rank == nil && ratio == nil { return IVRead(rank: rank, ratio: ratio, tone: nil) }
        let rich = (rank.map { $0 >= 70 } ?? false) || (ratio.map { $0 >= 1.3 } ?? false)
        let cheap = !rich && ((rank.map { $0 <= 20 } ?? false) || (ratio.map { $0 <= 1 } ?? false))
        return IVRead(rank: rank, ratio: ratio, tone: rich ? .rich : cheap ? .cheap : .fair)
    }

    // MARK: A6 Cover check (sd-engine cover())

    struct Cover: Equatable { let sold: Double; let open: Double; let sale: Double; let byShares: Double; let byOtm: Double; let uncovered: Double; let capShares: Double; let capOtm: Double }
    /// Calls sold = calls still open at this expiry and later + the new sale; covered = ⌊shares ÷ 100⌋ first, then OTM
    /// calls bought that end on or after each sold call (LEAPS never count).
    static func coverCheck(shares: Double, held: [(K: Double, n: Double, ex: String)], otm: [(n: Double, ex: String)], sale: (K: Double, n: Double)?, ex: String) -> Cover {
        let open = held.filter { $0.ex >= ex }
        var sold = open.map { (n: $0.n, ex: $0.ex) }
        if let s = sale, s.n > 0 { sold.append((n: s.n, ex: ex)) }
        sold = sold.enumerated().sorted { $0.element.ex != $1.element.ex ? $0.element.ex < $1.element.ex : $0.offset < $1.offset }.map(\.element)
        // sd-engine cover(): the shares first, then the OTM calls that last to each sold call.
        var sh = (shares / 100).rounded(.down), covered = 0.0, capped = 0.0, naked = 0.0
        var used = otm.map { _ in 0.0 }
        for s in sold {
            var left = s.n
            let a = min(left, sh); covered += a; sh -= a; left -= a
            for (i, l) in otm.enumerated() where l.ex >= s.ex {
                let b = min(left, l.n - used[i])
                if b > 0 { used[i] += b; capped += b; left -= b }
            }
            naked += left
        }
        return Cover(sold: sold.reduce(0) { $0 + $1.n }, open: open.reduce(0) { $0 + $1.n }, sale: sale?.n ?? 0, byShares: covered, byOtm: capped,
                     uncovered: naked, capShares: (shares / 100).rounded(.down), capOtm: otm.filter { $0.ex >= ex }.reduce(0) { $0 + $1.n })
    }

    // MARK: §3.9.4 The read

    struct Levels: Equatable {
        var ceiling: Double? = nil, floor: Double? = nil, accelerator: Double? = nil
        var resistance: Double? = nil, support: Double? = nil
        var sma20: Double? = nil, sma50: Double? = nil, sma100: Double? = nil, sma200: Double? = nil
    }
    struct ReadSide: Equatable { let K: Double; let k: Double }
    struct ReadIn {
        let S0: Double
        /// The chain's strike step (half a step, or 0.6% of S0, is "on" a strike).
        let step: Double
        /// The sale's sides (phone: what is sold). Nil leaves that side out.
        let call: ReadSide?, put: ReadSide?
        let levels: Levels
        /// Calls left uncovered after the sale, and the calls in the sale (the lead counts only a new call sale).
        let uncovered: Double, newCalls: Double
        let earnings: Bool, dividend: Bool
        /// Where the 5-day pace lands by the expiry (nil when flat or unknown).
        let pace: Double?
        /// The chance of profit, 0 to 1 (nil leaves the odds out).
        let odds: Double?
        let tone: IVTone?
    }
    /// The read never passes 150 characters (README §8).
    static let READ_MAX = 150
    private static func anA(_ n: Int) -> String {
        let s = String(n)
        return s == "8" || s == "11" || s == "18" || (s.count == 2 && s.hasPrefix("8")) ? "an" : "a"
    }
    /// The read: one lead, one line on both strikes, the odds, the premiums if there is room; 150 characters at most.
    static func theRead(_ x: ReadIn) -> (lead: String, rest: String) {
        let S0 = x.S0, call = x.call, put = x.put, L = x.levels, tol = max(x.step * 0.5, S0 * 0.006)
        let ok = { (v: Double?) -> Bool in v != nil && v!.isFinite && v! > 0 }
        let MA: [(String, Double?)] = [("the 20-day", L.sma20), ("the 50-day", L.sma50), ("the 100-day", L.sma100), ("the 200-day", L.sma200)]
        let CM = ([("the ceiling", L.ceiling), ("resistance", L.resistance)] + MA).filter { ok($0.1) }.map { ($0.0, $0.1!) }
        let PM = ([("the floor", L.floor), ("support", L.support)] + MA).filter { ok($0.1) }.map { ($0.0, $0.1!) }
        let Kc = call?.K, Kp = put?.K
        let cItm = Kc != nil && S0 > Kc!, pItm = Kp != nil && S0 < Kp!
        let byUp = { (a: [(String, Double)]) in a.enumerated().sorted { $0.element.1 != $1.element.1 ? $0.element.1 < $1.element.1 : $0.offset < $1.offset }.map(\.element) }
        let byDn = { (a: [(String, Double)]) in a.enumerated().sorted { $0.element.1 != $1.element.1 ? $0.element.1 > $1.element.1 : $0.offset < $1.offset }.map(\.element) }
        let cOn = Kc == nil ? [] : CM.filter { abs($0.1 - Kc!) <= tol }
        let cIn = Kc == nil ? [] : byUp(CM.filter { $0.1 > S0 && $0.1 < Kc! - tol })
        let pOn = Kp == nil ? [] : PM.filter { abs($0.1 - Kp!) <= tol }
        let pIn = Kp == nil ? [] : byDn(PM.filter { $0.1 < S0 && $0.1 > Kp! + tol })
        let A: Double? = ok(L.accelerator) ? L.accelerator : nil
        let accIn = A != nil && Kp != nil && A! < S0 && A! >= Kp! - tol, accNear = accIn && abs(A! - Kp!) <= x.step * 2
        let cM = cOn.first ?? cIn.first, pM = pOn.first ?? pIn.first
        let mvC = x.pace != nil && Kc != nil && x.pace! >= Kc! - tol, mvP = x.pace != nil && Kp != nil && x.pace! <= Kp! + tol
        let lead: String
        if x.uncovered > 0 && x.newCalls > 0 { let u = Int(x.uncovered); lead = "\(u) \(u == 1 ? "call" : "calls") would be uncovered." }
        else if cItm { lead = "Your call is in the money." }
        else if pItm { lead = "Your put is in the money." }
        else if x.earnings { lead = "Earnings land before expiry." }
        else if x.dividend { lead = "The dividend lands before expiry." }
        else if accNear { lead = "A drop could speed up." }
        else if mvC { lead = "Running toward your call." }
        else if mvP { lead = "Sliding toward your put." }
        else if call != nil && cM == nil { lead = "The call has no cushion." }
        else if put != nil && pM == nil { lead = "The put has no cushion." }
        else { lead = call != nil && put != nil ? "Both strikes look covered." : call != nil ? "The call looks covered." : "The put looks covered." }
        let lvl = { (v: Double) in fk(Double(num(v, 2)) ?? v) }
        let cP: String = Kc == nil ? "" : cItm ? "The price is \(f2(S0 - Kc!)) past call \(fk(Kc!))" : !cOn.isEmpty ? "Call \(fk(Kc!)) sits on \(cM!.0)"
            : !cIn.isEmpty ? "Call \(fk(Kc!)) has \(cM!.0) at \(lvl(cM!.1)) in front" : "Nothing caps call \(fk(Kc!))"
        let pP: String = Kp == nil ? "" : pItm ? "the price is \(f2(Kp! - S0)) under put \(fk(Kp!))" : accNear ? "put \(fk(Kp!)) sits by a fast drop at \(fk(A!))"
            : !pOn.isEmpty ? "put \(fk(Kp!)) sits on \(pM!.0)" : !pIn.isEmpty ? "put \(fk(Kp!)) has \(pM!.0) at \(lvl(pM!.1)) in front" : "nothing holds a fall to put \(fk(Kp!))"
        let s1 = cP.isEmpty && pP.isEmpty ? "" : (pP.isEmpty ? cP : cP.isEmpty ? pP.prefix(1).uppercased() + pP.dropFirst() : cP + "; " + pP) + "."
        let sdP: String = call != nil && put != nil ? (call!.k == put!.k ? "\(sdK(call!.k)) SD" : "\(sdK(call!.k)) and \(sdK(put!.k)) SD")
            : call != nil ? "\(sdK(call!.k)) SD" : put != nil ? "\(sdK(put!.k)) SD" : ""
        let cpN: Int? = x.odds.map { Int(jsRound($0 * 100)) }
        let s2: String = cpN == nil ? "" : cItm || pItm ? "\(anA(cpN!) == "an" ? "An" : "A") \(cpN!)% chance you still finish ahead." : "At \(sdP), \(anA(cpN!)) \(cpN!)% chance you finish ahead."
        let s3 = x.earnings ? "Premiums are up for the report." : x.tone == .rich ? "Premiums are high." : x.tone == .cheap ? "Premiums are low." : ""
        var rest = ""
        for s in [s1, s2, s3] where !s.isEmpty {
            let nx = rest.isEmpty ? s : rest + " " + s
            if (lead + " " + nx).utf16.count <= READ_MAX { rest = nx }
        }
        return (lead, rest)
    }

    // MARK: One price scale for the lanes

    struct Scale { let X0: Double; let W: Double; let ticks: [Double]; func fr(_ x: Double) -> Double { (x - X0) / W } }
    /// The lanes' scale: ±2 SD at least, and every level given (each held to ±3.5 SD so one far average does not squash
    /// the rest), 5% padding. fr(x) is 0 to 1 across it; ticks every $1, $2, $5, $10 or $20 by its width.
    static func priceScale(_ S0: Double, _ m: Double, _ levels: [Double?]) -> Scale {
        let lim = { (v: Double) in max(atSd(S0, -3.5, m), min(atSd(S0, 3.5, m), v)) }
        let pts = [atSd(S0, -2, m), atSd(S0, 2, m)] + levels.compactMap { $0 }.filter { $0.isFinite && $0 > 0 }.map(lim)
        let lo = pts.min()!, hi = pts.max()!, pd0 = (hi - lo) * 0.05, pd = pd0 != 0 ? pd0 : S0 * 0.05
        let X0 = lo - pd, W = hi - lo + 2 * pd
        let stp: Double = W <= 7 ? 1 : W <= 14 ? 2 : W <= 35 ? 5 : W <= 70 ? 10 : 20
        var ticks: [Double] = []
        var v = (X0 / stp).rounded(.up) * stp
        while v <= X0 + W + 1e-9 { ticks.append(Double(num(v, 2)) ?? v); v += stp }
        return Scale(X0: X0, W: W, ticks: ticks)
    }

    /// The strike step the design uses when the chain's own is not to hand: $0.50 under $50, $1 under $200, else $5.
    static func stepOf(_ S0: Double) -> Double { S0 < 50 ? 0.5 : S0 < 200 ? 1 : 5 }
    /// Weekly, monthly (the third Friday, or the Thursday before it on a holiday) or earnings, for the expiry line.
    static func expiryKind(_ ex: String, earnings: Bool) -> String {
        if earnings { return "earnings" }
        let wd = weekday(ex), dd = Int(ex.suffix(2)) ?? 0
        return (wd == 5 && dd >= 15 && dd <= 21) || (wd == 4 && dd >= 14 && dd <= 20) ? "monthly" : "weekly"
    }
    /// D1: Intelligence opens on this Friday's expiry, or the first one after it. From the Friday itself it opens on
    /// the next Friday's (Nik, 13 Nov 2026: on the day it expires, "this week" is hours long).
    static func openExpiry(_ exps: [String], friday: String, today: String = "") -> String? {
        var f = friday
        if !today.isEmpty, !friday.isEmpty, friday <= today {
            let fm = DateFormatter(); fm.dateFormat = "yyyy-MM-dd"; fm.timeZone = TimeZone(identifier: "UTC")
            if let d = fm.date(from: friday) { f = fm.string(from: d.addingTimeInterval(7 * 86400)) }
        }
        return exps.first { $0 == f } ?? exps.first { $0 >= f } ?? exps.first
    }
}
