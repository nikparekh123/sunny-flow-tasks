//
//  PlannerMath.swift
//  Sunny
//
//  Block 14b, the Planner: what to sell by next Friday on one name. Every
//  rule here follows reference/SunnyPlanner.dc.html (handoff 23); where the
//  app's data differs from the prototype's sample book it says so.
//
//  · The starting plan is the engine's pick (the roll sheet, sunny-home's
//    writes rows), not the prototype's 0.6 / 1 SD split (Nik, 14 Oct 2026).
//  · Calls are capped at the LEAPs held, puts at the puts bought, less what
//    is already sold for that Friday (Nik, 14 Oct 2026: "All puts bought").
//  · Prices, deltas and the 1 SD move come from the live chain (chain-next,
//    one name, one Friday, every 15 s). The chain's IV already carries an
//    earnings report, so the prototype's extra 1.5x is not applied.
//

import Foundation
import CoreGraphics

/// One planned strike.
struct PlanLeg: Identifiable, Hashable {
    enum Side: String, Hashable { case c, p }
    let id: Int
    var side: Side
    var k: Double
    var q: Int
    var call: Bool { side == .c }
}

/// chain-next's Planner read: every listed strike out to about 2 SD on both
/// sides, with the live mid and its delta (puts negative).
struct PlannerChain: Decodable, Equatable {
    struct Row: Decodable, Equatable { let k: Double; let mid: Double; let dl: Double? }
    let ok: Bool
    let spot: Double?
    let iv: Double?
    let sd: Double?
    let calls: [Row]?
    let puts: [Row]?
}

/// One name as the Planner sees it: what is held and sold for the Friday,
/// the engine's pick, and the live chain once it has come in.
struct PlannerBook {
    let t: String
    let px: Double
    let expiry: String
    let leaps: Int
    let putsHeld: Int
    let cs: Int                         // calls already sold for that Friday
    let ps: Int                         // puts already sold for that Friday
    let sold: [(call: Bool, k: Double, q: Int)]
    let engine: [PlanLeg]
    let deltaNow: Double
    let earnDate: String?               // the next report, any date
    let earnIn: Bool                    // it falls before the expiry closes
    let sd: Double                      // 1 SD by the expiry, in dollars
    let chain: PlannerChain?
    /// Eight stops a side, ATM to 1.4 SD, on listed strikes. Empty until the
    /// live chain is in (the sliders wait for it; nothing is made up).
    let stops: [PlanLeg.Side: [Double]]
    private let prices: [String: (mid: Double, dl: Double?)]

    static let SD: [Double] = [0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4]

    var cap: (c: Int, p: Int) { (max(0, leaps - cs), max(0, putsHeld - ps)) }
    var fullySold: Bool { cap.c + cap.p == 0 }
    var live: Bool { !(stops[.c] ?? []).isEmpty || !(stops[.p] ?? []).isEmpty }

    init(name n: Writes.Name, px: Double, chain: PlannerChain?, today: String) {
        t = n.ticker
        self.px = px
        expiry = n.expiry
        leaps = n.leaps ?? n.calls.of
        putsHeld = n.puts.bought
        cs = n.calls.sold
        ps = n.puts.sold
        // Already sold for that Friday, one row per strike and side.
        var agg: [String: (call: Bool, k: Double, q: Int)] = [:]
        for a in n.already {
            let key = "\(a.type)|\(a.strike)"
            agg[key] = (a.type == "call", a.strike, (agg[key]?.q ?? 0) + a.n)
        }
        sold = agg.values.sorted { $0.k < $1.k }
        engine = n.plan.enumerated().map { PlanLeg(id: $0.offset + 1, side: $0.element.type == "put" ? .p : .c,
                                                    k: $0.element.strike, q: $0.element.n) }
        deltaNow = n.delta.now
        let e = n.nextEarnings ?? n.earnings
        earnDate = e?.date
        if let e, e.date >= today {
            // A report after the close on the expiry itself comes after it.
            earnIn = e.date < n.expiry || (e.date == n.expiry && e.time != "amc")
        } else { earnIn = false }
        self.chain = chain?.ok == true ? chain : nil
        sd = self.chain?.sd ?? n.sd ?? px * 0.03
        var pr: [String: (mid: Double, dl: Double?)] = [:]
        for p in n.plan { pr[(p.type == "put" ? "p" : "c") + "|\(p.strike)"] = (p.mid ?? 0, p.delta) }
        for r in self.chain?.calls ?? [] where r.mid > 0 { pr["c|\(r.k)"] = (r.mid, r.dl) }
        for r in self.chain?.puts ?? [] where r.mid > 0 { pr["p|\(r.k)"] = (r.mid, r.dl) }
        prices = pr
        var st: [PlanLeg.Side: [Double]] = [:]
        if let c = self.chain {
            st[.c] = Self.stops(listed: (c.calls ?? []).filter { $0.mid > 0 }.map(\.k), px: px, sd: sd, dir: 1)
            st[.p] = Self.stops(listed: (c.puts ?? []).filter { $0.mid > 0 }.map(\.k), px: px, sd: sd, dir: -1)
        }
        stops = st
    }

