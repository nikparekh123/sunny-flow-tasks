//
//  BriefCardsBook.swift
//  Sunny
//
//  Sections 2 to 4 of New Home (README 5.2): What's moving, To decide, Coming up and Remember, Earnings ahead,
//  Your results and Results, Closed and rolled, After hours, Tomorrow's orders, Theta · October, Payback and
//  the Thesis check. Every money figure follows privacy; dividends always sit on their own line.
//  Sizes and gaps from SunnyBriefs.dc.html: blocks 16 apart in a card, the title and its sub 4 apart.
//

import SwiftUI

/// The book cards' own measures from the design's CSS.
enum BB {
    /// The design's --fill: rgba(118,118,128,.12) light, .24 dark (bands, boxes inside cards, quiet buttons).
    static let fill = S.dynA(0x767680, 0.12, 0x767680, 0.24)
    static let body = SType(size: 15, weight: 500, line: 21, tracking: 0)
    static let big = SType(size: 40, weight: 800, line: 44, tracking: -0.03)
    static let bigSub = SType(size: 14, weight: 500, line: 19, tracking: 0)
    static let legend = SType(size: 12, weight: 700, line: 15, tracking: 0)
    static let axis = SType(size: 11, weight: 500, line: 14, tracking: 0)
    static let note = SType(size: 12, weight: 500, line: 15, tracking: 0)
}

/// Marks along a width: each child at `at` of it, pulled back by `anchor` of its own width
/// (CSS `left: at%` with `translateX(-anchor%)`). As tall as the tallest child.
struct BAxis: Layout {
    var marks: [(at: CGFloat, anchor: CGFloat)]
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            let m: (at: CGFloat, anchor: CGFloat) = marks.isEmpty ? (0, 0) : marks[min(i, marks.count - 1)]
            v.place(at: CGPoint(x: b.minX + b.width * m.at - s.width * m.anchor, y: b.minY), proposal: ProposedViewSize(s))
        }
    }
}

/// A card's title over its sub line, 4 apart.
private struct BHead: View {
    let card: JSONValue
    var privacy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            BTitle(t: card["title"].string)
            BSub(t: card["subtitle"].string, privacy: privacy, type: BK.cardSub)
        }
    }
}

/// Week or month labels under a bar row: 11/14 medium secondary, the last one 800 ink.
private struct BBarLabels: View {
    let labels: [String]
    var spacing: CGFloat = 10
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, l in
                let last = i == labels.count - 1
                Text(l).sType(SType(size: 11, weight: last ? 800 : 500, line: 14, tracking: 0), tabular: false)
                    .foregroundStyle(last ? S.ink : S.secondary)
                    .lineLimit(dts > .large ? nil : 1).minimumScaleFactor(dts > .large ? 1 : 0.8)   // wraps only at large text (Audit 6)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: dts > .large)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - What's moving (market hours)

/// Each name's move today against the move its options priced for today: a grey band is the priced move,
/// the dot is where the name is (coloured when it is past the band). Track ↓6% to ↑6%, labels at ↓5%, Flat, ↑5%.
struct BWhatsMoving: View {
    let card: JSONValue
    let privacy: Bool

    /// A row spoken: "Nike, down 1.7%, priced move 2.2%", or "..., past its priced move of 3.0%".
    static func rowSays(_ r: JSONValue) -> String {
        let t = r["ticker"].string ?? ""
        let name = r["name"].string ?? SampleBook.company[t] ?? t
        let mv = r["movePct"].double
        let move = BSay.move(r["move"].string ?? mv.map { String(format: "%.1f%%", abs($0)) }, color: r["moveColor"].string, signed: mv)
        let priced = r["pricedPct"].double.map { String(format: "%.1f%%", $0) }
        let band = priced.map { r["pastPricedMove"].bool ? "past its priced move of \($0)" : "priced move \($0)" }
        return BSay.join([name, move, band])
    }

    /// The scale's labels: three at ↓5%, Flat and ↑5% of the ↓6% to ↑6% track, else spread evenly; each centred.
    static func axisMarks(_ n: Int) -> [(at: CGFloat, anchor: CGFloat)] {
        if n == 3 { return [(at(-5), 0.5), (0.5, 0.5), (at(5), 0.5)] }
        return (0..<n).map { (CGFloat($0) / CGFloat(max(1, n - 1)), 0.5) }
    }

