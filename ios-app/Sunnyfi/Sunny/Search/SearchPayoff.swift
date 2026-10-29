//
//  SearchPayoff.swift
//  Sunny
//
//  The payoff card (block 28, handoff Oct 29 2026): the first picture in Search. Price across, dollars up: what
//  each price by Friday adds or costs. One name with every leg a chip (tap one to take it out) and the walls on the
//  price line; what was sold alone, from the sale; or the book, every name moved by the same %, with a chip per
//  name. Dots at 1 SD down, today and 1 SD up carry their numbers on the line; press and slide to read any price.
//  sunny-search sends every leg (strike, days left, contracts, IV, value today, price paid) and the card does the
//  sums itself with the server's Black-Scholes, so a chip redraws the line at once and the sentence above agrees.
//

import SwiftUI
import UIKit

/// What sunny-search sends for the card: the mode, the day it runs to, and each name's legs.
struct SXPayoff: Decodable, Equatable {
    struct Leg: Decodable, Equatable {
        /// sc sold calls · sp sold puts · lp LEAPS · hc hedge calls · ip insurance puts
        let g: String
        let cp: String
        let k: Double
        /// Days to expiry from the answer, and to the card's close (d0).
        let T: Double
        /// Contracts, sold negative.
        let n: Double
        let v: Double
        let now: Double
        let paid: Double
    }
    struct Chip: Decodable, Equatable { let g: String; let t: String }
    struct Wall: Decodable, Equatable { let k: Double; let side: String; let label: String; let conf: Int?; let dash: Bool }
    struct Name: Decodable, Equatable {
        let t: String
        let px: Double
        let iv: Double
        let reports: String?
        let chips: [Chip]
        let walls: [Wall]
        let legs: [Leg]
    }
    /// one | sold | book
    let mode: String
    /// "Fri Oct 30"
    let by: String
    /// Friday, or Thursday when the market is shut that Friday.
    let word: String
    let d0: Double
    let names: [Name]
    /// "3:42 PM" while the market is open, else "Wed 4:00 PM close".
    let at: String
}

// MARK: - The sums (the server's, line for line)

enum SXPay {
    static let rate = 0.04
    static func N(_ x: Double) -> Double {
        let t = 1 / (1 + 0.2316419 * abs(x)), d = 0.3989423 * exp(-x * x / 2)
        let p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))))
        return x > 0 ? 1 - p : p
    }
    static func bs(_ S: Double, _ K: Double, _ days: Double, _ v: Double, _ call: Bool) -> Double {
        if days <= 0 { return call ? max(0, S - K) : max(0, K - S) }
        let T = days / 365, sq = v * T.squareRoot(), d1 = (log(S / K) + (rate + v * v / 2) * T) / sq, d2 = d1 - sq, df = exp(-rate * T)
        return call ? S * N(d1) - K * df * N(d2) : K * df * N(-d2) - S * N(-d1)
    }
    /// What a price by the close adds or costs: from today, or from the sale.
    static func pnl(_ L: [SXPayoff.Leg], _ S: Double, _ d0: Double, sale: Bool) -> Double {
        L.reduce(0) { $0 + $1.n * 100 * (bs(S, $1.k, $1.T - d0, $1.v, $1.cp == "c") - (sale ? $1.paid : $1.now)) }
    }
    static func zeros(_ f: (Double) -> Double, _ lo: Double, _ hi: Double) -> [Double] {
        var out: [Double] = [], ps = lo, pv = f(lo)
        for i in 1...240 {
            let s = lo + (hi - lo) * Double(i) / 240, v = f(s)
            if (pv < 0) != (v < 0) { out.append(ps + (s - ps) * (pv / (pv - v))) }
            pv = v; ps = s
        }
        return out
    }
    /// The chart's half-width as a share of the price: 5% at least, 1.9 priced moves, every sold strike with 2.5% spare, 15% at most.
    static func span(_ px: Double, _ m: Double, _ L: [SXPayoff.Leg]) -> Double {
        min(0.15, L.filter { $0.n < 0 }.reduce(max(0.05, 1.9 * m)) { max($0, abs($1.k / px - 1) + 0.025) })
    }
    static func nice(_ x: Double) -> Double {
        let p = pow(10, floor(log10(x))), m = x / p
        return (m < 1.5 ? 1 : m < 3 ? 2 : m < 7 ? 5 : 10) * p
    }
    /// Dollars to the nearest $10, no sign: red says it costs.
    static func usd(_ v: Double) -> String { "$" + Int((abs(v) / 10).rounded() * 10).formatted(.number.grouping(.automatic)) }
    static func k(_ x: Double) -> String { x == x.rounded() ? String(Int(x)) : String(format: "%.2f", x) }
    static func px(_ x: Double) -> String { String(format: "%.2f", x) }
}

