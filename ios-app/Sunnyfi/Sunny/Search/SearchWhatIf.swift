//
//  SearchWhatIf.swift
//  Sunny
//
//  What if · Delta and Gamma (block 29, handoff Oct 30 2026): what a move does to a name's delta. A slider from 15%
//  down to 15% up in 0.5% steps; the state (On target, Thin, Short), net delta in shares, its share of long delta and
//  the P&L follow it live. The chart: bought delta as a green area above zero, sold as a red area below, net as the
//  ink line, the week's walls as verticals, today as a gray line, dots where the slider sits. sunny-search sends every
//  step worked out (sunny-home's Δ Γ model, widened to 15%) and the tip already written: the To do hedge as a story.
//

import SwiftUI
import UIKit

/// What sunny-search sends: each 0.5% step's delta and P&L, the walls within 15%, and the hedge told as a story.
struct SXWhatIf: Decodable, Equatable {
    struct Wall: Decodable, Equatable { let k: Double; let lb: String; let side: String; let dash: Bool }
    struct Tip: Decodable, Equatable { let a: String; let b: String }
    let t: String, px: Double, sd: Double?
    /// Today's long delta in shares: Thin is net under 25% of it (a stable base, as Home reads it).
    let long: Double
    /// The move asked, where the slider opens.
    let mv: Double
    /// [move %, bought, sold, net, P&L $] every 0.5% from 15% down to 15% up.
    let rows: [[Double]]
    let walls: [Wall]
    let tip: Tip?
    let at: String
}

struct SXWhatIfCard: View {
    let p: SXWhatIf
    @State private var mv: Double

    init(p: SXWhatIf) {
        self.p = p
        _mv = State(initialValue: min(15, max(-15, (p.mv * 2).rounded() / 2)))
    }

    private typealias At = SXWhatIfStep
    private func at(_ m: Double) -> At {
        let i = min(max(0, Int(((m + 15) * 2).rounded())), max(0, p.rows.count - 1))
        let r = p.rows.indices.contains(i) && p.rows[i].count >= 5 ? p.rows[i] : [m, 0, 0, 0, 0]
        return At(m: r[0], S: p.px * (1 + r[0] / 100), b: r[1], s: r[2], d: r[3], pl: r[4])
    }
    private func state(_ a: At) -> String { a.d < 0 ? "Short" : a.d < 0.25 * p.long ? "Thin" : "On target" }
    private func stateC(_ s: String) -> Color { s == "Short" ? SX.down : s == "Thin" ? SX.thin : SX.up }

