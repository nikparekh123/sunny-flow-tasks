//
//  SunnyFeed.swift
//  Sunny — the pane. Two tabs, New and Options, one page each.
//
//  ⚠ THE STRIP, THE PER-NAME PAGES, THE FILTER, THE SEARCH DRAWER AND THE RAIL
//  ARE ALL RETIRED. The glass tab bar (14 Sep 2026) is the whole navigation; the
//  name pages and their stores were deleted in the 8 Oct 2026 cleanup. Do not
//  rebuild any of them from an old handoff or screenshot.
//

import SwiftUI

/// ⚠ EVERY STORE THE PANES SHARE, HOISTED OUT OF THE PANE ITSELF. Both tabs
/// are alive at once, so stores held as a pane's own `@State` would be fetched
/// once per tab and drift apart.
///
/// ⚠ THE PER-NAME PAGES ARE GONE (8 Oct 2026 cleanup), and with them the
/// digest, week, planner, legs and rail stores. They fed pages nothing could
/// open, yet three of them still fired a request on every load.
@Observable
final class PaneModel {
    /// The New page's whole payload.
    var newPage = NewPageStore()
    /// The option cards read ONE contract, because the weekly-yield card's
    /// last bar must equal the yield-progress card's "this week" figure and two
    /// endpoints would let them drift.
    var options = OptionsStore()

