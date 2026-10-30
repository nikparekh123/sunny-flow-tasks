//
//  SearchChart.swift
//  Sunny
//
//  The price chart (block 29, handoff Oct 30 2026): how a name is doing over a Week, Month, Quarter or Year, the
//  range control changing the card in place. Each range offers only its own chips: Positions and Walls on Week,
//  Technicals and Positions on Month, those and Value on Quarter, Value and Technicals on Year. sunny-search sends
//  every range at once (a year of closes with the 50 and 200-day averages, this week's line every 15 minutes, what
//  is held, the week's walls, the saved research), and the card draws it and writes the sentence under it from the
//  same figures the answer was written from. The price line and today's dot are green or red by the move over the
//  range, as the number in the header. Values never move the scale: past an edge they pin to it with an arrow.
//

import SwiftUI

/// What sunny-search sends for the card.
struct SXChart: Decodable, Equatable {
    struct Week: Decodable, Equatable {
        struct Day: Decodable, Equatable { let lab: String; let closed: Bool }
        let days: [Day]
        /// The weekday of today (-1 on a weekend), and of the week's expiry.
        let today: Int, exp: Int
        /// Across the week 0 to 1, and the price; the first is last Friday's close.
        let pts: [[Double]]
    }
    struct Sold: Decodable, Equatable { let k: Double; let cp: String }
    struct Cap: Decodable, Equatable { let pct: Int; let tag: String? }
    struct Leg: Decodable, Equatable { let g: String; let k: Double }
    struct Wall: Decodable, Equatable { let lb: String; let k: Double }
    struct Research: Decodable, Equatable { let an: Double; let fv: Double; let src: String }
    struct Ix: Decodable, Equatable { let w: Int; let m: Int; let q: Int }

    let t: String, co: String, px: Double
    /// w m q y, and "cross" to mark the last cross of the 50-day.
    let range: String, mark: String?
    /// A year of sessions, today last once it has opened.
    let d: [String], c: [Double], ma50: [Double?], ma200: [Double?], rsi: Double?
    /// Where Week (last Friday's close), Month and Quarter start; Year starts at 0.
    let ix: Ix
    let week: Week
    let sold: [Sold], cap: Cap?, legs: [Leg], leapsK: Double?, walls: [Wall], res: Research?
    /// "1:52 PM" while the market is open, else "Thu 4:00 PM close".
    let at: String
    let live: Bool?
}

// MARK: - Colours (block 29)

extension SX {
    /// Research: fair value and the analysts' target.
    static let research = S.dyn(0x6941C6, 0xB69CFF)
    /// The days left in the week, and the range control's track.
    static let left = S.dynA(0x1D1D1F, 0.045, 0xFFFFFF, 0.06)
    static let segTrack = S.dynA(0x767680, 0.12, 0x767680, 0.24)
    static let segThumb = S.dynA(0xFFFFFF, 0.88, 0xFFFFFF, 0.20)
}

// MARK: - The card

struct SXChartCard: View {
    let p: SXChart

    @Environment(\.accessibilityReduceMotion) private var still
    @State private var rg: String
    /// Chips each range has on, once he changes them.
    @State private var lay: [String: Set<String>] = [:]

    init(p: SXChart) {
        self.p = p
        _rg = State(initialValue: ["w", "m", "q", "y"].contains(p.range) ? p.range : "w")
    }

    private static let names = ["w": "Week", "m": "Month", "q": "Quarter", "y": "Year"]
    private static let over = ["w": "this week", "m": "over the month", "q": "over the quarter", "y": "over the year"]
    private static let chipName = ["pos": "Positions", "walls": "Walls", "tech": "Technicals", "val": "Value"]
    private var held: Bool { !p.sold.isEmpty || !p.legs.isEmpty }

