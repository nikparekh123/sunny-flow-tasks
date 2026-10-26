//
//  SunnySides.swift
//  Sunny
//
//  Block 13f (handoff 32) · the Sold and Bought faces with the week's plan.
//  Sold: the week's contract only, Mon to Fri hourly, the line ends at today
//  with the price at its end, the days left shaded, the strike dashed and a
//  faint breakeven at strike plus premium; collected · left to earn · kept;
//  captured against the week gone with On pace, Ahead or Behind (on pace is
//  1 less the square root of the share of the week still ahead, within 5
//  points). Bought: LEAPS under 0.70 delta flagged against the playbook, where
//  the hedge and the insurance start, daily closes back as far as the hedge
//  has left (a month at least), one row per leg type. Both end with This week:
//  the premium on what the week's expiry sold against a week of decay on
//  everything bought (sunny-home `plan.wk`, one source).
//

import SwiftUI

// MARK: - Shared: the tag column, the week's net

struct PSideTag: Identifiable {
    let id: String
    let y: CGFloat
    var top: CGFloat = 0
    let num: String
    let sub: String
    var qty: String = ""
    let isPrice: Bool
    let pill: Bool
    var cy: CGFloat { top + 9 }

    /// Spread around their lines in 18 pt rows; a stack holding the price stays pinned to it (as PChartGeom).
    static func spread(_ tags: [PSideTag], H: CGFloat) -> [PSideTag] {
        let tg = tags.sorted { $0.y < $1.y }, PT: CGFloat = 18
        func place(_ cl: [PSideTag]) -> CGFloat {
            let top: CGFloat
            if let j = cl.firstIndex(where: \.isPrice) { top = cl[j].y - PT / 2 - CGFloat(j) * PT }
            else { top = cl.enumerated().reduce(0) { $0 + $1.element.y - CGFloat($1.offset) * PT } / CGFloat(cl.count) - PT / 2 }
            return max(0, min(H - PT * CGFloat(cl.count), top))
        }
        var cls: [(tags: [PSideTag], top: CGFloat)] = tg.map { ([$0], place([$0])) }
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
        return cls.flatMap { cl in cl.tags.enumerated().map { j, t in var t = t; t.top = cl.top + CGFloat(j) * PT; return t } }
    }
}

private struct PSideTagView: View {
    let t: PSideTag
    var body: some View {
        if t.isPrice {
            Text(t.num).sType(SType(size: 13, weight: 700, line: 13, tracking: 0)).foregroundStyle(S.paper)
                .padding(.horizontal, 7).frame(height: 18)
                .background(Capsule().fill(S.ink))
                .fixedSize()
        } else {
            HStack(spacing: 4) {
                Text(t.num).sType(SType(size: 13, weight: 700, line: 13, tracking: 0)).foregroundStyle(S.ink)
                if !t.qty.isEmpty { Text(t.qty).sType(SType(size: 11, weight: 600, line: 11, tracking: 0)).foregroundStyle(S.ink) }
                Text(t.sub).sType(SType(size: 11, weight: 600, line: 11, tracking: 0), tabular: false).foregroundStyle(S.muted)
            }
            .padding(.horizontal, t.pill ? 6 : 0).frame(height: 18)
            .background { if t.pill { Capsule().fill(S.pTrack) } }
            .fixedSize()
        }
    }
}

private struct PSegLine: Shape {
    let pts: [CGPoint]
    func path(in r: CGRect) -> Path {
        var p = Path()
        for (i, q) in pts.enumerated() { i == 0 ? p.move(to: q) : p.addLine(to: q) }
        return p
    }
}

/// "This week · net $243" and what it is made of; losses red, never a minus sign.
struct PWeekNet: View {
    let wk: NamePlan.Wk
    let legs: [Leg]
    let week: String