    var body: some View {
        let a = at(mv), st = state(a)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                (Text(p.t).foregroundColor(SX.ink) + Text(" · What if").foregroundColor(SX.muted))
                    .sx(.question).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Delta and Gamma").sx(SXType(size: 13, line: 16, weight: .semibold, style: .footnote, tracking: 0)).foregroundStyle(SX.muted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            reading(a, st).padding(.top, -4)
            SXMoveSlider(mv: $mv, said: moveText(mv))
                .padding(.top, -4).padding(.bottom, -6)
            SXWhatIfPlot(p: p, cur: a)
            Text("Thin is net delta under 25% of long delta. Short is under zero.")
                .sx(SXType(size: 15, line: 21, weight: .medium, style: .subheadline, tracking: 0)).foregroundStyle(SX.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let tip = p.tip {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tip.a).sx(SXType(size: 15, line: 21, weight: .bold, style: .subheadline, tracking: 0)).foregroundStyle(SX.ink)
                    Text(tip.b).sx(SXType(size: 14, line: 20, weight: .medium, style: .subheadline, tracking: 0)).foregroundStyle(SX.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SX.tile, in: .rect(cornerRadius: 14, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            SXSourceLine(kind: "sunny", text: "Sunny · \(p.at) · IV held")
        }
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 14, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SXPaper(radius: 22))
    }

    // MARK: The move, the state and three numbers

    private func moveText(_ m: Double) -> String {
        m == 0 ? "stays flat" : (m > 0 ? "rises " : "falls ") + SXC.k(abs(m)) + "%"
    }

    private func reading(_ a: At, _ st: String) -> some View {
        let pct = Int((abs(a.d) / max(1, p.long) * 100).rounded())
        let plC = a.pl >= 5 ? SX.up : a.pl <= -5 ? SX.down : SX.ink
        let sdT = mv == 0 ? "" : p.sd.map { $0 > 0 ? " · " + String(format: "%.1f", abs(mv) / $0) + " SD" : "" } ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                (Text("If \(p.t) \(moveText(mv))").font(.system(size: 20, weight: .bold)).tracking(-0.2).foregroundColor(SX.ink)
                    + Text(sdT).font(.system(size: 15, weight: .semibold)).foregroundColor(SX.muted))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(st).sx(SXType(size: 15, line: 20, weight: .bold, style: .subheadline, tracking: 0)).foregroundStyle(stateC(st))
                    .fixedSize()
            }
            HStack(alignment: .top, spacing: 10) {
                num("Net delta", Int(abs(a.d).rounded()).formatted(.number.grouping(.automatic)) + " Δ", a.d < 0 ? SX.down : SX.ink,
                    a.d < 0 ? "short, in shares" : "in shares", SX.muted)
                num("Of long delta", "\(pct)%", a.d < 0 ? SX.down : pct < 25 ? SX.thin : SX.ink, "25% is the line", SX.muted)
                num("P&L if today", Self.money(a.pl), plC, abs(a.pl) < 5 ? "flat" : a.pl > 0 ? "gain" : "loss", plC)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("If \(p.t) \(moveText(mv)): \(st). Net delta \(Int(abs(a.d).rounded())) shares" + (a.d < 0 ? " short" : "") +
                            ", \(pct)% of long delta. P&L if today " + (a.pl < 0 ? "loss " : "gain ") + Self.money(a.pl))
    }

    private func num(_ l: String, _ v: String, _ c: Color, _ sub: String, _ subC: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(l).sx(SXType(size: 12, line: 16, weight: .semibold, style: .caption1, tracking: 0)).foregroundStyle(SX.muted)
            Text(v).font(.system(size: 20, weight: .bold)).tracking(-0.2).monospacedDigit().foregroundStyle(c)
                .lineLimit(1).minimumScaleFactor(0.7).frame(height: 24)
            Text(sub).sx(SXType(size: 12, line: 16, weight: .semibold, style: .caption1, tracking: 0)).foregroundStyle(subC)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The design's money: $4.9K from a thousand, else to the $10; no sign (the colour says it).
    static func money(_ v: Double) -> String {
        let a = abs(v)
        guard a >= 1000 else { return "$" + String(Int((a / 10).rounded() * 10)) }
        let k = a / 1000
        return "$" + (k >= 10 || abs(k - k.rounded()) < 0.05 ? String(Int(k.rounded())) : String(format: "%.1f", k)) + "K"
    }
}

// MARK: - The slider

/// 15% down to 15% up in 0.5% steps: drag, tap the track, or swipe up and down with VoiceOver. The ink fill runs from
/// today (the middle tick) to the move.
struct SXMoveSlider: View {
    @Binding var mv: Double
    let said: String
    @State private var w: CGFloat = 0

    private func set(_ x: CGFloat) {
        guard w > 0 else { return }
        let f = min(1, max(0, x / w)), m = ((f * 30 - 15) * 2).rounded() / 2
        if m != mv { mv = m }
    }

    var body: some View {
        let x = CGFloat((mv + 15) / 30)
        ZStack(alignment: .topLeading) {
            Capsule().fill(SX.fill).frame(height: 4).offset(y: 16)
            Capsule().fill(SX.ink).frame(width: abs(x - 0.5) * w, height: 4).offset(x: min(0.5, x) * w, y: 16)
            RoundedRectangle(cornerRadius: 1).fill(SX.muted).frame(width: 2, height: 14).offset(x: w / 2 - 1, y: 11)
            Circle().fill(.white)
                .overlay(Circle().strokeBorder(.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 0.5)
                .shadow(color: .black.opacity(0.12), radius: 6.5, y: 6)
                .frame(width: 28, height: 28)
                .offset(x: x * w - 14, y: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 36)
        .contentShape(.rect)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w = $0 }
        .onTapGesture(coordinateSpace: .local) { set($0.x) }
        .gesture(SXSideSlide { set($0.x) })
        .accessibilityElement()
        .accessibilityLabel("Move in the price")
        .accessibilityValue(said)
        .accessibilityAdjustableAction { d in mv = min(15, max(-15, mv + (d == .increment ? 0.5 : -0.5))) }
    }
}

/// A pan that only starts sideways, so an upward swipe over the slider still scrolls the answer.
final class SXSidePan: UIPanGestureRecognizer {
    private var start: CGPoint?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        start = touches.first?.location(in: view)
        super.touchesBegan(touches, with: event)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, let s = start, let p = touches.first?.location(in: view), abs(p.y - s.y) > abs(p.x - s.x), abs(p.y - s.y) > 4 {
            state = .failed
            return
        }
        super.touchesMoved(touches, with: event)
    }
}

struct SXSideSlide: UIGestureRecognizerRepresentable {
    let changed: (CGPoint) -> Void
    func makeUIGestureRecognizer(context: Context) -> SXSidePan { SXSidePan() }
    func handleUIGestureRecognizerAction(_ g: SXSidePan, context: Context) {
        if g.state == .began || g.state == .changed { changed(context.converter.localLocation) }
    }
}

// MARK: - The chart

/// One step of the slider: the move, the price, bought, sold and net delta in shares, the P&L in dollars.
fileprivate struct SXWhatIfStep { let m: Double, S: Double, b: Double, s: Double, d: Double, pl: Double }

/// The reference's dgV chart: delta in dollars at each price (shares × price), so the areas widen as the price climbs.
private struct SXWhatIfPlot: View {
    let p: SXWhatIf
    let cur: SXWhatIfStep
    private static let H: CGFloat = 150

    /// Every step as (x 0 to 1, bought $, sold $, net $).
    private var ser: [(x: CGFloat, b: Double, s: Double, n: Double)] {
        p.rows.filter { $0.count >= 4 }.map { r in
            let S = p.px * (1 + r[0] / 100)
            return (CGFloat((r[0] + 15) / 30), r[1] * S, r[2] * S, r[3] * S)
        }
    }

    var body: some View {
        let H = Self.H, ser = ser
        let M = max(1, ser.map { max(abs($0.b), abs($0.s), abs($0.n)) }.max() ?? 1)
        let Y = { (v: Double) in H / 2 - CGFloat(v / M) * (H / 2 - 10) }
        let walls = p.walls.map { (w: $0, m: ($0.k / p.px - 1) * 100) }.filter { abs($0.m) <= 15 }.sorted { $0.m < $1.m }
        VStack(spacing: 6) {
            GeometryReader { g in
                let W = g.size.width
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        let w = size.width, z = H / 2
                        func area(_ f: (Int) -> Double, _ c: Color) {
                            var path = Path()
                            for (i, q) in ser.enumerated() { let pt = CGPoint(x: q.x * w, y: Y(f(i))); if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) } }
                            path.addLine(to: CGPoint(x: w, y: z)); path.addLine(to: CGPoint(x: 0, y: z)); path.closeSubpath()
                            ctx.fill(path, with: .color(c))
                        }
                        area({ ser[$0].b }, Color(red: 101 / 255, green: 196 / 255, blue: 102 / 255).opacity(0.38))
                        area({ ser[$0].s }, Color(red: 235 / 255, green: 75 / 255, blue: 70 / 255).opacity(0.40))
                        func vline(_ x: CGFloat, _ c: Color, _ lw: CGFloat, _ dash: [CGFloat]) {
                            var l = Path(); l.move(to: CGPoint(x: x * w, y: 0)); l.addLine(to: CGPoint(x: x * w, y: H))
                            ctx.stroke(l, with: .color(c), style: StrokeStyle(lineWidth: lw, lineCap: .round, dash: dash))
                        }
                        var zl = Path(); zl.move(to: CGPoint(x: 0, y: z)); zl.addLine(to: CGPoint(x: w, y: z))
                        ctx.stroke(zl, with: .color(SX.muted), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        vline(0.5, SX.line, 1.5, [])
                        for x in walls { vline(CGFloat((x.m + 15) / 30), x.w.side == "call" ? SX.call : SX.put, 1.25, x.w.dash ? [4, 3] : []) }
                        vline(CGFloat((cur.m + 15) / 30), SX.ink, 1, [2, 3])
                        var n = Path()
                        for (i, q) in ser.enumerated() { let pt = CGPoint(x: q.x * w, y: Y(q.n)); if i == 0 { n.move(to: pt) } else { n.addLine(to: pt) } }
                        ctx.stroke(n, with: .color(SX.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(Array(wallLabels(walls, W).enumerated()), id: \.offset) { _, l in
                        Text(l.t).sx(SXType(size: 12, line: 14, weight: .bold, style: .caption1, tracking: 0)).foregroundStyle(l.c)
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 3)
                            .background(SX.paper, in: .rect(cornerRadius: 6))
                            .offset(x: l.x, y: l.y)
                    }
                    Text("Bought").sx(SXType(size: 12, line: 14, weight: .bold, style: .caption1, tracking: 0)).foregroundStyle(SX.up).offset(y: 36)
                    Text("Sold").sx(SXType(size: 12, line: 14, weight: .bold, style: .caption1, tracking: 0)).foregroundStyle(SX.down).offset(y: H - 16)
                    let xm = CGFloat((cur.m + 15) / 30) * W
                    ForEach(Array([(cur.b, SX.up), (cur.s, SX.down), (cur.d, cur.d < 0 ? SX.down : SX.ink)].enumerated()), id: \.offset) { _, d in
                        Circle().fill(d.1).frame(width: 9, height: 9)
                            .background(Circle().fill(SX.paper).frame(width: 14, height: 14))
                            .position(x: xm, y: Y(d.0 * cur.S))
                    }
                }
            }
            .frame(height: H)
            ZStack(alignment: .top) {
                Text("15% down").frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 0) {
                    Text("Today").fontWeight(.bold).foregroundStyle(SX.ink)
                    Text(String(format: "%.2f", p.px))
                }
                Text("15% up").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .sx(SXType(size: 12, line: 15, weight: .medium, style: .caption1, tracking: 0))
            .foregroundStyle(SX.muted)
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(said(walls))
    }

    private func said(_ walls: [(w: SXWhatIf.Wall, m: Double)]) -> String {
        let c = cur
        var s = "Delta from 15% down to 15% up. At \(SXC.k(abs(c.m)))% " + (c.m < 0 ? "down" : "up") +
            ": bought \(Int(c.b.rounded())), sold \(Int(abs(c.s).rounded())), net \(Int(c.d.rounded())) shares"
        if !walls.isEmpty { s += ". Walls: " + walls.map { "\($0.w.lb) \(SXC.k($0.w.k))" }.joined(separator: ", ") }
        return s
    }

    /// Very close walls share one label; a label that would overlap the one before it drops to a second row.
    private func wallLabels(_ ws: [(w: SXWhatIf.Wall, m: Double)], _ W: CGFloat) -> [(t: String, x: CGFloat, y: CGFloat, c: Color)] {
        var cl: [[(w: SXWhatIf.Wall, m: Double)]] = []
        for w in ws {
            if let last = cl.last?.last, CGFloat((w.m - last.m) / 30) < 0.06 { cl[cl.count - 1].append(w) } else { cl.append([w]) }
        }
        var rowEnd: [CGFloat] = [-1e9, -1e9]
        return cl.map { c in
            let xc = c.reduce(0) { $0 + CGFloat(($1.m + 15) / 30) } / CGFloat(c.count) * W
            let same = c.allSatisfy { $0.w.lb == c[0].w.lb }
            let lb = same ? c[0].w.lb : c.contains { $0.w.lb == "Floor" } ? "Floor" : c.contains { $0.w.lb == "Ceiling" } ? "Ceiling" : c[0].w.lb
            let t = c.map { SXC.k($0.w.k) }.joined(separator: " · ") + " " + lb
            let wpx = CGFloat(t.count) * 7 + 6, x0 = max(0, min(W - wpx, xc - wpx / 2)), row = x0 >= rowEnd[0] + 6 ? 0 : 1
            rowEnd[row] = x0 + wpx
            return (t, x0, 1 + CGFloat(row) * 16, c[0].w.side == "call" ? SX.call : SX.put)
        }
    }
}
