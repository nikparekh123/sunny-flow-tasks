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
    var view: View = DebugPreset.string("period.view") == "month" ? .month : .week
    /// Months (Week) or years (Month) back from now; 0 = now, never ahead.
    var back = DebugPreset.int("period.back") ?? 0
    var picked: [String: Int] = {      // card key -> picked column
        var p: [String: Int] = [:]
        for k in ["inv", "yield", "svb"] { if let v = DebugPreset.int("\(k).pick") { p[k] = v } }
        return p
    }()

    func step(_ d: Int) {
        withAnimation(S.standard()) { back = max(0, back - d); picked = [:] }
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

    var body: some View {
        // The arrows sit beside the label; the number runs the full width under them.
        VStack(alignment: .leading, spacing: 12) {
            Text(label).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.muted)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .overlay(alignment: .trailing) {
                    if arrows {
                        HStack(spacing: 4) {
                            SArrowButton(left: true) { period.step(-1) }
                            SArrowButton(left: false) { period.step(1) }
                                .disabled(period.back == 0).opacity(period.back == 0 ? 0.35 : 1)
                        }
                    }
                }
                .padding(.vertical, -4)
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
            Image(systemName: left ? "chevron.left" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(S.ink)
                .frame(width: 28, height: 28)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(Circle().inset(by: -8))
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
    var body: some View {
        HStack(spacing: 0) {
            ForEach(PeriodState.View.allCases, id: \.self) { v in
                Button {
                    withAnimation(.timingCurve(0.34, 1.4, 0.4, 1, duration: 0.45)) {
                        period.view = v; period.back = 0; period.picked = [:]
                    }
                } label: {
                    Text(v.rawValue).sType(.label, tabular: false)
                        .foregroundStyle(period.view == v ? S.chipOnInk : S.ink)
                        .frame(width: 68, height: 28)
                        .background {
                            if period.view == v { Capsule().fill(S.ink).matchedGeometryEffect(id: "thumb", in: ns) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(SPressStyle())
                .accessibilityAddTraits(period.view == v ? .isSelected : [])
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
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
            .onAppear {
                if let now = columns.first(where: \.isNow)?.id { proxy.scrollTo(now, anchor: .center) }
            }
        }
    }

    private func column(_ col: SBarColumn) -> some View {
        let fade = picked != nil && picked != col.id
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
                            VStack(spacing: 0) {
                                ForEach(Array(b.segs.reversed().enumerated()), id: \.offset) { _, g in
                                    Rectangle().fill(g.color).frame(height: max(0, g.value)).opacity(g.hidden ? 0.25 : 1)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text(col.label)
                    .sType(SType(size: 12, weight: col.isNow ? 700 : 600, line: 12, tracking: 0), tabular: false)
                    .foregroundStyle(col.isNow ? S.ink : S.muted)
                    .frame(height: 14)
            }
            .frame(width: Self.colW)
            .background {
                if col.isNow {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(S.pGrid)
                        .padding(.horizontal, -12).padding(.top, -10).padding(.bottom, -12)
                }
            }
            .opacity(fade ? 0.35 : 1)
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
    @State private var open = false
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
        .padding(.horizontal, -20)
        .clipped()
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
