//
//  PositionsTab.swift
//  Sunny
//
//  The Positions tab (handoff 2026-11-13-positions §2, App Explorations 154a), view only, top to bottom:
//    the account strip (owners of both books) · large title Positions, "Sunny’s book · Fri Nov 13 close" ·
//    Your book (handoff 2026-11-18 §2.1: one glass card, Long · Hedge · Income with Today and All time, a tap opens a
//    group's parts; it replaces the Nov 13 totals cards and Sold, in SD) · the name strip (a dot: red short at the priced move by Friday, orange a sold leg within 0.5 SD, A7) · the name
//    header · Price | Payoff (Payoff at this Friday's close) · Every leg, a native switch on each row (Nik 13 Nov 2026),
//    and the Whole TICKER book row · Intelligence for this week, always open (PositionsIntelView).
//    Legs sold start on, shares and legs bought start off (Nik, 13 Nov 2026, every name). A leg switched off drops out
//    of the Whole TICKER book row and the Payoff with its Greeks, per book and name, for as long as the app is open.
//    The Price chart keeps every strike held; Your book and Intelligence stay whole.
//  Not on the phone: the SD calculator, What if, Try a trade, New and Both, the cover check, dates, table.
//
//  Every model is worked out once per input (PositionsMemo), never in a body. The screen handles its own loading,
//  empty and error states, and both books (S and N: whichever the account strip has on screen).
//  No em dashes in any words here.
//

import SwiftUI

struct PositionsTab: View {
    @Environment(BriefState.self) private var brief
    @Environment(HomeRouter.self) private var router
    @Environment(\.todoTap) private var todoTap
    @Environment(\.accessibilityReduceMotion) private var reduce
    @AppStorage(BriefPrivacy.key) private var privacy = false
    @State private var todo = TodoStore.shared
    @State private var sd = SDStore.shared
    @State private var charts = PositionsCharts.shared
    @State private var targets = PositionsTargets.shared
    /// The Payoff's date (an index on its slider; nil = the end, the expiry) and range in % either side (168b).
    @State private var payAt: Int?
    @State private var payRange = 12
    /// The Price chart's 1 SD layer, remembered (round 164; the web keeps it as sunny.cone164 too).
    @AppStorage("sunny.cone164") private var cone = false
    @State private var memo = PositionsMemo()

    @State private var name: String = BriefDebug.name ?? ""
    @State private var view: Band = .price
    /// Legs switched away from how they start in Every leg (Income on, the rest off), per "book|TICKER".
    @State private var flip: [String: Set<String>] = [:]
    /// The open box ("lane|box"): one at a time across the lanes.
    @State private var box: String?
    @State private var scrolled: CGFloat = 0
    @State private var pos = ScrollPosition()
    @State private var picks = 0
    /// Your book's open groups.
    @State private var bookOpen: Set<String> = []
    /// The name's own book: its open group (one at a time).
    @State private var ownOpen: String?
    // The account switch, as Home does it: the page at 15% and 28 pt toward the new account, then back.
    @State private var faded = false
    @State private var slid = false
    @State private var dipDir: CGFloat = 0
    @State private var settling: Task<Void, Never>?

    enum Band: Hashable { case price, payoff }
    static let page = "positionsTab"
    private static let margin: CGFloat = 16

