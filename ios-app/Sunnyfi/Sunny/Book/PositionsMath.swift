//
//  PositionsMath.swift
//  Sunny
//
//  The arithmetic behind SunnyPositions (blocks 12 and 13, handoff 22), as
//  SunnyPositions.dc.html works it: legs at their marks, side and ticker
//  totals, the distance to a strike and its status, the five pages, and the
//  Bar and Chart geometry (axis, fill zones, label rows, the hourly line's
//  scale and the tag stacks).
//

import Foundation
import CoreGraphics
import UIKit

/// The big number's mode. Yield and Payback cycle % → $ → time value
/// (`next`); Positions cycles time value → % → $ (`nextPositions`, block 12).
enum PMode { case pct, usd, tv
    var next: PMode { switch self { case .pct: .usd; case .usd: .tv; case .tv: .pct } }
    var nextPositions: PMode { switch self { case .tv: .pct; case .pct: .usd; case .usd: .tv } }
    static func preset(_ s: String?, default d: PMode = .pct) -> PMode {
        s == "usd" ? .usd : s == "tv" ? .tv : s == "pct" ? .pct : d
    }
}

/// One open leg at its mark.
struct PLeg: Identifiable, Hashable {
    let id: String
    let t: String            // ticker
    let k: Double            // strike
    let q: Int               // contracts
    let a: Double            // premium opened (sold) or paid (bought), per share
    let b: Double            // mark now, per share
    let expiry: String
    let sold: Bool
    let call: Bool
    let px: Double           // the ticker's price now
    let w: Double            // mark at the start of the Chart cards' week

    var base: Double { a * 100 * Double(q) }
    var now: Double { b * 100 * Double(q) }
    /// $ kept when sold, $ gain when bought.
    var g: Double { (sold ? a - b : b - a) * 100 * Double(q) }
    var intrinsic: Double { call ? max(0, px - k) : max(0, k - px) }
    var tv: Double { max(0, b - intrinsic) * 100 * Double(q) }
    /// % from the price to the strike, positive while out of the money.
    var dist: Double { (call ? k - px : px - k) / px * 100 }
    /// $ made or lost over the week the Chart card shows.
    var week: Double { (sold ? w - b : b - w) * 100 * Double(q) }
}

/// Sums over legs (block 12, Logic).
struct PTotals {
    var base = 0.0, g = 0.0, now = 0.0, tv = 0.0, week = 0.0
    init(_ L: [PLeg]) { for l in L { base += l.base; g += l.g; now += l.now; tv += l.tv; week += l.week } }
    /// % captured (sold) or % return (bought).
    var pct: Double { base > 0 ? g / base * 100 : 0 }
    var up: Bool { g >= 0 }
    /// The Chart line's colour: the week shown, not since opened (Nik, 14 Oct
    /// 2026: a LEAP rising all week drew red because it is down since bought).
    var weekUp: Bool { week >= 0 }
}

/// A strike's status: on your side (out of the money sold, in the money
/// bought) by more than 1%, inside 1%, or on the wrong side.
enum PStatus: Int, Comparable {
    case safe, near, past
    static func of(dist: Double, sold: Bool) -> PStatus { abs(dist) < 1 ? .near : (dist > 0) == sold ? .safe : .past }
    static func worst(_ xs: [PStatus]) -> PStatus { xs.max() ?? .safe }
    static func < (a: PStatus, b: PStatus) -> Bool { a.rawValue < b.rawValue }
}

/// Legs at the same strike, type and side, merged; sizes add.
struct PStrike: Hashable {
    let k: Double
    let call: Bool
    let sold: Bool
    var q: Int
    let dist: Double
    var key: String { (sold ? "s" : "b") + (call ? "c" : "p") + PF.strike(k) }
    var status: PStatus { .of(dist: dist, sold: sold) }
}

/// One ticker card on a side's page (block 13).
struct PCard: Identifiable {
    let id: String
    let t: String
    let px: Double
    let sold: Bool                   // the page's side
    let legs: [PLeg]
    let strikes: [PStrike]
    let totals: PTotals
    let status: PStatus              // the glow: worst strike on the card
    let near: Double                 // the order key, safe first sorts high to low
    let by: String                   // "By Fri", "By Mar 19"
    let weekExpiry: String?          // the expiry when it falls this week
    /// The put and the call closest to the price (block 13, Header strikes).
    let heads: [(word: String, dist: Double, k: Double)]
}

