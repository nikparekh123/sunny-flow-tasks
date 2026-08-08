//
//  TLTInsights.swift
//  Sunnyfi — TLT-only Insights (the three bond cards)
//
//  Faithful port of the handoff's TLTInsights: Hike odds · Rates & range ·
//  Vol & engine. These replace NVDA's Volatility/Protection/Vega for the TLT
//  book. Fixtures live on TLTBook; swap for the real feeds next week.
//

import SwiftUI

private func tltDec(_ v: Double, _ d: Int) -> String { String(format: "%.\(d)f", v) }
private func tltUsd(_ v: Double) -> String { "$" + Int(v.rounded()).formatted(.number.grouping(.automatic)) }

// MARK: - small parts

/// A 30-day line, drawn small — the level is the number above it, this is the shape.
private struct MiniSpark: View {
    let series: [Double]
    var height: CGFloat = 34
    var body: some View {
        GeometryReader { g in
            let lo = series.min() ?? 0, hi = series.max() ?? 1, span = max(hi - lo, 0.0001)
            let w = g.size.width, h = height
            let pts = series.indices.map { i in
                CGPoint(x: CGFloat(i) / CGFloat(max(series.count - 1, 1)) * w,
                        y: h - CGFloat((series[i] - lo) / span) * h)
            }
            ZStack {
                Path { p in for (i, pt) in pts.enumerated() { i == 0 ? p.move(to: pt) : p.addLine(to: pt) } }
                    .stroke(Ink.text, style: .init(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                if let last = pts.last { Circle().fill(Ink.text).frame(width: 6, height: 6).position(last) }
            }
        }
        .frame(height: height)
    }
}

/// A scale with a marker on it — the zones are typographic, never coloured.
private struct ScaleBar: View {
    let at: Double            // 0…100
    let marks: [String]
    var body: some View {
        VStack(spacing: 9) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.hair).frame(height: 7)
                    Rectangle().fill(Ink.text).frame(width: 2, height: 15)
                        .offset(x: CGFloat(max(0, min(100, at)) / 100) * g.size.width - 1)
                }
                .frame(height: 15)
            }
            .frame(height: 15)
            HStack(spacing: 8) {
                ForEach(Array(marks.enumerated()), id: \.offset) { i, m in
                    Text(m.uppercased()).font(InkFont.mono(10.5)).tracking(10.5 * 0.06).foregroundStyle(Ink.dim)
                        .lineLimit(1).fixedSize()
                        .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : i == marks.count - 1 ? .trailing : .center)
                }
            }
        }
        .padding(.top, 14)
    }
}

private struct RuleFoot: View {
    let label: String; let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased()).font(InkFont.mono(11)).tracking(11 * 0.08).foregroundStyle(Ink.dim)
            Text(text).font(InkFont.display(13, .regular)).foregroundStyle(Ink.dim)
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A labelled figure row inside a card body (label left, mono figure right).
private struct StatRow: View {
    let k: String; let v: String; var hue: Color = Ink.text; var first: Bool = false
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(InkFont.display(13.5, .regular)).foregroundStyle(Ink.text)
            Spacer(minLength: 0)
            Text(v).font(InkFont.mono(14.5)).tracking(14.5 * -0.02).foregroundStyle(hue)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Ink.hair).frame(height: 1) } }
    }
}

// MARK: - the three cards

private struct HikeOddsCard: View {
    private let h = TLTBook.hike
    var body: some View {
        let hot = h.odds >= 50
        return InkCard(compact: true, height: 452, stamp: (.delayed, "Fed funds futures · 15 min delayed")) {
            InkBody(compact: true) {
                InkEyebrow(cat: "Hike odds") { InkBand(skin: .mod, text: h.meeting) }
                VStack(alignment: .leading, spacing: 0) {
                    InkRoll(text: "\(h.odds)%", font: InkFont.mono(40, .medium), tracking: 40 * -0.04, color: hot ? Ink.loss : Ink.text)
                    Text("market-implied · \(h.trend)".uppercased()).font(InkFont.mono(11.5, .medium)).tracking(11.5 * 0.05)
                        .foregroundStyle(Ink.dim).padding(.top, 11).lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.top, 16)
                MiniSpark(series: h.series).padding(.top, 16)
                ScaleBar(at: Double(h.odds), marks: ["20 calm", "50 watch", "danger"])
                InkSpacer()
                VStack(spacing: 0) {
                    ForEach(Array(h.next.enumerated()), id: \.offset) { i, n in
                        StatRow(k: n.d, v: "\(n.p)%", hue: n.p >= 50 ? Ink.loss : Ink.text, first: i == 0)
                    }
                }
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
            }
            InkFoot(compact: true) { RuleFoot(label: "The rule", text: h.rule) }
        }
    }
}

