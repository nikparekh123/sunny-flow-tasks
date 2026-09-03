//
//  SunnyFeed.swift
//  Sunny — the pane. SHELL-PAGED.md is normative.
//
//  ⚠ THE PANE IS ONE PAGE AT A TIME NOW. It used to be one scroll holding
//  Featured, a section per name, then Misc — and before that three zones.
//  SHELL-PAGED.md replaces the lot: the strip is the navigation, and tapping a
//  circle REPLACES the pane rather than scrolling to a section. A section
//  answered "whose is this" while you scrolled past six other names; a page
//  answers it by being the only thing on screen.
//
//  ⚠ THE FILTER STRIP, THE SEARCH DRAWER, THE LOADING SKELETON AND THE BOTTOM
//  RAIL ARE ALL RETIRED (26 Aug 2026), along with Featured / Misc and the
//  headings and empty lines they used. SunnyChrome.swift is deleted. SHELL.md
//  is history — do not rebuild any part of it from that file or a screenshot.
//  The reasoning: a filter is a question the app asks the user, a position list
//  is an answer, and seven names fit in a strip. Two navigations is one too many.
//
//  ⚠ AND THE HORIZONTAL AWARENESS SCROLLER WENT WITH THEM. Six Awareness Cards
//  stacked measured 3,361pt in a 718pt pane, which is why they were laid side
//  by side. Under the new shell they are never stacked: one card files under
//  each name, so the scroller had nothing left to solve and the feed grid is
//  the feed grid again. Do not re-add it — it was a fix for a layout that no
//  longer exists.
//

import SwiftUI

// MARK: - what a card is, and where it goes

/// One card in the feed, whatever kind it is.
struct SunnyFeedItem: Identifiable {
    /// Stable across a reload and across a relaunch — the read flag is keyed on
    /// it, so it must change when the card has something new to say and only
    /// then. See `SunnyRead`.
    let id: String
    /// The name it files under. Nil means it belongs to no single position.
    let ticker: String?
    /// Something on a clock, or unread items. A card that never qualifies never
    /// visits New — it lives on its name's page from the day it exists.
    let clock: Bool
    let tags: [SunnyTag]
    let name: String
    let kind: Kind

    enum Kind {
        case week(SunnyWeekModel)
        case digest(SunnyDigestCardModel)
        case planner(PlannerModel)
    }

}

/// Which cards have been read.
///
/// ⚠ THE KEY IS A CONTENT SIGNATURE, NOT A CARD ID. SHELL.md §9: "A filed card
/// comes back to Featured when that name has something new." If the key were
/// just the ticker, reading NKE once would file it forever and Featured would
/// drain permanently, which is the failure mode that section exists to prevent.
/// If the key carried the timestamp instead, every card would return every
/// morning whether or not anything happened, which is the same bug facing the
/// other way. So the key carries the NEW COUNT: read at 3 new, and the card
/// returns at 4.
enum SunnyRead {
    private static let store = "sunny.read.v1"

    static func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: store) ?? [])
    }
    static func save(_ s: Set<String>) {
        UserDefaults.standard.set(Array(s), forKey: store)
    }
}

// MARK: - row 3 · the pane

/// What the strip needs to draw itself. The pane owns the stores, so it is the
/// only thing that knows the book, and it hands the strip the three facts the
/// strip cannot compute: the names in book order, which of them have something
/// unread, and how many dated cards are due in total.
///
/// Equatable so the pane can push it on change rather than on every render —
/// which is also why it carries a flat pair per name instead of the whole
/// BookName, whose five-day series has no business in a navigation signal.
struct SunnyNav: Equatable {
    struct Name: Equatable, Identifiable {
        let ticker: String
        let weight: Int
        var id: String { ticker }
    }
    var book: [Name] = []
    var pending: Set<String> = []
    /// A short leg in the money. See SunnyStrip.flagged for why it is that and
    /// not "has an exception".
    var flagged: Set<String> = []
    var due: Int = 0
    /// Short legs in the money, book-wide. The Options tile's ring reads this,
    /// and so does the roll check's footer, so the two cannot disagree.
    var rolling: Int = 0

