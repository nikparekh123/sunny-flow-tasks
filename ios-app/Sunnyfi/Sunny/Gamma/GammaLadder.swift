//
//  GammaLadder.swift
//  Sunny
//
//  Block 13h · the price ladder: every wall at its distance from the price, today and the flip, the zones
//  split at the flip (calmer where dealers are long gamma, amplified where short), the priced move as a band
//  on the axis (1 SD, lighter to 1.5 SD). The scale is linear inside 1.5 SD and tighter outside, so close
//  walls get room; rows never overlap. Compare with 1 week ago shows a moved wall's old strike dashed with an
//  arrow to the new one (grey when the old one rolled off); Show your trades adds your strikes and
//  breakevens, inside a wall's row when they sit on it. No drag.
//

import SwiftUI

struct GammaLadder: View {
    let v: GammaView
    /// The walls five sessions back (the server's `week`), when Compare with 1 week ago is on.
    let week: [GammaView.WeekWall]?
    let legs: [Leg]
    let ring: Double?
    let today: String

    private struct Item: Identifiable {
        enum Kind { case wall(GWall, String?, [String]), ghost(GammaView.WeekWall, Bool), today, flip, trade(String) }
        let id: String
        let k: Double
        let kind: Kind
        let h: CGFloat
        var y: CGFloat = 0
    }

