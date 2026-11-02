//
//  SearchTech.swift
//  Sunny
//
//  Technicals (block 29, card 4; opened from block 30's 50-day and 52-week
//  tiles): four small cards two across, all the same height, the one asked top
//  left. 50-day, 200-day, RSI, 52-week; the 20-day takes the 50-day's place when
//  it is the one asked. Every figure is from the last close and comes worked
//  out from sunny-search, so a tile under the payoff and the card it opens print
//  the same number.
//

import SwiftUI

struct SXTech: Decodable, Equatable {
    struct Avg: Decodable, Equatable {
        let v: Double
        /// How far the price sits from the average, in percent, one place, no sign; up when above.
        let p: Double
        let up: Bool
        /// The last month of closes and the average over the same days, for the small chart.
        let c: [Double]
        let a: [Double?]
    }
    struct Rsi: Decodable, Equatable { let v: Int; let x: Double; let reads: String? }
    struct Range: Decodable, Equatable { let under: Int; let lo: Double; let hi: Double; let x: Double }
    let t: String
    /// "Fri close"
    let at: String
    let order: [String]
    let px: Double
    let ma: [String: Avg?]
    let rsi: Rsi?
    let range: Range
}

struct SXTechCard: View {
    let p: SXTech

    private static let titles = ["ma20": "20-day", "ma50": "50-day", "ma200": "200-day", "rsi": "RSI", "range": "52-week"]
    private var shown: [String] {
        p.order.filter { k in k == "range" || (k == "rsi" ? p.rsi != nil : (p.ma[k] ?? nil) != nil) }
    }

    var body: some View {
        SXTwoUp(h: 12, v: 14) { ForEach(shown, id: \.self) { widget($0) } }
    }

    private func widget(_ k: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            (Text(p.t).foregroundColor(SX.ink) + Text(" · " + (Self.titles[k] ?? k)).foregroundColor(SX.muted))
                .sx(.question).lineLimit(1).truncationMode(.tail)
            VStack(alignment: .leading, spacing: 2) {
                let (big, line, tone) = words(k)
                Text(big).sx(SXType(size: 32, line: 36, weight: .bold, style: .title1, tracking: -0.03)).foregroundStyle(SX.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(line).sx(SXType(size: 14, line: 18, weight: .semibold, style: .subheadline, tracking: 0)).foregroundStyle(tone)
                    .fixedSize(horizontal: false, vertical: true)
                picture(k)
            }
            .padding(.top, -8)
            // Last, at the foot of the tallest widget's height (a Spacer here would add the stack's 14 twice).
            SXSourceLine(kind: "sunny", text: "Sunny · \(p.at)").frame(maxHeight: .infinity, alignment: .bottomLeading)
        }
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 14, trailing: 18))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(SXPaper(radius: 22))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(k))
    }

    /// The big number, the line under it and its colour.
    private func words(_ k: String) -> (String, String, Color) {
        if k == "rsi", let r = p.rsi {
            let hot = r.reads == "overbought" || r.reads == "oversold"
            return (String(r.v), (r.reads ?? "neutral").capitalized, hot ? SX.thin : SX.ink)
        }
        if k == "range" { return ("\(p.range.under)%", "under the high", SX.muted) }
        guard let a = p.ma[k] ?? nil else { return ("", "", SX.muted) }
        return (String(format: "%.2f", a.v), String(format: "Price %.1f%% ", a.p) + (a.up ? "above" : "below"), a.up ? SX.up : SX.down)
    }

    private func label(_ k: String) -> String {
        let (big, line, _) = words(k)
        var s = "\(p.t) \(Self.titles[k] ?? k), \(big), \(line)"
        if k == "range" { s += String(format: ", %.2f to %.2f", p.range.lo, p.range.hi) }
        return s + ". Sunny, \(p.at)."
    }

    @ViewBuilder private func picture(_ k: String) -> some View {
        if k == "rsi", let r = p.rsi {
            let hot = r.reads == "overbought" || r.reads == "oversold"
            SXTechBar(at: r.x / 100, band: (0.3, 0.7), dot: hot ? SX.thin : SX.ink, marks: [("30", 0.3), ("70", 0.7)]).padding(.top, 12)
        } else if k == "range" {
            SXTechBar(at: p.range.x, band: nil, dot: SX.ink, ends: (String(format: "%.2f", p.range.lo), String(format: "%.2f", p.range.hi)))
                .padding(.top, 12)
        } else if let a = p.ma[k] ?? nil {
            SXTechSpark(c: a.c, a: a.a).frame(height: 30).padding(.top, 10)
        }
    }
}

