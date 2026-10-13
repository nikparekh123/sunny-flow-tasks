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

    var body: some View {
        ZStack {
            SBackground()
            if let home = store.home {
                page(home)
            } else if store.loadError != nil {
                HomeUnavailable(store: store)
            } else {
                SunriseLoading()
            }
            if let home = store.home, router.writes != nil {
                SunnyWritesSheet(home: home, ticker: Bindable(router).writes)
                    .transition(.move(edge: .trailing))
                    .zIndex(9)
            }
            if let home = store.home, let r = router.receipt {
                receipt(r, home)
                    .transition(.move(edge: .bottom))
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
                    SunnyPositions(home: home)
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
            .refreshable { await store.refresh(.pull) }
            .onChange(of: router.scrollID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .top) }
            }
        }
        .environment(\.livePulse, store.livePulse)
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