    var body: some View {
        let net = wk.prem - wk.dec
        let sold = legs.filter { $0.side == "sold" && $0.expiry == week }
        let what = sold.contains { $0.type == "call" } && sold.contains { $0.type == "put" } ? "calls and puts" : sold.contains { $0.type == "put" } ? "puts" : "calls"
        let bought = legs.filter { $0.side == "bought" }
        let hedged = bought.contains { $0.type == "put" || ($0.up ?? false) }
        var t = Text("")
        t = wk.prem > 0 ? t + Text(PF.usd(wk.prem)).foregroundStyle(S.green) + Text(" from sold \(what), ") : t + Text("Nothing sold yet, ")
        t = bought.isEmpty ? t + Text("nothing bought to decay. ")
            : t + Text(PF.usd(wk.dec)).foregroundStyle(S.red) + Text(" decay on " + (hedged ? "LEAPS and hedges" : "LEAPS") + ". ")
        t = t + Text(net >= 0 ? "Premium covers the decay." : "Premium does not cover the decay yet.")
        return VStack(alignment: .leading, spacing: 2) {
            (Text("This week · net ") + Text(PF.usd(net)).foregroundStyle(net >= 0 ? S.green : S.red))
                .sType(SType(size: 15, weight: 600, line: 20, tracking: 0)).foregroundStyle(S.ink)
            t.sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(S.surface))
        .accessibilityElement(children: .combine)
    }
}

/// Stats along a face's foot: 17 bold over a 12 label, a rule above (as block 13).
private struct PSideStats: View {
    let cells: [(String, String, Color)]
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(cells, id: \.1) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.0).sType(SType(size: 17, weight: 700, line: 20, tracking: 0)).foregroundStyle(c.2).lineLimit(1)
                    Text(c.1).sType(SType(size: 12, weight: 500, line: 14, tracking: 0), tabular: false).foregroundStyle(S.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 16)
        .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
    }
}

// MARK: - Sold

struct PSoldPlan: View {
    let c: PCard
    let n: PName
    let width: CGFloat
    private let exp: String
    private let legs: [PLeg]
    private let g: Geom
    private let gone: Double
    private let left: Int
    @Environment(\.colorScheme) private var scheme

    /// The chart: Mon to Fri of the expiry's week, 7 hourly slots a day.
    struct Geom {
        static let H: CGFloat = 170
        let plot: CGFloat
        let pts: [CGPoint]
        let end: CGPoint
        let lines: [(id: String, y: CGFloat)]
        let tags: [PSideTag]
        let bes: [(y: CGFloat, text: String, call: Bool)]
        let today: Int?
    }