    /// Where a move sits on the track: clamp(2%, 98%, 50% + move / 6 × 50%).
    static func at(_ m: Double) -> CGFloat { CGFloat(min(98, max(2, 50 + m / 6 * 50)) / 100) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BHead(card: card)
            BBody(v: card["body"], privacy: privacy, type: BB.body)
            // Rows: 26 logo, the track, the move in a 56 column, 10 apart; rows 10 apart.
            VStack(spacing: 10) {
                ForEach(Array(card["rows"].array.enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 10) {
                        BLogo(ticker: r["ticker"].string, size: 26)
                        GeometryReader { g in
                            let w = g.size.width, pos = { (p: Double) -> CGFloat in w * Self.at(p) }
                            let pr = r["pricedPct"].double ?? 0, mv = r["movePct"].double ?? 0, past = r["pastPricedMove"].bool
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 1).fill(BB.fill).frame(width: w, height: 2).offset(y: 7)
                                Capsule().fill(BB.fill).frame(width: max(0, pos(pr) - pos(-pr)), height: 12).offset(x: pos(-pr), y: 2)
                                RoundedRectangle(cornerRadius: 1).fill(S.secondary.opacity(0.5)).frame(width: 1.5, height: 16).offset(x: w / 2 - 0.75)
                                Circle().fill(past ? BK.color(r["moveColor"].string) : S.ink).frame(width: 10, height: 10)
                                    .background(Circle().fill(S.paper).padding(-2))
                                    .offset(x: pos(mv) - 5, y: 3)
                            }
                        }
                        .frame(height: 16)
                        Text(r["move"].string ?? "").sType(SType(size: 14, weight: 800, line: 17, tracking: 0))
                            .foregroundStyle(BK.color(r["moveColor"].string)).lineLimit(1).fixedSize()
                            .frame(minWidth: 56, alignment: .trailing)   // one line at any text size (Pass 5)
                    }
                    // One stop per name (the logo is hidden, so the name is said here): "Nike, down 1.7%, priced move 2.2%".
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.rowSays(r))
                }
            }
            // The scale under the track (6 up from the 16 gap): ↓ 5% at 8.33%, Flat at 50%, ↑ 5% at 91.67%.
            HStack(spacing: 10) {
                Color.clear.frame(width: 26, height: 1)
                let ax = card["axis"].array.compactMap(\.string)
                BAxis(marks: Self.axisMarks(ax.count)) {
                    ForEach(Array(ax.enumerated()), id: \.offset) { _, a in
                        Text(a).sType(BB.axis, tabular: false).foregroundStyle(S.secondary)
                    }
                }
                Color.clear.frame(width: 56, height: 1)
            }
            .padding(.top, -6)
            .accessibilityHidden(true)   // the scale; each row says its own move
            if let l = card["legend"].string {
                HStack(spacing: 6) {
                    Capsule().fill(BB.fill).frame(width: 18, height: 10)
                    Text(l).sType(BB.legend, tabular: false).foregroundStyle(S.ink)
                }
                .accessibilityElement(children: .combine)
            }
            if let w = card["watchlistLine"].string {
                VStack(alignment: .leading, spacing: 0) {
                    BHairline()
                    Text(w).sType(SType(size: 14, weight: 600, line: 19, tracking: 0), tabular: false).foregroundStyle(S.ink)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                }
            }
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}

// MARK: - To decide (market hours)

