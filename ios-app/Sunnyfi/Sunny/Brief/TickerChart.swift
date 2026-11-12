//
//  TickerChart.swift
//  Sunny
//
//  The ticker chart, pushed from a name tile (block 33, SunnyTickerChart.dc.html). Moved here from
//  BriefOverlays.swift on 8 Nov 2026 (type pass) so it can change without touching the sheets.
//
//  8 Nov 2026, Nik on his iPhone 15 Pro (iOS 27): "I should be able to switch off positions"; "Numbers on the right
//  are getting cut off and who can read positions this way also there is a drag to compress the chart it's not
//  working"; "X button is also almost cut off". Built as the design codes it:
//  · Layers are switches, any number on at once (the design's aria-pressed chips). Positions starts on when the
//    name is held, and its chip only shows then. Walls leave room after today for the chain ahead.
//  · The price column on the right (56 wide) is a drag: up zooms in, down zooms out, around the price under the
//    finger (span × e^(dy/160), from a sixth to four times the auto span). A double tap or Auto goes back.
//  · The dates under the chart are the same drag sideways (Nik 10 Nov 2026: "one is up and down to get the prices
//    closer and one is left and right to spread out the chart"): right spreads the days out around the day under
//    the finger, left squeezes them back, from one week to the whole range; the auto price scale fits the days on
//    screen. A double tap on the dates, Auto, or a new range goes back.
//  · A pinch on the chart (Nik 12 Nov 2026: "when you pinch on the chart we should be able to zoom in also") follows
//    the fingers: their spread sideways scales the days, up and down the prices, around the point between them. Held
//    within 25° of flat it moves only the days, within 25° of upright only the prices, in between both. Same limits as
//    the two drags; Auto or a double tap goes back.
//  · A tag per leg ("Sold call 40 ×50"), 19 apart so none overlaps; off the scale it pins to the edge with an arrow.
//  · ⚠ THE PAGE IS EXACTLY THE SCREEN. The layer chips sat at their own width in a plain HStack: one text size up
//    they summed wider than the phone, the page grew past the screen and, centred, lost both edges (the price
//    numbers on the right, the X on the left). Now the chips scroll (the design's overflow-x: auto), the page is
//    framed to the screen, the X sits at the window's real top inset, and the price column widens before a
//    number would be cut.
//

import SwiftUI
import UIKit

// MARK: - Tokens

/// SunnyTickerChart.dc.html's own tokens ([data-tk]). Where they differ from the app's S tokens the design wins:
/// muted text #646469 (not #6E6E73), technicals #0F7F86 (not #0B6F75), tags on an 88% chip.
enum TK {
    static let ink = S.ink
    static let mu = S.dyn(0x646469, 0x98989D)
    static let line = S.dynA(0x1D1D1F, 0.08, 0xFFFFFF, 0.10)
    static let call = S.dyn(0x2F5AA8, 0x86A8F0)
    static let put = S.dyn(0x995123, 0xE8975C)
    static let tc = S.dyn(0x0F7F86, 0x4CC9D0)
    static let chip = S.dynA(0xFFFFFF, 0.88, 0x1C1C1E, 0.88)
    static let onink = S.dyn(0xFFFFFF, 0x1C1C1E)
    static let ring = S.dyn(0xF1F2F4, 0x0A0B0D)
    /// Overbought / Oversold (the design's --or: #A34B00, dark #F2A93B).
    static let or = S.dyn(0xA34B00, 0xF2A93B)
    /// RSI's 70 to 30 band (--tc-t) and the Walls band, the move priced by Friday (--band).
    static let tcTint = S.dynA(0x0F7F86, 0.10, 0x4CC9D0, 0.14)
    static let band = S.dynA(0x767680, 0.14, 0x767680, 0.26)

    /// The world markets Overnight lists (sunny-home WORLD), opened by symbol (10 Nov 2026): the name on the capsule,
    /// the line under it, and how its price reads (an index in points, the 10-year yield in %, the rest in dollars).
    enum Unit { case dollars, points, yield }
    static let markets: [String: (name: String, sub: String, unit: Unit)] = [
        "^N225": ("Nikkei", "Nikkei 225 · Japan", .points), "^HSI": ("Hang Seng", "Hang Seng Index · Hong Kong", .points),
        "000001.SS": ("Shanghai", "Shanghai Composite · China", .points), "^GDAXI": ("DAX", "DAX · Germany", .points),
        "^TNX": ("10y yield", "US 10-year Treasury yield", .yield), "DX-Y.NYB": ("Dollar", "US dollar index", .points),
        "CL=F": ("Oil", "WTI crude futures", .dollars), "GC=F": ("Gold", "Gold futures", .dollars),
        "BTC-USD": ("Bitcoin", "Bitcoin in dollars · trades 24/7", .dollars),
    ]
    static func unit(_ t: String) -> Unit { markets[t]?.unit ?? .dollars }
    /// A price as the name trades: "$38.59", "$74,726.12", "60,459.58" for an index, "4.94%" for the yield.
    static func price(_ v: Double, _ t: String) -> String {
        let n = grouped(v)
        switch unit(t) { case .dollars: return "$" + n; case .points: return n; case .yield: return String(format: "%.2f%%", v) }
    }
    /// A move in the name's own terms, unsigned: "$1.20", "512.40" points, "12 bp" for the yield.
    static func change(_ v: Double, _ t: String) -> String {
        unit(t) == .yield ? "\(Int((abs(v) * 100).rounded())) bp" : price(abs(v), t)
    }
    /// One formatter per number of decimals, built once (the axis asks on every frame of a drag).
    nonisolated(unsafe) private static var groupedFmts: [Int: NumberFormatter] = [:]
    private static let fmtLock = NSLock()
    /// "60,459.58"; "70,000" with no decimals.
    static func grouped(_ v: Double, _ dec: Int = 2) -> String {
        fmtLock.lock(); defer { fmtLock.unlock() }
        let f = groupedFmts[dec] ?? {
            let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_US")
            f.minimumFractionDigits = dec; f.maximumFractionDigits = dec
            groupedFmts[dec] = f
            return f
        }()
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.\(dec)f", v)
    }
    /// A percentage as the design writes it: one decimal, two under 0.1%.
    static func pct(_ x: Double) -> String { String(format: abs(x) < 0.1 ? "%.2f%%" : "%.1f%%", abs(x)) }
    /// A strike as the design's fk(): "40", "42.5", "40.85".
    static func fk(_ k: Double) -> String {
        k.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", k) : String(format: "%g", (k * 100).rounded() / 100)
    }
    /// A string's width in Inter at a size and weight, tabular figures, as drawn.
    static func width(_ s: String, _ size: CGFloat, _ weight: CGFloat) -> CGFloat {
        let f = SType(size: size, weight: weight, line: size, tracking: 0).uiFont(tabular: true)
        return ceil((s as NSString).size(withAttributes: [.font: f]).width)
    }
    /// The phone's own safe area, read from the window: the floor under the X whatever the views around the page do.
    @MainActor static var windowInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let w = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        return w?.safeAreaInsets ?? .zero
    }
}