    /// The first listed strike at or past the money (the engine's "at the
    /// money": never in the money), then the listed strike nearest each SD
    /// step, kept strictly apart.
    static func stops(listed: [Double], px: Double, sd: Double, dir: Double) -> [Double] {
        let ks = (dir > 0 ? listed.sorted() : listed.sorted(by: >)).filter { dir * ($0 - px) >= 0 }
        guard let first = ks.first else { return [] }
        var out = [first]
        for s in SD.dropFirst() {
            let target = px + dir * s * sd
            var k = ks.min { abs($0 - target) < abs($1 - target) } ?? first
            if dir * (k - out.last!) <= 0 { k = ks.first { dir * ($0 - out.last!) > 0 } ?? out.last! }
            out.append(k)
        }
        return out
    }

    // MARK: Prices

    func mid(_ side: PlanLeg.Side, _ k: Double) -> Double? { prices["\(side.rawValue)|\(k)"]?.mid }
    func delta(_ side: PlanLeg.Side, _ k: Double) -> Double? { prices["\(side.rawValue)|\(k)"]?.dl ?? nil }
    func premium(_ l: PlanLeg) -> Double { Double(l.q) * 100 * (mid(l.side, l.k) ?? 0) }
    func expected(_ L: [PlanLeg]) -> Double { L.reduce(0) { $0 + premium($1) } }
    /// Selling moves the book's delta by minus its own: a call takes delta
    /// off, a put (negative delta) adds it.
    func after(_ L: [PlanLeg]) -> Double { deltaNow - L.reduce(0) { $0 + Double($1.q) * 100 * (delta($1.side, $1.k) ?? 0) } }

    /// "0.6 SD · 5.6%", or "ATM · 0.4%" within 0.05 SD.
    func meta(_ k: Double) -> String {
        let z = sd > 0 ? abs(k - px) / sd : 0
        return (z < 0.05 ? "ATM" : String(format: "%.1f SD", z)) + " · " + PF.dist(abs(k - px) / px * 100)
    }

    // MARK: Where a strike sits on its slider

    /// 0 at the money, 1 at 1.4 SD, piecewise between the stops so the ticks
    /// and the thumb agree.
    func kf(_ side: PlanLeg.Side, _ k: Double) -> Double {
        guard let s = stops[side], s.count == 8 else { return 0 }
        let dir: Double = side == .c ? 1 : -1
        if dir * (k - s[0]) <= 0 { return 0 }
        for i in 0..<7 where dir * (k - s[i + 1]) <= 0 {
            let span = s[i + 1] - s[i]
            return (Double(i) + (span == 0 ? 1 : (k - s[i]) / span)) / 7
        }
        return 1
    }
    func stop(_ side: PlanLeg.Side, _ k: Double) -> Int { Int((kf(side, k) * 7).rounded()) }

    // MARK: Quantity rules

    func used(_ side: PlanLeg.Side, _ L: [PlanLeg]) -> Int { L.filter { $0.side == side }.reduce(0) { $0 + $1.q } }
    func free(_ side: PlanLeg.Side, _ L: [PlanLeg]) -> Int { (side == .c ? cap.c : cap.p) - used(side, L) }