// MARK: - Colours (block 28)

extension SX {
    /// The payoff line: green where it pays, red where it costs.
    static let payUp = S.dyn(0x1BA94C, 0x34D35B)
    static let payDown = S.dyn(0xEE3B3B, 0xFF5A4F)
    /// The move priced in by Friday.
    static let cone = S.dynA(0x1D1D1F, 0.055, 0xFFFFFF, 0.07)
    static let grid = S.dynA(0x1D1D1F, 0.05, 0xFFFFFF, 0.06)
    static let zero = S.dynA(0x1D1D1F, 0.26, 0xFFFFFF, 0.30)
    /// Each name behind the book's line.
    static let leg = S.dynA(0x1D1D1F, 0.30, 0xFFFFFF, 0.34)
    /// Text on a number: the app's shades, so it passes 4.5:1.
    static func value(_ v: Double) -> Color { v >= 5 ? up : v <= -5 ? down : ink }
}

// MARK: - The card

struct SXPayoffCard: View {
    let p: SXPayoff

    /// Leg kinds taken out (one name).
    @State private var off: Set<String> = []
    /// The book: All, or a name picked.
    @State private var pick = "All"
    /// A finger on the chart, 0 to 1 across.
    @State private var sx: Double?

    private var book: Bool { p.mode == "book" }
    private var name: SXPayoff.Name? { book ? p.names.first { $0.t == pick } : p.names.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if book { names.padding(.top, -8).padding(.bottom, -10) }
            if p.mode == "one", let n = name { chips(n).padding(.top, -8).padding(.bottom, -10) }
            if let n = name { plotView(one(n)) } else { plotView(all()) }
            SXFlowLegend(items: legend)
            SXSourceLine(kind: "sunny", text: source)
        }
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 14, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SXPaper(radius: 22))
    }

    // MARK: Header and chips

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            (Text(name?.t ?? "Book").foregroundColor(SX.ink) + Text(" · " + title).foregroundColor(SX.muted))
                .sx(.question).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(p.by).sx(.time.weighted(.semibold)).foregroundStyle(SX.muted).fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var title: String {
        guard p.mode == "sold", let n = name else { return "Payoff by \(p.word)" }
        let s = n.legs.filter { $0.n < 0 }
        return s.allSatisfy { $0.cp == "c" } ? "Sold calls" : s.allSatisfy { $0.cp == "p" } ? "Sold puts" : "What you sold"
    }

    /// One chip per kind of leg, ink when on, gray when off. The last leg on cannot go off.
    private func chips(_ n: SXPayoff.Name) -> some View {
        SXFlow(spacing: 6) {
            ForEach(n.chips, id: \.g) { c in
                let on = !off.contains(c.g)
                Button {
                    var o = off
                    if on { o.insert(c.g) } else { o.remove(c.g) }
                    if n.chips.allSatisfy({ o.contains($0.g) }) { return }
                    off = o
                    sx = nil
                } label: { SXPayChip(text: c.t, on: on) }
                .buttonStyle(.plain)
                .accessibilityLabel(c.t)
                .accessibilityValue(on ? "on" : "off")
                .accessibilityAddTraits(.isToggle)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Legs on the chart")
    }

    /// All, then each name; they scroll sideways to the card's edges.
    private var names: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(["All"] + p.names.map(\.t), id: \.self) { t in
                    Button { pick = t; sx = nil } label: { SXPayChip(text: t, on: pick == t) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(pick == t ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 18)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -18)
        .accessibilityLabel("Which name")
    }

    // MARK: Legend and source

    private var legend: [SXFlowLegend.Item] {
        guard let n = name else {
            return [.line(SX.ink, 2, "Book, every name moving the same %"), .line(SX.leg, 1.5, "Each name")]
        }
        let m = n.iv * (max(0, p.d0) / 365).squareRoot()
        var out: [SXFlowLegend.Item] = [.box("Move priced in by \(p.word) · " + String(format: "%.1f%%", m * 100))]
        if p.mode != "book" {
            let r = SXPay.span(n.px, m, legs(n)), lo = n.px * (1 - r), hi = n.px * (1 + r)
            let shown = n.walls.filter { $0.k >= lo && $0.k <= hi }
            if shown.contains(where: { $0.side == "call" }) { out.append(.line(SX.call, 1.5, "Call wall")) }
            if shown.contains(where: { $0.side == "put" }) { out.append(.line(SX.put, 1.5, "Put wall")) }
        }
        out.append(.text("Touch the chart to read any price"))
        return out
    }

    private var source: String {
        guard let n = name else { return "Sunny · \(p.at) · each name at its own IV · from today" }
        let iv = "IV held at \(Int((n.iv * 100).rounded()))%" + (n.reports.map { " through earnings \($0)" } ?? "")
        return "Sunny · \(p.at) · \(iv) · " + (p.mode == "sold" ? "from what you paid" : "from today")
    }

    // MARK: The plots

    private func legs(_ n: SXPayoff.Name) -> [SXPayoff.Leg] {
        if p.mode == "sold" { return n.legs.filter { $0.n < 0 } }
        if p.mode == "one" { return n.legs.filter { !off.contains($0.g) } }
        return n.legs
    }

    /// One name: the line, the band, today, the walls (one and sold), the three numbers or the finger's.
    private func one(_ n: SXPayoff.Name) -> SXPlot {
        let L = legs(n), sale = p.mode == "sold", d0 = p.d0, px = n.px
        let m = n.iv * (max(0, d0) / 365).squareRoot(), r = SXPay.span(px, m, L), lo = px * (1 - r), hi = px * (1 + r)
        let f: (Double) -> Double = { SXPay.pnl(L, $0, d0, sale: sale) }
        var marks: [SXPlot.Mark] = [.init(S: px, color: SX.zero, w: 1, dash: [2, 3])]
        if p.mode != "book" {
            for w in n.walls where w.k >= lo && w.k <= hi {
                marks.append(.init(S: w.k, color: w.side == "call" ? SX.call : SX.put, w: w.dash ? 1.25 : 1.5, dash: w.dash ? [4, 3] : [],
                                   label: "\(w.label) \(SXPay.k(w.k))", conf: w.conf))
            }
        }
        var dots: [SXPlot.Dot] = [.init(S: px, v: f(px), size: 8)], tags: [SXPlot.Tag] = []
        if let sx {
            let s = lo + sx * (hi - lo)
            marks.append(.init(S: s, color: SX.ink, w: 1, dash: []))
            dots.append(.init(S: s, v: f(s), size: 11))
            tags.append(.init(S: s, v: f(s), dot: false, t2: " at " + SXPay.px(s)))
        } else {
            tags = [px * (1 - m), px, px * (1 + m)].enumerated().map { .init(S: $1, v: f($1), dot: $0 != 1, t2: "") }
        }
        var ax: [SXPlot.Ax] = [.init(S: px, t: SXPay.px(px), t2: "Today", pr: 1, weight: .bold, ink: true)]
        let word = ["lp": "LEAPS", "hc": "Hedge", "ip": "Insurance"]
        for l in L {
            let sold = l.n < 0
            ax.append(.init(S: l.k, t: SXPay.k(l.k), t2: sold ? "Sold" : word[l.g] ?? "", pr: sold ? 2 : 5, weight: sold ? .semibold : .medium, ink: sold))
        }
        for b in SXPay.zeros(f, lo, hi).prefix(2) { ax.append(.init(S: b, t: SXPay.px(b), t2: "Breakeven", pr: 3)) }
        for s in [px * (1 - m), px * (1 + m)] { ax.append(.init(S: s, t: SXPay.px(s), t2: "1 SD", pr: 4)) }
        let labelled = marks.contains { $0.label != nil }
        return SXPlot(lo: lo, hi: hi, H: 196, top: labelled ? 34 : 14, curves: [.init(f: f, main: true)],
                      band: (px * (1 - m), px * (1 + m)), marks: marks, dots: dots, tags: tags, ax: ax, axH: 30,
                      said: said(n.t, [px * (1 - m), px, px * (1 + m)].map(f), sd: true), scrub: true)
    }

    /// The book on All: every name moved by the same %, the book bold and each name faint behind it.
    private func all() -> SXPlot {
        let d0 = p.d0
        let F: [(t: String, f: (Double) -> Double)] = p.names.map { n in (n.t, { x in SXPay.pnl(n.legs, n.px * (1 + x), d0, sale: false) }) }
        let tot: (Double) -> Double = { x in F.reduce(0) { $0 + $1.f(x) } }
        let big = Set(F.sorted { abs($0.f(0.1)) > abs($1.f(0.1)) }.prefix(2).map(\.t))
        let curves = F.map { SXPlot.Curve(f: $0.f, main: false, end: big.contains($0.t) ? $0.t : nil) } + [.init(f: tot, main: true, end: "Book")]
        let mv = { (x: Double) in (x < 0 ? "▼ " : "▲ ") + "\(Int(abs(x * 100).rounded()))%" }
        let ax = [-0.1, -0.05, 0, 0.05, 0.1].map { x in
            SXPlot.Ax(S: x, t: x == 0 ? "Today" : mv(x), t2: "", pr: x == 0 ? 1 : 2, weight: x == 0 ? .bold : .medium, ink: x == 0, edge: true)
        }
        return SXPlot(lo: -0.1, hi: 0.1, H: 200, top: 12, curves: curves, band: nil,
                      marks: [.init(S: 0, color: SX.zero, w: 1, dash: [2, 3])], dots: [.init(S: 0, v: tot(0), size: 8)],
                      tags: [-0.05, 0, 0.05].enumerated().map { .init(S: $1, v: tot($1), dot: $0 != 1, t2: "") }, ax: ax, axH: 16,
                      said: said("Book", [-0.05, 0, 0.05].map(tot), sd: false), scrub: false)
    }

    /// The chart as one sentence for VoiceOver.
    private func said(_ t: String, _ v: [Double], sd: Bool) -> String {
        let w = { (x: Double) in (x >= 0 ? "adds " : "costs ") + SXPay.usd(x) }
        return sd ? "\(t) by \(p.word): 1 SD down \(w(v[0])), flat \(w(v[1])), 1 SD up \(w(v[2]))"
            : "\(t) by \(p.word): a 5% drop \(w(v[0])), flat \(w(v[1])), a 5% rise \(w(v[2]))"
    }

    private func plotView(_ plot: SXPlot) -> some View {
        SXPlotView(plot: plot, sx: $sx)
    }
}

/// A chip: 30 high inside a 44 pt target; ink when on, a gray fill when off; the colour eases in 0.2 s.
private struct SXPayChip: View {
    let text: String, on: Bool
    var body: some View {
        Text(text)
            .sx(SXType(size: 14, line: 18, weight: .semibold, style: .subheadline, tracking: 0))
            .foregroundStyle(on ? SX.paper : SX.ink)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(on ? SX.ink : SX.fill, in: .capsule)
            .animation(.easeOut(duration: 0.2), value: on)
            .frame(height: 44)
            .contentShape(.rect)
    }
}

/// The legend: a box or a line beside each word, wrapping.
struct SXFlowLegend: View {
    enum Item {
        case box(String), line(Color, CGFloat, String), text(String)
        var word: String { switch self { case .box(let t), .line(_, _, let t), .text(let t): t } }
    }
    let items: [Item]
    var body: some View {
        SXFlowGaps(column: 14, row: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                HStack(spacing: 6) {
                    switch it {
                    case .box: RoundedRectangle(cornerRadius: 2).fill(SX.cone).frame(width: 12, height: 9)
                    case .line(let c, let w, _): Rectangle().fill(c).frame(width: 14, height: w)
                    case .text: EmptyView()
                    }
                    Text(it.word).sx(.source).foregroundStyle(SX.muted)
                }
            }
        }
    }
}

