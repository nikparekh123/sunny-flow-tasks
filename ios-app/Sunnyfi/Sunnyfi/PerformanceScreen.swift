//
//  PerformanceScreen.swift
//  Sunnyfi
//
//  Performance — top-tabbed page with two views:
//   1. Gains & Losses — diverging stacked bar chart of REALIZED P&L,
//      broken out by source (Shares · Calls sold · Calls bought ·
//      Puts sold · Puts bought) over a Week / Month / Year window.
//      Empty days/months are SKIPPED so the chart reads as a row of
//      event days, not a calendar with gaps. Net mode collapses each
//      bar into a single signed bar.
//   2. Leaderboard — open + closed positions ranked by LIFETIME
//      realized P&L (winners → #1). Not period-bound.
//
//  Built from the design handoff in `design_handoff_performance/`. The
//  chart uses Swift Charts (BarMark with positional stacking + per-
//  source color). Top tabs match the design's solid-neon style (this
//  is the one place the deep teal accent leads a top-of-screen nav).
//

import SwiftUI
import Charts

struct PerformanceScreen: View {
    let store: PortfolioStore
    let auth: AuthStore

    enum Tab: String, CaseIterable, Identifiable {
        case gainsLosses = "Gains & Losses"
        case leaderboard = "Leaderboard"
        var id: String { rawValue }
    }
    @State private var tab: Tab = .gainsLosses
    /// Multi-select ticker filter. EMPTY = all tickers (the default).
    /// Every metric and chart on this page reads through it.
    @State private var tickerFilter: Set<String> = []

