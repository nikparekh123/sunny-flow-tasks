//
//  AccountChart.swift
//  Sunny
//
//  Blocks 02 + 02b · SunnyAccountChart (design file SunnyHomeChart.dc.html).
//  The account value, the change for the range, a daily line under it with
//  ranges 1W · 1M · 3M · YTD · 1Y · All (opens on 1M), scrub to read any
//  close, and the stats that follow the range and the finger. The filter
//  icon compares Sold, Bought, Shares and Dividends as P&L lines from $0; a
//  legend name singles one out, and Sold and Bought split into Calls · Puts.
//  × on the title pill steps back one level. The eye blurs every number.
//
//  Geometry as the design file draws it: the line box is 148 tall, the line
//  sits between 26 from the top and 8 from the bottom with 4% headroom, 240
//  samples per line so any two shapes morph into each other (0.56 s).
//

import SwiftUI
import UIKit

// MARK: - Ranges and groups

enum ChartRange: String, CaseIterable, Identifiable {
    case w1 = "1W", m1 = "1M", m3 = "3M", ytd = "YTD", y1 = "1Y", all = "All"
    var id: String { rawValue }
    /// The change line's words (design file S.label).
    var words: String {
        switch self {
        case .w1: "past week"; case .m1: "past month"; case .m3: "past 3 months"
        case .ytd: "this year"; case .y1: "past year"; case .all: "all time"
        }
    }
}

enum ChartGroup: String, CaseIterable, Identifiable {
    case sold = "Sold", bought = "Bought", shares = "Shares", dividends = "Dividends"
    var id: String { rawValue }
    var color: Color {
        switch self { case .sold: S.lineSold; case .bought: S.lineBought; case .shares: S.lineShares; case .dividends: S.lineDividends }
    }
    var splits: Bool { self == .sold || self == .bought }
}

enum ChartHalf: String, CaseIterable, Identifiable {
    case both = "Both", calls = "Calls", puts = "Puts"
    var id: String { rawValue }
}

// MARK: - The arithmetic

/// Every number the chart shows comes from here, so the view only lays out.
struct ChartModel {
    let c: Chart
    let today: String
    /// The live account value: today's point while the session runs.
    let live: Double?

    var n: Int { c.days.count }

    /// Index of the first point in a range. 1W = the last 5 closes plus the
    /// one before.
    func start(_ r: ChartRange) -> Int {
        guard n > 1 else { return 0 }
        let from: String
        switch r {
        case .w1: return max(0, n - 6)
        case .all: return 0
        case .m1: from = Self.shift(today, months: -1)
        case .m3: from = Self.shift(today, months: -3)
        case .y1: from = Self.shift(today, months: -12)
        case .ytd: from = String(today.prefix(4)) + "-01-01"
        }
        // The last close on or before the range start, so 1M opens on the
        // close a month ago.
        return c.days.lastIndex { $0 <= from } ?? 0
    }

    /// Ranges longer than the history are hidden, except All. YTD shows from
    /// Sep 1 until Jan 1, 2027.
    func available(_ r: ChartRange) -> Bool {
        if n < 2 { return r == .all }
        switch r {
        case .all, .w1, .ytd: return true
        case .m1: return c.from <= Self.shift(today, months: -1)
        case .m3: return c.from <= Self.shift(today, months: -3)
        case .y1: return c.from <= Self.shift(today, months: -12)
        }
    }

    // Series

    func nav(_ i: Int) -> Double {
        if i == n - 1, c.liveLast, let live { return live }
        return c.nav[i] ?? 0
    }
    func keys(_ g: ChartGroup, _ h: ChartHalf) -> [String] {
        switch g {
        case .sold: h == .calls ? ["cs"] : h == .puts ? ["ps"] : ["cs", "ps"]
        case .bought: h == .calls ? ["cb"] : h == .puts ? ["pb"] : ["cb", "pb"]
        case .shares: ["sh"]
        case .dividends: []
        }
    }
    private func sum(_ ks: [String], _ i: Int, _ f: (Chart.Group) -> [Double]) -> Double {
        ks.reduce(0) { acc, k in acc + (c.groups[k].map { f($0)[safe: i] ?? 0 } ?? 0) }
    }
    /// A group's running P&L, as a level (subtract the range start for "from $0").
    func line(_ g: ChartGroup, _ h: ChartHalf, _ i: Int) -> Double {
        g == .dividends ? (c.dividendsCum[i] ?? 0) : sum(keys(g, h), i) { $0.line }
    }
    func realized(_ g: ChartGroup, _ h: ChartHalf, _ i: Int) -> Double { sum(keys(g, h), i) { $0.real } }
    func unreal(_ g: ChartGroup, _ h: ChartHalf, _ i: Int) -> Double { sum(keys(g, h), i) { $0.unreal } }
    func tv(_ g: ChartGroup, _ h: ChartHalf, _ i: Int) -> Double { sum(keys(g, h), i) { $0.tv } }