/// A wrap with its own column and row gaps.
struct SXFlowGaps: Layout {
    var column: CGFloat, row: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, h: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > w { y += h + row; x = 0; h = 0 }
            x += z.width + column; h = max(h, z.height); widest = max(widest, x - column)
        }
        return CGSize(width: min(widest, w), height: y + h)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, h: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > b.minX && x + z.width > b.maxX { y += h + row; x = b.minX; h = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + column; h = max(h, z.height)
        }
    }
}

// MARK: - The plot

/// One chart: price (or the move, for the book) across, dollars up.
struct SXPlot {
    struct Curve { let f: (Double) -> Double; let main: Bool; var end: String? = nil }
    struct Mark {
        let S: Double; let color: Color; let w: CGFloat; let dash: [CGFloat]; var label: String? = nil
        /// A wall's confidence, 1 to 3: its dots after the label.
        var conf: Int? = nil
    }
    struct Dot { let S: Double; let v: Double; let size: CGFloat }
    struct Tag { let S: Double; let v: Double; let dot: Bool; let t2: String }
    struct Ax {
        let S: Double; let t: String; let t2: String; let pr: Int
        var weight: Font.Weight = .medium; var ink = false; var edge = false
    }
    let lo: Double, hi: Double, H: CGFloat, top: CGFloat
    let curves: [Curve]
    let band: (Double, Double)?
    let marks: [Mark], dots: [Dot], tags: [Tag], ax: [Ax]
    let axH: CGFloat
    /// VoiceOver's sentence.
    let said: String
    let scrub: Bool
}