    private let left: CGFloat = 58, axis: CGFloat = 66, unit: CGFloat = 64

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, items = layout(), maxY = (items.map { $0.y + $0.h }.max() ?? 200) + 26
            ZStack(alignment: .topLeading) {
                zones(items, W, maxY)
                band(items, maxY)
                ForEach(items) { it in row(it, W) }
            }
            .frame(width: W, height: maxY, alignment: .topLeading)
        }
        .frame(height: height())
    }

    // MARK: Scale and layout

    private var sd: Double { v.priced?.sd1 ?? v.spot * 0.04 }
    /// Linear to 1.5 SD, then 40% as steep, capped.
    private func f(_ k: Double) -> CGFloat {
        let u = (k - v.spot) / max(0.01, sd), a = abs(u)
        let s = a <= 1.5 ? a : min(3.6, 1.5 + (a - 1.5) * 0.4)
        return CGFloat(u >= 0 ? s : -s)
    }

    private func layout() -> [Item] {
        var xs: [Item] = []
        let byKey = Dictionary(grouping: v.walls, by: { "\($0.side)\($0.rank)" })
        for w in v.walls {
            let old = week?.first { $0.side == w.side && $0.rank == w.rank }
            var change: String? = nil
            if let o = old {
                if abs(o.k - w.k) > 1e-6 { change = (w.k < o.k ? "↓ from " : "↑ from ") + PF.strike(o.k) }
                else {
                    let d = abs(w.gex) - abs(o.gex)
                    change = abs(d) < 5e4 ? "same as a week ago" : (d > 0 ? "+" : "-") + GammaText.size(abs(d)) + " in a week"
                }
            }
            let trades = tradeLines.filter { abs($0.0 - w.k) < 1e-6 }.map(\.1)
            xs.append(Item(id: "w\(w.side)\(w.rank)", k: w.k, kind: .wall(w, change, trades), h: 50 + CGFloat(trades.count) * 16))
        }
        if let wk = week {
            for o in wk where byKey["\(o.side)\(o.rank)"]?.first.map({ abs($0.k - o.k) > 1e-6 }) ?? false {
                // A wall that moved: its old strike, dashed (grey when it rolled off).
                let rolled = (o.exp ?? "9999") <= today
                if !v.walls.contains(where: { abs($0.k - o.k) < 1e-6 }) {
                    xs.append(Item(id: "g\(o.side)\(o.rank)", k: o.k, kind: .ghost(o, rolled), h: 30))
                }
            }
        }
        xs.append(Item(id: "today", k: v.spot, kind: .today, h: 26))
        if let fl = v.flip, abs(fl / v.spot - 1) < 0.25 { xs.append(Item(id: "flip", k: fl, kind: .flip, h: 26)) }
        for (k, s) in tradeLines where !v.walls.contains(where: { abs($0.k - k) < 1e-6 }) && abs(k / v.spot - 1) < 0.3 {
            xs.append(Item(id: "t\(k)\(s)", k: k, kind: .trade(s), h: 20))
        }
        // Top to bottom by strike, each at its scaled place or just under the one above.
        xs.sort { $0.k > $1.k }
        let top = (xs.map { f($0.k) }.max() ?? 0)
        var y: CGFloat = 26
        for i in xs.indices {
            let want = 26 + (top - f(xs[i].k)) * unit - xs[i].h / 2
            y = max(want, i == 0 ? 26 : xs[i - 1].y + xs[i - 1].h + 6)
            xs[i].y = y
        }
        return xs
    }

    private func height() -> CGFloat { (layout().map { $0.y + $0.h }.max() ?? 200) + 26 }

    /// Your strikes and breakevens: sold calls, LEAPS, hedge calls, insurance puts.
    private var tradeLines: [(Double, String)] {
        var out: [(Double, String)] = []
        let g = Dictionary(grouping: legs, by: { "\($0.side)|\($0.type)|\($0.strike)|\($0.expiry)" })
        for (_, ls) in g {
            guard let l = ls.first else { continue }
            let n = ls.reduce(0) { $0 + $1.n }, md = PF.monthDay(l.expiry)
            let what = l.side == "sold" ? "Short \(n) \(md) \(l.type)s"
                : l.type == "put" ? "Insurance \(n) \(md) puts" : (l.up ?? false) ? "Hedge \(n) \(md) calls" : "LEAPS \(n) \(md)"
            out.append((l.strike, what))
            if l.side == "sold" { out.append((l.strike + (l.type == "call" ? l.avg : -l.avg), "Breakeven \(PF.price(l.strike + (l.type == "call" ? l.avg : -l.avg)))")) }
        }
        return out
    }

    // MARK: Drawing

    private func yOf(_ items: [Item], _ id: String) -> CGFloat? { items.first { $0.id == id }.map { $0.y + $0.h / 2 } }

    /// The two zones, split at the flip: calmer where dealers are long gamma, amplified where short.
    private func zones(_ items: [Item], _ W: CGFloat, _ H: CGFloat) -> some View {
        let fy = yOf(items, "flip")
        let calmAbove: Bool = {
            let atPrice = v.regime == "calmer"
            guard let fl = v.flip else { return atPrice }
            return v.spot >= fl ? atPrice : !atPrice
        }()
        let split = fy ?? (v.regime == "calmer" ? H : 0)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill((calmAbove ? S.blue : S.orange).opacity(calmAbove ? 0.06 : 0.10))
                .frame(width: W - left + 6, height: max(0, split)).offset(x: left - 6)
            RoundedRectangle(cornerRadius: 12).fill((calmAbove ? S.orange : S.blue).opacity(calmAbove ? 0.10 : 0.06))
                .frame(width: W - left + 6, height: max(0, H - split)).offset(x: left - 6, y: split)
            Text(calmAbove ? "Calmer: dealers absorb moves" : "Amplified: dealers chase moves")
                .sType(SType(size: 11, weight: 600, line: 14, tracking: 0), tabular: false)
                .foregroundStyle(calmAbove ? S.blue : S.orangeDeep)
                .frame(width: W - left - 8, alignment: .trailing).offset(x: left, y: 2)
            if fy != nil {
                Text(calmAbove ? "Amplified: dealers chase moves" : "Calmer: dealers absorb moves")
                    .sType(SType(size: 11, weight: 600, line: 14, tracking: 0), tabular: false)
                    .foregroundStyle(calmAbove ? S.orangeDeep : S.blue)
                    .frame(width: W - left - 8, alignment: .trailing).offset(x: left, y: H - 18)
            }
        }
    }

    /// The axis with the priced move: darker to 1 SD, lighter to 1.5 SD.
    private func band(_ items: [Item], _ H: CGFloat) -> some View {
        let ty = yOf(items, "today") ?? H / 2
        let s1 = CGFloat(1) * unit, s15 = CGFloat(1.5) * unit
        return ZStack(alignment: .topLeading) {
            Capsule().fill(S.track).frame(width: 6, height: H - 8).offset(x: axis - 3, y: 4)
            Capsule().fill(S.muted.opacity(0.18)).frame(width: 10, height: 2 * s15).offset(x: axis - 5, y: ty - s15)
            Capsule().fill(S.muted.opacity(0.32)).frame(width: 10, height: 2 * s1).offset(x: axis - 5, y: ty - s1)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func row(_ it: Item, _ W: CGFloat) -> some View {
        switch it.kind {
        case .wall(let w, let change, let trades):
            wallRow(w, change: change, trades: trades, W: W).offset(y: it.y)
        case .ghost(let o, let rolled):
            ghostRow(o, rolled: rolled, W: W).offset(y: it.y)
        case .today:
            HStack(spacing: 0) {
                Text(PF.price(v.spot)).sType(SType(size: 13, weight: 700, line: 16, tracking: 0)).foregroundStyle(S.paper)
                    .padding(.horizontal, 6).frame(height: 22).background(Capsule().fill(S.ink))
                    .frame(width: left, alignment: .trailing)
                Circle().fill(S.ink).frame(width: 12, height: 12).padding(.leading, axis - left - 6)
                Rectangle().fill(S.ink).frame(height: 1.5).padding(.horizontal, 8)
                Text("Today").sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink)
            }
            .frame(width: W, height: it.h).offset(y: it.y)
            .accessibilityElement(children: .ignore).accessibilityLabel("Today \(PF.price(v.spot))")
        case .flip:
            HStack(spacing: 0) {
                Text(PF.price(it.k)).sType(SType(size: 13, weight: 600, line: 16, tracking: 0)).foregroundStyle(S.ink)
                    .frame(width: left, alignment: .trailing)
                Rectangle().fill(S.ink).frame(width: 9, height: 9).rotationEffect(.degrees(45)).padding(.leading, axis - left - 4.5)
                Line().stroke(S.ink, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])).frame(height: 1).padding(.horizontal, 6)
                Text("Flip · " + GammaText.vs(it.k, v.spot)).sType(SType(size: 12, weight: 600, line: 16, tracking: 0), tabular: false)
                    .foregroundStyle(S.ink).padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(S.paper)).overlay(Capsule().strokeBorder(S.ink, lineWidth: 1))
            }
            .frame(width: W, height: it.h).offset(y: it.y)
            .accessibilityElement(children: .ignore).accessibilityLabel("Flip \(PF.price(it.k))")
        case .trade(let s):
            HStack(spacing: 8) {
                Text(PF.strike(it.k)).sType(SType(size: 11, weight: 600, line: 14, tracking: 0)).foregroundStyle(S.muted)
                    .frame(width: left, alignment: .trailing)
                Circle().strokeBorder(S.muted, lineWidth: 1).frame(width: 7, height: 7).padding(.leading, axis - left - 12)
                Text(s).sType(SType(size: 11, weight: 600, line: 14, tracking: 0), tabular: false).foregroundStyle(S.muted)
                Spacer(minLength: 0)
            }
            .frame(width: W, height: it.h).offset(y: it.y)
        }
    }

    private func wallRow(_ w: GWall, change: String?, trades: [String], W: CGFloat) -> some View {
        let big = max(1, v.walls.map { abs($0.gex) }.max() ?? 1), size = abs(w.gex) / big
        // The dot follows the side (calls blue, puts orange); the bar, icon and row follow the label (design 13h):
        // Ceiling or Floor blue and solid, Accelerator orange and striped, Unclear grey with a dashed outline.
        let side = w.call ? S.blue : S.orangeDeep
        let tint = w.label == "unclear" ? S.muted : w.label == "accelerator" ? S.orangeDeep : S.blue
        let rowFill = w.label == "unclear" ? Color.clear : w.label == "accelerator" ? S.orange.opacity(0.14) : S.blue.opacity(0.10)
        let oiSaid = w.oiLabel.map { $0 != w.label && w.label != "unclear" ? "OI model said \(GammaText.label($0))" : nil } ?? nil
        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(PF.strike(w.k)).sType(SType(size: 15, weight: 700, line: 18, tracking: 0)).foregroundStyle(S.ink)
                Text(GammaText.arrowPct(w.k, v.spot)).sType(SType(size: 11, weight: 500, line: 14, tracking: 0)).foregroundStyle(S.muted)
            }
            .frame(width: left, alignment: .trailing)
            Circle().fill(side).frame(width: 12, height: 12).overlay(Circle().strokeBorder(S.paper, lineWidth: 2))
                .padding(.leading, axis - left - 6).padding(.top, 4)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: GammaText.icon(w.label, call: w.call)).font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
                    Text(GammaText.label(w.label)).sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Text(GammaText.dots(w.conf)).sType(SType(size: 9, weight: 600, line: 12, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Spacer(minLength: 4)
                    Text(GammaText.money(w.gex)).sType(SType(size: 15, weight: 700, line: 18, tracking: 0)).foregroundStyle(S.ink)
                }
                HStack(spacing: 8) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(S.track)
                            if w.label == "accelerator" {
                                GammaStripes(color: tint).frame(width: g.size.width * size).clipShape(Capsule())
                            } else {
                                Capsule().fill(tint).frame(width: g.size.width * size)
                            }
                        }
                    }
                    .frame(height: 4)
                    Text(oiSaid ?? change ?? "").sType(SType(size: 11, weight: 500, line: 14, tracking: 0), tabular: false)
                        .foregroundStyle(oiSaid != nil ? S.orangeDeep : S.muted).lineLimit(1).fixedSize()
                }
                ForEach(trades, id: \.self) { s in
                    Text(s).sType(SType(size: 11, weight: 600, line: 14, tracking: 0), tabular: false).foregroundStyle(S.muted)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(rowFill))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(w.label == "unclear" ? S.muted : .clear, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(S.ink, lineWidth: 2).padding(-3)
                    .opacity(ring.map { abs($0 - w.k) < 1e-6 } ?? false ? 1 : 0)
                    .animation(.easeOut(duration: 0.4), value: ring)
            }
            .padding(.leading, 8)
        }
        .frame(width: W, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(w.call ? "Call" : "Put") wall \(PF.strike(w.k)), \(GammaText.vs(w.k, v.spot)), \(GammaText.label(w.label)), \(GammaText.conf(w.conf)) confidence, \(GammaText.money(w.gex)) gamma" + (oiSaid.map { ", \($0)" } ?? "") + (change.map { ", \($0)" } ?? ""))
    }

    private func ghostRow(_ o: GammaView.WeekWall, rolled: Bool, W: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(PF.strike(o.k)).sType(SType(size: 13, weight: 600, line: 16, tracking: 0)).foregroundStyle(S.muted)
                .frame(width: left, alignment: .trailing)
            Circle().strokeBorder(S.muted, style: StrokeStyle(lineWidth: 1, dash: [2, 2])).frame(width: 10, height: 10).padding(.leading, axis - left - 5)
            HStack {
                Text("\(o.rank == 1 ? "1st" : o.rank == 2 ? "2nd" : "3rd") \(o.side) wall last week" + (rolled ? ", expired" : ""))
                    .sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
                Spacer(minLength: 4)
                Text(GammaText.money(o.gex)).sType(SType(size: 12, weight: 600, line: 16, tracking: 0)).foregroundStyle(S.muted)
            }
            .padding(.horizontal, 10).frame(height: 26)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(rolled ? S.muted.opacity(0.5) : (o.side == "call" ? S.blue : S.orange),
                                                                     style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .padding(.leading, 10)
        }
        .frame(width: W, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last week the \(o.side) wall was at \(PF.strike(o.k))" + (rolled ? ", rolled off" : ""))
    }

}

/// The Accelerator bar: orange in diagonal stripes (the ladder and its legend).
struct GammaStripes: View {
        let color: Color
        var body: some View {
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(0.25)))
                var x: CGFloat = -size.height
                while x < size.width {
                    var p = Path(); p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                    ctx.stroke(p, with: .color(color), lineWidth: 2); x += 4
                }
            }
        }
}

extension GammaLadder {
    struct Line: Shape {
        func path(in r: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: 0, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
    }
}

extension GammaLadder: Equatable {
    static func == (a: GammaLadder, b: GammaLadder) -> Bool {
        a.v == b.v && a.week == b.week && a.legs == b.legs && a.ring == b.ring && a.today == b.today
    }
}