    var body: some View {
        let o = SXChartBuild(p: p, rg: rg, on: on).out
        VStack(alignment: .leading, spacing: 14) {
            header
            price
            SXSegment(items: ["w", "m", "q", "y"].map { ($0, Self.names[$0]!) }, pick: $rg, still: still)
                .padding(.top, -4)
            if !available.isEmpty { chips.padding(.vertical, -10) }
            SXChartPlot(o: o)
                .id(rg + "|" + available.filter(on).joined(separator: ","))
                .transition(.opacity)
            if !o.foot.isEmpty { foot(o.foot).padding(.top, -4) }
            SXSourceLine(kind: "sunny", text: source(o))
        }
        .animation(still ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.38), value: rg)
        .animation(still ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.38), value: lay)
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 14, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SXPaper(radius: 22))
    }

    // MARK: Header, price, chips

    private var header: some View {
        (Text(p.t).foregroundColor(SX.ink) + Text(" · " + p.co).foregroundColor(SX.muted))
            .sx(.question).lineLimit(1).truncationMode(.tail)
            .accessibilityAddTraits(.isHeader)
    }

    private var move: Double {
        let n = p.c.count, i0 = rg == "w" ? p.ix.w : rg == "m" ? p.ix.m : rg == "q" ? p.ix.q : 0
        guard n > 0, i0 >= 0, i0 < n, p.c[i0] > 0 else { return 0 }
        return p.c[n - 1] / p.c[i0] - 1
    }

    private var price: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(String(format: "$%.2f", p.c.last ?? p.px))
                .sx(SXType(size: 30, line: 34, weight: .bold, style: .title1, tracking: -0.025)).foregroundStyle(SX.ink)
            Text(SXC.pc(move) + " " + Self.over[rg]!)
                .sx(.question).foregroundStyle(move < 0 ? SX.down : SX.up)
        }
        .accessibilityElement(children: .combine)
    }

    /// The chips this range offers: Positions only for a held name, Value only where research is saved.
    private var available: [String] {
        let all = ["w": ["pos", "walls"], "m": ["tech", "pos"], "q": ["tech", "pos", "val"], "y": ["val", "tech"]][rg]!
        return all.filter { ($0 != "pos" || held) && ($0 != "val" || p.res != nil) }
    }
    private func layers(_ r: String) -> Set<String> {
        if let s = lay[r] { return s }
        switch r {
        case "w": return held ? ["pos", "walls"] : ["walls"]
        case "y": return ["val"]
        default: return ["tech"]
        }
    }
    private func on(_ k: String) -> Bool { available.contains(k) && layers(rg).contains(k) }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(available, id: \.self) { k in
                    let x = on(k)
                    Button {
                        var s = layers(rg)
                        if x { s.remove(k) } else { s.insert(k) }
                        lay[rg] = s
                    } label: {
                        Text(Self.chipName[k]!)
                            .sx(SXType(size: 14, line: 18, weight: .semibold, style: .subheadline, tracking: 0))
                            .foregroundStyle(x ? SX.paper : SX.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(x ? SX.ink : SX.fill, in: .capsule)
                            .animation(.easeOut(duration: 0.2), value: x)
                            .frame(height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.chipName[k]!)
                    .accessibilityValue(x ? "on" : "off")
                    .accessibilityAddTraits(.isToggle)
                }
            }
            .padding(.horizontal, 18)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What the chart shows")
    }

    // MARK: The sentence and the source

    private func foot(_ lines: [[SXChartBuild.Run]]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, runs in
                runs.enumerated().reduce(Text("")) { t, e in
                    t + Text((e.offset > 0 ? " " : "") + e.element.t).foregroundColor(e.element.c).fontWeight(e.element.w)
                }
                .sx(SXType(size: 15, line: 21, weight: .medium, style: .subheadline, tracking: 0))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func source(_ o: SXChartOut) -> String {
        var s = "Sunny · \(p.at)"
        if o.wallsOn { s += p.live == true ? " · walls Live" : " · walls" }
        if o.valOn, let r = p.res { s += " · " + r.src }
        return s
    }
}

