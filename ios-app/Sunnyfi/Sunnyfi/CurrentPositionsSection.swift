//
//  CurrentPositionsSection.swift
//  Sunnyfi
//
//  All open option legs, filtered + grouped by ticker. Each leg renders
//  as a PositionCardView with Edit / Close / Resolve actions.
//
//  Filters — three INDEPENDENT dimensions, AND-combined:
//    TYPE       Calls / Puts
//    DIRECTION  Sold / Bought   (short / long)
//    MONEYNESS  Soon / ITM / OTM
//
//  Tap any pill to set; tap the same pill again to clear that
//  dimension. Combined query is the intersection — so "Calls" + "Sold"
//  shows exactly the calls-sold set; "Calls" + "Sold" + "ITM" narrows
//  further to assignment-risk shorts.
//

import SwiftUI

struct CurrentPositionsSection: View {
    let store: PortfolioStore
    let onEdit: (OptionTradeRow) -> Void
    let onClose: (OptionTradeRow) -> Void
    let onResolve: (OptionTradeRow) -> Void

    @State private var filters: PositionFilters = .init()

    /// Selected filter dimensions. Nil = no filter on that axis.
    /// `sortBy` defaults to `.expiry` (the historical sort order).
    struct PositionFilters: Equatable {
        var kind: OptionKind? = nil
        var sortBy: SortBy = .expiry
        var ticker: String? = nil

        var isEmpty: Bool {
            kind == nil && sortBy == .expiry && ticker == nil
        }

        mutating func clearAll() { self = .init() }
    }

    /// Type pill now collapses the previous Type + Direction axes into
    /// the four legal combinations. Order is intentional — Calls Sold
    /// (the most common trade we open) leads, Calls Bought (least
    /// common) trails.
    enum OptionKind: String, CaseIterable, Identifiable {
        case callsSold   = "Calls Sold"
        case putsBought  = "Puts Bought"
        case putsSold    = "Puts Sold"
        case callsBought = "Calls Bought"

        var id: String { rawValue }
        /// (option_type, direction) tuple matching the DB columns.
        var dbType: String {
            switch self {
            case .callsSold, .callsBought: return "call"
            case .putsSold, .putsBought:   return "put"
            }
        }
        var dbDirection: String {
            switch self {
            case .callsSold, .putsSold:   return "short"
            case .callsBought, .putsBought: return "long"
            }
        }
    }

    /// Combined sort order + moneyness lens. Mutually exclusive single-
    /// select — replaces the old MONEYNESS row. ITM / OTM act as
    /// filters; Expiry / By Gains / By Losses re-sort the full list.
    enum SortBy: String, CaseIterable, Identifiable {
        case expiry = "Expiry"
        case itm    = "ITM"
        case otm    = "OTM"
        case gains  = "By Gains"
        case losses = "By Losses"

        var id: String { rawValue }
    }

    /// Unique tickers across every open leg, sorted alphabetically.
    /// Drives the TICKER filter pill row.
    private var availableTickers: [String] {
        Array(Set(liveLegs.map(\.ticker))).sorted()
    }

    /// All opens that still have contracts active, sorted by DTE ascending.
    private var liveLegs: [OptionTradeRow] {
        store.allTrades
            .filter { $0.action == "open" && store.remainingContracts(for: $0) > 0 }
            .sorted { lhs, rhs in
                let l = AppDates.daysUntil(lhs.expiry) ?? Int.max
                let r = AppDates.daysUntil(rhs.expiry) ?? Int.max
                return l < r
            }
    }

    private var filteredLegs: [OptionTradeRow] {
        let filtered = liveLegs.filter { matches($0) }
        return sortedLegs(filtered)
    }

    private func matches(_ t: OptionTradeRow) -> Bool {
        if let tk = filters.ticker, t.ticker      != tk { return false }
        if let k = filters.kind,
           !(t.option_type == k.dbType && t.direction == k.dbDirection) { return false }
        // ITM / OTM are filters (the other sort modes don't narrow).
        switch filters.sortBy {
        case .itm:
            let s = store.spot(for: t.ticker)
            guard s > 0 else { return false }
            let isItm = t.option_type == "call" ? s >= t.strike : s <= t.strike
            if !isItm { return false }
        case .otm:
            let s = store.spot(for: t.ticker)
            guard s > 0 else { return false }
            let isOtm = t.option_type == "call" ? s < t.strike : s > t.strike
            if !isOtm { return false }
        case .expiry, .gains, .losses:
            break
        }
        return true
    }

    /// Apply the sort axis. ITM/OTM keep DTE-asc ordering inside the
    /// filter; Gains/Losses re-sort by live unrealized P&L.
    private func sortedLegs(_ legs: [OptionTradeRow]) -> [OptionTradeRow] {
        switch filters.sortBy {
        case .expiry, .itm, .otm:
            return legs.sorted { lhs, rhs in
                (AppDates.daysUntil(lhs.expiry) ?? Int.max)
                  < (AppDates.daysUntil(rhs.expiry) ?? Int.max)
            }
        case .gains:
            return legs.sorted { store.unrealizedPL(for: $0) > store.unrealizedPL(for: $1) }
        case .losses:
            return legs.sorted { store.unrealizedPL(for: $0) < store.unrealizedPL(for: $1) }
        }
    }