struct BToDecide: View {
    let card: JSONValue
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BHead(card: card)
            BBody(v: card["body"], privacy: privacy, type: BB.body)
            let w = card["whatIf"]
            if !w.isNull {
                // The what-if box: padding 12, radius 16, the design's fill; header, chart, legend 8 apart.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        HStack(spacing: 6) {
                            Text(w["label"].string ?? "What if").sType(SType(size: 12, weight: 700, line: 15, tracking: 0), tabular: false)
                                .foregroundStyle(S.ink).lineLimit(1)
                                .padding(.horizontal, 9).frame(height: 22)
                                .overlay(Capsule().strokeBorder(S.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                            Text(w["title"].string ?? "").sType(SType(size: 14, weight: 700, line: 18, tracking: 0), tabular: false)
                                .foregroundStyle(S.ink).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text(w["by"].string ?? "").sType(SType(size: 12, weight: 500, line: 15, tracking: 0), tabular: false)
                            .foregroundStyle(S.secondary).lineLimit(1).fixedSize()
                    }
                    .accessibilityElement(children: .combine)
                    BWhatIfChart(labels: w["chartLabels"].array)
                    HStack(spacing: 12) {
                        ForEach(Array(w["legend"].array.enumerated()), id: \.offset) { i, l in
                            HStack(spacing: 5) {
                                let keep = i == 0 && w["legend"].array.count > 1
                                Path { $0.move(to: CGPoint(x: 0, y: 1)); $0.addLine(to: CGPoint(x: 14, y: 1)) }
                                    .stroke(keep ? S.secondary : S.ink, style: StrokeStyle(lineWidth: keep ? 1.5 : 2.25, dash: keep ? [3, 2.5] : []))
                                    .frame(width: 14, height: 2)
                                Text(l["t"].string ?? "").sType(BB.legend, tabular: false).foregroundStyle(BK.color(l["c"].string))
                            }
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BB.fill))
            }
            BriefSentence(BriefSpan.list(card["footer"]), base: SType(size: 15, weight: 600, line: 21, tracking: 0), boldWeight: 600, privacy: privacy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}

/// The what-if's picture (SunnyBriefs `pay(t, roll)`): P&L by the what-if's date across the name's price, keeping the
/// sold calls (dashed) or rolling them up (solid), green above zero and red below, the strikes (grey dashes, labels
/// under), the walls (coloured dashes, labels on two rows over the chart) and Today. Drawn in the design's 252 × 124
/// box and scaled to the width, lines and the Today word with it; the HTML labels keep their 12 pt.
struct BWhatIfChart: View {
    let labels: [JSONValue]
    @Environment(BriefState.self) private var brief

    struct Mark { let x: CGFloat; let y: CGFloat; let l: String; let c: Color }
    struct Model {
        var act: [CGPoint] = [], keep: [CGPoint] = [], fill: [CGPoint] = []
        var zy: CGFloat = 69, today = CGPoint(x: 126, y: 69)
        var strikes: [CGFloat] = [], strikeLabels: [Mark] = []
        var walls: [(x: CGFloat, c: Color)] = [], wallLabels: [Mark] = []
    }

    /// Strikes and walls come from the card's labels; the P&L from the sample book (the name whose sold call sits at
    /// the kept strike), or, with no book to read, 100 shares and that call.
    static func model(_ labels: [JSONValue], acct: String?) -> Model {
        let num = { (t: String) -> Double? in Double(t.split(separator: " ").last ?? "") }
        let fk = { (k: Double) -> String in k.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(k)) : String(format: "%.1f", k) }
        let ks = labels.filter { $0["kind"].string == "strike" }.compactMap { $0["t"].string.flatMap(num) }
        guard let keepK = ks.first, let rollK = ks.last else { return Model() }
        let book = acct.map(SampleBook.book) ?? [:]
        let t = SampleBook.names.first { book[$0]?.sold.contains { !$0.put && $0.k == keepK } == true }
        let p0 = t.flatMap { SampleBook.q[$0]?.0 } ?? (ks.min()! + ks.max()!) / 2
        let shares = Double(t.flatMap { book[$0]?.shares } ?? 100)
        let sold = t.flatMap { book[$0]?.sold } ?? [SampleBook.Sold(k: keepK, put: false, q: 1, at: 0, now: 0)]
        let iv = t.flatMap { SampleBook.iv[$0] } ?? 0.35
        let sc = sold.first { !$0.put && $0.k == keepK }
        let p2 = SampleEngine.bs(p0, rollK, 8.0 / 365, iv, put: false)
        func base(_ S: Double) -> Double {
            sold.reduce(shares * (S - p0)) { $0 + Double($1.q) * 100 * ($1.now - ($1.put ? max(0, $1.k - S) : max(0, S - $1.k))) }
        }
        func rolled(_ S: Double) -> Double {
            guard let c = sc, rollK != keepK else { return base(S) }
            return base(S) - Double(c.q) * 100 * (c.now - max(0, S - c.k)) + Double(c.q) * 100 * (p2 - max(0, S - rollK))
        }
        let r = max(0.06, ks.map { abs($0 / p0 - 1) + 0.03 }.max() ?? 0), lo = p0 * (1 - r), hi = p0 * (1 + r)
        let xs = ([lo, hi] + ks.filter { $0 > lo && $0 < hi }).sorted()
        let vals = xs.map(rolled) + xs.map(base) + [0]
        let mn = vals.min() ?? 0, mx = vals.max() ?? 1, span = mx - mn == 0 ? 1 : mx - mn
        let Y = { (v: Double) -> CGFloat in CGFloat(28 + (mx - v) / span * 82) }
        let X = { (S: Double) -> CGFloat in CGFloat((S - lo) / (hi - lo) * 252) }
        var m = Model()
        m.zy = Y(0)
        m.act = xs.map { CGPoint(x: X($0), y: Y(rolled($0))) }
        m.keep = rollK != keepK ? xs.map { CGPoint(x: X($0), y: Y(base($0))) } : []
        for (i, S) in xs.enumerated() {
            if i > 0 {
                let a = rolled(xs[i - 1]), c = rolled(S)
                if (a < 0) != (c < 0) { m.fill.append(CGPoint(x: X(xs[i - 1] + (S - xs[i - 1]) * (a / (a - c))), y: m.zy)) }
            }
            m.fill.append(CGPoint(x: X(S), y: Y(rolled(S))))
        }
        m.today = CGPoint(x: X(p0), y: Y(rolled(p0)))
        m.strikes = ks.map(X)
        m.strikeLabels = ks.prefix(3).map { Mark(x: X($0), y: 122, l: fk($0), c: S.secondary) }
        // Walls in view, by strike, at most 4; close walls of one kind share a label; labels take the first of two
        // rows (9 and 21) with room, clear of Today and of each other, or are left off.
        let wv = labels.filter { $0["kind"].string == "wall" }.compactMap { l -> (k: Double, ty: String, c: Color)? in
            guard let s = l["t"].string, let k = num(s) else { return nil }
            return (k, String(s.split(separator: " ").first ?? ""), BK.color(l["c"].string))
        }.filter { $0.k > lo && $0.k < hi }.sorted { $0.k < $1.k }.prefix(4)
        m.walls = wv.map { (X($0.k), $0.c) }
        var groups: [(ty: String, ks: [Double], xs: [CGFloat], c: Color)] = []
        for w in wv {
            if let g = groups.last, g.ty == w.ty, X(w.k) - g.xs.last! < 40 { groups[groups.count - 1].ks.append(w.k); groups[groups.count - 1].xs.append(X(w.k)) }
            else { groups.append((w.ty, [w.k], [X(w.k)], w.c)) }
        }
        let tw = { (l: String) -> CGFloat in CGFloat(l.count) * 5.6 + 6 }
        var occ: [[(CGFloat, CGFloat)]] = [[(m.today.x - tw("Today") / 2, m.today.x + tw("Today") / 2)], []]
        for g in groups {
            let x = g.xs.reduce(0, +) / CGFloat(g.xs.count)
            let l = (g.ks.count > 1 ? g.ty + "s " : g.ty + " ") + g.ks.map(fk).joined(separator: ", ")
            let h = tw(l) / 2, lo2 = max(0, min(252 - 2 * h, x - h)), hi2 = lo2 + 2 * h
            guard let row = occ.firstIndex(where: { $0.allSatisfy { hi2 + 4 < $0.0 || lo2 - 4 > $0.1 } }) else { continue }
            occ[row].append((lo2, hi2))
            m.wallLabels.append(Mark(x: (lo2 + hi2) / 2, y: row == 0 ? 9 : 21, l: l, c: g.c))
        }
        return m
    }

    var body: some View {
        let nums = labels.compactMap { l -> (String, Double, String, String)? in
            guard let t = l["t"].string, let v = Double(t.split(separator: " ").last ?? "") else { return nil }
            return (t, v, l["c"].string ?? "secondary", l["kind"].string ?? "")
        }
        let strikes = nums.filter { $0.3 == "strike" }.map(\.1)
        let keep = strikes.first ?? 36, roll = strikes.last ?? 37.5
        let m = Self.model(labels, acct: BriefDebug.sample ? brief.account.sampleKey : nil)
        GeometryReader { g in
            let s = g.size.width / 252
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    ctx.scaleBy(x: s, y: s)
                    let poly = { (cl: (CGFloat) -> CGFloat) -> Path in
                        var p = Path(); p.move(to: CGPoint(x: 0, y: m.zy))
                        for q in m.fill { p.addLine(to: CGPoint(x: q.x, y: cl(q.y))) }
                        p.addLine(to: CGPoint(x: 252, y: m.zy)); p.closeSubpath(); return p
                    }
                    let line = { (a: [CGPoint]) -> Path in var p = Path(); if let f = a.first { p.move(to: f); a.dropFirst().forEach { p.addLine(to: $0) } }; return p }
                    let v = { (x: CGFloat) -> Path in Path { $0.move(to: CGPoint(x: x, y: 26)); $0.addLine(to: CGPoint(x: x, y: 112)) } }
                    ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: m.zy)); $0.addLine(to: CGPoint(x: 252, y: m.zy)) }, with: .color(S.secondary.opacity(0.35)), lineWidth: 1)
                    ctx.fill(poly { max($0, m.zy) }, with: .color(S.red.opacity(0.13)))
                    ctx.fill(poly { min($0, m.zy) }, with: .color(S.green.opacity(0.15)))
                    for x in m.strikes { ctx.stroke(v(x), with: .color(S.secondary.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [2, 3])) }
                    for w in m.walls { ctx.stroke(v(w.x), with: .color(w.c), style: StrokeStyle(lineWidth: 1.25, dash: [4, 3])) }
                    if !m.keep.isEmpty { ctx.stroke(line(m.keep), with: .color(S.secondary), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])) }
                    ctx.stroke(line(m.act), with: .color(S.ink), style: StrokeStyle(lineWidth: 2.25, lineJoin: .round))
                    ctx.stroke(v(m.today.x), with: .color(S.ink.opacity(0.5)), lineWidth: 1)
                    let dot = Path(ellipseIn: CGRect(x: m.today.x - 4.5, y: m.today.y - 4.5, width: 9, height: 9))
                    ctx.fill(dot, with: .color(S.ink))
                    ctx.stroke(dot, with: .color(S.paper), lineWidth: 2)
                    // SVG text: 11 bold, centred on Today, baseline at 9.
                    ctx.draw(Text("Today").font(.system(size: 11, weight: .bold)).foregroundStyle(S.ink), at: CGPoint(x: m.today.x, y: 9), anchor: UnitPoint(x: 0.5, y: 0.78))
                }
                ForEach(Array((m.strikeLabels + m.wallLabels).enumerated()), id: \.offset) { _, k in
                    Text(k.l).sType(SType(size: 12, weight: 700, line: 13, tracking: 0)).foregroundStyle(k.c).lineLimit(1).fixedSize()
                        .position(x: k.x * s, y: k.y * s)
                }
            }
        }
        .aspectRatio(252 / 124, contentMode: .fit)
        .environment(\.sTypeScales, false)   // the labels sit at the chart's own points
        // The picture as one stop, from its own labels: where each choice caps the gain, and the walls.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BSay.join([
            "What if chart",
            strikes.isEmpty ? "keep the calls or roll them up"
                : "keeping the calls caps the gain at \(String(format: "%g", keep)), rolling up moves the cap to \(String(format: "%g", roll))",
            nums.filter { $0.3 == "wall" }.isEmpty ? nil : "walls at " + nums.filter { $0.3 == "wall" }.map(\.0).joined(separator: ", "),
        ]))
    }
}