    /// What a group ties up (Nik, 12 Oct): money in long options for Sold and
    /// Bought, the shares' value for Shares and Dividends, both for the total.
    func capital(_ g: ChartGroup?, _ i: Int) -> Double {
        let longs = c.capitalLong[i] ?? 0, shares = c.sharesValue[i] ?? 0
        switch g {
        case .none: return longs + shares
        case .sold?, .bought?: return longs
        case .shares?, .dividends?: return shares
        }
    }

    /// A group with nothing in the range drops out of compare and the legend.
    func empty(_ g: ChartGroup, s: Int, e: Int) -> Bool {
        let base = line(g, .both, s)
        return (s...e).allSatisfy { abs(line(g, .both, $0) - base) < 0.5 }
    }

    /// Closed positions in (from, to]: kept full credit (sold) or closed in
    /// profit (bought), out of all closed.
    func closed(_ g: ChartGroup, _ h: ChartHalf, from: String, to: String) -> (hit: Int, of: Int) {
        let ks = keys(g, h)
        let rows = c.closed.filter { r in
            guard r.count >= 3, let d = r[0].string, let k = r[1].string else { return false }
            return d > from && d <= to && ks.contains(k)
        }
        return (rows.filter { ($0[2].number ?? 0) > 0 }.count, rows.count)
    }

    /// Names that paid a dividend in (from, to].
    func payers(from: String, to: String) -> Int {
        Set((c.dividends.payers ?? []).filter { $0.count == 2 && $0[0] > from && $0[0] <= to }.map { $0[1] }).count
    }

    /// The scrub label: "Mon Oct 5" on 1W, "Oct 5, 2026" on 1Y and All.
    func label(_ i: Int, _ r: ChartRange) -> String {
        let iso = c.days[i]
        switch r {
        case .w1:
            let wd = MarketClock.addDays(iso, 0).weekday
            return "\(MarketClock.dayName[wd]) \(F.day(iso))"
        case .y1, .all: return "\(F.day(iso)), \(iso.prefix(4))"
        default: return F.day(iso)
        }
    }

    static func shift(_ iso: String, months: Int) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = MarketClock.ny
        let f = DateFormatter(); f.calendar = cal; f.timeZone = MarketClock.ny; f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso), let s = cal.date(byAdding: .month, value: months, to: d) else { return iso }
        return f.string(from: s)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - View