    /// Up to four; a free side, or a strike big enough to split.
    func canAdd(_ L: [PlanLeg]) -> Bool {
        L.count < 4 && (free(.c, L) > 0 || free(.p, L) > 0 || L.contains { $0.q >= 2 })
    }

    /// A new strike takes what is left on a side, calls first; when all is
    /// planned it splits the biggest strike in two. It lands one stop past
    /// the farthest strike on that side (stop 3 on an empty side).
    func add(_ L0: [PlanLeg]) -> [PlanLeg]? {
        guard canAdd(L0), live else { return nil }
        var L = L0
        let nid = (L.map(\.id).max() ?? 0) + 1
        var side: PlanLeg.Side, q: Int
        if free(.c, L) > 0 { side = .c; q = free(.c, L) }
        else if free(.p, L) > 0 { side = .p; q = free(.p, L) }
        else {
            guard let big = L.filter({ $0.q >= 2 }).max(by: { $0.q < $1.q }),
                  let i = L.firstIndex(where: { $0.id == big.id }) else { return nil }
            side = big.side; q = big.q / 2
            L[i].q = big.q - q
        }
        let js = L.filter { $0.side == side }.map { stop(side, $0.k) }
        guard let s = stops[side], s.count == 8 else { return nil }
        L.append(PlanLeg(id: nid, side: side, k: s[min(7, (js.max() ?? 2) + 1)], q: q))
        return L
    }

    /// Call / Put: keeps the stop, takes as many as are free on the new side.
    /// A side with nothing free does nothing.
    func toSide(_ L: [PlanLeg], _ id: Int, _ side: PlanLeg.Side) -> [PlanLeg]? {
        guard let l = L.first(where: { $0.id == id }), l.side != side, free(side, L) >= 1,
              let s = stops[side], s.count == 8 else { return nil }
        let j = stop(l.side, l.k), f = free(side, L)
        return L.map { $0.id == id ? PlanLeg(id: id, side: side, k: s[j], q: min($0.q, f)) : $0 }
    }

    /// The slider: stop j on the leg's side.
    func slide(_ L: [PlanLeg], _ id: Int, _ j: Int) -> [PlanLeg]? {
        guard let l = L.first(where: { $0.id == id }), let s = stops[l.side], s.count == 8 else { return nil }
        let k = s[max(0, min(7, j))]
        return k == l.k ? nil : L.map { $0.id == id ? PlanLeg(id: id, side: $0.side, k: k, q: $0.q) : $0 }
    }

    /// Typing a strike: any listed strike from the money to 1.4 SD; snaps to
    /// the nearest listed one and clamps into that range.
    func typeStrike(_ L: [PlanLeg], _ id: Int, _ v: Double) -> [PlanLeg] {
        guard v.isFinite, let l = L.first(where: { $0.id == id }), let s = stops[l.side], s.count == 8 else { return L }
        let lo = min(s[0], s[7]), hi = max(s[0], s[7])
        let listed = ((l.call ? chain?.calls : chain?.puts) ?? []).filter { $0.mid > 0 && $0.k >= lo && $0.k <= hi }.map(\.k)
        let x = max(lo, min(hi, v))
        let k = listed.min { abs($0 - x) < abs($1 - x) } ?? x
        return L.map { $0.id == id ? PlanLeg(id: id, side: $0.side, k: k, q: $0.q) : $0 }
    }

    /// Typing a quantity: 1 up to all held on that side, one less per other
    /// strike there. If that is more than is free, the other strikes on that
    /// side give way, biggest first, down to 1 each.
    func typeQty(_ L: [PlanLeg], _ id: Int, _ v: Double) -> [PlanLeg] {
        guard v.isFinite, let me = L.first(where: { $0.id == id }) else { return L }
        let c = me.call ? cap.c : cap.p
        let oth = L.filter { $0.side == me.side && $0.id != id }
        let q = max(1, min(c - oth.count, Int(v.rounded())))
        var over = q + oth.reduce(0) { $0 + $1.q } - c
        var cut: [Int: Int] = [:]
        for o in oth.sorted(by: { $0.q > $1.q }) {
            let t = min(max(0, over), o.q - 1)
            cut[o.id] = t; over -= t
        }
        return L.map { o in
            if o.id == id { return PlanLeg(id: id, side: o.side, k: o.k, q: q) }
            if let t = cut[o.id], t > 0 { return PlanLeg(id: o.id, side: o.side, k: o.k, q: o.q - t) }
            return o
        }
    }
}