    /// Every ticker with any history — held or fully closed out.
    private var availableTickers: [String] {
        Set(store.companies.map(\.ticker))
            .union(store.closedCompanies.map(\.ticker))
            .union(store.allTrades.map(\.ticker))
            .sorted()
    }
    private var activeTickers: [String] {
        tickerFilter.isEmpty ? availableTickers : availableTickers.filter { tickerFilter.contains($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                titleRow
                pnlStrip
                tickerFilterRow
                tabBar

                // Tab content with a sliding transition + horizontal
                // swipe gesture so the user can flick between Gains &
                // Losses and Leaderboard. The transition direction is
                // wired so that swiping LEFT on the first tab brings
                // the second tab in from the right (iOS-native feel).
                ZStack {
                    if tab == .gainsLosses {
                        GainsLossesTab(store: store, filter: tickerFilter)
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal:   .move(edge: .leading).combined(with: .opacity)
                            ))
                    } else {
                        LeaderboardTab(store: store, filter: tickerFilter)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal:   .move(edge: .trailing).combined(with: .opacity)
                            ))
                    }
                }
                .animation(Motion.standard, value: tab)
                // Horizontal swipe to flip tabs. minimumDistance is
                // high enough that vertical scrolling still wins, but
                // a clear horizontal flick (>80pt) commits a switch.
                .gesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            guard abs(dx) > abs(dy) * 1.4, abs(dx) > 70 else { return }
                            withAnimation(Motion.standard) {
                                if dx < 0 {
                                    if tab == .gainsLosses { tab = .leaderboard }
                                } else {
                                    if tab == .leaderboard { tab = .gainsLosses }
                                }
                            }
                        }
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 100)
        }
        .background(Color.theme.page.ignoresSafeArea())
    }

    // ── Title — Navi DS hero ──
    private var titleRow: some View {
        HStack {
            Text("Performance").heroTitle()
            Spacer()
        }
    }

    // ── Top tabs — design-spec solid-neon segmented (page-2 track,
    // neon-filled active, white ink) with a sliding thumb. ──
    // MARK: P&L strip
    //
    // Realized / unrealized / total, computed by CoveredCallData — the
    // SAME engine the Covered Call tab uses — so the two can never
    // disagree. Respects the ticker filter.
    private var pnlStrip: some View {
        let p = CoveredCallData.pnl(store: store, tickers: activeTickers)
        return HStack(alignment: .top, spacing: 0) {
            pnlCell("REALIZED", p.realized)
            Rectangle().fill(Color.theme.hair).frame(width: 0.5, height: 34)
            pnlCell("UNREALIZED", p.unrealized)
            Rectangle().fill(Color.theme.hair).frame(width: 0.5, height: 34)
            pnlCell("TOTAL", p.total, loud: true)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: Radius.xl).fill(Color.theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl)
            .strokeBorder(Color.theme.hair, lineWidth: 0.5))
    }

    private func pnlCell(_ k: String, _ v: Double, loud: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(k).font(.system(size: 8.5, weight: .bold)).tracking(0.9)
                .foregroundStyle(Color.theme.fg3)
            Text(fmtMoney(v, sign: true))
                .font(.numeric(size: loud ? 18 : 16, weight: .heavy))
                .tracking(-0.4).monospacedDigit()
                .foregroundStyle(Color.signed(v))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 2)
    }

    // MARK: Ticker filter (multi-select, all by default)

    private var tickerFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterPill("All", active: tickerFilter.isEmpty) {
                    withAnimation(Motion.standard) { tickerFilter.removeAll() }
                }
                ForEach(availableTickers, id: \.self) { t in
                    filterPill(t, active: tickerFilter.contains(t)) {
                        withAnimation(Motion.standard) {
                            if tickerFilter.contains(t) { tickerFilter.remove(t) }
                            else { tickerFilter.insert(t) }
                        }
                    }
                }
            }
            .padding(.horizontal, 1)
        }
    }

    @ViewBuilder
    private func filterPill(_ label: String, active: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label)
                .font(.system(size: 11.5, weight: active ? .bold : .semibold))
                .tracking(0.3)
                .foregroundStyle(active ? Color.theme.onNeon : Color.theme.fg2)
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .background(
                    Capsule()
                        .fill(active ? Color.theme.neon : Color.theme.surface)
                        .overlay(Capsule().strokeBorder(
                            active ? Color.clear : Color.theme.borderBright, lineWidth: 1))
                )
        }
        .buttonStyle(.pressable)
    }

    @Namespace private var topTabNS
    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { t in
                let active = tab == t
                Button {
                    withAnimation(Motion.standard) { tab = t }
                } label: {
                    Text(t.rawValue)
                        .font(.ui(size: 14, weight: active ? .bold : .semibold))
                        .tracking(-0.1)
                        .foregroundStyle(active ? Color.theme.onNeon : Color.theme.fg2)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .padding(.vertical, 4)
                        .background {
                            if active {
                                Capsule()
                                    .fill(Color.theme.neon)
                                    .matchedGeometryEffect(id: "perfTopTab", in: topTabNS)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.theme.page2)
        )
    }
}

// MARK: - Gains & Losses tab

private struct GainsLossesTab: View {
    let store: PortfolioStore
    /// Ticker filter from the page header. Empty = all.
    let filter: Set<String>

    /// Filtering the SOURCE arrays means every metric, readout, legend
    /// and chart below inherits the filter for free.
    private var trades: [OptionTradeRow] {
        filter.isEmpty ? store.allTrades : store.allTrades.filter { filter.contains($0.ticker) }
    }
    private var sells: [ShareSellRow] {
        filter.isEmpty ? store.allShareSells : store.allShareSells.filter { filter.contains($0.ticker) }
    }

    @State private var scope: ChartScope = .month        // Default: Month
    @State private var offset: Int = 0
    enum Mode: String, CaseIterable, Identifiable {
        case source = "Source", net = "Net"
        var id: String { rawValue }
    }
    @State private var mode: Mode = .source
    @State private var active: Set<FlowSource> = Set(FlowSource.allCases)
    @State private var selected: Int? = nil

    private var dataset: ChartDataset {
        PerformanceData.sourceBars(
            scope: scope,
            offset: offset,
            allTrades: trades,
            shareSells: sells
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            scopePicker
            periodRow
            metrics
            readout
            chartPanel
            sourceLegend
        }
        .onChange(of: scope) { _, _ in
            withAnimation(Motion.standard) {
                selected = nil
                offset = 0
            }
        }
    }

