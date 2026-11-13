//
//  PositionsTab.swift
//  Sunny
//
//  The Positions tab (handoff 2026-11-13-positions §2, App Explorations 154a), view only, top to bottom:
//    the account strip (owners of both books) · large title Positions, "Sunny’s book · Fri Nov 13 close" ·
//    Book totals (three cards sideways: Long, Hedge, Income; Nik's five pieces, D7) · Sold, in SD (a full-width glass
//    row; a tap opens every sold leg on one SD axis, a row tap selects that name and scrolls to Intelligence, D2) ·
//    the name strip (a dot: red short at the priced move by Friday, orange a sold leg within 0.5 SD, A7) · the name
//    header · Price | Payoff (Payoff read only at this Friday's close) · Every leg (no switches) and the Whole TICKER
//    book row · Intelligence for this week, always open (PositionsIntelView).
//  Not on the phone: the SD calculator, What if, Try a trade, leg switches, New and Both, the cover check, dates, table.
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
    @State private var memo = PositionsMemo()

    @State private var name: String = BriefDebug.name ?? ""
    @State private var view: Band = .price
    @State private var soldOpen = false
    /// The open box ("lane|box"): one at a time across the lanes.
    @State private var box: String?
    @State private var scrolled: CGFloat = 0
    @State private var pos = ScrollPosition()
    /// Where Intelligence sits in the page: a Sold in SD row scrolls there (never read in layout).
    @State private var intelY: CGFloat = 0
    @State private var picks = 0
    @State private var intelTick = 0
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
                .padding(.bottom, 120)
                .containerRelativeFrame(.horizontal)
                .coordinateSpace(.named(Self.page))
            }
            .scrollIndicators(.hidden)
            .scrollPosition($pos)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, v in scrolled = v }
            .onChange(of: intelTick) { _, _ in
                // A Sold in SD row tap: once the rows have folded away, bring Intelligence up under the small title bar
                // (scrollTo(y:) puts that point at the safe area's top; the bar is 44 pt under it).
                Task {
                    try? await Task.sleep(for: .milliseconds(reduce ? 60 : 520))
                    withAnimation(S.moving(S.standard(0.5), reduce)) { pos.scrollTo(y: max(0, intelY - 52)) }
                }
            }
            .task {
                #if DEBUG && targetEnvironment(simulator)
                // Screens checked in the simulator: `-posOpen sold` opens Sold, in SD; `-posBox w|ce` opens a box's
                // detail; `-posAt intel` scrolls to Intelligence; `-posView payoff` shows Payoff.
                let a = ProcessInfo.processInfo.arguments
                func arg(_ k: String) -> String? { a.firstIndex(of: k).flatMap { a.indices.contains($0 + 1) ? a[$0 + 1] : nil } }
                if arg("-posView") == "payoff" { view = .payoff }
                if arg("-posOpen") == "sold" { try? await Task.sleep(for: .milliseconds(900)); soldOpen = true }
                if let b = arg("-posBox") { box = b }
                if let at = arg("-posAt") { try? await Task.sleep(for: .milliseconds(1400)); proxy.scrollTo(at, anchor: .top) }
                if let y = BriefDebug.scroll { try? await Task.sleep(for: .milliseconds(1200)); pos.scrollTo(y: y) }
                #endif
            }
        }
        .background(SBackground(glows: false))
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
            if !t.isEmpty, let b = bookID { UserDefaults.standard.set(t, forKey: "positions.last.\(b)") }
            box = nil
            load()
        }
        .onChange(of: soldOpen) { _, open in if open { loadSold() } }
        .onChange(of: pageBook) { _, _ in soldOpen = false; box = nil; dip() }
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
        PosTotals(groups: book.groups, privacy: privacy)
        if !book.sold.isEmpty {
            PosSoldInSD(book: book, open: $soldOpen, reduce: reduce) { t in
                if t != name { name = t }
                withAnimation(S.moving(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45), reduce)) { soldOpen = false }
                intelTick += 1
            }
            .padding(.horizontal, Self.margin)
        }
        PosStrip(names: book.names, selected: n?.t ?? "") { t in
            guard t != name else { return }
            picks += 1
            withAnimation(S.fade) { name = t }
        }
        .sensoryFeedback(.selection, trigger: picks)
        if let n {
            nameSection(n, book: b)
        }
    }

    /// The header, Price | Payoff, Every leg and Intelligence for the name on screen.
    @ViewBuilder private func nameSection(_ n: PosBook.Name, book b: String) -> some View {
        let m = brief.positions.model(b, n.t)
        let built = brief.positions.models["\(b)|\(n.t)"]?.built ?? ""
        let nm = m.map { mm in memo.name(key: "\(b)|\(n.t)|\(built)|\(brief.built ?? "")") { PosName.build(mm, inputs: brief.inputs) } }
        let S0 = nm?.S0 ?? n.S0
        PosHeader(n: n, S0: S0).padding(.horizontal, Self.margin)
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
                    let w = charts.chart(b, n.t)
                    let pr = w.flatMap { w in memo.price(key: "\(b)|\(n.t)|\(w.dates.last ?? "")|\(S0)") { PosPrice.build(w, S0: S0, today: MarketClock.ny(SClock.now()).date) } }
                    PosPriceChart(price: pr, strikes: nm?.strikes ?? [], S0: S0, failed: charts.hasFailed(b, n.t))
                } else if let p = nm?.payoff {
                    PosPayoffView(t: n.t, S0: S0, p: p, privacy: privacy)
                } else {
                    loadingBox(error: brief.positions.error(b, n.t), height: 300)
                }
            }
            .transition(.opacity)
        }
        .animation(S.fade, value: view)
        .padding(.horizontal, Self.margin)
        Group {
            if let nm { PosEveryLeg(t: n.t, m: nm, privacy: privacy) }
            else { loadingBox(error: brief.positions.error(b, n.t), height: 160) }
        }
        .padding(.horizontal, Self.margin)
        intelSection(n, book: b)
            .id("intel")
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.page)).minY } action: { intelY = $0 }
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
        if !names.contains(name) {
            let last = bookID.flatMap { UserDefaults.standard.string(forKey: "positions.last.\($0)") }
            let live = brief.live?.names ?? []
            if let l = last, names.contains(l) { name = l }
            else if let s = live.first(where: { $0["short"].bool })?["t"].string { name = s }
            else { name = live.max { ($0["size"].double ?? 0) < ($1["size"].double ?? 0) }?["t"].string ?? names.first ?? "" }
        }
        load()
    }
    /// The name's grid (sunny-positions), its closes (sunny-chart) and its chain (sunny-sd).
    private func load() {
        guard !name.isEmpty, let b = bookID, let built = brief.built,
              let n = brief.live?.names.first(where: { $0["t"].string == name }) else { return }
        brief.positions.load(book: b, t: name, built: built, name: n)
        charts.load(book: b, t: name)
        sd.load(book: b, t: name)
        if soldOpen { loadSold() }
    }
    /// Sold, in SD opened: every name with a sold leg, for the SD each sat at when sold.
    private func loadSold() {
        guard let b = bookID, let inp = brief.inputs else { return }
        for n in inp["names"].array where n["legs"].array.contains(where: { ($0["q"].double ?? 0) < 0 && $0["ty"].string != "S" }) {
            if let t = n["t"].string { sd.load(book: b, t: t) }
        }
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
struct PosTotals: View {
    let groups: [PosBook.Group]
    let privacy: Bool
    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(groups) { g in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(g.title.uppercased()).sType(PT.t(12, 16, 700, tr: 0.05), tabular: false).foregroundStyle(PC.mu)
                            .accessibilityHidden(true)
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(g.pieces) { p in piece(g.title, p).frame(maxWidth: .infinity, alignment: .leading) }
                            if g.pieces.count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(width: 244, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .modifier(PosSoftCard(radius: 16, fill: PC.totalsFill))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Book totals")
    }

    private func piece(_ group: String, _ p: PosBook.Piece) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(p.label).sType(PT.t(13, 18), tabular: false).foregroundStyle(PC.muT)
            if let f = p.fig {
                let g = p.sold ? f.paid - f.now : f.now - f.paid, pct = f.paid > 0 ? g / f.paid : 0
                Text(privacy ? BriefMask.shown : PosFmt.money(p.sold ? f.paid : f.now)).sType(PT.t(19, 24, 600)).foregroundStyle(PC.ink)
                Text("\(p.sold ? (g < 0 ? "lost " : "kept ") : "")\(privacy ? BriefMask.shown : PosFmt.money(g)) · \(PE.pcx(pct))")
                    .sType(PT.t(13, 18, 600)).foregroundStyle(g > 0.5 ? PC.green : g < -0.5 ? PC.red : PC.ink)
            } else {
                Text("None").sType(PT.t(19, 24, 600), tabular: false).foregroundStyle(PC.mu)
            }
        }
        .lineLimit(1).minimumScaleFactor(0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(said(group, p))
    }

    /// "Income calls, collected 13.5 thousand dollars, kept 3.9 thousand dollars, 28.9 percent".
    private func said(_ group: String, _ p: PosBook.Piece) -> String {
        let n = "\(group) \(p.label.lowercased())"
        guard let f = p.fig else { return "\(n), none" }
        let g = p.sold ? f.paid - f.now : f.now - f.paid, pct = PE.pcx(f.paid > 0 ? g / f.paid : 0)
        return PosSay.words(p.sold ? "\(n), collected \(PosSay.money(f.paid, privacy)), \(g < 0 ? "lost" : "kept") \(PosSay.money(g, privacy)), \(pct)"
                                   : "\(n), \(PosSay.money(f.now, privacy)), \(g < 0 ? "down" : "up") \(PosSay.money(g, privacy)), \(pct)")
    }
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
                            ZStack(alignment: .topTrailing) {
                                Circle().fill(PC.stripFill)
                                    .overlay { Circle().strokeBorder(on ? PC.ink : PC.stripRing, lineWidth: on ? 3 : 1.5) }
                                    .overlay { Text(n.t).font(.inter(n.t.count > 4 ? 11 : 12, 700)).tracking(-0.12).foregroundStyle(PC.ink).lineLimit(1).minimumScaleFactor(0.7).padding(.horizontal, 4) }
                                    .frame(width: 56, height: 56)
                                if let d = n.dot {
                                    Circle().fill(PC.tone(d)).frame(width: 12, height: 12)
                                        .background(Circle().fill(PC.page).padding(-2))
                                }
                            }
                            Text(n.t).sType(PT.t(13, 16, on ? 700 : 400), tabular: false).foregroundStyle(on ? PC.ink : PC.mu)
                        }
                        .frame(width: 64)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(n.company + (n.dot == .red ? ", short at the priced move by Friday" : n.dot == .orange ? ", a sold leg within 0.5 SD" : ""))
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

// MARK: - Every leg (no switches)

/// README §3.7 on the phone: each row the leg (Long, Hedge or Income), contract · count, so far and delta, then the
/// Whole TICKER book row. So far = (mark − entry) × q × mul; delta = q × 100 × Δ from the grid (shares q).
struct PosEveryLeg: View {
    let t: String
    let m: PosName
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Every leg").sType(PT.section, tabular: false).foregroundStyle(PC.ink).padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            ForEach(m.legs) { l in
                row(l.group, sub: "\(l.contract) · \(l.qty)", soFar: l.soFar, delta: l.delta, bold: false)
                    .overlay(alignment: .top) { Rectangle().fill(PC.rule).frame(height: 1) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(PosSay.words("\(l.group), \(l.contract), \(l.qty), so far \(PosSay.signed(l.soFar, privacy)), delta \(PosFmt.side(l.delta))"))
            }
            row("Whole \(t) book", sub: nil, soFar: m.soFar, delta: m.delta, bold: true)
                .padding(.top, 4)
                .overlay(alignment: .top) { Rectangle().fill(PC.ruleStrong).frame(height: 1) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(PosSay.words("Whole \(t) book, so far \(PosSay.signed(m.soFar, privacy)), delta \(PosFmt.side(m.delta))"))
        }
    }

    private func row(_ l: String, sub: String?, soFar: Double, delta: Double, bold: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(l).sType(PT.t(15, 20, bold ? 700 : 600), tabular: false).foregroundStyle(PC.ink)
                if let sub { Text(sub).sType(PT.t(12, 16)).foregroundStyle(PC.mu).lineLimit(1).minimumScaleFactor(0.85) }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(privacy ? BriefMask.shown : PosFmt.money(soFar)).sType(PT.t(15, 20, bold ? 700 : 600))
                    .foregroundStyle(soFar > 0.5 ? PC.green : soFar < -0.5 ? PC.red : PC.ink)
                Text(PosFmt.side(delta)).sType(PT.t(12, 16)).foregroundStyle(bold ? (delta < 0 ? PC.orange : PC.ink) : PC.mu)
            }
        }
        .padding(.vertical, bold ? 6 : 6)
        .frame(minHeight: 44)
    }
}
