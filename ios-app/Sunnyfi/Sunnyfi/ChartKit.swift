//
//  ChartKit.swift
//  Sunnyfi
//
//  SunnyBarChart — the one bar-chart vocabulary used on every handoff-7
//  screen (Today premium, Position harvest + premium-by-week, Performance
//  gains & losses). A gridded plot with a right-hand value axis rounded to
//  a nice number, dotted gridlines + one solid zero line, defined ticks,
//  and stacked segments up/down from zero. Faithful port of chart-kit.jsx.
//

import SwiftUI

struct SBCSeg {
    let v: Double
    let color: Color
    var opacity: Double? = nil
}

struct SBCBar: Identifiable {
    let key: String
    let label: String
    let sub: String
    let segs: [SBCSeg]
    var id: String { key }
}

/// Round up to a "nice" axis number: 1 · 1.5 · 2 · 2.5 · 3 · 4 · 5 · 6 · 8 · 10 × 10ⁿ.
func sbcNice(_ v: Double) -> Double {
    guard v > 0 else { return 0 }
    let e = pow(10, floor(log10(v)))
    let f = v / e
    let ladder: [Double] = [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]
    return (ladder.first { f <= $0 + 1e-9 } ?? 10) * e
}

/// Compact money for axis labels: K steps, real minus.
func sbcMoney(_ v: Double) -> String {
    let a = abs(v)
    let body: String
    if a >= 1000 { body = "$" + String(format: a >= 10000 ? "%.0f" : "%.1f", a / 1000) + "K" }
    else { body = "$" + String(format: "%.0f", a) }
    return (v < 0 ? "−" : "") + body
}

/// A single horizontal hairline (dotted when stroked with a dash).
private struct HLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: r.width, y: 0))
        return p
    }
}

struct SunnyBarChart: View {
    let bars: [SBCBar]
    var height: CGFloat = 180
    var sel: Int? = nil
    var onSel: ((Int?) -> Void)? = nil
    var ticks: [Int: String]? = nil
    var fmtY: (Double) -> String = sbcMoney
    var topLabel: String? = nil
    var bottomLabel: String? = nil
    var dark: Bool = false
    var compact: Bool = false
    var dense: Bool? = nil

    private var n: Int { max(bars.count, 1) }
    private func segUp(_ b: SBCBar) -> [SBCSeg] { b.segs.filter { $0.v > 0 } }
    private func segDn(_ b: SBCBar) -> [SBCSeg] { b.segs.filter { $0.v < 0 } }
    private func sumAbs(_ a: [SBCSeg]) -> Double { a.reduce(0) { $0 + abs($1.v) } }

    private var lineColor: Color { dark ? Color.white.opacity(0.13) : Color(hex: 0x182420).opacity(0.16) }
    private var zeroColor: Color { dark ? Color.white.opacity(0.28) : Color(hex: 0x182420).opacity(0.34) }
    private var lblColor: Color { dark ? Color(hex: 0xf2eee5).opacity(0.45) : Color.theme.fg4 }
    private var tickOnColor: Color { dark ? Color.theme.lime : Color.theme.neon }