    // ── Week | Month | Year ──
    private var scopePicker: some View {
        PerfSegmented(
            selection: $scope,
            options: ChartScope.allCases,
            label: { $0.rawValue },
            style: .full
        )
        .padding(.top, 4)
    }

    // ── ‹ April 2026 › · spacer · Source/Net ──
    private var periodRow: some View {
        HStack(spacing: 8) {
            navButton(symbol: "chevron.left") { offset -= 1; selected = nil }
            Text(dataset.period)
                .font(.ui(size: 15, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(Color.theme.fg1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            navButton(symbol: "chevron.right") { offset += 1; selected = nil }
            Spacer(minLength: 8)
            // .fixedSize prevents the parent HStack from compressing
            // the Source/Net segmented and forcing the labels to wrap.
            PerfSegmented(
                selection: $mode,
                options: Mode.allCases,
                label: { $0.rawValue },
                style: .fit
            )
            .fixedSize()
        }
    }

    @ViewBuilder
    private func navButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.theme.fg2)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.theme.surface)
                        .overlay(Circle().strokeBorder(Color.theme.borderBright, lineWidth: 1))
                )
        }
        .buttonStyle(.pressable)
    }

    // ── ↑ Gains   ↓ Losses ──
    private var metrics: some View {
        let bar = selected.flatMap { idx -> SourceBar? in
            guard dataset.bars.indices.contains(idx) else { return nil }
            return dataset.bars[idx]
        }
        let gains: Double
        let losses: Double
        if let b = bar {
            gains = b.gain(active: active)
            losses = b.loss(active: active)
        } else {
            gains = dataset.bars.reduce(0) { $0 + $1.gain(active: active) }
            losses = dataset.bars.reduce(0) { $0 + $1.loss(active: active) }
        }

        return HStack(alignment: .top, spacing: 14) {
            metricCell(arrow: "arrow.up", arrowTone: .theme.pos, label: "Gains",
                       value: gains, valueTone: .theme.pos)
            metricCell(arrow: "arrow.down", arrowTone: .theme.neg, label: "Losses",
                       value: losses, valueTone: .theme.neg)
        }
    }

    @ViewBuilder
    private func metricCell(arrow: String, arrowTone: Color, label: String, value: Double, valueTone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: arrow)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(arrowTone)
                Text(label)
                    .font(.numeric(size: 11))
                    .foregroundStyle(Color.theme.fg3)
            }
            // Signed format — gains render as "+$X", losses as "−$X"
            // (the value coming in is already signed: gain is positive,
            // loss is negative). Matches the design's m-v.pos / m-v.neg.
            Text(fmtMoney(value, sign: true))
                .font(.ui(size: 28, weight: .heavy))
                .tracking(-0.8)
                .foregroundStyle(value == 0 ? Color.theme.fg4 : valueTone)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ── Single mono line: "Net ±$X" or "selected day · Net ±$X" ──
    private var readout: some View {
        let bar = selected.flatMap { idx -> SourceBar? in
            guard dataset.bars.indices.contains(idx) else { return nil }
            return dataset.bars[idx]
        }
        let net = (bar?.net(active: active))
            ?? dataset.bars.reduce(0) { $0 + $1.net(active: active) }
        return HStack(spacing: 8) {
            if let b = bar {
                Text(b.sub)
                    .font(.numeric(size: 12, weight: .medium))
                    .foregroundStyle(Color.theme.fg1)
                Text("tap again to clear")
                    .font(.numeric(size: 11))
                    .foregroundStyle(Color.theme.fg4)
                Spacer(minLength: 4)
            } else {
                Spacer(minLength: 0)
            }
            Text("Net ")
                .font(.numeric(size: 12))
                .foregroundStyle(Color.theme.fg3)
            + Text(fmtMoney(net, sign: true))
                .font(.numeric(size: 12, weight: .semibold))
                .foregroundStyle(net >= 0 ? Color.theme.pos : Color.theme.neg)
        }
        .frame(minHeight: 22)
    }

    // ── Sage chart panel (page-2 fill). GAINS / LOSSES zone labels are
    //    rendered as siblings of the chart — pinned to the top and
    //    bottom of the panel padding — so they're never covered by
    //    bars (the previous in-plot overlay clashed with tall bars).
    //
    //    Horizontal swipe gesture flips the period — left = next
    //    (offset += 1), right = prev (offset -= 1). Vertical drags
    //    still win for outer scrolling.
    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GAINS")
                .font(.ui(size: 9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Color.theme.fg4)

            PerfBarChart(
                bars: dataset.bars,
                active: active,
                mode: mode,
                scope: scope,
                maxPosition: dataset.maxPosition,
                selected: $selected
            )
            .frame(height: 220)
            // Implicit animation on data + mode + filter changes.
            // Swift Charts interpolates bar heights / opacity smoothly
            // when the underlying dataset shifts.
            .animation(Motion.easeOut, value: dataset.bars)
            .animation(Motion.standard, value: mode)
            .animation(Motion.standard, value: active)

            Text("LOSSES")
                .font(.ui(size: 9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Color.theme.fg4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(Color.theme.page2)
        )
        // Swipe to change period. Threshold tuned so vertical-only
        // drags (outer scroll) and chart taps aren't intercepted.
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.4, abs(dx) > 60 else { return }
                    withAnimation(Motion.standard) {
                        offset += dx < 0 ? 1 : -1
                        selected = nil
                    }
                }
        )
    }

    // ── Source legend / filters (or Net key in Net mode) ──
    @ViewBuilder
    private var sourceLegend: some View {
        if mode == .net {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.theme.pos)
                        .frame(width: 9, height: 9)
                    Text("Net gain")
                        .font(.numeric(size: 11))
                        .foregroundStyle(Color.theme.fg3)
                }
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.theme.neg)
                        .frame(width: 9, height: 9)
                    Text("Net loss")
                        .font(.numeric(size: 11))
                        .foregroundStyle(Color.theme.fg3)
                }
                Spacer()
            }
            .padding(.top, 10)
        } else {
            let totals = sourceTotals
            // 2-column grid keeps the chips uniform width on iPhone.
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(FlowSource.allCases, id: \.self) { src in
                    sourceChip(src, total: totals[src] ?? 0)
                }
            }
            .padding(.top, 14)
        }
    }

    /// Per-source totals across all bars in the dataset (regardless of
    /// whether that source is currently active) — used by the legend
    /// chip's right-side number.
    private var sourceTotals: [FlowSource: Double] {
        var out: [FlowSource: Double] = [:]
        for b in dataset.bars {
            for (k, v) in b.vals { out[k, default: 0] += v }
        }
        return out
    }

    @ViewBuilder
    private func sourceChip(_ src: FlowSource, total: Double) -> some View {
        // Uniform-width chips (driven by LazyVGrid 2-col), 44pt minimum
        // hit-target, single-line text with both name AND value shrinking
        // together via minimumScaleFactor so neither wraps.
        let isActive = active.contains(src)
        Button {
            withAnimation(Motion.standard) {
                if isActive { active.remove(src) } else { active.insert(src) }
                selected = nil
            }
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(src.color)
                    .frame(width: 9, height: 9)
                Text(src.shortLabel)
                    .font(.numeric(size: 11))
                    .foregroundStyle(Color.theme.fg1)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(fmtMoney(total, sign: true, decimals: 0))
                    .font(.numeric(size: 11))
                    .foregroundStyle(
                        total > 0 ? Color.theme.pos
                            : total < 0 ? Color.theme.neg
                            : Color.theme.fg4
                    )
                    .lineLimit(1)
            }
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(
                Capsule()
                    .fill(isActive ? Color.theme.surface : Color.theme.page2)
                    .overlay(
                        Capsule().strokeBorder(
                            isActive ? Color.theme.borderBright : Color.theme.borderBright.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1, dash: isActive ? [] : [3, 3])
                        )
                    )
            )
            .opacity(isActive ? 1.0 : 0.55)
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Source palette + labels