struct AccountChart: View {
    let home: HomePayload
    /// Home opened or was pulled: Time value shows its read for a few seconds.
    var readTick = 0
    @State private var readOn = false
    @AppStorage(SunnyPrivacy.key) private var hidden = false   // also set by the Hide / Show Sunny numbers actions
    @State private var range: ChartRange = DebugPreset.string("chart.range").flatMap(ChartRange.init(rawValue:)) ?? .m1
    @State private var compare = DebugPreset.bool("chart.compare")
    @State private var single: ChartGroup? = DebugPreset.string("chart.single").flatMap(ChartGroup.init(rawValue:))
    @State private var half: ChartHalf = DebugPreset.string("chart.half").flatMap(ChartHalf.init(rawValue:)) ?? .both
    /// The finger, 0...1 across the line (continuous; numbers snap to a day).
    @State private var finger: CGFloat? = DebugPreset.double("chart.scrub").map { CGFloat($0) }
    @State private var drawn: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var model: ChartModel? {
        home.chart.map { ChartModel(c: $0, today: home.today, live: home.account.value) }
    }
    /// One close or none: the first-day state.
    private var fresh: Bool { (model?.n ?? 0) < 2 }
    private var pnl: Bool { compare && !fresh }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                headline.padding(.horizontal, S.margin)
                plotBox
            }
            rangesRow
            panel
        }
        .onAppear {
            if let m = model, !m.available(range) { range = .all }
            if DebugPreset.gallery != nil || !DebugPreset.values.isEmpty { hidden = DebugPreset.bool("eye") }
        }
        .task(id: readTick) {
            guard readTick > 0, Self.timeValueRead(home) != nil else { return }
            try? await Task.sleep(for: .milliseconds(1200))    // after the loading screen has gone
            guard !Task.isCancelled else { return }
            withAnimation(reduce ? nil : S.standard(0.4)) { readOn = true }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(reduce ? nil : S.standard(0.4)) { readOn = false }
        }
    }

    /// The one-word read that stands in for "Time value" for a few seconds
    /// (Nik, 16 Oct 2026). From the sold legs alone: what they are in the money
    /// at today's prices against the time value still in them. Under 10% is
    /// calm and shows nothing (Nik dropped "Decaying": the label staying put
    /// already says calm); otherwise the side with more in the money says which
    /// way prices are pushing: calls Stocks up, puts Stocks down.
    static func timeValueRead(_ home: HomePayload) -> (word: String, color: Color)? {
        let tv = home.account.timeValueSold ?? 0
        guard tv > 0 else { return nil }
        var calls = 0.0, puts = 0.0
        for l in home.legs where l.side == "sold" && l.expiry >= home.today {
            guard let s = home.portfolio.first(where: { $0.ticker == l.ticker })?.spot ?? l.underlying else { continue }
            let x = (l.type == "call" ? max(0, s - l.strike) : max(0, l.strike - s)) * Double(l.n) * 100
            if l.type == "call" { calls += x } else { puts += x }
        }
        if calls + puts < 0.1 * tv { return nil }
        return calls >= puts ? ("Stocks up", S.orangeDeep) : ("Stocks down", S.red)
    }

    // MARK: Where we are

    private var bounds: (s: Int, e: Int) {
        guard let m = model, m.n > 0 else { return (0, 0) }
        return fresh ? (0, m.n - 1) : (m.start(range), m.n - 1)
    }
    /// The day under the finger, else the range's last close.
    private var at: Int {
        let (s, e) = bounds
        guard let f = finger, e > s else { return e }
        return s + Int((f * CGFloat(e - s)).rounded())
    }
    private var scrubbing: Bool { finger != nil }
    private func toMorph(_ change: () -> Void) {
        withAnimation(reduce ? .easeOut(duration: 0.2) : S.morph) { change() }
    }

    // MARK: Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                let v = bigValue
                SNumber(value: v, format: { F.money($0) })
                    .sType(.largeNumber)
                    .foregroundStyle(pnl ? S.lossInk(v) : S.ink)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .blur(radius: hidden ? 9 : 0)
                    .accessibilityLabel(hidden ? "Hidden" : F.money(v))
                eyeButton.padding(.leading, -4)
                Spacer(minLength: 8)
                if pnl { titlePill.transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing))) }
            }
            .frame(minHeight: 34)
            changeLine
        }
    }

    private var bigValue: Double {
        guard let m = model, m.n > 0 else { return home.account.value ?? 0 }
        let (s, _) = bounds, i = at
        if fresh { return m.nav(m.n - 1) }
        if let g = single { return m.line(g, half, i) - m.line(g, half, s) }
        if compare { return shownGroups.reduce(0) { $0 + m.line($1, .both, i) - m.line($1, .both, s) } }
        return m.nav(i)
    }

    private static let changeValue = SType(size: 15, weight: 700, line: 20, tracking: 0)
    private static let changeWords = SType(size: 15, weight: 500, line: 20, tracking: 0)

    @ViewBuilder private var changeLine: some View {
        HStack(spacing: 8) {
            if let m = model, !fresh {
                let (s, _) = bounds, i = at
                if pnl {
                    let cap = m.capital(single, i)
                    let roc = cap > 0 ? bigValue / cap * 100 : 0
                    Text(F.pct(roc, places: 1))
                        .sType(Self.changeValue)
                        .foregroundStyle(roc < 0 ? S.red : S.green)
                        .contentTransition(.numericText(value: roc))
                        .blur(radius: hidden ? 9 : 0)
                    Text(scrubbing ? "on capital" : "on capital · \(range.words)")
                        .sType(Self.changeWords, tabular: false).foregroundStyle(S.muted)
                } else {
                    let first = m.nav(s), d = bigValue - first
                    let p = first != 0 ? d / abs(first) * 100 : 0
                    Text("\(F.money(d)) · \(F.pct(p, places: 1))")
                        .sType(Self.changeValue)
                        .foregroundStyle(S.signed(d.rounded()))
                        .contentTransition(.numericText(value: d))
                        .blur(radius: hidden ? 9 : 0)
                    if !scrubbing {
                        Text(range.words).sType(Self.changeWords, tabular: false).foregroundStyle(S.muted)
                    }
                }
            } else {
                Text("$0 · 0.0%").sType(Self.changeValue).foregroundStyle(S.ink)
                    .blur(radius: hidden ? 9 : 0)
                Text("first day of the book").sType(Self.changeWords, tabular: false).foregroundStyle(S.muted)
            }
        }
        .lineLimit(1)
        .frame(minHeight: 20)
        .animation(.smooth(duration: S.roll), value: at)
    }

    private var eyeButton: some View {
        Button { withAnimation(.easeOut(duration: 0.35)) { hidden.toggle() } } label: {
            Image(systemName: hidden ? "eye.slash" : "eye")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(S.muted)
                .opacity(hidden ? 1 : 0.55)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(SPressStyle())
        .accessibilityLabel(hidden ? "Show numbers" : "Hide numbers")
    }

    /// Total P&L × · ● Sold P&L × · ● Calls sold P&L ×
    private var titlePill: some View {
        Button {
            toMorph {
                finger = nil
                if single != nil { single = nil; half = .both } else { compare = false }
            }
        } label: {
            HStack(spacing: 6) {
                if let g = single { Circle().fill(g.color).frame(width: 8, height: 8) }
                Text(pillTitle).sType(.label, tabular: false).foregroundStyle(S.ink).lineLimit(1)
                SCross().stroke(S.muted, style: StrokeStyle(lineWidth: 1.5)).frame(width: 20, height: 20)
            }
            .padding(.leading, 10).padding(.trailing, 4)
            .frame(height: 28)
            .background(Capsule().fill(S.surface))
            .contentShape(Capsule().inset(by: -8))
        }
        .buttonStyle(SPressStyle())
        .accessibilityLabel(single == nil ? "Total P&L, back to account value" : "\(pillTitle), back to all lines")
    }
    private var pillTitle: String {
        guard let g = single else { return "Total P&L" }
        if g.splits, half != .both { return "\(half.rawValue) \(g.rawValue.lowercased()) P&L" }
        return "\(g.rawValue) P&L"
    }

    // MARK: The line box

    private static let samples = 240
    private static let boxH: CGFloat = 148
    private static let top: CGFloat = 26
    private static var plotH: CGFloat { boxH - top - 8 }

    /// Groups on the chart for this range (an empty one drops out).
    private var shownGroups: [ChartGroup] {
        guard let m = model, !fresh else { return [] }
        let (s, e) = bounds
        return ChartGroup.allCases.filter { !m.empty($0, s: s, e: e) }
    }

    private struct Lines {
        var main: [CGFloat]
        var groups: [[CGFloat]]       // Sold, Bought, Shares, Dividends
        var base: CGFloat
        var tone: Color
        var dot: [CGFloat]?
    }

    private func lines(_ m: ChartModel) -> Lines {
        let (s, e) = bounds
        let h = Self.plotH, top = Self.top
        let resample = { (vals: [Double], lo: Double, hi: Double) -> [CGFloat] in
            let n = vals.count, M = Self.samples
            return (0..<M).map { k in
                let pos = Double(k) / Double(M - 1) * Double(max(n - 1, 0))
                let i0 = min(max(n - 2, 0), Int(pos.rounded(.down))), t = pos - Double(i0)
                let v = n > 1 ? vals[i0] + (vals[i0 + 1] - vals[i0]) * t : (vals.first ?? 0)
                return top + CGFloat(1 - (v - lo) / (hi - lo)) * h
            }
        }
        let pad = { (lo: Double, hi: Double) -> (Double, Double) in
            let p = (hi - lo) * 0.04; return p > 0 ? (lo - p, hi + p) : (lo - 1, hi + 1)
        }
        // Each group from $0 at the range start (the singled-out one by half).
        let series: [[Double]] = ChartGroup.allCases.map { g in
            let hh = single == g ? half : .both
            let b = m.line(g, hh, s)
            return (s...e).map { m.line(g, hh, $0) - b }
        }
        if pnl {
            let shown = shownGroups
            let all: [Double] = zip(ChartGroup.allCases, series).filter { shown.contains($0.0) }.flatMap { $0.1 } + [0]
            let (lo, hi) = pad(all.min() ?? 0, all.max() ?? 0)
            let ys = series.map { resample($0, lo, hi) }
            let k = single.flatMap { ChartGroup.allCases.firstIndex(of: $0) }
            let tone: Color = k.map { (series[$0].last ?? 0) - (series[$0].first ?? 0) < 0 ? S.red : S.green } ?? S.green
            return Lines(main: ys[k ?? 0], groups: ys,
                         base: top + CGFloat(1 - (0 - lo) / (hi - lo)) * h, tone: tone,
                         dot: k.map { ys[$0] })
        }
        let navs = (s...e).map { m.nav($0) }
        let (lo, hi) = pad(navs.min() ?? 0, navs.max() ?? 0)
        let main = resample(navs, lo, hi)
        let tone = (navs.last ?? 0) - (navs.first ?? 0) < 0 ? S.red : S.green
        return Lines(main: main, groups: Array(repeating: main, count: 4),
                     base: top + CGFloat(1 - ((navs.first ?? 0) - lo) / (hi - lo)) * h, tone: tone, dot: main)
    }

    private static let lineStyle = StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round)
    private static let dotted = StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0, 5])

    private var plotBox: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                if let m = model, !fresh {
                    let L = lines(m)
                    let shown = shownGroups
                    // Dotted zero line (compare only).
                    SHLine(y: L.base).stroke(S.chartBase, style: Self.dotted).opacity(pnl ? 1 : 0)
                    // The four group lines.
                    ForEach(Array(ChartGroup.allCases.enumerated()), id: \.offset) { k, g in
                        SLine(ys: L.groups[k], from: 0, to: 1)
                            .stroke(single == g ? L.tone : g.color, style: Self.lineStyle)
                            .opacity(pnl && shown.contains(g) ? (single == nil || single == g ? 1 : 0.14) : 0)
                    }
                    // The account line: solid to the finger, 22% after it.
                    let cut = finger ?? 1
                    SLine(ys: L.main, from: cut, to: 1)
                        .stroke(L.tone, style: Self.lineStyle)
                        .opacity(pnl || finger == nil ? 0 : 0.22)
                    SLine(ys: L.main, from: 0, to: cut)
                        .stroke(L.tone, style: Self.lineStyle)
                        .opacity(pnl ? 0 : 1)
                    scrubMarks(m, L: L, w: w)
                } else {
                    // First day: a dotted baseline and the note.
                    SHLine(y: Self.top + Self.plotH * 0.62).stroke(S.chartBase, style: Self.dotted)
                    Text("The chart starts after your first close")
                        .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false)
                        .foregroundStyle(S.muted)
                        .multilineTextAlignment(.center)
                        .frame(width: max(0, w - 40))
                        .offset(x: 20, y: 34)
                }
            }
            .frame(width: w, height: Self.boxH, alignment: .topLeading)
            .mask(alignment: .leading) { Rectangle().frame(width: max(0, w * drawn)) }
            .contentShape(Rectangle())
            .gesture(ScrubGesture(
                onChange: { x in
                    guard !fresh, w > 0 else { return }
                    let before = at
                    finger = min(max(x / w, 0), 1)
                    if at != before { UISelectionFeedbackGenerator().selectionChanged() }
                },
                onEnd: { finger = nil }))
        }
        .frame(height: Self.boxH)
        .onAppear {
            guard drawn == 0 else { return }
            if reduce { drawn = 1 } else { withAnimation(S.standard(0.9)) { drawn = 1 } }
        }
        .accessibilityElement()
        .accessibilityLabel(chartSummary)
        .accessibilityAdjustableAction { dir in
            let (s, e) = bounds
            guard e > s else { return }
            let i = min(max(at + (dir == .increment ? 1 : -1), s), e)
            finger = CGFloat(i - s) / CGFloat(e - s)
        }
    }

    private var chartSummary: String {
        guard let m = model, !fresh else { return "The chart starts after your first close" }
        if hidden { return "Account chart, numbers hidden" }
        let (s, _) = bounds
        return "\(m.label(at, range)), \(F.money(bigValue)), from \(m.label(s, range))"
    }

    /// Hairline, the date over it and the dot riding the line.
    @ViewBuilder private func scrubMarks(_ m: ChartModel, L: Lines, w: CGFloat) -> some View {
        if let f = finger {
            let x = f * w
            SVLine(x: x, from: 20, to: Self.boxH).stroke(S.ink.opacity(0.28), lineWidth: 1)
            Text(m.label(at, range))
                .sType(SType(size: 12, weight: 600, line: 16, tracking: 0))
                .foregroundStyle(S.muted)
                .fixedSize()
                .position(x: min(max(x, 48), w - 48), y: 8)
            if let d = L.dot {
                let p = f * CGFloat(Self.samples - 1)
                let i0 = min(Self.samples - 2, Int(p.rounded(.down))), t = p - CGFloat(i0)
                Circle().fill(L.tone)
                    .overlay(Circle().stroke(S.chartRing, lineWidth: 2))
                    .frame(width: 9, height: 9)
                    .position(x: x, y: d[i0] + (d[i0 + 1] - d[i0]) * t)
            }
        }
    }

    // MARK: Ranges and the filter icon

    private var rangesRow: some View {
        HStack(spacing: 0) {
            let shown = ChartRange.allCases.filter { model?.available($0) ?? ($0 == .all) }
            ForEach(Array(shown.enumerated()), id: \.element) { k, r in
                if k > 0 { Spacer(minLength: 0) }
                let sel = fresh || r == range
                Button {
                    toMorph { finger = nil; range = r }
                } label: {
                    Text(r.rawValue)
                        .sType(SType(size: 13, weight: sel ? 800 : 600, line: 13, tracking: 0), tabular: false)
                        .foregroundStyle(sel ? S.ink : S.muted)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 40, minHeight: 28)
                        .contentShape(Rectangle().inset(by: -8))
                }
                .buttonStyle(SPressStyle())
                .accessibilityAddTraits(sel ? .isSelected : [])
            }
            if !fresh {
                Spacer(minLength: 0)
                Button {
                    toMorph { finger = nil; compare.toggle(); single = nil; half = .both }
                } label: {
                    SFilterIcon()
                        .stroke(compare ? S.chipOnInk : S.muted, style: StrokeStyle(lineWidth: 2.2 * 16 / 24, lineCap: .round))
                        .frame(width: 16, height: 16)
                        .frame(width: 36, height: 28)
                        .background(Capsule().fill(compare ? S.chipOn : .clear))
                        .contentShape(Rectangle().inset(by: -8))
                }
                .buttonStyle(SPressStyle())
                .accessibilityLabel(compare ? "Back to account value" : "Compare strategies")
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: Stats, legend, quiet line

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if pnl && single == nil {
                legend.transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(stats.enumerated()), id: \.offset) { _, st in
                            statCell(st).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    HStack(spacing: 12) {
                        HStack(spacing: 16) {
                            ForEach(Array(minors.enumerated()), id: \.offset) { _, mn in minor(mn) }
                        }
                        Spacer(minLength: 0)
                        if let g = single, g.splits { halfToggle.transition(.opacity) }
                    }
                    .frame(minHeight: 24)
                }
                .padding(.top, 4)
                .padding(.horizontal, S.margin)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
    }

    private struct Stat {
        let label: String
        var value: Double = 0
        var text: String? = nil
        var color: Color = S.ink
        /// Time value only, live (not while dragging): the word and its colour.
        var read: (word: String, color: Color)? = nil
    }

    private var stats: [Stat] {
        guard let m = model, !fresh else {
            return ["Realized", "Unrealized", "Time value"].map { Stat(label: $0) }
        }
        let (s, e) = bounds, i = at
        let lastLive = i == e && m.c.liveLast
        switch single {
        case .none:
            let r = (m.c.realizedCum[i] ?? 0) - (m.c.realizedCum[s] ?? 0)
            let u = lastLive ? (home.account.unrealized ?? m.c.unrealized[i] ?? 0) : (m.c.unrealized[i] ?? 0)
            let tv = lastLive ? (home.account.timeValueSold ?? m.c.timeValue[i] ?? 0) : (m.c.timeValue[i] ?? 0)
            return [Stat(label: "Realized", value: r, color: S.lossInk(r)),
                    Stat(label: "Unrealized", value: u, color: S.lossInk(u)),
                    Stat(label: "Time value", value: tv, color: S.lossInk(tv),
                         read: scrubbing ? nil : Self.timeValueRead(home))]
        case .shares?:
            let r = m.realized(.shares, .both, i) - m.realized(.shares, .both, s)
            let u = m.unreal(.shares, .both, i)
            return [Stat(label: "Realized", value: r, color: S.lossInk(r)),
                    Stat(label: "Unrealized", value: u, color: S.lossInk(u)),
                    Stat(label: "Held", value: m.c.sharesValue[i] ?? 0)]
        case .dividends?:
            let paid = (m.c.dividendsCum[i] ?? 0) - (m.c.dividendsCum[s] ?? 0)
            let next = m.c.dividends.next.map { F.day($0.payDate ?? $0.exDate) } ?? "-"
            return [Stat(label: "Paid", value: paid),
                    Stat(label: "Yield", text: m.c.dividends.yieldPct.map { F.pct($0, places: 1) } ?? "-"),
                    Stat(label: "Next", text: next)]
        case let g?:
            let r = m.realized(g, half, i) - m.realized(g, half, s)
            let u = m.unreal(g, half, i), tv = m.tv(g, half, i)
            return [Stat(label: "Realized", value: r, color: S.lossInk(r)),
                    Stat(label: "Unrealized", value: u, color: S.lossInk(u)),
                    Stat(label: "Time value", value: tv, color: S.lossInk(tv))]
        }
    }

    private func statCell(_ st: Stat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let t = st.text {
                    Text(t)
                } else {
                    // Full dollars; $K above $100,000 only when the column would wrap.
                    ViewThatFits(in: .horizontal) {
                        SNumber(value: st.value, format: { F.money($0) }, countUp: false)
                        SNumber(value: st.value, format: { F.moneyK($0) }, countUp: false)
                    }
                }
            }
            .sType(SType(size: 20, weight: 700, line: 24, tracking: -0.01))
            .foregroundStyle(st.color)
            .lineLimit(1)
            .blur(radius: hidden ? 9 : 0)
            // The read rolls in over "Time value" for a few seconds, then back.
            let word = readOn ? st.read : nil
            ZStack(alignment: .leading) {
                Text(word?.word ?? st.label)
                    .sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false)
                    .foregroundStyle(word?.color ?? S.muted)
                    .lineLimit(1)
                    .id(word?.word ?? st.label)
                    .transition(reduce ? .identity : .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)))
            }
            .frame(height: 16, alignment: .leading)
            .clipped()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(st.read?.word ?? st.label) \(hidden ? "hidden" : st.text ?? F.money(st.value))")
    }

    private struct Minor { let label: String; let text: String; var color: Color = S.ink }

    private var minors: [Minor] {
        guard let m = model, m.n > 0 else { return [] }
        let (s, e) = bounds, i = at
        if fresh {
            return [Minor(label: "Margin", text: F.money(home.account.margin ?? m.c.margin[e] ?? 0)),
                    Minor(label: "Interest", text: "$0"), Minor(label: "Fees", text: "$0")]
        }
        switch single {
        case .none:
            let margin = i == e && m.c.liveLast ? (home.account.margin ?? m.c.margin[i] ?? 0) : (m.c.margin[i] ?? 0)
            let interest = (m.c.interestCum[i] ?? 0) - (m.c.interestCum[s] ?? 0)
            let fees = (m.c.commissionCum[i] ?? 0) - (m.c.commissionCum[s] ?? 0)
            return [Minor(label: "Margin", text: F.money(margin)),
                    Minor(label: "Interest", text: F.money(interest)),
                    Minor(label: "Fees", text: F.money(fees), color: fees.rounded() < 0 ? S.red : S.ink)]
        case .shares?:
            return [Minor(label: "Tickers", text: "\(m.c.sharesTickers[safe: i] ?? 0)")]
        case .dividends?:
            return [Minor(label: "Payers", text: "\(m.payers(from: m.c.days[s], to: m.c.days[i]))")]
        case let g?:
            let k = m.closed(g, half, from: m.c.days[s], to: m.c.days[i])
            return [Minor(label: g == .sold ? "Kept full credit" : "Closed in profit", text: "\(k.hit) of \(k.of)")]
        }
    }

    private func minor(_ mn: Minor) -> some View {
        HStack(spacing: 5) {
            Text(mn.label).sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false)
                .foregroundStyle(S.muted)
            Text(mn.text).sType(SType(size: 13, weight: 700, line: 18, tracking: 0))
                .foregroundStyle(mn.color)
                .contentTransition(.numericText())
                .blur(radius: hidden ? 9 : 0)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mn.label) \(hidden ? "hidden" : mn.text)")
    }

    private var halfToggle: some View {
        HStack(spacing: 0) {
            ForEach(ChartHalf.allCases) { h in
                Button { toMorph { finger = nil; half = h } } label: {
                    Text(h.rawValue)
                        .sType(SType(size: 11, weight: 600, line: 11, tracking: 0), tabular: false)
                        .foregroundStyle(half == h ? S.chipOnInk : S.ink)
                        .padding(.horizontal, 10).frame(height: 20)
                        .background(Capsule().fill(half == h ? S.chipOn : .clear))
                        .contentShape(Rectangle().inset(by: -10))
                }
                .buttonStyle(SPressStyle())
                .accessibilityAddTraits(half == h ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(height: 24)
        .background(Capsule().fill(S.surface))
    }

    // MARK: Legend (compare, nothing singled out)

    private var legend: some View {
        let m = model
        let (s, _) = bounds, i = at
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())],
                         alignment: .leading, spacing: 4) {
            ForEach(shownGroups) { g in
                let v = m.map { $0.line(g, .both, i) - $0.line(g, .both, s) } ?? 0
                Button { toMorph { finger = nil; single = g; half = .both } } label: {
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Circle().fill(g.color).frame(width: 8, height: 8)
                            Text(g.rawValue).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false)
                                .foregroundStyle(S.ink)
                        }
                        Spacer(minLength: 0)
                        Text(F.money(v)).sType(SType(size: 13, weight: 700, line: 18, tracking: 0))
                            .foregroundStyle(S.lossInk(v))
                            .contentTransition(.numericText(value: v))
                            .blur(radius: hidden ? 9 : 0)
                    }
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SPressStyle())
                .accessibilityLabel("\(g.rawValue) \(hidden ? "hidden" : F.money(v))")
                .accessibilityHint("Shows \(g.rawValue) on its own")
            }
        }
        .padding(.horizontal, S.margin)
        .animation(.smooth(duration: S.roll), value: i)
    }
}

