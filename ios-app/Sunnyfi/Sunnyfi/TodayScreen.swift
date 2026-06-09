//
//  TodayScreen.swift
//  Sunnyfi
//
//  The new "Today" landing tab. See design_handoff_today_homepage.
//
//  Structure:
//    BrandRow      — "SUNNYFI" wordmark + cursor + "Markets open"
//    Headline      — "Today · Tue Jun 8" + "5 things that matter today"
//    PinnedRail    — horizontal scroll of pinned narrative cards
//    RankedList    — 5 editorial rows from TodayData.compute()
//
//  Tap any row or pinned card → TodaySheet (bottom sheet).
//

import Combine
import SwiftUI

struct TodayScreen: View {

    @Bindable var store: PortfolioStore
    @State private var openItemId: String? = nil
    @State private var pins = TodayPinStore.shared
    @State private var ivPins = IVPinStore.shared

    /// Sheet state for the IV section.
    /// .scan = open the cross-portfolio scan list.
    /// .ticker(t) = open directly on the per-ticker detail view.
    @State private var ivSheet: IVSheetMode?

    enum IVSheetMode: Identifiable {
        case scan
        case ticker(String)
        var id: String { if case .ticker(let t) = self { return "iv:\(t)" } else { return "iv:scan" } }
    }

    /// Summary keyed by ticker for the tracker rail lookup.
    private var ivByTicker: [String: TickerIVRow] {
        Dictionary(uniqueKeysWithValues: store.allIvSummaries.map { ($0.ticker, $0) })
    }

    /// The single ticker featured in the in-list Volatility card.
    /// Top Seller Score wins. nil → don't render the card.
    private var featuredIvRow: TickerIVRow? {
        store.allIvSummaries
            .filter { IVMath.sellerScore($0) != nil }
            .max { (IVMath.sellerScore($0) ?? -1) < (IVMath.sellerScore($1) ?? -1) }
    }

    private var allItems: [TodayItem] { TodayData.compute(store: store) }
    private var pinnedItems: [TodayItem] {
        // Preserve user's pin order. Falls back to synthesizing a
        // TodayItem from store.macro/earnings rows when the pin is
        // an individual event id rather than a bucket id.
        let today = Date()
        return pins.pinnedIds.compactMap { id -> TodayItem? in
            if let direct = allItems.first(where: { $0.id == id }) { return direct }
            if id.hasPrefix("macro:") {
                let evId = String(id.dropFirst("macro:".count))
                if let ev = store.allMacroEvents.first(where: { $0.id == evId }) {
                    return TodayData.itemForMacroEvent(ev, today: today)
                }
            }
            if id.hasPrefix("earnings:") {
                let evId = String(id.dropFirst("earnings:".count))
                if let ev = store.allEarningsEvents.first(where: { $0.id == evId }) {
                    return TodayData.itemForEarnings(ev, today: today)
                }
            }
            // (iv:<TICKER> pins removed — IV pins now live in their own
            // store (IVPinStore) and render via IVTracker above the
            // headline, not in this Pinned rail.)
            return nil
        }
    }
    /// Top-N from the ranking, with pinned items removed (they're
    /// already shown above in the rail).
    private var rankedItems: [TodayItem] {
        let pinned = Set(pins.pinnedIds)
        return allItems
            .filter { !pinned.contains($0.id) }
            .prefix(TodayData.targetCount)
            .map { $0 }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BrandRow()
                        .padding(.horizontal, 22)
                        .padding(.top, 8)

                    if !pinnedItems.isEmpty {
                        PinnedRail(
                            items: pinnedItems,
                            onOpen: { id in openItemId = id },
                            onUnpin: { id in pins.unpin(id) }
                        )
                        .padding(.top, 18)
                    }

                    // "Tracking IV" chip rail — separate from regular
                    // Pinned. Only renders when ≥ 1 ticker is IV-pinned.
                    if !ivPins.pinnedTickers.isEmpty {
                        IVTrackerRail(
                            tickers: ivPins.pinnedTickers,
                            summary: ivByTicker,
                            onOpenTicker: { tk in ivSheet = .ticker(tk) }
                        )
                        .padding(.top, pinnedItems.isEmpty ? 18 : 16)
                    }

                    Headline(count: rankedItems.count + (featuredIvRow != nil ? 1 : 0))
                        .padding(.horizontal, 22)
                        .padding(.top, (pinnedItems.isEmpty && ivPins.pinnedTickers.isEmpty) ? 18 : 22)

                    LazyVStack(spacing: 0) {
                        // Volatility card always first in the list when
                        // we have any IV data to feature.
                        if let row = featuredIvRow {
                            IVMergedRow(
                                row: row,
                                isPinned: ivPins.isPinned(row.ticker),
                                onOpen: { ivSheet = .scan },
                                onPin: { ivPins.toggle(row.ticker) }
                            )
                            .padding(.horizontal, 22)
                        }

                        ForEach(Array(rankedItems.enumerated()), id: \.element.id) { idx, item in
                            if idx > 0 || featuredIvRow != nil {
                                Rectangle()
                                    .fill(Color.theme.hair)
                                    .frame(height: 1)
                                    .padding(.horizontal, 22)
                            }
                            TodayRow(
                                idx: idx + 1 + (featuredIvRow != nil ? 1 : 0),
                                item: item,
                                isLead: idx == 0 && featuredIvRow == nil,
                                isPinned: pins.isPinned(item.id),
                                onOpen: { openItemId = item.id },
                                onPin:  { pins.toggle(item.id) }
                            )
                            .padding(.horizontal, 22)
                        }
                    }
                    .padding(.top, 4)

                    Color.clear.frame(height: 120) // clear floating tab bar
                }
            }
            .refreshable { await store.refresh() }
            .background(Color.theme.page)
        }
        .sheet(isPresented: Binding(
            get: { openItemId != nil },
            set: { if !$0 { openItemId = nil } }
        )) {
            if let id = openItemId, let item = allItems.first(where: { $0.id == id }) {
                TodaySheet(
                    item: item,
                    pins: pins,
                    onClose: { openItemId = nil }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.theme.elevated)
            }
        }
        .sheet(item: $ivSheet) { mode in
            let initial: String? = {
                if case .ticker(let t) = mode { return t } else { return nil }
            }()
            IVSheet(
                summaries: store.allIvSummaries,
                initialTicker: initial,
                pins: ivPins,
                onClose: { ivSheet = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.theme.elevated)
        }
    }
}