extension FlowSource {
    /// Color used in the chart stack and the legend swatch.
    var color: Color {
        switch self {
        case .shares:      return Color.theme.neon       // deep teal
        case .callsSold:   return Color.theme.oi         // blue
        case .callsBought: return Color.theme.earnings   // violet
        case .putsSold:    return Color.theme.gold       // gold
        case .putsBought:  return Color.theme.note       // magenta
        }
    }
    /// Short label for the legend chip.
    var shortLabel: String {
        switch self {
        case .shares:      return "Shares"
        case .callsSold:   return "Calls Sold"
        case .callsBought: return "Calls Bought"
        case .putsSold:    return "Puts Sold"
        case .putsBought:  return "Puts Bought"
        }
    }
    /// Stable order on the chart x-axis stack.
    static let stackOrder: [FlowSource] = [.shares, .callsSold, .callsBought, .putsSold, .putsBought]
}

// MARK: - Bar chart (Swift Charts)

/// Diverging stacked bar chart. Positive segments grow up from zero,
/// negative segments grow down. Each segment colored by source. Tap a
/// bar to select; tap again to clear.
///
/// Bars are placed at calendar POSITIONS (day-of-week / day-of-month
/// / month-of-year) on a fixed x-domain. With 1 event-day in a month,
/// you see one thin bar at its actual position with the rest of the
/// month as empty slots — bar width never grows to fill the chart.
private struct PerfBarChart: View {
    let bars: [SourceBar]
    let active: Set<FlowSource>
    let mode: GainsLossesTab.Mode
    let scope: ChartScope
    let maxPosition: Int
    @Binding var selected: Int?