// MARK: - Dated rows: Coming up, Remember for next week

struct BDatedRows: View {
    let card: JSONValue
    let privacy: Bool
    var body: some View {
        // The one-line Coming up keeps its title 8 over the line; the calendar's rows sit 16 under the title.
        VStack(alignment: .leading, spacing: card["line"].isNull ? 16 : 8) {
            BTitle(t: card["title"].string)
            if !card["line"].isNull { BBody(v: card["line"], privacy: privacy, type: BB.body) }
            if !card["rows"].array.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(card["rows"].array.enumerated()), id: \.offset) { i, r in
                        if i > 0 { BHairline() }
                        // Date 84, logo 28, text, 10 apart; 9 above and below.
                        HStack(alignment: .center, spacing: 10) {
                            Text(r["date"].string ?? "").sType(SType(size: 13, weight: 700, line: 17, tracking: 0), tabular: false)
                                .foregroundStyle(S.ink).frame(width: 84, alignment: .leading)
                            if let t = r["logo"].string { BLogo(ticker: t, size: 28) } else { Color.clear.frame(width: 28, height: 1) }
                            BriefSentence(BriefSpan.list(r["text"]), base: SType(size: 14, weight: 500, line: 18, tracking: 0), boldWeight: 600, privacy: privacy)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 9)
                    }
                }
            }
        }
        .briefCard()
        .background(alignment: .bottom) {
            // The calendar card's soft yellow foot (as the design draws it).
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LinearGradient(colors: [.clear, S.yellow.opacity(0.18)], startPoint: .top, endPoint: .bottom))
        }
        .padding(.horizontal, S.margin)
    }
}