// ───────────────────────────────────────────────────────────────
// MARK: - Brand row (top of screen)
// ───────────────────────────────────────────────────────────────

private struct BrandRow: View {
    @State private var cursorOn = true
    private let timer = Timer.publish(every: 0.55, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 3) {
                Text("SUNNYFI")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(Color.theme.neon)
                Rectangle()
                    .fill(Color.theme.neon)
                    .frame(width: 6, height: 13)
                    .opacity(cursorOn ? 1 : 0)
            }
            Spacer()
            MarketsOpenChip()
        }
        .onReceive(timer) { _ in cursorOn.toggle() }
    }
}

private struct MarketsOpenChip: View {
    private var isOpen: Bool {
        // Mon-Fri 9:30am-4:00pm ET — rough; doesn't account for early
        // closes (Thanksgiving etc.) but good enough for the chip.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let now = Date()
        let wd = cal.component(.weekday, from: now)  // 1=Sun, 7=Sat
        if wd == 1 || wd == 7 { return false }
        let h = cal.component(.hour, from: now)
        let m = cal.component(.minute, from: now)
        let mins = h * 60 + m
        return mins >= 9*60 + 30 && mins < 16*60
    }

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            // Live-dot: lime fill + soft halo that breathes every 2.5s
            // (spec: --tint-lime ring · pulse 2.5s var(--ease) infinite).
            ZStack {
                Circle()
                    .fill(Color.theme.lime.opacity(0.30))
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulse ? 1.0 : 0.5)
                    .opacity(pulse ? 0 : 0.6)
                    .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: false), value: pulse)
                Circle()
                    .fill(isOpen ? Color.theme.lime : Color.theme.fg4)
                    .frame(width: 6, height: 6)
            }
            .onAppear { if isOpen { pulse = true } }
            Text(isOpen ? "Markets open" : "Markets closed")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(Color.theme.fg3)
        }
    }
}

// ───────────────────────────────────────────────────────────────
// MARK: - Headline
// ───────────────────────────────────────────────────────────────

private struct Headline: View {
    let count: Int