/// The price over the last month as an ink line, the average dashed, today's dot at the end. The canvas reaches 6 pt
/// past its frame on every side, so the dot at the edge is drawn whole, as the design lets it overflow.
private struct SXTechSpark: View {
    let c: [Double]
    let a: [Double?]
    private let o: CGFloat = 6
    var body: some View {
        Canvas { ctx, full in
            let size = CGSize(width: full.width - 2 * o, height: full.height - 2 * o)
            let all = c + a.compactMap { $0 }
            guard c.count > 1, let lo = all.min(), let hi = all.max() else { return }
            let span = hi - lo > 0 ? hi - lo : 1
            let X = { (i: Int) in o + CGFloat(i) / CGFloat(c.count - 1) * size.width }
            let Y = { (v: Double) in o + 3 + CGFloat((hi - v) / span) * (size.height - 6) }
            var avg = Path(), line = Path(), started = false
            for (i, v) in a.enumerated() {
                guard let v else { started = false; continue }
                if started { avg.addLine(to: CGPoint(x: X(i), y: Y(v))) } else { avg.move(to: CGPoint(x: X(i), y: Y(v))); started = true }
            }
            for (i, v) in c.enumerated() { i == 0 ? line.move(to: CGPoint(x: X(i), y: Y(v))) : line.addLine(to: CGPoint(x: X(i), y: Y(v))) }
            ctx.stroke(avg, with: .color(SX.muted), style: StrokeStyle(lineWidth: 1.25, dash: [4, 3]))
            ctx.stroke(line, with: .color(SX.ink), style: StrokeStyle(lineWidth: 1.75, lineJoin: .round))
            let end = CGPoint(x: X(c.count - 1), y: Y(c[c.count - 1]))
            ctx.fill(Path(ellipseIn: CGRect(x: end.x - 5.5, y: end.y - 5.5, width: 11, height: 11)), with: .color(SX.paper))
            ctx.fill(Path(ellipseIn: CGRect(x: end.x - 3.5, y: end.y - 3.5, width: 7, height: 7)), with: .color(SX.ink))
        }
        .padding(-o)
        .accessibilityHidden(true)
    }
}

/// A track with an optional band (RSI's 30 to 70), a dot where today sits, and labels under it: marks centred on
/// their place, or the two ends (the 52-week low and high) at the edges.
private struct SXTechBar: View {
    let at: Double
    let band: (Double, Double)?
    let dot: Color
    var marks: [(String, Double)] = []
    var ends: (String, String)? = nil

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(SX.track)
                    if let b = band { Rectangle().fill(SX.fill).frame(width: w * (b.1 - b.0)).offset(x: w * b.0) }
                }
                .overlay {
                    Circle().fill(dot).frame(width: 12, height: 12)
                        .background(Circle().fill(SX.paper).frame(width: 17, height: 17))
                        .position(x: w * min(1, max(0, at)), y: 4)
                }
            }
            .frame(height: 8)
            if let e = ends {
                HStack { tick(e.0); Spacer(minLength: 4); tick(e.1) }
            } else {
                GeometryReader { g in
                    ForEach(Array(marks.enumerated()), id: \.offset) { _, m in tick(m.0).position(x: g.size.width * m.1, y: 7.5) }
                }
                .frame(height: 15)
            }
        }
        .accessibilityHidden(true)
    }

    private func tick(_ t: String) -> some View {
        Text(t).sx(SXType(size: 12, line: 15, weight: .medium, style: .caption1, tracking: 0)).foregroundStyle(SX.muted).fixedSize()
    }
}