    private var bookID: String? { brief.book }
    private var pageBook: BriefAccount { brief.account == .overview ? brief.lastBook : brief.account }
    private var pageReady: Bool { brief.book == nil || brief.book == (pageBook == .nicolay ? "N" : "S") }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if brief.showsStrip {
                        AccountStrip(accounts: brief.accounts, selected: brief.account) { a in brief.pick(a) }
                    }
                    content
                        .padding(.top, brief.showsStrip ? 28 - AccountStrip.lift : 12)
                        .opacity(faded ? 0.15 : 1)
                        .offset(x: slid ? 28 * dipDir : 0)
                }
                .overlay(alignment: .topTrailing) { ActivityBellSlot() }
                .padding(.bottom, 120)
                .containerRelativeFrame(.horizontal)
                .coordinateSpace(.named(Self.page))
            }
            .scrollIndicators(.hidden)
            .scrollPosition($pos)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, v in scrolled = v }
            .task {
                #if DEBUG && targetEnvironment(simulator)
                // Screens checked in the simulator: `-posOpen Hedge` opens a Your book group; `-posBox w|ce` opens a
                // box's detail; `-posAt intel` scrolls to Intelligence; `-posView payoff` shows Payoff.
                let a = ProcessInfo.processInfo.arguments
                func arg(_ k: String) -> String? { a.firstIndex(of: k).flatMap { a.indices.contains($0 + 1) ? a[$0 + 1] : nil } }
                if arg("-posView") == "payoff" { view = .payoff }
                if let g = arg("-posOpen") { bookOpen = [g] }
                if let b = arg("-posBox") { box = b }
                if let at = arg("-posAt") { try? await Task.sleep(for: .milliseconds(1400)); proxy.scrollTo(at, anchor: .top) }
                if let y = BriefDebug.scroll { try? await Task.sleep(for: .milliseconds(1200)); pos.scrollTo(y: y) }
                #endif
            }
        }
        .background(SBackground(glows: true))   // Home's background, glows fixed (handoff 2026-11-18 §1.1)
        .overlay(alignment: .top) { BriefTopEdge() }
        // The small title once the large one has scrolled under the top edge: "NKE Positions".
        .overlay(alignment: .top) {
            let shown = scrolled > (brief.showsStrip ? 110 : 40)
            Text(name.isEmpty ? "Positions" : "\(name) Positions").sFont(17, .semibold).foregroundStyle(S.ink)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(alignment: .bottom) { Rectangle().fill(.bar).ignoresSafeArea(edges: .top).frame(height: 120, alignment: .bottom) }
                .overlay(alignment: .bottom) { Rectangle().fill(S.hairline).frame(height: 0.5) }
                .opacity(shown ? 1 : 0)
                .animation(S.fade, value: shown)
                .allowsHitTesting(false)
                .accessibilityHidden(!shown)
        }
        .onAppear { arrive() }
        .onChange(of: brief.positionsName) { _, _ in arrive() }
        // A name opened from elsewhere (a deck card, Risk): select it.
        .onChange(of: router.positionsName, initial: true) { _, t in
            guard let t else { return }
            router.positionsName = nil
            brief.positionsName = t
            arrive()
        }
        .onChange(of: brief.built) { _, _ in arrive() }
        .onChange(of: name) { _, t in
            ownOpen = nil
            payAt = nil; payRange = 12
            if !t.isEmpty, let b = bookID { UserDefaults.standard.set(t, forKey: "positions.last.\(b)") }
            box = nil
            load()
        }
        .onChange(of: pageBook) { _, _ in bookOpen = []; box = nil; dip() }
        // Back from Overview, even to the same account, the page plays the same move (handoff 2026-11-18 §1.2).
        .onChange(of: brief.onOverview) { was, now in if was && !now && router.tab == .positions { dip() } }
        .onChange(of: pageReady) { _, ready in if ready && faded { settle(wait: false) } }
    }

    // MARK: The page

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            title.padding(.horizontal, Self.margin)
            if let live = brief.live, live.error == nil, pageReady {
                if live.names.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nothing held yet").sType(PT.section, tabular: false).foregroundStyle(PC.ink)
                        Text("Each name you hold shows here once IBKR reports it.").sType(PT.t(13, 18), tabular: false).foregroundStyle(PC.mu)
                    }
                    .padding(.horizontal, Self.margin)
                } else {
                    page(live)
                }
            } else if let e = brief.live?.error {
                Text(e).sType(PT.t(13, 18), tabular: false).foregroundStyle(PC.mu).padding(.horizontal, Self.margin)
            } else {
                ProgressView().controlSize(.regular).frame(maxWidth: .infinity).padding(.top, 60)
            }
        }
    }

    @ViewBuilder private func page(_ live: BriefLive) -> some View {
        let b = bookID ?? "S"
        let book = memo.book(key: "\(brief.built ?? "")|\(b)|\(sd.version)") {
            PosBook.build(brief: live, inputs: brief.inputs, calendar: brief.calendar, replies: { sd.reply(b, $0) }, now: SClock.now())
        }
        let n = book.names.first { $0.t == name } ?? book.names.first
        if !book.groups.isEmpty {
            PosYourBook(groups: book.groups, open: $bookOpen, privacy: privacy, reduce: reduce)
                .padding(.horizontal, Self.margin)
        }
        PosStrip(names: book.names, selected: n?.t ?? "") { t in
            guard t != name else { return }
            picks += 1
            withAnimation(S.fade) { name = t }
        }
        .sensoryFeedback(.selection, trigger: picks)
        if let n {
            nameSection(n, book: b, sold: book.sold, own: book.nameGroups[n.t] ?? [])
        }
    }

    /// The header, Price | Payoff, Every leg and Intelligence for the name on screen.
    @ViewBuilder private func nameSection(_ n: PosBook.Name, book b: String, sold: [PE.SoldRow], own: [PosBook.Group]) -> some View {
        let m = brief.positions.model(b, n.t)
        let built = brief.positions.models["\(b)|\(n.t)"]?.built ?? ""
        let offK = "\(b)|\(n.t)", offs = flip[offK] ?? []
        let nm = m.map { mm in
            memo.name(key: "\(b)|\(n.t)|\(built)|\(brief.built ?? "")|\(offs.sorted().joined(separator: ","))") {
                PosName.build(mm, inputs: brief.inputs, flip: offs)
            }
        }
        // Home's price every 15 s (the grid now refreshes on a real move or each minute, PositionsLive).
        let S0 = n.S0 > 0 ? n.S0 : (nm?.S0 ?? 0)
        PosHeader(n: n, S0: S0).padding(.horizontal, Self.margin)
        if !own.isEmpty {
            PosNameBook(t: n.t, groups: own, open: $ownOpen, privacy: privacy, reduce: reduce)
                .padding(.horizontal, Self.margin)
                .padding(.top, -4)
        }
        VStack(alignment: .leading, spacing: 12) {
            Picker("Price or payoff", selection: $view) {
                Text("Price").tag(Band.price)
                Text("Payoff").tag(Band.payoff)
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .sensoryFeedback(.selection, trigger: view)
            Group {
                if view == .price {
                    // A sold strike wears its Sold in SD closeness (Nik, 14 Nov 2026, "4 + 2").
                    let w = charts.chart(b, n.t), now = MarketClock.ny(SClock.now()), stk = PosPrice.toned(nm?.strikes ?? [], sold.filter { $0.l.t == n.t })
                    // This week's IV (Home's brief_inputs, the Friday chain's at the money), for the strikes' SD and the cone.
                    let ivNow = brief.inputs?["names"].array.first { $0["t"].string == n.t }?["iv"].double
                    let closed = Set(brief.calendar.filter { $0.kind == "closed" }.map(\.date))
                    let pr = w.flatMap { w in
                        memo.price(key: "\(b)|\(n.t)|\(w.dates.last ?? "")|\(w.hours?.count ?? 0)|\(S0)|\(now.date)|\(now.minutes)|\(cone)|\(stk.map { $0.id + ($0.tone?.rawValue ?? "") }.joined(separator: ","))") {
                            PosPrice.build(w, S0: S0, today: now.date, mins: now.minutes, closed: closed, strikes: stk, iv: ivNow, cone: cone)
                        }
                    }
                    PosPriceChart(price: pr, failed: charts.hasFailed(b, n.t), cone: $cone)
                } else if let mm = m, let nm, !nm.dates.isEmpty {
                    let ai = min(payAt ?? nm.dateEnd, nm.dateEnd), stop = nm.dates[ai].i
                    if let p = memo.payoff(key: "\(b)|\(n.t)|\(built)|\(brief.built ?? "")|\(offs.sorted().joined(separator: ","))|\(stop)|\(payRange)", {
                        PosName.payoff(mm, off: PosName.offs(mm, flip: offs), stop: stop, range: Double(payRange) / 100, hold: nm.dates.map(\.i))
                    }) {
                        PosPayoffView(t: n.t, S0: S0, p: p, privacy: privacy, changed: nm.changed, dates: nm.dates,
                                      at: Binding(get: { ai }, set: { payAt = $0 }), rangePct: $payRange, target: targets.price(b, n.t))
                    } else {
                        loadingBox(error: brief.positions.error(b, n.t), height: 300)
                    }
                } else {
                    loadingBox(error: brief.positions.error(b, n.t), height: 300)
                }
            }
            .transition(.opacity)
        }
        .animation(S.fade, value: view)
        .padding(.horizontal, Self.margin)
        Group {
            if let nm {
                PosEveryLeg(t: n.t, m: nm, privacy: privacy) { id, _ in
                    withAnimation(S.fade) {
                        var s = flip[offK] ?? []
                        if s.contains(id) { s.remove(id) } else { s.insert(id) }
                        flip[offK] = s
                    }
                }
            }
            else { loadingBox(error: brief.positions.error(b, n.t), height: 160) }
        }
        .padding(.horizontal, Self.margin)
        intelSection(n, book: b)
            .id("intel")
            .padding(.horizontal, Self.margin)
    }

    @ViewBuilder private func intelSection(_ n: PosBook.Name, book b: String) -> some View {
        let reply = sd.reply(b, n.t)
        let friday = brief.live?.friday ?? MarketClock.ny(SClock.now()).date
        let walls = brief.inputs?["names"].array.first { $0["t"].string == n.t }?["walls"]
        let intel = reply.flatMap { r in memo.intel(key: "\(b)|\(n.t)|\(sd.version)|\(friday)") { PosIntel.build(r, friday: friday, walls: walls) } }
        PosIntelView(t: n.t, intel: intel, failed: reply == nil && sd.hasFailed(b, n.t), loaded: reply != nil, privacy: privacy, box: $box, reduce: reduce)
    }

    private func loadingBox(error: String?, height: CGFloat) -> some View {
        Group {
            if let error { Text(error).sType(PT.t(13, 18), tabular: false).foregroundStyle(PC.mu) }
            else { ProgressView().controlSize(.regular) }
        }
        .frame(maxWidth: .infinity, minHeight: height)
    }

    // MARK: Title

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Positions").sType(PT.title, tabular: false).foregroundStyle(PC.ink)
                    .accessibilityAddTraits(.isHeader)
                if let tap = todoTap {
                    Spacer(minLength: 8)
                    TodoLink(open: todo.openCount, action: tap)
                }
            }
            Text(subtitle).sType(PT.t(14, 20), tabular: false).foregroundStyle(PC.mu)
                .accessibilityLabel(PosSay.words(subtitle))
            if let t = brief.asOf() {
                Text("As of \(Self.asOfWords(t)) · IBKR data is late").sType(PT.t(13, 18, 500), tabular: false).foregroundStyle(PC.orange)
            }
        }
    }

    /// "Sunny’s book · Fri Nov 13 close" for marks taken at or after the close (or an earlier day), else
    /// "Sunny’s book · Fri Nov 13 · 12:40 PM ET" (the web's asOf).
    private var subtitle: String {
        let who = "\(pageBook.name)’s book"
        /* Before the open and after the close the marks are estimates from pre-market or after-hours trades. */
        if let e = brief.est {
            let w = e.session == "pre" ? "pre-market est." : "after hours est."
            guard let at = e.at else { return "\(who) · \(w)" }
            let f = DateFormatter(); f.timeZone = MarketClock.ny; f.dateFormat = "h:mm a"
            return "\(who) · \(w) · \(f.string(from: at)) ET"
        }
        guard let d = brief.fresh.marks else { return who }
        let n = MarketClock.ny(d), today = MarketClock.ny(SClock.now())
        if n.date < today.date || n.minutes >= 16 * 60 { return "\(who) · \(PosFmt.dmd(n.date)) close" }
        let f = DateFormatter(); f.timeZone = MarketClock.ny; f.dateFormat = "h:mm a"
        return "\(who) · \(PosFmt.dmd(n.date)) · \(f.string(from: d)) ET"
    }

    /// "3:58 PM" today, "Fri 3:58 PM" before today (Home's Your position reads it too).
    static func asOfWords(_ d: Date) -> String {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = Calendar.current.isDate(d, inSameDayAs: SClock.now()) ? "h:mm a" : "EEE h:mm a"
        return f.string(from: d)
    }

    // MARK: Loading

    /// The name on screen: the one Your position opened, else the last viewed in this book, else the first short at
    /// its priced move by Friday, else the biggest.
    private func arrive() {
        let names = brief.live?.names.compactMap { $0["t"].string } ?? []
        if let t = brief.positionsName, names.contains(t) { name = t; brief.positionsName = nil }
        if !names.contains(name) { name = Self.firstName(brief) }
        load()
    }
    /// The name Positions opens on: the last one looked at in this book, else a name short at its priced move, else
    /// the biggest.
    static func firstName(_ brief: BriefState) -> String {
        let live = brief.live?.names ?? [], names = live.compactMap { $0["t"].string }
        if let l = brief.book.flatMap({ UserDefaults.standard.string(forKey: "positions.last.\($0)") }), names.contains(l) { return l }
        if let s = live.first(where: { $0["short"].bool })?["t"].string { return s }
        return live.max { ($0["size"].double ?? 0) < ($1["size"].double ?? 0) }?["t"].string ?? names.first ?? ""
    }
    /// Positions made ready in the background (handoff 2026-11-18 §1.3): about 0.9 s after Home shows, the name it
    /// will open on is fetched (its grid, closes, chain and the book's targets), so the first tap on the tab is instant.
    /// A name's legs as the grid lists them (key and count), from Home's brief_inputs: a trade picked up asks at once.
    static func legSig(_ brief: BriefState, _ t: String) -> String {
        let n = brief.inputs?["names"].array.first { $0["t"].string == t }
        return (n?["legs"].array ?? []).map { "\($0["k"].string ?? ""):\($0["q"].double ?? 0)" }.sorted().joined(separator: ",")
    }
    static func prefetch(_ brief: BriefState) {
        let t = firstName(brief)
        guard !t.isEmpty, let b = brief.book, let built = brief.built,
              let n = brief.live?.names.first(where: { $0["t"].string == t }) else { return }
        brief.positions.load(book: b, t: t, built: built, name: n, legs: legSig(brief, t))
        PositionsTargets.shared.load(book: b)
        PositionsCharts.shared.load(book: b, t: t)
        SDStore.shared.load(book: b, t: t)
    }
    /// The name's grid (sunny-positions), its closes (sunny-chart) and its chain (sunny-sd).
    private func load() {
        guard !name.isEmpty, let b = bookID, let built = brief.built,
              let n = brief.live?.names.first(where: { $0["t"].string == name }) else { return }
        brief.positions.load(book: b, t: name, built: built, name: n, legs: Self.legSig(brief, name))
        targets.load(book: b)
        charts.load(book: b, t: name)
        sd.load(book: b, t: name)
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

/// Positions redraws from its own state and data, never because Home's parent did (11 Nov 2026: the tab switch jerk).
extension PositionsTab: Equatable {
    nonisolated static func == (_: PositionsTab, _: PositionsTab) -> Bool { true }
}

// MARK: - Book totals (three cards sideways, 244 wide)

/// README §3.1 with Nik's D7: LONG Shares · HEDGE Calls (every call bought, LEAPS too), Puts · INCOME Calls, Puts. Long
/// and Hedge read their value now, and the gain on what was paid; Income reads what was collected, and what is kept
/// (collected less the cost to close) on it. "None" where the book holds none. Gains green, losses red, never a sign.
/// Your book (handoff 2026-11-18 §2.1): one glass card. A header row (Your book · Today · All time), then Long, Hedge
/// and Income, the groups the book holds, each its value under its name and its Today and All time ($ over %, green up
/// or kept, red down, never a sign). A tap opens the group's parts in the same columns; a group with one part names it
/// ("Long · Shares") and has no chevron. Figures from sunny-home (brief_inputs.parts): Today is Home's today split by
/// part, so the rows add up to it; All time is against IBKR's cost, or kept of what was sold.
struct PosYourBook: View {
    let groups: [PosBook.Group]
    @Binding var open: Set<String>
    let privacy: Bool
    let reduce: Bool

    private static let label = PC.say                          // #C7C7CC
    private static let chevron = S.dyn(0x8E8E93, 0x636366)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Your book").sType(PT.t(13, 16, 600), tabular: false).foregroundStyle(Self.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Text("Today").sType(PT.t(12, 16, 500), tabular: false).foregroundStyle(PC.mu).frame(width: 74, alignment: .trailing)
                Text("All time").sType(PT.t(12, 16, 500), tabular: false).foregroundStyle(PC.mu).frame(width: 74, alignment: .trailing)
                Color.clear.frame(width: 12, height: 1)
            }
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
            ForEach(groups) { g in row(g) }
        }
        .padding(.top, 16).padding(.horizontal, 16).padding(.bottom, 6)
        .sunnyGlass(radius: 22)
    }

    @ViewBuilder private func row(_ g: PosBook.Group) -> some View {
        let one = g.parts.count == 1, isOpen = !one && open.contains(g.title), x = g.sum
        VStack(spacing: 0) {
            Button {
                guard !one else { return }
                withAnimation(S.moving(.easeInOut(duration: 0.25), reduce) ?? .linear(duration: 0)) {
                    if isOpen { open.remove(g.title) } else { open.insert(g.title) }
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        (Text(g.title).foregroundStyle(Self.label)
                         + Text(one ? " · \(g.parts[0].label)" : "").font(.custom("Inter", size: 15).weight(.medium)).foregroundStyle(PC.mu))
                            .sType(PT.t(15, 20, 600), tabular: false)
                        Text(money(x.value)).sType(PT.t(24, 28, 700, tr: -0.02)).foregroundStyle(PC.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    figure(x.today, x.todayPct, big: true).frame(width: 74, alignment: .trailing)
                    figure(x.all, x.allPct, big: true).frame(width: 74, alignment: .trailing)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Self.chevron)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 12)
                        .opacity(one ? 0 : 1)
                }
                .frame(minHeight: 44)      // at least 68 with the 12 above and below
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!one)   // a one-part group does not open (not .disabled: that dims it)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(said(one ? "\(g.title), \(g.parts[0].label)" : g.title, x))
            .accessibilityHint(one ? "" : (isOpen ? "Hides its parts" : "Shows its parts"))
            .accessibilityAddTraits(one ? [] : .isButton)
            if isOpen {
                VStack(spacing: 0) {
                    ForEach(g.parts) { p in
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(p.label).sType(PT.t(13, 17), tabular: false).foregroundStyle(PC.mu)
                                Text(money(p.value)).sType(PT.t(15, 20, 600)).foregroundStyle(PC.ink)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            figure(p.today, p.todayPct, big: false).frame(width: 74, alignment: .trailing)
                            figure(p.all, p.allPct, big: false).frame(width: 74, alignment: .trailing)
                            Color.clear.frame(width: 12, height: 1)
                        }
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(said(p.label, p))
                    }
                }
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(PC.rule).frame(height: 1) }
    }

    /// $ over %, green when up or kept, red when down; no sign.
    private func figure(_ v: Double, _ pct: Double, big: Bool) -> some View {
        let c = v > 0.5 ? PC.green : v < -0.5 ? PC.red : PC.ink
        return VStack(alignment: .trailing, spacing: 0) {
            Text(money(v)).sType(big ? PT.t(15, 20, 600) : PT.t(14, 18, 600))
            Text(PE.pcx(pct)).sType(big ? PT.t(12, 16, 600) : PT.t(11, 14, 600))
        }
        .foregroundStyle(c)
        .lineLimit(1).minimumScaleFactor(0.8)
    }

    private func money(_ v: Double) -> String { privacy ? BriefMask.shown : PosFmt.money(v) }

    /// "Hedge, 87.2 thousand dollars, today up 1.2 thousand dollars, 1.4 percent, all time down 25.4 thousand dollars, 22.7 percent".
    private func said(_ what: String, _ x: PosBook.Part) -> String {
        PosSay.words("\(what), \(PosSay.money(x.value, privacy)), today \(PosSay.signed(x.today, privacy)), \(PE.pcx(x.todayPct)), "
                     + "all time \(PosSay.signed(x.all, privacy)), \(PE.pcx(x.allPct))")
    }
}