    /* ⚠ ONE ORDER, READ BY BOTH THE STRIP AND THE SWIPE. Flagged names sort
       first after New, then the rest, each group alphabetical — the price of
       `New` saying nothing about assignment is that a flagged name off the right
       edge of the scroller is invisible. The weight is still on the caption; it
       is no longer the order.

       ⚠ AND THE SWIPE MUST WALK THIS LIST, NOT THE BOOK. A swipe that advanced
       through book order while the strip showed another would make the strip
       lie about where the next page is — the strip is the whole navigation, so
       nothing may disagree with it. */
    var ordered: [Name] {
        book.sorted {
            let a = flagged.contains($0.ticker), b = flagged.contains($1.ticker)
            return a != b ? a : $0.ticker < $1.ticker
        }
    }
    /* ⚠ ONE ORDER, AND THE SWIPE MUST SEE THE OPTIONS PAGE TOO. The strip and
       the pager both read this; a page in the strip that the pager did not know
       about would be reachable by tap and skipped by swipe. */
    var pages: [SunnyPage] { [.new, .options] + ordered.map { .name($0.ticker) } }
}


/// ⚠ EVERY STORE THE PANES SHARE, HOISTED OUT OF THE PANE ITSELF. It moved here
/// the day the swipe had to track the finger: a pager lays the pages SIDE BY
/// SIDE, so more than one pane exists at once, and stores held as the pane's own
/// `@State` would be fetched once per visible page and mutate independently —
/// a Read on one copy would leave the next copy still showing the card as
/// unread.
///
/// ⚠ AND THE PLACEMENT LIVES HERE TOO, not on the pane. `place`, `due` and
/// `pending` are facts about the BOOK, not about the page being looked at, and
/// the shell needs them for the strip before any pane has rendered.
@Observable
final class PaneModel {
    var digest = DigestStore()
    var week = WeekStore()
    var planner = PlannerStore()
    var legs = LegsStore()
    var rail = RailStore()
    /// The New page's whole payload. It lives here with the other stores so the
    /// pager can hold more than one pane without fetching it twice.
    var newPage = NewPageStore()
    /// The six option cards read ONE contract, because the weekly-yield card's
    /// last bar must equal the yield-progress card's "this week" figure and two
    /// endpoints would let them drift.
    var options = OptionsStore()
    var read: Set<String> = SunnyRead.load()
    /// ⚠ PER NAME, NOT PER CARD (five-day-price.md §6), so an M and an L on the
    /// same ticker flip together.
    var priceUnits: Set<String> = []

    private static let forceFeatured =
        ProcessInfo.processInfo.arguments.contains("-forceFeatured")

    var items: [SunnyFeedItem] {
        var out: [SunnyFeedItem] = []
        if let w = week.card {
            /* The weekly cross-position summary. It has no ticker on purpose —
               it is about every name at once — so reading it removes it rather
               than filing it, exactly as SHELL-PAGED.md's slot D does. */
            out.append(SunnyFeedItem(id: "week|" + w.label, ticker: nil, clock: true,
                                     tags: [SunnyTag("Week")], name: "last week summary",
                                     kind: .week(w)))
        }
        if let pl = planner.card {
            /* ⚠ ON NEW, AND NEVER FILED. A planner that fired is on a clock by
               definition. It carries NO read control, deliberately: filing an
               open instruction hides the one thing on the screen that is asking
               to be done. It leaves when the gate shuts. */
            out.append(SunnyFeedItem(id: "planner|" + pl.answer,
                                     ticker: "TLT", clock: true,
                                     tags: [.ticker("TLT")], name: "TLT planner",
                                     kind: .planner(pl)))
        }
        for d in digest.cards {
            /* ⚠ KEYED ON THE FRESHEST EVENT, NOT ON THE COUNT. The id was
               `digest|BABA|1`, which is the same string every day a name has one
               new item — so the first day's Read filed every later day's card
               before it reached New, and the awareness card went straight to the
               ticker page. The date moves only when something arrives. */
            out.append(SunnyFeedItem(
                id: "digest|\(d.ticker)|\(d.freshest.isEmpty ? String(d.newCount) : d.freshest)",
                ticker: d.ticker, clock: d.newCount > 0 || Self.forceFeatured,
                tags: d.tags, name: d.name, kind: .digest(d)))
        }
        return out
    }

