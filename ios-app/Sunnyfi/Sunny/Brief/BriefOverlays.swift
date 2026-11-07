//
//  BriefOverlays.swift
//  Sunny
//
//  The overlays of New Home (block 33): the Time value sheet (from "Time value ›" under the account chart),
//  the economy sheet (from "See the other 7"), and the ticker chart pushed from any name tile. Sheets sit
//  inset 8 with radius 38 and a grabber, close by X, a drag down or a tap on the dim; the push comes from the
//  right and closes with X.
//
//  ⚠ THE TIME VALUE SHEET READS THE BOOK'S OWN SOLD LEGS (answer 2), never the prototype's stand-in book with
//  extra strikes. Ready to roll = under $0.05 a share left, or 90% captured (the notification design's rule).
//

import SwiftUI

// MARK: - Sample price series (the prototype's seeded walk, so lines match it)

enum SampleSeries {
    static func hash(_ s: String) -> UInt32 {
        var h: UInt32 = 2166136261
        for u in s.utf16 { h ^= UInt32(u); h = h &* 16777619 }
        return h
    }
    struct RNG {
        var a: UInt32
        mutating func next() -> Double {
            a = a &+ 0x6D2B79F5
            var t = (a ^ (a >> 15)) &* (1 | a)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4294967296
        }
    }
    /// 75 closes ending at today's price (the last 22 are the month on screen).
    static func series(_ t: String) -> [Double] {
        guard let q = SampleBook.q[t] else { return [] }
        let sg = (SampleBook.iv[t] ?? 0.3) / (252.0).squareRoot() * 0.8
        var r = RNG(a: hash(t)), s = Array(repeating: 0.0, count: 75)
        s[74] = q.0; s[73] = q.1
        for i in stride(from: 72, through: 0, by: -1) {
            let z = (r.next() + r.next() + r.next() - 1.5) * 2
            s[i] = s[i + 1] / exp(sg * z)
        }
        return s
    }
    /// About a year of weekday closes, the last 75 the series above.
    static func year(_ t: String) -> [Double] {
        let s0 = series(t), n = 470, m = n - s0.count
        guard !s0.isEmpty else { return [] }
        let sg = (SampleBook.iv[t] ?? 0.3) / (252.0).squareRoot() * 0.8
        var r = RNG(a: hash(t + " year")), c = Array(repeating: 0.0, count: n)
        for (i, x) in s0.enumerated() { c[m + i] = x }
        for i in stride(from: m - 1, through: 0, by: -1) { c[i] = c[i + 1] / exp(sg * (r.next() + r.next() + r.next() - 1.5) * 2) }
        return c
    }
}

// MARK: - Sheet chrome

struct BriefSheetChrome<Content: View>: View {
    let title: String
    let close: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(S.grabber).frame(width: 36, height: 5).frame(maxWidth: .infinity).padding(.top, 8)
            HStack {
                Text(title).sType(SType(size: 22, weight: 700, line: 28, tracking: -0.01), tabular: false).foregroundStyle(S.ink)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(S.secondary)
                        .frame(width: 30, height: 30).background(Circle().fill(S.chip))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, S.margin).padding(.top, 10)
            ScrollView { content().padding(.horizontal, S.margin).padding(.top, 14).padding(.bottom, 40) }
                .scrollIndicators(.hidden)
        }
        .background(S.sheetFill)
    }
}

// MARK: - Time value

struct TimeValueSheet: View {
    let acct: String
    let privacy: Bool
    let close: () -> Void

    struct Row: Identifiable { let id: String; let t: String; let leg: String; let left: Double; let collected: Double; let intrinsic: Double; let perShare: Double }