// MARK: - Chart

/// The chart card's plot: hourly closes for five sessions, then the sessions
/// to the expiry. Measurements on a 393 phone: 300 tall, plot 228, tags from
/// 236 (content 321 less 93), tags 18 a row.
struct PlannerGeom {
    struct Tag: Identifiable {
        enum Kind { case price, sold, plan }
        let id: String
        let y: CGFloat
        var top: CGFloat = 0
        let num: String
        let sub: String
        let kind: Kind
        let call: Bool
        var cy: CGFloat { top + 9 }
    }
    struct Line: Identifiable { let id: String; let y: CGFloat; let kind: Tag.Kind; let call: Bool }
    struct Day: Identifiable { let id: String; let x: CGFloat; let text: String; let today: Bool; let earn: Bool }

    static let H: CGFloat = 300
    let plot: CGFloat
    /// The week as (x in points, price); the line maps prices with lo / hi
    /// itself so a change of scale glides instead of jumping.
    let series: [CGPoint]
    let lo: Double
    let hi: Double
    let dot: CGPoint
    let up: Bool
    let atmY: CGFloat
    let lines: [Line]
    let tags: [Tag]
    let days: [Day]
    let earnX: CGFloat?

    /// `per`: hourly slots a future session takes (7 = the same as a past one).
    init(_ b: PlannerBook, legs: [PlanLeg], width W: CGFloat, hist: [Double?], live: Double,
         sessions: [String], ahead: [String], today: String, per: Double) {
        let H = Self.H, PR = W - 93
        plot = PR
        let F = Double(ahead.count) * per
        var pts: [(Double, Double?)] = hist.prefix(35).enumerated().map { (Double($0.offset), $0.element) }.filter { $0.0 < live }
        pts.append((live, b.px))
        let vals = pts.compactMap(\.1)
        // Zoomed to the price and the strikes, sold and planned, so they sit
        // well apart (Nik, 14 Oct 2026: "breathing room between strikes", the
        // Positions zoom; the design's fixed 1.5 SD scale bunched them). The
        // week may stretch it by a quarter at most, beyond that it clips. As
        // a strike slides out the scale glides with it.
        let ks = b.sold.map(\.k) + legs.map(\.k)
        var ylo = min(b.px, ks.min() ?? b.px), yhi = max(b.px, ks.max() ?? b.px)
        let sp0 = max(yhi - ylo, b.px * 0.02), mid0 = (ylo + yhi) / 2
        ylo = mid0 - sp0 * 0.62; yhi = mid0 + sp0 * 0.62
        // With no strike to fit (none planned, none sold) the whole week shows.
        let stretch = ks.isEmpty ? Double.infinity : sp0 * 0.25
        ylo = max(min(ylo, vals.min() ?? ylo), ylo - stretch)
        yhi = min(max(yhi, vals.max() ?? yhi), yhi + stretch)
        let (lo, hi) = (ylo, yhi)
        self.lo = lo; self.hi = hi
        let Y = { (v: Double) in H - CGFloat((v - lo) / max(hi - lo, 0.0001)) * H }
        let Xi = { (i: Double) in CGFloat(i / max(34 + F, 1)) * PR }
        series = pts.compactMap { p in p.1.map { CGPoint(x: Xi(p.0), y: CGFloat($0)) } }
        dot = CGPoint(x: Xi(live), y: Y(b.px))
        up = b.px >= (vals.first ?? b.px)
        atmY = Y(b.px)
        lines = b.sold.map { Line(id: "s\($0.call ? "c" : "p")\($0.k)", y: Y($0.k), kind: .sold, call: $0.call) }
            + legs.map { Line(id: "l\($0.id)", y: Y($0.k), kind: .plan, call: $0.call) }
        // Tags: the price, the strikes already sold, the planned ones; spread
        // in 18 pt rows around their lines, a stack holding the price pinned
        // to it, all inside the plot.
        let away = { (k: Double) in PF.dist(abs(k - b.px) / b.px * 100) }
        var tg = [Tag(id: "px", y: Y(b.px), num: PF.price(b.px), sub: "", kind: .price, call: true)]
            + b.sold.map { Tag(id: "s\($0.call ? "c" : "p")\($0.k)", y: Y($0.k), num: PF.strike($0.k),
                               sub: "×\($0.q) " + away($0.k), kind: .sold, call: $0.call) }
            + legs.map { Tag(id: "l\($0.id)", y: Y($0.k), num: PF.strike($0.k), sub: "×\($0.q) " + away($0.k),
                             kind: .plan, call: $0.call) }
        tg.sort { $0.y < $1.y }
        let PT: CGFloat = 18
        func place(_ cl: [Tag]) -> CGFloat {
            let top: CGFloat
            if let j = cl.firstIndex(where: { $0.kind == .price }) { top = cl[j].y - PT / 2 - CGFloat(j) * PT }
            else { top = cl.enumerated().reduce(0) { $0 + $1.element.y - CGFloat($1.offset) * PT } / CGFloat(cl.count) - PT / 2 }
            return max(0, min(H - PT * CGFloat(cl.count), top))
        }
        var cls: [(tags: [Tag], top: CGFloat)] = tg.map { ([$0], place([$0])) }
        var merged = true, it = 0
        while merged && it < 20 {
            merged = false; it += 1
            for i in 0..<max(0, cls.count - 1) where cls[i].top + CGFloat(cls[i].tags.count) * PT > cls[i + 1].top {
                let c2 = cls[i].tags + cls[i + 1].tags
                cls.replaceSubrange(i...(i + 1), with: [(c2, place(c2))])
                merged = true
                break
            }
        }
        tags = cls.flatMap { cl in cl.tags.enumerated().map { j, t in var t = t; t.top = cl.top + CGFloat(j) * PT; return t } }
        // The report: a dotted line at that day's close.
        let ed = b.earnIn ? b.earnDate : nil
        if let ed, let j = ahead.firstIndex(of: ed) { earnX = Xi(34 + Double(j + 1) * per) }
        else if let ed, ed == sessions.last { earnX = Xi(34) }
        else { earnX = nil }
        // A label at each session start; today in ink, the report day gold.
        // Labels need 30 pt; today, the report day and the expiry keep theirs
        // and the rest fill in left to right where they fit.
        let past = sessions.enumerated().map { j, d in
            Day(id: "p" + d, x: Xi(Double(j * 7)), text: PBook.weekday(d), today: d == today, earn: d == ed) }
        let fut = ahead.enumerated().map { j, d in
            Day(id: "f" + d, x: Xi(35 + Double(j) * per), text: PBook.weekday(d), today: false, earn: d == ed) }
        let all = past + fut, gap: CGFloat = 30
        var keep = all.filter { $0.today || $0.earn || $0.id == fut.last?.id }
        for d in all where !keep.contains(where: { $0.id == d.id }) && keep.allSatisfy({ abs($0.x - d.x) >= gap }) {
            keep.append(d)
        }
        days = keep.sorted { $0.x < $1.x }
    }

    /// Strike tags more than 3 off their line get a connector.
    var connectors: [(y: CGFloat, cy: CGFloat)] { tags.filter { $0.kind != .price && abs($0.cy - $0.y) > 3 }.map { ($0.y, $0.cy) } }
}

// MARK: - Words

enum PlannerWords {
    /// $2,091 (commas, no K), no sign.
    static func usd(_ v: Double) -> String { F.money(v) }
    /// 850 · 1.6K, no sign.
    static func delta(_ v: Double) -> String {
        let x = abs(v.rounded())
        return x >= 1000 ? F.trim(x / 1000) + "K" : String(Int(x))
    }
}