/// The picked name's own book (handoff 2026-11-18 §2.3), under the name: Long · Hedge · Income in as many columns as
/// the name holds (never None or To do), each its value and its all-time gain ($ · %, green or red). A tap on a group
/// with two parts opens them under the row; the open cell sits on a soft tile. Same parts as Your book, this name only.
struct PosNameBook: View {
    let t: String
    let groups: [PosBook.Group]
    @Binding var open: String?
    let privacy: Bool
    let reduce: Bool

    var body: some View {
        let shown = groups.first { $0.title == open && $0.parts.count > 1 }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(groups) { g in cell(g) }
            }
            .padding(.vertical, 6)
            .overlay(alignment: .top) { Rectangle().fill(PC.rule).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(PC.rule).frame(height: 1) }
            if let g = shown {
                VStack(spacing: 8) {
                    ForEach(g.parts) { p in partRow(p) }
                }
                .padding(.top, 12).padding(.bottom, 4)
                .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(t) in your book")
    }

    private func cell(_ g: PosBook.Group) -> some View {
        let x = g.sum, two = g.parts.count > 1, on = two && open == g.title
        return Button {
            guard two else { return }
            withAnimation(S.moving(.easeOut(duration: 0.2), reduce) ?? .linear(duration: 0)) { open = on ? nil : g.title }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(g.title).sType(PT.t(12, 16, 500), tabular: false).foregroundStyle(PC.mu)
                Text(money(x.value)).sType(PT.t(17, 22, 700)).foregroundStyle(PC.ink)
                Text("\(money(x.all)) · \(PE.pcx(x.allPct))").sType(PT.t(12, 16, 600)).foregroundStyle(tone(x.all))
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(on ? S.dynA(0x1D1D1F, 0.06, 0xFFFFFF, 0.08) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(two)
        .padding(.horizontal, -2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PosSay.words("\(t) \(g.title), \(PosSay.money(x.value, privacy)), \(PosSay.signed(x.all, privacy)), \(PE.pcx(x.allPct))"))
        .accessibilityHint(two ? (on ? "Hides its parts" : "Shows its parts") : "")
        .accessibilityAddTraits(two ? .isButton : [])
    }

    private func partRow(_ p: PosBook.Part) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(p.label).sType(PT.t(14, 18), tabular: false).foregroundStyle(PC.say)
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(money(p.value)).sType(PT.t(14, 18, 600)).foregroundStyle(PC.ink)
                if let tv = p.tv { Text("(\(money(tv)))").sType(PT.t(12, 16)).foregroundStyle(PC.mu) }
                Text("\(money(p.all)) · \(PE.pcx(p.allPct))").sType(PT.t(12, 16, 600)).foregroundStyle(tone(p.all))
            }
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PosSay.words("\(p.label), \(PosSay.money(p.value, privacy))\(p.tv.map { ", time value left \(PosSay.money($0, privacy))" } ?? ""), \(PosSay.signed(p.all, privacy)), \(PE.pcx(p.allPct))"))
    }

    private func tone(_ v: Double) -> Color { v > 0.5 ? PC.green : v < -0.5 ? PC.red : PC.ink }
    private func money(_ v: Double) -> String { privacy ? BriefMask.shown : PosFmt.money(v) }
}

