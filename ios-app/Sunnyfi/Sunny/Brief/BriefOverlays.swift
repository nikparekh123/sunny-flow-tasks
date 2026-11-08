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
                    Image(systemName: "xmark").sFont(13, .bold).foregroundStyle(S.secondary)
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
    /// The server's timeValue (brief.ts): every sold leg still open, with its time value left.
    var live: JSONValue = .null
    let close: () -> Void
    @Environment(\.dynamicTypeSize) private var dts

    struct Row: Identifiable { let id: String; let t: String; let name: String; let leg: String; let left: Double; let collected: Double; let intrinsic: Double; let perShare: Double }

    /// The sold legs: the server's real ones (answer 2), or the sample book's in a -sample run.
    private var rows: [Row] {
        if !BriefDebug.sample {
            return live["legs"].array.enumerated().map { i, l in
                let t = l["t"].string ?? "", k = l["K"].double ?? 0, q = l["q"].double ?? 0
                return Row(id: "\(t)\(i)", t: t, name: l["name"].string ?? t, leg: "\(String(format: "%g", k)) \(l["put"].bool ? "puts" : "calls") ×\(Int(q))",
                           left: l["tvLeft"].double ?? 0, collected: l["col"].double ?? 0, intrinsic: l["intr"].double ?? 0, perShare: l["tvPer"].double ?? 0)
            }
        }
        let book = SampleBook.book(acct)
        return SampleBook.names.flatMap { t -> [Row] in
            guard let b = book[t], let q = SampleBook.q[t] else { return [] }
            return b.sold.enumerated().map { i, s in
                let intr = s.put ? max(0, s.k - q.0) : max(0, q.0 - s.k)
                let tv = max(0, s.now - intr)
                return Row(id: "\(t)\(i)", t: t, name: SampleBook.company[t] ?? t, leg: "\(String(format: "%g", s.k)) \(s.put ? "puts" : "calls") ×\(s.q)",
                           left: tv * Double(s.q) * 100, collected: s.at * Double(s.q) * 100, intrinsic: intr, perShare: tv)
            }
        }
    }

    var body: some View {
        let rows = rows
        let left = rows.reduce(0) { $0 + $1.left }, coll = rows.reduce(0) { $0 + $1.collected }
        let cap = coll > 0 ? 1 - left / coll : 0
        let ready = rows.filter { $0.perShare < 0.05 || ($0.collected > 0 && 1 - $0.left / $0.collected >= 0.9) || $0.intrinsic > 0 }
        BriefSheetChrome(title: "Time value", close: close) {
            if rows.isEmpty {
                // An account with nothing sold (README 10): one line, no zero bars.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing sold yet").sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Text("Time value shows here once calls or puts are sold.").sType(BK.sub, tabular: false).foregroundStyle(S.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    BriefWords.line("$" + SampleEngine.fn(left), privacy: privacy)
                        .sType(SType(size: 34, weight: 800, line: 40, tracking: -0.02)).foregroundStyle(S.ink)
                    Text("left of \(BriefWords.plain("$" + SampleEngine.fn(coll), privacy: privacy)) collected")
                        .accessibilityLabel(BriefMask.spoken("left of \(BriefWords.plain("$" + SampleEngine.fn(coll), privacy: privacy)) collected"))
                        .sType(BK.body, tabular: false).foregroundStyle(S.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(privacy ? "Time value left, hidden" : BSay.words("$\(SampleEngine.fn(left)) left of $\(SampleEngine.fn(coll)) collected"))
                VStack(alignment: .trailing, spacing: 4) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(S.chip)
                            Capsule().fill(S.green).frame(width: g.size.width * CGFloat(min(1, max(0, cap))))
                        }
                    }
                    .frame(height: 8)
                    // Worth more than it was sold for: a loss so far, in red without a minus sign (colour carries the sign).
                    Text("\(Int(abs(cap * 100).rounded()))% \(cap < -0.005 ? "given back" : "captured")").sType(SType(size: 13, weight: 700, line: 16, tracking: 0)).foregroundStyle(cap < -0.005 ? S.red : S.green)
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
                                    Text(r.name).sType(BK.row, tabular: false).foregroundStyle(S.ink).padding(.top, 6)
                                    Text(r.leg).sType(BK.rowSub, tabular: false).foregroundStyle(S.secondary)
                                        .accessibilityLabel(BSay.words(r.leg))
                                    // At a large text size "left" drops under the amount rather than cutting it (Pass 5).
                                    ViewThatFits(in: .horizontal) {
                                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                                            BriefWords.line("$" + SampleEngine.fn(r.left), privacy: privacy)
                                                .sType(SType(size: 22, weight: 800, line: 26, tracking: 0)).foregroundStyle(S.ink)
                                            Text("left").sType(BK.rowSub, tabular: false).foregroundStyle(S.secondary)
                                        }
                                        VStack(alignment: .leading, spacing: 0) {
                                            BriefWords.line("$" + SampleEngine.fn(r.left), privacy: privacy)
                                                .sType(SType(size: 22, weight: 800, line: 26, tracking: 0)).foregroundStyle(S.ink)
                                                .lineLimit(1).minimumScaleFactor(0.7)
                                            Text("left").sType(BK.rowSub, tabular: false).foregroundStyle(S.secondary)
                                        }
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
                                .accessibilityElement(children: .combine)
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
                                Text("\(rs.first?.name ?? t) · \(rs.map(\.leg).joined(separator: ", "))")
                                    .sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                                    .lineLimit(dts > .large ? 3 : 1)   // one line as designed; wraps at a large text size (Pass 5)
                                HStack(spacing: 8) {
                                    GeometryReader { g in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(S.chip)
                                            Capsule().fill(S.green).frame(width: g.size.width * CGFloat(min(1, max(0, k))))
                                        }
                                    }
                                    .frame(height: 6)
                                    Text("\(Int(abs(k * 100).rounded()))%").sType(SType(size: 12, weight: 700, line: 15, tracking: 0)).foregroundStyle(k < -0.005 ? S.red : S.green)
                                }
                            }
                            VStack(alignment: .trailing, spacing: 1) {
                                BriefWords.line("$" + SampleEngine.fn(l), privacy: privacy).sType(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink)
                                Text("of \(BriefWords.plain("$" + SampleEngine.fn(c), privacy: privacy))")
                                    .accessibilityLabel(BriefMask.spoken("of \(BriefWords.plain("$" + SampleEngine.fn(c), privacy: privacy))"))
                                    .sType(BK.rowSub).foregroundStyle(S.secondary)
                            }
                            .frame(width: 72, alignment: .trailing)
                        }
                        .padding(.vertical, 10)
                        // One stop per name, the sign in words: "Nike, 36 calls, 71 contracts, 81% captured, $412 left of $2,130".
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(BSay.join([
                            rs.first?.name ?? t, BSay.words(rs.map(\.leg).joined(separator: ", ")),
                            "\(Int(abs(k * 100).rounded()))% \(k < -0.005 ? "given back" : "captured")",
                            privacy ? "amounts hidden" : BSay.words("$\(SampleEngine.fn(l)) left of $\(SampleEngine.fn(c))"),
                        ]))
                    }
                }
            }
            }
        }
    }
}