// MARK: - The range control

/// Week · Month · Quarter · Year: one track, a thumb that slides to the pick in 0.38 s (none with Reduce Motion).
struct SXSegment: View {
    let items: [(String, String)]
    @Binding var pick: String
    let still: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { g in
            let w = (g.size.width - 4) / CGFloat(max(1, items.count)), i = CGFloat(items.firstIndex { $0.0 == pick } ?? 0)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(SX.segThumb)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(scheme == .dark ? 0.22 : 0.9), lineWidth: 0.5))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.12), radius: 4, y: 2)
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 1, y: 1)
                    .frame(width: w, height: 40)
                    .offset(x: 2 + i * w, y: 2)
                    .animation(still ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.38), value: pick)
                HStack(spacing: 0) {
                    ForEach(items, id: \.0) { k, l in
                        Button { pick = k } label: {
                            Text(l)
                                .sx(SXType(size: 14, line: 18, weight: k == pick ? .semibold : .medium, style: .subheadline, tracking: 0))
                                .foregroundStyle(SX.ink).lineLimit(1)
                                .frame(maxWidth: .infinity).frame(height: 40).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(k == pick ? [.isSelected] : [])
                    }
                }
                .padding(2)
            }
        }
        .frame(height: 44)
        .background(SX.segTrack, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How far back")
    }
}

// MARK: - The plot, drawn

/// Every mark in the chart's own terms: x as a share of the width, y in points from the top.
struct SXChartOut {
    struct Line { let pts: [CGPoint]; let c: Color; let w: CGFloat; var dash: [CGFloat] = [] }
    struct Fill { let pts: [CGPoint]; let c: Color }
    struct Box { let x0: CGFloat; let x1: CGFloat; let c: Color }
    enum Align { case leading, trailing, leadingAt(CGFloat), trailingAt(CGFloat), centerAt(CGFloat) }
    struct Label { let t: String; let y: CGFloat; let c: Color; let align: Align; var bg = true; var w: Font.Weight = .semibold }
    struct Dot { let x: CGFloat; let y: CGFloat; let s: CGFloat; let c: Color }
    struct Ax { let x: CGFloat; let t: String; let t2: String; let w: Font.Weight; let c: Color; let edge: Int }
    var H: CGFloat = 190
    var lines: [Line] = [], fills: [Fill] = [], boxes: [Box] = [], labels: [Label] = [], dots: [Dot] = [], ax: [Ax] = []
    var pill: (x: CGFloat, y: CGFloat, t: String)?
    var foot: [[SXChartBuild.Run]] = []
    var wallsOn = false, valOn = false
    var said = ""
}