    /* ⚠ NEW NO LONGER HOLDS CARDS, SO NOTHING FILES TO IT (29 Aug 2026). A
       dated card used to sit on New while unread and move to its name once
       read; with the New page rebuilt as five sections of its own, an unread
       card would have rendered NOWHERE. Every card now goes straight to its
       name's page.

       ⚠ AND A CARD WITH NO NAME IS GONE. The week card belonged to no ticker
       and reading it cleared it — it has nowhere left to land, which is what
       "everything else not on this new layout goes" means for it. */
    func place(_ i: SunnyFeedItem) -> SunnyPage? {
        i.ticker.map { .name($0) }
    }

    /* ⚠ THE STRIP'S TWO SIGNALS HAD TO BE REDEFINED WITH THE CARDS GONE. The
       count was "dated cards unread" and the amber ring was "this name has one
       waiting"; neither exists any more, and both would have kept reporting a
       dead code path — the count read 7 against a page holding no cards at all.

       They now read the same feeds the page does: the count is what ARRIVED
       TODAY across the book, and a name wears amber when it has news or a
       rating THIS WEEK. Amber still means "changed since you last read" — the
       card layer's own meaning — it is just measured against the feed rather
       than against a read pill that no longer exists. */
    var due: Int {
        let p = newPage.page
        let fresh = (p?.news.lead.map { $0.hours < 24 } ?? false) ? 1 : 0
        let links = p?.news.links.filter { $0.hours < 24 }.count ?? 0
        let acts = p?.analysts.cards.filter { $0.date == p?.date }.count ?? 0
        return fresh + links + acts
    }
    var pending: Set<String> {
        guard let p = newPage.page else { return [] }
        var out = Set(p.analysts.cards.map(\.ticker) + p.analysts.rest.map(\.ticker))
        if let l = p.news.lead { out.insert(l.ticker) }
        for l in p.news.links { out.insert(l.ticker) }
        return out
    }

    var nav: SunnyNav {
        SunnyNav(book: rail.book.map { .init(ticker: $0.ticker, weight: $0.weight) },
                 pending: pending,
                 /* Puts bought are never here: a long put in the money is cover
                    doing its job, not something that could be done to him. */
                 flagged: Set((rail.callsSold + rail.putsSold).filter(\.itm).map(\.ticker)),
                 due: due, rolling: options.data?.book.rolling ?? 0)
    }

    func book(_ t: String) -> BookName {
        rail.book.first { $0.ticker == t }
            ?? BookName(ticker: t, name: "", weight: 0, week: nil,
                        avg: nil, exercise: nil, delta: nil)
    }
    func position(_ t: String) -> LegsPosition? { legs.positions.first { $0.ticker == t } }

    /* Reading changes WHERE the card is, never what it says: the control files
       the card, it does not dismiss it.

       ⚠ ONE FUNCTION, SO THE PROBE CANNOT DIVERGE FROM THE BUTTON. -tapRead
       calls this, not a copy of it. A verification path that reimplements the
       thing it verifies is the shape of test that passes while the real control
       is broken, and this file has been burned by that once already. */
    func markRead(_ i: SunnyFeedItem) {
        read.insert(i.id)
        SunnyRead.save(read)
        /* ⚠ AND TELL THE SERVER, because the server's idea of "read" used to be
           "somebody fetched this", which any probe or refresh could satisfy. The
           Read control is now the only thing that advances the freshness window.
           Digests only — the week card belongs to no name and the planner has no
           read control at all. */
        if case .digest = i.kind, let t = i.ticker {
            Task { await digest.markSeen(t) }
        }
    }

    func loadAll() async {
        async let a: Void = rail.load()
        async let b: Void = digest.load()
        async let c: Void = week.load()
        async let d: Void = planner.load()
        async let e: Void = legs.load()
        async let f: Void = newPage.load()
        async let g: Void = options.load()
        _ = await (a, b, c, d, e, f, g)
        if ProcessInfo.processInfo.arguments.contains("-showPrice") {
            priceUnits = Set(rail.book.map(\.ticker))
        }
    }
}