    var body: some View {
        let book = SampleBook.book(acct)
        let rows: [Row] = SampleBook.names.flatMap { t -> [Row] in
            guard let b = book[t], let q = SampleBook.q[t] else { return [] }
            return b.sold.enumerated().map { i, s in
                let intr = s.put ? max(0, s.k - q.0) : max(0, q.0 - s.k)
                let tv = max(0, s.now - intr)
                return Row(id: "\(t)\(i)", t: t, leg: "\(String(format: "%g", s.k)) \(s.put ? "puts" : "calls") ×\(s.q)",
                           left: tv * Double(s.q) * 100, collected: s.at * Double(s.q) * 100, intrinsic: intr, perShare: tv)
            }
        }
        let left = rows.reduce(0) { $0 + $1.left }, coll = rows.reduce(0) { $0 + $1.collected }
        let cap = coll > 0 ? 1 - left / coll : 0
        let ready = rows.filter { $0.perShare < 0.05 || ($0.collected > 0 && 1 - $0.left / $0.collected >= 0.9) || $0.intrinsic > 0 }
        BriefSheetChrome(title: "Time value", close: close) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(BriefWords.plain("$" + SampleEngine.fn(left), privacy: privacy))
                        .sType(SType(size: 34, weight: 800, line: 40, tracking: -0.02)).foregroundStyle(S.ink)
                    Text("left of \(BriefWords.plain("$" + SampleEngine.fn(coll), privacy: privacy)) collected").sType(BK.body, tabular: false).foregroundStyle(S.secondary)
                }
                VStack(alignment: .trailing, spacing: 4) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(S.chip)
                            Capsule().fill(S.green).frame(width: g.size.width * CGFloat(cap))
                        }
                    }
                    .frame(height: 8)
                    Text("\(Int((cap * 100).rounded()))% captured").sType(SType(size: 13, weight: 700, line: 16, tracking: 0)).foregroundStyle(S.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Ready to roll").sType(SType(size: 17, weight: 700, line: 22, tracking: 0), tabular: false).foregroundStyle(S.ink)
                        Spacer()
                        Text("\(ready.count) strike\(ready.count == 1 ? "" : "s")").sType(BK.small, tabular: false).foregroundStyle(S.secondary)
                    }
                    Text("Under $0.05 a share left, or 90% captured").sType(BK.small, tabular: false).foregroundStyle(S.secondary)
                }
                if ready.isEmpty {
                    Text("Nothing ready yet.").sType(BK.body, tabular: false).foregroundStyle(S.secondary)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(ready) { r in
                                VStack(alignment: .leading, spacing: 4) {
                                    BLogo(ticker: r.t, size: 28)
                                    Text(SampleBook.company[r.t] ?? r.t).sType(BK.row, tabular: false).foregroundStyle(S.ink).padding(.top, 6)
                                    Text(r.leg).sType(BK.rowSub, tabular: false).foregroundStyle(S.secondary)
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text(BriefWords.plain("$" + SampleEngine.fn(r.left), privacy: privacy)).sType(SType(size: 22, weight: 800, line: 26, tracking: 0)).foregroundStyle(S.ink)
                                        Text("left").sType(BK.rowSub, tabular: false).foregroundStyle(S.secondary)
                                    }
                                    .padding(.top, 8)
                                    if r.intrinsic > 0 {
                                        Text("$\(String(format: "%.2f", r.intrinsic)) in the money").sType(SType(size: 12, weight: 600, line: 15, tracking: 0)).foregroundStyle(S.red)
                                        Text("Roll before Friday").sType(SType(size: 12, weight: 600, line: 15, tracking: 0), tabular: false).foregroundStyle(S.red)
                                    } else {
                                        Text("\(Int(((1 - r.left / max(r.collected, 1)) * 100).rounded()))% captured").sType(SType(size: 12, weight: 600, line: 15, tracking: 0)).foregroundStyle(S.act)
                                        Text("Roll to next week").sType(SType(size: 12, weight: 600, line: 15, tracking: 0), tabular: false).foregroundStyle(S.act)
                                    }
                                }
                                .padding(14)
                                .frame(width: 148, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(S.chip))
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                let byName = Dictionary(grouping: rows, by: \.t)
                let order = byName.keys.sorted { byName[$0]!.reduce(0) { $0 + $1.left } > byName[$1]!.reduce(0) { $0 + $1.left } }
                VStack(spacing: 0) {
                    ForEach(order, id: \.self) { t in
                        let rs = byName[t]!, l = rs.reduce(0) { $0 + $1.left }, c = rs.reduce(0) { $0 + $1.collected }
                        let k = c > 0 ? 1 - l / c : 0
                        BHairline()
                        HStack(spacing: 12) {
                            BLogo(ticker: t, size: 28)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(SampleBook.company[t] ?? t) · \(rs.map(\.leg).joined(separator: ", "))")
                                    .sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink).lineLimit(1)
                                HStack(spacing: 8) {
                                    GeometryReader { g in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(S.chip)
                                            Capsule().fill(S.green).frame(width: g.size.width * CGFloat(k))
                                        }
                                    }
                                    .frame(height: 6)
                                    Text("\(Int((k * 100).rounded()))%").sType(SType(size: 12, weight: 700, line: 15, tracking: 0)).foregroundStyle(S.green)
                                }
                            }
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(BriefWords.plain("$" + SampleEngine.fn(l), privacy: privacy)).sType(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink)
                                Text("of \(BriefWords.plain("$" + SampleEngine.fn(c), privacy: privacy))").sType(BK.rowSub).foregroundStyle(S.secondary)
                            }
                            .frame(width: 72, alignment: .trailing)
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }
}