struct SXChartPlot: View {
    let o: SXChartOut
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { g in
                let W = g.size.width
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        for b in o.boxes {
                            ctx.fill(Path(roundedRect: CGRect(x: b.x0 * size.width, y: 0, width: max(0, (b.x1 - b.x0) * size.width), height: o.H), cornerRadius: 6), with: .color(b.c))
                        }
                        for f in o.fills where f.pts.count > 2 {
                            var p = Path(); p.move(to: pt(f.pts[0], size.width)); f.pts.dropFirst().forEach { p.addLine(to: pt($0, size.width)) }; p.closeSubpath()
                            ctx.fill(p, with: .color(f.c))
                        }
                        for l in o.lines where l.pts.count > 1 {
                            var p = Path(); p.move(to: pt(l.pts[0], size.width)); l.pts.dropFirst().forEach { p.addLine(to: pt($0, size.width)) }
                            ctx.stroke(p, with: .color(l.c), style: StrokeStyle(lineWidth: l.w, lineCap: .round, lineJoin: .round, dash: l.dash))
                        }
                    }
                    ForEach(Array(o.labels.enumerated()), id: \.offset) { _, l in label(l, W) }
                    ForEach(Array(o.dots.enumerated()), id: \.offset) { _, d in
                        Circle().fill(d.c).frame(width: d.s, height: d.s)
                            .background(Circle().fill(SX.paper).frame(width: d.s + 5, height: d.s + 5))
                            .position(x: d.x * W, y: d.y)
                    }
                    if let pl = o.pill {
                        let right = pl.x > 0.8
                        Text(pl.t).sx(SXType(size: 12, line: 14, weight: .bold, style: .caption1, tracking: 0))
                            .foregroundStyle(SX.paper)
                            .padding(.horizontal, 8).frame(height: 22)
                            .background(SX.ink, in: .capsule)
                            .fixedSize()
                            .frame(width: W, alignment: right ? .trailing : .leading)
                            .offset(x: right ? pl.x * W - 10 - W : pl.x * W + 10, y: pl.y - 11)
                    }
                }
            }
            .frame(height: o.H)
            axis
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(o.said)
    }

    private func pt(_ p: CGPoint, _ w: CGFloat) -> CGPoint { CGPoint(x: p.x * w, y: p.y) }

    /// A label sits above its line (its bottom on the y given), on a patch of paper so lines never cross it.
    @ViewBuilder private func label(_ l: SXChartOut.Label, _ W: CGFloat) -> some View {
        let t = Text(l.t).sx(SXType(size: 12, line: 14, weight: l.w, style: .caption1, tracking: 0)).foregroundStyle(l.c)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, l.bg ? 4 : 0)
            .background(l.bg ? SX.paper : .clear, in: .rect(cornerRadius: 6))
        switch l.align {
        case .leading: t.frame(width: W, alignment: .leading).offset(y: l.y - 14)
        case .trailing: t.frame(width: W, alignment: .trailing).offset(y: l.y - 14)
        case .centerAt(let x): t.position(x: x * W, y: l.y - 7)
        case .leadingAt(let x): t.frame(width: W, alignment: .leading).offset(x: x * W - 10, y: l.y - 14)
        case .trailingAt(let x): t.frame(width: W, alignment: .trailing).offset(x: x * W + 10 - W, y: l.y - 14)
        }
    }

    private var axis: some View {
        GeometryReader { g in
            let W = g.size.width
            ZStack(alignment: .topLeading) {
                ForEach(Array(o.ax.enumerated()), id: \.offset) { _, a in
                    let al: HorizontalAlignment = a.edge < 0 ? .leading : a.edge > 0 ? .trailing : .center
                    VStack(alignment: al, spacing: 0) {
                        Text(a.t).sx(SXType(size: 12, line: 15, weight: a.w, style: .caption1, tracking: 0)).foregroundStyle(a.c)
                        if !a.t2.isEmpty { Text(a.t2).sx(SXType(size: 12, line: 15, weight: .semibold, style: .caption1, tracking: 0)).foregroundStyle(SX.ink) }
                    }
                    .lineLimit(1).fixedSize()
                    .frame(width: W, alignment: a.edge < 0 ? .leading : a.edge > 0 ? .trailing : .center)
                    .offset(x: a.edge < 0 ? a.x * W : a.edge > 0 ? a.x * W - W : a.x * W - W / 2)
                }
            }
        }
        .frame(height: 30)
    }
}

// MARK: - Formats

enum SXC {
    /// A move with no sign: 18.7%.
    static func pc(_ v: Double) -> String { String(format: "%.1f%%", abs(v * 100)) }
    /// A strike as the design writes it: 36, 39.5, 37.25.
    static func k(_ x: Double) -> String {
        x == x.rounded() ? String(Int(x)) : String(format: "%g", (x * 100).rounded() / 100)
    }
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    /// "2026-10-05" as (year, month 0-11, day, weekday 0 Sunday).
    static func parts(_ iso: String) -> (y: Int, mo: Int, d: Int, wd: Int) {
        let a = iso.split(separator: "-").compactMap { Int($0) }
        guard a.count == 3 else { return (0, 0, 0, 0) }
        var c = DateComponents(); c.year = a[0]; c.month = a[1]; c.day = a[2]; c.hour = 12
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let wd = cal.date(from: c).map { cal.component(.weekday, from: $0) - 1 } ?? 0
        return (a[0], a[1] - 1, a[2], wd)
    }
}

