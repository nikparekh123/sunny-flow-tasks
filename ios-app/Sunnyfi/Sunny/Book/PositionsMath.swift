//
//  PositionsMath.swift
//  Sunny
//
//  The arithmetic behind SunnyPositions (blocks 12 and 13, handoff 22), as
//  SunnyPositions.dc.html works it: legs at their marks, side and ticker
//  totals, the distance to a strike and its status, the three pages, and the
//  Chart geometry (the hourly line's scale and the tag stacks). The Bar style
//  was removed on 14 Oct 2026 when Nik picked the Chart.
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

/// A page: All, or a side in one of the two styles.
struct PPage: Identifiable {
    enum Kind { case all, sold, bought }
    let id: Int
    let kind: Kind
    let chip: String
    let legs: [PLeg]
    let cards: [PCard]
    let status: PStatus              // the chip's dot (All: the sold legs)
    var sold: Bool { kind == .sold }
    var tickers: Int { Set(legs.map(\.t)).count }
}

enum PBook {
    /// The five pages; a side with no legs drops both of its pages.
    static func pages(_ L: [PLeg], today: String, order: [Bool: [String]]? = nil) -> [PPage] {
        let S0 = L.filter(\.sold), B0 = L.filter { !$0.sold }
        /* Three pages: the Chart style won (Nik, 14 Oct 2026); the Bar pages went. */
        let kinds: [(PPage.Kind, String, [PLeg])] = [
            (.all, "All", L), (.sold, "Sold", S0), (.bought, "Bought", B0),
        ].filter { !$0.2.isEmpty }
        let soldCards = cards(S0, sold: true, today: today, order: order?[true])
        let boughtCards = cards(B0, sold: false, today: today, order: order?[false])
        return kinds.enumerated().map { i, k in
            let dots = (k.0 == .all ? S0 : k.2).map { PStatus.of(dist: $0.dist, sold: $0.sold) }
            return PPage(id: i, kind: k.0, chip: k.1, legs: k.2,
                         cards: k.0 == .all ? [] : k.0 == .sold ? soldCards : boughtCards,
                         status: .worst(dots))
        }
    }

    /// The card order a payload gives: each side's tickers, safest first.
    static func order(_ L: [PLeg], today: String) -> [Bool: [String]] {
        [true: cards(L.filter(\.sold), sold: true, today: today).map(\.t),
         false: cards(L.filter { !$0.sold }, sold: false, today: today).map(\.t)]
    }

    /// One card per ticker, safest first; with `order`, in that frozen order
    /// (names it does not know go last, safest first).
    static func cards(_ L: [PLeg], sold: Bool, today: String, order: [String]? = nil) -> [PCard] {
        let live = safestFirst(L, sold: sold, today: today)
        guard let order else { return live }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return live.enumerated().sorted { a, b in
            switch (rank[a.element.t], rank[b.element.t]) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    private static func safestFirst(_ L: [PLeg], sold: Bool, today: String) -> [PCard] {
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
    /// `orderFrom`: the payload the card order is read from (the insight
    /// words' copy, which only moves on open, pull and after the close).
    static func pages(_ home: HomePayload, orderFrom: HomePayload? = nil) -> [PPage] {
        let k = home.builtAt + "|" + (orderFrom?.builtAt ?? "")
        if key == k { return value }
        let order = orderFrom.map { PBook.order(PMath.legs($0), today: $0.today) }
        key = k; value = PBook.pages(PMath.legs(home), today: home.today, order: order); return value
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
}

// MARK: - Chart geometry (block 13, Chart)

struct PChartGeom {
    struct Tag: Identifiable {
        let id: String
        let y: CGFloat            // its line
        var top: CGFloat = 0      // the 18 pt row it sits in
        let num: String
        let sub: String
        var qty: String = ""         // "×6": the contracts at that strike
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
        // The tag column is 77 wide (design 65) so it can carry the contract count.
        let H = Self.H, PR = W - 85
        plot = PR
        let F = Double(ahead.count * 7)
        // Hourly closes before the live slot, then the live price.
        var pts: [(Double, Double?)] = hist.prefix(35).enumerated().map { (Double($0.offset), $0.element) }.filter { $0.0 < live }
        pts.append((live, c.px))
        let vals = pts.compactMap(\.1)
        // Y fits the strikes and the price, zoomed in so the strikes sit well
        // apart (Nik, 13 Oct 2026: "increase the gap between strikes"; the
        // design's 6% minimum span and half-span history stretch left them
        // squeezed at the top). The week's line always fits as well, as on the
        // Planner (Nik, 15 Oct 2026: after NKE's 5% jump the week was cut off
        // below the chart and the line seemed to start on Thursday); the
        // tags still spread apart when a jump brings the strike lines closer.
        let ks = c.strikes.map(\.k)
        var ylo = min(c.px, ks.min() ?? c.px), yhi = max(c.px, ks.max() ?? c.px)
        let sp0 = max(yhi - ylo, c.px * 0.02), mid0 = (ylo + yhi) / 2
        ylo = mid0 - sp0 * 0.62; yhi = mid0 + sp0 * 0.62
        if let vlo = vals.min(), let vhi = vals.max() {
            let pad = (max(yhi, vhi) - min(ylo, vlo)) * 0.04
            ylo = min(ylo, vlo - pad); yhi = max(yhi, vhi + pad)
        }
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
            + c.strikes.map { Tag(id: $0.key, y: Y($0.k), num: PF.strike($0.k), sub: PF.dist($0.dist), qty: "×\($0.q)", isPrice: false, isPut: !$0.call) }
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