/// The page behind the chart: #EEF2F0 → #F1F2F4 (38%) → #F3F1EE; dark #0E1217 → #0A0B0D (45%) → #0D0C0B. No glows.
private struct TKBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = { (h: UInt32) in Color(UIColor(hex: h)) }
        LinearGradient(stops: scheme == .dark
                       ? [.init(color: c(0x0E1217), location: 0), .init(color: c(0x0A0B0D), location: 0.45), .init(color: c(0x0D0C0B), location: 1)]
                       : [.init(color: c(0xEEF2F0), location: 0), .init(color: c(0xF1F2F4), location: 0.38), .init(color: c(0xF3F1EE), location: 1)],
                       startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A labelled level on the price: a leg, a wall or a technical line, drawn the way its layer draws it.
struct TKMark: Identifiable {
    let id: String
    let k: Double
    let label: String
    let color: Color
    var width: CGFloat = 1.5
    var dash: [CGFloat] = []
    /// Positions tag on the left; walls and technicals on the right.
    var right = false
    /// Walls run on through the room after today; the rest stop at today.
    var full = false
    /// False for a second leg on a strike already drawn: its tag only.
    var line = true
}

/// The Technicals of every close, built once per name (the design's hist()): the 20, 50 and 200-day simple averages
/// (nil until a full window) and RSI 14 (the up moves over the down moves in the last 14 days; 50 before that).
nonisolated struct TKCalc: Sendable {
    let ma: [Int: [Double?]]
    let rsi: [Double]
    init(_ c: [Double]) {
        let n = c.count
        var m: [Int: [Double?]] = [:]
        for L in [20, 50, 200] {
            var a = [Double?](repeating: nil, count: n), s = 0.0
            for i in 0..<n { s += c[i]; if i >= L { s -= c[i - L] }; if i >= L - 1 { a[i] = s / Double(L) } }
            m[L] = a
        }
        var r = [Double](repeating: 50, count: n)
        if n > 14 {
            for i in 14..<n {
                var up = 0.0, dn = 0.0
                for j in (i - 13)...i { let x = c[j] - c[j - 1]; if x > 0 { up += x } else { dn -= x } }
                r[i] = dn > 0 ? 100 - 100 / (1 + up / dn) : 100
            }
        }
        ma = m; rsi = r
    }
}

/// One moving average over the range on screen, and its dash (20 solid, 50 6 4, 200 1 4).
struct TKMA: Identifiable { let id: Int; let vals: [Double?]; let dash: [CGFloat] }

/// The readout under the name: its pieces 6 apart, wrapping to a new line when they don't fit (CSS flex-wrap).
private struct TKFlow: Layout {
    var spacing: CGFloat = 6
    /// How many lines pieces of these widths take in `maxW`, wrapped as below.
    static func lines(_ widths: [CGFloat], maxW: CGFloat, spacing: CGFloat = 6) -> Int {
        var n = widths.isEmpty ? 0 : 1, x: CGFloat = 0
        for w in widths {
            if x > 0 && x + spacing + w > maxW { n += 1; x = 0 }
            x = (x > 0 ? x + spacing : 0) + w
        }
        return n
    }
    private func rows(_ maxW: CGFloat, _ subviews: Subviews) -> [CGRect] {
        var out: [CGRect] = [], x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + spacing + sz.width > maxW { y += rowH; x = 0; rowH = 0 }
            let px = x > 0 ? x + spacing : 0
            out.append(CGRect(x: px, y: y, width: sz.width, height: sz.height))
            x = px + sz.width; rowH = max(rowH, sz.height)
        }
        return out
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let r = rows(proposal.width ?? .infinity, subviews)
        return CGSize(width: r.map(\.maxX).max() ?? 0, height: r.map(\.maxY).max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = rows(bounds.width, subviews)
        for (i, s) in subviews.enumerated() {
            s.place(at: CGPoint(x: bounds.minX + r[i].minX, y: bounds.minY + r[i].minY), proposal: ProposedViewSize(r[i].size))
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
    /// The layers switched on. Nil until a chip is tapped: the design's default, Positions on when the name is held.
    @State private var lay: Set<Layer>?
    @State private var wire: TickerWire?
    @State private var failed = false
    /// The averages and RSI of every close, built once when the closes arrive (never in the body).
    @State private var calc: TKCalc?
    /// The close under the finger while it scrubs the chart (an index into the range on screen); nil at rest.
    @State private var si: Int?
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.sTypeScales) private var scales

    enum Layer: String, CaseIterable { case pos = "Positions", tech = "Technicals", walls = "Walls" }

    private var live: Bool { !BriefDebug.sample }
    /// Held: the server sent legs (or shares) in this name; in sample mode, the sample book holds it.
    private var held: Bool { live ? !(wire?.positions.isEmpty ?? true) : SampleBook.book(acct)[t] != nil }
    /// The chips: Positions only for a name held (the design filters it out otherwise).
    /// A world market has no walls or legs: Technicals only.
    private var chips: [Layer] { Layer.allCases.filter { ($0 != .pos || held) && ($0 != .walls || TK.markets[t] == nil) } }
    private var on: Set<Layer> { (lay ?? (held ? [.pos] : [])).filter { chips.contains($0) } }

    /// The range chips in words, and the phrase under the price.
    private static let rangeWords = ["1W": "1 week", "1M": "1 month", "3M": "3 months", "YTD": "year to date", "1Y": "1 year", "All": "all"]
    private static let rangePhrase = ["1W": "past week", "1M": "past month", "3M": "past 3 months", "YTD": "this year", "1Y": "past year"]

    private static func day(_ iso: String) -> Date? {
        let p = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        var c = DateComponents(); c.year = p[0]; c.month = p[1]; c.day = p[2]
        return Calendar(identifier: .gregorian).date(from: c)
    }
    /// One formatter per pattern, built once (a formatter per date was the cost while the finger scrubs).
    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]
    private static let formatLock = NSLock()
    private static func format(_ d: Date, _ f: String) -> String {
        formatLock.lock(); defer { formatLock.unlock() }
        if let x = formatters[f] { return x.string(from: d) }
        let x = DateFormatter(); x.locale = Locale(identifier: "en_US_POSIX"); x.timeZone = TimeZone(identifier: "UTC"); x.dateFormat = f
        formatters[f] = x
        return x.string(from: d)
    }
    /// A date under the chart, as the design writes it for the range: "Mon", "Aug 3", "Aug", "Aug ’25".
    static func dateLabel(_ iso: String, _ range: String) -> String {
        guard let d = day(iso) else { return "" }
        return format(d, range == "1W" ? "EEE" : range == "1M" || range == "3M" ? "MMM d" : range == "All" ? "MMM ’yy" : "MMM")
    }
    /// A close under the finger, as the design's readout writes it: "Fri Oct 30 close" on 1W, "Aug 3" on 1M to YTD,
    /// "Aug 3, 2025" on 1Y and All.
    static func scrubLabel(_ iso: String, _ range: String) -> String {
        guard let d = day(iso) else { return "" }
        return range == "1W" ? format(d, "EEE MMM d") + " close" : format(d, range == "1Y" || range == "All" ? "MMM d, yyyy" : "MMM d")
    }
    /// The range's first close (the design's d0): "Fri Oct 23", "Aug 3", "Nov 8, 2021".
    static func firstLabel(_ iso: String?, _ range: String) -> String {
        guard let iso, let d = day(iso) else { return "the start" }
        return format(d, range == "1W" ? "EEE MMM d" : range == "1Y" || range == "All" ? "MMM d, yyyy" : "MMM d")
    }

    /// The chart as one spoken line: "Nike price, past 3 months, from $33.10 to $35.28. Lines: Sold call 36 ×72, ...".
    private func chartSays(_ name: String, _ pts: [Double], _ now: Double, _ phrase: String, _ marks: [TKMark]) -> String {
        guard let a = pts.first, let b = pts.last else { return "\(name) price chart, no data" }
        let f = { (v: Double) in TK.price(v, t) }
        let head = BSay.join(["\(name) price", phrase, "from \(f(a)) to \(f(b))", f(now) == f(b) ? nil : "now \(f(now))"])
        let ls = marks.map { m -> String in
            let said = BSay.words(m.label)
            return said.contains(TK.fk(m.k)) ? said : "\(said) at \(f(m.k))"
        }
        return ls.isEmpty ? head : head + ". Lines: " + ls.joined(separator: "; ")
    }

    var body: some View {
        let q = live ? (wire?.price ?? 0, wire?.prev ?? 0) : (SampleBook.q[t] ?? (0, 0))
        let mv = q.1 > 0 ? (q.0 - q.1) / q.1 * 100 : 0
        let all = live ? (wire?.closes ?? []) : SampleSeries.year(t)
        let ytd = live ? (wire?.ytdCount ?? 210) : 210
        // Bitcoin trades every day: seven closes a week, so its ranges hold 7/5 as many to cover the same weeks.
        let wk = t == "BTC-USD" ? 7.0 / 5.0 : 1.0, d = { (x: Int) in Int((Double(x) * wk).rounded()) }
        let n = ["1W": d(5), "1M": d(22), "3M": d(63), "YTD": ytd, "1Y": d(252), "All": all.count][range] ?? d(63)
        let pts = Array(all.suffix(n + 1))
        let ch = (pts.last ?? 0) - (pts.first ?? 0), chp = (pts.first ?? 0) > 0 ? ch / pts[0] * 100 : 0
        let name = TK.markets[t]?.sub ?? (live ? (wire?.short ?? wire?.name ?? t) : (SampleBook.company[t] ?? t))
        let dates = Array((live ? (wire?.dates ?? []) : SampleSeries.dates(all.count)).suffix(n + 1))
        let d0 = Self.firstLabel(dates.first, range)
        // "past 3 months"; All reads "since Nov 8, 2021" (the design's d0).
        let phrase = range == "All" ? "since " + d0 : (Self.rangePhrase[range] ?? "")
        // The sub line (13/16 600 muted): the name and its strategy word ("Nike · Rebound"); a name not held that is
        // on the watchlist says so; else the name alone.
        let stRaw = live ? wire?.strategy : SampleBook.book(acct)[t]?.strategy
        let st = Strategy.name(stRaw?.lowercased()) ?? stRaw.flatMap { $0.isEmpty ? nil : $0.prefix(1).uppercased() + $0.dropFirst() }
        let sub = name + (st.map { " · " + $0 } ?? (!held && (wire?.watch ?? false) ? " · Watchlist" : ""))
        let on = self.on
        // The range's averages and RSI, cut from the whole history so the 200-day is right from the first close.
        let s0 = max(0, all.count - pts.count)
        let ma: [TKMA] = calc.map { c in
            [(20, [CGFloat]()), (50, [6, 4]), (200, [1, 4])].compactMap { m, dash -> TKMA? in
                guard let a = c.ma[m], a.count == all.count else { return nil }
                return TKMA(id: m, vals: Array(a[s0...]), dash: dash)
            }
        } ?? []
        let rsi: [Double]? = calc.flatMap { $0.rsi.count == all.count ? Array($0.rsi[s0...]) : nil }
        // The move priced by Friday (one weekly SD): the server's for the book, the sample IV's in a -sample run.
        let sd: Double? = live ? wire?.sd : SampleBook.iv[t].map { $0 * (5.0 / 252).squareRoot() * 100 }
        let walls = wallMarks(price: q.0), tech = techMarks(ma)
        let marks = (on.contains(.pos) ? positionMarks() : []) + (on.contains(.walls) ? walls : []) + (on.contains(.tech) ? tech : [])
        let room = on.contains(.walls) && !walls.isEmpty
        let band: TickerLine.Scale? = room ? sd.map { TickerLine.Scale(lo: q.0 * (1 - $0 / 100), hi: q.0 * (1 + $0 / 100)) } : nil
        // The scale reaches for the walls, the band and the averages near the price whatever is on, so a layer
        // never rescales the chart (the design's ext).
        let ext = walls.map(\.k) + ma.flatMap { $0.vals.compactMap { $0 } } + (sd.map { [q.0 * (1 + $0 / 100), q.0 * (1 - $0 / 100)] } ?? [])
        let at = si.flatMap { $0 < pts.count && $0 < dates.count ? $0 : nil }
        GeometryReader { g in
            // ⚠ The X sits at the real top inset: the larger of what this view is told and the window's own, so a
            // container that drops the safe area (or a future iOS that lays the page out under the status bar)
            // cannot lift it into the Dynamic Island. The page is exactly the screen and top-aligned: if its
            // content ever runs taller, the bottom gives, never the top.
            let win = TK.windowInsets
            let top = max(g.safeAreaInsets.top, win.top), bottom = max(g.safeAreaInsets.bottom, win.bottom, 16)
            VStack(alignment: .leading, spacing: 0) {
                header(q, mv, name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sub).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(TK.mu)
                        .lineLimit(1)
                    readout(pts: pts, dates: dates, at: at, ch: ch, chp: chp, phrase: phrase, d0: d0, width: g.size.width - 40)
                }
                .padding(.horizontal, 20).padding(.top, 14)
                if live && wire == nil {
                    Group { if failed { Text("Could not load \(t). Try again in a moment.") } else { ProgressView() } }
                        .sType(BK.sub, tabular: false).foregroundStyle(TK.mu)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // The chart 12 under the readout (240 at least), RSI 10 under it (76) while Technicals is on, the
                    // dates 8 under those (16 tall).
                    TickerLine(pts: pts, dates: dates, range: range, marks: marks, ext: ext, room: room,
                               roomLabel: wallExp, up: ch >= 0, summary: chartSays(name, pts, q.0, phrase, marks),
                               ma: on.contains(.tech) ? ma : [], rsi: on.contains(.tech) ? rsi : nil, band: band, si: $si)
                        .frame(minHeight: 240 + (on.contains(.tech) && rsi != nil ? 86 : 0) + 24, maxHeight: .infinity)
                        .padding(.top, 12)
                    // The design's note under the dates (13/18 500 muted, 10 under, 20 in) while Walls is on.
                    if on.contains(.walls) {
                        Text(walls.isEmpty ? "No walls saved for \(t)."
                             : "Walls from the \(wallExp) chain." + (sd.map { " Shaded: the move priced by Friday, ±\(String(format: "%.1f", $0))%." } ?? ""))
                            .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(TK.mu)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20).padding(.top, 10)
                            .transition(.opacity)
                    }
                }
                ranges
                layerRow(width: g.size.width)
            }
            .padding(.top, top).padding(.bottom, bottom)
            .padding(.leading, g.safeAreaInsets.leading).padding(.trailing, g.safeAreaInsets.trailing)
            .frame(width: g.size.width, height: g.size.height, alignment: .top)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .background(TKBackground())
        // A full-screen page over Home: VoiceOver stays on it until Close.
        .accessibilityAddTraits(.isModal)
        .task(id: t) {
            guard live else { calc = TKCalc(SampleSeries.year(t)); return }
            do {
                let w = try await TickerChartClient.fetch(t: t, book: book)
                calc = TKCalc(w.closes)   // once per name: three averages and RSI over about 1,250 closes
                wire = w
            } catch { failed = true }
        }
    }

    /// The readout, 17/22 with its pieces 6 apart. At rest: the move over the range in dollars and percent (700, the
    /// line's colour) and the range (500 muted). Under the finger: the close's date (600 ink), its price (700 ink), the
    /// move since the range's first close (700, green or red) and "since" that date (500 muted). Its height holds
    /// whichever of the two needs more lines, so the chart never jumps while the finger scrubs.
    private func readout(pts: [Double], dates: [String], at: Int?, ch: Double, chp: Double, phrase: String, d0: String, width: CGFloat) -> some View {
        let tBold = SType(size: 17, weight: 700, line: 22, tracking: 0), tSemi = SType(size: 17, weight: 600, line: 22, tracking: 0)
        let tMed = SType(size: 17, weight: 500, line: 22, tracking: 0)
        let sc = { (x: SType) in scales ? x.scaled(dts) : x }
        let w = { (s: String, x: SType) in TK.width(s, sc(x).size, x.weight) }
        let first = pts.first ?? 0
        // The 10-year yield moves in bp alone (as Overnight writes it), never a percent of a percent.
        let bp = TK.unit(t) == .yield
        let rest = [w(TK.change(ch, t), tBold)] + (bp ? [] : [w(TK.pct(chp), tBold)]) + [w(phrase, tMed)]
        // The widest a scrub can read on this range: a wide date of its kind, the highest price, a two-digit move.
        let wide = range == "1W" ? "Wed May 28 close" : range == "1Y" || range == "All" ? "May 28, 2026" : "May 28"
        let scrub = [w(wide, tSemi), w(TK.price(pts.max() ?? 0, t), tBold), w("88.8%", tBold), w("since " + d0, tMed)]
        let lines = max(1, TKFlow.lines(rest, maxW: width), TKFlow.lines(scrub, maxW: width))
        return TKFlow(spacing: 6) {
            if let i = at {
                let up = pts[i] >= first, mvp = first > 0 ? (pts[i] / first - 1) * 100 : 0
                Text(Self.scrubLabel(dates[i], range)).sType(tSemi, tabular: false).foregroundStyle(TK.ink)
                Text(TK.price(pts[i], t)).sType(tBold).foregroundStyle(TK.ink)
                Text(bp ? TK.change(pts[i] - first, t) : TK.pct(mvp)).sType(tBold).foregroundStyle(up ? S.green : S.red)
                Text("since " + d0).sType(tMed, tabular: false).foregroundStyle(TK.mu)
            } else {
                Text(TK.change(ch, t)).sType(tBold).foregroundStyle(ch < 0 ? S.red : S.green)
                if !bp { Text(TK.pct(chp)).sType(tBold).foregroundStyle(ch < 0 ? S.red : S.green) }
                Text(phrase).sType(tMed, tabular: false).foregroundStyle(TK.mu)
            }
        }
        .frame(minHeight: CGFloat(lines) * sc(tBold).line, alignment: .topLeading)
        // "down $1.20, 3.5%, past 3 months" (or the close under the finger): the colour's sign in words.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(at.map { i in
            let up = pts[i] >= first
            return "\(Self.scrubLabel(dates[i], range)), \(TK.price(pts[i], t)), \(up ? "up" : "down") \(bp ? TK.change(pts[i] - first, t) : TK.pct(first > 0 ? (pts[i] / first - 1) * 100 : 0)) since \(d0)"
        } ?? "\(ch < 0 ? "down" : "up") \(TK.change(ch, t)), \(bp ? "" : TK.pct(chp) + ", ")\(phrase)")
    }

    /// The head, 44 tall, 16 in: the X (a 44 glass circle, the cross 14 at 2) and 10 on the capsule with the logo
    /// 32, the ticker 15/20 800, the price and today's move 15/20 600 (padding 0 16 0 6, 8 apart).
    private func header(_ q: (Double, Double), _ mv: Double, _ name: String) -> some View {
        HStack(spacing: 10) {
            Button(action: close) {
                Path { p in p.move(to: CGPoint(x: 2, y: 2)); p.addLine(to: CGPoint(x: 12, y: 12)); p.move(to: CGPoint(x: 12, y: 2)); p.addLine(to: CGPoint(x: 2, y: 12)) }
                    .stroke(TK.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 14, height: 14)
                    .frame(width: 44, height: 44).glassEffect(.regular, in: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Close")
            HStack(spacing: 8) {
                // The logo for a name held; for any other, 6 of space instead (the design's noLogo span).
                if held { BriefLogoDisc(t: t, size: 32, pct: 0.7) } else { Color.clear.frame(width: 6, height: 1).accessibilityHidden(true) }
                Text(TK.markets[t]?.name ?? t).sType(SType(size: 15, weight: 800, line: 20, tracking: 0), tabular: false).foregroundStyle(TK.ink)
                Text(TK.price(q.0, t)).sType(SType(size: 15, weight: 600, line: 20, tracking: 0)).foregroundStyle(TK.ink)
                Text(TK.unit(t) == .yield ? TK.change(q.0 - q.1, t) : TK.pct(mv)).sType(SType(size: 15, weight: 600, line: 20, tracking: 0)).foregroundStyle(mv < 0 ? S.red : S.green)
            }
            .lineLimit(1)
            .padding(.leading, 6).padding(.trailing, 16).frame(height: 44).glassEffect(.regular, in: .capsule)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(live && wire == nil ? name
                : BSay.join([name, TK.price(q.0, t), "\(mv < 0 ? "down" : "up") \(TK.unit(t) == .yield ? TK.change(q.0 - q.1, t) : TK.pct(mv)) today"]))
            .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 16)
    }

    /// Ranges: six equal 44 pt targets, 2 apart, padding 8 12 0; the chip 32 tall, 10 a side, 14/14, the one picked
    /// 700 on ink, the rest 600 muted.
    private var ranges: some View {
        HStack(spacing: 2) {
            ForEach(["1W", "1M", "3M", "YTD", "1Y", "All"], id: \.self) { r in
                // The chips' colour fades (S.fade); the line crossfades in TickerLine.
                Button { si = nil; withAnimation(S.moving(S.fade, reduce)) { range = r } } label: {
                    Text(r).sType(SType(size: 14, weight: r == range ? 700 : 600, line: 14, tracking: 0), tabular: false)
                        .foregroundStyle(r == range ? TK.onink : TK.mu)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 10).frame(height: 32).background(Capsule().fill(r == range ? TK.ink : .clear))
                        .frame(maxWidth: .infinity).frame(height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                .accessibilityLabel(Self.rangeWords[r] ?? r)
                .accessibilityAddTraits(r == range ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12).padding(.top, 8)
        .sensoryFeedback(.selection, trigger: range)
    }

    /// Layers: switches, 48 tall, 8 apart, padding 8 16; a 14 x 3 swatch 8 before the words (15/15 600). On: ink with
    /// the words in the page colour; off: glass. Each chip is its own width and they share what is left (flex 1 0
    /// auto); when they don't fit (a larger text size) the row scrolls instead of widening the page.
    private func layerRow(width: CGFloat) -> some View {
        let t15 = SType(size: 15, weight: 600, line: 15, tracking: 0)
        let size = scales ? t15.scaled(dts).size : 15
        let nat = chips.map { 16 + 14 + 8 + TK.width($0.rawValue, size, 600) + 16 }
        let free = width - 32 - CGFloat(max(0, chips.count - 1)) * 8 - nat.reduce(0, +)
        let extra = max(0, free) / CGFloat(max(1, chips.count))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(chips.enumerated()), id: \.element) { i, l in chip(l, width: nat[i] + extra) }
            }
            .padding(.horizontal, 16)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .scrollClipDisabled()
        .frame(height: 48)
        .padding(.top, 8)
        .sensoryFeedback(.selection, trigger: lay)
    }

    private func chip(_ l: Layer, width: CGFloat) -> some View {
        let isOn = on.contains(l)
        return Button {
            // Walls glide the line to leave room after today (520 ms ease out, the design's anim); the rest fade.
            si = nil
            withAnimation(S.moving(l == .walls ? .timingCurve(0.33, 1, 0.68, 1, duration: 0.52) : S.fade, reduce)) {
                lay = self.on.symmetricDifference([l])
            }
        } label: {
            HStack(spacing: 8) {
                Group {
                    switch l {
                    case .pos: RoundedRectangle(cornerRadius: 2).fill(isOn ? TK.onink : TK.ink)
                    case .tech: RoundedRectangle(cornerRadius: 2).fill(TK.tc)
                    case .walls: HStack(spacing: 0) { Rectangle().fill(TK.call); Rectangle().fill(TK.put) }.clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                }
                .frame(width: 14, height: 3)
                .accessibilityHidden(true)
                Text(l.rawValue).sType(SType(size: 15, weight: 600, line: 15, tracking: 0), tabular: false)
                    .foregroundStyle(isOn ? TK.onink : TK.ink).lineLimit(1).fixedSize()
            }
            .frame(width: width, height: 48)
            .background { if isOn { Capsule().fill(TK.ink) } }
            .glassEffect(isOn ? .identity : .regular, in: .capsule)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(l.rawValue) lines")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }

    // MARK: Layer lines

    /// Positions: a tag per leg the way the design writes it ("Sold call 40 ×50", "Hedge 40 ×14", "Put 37.5 ×30"),
    /// in ink on the left, sold solid and bought dotted. The server joins the legs on one strike ("Hedge 40 ×14 · Sold
    /// call 40 ×50, Nov 13 · Sold put 40 ×16, Nov 20"): one line for the strike (solid when a leg is sold) and a tag
    /// for each leg, sold first. The expiry stays on a tag only when two legs would otherwise read the same.
    private func positionMarks() -> [TKMark] {
        let src: [(k: Double, label: String, solid: Bool)] = live
            ? (wire?.positions ?? []).map { ($0.k, $0.label, $0.solid ?? false) } : samplePositions()
        var byK: [(k: Double, solid: Bool, legs: [String])] = []
        for p in src {
            let legs = p.label.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if let i = byK.firstIndex(where: { abs($0.k - p.k) < 1e-9 }) { byK[i].solid = byK[i].solid || p.solid; byK[i].legs += legs }
            else { byK.append((p.k, p.solid, legs)) }
        }
        var out: [TKMark] = [], seen = Set<String>()
        for s in byK {
            let short = s.legs.map(Self.shortLeg)
            let named = s.legs.indices.map { i in short.filter { $0 == short[i] }.count > 1 ? s.legs[i] : short[i] }
            let order = named.indices.sorted { a, b in
                let sa = named[a].hasPrefix("Sold"), sb = named[b].hasPrefix("Sold")
                return sa != sb ? sa : a < b
            }
            for (j, i) in order.enumerated() {
                var id = "p|\(s.k)|\(named[i])"
                while seen.contains(id) { id += "+" }
                seen.insert(id)
                out.append(TKMark(id: id, k: s.k, label: named[i], color: TK.ink, dash: s.solid ? [] : [1, 4], line: j == 0))
            }
        }
        return out
    }

    /// "Sold call 40 ×50, Nov 13" → "Sold call 40 ×50"; "Puts 37.5 ×30" → "Put 37.5 ×30" (the design's tags).
    static func shortLeg(_ s: String) -> String {
        var x = s
        if let r = x.range(of: #",\s*[A-Z][a-z]{2} \d{1,2}$"#, options: .regularExpression) { x.removeSubrange(r) }
        if x.hasPrefix("Puts ") { x = "Put " + x.dropFirst(5) }
        return x
    }

    /// Walls of the nearest weekly chain, on the right as the design writes them ("Ceiling 39", "Floor 38.5",
    /// "Flip 40.85"): the ceiling in call navy, the floor in put brown, the accelerator dashed (5 4) in the colour of
    /// its side, the flip dashed (2 4) muted. They run on through the room after today.
    private func wallMarks(price: Double) -> [TKMark] {
        guard live, let w = wire else { return [] }
        return w.walls.map { x in
            let kind = x.label.components(separatedBy: " · ").first?.trimmingCharacters(in: .whitespaces) ?? x.label
            let id = "w|\(kind)|\(x.k)"
            switch kind {
            case "Ceiling": return TKMark(id: id, k: x.k, label: "Ceiling " + TK.fk(x.k), color: TK.call, right: true, full: true)
            case "Floor": return TKMark(id: id, k: x.k, label: "Floor " + TK.fk(x.k), color: TK.put, right: true, full: true)
            case "Accelerator": return TKMark(id: id, k: x.k, label: "Accelerator " + TK.fk(x.k), color: x.k > price ? TK.call : TK.put,
                                              dash: [5, 4], right: true, full: true)
            case "Flip": return TKMark(id: id, k: x.k, label: "Flip " + String(format: "%.2f", x.k), color: TK.mu, width: 1.25,
                                       dash: [2, 4], right: true, full: true)
            default: return TKMark(id: id, k: x.k, label: kind + " " + TK.fk(x.k), color: TK.mu, width: 1.25, dash: [2, 4], right: true, full: true)
            }
        }
    }
    /// The chain the walls come from ("Nov 13"), from the server's tags.
    private var wallExp: String {
        wire?.walls.first.flatMap { $0.label.components(separatedBy: " · ").dropFirst().first?.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// Technicals' tags, teal on the right at each average's last value ("20-day", "50-day", "200-day"); the
    /// averages themselves are drawn over time in TickerLine (the design has no year high or low).
    private func techMarks(_ ma: [TKMA]) -> [TKMark] {
        ma.compactMap { m in
            guard let last = m.vals.last ?? nil else { return nil }
            return TKMark(id: "t|\(m.id)", k: last, label: "\(m.id)-day", color: TK.tc, right: true, line: false)
        }
    }

    /// The sample book's legs in this name (a -sample run): hedge calls and LEAPS dotted, sold legs solid, puts dotted.
    private func samplePositions() -> [(k: Double, label: String, solid: Bool)] {
        guard let b = SampleBook.book(acct)[t] else { return [] }
        var out: [(Double, String, Bool)] = []
        for x in b.bought where x.kind != .ins { out.append((x.k, "\(x.kind == .leaps ? "LEAPS" : "Hedge") \(TK.fk(x.k)) ×\(x.q)", false)) }
        for s in b.sold { out.append((s.k, "Sold \(s.put ? "put" : "call") \(TK.fk(s.k)) ×\(s.q)", true)) }
        for x in b.bought where x.kind == .ins { out.append((x.k, "Put \(TK.fk(x.k)) ×\(x.q)", false)) }
        return out
    }
}

// MARK: - The chart

/// A level across the plot, drawn in the middle of its frame.
/// A two-finger pinch that reports the fingers' spread across and down (SwiftUI's MagnifyGesture gives one scale for
/// both, so it can't tell a sideways pinch from an upright one). `began` gets the point between the fingers in the
/// view's own space; a moment with one finger up is skipped.
private struct TKPinch: UIGestureRecognizerRepresentable {
    var began: (CGPoint, CGSize) -> Void
    var changed: (CGSize) -> Void
    var ended: () -> Void
    /// Recognised alongside the scrub (the first finger is already scrubbing when the second lands).
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
    }
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let g = UIPinchGestureRecognizer()
        g.delegate = context.coordinator
        return g
    }
    func handleUIGestureRecognizerAction(_ g: UIPinchGestureRecognizer, context: Context) {
        switch g.state {
        case .began, .changed:
            guard g.numberOfTouches >= 2 else { return }
            let p0 = g.location(ofTouch: 0, in: nil), p1 = g.location(ofTouch: 1, in: nil)
            let d = CGSize(width: abs(p1.x - p0.x), height: abs(p1.y - p0.y))
            if g.state == .began { began(context.converter.localLocation, d) } else { changed(d) }
        default: ended()
        }
    }
}

private struct TKHLine: Shape {
    func path(in r: CGRect) -> Path {
        Path { $0.move(to: CGPoint(x: 0, y: r.midY)); $0.addLine(to: CGPoint(x: r.maxX, y: r.midY)) }
    }
}

/// A series on the price scale (the closes, or an average with gaps before its first full window). The scale and the
/// room after today animate: a zoom reset or Walls glides the line.
private struct TKSeriesLine: Shape {
    var vals: [Double?]
    var lo: Double
    var hi: Double
    var xw: CGFloat
    /// The closes on screen in index units: x0 at the left edge, x1 at xw (0 and n - 1 until the dates are dragged).
    var x0: Double
    var x1: Double
    var padTop: CGFloat
    var padBottom: CGFloat
    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<CGFloat, AnimatablePair<Double, Double>>> {
        get { AnimatablePair(AnimatablePair(lo, hi), AnimatablePair(xw, AnimatablePair(x0, x1))) }
        set {
            lo = newValue.first.first; hi = newValue.first.second
            xw = newValue.second.first; x0 = newValue.second.second.first; x1 = newValue.second.second.second
        }
    }
    func path(in r: CGRect) -> Path {
        var p = Path(), pen = false
        let n = vals.count, span = max(1e-9, hi - lo), dx = max(1e-9, x1 - x0)
        // Only the closes on screen and one either side: the rest are clipped anyway.
        let from = max(0, Int(floor(x0)) - 1), to = min(n - 1, Int(ceil(x1)) + 1)
        guard from <= to else { return p }
        for i in from...to {
            guard let v = vals[i] else { pen = false; continue }
            let pt = CGPoint(x: n > 1 ? CGFloat((Double(i) - x0) / dx) * xw : 0, y: padTop + CGFloat((hi - v) / span) * (r.height - padTop - padBottom))
            if pen { p.addLine(to: pt) } else { p.move(to: pt); pen = true }
        }
        return p
    }
}

/// RSI in its 58 pt strip: 100 at 3, 0 at 55 (the design's yR).
private struct TKRSILine: Shape {
    var vals: [Double]
    var xw: CGFloat
    var x0: Double
    var x1: Double
    var animatableData: AnimatablePair<CGFloat, AnimatablePair<Double, Double>> {
        get { AnimatablePair(xw, AnimatablePair(x0, x1)) }
        set { xw = newValue.first; x0 = newValue.second.first; x1 = newValue.second.second }
    }
    static func y(_ v: Double) -> CGFloat { 3 + CGFloat((100 - v) / 100 * 52) }
    func path(in r: CGRect) -> Path {
        var p = Path()
        let n = vals.count, dx = max(1e-9, x1 - x0)
        let from = max(0, Int(floor(x0)) - 1), to = min(n - 1, Int(ceil(x1)) + 1)
        guard from <= to else { return p }
        for i in from...to {
            let pt = CGPoint(x: n > 1 ? CGFloat((Double(i) - x0) / dx) * xw : 0, y: Self.y(vals[i]))
            i == from ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

private struct TickerLine: View {
    struct Scale: Equatable { var lo: Double; var hi: Double }
    /// A tag placed on the plot.
    struct Tag: Identifiable { let id: String; let text: String; let color: Color; var y: CGFloat; let right: Bool; let w: CGFloat }
    private struct Drag { let y0: CGFloat; let lo0: Double; let hi0: Double; let a: Double; var moved: Bool }
    /// The closes on screen, in index units (a at the left edge, b at today's place).
    struct Win: Equatable { var a: Double; var b: Double }
    /// A drag on the dates: where it started, the window then, the close under the finger and its place across.
    private struct TDrag { let x0: CGFloat; let a0: Double; let b0: Double; let at: Double; let fa: Double; var moved: Bool }

    let pts: [Double]
    let dates: [String]
    let range: String
    let marks: [TKMark]
    /// Levels the auto scale may stretch to (walls, the band and the averages near the price, whether shown or not),
    /// so switching a layer never rescales the chart. Positions off the scale pin to the edge instead.
    let ext: [Double]
    /// Walls on: the line stops at 86% and the room after today holds the chain ahead.
    let room: Bool
    let roomLabel: String
    let up: Bool
    let summary: String
    /// Technicals on: the 20, 50 and 200-day averages over the range, and RSI 14 in its strip under the chart.
    var ma: [TKMA] = []
    var rsi: [Double]? = nil
    /// Walls on: the move priced by Friday, shaded over the room after today.
    var band: Scale? = nil
    /// The close under the finger (the page's readout follows it).
    @Binding var si: Int?

    /// The zoomed scale; nil = auto. Reset by a double tap on the price column, Auto, or a new range.
    @State private var vr: Scale?
    @State private var drag: Drag?
    @State private var lastTap = Date.distantPast
    /// The spread-out window; nil = the whole range. Reset by a double tap on the dates, Auto, or a new range.
    @State private var win: Win?
    @State private var tdrag: TDrag?
    @State private var lastDateTap = Date.distantPast
    /// A pinch on the plot: the fingers' spread when it began, which scales it moves, and both scales then.
    private struct Pinch { let d0: CGSize; let mx: Bool; let my: Bool; let a0: Double; let b0: Double; let at: Double; let fa: Double; let full: Double; let lo0: Double; let hi0: Double; let pv: Double; let span: Double }
    @State private var pinch: Pinch?
    /// A touch that became a pinch never scrubs again; the next touch does.
    @State private var scrubOff = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// 14 clear over the plot, 12 under it (PT, PB).
    static let PT: CGFloat = 14, PB: CGFloat = 12

    /// The design's auto scale: the closes, stretched to the levels within 8% of the price beyond them, plus 5% of
    /// the span on each side.
    static func auto(_ pts: [Double], _ ext: [Double]) -> Scale {
        let px = pts.last ?? 0
        var lo0 = pts.min() ?? 0, hi0 = pts.max() ?? 1
        let wA = lo0 - px * 0.08, wB = hi0 + px * 0.08
        for v in ext where v >= wA && v <= wB { lo0 = min(lo0, v); hi0 = max(hi0, v) }
        let sp = hi0 - lo0 > 0 ? hi0 - lo0 : max(0.01, px * 0.02)
        return Scale(lo: lo0 - sp * 0.05, hi: hi0 + sp * 0.05)
    }

    /// The design's spr: sorted top to bottom inside [lo, hi], each at least `gap` under the one above, the last
    /// pushed back up if it runs past the bottom. Ties keep their order (sold legs first).
    static func spread(_ ys: [CGFloat], lo: CGFloat, hi: CGFloat, gap: CGFloat = 19) -> [CGFloat] {
        let order = ys.indices.sorted { ys[$0] != ys[$1] ? ys[$0] < ys[$1] : $0 < $1 }
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

    /// Every tag's place (the design's place() and spr): at its level when on the scale, pinned 6 inside the top or
    /// bottom with an arrow when not; each side spread 19 apart. Left tags start 12 in and right ones end 6 short of
    /// the price column: if a left and a right tag would meet across the plot, both sides spread as one column.
    static func layout(_ marks: [TKMark], lo: Double, hi: Double, Y: (Double) -> CGFloat, H: CGFloat, W: CGFloat) -> [Tag] {
        let base = marks.map { m -> Tag in
            let inn = m.k >= lo && m.k <= hi
            let text = (inn ? "" : m.k > hi ? "↑ " : "↓ ") + m.label
            return Tag(id: m.id, text: text, color: m.color, y: inn ? Y(m.k) : m.k > hi ? PT + 6 : H - PB - 6, right: m.right,
                       w: TK.width(text, 11, 700) + 12)
        }
        var tags = base
        let mn = PT + 7, mx = H - PB - 7
        func spreadSide(_ idx: [Int]) {
            let ys = spread(idx.map { base[$0].y }, lo: mn, hi: mx)
            for (j, i) in idx.enumerated() { tags[i].y = ys[j] }
        }
        let L = tags.indices.filter { !tags[$0].right }, R = tags.indices.filter { tags[$0].right }
        spreadSide(L); spreadSide(R)
        let meet = L.contains { i in R.contains { j in abs(tags[i].y - tags[j].y) < 19 && 12 + tags[i].w + 4 > W - 6 - tags[j].w } }
        if meet { spreadSide(Array(tags.indices)) }
        return tags
    }

    var body: some View {
        GeometryReader { g in
            let PT = Self.PT, PB = Self.PB
            let rsiH: CGFloat = rsi == nil ? 0 : 86                     // RSI: 10 under the chart, 76 tall
            let H = max(PT + PB + 20, g.size.height - 24 - rsiH)       // the plot; the dates 8 under, 16 tall
            // The closes on screen: the whole range, or the window the dates were dragged to. While spread out the
            // auto scale fits the closes on screen, so the stretch gets the height too.
            let N = pts.count, full = Double(max(1, N - 1))
            let w = win.flatMap { N > 1 && $0.a >= -1e-9 && $0.b <= full + 1e-9 && $0.b - $0.a < full - 1e-9 ? $0 : nil } ?? Win(a: 0, b: full)
            let zoomed = w.b - w.a < full - 1e-9
            let vis = zoomed ? Array(pts[max(0, Int(floor(w.a)))...min(N - 1, Int(ceil(w.b)))]) : pts
            let a = Self.auto(vis, ext), s = vr ?? a
            let lo = s.lo, hi = s.hi
            let Y = { (v: Double) -> CGFloat in PT + CGFloat((hi - v) / max(1e-9, hi - lo)) * (H - PT - PB) }
            let px = pts.last ?? lo
            let pyC = max(PT, min(H - PB, Y(px)))
            // The price grid: about five steps of 1, 2, 2.5, 5 or 10 times a power of ten; a number at the right
            // (12/14 500, 8 in) unless within 14 of the last-price pill.
            let raw = max(1e-9, (hi - lo) / 5), mag = pow(10, floor(log10(raw)))
            let stp = [1, 2, 2.5, 5, 10].map { $0 * mag }.first { $0 >= raw } ?? 10 * mag
            let dec = stp >= 1 ? (stp.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1) : (abs(stp * 10 - (stp * 10).rounded()) < 1e-9 ? 1 : 2)
            let grid = Array(stride(from: (lo / stp).rounded(.up) * stp, through: hi + 1e-9, by: stp)).filter { Y($0) >= 4 && Y($0) <= H - 4 }
            let axis = grid.filter { abs(Y($0) - pyC) > 14 }
            // Commas from 1,000 (an index reads 70,000, not 70000).
            let fmt = { (v: Double) in abs(v) >= 1000 ? TK.grouped(v, dec) : String(format: "%.\(dec)f", v) }
            let pill = px >= 1000 ? TK.grouped(px) : String(format: "%.2f", px)
            // ⚠ The price column is 56 as designed, wider when its widest number needs it: a number ends 8 in with
            // 4 clear of the plot, the pill ends 4 in. So no number is ever cut.
            let colW = max(56, (axis.map { TK.width(fmt($0), 12, 500) + 12 }.max() ?? 0), TK.width(pill, 12, 700) + 12 + 4)
            let W = max(1, g.size.width - colW)
            let XW = room ? W * 0.86 : W
            let Xr = { (i: Int) -> CGFloat in N > 1 ? CGFloat((Double(i) - w.a) / max(1e-9, w.b - w.a)) * XW : 0 }
            let tags = Self.layout(marks, lo: lo, hi: hi, Y: Y, H: H, W: W)
            let at = si.flatMap { $0 < N ? $0 : nil }
            ZStack(alignment: .topLeading) {
                plot(W: W, XW: XW, H: H, lo: lo, hi: hi, grid: grid, Y: Y, w: w)
                // The scrub: a finger on the plot reads the close under it (the readout above follows); lifting it
                // goes back to the range's move.
                Color.clear
                    .frame(width: W, height: H)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if v.translation == .zero { scrubOff = false }   // a new touch
                            guard N > 0, pinch == nil, !scrubOff else { return }
                            let f = Double(max(0, min(1, v.location.x / max(1, XW))))
                            let i = min(Int(floor(w.b + 1e-9)), max(Int(ceil(w.a - 1e-9)), Int((w.a + f * (w.b - w.a)).rounded())))
                            if i != si { var tx = Transaction(); tx.disablesAnimations = true; withTransaction(tx) { si = i } }
                        }
                        .onEnded { _ in var tx = Transaction(); tx.disablesAnimations = true; withTransaction(tx) { si = nil } })
                    // The pinch (Nik 12 Nov 2026): it follows the fingers, sideways the days, up and down the prices.
                    .gesture(pinchGesture(N: N, XW: XW, H: H, lo: lo, hi: hi, w: w, span: a.hi - a.lo))
                    .position(x: W / 2, y: H / 2)
                    .accessibilityHidden(true)
                // The last close: a 9 pt dot ringed 2 in the page colour, at today.
                if let last = pts.last {
                    Circle().fill(up ? S.green : S.red).frame(width: 9, height: 9)
                        .background(Circle().fill(TK.ring).padding(-2))
                        .position(x: Xr(N - 1), y: Y(last))
                        .opacity(last >= lo && last <= hi && Xr(N - 1) <= XW + 1 ? 1 : 0)
                        .accessibilityHidden(true)
                }
                // The tags: 11/14 700, padding 1 6, radius 7, on the chart chip.
                ForEach(tags) { tg in
                    Text(tg.text).font(.inter(11, 700, tabular: true)).foregroundStyle(tg.color)
                        .lineLimit(1)
                        .padding(.horizontal, 6).frame(height: 16)
                        .background(RoundedRectangle(cornerRadius: 7).fill(TK.chip))
                        .frame(width: max(0, W - 18), alignment: tg.right ? .trailing : .leading)
                        .position(x: 12 + max(0, W - 18) / 2, y: tg.y)
                        .transition(.opacity)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                // Under the finger: a 1 pt line down the plot (muted at 60%) and an 11 pt dot ringed 2 on the close.
                if let i = at {
                    Rectangle().fill(TK.mu).opacity(0.6).frame(width: 1, height: H).position(x: Xr(i), y: H / 2)
                        .allowsHitTesting(false).accessibilityHidden(true)
                    Circle().fill(up ? S.green : S.red).frame(width: 11, height: 11)
                        .background(Circle().fill(TK.ring).padding(-2))
                        .position(x: Xr(i), y: Y(pts[i]))
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                ForEach(axis, id: \.self) { v in
                    Text(fmt(v)).font(.inter(12, 500, tabular: true)).foregroundStyle(TK.mu).fixedSize()
                        .frame(width: colW - 8, alignment: .trailing)
                        .position(x: W + (colW - 8) / 2, y: Y(v))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                // The last price: 12/14 700 in the page colour on the line's colour, padding 3 6, radius 8, 4 in.
                Text(pill).font(.inter(12, 700, tabular: true)).foregroundStyle(TK.onink).fixedSize()
                    .frame(height: 14)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 8).fill(up ? S.green : S.red))
                    .frame(width: colW - 4, alignment: .trailing)
                    .position(x: W + (colW - 4) / 2, y: pyC)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if let r = rsi {
                    rsiPanel(r, at: at, full: g.size.width, W: W, XW: XW, colW: colW, Xr: Xr, w: w)
                        .position(x: g.size.width / 2, y: H + 10 + 38)
                        .transition(.opacity)
                }
                dateRow(XW: XW, W: W, top: H + rsiH, w: w, zoomed: zoomed, Xr: Xr)
                // The time scale: the dates under the chart are the handle, the price column's twin sideways. Right
                // spreads the chart out around the day under the finger, left squeezes it back to the whole range.
                Color.clear
                    .frame(width: W, height: 24)
                    .contentShape(Rectangle())
                    .gesture(stretch(w: w, XW: XW, N: N))
                    .accessibilityElement()
                    .accessibilityLabel("Time scale")
                    .accessibilityValue(zoomed ? "\(Int((w.b - w.a).rounded()) + 1) days on screen" : "Whole range")
                    .accessibilityHint("Swipe up to spread the chart out, down to squeeze it back")
                    .accessibilityAdjustableAction { d in
                        let minSpan = min(full, 5), span = min(full, max(minSpan, (w.b - w.a) * (d == .increment ? 0.8 : 1.25)))
                        let st = min(max(0, w.b - span), full - span)
                        win = span >= full - 1e-9 ? nil : Win(a: st, b: st + span)
                    }
                    .accessibilityAction(named: "Auto") { reset(price: false) }
                    .position(x: W / 2, y: H + rsiH + 12)
                // The price scale: the whole price column is the handle.
                Color.clear
                    .frame(width: colW, height: H)
                    .contentShape(Rectangle())
                    .gesture(zoom(lo: lo, hi: hi, span: a.hi - a.lo, H: H))
                    .accessibilityElement()
                    .accessibilityLabel("Price scale")
                    .accessibilityValue(vr == nil ? "Auto" : "Zoomed to \(Int(((a.hi - a.lo) / max(1e-9, hi - lo) * 100).rounded()))%")
                    .accessibilityHint("Swipe up to zoom in, down to zoom out")
                    .accessibilityAdjustableAction { d in
                        let c = (lo + hi) / 2, sp = min((a.hi - a.lo) * 4, max((a.hi - a.lo) / 6, (hi - lo) * (d == .increment ? 0.8 : 1.25)))
                        vr = Scale(lo: c - sp / 2, hi: c + sp / 2)
                    }
                    .accessibilityAction(named: "Auto") { reset(time: false) }
                    .position(x: W + colW / 2, y: H / 2)
                // Auto while zoomed either way: 12/12 700 on ink, 26 tall, 10 a side, in a 44 target 12 over the
                // chart's top. It puts both scales back.
                if vr != nil || zoomed {
                    Button { reset() } label: {
                        Text("Auto").sType(SType(size: 12, weight: 700, line: 12, tracking: 0), tabular: false).foregroundStyle(TK.onink)
                            .padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(TK.ink))
                            .padding(.horizontal, 4).frame(height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset the chart to auto")
                    .frame(width: g.size.width, alignment: .trailing)
                    .position(x: g.size.width / 2, y: -12 + 22)
                    .transition(.opacity)
                }
            }
        }
        .onChange(of: range) { _, _ in vr = nil; win = nil }
    }

    /// The grid, the band, the range's first close dotted, the layers' lines, the averages and the price, clipped to
    /// the plot. One spoken stop. The closes and averages stop at today's place (XW), so spread out over an earlier
    /// stretch the room after today stays empty.
    private func plot(W: CGFloat, XW: CGFloat, H: CGFloat, lo: Double, hi: Double, grid: [Double], Y: @escaping (Double) -> CGFloat, w: Win) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(grid, id: \.self) { v in
                Rectangle().fill(TK.line).frame(width: W, height: 1).position(x: W / 2, y: Y(v))
            }
            // The move priced by Friday, shaded over the room after today (the design's band).
            if let b = band, XW < W {
                let y1 = max(Self.PT, Y(b.hi)), y2 = min(H - Self.PB, Y(b.lo))
                Rectangle().fill(TK.band).frame(width: W - XW, height: max(0, y2 - y1)).position(x: (XW + W) / 2, y: (y1 + y2) / 2)
                    .transition(.opacity)
            }
            if let first = pts.first {
                TKHLine().stroke(TK.mu.opacity(0.8), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [1, 4]))
                    .frame(width: XW, height: 2).position(x: XW / 2, y: Y(first))
            }
            // Sold solid, bought dotted (1 4), walls their own; 1.5 pt (the flip 1.25). Walls run to the column.
            ForEach(marks.filter { $0.line && $0.k >= lo && $0.k <= hi }) { m in
                let len = m.full ? W : XW
                TKHLine().stroke(m.color, style: StrokeStyle(lineWidth: m.width, lineCap: .round, dash: m.dash))
                    .frame(width: len, height: 2).position(x: len / 2, y: Y(m.k))
                    .transition(.opacity)
            }
            // Technicals: the 20-day solid, the 50-day dashed (6 4), the 200-day dotted (1 4), teal 1.5.
            ForEach(ma) { m in
                TKSeriesLine(vals: m.vals, lo: lo, hi: hi, xw: XW, x0: w.a, x1: w.b, padTop: Self.PT, padBottom: Self.PB)
                    .stroke(TK.tc, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: m.dash))
                    .frame(width: W, height: H)
                    .frame(width: XW + 1.5, height: H, alignment: .topLeading).clipped()
                    .id("\(range)|\(m.id)")
                    .transition(.opacity)
            }
            ZStack {
                TKSeriesLine(vals: pts.map { Optional($0) }, lo: lo, hi: hi, xw: XW, x0: w.a, x1: w.b, padTop: Self.PT, padBottom: Self.PB)
                    .stroke(up ? S.green : S.red, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .id(range)
                    .transition(.opacity)
            }
            .frame(width: W, height: H)
            .frame(width: XW + 1.5, height: H, alignment: .topLeading).clipped()
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    /// RSI 14 (the design's strip, 76 tall): "RSI (14)" 12/15 600 muted 16 in with its value 700 ink and Overbought or
    /// Oversold 700 orange, 6 apart; under it the 58 pt strip with 70 to 30 shaded teal to today and the line teal 1.5;
    /// 70 and 30 at the right (12/14 500 muted). Under the finger: its value then, and the same line.
    private func rsiPanel(_ r: [Double], at: Int?, full: CGFloat, W: CGFloat, XW: CGFloat, colW: CGFloat, Xr: @escaping (Int) -> CGFloat, w: Win) -> some View {
        let i = at.flatMap { $0 < r.count ? $0 : nil } ?? (r.count - 1)
        let rv = r.indices.contains(i) ? r[i] : 50
        let y70 = TKRSILine.y(70), y30 = TKRSILine.y(30)
        return ZStack(alignment: .topLeading) {
            HStack(spacing: 6) {
                Text("RSI (14)").font(.inter(12, 600)).foregroundStyle(TK.mu)
                Text(String(format: "%.2f", rv)).font(.inter(12, 700, tabular: true)).foregroundStyle(TK.ink)
                if rv > 70 || rv < 30 { Text(rv > 70 ? "Overbought" : "Oversold").font(.inter(12, 700)).foregroundStyle(TK.or) }
            }
            .lineLimit(1).fixedSize()
            .frame(height: 15)
            .offset(x: 16)
            Rectangle().fill(TK.tcTint).frame(width: XW, height: y30 - y70).offset(y: 18 + y70)
            TKRSILine(vals: r, xw: XW, x0: w.a, x1: w.b).stroke(TK.tc, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                .frame(width: XW + 1.5, height: 58).clipped().offset(y: 18)
                .id("rsi|\(range)").transition(.opacity)
            if let s = at {
                Rectangle().fill(TK.mu).opacity(0.6).frame(width: 1, height: 58).offset(x: Xr(s) - 0.5, y: 18)
            }
            ForEach([(70.0, y70), (30.0, y30)], id: \.0) { v, y in
                Text(String(format: "%.0f", v)).font(.inter(12, 500, tabular: true)).foregroundStyle(TK.mu).fixedSize()
                    .frame(width: colW - 8, height: 14, alignment: .trailing)
                    .offset(x: W, y: 18 + y - 7)
            }
        }
        .frame(width: full, height: 76, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("RSI 14, \(String(format: "%.2f", rv))\(rv > 70 ? ", overbought" : rv < 30 ? ", oversold" : "")")
    }

    /// The dates 8 under the chart (12/16 500 muted) at 8, 36, 64 and 92% of the closes; on 1W each weekday in the
    /// middle of its day, as the design's week. The chain's date over the room after today while Walls is on. A date
    /// never runs off the chart's edge.
    private func dateRow(XW: CGFloat, W: CGFloat, top: CGFloat, w: Win, zoomed: Bool, Xr: @escaping (Int) -> CGFloat) -> some View {
        let N = pts.count
        // Spread out, the dates read for the days on screen: "Aug 3" up to about three months, "Aug" (or "Aug ’25"
        // on All) up to about a year.
        let sp = w.b - w.a
        let fmt = !zoomed ? range : sp <= 70 ? "3M" : sp <= 300 ? (range == "All" ? "All" : "1Y") : range
        let at: [(x: CGFloat, i: Int)] = range == "1W" && N > 1 && !zoomed
            ? (1..<N).map { s in ((CGFloat(s) - 0.5) / CGFloat(N - 1) * XW, s) }
            : [0.08, 0.36, 0.64, 0.92].map { f in
                let i = Int((w.a + f * sp).rounded())
                return (Xr(i), i)
            }
        return ZStack(alignment: .topLeading) {
            ForEach(Array(at.enumerated()), id: \.offset) { _, p in
                if dates.indices.contains(p.i) {
                    let s = TickerChartPage.dateLabel(dates[p.i], fmt), half = TK.width(s, 12, 500) / 2
                    Text(s).font(.inter(12, 500)).foregroundStyle(TK.mu).fixedSize()
                        .position(x: min(max(p.x, half), W - half), y: top + 16)
                }
            }
            if room && !roomLabel.isEmpty {
                Text(roomLabel).font(.inter(12, 500)).foregroundStyle(TK.mu).fixedSize()
                    .position(x: (XW + W) / 2, y: top + 16)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The design's drag on the price scale: the price under the finger stays put, the span scales by e^(dy/160)
    /// (up zooms in, down out) between a sixth and four times the auto span. A tap that doesn't move, twice within
    /// 320 ms, goes back to auto.
    private func zoom(lo: Double, hi: Double, span: Double, H: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if drag == nil {
                    let a = hi - Double((v.startLocation.y - Self.PT) / max(1, H - Self.PT - Self.PB)) * (hi - lo)
                    drag = Drag(y0: v.startLocation.y, lo0: lo, hi0: hi, a: min(hi, max(lo, a)), moved: false)
                }
                guard var z = drag else { return }
                let dy = v.location.y - z.y0
                if !z.moved && abs(dy) > 3 { z.moved = true; drag = z }
                guard z.moved else { return }
                let s0 = z.hi0 - z.lo0, f = min(span * 4, max(span / 6, s0 * exp(Double(dy) / 160))) / s0
                var tx = Transaction(); tx.disablesAnimations = true
                withTransaction(tx) { vr = Scale(lo: z.a - (z.a - z.lo0) * f, hi: z.a + (z.hi0 - z.a) * f); si = nil }
            }
            .onEnded { _ in
                let moved = drag?.moved ?? false
                drag = nil
                guard !moved else { return }
                let now = Date()
                if now.timeIntervalSince(lastTap) < 0.32 { lastTap = .distantPast; reset(time: false) } else { lastTap = now }
            }
    }

    /// The drag on the dates (Nik 10 Nov: "one is up and down to get the prices closer and one is left and right to
    /// spread out the chart"): the day under the finger stays put and the days on screen scale by e^(-dx/120), so
    /// right spreads the chart out and left squeezes it back, from one week (6 closes) to the whole range. A tap that
    /// doesn't move, twice within 320 ms, goes back to the whole range.
    private func stretch(w: Win, XW: CGFloat, N: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let full = Double(max(1, N - 1)), minSpan = min(full, 5)
                guard full > minSpan else { return }
                if tdrag == nil {
                    let fa = Double(max(0, min(1, v.startLocation.x / max(1, XW))))
                    tdrag = TDrag(x0: v.startLocation.x, a0: w.a, b0: w.b, at: w.a + fa * (w.b - w.a), fa: fa, moved: false)
                }
                guard var z = tdrag else { return }
                let dx = v.location.x - z.x0
                if !z.moved && abs(dx) > 3 { z.moved = true; tdrag = z }
                guard z.moved else { return }
                let span = min(full, max(minSpan, (z.b0 - z.a0) * exp(-Double(dx) / 120)))
                let st = min(max(0, z.at - z.fa * span), full - span)
                var tx = Transaction(); tx.disablesAnimations = true
                withTransaction(tx) { win = span >= full - 1e-9 ? nil : Win(a: st, b: st + span); si = nil }
            }
            .onEnded { _ in
                let moved = tdrag?.moved ?? false
                tdrag = nil
                guard !moved else { return }
                let now = Date()
                if now.timeIntervalSince(lastDateTap) < 0.32 { lastDateTap = .distantPast; reset(price: false) } else { lastDateTap = now }
            }
    }

    /// The pinch at the fingers' spread now: the days scale by how much wider (or narrower) the fingers are apart
    /// sideways than when it began, the prices by how much further apart up and down; the day and the price between
    /// the fingers stay put. The same limits as the two drags: one week to the whole range, a sixth to four times the
    /// auto price span.
    /// The pinch on the plot: at its start, the day and price between the fingers and which scales it moves (within
    /// 25° of flat the days only, within 25° of upright the prices only, between them both).
    private func pinchGesture(N: Int, XW: CGFloat, H: CGFloat, lo: Double, hi: Double, w: Win, span: Double) -> TKPinch {
        TKPinch(
            began: { mid, d in
                let full = Double(max(1, N - 1))
                let deg = atan2(Double(d.height), Double(d.width)) * 180 / .pi
                let fa = Double(max(0, min(1, mid.x / max(1, XW))))
                let pv = hi - Double((mid.y - Self.PT) / max(1, H - Self.PT - Self.PB)) * (hi - lo)
                pinch = Pinch(d0: d, mx: deg < 65 && d.width > 20 && full > 5, my: deg > 25 && d.height > 20,
                              a0: w.a, b0: w.b, at: w.a + fa * (w.b - w.a), fa: fa, full: full,
                              lo0: lo, hi0: hi, pv: min(hi, max(lo, pv)), span: span)
                scrubOff = true
                var tx = Transaction(); tx.disablesAnimations = true
                withTransaction(tx) { si = nil }
            },
            changed: { d in pinchTo(d) },
            ended: { pinch = nil })
    }

    private func pinchTo(_ d: CGSize) {
        guard let p = pinch else { return }
        var tx = Transaction(); tx.disablesAnimations = true
        withTransaction(tx) {
            if p.mx {
                let span = min(p.full, max(min(p.full, 5), (p.b0 - p.a0) * Double(p.d0.width / max(1, d.width))))
                let st = min(max(0, p.at - p.fa * span), p.full - span)
                win = span >= p.full - 1e-9 ? nil : Win(a: st, b: st + span)
            }
            if p.my {
                let s0 = p.hi0 - p.lo0, f = min(p.span * 4, max(p.span / 6, s0 * Double(p.d0.height / max(1, d.height)))) / s0
                vr = Scale(lo: p.pv - (p.pv - p.lo0) * f, hi: p.pv + (p.hi0 - p.pv) * f)
            }
            si = nil
        }
    }

    /// Back to auto: a 520 ms ease-out glide (the design's anim), none under Reduce Motion. Auto puts both scales
    /// back; a double tap on the price column or on the dates puts back its own.
    private func reset(price: Bool = true, time: Bool = true) {
        guard (price && vr != nil) || (time && win != nil) else { return }
        withAnimation(S.moving(.timingCurve(0.33, 1, 0.68, 1, duration: 0.52), reduce)) {
            if price { vr = nil }
            if time { win = nil }
        }
    }
}