    /// Filtered legs grouped by ticker (preserving overall sort).
    private var grouped: [(ticker: String, legs: [OptionTradeRow])] {
        var seen: [String] = []
        var bucket: [String: [OptionTradeRow]] = [:]
        for t in filteredLegs {
            if bucket[t.ticker] == nil { seen.append(t.ticker) }
            bucket[t.ticker, default: []].append(t)
        }
        return seen.map { ($0, bucket[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            FilterPills(filters: $filters, tickers: availableTickers)

            // Extra breathing room before content.
            Color.clear.frame(height: 6)

            if filteredLegs.isEmpty {
                emptyState
            } else {
                // Each PositionCardView now embeds its own ticker
                // header (META · spot · N legs), so the per-ticker
                // grouping header has been dropped. We still group
                // legs by ticker so they stay visually adjacent.
                ForEach(grouped, id: \.ticker) { group in
                    VStack(spacing: 12) {
                        ForEach(group.legs, id: \.id) { t in
                            PositionCardView(
                                trade: t,
                                store: store,
                                onEdit: { onEdit(t) },
                                onClose: { onClose(t) },
                                onResolve: { onResolve(t) }
                            )
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Current positions")
                .font(.ui(size: 18, weight: .bold))
                .foregroundStyle(Color.theme.fg1)
            Spacer()
            Text(
                filters.isEmpty
                ? "\(liveLegs.count) leg\(liveLegs.count == 1 ? "" : "s")"
                : "\(filteredLegs.count) of \(liveLegs.count)"
            )
            .font(.numeric(size: 12))
            .foregroundStyle(Color.theme.fg3)
        }
    }

    @ViewBuilder
    private func tickerHeader(ticker: String, count: Int) -> some View {
        HStack {
            Text(ticker)
                .font(.ui(size: 13, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(Color.theme.fg2)
            Text("· \(count) leg\(count == 1 ? "" : "s")")
                .font(.numeric(size: 11))
                .foregroundStyle(Color.theme.fg3)
            Spacer()
            if store.spot(for: ticker) > 0 {
                Text("spot \(fmtMoney(store.spot(for: ticker)))")
                    .font(.numeric(size: 11))
                    .foregroundStyle(Color.theme.fg3)
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var emptyState: some View {
        Text(filters.isEmpty ? "No open option positions." : "No legs match this filter.")
            .font(.ui(size: 13))
            .foregroundStyle(Color.theme.fg3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: Radius.xl)
                    .strokeBorder(Color.theme.hair, lineWidth: 0.5)
            )
    }
}

// MARK: - Three-row composable filter pill rack
//
// Labelled rows of inline pills — TICKER (single-select scrollable),
// then TYPE / DIRECTION / MONEYNESS. Tap a pill to set; tap the same
// pill again to clear. AND-combined across dimensions. Reverted from
// the dropdown variant per user feedback.

private struct FilterPills: View {
    @Binding var filters: CurrentPositionsSection.PositionFilters
    /// Unique tickers across current open legs. Renders nothing if
    /// empty (no positions yet — no rows for the user to scroll past).
    let tickers: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !tickers.isEmpty {
                tickerRow
            }

            // TYPE collapses the old Type + Direction axes into the
            // four legal combinations (Calls Sold / Puts Bought / etc.).
            row(label: "TYPE", values: CurrentPositionsSection.OptionKind.allCases,
                isActive: { filters.kind == $0 },
                onPick:   { filters.kind = (filters.kind == $0) ? nil : $0 })

            // SORT BY is a single-select view lens — Expiry is the
            // default; ITM / OTM act as filters; Gains / Losses re-sort
            // by live P&L.
            row(label: "SORT BY", values: CurrentPositionsSection.SortBy.allCases,
                isActive: { filters.sortBy == $0 },
                onPick:   { filters.sortBy = (filters.sortBy == $0) ? .expiry : $0 })

            if !filters.isEmpty {
                Button {
                    withAnimation(Motion.standard) { filters.clearAll() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Clear filters")
                            .font(.ui(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.theme.fg3)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    /// Ticker row — one pill per held symbol. Single-select; tapping
    /// the active pill clears the filter. Horizontal-scrolls so 10+
    /// tickers don't crowd at narrow widths.
    @ViewBuilder
    private var tickerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("TICKER")
                .font(.ui(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Color.theme.fg3)
                .frame(width: 72, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tickers, id: \.self) { tk in
                        let active = filters.ticker == tk
                        Button {
                            filters.ticker = active ? nil : tk
                        } label: {
                            Text(tk)
                                .font(.numeric(size: 12, weight: .bold))
                                .foregroundStyle(active ? Color.theme.onNeon : Color.theme.fg2)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(active ? Color.theme.neon : Color.clear)
                                        .overlay(Capsule().strokeBorder(
                                            active ? Color.theme.neon : Color.theme.soft,
                                            lineWidth: 1))
                                )
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
        }
    }

    /// One labelled row of toggleable pills.
    @ViewBuilder
    private func row<T: RawRepresentable & Identifiable>(
        label: String,
        values: [T],
        isActive: @escaping (T) -> Bool,
        onPick: @escaping (T) -> Void
    ) -> some View where T.RawValue == String {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.ui(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Color.theme.fg3)
                .frame(width: 72, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(values) { v in
                        pill(label: v.rawValue, isActive: isActive(v)) { onPick(v) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pill(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.ui(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? Color.theme.onNeon : Color.theme.fg2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isActive ? Color.theme.neon : Color.clear)
                        .overlay(Capsule().strokeBorder(isActive ? Color.theme.neon : Color.theme.soft, lineWidth: 1))
                )
        }
        .buttonStyle(.pressable)
    }
}