// MARK: - What the chart shows, worked out

/// The reference's simWeek and simTrend, line for line: one range's marks, labels, axis and sentence.
struct SXChartBuild {
    struct Run { let t: String; let c: Color; let w: Font.Weight }
    let p: SXChart, rg: String, on: (String) -> Bool

    var out: SXChartOut {
        var o = rg == "w" ? week() : trend()
        let mv = move, mc = mv < 0 ? SX.down : SX.up
        // The price line and today's dot take the colour of the move over the range.
        o.lines = o.lines.map { $0.w == 2 ? .init(pts: $0.pts, c: mc, w: 2) : $0 }
        o.dots = o.dots.map { $0.s == 9 ? .init(x: $0.x, y: $0.y, s: 9, c: mc) : $0 }
        let head = "\(p.t) \(["w": "this week", "m": "over the month", "q": "over the quarter", "y": "over the year"][rg]!): " +
            (mv < 0 ? "down " : "up ") + SXC.pc(mv) + " at " + String(format: "%.2f", p.c.last ?? p.px)
        o.said = ([head] + o.foot.map { $0.map(\.t).joined(separator: " ") }).joined(separator: ". ")
        return o
    }

    private var move: Double {
        let n = p.c.count, i0 = rg == "w" ? p.ix.w : rg == "m" ? p.ix.m : rg == "q" ? p.ix.q : 0
        guard n > 0, i0 >= 0, i0 < n, p.c[i0] > 0 else { return 0 }
        return p.c[n - 1] / p.c[i0] - 1
    }

    /// The scale: the values' span with 7% spare each side, top and bottom padding in points.
    private func scale(_ v: [Double], _ H: CGFloat, _ pt: CGFloat, _ pb: CGFloat) -> (lo: Double, hi: Double, y: (Double) -> CGFloat) {
        var lo = v.min() ?? 0, hi = v.max() ?? 1
        let sp = hi - lo > 0 ? hi - lo : 1
        lo -= sp * 0.07; hi += sp * 0.07
        return (lo, hi, { p in pt + CGFloat((hi - p) / (hi - lo)) * (H - pt - pb) })
    }

    /// Labels pushed apart so none overlap: at least 15 from the top, each `gap` below the last, none past the bottom.
    private func spread(_ L: [SXChartOut.Label], _ H: CGFloat, _ gap: CGFloat) -> [SXChartOut.Label] {
        var a = L.sorted { $0.y < $1.y }.map { SXChartOut.Label(t: $0.t, y: max(15, $0.y), c: $0.c, align: $0.align, bg: $0.bg, w: $0.w) }
        func set(_ i: Int, _ y: CGFloat) { a[i] = .init(t: a[i].t, y: y, c: a[i].c, align: a[i].align, bg: a[i].bg, w: a[i].w) }
        for i in a.indices.dropFirst() where a[i].y - a[i - 1].y < gap { set(i, a[i - 1].y + gap) }
        if let last = a.last, last.y - (H - 1) > 0 {
            set(a.count - 1, last.y - (last.y - (H - 1)))
            for i in stride(from: a.count - 2, through: 0, by: -1) where a[i + 1].y - a[i].y < gap { set(i, a[i + 1].y - gap) }
        }
        return a
    }

    // MARK: Week

