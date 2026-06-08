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
    @State private var sheetFull: Bool = false
    @State private var pins = TodayPinStore.shared

    private var allItems: [TodayItem] { TodayData.compute(store: store) }
    private var pinnedItems: [TodayItem] {
        // Preserve user's pin order.
        pins.pinnedIds.compactMap { id in
            allItems.first(where: { $0.id == id })
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

                    Headline(count: rankedItems.count)
                        .padding(.horizontal, 22)
                        .padding(.top, pinnedItems.isEmpty ? 18 : 22)

                    LazyVStack(spacing: 0) {
                        ForEach(Array(rankedItems.enumerated()), id: \.element.id) { idx, item in
                            if idx > 0 {
                                Rectangle()
                                    .fill(Color.theme.hair)
                                    .frame(height: 1)
                                    .padding(.horizontal, 22)
                            }
                            TodayRow(
                                idx: idx + 1,
                                item: item,
                                isLead: idx == 0,
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
            set: { if !$0 { openItemId = nil; sheetFull = false } }
        )) {
            if let id = openItemId, let item = allItems.first(where: { $0.id == id }) {
                TodaySheet(
                    item: item,
                    full: $sheetFull,
                    isPinned: pins.isPinned(item.id),
                    onPin:  { pins.toggle(item.id) },
                    onClose: { openItemId = nil; sheetFull = false }
                )
                .presentationDetents(sheetFull ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.theme.elevated)
            }
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

            // Single concatenated Text so "{N} things that matter today"
            // flows as one sentence — wraps as one block, just with the
            // leading number bolder + tighter (matches the spec's <h1>
            // with inline <span class="hero-n">).
            (
                Text("\(count)")
                    .font(.system(size: 30, weight: .heavy))
                    .tracking(-1.35)
                +
                Text(" things that matter today")
                    .font(.system(size: 30, weight: .light))
                    .tracking(-0.6)
            )
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
                HStack(spacing: 12) {
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
            .frame(width: 270, height: 154, alignment: .topLeading)
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
                            .font(.system(
                                size: isLead ? 38 : 30,
                                weight: .semibold,
                                design: .monospaced
                            ))
                            .tracking(-1)
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
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.theme.neon)
                            Text(item.category.uppercased())
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .tracking(1.6)
                                .foregroundStyle(Color.theme.fg3)
                        }
                        Text(item.name)
                            .font(.system(
                                size: isLead ? 19 : 17,
                                weight: .semibold
                            ))
                            .foregroundStyle(Color.theme.fg1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(item.sub)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.theme.fg3)
                            .lineLimit(1)
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
    @Binding var full: Bool
    let isPinned: Bool
    let onPin: () -> Void
    let onClose: () -> Void

    private var visibleRows: [DetailRow] {
        full ? item.detailRows : Array(item.detailRows.prefix(3))
    }
    private var hiddenCount: Int { max(0, item.detailRows.count - 3) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Head
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
                        Text(item.detailSub)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.theme.fg3)
                            .padding(.top, 2)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button(action: onPin) {
                            HStack(spacing: 6) {
                                Image(systemName: isPinned ? "pin.fill" : "pin")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(isPinned ? "Tracking" : "Track")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .tracking(0.4)
                            }
                            .foregroundStyle(isPinned ? Color.white : Color.theme.neon)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 38)         // spec min-height
                            .background(
                                Capsule().fill(isPinned ? Color.theme.neon : Color.theme.neon.opacity(0.09))
                            )
                            .overlay(
                                Capsule().stroke(Color.theme.neon.opacity(isPinned ? 1 : 0.32), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
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
                }

                // Hero
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(item.num)
                        .font(.system(size: 54, weight: .semibold, design: .monospaced))
                        .tracking(-1.9)
                        .foregroundStyle(toneColor(item.tone))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("\(item.unit.lowercased()) · \(item.short)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.theme.fg3)
                }
                .padding(.top, 18)

                Text(item.line)
                    .font(.system(size: 13.5))
                    .lineSpacing(4)
                    .foregroundStyle(Color.theme.fg2)
                    .padding(.top, 14)

                // List head + toggle
                HStack {
                    Text(full ? "THE FULL LIST" : "TOP OF THE LIST")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(Color.theme.fg3)
                    Spacer()
                    if hiddenCount > 0 {
                        Button(action: { full.toggle() }) {
                            Text(full ? "Show less" : "View all \(item.detailRows.count) →")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Color.theme.neon)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 18)
                .padding(.bottom, 4)

                // Rows
                VStack(spacing: 0) {
                    ForEach(Array(visibleRows.enumerated()), id: \.offset) { idx, r in
                        if idx > 0 {
                            Rectangle()
                                .fill(Color.theme.hair)
                                .frame(height: 1)
                        }
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(r.name)
                                    .font(.system(size: 14.5, weight: .medium))
                                    .foregroundStyle(Color.theme.fg1)
                                Text(r.sub)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Color.theme.fg3)
                            }
                            Spacer()
                            Text(r.value)
                                .font(.system(size: 16, weight: .medium, design: .monospaced))
                                .foregroundStyle(toneColor(r.tone))
                        }
                        .padding(.vertical, 13)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
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