    private var eyebrow: String {
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d"
        df.timeZone = TimeZone(identifier: "America/New_York")
        return "TODAY · \(df.string(from: Date()).uppercased())"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Color.theme.fg3)

            // "{N} things that matter today" — all one weight, New York
            // serif via design: .serif. No bold-emphasis on the count
            // (per user — the editorial weight comes from the serif
            // itself, not weight contrast).
            Text("\(count) things that matter today")
                .font(.system(size: 35, weight: .light, design: .serif))
                .tracking(-0.7)
                .foregroundStyle(Color.theme.fg1)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)

            Rectangle()
                .fill(Color.theme.neon)
                .frame(width: 38, height: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .padding(.top, 15)
        }
    }
}

// ───────────────────────────────────────────────────────────────
// MARK: - Pinned rail
// ───────────────────────────────────────────────────────────────

private struct PinnedRail: View {
    let items: [TodayItem]
    let onOpen: (String) -> Void
    let onUnpin: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.theme.neon)
                Text("PINNED · \(items.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Color.theme.fg3)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 11)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        PinCard(
                            item: item,
                            onOpen: { onOpen(item.id) },
                            onUnpin: { onUnpin(item.id) }
                        )
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 4)
            }
        }
    }
}

private struct PinCard: View {
    let item: TodayItem
    let onOpen: () -> Void
    let onUnpin: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(item.category.uppercased()) · \(item.short)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(Color.theme.fg3)

                    if let p = item.pinNarrative {
                        (
                            Text(p.lead) +
                            Text(p.value)
                                .foregroundColor(toneColor(item.tone))
                                .fontWeight(.bold) +
                            Text(p.tail)
                        )
                        .font(.system(size: 19, weight: .semibold))
                        .tracking(-0.38)            // -.02em × 19
                        .lineSpacing(6)              // line-height 1.32 × 19 ≈ 25 → ~6pt spacing
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(Color.theme.fg1)
                    } else {
                        Text(item.line)
                            .font(.system(size: 19, weight: .semibold))
                            .tracking(-0.38)
                            .lineSpacing(6)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(Color.theme.fg1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(EdgeInsets(top: 17, leading: 18, bottom: 46, trailing: 18))

                Button(action: onUnpin) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.theme.fg4)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 7)
                .padding(.bottom, 6)
            }
            // Width fixed for horizontal rail; height grows with the
            // narrative so the full sentence is always visible. minHeight
            // keeps the visual rhythm when the text happens to be short.
            .frame(width: 270, alignment: .topLeading)
            .frame(minHeight: 154)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.theme.elevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.theme.borderBright, lineWidth: 1)
            )
            // Matches spec --shadow-card: tight contact shadow + softer drop
            .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

// ───────────────────────────────────────────────────────────────
// MARK: - Ranked row (Editorial)
// ───────────────────────────────────────────────────────────────

private struct TodayRow: View {
    let idx: Int
    let item: TodayItem
    let isLead: Bool
    let isPinned: Bool
    let onOpen: () -> Void
    let onPin: () -> Void

    private var numRendered: String {
        // bigNum() from the JSX: round percentages, drop the +/- sign,
        // and keep the unit at the same size. Direction = color.
        let s = item.num
        // Match "+5.1%" or "−3.2%" etc.
        let pattern = #"^([+\-−]?)(\d+)\.(\d)\d*(%.*)$"#
        if let r = s.range(of: pattern, options: .regularExpression) {
            let parts = String(s[r])
            let scanner = Scanner(string: parts)
            scanner.charactersToBeSkipped = nil
            _ = scanner.scanCharacters(from: CharacterSet(charactersIn: "+-−"))
            let i = scanner.scanInt() ?? 0
            _ = scanner.scanString(".")
            let dec = scanner.scanInt() ?? 0
            let unit = scanner.scanCharacters(from: CharacterSet(charactersIn: "%abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ ")) ?? "%"
            let rounded = i + (dec >= 5 ? 1 : 0)
            return "\(rounded)\(unit)"
        }
        // Strip leading +/- sign for non-percent (e.g. "+$120")
        if s.first == "+" || s.first == "-" || s.first == "−" {
            return String(s.dropFirst())
        }
        return s
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button(action: onOpen) {
                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(numRendered)
                            .font(.system(size: 32, weight: .semibold))
                            .monospacedDigit()                  // tabular digits, SF Pro 0 (no slash) — matches Trades
                            .tracking(-1.0)
                            .foregroundStyle(toneColor(item.tone))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(item.unit)
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .tracking(0.8)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.theme.fg3)
                    }
                    .frame(minWidth: 80, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 9) {
                            Text(String(format: "%02d", idx))
                                .font(.system(size: 11, weight: .bold))
                                .monospacedDigit()                  // SF Pro tabular — matches the row number/sub font
                                .foregroundStyle(Color.theme.neon)
                            Text(item.category.uppercased())
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .tracking(1.6)
                                .foregroundStyle(Color.theme.fg3)
                        }
                        Text(item.name)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.theme.fg1)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Text(item.sub)
                            .font(.system(size: 14))
                            .monospacedDigit()
                            .foregroundStyle(Color.theme.fg3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 21)
                .padding(.trailing, 30)        // clears the absolute pin
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onPin) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isPinned ? Color.theme.neon : Color.theme.fg4)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .padding(.trailing, -4)
        }
    }
}