    private func week() -> SXChartOut {
        var o = SXChartOut(); o.H = 200
        let H: CGFloat = 200, pos = on("pos"), walls = on("walls")
        let pts = p.week.pts.map { (x: CGFloat($0[0]), p: $0[1]) }
        let px = p.c.last ?? p.px, xT = pts.last?.x ?? 0
        let sold = pos ? p.sold : []
        let W = walls ? p.walls : []
        let sc = scale(pts.map(\.p) + sold.map(\.k) + W.map(\.k), H, 14, 8), Y = sc.y
        if p.week.today >= 0 { o.boxes.append(.init(x0: xT, x1: 1, c: SX.left)) }
        // One line per level: a sold strike reads "Your 36 calls", a wall on it adds its name and colour.
        var lev: [(k: Double, t: String, c: Color)] = sold.map { ($0.k, "Your \(SXC.k($0.k)) " + ($0.cp == "c" ? "calls" : "puts"), SX.ink) }
        for w in W {
            let col = w.lb == "Ceiling" ? SX.call : SX.put
            if let i = lev.firstIndex(where: { $0.k == w.k }) { lev[i].t += " · " + w.lb; lev[i].c = col }
            else { lev.append((w.k, "\(w.lb) \(SXC.k(w.k))", col)) }
        }
        var labs: [SXChartOut.Label] = []
        for l in lev {
            o.lines.append(.init(pts: [CGPoint(x: 0, y: Y(l.k)), CGPoint(x: 1, y: Y(l.k))], c: l.c, w: 1.5))
            labs.append(.init(t: l.t, y: Y(l.k) - 1, c: l.c, align: .trailing))
        }
        o.labels = spread(labs, H, 17)
        o.lines.append(.init(pts: pts.map { CGPoint(x: $0.x, y: Y($0.p)) }, c: SX.ink, w: 2))
        o.dots.append(.init(x: xT, y: Y(px), s: 9, c: SX.ink))
        o.pill = (xT, Y(px), String(format: "%.2f", px))
        o.ax = p.week.days.enumerated().map { i, d in
            let today = i == p.week.today
            let t2 = today ? "Today" : d.closed ? "Closed" : i == p.week.exp && !p.sold.isEmpty ? "Expiry" : ""
            return .init(x: (CGFloat(i) + 0.5) / 5, t: d.lab, t2: t2, w: today ? .bold : .medium, c: today ? SX.ink : SX.muted, edge: 0)
        }
        // Under the chart: what is captured against the pace, or where the price sits between the walls.
        if !sold.isEmpty, let cap = p.cap {
            if cap.pct >= 0 {
                let tag = cap.tag ?? "on pace"
                o.foot.append([Run(t: "\(cap.pct)% captured", c: SX.ink, w: .bold), Run(t: "· " + tag, c: tag == "behind pace" ? SX.thin : SX.up, w: .semibold)])
            } else if let s = sold.max(by: { abs(px - $0.k) > abs(px - $1.k) }) {
                // Worth more than sold: how far through the strike the price sits (not in the design, 30 Oct).
                o.foot.append([Run(t: SXC.pc(abs(px / s.k - 1)) + (s.cp == "c" ? " over" : " under") + " your \(SXC.k(s.k)) " + (s.cp == "c" ? "calls" : "puts"), c: SX.down, w: .bold)])
            }
        } else if !W.isEmpty {
            let ce = W.first { $0.lb == "Ceiling" }, fl = W.first { $0.lb == "Floor" }
            let t = ce.map { px > $0.k } == true ? "Above the Ceiling" : fl.map { px < $0.k } == true ? "Below the Floor"
                : ce != nil && fl != nil ? "Between the Floor and the Ceiling" : ce != nil ? "Under the Ceiling" : "Above the Floor"
            o.foot.append([Run(t: t, c: SX.ink, w: .semibold)])
        }
        o.wallsOn = walls
        return o
    }

    // MARK: Month, Quarter, Year

