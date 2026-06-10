//
//  TradesScreen.swift
//  Sunnyfi
//
//  Positions screen — full rebuild against Positions Handoff 2.
//  Shell, top to bottom:
//
//   • Compact header: iOS-native segmented control (Positions /
//     Activity) on the LEFT, a small Open-call-credit stat on the
//     RIGHT. NO big "Positions" title (it duplicated the tab).
//   • Ticker filter pills (All + per-ticker).
//   • Content:
//       Positions tab — Open-call-credit CARD (All view only) on
//       top, then one unified TickerCard per ticker.
//       Activity tab — existing TradesActivityTab.
//   • Trade pill bottom-right that expands into Option / Shares /
//     ✕ pills over a dim backdrop.
//
//  Routing:
//   • Trade pill → Option → TradeSheet(.option)
//   • Trade pill → Shares → TradeSheet(.shares)
//   • Swipe-left Close on a leg → TradeSheet pre-filled to close
//   • "Likely assignment · log it →" CTA → AssignmentSheet
//

import SwiftUI

struct TradesScreen: View {
    let store: PortfolioStore
    let auth: AuthStore

    @State private var tab: TradesTab = .positions
    /// nil = "All"; otherwise the symbol of the active ticker pill.
    @State private var tickerFilter: String? = nil

    /// Driven by both the FAB and per-leg routing. Non-nil = full-
    /// screen TradeSheet is visible.
    @State private var tradePreset: TradePresetWrap? = nil
    /// Non-nil = AssignmentSheet is visible.
    @State private var assignmentTrade: TradeWrap? = nil
    /// Active page in the hedge carousel ("calls" or "puts"). String
    /// IDs so the binding survives even when one of the cards
    /// disappears (e.g. user closes all short calls — the carousel
    /// still works for the remaining Puts card).
    @State private var hedgeCardPage: String? = "calls"
    /// Hedge funding sheet — opens from the "Funds hedge" row on
    /// Open call credit. Bool because the sheet renders portfolio-
    /// level data, no per-row context to carry.
    @State private var showHedgeFunding: Bool = false
    /// Downside Protection sheet — opens from "Net cost" row on
    /// Open puts bought. Portfolio-wide view of how each long put
    /// shelters the share book against drawdown.
    @State private var showDownsideProtection: Bool = false
    /// Break-even sheet — opens from "Effective basis" row on Open
    /// shares. Per-lot recovery view using lifetime-adjusted basis.
    @State private var showBreakeven: Bool = false
    /// Non-nil = per-ticker lot/trade admin sheet is visible
    /// (Edit on a shares leg routes here).
    @State private var editStockTicker: TickerWrap? = nil

    /// Local view-state for the expanding Trade pill menu.
    @State private var tradeMenuOpen = false

    enum TradesTab: String, CaseIterable, Identifiable, Hashable {
        case positions = "Positions"
        case activity  = "Activity"
        var id: String { rawValue }
    }

    // ── Derived ─────────────────────────────────────────────────
    private var allSummaries: [TickerSummary] {
        TradesData.buildSummaries(store: store)
    }
    private var summaries: [TickerSummary] {
        guard let t = tickerFilter else { return allSummaries }
        return allSummaries.filter { $0.ticker == t }
    }
    private var openCallCredit: Double {
        TradesData.openCallCredit(store: store)
    }
    private var openCallCreditNow: Double {
        TradesData.openCallCreditNow(store: store)
    }
    private var openCallCreditTimeValue: Double {
        TradesData.openCallCreditTimeValue(store: store)
    }
    private var openPutsPaid: Double {
        TradesData.openPutsPaid(store: store)
    }
    private var openPutsValueNow: Double {
        TradesData.openPutsValueNow(store: store)
    }
    private var openPutsTimeValue: Double {
        TradesData.openPutsTimeValue(store: store)
    }