    /// Flat per-segment points for Swift Charts. `position` is the
    /// 1-based calendar slot inside the period.
    private struct Segment: Identifiable {
        let id: String
        let position: Int
        let barIdx: Int
        let source: FlowSource?  // nil = net
        let value: Double
    }

    private var segments: [Segment] {
        if mode == .net {
            return bars.enumerated().map { (i, b) in
                Segment(id: "\(i)-net", position: b.position, barIdx: i,
                        source: nil, value: b.net(active: active))
            }
        }
        var out: [Segment] = []
        for (i, b) in bars.enumerated() {
            for src in FlowSource.stackOrder where active.contains(src) {
                let v = b.vals[src] ?? 0
                if v == 0 { continue }
                out.append(Segment(id: "\(i)-\(src.rawValue)", position: b.position,
                                   barIdx: i, source: src, value: v))
            }
        }
        return out
    }

    /// Calendar positions that should show an x-axis tick. Month view
    /// thins to every-7th-day (~6,13,20,27); week and year show every
    /// slot.
    private var tickPositions: [Int] {
        switch scope {
        case .week:  return Array(1...maxPosition)
        case .month:
            // 6, 13, 20, 27 if maxPosition >= 28; clamp to bounds.
            let cands = [6, 13, 20, 27, maxPosition]
            return Array(Set(cands.filter { $0 >= 1 && $0 <= maxPosition })).sorted()
        case .year:  return Array(1...12)
        }
    }

    private func tickLabel(for pos: Int) -> String {
        switch scope {
        case .week:
            let days = ["M", "T", "W", "T", "F", "S", "S"]
            return days[max(0, min(6, pos - 1))]
        case .month:
            return "\(pos)"
        case .year:
            let months = ["J","F","M","A","M","J","J","A","S","O","N","D"]
            return months[max(0, min(11, pos - 1))]
        }
    }

    var body: some View {
        if bars.isEmpty {
            HStack {
                Spacer()
                Text("No realized P&L in this window.")
                    .font(.ui(size: 13, weight: .medium))
                    .foregroundStyle(Color.theme.fg3)
                Spacer()
            }
            .frame(height: 220)
        } else {
            chartBody
        }
    }

    // Fixed bar width — bars stay this thick at any scope. With 7
    // positions (week) the chart looks airier; with 30 (month) they
    // pack tightly. Either way bar width never grows to fill the panel.
    private let barWidthPt: CGFloat = 8