// MARK: - Earnings ahead

struct BEarningsAhead: View {
    let card: JSONValue
    let privacy: Bool

    /// One earnings column spoken: "Q3 2025, beat, actual above expected", "Tue, reports, expected only".
    static func columnSays(_ col: String, _ d: JSONValue?) -> String {
        let day = col.replacingOccurrences(of: "’", with: "20").replacingOccurrences(of: "'", with: "20")
        guard let d else { return day }
        let e = d["expectedTop"].double, a = d["actualTop"].double
        // The dots' tops are points down from the plot's top: a smaller top sits higher.
        let vs: String? = e != nil && a != nil ? (a! < e! ? "actual above expected" : a! > e! ? "actual below expected" : "actual at expected") : nil
        switch d["result"].string {
        case "beat": return BSay.join([day, "beat", vs])
        case "missed": return BSay.join([day, "missed", vs])
        default: return BSay.join([day, a == nil ? "not reported yet, expected only" : vs])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BHead(card: card)
            HStack(spacing: 10) {
                BLogo(ticker: card["logo"].string, size: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(card["name"].string ?? "").sType(SType(size: 16, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Text(card["when"].string ?? "").sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                }
            }
            BStats(stats: card["stats"].array, privacy: privacy, value: SType(size: 20, weight: 800, line: 25, tracking: -0.02), spacing: 10)
            let ch = card["chart"]
            if !ch.isNull {
                // Padding 12, radius 14, the design's fill; legend, dots (74 tall) over their labels, caption, 8 apart.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        ForEach(Array(ch["legend"].array.compactMap(\.string).enumerated()), id: \.offset) { i, l in
                            HStack(spacing: 6) {
                                Circle().fill(i == 0 ? S.green.opacity(0.38) : i == 1 ? S.green : S.red).frame(width: 9, height: 9)
                                Text(l).sType(BB.legend, tabular: false).foregroundStyle(S.ink)
                            }
                        }
                    }
                    .accessibilityHidden(true)   // each column says expected against actual
                    let cols = ch["columns"].array.compactMap(\.string)
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(cols.enumerated()), id: \.offset) { i, col in
                            let d = ch["dots"].array.first { $0["col"].string == col }
                            let last = i == cols.count - 1
                            VStack(spacing: 8) {
                                ZStack(alignment: .top) {
                                    Color.clear.frame(height: 74)
                                    if let e = d?["expectedTop"].double { Circle().fill(S.green.opacity(0.38)).frame(width: 12, height: 12).offset(y: e - 6) }
                                    if let a = d?["actualTop"].double {
                                        Circle().fill(d?["result"].string == "missed" ? S.red : S.green).frame(width: 12, height: 12).offset(y: a - 6)
                                    }
                                }
                                Text(col).sType(SType(size: 11, weight: last ? 800 : 500, line: 14, tracking: 0), tabular: false)
                                    .foregroundStyle(last ? S.ink : S.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Self.columnSays(col, d))
                        }
                    }
                    if let c = ch["caption"].string { Text(c).sType(BB.note, tabular: false).foregroundStyle(S.secondary) }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BB.fill))
            }
            BNotes(notes: card["notes"].array, privacy: privacy)
            if let s = card["source"].string { Text(s).sType(SType(size: 12, weight: 600, line: 15, tracking: 0), tabular: false).foregroundStyle(S.ink) }
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}

