//
//  SPeriodCard.swift
//  Sunny
//
//  The parts Inventory (14), Yield (17) and Sold vs Bought (19) share, as the
//  phone design builds them: a small label over the big number and its sub
//  line, ‹ › to step months (Week) or years (Month), the stat line, Week |
//  Month, SunnyBarChart (80 pt columns, 40 apart, scrolls when wider than
//  the card, opens on now) and the two-column legend. Plus the inline
//  insight: a hairline under the stats that opens the card's sentence.
//

import SwiftUI

// MARK: - Periods

/// Week shows W1 to W5 of a month; Month shows Jan to Dec of a year.
/// One state, shared by every period card so they move together.
@MainActor
@Observable
final class PeriodState {
    enum View: String, CaseIterable { case week = "Week", month = "Month" }
    /// What the cards show. It changes 240 ms after a flip, with no animation.
    var view: View = DebugPreset.string("period.view") == "month" ? .month : .week
    /// What the Week | Month switch shows: it moves at once.
    var selected: View = DebugPreset.string("period.view") == "month" ? .month : .week
    /// Bars up, hero and value labels shown. False through a flip's Out phase.
    var grown = true
    private var swap: Task<Void, Never>?
    /// Months (Week) or years (Month) back from now; 0 = now, never ahead.
    var back = DebugPreset.int("period.back") ?? 0
    var picked: [String: Int] = {      // card key -> picked column
        var p: [String: Int] = [:]
        for k in ["inv", "yield", "svb"] { if let v = DebugPreset.int("\(k).pick") { p[k] = v } }
        return p
    }()

    /// ‹ ›: no Out phase; the bars morph from old to new height.
    func step(_ d: Int) {
        withAnimation(S.standard(S.grow)) { back = max(0, back - d); picked = [:] }
    }

    /// Week ↔ Month (update 14 Oct): the thumb slides; Out (bars shrink, the
    /// hero and value labels fade) runs 240 ms; then the data, labels and
    /// scroll swap with no animation and the bars render at 0; two frames on,
    /// In: bars grow 0.7 s, the hero rises in after 0.2 s, labels after 0.5 s.
    /// Each part carries its own timing, keyed on `grown`. The last tap wins;
    /// Reduce Motion swaps at once.
    func flip(to v: View, reduce: Bool) {
        guard v != selected else { return }
        withAnimation(reduce ? .easeOut(duration: 0.2) : S.thumb()) { selected = v }
        swap?.cancel()
        if reduce {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { view = v; back = 0; picked = [:]; grown = true }
            return
        }
        grown = false
        swap = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled else { return }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { view = v; back = 0; picked = [:] }
            try? await Task.sleep(for: .milliseconds(32))
            guard !Task.isCancelled else { return }
            grown = true
        }
    }
}

enum Periods {
    static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let longMonths = DeckBuilder.months

    /// The month (Week view) or year (Month view) on screen, "2026-10" / "2026".
    static func anchor(_ s: PeriodState, today: String) -> String {
        let y = Int(today.prefix(4)) ?? 2026, m = Int(today.dropFirst(5).prefix(2)) ?? 1
        if s.view == .month { return String(y - s.back) }
        let idx = y * 12 + (m - 1) - s.back
        return String(format: "%04d-%02d", idx / 12, idx % 12 + 1)
    }
    /// Fridays of a month (the week's label is its Friday's month).
    static func fridays(_ ym: String) -> [String] {
        var out: [String] = []
        var d = MarketClock.addDays(ym + "-01", 0)
        while d.iso.hasPrefix(ym) {
            if d.weekday == 6 { out.append(d.iso) }
            d = MarketClock.addDays(d.iso, 1)
        }
        return out
    }
    /// The book's first day (1 Sep 2026): Month view starts at its month, and
    /// the back arrow stops there (Nik, 13 Oct 2026: no empty Jan to Aug).
    static func bookStart(_ h: HomePayload) -> String { h.history.from ?? h.history.days.first ?? "2026-09-01" }
    /// Month indices (0 = Jan) shown for a year: from the book's first month on.
    static func months(_ year: String, start: String) -> [Int] {
        let sy = String(start.prefix(4)), sm = Int(start.dropFirst(5).prefix(2)) ?? 1
        if year < sy { return [] }
        return year == sy ? Array((sm - 1)..<12) : Array(0..<12)
    }
    /// Is there an earlier week-month (Week) or year (Month) with the book in it?
    static func canGoBack(_ s: PeriodState, today: String, start: String) -> Bool {
        let a = anchor(s, today: today)
        return s.view == .month ? a > String(start.prefix(4)) : a > String(start.prefix(7))
    }
    /// This week's Friday (the coming one at the weekend).
    static func thisFriday(_ today: String) -> String {
        var d = MarketClock.addDays(today, 0)
        while d.weekday != 6 { d = MarketClock.addDays(d.iso, d.weekday == 7 ? 6 : 1) }
        return d.iso
    }
    /// "October" · "October · W2" · "2026" · "2026 · Sep"
    static func label(_ s: PeriodState, today: String, picked: Int?) -> String {
        let a = anchor(s, today: today)
        if s.view == .month {
            return picked.map { "\(longMonths[$0]) \(a)" } ?? a
        }
        let m = longMonths[(Int(a.suffix(2)) ?? 1) - 1]
        return picked.map { "\(m) · W\($0 + 1)" } ?? m
    }
}