    // ── Hedge / cross-book figures (design_handoff_hedge_rows) ─────
    private var openSharesCost: Double { TradesData.openSharesCost(store: store) }
    private var openSharesValueNow: Double { TradesData.openSharesValue(store: store) }
    private var openSharesTodayPnL: Double { TradesData.openSharesTodayPnL(store: store) }
    private var fundedPct: Int { TradesData.fundedPct(store: store) }
    private var hedgeSurplus: Double { TradesData.hedgeSurplus(store: store) }
    private var hedgeNetCost: Double { TradesData.netCost(store: store) }
    private var hedgeNetCostBookPct: Double { TradesData.netCostBookPct(store: store) }
    private var effectiveBasis: Double { TradesData.effectiveBasis(store: store) }
    private var effectiveBasisPct: Double { TradesData.effectiveBasisPct(store: store) }
    private var hasPuts: Bool { TradesData.hasPuts(store: store) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // ONLY the segmented control stays pinned. The
                // "Open positions" header + ticker pills live INSIDE
                // the ScrollView so they scroll away as the user
                // moves down (matches the design's pin behavior).
                compactHeader
                contentArea
            }
            // Trade pill hidden by default (IBKR Flex sync is primary).
            // Re-enable via Settings → "Manual entry (use sparingly)"
            // for out-of-broker fills or when IBKR sync is paused.
            if AppPrefs.shared.manualEntryEnabled {
                tradePillStack
            }
        }
        .background(Color.theme.page)
        .fullScreenCover(item: $tradePreset) { wrap in
            TradeSheet(store: store,
                       preset: wrap.preset,
                       onDismiss: { tradePreset = nil })
        }
        .fullScreenCover(item: $assignmentTrade) { wrap in
            AssignmentSheet(store: store,
                            trade: wrap.trade,
                            onDismiss: { assignmentTrade = nil })
        }
        .sheet(isPresented: $showHedgeFunding) {
            HedgeFundingSheet(
                callCredit: openCallCredit,
                putPaid: openPutsPaid,
                fundedPct: fundedPct,
                hedgeSurplus: hedgeSurplus,
                netCost: hedgeNetCost,
                putRows: TradesData.hedgePutRows(store: store),
                creditRows: TradesData.hedgeCreditRows(store: store),
                putGain: TradesData.putGain(store: store),
                onClose: { showHedgeFunding = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.theme.elevated)
        }
        .sheet(isPresented: $showDownsideProtection) {
            DownsideProtectionSheet(
                store: store,
                onClose: { showDownsideProtection = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.theme.elevated)
        }
        .sheet(isPresented: $showBreakeven) {
            BreakevenSheet(
                store: store,
                onClose: { showBreakeven = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.theme.elevated)
        }
        // Stock-leg swipe → Edit. Opens the per-ticker admin sheet
        // on the lots tab so the user can fix a bad cost basis.
        .sheet(item: $editStockTicker) { wrap in
            TickerTradesSheet(store: store, ticker: wrap.ticker, initialTab: .lots)
                .presentationDetents([.large])
        }
    }

    // MARK: Compact header

    /// Custom segmented control — light grey track with neon-filled
    /// active capsule + white text. Replaces the iOS-native
    /// `Picker(.segmented)` which renders a white-on-grey active
    /// state that doesn't match the design.
    private var compactHeader: some View {
        HStack(spacing: 0) {
            segmentedTab(.positions)
            segmentedTab(.activity)
        }
        .padding(4)
        .background(
            Capsule().fill(Color.theme.page2)
        )
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    /// Sized to match the Performance tab's Gains/Leaderboard
    /// segmented control exactly: 14pt bold/semibold, minHeight 32,
    /// `padding(.vertical, 4)`. Outer `padding(4)` on the container
    /// matches too.
    @ViewBuilder
    private func segmentedTab(_ t: TradesTab) -> some View {
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
                            .matchedGeometryEffect(id: "topTab", in: topTabNS)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @Namespace private var topTabNS

    /// "Open positions" heading + count on the right. Matches the
    /// design's chrome between the segmented control and the
    /// ticker pills.
    private var openPositionsHeader: some View {
        let count = allSummaries.count
        return HStack(alignment: .lastTextBaseline) {
            Text("Open positions")
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.66)        // -.03em × 22
                .foregroundStyle(Color.theme.fg1)
            Spacer(minLength: 0)
            Text("\(count) position\(count == 1 ? "" : "s")")
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Color.theme.labelMuted)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: Ticker pills

    private var tickerPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                pill(label: "All", active: tickerFilter == nil) {
                    withAnimation(Motion.standard) { tickerFilter = nil }
                }
                ForEach(allSummaries) { s in
                    pill(label: s.ticker, active: tickerFilter == s.ticker) {
                        withAnimation(Motion.standard) {
                            tickerFilter = tickerFilter == s.ticker ? nil : s.ticker
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
        }
    }

    @ViewBuilder
    private func pill(label: String, active: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label)
                .font(.system(size: 13, weight: active ? .bold : .semibold))
                .tracking(0.4)
                .foregroundStyle(active ? Color.theme.onNeon : Color.theme.fg2)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .frame(minHeight: 42)
                .background(
                    Capsule()
                        .fill(active ? Color.theme.neon : Color.theme.surface)
                        .overlay(
                            Capsule().strokeBorder(
                                active ? Color.clear : Color.theme.borderBright,
                                lineWidth: 1
                            )
                        )
                )
        }
        .buttonStyle(.pressable)
    }

    // MARK: Content area

    @ViewBuilder
    private var contentArea: some View {
        if tab == .positions {
            positionsTab
        } else {
            // TradesActivityTab is a plain VStack — without a
            // ScrollView wrapper it overflows beyond the screen and
            // its top rows render under the status bar. Wrap it
            // here so vertical scroll works and content is properly
            // clipped under the chrome above.
            ScrollView {
                TradesActivityTab(store: store, onTapRow: { _ in })
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 120)   // clear FAB + tab bar
            }
            .refreshable {
                await store.refresh()
            }
        }
    }

    @ViewBuilder
    private var positionsTab: some View {
        ScrollView {
            // "Open positions / N positions" + ticker pills live
            // INSIDE the scroll so they slide up out of view as the
            // user moves down — the segmented control above remains
            // the only persistent chrome. Both bring their own
            // horizontal padding so they don't inherit the inner
            // VStack's 18pt inset.
            openPositionsHeader
            tickerPills
                .padding(.bottom, 14)
            VStack(spacing: 11) {
                // Hedge carousel — paged swipe between
                // Calls Sold (income) and Puts Bought (hedge).
                // Both render with the same Paid/Value/TimeValue
                // structure so they swap cleanly. Only shown in
                // All view (§4).
                if tickerFilter == nil && (openCallCredit > 0 || openPutsPaid > 0) {
                    hedgeCarousel
                }

                if summaries.isEmpty {
                    emptyState
                } else {
                    ForEach(summaries) { s in
                        TickerCard(
                            summary: s,
                            store: store,
                            onCloseLeg: { trade in
                                let remaining = store.remainingContracts(for: trade)
                                tradePreset = TradePresetWrap(
                                    preset: .closingOption(trade, remaining: remaining)
                                )
                            },
                            onCloseStock: { ticker in
                                let qty = store.companies
                                    .first(where: { $0.ticker == ticker })?
                                    .legs.first(where: { $0.kind == .stock })?.qty ?? 0
                                tradePreset = TradePresetWrap(
                                    preset: .closingShares(ticker: ticker, qty: qty)
                                )
                            },
                            onEditLeg: { trade in
                                // Edit path uses the SAME new
                                // TradeSheet as open/close — with
                                // `editingTradeId` set so save()
                                // routes to updateTrade. Avoids the
                                // old EditTradeSheet UI, keeps the
                                // user in one consistent ticket.
                                tradePreset = TradePresetWrap(
                                    preset: .editingOption(trade)
                                )
                            },
                            onEditStock: { ticker in
                                // Stock edits live in the per-ticker
                                // lot admin sheet — opens on the
                                // .lots tab so the user can fix a
                                // cost-basis mistake at the lot level.
                                editStockTicker = TickerWrap(ticker: ticker)
                            },
                            onAssign: { trade in
                                assignmentTrade = TradeWrap(trade: trade)
                            }
                        )
                    }
                }
                // Bottom padding to clear the FAB + docked tab bar.
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
        }
        .refreshable {
            await store.refresh()
        }
    }

    /// Paged carousel — Calls Sold (id: "calls") ↔ Puts Bought
    /// (id: "puts"). Uses iOS 17's native `ScrollView` paging
    /// with `containerRelativeFrame(.horizontal)`, which is much
    /// smoother than `TabView(.page)`. TabView reserves layout
    /// space for its built-in indicator even when hidden — that
    /// space fight + card shadow rendering is what made the swipe
    /// feel jerky.
    private var hedgeCarousel: some View {
        let hasCalls = openCallCredit > 0
        let hasPutsLocal = openPutsPaid > 0
        let hasShares = openSharesCost > 0
        let pageCount = (hasCalls ? 1 : 0) + (hasPutsLocal ? 1 : 0) + (hasShares ? 1 : 0)

        return VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    if hasCalls {
                        OpenCallCard(collected: openCallCredit,
                                     valueNow: openCallCreditNow,
                                     timeValue: openCallCreditTimeValue,
                                     hasPuts: hasPutsLocal,
                                     fundedPct: fundedPct,
                                     hedgeSurplus: hedgeSurplus,
                                     onHedge: { showHedgeFunding = true })
                            .containerRelativeFrame(.horizontal)
                            .id("calls")
                    }
                    if hasPutsLocal {
                        OpenPutsBoughtCard(paid: openPutsPaid,
                                           valueNow: openPutsValueNow,
                                           timeValue: openPutsTimeValue,
                                           netCost: hedgeNetCost,
                                           netCostBookPct: hedgeNetCostBookPct,
                                           onProtection: { showDownsideProtection = true })
                            .containerRelativeFrame(.horizontal)
                            .id("puts")
                    }
                    if hasShares {
                        OpenSharesCard(cost: openSharesCost,
                                       effectiveBasis: effectiveBasis,
                                       effectiveBasisPct: effectiveBasisPct,
                                       valueNow: openSharesValueNow,
                                       todayPnL: openSharesTodayPnL,
                                       onBreakeven: { showBreakeven = true })
                            .containerRelativeFrame(.horizontal)
                            .id("shares")
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $hedgeCardPage)
            // Default clip kept — `.scrollClipDisabled()` was
            // letting the off-screen next card bleed into view on
            // the right edge, which read as a broken layout.

            // Custom dots — only when there's something to switch
            // between. One dot per active page, in the same order
            // as the cards above. Tappable as a fallback for users
            // who don't discover the swipe.
            if pageCount > 1 {
                HStack(spacing: 8) {
                    if hasCalls { dot(id: "calls") }
                    if hasPutsLocal { dot(id: "puts") }
                    if hasShares { dot(id: "shares") }
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func dot(id: String) -> some View {
        let active = hedgeCardPage == id
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                hedgeCardPage = id
            }
        } label: {
            Capsule()
                .fill(active ? Color.theme.neon : Color.theme.fg4.opacity(0.4))
                .frame(width: active ? 18 : 7, height: 7)   // active = pill, inactive = dot
                .animation(.easeInOut(duration: 0.25), value: active)
                .padding(8)                                  // generous hit target
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text(tickerFilter == nil
                 ? "No open positions yet."
                 : "No positions for \(tickerFilter ?? "")")
                .font(.system(size: 13))
                .foregroundStyle(Color.theme.fg3)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    // MARK: Trade pill (expanding menu)

    /// Bottom-right Trade pill. Collapsed: a single accent pill that
    /// reads "Trade". Expanded: a stack of pills (Option / Shares /
    /// ✕) growing up from the bottom with a dim backdrop. Per §7.
    /// Bottom pill is ALWAYS rendered; its label/action toggles
    /// between "Trade" (closed) and "✕" (open). Option and Shares
    /// are conditionally rendered ABOVE it with bottom-edge slide-
    /// in transitions. This keeps the bottom anchor visually fixed
    /// so the "Trade" → "✕" swap reads as one button morphing
    /// rather than two separate elements appearing/disappearing.
    private var tradePillStack: some View {
        ZStack(alignment: .bottomTrailing) {
            if tradeMenuOpen {
                Color.theme.fg1.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            tradeMenuOpen = false
                        }
                    }
                    .transition(.opacity)
            }
            VStack(alignment: .trailing, spacing: 11) {
                if tradeMenuOpen {
                    pillButton("Option", style: .filled) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            tradeMenuOpen = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            // Pre-select the active filter ticker (if
                            // any). On "All" view, tickerFilter is nil
                            // → user picks from pills as usual.
                            tradePreset = TradePresetWrap(
                                preset: .openOption(ticker: tickerFilter)
                            )
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    pillButton("Shares", style: .filled) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            tradeMenuOpen = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            tradePreset = TradePresetWrap(
                                preset: .openShares(ticker: tickerFilter)
                            )
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                }
                // Persistent anchor — swaps text only. Stays in the
                // same on-screen position so the morph reads as one
                // object changing.
                pillButton(
                    tradeMenuOpen ? "✕" : "Trade",
                    style: tradeMenuOpen ? .outlined : .filled
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        tradeMenuOpen.toggle()
                    }
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, 80)
        }
    }

    private enum PillStyle { case filled, outlined }

    @ViewBuilder
    private func pillButton(_ label: String,
                            style: PillStyle,
                            tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(style == .filled ? Color.theme.onNeon : Color.theme.neon)
                .frame(width: 168, height: 42)
                .background(
                    Capsule()
                        .fill(style == .filled ? Color.theme.neon : Color.theme.surface)
                        .overlay(
                            Capsule().strokeBorder(
                                style == .outlined ? Color.theme.neon : Color.clear,
                                lineWidth: 1.5
                            )
                        )
                )
                .shadow(color: Color.theme.neon.opacity(0.35),
                        radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Sheet item wrappers

private struct TradePresetWrap: Identifiable {
    let id = UUID()
    let preset: TradePreset
}
private struct TradeWrap: Identifiable {
    let trade: OptionTradeRow
    var id: String { trade.id }
}
/// Identifiable wrapper so a String ticker can drive a sheet item
/// binding.
private struct TickerWrap: Identifiable {
    let ticker: String
    var id: String { ticker }
}