private struct RatesRangeCard: View {
    private let r = TLTBook.rates
    private let spot = TLTBook.spot
    var body: some View {
        let at = ((spot - r.exit) / (r.assign - r.exit)) * 100
        let toHigh = ((r.cycleHigh - r.y10) * 100).rounded() / 100
        let dev = ((spot - r.sma25) / r.sma25) * 100
        return InkCard(compact: true, height: 452, stamp: (.delayed, "FRED · DGS10, DGS30 · daily")) {
            InkBody(compact: true) {
                InkEyebrow(cat: "Rates & range") { InkBand(skin: .mod, text: "10-year") }
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        InkRoll(text: "\(tltDec(r.y10, 2))%", font: InkFont.mono(40, .medium), tracking: 40 * -0.04, color: Ink.text)
                        Text("yields up · TLT down".uppercased()).font(InkFont.mono(11.5, .medium)).tracking(11.5 * 0.05)
                            .foregroundStyle(Ink.dim).padding(.top, 11)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 0) {
                        InkRoll(text: "\(tltDec(r.y30, 2))%", font: InkFont.mono(18, .regular), tracking: 18 * -0.03, color: Ink.text)
                        Text("30-YEAR").font(InkFont.mono(10.5)).tracking(10.5 * 0.06).foregroundStyle(Ink.dim).padding(.top, 7).fixedSize()
                    }
                    .padding(.leading, 12).overlay(alignment: .leading) { Rectangle().fill(Ink.hair).frame(width: 1) }
                }
                .padding(.top, 16)
                ScaleBar(at: at, marks: ["\(Int(r.exit)) exit", "you are here", "\(Int(r.assign)) assign"])
                InkSpacer()
                VStack(spacing: 0) {
                    StatRow(k: "From the cycle high", v: "\(tltDec(toHigh, 2)) pts", hue: toHigh <= 0.1 ? Ink.loss : Ink.text, first: true)
                    StatRow(k: "Against the 25-day", v: "\(dev >= 0 ? "+" : "−")\(tltDec(abs(dev), 1))%", hue: dev >= 0 ? Ink.gain : Ink.loss)
                }
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
            }
            InkFoot(compact: true) { RuleFoot(label: "Exit rule", text: r.rule) }
        }
    }
}

private struct VolEngineCard: View {
    private let e = TLTBook.engine
    private func fig(_ v: String, _ k: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(InkFont.mono(20, .regular)).tracking(20 * -0.03).foregroundStyle(Ink.text)
            Text(k.uppercased()).font(InkFont.mono(10.5)).tracking(10.5 * 0.06).foregroundStyle(Ink.dim).padding(.top, 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    var body: some View {
        InkCard(compact: true, height: 452, stamp: (.delayed, "Chain · 15 min delayed")) {
            InkBody(compact: true) {
                InkEyebrow(cat: "Vol & engine") { InkBand(skin: .mod, text: e.verdict) }
                VStack(alignment: .leading, spacing: 0) {
                    InkRoll(text: "\(e.spread >= 0 ? "+" : "−")\(tltDec(abs(e.spread), 1))",
                            font: InkFont.mono(40, .medium), tracking: 40 * -0.04, color: e.spread >= 0 ? Ink.gain : Ink.loss)
                    Text("implied over 20-day realized".uppercased()).font(InkFont.mono(11.5, .medium)).tracking(11.5 * 0.05)
                        .foregroundStyle(Ink.dim).padding(.top, 11).lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.top, 16)
                HStack(spacing: 10) {
                    fig(tltDec(e.iv, 1), "TLT IV"); fig(tltDec(e.hv20, 1), "20d HV"); fig("\(e.move)", "MOVE")
                }
                .padding(.top, 18)
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1).offset(y: -9) }
                InkSpacer()
                VStack(spacing: 0) {
                    HStack {
                        Text("\(e.sold) @ \(tltDec(e.price, 2))").font(InkFont.mono(13)).foregroundStyle(Ink.text).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(tltUsd(Double(e.premium))).font(InkFont.mono(14.5)).tracking(14.5 * -0.02).foregroundStyle(Ink.gain)
                    }
                    .padding(.vertical, 10)
                    StatRow(k: "Expires", v: e.expires)
                }
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
            }
            InkFoot(compact: true) { RuleFoot(label: "Re-strike", text: e.restrike) }
        }
    }
}

// MARK: - the TLT Insights section

struct TLTInsightsScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InkSectionHead(title: "Insights")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    HikeOddsCard().inkEntrance(0)
                    RatesRangeCard().inkEntrance(1)
                    VolEngineCard().inkEntrance(2)
                }
                .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 8)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
