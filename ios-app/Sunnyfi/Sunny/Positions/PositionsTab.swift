//
//  PositionsTab.swift
//  Sunny
//
//  The Positions tab (handoff 2026-11-13-positions §2, 2026-11-18 §2, 2026-11-24 §4), top to bottom:
//    the account strip · large title Positions, "Sunny’s book · Fri Nov 13 close" · Your book (one flat card, a block
//    per leg: Shares, Calls bought, Calls sold, Puts bought, Puts sold, all time only; no account lines on Together) ·
//    the name strip (Together: Sunny's names, a hairline, Nicolay's) · the
//    name header · the name's own book (the same blocks) · Share average · Payoff | Price (the Payoff's touch reads the Greeks at that
//    price) · Every leg (SunnyBook, PositionsEvery.swift: List only, switches and chips on three lines) · Intelligence
//    (SunnyStrikes look card, PositionsStrikes.swift: strike tiles in one swiped row, the strike card, Try in Payoff kept
//    in public.payoff_tries, PositionsTries.swift).
//    Legs sold start on, shares and legs bought start off (Nik, 13 Nov 2026, every name). A leg counts in Payoff and its
//    Greeks when its own switch and each of its chips are on, per book and name, for as long as the app is open; tried
//    legs count too. The Price chart keeps every strike held; Your book stays whole.
//    No explanation or how-to lines on the face of the screen (Nik, 24 Nov 2026): labels, figures and statuses only.
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
    @State private var tries = PositionsTries.shared
    /// Every leg's chips switched off, per "book|TICKER" ("ex:2026-11-27", "kind:s", "leg:c:sold"), for as long as the app is open.
    @State private var chips: [String: Set<String>] = [:]
    /// Intelligence: what is picked, and the contracts added in Your trade, per "book|TICKER".
    @State private var strikeSel: [String: PosStrikeSel] = [:]
    @State private var trades: [String: [String: Int]] = [:]
    /// Try in Payoff scrolls the page to the Payoff.
    @State private var scrollTo: String?
    /// The Payoff's date (an index on its slider; nil = the end, the expiry) and range in % either side (168b).
    @State private var payAt: Int?
    @State private var payRange = 12
    /// The Price chart's 1 SD layer, remembered (round 164; the web keeps it as sunny.cone164 too).
    @AppStorage("sunny.cone164") private var cone = false
    @State private var memo = PositionsMemo()

    @State private var name: String = BriefDebug.name ?? ""
    /// Payoff first and open on it, Price second (Nik, 20 Nov 2026).
    @State private var view: Band = .payoff
    /// Legs switched off in Every leg (every leg starts on), per "book|TICKER".
    @State private var flip: [String: Set<String>] = [:]
    @State private var scrolled: CGFloat = 0
    @State private var pos = ScrollPosition()
    @State private var picks = 0
    // The account switch, as Home does it: the page at 15% and 28 pt toward the new account, then back.
    @State private var faded = false
    @State private var slid = false
    @State private var dipDir: CGFloat = 0
    @State private var settling: Task<Void, Never>?

    enum Band: Hashable { case price, payoff }
    static let page = "positionsTab"
    static let margin: CGFloat = 16

    private var bookID: String? { brief.book }
    private var pageBook: BriefAccount { brief.account }
    private var pageReady: Bool { brief.book == nil || brief.book == pageBook.book }

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
            // The open Positions tab tapped again: back to the top (as Home and Income do).
            .onChange(of: router.topTick[.positions]) { _, _ in withAnimation(S.moving(S.page, reduce)) { pos.scrollTo(edge: .top) } }
            .onChange(of: scrollTo) { _, id in
                guard let id else { return }
                withAnimation(S.moving(.easeInOut(duration: 0.45), reduce)) { proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.12)) }
                scrollTo = nil
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, v in scrolled = v }
            .task {
                #if DEBUG && targetEnvironment(simulator)
                // Screens checked in the simulator: `-posAt intel` (or every, pay) scrolls there; `-posView price` shows Price;
                // `-posChips leg:c:sold,kind:s` switches those Every leg chips off for the name on screen.
                let a = ProcessInfo.processInfo.arguments
                func arg(_ k: String) -> String? { a.firstIndex(of: k).flatMap { a.indices.contains($0 + 1) ? a[$0 + 1] : nil } }
                if let v = arg("-posView") { view = v == "price" ? .price : .payoff }
                if let c = arg("-posChips") {
                    try? await Task.sleep(for: .milliseconds(800))
                    chips["\(bookID ?? "S")|\(name)"] = Set(c.split(separator: ",").map(String.init))
                }
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
        // Per-screen loading (18 Nov 2026): Home's inputs come with each update only while Positions is on show.
        .onAppear { HomeStore.need(.inputs, true) }
        .onDisappear { HomeStore.need(.inputs, false) }
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
            payAt = nil; payRange = 12
            if !t.isEmpty, let b = bookID { UserDefaults.standard.set(t, forKey: "positions.last.\(b)") }
            load()
        }
        .onChange(of: pageBook) { _, _ in dip() }
        // Back from Overview, even to the same account, the page plays the same move (handoff 2026-11-18 §1.2).
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
        let tog = brief.account == .together
        if !book.parts.isEmpty {
            PosYourBook(parts: book.parts, tickers: book.names.count, privacy: privacy)
                .padding(.horizontal, Self.margin)
        }
        // Together: Sunny's names, a hairline, then Nicolay's (each account's names, payload.split[i].names).
        PosStrip(names: book.names, selected: n?.t ?? "", groups: tog ? (brief.splitRaw?.array ?? []).map { $0["names"].array.compactMap(\.string) } : []) { t in
            guard t != name else { return }
            picks += 1
            withAnimation(S.fade) { name = t }
        }
        .sensoryFeedback(.selection, trigger: picks)
        if let n {
            nameSection(n, book: b, sold: book.sold, own: book.nameParts[n.t] ?? [])
        }
    }

    /// The name's share average after every closed trade (sunny-home share_avg; Together's rows weigh both accounts).
    private func shareAvg(_ t: String) -> (avg: Double, paid: Double)? {
        guard let r = HomeStore.current?.home?.shareAvg?.array.first(where: { $0["t"].string == t }), let paid = r["paid"].double else { return nil }
        let w = r["w"].array.compactMap(\.double)
        return (max(0, w.last ?? paid), paid)
    }

    /// The header, the name's own book, Share average, Payoff | Price, Every leg and Intelligence for the name on screen.
    @ViewBuilder private func nameSection(_ n: PosBook.Name, book b: String, sold: [PE.SoldRow], own: [PosBook.Part]) -> some View {
        let m = brief.positions.model(b, n.t)
        let built = brief.positions.models["\(b)|\(n.t)"]?.built ?? ""
        let offK = "\(b)|\(n.t)", offs = flip[offK] ?? [], cf = chips[offK] ?? []
        let nm = m.map { mm in
            memo.name(key: "\(b)|\(n.t)|\(built)|\(brief.built ?? "")|\(offs.sorted().joined(separator: ","))") {
                PosName.build(mm, inputs: brief.inputs, flip: offs)
            }
        }
        // Home's price every 15 s (the grid now refreshes on a real move or each minute, PositionsLive).
        let S0 = n.S0 > 0 ? n.S0 : (nm?.S0 ?? 0)
        let reply = sd.reply(b, n.t)
        let trs = tries.list(b, n.t), tsig = trs.map { "\($0.id)\($0.on)" }.joined(separator: ",")
        let now = MarketClock.ny(SClock.now())
        let closed = Set(brief.calendar.filter { $0.kind == "closed" }.map(\.date))
        let priced = m.map { mm in
            memo.tries(key: "\(b)|\(n.t)|\(built)|\(sd.version)|\(tries.version)|\(tsig)") { PosTryLeg.price(trs, reply: reply, model: mm) }
        } ?? []
        // Every leg (SunnyBook): a leg counts when its own switch and each of its chips are on.
        let every = m.map { mm in
            memo.every(key: "\(b)|\(n.t)|\(built)|\(brief.built ?? "")|\(offs.sorted().joined(separator: ","))|\(cf.sorted().joined(separator: ","))|\(tsig)|\(tries.version)|\(sd.version)|\(now.date)") {
                PosEvery.build(mm, inputs: brief.inputs, offs: PosName.offs(mm, flip: offs), chips: cf, sold: sold.filter { $0.l.t == n.t },
                               tries: priced, S0: S0, today: now.date, mins: now.minutes, closed: closed)
            }
        }
        PosHeader(n: n, S0: S0).padding(.horizontal, Self.margin)
        if !own.isEmpty {
            PosNameBook(t: n.t, parts: own, privacy: privacy)
                .padding(.horizontal, Self.margin)
                .padding(.top, -4)
        }
        if let sa = shareAvg(n.t) {
            PosShareAvg(avg: sa.avg, paid: sa.paid).padding(.horizontal, Self.margin).padding(.top, -6)
        }
        VStack(alignment: .leading, spacing: 12) {
            Color.clear.frame(height: 0).id("pay")
            Picker("Payoff or price", selection: $view) {
                Text("Payoff").tag(Band.payoff)
                Text("Price").tag(Band.price)
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .sensoryFeedback(.selection, trigger: view)
            Group {
                if view == .price {
                    // A sold strike wears its Sold in SD closeness (Nik, 14 Nov 2026, "4 + 2").
                    let w = charts.chart(b, n.t), stk = PosPrice.toned(nm?.strikes ?? [], sold.filter { $0.l.t == n.t })
                    // This week's IV (Home's brief_inputs, the Friday chain's at the money), for the strikes' SD and the cone.
                    let ivNow = brief.inputs?["names"].array.first { $0["t"].string == n.t }?["iv"].double
                    let pr = w.flatMap { w in
                        memo.price(key: "\(b)|\(n.t)|\(w.dates.last ?? "")|\(w.hours?.count ?? 0)|\(S0)|\(now.date)|\(now.minutes)|\(cone)|\(stk.map { $0.id + ($0.tone?.rawValue ?? "") }.joined(separator: ","))") {
                            PosPrice.build(w, S0: S0, today: now.date, mins: now.minutes, closed: closed, strikes: stk, iv: ivNow, cone: cone)
                        }
                    }
                    PosPriceChart(price: pr, failed: charts.hasFailed(b, n.t), cone: $cone)
                } else if let mm = m, let nm, !nm.dates.isEmpty {
                    let ai = min(payAt ?? nm.dateOpen, nm.dateEnd), stop = nm.dates[ai].i
                    let off = every?.offGrid ?? PosName.offs(mm, flip: offs), extra = every?.onTries ?? []
                    let xsig = extra.map { "\($0.t.id):\($0.iv)" }.joined(separator: ",")
                    if let p = memo.payoff(key: "\(b)|\(n.t)|\(built)|\(brief.built ?? "")|\(off.sorted().joined(separator: ","))|\(xsig)|\(stop)|\(payRange)", {
                        PosName.payoff(mm, off: off, stop: stop, range: Double(payRange) / 100, hold: nm.dates.map(\.i), extra: extra)
                    }) {
                        let tt = mm.stops.indices.contains(stop) ? mm.stops[stop].tt : 0
                        PosPayoffView(t: n.t, S0: S0, p: p, privacy: privacy, changed: nm.changed || !cf.isEmpty || !extra.isEmpty, dates: nm.dates,
                                      at: Binding(get: { ai }, set: { payAt = $0 }), rangePct: $payRange, target: targets.price(b, n.t),
                                      gone: PosName.gone(mm, off: off, stop: stop),
                                      greeksAt: { x in PosName.greeks(mm, x, tt, off: off, extra: extra) })
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
            if let mm = m, let every {
                PosEveryBook(t: n.t, m: every, privacy: privacy,
                             toggle: { l in withAnimation(S.fade) { toggleLeg(l, mm, book: b, t: n.t) } },
                             setL: { ls, v in withAnimation(S.fade) { setLegs(ls, v, mm, book: b, t: n.t) } },
                             chip: { id in
                                 withAnimation(S.fade) {
                                     var c = chips[offK] ?? []
                                     if c.contains(id) { c.remove(id) } else { c.insert(id) }
                                     chips[offK] = c
                                 }
                             },
                             all: {
                                 withAnimation(S.fade) {
                                     if every.anyOn { chips[offK] = every.allOffChips }
                                     else { chips[offK] = []; setLegs(every.legs, true, mm, book: b, t: n.t) }
                                 }
                             },
                             remove: { l in if let id = l.tryID { withAnimation(S.fade) { tries.remove(book: b, t: n.t, id: id) } } })
                    .id("every")
            }
            else { loadingBox(error: brief.positions.error(b, n.t), height: 160) }
        }
        .padding(.horizontal, Self.margin)
        intelSection(n, book: b, tries: trs)
            .id("intel")
            .padding(.horizontal, Self.margin)
    }

    /// A leg's own switch: a leg held flips from how it starts (every leg on); a tried leg saves its switch.
    private func toggleLeg(_ l: PosEvery.Leg, _ m: PositionsModel, book b: String, t: String) {
        if let id = l.tryID { tries.setOn(book: b, t: t, ids: [id], !l.own); return }
        let k = "\(b)|\(t)"
        var s = flip[k] ?? []
        if s.contains(l.id) { s.remove(l.id) } else { s.insert(l.id) }
        flip[k] = s
    }
    /// A group's switch, and Switch on all: each leg on (or off) whatever its start.
    private func setLegs(_ ls: [PosEvery.Leg], _ v: Bool, _ m: PositionsModel, book b: String, t: String) {
        let k = "\(b)|\(t)"
        var s = flip[k] ?? []
        for l in ls where l.tryID == nil {
            if v { s.remove(l.id) } else { s.insert(l.id) }
        }
        flip[k] = s
        let ti = Set(ls.compactMap(\.tryID))
        if !ti.isEmpty { tries.setOn(book: b, t: t, ids: ti, v) }
    }

    @ViewBuilder private func intelSection(_ n: PosBook.Name, book b: String, tries trs: [PosTry]) -> some View {
        let reply = sd.reply(b, n.t)
        let friday = brief.live?.friday ?? MarketClock.ny(SClock.now()).date
        let today = MarketClock.ny(SClock.now()).date
        let walls = brief.inputs?["names"].array.first { $0["t"].string == n.t }?["walls"]
        let st = reply.flatMap { r in memo.strikes(key: "\(b)|\(n.t)|\(sd.version)|\(friday)|\(today)") { PosStrikes.build(r, friday: friday, today: today, homeWalls: walls) } }
        let k = "\(b)|\(n.t)"
        // Your trade opens on what is in Payoff already (the tries), so the button reads In Payoff · Undo.
        let seed = Dictionary(trs.map { ("\($0.ex):\($0.ty):\(PE.jsNum($0.K))", $0.n) }, uniquingKeysWith: +)
        let trade = trades[k] ?? seed
        let sig = { (d: [String: Int]) in d.filter { $0.value > 0 }.map { "\($0.key):\($0.value)" }.sorted().joined(separator: ",") }
        PosStrikesView(t: n.t, m: st, failed: reply == nil && sd.hasFailed(b, n.t), loaded: reply != nil,
                       sel: Binding(get: { strikeSel[k] ?? PosStrikeSel() }, set: { strikeSel[k] = $0 }),
                       trade: Binding(get: { trade }, set: { trades[k] = $0 }),
                       tried: !sig(trade).isEmpty && sig(trade) == sig(seed)) { list in
            tries.set(book: b, t: n.t, list)
            trades[k] = trade
            if !list.isEmpty {
                withAnimation(S.fade) { view = .payoff }
                scrollTo = "pay"
            }
        }
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
        let who = pageBook.bookTitle
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
        PositionsTries.shared.load(book: b)
        PositionsCharts.shared.load(book: b, t: t)
        SDStore.shared.load(book: b, t: t)
    }
    /// The name's grid (sunny-positions), its closes (sunny-chart) and its chain (sunny-sd).
    private func load() {
        guard !name.isEmpty, let b = bookID, let built = brief.built,
              let n = brief.live?.names.first(where: { $0["t"].string == name }) else { return }
        brief.positions.load(book: b, t: name, built: built, name: n, legs: Self.legSig(brief, name))
        targets.load(book: b)
        tries.load(book: b)
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

// MARK: - Your book

/// Your book (Nik, 24 Nov 2026: "Move away from Long, Hedge and Income to each leg"; "No need for Today and All time,
/// just all time"; 25 Nov: "horizontal cards ... to save on scrolling", "iOS liquid glass effect so not a black box"):
/// "Your book" with "9 tickers · 58 legs" on the right, then one Liquid Glass card per leg the book holds, side by side
/// and swiped sideways, in Nik's order (Shares, Calls bought, Calls sold, Puts bought, Puts sold), all time only.
/// Figures from sunny-home (brief_inputs.parts). Together shows the sums only: no account lines, no S or N.
struct PosYourBook: View {
    let parts: [PosBook.Part]
    let tickers: Int
    let privacy: Bool

    var body: some View {
        let legs = parts.reduce(0) { $0 + $1.nl }
        let count = "\(tickers) \(tickers == 1 ? "ticker" : "tickers") · \(legs) \(legs == 1 ? "leg" : "legs")"
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Your book").sType(PT.t(20, 24, 700), tabular: false).foregroundStyle(PC.ink).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(count).sType(PT.t(15, 20), tabular: true).foregroundStyle(PC.mu).lineLimit(1)
                    .accessibilityLabel(PosSay.words(count))
            }
            PosPartCards(parts: parts, privacy: privacy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The legs side by side, one Liquid Glass card each (.glassEffect, the system's own: clear over the page, solid with
/// Reduce Transparency), swiped sideways freely; the row runs to the screen edges and the next card peeks.
/// Every card is as tall as the tallest, so the row reads as one band.
struct PosPartCards: View {
    let parts: [PosBook.Part]
    let privacy: Bool
    /// Tap any card and every card's change reads in dollars instead of %, and stays that way (Nik, 25 Nov 2026).
    @AppStorage("pos.changeInDollars") private var inDollars = false
    @State private var taps = 0
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(parts) { p in
                    // Its own height, never squeezed: a card's lines keep 14 pt whatever the tallest card is.
                    // 225 x 75 (Nik, 25 Nov 2026): one line under the label, the next card peeks in from the right.
                    PosPartBlock(p: p, privacy: privacy)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .frame(width: 225, height: 75, alignment: .leading)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                        .contentShape(.rect(cornerRadius: 20))
                        .onTapGesture { taps += 1; withAnimation(.snappy) { inDollars.toggle() } }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        // Free flowing, no snap to a card (Nik, 25 Nov 2026).
        .sensoryFeedback(.selection, trigger: taps)
        .contentMargins(.horizontal, PositionsTab.margin, for: .scrollContent)
        .scrollClipDisabled()
        .padding(.horizontal, -PositionsTab.margin)
    }
}

/// One leg of a book (Your book and the name's own book), one line under the label (Nik, 25 Nov 2026: "Now (change %),
/// on tap change dollars, TV", kept on one line): what it is worth now big in ink (sold: what it costs to buy back),
/// then the all-time change in brackets, green gained or kept, red lost, never a sign: the % (on cost; sold: the share
/// of what was collected) or, after a tap on any card, the dollars; options end the line with their time value.
struct PosPartBlock: View {
    let p: PosBook.Part
    let privacy: Bool
    @AppStorage("pos.changeInDollars") private var inDollars = false
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.sTypeScales) private var scales

    var body: some View {
        let up = p.all >= 0, c = tone(p.all)
        let word = p.sold ? (up ? "kept" : "lost") : (up ? "gain" : "loss")
        let pctWord = p.sold ? "captured" : "return"
        VStack(alignment: .leading, spacing: 0) {
            Text(p.label).sType(PT.t(14, 18), tabular: false).foregroundStyle(PC.mu).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // Big figure 18 (Nik, 25 Nov 2026). The time value never shrinks: it takes its room first, and a
                // tight card shrinks the figures instead.
                Text(money(p.now)).sType(PT.t(18, 24, 700, tr: -0.01)).foregroundStyle(PC.ink).layoutPriority(1)
                Text("(\(inDollars ? money(p.all) : pc0(p.pct)))").sType(PT.t(17, 22, 600)).foregroundStyle(c)
                    .contentTransition(.numericText()).layoutPriority(1)
                Spacer(minLength: 6)
                if let tv = p.tv {
                    tvLine(tv).sType(PT.t(14, 18), tabular: true).foregroundStyle(PC.mu)
                        .minimumScaleFactor(1).fixedSize().layoutPriority(3)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(said(word, pctWord))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { withAnimation(.snappy) { inDollars.toggle() } }
    }

    /// A clock, then "$92K": time value (Nik, 25 Nov 2026: "Instead of TV can we use a time icon?"), the clock muted,
    /// the figure semibold in ink; VoiceOver still says "time value".
    /// Inter is one variable font, so the semibold is its own font (fontWeight cannot reach the wght axis).
    private func tvLine(_ tv: Double) -> Text {
        let size = scales ? SDynamic.scaled(14, dts) : 14
        let semi = Font.inter(size, 600, tabular: true)
        return Text(Image(systemName: "clock")).font(.system(size: size - 1, weight: .medium)) + Text(" ")
            + Text(money(tv)).font(semi).foregroundStyle(PC.ink)
    }

    /// "Calls bought, 92 thousand now, loss 46 thousand dollars, 33 percent return, 91 thousand time value".
    private func said(_ word: String, _ pctWord: String) -> String {
        let fig = { (v: Double) in PosSay.money(v, privacy).replacingOccurrences(of: " dollars", with: "") }
        let tv = p.tv.map { ", \(fig($0)) time value" } ?? ""
        return PosSay.words("\(p.label), \(fig(p.now)) now, \(word) \(PosSay.money(p.all, privacy)), \(pc0(p.pct)) \(pctWord)\(tv)")
    }

    private func tone(_ v: Double) -> Color { v > 0.5 ? PC.green : v < -0.5 ? PC.red : PC.ink }
    /// Whole K and M, no decimals, no sign (Nik, 25 Nov 2026: "Round off the numbers also to be K M no decimals"):
    /// $92.3K reads $92K, $7.8K $8K; under $1K whole dollars.
    private func money(_ v: Double) -> String {
        if privacy { return BriefMask.shown }
        let a = abs(v)
        if a >= 999_500 { return "$\(Int((a / 1_000_000).rounded()))M" }
        if a >= 999.5 { return "$\(Int((a / 1_000).rounded()))K" }
        return "$\(Int(a.rounded()))"
    }
    /// A whole-number percent, no sign (Nik, 25 Nov 2026: "Use no decimal in %"): 33.2% reads 33%.
    private func pc0(_ x: Double) -> String { "\(Int((abs(x) * 100).rounded()))%" }
}

/// The picked name's own book (handoff 2026-11-18 §2.3; Nik, 24 and 25 Nov 2026), under the name: the same glass cards
/// as Your book for the legs this name holds, in the same order, swiped sideways; a rule under them. No header row; no
/// account lines on Together.
struct PosNameBook: View {
    let t: String
    let parts: [PosBook.Part]
    let privacy: Bool
    var body: some View {
        PosPartCards(parts: parts, privacy: privacy)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6).padding(.bottom, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(PC.rule).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(t) in your book")
    }
}

/// The name's share average after the premium kept on sold calls and puts (Nik, 24 Nov 2026; handoff 2026-11-24 §4, SunnyPositionsPhone sa189), under the name's
/// own book: "Share average" and the average on one line, "Paid $Y" under it. Only names that have one.
struct PosShareAvg: View {
    let avg: Double
    let paid: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Share average").sType(PT.t(15, 20, 600), tabular: false).foregroundStyle(PC.ink)
                Spacer(minLength: 8)
                Text(PosFmt.price(avg)).sType(PT.t(17, 22, 700)).foregroundStyle(PC.ink)
            }
            Text("Paid \(PosFmt.price(paid))").sType(PT.t(13, 18), tabular: true).foregroundStyle(PC.mu)
        }
        // No rule of its own: the name's book above ends on one (two lines 12 pt apart read as a mistake).
        .padding(.top, 12).padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Share average \(PosFmt.price(avg)), paid \(PosFmt.price(paid))")
    }
}

// MARK: - The name strip and the header

struct PosStrip: View {
    let names: [PosBook.Name]
    let selected: String
    /// Together: each account's names (Sunny's, then Nicolay's), a hairline between; empty on one account.
    var groups: [[String]] = []
    let pick: (String) -> Void
    var body: some View {
        let parts = sections
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { i, ns in
                    if i > 0 {
                        Rectangle().fill(PC.ruleStrong).frame(width: 1, height: 40).padding(.horizontal, 4).padding(.top, 8)
                            .accessibilityHidden(true)
                    }
                    ForEach(ns) { n in logo(n) }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }

    /// The names in book order, cut into the accounts' groups (a name both hold sits with the first); any left over last.
    private var sections: [[PosBook.Name]] {
        guard groups.count > 1 else { return [names] }
        var used = Set<String>(), out: [[PosBook.Name]] = []
        for g in groups {
            let ns = names.filter { g.contains($0.t) && !used.contains($0.t) }
            used.formUnion(ns.map(\.t))
            if !ns.isEmpty { out.append(ns) }
        }
        let rest = names.filter { !used.contains($0.t) }
        if !rest.isEmpty { out.append(rest) }
        return out
    }

    private func logo(_ n: PosBook.Name) -> some View {
        let on = n.t == selected
        return Button { pick(n.t) } label: {
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