    var body: some View {
        let maxUp = bars.map { sumAbs(segUp($0)) }.max() ?? 0
        let maxDn = bars.map { sumAbs(segDn($0)) }.max() ?? 0
        let niceUp = sbcNice(maxUp)
        let Mu = niceUp == 0 ? (maxDn > 0 ? 0 : 1) : niceUp
        let Md = sbcNice(maxDn)
        let total = (Mu + Md) == 0 ? 1 : (Mu + Md)
        let upH = height * CGFloat(Mu / total)
        let sc = height / CGFloat(total)
        let isDense = dense ?? (n > 14)
        let step = n <= 7 ? 1 : Int(ceil(Double(n) / 5))
        let gut: CGFloat = compact ? 0 : 44
        let barGap: CGFloat = isDense ? 1.5 : 3

        // gridlines as (y, value)
        var lines: [(CGFloat, Double)] = []
        if !compact {
            if Mu > 0 { lines.append((0, Mu)); if upH / 2 > 26 { lines.append((upH / 2, Mu / 2)) } }
            if Md > 0 { let dnH = height - upH; if dnH / 2 > 26 { lines.append((upH + dnH / 2, -Md / 2)) }; lines.append((height, -Md)) }
        }

        return VStack(spacing: 0) {
            GeometryReader { g in
                let totalW = g.size.width
                let plotW = max(totalW - gut, 1)
                ZStack(alignment: .topLeading) {
                    // dotted gridlines + right-gutter value labels
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, ln in
                        HLine().stroke(lineColor, style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                            .frame(width: plotW, height: 1).offset(y: ln.0)
                        Text(fmtY(ln.1)).font(.mono(size: 9.5, weight: .medium)).foregroundStyle(lblColor)
                            .fixedSize().offset(x: plotW + 9, y: ln.0 - 6)
                    }
                    // solid zero line + label
                    if !compact {
                        HLine().stroke(zeroColor, style: StrokeStyle(lineWidth: 1))
                            .frame(width: plotW, height: 1).offset(y: upH)
                        Text(fmtY(0)).font(.mono(size: 9.5, weight: .medium)).foregroundStyle(lblColor)
                            .fixedSize().offset(x: plotW + 9, y: upH - 6)
                    }
                    // zone labels inside the plot
                    if !compact, let tl = topLabel {
                        Text(tl.uppercased()).font(.mono(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(lblColor)
                    }
                    if !compact, let bl = bottomLabel, Md > 0 {
                        Text(bl.uppercased()).font(.mono(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(lblColor)
                            .offset(y: height - 12)
                    }
                    // bars
                    HStack(spacing: barGap) {
                        ForEach(Array(bars.enumerated()), id: \.offset) { i, b in
                            barView(b, i: i, upH: upH, sc: sc, tick: vlineAt(i, step: step))
                        }
                    }
                    .frame(width: plotW, height: height, alignment: .top)
                }
            }
            .frame(height: height)
            // x-axis
            HStack(spacing: barGap) {
                ForEach(Array(bars.enumerated()), id: \.offset) { i, b in
                    let t = tickOf(i, step: step)
                    Text(t).font(.mono(size: 9.5, weight: (sel == i && !t.isEmpty) ? .semibold : .medium))
                        .foregroundStyle((sel == i && !t.isEmpty) ? tickOnColor : lblColor)
                        .lineLimit(1).fixedSize().frame(maxWidth: .infinity)
                }
            }
            .padding(.trailing, gut).padding(.top, 10)
        }
        .padding(.top, compact ? 0 : 18)
    }

    private func tickOf(_ i: Int, step: Int) -> String {
        if let ticks { return ticks[i] ?? "" }
        return (n - 1 - i) % step == 0 ? bars[i].label : ""
    }
    private func vlineAt(_ i: Int, step: Int) -> Bool { (n - 1 - i) % step == 0 }

    @ViewBuilder
    private func barView(_ b: SBCBar, i: Int, upH: CGFloat, sc: CGFloat, tick: Bool) -> some View {
        let ups = segUp(b), dns = segDn(b)
        let dim = sel != nil && sel != i
        let stack = VStack(spacing: 0) {
            // above zero — grows up from the zero line
            VStack(spacing: 0) {
                ForEach(Array(ups.reversed().enumerated()), id: \.offset) { _, s in
                    Rectangle().fill(s.color).frame(height: CGFloat(abs(s.v)) * sc)
                }
            }
            .frame(maxWidth: 76)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2))
            .frame(maxWidth: .infinity, maxHeight: upH, alignment: .bottom)
            // below zero — grows down from the zero line
            VStack(spacing: 0) {
                ForEach(Array(dns.enumerated()), id: \.offset) { _, s in
                    Rectangle().fill(s.color).opacity(s.opacity ?? 0.72).frame(height: CGFloat(abs(s.v)) * sc)
                }
            }
            .frame(maxWidth: 76)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 2, bottomTrailingRadius: 2))
            .frame(maxWidth: .infinity, maxHeight: height - upH, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .center) {
            if tick && !compact {
                HLine().rotation(.degrees(90)).stroke(lineColor, style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                    .frame(width: 1)
            }
        }
        .opacity(dim ? 0.3 : 1)
        .contentShape(Rectangle())

        if let onSel {
            Button { onSel(sel == i ? nil : i) } label: { stack }.buttonStyle(.plain)
        } else {
            stack
        }
    }
}
