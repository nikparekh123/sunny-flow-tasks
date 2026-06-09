//
//  TradesActivityTab.swift
//  Sunnyfi
//
//  Date-grouped trade ledger for the Activity tab. Pulls from the
//  existing `ActivityFeed.dailyGroups(...)` data layer and presents
//  it in the new design's vertical feed style:
//
//    All dates ›        ← date filter pill (right-aligned)
//    [All | Open | Closed]   ← segmented filter w/ counts
//    TODAY · JUN 2
//      META $630 call    OPEN     +$1,410
//      5 calls closed              ↑ colored
//      …
//

import SwiftUI

struct TradesActivityTab: View {
    let store: PortfolioStore
    /// Tap-through — receives the row's ticker so the parent screen can
    /// open the per-ticker modal (lots / trades context).
    var onTapRow: (ActivityRow) -> Void = { _ in }

    @State private var statusFilter: ActivityStatus? = nil  // nil = All
    @State private var dateFilter: Date? = nil
    @State private var showDatePicker = false

    // ── Counts ──
    private var totalCounts: (all: Int, open: Int, closed: Int) {
        let groups = ActivityFeed.dailyGroups(
            trades: store.allTrades,
            shareSells: store.allShareSells,
            shareLots: store.allShareLots,
            dateFilter: dateFilter
        )
        var open = 0, closed = 0
        for g in groups {
            for r in g.rows {
                if r.status == .open { open += 1 } else { closed += 1 }
            }
        }
        return (open + closed, open, closed)
    }

    private var filteredGroups: [ActivityDayGroup] {
        let raw = ActivityFeed.dailyGroups(
            trades: store.allTrades,
            shareSells: store.allShareSells,
            shareLots: store.allShareLots,
            dateFilter: dateFilter
        )
        guard let s = statusFilter else { return raw }
        return raw
            .map { g in
                ActivityDayGroup(day: g.day, label: g.label,
                                 rows: g.rows.filter { $0.status == s })
            }
            .filter { !$0.rows.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            datePickerRow
            segmentedFilter
            feed
        }
        .sheet(isPresented: $showDatePicker) {
            ActivityDatePicker(selected: $dateFilter)
                .presentationDetents([.medium])
        }
    }

    // ── Date filter pill (right-aligned) ──
    private var datePickerRow: some View {
        HStack {
            Spacer()
            Button { showDatePicker = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.theme.fg3)
                    Text(dateFilterLabel)
                        .font(.numeric(size: 11, weight: .medium))
                        .tracking(0.2)
                        .foregroundStyle(Color.theme.fg2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.theme.fg4)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.theme.surface)
                        .overlay(Capsule().strokeBorder(Color.theme.borderBright, lineWidth: 1))
                )
            }
            .buttonStyle(.pressable)
        }
    }

    private var dateFilterLabel: String {
        guard let d = dateFilter else { return "All dates" }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: d)
    }

    // ── Segmented filter ──
    @Namespace private var segNS
    private var segmentedFilter: some View {
        let counts = totalCounts
        return HStack(spacing: 4) {
            segChip(label: "All",    count: counts.all,    target: nil)
            segChip(label: "Open",   count: counts.open,   target: .open)
            segChip(label: "Closed", count: counts.closed, target: .closed)
        }
        .padding(4)
        .background(
            Capsule().fill(Color.theme.page2)
        )
    }

    @ViewBuilder
    private func segChip(label: String, count: Int, target: ActivityStatus?) -> some View {
        let active = statusFilter == target
        Button {
            withAnimation(Motion.standard) { statusFilter = target }
        } label: {
            HStack(spacing: 7) {
                Text(label)
                    .font(.ui(size: 13, weight: active ? .bold : .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(active ? Color.theme.onNeon : Color.theme.fg2)
                Text("\(count)")
                    .font(.numeric(size: 11, weight: .medium))
                    .foregroundStyle(active ? Color.theme.onNeon.opacity(0.82) : Color.theme.fg4)
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.vertical, 4)
            .background {
                if active {
                    Capsule()
                        .fill(Color.theme.neon)
                        .matchedGeometryEffect(id: "activitySeg", in: segNS)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // ── Feed ──
    private var feed: some View {
        VStack(alignment: .leading, spacing: 0) {
            if filteredGroups.isEmpty {
                Text("No activity yet.")
                    .font(.numeric(size: 13))
                    .foregroundStyle(Color.theme.fg3)
                    .padding(.top, 24)
            } else {
                ForEach(filteredGroups) { g in groupBlock(g) }
            }
        }
    }

    @ViewBuilder
    private func groupBlock(_ g: ActivityDayGroup) -> some View {
        Text(g.label.uppercased())
            .font(.numeric(size: 9, weight: .semibold))
            .tracking(2.2)
            .foregroundStyle(Color.theme.fg3)
            .padding(.top, 16)
            .padding(.bottom, 6)
            .padding(.horizontal, 2)
        ForEach(g.rows) { r in
            row(r)
            Rectangle()
                .fill(Color.theme.fg5.opacity(0.6))
                .frame(height: 1)
                .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func row(_ r: ActivityRow) -> some View {
        Button {
            onTapRow(r)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 9) {
                        Text(r.asset)
                            .font(.ui(size: 16, weight: .bold))
                            .tracking(-0.2)
                            .foregroundStyle(Color.theme.fg1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        statusPill(r.status)
                    }
                    Text(r.action)
                        .font(.numeric(size: 12))
                        .foregroundStyle(Color.theme.fg3)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(r.valueText)
                    .font(.numeric(size: 17, weight: .medium))
                    .foregroundStyle(r.isPositive ? Color.theme.pos : Color.theme.neg)
                    .lineLimit(1)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusPill(_ s: ActivityStatus) -> some View {
        let (ink, bg, border): (Color, Color, Color) = {
            switch s {
            case .open:   return (Color.theme.pos, Color.theme.tintPos, Color.theme.pos.opacity(0.45))
            case .closed: return (Color.theme.fg3, Color.theme.page2,   Color.theme.borderBright)
            }
        }()
        Text(s.rawValue)
            .font(.numeric(size: 8.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(bg)
                    .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            )
    }
}

// MARK: - Date picker sheet (minimal)

private struct ActivityDatePicker: View {
    @Binding var selected: Date?
    @State private var local: Date = Date()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("Pick a date", selection: $local, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .padding()
                Spacer()
            }
            .navigationTitle("Activity date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("All dates") { selected = nil; dismiss() }
                        .foregroundStyle(Color.theme.fg3)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { selected = local; dismiss() }
                        .foregroundStyle(Color.theme.neon)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