// MARK: - Shapes

/// A line through 240 samples between two fractions of the width. The
/// samples animate, so a range or filter change morphs the old shape into
/// the new one instead of redrawing it.
struct SLine: Shape {
    var ys: AnimatableVector
    var from: CGFloat
    var to: CGFloat

    init(ys: [CGFloat], from: CGFloat, to: CGFloat) {
        self.ys = AnimatableVector(ys.map(Double.init))
        self.from = from; self.to = to
    }
    var animatableData: AnimatableVector {
        get { ys }
        set { ys = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let v = ys.values, M = v.count
        guard M > 1, to > from else { return p }
        let W = rect.width
        let at = { (pos: CGFloat) -> CGFloat in
            let i0 = max(0, min(M - 2, Int(pos.rounded(.down)))), t = pos - CGFloat(i0)
            return CGFloat(v[i0]) + (CGFloat(v[i0 + 1]) - CGFloat(v[i0])) * t
        }
        let pa = from * CGFloat(M - 1), pb = to * CGFloat(M - 1)
        p.move(to: CGPoint(x: from * W, y: at(pa)))
        var m = Int(pa.rounded(.down)) + 1
        while CGFloat(m) < pb {
            p.addLine(to: CGPoint(x: CGFloat(m) / CGFloat(M - 1) * W, y: CGFloat(v[m])))
            m += 1
        }
        p.addLine(to: CGPoint(x: to * W, y: at(pb)))
        return p
    }
}

/// The full-width dotted base line; its height animates with the morph.
struct SHLine: Shape {
    var y: CGFloat
    var animatableData: CGFloat {
        get { y }
        set { y = newValue }
    }
    func path(in rect: CGRect) -> Path {
        Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: rect.width, y: y)) }
    }
}

