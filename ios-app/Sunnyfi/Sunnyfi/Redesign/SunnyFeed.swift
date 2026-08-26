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
    var due: Int = 0
}

struct SunnyPane: View {
    /// ⚠ THE PAGE REPLACES THE PANE. It does not scroll to a section — with no
    /// filter the strip carries the whole "where am I" job, and scrolling makes
    /// every page one long page, so the answer goes ambiguous again.
    @Binding var page: SunnyPage
    let onNav: (SunnyNav) -> Void
    var startAt: CGFloat? = nil

    @State private var digest = DigestStore()
    @State private var week = WeekStore()
    @State private var planner = PlannerStore()
    @State private var legs = LegsStore()
    @State private var rail = RailStore()
    @State private var read: Set<String> = SunnyRead.load()
    /// ⚠ PER NAME, NOT PER CARD (five-day-price.md §6). Held here rather than
    /// inside the card so an M and an L on the same ticker flip together.
    @State private var priceUnits: Set<String> = []
    @State private var pos = ScrollPosition()
    private static let argShowPrice =
        ProcessInfo.processInfo.arguments.contains("-showPrice")

    // MARK: the items, and where each one sits

    private var items: [SunnyFeedItem] {
        var out: [SunnyFeedItem] = []
        if let w = week.card {
            /* The weekly cross-position summary. It has no ticker on purpose —
               it is about every name at once — so reading it removes it rather
               than filing it, exactly as SHELL-PAGED.md's slot D does. The
               engine also decides whether it exists at all (Monday, once). */
            out.append(SunnyFeedItem(id: "week|" + w.label, ticker: nil, clock: true,
                                     tags: [SunnyTag("Week")], name: "last week summary",
                                     kind: .week(w)))
        }
        if let pl = planner.card {
            /* ⚠ ON NEW, AND NEVER FILED. A planner that fired is on a clock by
               definition. It carries NO read control, deliberately: filing an
               open instruction hides the one thing on the screen that is asking
               to be done. It leaves when the gate shuts, which is its own
               lifecycle and a better one. */
            out.append(SunnyFeedItem(id: "planner|" + pl.answer,
                                     ticker: "TLT", clock: true,
                                     tags: [.ticker("TLT")], name: "TLT planner",
                                     kind: .planner(pl)))
        }
        for d in digest.cards {
            out.append(SunnyFeedItem(id: "digest|\(d.ticker)|\(d.newCount)",
                                     ticker: d.ticker, clock: d.newCount > 0 || Self.forceFeatured,
                                     tags: d.tags, name: d.name, kind: .digest(d)))
        }
        return out
    }

    /* New is empty on a quiet day by design, and a quiet day is the common case
       — every name currently reads new_count 0 and the engine has already spent
       this week's Monday card. That leaves the read control, the filing move and
       the empty state unverifiable from a screenshot, so this forces every card
       onto a clock. Verification only; it changes nothing a normal run reaches. */
    private static let forceFeatured =
        ProcessInfo.processInfo.arguments.contains("-forceFeatured")

    /* ⚠ ONE COPY OF EACH CARD. SHELL-PAGED.md §0 rule 2: a dated card has ONE
       wrapper. While unread it shows on New; once read it shows on its own
       name's page. Never both, never rendered twice. Here that is structural:
       one array of items and `place()` is a pure function of the item plus the
       read set, so a card cannot be in two places even by mistake. */
    private func place(_ i: SunnyFeedItem) -> SunnyPage? {
        if i.clock && !read.contains(i.id) { return .new }
        if let t = i.ticker { return .name(t) }
        /* Read, and no name to file under: it is gone until it is due again.
           That is SHELL-PAGED.md's slot D — the card belongs to no name, so
           reading it clears it rather than moving it. */
        return nil
    }

    private var due: [SunnyFeedItem] { items.filter { place($0) == .new } }