/// Label · text rows (Estimates, You, Analysts, Pro Tip, Health...): label 92 wide, 10 apart, a rule over each, 9 above and below.
struct BNotes: View {
    let notes: [JSONValue]
    let privacy: Bool
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(notes.enumerated()), id: \.offset) { _, n in
                BHairline()
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(n["label"].string ?? "").sType(SType(size: 13, weight: 700, line: 17, tracking: 0), tabular: false)
                        .foregroundStyle(S.secondary).frame(width: 92, alignment: .leading)
                    BriefWords.line(n["text"].string, privacy: privacy).sType(SType(size: 14, weight: 600, line: 19, tracking: 0), tabular: false)
                        .foregroundStyle(S.ink).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9)
            }
        }
    }
}

// MARK: - Your results (post-market) and Results (weekend)

struct BResults: View {
    let card: JSONValue
    let privacy: Bool
    @State private var seg: String = ""
    var body: some View {
        let segs = card["segments"].array.compactMap(\.string)
        let pick = seg.isEmpty ? (card["selected"].string ?? segs.first ?? "") : seg
        let s = card["bySegment"][pick]
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                BTitle(t: card["title"].string)
                Spacer(minLength: 0)
                if segs.count > 1 {
                    BSegmented(items: segs, selected: Binding(get: { pick }, set: { seg = $0 })).frame(width: 184)   // two 1fr cells of "This week" + 28, track 2
                }
            }
            // The range's blocks, 12 apart; the dividends and each chart under a rule, 12 below it.
            VStack(alignment: .leading, spacing: 12) {
                if let b = s["big"].string {
                    VStack(alignment: .leading, spacing: 2) {
                        BriefWords.line(b, privacy: privacy).sType(BB.big).foregroundStyle(BK.color(s["bigColor"].string))
                        BriefWords.line(s["bigSub"].string, privacy: privacy).sType(BB.bigSub, tabular: false).foregroundStyle(S.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                BStats(stats: s["stats"].array, privacy: privacy)
                BBody(v: s["body"], privacy: privacy, type: BB.body)
                let dv = s["dividends"]
                if !dv.isNull {
                    VStack(alignment: .leading, spacing: 0) {
                        BHairline()
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(dv["title"].string ?? "Dividends").sType(SType(size: 14, weight: 700, line: 18, tracking: 0), tabular: false).foregroundStyle(S.ink)
                                BBody(v: dv["line"], privacy: privacy, type: BB.note)
                            }
                            Spacer(minLength: 0)
                            BriefWords.line(dv["right"].string, privacy: privacy).sType(SType(size: 17, weight: 800, line: 22, tracking: 0))
                                .foregroundStyle(BK.color(dv["rightColor"].string)).lineLimit(1).fixedSize()
                        }
                        .padding(.top, 12)
                    }
                }
                ForEach(Array(s["charts"].array.enumerated()), id: \.offset) { _, c in
                    VStack(alignment: .leading, spacing: 0) {
                        BHairline()
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(c["title"].string ?? "").sType(SType(size: 14, weight: 700, line: 18, tracking: 0), tabular: false).foregroundStyle(S.ink)
                                Spacer(minLength: 0)
                                if let sub = c["sub"].string { BriefWords.line(sub, privacy: privacy).sType(BB.note, tabular: false).foregroundStyle(S.secondary) }
                            }
                            // The bars' grid is 84 tall, the labels 4 under it (11/14).
                            Group {
                                if !c["bars"].array.isEmpty {
                                    BBars(bars: c["bars"].array, height: 56, privacy: privacy, title: c["title"].string)
                                } else if !c["groups"].array.isEmpty {
                                    BBars(bars: c["groups"].array.map { g in
                                        JSONValue.object(["label": g["label"], "highlight": g["highlight"],
                                                          "value": g["values"][0]["value"], "valueColor": g["values"][0]["valueColor"]])
                                    }, height: 56, privacy: privacy, title: c["title"].string)
                                }
                            }
                            .frame(height: 102, alignment: .bottom)
                            if let n = c["note"].string { Text(n).sType(BB.body, tabular: false).foregroundStyle(S.ink).fixedSize(horizontal: false, vertical: true) }
                        }
                        .padding(.top, 12)
                    }
                }
            }
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}

// MARK: - Closed and rolled today