    /// ⚠ `force` EXISTS FOR THE PULL, and only `options` reads it. OptionsStore
    /// alone holds a five-minute cache, so without this a pull-to-refresh would
    /// silently return the same cards it was already showing.
    /* ⚠ OPTIONS FIRST. Nik, 17 Sep 2026: "sometimes it takes around 15secs to
       load". Requests fired together queued behind each other on the same small
       database, so the landing page loads alone and the New page follows. */
    func loadAll(force: Bool = false) async {
        await options.load(force: force)
        await newPage.load()
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
    /* ⚠ A COUNTER, NOT A FLAG. The shell bumps it when the tab already showing
       is tapped again, which is the one gesture a selection binding cannot
       report: the value it writes is the value already there. */
    var toTop: Int = 0

    @State private var pos = ScrollPosition()
    /// Expand-in-place state for the news gate's chip. Per view, not per model:
    /// it is a reading position, not a fact about the book.
    @State private var showFiltered = false

    // MARK: body

    var body: some View {
        scroller
    }

    @ViewBuilder private var scroller: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: S.shellPaneGap) {
                switch page {
                case .new:  newPage
                case .options: optionsPage
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
        /* ⚠ THE ONLY WAY TO PULL FRESH FIGURES WITHOUT QUITTING THE APP.
           Nik, 2026-09-10, on finding the marks were an hour old: the shell's
           `.task` fires once per launch and nothing ever called a store again,
           so an app left open all afternoon showed whatever it fetched when it
           was opened. The marks now refresh every minute on the server; this is
           how they reach the glass.

           It lives on the vertical scroller inside the horizontal pager, so a
           downward pull refreshes and a sideways drag still pages. */
        /* ⚠ THE PLATFORM SPINNER IS REMOVED, NOT HIDDEN, 14 Sep 2026, from the
           `loading` handoff. `.refreshable` drew a ring, and nothing in this
           deck spins. The control is a hairline that grows from the centre with
           the pull, a caret that travels it while the feed answers, and the
           real close label on done. */
        .sunnyPullRefresh { await m.loadAll(force: true) }
        .onChange(of: toTop) { _, _ in
            withAnimation(S.easeOut(S.durPage)) { pos.scrollTo(edge: .top) }
        }
        .background(S.ground)
        .task {
            /* Verification only: -scrollTo starts the pane at a fixed offset so a
               screenshot of "TLT at 900" does not depend on a simulated drag
               landing on the right pixel. */
            guard let y = startAt else { return }
            /* ⚠ ONCE IS NOT ENOUGH. A single scroll at six seconds landed on a
               page the fetch then re-laid out, and the pane came back at the
               top — which reads as the argument being ignored. Three attempts
               across the first twenty seconds survive the second layout. */
            for _ in 0..<3 {
                try? await Task.sleep(for: .seconds(6))
                pos.scrollTo(y: y)
            }
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
                ForEach(p.analysts.cards) {
                    SunnyAnalystCard(a: $0,
                                     isNew: NewToday.action(date: $0.date, pageDate: p.date))
                }
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
    /* ⚠ THE RING'S FAKE BOOK IS GONE with the rings, 14 Sep 2026. `-fakeCover`
       existed so the put cover ring could be measured before the first put was
       bought; there are 83 of them now and the bars read the real book. */

    private func optionsNote(_ o: OptionsPayload) -> String {
        if o.book.rolling > 0 {
            return "\(o.book.rolling) to roll"
        }
        let names = o.positions.count
        return "\(names) name\(names == 1 ? "" : "s"), \(o.book.legs) sold"
    }

    /* ⚠ THE ORDER IS NIK'S, 14 Sep 2026: "always want price as first, roll
       check, weekly yield, long lesga dn instricntic, call cover, put cover ...
       after that whatever works. Start wiorh price since it's about knowing how
       miuch the stock moved". The tail is mine: Yield progress stays with the
       two cover cards because it is the same question by name, then the
       standing figure and the two rate cards.

       ⚠ NO BUCKETS AND NO RAIL. Both were built and both came off — the four
       question headers on 14 Sep ("no bucketing it's confusing"), the tile rail
       the same night ("Remove the rail sorry not a big fan of it"). The page is
       a plain run of cards in this order and nothing above them but the day. */
    @ViewBuilder
    private var optionsPage: some View {
        if let o = m.options.data, !o.positions.isEmpty {
            /* ⚠ THE DAY, NOT THE PAGE. Nik, 14 Sep 2026: "add today on top with
               date". With two destinations the nav already says where you are,
               so the one line worth spending here is which day these figures
               are — no card carries the date except in its own header. It
               scrolls away with the feed, like every other page title. */
            SunnyPageTitle(title: "Today", note: ivDay(o.date))
            /* ⚠ PRICES AND POSITIONS ARE BACK, 27 Sep 2026. Nik, after the
               notes card: "I want to go back to this card... lets bring it
               back". The notes card and the ladder card stay in the code,
               unmounted. The roll sheet lives on Inventory's tickers. */
            if let pr = o.prices, !pr.rows.isEmpty {
                SunnyPrices(prices: pr)
            }
            SunnyPositions(positions: o.positions, legs: o.longLegs?.legs ?? [],
                           prices: o.prices?.rows ?? [], asOf: o.prices?.asOf ?? o.date,
                           fresh: m.options.posFresh, updating: m.options.loading)
            /* ⚠ INVENTORY, DIRECTLY AFTER POSITIONS, 18 Sep 2026 (`export 20`). The
               true book behind the same four tabs; it is Left to sell's new home. */
            if let inv = o.inventoryCard {
                SunnyInventory(block: inv, fresh: m.options.invFresh,
                               updating: m.options.loading,
                               roll: o.rollCard, positions: o.positions,
                               refresh: { await m.options.load(force: true) })
            }
            SunnyWeeklyYield(book: o.book, putNeed: o.putCover?.need ?? 0,
                             fresh: m.options.wyFresh, updating: m.options.loading)
            if let iv = o.intrinsic, !iv.legs.isEmpty {
                SunnyIntrinsic(block: iv, prices: o.prices?.rows ?? [],
                               asOf: o.prices?.asOf ?? o.date, book: o.book)
            }
            /* ⚠ CALL DIRECTLY BEFORE PUT, and one tile over the pair. Read
               together they say what fraction of each half of the book has paid
               for itself, on the same scale. */
            if let cb = o.coverBars, cb.sides.call.time > 0 || cb.sides.put.time > 0 {
                SunnyCoverage(block: cb)
            }
            /* ⚠ PERFORMANCE REPLACES PROGRAMME, AND YIELD PROGRESS'S SLOT
               CLOSES, 18 Sep 2026 (`export 20`). Its question is the fourth row
               of what the programme is made of. */
            /* ⚠ THE BOOK REPLACES PERFORMANCE AND ALLOCATION, 23 Sep 2026
               (final cards). Nik: "also remove the old allocation and
               performance card". Two rankings of one book, two tabs. */
            if o.programme?.rows.isEmpty == false || o.allocationCard?.book.isEmpty == false {
                SunnyBook(programme: o.programme, legs: o.longLegs?.legs ?? [],
                          allocation: o.allocationCard, closed: o.closedCard,
                          positions: o.positions, intrinsic: o.intrinsic,
                          prices: o.prices?.rows ?? [])
            }
            /* ⚠ CREDIT & THETA REPLACES THETA AND AVERAGE CREDIT, 17 Sep 2026,
               in their place at the end of the run. */
            if let ct = o.creditTrend, ct.weeks.count > 1 {
                SunnyCreditTheta(block: ct)
            }
        } else if m.options.error != nil {
            SunnyPageNote("The book did not answer. It will try again when you "
                        + "come back to this page.")
        } else {
            /* ⚠ THE PANE'S OWN LOADING STATE, and it waits 400 ms before it
               appears: a flash of this screen on a fast load is worse than a
               blank one. It has no done state — the page arriving is done. */
            SunnyWaitGate(title: "Options")
        }
    }
}