struct SVLine: Shape {
    let x: CGFloat, from: CGFloat, to: CGFloat
    func path(in rect: CGRect) -> Path {
        Path { $0.move(to: CGPoint(x: x, y: from)); $0.addLine(to: CGPoint(x: x, y: to)) }
    }
}

/// The filter icon from the design file (two sliders, 24 pt grid).
struct SFilterIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 24
        var p = Path()
        for (a, b, y) in [(4.0, 14.0, 7.0), (18, 20, 7), (4, 8, 17), (12, 20, 17)] {
            p.move(to: CGPoint(x: a * k, y: y * k)); p.addLine(to: CGPoint(x: b * k, y: y * k))
        }
        p.addEllipse(in: CGRect(x: 14 * k, y: 5 * k, width: 4 * k, height: 4 * k))
        p.addEllipse(in: CGRect(x: 8 * k, y: 15 * k, width: 4 * k, height: 4 * k))
        return p
    }
}

/// A ×: two bars crossed at the centre. `half` is half a bar's length
/// (4 on the chart's title pill, 6 on a deck card's dismiss).
struct SCross: Shape {
    var half: CGFloat = 4
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY), d = half / 2.squareRoot()
        return Path { p in
            p.move(to: CGPoint(x: c.x - d, y: c.y - d)); p.addLine(to: CGPoint(x: c.x + d, y: c.y + d))
            p.move(to: CGPoint(x: c.x + d, y: c.y - d)); p.addLine(to: CGPoint(x: c.x - d, y: c.y + d))
        }
    }
}