    private var chartBody: some View {
        baseChart
            .chartBackground { proxy in lossWash(proxy: proxy) }
            .chartXScale(domain: 0.5...(Double(maxPosition) + 0.5))
            .chartXAxis { xAxisMarks }
            .chartYAxis { yAxisMarks }
    }

    // ── Broken-out chart pieces (keeps Swift's type-checker fast) ──

    private var baseChart: some View {
        Chart {
            ForEach(segments) { seg in
                BarMark(
                    x: .value("Position", seg.position),
                    y: .value("PnL", seg.value),
                    width: .fixed(barWidthPt)
                )
                .foregroundStyle(color(for: seg))
                .opacity(selected == nil || selected == seg.barIdx ? 1.0 : 0.32)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            RuleMark(y: .value("Zero", 0))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .foregroundStyle(Color.theme.fg3.opacity(0.7))
        }
        // Tap detection on the chart body.
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plot = proxy.plotFrame else { return }
                        let frame = geo[plot]
                        let x = location.x - frame.origin.x
                        guard x >= 0, x <= frame.width, !bars.isEmpty else { return }
                        // Tapped position on the calendar axis.
                        let frac = max(0, min(0.999, x / frame.width))
                        let tappedPos = Double(maxPosition) * frac + 0.5
                        // Snap to the nearest bar (within ±0.6 slots).
                        var bestIdx: Int? = nil
                        var bestDist = Double.infinity
                        for (i, b) in bars.enumerated() {
                            let d = abs(Double(b.position) - tappedPos)
                            if d < bestDist { bestDist = d; bestIdx = i }
                        }
                        guard let idx = bestIdx, bestDist <= 0.8 else {
                            selected = nil; return
                        }
                        selected = (selected == idx) ? nil : idx
                    }
            }
        }
    }

    // Coral wash across the loss zone (below the zero line).
    @ViewBuilder
    private func lossWash(proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            if let plot = proxy.plotFrame,
               let zeroY = proxy.position(forY: 0.0) {
                let frame = geo[plot]
                let h = max(0, frame.height - zeroY)
                Rectangle()
                    .fill(Color.theme.neg.opacity(0.045))
                    .frame(width: frame.width, height: h)
                    .position(x: frame.midX, y: frame.minY + zeroY + h / 2)
            }
        }
    }

    private var xAxisMarks: AxisMarks<some AxisMark> {
        AxisMarks(values: tickPositions) { value in
            if let pos = value.as(Int.self) {
                AxisValueLabel {
                    Text(tickLabel(for: pos))
                        .font(.numeric(size: 9))
                        .foregroundStyle(
                            isTickSelected(pos: pos) ? Color.theme.neon : Color.theme.fg4
                        )
                }
            }
        }
    }

    private var yAxisMarks: AxisMarks<some AxisMark> {
        AxisMarks(position: .trailing) { value in
            AxisGridLine().foregroundStyle(Color.theme.fg5.opacity(0.6))
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text(formatYAxisLabel(v))
                        .font(.numeric(size: 9))
                        .foregroundStyle(
                            abs(v) < 0.001 ? Color.theme.fg3 : Color.theme.fg4
                        )
                }
            }
        }
    }

    private func color(for seg: Segment) -> Color {
        if mode == .net {
            return seg.value >= 0 ? Color.theme.pos : Color.theme.neg
        }
        return seg.source?.color ?? Color.theme.fg4
    }

    /// True if the tick position matches the currently-selected bar.
    private func isTickSelected(pos: Int) -> Bool {
        guard let s = selected, bars.indices.contains(s) else { return false }
        return bars[s].position == pos
    }

    /// Compact $-format for Y-axis ticks. $5,432 → "$5.43k"; 0 → "0".
    /// Sign drops because the up/down zone is already conveyed by the
    /// GAINS / LOSSES labels.
    private func formatYAxisLabel(_ v: Double) -> String {
        if abs(v) < 0.5 { return "0" }
        let abs = Swift.abs(v)
        if abs >= 1_000_000 {
            return String(format: "$%.1fM", abs / 1_000_000)
        }
        if abs >= 1_000 {
            // 2-decimal under $10k, 1-decimal at/above (matches design's $5.00k).
            let decimals = abs >= 10_000 ? 1 : 2
            return String(format: "$%.\(decimals)fk", abs / 1_000)
        }
        return String(format: "$%.0f", abs)
    }
}