struct SunnyPane: View {
    /// ⚠ THE PAGE REPLACES THE PANE. It does not scroll to a section — with no
    /// filter the strip carries the whole "where am I" job, and scrolling makes
    /// every page one long page, so the answer goes ambiguous again.
    /// ⚠ A `let`, NOT A BINDING. The pane renders one page and never changes
    /// which — the pager decides that by scrolling. A binding here would let
    /// every visible pane fight over the same value.
    let page: SunnyPage
    let m: PaneModel
    var startAt: CGFloat? = nil

    @State private var pos = ScrollPosition()
    /// Expand-in-place state for the news gate's chip. Per view, not per model:
    /// it is a reading position, not a fact about the book.
    @State private var showFiltered = false

    private var current: BookName? {
        guard case .name(let t) = page else { return nil }
        return m.book(t)
    }
    private var position: LegsPosition? {
        guard case .name(let t) = page else { return nil }
        return m.position(t)
    }

    // MARK: body

    var body: some View {
        /* ⚠ NO TRANSITION AND NO `.id` ANY MORE. Both existed to fake a slide
           between two pages that were never on screen together; the pager lays
           them side by side and moves them with the finger, so the motion is
           real and a transition would fight it. */
        ScrollView {
            VStack(alignment: .leading, spacing: S.shellPaneGap) {
                switch page {
                case .new:  newPage
                case .options: optionsPage
                case .name: namePage
                }
            }
            /* ⚠ 361 CENTRED, NOT MARGIN 16. Nik's call, 2026-08-24. The handoff
               is drawn at 393pt and the column arithmetic only closes there:
               16 + 175 + 11 + 175 + 16. Holding --margin at 16 on a wider phone
               would widen the content to 370 and resize every card already
               signed off. Do not "fix" this back to a leading 16. */
            /* ⚠ 361 WIDE AND CENTRED, NOT maxWidth: .infinity. The pager made
               each page the full screen width and this frame was widened to
               match it, which is a different thing entirely: the CONTENT column
               is 361 and the page is 393, and the 16 either side is the margin.
               Widened, every card sat hard against the left edge with all 32 of
               the slack on the right. The page's width is the pager's business;
               the column's is this line's. */
            .frame(width: S.content)
            .padding(EdgeInsets(top: S.shellPanePadTop, leading: S.margin,
                                bottom: S.shellPanePadBottom, trailing: S.margin))
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($pos)
        .background(S.ground)
        .task {
            /* Verification only: -scrollTo starts the pane at a fixed offset so a
               screenshot of "TLT at 900" does not depend on a simulated drag
               landing on the right pixel. */
            guard let y = startAt else { return }
            try? await Task.sleep(for: .seconds(6))   // let the cards land first
            pos.scrollTo(y: y)
        }
    }

    // MARK: the New page

    @ViewBuilder
    private var newPage: some View {
        /* ⚠ EVERYTHING THAT WAS ON THIS PAGE IS GONE (29 Aug 2026). The
           awareness digests, the planner, the week card and the three
           open-short figures are all off it. Nik: "everything else not on this
           new layout goes."

           ⚠ SECTIONS ARE SPEEDS, NEVER TICKERS. Sorting by name gave every
           section eight of everything and turned a quiet week into forty cells.
           Three sections, because the five feeds collapse to three rhythms:
           news daily, analysts weekly, earnings and guidance quarterly.

           ⚠ AND THE PAGE RUNS ON TWO CLOCKS. The lead says TODAY, the analyst
           seam says THIS WEEK, and the header date is a DAY. */
        if let p = m.newPage.page {
            SunnyNewTitle(date: p.date)
            SunnyDateRow(dates: p.dates)

            /* News carries NO SEAM: a 26/300 headline under the date row is
               self-evidently news, and a heading over the first block on a page
               is a partition with nothing on the other side. */
            SunnyNewsLead(lead: p.news.lead, filtered: p.news.filtered.count,
                          onChip: { showFiltered.toggle() },
                          chipLabel: showFiltered ? "Fewer" : "See them")
            if p.news.lead != nil {
                VStack(alignment: .leading, spacing: S.gap7) {
                    ForEach(p.news.links) { SunnyLinkRow(l: $0) }
                }
                .padding(.top, S.gap3)
                HStack(spacing: S.gap6) {
                    /* ⚠ THE FILTERED COUNT IS ALWAYS SHOWN AND NAMED. A silent
                       gate on a paid feed looks broken. */
                    Text("\(p.news.filtered.count) filtered")
                        .font(S.inter(S.t14, S.wMidSmN))
                        .foregroundStyle(S.mute2)
                    SunnyExpandChip(label: showFiltered ? "Fewer" : "See them") {
                        showFiltered.toggle()
                    }
                    Spacer(minLength: 0)
                }
            }
            if showFiltered { SunnyFilteredList(rows: p.news.filtered.rows) }

            SunnySeam(label: "This week · analysts", count: p.analysts.count)
            if p.analysts.cards.isEmpty {
                /* ⚠ AN EMPTY SECTION STATES ITS LAST DATE. Without one, an
                   empty feed and a broken feed are indistinguishable. */
                SunnyEmptyNote(
                    line: "No firm has moved on any of your names this week.",
                    last: p.analysts.last.map {
                        "Last was \(p.analysts.lastFirm ?? "a firm") on "
                        + "\(p.analysts.lastTicker ?? ""), \(shortDate($0))."
                    })
            } else {
                ForEach(p.analysts.cards) { SunnyAnalystCard(a: $0) }
                if !p.analysts.rest.isEmpty { SunnyActionList(rows: p.analysts.rest) }
            }
            /* On every state of the page, with that state's own numbers — a
               standing fact, not an arrival. */
            /* ⚠ THE ROOM DOES NOT REPLACE THE MEDIAN. It did, and that was
               wrong. The two answer different questions: the room is the
               spread of opinion and how it MOVED, the median is the single
               number and the distance from today's price to it. Demoting the
               median to an `else` branch meant it could never render at all,
               because `room` always has rows — so a card whose own comment
               says "on every state of the page" was invisible for weeks.

               Nik, 2026-09-03: "we use to have this on the new page and then
               it was removed I want to keep this always as a view." Both now
               render, room first because movement is the newer information and
               the median is the standing fact underneath it. */
            if let room = p.room, !room.rows.isEmpty {
                SunnyRoomCard(r: room)
            }
            if !p.targets.rows.isEmpty {
                SunnyTargetCard(t: p.targets)
            }

            SunnySeam(label: "Earnings & guidance", count: p.earnings.count)
            if p.earnings.rows.isEmpty {
                SunnyEmptyNote(line: "Nothing reports inside 30 days, and no guide has changed.",
                               last: nil)
            } else {
                SunnyEarningsCard(e: p.earnings)
            }

            /* ⚠ THE NEVER-EMPTY BLOCK, AND IT GOES LAST. On a dead week it and
               the room are the page. It came back as a slope chart because the
               single blended cut share could not tell a REGIME BREAK from a
               name that has always been unloved, and those are opposite
               situations to sell calls into. */
            if let drift = p.drift, !drift.rows.isEmpty {
                SunnySeam(label: "The drift", count: nil)
                SunnyDriftCard(d: drift)
            }
        } else if m.newPage.error != nil {
            SunnyPageNote("The feed did not answer. It will try again when you "
                        + "come back to this page.")
        }
    }

    // MARK: the options page

    /* ⚠ ITS OWN PAGE, NOT A BLOCK ON `New`. They shipped on New and pushed the
       news below three full-height cards, which made an eight-block page whose
       lead was buried. Nik: "new is getting crowded... we need another
       dedicated space." The order is the sheet's: roll check first, because it
       is the only one of the three that asks for an action. */
    @ViewBuilder
    private var optionsPage: some View {
        if let o = m.options.data, !o.positions.isEmpty {
            SunnyPageTitle(title: "Options",
                           note: o.book.rolling > 0
                                 ? "\(o.book.rolling) to roll" : "\(o.book.legs) legs open")
            SunnyRollCheck(book: o.book, positions: o.positions)
            SunnyYieldProgress(book: o.book, positions: o.positions)
            /* Directly under Yield progress on purpose: the two share the
               $164,725 denominator and answer the halves of one question,
               how much the premium has paid back and what the LEAP is worth. */
            SunnyLeapGains(book: o.book, positions: o.positions)
            SunnyWeeklyYield(book: o.book)
        } else if m.options.error != nil {
            SunnyPageNote("The book did not answer. It will try again when you "
                        + "come back to this page.")
        }
    }

    // MARK: a name page

    @ViewBuilder
    private var namePage: some View {
        if let b = current {
            SunnyPageHead(ticker: b.ticker, name: b.name, weight: b.weight)
            /* ⚠ THE FIGURES COME FROM THE OPTIONS BOOK NOW. They read from
               `position`, which is share-lot derived, and there are no shares
               left — so both printed an em dash on every name. Per the P&L
               glossary: CURRENT is unrealized on what is open (the LEAP's mark
               against its cost, plus each open short's credit against its
               current value); TOTAL is net, that plus the credits already
               realized on legs since closed. */
            let opt = m.options.data?.positions.first { $0.t == b.ticker }
            SunnyPageFigures(current: opt.map(optCurrent) ?? position?.total,
                             total: opt.map(optTotal) ?? position?.allTime)

            /* ⚠ A FILED CARD LANDS BETWEEN THE FIGURES AND THE RESIDENT CARDS,
               not above the heading and not at the bottom. A thing that just
               arrived belongs at the top of what is already there. */
            let filed = m.items.filter { m.place($0) == .name(b.ticker) }
            ForEach(filed) { card($0) }

            /* ⚠ THE TICKER CARD IS GONE, 2026-09-02. It led the page with
               the short leg's strike, its moneyness and its credit against its
               current value — which is now the roll check, the pair card and
               the figures above it, three times over. Nik: "remove the first
               card it's a repeat." Its file stays; nothing renders it. */

            /* ⚠ THE THREE OPTION CARDS, IN THE SHEET'S ORDER: weekly credit,
               the pair in THIS WEEK, pace to cover. Three, not four — Part 1
               §2 and Part 4 §11 of OPTIONS-CARDS.md contradict each other on
               whether SINCE OPEN also renders, and Nik ruled three. The scope
               is a tag, not a second card type, so `SunnyPair(p:scope:)` builds
               both and only one is called. */
            if let o = m.options.data,
               let op = o.positions.first(where: { $0.t == b.ticker }) {
                SunnySeam(label: "The position", count: nil)
                SunnyNameCredit(p: op)
                SunnyPair(p: op, scope: .week)
                SunnyPace(p: op)
            }

            /* ⚠ SECOND, AND ONLY WHERE SOMETHING COULD BE ASSIGNED. It answers a
               different question from the card above it — that one is what do I
               have on this name, this one is what happens if the price moves —
               so it is not a variant of it and never folds into it. */
            if let x = b.exercise {
                SunnyLadderCard(ticker: b.ticker, e: x)
            }

            /* ⚠ THIRD, AND ONLY FOR THE CHART. The two cards above answer what
               he holds and what happens next; this one is the only place the
               week-by-week P&L is drawn, which is a shape and not a reading.
               It was one card, not five, for the same reason the ticker card is
               one card and not five: the per-leg scales were not comparable, so
               shares showing a loss beside calls showing a profit could not be
               reconciled, and Nik read it as losing the story. */
            SunnyPositionCards(p: position)

            if let w = b.week {
                SunnyFiveDayCard(
                    ticker: b.ticker, m: w,
                    showPrice: Binding(
                        get: { m.priceUnits.contains(b.ticker) },
                        set: { on in
                            if on { m.priceUnits.insert(b.ticker) }
                            else { m.priceUnits.remove(b.ticker) }
                        }))
            }

            if filed.isEmpty && position == nil && b.week == nil && b.avg == nil
                && b.delta == nil && b.exercise == nil {
                SunnyPageNote("Held, and quiet. No card has been built for this "
                            + "name yet — it earns one when it has something to say.")
            }
        }
    }

    // MARK: a card

    @ViewBuilder
    private func card(_ i: SunnyFeedItem) -> some View {
        let onNew = m.place(i) == .new
        let mark: (() -> Void)? = onNew ? { withAnimation(S.easeSettle(S.durRevealTransform)) { m.markRead(i) } } : nil
        switch i.kind {
        case .week(let w):    SunnyWeekCard(m: w, onRead: mark)
        case .digest(let d):  SunnyDigestCard(d, onRead: mark)
        case .planner(let p): SunnyPlannerCard(m: p)      // no read control, see items
        }
    }

}
