//
//  HomeView.swift
//  Sunny
//
//  The one Home page, in Home order: status and the account (01, 02, 02b),
//  the deck (03-07), quick nav (08), Today (09), then Book · Risk · Income ·
//  Results. 20 pt margins, 20 between blocks, the screen gradient under
//  everything, live every 30 s while a session runs.
//

import SwiftUI

struct HomeView: View {
    let store: HomeStore
    @State private var router = HomeRouter()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduce
    // Pull to refresh (block 25): how far the page is pulled past the top,
    // the phase, and the space held open while it fetches.
    @State private var pull: CGFloat = 0
    @State private var phase: PullPhase = .idle
    @State private var hold: CGFloat = 0
    @State private var shown = false
    @State private var touching = false

    var body: some View {
        ZStack {
            SBackground()
            if let home = store.home {
                #if DEBUG
                if let g = DebugPreset.gallery {
                    GalleryHost(block: g, store: store, home: home)
                        .environment(\.livePulse, store.livePulse)
                } else {
                    page(home)
                        .opacity(shown ? 1 : 0)
                        .onAppear { withAnimation(.easeOut(duration: 0.5)) { shown = true } }
                }
                #else
                page(home)
                    .opacity(shown ? 1 : 0)
                    .onAppear { withAnimation(.easeOut(duration: 0.5)) { shown = true } }
                #endif
            } else if store.loadError != nil {
                HomeUnavailable(store: store)
            } else {
                SunriseLoading().transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
            // The toast's slide animates the toast alone: on the page it also
            // animated every card change from the same update, and the cards
            // jumped (Nik, 14 Oct 2026).
            ZStack(alignment: .top) {
                if let t = store.toast {
                    SunnyToast(text: t)
                        .padding(.top, 4)
                        .transition(reduce ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(.easeOut(duration: 0.3), value: store.toast)
            .zIndex(8)
            if let home = store.home, router.writes != nil {
                SunnyPlanner(home: home, words: store.words ?? home)
                    .transition(reduce ? .opacity : .move(edge: .trailing))   // Reduce Motion: fades, no slides
                    .zIndex(9)
            }
            if let home = store.home, let r = router.receipt {
                receipt(r, home)
                    .transition(reduce ? .opacity : .move(edge: .bottom))
                    .zIndex(10)
            }
        }
        .environment(router)
        .onAppear(perform: debugOpen)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.live()
        }
    }

    private func page(_ home: HomePayload) -> some View {
        let words = store.words ?? home
        return ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: hold)
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        StatusLine(store: store).padding(.horizontal, S.margin)
                        AccountChart(home: home)
                    }
                    .sEnter(0)
                    SunnyDeck(cards: DeckBuilder.cards(home), today: home.today) { act(action: $0) }
                        .padding(.horizontal, S.margin)
                        .sEnter(1)
                    SunnyQuickNav { s in
                        withAnimation(S.standard(0.6)) { proxy.scrollTo(s, anchor: .top) }
                    }
                    .sEnter(2)
                    SunnySectionTitle(title: "Today").id("today")
                    SunnyToday(home: home).sEnter(3)

                    SunnySectionTitle(title: "Book").id(HomeRouter.Section.book)
                    SunnyPortfolio(home: home, words: words)
                        .padding(.horizontal, S.margin)
                        .id("portfolio")
                        .sEnter(4)
                    SunnyPositions(home: home, orderFrom: words)
                        .id("positions")
                        .sEnter(5)
                    SunnyInventory(home: home, words: words)
                        .padding(.horizontal, S.margin)
                        .id("inventory")
                        .sEnter(6)

                    SunnySectionTitle(title: "Risk").id(HomeRouter.Section.risk)
                    SunnyRisk(home: home).id("risk")

                    SunnySectionTitle(title: "Income").id(HomeRouter.Section.income)
                    SunnyYield(home: home, words: words).padding(.horizontal, S.margin).id("yield")
                    SunnyPayback(home: home, words: words).padding(.horizontal, S.margin).id("payback")

                    SunnySectionTitle(title: "Results").id(HomeRouter.Section.results)
                    SunnySoldBought(home: home).padding(.horizontal, S.margin).id("svb")
                    SunnyPerformance(words: words).padding(.horizontal, S.margin).id("performance")
                    SunnyAllocation(home: home, words: words).padding(.horizontal, S.margin).id("allocation")
                }
                .padding(.top, 14)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { -($0.contentOffset.y + $0.contentInsets.top) } action: { _, v in
                pull = max(0, v)
                guard phase == .idle || phase == .pulling || phase == .armed else { return }
                if phase == .armed && !touching { Task { await pullRefresh() }; return }
                // Only a finger arms it; the bounce back never does.
                if touching { phase = pull >= 110 ? .armed : pull > 0 ? .pulling : .idle }
                else if pull <= 0 { phase = .idle }
            }
            .onScrollPhaseChange { _, new in
                touching = new == .interacting || new == .tracking
                if !touching, phase == .armed { Task { await pullRefresh() } }
            }
            .overlay(alignment: .top) {
                if pull + hold > 0 {
                    PullSunrise(pull: max(pull, hold), phase: phase)
                        .frame(height: pull + hold, alignment: .bottom)
                        .clipped()
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: router.scrollID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .top) }
            }
        }
        .environment(\.livePulse, store.livePulse)
        .environment(\.changedLegs, store.changedLegs)
    }

    /// Let go past 110: hold the sun open, fetch, say "Updated · just now",
    /// then set.
    private func pullRefresh() async {
        guard phase == .armed else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        phase = .refreshing
        withAnimation(S.standard(0.5)) { hold = 136 }
        await store.refresh(.pull)
        phase = .done
        try? await Task.sleep(for: .seconds(1))
        withAnimation(S.standard(0.5)) { hold = 0 }
        try? await Task.sleep(for: .milliseconds(500))
        phase = .idle
    }

    /// DEBUG simulator runs only: `-open report|theta|writes:TICKER` opens a
    /// state straight away, so every state can be screenshotted.
    private func debugOpen() {
        #if DEBUG && targetEnvironment(simulator)
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-open"), i + 1 < a.count else { return }
        let v = a[i + 1]
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if v == "report" { router.open(.report(0)) }
            else if v == "theta", let c = (store.home?.thetaChecks ?? []).first { router.open(.theta(c.leg)) }
            else if v.hasPrefix("writes:") { router.writes = String(v.dropFirst(7)) }
            else if v.hasPrefix("at:") { router.scrollID = String(v.dropFirst(3)) }
            else if v.hasPrefix("pick:") { router.debugPick = String(v.dropFirst(5)); router.scrollID = "positions" }
        }
        #endif
    }

    private func act(action: DeckCard.Action) {
        switch action {
        case .writes(let t): withAnimation(S.standard(0.45)) { router.writes = t }
        case .report(let i): router.open(.report(i))
        case .theta(let leg): router.open(.theta(leg))
        }
    }

    @ViewBuilder private func receipt(_ r: HomeRouter.Receipt, _ home: HomePayload) -> some View {
        switch r {
        case .report(let i):
            if let rep = home.deck.reports?[safe: i], let p = rep.period {
                SunnyReceipt(range: Self.range(rep, p), onClose: router.closeReceipt) {
                    ReportPaper(report: rep, today: home.today)
                }
            }
        case .theta(let leg):
            let all = (home.thetaChecks ?? []) + (home.deck.thetaChecks ?? [])
            if let c = all.first(where: { $0.leg == leg }) {
                SunnyReceipt(range: "THETA CHECK · \(R.weekdayDay(c.foundOn))", onClose: router.closeReceipt) {
                    ThetaPaper(check: c, calendar: home.calendar)
                }
            }
        }
    }

    /// "WK 41 · OCT 5 - 9" · "SEPTEMBER · SEP 1 - 30"
    static func range(_ r: Deck.Report, _ p: Deck.Report.Period) -> String {
        let to = DeckBuilder.lastTrading(onOrBefore: p.to)
        let end = p.from.prefix(7) == to.prefix(7) ? DeckBuilder.dayNum(to) : R.day(to)
        if r.kind == "monthly" {
            let m = Int(p.from.dropFirst(5).prefix(2)) ?? 1
            return "\(DeckBuilder.months[m - 1].uppercased()) · \(R.day(p.from)) - \(DeckBuilder.dayNum(p.to))"
        }
        return "WK \(r.mark) · \(R.day(p.from)) - \(end)"
    }
}

/// No good update yet and the fetch failed: say so plainly, offer a retry.
struct HomeUnavailable: View {
    let store: HomeStore
    var body: some View {
        VStack(spacing: 14) {
            Text("Can't reach Sunny").sType(.headline, tabular: false).foregroundStyle(S.ink)
            Text("Check the connection and try again.").sType(.body, tabular: false).foregroundStyle(S.muted)
            Button { Task { await store.refresh() } } label: {
                Text("Try again").sType(.label, tabular: false).foregroundStyle(S.ink)
                    .padding(.horizontal, 18).frame(height: 36)
                    .glassEffect(.regular, in: .capsule)
            }
            .buttonStyle(SPressStyle())
        }
        .padding(S.margin)
    }
}