// MARK: - Leaderboard tab

private struct LeaderboardTab: View {
    let store: PortfolioStore
    /// Ticker filter from the page header. Empty = all.
    let filter: Set<String>

    private func keep(_ ticker: String) -> Bool {
        filter.isEmpty || filter.contains(ticker)
    }

    /// Lifetime-realized ranking. Combines open companies + closed
    /// companies so a fully-exited winner still shows up.
    private var ranked: [StockPerf] {
        let lifetime = PerformanceData.lifetimeStocks(
            companies: (store.companies + store.closedCompanies).filter { keep($0.ticker) },
            allTrades: store.allTrades.filter { keep($0.ticker) },
            shareSells: store.allShareSells.filter { keep($0.ticker) },
            shareLots: store.allShareLots.filter { keep($0.ticker) }
        )
        return lifetime.sorted { $0.realized > $1.realized }
    }
    private var winners: Int { ranked.filter { $0.realized >= 0 }.count }
    private var losers: Int  { ranked.count - winners }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Text("NOT PERIOD-BOUND")
                .font(.ui(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.theme.fg4)

            if ranked.isEmpty {
                Text("No realized P&L yet.")
                    .font(.ui(size: 13))
                    .foregroundStyle(Color.theme.fg3)
                    .padding(.top, 10)
            } else {
                VStack(spacing: 11) {
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { (i, p) in
                        LeaderboardCard(rank: i + 1, perf: p, sector: sector(for: p.ticker))
                    }
                }
            }
        }
    }

    private func sector(for ticker: String) -> String {
        (store.companies + store.closedCompanies)
            .first(where: { $0.ticker == ticker })?.sector ?? ""
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Leaderboard")
                    .font(.ui(size: 22, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Color.theme.fg1)
                Text("By realized P&L")
                    .font(.numeric(size: 11))
                    .foregroundStyle(Color.theme.fg3)
            }
            Spacer()
            HStack(spacing: 6) {
                upDownPill(count: winners, label: "up", tint: Color.theme.pos, bg: Color.theme.tintPos)
                upDownPill(count: losers,  label: "down", tint: Color.theme.neg, bg: Color.theme.tintNeg)
            }
        }
    }

    @ViewBuilder
    private func upDownPill(count: Int, label: String, tint: Color, bg: Color) -> some View {
        Text("\(count) \(label)")
            .font(.numeric(size: 10))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(bg))
    }
}

private struct LeaderboardCard: View {
    let rank: Int
    let perf: StockPerf
    let sector: String

    /// Realized-only since unrealized was removed from the card — that
    /// also matches the leaderboard's ranking criterion ("By realized
    /// P&L"), so the headline number now agrees with the sort.
    private var total: Double { perf.realized }
    private var isWinner: Bool { perf.realized >= 0 }