enum PViz { case bar, chart }

/// A page: All, or a side in one of the two styles.
struct PPage: Identifiable {
    enum Kind { case all, sold, bought }
    let id: Int
    let kind: Kind
    let viz: PViz?
    let chip: String
    let legs: [PLeg]
    let cards: [PCard]
    let status: PStatus              // the chip's dot (All: the sold legs)
    var sold: Bool { kind == .sold }
    var tickers: Int { Set(legs.map(\.t)).count }
}

enum PBook {
    /// The five pages; a side with no legs drops both of its pages.
    static func pages(_ L: [PLeg], today: String) -> [PPage] {
        let S0 = L.filter(\.sold), B0 = L.filter { !$0.sold }
        let kinds: [(PPage.Kind, String, [PLeg], PViz?)] = [
            (.all, "All", L, nil), (.sold, "Sold (Bar)", S0, .bar), (.sold, "Sold (Chart)", S0, .chart),
            (.bought, "Bought (Bar)", B0, .bar), (.bought, "Bought (Chart)", B0, .chart),
        ].filter { !$0.2.isEmpty }
        let soldCards = cards(S0, sold: true, today: today), boughtCards = cards(B0, sold: false, today: today)
        return kinds.enumerated().map { i, k in
            let dots = (k.0 == .all ? S0 : k.2).map { PStatus.of(dist: $0.dist, sold: $0.sold) }
            return PPage(id: i, kind: k.0, viz: k.3, chip: k.1, legs: k.2,
                         cards: k.0 == .all ? [] : k.0 == .sold ? soldCards : boughtCards,
                         status: .worst(dots))
        }
    }

    /// One card per ticker, safest first.
    static func cards(_ L: [PLeg], sold: Bool, today: String) -> [PCard] {
        var order: [String] = []
        for l in L where !order.contains(l.t) { order.append(l.t) }
        let week = fridayOnOrAfter(today)
        return order.map { t in
            let Lt = L.filter { $0.t == t }
            var S: [PStrike] = []
            for l in Lt {
                if let i = S.firstIndex(where: { $0.k == l.k && $0.call == l.call && $0.sold == l.sold }) { S[i].q += l.q }
                else { S.append(PStrike(k: l.k, call: l.call, sold: l.sold, q: l.q, dist: l.dist)) }
            }
            var heads: [(word: String, dist: Double, k: Double)] = []
            for (w, xs) in [("put", S.filter { !$0.call }), ("call", S.filter(\.call))] where !xs.isEmpty {
                let s = xs.min { abs($0.dist) < abs($1.dist) }!
                heads.append((w, s.dist, s.k))
            }
            let exp = Lt.map(\.expiry).min()!
            let thisWeek = exp <= week
            let near = sold ? S.map(\.dist).min()! : S.map { -$0.dist }.min()!
            return PCard(id: t, t: t, px: Lt[0].px, sold: sold, legs: Lt, strikes: S, totals: PTotals(Lt),
                         status: .worst(S.map(\.status)), near: near,
                         by: "By " + (thisWeek ? weekday(exp) : PF.monthDay(exp)),
                         weekExpiry: thisWeek ? exp : nil, heads: heads)
        }
        .sorted { $0.near != $1.near ? $0.near > $1.near : $0.t < $1.t }
    }

    /// This week's Friday (on a weekend, the coming one).
    static func fridayOnOrAfter(_ iso: String) -> String {
        var d = MarketClock.addDays(iso, 0)
        while d.weekday != 6 { d = MarketClock.addDays(d.iso, 1) }
        return d.iso
    }
    static func weekday(_ iso: String) -> String { MarketClock.dayName[MarketClock.addDays(iso, 0).weekday] }
}

/// The priced book and its pages, built once per payload.
@MainActor
enum PCache {
    private static var key = ""
    private static var value: [PPage] = []
    static func pages(_ home: HomePayload) -> [PPage] {
        if key == home.builtAt { return value }
        key = home.builtAt; value = PBook.pages(PMath.legs(home), today: home.today); return value
    }
}