// MARK: - The name strip and the header

struct PosStrip: View {
    let names: [PosBook.Name]
    let selected: String
    let pick: (String) -> Void
    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 6) {
                ForEach(names) { n in
                    let on = n.t == selected
                    Button { pick(n.t) } label: {
                        VStack(spacing: 6) {
                            // Handoff 2026-11-18 §2.2: the company's logo at 60% on a white disc; the picked ring is drawn
                            // inside the disc (an inset, never a border), so the red dot never moves when it thickens.
                            ZStack(alignment: .topTrailing) {
                                Circle().fill(.white)
                                    .overlay {
                                        if let img = UIImage(named: "logo-\(n.t)") {
                                            Image(uiImage: img).resizable().scaledToFit().frame(width: 34, height: 34)
                                        } else {
                                            Text(n.t).font(.inter(n.t.count > 4 ? 11 : 12, 700)).tracking(-0.12).foregroundStyle(Color(hex: 0x1D1D1F))
                                                .lineLimit(1).minimumScaleFactor(0.7).padding(.horizontal, 4)
                                        }
                                    }
                                    .overlay { Circle().strokeBorder(PC.ink, lineWidth: on ? 2.5 : 0) }
                                    .animation(.easeOut(duration: 0.2), value: on)
                                    .frame(width: 56, height: 56)
                                if n.dot != nil {
                                    Circle().fill(PC.red).frame(width: 12, height: 12)
                                        .background(Circle().fill(Color(hex: 0x060807)).padding(-2))
                                }
                            }
                            Text(n.t).sType(PT.t(13, 16, on ? 700 : 500), tabular: false).foregroundStyle(on ? PC.ink : PC.mu)
                        }
                        .frame(width: 64)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(n.company + (n.dot != nil ? ", a strike sold this week within 0.5 SD" : ""))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }
}

/// "NKE $38.05 ▲ 0.8%", then "Nike · Rebound".
struct PosHeader: View {
    let n: PosBook.Name
    let S0: Double
    var body: some View {
        let mv = n.P0 > 0 ? S0 / n.P0 - 1 : 0
        let strat = n.strategy.isEmpty ? "" : n.strategy.prefix(1).uppercased() + n.strategy.dropFirst()
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(n.t).sType(PT.t(26, 32, 700, tr: -0.02), tabular: false).foregroundStyle(PC.ink)
                Text(PosFmt.price(S0)).sType(PT.t(19, 24)).foregroundStyle(PC.mu)
                Text("\(mv < 0 ? "▼" : "▲") \(PE.pcx(mv))").sType(PT.t(15, 20, 600)).foregroundStyle(mv < 0 ? PC.red : PC.green)
            }
            .lineLimit(1)
            Text(strat.isEmpty ? n.company : "\(n.company) · \(strat)").sType(PT.t(14, 20), tabular: false).foregroundStyle(PC.mu)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(n.company), \(PosFmt.price(S0)), \(mv < 0 ? "down" : "up") \(PE.pcx(mv).replacingOccurrences(of: "%", with: " percent"))\(strat.isEmpty ? "" : ", \(strat)")")
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Every leg

/// README §3.7 on the phone: each row a native switch on the left (Nik 13 Nov 2026), the contract strike first as the
/// title ("110 call · Mar 19", "LULU shares"; never "Hedge", as agreed 12 Nov), the group (Long, Hedge or Income) ·
/// count under it, so far and delta, then the Whole TICKER book row for the legs switched on. So far = (mark − entry) × q × mul;
/// delta = q × 100 × Δ from the grid (shares q). An off row fades to .4, as the web's.
struct PosEveryLeg: View {
    let t: String
    let m: PosName
    let privacy: Bool
    let toggle: (String, Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Every leg").sType(PT.section, tabular: false).foregroundStyle(PC.ink).padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            ForEach(m.legs) { l in
                HStack(spacing: 12) {
                    Toggle(isOn: Binding(get: { l.on }, set: { toggle(l.id, $0) })) {
                        Text(PosSay.words("\(l.contract), \(l.qty)"))
                    }
                    .labelsHidden()
                    .fixedSize()
                    row(Text(l.contract), sub: Text(l.sub), soFar: l.soFar, delta: l.delta, bold: false)
                        .opacity(l.on ? 1 : 0.4)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(PosSay.words("\(l.contract), \(l.sub.replacingOccurrences(of: "−", with: "minus ").replacingOccurrences(of: "+", with: "plus ")), so far \(PosSay.signed(l.soFar, privacy)), delta \(PosFmt.side(l.delta))"))
                }
                .overlay(alignment: .top) { Rectangle().fill(PC.rule).frame(height: 1) }
            }
            HStack(spacing: 12) {
                // Keeps the words in line with the rows' above.
                Toggle("", isOn: .constant(true)).labelsHidden().fixedSize().hidden().accessibilityHidden(true)
                // At, as the web's Whole row (Nov 18): "$8.5K in" green · "$4.3K out" red, the legs switched on.
                let inOut = Text(privacy ? BriefMask.shown : PosFmt.money(m.cashIn)).foregroundStyle(PC.green) + Text(" in · ")
                    + Text(privacy ? BriefMask.shown : PosFmt.money(m.cashOut)).foregroundStyle(PC.red) + Text(" out")
                row(Text("Whole \(t) book"), sub: m.cashIn > 0 || m.cashOut > 0 ? inOut : Text(m.changed ? "with your changes" : "income only"),
                    soFar: m.soFar, delta: m.delta, bold: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(PosSay.words("Whole \(t) book, \(PosSay.money(m.cashIn, privacy)) in, \(PosSay.money(m.cashOut, privacy)) out, so far \(PosSay.signed(m.soFar, privacy)), delta \(PosFmt.side(m.delta))"))
            }
            .padding(.top, 4)
            .overlay(alignment: .top) { Rectangle().fill(PC.ruleStrong).frame(height: 1) }
        }
    }

    private func row(_ l: Text, sub: Text?, soFar: Double, delta: Double, bold: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                l.sType(PT.t(15, 20, bold ? 700 : 600), tabular: false).foregroundStyle(PC.ink)
                if let sub { sub.sType(PT.t(12, 16)).foregroundStyle(PC.mu).lineLimit(1).minimumScaleFactor(0.85) }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(privacy ? BriefMask.shown : PosFmt.money(soFar)).sType(PT.t(15, 20, bold ? 700 : 600))
                    .foregroundStyle(soFar > 0.5 ? PC.green : soFar < -0.5 ? PC.red : PC.ink)
                Text(PosFmt.side(delta)).sType(PT.t(12, 16)).foregroundStyle(bold ? (delta < 0 ? PC.orange : PC.ink) : PC.mu)
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44)
    }
}