    var body: some View {
        HStack(spacing: 0) {
            // Left rank rail.
            Text("\(rank)")
                .font(.numeric(size: 15, weight: .medium))
                .foregroundStyle(isWinner ? Color.theme.neon : Color.theme.neg)
                .frame(width: 40)
                .frame(maxHeight: .infinity)
                .background(isWinner ? Color.theme.tintNeon : Color.theme.tintNeg)
                .overlay(
                    Rectangle()
                        .fill(isWinner
                              ? Color.theme.neon.opacity(0.16)
                              : Color.theme.neg.opacity(0.16))
                        .frame(width: 1),
                    alignment: .trailing
                )

            VStack(alignment: .leading, spacing: 0) {
                // Top row — ticker + sector ⟂ total + % return.
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(perf.ticker)
                                .font(.ui(size: 21, weight: .heavy))
                                .tracking(-0.5)
                                .foregroundStyle(Color.theme.fg1)
                                .lineLimit(1)
                            if perf.closed {
                                // Inline "CLOSED" badge — small mono caps
                                // pill. Paired with a slight opacity drop
                                // on the whole card below so closed
                                // positions are scannable at a glance.
                                Text("CLOSED")
                                    .font(.ui(size: 9, weight: .bold))
                                    .tracking(1.0)
                                    .foregroundStyle(Color.theme.fg3)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(Color.theme.tintMuted)
                                            .overlay(Capsule().strokeBorder(Color.theme.borderBright, lineWidth: 1))
                                    )
                            }
                        }
                        if !sector.isEmpty {
                            Text(sector)
                                .font(.numeric(size: 10))
                                .foregroundStyle(Color.theme.fg3)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    // Right-aligned: realized $ (fg1 ink) with ROI %
                    // below (signed color). ROI = realized / lifetime
                    // cost basis — true realized-only, no unrealized
                    // leakage. Nil for tickers with no share lots
                    // (pure options-only) where there's no basis.
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(fmtMoney(total, sign: true))
                            .font(.numeric(size: 17, weight: .medium))
                            .tracking(-0.2)
                            .foregroundStyle(Color.theme.fg1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let roi = perf.realizedROI {
                            Text("ROI \(fmtPct(roi))")
                                .font(.numeric(size: 11))
                                .foregroundStyle(roi >= 0 ? Color.theme.pos : Color.theme.neg)
                        }
                    }
                }

                // Hairline + 4-col stats.
                Rectangle()
                    .fill(Color.theme.hair)
                    .frame(height: 1)
                    .padding(.top, 14)
                    .padding(.bottom, 13)
                // 3-col stats (Unrealized dropped per design tweak).
                HStack(alignment: .top, spacing: 8) {
                    statCell(label: "Realized",
                             value: fmtMoney(perf.realized, sign: true, decimals: 0),
                             tone: perf.realized >= 0 ? Color.theme.pos : Color.theme.neg)
                    statCell(label: "Net price",
                             value: fmtMoney(perf.netPrice, sign: false, decimals: 0),
                             tone: Color.theme.fg1)
                    statCell(label: "Avg cost",
                             value: fmtMoney(perf.avgPrice, sign: false, decimals: 0),
                             tone: Color.theme.fg4)
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(Color.theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl)
                        .strokeBorder(Color.theme.borderBright, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .shadow(color: Color.cardGrad.glow, radius: 8, x: 0, y: 2)
        // Subtle dim on closed positions so the live book is the
        // visual lead. The CLOSED badge gives the precise signal;
        // this just changes the weight.
        .opacity(perf.closed ? 0.72 : 1.0)
    }

    @ViewBuilder
    private func statCell(label: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.ui(size: 9, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.theme.fg3)
            Text(value)
                .font(.numeric(size: 13, weight: .medium))
                .tracking(-0.1)
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - PerfSegmented — design-spec segmented control
//
// Surface thumb on a subtle dark track, matchedGeometry slide, two
// presentation styles:
//   .full — full-width (Week | Month | Year)
//   .fit  — content-fit, padding-around-content (Source | Net)

private struct PerfSegmented<T: Hashable & Identifiable>: View {
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String

    enum Style { case full, fit }
    let style: Style

    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { opt in
                let active = selection == opt
                Button {
                    withAnimation(Motion.standard) { selection = opt }
                } label: {
                    Text(label(opt))
                        .font(.ui(size: style == .full ? 13 : 12.5,
                                  weight: active ? .bold : .semibold))
                        .tracking(-0.1)
                        .foregroundStyle(active ? Color.theme.fg1 : Color.theme.fg2)
                        .padding(.horizontal, style == .full ? 0 : 14)
                        .padding(.vertical, style == .full ? 8 : 6)
                        .frame(
                            maxWidth: style == .full ? .infinity : nil,
                            minHeight: style == .full ? 32 : 28
                        )
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.theme.surface)
                                    .shadow(color: Color.cardGrad.glow.opacity(0.6),
                                            radius: 2, x: 0, y: 1)
                                    .matchedGeometryEffect(id: "perfSegThumb-\(style)", in: thumb)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(Color.theme.tintMuted)
        )
    }
}