    /// Names with a dated card still sitting on New. They wear the blue ring.
    private var pending: Set<String> {
        Set(due.compactMap(\.ticker))
    }

    private var nav: SunnyNav {
        SunnyNav(book: rail.book.map { .init(ticker: $0.ticker, weight: $0.weight) },
                 pending: pending, due: due.count)
    }

    /// The name pages, in book order — largest position first, exactly as the
    /// strip runs. A name is a page whether or not it has a card: the heading
    /// and its two figures are the page's floor, and an empty page says so.
    private var current: BookName? {
        guard case .name(let t) = page else { return nil }
        return rail.book.first { $0.ticker == t }
            ?? BookName(ticker: t, name: "", weight: 0, week: nil, avg: nil)
    }

    private var position: LegsPosition? {
        guard case .name(let t) = page else { return nil }
        return legs.positions.first { $0.ticker == t }
    }

    // MARK: body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: S.shellPaneGap) {
                switch page {
                case .new:  newPage
                case .name: namePage
                }
            }
            /* ⚠ 361 CENTRED, NOT MARGIN 16. Nik's call, 2026-08-24. The handoff
               is drawn at 393pt and the column arithmetic only closes there:
               16 + 175 + 11 + 175 + 16. Holding --margin at 16 on a wider phone
               would widen the content to 370 and resize every card already
               signed off; holding the 361 block keeps the grid exactly as drawn
               and spends the spare width on the margin. Do not "fix" this back
               to a leading 16. */
            .frame(width: S.content)
            .padding(EdgeInsets(top: S.shellPanePadTop, leading: S.margin,
                                bottom: S.shellPanePadBottom, trailing: S.margin))
        }
        .scrollIndicators(.hidden)
        .background(S.ground)
        .scrollPosition($pos)
        /* ⚠ A PAGE CHANGE SETS THE OFFSET TO THE TOP, AND NOTHING ELSE. No DOM
           insertion, no scroll-into-view, no reload.

           ⚠ AND IT MUST NOT BE `.id(page.key)`. Keying the scroller on the page
           resets the offset for free, but it also gives every page a new view
           identity — which throws away the @State stores and refetches the whole
           book, the digests, the legs and the planner on every tap of the strip.
           The scroller stays one view; only its offset moves. */
        .onChange(of: page) { _, _ in pos.scrollTo(edge: .top) }
        .onChange(of: nav) { _, n in onNav(n) }
        .task {
            /* Verification only: -scrollTo starts the pane at a fixed offset so a
               screenshot of "TLT at 900" does not depend on a simulated drag
               landing on the right pixel. */
            guard let y = startAt else { return }
            try? await Task.sleep(for: .seconds(6))   // let the cards land first
            pos.scrollTo(y: y)
        }
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-tapRead") else { return }
            try? await Task.sleep(for: .seconds(10))
            if let first = due.first { markRead(first) }
        }
        .task {
            await rail.load()
            if Self.argShowPrice { priceUnits = Set(rail.book.map(\.ticker)) }
            onNav(nav)
        }
        .task { await digest.load(); onNav(nav) }
        .task { await week.load(); onNav(nav) }
        .task { await planner.load() }
        .task { await legs.load() }
    }

    // MARK: the New page

    @ViewBuilder
    private var newPage: some View {
        SunnyNewHead(due: due.count)
        /* ⚠ THE LIST IS NOT A DATED CARD. It has no read control and no name to
           file under: it is about the whole book, so it belongs on New every
           morning rather than moving to a page when it is read. The per-name S
           cards on each page are the same number, one at a time. */
        if rail.book.contains(where: { $0.avg != nil }) {
            SunnyAverageList(book: rail.book)
        }
        if due.isEmpty {
            SunnyPageNote("Nothing on a clock. Every card has moved to its own "
                        + "name — a name comes back here when it has something new.")
        } else {
            /* ⚠ NO SEPARATE READ ROW, AND THAT IS NOT AN OMISSION. SHELL-PAGED
               §7 measures a dated wrapper as card + 4 + a 44pt Read row, because
               in the handoff the planner and the put floor sit on New without a
               control of their own. Every dated card this app actually builds
               carries its read control INSIDE itself — the digest's pill, the
               week card's — and the planner carries none deliberately. A row
               under those would put two Reads on one card. Add the wrapper back
               the day a dated card arrives without one, not before. */
            ForEach(due) { card($0) }
        }
    }

    // MARK: a name page

    @ViewBuilder
    private var namePage: some View {
        if let b = current {
            SunnyPageHead(ticker: b.ticker, name: b.name, weight: b.weight)
            SunnyPageFigures(current: position?.total, total: position?.allTime)

            /* ⚠ A FILED CARD LANDS BETWEEN THE FIGURES AND THE RESIDENT CARDS,
               not above the heading and not at the bottom. A thing that just
               arrived belongs at the top of what is already there. */
            let filed = items.filter { place($0) == .name(b.ticker) }
            ForEach(filed) { card($0) }

            /* ⚠ ONE CARD, NOT FIVE (26 Aug 2026). The five per-leg cards are
               retired: their scales were not comparable, so shares showing a
               loss beside calls showing a profit could not be reconciled, and
               Nik read it as losing the story. One figure and one chart of every
               leg summed per week. The put floors stay separate below it,
               because a floor is a distance from a strike and not a
               contribution to a P&L total. */
            SunnyPositionCards(p: position)

            /* The same average as the list's row for this name, alone. It sits
               above the price week for the same reason the position card does:
               the basis is the position, the week is the backdrop. */
            if let a = b.avg {
                SunnyAverageCard(ticker: b.ticker, a: a)
            }
            if let w = b.week {
                SunnyFiveDayCard(
                    ticker: b.ticker, m: w,
                    showPrice: Binding(
                        get: { priceUnits.contains(b.ticker) },
                        set: { on in
                            if on { priceUnits.insert(b.ticker) }
                            else { priceUnits.remove(b.ticker) }
                        }))
            }

            if filed.isEmpty && position == nil && b.week == nil && b.avg == nil {
                SunnyPageNote("Held, and quiet. No card has been built for this "
                            + "name yet — it earns one when it has something to say.")
            }
        }
    }

    // MARK: a card

    @ViewBuilder
    private func card(_ i: SunnyFeedItem) -> some View {
        let onNew = place(i) == .new
        let mark: (() -> Void)? = onNew ? { markRead(i) } : nil
        switch i.kind {
        case .week(let w):    SunnyWeekCard(m: w, onRead: mark)
        case .digest(let d):  SunnyDigestCard(d, onRead: mark)
        case .planner(let p): SunnyPlannerCard(m: p)      // no read control, see items
        }
    }

    /* Reading changes WHERE the card is, never what it says: the control files
       the card, it does not dismiss it.

       ⚠ ONE FUNCTION, SO THE PROBE CANNOT DIVERGE FROM THE BUTTON. -tapRead
       calls this, not a copy of it. A verification path that reimplements the
       thing it verifies is the shape of test that passes while the real control
       is broken, and this file has been burned by that once already. */
    private func markRead(_ i: SunnyFeedItem) {
        withAnimation(S.easeSettle(S.durRevealTransform)) {
            read.insert(i.id)
            SunnyRead.save(read)
        }
        /* ⚠ AND TELL THE SERVER, because the server's idea of "read" used to be
           "somebody fetched this", which any probe or refresh could satisfy.
           The Read control is now the only thing that advances the freshness
           window, so the amber highlight and the NEW tags mean on the wire what
           the pill means on the screen. Digests only — the week card belongs to
           no name and the planner has no read control at all. */
        if case .digest = i.kind, let t = i.ticker {
            Task { await digest.markSeen(t) }
        }
    }
}
