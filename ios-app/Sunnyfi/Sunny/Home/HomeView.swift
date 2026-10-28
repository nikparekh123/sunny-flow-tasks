//
//  HomeView.swift
//  Sunny
//
//  The app's two tabs (handoff 30, block 12a): Home and Positions, in the
//  native tab bar, each with its own scroll. Home in Home order: status and
//  the account (01, 02, 02b), the deck (03-07), quick nav (08), Today (09),
//  then Book · Risk · Income · Results. Positions is its own screen (12).
//  20 pt margins, 20 between blocks, the screen gradient under everything,
//  live every 30 s while a session runs.
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
    @State private var homePos = ScrollPosition()
    // Search (block 27): its thread and your last 10 live as long as the app, so a tab switch keeps them.
    @State private var search = SearchStore()
    @State private var voice = SXVoice()

    var body: some View {
        ZStack {
            SBackground()
            if let home = store.home {
                #if DEBUG
                if let g = DebugPreset.gallery {
                    GalleryHost(block: g, store: store, home: home)
                        .environment(\.livePulse, store.livePulse)
                } else {
                    tabs(home)
                        .opacity(shown ? 1 : 0)
                        .onAppear { withAnimation(.easeOut(duration: 0.5)) { shown = true } }
                }
                #else
                tabs(home)
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
            if let home = store.home, let r = router.receipt {
                receipt(r, home)
                    .transition(reduce ? .opacity : .move(edge: .bottom))
                    .zIndex(10)
            }
            // Over everything, so the 4:16 PM push lands on it from anywhere.
            if let home = store.home, router.aftershockOpen, home.aftershock != nil {
                SunnyAftershockPage(home: home, onBack: router.closeAftershock)
                    .transition(reduce ? .opacity : .move(edge: .trailing))
                    .zIndex(10.5)
            }
        }
        // This week's insights (14c): a sheet from every Position card.
        .sheet(isPresented: Binding(get: { router.insights != nil }, set: { if !$0 { router.insights = nil } })) {
            if let t = router.insights {
                SunnyInsightsSheet(t: t, insights: store.home?.writes.names.first { $0.ticker == t }?.insights?.value) {
                    router.insights = nil
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
                .environment(router)
            }
        }
        .environment(router)
        .onAppear(perform: debugOpen)
        // A tapped push: Aftershock opens its page once Home has its data.
        .onChange(of: PushInbox.shared.link, initial: true) { _, _ in openPushed() }
        .onChange(of: store.home == nil) { _, _ in openPushed() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.live()
        }
    }

    /// The native tab bar (block 12a): iOS draws the floating glass bar, its lens and labels. Opens on Home.
    private func tabs(_ home: HomePayload) -> some View {
        // A tap on the open tab comes through as the same value: that tab scrolls to the top.
        let pick = Binding(get: { router.tab }, set: { t in
            if t == router.tab { router.topTick[t, default: 0] += 1; return }
            if t == .search { router.searchFrom = router.tab }
            router.tab = t
        })
        return TabView(selection: pick) {
            Tab("Home", systemImage: "house.fill", value: HomeRouter.Tab.home) {
                NavigationStack {
                    ZStack {
                        SBackground()
                        page(home)
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
            Tab("Positions", systemImage: "rectangle.stack.fill", value: HomeRouter.Tab.positions) {
                NavigationStack { SunnyPositionsTab(store: store) }
            }
            // Handoff 32 (12c): Gamma and Insights, one name at a time, the name carried between them.
            Tab("Gamma", systemImage: "chart.bar.doc.horizontal", value: HomeRouter.Tab.gamma) {
                NavigationStack { SunnyGammaTab(store: store) }
            }
            Tab("Insights", systemImage: "lightbulb", value: HomeRouter.Tab.insights) {
                NavigationStack { SunnyInsightsTab(store: store) }
            }
            // Block 27: the round glass search button right of the four tabs. Tap opens Search; press and hold
            // (0.45 s) opens it listening.
            Tab(value: HomeRouter.Tab.search, role: .search) {
                NavigationStack {
                    SunnySearchPage(search: search, voice: voice, from: router.searchFrom,
                                    leave: { router.tab = router.searchFrom }, listenTick: router.listenTick)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .background(SXHoldToTalk { router.searchFrom = router.tab == .search ? router.searchFrom : router.tab
                                   router.tab = .search; router.listenTick += 1 })
        // The bar stays as it is while scrolling (Nik, 26 Oct 2026: do not minimise it).
        .tabBarMinimizeBehavior(.never)
    }

    private func page(_ home: HomePayload) -> some View {
        let words = store.words ?? home
        return ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: hold)
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        StatusLine(store: store).padding(.horizontal, S.margin)
                        AccountChart(home: home, readTick: store.readTick)
                    }
                    .sEnter(0)
                    // Rebuilt every 15 s as well as on each update, so the
                    // Aftershock card comes in at 4:00 PM and leaves at 8:00 PM
                    // with nothing else changing.
                    TimelineView(.periodic(from: .now, by: 15)) { _ in
                        SunnyDeck(cards: DeckBuilder.cards(home), today: home.today) { act(action: $0) }
                    }
                    .padding(.horizontal, S.margin)
                    .sEnter(1)
                    // An even glide in and out over a second; the 0.6 s ease-out
                    // started at full speed and felt like a jump (Nik, 15 Oct 2026).
                    SunnyQuickNav { s in
                        withAnimation(reduce ? nil : .timingCurve(0.45, 0, 0.25, 1, duration: 1.0)) { proxy.scrollTo(s, anchor: .top) }
                    }
                    .sEnter(2)
                    SunnySectionTitle(title: "Today").id("today")
                    SunnyToday(home: home).sEnter(3)

                    // Book keeps Portfolio and the watchlist; the cards, To do and Inventory moved to the
                    // Positions tab (handoff 30).
                    SunnySectionTitle(title: "Book").id(HomeRouter.Section.book)
                    SunnyPortfolio(home: home, words: words)
                        .padding(.horizontal, S.margin)
                        .id("portfolio")
                        .sEnter(4)

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
            .scrollPosition($homePos)
            .onChange(of: router.topTick[.home]) { _, _ in withAnimation(reduce ? nil : S.standard(0.45)) { homePos.scrollTo(edge: .top) } }
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

    /// DEBUG simulator runs only: `-open report|theta|writes:TICKER|aftershock`
    /// opens a state straight away, so every state can be screenshotted.
    private func debugOpen() {
        #if DEBUG && targetEnvironment(simulator)
        let a = ProcessInfo.processInfo.arguments
        // `-pushlink <url>`: as if a push carrying that deep link was tapped.
        if let i = a.firstIndex(of: "-pushlink"), i + 1 < a.count { PushInbox.shared.link = a[i + 1] }
        guard let i = a.firstIndex(of: "-open"), i + 1 < a.count else { return }
        let v = a[i + 1]
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if v == "report" { router.open(.report(0)) }
            else if v == "theta", let c = (store.home?.thetaChecks ?? []).first { router.open(.theta(c.leg)) }
            else if v.hasPrefix("card:") {
                let p = v.dropFirst(5).split(separator: ":").map(String.init)
                router.openCard(p[0], face: p.count > 1 ? p[1] : "sold")
            }
            else if v.hasPrefix("insights:") { router.insights = String(v.dropFirst(9)) }
            else if v == "aftershock" { router.openAftershock(animated: false) }
            else if v.hasPrefix("at:") { router.scrollID = String(v.dropFirst(3)) }
            else if v.hasPrefix("tab:") {
                let x = v.dropFirst(4)
                router.tab = x == "positions" ? .positions : x == "gamma" ? .gamma : x == "insights" ? .insights : .home
            }
            else if v.hasPrefix("gamma:") { let p = v.dropFirst(6).split(separator: ":").map(String.init); router.openGamma(p[0], view: p.count > 1 ? p[1] : nil, wall: nil) }
            else if v.hasPrefix("itab:") { let t = String(v.dropFirst(5)); router.tab = .insights; if t != "All" { router.insightsAll = false; router.focus = t } }
            else if v.hasPrefix("walls:") {
                router.tab = .positions
                try? await Task.sleep(for: .milliseconds(500))
                router.walls = String(v.dropFirst(6))
            }
            else if v.hasPrefix("filter:") {
                let f = String(v.dropFirst(7))
                router.tab = .positions
                router.filter = f == "todo" ? .todo : f == "up" ? .up : f == "down" ? .down : Int(f).map { .kept($0) } ?? .all
            }
        }
        #endif
    }

    private func act(action: DeckCard.Action) {
        switch action {
        case .writes(let t): router.openCard(t, face: "sold")
        case .report(let i): router.open(.report(i))
        case .theta(let leg): router.open(.theta(leg))
        case .aftershock: router.openAftershock()
        }
    }

    private func openPushed() {
        guard let link = PushInbox.shared.link, store.home != nil else { return }
        PushInbox.shared.link = nil
        if link == "sunny://aftershock" { router.openAftershock(animated: false) }
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