enum PMath {
    /// Legs from the payload at the ticker's live price.
    static func legs(_ home: HomePayload) -> [PLeg] {
        let spot = Dictionary(home.portfolio.compactMap { p in p.spot.map { (p.ticker, $0) } }, uniquingKeysWith: { a, _ in a })
        return home.legs.compactMap { l in
            guard let px = spot[l.ticker] ?? l.underlying, px > 0 else { return nil }
            return PLeg(id: l.id, t: l.ticker, k: l.strike, q: l.n, a: l.avg, b: l.mark ?? l.avg, expiry: l.expiry,
                        sold: l.side == "sold", call: l.type == "call", px: px, w: l.markWk ?? l.avg)
        }
    }

    /// A New York wall-clock time on a date.
    static func nyDate(_ iso: String, minutes: Int) -> Date {
        var c = DateComponents(); let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return Date() }
        c.year = p[0]; c.month = p[1]; c.day = p[2]; c.hour = minutes / 60; c.minute = minutes % 60
        var cal = Calendar(identifier: .gregorian); cal.timeZone = MarketClock.ny
        return cal.date(from: c) ?? Date()
    }
}

// MARK: - Money and % as Positions writes them

enum PF {
    /// $860 · $1.2K · $22K (no decimal from $10K), no sign.
    static func usd(_ v: Double) -> String {
        let x = abs(v)
        if x >= 10_000 { return "$\(Int((x / 1000).rounded()))K" }
        if x >= 1_000 { return "$" + F.trim(x / 1000) + "K" }
        return "$\(Int(x.rounded()))"
    }
    /// 1.2K · 860 (delta in shares), no sign.
    static func count(_ v: Double) -> String {
        let x = abs(v)
        if x >= 10_000 { return "\(Int((x / 1000).rounded()))K" }
        if x >= 1_000 { return F.trim(x / 1000) + "K" }
        return "\(Int(x.rounded()))"
    }
    /// 42.1% · 100%
    static func pct(_ v: Double) -> String {
        let x = abs(v)
        return x >= 99.95 ? "\(Int(x.rounded()))%" : String(format: "%.1f%%", x)
    }
    /// Distance to a strike: one decimal under 10%, whole above.
    static func dist(_ v: Double) -> String {
        let x = abs(v)
        return x >= 10 ? "\(Int(x.rounded()))%" : String(format: "%.1f%%", x)
    }
    static func strike(_ k: Double) -> String { k == k.rounded() ? String(Int(k)) : String(k) }
    static func price(_ v: Double) -> String { String(format: "%.2f", v) }
    /// "5 calls", "1 put".
    static func count(_ n: Int, _ w: String) -> String { "\(n) \(w)\(n == 1 ? "" : "s")" }
    /// "Mar 19"
    static func monthDay(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return iso }
        let m = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][p[1] - 1]
        return "\(m) \(p[2])"
    }
    /// Width of a string in a type style (tabular figures), for the label rows.
    static func width(_ s: String, _ t: SType) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: t.uiFont(tabular: true), .kern: t.tracking * t.size]).width
    }
}

// MARK: - Bar geometry (block 13, Bar)

struct PBarGeom {
    struct Label: Identifiable {
        let id: String
        let x: CGFloat            // the tick
        let left: CGFloat         // the label box, pinned inside the card
        let w: CGFloat
        let align: Align
        let num: String
        let sub: String
        let strike: PStrike
        var row = 0
        enum Align { case leading, center, trailing }
    }

    static let numType = SType(size: 15, weight: 700, line: 18, tracking: 0)
    static let subType = SType(size: 12, weight: 500, line: 14, tracking: 0)
    static let pillType = SType(size: 13, weight: 700, line: 24, tracking: 0)

    let W: CGFloat
    let lo: Double, hi: Double
    let zones: [(CGFloat, CGFloat)]   // x from, x to
    let labels: [Label]
    let rows: Int
    let xp: CGFloat
    let pillText: String
    let pillW: CGFloat