// MARK: - The economy (12 indicators)

struct EconomySheet: View {
    let close: () -> Void
    var body: some View {
        let e = BriefSample.sheets["economy"]
        BriefSheetChrome(title: e["title"].string ?? "The economy", close: close) {
            VStack(alignment: .leading, spacing: 14) {
                Text(e["sub"].string ?? "").sType(BK.small, tabular: false).foregroundStyle(S.secondary)
                ForEach(Array(e["indicators"].array.enumerated()), id: \.offset) { _, c in
                    BIndicatorCard(c: c, width: nil)
                }
            }
        }
    }
}

// MARK: - Ticker chart (pushed from a name tile)

struct TickerChartPage: View {
    let t: String
    let acct: String
    let close: () -> Void
    @State private var range = "3M"
    @State private var layer = "Positions"

    var body: some View {
        let q = SampleBook.q[t] ?? (0, 0)
        let mv = q.1 > 0 ? (q.0 - q.1) / q.1 * 100 : 0
        let all = SampleSeries.year(t)
        let n = ["1W": 5, "1M": 22, "3M": 63, "YTD": 210, "1Y": 252, "All": all.count][range] ?? 63
        let pts = Array(all.suffix(n + 1))
        let ch = (pts.last ?? 0) - (pts.first ?? 0), chp = (pts.first ?? 1) > 0 ? ch / pts.first! * 100 : 0
        let lines = positionLines()
        ZStack(alignment: .top) {
            SBackground()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(S.ink)
                            .frame(width: 44, height: 44).glassEffect(.regular, in: .circle)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Back")
                    HStack(spacing: 8) {
                        BLogo(ticker: t, size: 24)
                        Text(t).font(.system(size: 15, weight: .bold)).foregroundStyle(S.ink)
                        Text(String(format: "$%.2f", q.0)).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(S.ink)
                        Text(String(format: "%.2f%%", abs(mv))).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(mv < 0 ? S.red : S.green)
                    }
                    .padding(.horizontal, 12).frame(height: 44).glassEffect(.regular, in: .capsule)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(SampleBook.company[t] ?? t).sType(BK.small, tabular: false).foregroundStyle(S.secondary)
                    HStack(spacing: 6) {
                        Text(String(format: "$%.2f %.2f%%", abs(ch), abs(chp))).sType(SType(size: 17, weight: 700, line: 22, tracking: 0)).foregroundStyle(ch < 0 ? S.red : S.green)
                        Text(["1W": "past week", "1M": "past month", "3M": "past 3 months", "YTD": "this year", "1Y": "past year", "All": "since the start"][range] ?? "")
                            .sType(SType(size: 17, weight: 500, line: 22, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    }
                }
                TickerLine(pts: pts, lines: layer == "Positions" ? lines : [], up: ch >= 0).frame(maxHeight: .infinity)
                HStack {
                    ForEach(["1W", "1M", "3M", "YTD", "1Y", "All"], id: \.self) { r in
                        Button { withAnimation(S.morph) { range = r } } label: {
                            Text(r).font(.system(size: 14, weight: r == range ? .bold : .medium)).foregroundStyle(r == range ? S.sheetFill : S.secondary)
                                .frame(width: 44, height: 30).background(Capsule().fill(r == range ? S.ink : .clear))
                        }.buttonStyle(.plain)
                        if r != "All" { Spacer() }
                    }
                }
                HStack(spacing: 8) {
                    ForEach(["Positions", "Technicals", "Walls"], id: \.self) { l in
                        Button { withAnimation(.easeOut(duration: 0.2)) { layer = l } } label: {
                            Text(l).font(.system(size: 15, weight: .semibold)).foregroundStyle(layer == l ? S.sheetFill : S.ink)
                                .padding(.horizontal, 16).frame(height: 44)
                                .background(Capsule().fill(layer == l ? S.ink : .clear))
                                .glassEffect(.regular, in: .capsule)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, S.margin)
        }
    }

    /// The legs held in this name, as labelled lines on the price: hedge (OTM) calls and LEAPS dotted, sold calls solid.
    private func positionLines() -> [(k: Double, label: String, solid: Bool)] {
        guard let b = SampleBook.book(acct)[t] else { return [] }
        var out: [(Double, String, Bool)] = []
        for x in b.bought where x.kind != .ins { out.append((x.k, "\(x.kind == .leaps ? "LEAPS" : "Hedge") \(String(format: "%g", x.k)) ×\(x.q)", false)) }
        for s in b.sold { out.append((s.k, "Sold \(s.put ? "put" : "call") \(String(format: "%g", s.k)) ×\(s.q)", true)) }
        for x in b.bought where x.kind == .ins { out.append((x.k, "Puts \(String(format: "%g", x.k)) ×\(x.q)", false)) }
        return out
    }
}

private struct TickerLine: View {
    let pts: [Double]
    let lines: [(k: Double, label: String, solid: Bool)]
    let up: Bool
    var body: some View {
        GeometryReader { g in
            let lo0 = pts.min() ?? 0, hi0 = pts.max() ?? 1
            let inRange = lines.map(\.k).filter { $0 >= lo0 * 0.9 && $0 <= hi0 * 1.1 }
            let lo = min(lo0, inRange.min() ?? lo0) * 0.98, hi = max(hi0, inRange.max() ?? hi0) * 1.02
            let W = g.size.width - 40, H = g.size.height
            let X = { (i: Int) -> CGFloat in CGFloat(i) / CGFloat(max(1, pts.count - 1)) * W }
            let Y = { (p: Double) -> CGFloat in CGFloat((hi - p) / (hi - lo)) * H }
            ZStack(alignment: .topLeading) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                    if l.k >= lo && l.k <= hi {
                        Path { $0.move(to: CGPoint(x: 0, y: Y(l.k))); $0.addLine(to: CGPoint(x: W, y: Y(l.k))) }
                            .stroke(S.ink.opacity(l.solid ? 0.8 : 0.5), style: StrokeStyle(lineWidth: 1, dash: l.solid ? [] : [2, 3]))
                        Text(l.label).font(.system(size: 10, weight: .bold)).foregroundStyle(S.ink)
                            .padding(.horizontal, 4).background(S.dyn(0xF1F2F4, 0x0A0F0C))
                            .position(x: 52, y: Y(l.k))
                    }
                }
                Path { p in for (i, v) in pts.enumerated() { let pt = CGPoint(x: X(i), y: Y(v)); i == 0 ? p.move(to: pt) : p.addLine(to: pt) } }
                    .stroke(up ? S.green : S.red, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                if let last = pts.last {
                    Text(String(format: "%.2f", last)).font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                        .padding(.horizontal, 5).frame(height: 18).background(RoundedRectangle(cornerRadius: 4).fill(up ? S.green : S.red))
                        .position(x: W + 22, y: Y(last))
                }
            }
        }
    }
}
