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
    /// Weekday sessions ending Tue Oct 27, 2026 (the sample's today), oldest first, market holidays skipped.
    static func dates(_ n: Int) -> [String] {
        let hol: Set<String> = ["2026-09-07", "2026-07-03", "2026-06-19", "2026-05-25", "2026-04-03", "2026-02-16", "2026-01-19",
                                "2026-01-01", "2025-12-25", "2025-11-27"]
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard var d = cal.date(from: DateComponents(year: 2026, month: 10, day: 27)) else { return [] }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd"
        var out: [String] = []
        while out.count < n {
            let wd = cal.component(.weekday, from: d), k = f.string(from: d)
            if wd != 1 && wd != 7 && !hol.contains(k) { out.append(k) }
            guard let p = cal.date(byAdding: .day, value: -1, to: d) else { break }
            d = p
        }
        return out.reversed()
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

/// BLogo with the logo at another share of the circle (the ticker pill's is 70%, BLogo's 74%).
struct BriefLogoDisc: View {
    let t: String
    let size: CGFloat
    var pct: CGFloat = 0.74
    var body: some View {
        ZStack {
            Circle().fill(.white)
            if let img = UIImage(named: "logo-\(t)") {
                Image(uiImage: img).resizable().scaledToFit().frame(width: size * pct, height: size * pct)
            } else {
                Text(String(t.prefix(4))).font(.system(size: size * 0.26, weight: .bold)).foregroundStyle(Color(white: 0.11))
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5).padding(-0.25))
        .accessibilityHidden(true)
    }
}

/// The sheets' head (New Home iPhone Preview, tv and es): the grabber 36 x 5 at 8, 12 under it the title 22/28 bold
/// (and a line 15/20 under it, 4 apart), the close button a 30 pt circle flush with the title's top and 20 from the
/// edge (its 44 pt target reaches 7 past both); then `gap` to the content, which pads `side` and `bottom`.
struct BriefSheetChrome<Content: View>: View {
    let title: String
    var sub: String? = nil
    var gap: CGFloat = 16
    var side: CGFloat = 20
    var bottom: CGFloat = 24
    let close: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(S.grabber).frame(width: 36, height: 5).frame(maxWidth: .infinity).padding(.top, 8)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).sType(SType(size: 22, weight: 700, line: 28, tracking: -0.01), tabular: false).foregroundStyle(S.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let sub { Text(sub).sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(S.secondary) }
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Path { p in p.move(to: CGPoint(x: 1, y: 1)); p.addLine(to: CGPoint(x: 10, y: 10)); p.move(to: CGPoint(x: 10, y: 1)); p.addLine(to: CGPoint(x: 1, y: 10)) }
                        .stroke(S.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 11, height: 11)
                        .frame(width: 30, height: 30).background(Circle().fill(S.chip))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, -7).padding(.trailing, -7)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, S.margin).padding(.top, 12)
            ScrollView { content().padding(.horizontal, side).padding(.top, gap).padding(.bottom, bottom) }
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

    /// The design's bar track: rgba(118,118,128,.2), .32 in dark (the system fill).
    private let barTrack = Color(uiColor: .systemFill)

    private func bar(_ k: Double, height h: CGFloat) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(barTrack)
                Capsule().fill(S.green).frame(width: g.size.width * CGFloat(min(1, max(0, k))))
            }
        }
        .frame(height: h)
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
            // SunnyHomeChart view="tv": 16 between the total, Ready to roll and the list.
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        BriefWords.line("$" + SampleEngine.fn(left), privacy: privacy)
                            .sType(SType(size: 34, weight: 800, line: 38, tracking: -0.02)).foregroundStyle(S.ink)
                            .fixedSize()   // the number never breaks; the words beside it wrap at large text (Audit 6)
                        Text("left of \(BriefWords.plain("$" + SampleEngine.fn(coll), privacy: privacy)) collected")
                            .accessibilityLabel(BriefMask.spoken("left of \(BriefWords.plain("$" + SampleEngine.fn(coll), privacy: privacy)) collected"))
                            .sType(SType(size: 15, weight: 500, line: 20, tracking: 0)).foregroundStyle(S.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(privacy ? "Time value left, hidden" : BSay.words("$\(SampleEngine.fn(left)) left of $\(SampleEngine.fn(coll)) collected"))
                    HStack(spacing: 10) {
                        bar(cap, height: 10)
                        // Worth more than it was sold for: a loss so far, in red without a minus sign (colour carries the sign).
                        Text("\(Int(abs(cap * 100).rounded()))% \(cap < -0.005 ? "given back" : "captured")").sType(SType(size: 13, weight: 700, line: 16, tracking: 0))
                            .foregroundStyle(cap < -0.005 ? S.red : S.green).fixedSize()
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Ready to roll").sType(SType(size: 17, weight: 700, line: 22, tracking: 0), tabular: false).foregroundStyle(S.ink)
                            Spacer(minLength: 0)
                            if !ready.isEmpty {   // "Nothing ready yet" below says it; no "0 strikes"
                                Text("\(ready.count) strike\(ready.count == 1 ? "" : "s")").sType(SType(size: 13, weight: 600, line: 16, tracking: 0)).foregroundStyle(S.secondary)
                            }
                        }
                        Text("Under $0.05 a share left, or 90% captured").sType(SType(size: 13, weight: 500, line: 17, tracking: 0)).foregroundStyle(S.secondary)
                    }
                    if ready.isEmpty {
                        Text("Nothing ready yet.").sType(BK.body, tabular: false).foregroundStyle(S.secondary)
                    } else {
                        ScrollView(.horizontal) {
                            // 148 wide cards, 10 apart, padding 14, radius 16, all as tall as the tallest.
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(ready) { r in rollCard(r) }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, S.margin).padding(.bottom, 2)
                        }
                        .scrollIndicators(.hidden)
                        .padding(.horizontal, -S.margin)
                    }
                }
                let byName = Dictionary(grouping: rows, by: \.t)
                let order = byName.keys.sorted { byName[$0]!.reduce(0) { $0 + $1.left } > byName[$1]!.reduce(0) { $0 + $1.left } }
                // A row per name between 1 pt rules: logo 26, the name 15/18 and its legs 13/16 over a bar 8 and its
                // percent 12/15, left and "of" on the right (64 wide at least), 10 across. The rows render 69 apart
                // in screen 24 (its CSS sums to 65): 13 above and below, 9 down to the bar, 3 down to "of".
                VStack(spacing: 0) {
                    BHairline()
                    ForEach(order, id: \.self) { t in
                        let rs = byName[t]!, l = rs.reduce(0) { $0 + $1.left }, c = rs.reduce(0) { $0 + $1.collected }
                        let k = c > 0 ? 1 - l / c : 0
                        HStack(spacing: 10) {
                            BLogo(ticker: t, size: 26)
                            VStack(alignment: .leading, spacing: 9) {
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Text(rs.first?.name ?? t).sType(SType(size: 15, weight: 600, line: 18, tracking: 0), tabular: false).foregroundStyle(S.ink)
                                        .lineLimit(1).layoutPriority(1)
                                    Text("· \(rs.map(\.leg).joined(separator: ", "))").sType(SType(size: 13, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.secondary)
                                        .lineLimit(dts > .large ? nil : 1)   // one line as designed; wraps in full at a large text size (Audit 6)
                                }
                                HStack(spacing: 8) {
                                    bar(k, height: 8)
                                    Text("\(Int(abs(k * 100).rounded()))%").sType(SType(size: 12, weight: 700, line: 15, tracking: 0))
                                        .foregroundStyle(k < -0.005 ? S.red : S.green).frame(minWidth: 34, alignment: .trailing)
                                }
                            }
                            VStack(alignment: .trailing, spacing: 3) {
                                BriefWords.line("$" + SampleEngine.fn(l), privacy: privacy).sType(SType(size: 15, weight: 800, line: 18, tracking: 0)).foregroundStyle(S.ink)
                                Text("of \(BriefWords.plain("$" + SampleEngine.fn(c), privacy: privacy))")
                                    .accessibilityLabel(BriefMask.spoken("of \(BriefWords.plain("$" + SampleEngine.fn(c), privacy: privacy))"))
                                    .sType(SType(size: 12, weight: 500, line: 15, tracking: 0)).foregroundStyle(S.secondary)
                            }
                            .fixedSize()
                            .frame(minWidth: 64, alignment: .trailing)
                        }
                        .padding(.vertical, 13)
                        .frame(minHeight: 44)
                        // One stop per name, the sign in words: "Nike, 36 calls, 71 contracts, 81% captured, $412 left of $2,130".
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(BSay.join([
                            rs.first?.name ?? t, BSay.words(rs.map(\.leg).joined(separator: ", ")),
                            "\(Int(abs(k * 100).rounded()))% \(k < -0.005 ? "given back" : "captured")",
                            privacy ? "amounts hidden" : BSay.words("$\(SampleEngine.fn(l)) left of $\(SampleEngine.fn(c))"),
                        ]))
                        BHairline()
                    }
                }
            }
            }
        }
    }

    /// A Ready to roll card: logo 32, 10, the name 15/19 and leg 13/17, then at the foot what is left 24/28 heavy and
    /// why, 13/17 bold and semibold.
    private func rollCard(_ r: Row) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            BLogo(ticker: r.t, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name).sType(SType(size: 15, weight: 600, line: 19, tracking: 0), tabular: false).foregroundStyle(S.ink).lineLimit(1)
                Text(r.leg).sType(SType(size: 13, weight: 500, line: 17, tracking: 0)).foregroundStyle(S.secondary).lineLimit(1)
                    .accessibilityLabel(BSay.words(r.leg))
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                // At a large text size "left" drops under the amount rather than cutting it (Pass 5).
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        BriefWords.line("$" + SampleEngine.fn(r.left), privacy: privacy)
                            .sType(SType(size: 24, weight: 800, line: 28, tracking: -0.01)).foregroundStyle(S.ink)
                        Text("left").sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        BriefWords.line("$" + SampleEngine.fn(r.left), privacy: privacy)
                            .sType(SType(size: 24, weight: 800, line: 28, tracking: -0.01)).foregroundStyle(S.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("left").sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    if r.intrinsic > 0 {
                        Text("$\(String(format: "%.2f", r.intrinsic)) in the money").sType(SType(size: 13, weight: 700, line: 17, tracking: 0)).foregroundStyle(S.red)
                        Text("Roll before Friday").sType(SType(size: 13, weight: 600, line: 17, tracking: 0), tabular: false).foregroundStyle(S.red)
                    } else {
                        Text("\(Int(((1 - r.left / max(r.collected, 1)) * 100).rounded()))% captured").sType(SType(size: 13, weight: 700, line: 17, tracking: 0)).foregroundStyle(S.act)
                        Text("Roll to next week").sType(SType(size: 13, weight: 600, line: 17, tracking: 0), tabular: false).foregroundStyle(S.act)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 148, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(S.chip))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The economy (12 indicators)

struct EconomySheet: View {
    /// The live sheet (doc.economy); the sample's in sample mode.
    var live: JSONValue = .null
    let close: () -> Void
    var body: some View {
        let e = BriefDebug.sample || live.isNull ? BriefSample.sheets["economy"] : live
        // The design's es sheet: the line under the title in the head, 14 to the cards, 12 apart, 16 from the sides.
        BriefSheetChrome(title: e["title"].string ?? "The economy", sub: e["sub"].string, gap: 14, side: 16, bottom: 32, close: close) {
            VStack(alignment: .leading, spacing: 12) {
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

    /// A date under the chart, as the design writes it for the range: "Mon", "Aug 3", "Aug", "Aug ’25".
    static func dateLabel(_ iso: String, _ range: String) -> String {
        let p = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return "" }
        var c = DateComponents(); c.year = p[0]; c.month = p[1]; c.day = p[2]
        guard let d = Calendar(identifier: .gregorian).date(from: c) else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = range == "1W" ? "EEE" : range == "1M" || range == "3M" ? "MMM d" : range == "All" ? "MMM ’yy" : "MMM"
        return f.string(from: d)
    }

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
        let dates = Array((live ? (wire?.dates ?? []) : SampleSeries.dates(all.count)).suffix(n + 1))
        ZStack(alignment: .top) {
            SBackground()
            // SunnyTickerChart.dc.html: the head 44 at the top (padding 0 16), the name and the move 14 under it
            // (padding 20), the chart 12 under that, the dates 8 under it, the ranges 8 under those, then the layers
            // 8 under and 34 off the bottom (here the safe area).
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Button(action: close) {
                        Path { p in p.move(to: CGPoint(x: 2, y: 2)); p.addLine(to: CGPoint(x: 12, y: 12)); p.move(to: CGPoint(x: 12, y: 2)); p.addLine(to: CGPoint(x: 2, y: 12)) }
                            .stroke(S.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 14, height: 14)
                            .frame(width: 44, height: 44).glassEffect(.regular, in: .circle)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Back")
                    HStack(spacing: 8) {
                        BriefLogoDisc(t: t, size: 32, pct: 0.7)
                        Text(t).sType(SType(size: 15, weight: 800, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                        Text(String(format: "$%.2f", q.0)).sType(SType(size: 15, weight: 600, line: 20, tracking: 0)).foregroundStyle(S.ink)
                        Text(String(format: "%.2f%%", abs(mv))).sType(SType(size: 15, weight: 600, line: 20, tracking: 0)).foregroundStyle(mv < 0 ? S.red : S.green)
                    }
                    .lineLimit(1)
                    .padding(.leading, 6).padding(.trailing, 16).frame(height: 44).glassEffect(.regular, in: .capsule)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(live && wire == nil ? name
                        : BSay.join([name, String(format: "$%.2f", q.0), "\(mv < 0 ? "down" : "up") \(String(format: "%.2f%%", abs(mv))) today"]))
                    .accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    HStack(spacing: 6) {
                        Text(String(format: "$%.2f %.2f%%", abs(ch), abs(chp))).sType(SType(size: 17, weight: 700, line: 22, tracking: 0)).foregroundStyle(ch < 0 ? S.red : S.green)
                        Text(Self.rangePhrase[range] ?? "")
                            .sType(SType(size: 17, weight: 500, line: 22, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    }
                    // "down $1.20, 3.50%, past 3 months": the colour's sign in words.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(ch < 0 ? "down" : "up") \(String(format: "$%.2f, %.2f%%", abs(ch), abs(chp))), \(Self.rangePhrase[range] ?? "")")
                }
                .padding(.horizontal, S.margin).padding(.top, 14)
                if live && wire == nil {
                    Group { if failed { Text("Could not load \(t). Try again in a moment.") } else { ProgressView() } }
                        .sType(BK.sub, tabular: false).foregroundStyle(S.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TickerLine(pts: pts, lines: lines, up: ch >= 0, key: range, layer: layer).frame(maxHeight: .infinity)
                        .padding(.top, 12)
                        // One stop for the chart; its line labels and the last-price chip are in the summary.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(chartSays(name, pts, q.0, lines))
                        .overlay(alignment: .topLeading) {
                            if live && lines.isEmpty {
                                Text(layer == "Positions" ? "Nothing held in \(t)" : layer == "Walls" ? "No walls saved for \(t)" : "")
                                    .sType(BK.small, tabular: false).foregroundStyle(S.secondary)
                                    .padding(.horizontal, S.margin).padding(.top, 12)
                            }
                        }
                    // The dates under it: 12/16, at 8, 36, 64 and 92% of the plot (the price column is 56).
                    GeometryReader { g in
                        let w = g.size.width - 56
                        ForEach(Array([0.08, 0.36, 0.64, 0.92].enumerated()), id: \.offset) { _, f in
                            let i = Int((f * Double(max(0, dates.count - 1))).rounded())
                            if dates.indices.contains(i) {
                                Text(Self.dateLabel(dates[i], range)).sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false)
                                    .foregroundStyle(S.secondary).fixedSize()
                                    .position(x: w * f, y: 8)
                            }
                        }
                    }
                    .frame(height: 16).padding(.top, 8)
                    .environment(\.sTypeScales, false)
                    .accessibilityHidden(true)
                }
                // Ranges: six equal 44 pt targets, 2 apart, padding 8 12 0; the chip 32 tall, 10 a side, 14 bold picked.
                HStack(spacing: 2) {
                    ForEach(["1W", "1M", "3M", "YTD", "1Y", "All"], id: \.self) { r in
                        // The chips' colour fades (S.fade); the line crossfades and its labels move in TickerLine.
                        Button { withAnimation(S.fade) { range = r } } label: {
                            Text(r).sType(SType(size: 14, weight: r == range ? 700 : 600, line: 14, tracking: 0), tabular: false)
                                .foregroundStyle(r == range ? S.sheetFill : S.secondary)
                                .padding(.horizontal, 10).frame(height: 32).background(Capsule().fill(r == range ? S.ink : .clear))
                                .frame(maxWidth: .infinity).frame(height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .accessibilityLabel(Self.rangeWords[r] ?? r)
                        .accessibilityAddTraits(r == range ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 12).padding(.top, 8)
                .sensoryFeedback(.selection, trigger: range)
                // Layers: 48 tall, 8 apart, padding 8 16; a 14 x 3 swatch 8 before the words (15 semibold).
                HStack(spacing: 8) {
                    ForEach(["Positions", "Technicals", "Walls"], id: \.self) { l in
                        let on = layer == l
                        Button { withAnimation(S.fade) { layer = l } } label: {
                            HStack(spacing: 8) {
                                Group {
                                    switch l {
                                    case "Technicals": Capsule().fill(S.teal)
                                    case "Walls": HStack(spacing: 0) { Rectangle().fill(S.navy); Rectangle().fill(S.brown) }.clipShape(Capsule())
                                    default: Capsule().fill(on ? S.sheetFill : S.ink)
                                    }
                                }
                                .frame(width: 14, height: 3)
                                .accessibilityHidden(true)
                                Text(l).sType(SType(size: 15, weight: 600, line: 15, tracking: 0), tabular: false).foregroundStyle(on ? S.sheetFill : S.ink)
                            }
                            // flex 1 0 auto: never under its own width, the rest shared.
                            .padding(.horizontal, 16).fixedSize()
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background { if on { Capsule().fill(S.ink) } }
                            .glassEffect(on ? .identity : .regular, in: .capsule)
                        }.buttonStyle(.plain)
                        .accessibilityLabel("\(l) lines")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8)
                .sensoryFeedback(.selection, trigger: layer)
            }
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
    /// A labelled line keyed by what it is (label and strike), not its place in the list: a layer switch fades the
    /// old lines out and the new ones in instead of sliding one label into another. `y` is where its tag sits.
    struct Mark: Identifiable { let id: String; let k: Double; let label: String; let solid: Bool; let y: CGFloat }

    /// The design's spr: tags sorted top to bottom inside [lo, hi], each at least `gap` under the one above, the
    /// last pushed back up if it runs past the bottom.
    static func spread(_ ys: [CGFloat], lo: CGFloat, hi: CGFloat, gap: CGFloat = 19) -> [CGFloat] {
        let order = ys.indices.sorted { ys[$0] < ys[$1] }
        var v = order.map { min(hi, max(lo, ys[$0])) }
        for i in v.indices.dropFirst() where v[i] - v[i - 1] < gap { v[i] = v[i - 1] + gap }
        if let last = v.last, last > hi {
            v[v.count - 1] = hi
            for i in stride(from: v.count - 2, through: 0, by: -1) where v[i + 1] - v[i] < gap { v[i] = v[i + 1] - gap }
        }
        var out = ys
        for (j, i) in order.enumerated() { out[i] = v[j] }
        return out
    }

    let pts: [Double]
    let lines: [(k: Double, label: String, solid: Bool)]
    let up: Bool
    /// The range on screen: a new range redraws the line (a 0.3 s crossfade, S.lineMorph).
    var key: String = ""
    /// Positions tag on the left in ink; Technicals (teal) and Walls on the right.
    var layer = "Positions"
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        GeometryReader { g in
            // The plot is the width less the 56 pt price column; 14 clear on top, 12 under (PT, PB).
            // The design's scale: the closes, stretched to lines within 8% of the price beyond them, plus 5% of the span.
            let px = pts.last ?? 0, c0 = pts.min() ?? 0, c1 = pts.max() ?? 1
            let near = lines.map(\.k).filter { $0 >= c0 - px * 0.08 && $0 <= c1 + px * 0.08 }
            let lo1 = min(c0, near.min() ?? c0), hi1 = max(c1, near.max() ?? c1)
            let sp = hi1 - lo1 > 0 ? hi1 - lo1 : max(0.01, px * 0.02)
            let lo = lo1 - sp * 0.05, hi = hi1 + sp * 0.05
            let W = g.size.width - 56, H = g.size.height, PT: CGFloat = 14, PB: CGFloat = 12
            let X = { (i: Int) -> CGFloat in CGFloat(i) / CGFloat(max(1, pts.count - 1)) * W }
            let Y = { (p: Double) -> CGFloat in PT + CGFloat((hi - p) / max(1e-9, hi - lo)) * (H - PT - PB) }
            let left = layer == "Positions", tint = layer == "Technicals" ? S.teal : S.ink
            let shown = lines.filter { $0.k >= lo && $0.k <= hi }.sorted { $0.k > $1.k }
            let tagY = Self.spread(shown.map { Y($0.k) }, lo: PT + 7, hi: H - PB - 7)
            let marks: [Mark] = {
                var seen: [String: Int] = [:]
                return shown.enumerated().map { i, l in
                    let base = "\(l.label)|\(l.k)", n = seen[base, default: 0]
                    seen[base] = n + 1
                    return Mark(id: n == 0 ? base : "\(base)#\(n)", k: l.k, label: l.label, solid: l.solid, y: tagY[i])
                }
            }()
            // The price grid: about five steps of 1, 2, 2.5, 5 or 10 times a power of ten, labelled at the right
            // (12/14) unless within 14 of the last-price pill.
            let raw = max(1e-9, (hi - lo) / 5), mag = pow(10, floor(log10(raw)))
            let stp = [1, 2, 2.5, 5, 10].map { $0 * mag }.first { $0 >= raw } ?? 10 * mag
            let dec = stp >= 1 ? (stp.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1) : 2
            let grid = stride(from: (lo / stp).rounded(.up) * stp, through: hi + 1e-9, by: stp).filter { Y($0) >= 4 && Y($0) <= H - 4 }
            let pyC = max(PT, min(H - PB, Y(pts.last ?? lo)))
            // A plain Path does not interpolate, so a new line (range, or a scale change from a layer) crossfades.
            let lineKey = "\(key)|\(pts.count)|\(pts.first ?? 0)|\(pts.last ?? 0)|\(lo)|\(hi)"
            ZStack(alignment: .topLeading) {
                ForEach(grid, id: \.self) { v in
                    Path { $0.move(to: CGPoint(x: 0, y: Y(v))); $0.addLine(to: CGPoint(x: W, y: Y(v))) }.stroke(S.pRule, lineWidth: 1)
                    if abs(Y(v) - pyC) > 14 {
                        Text(String(format: "%.\(dec)f", v)).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(S.secondary)
                            .fixedSize().frame(width: 48, height: 14, alignment: .trailing)
                            .offset(x: W + 56 - 8 - 48, y: Y(v) - 7)
                    }
                }
                // The range's first close, dotted (the design's ref line).
                if let first = pts.first {
                    Path { $0.move(to: CGPoint(x: 0, y: Y(first))); $0.addLine(to: CGPoint(x: W, y: Y(first))) }
                        .stroke(S.secondary.opacity(0.8), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [1, 4]))
                        .animation(S.moving(S.lineMorph, reduce), value: Y(first))
                }
                ForEach(marks) { m in
                    ZStack(alignment: .topLeading) {
                        // Sold solid, bought dotted (1 on, 4 off), 1.5 pt.
                        Path { $0.move(to: CGPoint(x: 0, y: Y(m.k))); $0.addLine(to: CGPoint(x: W, y: Y(m.k))) }
                            .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: m.solid ? [] : [1, 4]))
                        // The tag: 11/14 bold, padding 1 6, radius 7, on the chart chip; left at 12, or right 6 in.
                        Text(m.label).font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(tint)
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 6).frame(height: 16)
                            .background(RoundedRectangle(cornerRadius: 7).fill(S.chartChip))
                            .frame(width: W - 18, height: 16, alignment: left ? .leading : .trailing)
                            .offset(x: 12, y: m.y - 8)
                    }
                    // A line that stays moves to its new height with the redraw; nothing slides under Reduce Motion.
                    .animation(S.moving(S.lineMorph, reduce), value: [Y(m.k), m.y])
                    .transition(.opacity)
                }
                ZStack {
                    Path { p in for (i, v) in pts.enumerated() { let pt = CGPoint(x: X(i), y: Y(v)); i == 0 ? p.move(to: pt) : p.addLine(to: pt) } }
                        .stroke(up ? S.green : S.red, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .id(lineKey)
                        .transition(.opacity)
                }
                .animation(S.lineMorph, value: lineKey)
                if let last = pts.last {
                    // The last close: a 9 pt dot ringed 2 in the page, and its pill at the right (12/14 bold, padding 3 6).
                    Circle().fill(up ? S.green : S.red).frame(width: 9, height: 9)
                        .background(Circle().fill(S.dyn(0xF1F2F4, 0x0A0F0C)).padding(-2))
                        .offset(x: W - 4.5, y: Y(last) - 4.5)
                    Text(String(format: "%.2f", last)).font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(S.onSignal)
                        .fixedSize().padding(.horizontal, 6).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 8).fill(up ? S.green : S.red))
                        .frame(width: 52, alignment: .trailing)
                        .offset(x: W, y: pyC - 10)
                        .animation(S.moving(S.lineMorph, reduce), value: pyC)
                }
            }
        }
    }
}