    init(_ c: PCard, width W: CGFloat) {
        self.W = W
        let ks = c.strikes.map(\.k)
        // Zoomed on the strikes (Nik, 13 Oct 2026): at least 1% either side of
        // the price, not the design's 3%, so close strikes sit apart; the axis
        // still widens to every strike and the price.
        var lo = min(c.px * 0.99, ks.min() ?? c.px), hi = max(c.px * 1.01, ks.max() ?? c.px)
        let pd = (hi - lo) * 0.1; lo -= pd; hi += pd
        self.lo = lo; self.hi = hi
        let X = { (v: Double) in CGFloat((v - lo) / (hi - lo)) * W }
        // The stretch where the premium holds (Logic, Fill zone).
        var z: [(Double, Double)] = []
        if c.sold {
            let sp = c.strikes.filter { !$0.call }.map(\.k), sc = c.strikes.filter(\.call).map(\.k)
            z.append((sp.max() ?? lo, sc.min() ?? hi))
        } else {
            let bc = c.strikes.filter(\.call).map(\.k), bp = c.strikes.filter { !$0.call }.map(\.k)
            if let m = bc.min() { z.append((m, hi)) }
            if let m = bp.max() { z.append((lo, m)) }
        }
        zones = z.filter { $0.1 > $0.0 }.map { (X($0.0), X($0.1)) }
        xp = X(c.px)
        pillText = PF.price(c.px)
        pillW = ceil(PF.width(pillText, Self.pillType)) + 18
        // Strikes hang under the bar on alternating rows; a label drops one
        // more row only if it would still come within 6 of another label or
        // 3 of another tick.
        var its: [Label] = c.strikes.map { s in
            let num = PF.strike(s.k), sub = PF.dist(s.dist) + " · " + PF.count(s.q, s.call ? "call" : "put")
            let w = ceil(max(PF.width(num, Self.numType), PF.width(sub, Self.subType))) + 2
            let x = X(s.k), l = min(max(x - w / 2, 0), W - w)
            let a: Label.Align = x - w / 2 < 0 ? .leading : x + w / 2 > W ? .trailing : .center
            return Label(id: s.key, x: x, left: l, w: w, align: a, num: num, sub: sub, strike: s)
        }.sorted { $0.x < $1.x }
        var placed: [Label] = []
        for i in its.indices {
            var it = its[i], r = i % 2
            while r < 6 {
                let ok = placed.allSatisfy { p in
                    if p.row == r { return it.left >= p.left + p.w + 6 || it.left + it.w <= p.left - 6 }
                    if p.row > r { return p.x < it.left - 3 || p.x > it.left + it.w + 3 }
                    return it.x < p.left - 3 || it.x > p.left + p.w + 3
                }
                if ok { break }
                r += 1
            }
            it.row = r; placed.append(it); its[i] = it
        }
        labels = placed
        rows = placed.reduce(0) { max($0, $1.row + 1) }
    }

    /// 36 to the bar's bottom (50), then the rows.
    var height: CGFloat { 50 + (rows > 0 ? 8 + CGFloat(rows) * 36 : 4) }
    var pillLeft: CGFloat { min(max(xp - pillW / 2, 0), W - pillW) }
    var caretLeft: CGFloat { min(max(xp - 5, 6), W - 16) }
}

// MARK: - Chart geometry (block 13, Chart)

struct PChartGeom {
    struct Tag: Identifiable {
        let id: String
        let y: CGFloat            // its line
        var top: CGFloat = 0      // the 18 pt row it sits in
        let num: String
        let sub: String
        let isPrice: Bool
        let isPut: Bool
        var cy: CGFloat { top + 9 }
    }
    struct Day: Identifiable { let id: String; let x: CGFloat; let text: String; let today: Bool }

    static let H: CGFloat = 150
    let plot: CGFloat                 // 240 on a 393 phone
    let segments: [[CGPoint]]         // the hourly line, joined across hours with no quote
    let dot: CGPoint
    let lines: [(id: String, y: CGFloat, sold: Bool)]
    let tags: [Tag]
    let days: [Day]