    init?(c: PCard, n: PName, hours: Hours?, live: Double, today: String, cal: [CalendarDay], width: CGFloat) {
        let exp = c.weekExpiry ?? c.legs.map(\.expiry).min() ?? ""
        let legs = c.legs.filter { $0.expiry == exp }
        guard !legs.isEmpty else { return nil }
        self.c = c; self.n = n; self.width = width; self.exp = exp; self.legs = legs
        // The five weekdays of the expiry's week and which of them trade.
        let wd = MarketClock.addDays(exp, 0).weekday
        let mon = MarketClock.addDays(exp, -(wd - 2)).iso
        let week = (0..<5).map { MarketClock.addDays(mon, $0).iso }
        let trades = week.filter { d in d <= exp && MarketClock.isTradingDay(d, weekday: MarketClock.addDays(d, 0).weekday, cal) }
        // Hourly closes this week so far, then the live price (or the last close).
        let days = hours?.days ?? [], hist = hours?.px[c.t] ?? []
        let H = Geom.H, PR = width - 85
        var raw: [(Double, Double)] = []
        for (si, d) in days.enumerated() {
            guard let j = week.firstIndex(of: d) else { continue }
            for h in 0..<7 {
                let slot = Double(si * 7 + h)
                if si == days.count - 1 && d == today && slot >= live { continue }
                if let v = hist[safe: si * 7 + h] ?? nil { raw.append((Double(j * 7 + h), v)) }
            }
        }
        let todayJ = week.firstIndex(of: today)
        let endSlot: Double = {
            if let j = todayJ, days.last == today { return Double(j * 7) + live - Double((days.count - 1) * 7) }
            if let last = days.last(where: { week.contains($0) }), let j = week.firstIndex(of: last) { return Double(j * 7 + 6) }
            return -0.5
        }()
        raw.append((endSlot, c.px))
        // Breakevens: the nearest sold call's strike plus its premium, the nearest sold put's less it.
        var be: [(v: Double, call: Bool)] = []
        for call in [true, false] {
            let a = legs.filter { $0.call == call }
            guard let k = call ? a.map(\.k).min() : a.map(\.k).max() else { continue }
            let at = a.filter { $0.k == k }, q = at.reduce(0) { $0 + $1.q }
            guard q > 0 else { continue }
            let pr = at.reduce(0.0) { $0 + $1.base } / Double(q * 100)
            be.append((call ? k + pr : k - pr, call))
        }
        // Y fits the price, strikes and breakevens (a 6% span at least), then the week's line.
        var ks: [Double: (q: Int, call: Bool, dist: Double)] = [:]
        for l in legs { let e = ks[l.k]; ks[l.k] = ((e?.q ?? 0) + l.q, l.call, l.dist) }
        let all = [c.px] + Array(ks.keys) + be.map(\.v)
        var ylo = all.min() ?? c.px, yhi = all.max() ?? c.px
        let sp0 = max(yhi - ylo, c.px * 0.06), mid0 = (ylo + yhi) / 2
        ylo = mid0 - sp0 * 0.62; yhi = mid0 + sp0 * 0.62
        let vals = raw.map(\.1)
        let a0 = min(ylo, vals.min() ?? ylo), b0 = max(yhi, vals.max() ?? yhi), pad = (b0 - a0) * 0.04
        let lo = a0 - pad, hi = b0 + pad
        let Y = { (v: Double) in H - CGFloat((v - lo) / (hi - lo)) * H }
        let X = { (s: Double) in CGFloat((s + 0.5) / 35) * PR }
        let pts = raw.map { CGPoint(x: X($0.0), y: Y($0.1)) }
        let tags = PSideTag.spread(ks.map { k, v in
            PSideTag(id: "\(v.call ? "c" : "p")\(k)", y: Y(k), num: PF.strike(k), sub: PF.dist(v.dist), qty: "×\(v.q)", isPrice: false, pill: !v.call)
        }, H: H)
        g = Geom(plot: PR, pts: pts, end: pts.last ?? CGPoint(x: 0, y: Y(c.px)), lines: ks.keys.sorted().map { ("s\($0)", Y($0)) }, tags: tags,
                 bes: be.map { (Y($0.v), "Breakeven " + PF.price($0.v), $0.call) }, today: todayJ)
        // The share of the week gone, in trading time; the days left after today.
        let total = Double(max(1, trades.count))
        let done = Double(trades.filter { $0 < today }.count)
        let inToday: Double = trades.contains(today) && days.last == today ? max(0, min(1, (live - Double((days.count - 1) * 7) + 0.5) / 6.5)) : 0
        gone = min(1, (done + inToday) / total)
        left = trades.filter { $0 > today }.count + (trades.contains(today) && inToday == 0 ? 1 : 0)
    }