    private func trend() -> SXChartOut {
        var o = SXChartOut(); o.H = 190
        let yr = rg == "y", i0 = rg == "m" ? p.ix.m : rg == "q" ? p.ix.q : 0
        let cs = Array(p.c[i0...]), L = cs.count, px = cs.last ?? p.px, H: CGFloat = 190, xe: CGFloat = 0.96
        let XI = { (i: Int) in CGFloat(i) / CGFloat(max(1, L - 1)) * xe }
        let mk = yr ? 200 : 50, A = yr ? p.ma200 : p.ma50, ma = Array(A[i0...])
        let tech = on("tech"), pos = on("pos"), val = on("val")
        var vals = cs + ma.compactMap { $0 }
        if held && !yr { vals += p.legs.map(\.k) }
        let sc = scale(vals, H, yr ? 30 : 14, yr ? 26 : 8), Y = sc.y
        let ptsC = cs.enumerated().map { CGPoint(x: XI($0.offset), y: Y($0.element)) }
        let dist = { (v: Double) in "\(Int((abs(v / px - 1) * 100).rounded()))% " + (v >= px ? "above" : "below") }
        var labs: [SXChartOut.Label] = [], foot: [[Run]] = []

        if pos {
            let col = ["LEAPS": SX.ink, "Hedge": SX.call, "Insurance": SX.put]
            if let k = p.leapsK {
                o.fills.append(.init(pts: cs.enumerated().map { CGPoint(x: XI($0.offset), y: Y(max($0.element, k))) }
                    + [CGPoint(x: xe, y: Y(k)), CGPoint(x: 0, y: Y(k))], c: SX.upTint))
                foot.append([Run(t: "LEAPS", c: SX.muted, w: .medium),
                             Run(t: "\(Int(((px / k - 1) * 100).rounded()))% in the money", c: px > k ? SX.up : SX.down, w: .bold)])
            }
            for l in p.legs {
                let c = col[l.g] ?? SX.ink
                o.lines.append(.init(pts: [CGPoint(x: 0, y: Y(l.k)), CGPoint(x: xe, y: Y(l.k))], c: c, w: 1.5))
                labs.append(.init(t: "\(l.g) \(SXC.k(l.k))", y: Y(l.k) - 1, c: c, align: .leading))
            }
        }
        var xm: (j: Int, up: Bool, d: String)?
        if tech, let m0 = ma.first(where: { $0 != nil }) ?? nil {
            let mpts = ma.enumerated().compactMap { i, v in v.map { CGPoint(x: XI(i), y: Y($0)) } }
            o.lines.append(.init(pts: mpts, c: SX.muted, w: 1.5))
            labs.append(.init(t: "\(mk)-day", y: Y(m0) - 1, c: SX.muted, align: .leading))
            // The last time the price crossed its average inside the range: a dot with its date.
            if p.mark == "cross" {
                var i = p.c.count - 1
                while i > i0 {
                    guard let a1 = A[i], let a0 = A[i - 1] else { break }
                    if (p.c[i] > a1) != (p.c[i - 1] > a0) {
                        let d = SXC.parts(p.d[i]); xm = (i - i0, p.c[i] > a1, "\(SXC.months[d.mo]) \(d.d)"); break
                    }
                    i -= 1
                }
            }
            let r = p.rsi ?? 50, hot = r > 70 || r < 30, last = ma.last.flatMap { $0 } ?? px
            foot.insert([Run(t: (px >= last ? "Above" : "Below") + " its \(mk)-day" + (xm.map { " since " + $0.d } ?? ""), c: SX.ink, w: .bold),
                         Run(t: "· RSI \(Int(r.rounded())), " + (r > 70 ? "overbought" : r < 30 ? "oversold" : "neutral"), c: hot ? SX.thin : SX.muted, w: .medium)], at: 0)
        }
        if val, let res = p.res {
            func lvl(_ v: Double, _ t: String, _ dash: [CGFloat]) {
                if v > sc.hi || v < sc.lo {
                    let up = v > sc.hi
                    labs.append(.init(t: (up ? "↑ " : "↓ ") + t, y: up ? 15 : H - 1, c: SX.research, align: .leading))
                } else {
                    o.lines.append(.init(pts: [CGPoint(x: 0, y: Y(v)), CGPoint(x: xe, y: Y(v))], c: SX.research, w: 1.5, dash: dash))
                    labs.append(.init(t: t, y: Y(v) - 1, c: SX.research, align: .leading))
                }
            }
            lvl(res.an, "Analysts " + String(format: "%.2f", res.an), [5, 4])
            lvl(res.fv, "Fair value " + String(format: "%.2f", res.fv), [])
            let tone = { (v: Double) in v >= px ? SX.up : SX.down }
            foot.insert([Run(t: "Analysts", c: SX.muted, w: .medium), Run(t: dist(res.an), c: tone(res.an), w: .bold),
                         Run(t: "· fair value", c: SX.muted, w: .medium), Run(t: dist(res.fv), c: tone(res.fv), w: .bold)], at: 0)
        }
        o.lines.append(.init(pts: ptsC, c: SX.ink, w: 2))
        o.dots.append(.init(x: xe, y: Y(px), s: 9, c: SX.ink))

        // The axis: Mondays on Month, month starts on Quarter, quarter months on Year; the cross; Today at the end.
        let xp = xm.map { XI($0.j) }
        if let xm, let xp {
            o.lines.append(.init(pts: [CGPoint(x: xp, y: 0), CGPoint(x: xp, y: H)], c: SX.muted, w: 1, dash: [2, 3]))
            o.dots.append(.init(x: xp, y: Y(cs[xm.j]), s: 11, c: SX.ink))
        }
        var last: CGFloat = -99
        let ds = p.d[i0...].map(SXC.parts)
        for (i, d) in ds.enumerated() {
            let pp = XI(i) * 100
            let first = rg == "m" ? d.wd == 1 : i > 0 && d.mo != ds[i - 1].mo && (!yr || d.mo % 3 == 0)
            if !first || pp - last < (yr ? 14 : 11) || pp > 82 || (xp.map { abs(pp - $0 * 100) < 13 } ?? false) { continue }
            last = pp
            let t = rg == "m" ? "\(SXC.months[d.mo]) \(d.d)" : SXC.months[d.mo] + (d.mo == 0 ? " ’" + String(d.y % 100) : "")
            o.ax.append(.init(x: XI(i), t: t, t2: "", w: .medium, c: SX.muted, edge: pp < 4 ? -1 : 0))
        }
        if let xm, let xp { o.ax.append(.init(x: xp, t: xm.d, t2: xm.up ? "Crossed above" : "Crossed below", w: .bold, c: SX.ink, edge: 0)) }
        o.ax.append(.init(x: 1, t: "Today", t2: "", w: .bold, c: SX.ink, edge: 1))

        o.labels = spread(labs, H, 18)
        // Year: the 52-week high and low, always on, as dots on the line with their prices.
        if yr, let hi = cs.indices.max(by: { cs[$0] < cs[$1] }), let lo = cs.indices.min(by: { cs[$0] < cs[$1] }) {
            for (i, word, below) in [(hi, "high", false), (lo, "low", true)] {
                let x = XI(i)
                o.dots.append(.init(x: x, y: Y(cs[i]), s: 7, c: SX.ink))
                let y = below ? Y(cs[i]) + 9 + 14 : Y(cs[i]) - 9
                let al: SXChartOut.Align = x * 100 < 18 ? .leadingAt(x) : x * 100 > 82 ? .trailingAt(x) : .centerAt(x)
                o.labels.append(.init(t: "52-week \(word) " + String(format: "%.2f", cs[i]), y: y, c: SX.ink, align: al))
            }
            let up = px / cs[lo] - 1, dn = 1 - px / cs[hi]
            foot.append([Run(t: "\(Int((dn * 100).rounded()))% under the 52-week high", c: SX.ink, w: .bold),
                         Run(t: "· \(Int((up * 100).rounded()))% over the low", c: SX.muted, w: .medium)])
        }
        o.foot = foot
        o.valOn = val
        return o
    }

    private var held: Bool { !p.sold.isEmpty || !p.legs.isEmpty }
}