struct SXPlotView: View {
    let plot: SXPlot
    @Binding var sx: Double?
    @State private var width: CGFloat = 0

    var body: some View {
        VStack(spacing: 6) {
            Canvas { ctx, size in draw(&ctx, size) }
                .frame(height: plot.H)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .gesture(SXPressSlide { pt in
                    guard plot.scrub, width > 0 else { return }
                    sx = pt.map { min(1, max(0, $0.x / width)) }
                })
                .accessibilityElement()
                .accessibilityLabel(plot.said)
                .accessibilityValue(reading)
                .accessibilityAdjustableAction { d in
                    guard plot.scrub else { return }
                    let now = sx ?? 0.5
                    sx = min(1, max(0, now + (d == .increment ? 0.05 : -0.05)))
                }
            Canvas { ctx, size in axis(&ctx, size) }
                .frame(height: plot.axH)
                .accessibilityHidden(true)
        }
    }

    /// What slide to read says: the value and the price under the finger.
    private var reading: String {
        guard let sx, let main = plot.curves.last(where: \.main) else { return "" }
        let s = plot.lo + sx * (plot.hi - plot.lo), v = main.f(s)
        return (v >= 0 ? "adds " : "costs ") + SXPay.usd(v) + " at " + SXPay.px(s)
    }

