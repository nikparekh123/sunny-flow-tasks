//
//  IncomeTab.swift
//  Sunny
//
//  The Income tab (handoff 2026-11-24 late §1.1; Current App: SunnyIncome only banner, bvo m, then SunnyIncomeCal
//  head false, narrow, view m, views m, quiet fold), on the same background as Positions, under the account strip,
//  which scrolls away with the page as on the other tabs. Padding 120 16 128; its own scroll position. Top to bottom:
//  "Income" 28/34 bold with nothing under it, 18, the realized banner (Monthly only, opens on this month), 20, the
//  calendar. The calendar's ticker is kept for the session and goes back to All when the account changes (the
//  calendar follows the account strip: Together has both books' names).
//  The account switch dips the page as Home does (opacity .15 → 1 over .4 s, 28 pt over .5 s; Reduce Motion fades).
//

import SwiftUI

struct IncomeTab: View {
    @Environment(BriefState.self) private var brief
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce
    @AppStorage(BriefPrivacy.key) private var privacy = false
    @State private var pos = ScrollPosition()
    /// The calendar's ticker (per session); nil is All.
    @State private var tk: String?
    /// Where the calendar's top sits: in the page (to scroll to) and on the screen (to see if it is above the top).
    @State private var calTop = IncCalTop()
    @State private var faded = false
    @State private var slid = false
    @State private var dipDir: CGFloat = 0
    @State private var settling: Task<Void, Never>?

    static let space = "incomeTab"
    private var pageBook: BriefAccount { brief.account }
    private var pageReady: Bool { brief.book == nil || brief.book == pageBook.book }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if brief.showsStrip {
                    AccountStrip(accounts: brief.accounts, selected: brief.account) { a in brief.pick(a) }
                }
                page
                    .padding(.horizontal, 16)
                    // The page's first line at y 120, 4 under the strip (as Home's chart).
                    .padding(.top, brief.showsStrip ? 4 - AccountStrip.lift : 14)
                    .opacity(faded ? 0.15 : 1)
                    .offset(x: slid ? 28 * dipDir : 0)
            }
            .overlay(alignment: .topTrailing) { ActivityBellSlot() }
            .padding(.bottom, 128)
            .containerRelativeFrame(.horizontal)
            .coordinateSpace(.named(Self.space))
        }
        .scrollIndicators(.hidden)
        .scrollPosition($pos)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { calTop.top = $0 }
        .background(SBackground(glows: true))
        .overlay(alignment: .top) { BriefTopEdge() }
        // Tap the open tab: smooth to the top. Every rung on Home: open at the top.
        .onChange(of: router.topTick[.income]) { _, _ in withAnimation(S.moving(S.page, reduce)) { pos.scrollTo(edge: .top) } }
        .onChange(of: router.incomeTop) { _, _ in pos.scrollTo(edge: .top) }
        .onChange(of: pageBook) { _, _ in tk = nil; dip() }
        .onChange(of: pageReady) { _, ready in if ready && faded { settle(wait: false) } }
        .task {
            #if DEBUG && targetEnvironment(simulator)
            // Screens checked in the simulator: `-incPick NVDA` picks that ticker on the calendar's strip;
            // `-scroll 900` opens scrolled.
            let a = ProcessInfo.processInfo.arguments
            if let i = a.firstIndex(of: "-incPick"), i + 1 < a.count { try? await Task.sleep(for: .milliseconds(1200)); tk = a[i + 1] }
            if let y = BriefDebug.scroll { try? await Task.sleep(for: .milliseconds(1200)); pos.scrollTo(y: y) }
            #endif
        }
    }

    // MARK: The page

    @ViewBuilder private var page: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Income").sType(IncT.t(28, 34, 700, tr: -0.02), tabular: false).foregroundStyle(IncC.ink)
                .accessibilityAddTraits(.isHeader)
            if let m = brief.incomeModel, pageReady || brief.book == nil {
                content(m)
            } else if brief.income == nil && brief.live != nil {
                Text("Income shows here once Sunny’s server sends it.")
                    .sType(IncT.t(13, 18), tabular: false).foregroundStyle(IncC.mu)
            } else {
                ProgressView().controlSize(.regular).frame(maxWidth: .infinity).padding(.top, 60)
            }
        }
    }

    /// The banner, then 20 under it the calendar.
    private func content(_ m: IncModel) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let b = m.banner {
                IncBannerView(banner: b, privacy: privacy, accounts: brief.account == .together ? brief.split.map(\.name) : [])
                    .id("banner-\(brief.account.book)")
            }
            IncCalView(cal: m.cal, names: m.names, account: brief.account, closed: closedDays, tk: $tk) { t in
                tk = t
                bringCalendar()
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).minY } action: { calTop.y = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { calTop.screen = $0 }
        }
    }

    /// The market holidays in the app's calendar.
    private var closedDays: Set<String> {
        Set(brief.calendar.filter { $0.kind == "closed" }.map(\.date))
    }

    /// A name's line tapped far down the calendar: bring the calendar's top (the strip and the status line) to 96 pt
    /// under the screen's top, so the picked name shows; a calendar whose top is already on screen stays put.
    private func bringCalendar() {
        guard calTop.screen < 96 else { return }
        // The scroll position counts from the scroll view's own top (under the status bar, `top` on the screen).
        withAnimation(S.moving(S.page, reduce)) { pos.scrollTo(y: max(0, calTop.y - 96 + calTop.top)) }
    }

    // MARK: The account switch (Home's dip)

    private func dip() {
        guard brief.showsStrip else { return }
        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t) { dipDir = brief.switchDir; faded = true; slid = !reduce }
        settle(wait: !pageReady)
    }
    private func settle(wait: Bool) {
        settling?.cancel()
        settling = Task {
            try? await Task.sleep(for: .milliseconds(wait ? 1500 : 34))
            guard !Task.isCancelled else { return }
            withAnimation(S.switchFade) { faded = false }
            withAnimation(S.moving(S.switchMove, reduce)) { slid = false }
        }
    }
}

/// Income redraws from its own state and data, never because Home's parent did.
extension IncomeTab: Equatable {
    nonisolated static func == (_: IncomeTab, _: IncomeTab) -> Bool { true }
}

/// Where the calendar's top sits in the page and on the screen, and the scroll view's top on the screen: read on a
/// tap, never drawn.
final class IncCalTop {
    var y: CGFloat = 0
    var screen: CGFloat = 0
    var top: CGFloat = 0
}