    /// `hist`: 35 hourly closes over five sessions (nil where missing).
    /// `live`: the slot the live price sits at (fractional in the session).
    /// `ahead`: future sessions shown to the expiry (sold cards this week).
    init(_ c: PCard, width W: CGFloat, hist: [Double?], live: Double, sessions: [String], ahead: [String], today: String) {
        let H = Self.H, PR = W - 73
        plot = PR
        let F = Double(ahead.count * 7)
        // Hourly closes before the live slot, then the live price.
        var pts: [(Double, Double?)] = hist.prefix(35).enumerated().map { (Double($0.offset), $0.element) }.filter { $0.0 < live }
        pts.append((live, c.px))
        let vals = pts.compactMap(\.1)
        // Y fits the strikes and the price, zoomed in so the strikes sit well
        // apart (Nik, 13 Oct 2026: "increase the gap between strikes"; the
        // design's 6% minimum span and half-span history stretch left them
        // squeezed at the top). The scale widens only as far as the price has
        // to go; the week's line may stretch it by a quarter at most, and
        // beyond that it clips.
        let ks = c.strikes.map(\.k)
        var ylo = min(c.px, ks.min() ?? c.px), yhi = max(c.px, ks.max() ?? c.px)
        let sp0 = max(yhi - ylo, c.px * 0.02), mid0 = (ylo + yhi) / 2
        ylo = mid0 - sp0 * 0.62; yhi = mid0 + sp0 * 0.62
        ylo = max(min(ylo, vals.min() ?? ylo), ylo - sp0 * 0.25)
        yhi = min(max(yhi, vals.max() ?? yhi), yhi + sp0 * 0.25)
        let (l0, h0) = (ylo, yhi)
        let Y = { (v: Double) in H - CGFloat((v - l0) / (h0 - l0)) * H }
        let Xi = { (i: Double) in CGFloat(i / (34 + F)) * PR }
        // One line, joined across any hour with no quote (Nik, 13 Oct 2026: a
        // break "looks odd"; our feed missed the morning of 12 Oct).
        let joined = pts.compactMap { p in p.1.map { CGPoint(x: Xi(p.0), y: Y($0)) } }
        segments = joined.isEmpty ? [] : [joined]
        dot = CGPoint(x: Xi(live), y: Y(c.px))
        lines = c.strikes.map { ($0.key, Y($0.k), $0.sold) }
        // Tags spread around their lines in 18 pt rows; a stack holding the
        // price stays pinned to it; all kept inside the plot's height.
        var tg: [Tag] = [Tag(id: "px", y: Y(c.px), num: PF.price(c.px), sub: "", isPrice: true, isPut: false)]
            + c.strikes.map { Tag(id: $0.key, y: Y($0.k), num: PF.strike($0.k), sub: PF.dist($0.dist), isPrice: false, isPut: !$0.call) }
        tg.sort { $0.y < $1.y }
        let PT: CGFloat = 18
        func place(_ cl: [Tag]) -> CGFloat {
            let top: CGFloat
            if let j = cl.firstIndex(where: \.isPrice) { top = cl[j].y - PT / 2 - CGFloat(j) * PT }
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
        // A label at each session start; on a sold card this week, the days ahead.
        days = sessions.enumerated().map { j, d in Day(id: "p" + d, x: Xi(Double(j * 7)), text: PBook.weekday(d), today: d == today) }
            + ahead.enumerated().map { j, d in Day(id: "f" + d, x: Xi(Double(35 + j * 7)), text: PBook.weekday(d), today: false) }
    }

    /// Strike tags more than 3 off their line get a connector.
    var connectors: [(y: CGFloat, cy: CGFloat)] { tags.filter { !$0.isPrice && abs($0.cy - $0.y) > 3 }.map { ($0.y, $0.cy) } }

    /// Where the live price sits: in the session while it trades, otherwise
    /// on the last close (the 16:00 slot of the last session).
    static func liveSlot(sessions: [String], today: String, now: Date, calendar: [CalendarDay]) -> Double {
        guard sessions.last == today else { return 34 }
        let m = MarketClock.ny(now).minutes, close = MarketClock.closeMinutes(today, calendar)
        return max(27.5, min(34, 28 + Double(min(m, close) - 600) / 60))
    }
}