    // The chart, drawn as the design's SVG: the band, fills, grid, zero, marks, lines; then dots; then labels.
    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let p = plot, w = size.width, H = p.H, bot: CGFloat = 8, n = 96
        guard w > 0 else { return }
        let XF = { (S: Double) in CGFloat(min(1, max(0, (S - p.lo) / (p.hi - p.lo)))) }
        let X = { (S: Double) in XF(S) * w }
        let pts = p.curves.map { c in (0...n).map { i -> (Double, Double) in let s = p.lo + (p.hi - p.lo) * Double(i) / Double(n); return (s, c.f(s)) } }
        var mn = 0.0, mx = 0.0
        for c in pts { for q in c { mn = min(mn, q.1); mx = max(mx, q.1) } }
        let sp = (mx - mn) > 0 ? mx - mn : 1000
        mx += sp * 0.08; mn -= sp * 0.08
        let Y = { (v: Double) in p.top + CGFloat((mx - v) / (mx - mn)) * (H - p.top - bot) }
        let y0 = Y(0), z = min(1, max(0, y0 / H))
        let path = { (q: [(Double, Double)]) -> Path in var a = Path(); for (i, e) in q.enumerated() { let pt = CGPoint(x: X(e.0), y: Y(e.1)); if i == 0 { a.move(to: pt) } else { a.addLine(to: pt) } }; return a }
        let vline = { (x: CGFloat) -> Path in var a = Path(); a.move(to: CGPoint(x: x, y: 0)); a.addLine(to: CGPoint(x: x, y: H)); return a }
        let hline = { (y: CGFloat) -> Path in var a = Path(); a.move(to: CGPoint(x: 0, y: y)); a.addLine(to: CGPoint(x: w, y: y)); return a }
        let round = { (lw: CGFloat, dash: [CGFloat]) in StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round, dash: dash) }

        // The move priced in.
        if let b = p.band { ctx.fill(Path(CGRect(x: X(b.0), y: 0, width: X(b.1) - X(b.0), height: H)), with: .color(SX.cone)) }
        // Fills under the main line, fading toward zero.
        for (c, q) in zip(p.curves, pts) where c.main {
            var up = Path(), dn = Path()
            up.move(to: CGPoint(x: 0, y: y0)); dn.move(to: CGPoint(x: 0, y: y0))
            for e in q { up.addLine(to: CGPoint(x: X(e.0), y: Y(max(0, e.1)))); dn.addLine(to: CGPoint(x: X(e.0), y: Y(min(0, e.1)))) }
            up.addLine(to: CGPoint(x: w, y: y0)); up.closeSubpath(); dn.addLine(to: CGPoint(x: w, y: y0)); dn.closeSubpath()
            ctx.fill(up, with: .linearGradient(Gradient(stops: [.init(color: SX.payUp.opacity(0.34), location: 0), .init(color: SX.payUp.opacity(0.03), location: z)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: H)))
            ctx.fill(dn, with: .linearGradient(Gradient(stops: [.init(color: SX.payDown.opacity(0.03), location: z), .init(color: SX.payDown.opacity(0.34), location: 1)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: H)))
        }
        // Grid, every nice step but zero; then zero.
        let step = SXPay.nice((mx - mn) / 3.6)
        var gv = (mn / step).rounded(.up) * step, zeroLabel = false
        while gv <= mx {
            let y = Y(gv), isZero = abs(gv) < step / 2
            if y >= 4 && y <= H - 4 {
                if !isZero { ctx.stroke(hline(y), with: .color(SX.grid), style: round(1, [])) }
                else if y > 16 { zeroLabel = true }
            }
            gv += step
        }
        ctx.stroke(hline(y0), with: .color(SX.zero), style: round(1, []))
        // Today, the walls and the finger.
        for m in p.marks where m.S >= p.lo && m.S <= p.hi { ctx.stroke(vline(X(m.S)), with: .color(m.color), style: round(m.w, m.dash)) }
        // Each name faint, then the main line, green above zero and red below.
        for (c, q) in zip(p.curves, pts) where !c.main { ctx.stroke(path(q), with: .color(SX.leg), style: round(1.25, [])) }
        for (c, q) in zip(p.curves, pts) where c.main {
            ctx.stroke(path(q), with: .linearGradient(Gradient(stops: [.init(color: SX.payUp, location: 0), .init(color: SX.payUp, location: z),
                                                                      .init(color: SX.payDown, location: z), .init(color: SX.payDown, location: 1)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: H)), style: round(2.75, []))
        }

        // Dots: today with a halo of its own colour, the finger's larger; the three numbers' plain.
        let sgn = { (v: Double) in v >= 0 ? SX.payUp : SX.payDown }
        func dot(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat, halo: Bool, _ c: Color) {
            let r = s / 2
            if halo { ctx.fill(Path(ellipseIn: CGRect(x: x - r - 7, y: y - r - 7, width: s + 14, height: s + 14)), with: .color(c.opacity(0.24))) }
            ctx.fill(Path(ellipseIn: CGRect(x: x - r - 2.5, y: y - r - 2.5, width: s + 5, height: s + 5)), with: .color(SX.paper))
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: s, height: s)), with: .color(c))
        }
        for d in p.dots where d.S >= p.lo && d.S <= p.hi { dot(X(d.S), Y(d.v), d.size, halo: true, sgn(d.v)) }
        for t in p.tags where t.dot && t.S >= p.lo && t.S <= p.hi { dot(X(t.S), Y(t.v), 8, halo: false, sgn(t.v)) }

        // Labels: $0, the walls' names in rows at the top, the line ends, then the numbers on the line.
        func label(_ s: String, _ c: Color, _ weight: Font.Weight, padX: CGFloat, padY: CGFloat, paper: Bool,
                   at place: (CGSize) -> CGPoint) {
            let r = ctx.resolve(Text(s).font(.system(size: 12, weight: weight)).monospacedDigit().foregroundStyle(c))
            let m = r.measure(in: CGSize(width: 1000, height: 100))
            let box = CGSize(width: m.width + padX * 2, height: 14 + padY * 2), o = place(box)
            if paper { ctx.fill(Path(roundedRect: CGRect(origin: o, size: box), cornerRadius: 4), with: .color(SX.paper)) }
            ctx.draw(r, at: CGPoint(x: o.x + box.width / 2, y: o.y + box.height / 2), anchor: .center)
        }
        if zeroLabel { label("$0", SX.muted, .semibold, padX: 0, padY: 0, paper: false) { _ in CGPoint(x: 0, y: y0 - 15) } }
        // A wall's name, then its confidence as three 5 pt dots, filled or ringed ("Ceiling 36 ●●●").
        var row = 0
        for m in p.marks where m.label != nil && m.S >= p.lo && m.S <= p.hi {
            let x = X(m.S), right = XF(m.S) > 0.62, top = CGFloat(row) * 15
            let r = ctx.resolve(Text(m.label!).font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(m.color))
            let tw = r.measure(in: CGSize(width: 1000, height: 100)).width, dw: CGFloat = m.conf == nil ? 0 : 4 + 3 * 5 + 2 * 1.6
            let box = CGRect(x: right ? x - 4 - (tw + dw + 4) : x + 4, y: top, width: tw + dw + 4, height: 14)
            ctx.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(SX.paper))
            ctx.draw(r, at: CGPoint(x: box.minX + 2, y: box.midY), anchor: .leading)
            if let c = m.conf {
                for i in 0..<3 {
                    let d = CGRect(x: box.minX + 2 + tw + 4 + CGFloat(i) * 6.6, y: box.midY - 2, width: 5, height: 5)
                    if i < c { ctx.fill(Path(ellipseIn: d), with: .color(m.color)) }
                    else { ctx.stroke(Path(ellipseIn: d.insetBy(dx: 0.5, dy: 0.5)), with: .color(m.color), lineWidth: 1) }
                }
            }
            row += 1
        }
        let wallRows = CGFloat(row) * 15
        var ends = zip(p.curves, pts).compactMap { c, q -> (y: CGFloat, t: String, ink: Bool)? in c.end.map { (Y(q.last!.1) - 17, $0, c.main) } }
            .sorted { $0.y < $1.y }
        if ends.count > 1 { for i in 1..<ends.count where ends[i].y - ends[i - 1].y < 15 { ends[i].y = ends[i - 1].y + 15 } }
        if let l = ends.last, l.y > H - 14 { let o = l.y - (H - 14); for i in ends.indices { ends[i].y -= o } }
        if let f = ends.first, f.y < 0 { let o = -f.y; for i in ends.indices { ends[i].y += o } }
        for e in ends { label(e.t, e.ink ? SX.ink : SX.muted, .semibold, padX: 3, padY: 0, paper: true) { b in CGPoint(x: w - b.width, y: max(0, e.y)) } }
        var seen = Set<String>()
        for t in p.tags where t.S >= p.lo && t.S <= p.hi {
            let key = SXPay.usd(t.v)
            if seen.contains(key) { continue }
            seen.insert(key)
            let y = Y(t.v), f = XF(t.S), x = X(t.S)
            let above = t.v >= 0 ? y - 26 > wallRows : y + 26 > H - 4
            label(key + t.t2, SX.value(t.v), .bold, padX: 4, padY: 1, paper: true) { b in
                CGPoint(x: f < 0.1 ? x - 4 : f > 0.9 ? x + 4 - b.width : x - b.width / 2, y: above ? y - 25 : y + 9)
            }
        }
    }

    // The price axis: today bold, then sold strikes, breakevens, the 1 SD prices and bought strikes; a label that
    // would touch another drops, in that order.
    private func axis(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let p = plot, w = size.width
        guard w > 0 else { return }
        let XF = { (S: Double) in (S - p.lo) / (p.hi - p.lo) }
        // Each label's own box, as it is drawn (left-aligned near the left edge, right-aligned near the right, else
        // centred), so an edge label is measured where it really sits; 3% of the width spare between boxes.
        typealias Placed = (a: SXPlot.Ax, f: CGFloat, x: CGFloat, l: CGFloat, r: CGFloat, t: GraphicsContext.ResolvedText, t2: GraphicsContext.ResolvedText)
        var acc: [Placed] = []
        for a in p.ax.sorted(by: { $0.pr < $1.pr }) {
            let f = CGFloat(XF(a.S))
            if f < 0 || f > 1 || (!a.edge && (f <= 0 || f >= 1)) { continue }
            let t = ctx.resolve(Text(a.t).font(.system(size: 12, weight: a.weight)).monospacedDigit().foregroundStyle(a.ink ? SX.ink : SX.muted))
            let t2 = ctx.resolve(Text(a.t2).font(.system(size: 12, weight: .medium)).foregroundStyle(SX.muted))
            let wd = max(t.measure(in: size).width, a.t2.isEmpty ? 0 : t2.measure(in: size).width)
            let x = f < 0.07 ? f * w - 2 : f > 0.93 ? f * w + 2 : f * w
            let l = f < 0.07 ? x : f > 0.93 ? x - wd : x - wd / 2, gap = 0.03 * w
            if acc.contains(where: { l < $0.r + gap && l + wd > $0.l - gap }) { continue }
            acc.append((a, f, x, l, l + wd, t, t2))
        }
        for q in acc {
            let anchor = UnitPoint(x: q.f < 0.07 ? 0 : q.f > 0.93 ? 1 : 0.5, y: 0.5)
            ctx.draw(q.t, at: CGPoint(x: q.x, y: 7.5), anchor: anchor)
            if !q.a.t2.isEmpty { ctx.draw(q.t2, at: CGPoint(x: q.x, y: 22.5), anchor: anchor) }
        }
    }
}

/// Press and slide: a short hold (0.15 s) starts reading, so a swipe still scrolls the answer; let go and the three
/// numbers come back.
struct SXPressSlide: UIGestureRecognizerRepresentable {
    let changed: (CGPoint?) -> Void
    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let g = UILongPressGestureRecognizer()
        g.minimumPressDuration = 0.15
        g.allowableMovement = 10
        return g
    }
    func handleUIGestureRecognizerAction(_ g: UILongPressGestureRecognizer, context: Context) {
        switch g.state {
        case .began, .changed: changed(context.converter.localLocation)
        default: changed(nil)
        }
    }
}
