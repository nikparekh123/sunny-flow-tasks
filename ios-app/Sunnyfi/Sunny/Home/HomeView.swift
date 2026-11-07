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
    /// While Search is open the tab bar and the search button are 120 pt down and faded out.
    @State private var barDown = false
    @State private var barGone = false
    /// New Home (handoff 6 Nov): the account on screen, shared by Home, Positions and Overview.
    @State private var brief = BriefState()

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
            // Block 27: Search, a page of its own over the tab you came from.
            if store.home != nil, router.searchOpen {
                SunnySearchPage(search: search, voice: voice, from: router.searchFrom, leave: closeSearch, listenTick: router.listenTick)
                    .zIndex(9)
            }
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

    /// The four tabs (block 12a, 12c). The system's bar is hidden: Sunny draws its own (SunnyTabBar), so Search
    /// sits apart on every iOS (iOS 27 put the system search tab inside the bar). Each tab keeps the 49 pt the
    /// system bar held under it, so nothing moves. Opens on Home.
    /// Two tabs since the 6 Nov handoff (answer 7): Home and Positions, Search its own circle. Gamma and
    /// Insights are gone. Overview (block 32) lies over both when the strip lands on it; the tab bar and
    /// Search slide away and come back when an account is picked.
    private func tabs(_ home: HomePayload) -> some View {
        ZStack {
            TabView(selection: Binding(get: { router.tab }, set: { router.tab = $0 })) {
                Tab("Home", systemImage: "house.fill", value: HomeRouter.Tab.home) {
                    NavigationStack {
                        ZStack {
                            SBackground()
                            BriefHomeScreen(store: store, home: home)
                        }
                        .toolbar(.hidden, for: .navigationBar)
                    }
                    .modifier(OwnTabBar())
                }
                Tab("Positions", systemImage: "rectangle.stack.fill", value: HomeRouter.Tab.positions) {
                    // Pass 1 (6 Nov handoff): one name at a time on the sample book; the old stacked cards stay for real
                    // data until Pass 2 feeds the new screen.
                    NavigationStack {
                        // Pass 2: the new screen on the real book once the server's brief is in; the old cards until then.
                        if BriefDebug.sample || (brief.live != nil && brief.live?.error == nil) { BriefPositionsScreen().toolbar(.hidden, for: .navigationBar) }
                        else { SunnyPositionsTab(store: store) }
                    }
                    .modifier(OwnTabBar())
                }
            }
            if brief.onOverview {
                OverviewScreen()
                    .transition(reduce ? .opacity : .move(edge: .leading).combined(with: .opacity))
                    .zIndex(1)
            }
            // A ticker chart, pushed from any name tile (block 33): from the right, full screen, X goes back.
            if let t = brief.ticker {
                TickerChartPage(t: t, acct: brief.account.sampleKey, book: brief.book) { withAnimation(reduce ? nil : S.standard(0.45)) { brief.ticker = nil } }
                    .transition(reduce ? .opacity : .move(edge: .trailing))
                    .zIndex(3)
            }
        }
        .animation(reduce ? .easeOut(duration: 0.2) : S.standard(0.5), value: brief.onOverview)
        .animation(reduce ? .easeOut(duration: 0.2) : S.standard(0.45), value: brief.ticker)
        .sheet(item: Binding(get: { brief.sheet }, set: { brief.sheet = $0 })) { k in
            Group {
                switch k {
                case .timeValue: TimeValueSheet(acct: brief.account.sampleKey, privacy: UserDefaults.standard.bool(forKey: BriefPrivacy.key),
                                                live: brief.live?.timeValue ?? .null) { brief.sheet = nil }
                case .economy: EconomySheet(live: brief.live?.economy ?? .null) { brief.sheet = nil }
                }
            }
            .presentationDetents([.large])
            .presentationCornerRadius(38)
            .presentationBackground(S.sheetFill)
        }
        .overlay {
            SunnyTabBar(tab: router.tab, pick: pickTab, search: openSearch)
                .offset(y: barDown || brief.onOverview || brief.ticker != nil ? 120 : 0)
                .opacity(barGone || brief.onOverview || brief.ticker != nil ? 0 : 1)
                .allowsHitTesting(!router.searchOpen && !brief.onOverview && brief.ticker == nil)
                .animation(reduce ? .easeOut(duration: 0.2) : .timingCurve(0.32, 0.72, 0, 1, duration: 0.45), value: brief.onOverview)
        }
        .environment(brief)
        .onAppear(perform: briefSetup)
        // The server's brief, decoded once per build (memoized; HomeStore ticks every 15 to 30 s).
        .onChange(of: home.builtAt, initial: true) { _, _ in
            brief.ingest(home.brief, key: home.builtAt, book: store.bookIDNow, overview: home.overview, books: store.books)
        }
        // The strip picked a book: read its Home (Overview stays on S's last build).
        .onChange(of: brief.account) { _, a in
            guard !BriefDebug.sample, a != .overview else { return }
            Task { await store.show(book: a == .nicolay ? "N" : "S") }
        }
    }

    /// Who sees which accounts. Sample mode (DEBUG): both books and Overview, as the design shows Nik.
    /// Real books arrive with the account strip in Pass 2 (book_members, owned books).
    private func briefSetup() {
        // Debug runs (simulator only): open on a tab or an overlay, on the sample or the real book.
        if BriefDebug.tab == "positions" { router.tab = .positions }
        defer {
            switch BriefDebug.open {
            case "timevalue": brief.sheet = .timeValue
            case "economy": brief.sheet = .economy
            case let o? where o.hasPrefix("ticker:"): brief.ticker = String(o.dropFirst(7))
            default: break
            }
        }
        guard BriefDebug.sample else { return }
        brief.accounts = [.overview, .sunny, .nicolay]
        brief.account = BriefDebug.account ?? .sunny
        UserDefaults.standard.set(BriefDebug.privacy, forKey: BriefPrivacy.key)
    }

    /// A tap on the open tab scrolls it to the top.
    private func pickTab(_ t: HomeRouter.Tab) {
        if t == router.tab { router.topTick[t, default: 0] += 1; return }
        router.tab = t
    }

    /// Search opens over the tab you are on; the tab bar and the search button slide down 120 pt (0.45 s) and
    /// fade (0.3 s). Reduce Motion cross-fades.
    private func openSearch(listening: Bool) {
        guard !router.searchOpen else { return }
        router.searchFrom = router.tab
        if listening { router.listenTick += 1 }
        router.searchOpen = true
        if reduce { withAnimation(.easeOut(duration: 0.25)) { barGone = true }; return }
        withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.45)) { barDown = true }
        withAnimation(.easeOut(duration: 0.3)) { barGone = true }
    }

    /// The page has started fading out (0.22 s after a 0.08 s wait); the tab bar slides back up from 0.05 s.
    private func closeSearch() {
        if reduce { withAnimation(.easeOut(duration: 0.25)) { barGone = false } }
        else {
            withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.45).delay(0.05)) { barDown = false }
            withAnimation(.easeIn(duration: 0.3).delay(0.05)) { barGone = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { router.searchOpen = false }
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
                    // No LEAPs, nothing to pay back: no card (a book that is all cash, 31 Oct 2026).
                    if home.payback != nil && words.payback != nil {
                        SunnyPayback(home: home, words: words).padding(.horizontal, S.margin).id("payback")
                    }

                    SunnySectionTitle(title: "Results").id(HomeRouter.Section.results)
                    SunnySoldBought(home: home).padding(.horizontal, S.margin).id("svb")
                    SunnyPerformance(words: words).padding(.horizontal, S.margin).id("performance")
                    SunnyAllocation(home: home, words: words).padding(.horizontal, S.margin).id("allocation")
                }
                .padding(.top, 14)
                .padding(.bottom, 40)
                // Held to the screen's exact width. The stack measured 393.00000000000006 on a 393 pt
                // screen (rounding), so iOS let the page slide sideways under an angled drag and spring
                // back, up to 65 pt (Nik, 4 Nov 2026).
                .containerRelativeFrame(.horizontal)
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

/// A tab's content without the system's tab bar, keeping the 49 pt it held so the pages sit where they did.
private struct OwnTabBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .safeAreaPadding(.bottom, 49)
    }
}
