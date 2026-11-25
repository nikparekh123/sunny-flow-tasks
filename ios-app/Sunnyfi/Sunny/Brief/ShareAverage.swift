//
//  ShareAverage.swift
//  Sunny
//
//  Share average (handoff 2026-11-18, round 157a; Nik's rule of 15 Nov 2026): one card per name holding shares, on the
//  weekend Home (section "Share average" after Your book, cards 341 wide that snap sideways, only the names whose
//  average moved this week, biggest move first, the rest in one quiet line) and in Search. Never on Positions.
//  New average = (shares × average paid − premium kept) ÷ shares; premium kept = every close of a call or put sold on
//  the ticker since the book started (Nik, 24 Nov 2026: premium kept only). On this card down is good: a lower average
//  is a win. Data: sunny-home `share_avg` (index.ts), s2 = [calls sold, puts sold] a share.
//    Header: logo, ticker, N shares; "Down $8.13" or "Up" in ink, "Held" grey.
//    Summary: "Ahead of the price by $X a share." then "Sold calls and puts took $Y off the $Z you paid."
//    Chart: the week's closes, the average from last Friday to now, the gap shaded (grey under or over the price),
//    Paid dashed, tags Avg · Price · Paid on the right.
//    What moved it · a share · since Sep 1: two tiles, Calls sold and Puts sold, in the Performance legend colours
//    (up is a loss, +).
//  No em dashes in any words here.
//  Focus (25 Nov): the words carry no colour ("Down $8.13", the summary's figures and the tiles are ink; Down, Up,
//  Ahead, took and added say which way, and a tile that pushed the average up starts with +); the gap's shading is
//  green and red with their legend squares (the focus reference keeps them).
//

import SwiftUI

struct ShareAvgRow: View {
    let card: JSONValue
    let privacy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(card["names"].array.enumerated()), id: \.offset) { _, a in
                        ShareAvgCard(a: a, privacy: privacy).frame(width: 341)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, S.margin, for: .scrollContent)
            .accessibilityLabel("Share averages, swipe for more")
            if let n = card["note"].string, !n.isEmpty {
                Text(n).sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.secondary)
                    .padding(.horizontal, S.margin)
            }
        }
    }
}

struct ShareAvgCard: View {
    let a: JSONValue
    let privacy: Bool

    static let labels = ["Calls sold", "Puts sold"]
    static let colors: [Color] = [S.dyn(0x1C7840, 0x1C7840), S.dyn(0x3E6AE1, 0x3E6AE1)]
    private let H: CGFloat = 140

    private func m2(_ v: Double) -> String { String(format: "$%.2f", abs(v)) }