struct BClosedRolled: View {
    let card: JSONValue
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BHead(card: card)
            // Rows 12 apart, a rule 12 over each after the first; a row's note sits 12 under it.
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(card["rows"].array.enumerated()), id: \.offset) { i, r in
                    if i > 0 {
                        VStack(spacing: 0) { BHairline(); row(r).padding(.top, 12) }
                    } else {
                        row(r)
                    }
                    BBody(v: r["note"], privacy: privacy, type: BB.body)
                }
            }
            BFooter(v: card["footer"], privacy: privacy, type: SType(size: 12, weight: 500, line: 15, tracking: 0))
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }

    /// Logo 36, the title (15/19 bold) over its line (13/16), the figure (17/21 heavy) over its label (11/14), 10 apart.
    private func row(_ r: JSONValue) -> some View {
        HStack(alignment: .center, spacing: 10) {
            BLogo(ticker: r["logo"].string, size: 36)
            VStack(alignment: .leading, spacing: 0) {
                Text(r["title"].string ?? "").sType(SType(size: 15, weight: 700, line: 19, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Text(r["sub"].string ?? "").sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                BriefWords.line(r["value"].string, privacy: privacy).sType(SType(size: 17, weight: 800, line: 21, tracking: 0))
                    .foregroundStyle(BK.color(r["valueColor"].string)).lineLimit(1)
                Text(r["valueLabel"].string ?? "").sType(SType(size: 11, weight: 500, line: 14, tracking: 0), tabular: false).foregroundStyle(S.secondary)
            }
            .fixedSize()
        }
    }
}

// MARK: - After hours

struct BAfterHours: View {
    let card: JSONValue
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BHead(card: card)
            HStack(alignment: .center, spacing: 10) {
                BLogo(ticker: card["logo"].string, size: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(card["name"].string ?? "").sType(SType(size: 16, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Text(card["source"].string ?? "").sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                        .accessibilityLabel(BSay.words(card["source"].string))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(card["move"].string ?? "").sType(SType(size: 20, weight: 800, line: 24, tracking: 0)).foregroundStyle(BK.color(card["moveColor"].string))
                    .lineLimit(1).fixedSize()
                    .accessibilityLabel("after hours " + BSay.move(card["move"].string, color: card["moveColor"].string))
            }
            .accessibilityElement(children: .combine)
            BBody(v: card["body"], privacy: privacy, type: BB.body)
            let r = card["range"]
            if !r.isNull {
                // Padding 12, radius 14, the fill; the key, the 14 tall range, the ends, 6 apart.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Circle().fill(S.ink).frame(width: 8, height: 8)
                            Text(r["today"].string ?? "").sType(BB.legend, tabular: false).foregroundStyle(S.ink)
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 1).fill(S.ink).frame(width: 2, height: 11)
                            Text(r["avg"].string ?? "").sType(BB.legend, tabular: false).foregroundStyle(S.ink)
                        }
                    }
                    .lineLimit(1)
                    GeometryReader { g in
                        let lo = Double(r["low"].string?.filter { $0.isNumber || $0 == "." } ?? "") ?? 0
                        let hi = Double(r["high"].string?.filter { $0.isNumber || $0 == "." } ?? "") ?? 1
                        let td = Double(r["today"].string?.filter { $0.isNumber || $0 == "." } ?? "") ?? lo
                        let av = Double((r["avg"].string?.components(separatedBy: " ·").first ?? "").filter { $0.isNumber || $0 == "." }) ?? lo
                        let fx = { (v: Double) -> CGFloat in g.size.width * CGFloat(max(0, min(1, (v - lo) / max(hi - lo, 0.01)))) }
                        ZStack(alignment: .topLeading) {
                            Capsule().fill(S.paper).frame(width: g.size.width, height: 4).offset(y: 5)
                            Rectangle().fill(S.ink.opacity(0.35)).frame(width: max(0, fx(av) - fx(td)), height: 4).offset(x: fx(td), y: 5)
                            RoundedRectangle(cornerRadius: 1).fill(S.ink).frame(width: 2, height: 14).offset(x: fx(av) - 1)
                            Circle().fill(S.ink).frame(width: 10, height: 10)
                                .background(Circle().fill(BB.fill).padding(-2))
                                .offset(x: fx(td) - 5, y: 2)
                        }
                    }
                    .frame(height: 14)
                    HStack {
                        Text(r["low"].string ?? "")
                        Spacer(minLength: 4)
                        Text(r["analysts"].string ?? "")
                        Spacer(minLength: 4)
                        Text(r["high"].string ?? "")
                    }
                    .sType(BB.axis, tabular: false).foregroundStyle(S.secondary).lineLimit(1)
                }
                // One stop in words: "Today $65.09, average $84, 29% above, low $55, ...".
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(BSay.join([r["today"].string, r["avg"].string?.replacingOccurrences(of: "Avg", with: "analysts' average"),
                                               r["low"].string, r["high"].string, r["analysts"].string].map { BSay.words($0) }))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BB.fill))
            }
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}

// MARK: - Tomorrow's orders