    var body: some View {
        let A = PTotals(legs), keptUp = A.g >= 0
        VStack(alignment: .leading, spacing: 16) {
            header
            chart
            pace(A)
            PSideStats(cells: [(PF.usd(A.base), "collected", S.ink), (PF.usd(A.tv), "left to earn", S.ink),
                               (PF.usd(abs(A.g)), keptUp ? "kept" : "lost", keptUp ? S.green : S.red)])
            if let p = n.plan, let wk = p.wk { PWeekNet(wk: wk, legs: n.legs, week: p.week) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(PF.monthDay(exp)) · " + (left == 0 ? "expires today" : PWords.n(left, "day") + " left")).foregroundStyle(S.muted)
            Spacer(minLength: 0)
            c.heads.enumerated().reduce(Text("")) { acc, e in
                let h = e.element
                return acc + Text(PF.dist(h.dist) + (h.dist >= 0 ? " to " : " past ") + h.word)
                    .foregroundStyle(h.dist < 0 ? S.red : h.dist < 2 ? S.yellowDeep : S.muted)
                    + Text(e.offset < c.heads.count - 1 ? " · " : "").foregroundStyle(S.muted)
            }
        }
        .sType(SType(size: 13, weight: 500, line: 16, tracking: 0))
        .lineLimit(1)
    }

    private var chart: some View {
        let H = Geom.H, PR = g.plot, lineC = PTotals(legs).weekUp ? S.green : S.red
        let shade = scheme == .dark ? Color.white.opacity(0.06) : Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255).opacity(0.045)
        let beC = scheme == .dark ? Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255).opacity(0.24) : Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255).opacity(0.22)
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                // The days left, shaded from today to Friday's close.
                UnevenRoundedRectangle(cornerRadii: .init(bottomTrailing: 8, topTrailing: 8), style: .continuous)
                    .fill(shade)
                    .frame(width: max(0, PR - g.end.x), height: H)
                    .offset(x: g.end.x)
                ForEach(Array(g.bes.enumerated()), id: \.offset) { _, b in
                    Rectangle().fill(beC).frame(width: PR, height: 1).offset(y: b.y)
                    Text(b.text).sType(SType(size: 11, weight: 600, line: 13, tracking: 0)).foregroundStyle(S.muted)
                        .fixedSize()
                        .frame(width: PR - 4, alignment: .trailing)
                        .offset(y: b.call ? (b.y < 16 ? b.y + 2 : b.y - 15) : (b.y > H - 16 ? b.y - 15 : b.y + 2))
                }
                ForEach(g.lines, id: \.id) { l in
                    PSegLine(pts: [CGPoint(x: 0, y: l.y), CGPoint(x: PR, y: l.y)])
                        .stroke(S.pStrike, style: StrokeStyle(lineWidth: 1.5, dash: [4.5, 3]))
                }
                PSegLine(pts: g.pts).stroke(lineC, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                Path { p in for t in g.tags where abs(t.cy - t.y) > 3 { p.move(to: CGPoint(x: PR, y: t.y)); p.addLine(to: CGPoint(x: PR + 6, y: t.cy)) } }
                    .stroke(S.muted, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                ForEach(g.tags) { t in PSideTagView(t: t).offset(x: PR + 8, y: t.top) }
                Circle().fill(S.paper)
                    .overlay(Circle().strokeBorder(lineC, lineWidth: 2.5))
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    .offset(x: g.end.x - 6, y: g.end.y - 6)
                Text(PF.price(c.px)).sType(SType(size: 13, weight: 700, line: 13, tracking: 0)).foregroundStyle(S.paper)
                    .padding(.horizontal, 7).frame(height: 18)
                    .background(Capsule().fill(S.ink))
                    .fixedSize()
                    .offset(x: min(g.end.x + 9, PR - 40), y: max(0, min(H - 18, g.end.y - 9)))
            }
            .frame(width: width, height: H, alignment: .topLeading)
            // One label per day; today in ink.
            HStack(spacing: 0) {
                ForEach(Array(["Mon", "Tue", "Wed", "Thu", "Fri"].enumerated()), id: \.offset) { j, d in
                    Text(d).sType(SType(size: 11, weight: 500, line: 14, tracking: 0), tabular: false)
                        .foregroundStyle(g.today == j ? S.ink : S.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: PR)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(c.t) at \(PF.price(c.px)), " + g.bes.map(\.text).joined(separator: ", "))
    }

    private func pace(_ A: PTotals) -> some View {
        let cap = A.base > 0 ? A.g / A.base : 0, ex = 1 - (1 - gone).squareRoot(), dv = (cap - ex) * 100
        let tag = dv < -5 ? "Behind pace" : dv > 5 ? "Ahead of pace" : "On pace", behind = dv < -5
        return VStack(alignment: .leading, spacing: 4) {
            // Red, never a minus sign: a loss so far reads "4% lost".
            (Text("\(Int(abs(cap * 100).rounded()))%").foregroundStyle(cap >= 0 ? S.green : S.red)
             + Text((cap >= 0 ? " captured" : " lost") + " · \(Int((gone * 100).rounded()))% of the week gone"))
                .sType(SType(size: 15, weight: 600, line: 20, tracking: 0)).foregroundStyle(S.ink)
            HStack(alignment: .top, spacing: 8) {
                Text(tag).sType(SType(size: 12, weight: 600, line: 16, tracking: 0), tabular: false)
                    .foregroundStyle(behind ? S.orangeDeep : S.green)
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(behind ? S.orangeDeep.opacity(scheme == .dark ? 0.18 : 0.10) : S.green.opacity(scheme == .dark ? 0.18 : 0.12)))
                    .fixedSize()
                Text("Decay speeds up near Friday, so \(Int((ex * 100).rounded()))% is on pace by now.")
                    .sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - Bought

struct PBoughtPlan: View {
    let c: PCard
    let n: PName
    let today: String
    let width: CGFloat
    @Environment(\.colorScheme) private var scheme

    private var leaps: [PLeg] { c.legs.filter { $0.call && !$0.up } }
    private var hedges: [PLeg] { c.legs.filter { $0.call && $0.up } }
    private var puts: [PLeg] { c.legs.filter { !$0.call } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let d = drift { flag(d) }
            header
            PBoughtChart(c: c, daily: n.daily, today: today, width: width, leaps: Set(leaps.map(\.k)), hedges: Set(hedges.map(\.k)))
            rows
            if let p = n.plan, let wk = p.wk { PWeekNet(wk: wk, legs: n.legs, week: p.week) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
    }

    /// The LEAPS' delta, weighted by contracts, from the marks (nil when unmarked).
    private func delta(_ ls: [PLeg]) -> Double? {
        let ds = ls.compactMap { l in n.legs.first { $0.side == "bought" && $0.type == "call" && $0.strike == l.k && $0.expiry == l.expiry }?.delta.map { ($0, l.q) } }
        let q = ds.reduce(0) { $0 + $1.1 }
        return q > 0 ? ds.reduce(0.0) { $0 + $1.0 * Double($1.1) } / Double(q) : nil
    }

    /// The playbook holds deep ITM LEAPS: under 0.70 delta the face says so, with how much is time value.
    private var drift: (t: String, s: String)? {
        guard !leaps.isEmpty, let dl = delta(leaps), dl < 0.7, let k = leaps.map(\.k).min() else { return nil }
        let d = (k / c.px - 1) * 100
        let nw = leaps.reduce(0) { $0 + $1.now }, tv = leaps.reduce(0) { $0 + $1.tv }
        let where_ = abs(d) < 3 ? "at the money" : d < 0 ? "only \(PF.dist(d)) in the money" : "\(PF.dist(d)) out of the money"
        return ("LEAPS \(where_), delta \(String(format: "%.2f", dl)). Playbook expects deep ITM.",
                (nw > 0 && tv / nw >= 0.85 ? "Nearly all of their \(PF.usd(nw))" : "\(PF.usd(tv)) of their \(PF.usd(nw))") + " is time value, and it decays.")
    }

    private func flag(_ d: (t: String, s: String)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(d.t).sType(SType(size: 15, weight: 600, line: 20, tracking: 0)).foregroundStyle(S.orangeDeep)
                .fixedSize(horizontal: false, vertical: true)
            Text(d.s).sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(S.orangeDeep.opacity(scheme == .dark ? 0.18 : 0.10)))
        .accessibilityAddTraits(.isStaticText)
    }

    /// Where the protection starts: the lowest hedge call above, the highest insurance put below.
    private var header: some View {
        var t = Text("")
        if let h = hedges.map(\.k).min() {
            let d = (h / c.px - 1) * 100
            t = d > 0 ? t + Text("Hedge kicks in at ") + Text("+" + PF.dist(d)).foregroundStyle(S.ink) : t + Text("Hedge in play").foregroundStyle(S.green)
        } else { t = t + Text("No hedge") }
        t = t + Text(" · ")
        if let p = puts.map(\.k).max() {
            let d = (1 - p / c.px) * 100
            t = d > 0 ? t + Text("insurance at ") + Text(PF.dist(d)).foregroundStyle(S.red) : t + Text("insurance in play").foregroundStyle(S.green)
        } else { t = t + Text("no insurance") }
        return t.sType(SType(size: 13, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.muted).lineLimit(1)
    }

    private var rows: some View {
        let rs = [row("lp", "LEAPS", leaps), row("hc", "Hedge call", hedges), row("ip", "Insurance put", puts)].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(rs, id: \.key) { r in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.t).sType(SType(size: 15, weight: 600, line: 20, tracking: 0)).foregroundStyle(S.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(r.sub).sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.muted)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(PF.usd(r.g)).sType(SType(size: 15, weight: 700, line: 20, tracking: 0))
                        Text(PF.pct(r.pct)).sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                    }
                    .foregroundStyle(r.g >= 0 ? S.green : S.red)
                }
                .padding(.vertical, 12)
                .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(r.t), \(r.sub), \(r.g >= 0 ? "up" : "down") \(PF.usd(r.g))")
            }
        }
        .padding(.top, -4)
    }

    private func row(_ key: String, _ name: String, _ a: [PLeg]) -> (key: String, t: String, sub: String, g: Double, pct: Double)? {
        guard !a.isEmpty else { return nil }
        var qs: [Double: Int] = [:]
        for l in a { qs[l.k, default: 0] += l.q }
        let b = a.reduce(0) { $0 + $1.base }, nw = a.reduce(0) { $0 + $1.now }, g = nw - b
        let exps = Set(a.map(\.expiry)).sorted()
        let t = "\(name) " + qs.keys.sorted().map { "\(PF.strike($0)) ×\(qs[$0]!)" }.joined(separator: " and ") + ", " + exps.map(expLabel).joined(separator: " and ")
        let sub = "Paid \(PF.usd(b)) · now \(PF.usd(nw))" + (key == "lp" ? delta(a).map { " · delta " + String(format: "%.2f", $0) } ?? "" : "")
        return (key, t, sub, g, b > 0 ? g / b * 100 : 0)
    }

    /// "Jan 15" inside a year, "Jan ’28" past it.
    private func expLabel(_ e: String) -> String {
        guard e > MarketClock.addDays(today, 365).iso else { return PF.monthDay(e) }
        return String(PF.monthDay(e).prefix(3)) + " ’" + String(e.prefix(4).suffix(2))
    }
}

/// Daily closes back as far as the hedge has left, a month at least; the strikes on the right.
private struct PBoughtChart: View {
    let c: PCard
    let daily: DailyCloses?
    let today: String
    let width: CGFloat
    let leaps: Set<Double>
    let hedges: Set<Double>
    static let H: CGFloat = 150

    var body: some View {
        let H = Self.H, PR = width - 85
        let hedgeLegs = c.legs.filter { !($0.call && !$0.up) }
        let days = max(30, hedgeLegs.map { l in max(0, Self.days(today, l.expiry)) }.max() ?? 30)
        let from = MarketClock.addDays(today, -days).iso
        let d = daily ?? DailyCloses(d: [], c: [])
        var pts: [(String, Double)] = zip(d.d, d.c).filter { $0.0 >= from && $0.0 < today }.map { ($0.0, $0.1) }
        pts.append((today, c.px))
        var ks: [Double: (q: Int, call: Bool)] = [:]
        for l in c.legs { let e = ks[l.k]; ks[l.k] = ((e?.q ?? 0) + l.q, l.call) }
        let all = [c.px] + Array(ks.keys)
        var ylo = all.min() ?? c.px, yhi = all.max() ?? c.px
        let sp0 = max(yhi - ylo, c.px * 0.06), mid0 = (ylo + yhi) / 2
        ylo = mid0 - sp0 * 0.62; yhi = mid0 + sp0 * 0.62
        let vals = pts.map(\.1)
        let a0 = min(ylo, vals.min() ?? ylo), b0 = max(yhi, vals.max() ?? yhi), pad = (b0 - a0) * 0.04
        let lo = a0 - pad, hi = b0 + pad
        let Y = { (v: Double) in H - CGFloat((v - lo) / (hi - lo)) * H }
        let X = { (i: Int) in pts.count > 1 ? CGFloat(i) / CGFloat(pts.count - 1) * PR : 0 }
        let line = pts.enumerated().map { CGPoint(x: X($0.offset), y: Y($0.element.1)) }
        let up = pts.count > 1 ? c.px >= pts[0].1 : true, lineC = up ? S.green : S.red
        let tags = PSideTag.spread([PSideTag(id: "px", y: Y(c.px), num: PF.price(c.px), sub: "", isPrice: true, pill: false)]
            + ks.map { k, v in PSideTag(id: "k\(k)\(v.call)", y: Y(k), num: PF.strike(k), sub: v.call ? (leaps.contains(k) && !hedges.contains(k) ? "LEAPS" : "Hedge") : "Put", isPrice: false, pill: !v.call) }, H: H)
        let end = line.last ?? CGPoint(x: 0, y: Y(c.px))
        // Month labels at each month's first session; the first month at the left when there is room.
        let months: [(x: CGFloat, t: String)] = {
            var out: [(CGFloat, String)] = [], last = ""
            for (i, p) in pts.enumerated() {
                let m = String(p.0.prefix(7))
                if m != last { out.append((X(i), String(PF.monthDay(p.0).prefix(3)))); last = m }
            }
            if out.count > 1 && out[1].0 - out[0].0 < 36 { out.removeFirst() }
            return out.map { ($0.0, $0.1) }
        }()
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                ForEach(ks.keys.sorted(), id: \.self) { k in
                    PSegLine(pts: [CGPoint(x: 0, y: Y(k)), CGPoint(x: PR, y: Y(k))])
                        .stroke(S.pStrike, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0, 3]))
                }
                PSegLine(pts: line).stroke(lineC, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                Path { p in for t in tags where !t.isPrice && abs(t.cy - t.y) > 3 { p.move(to: CGPoint(x: PR, y: t.y)); p.addLine(to: CGPoint(x: PR + 6, y: t.cy)) } }
                    .stroke(S.muted, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                ForEach(tags) { t in PSideTagView(t: t).offset(x: PR + 8, y: t.top) }
                Circle().fill(S.paper)
                    .overlay(Circle().strokeBorder(lineC, lineWidth: 2.5))
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    .offset(x: end.x - 6, y: end.y - 6)
            }
            .frame(width: width, height: H, alignment: .topLeading)
            ZStack(alignment: .topLeading) {
                ForEach(Array(months.enumerated()), id: \.offset) { j, m in
                    Text(m.t).sType(SType(size: 11, weight: 500, line: 14, tracking: 0), tabular: false)
                        .foregroundStyle(j == months.count - 1 ? S.ink : S.muted)
                        .fixedSize()
                        .offset(x: min(m.x, PR - 24))
                }
            }
            .frame(width: PR, height: 14, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(c.t) daily closes since \(PF.monthDay(from)), now \(PF.price(c.px))")
    }

    static func days(_ a: String, _ b: String) -> Int {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
        guard let x = f.date(from: a), let y = f.date(from: b) else { return 0 }
        return Int((y.timeIntervalSince(x) / 86400).rounded())
    }
}