// MARK: - Header

struct SPeriodHeader: View {
    let label: String
    let hero: String
    let heroValue: Double
    var heroColor: Color = S.ink
    let sub: String
    let onTap: () -> Void
    @Bindable var period: PeriodState
    var arrows = true
    /// False when the period on screen is the book's first (no earlier data).
    var canGoBack = true

    var body: some View {
        // The arrows sit beside the label; the number runs the full width under them.
        // The row is the arrows' 44 pt, so they sit inside the card's padding and
        // clear the number (the design's 28 pt row with negative padding did not).
        VStack(alignment: .leading, spacing: 8) {
            Text(label).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.muted)
                .frame(maxWidth: .infinity, minHeight: arrows ? 44 : 28, alignment: .leading)
                .overlay(alignment: .trailing) {
                    if arrows {
                        HStack(spacing: 8) {
                            SArrowButton(left: true) { period.step(-1) }
                                .disabled(!canGoBack).opacity(canGoBack ? 1 : 0.35)
                            SArrowButton(left: false) { period.step(1) }
                                .disabled(period.back == 0).opacity(period.back == 0 ? 0.35 : 1)
                        }
                    }
                }
                .padding(.vertical, arrows ? 0 : -4)
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(hero).sType(.largeNumber).foregroundStyle(heroColor)
                        .contentTransition(.numericText(value: heroValue))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(sub).sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                        .foregroundStyle(S.muted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                // Week ↔ Month: out 0.15 s with a 6 pt drop, back in 0.5 s after 0.2 s.
                .opacity(period.grown ? 1 : 0)
                .offset(y: period.grown ? 0 : 6)
                .animation(period.grown ? S.standard(0.5).delay(0.2) : .easeOut(duration: 0.15), value: period.grown)
            }
            .buttonStyle(SPressStyle())
            .accessibilityHint("Switches what the number shows")
        }
    }
}

struct SArrowButton: View {
    let left: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            // Apple's own size (Nik, 13 Oct 2026: the design's 28 pt read too small
            // next to iOS's back buttons): a 44 pt glass circle, 17 pt semibold chevron.
            Image(systemName: left ? "chevron.left" : "chevron.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(S.ink)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(Circle())
        }
        .buttonStyle(SPressStyle())
        .accessibilityLabel(left ? "Earlier" : "Later")
    }
}

// MARK: - Stat line

