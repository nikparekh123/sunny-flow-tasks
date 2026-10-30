//
//  SearchBook.swift
//  Sunny
//
//  Your book (block 29, handoff Oct 30 2026): every name at once, one row each, one range control for all. The list
//  opens first (ticker, the nearest thing that needs him, a small chart, price and move); small charts, one per row,
//  when he asks for charts. The row that needs him is on top: on Week the closest sold strike (else the Ceiling), on
//  Month and Quarter the furthest under the 50-day, on Year the biggest drop. A tap asks for that name's chart on the
//  same range, as the next answer in the thread.
//

import SwiftUI

/// What sunny-search sends: each name's year of closes, its 50-day, this week's line, its sold strikes and Ceiling.
struct SXBook: Decodable, Equatable {
    struct Name: Decodable, Equatable {
        struct Week: Decodable, Equatable { let today: Int; let pts: [[Double]] }
        let t: String, co: String
        let d: [String], c: [Double], ma50: [Double?]
        let ix: SXChart.Ix
        let week: Week
        let sold: [SXChart.Sold]
        let ceil: Double?
    }
    /// list or grid
    let view: String, range: String
    let names: [Name]
    let at: String
}

extension SX {
    /// A small chart's tile.
    static let tile = S.dynA(0x1D1D1F, 0.035, 0xFFFFFF, 0.05)
}

struct SXBookCard: View {
    let p: SXBook
    let ask: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var still
    @State private var rg: String

    init(p: SXBook, ask: @escaping (String) -> Void) {
        self.p = p
        self.ask = ask
        _rg = State(initialValue: ["w", "m", "q", "y"].contains(p.range) ? p.range : "w")
    }

    private static let order = ["w": "Closest to a strike first", "m": "Furthest under the 50-day first",
                                "q": "Furthest under the 50-day first", "y": "Biggest drop first"]
    private static let when = ["w": "this week", "m": "this month", "q": "this quarter", "y": "this year"]

    var body: some View {
        let rows = p.names.map { SXBookRow($0, rg) }.sorted { $0.ord < $1.ord }
        VStack(alignment: .leading, spacing: 14) {
            (Text("Your book").foregroundColor(SX.ink) + Text(" · \(p.names.count) names").foregroundColor(SX.muted))
                .sx(.question).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            SXSegment(items: [("w", "Week"), ("m", "Month"), ("q", "Quarter"), ("y", "Year")], pick: $rg, still: still)
                .padding(.top, -4)
            Group {
                if p.view == "grid" { grid(rows) } else { list(rows).padding(.top, -6).padding(.bottom, -4) }
            }
            .id(rg)
            .transition(.opacity)
            Text(Self.order[rg]! + " · tap a name for its chart")
                .sx(SXType(size: 15, line: 21, weight: .medium, style: .subheadline, tracking: 0)).foregroundStyle(SX.muted)
                .padding(.top, -4)
            SXSourceLine(kind: "sunny", text: "Sunny · \(p.at)")
        }
        .animation(still ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.38), value: rg)
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 14, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SXPaper(radius: 22))
    }

    private func open(_ r: SXBookRow) { ask("How’s \(r.t) doing \(Self.when[rg]!)?") }

    // MARK: The list

    private func list(_ rows: [SXBookRow]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.t) { i, r in
                Button { open(r) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.t).sx(SXType(size: 17, line: 22, weight: .bold, style: .body, tracking: 0)).foregroundStyle(SX.ink)
                            Text(r.st).sx(SXType(size: 13, line: 17, weight: .medium, style: .footnote, tracking: 0)).foregroundStyle(r.stC)
                                .lineLimit(1).truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        SXMini(r: r, H: 34, pt: 4, pb: 4, grid: false).frame(width: 64, height: 34)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(String(format: "$%.2f", r.px)).sx(.question).foregroundStyle(SX.ink)
                            Text(SXC.pc(r.mv)).sx(SXType(size: 13, line: 17, weight: .semibold, style: .footnote, tracking: 0))
                                .foregroundStyle(r.mv < 0 ? SX.down : SX.up)
                        }
                        .lineLimit(1).fixedSize()
                        .frame(width: 66, alignment: .trailing)
                    }
                    .frame(minHeight: 56)
                    .padding(.vertical, 8)
                    .contentShape(.rect)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(SX.line).frame(height: 1) } }
                }
                .buttonStyle(SXTextPress())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(r.aria)
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    // MARK: Small charts, one per row

    private func grid(_ rows: [SXBookRow]) -> some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.t) { r in
                Button { open(r) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            (Text(r.t).fontWeight(.bold).foregroundColor(SX.ink) + Text(" " + String(format: "$%.2f", r.px)).fontWeight(.medium).foregroundColor(SX.muted))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(SXC.pc(r.mv)).fontWeight(.bold).foregroundStyle(r.mv < 0 ? SX.down : SX.up)
                        }
                        .sx(SXType(size: 17, line: 22, weight: .bold, style: .body, tracking: 0))
                        SXMini(r: r, H: 56, pt: 5, pb: 5, grid: true).frame(height: 56)
                        Text(r.st).sx(SXType(size: 14, line: 18, weight: .semibold, style: .subheadline, tracking: 0)).foregroundStyle(r.stC)
                    }
                    .padding(EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14))
                    .background(SX.tile, in: .rect(cornerRadius: 16, style: .continuous))
                    .contentShape(.rect)
                }
                .buttonStyle(SXTextPress())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(r.aria)
                .accessibilityAddTraits(.isButton)
            }
        }
    }
}

