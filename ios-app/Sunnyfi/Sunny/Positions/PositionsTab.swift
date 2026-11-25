//
//  PositionsTab.swift
//  Sunny
//
//  The Positions tab (handoff 2026-11-13-positions §2, 2026-11-18 §2, 2026-11-24 §4), top to bottom:
//    the account strip · large title Positions, "Sunny’s book · Fri Nov 13 close" · Your book (one flat card, Long ·
//    Hedge · Income with Today and All time; Income leads with what is left to earn; Together names each account under
//    every total) · the name strip (Together: Sunny's names, a hairline, Nicolay's) · the name header · the name's own
//    book · Share average · Payoff | Price (the Payoff's touch reads the Greeks at that price) · Every leg (SunnyBook,
//    PositionsEvery.swift: Cards | List, switches and chips) · Intelligence (SunnyStrikes look card, PositionsStrikes.swift,
//    with Try in Payoff kept in public.payoff_tries, PositionsTries.swift).
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
    /// Every leg's view, Cards ("tiles") or List, remembered on the phone (handoff 2026-11-24 §6: sunny.book196p).
    @AppStorage("sunny.book196p") private var bookLook = "tiles"
    /// Every leg's chips switched off, per "book|TICKER" ("ex:2026-11-27", "kind:c", "role:inc"), for as long as the app is open.
    @State private var chips: [String: Set<String>] = [:]
    /// Every leg's groups folded or opened by a tap, per "book|TICKER".
    @State private var folds: [String: [String: Bool]] = [:]
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
    /// Legs switched away from how they start in Every leg (Income on, the rest off), per "book|TICKER".
    @State private var flip: [String: Set<String>] = [:]
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
                // Screens checked in the simulator: `-posOpen Hedge` opens a Your book group; `-posAt intel` (or every, pay)
                // scrolls there; `-posView price` shows Price; `-posLook list` shows Every leg as a list.
                let a = ProcessInfo.processInfo.arguments
                func arg(_ k: String) -> String? { a.firstIndex(of: k).flatMap { a.indices.contains($0 + 1) ? a[$0 + 1] : nil } }
                if let v = arg("-posView") { view = v == "price" ? .price : .payoff }
                if let g = arg("-posOpen") { bookOpen = [g] }
                if let l = arg("-posLook") { bookLook = l }
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
            ownOpen = nil
            payAt = nil; payRange = 12
            if !t.isEmpty, let b = bookID { UserDefaults.standard.set(t, forKey: "positions.last.\(b)") }
            load()
        }
        .onChange(of: pageBook) { _, _ in bookOpen = []; dip() }
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
        if !book.groups.isEmpty {
            PosYourBook(groups: book.groups, open: $bookOpen, privacy: privacy, reduce: reduce,
                        accts: tog ? brief.splitParts.map { ($0.name, PosBook.groups($0.parts)) } : [])
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
            nameSection(n, book: b, sold: book.sold, own: book.nameGroups[n.t] ?? [])
        }
    }

    /// Together: each account's parts of a name's own book (payload.split[i].nameParts[TICKER]); empty on one account.
    private func nameAccts(_ t: String) -> [(name: String, groups: [PosBook.Group])] {
        guard brief.account == .together else { return [] }
        return (brief.splitRaw?.array ?? []).compactMap { p in
            guard let nm = p["name"].string else { return nil }
            return (nm, PosBook.groups(p["nameParts"][t]))
        }
    }

    /// The name's share average after every closed trade (sunny-home share_avg; Together's rows weigh both accounts).
    private func shareAvg(_ t: String) -> (avg: Double, paid: Double)? {
        guard let r = HomeStore.current?.home?.shareAvg?.array.first(where: { $0["t"].string == t }), let paid = r["paid"].double else { return nil }
        let w = r["w"].array.compactMap(\.double)
        return (max(0, w.last ?? paid), paid)
    }

    /// The header, the name's own book, Share average, Payoff | Price, Every leg and Intelligence for the name on screen.
    @ViewBuilder private func nameSection(_ n: PosBook.Name, book b: String, sold: [PE.SoldRow], own: [PosBook.Group]) -> some View {
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
            PosNameBook(t: n.t, groups: own, open: $ownOpen, privacy: privacy, reduce: reduce, accts: nameAccts(n.t))
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
                PosEveryBook(t: n.t, m: every, privacy: privacy, look: $bookLook, folds: folds[offK] ?? [:],
                             fold: { k, open in folds[offK, default: [:]][k] = open },
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

    /// A leg's own switch: a leg held flips from how it starts (sold on, the rest off); a tried leg saves its switch.
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
            let starts = l.q < 0 && !l.sh
            if v == starts { s.remove(l.id) } else { s.insert(l.id) }
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

/// Your book (handoff 2026-11-18 §2.1, 2026-11-24 §4): one flat card. A header row (Your book · Today · All time), then
/// Long, Hedge and Income, the groups the book holds, each its value under its name and its Today and All time ($ over %,
/// green up or kept, red down, never a sign). A tap opens the group's parts in the same columns; a group with one part
/// names it ("Long · Shares") and has no chevron. Income leads with what is left to earn (collected less kept so far),
/// with collected and kept under it; its parts read left (Nik, 24 Nov 2026). Figures from sunny-home
/// (brief_inputs.parts): Today is Home's today split by part, so the rows add up to it; All time is against IBKR's cost,
/// or kept of what was sold.
/// Together: each total carries its accounts in full words under it ("Sunny $248K · Nicolay $367K"); the narrow Today and
/// All time columns keep "S $2.4K" and "N $27.7K", with a key in the header ("S Sunny · N Nicolay"; Nik, 24 Nov 2026).
struct PosYourBook: View {
    let groups: [PosBook.Group]
    @Binding var open: Set<String>
    let privacy: Bool
    let reduce: Bool
    /// Together (handoff 2026-11-24 §2.2): each account's groups. Empty on one account.
    var accts: [(name: String, groups: [PosBook.Group])] = []

    private static let label = PC.say                          // #C7C7CC
    private static let chevron = S.dyn(0x8E8E93, 0x636366)

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { title.fixedSize(); key.fixedSize() }
                    // On a second line when it does not fit beside the title; scaled down, never wider than the column.
                    VStack(alignment: .leading, spacing: 1) { title; key }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private var title: some View {
        Text("Your book").sType(PT.t(13, 16, 600), tabular: false).foregroundStyle(Self.label).lineLimit(1).minimumScaleFactor(0.6)
            .accessibilityAddTraits(.isHeader)
    }
    /// "S Sunny · N Nicolay": the key to the S and N under Today and All time (Together only).
    @ViewBuilder private var key: some View {
        if accts.count > 1 {
            Text(accts.map { "\($0.name.prefix(1)) \($0.name)" }.joined(separator: " · ")).sType(PT.t(12, 16, 500), tabular: false)
                .foregroundStyle(PC.mu).lineLimit(1).minimumScaleFactor(0.5)
                .accessibilityLabel(accts.map { "\($0.name.prefix(1)) is \($0.name)" }.joined(separator: ", "))
        }
    }

    @ViewBuilder private func row(_ g: PosBook.Group) -> some View {
        let one = g.parts.count == 1, isOpen = !one && open.contains(g.title), x = g.sum, inc = g.title == "Income"
        VStack(spacing: 0) {
            Button {
                guard !one else { return }
                withAnimation(S.moving(.easeInOut(duration: 0.25), reduce) ?? .linear(duration: 0)) {
                    if isOpen { open.remove(g.title) } else { open.insert(g.title) }
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        let sub = inc ? "left to earn" : one && g.parts[0].label != g.title ? g.parts[0].label : ""
                        (Text(g.title).foregroundStyle(Self.label)
                         + Text(sub.isEmpty ? "" : " · \(sub)").font(.custom("Inter", size: 15).weight(.medium)).foregroundStyle(PC.mu))
                            .sType(PT.t(15, 20, 600), tabular: false).lineLimit(1).minimumScaleFactor(0.8)
                        Text(money(inc ? x.value - x.all : x.value)).sType(PT.t(24, 28, 700, tr: -0.02)).foregroundStyle(PC.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if let ps = partsOf(g.title) {
                            Text(ps.map { "\($0.name) \(money(inc ? $0.x.value - $0.x.all : $0.x.value))" }.joined(separator: " · "))
                                .sType(PT.t(12, 16, 500), tabular: true).foregroundStyle(PC.mu).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        // The same small grey line as the accounts' line above it, one line (24 Nov 2026: it wrapped).
                        if inc {
                            Text((one ? g.parts[0].label + " · " : "") + "\(money(x.value)) collected · \(money(x.all)) kept")
                                .sType(PT.t(12, 16, 500), tabular: true).foregroundStyle(PC.mu).lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 0) {
                        figure(x.today, x.todayPct, big: true)
                        if let ps = partsOf(g.title) { ForEach(ps, id: \.name) { acctLine($0.name, $0.x.today, grey: inc) }.padding(.top, 3) }
                    }
                    .frame(width: 74, alignment: .trailing)
                    VStack(alignment: .trailing, spacing: 0) {
                        figure(x.all, x.allPct, big: true)
                        if let ps = partsOf(g.title) { ForEach(ps, id: \.name) { acctLine($0.name, $0.x.all, grey: false) }.padding(.top, 3) }
                    }
                    .frame(width: 74, alignment: .trailing)
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
            .accessibilityLabel(said(g, one: one, inc: inc))
            .accessibilityHint(one ? "" : (isOpen ? "Hides its parts" : "Shows its parts"))
            .accessibilityAddTraits(one ? [] : .isButton)
            if isOpen {
                VStack(spacing: 0) {
                    ForEach(g.parts) { p in
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(p.label).sType(PT.t(13, 17), tabular: false).foregroundStyle(PC.mu)
                                Text(inc ? "\(money(p.value - p.all)) left" : money(p.value)).sType(PT.t(15, 20, 600)).foregroundStyle(PC.ink)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            figure(p.today, p.todayPct, big: false).frame(width: 74, alignment: .trailing)
                            figure(p.all, p.allPct, big: false).frame(width: 74, alignment: .trailing)
                            Color.clear.frame(width: 12, height: 1)
                        }
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(PosSay.words("\(p.label), " + (inc ? "\(PosSay.money(p.value - p.all, privacy)) left to earn" : PosSay.money(p.value, privacy))
                                                         + ", today \(PosSay.signed(p.today, privacy)), \(PE.pcx(p.todayPct)), all time \(PosSay.signed(p.all, privacy)), \(PE.pcx(p.allPct))"))
                    }
                }
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(PC.rule).frame(height: 1) }
    }

    /// Each account's part of a group (Together only): its name and the group's sums on that account; nil on one account.
    private func partsOf(_ title: String) -> [(name: String, x: PosBook.Part)]? {
        guard accts.count > 1 else { return nil }
        return accts.map { a in (name: a.name, x: a.groups.first { $0.title == title }?.sum ?? PosBook.Part(key: title, label: title)) }
    }
    /// "S $5.1K" (11/14 600): grey, red when down; Income's Today always grey (the design's pcol).
    private func acctLine(_ name: String, _ v: Double, grey: Bool) -> some View {
        Text("\(name.prefix(1)) \(money(v))").sType(PT.t(11, 14, 600), tabular: true)
            .foregroundStyle(!grey && v < -0.5 ? PC.red : PC.mu)
            .lineLimit(1).minimumScaleFactor(0.8)
            .accessibilityLabel("\(name) \(PosSay.signed(v, privacy))")
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

    /// "Income, 11.5 thousand dollars left to earn of 16.2 thousand collected, today up 820 dollars, 5.1 percent, ...".
    private func said(_ g: PosBook.Group, one: Bool, inc: Bool) -> String {
        let x = g.sum
        let what = one ? "\(g.title), \(g.parts[0].label)" : g.title
        let v = inc ? "\(PosSay.money(x.value - x.all, privacy)) left to earn, of \(PosSay.money(x.value, privacy)) collected" : PosSay.money(x.value, privacy)
        let ac = partsOf(g.title).map { ps in ". " + ps.map { "\($0.name) \(PosSay.money(inc ? $0.x.value - $0.x.all : $0.x.value, privacy))" }.joined(separator: ", ") } ?? ""
        return PosSay.words("\(what), \(v), today \(PosSay.signed(x.today, privacy)), \(PE.pcx(x.todayPct)), all time \(PosSay.signed(x.all, privacy)), \(PE.pcx(x.allPct))\(ac)")
    }
}

/// The picked name's own book (handoff 2026-11-18 §2.3), under the name: Long · Hedge · Income in as many columns as
/// the name holds (never None or To do), each its value and its all-time gain ($ · %, green or red). Income reads what
/// is left to earn, "kept $X of $Y" under it (2026-11-24). A tap on a group with two parts opens them under the row; the
/// open cell sits on a soft tile. Together: each account's part under every total, in full words ("Sunny $48K").
struct PosNameBook: View {
    let t: String
    let groups: [PosBook.Group]
    @Binding var open: String?
    let privacy: Bool
    let reduce: Bool
    /// Together: each account's groups for this name (payload.split[i].nameParts[TICKER]). Empty on one account.
    var accts: [(name: String, groups: [PosBook.Group])] = []

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
                    ForEach(g.parts) { p in partRow(p, inc: g.title == "Income") }
                }
                .padding(.top, 12).padding(.bottom, 4)
                .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(t) in your book")
    }

    /// Each account holding this group, with its value ("Sunny $48K · Nicolay $12K", or "Nicolay $229K" when only one
    /// holds it); nil on one account.
    private func acctWords(_ title: String, inc: Bool) -> String? {
        guard accts.count > 1 else { return nil }
        let ps = accts.compactMap { a -> String? in
            guard let x = a.groups.first(where: { $0.title == title })?.sum else { return nil }
            return "\(a.name) \(money(inc ? x.value - x.all : x.value))"
        }
        return ps.isEmpty ? nil : ps.joined(separator: " · ")
    }

    private func cell(_ g: PosBook.Group) -> some View {
        let x = g.sum, two = g.parts.count > 1, on = two && open == g.title, inc = g.title == "Income"
        let ac = acctWords(g.title, inc: inc)
        return Button {
            guard two else { return }
            withAnimation(S.moving(.easeOut(duration: 0.2), reduce) ?? .linear(duration: 0)) { open = on ? nil : g.title }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(g.title).sType(PT.t(12, 16, 500), tabular: false).foregroundStyle(PC.mu)
                Text(inc ? "\(money(x.value - x.all)) left" : money(x.value)).sType(PT.t(17, 22, 700)).foregroundStyle(PC.ink)
                Text(inc ? "kept \(money(x.all)) of \(money(x.value))" : "\(money(x.all)) · \(PE.pcx(x.allPct))").sType(PT.t(12, 16, 600)).foregroundStyle(tone(x.all))
                if let ac { Text(ac).sType(PT.t(12, 16, 500)).foregroundStyle(PC.mu).padding(.top, 2) }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(on ? S.dynA(0x1D1D1F, 0.06, 0xFFFFFF, 0.08) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(two)
        .padding(.horizontal, -2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PosSay.words("\(t) \(g.title), " + (inc ? "\(PosSay.money(x.value - x.all, privacy)) left, kept \(PosSay.money(x.all, privacy)) of \(PosSay.money(x.value, privacy))"
                                                                 : "\(PosSay.money(x.value, privacy)), \(PosSay.signed(x.all, privacy)), \(PE.pcx(x.allPct))") + (ac.map { ". " + $0 } ?? "")))
        .accessibilityHint(two ? (on ? "Hides its parts" : "Shows its parts") : "")
        .accessibilityAddTraits(two ? .isButton : [])
    }

    private func partRow(_ p: PosBook.Part, inc: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(p.label).sType(PT.t(14, 18), tabular: false).foregroundStyle(PC.say)
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(inc ? "\(money(p.value - p.all)) left" : money(p.value)).sType(PT.t(14, 18, 600)).foregroundStyle(PC.ink)
                Text(inc ? "kept \(money(p.all)) of \(money(p.value))" : "\(money(p.all)) · \(PE.pcx(p.allPct))").sType(PT.t(12, 16, 600)).foregroundStyle(tone(p.all))
            }
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PosSay.words("\(p.label), " + (inc ? "\(PosSay.money(p.value - p.all, privacy)) left, kept \(PosSay.money(p.all, privacy)) of \(PosSay.money(p.value, privacy))"
                                                           : "\(PosSay.money(p.value, privacy)), \(PosSay.signed(p.all, privacy)), \(PE.pcx(p.allPct))")))
    }

    private func tone(_ v: Double) -> Color { v > 0.5 ? PC.green : v < -0.5 ? PC.red : PC.ink }
    private func money(_ v: Double) -> String { privacy ? BriefMask.shown : PosFmt.money(v) }
}

/// The name's share average after every closed trade (handoff 2026-11-24 §4, SunnyPositionsPhone sa189), under the name's
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
        .padding(.top, 12).padding(.bottom, 4)
        .overlay(alignment: .top) { Rectangle().fill(PC.rule).frame(height: 1) }
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