// ───────────────────────────────────────────────────────────────
// MARK: - Bottom sheet
// ───────────────────────────────────────────────────────────────

struct TodaySheet: View {
    let item: TodayItem
    @Bindable var pins: TodayPinStore
    let onClose: () -> Void

    // Show all rows always — no peek/full toggle. The sheet is
    // scrollable, so a longer list just scrolls naturally.
    private var visibleRows: [DetailRow] { item.detailRows }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Head — no top-level Tracking pill; pinning happens
                // per-row below (each event is independently pinnable).
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.category.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1.8)
                            .foregroundStyle(Color.theme.neon)
                        Text(item.detailTitle)
                            .font(.system(size: 26, weight: .bold))
                            .tracking(-0.78)
                            .foregroundStyle(Color.theme.fg1)
                            .lineLimit(2)
                        if !item.detailSub.isEmpty {
                            Text(item.detailSub)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.theme.fg3)
                                .padding(.top, 2)
                        }
                    }
                    Spacer()
                    Button(action: onClose) {
                        Text("✕")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.theme.fg3)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.theme.surface))
                            .overlay(Circle().stroke(Color.theme.borderBright, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                // Hero
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(item.num)
                        .font(.system(size: 40, weight: .semibold))
                        .monospacedDigit()         // SF Pro tabular 0 — matches Trades convention
                        .tracking(-1.4)            // -.035em × 40 ≈ -1.4
                        .foregroundStyle(toneColor(item.tone))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    // Subhead: just the short tag (HOUSING, etc.). The
                    // unit prefix ("today ·", "until ·") was redundant
                    // beside the hero num and got dropped per design.
                    Text(item.short)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.theme.fg3)
                }
                .padding(.top, 18)

                Text(item.line)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .foregroundStyle(Color.theme.fg2)
                    .padding(.top, 14)

                // Rows — each pinnable independently when `pinId` is
                // set (events / earnings). Other rows render without
                // a pin affordance.
                VStack(spacing: 0) {
                    ForEach(Array(visibleRows.enumerated()), id: \.offset) { idx, r in
                        if idx > 0 {
                            Rectangle()
                                .fill(Color.theme.hair)
                                .frame(height: 1)
                        }
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(r.name)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.theme.fg1)
                                Text(r.sub)
                                    .font(.system(size: 12))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.theme.fg3)
                            }
                            Spacer()
                            Text(r.value)
                                .font(.system(size: 20, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(toneColor(r.tone))
                            if let pinId = r.pinId {
                                Button {
                                    pins.toggle(pinId)
                                } label: {
                                    Image(systemName: pins.isPinned(pinId) ? "pin.fill" : "pin")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(pins.isPinned(pinId) ? Color.theme.neon : Color.theme.fg4)
                                        .frame(width: 30, height: 30)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 15)
                    }
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 22)
            .padding(.top, 45)        // breathing room below the grab handle
            .padding(.bottom, 32)
        }
    }
}

// ───────────────────────────────────────────────────────────────
// MARK: - Tone → Color
// ───────────────────────────────────────────────────────────────

private func toneColor(_ t: TodayTone) -> Color {
    switch t {
    case .pos:     return .theme.pos
    case .neg:     return .theme.neg
    case .neon:    return .theme.neon
    case .warn:    return .theme.warn
    case .neutral: return .theme.fg1
    }
}