    var body: some View {
        let t = a["t"].string ?? "", sh = a["sh"].double ?? 0, paid = a["paid"].double ?? 0, px = a["px"].double ?? 0
        let w = a["w"].array.compactMap(\.double), avg = max(0, w.last ?? paid), wk = a["wk"].double ?? 0
        let flat = abs(wk) < 0.005, gap = px - avg, ahead = gap > 0, at = abs(gap) < 0.005, pd0 = avg - paid
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                BLogo(ticker: t, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(t).sType(SType(size: 17, weight: 700, line: 22, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Text(privacy ? "•,••• shares" : "\(Int(sh.rounded()).formatted(.number.grouping(.automatic))) shares").sType(SType(size: 13, weight: 500, line: 17, tracking: 0)).foregroundStyle(S.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(flat ? "Held" : "\(wk < 0 ? "Down" : "Up") \(m2(wk))").sType(SType(size: 15, weight: 600, line: 20, tracking: 0))
                        .foregroundStyle(flat ? S.secondary : S.ink)
                    Text("this week").sType(SType(size: 12, weight: 500, line: 15, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                }
            }
            summary(at: at, ahead: ahead, gap: gap, pd0: pd0, paid: paid)
            chart(a).frame(height: H)
            tiles(a["s2"].array.compactMap(\.double))
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 18)
        .frame(maxHeight: .infinity, alignment: .top)
        .sunnyGlass(radius: 24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(t), share average \(m2(avg)), \(flat ? "held" : (wk < 0 ? "down " : "up ") + m2(wk)) this week, paid \(m2(paid)), price \(m2(px))")
    }

    private func summary(at: Bool, ahead: Bool, gap: Double, pd0: Double, paid: Double) -> some View {
        let even = abs(pd0) < 0.005
        let first: Text = at ? Text("At the price.").fontWeight(.semibold)
            : Text("\(ahead ? "Ahead of" : "Behind") the price by ").fontWeight(.semibold) + Text(m2(gap)).fontWeight(.semibold)
                + Text(" a share.").fontWeight(.semibold)
        let rest: Text = even ? Text(" Sold calls and puts left the \(m2(paid)) you paid where it was.")
            : Text(" Sold calls and puts \(pd0 > 0 ? "added " : "took ")") + Text(m2(pd0))
                + Text("\(pd0 > 0 ? " to" : " off") the \(m2(paid)) you paid.")
        return (first + rest).sType(SType(size: 15, weight: 400, line: 21, tracking: 0)).foregroundStyle(S.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The week's closes (the price), the average from last Friday to now, the gap shaded, Paid dashed, three tags.
    private func chart(_ a: JSONValue) -> some View {
        let cl = a["cl"].array.compactMap(\.double), w = a["w"].array.compactMap(\.double), paid = a["paid"].double ?? 0
        let px = a["px"].double ?? (cl.last ?? 0), days = a["days"].array.compactMap(\.string)
        let n = cl.count, avg0 = w.first ?? paid, avg1 = max(0, w.last ?? paid)
        let vals = cl + [avg0, avg1, paid]
        var lo = vals.min() ?? 0, hi = vals.max() ?? 1
        let pd = max((hi - lo) * 0.14, hi * 0.004); lo = max(0, lo - pd); hi += pd
        let TAGW: CGFloat = 76
        return GeometryReader { g in
            let pw = max(1, g.size.width - TAGW)
            let X = { (i: Double) in n > 1 ? CGFloat(i / Double(n - 1)) * pw : pw / 2 }, Y = { (v: Double) in CGFloat((hi - v) / (hi - lo)) * H }
            let aAt = { (i: Double) in avg0 + (avg1 - avg0) * (n > 1 ? i / Double(n - 1) : 1) }
            // The gap, a quad per day, split where the average crosses the price.
            let quads = { (green: Bool) -> [[CGPoint]] in
                var out: [[CGPoint]] = []
                let quad = { (i0: Double, A0: Double, P0: Double, i1: Double, A1: Double, P1: Double) -> [CGPoint] in
                    [CGPoint(x: X(i0), y: Y(A0)), CGPoint(x: X(i1), y: Y(A1)), CGPoint(x: X(i1), y: Y(P1)), CGPoint(x: X(i0), y: Y(P0))]
                }
                for i in 0..<max(0, n - 1) {
                    let a0 = aAt(Double(i)), a1 = aAt(Double(i + 1)), p0 = cl[i], p1 = cl[i + 1], d0 = a0 - p0, d1 = a1 - p1
                    if d0 * d1 >= 0 { if (d0 + d1 <= 0) == green { out.append(quad(Double(i), a0, p0, Double(i + 1), a1, p1)) } }
                    else {
                        let f = d0 / (d0 - d1), im = Double(i) + f, vm = a0 + (a1 - a0) * f
                        if (d0 <= 0) == green { out.append(quad(Double(i), a0, p0, im, vm, vm)) }
                        if (d1 <= 0) == green { out.append(quad(im, vm, vm, Double(i + 1), a1, p1)) }
                    }
                }
                return out
            }
            let shade = { (green: Bool) in Path { p in for q in quads(green) { p.addLines(q); p.closeSubpath() } } }
            // Tags on the right, at least 20 apart: Avg (ink), Price (chip), Paid (plain).
            let tg: [(k: String, y: CGFloat, n: String, s: String)] = [("a", Y(avg1), String(format: "%.2f", avg1), "Avg"), ("x", Y(px), String(format: "%.2f", px), "Price"), ("p", Y(paid), String(format: "%.2f", paid), "Paid")]
                .sorted { $0.1 < $1.1 }
            let cs: [CGFloat] = {
                var c = tg.map { max(9, min(H - 9, $0.y)) }
                for i in 1..<c.count where c[i] < c[i - 1] + 20 { c[i] = c[i - 1] + 20 }
                for i in stride(from: c.count - 1, through: 0, by: -1) { let mx = i == c.count - 1 ? H - 9 : c[i + 1] - 20; if c[i] > mx { c[i] = mx } }
                return c
            }()
            ZStack(alignment: .topLeading) {
                // The gap keeps green and red, so its legend still reads (as the focus reference draws it).
                shade(true).fill(S.green.opacity(0.16))
                shade(false).fill(S.red.opacity(0.16))
                Path { p in p.move(to: CGPoint(x: 0, y: Y(paid))); p.addLine(to: CGPoint(x: pw, y: Y(paid))) }
                    .stroke(S.secondary.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Path { p in for (i, v) in cl.enumerated() { let pt = CGPoint(x: X(Double(i)), y: Y(v)); if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) } } }
                    .stroke(S.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                Path { p in p.move(to: CGPoint(x: X(0), y: Y(avg0))); p.addLine(to: CGPoint(x: X(Double(max(0, n - 1))), y: Y(avg1))) }
                    .stroke(S.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                Circle().fill(S.secondary.opacity(0.6)).frame(width: 6, height: 6).position(x: X(Double(max(0, n - 1))), y: Y(px))
                Circle().strokeBorder(S.ink, lineWidth: 1.5).background(Circle().fill(S.paper)).frame(width: 8, height: 8).position(x: X(0), y: Y(avg0))
                Circle().strokeBorder(S.ink, lineWidth: 2.5).background(Circle().fill(S.paper)).frame(width: 12, height: 12).position(x: X(Double(max(0, n - 1))), y: Y(avg1))
                ForEach(Array(tg.enumerated()), id: \.offset) { i, x in
                    Path { p in p.move(to: CGPoint(x: pw, y: x.y)); p.addLine(to: CGPoint(x: pw + 8, y: cs[i])) }.stroke(S.secondary.opacity(0.4), lineWidth: 1)
                    HStack(spacing: 3) {
                        Text(x.n).font(.inter(12, x.k == "a" ? 700 : x.k == "x" ? 600 : 500, tabular: true))
                            .foregroundStyle(x.k == "a" ? S.dyn(0xFAFAFA, 0x171717) : x.k == "x" ? S.ink : S.secondary)
                        Text(x.s).font(.inter(10, 500)).foregroundStyle(x.k == "a" ? S.dyn(0xAAAAAA, 0x474747) : S.secondary)
                    }
                    .padding(.horizontal, x.k == "p" ? 3 : 7).frame(height: 18)
                    .background(Capsule().fill(x.k == "a" ? S.ink : x.k == "x" ? S.dynA(0x808080, 0.12, 0xFAFAFA, 0.12) : .clear))
                    .fixedSize()
                    .offset(x: pw + 10, y: cs[i] - 9)
                }
                if days.count > 1 {
                    Text(PositionsModel.md(days[0])).font(.inter(11, 500)).foregroundStyle(S.secondary).fixedSize().offset(x: 0, y: H + 2)
                    Text(PositionsModel.md(days[days.count - 1])).font(.inter(11, 500)).foregroundStyle(S.secondary).fixedSize()
                        .frame(width: pw, alignment: .trailing).offset(y: H + 2)
                }
            }
        }
        .padding(.bottom, 16)
        .accessibilityElement()
        .accessibilityLabel("Share average by Friday, \(String(format: "%.2f", avg0)) to \(String(format: "%.2f", avg1)); paid \(String(format: "%.2f", paid)), price \(String(format: "%.2f", px)). The average is \(avg1 < px ? "under" : "over") the price.")
    }

    /// What moved it · a share · since the book started: Calls sold and Puts sold, the Performance legend colours; up is
    /// a loss.
    private func tiles(_ s2: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What moved it · a share · since Sep 1").sType(SType(size: 12, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: Self.labels.count), alignment: .leading, spacing: 10) {
                ForEach(Array(Self.labels.enumerated()), id: \.offset) { j, l in
                    let v = s2.indices.contains(j) ? s2[j] : 0, z = v == 0, tz = !z && abs(v) < 0.005
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).fill(Self.colors[j]).frame(width: 8, height: 8)
                            Text(l).sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary).lineLimit(1)
                        }
                        Text(z ? "-" : tz ? "under 1¢" : v > 0 ? SF.signed(v, m2(v)) : m2(v)).sType(SType(size: 15, weight: 600, line: 20, tracking: 0))
                            .foregroundStyle(z || tz ? S.secondary : S.ink)
                    }
                    .opacity(z ? 0.35 : 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(l), " + (z ? "nothing kept yet" : tz ? "under a cent" : v > 0 ? "pushed the average up \(m2(v)) a share" : "took \(m2(v)) a share off the average"))
                }
            }
        }
    }
}