// MARK: - The economy (12 indicators)

struct EconomySheet: View {
    /// The live sheet (doc.economy); the sample's in sample mode.
    var live: JSONValue = .null
    let close: () -> Void
    var body: some View {
        let e = BriefDebug.sample || live.isNull ? BriefSample.sheets["economy"] : live
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
    /// The book on screen (live): sunny-chart adds its legs in this name. Nil in sample mode.
    var book: String? = nil
    let close: () -> Void
    @State private var range = "3M"
    @State private var layer = "Positions"
    @State private var wire: TickerWire?
    @State private var failed = false

    private var live: Bool { !BriefDebug.sample }

    /// The range chips in words, and the phrase under the price.
    private static let rangeWords = ["1W": "1 week", "1M": "1 month", "3M": "3 months", "YTD": "year to date", "1Y": "1 year", "All": "all"]
    private static let rangePhrase = ["1W": "past week", "1M": "past month", "3M": "past 3 months", "YTD": "this year", "1Y": "past year", "All": "since the start"]

    /// The chart as one spoken line: "Nike price, past 3 months, from $33.10 to $35.28, now $35.28. Lines: Sold call 36, ...".
    private func chartSays(_ name: String, _ pts: [Double], _ now: Double, _ lines: [(k: Double, label: String, solid: Bool)]) -> String {
        guard let a = pts.first, let b = pts.last else { return "\(name) price chart, no data" }
        let f = { (v: Double) in String(format: "$%.2f", v) }
        let head = BSay.join(["\(name) price", Self.rangePhrase[range], "from \(f(a)) to \(f(b))", f(now) == f(b) ? nil : "now \(f(now))"])
        let ls = lines.map { l -> String in
            let said = BSay.words(l.label)
            return said.contains(String(format: "%g", l.k)) ? said : "\(said) at \(f(l.k))"
        }
        return ls.isEmpty ? head : head + ". \(layer) lines: " + ls.joined(separator: "; ")
    }

    var body: some View {
        let q = live ? (wire?.price ?? 0, wire?.prev ?? 0) : (SampleBook.q[t] ?? (0, 0))
        let mv = q.1 > 0 ? (q.0 - q.1) / q.1 * 100 : 0
        let all = live ? (wire?.closes ?? []) : SampleSeries.year(t)
        let ytd = live ? (wire?.ytdCount ?? 210) : 210
        let n = ["1W": 5, "1M": 22, "3M": 63, "YTD": ytd, "1Y": 252, "All": all.count][range] ?? 63
        let pts = Array(all.suffix(n + 1))
        let ch = (pts.last ?? 0) - (pts.first ?? 0), chp = (pts.first ?? 0) > 0 ? ch / pts[0] * 100 : 0
        let lines = layerLines()
        let name = live ? (wire?.name ?? t) : (SampleBook.company[t] ?? t)
        ZStack(alignment: .top) {
            SBackground()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button(action: close) {
                        Image(systemName: "xmark").sFont(16, .semibold).foregroundStyle(S.ink)
                            .frame(width: 44, height: 44).glassEffect(.regular, in: .circle)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Back")
                    HStack(spacing: 8) {
                        BLogo(ticker: t, size: 24)
                        Text(t).sFont(15, .bold).foregroundStyle(S.ink)
                        Text(String(format: "$%.2f", q.0)).sFont(15, .semibold, mono: true).foregroundStyle(S.ink)
                        Text(String(format: "%.2f%%", abs(mv))).sFont(15, .semibold, mono: true).foregroundStyle(mv < 0 ? S.red : S.green)
                    }
                    .padding(.horizontal, 12).frame(height: 44).glassEffect(.regular, in: .capsule)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(live && wire == nil ? name
                        : BSay.join([name, String(format: "$%.2f", q.0), "\(mv < 0 ? "down" : "up") \(String(format: "%.2f%%", abs(mv))) today"]))
                    .accessibilityAddTraits(.isHeader)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).sType(BK.small, tabular: false).foregroundStyle(S.secondary)
                    HStack(spacing: 6) {
                        Text(String(format: "$%.2f %.2f%%", abs(ch), abs(chp))).sType(SType(size: 17, weight: 700, line: 22, tracking: 0)).foregroundStyle(ch < 0 ? S.red : S.green)
                        Text(Self.rangePhrase[range] ?? "")
                            .sType(SType(size: 17, weight: 500, line: 22, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    }
                    // "down $1.20, 3.50%, past 3 months": the colour's sign in words.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(ch < 0 ? "down" : "up") \(String(format: "$%.2f, %.2f%%", abs(ch), abs(chp))), \(Self.rangePhrase[range] ?? "")")
                }
                if live && wire == nil {
                    Group { if failed { Text("Could not load \(t). Try again in a moment.") } else { ProgressView() } }
                        .sType(BK.sub, tabular: false).foregroundStyle(S.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TickerLine(pts: pts, lines: lines, up: ch >= 0, key: range).frame(maxHeight: .infinity)
                        // One stop for the chart; its line labels and the last-price chip are in the summary.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(chartSays(name, pts, q.0, lines))
                        .overlay(alignment: .topLeading) {
                            if live && lines.isEmpty {
                                Text(layer == "Positions" ? "Nothing held in \(t)" : layer == "Walls" ? "No walls saved for \(t)" : "")
                                    .sType(BK.small, tabular: false).foregroundStyle(S.secondary)
                            }
                        }
                }
                HStack {
                    ForEach(["1W", "1M", "3M", "YTD", "1Y", "All"], id: \.self) { r in
                        // The chips' colour fades (S.fade); the line crossfades and its labels move in TickerLine.
                        Button { withAnimation(S.fade) { range = r } } label: {
                            Text(r).sFont(14, r == range ? .bold : .medium).foregroundStyle(r == range ? S.sheetFill : S.secondary)
                                .frame(width: 44, height: 30).background(Capsule().fill(r == range ? S.ink : .clear))
                        }.buttonStyle(.plain)
                        .accessibilityLabel(Self.rangeWords[r] ?? r)
                        .accessibilityAddTraits(r == range ? .isSelected : [])
                        if r != "All" { Spacer() }
                    }
                }
                .sensoryFeedback(.selection, trigger: range)
                HStack(spacing: 8) {
                    ForEach(["Positions", "Technicals", "Walls"], id: \.self) { l in
                        Button { withAnimation(S.fade) { layer = l } } label: {
                            Text(l).sFont(15, .semibold).foregroundStyle(layer == l ? S.sheetFill : S.ink)
                                .padding(.horizontal, 16).frame(height: 44)
                                .background(Capsule().fill(layer == l ? S.ink : .clear))
                                .glassEffect(.regular, in: .capsule)
                        }.buttonStyle(.plain)
                        .accessibilityLabel("\(l) lines")
                        .accessibilityAddTraits(layer == l ? .isSelected : [])
                    }
                }
                .sensoryFeedback(.selection, trigger: layer)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, S.margin)
        }
        // A full-screen page over Home: VoiceOver stays on it until Back.
        .accessibilityAddTraits(.isModal)
        .task(id: t) {
            guard live else { return }
            do { wire = try await TickerChartClient.fetch(t: t, book: book) } catch { failed = true }
        }
    }

    /// The layer's lines: Positions (the legs held), Walls (the nearest weekly's), Technicals (averages, year range).
    private func layerLines() -> [(k: Double, label: String, solid: Bool)] {
        guard live else { return layer == "Positions" ? positionLines() : [] }
        guard let w = wire else { return [] }
        switch layer {
        case "Positions": return w.positions.map { ($0.k, $0.label, $0.solid ?? false) }
        case "Walls": return w.walls.map { ($0.k, $0.label, false) }
        default: return w.techLines
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
    /// Label columns: a label within 14 pt of one above it in the same column moves one column right.
    static func columns(_ ys: [CGFloat]) -> [Int] {
        var last: [CGFloat] = [], out: [Int] = []
        for y in ys {
            if let c = last.firstIndex(where: { abs($0 - y) >= 14 }) { last[c] = y; out.append(c) }
            else { last.append(y); out.append(last.count - 1) }
        }
        return out.map { min($0, 2) }
    }

    /// A labelled line keyed by what it is (label and strike), not its place in the list: a layer switch fades the
    /// old lines out and the new ones in instead of sliding one label into another.
    struct Mark: Identifiable { let id: String; let k: Double; let label: String; let solid: Bool; let col: Int }
    static func marks(_ shown: [(k: Double, label: String, solid: Bool)], _ cols: [Int]) -> [Mark] {
        var seen: [String: Int] = [:]
        return shown.enumerated().map { i, l in
            let base = "\(l.label)|\(l.k)", n = seen[base, default: 0]
            seen[base] = n + 1
            return Mark(id: n == 0 ? base : "\(base)#\(n)", k: l.k, label: l.label, solid: l.solid, col: cols[i])
        }
    }

    let pts: [Double]
    let lines: [(k: Double, label: String, solid: Bool)]
    let up: Bool
    /// The range on screen: a new range redraws the line (a 0.3 s crossfade, S.lineMorph).
    var key: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        GeometryReader { g in
            let lo0 = pts.min() ?? 0, hi0 = pts.max() ?? 1
            let inRange = lines.map(\.k).filter { $0 >= lo0 * 0.9 && $0 <= hi0 * 1.1 }
            let lo = min(lo0, inRange.min() ?? lo0) * 0.98, hi = max(hi0, inRange.max() ?? hi0) * 1.02
            let W = g.size.width - 40, H = g.size.height
            let X = { (i: Int) -> CGFloat in CGFloat(i) / CGFloat(max(1, pts.count - 1)) * W }
            let Y = { (p: Double) -> CGFloat in CGFloat((hi - p) / (hi - lo)) * H }
            let shown = lines.filter { $0.k >= lo && $0.k <= hi }.sorted { $0.k > $1.k }
            let marks = Self.marks(shown, Self.columns(shown.map { Y($0.k) }))
            // A plain Path does not interpolate, so a new line (range, or a scale change from a layer) crossfades.
            let lineKey = "\(key)|\(pts.count)|\(pts.first ?? 0)|\(pts.last ?? 0)|\(lo)|\(hi)"
            ZStack(alignment: .topLeading) {
                ForEach(marks) { m in
                    ZStack(alignment: .topLeading) {
                        Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: W, y: 0)) }
                            .stroke(S.ink.opacity(m.solid ? 0.8 : 0.5), style: StrokeStyle(lineWidth: 1, dash: m.solid ? [] : [2, 3]))
                            .offset(y: Y(m.k))
                        Text(m.label).font(.system(size: 10, weight: .bold)).foregroundStyle(S.ink)
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 4).background(S.dyn(0xF1F2F4, 0x0A0F0C))
                            // Left-aligned in its column: the centre sits half the label's width in.
                            .position(x: 4 + CGFloat(m.col) * (W / 2.6) + (CGFloat(m.label.count) * 5.6 + 8) / 2, y: Y(m.k))
                    }
                    // A line that stays moves to its new height with the redraw; nothing slides under Reduce Motion.
                    .animation(S.moving(S.lineMorph, reduce), value: [Y(m.k), CGFloat(m.col)])
                    .transition(.opacity)
                }
                ZStack {
                    Path { p in for (i, v) in pts.enumerated() { let pt = CGPoint(x: X(i), y: Y(v)); i == 0 ? p.move(to: pt) : p.addLine(to: pt) } }
                        .stroke(up ? S.green : S.red, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                        .id(lineKey)
                        .transition(.opacity)
                }
                .animation(S.lineMorph, value: lineKey)
                if let last = pts.last {
                    Text(String(format: "%.2f", last)).font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(S.onSignal)
                        .padding(.horizontal, 5).frame(height: 18).background(RoundedRectangle(cornerRadius: 4).fill(up ? S.green : S.red))
                        .position(x: W + 22, y: Y(last))
                        .animation(S.moving(S.lineMorph, reduce), value: Y(last))
                }
            }
        }
    }
}