/// One name on one range: its line, the strike or average behind it, the status line and the order key.
struct SXBookRow {
    let t: String, px: Double, mv: Double, ord: Double
    /// Across 0 to 1, and the price.
    let raw: [(x: Double, p: Double)]
    /// A level (the nearest strike, or the Ceiling) or the 50-day as a line.
    let ref: Double?, refL: [Double]?
    let st: String, stC: Color
    /// Where the week's days left start (1 off Week).
    let dl: Double
    let aria: String

    init(_ n: SXBook.Name, _ rg: String) {
        t = n.t
        let cs = n.c, k = cs.count, px = cs.last ?? 0
        self.px = px
        let i0 = rg == "w" ? n.ix.w : rg == "m" ? n.ix.m : rg == "q" ? n.ix.q : 0
        mv = i0 >= 0 && i0 < k && cs[i0] > 0 ? px / cs[i0] - 1 : 0
        var st = "", stC = SX.muted, ord = 0.0, ref: Double? = nil, refL: [Double]? = nil
        if rg == "w" {
            raw = n.week.pts.map { (x: $0[0], p: $0[1]) }
            dl = n.week.today >= 0 ? (raw.last?.x ?? 1) : 1
            let near = n.sold.map { (s: $0, d: $0.cp == "c" ? ($0.k - px) / px : (px - $0.k) / px) }.min { $0.d < $1.d }
            if let near {
                let nm = SXC.k(near.s.k) + (near.s.cp == "c" ? " calls" : " puts")
                ref = near.s.k; ord = near.d
                st = near.d < 0 ? (near.s.cp == "c" ? "Above your " : "Below your ") + nm : SXC.pc(near.d) + (near.s.cp == "c" ? " under " : " over ") + nm
                stC = near.d < 0 ? SX.down : near.d < 0.015 ? SX.thin : SX.muted
            } else if let ce = n.ceil {
                let d = (ce - px) / px
                ref = ce; ord = d
                st = d < 0 ? "Above the Ceiling" : SXC.pc(d) + " under the Ceiling"
                stC = d < 0.015 ? SX.thin : SX.muted
            } else { st = "Nothing sold"; ord = 1 }
        } else {
            let part = Array(cs[min(max(0, i0), k)...])
            raw = part.enumerated().map { (x: Double($0.offset) / Double(max(1, part.count - 1)), p: $0.element) }
            dl = 1
            if rg == "y" {
                let hi = part.max() ?? px, dn = 1 - px / hi
                st = dn < 0.05 ? "Near the 52-week high" : "\(Int((dn * 100).rounded()))% under 52-week high"
                ord = mv
            } else if let m = n.ma50.last ?? nil {
                let d = px / m - 1
                refL = Array(n.ma50[min(max(0, i0), k)...]).compactMap { $0 }
                st = SXC.pc(d) + (d >= 0 ? " above the 50-day" : " below the 50-day")
                ord = d
            }
        }
        self.st = st; self.stC = stC; self.ord = ord; self.ref = ref; self.refL = refL
        aria = "\(n.co), \(st), " + (mv < 0 ? "down " : "up ") + SXC.pc(mv)
    }
}

/// A row's small chart: the line in the colour of its move, the level dashed, the week's days left shaded.
private struct SXMini: View {
    let r: SXBookRow, H: CGFloat, pt: CGFloat, pb: CGFloat, grid: Bool
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let vals = r.raw.map(\.p) + (r.ref.map { [$0] } ?? []) + (r.refL ?? [])
            let lo = vals.min() ?? 0, hi = vals.max() ?? 1
            let Y = { (p: Double) in pt + CGFloat((hi - p) / (hi - lo > 0 ? hi - lo : 1)) * (H - pt - pb) }
            if r.dl < 1 {
                ctx.fill(Path(roundedRect: CGRect(x: r.dl * w, y: 0, width: (1 - r.dl) * w, height: H), cornerRadius: grid ? 6 : 4), with: .color(SX.left))
            }
            var g = Path()
            if let k = r.ref { g.move(to: CGPoint(x: 0, y: Y(k))); g.addLine(to: CGPoint(x: w, y: Y(k))) }
            else if let L = r.refL, L.count > 1 {
                for (i, v) in L.enumerated() {
                    let p = CGPoint(x: Double(i) / Double(L.count - 1) * w, y: Y(v))
                    if i == 0 { g.move(to: p) } else { g.addLine(to: p) }
                }
            }
            ctx.stroke(g, with: .color(SX.muted), style: StrokeStyle(lineWidth: grid ? 1.25 : 1, dash: grid ? [4, 3] : [3, 3]))
            var l = Path()
            for (i, q) in r.raw.enumerated() {
                let p = CGPoint(x: q.x * w, y: Y(q.p))
                if i == 0 { l.move(to: p) } else { l.addLine(to: p) }
            }
            ctx.stroke(l, with: .color(r.mv < 0 ? SX.down : SX.up), style: StrokeStyle(lineWidth: grid ? 2 : 1.75, lineCap: .round, lineJoin: .round))
            if grid, let last = r.raw.last {
                let c = CGPoint(x: last.x * w, y: Y(last.p))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(SX.paper))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(SX.ink))
            }
        }
        .accessibilityHidden(true)
    }
}