struct AnimatableVector: VectorArithmetic {
    var values: [Double]
    init(_ v: [Double]) { values = v }
    static var zero: AnimatableVector { AnimatableVector([]) }
    static func + (a: Self, b: Self) -> Self { combine(a, b, +) }
    static func - (a: Self, b: Self) -> Self { combine(a, b, -) }
    mutating func scale(by r: Double) { values = values.map { $0 * r } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
    private static func combine(_ a: Self, _ b: Self, _ op: (Double, Double) -> Double) -> Self {
        let n = max(a.values.count, b.values.count)
        return AnimatableVector((0..<n).map { op($0 < a.values.count ? a.values[$0] : 0, $0 < b.values.count ? b.values[$0] : 0) })
    }
}

// MARK: - Scrub gesture

/// Touch and drag on the chart scrubs at once, without stealing the page's
/// vertical scroll: the touch starts the scrub immediately, a mostly vertical
/// first move hands the touch back to the scroll view, a horizontal one
/// keeps it and holds the page still.
struct ScrubGesture: UIGestureRecognizerRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> ScrubRecognizer {
        let r = ScrubRecognizer()
        r.delegate = context.coordinator
        return r
    }

    func handleUIGestureRecognizerAction(_ r: ScrubRecognizer, context: Context) {
        switch r.state {
        case .began, .changed: onChange(context.converter.localLocation.x)
        case .ended, .cancelled, .failed: onEnd()
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
    }
}

final class ScrubRecognizer: UIGestureRecognizer {
    private var start: CGPoint = .zero
    private var decided = false
    /// The view the finger landed on: the scroll views to hold are above it.
    private weak var touched: UIView?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, let t = touches.first else { state = .failed; return }
        touched = t.view
        start = t.location(in: view)
        decided = false
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = touches.first else { return }
        let p = t.location(in: view)
        if !decided {
            let dx = abs(p.x - start.x), dy = abs(p.y - start.y)
            if hypot(dx, dy) > 6 {
                decided = true
                if dy > dx { state = .cancelled; return }
                holdPage()
            }
        }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { state = .ended }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }
    override func reset() { decided = false }

    /// Cancel every enclosing scroll view's pan so the page, and a sideways
    /// card row (Theta and Delta), hold still while scrubbing. Walks up from
    /// the touched view: the recognizer's own view can sit above the scroll
    /// views in SwiftUI's hierarchy, which let the Risk row slide (13 Oct 2026).
    private func holdPage() {
        var v = touched ?? view
        while let s = v {
            if let sv = s as? UIScrollView {
                sv.panGestureRecognizer.isEnabled = false
                sv.panGestureRecognizer.isEnabled = true
            }
            v = s.superview
        }
    }
}