struct BOrders: View {
    let card: JSONValue
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    BTitle(t: card["title"].string)
                    Spacer(minLength: 0)
                    Text(card["count"].string ?? "").sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false)
                        .foregroundStyle(S.secondary).lineLimit(1).fixedSize()
                }
                BSub(t: card["subtitle"].string, privacy: privacy, type: BK.cardSub)
            }
            // Rows 14 apart, no rules: logo 36, the order over why and the wall, the amount over its label, 10 apart.
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(card["rows"].array.enumerated()), id: \.offset) { _, r in
                    HStack(alignment: .top, spacing: 10) {
                        BLogo(ticker: r["logo"].string, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r["order"].string ?? "").sType(SType(size: 15, weight: 600, line: 19, tracking: 0), tabular: false).foregroundStyle(S.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(r["why"].string ?? "").sType(SType(size: 13, weight: 500, line: 17, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let t = r["tag"].string { Text(t).sType(SType(size: 12, weight: 600, line: 15, tracking: 0), tabular: false).foregroundStyle(S.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 1) {
                            BriefWords.line(r["amount"].string, privacy: privacy).sType(SType(size: 15, weight: 700, line: 19, tracking: 0)).foregroundStyle(S.ink)
                                .lineLimit(1)
                            Text(r["amountLabel"].string ?? "").sType(SType(size: 12, weight: 500, line: 15, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                        }
                        .fixedSize()
                    }
                }
            }
            BFooter(v: card["footer"], privacy: privacy, type: SType(size: 12, weight: 500, line: 16, tracking: 0))
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}

// MARK: - Theta · October

struct BThetaMonth: View {
    let card: JSONValue
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BHead(card: card)
            HStack(spacing: 14) {
                ForEach(Array(card["legend"].array.compactMap(\.string).enumerated()), id: \.offset) { i, l in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(i == 0 ? S.green : S.red).frame(width: 10, height: 10)
                        Text(l).sType(BB.legend, tabular: false).foregroundStyle(S.ink)
                    }
                }
            }
            .accessibilityHidden(true)   // the bars' summary names both
            // The weeks: a 108 tall grid of bar pairs (the tallest 84), the labels 12 under it.
            let weeks = card["weeks"].array
            let mx = weeks.compactMap { Double(($0["ratio"].string ?? "").replacingOccurrences(of: "×", with: "")) }.max() ?? 1
            VStack(spacing: 12) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { i, w in
                        let r = Double((w["ratio"].string ?? "").replacingOccurrences(of: "×", with: "")) ?? 1
                        let now = i == weeks.count - 1, op = now ? 1 : 0.38
                        let bar = UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 1, bottomTrailingRadius: 1, topTrailingRadius: 4)
                        VStack(spacing: 5) {
                            Text(w["ratio"].string ?? "").sType(SType(size: 12, weight: 800, line: 14, tracking: 0)).foregroundStyle(now ? S.ink : S.secondary)
                                .lineLimit(1).fixedSize()
                            HStack(alignment: .bottom, spacing: 3) {
                                bar.fill(S.green.opacity(op)).frame(height: 84 * CGFloat(r / mx))
                                bar.fill(S.red.opacity(op)).frame(height: 84 / CGFloat(mx))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 108, alignment: .bottom)
                BBarLabels(labels: weeks.map { $0["label"].string ?? "" })
            }
            // The weeks as one stop: "Collected against paid in decay, week by week: Sep 28 3.9 times, ...".
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.weeksSay(card["legend"].array.compactMap(\.string), weeks))
            BBody(v: card["body"], privacy: privacy, type: BB.body)
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }

    private static func weeksSay(_ legend: [String], _ weeks: [JSONValue]) -> String {
        let what = legend.enumerated().map { $0.offset == 0 ? $0.element : $0.element.lowercased() }.joined(separator: " against ")
        let head = what.isEmpty ? "Week by week" : what + ", week by week"
        return head + ": " + weeks.map { BSay.join([$0["label"].string, BSay.words($0["ratio"].string)], " ") }.joined(separator: ", ")
    }
}

// MARK: - Payback · month end

struct BPayback: View {
    let card: JSONValue
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BHead(card: card)
            VStack(alignment: .leading, spacing: 2) {
                Text(card["big"].string ?? "").sType(BB.big).foregroundStyle(BK.color(card["bigColor"].string))
                BriefWords.line(card["bigSub"].string, privacy: privacy).sType(BB.bigSub, tabular: false).foregroundStyle(S.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let ch = card["chart"]
            if !ch.isNull {
                // The title 8 over a 90 tall grid (the tallest bar 70), the months 4 under it.
                VStack(alignment: .leading, spacing: 8) {
                    Text(ch["title"].string ?? "").sType(SType(size: 14, weight: 700, line: 18, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    BBars(bars: ch["bars"].array, height: 70, privacy: privacy, title: ch["title"].string)
                        .frame(height: 108, alignment: .bottom)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(card["rows"].array.enumerated()), id: \.offset) { _, r in
                    BHairline()
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        BriefWords.line(r["label"].string, privacy: privacy).sType(SType(size: 14, weight: 600, line: 19, tracking: 0), tabular: false)
                            .foregroundStyle(S.ink).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        // The figure and its words in one run: "$27.6K under what you paid".
                        BriefWords.line([r["value"].string, r["valueSub"].string].compactMap { $0 }.joined(separator: " "), privacy: privacy)
                            .sType(SType(size: 14, weight: 800, line: 19, tracking: 0))
                            .foregroundStyle(BK.color(r["valueColor"].string)).multilineTextAlignment(.trailing)
                            .layoutPriority(1)   // the grid's auto column: the figure keeps its width, the label wraps
                    }
                    .padding(.vertical, 9)
                }
            }
            if let f = card["footer"].string { Text(f).sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary) }
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}

// MARK: - Thesis check

struct BThesisCheck: View {
    let card: JSONValue
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BHead(card: card)
            BStats(stats: card["stats"].array, privacy: privacy, value: SType(size: 20, weight: 800, line: 25, tracking: -0.02), spacing: 10)
            BNotes(notes: card["notes"].array, privacy: privacy)
            if let s = card["source"].string { Text(s).sType(SType(size: 12, weight: 600, line: 15, tracking: 0), tabular: false).foregroundStyle(S.ink) }
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}