/// "$6.3K credit · 95 calls sold · 4 puts sold"
struct SStatLine: View {
    let items: [(value: String, label: String, color: Color)]
    var body: some View {
        items.enumerated().reduce(Text("")) { acc, e in
            let (i, it) = e
            let sep = i == 0 ? Text("") : Text(" · ").foregroundStyle(S.muted)
            return acc + sep
                + Text(it.value).font(SType(size: 13, weight: 700, line: 16, tracking: 0).font(tabular: true)).foregroundStyle(it.color)
                + Text(it.label.isEmpty ? "" : " " + it.label).foregroundStyle(S.muted)
        }
        .sType(SType(size: 13, weight: 500, line: 16, tracking: 0))
        .lineLimit(1).minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Week | Month

struct SViewToggle: View {
    @Bindable var period: PeriodState
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        HStack(spacing: 0) {
            ForEach(PeriodState.View.allCases, id: \.self) { v in
                Button {
                    period.flip(to: v, reduce: reduce)
                } label: {
                    Text(v.rawValue).sType(.label, tabular: false)
                        .foregroundStyle(period.selected == v ? S.chipOnInk : S.ink)
                        .animation(.easeOut(duration: 0.3), value: period.selected)
                        .frame(width: 68, height: 28)
                        .background {
                            if period.selected == v { Capsule().fill(S.ink).matchedGeometryEffect(id: "thumb", in: ns) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(SPressStyle())
                .accessibilityAddTraits(period.selected == v ? .isSelected : [])
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - SunnyBarChart

struct SBar {
    struct Seg { let value: CGFloat; let color: Color; var hidden = false }
    let segs: [Seg]               // bottom up, heights in points
    var label: String = ""
    var labelColor: Color = S.ink
    var sub: String? = nil
}

struct SBarColumn: Identifiable {
    let id: Int
    let label: String
    let bars: [SBar]
    var isNow = false
}

struct SBarChart: View {
    let columns: [SBarColumn]
    /// Dashed lines edge to edge: height from the base, label, colour.
    var caps: [(h: CGFloat, label: String, color: Color)] = []
    let picked: Int?
    let onPick: (Int?) -> Void
    /// Week ↔ Month: false while the bars are down (PeriodState.grown).
    var grown: Bool = true
    /// The row's identity: a new row (already on now) for each Week | Month view.
    var rowKey: String = ""
    @State private var viewW: CGFloat = 0

    private static let H: CGFloat = 172
    private static let colW: CGFloat = 80, gap: CGFloat = 40

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                let inner = max(0, CGFloat(columns.count) * Self.colW + CGFloat(max(0, columns.count - 1)) * Self.gap + 28)
                ZStack(alignment: .bottomLeading) {
                    // Four faint rules.
                    VStack(spacing: 0) {
                        ForEach(0..<4) { i in
                            Rectangle().fill(S.pGrid).frame(height: 1)
                            if i < 3 { Spacer(minLength: 0) }
                        }
                    }
                    .frame(height: Self.H - 24)
                    .padding(.horizontal, -20)
                    .frame(maxHeight: .infinity, alignment: .top)
                    ForEach(Array(caps.enumerated()), id: \.offset) { _, c in
                        DashedRule().stroke(c.color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .frame(height: 1.5)
                            .overlay(alignment: .bottomTrailing) {
                                Text(c.label).sType(SType(size: 11, weight: 700, line: 12, tracking: 0))
                                    .foregroundStyle(c.color).fixedSize().offset(x: 0, y: -6)
                            }
                            .padding(.horizontal, -20)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .offset(y: 146 - c.h)
                            .zIndex(2)
                    }
                    HStack(alignment: .bottom, spacing: Self.gap) {
                        ForEach(columns) { col in column(col).id(col.id) }
                    }
                    .padding(.horizontal, 14)
                    .zIndex(1)
                }
                .frame(width: inner, height: Self.H)
                // Room for the grey box's rounded ends (top -10, bottom -8), which
                // the scroll view would otherwise cut flat; layout height unchanged.
                .padding(.vertical, 12)
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
            .padding(.vertical, -12)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewW = $0 }
            .onAppear { land(proxy) }
            // ‹ › inside a view: the same row, scrolled along with the morph.
            .onChange(of: columns.map(\.label)) { _, _ in
                withAnimation(S.standard(S.grow)) { land(proxy) }
            }
            // Week ↔ Month: a new row, swapped in with no animation while the
            // bars are down and already on now. (Scrolling one row across the
            // swap clamped it to its start for a frame, the "flash".)
            .id(rowKey)
        }
    }

    /// Now sits 32 pt in from the right edge; a past period opens at the start.
    private func land(_ proxy: ScrollViewProxy) {
        if let now = columns.first(where: \.isNow)?.id {
            let w = viewW > Self.colW + 32 ? viewW : 353
            proxy.scrollTo(now, anchor: UnitPoint(x: (w - 32 - Self.colW) / (w - Self.colW), y: 0.5))
        } else if let first = columns.first?.id {
            proxy.scrollTo(first, anchor: .leading)
        }
    }

    private func column(_ col: SBarColumn) -> some View {
        // The grey box and bold label sit on the picked column, or on this
        // week (this month) when nothing is picked (phone design: isNow follows the pick).
        let lit = picked.map { $0 == col.id } ?? col.isNow
        return Button {
            withAnimation(S.standard(0.35)) { onPick(picked == col.id ? nil : col.id) }
        } label: {
            VStack(spacing: 12) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(col.bars.enumerated()), id: \.offset) { _, b in
                        VStack(spacing: 4) {
                            VStack(spacing: 2) {
                                if !b.label.isEmpty {
                                    Text(b.label).sType(SType(size: 11, weight: 600, line: 12, tracking: 0)).foregroundStyle(b.labelColor)
                                }
                                if let s = b.sub {
                                    Text(s).sType(SType(size: 11, weight: 600, line: 12, tracking: 0)).foregroundStyle(S.muted)
                                }
                            }
                            .fixedSize()
                            // Week ↔ Month: out 0.15 s, back 0.4 s once the bars are mostly up.
                            // Scoped to the opacity: value-keyed, the delay also held the
                            // label at the baseline behind its growing bar.
                            .animation(grown ? .easeOut(duration: 0.4).delay(0.5) : .easeOut(duration: 0.15)) {
                                $0.opacity(grown ? 1 : 0)
                            }
                            // Stacked segments shrink and grow as one bar.
                            VStack(spacing: 0) {
                                ForEach(Array(b.segs.reversed().enumerated()), id: \.offset) { _, g in
                                    Rectangle().fill(g.color).frame(height: grown ? max(0, g.value) : 0).opacity(g.hidden ? 0.25 : 1)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        // Bar heights, and the label riding on top, 0.7 s.
                        .animation(S.standard(S.grow), value: grown)
                        .frame(maxWidth: .infinity)
                    }
                }
                Text(col.label)
                    .sType(SType(size: 12, weight: lit ? 700 : 600, line: 12, tracking: 0), tabular: false)
                    .foregroundStyle(lit ? S.ink : S.muted)
                    .frame(height: 14)
            }
            .frame(width: Self.colW)
            .background {
                if lit {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(S.pGrid)
                        .padding(.horizontal, -12).padding(.top, -10).padding(.bottom, -8)
                }
            }
            // No fade on the other columns (Nik, 13 Oct 2026): the grey box marks the pick.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(col.label)
        .accessibilityAddTraits(picked == col.id ? .isSelected : [])
    }
}

// MARK: - Legend

struct SLegend: View {
    let rows: [(key: String, name: String, value: String, color: Color)]
    @Binding var hidden: Set<String>
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], alignment: .leading, spacing: 12) {
            ForEach(rows, id: \.key) { r in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if hidden.contains(r.key) { hidden.remove(r.key) } else { hidden.insert(r.key) }
                    }
                } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2).fill(r.color).frame(width: 4)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.name).sType(SType(size: 13, weight: 400, line: 16, tracking: 0), tabular: false)
                                .foregroundStyle(S.muted).lineLimit(1)
                            Text(r.value).sType(SType(size: 15, weight: 700, line: 15, tracking: 0)).foregroundStyle(S.ink)
                                .contentTransition(.numericText())
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(hidden.contains(r.key) ? 0.35 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(r.name) \(r.value)")
                .accessibilityHint(hidden.contains(r.key) ? "Shows this series" : "Hides this series")
            }
        }
    }
}

// MARK: - Inline insight (block 22, the default style)

/// A hairline under the stats. Tap: it thickens into the warm-to-cool line
/// and the card's sentence opens under it. Tap again to fold.
struct SInlineInsight: View {
    let lead: String
    let rest: String
    @State private var open = DebugPreset.bool("insight.open")
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.timingCurve(0.34, 1.4, 0.4, 1, duration: 0.6)) { open.toggle() } } label: {
                ZStack(alignment: .leading) {
                    Rectangle().fill(S.line)
                    LinearGradient(colors: [Color(hex: 0xF2A06E), Color(hex: 0xF7CE9A), Color(hex: 0x7FA6F0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .scaleEffect(x: open ? 1 : 0, anchor: .leading)
                        .opacity(open ? 1 : 0)
                }
                .frame(height: open ? 3 : 1)
                .shadow(color: open ? Color(hex: 0xF2A06E).opacity(0.55) : .clear, radius: 5, y: 2)
                .frame(height: 16, alignment: .bottom)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Hide the insight" : "Show the insight")
            if open {
                (Text(lead).font(SType(size: 15, weight: 700, line: 20, tracking: 0).font()).foregroundStyle(scheme == .dark ? .white : S.ink)
                 + Text(rest.isEmpty ? "" : " " + rest))
                    .sType(SType(size: 15, weight: 400, line: 20, tracking: 0), tabular: false)
                    .foregroundStyle(scheme == .dark ? Color.white.opacity(0.92) : S.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 16).padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(insightFill)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // Clip first, then widen: clipping after the negative padding cut the
        // line and gradient back to the text margins instead of the card edges.
        .clipped()
        .padding(.horizontal, -20)
    }

    private var insightFill: some View {
        Group {
            if scheme == .dark {
                LinearGradient(stops: [.init(color: Color(red: 54/255, green: 30/255, blue: 36/255).opacity(0.97), location: 0),
                                       .init(color: Color(red: 14/255, green: 14/255, blue: 16/255).opacity(0.97), location: 0.46),
                                       .init(color: Color(red: 22/255, green: 34/255, blue: 64/255).opacity(0.97), location: 1)],
                               startPoint: UnitPoint(x: 0, y: 0.3), endPoint: UnitPoint(x: 1, y: 0.7))
            } else {
                LinearGradient(stops: [.init(color: Color(red: 1, green: 190/255, blue: 150/255).opacity(0.72), location: 0),
                                       .init(color: Color(red: 1, green: 236/255, blue: 214/255).opacity(0.62), location: 0.46),
                                       .init(color: Color(red: 160/255, green: 196/255, blue: 1).opacity(0.72), location: 1)],
                               startPoint: UnitPoint(x: 0, y: 0.3), endPoint: UnitPoint(x: 1, y: 0.7))
            }
        }
    }
}
