//
//  SunnyFeed.swift
//  Sunny — the pane. SHELL.md is normative for everything below the chrome.
//
//  ⚠ ZONES ARE GONE. This file used to hold three of them (Now / New / Next),
//  each with its own padding, an active-zone scroll tracker and a jump target.
//  SHELL.md replaces the lot with Featured, one section per name, then Misc.
//  A zone answered "how recent is this"; a section answers "whose is this",
//  which is the question actually being asked of a feed of positions.
//
//  ⚠ AND THE HORIZONTAL AWARENESS SCROLLER WENT WITH THEM. Six Awareness Cards
//  stacked measured 3,361pt in a 718pt pane, which is why they were laid side
//  by side. Under the new shell they are never stacked: one card files under
//  each name, so the scroller had nothing left to solve and the feed grid is
//  the feed grid again. Do not re-add it — it was a fix for a layout that no
//  longer exists.
//

import SwiftUI

// MARK: - the card slot

/// CARDS.md: the shell ships with two --wash bars inside. Populating a card
/// means replacing ONLY those two bars. The shell itself is not to be touched.
///
/// ⚠ NEVER set opacity, transform or transition here. The reveal animation
/// writes all three from outside; a value in the shell will fight it and flicker.
struct SunnyCardSlot: View {
    let card: SunnyCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(S.wash).frame(width: 34, height: S.barH)
            Spacer(minLength: 0)                      // justify-content: space-between
            RoundedRectangle(cornerRadius: S.radiusBar)
                .fill(S.wash).frame(height: S.barH)
        }
        .padding(card.size.padding)
        .frame(maxWidth: .infinity)
        // Column span + aspect-ratio, never a fixed width or height (SPEC 01).
        .aspectRatio(card.size.ratio, contentMode: .fit)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(card.size.shadow)
        .measure("card-" + card.size.rawValue)
    }
}

/// ⚠ DO NOT RE-DERIVE THIS. CHROME.md §5: the 44pt target is DECOUPLED from the
/// text box by an overlay that overflows the row without participating in
/// layout, so the text keeps its 16pt rhythm while every label still gets
/// 44 × 44 of hit area, expanding symmetrically. Solving it with padding or a
/// minimum width instead pushes the text off the grid.
struct SunnyFilterLabel: View {
    let text: String
    let on: Bool
    let colourOn: Color
    let colourOff: Color
    var weight: Font.Weight? = nil
    let action: () -> Void

    var body: some View {
        Text(text)
            .font(InkFont.display(S.t13, weight ?? (on ? S.wBold : S.wMid)))
            .tracking(S.track(S.t13, -0.005))
            .foregroundStyle(on ? colourOn : colourOff)
            .fixedSize()
            .overlay {
                GeometryReader { g in
                    Color.clear
                        .frame(width: max(g.size.width + S.hitGrow, S.hitMin),
                               height: g.size.height + S.hitBleed * 2)
                        .contentShape(Rectangle())
                        .position(x: g.size.width / 2, y: g.size.height / 2)
                        .onTapGesture(perform: action)
                }
            }
    }
}

// MARK: - what a card is, and where it goes

/* ⚠ ONE COPY OF EACH CARD. SHELL.md §0 rule 3: a card is in Featured OR under
   its name, never both, and an `order` decides which. Duplicating a card so it
   can appear twice makes *read* ambiguous — read which one? — and is forbidden.
   Here that rule is structural: there is one array of items and `place()` is a
   pure function of the item plus the read set, so a card cannot be in two
   places even by mistake. */

/// Where a card sits in the pane.
enum SunnyPlace: Hashable {
    case featured
    case ticker(String)
    case misc
}

/// One card in the feed, whatever kind it is.
struct SunnyFeedItem: Identifiable {
    /// Stable across a reload and across a relaunch — the read flag is keyed on
    /// it, so it must change when the card has something new to say and only
    /// then. See `SunnyRead`.
    let id: String
    /// The name it files under. Nil means it belongs to no single position.
    let ticker: String?
    /// SHELL.md §9's entry rule: something on a clock, or unread items. A card
    /// that never qualifies starts in its section and never visits the top.
    let clock: Bool
    let tags: [SunnyTag]
    let name: String
    let kind: Kind

    enum Kind {
        case week(SunnyWeekModel)
        case digest(SunnyDigestCardModel)
        case planner(PlannerModel)
    }

    func matches(query: String, filters: Set<SunnyTag>) -> Bool {
        SunnyCard(tags: tags, name: name, size: .m).matches(query: query, filters: filters)
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

struct SunnyPane: View {
    @Binding var query: String
    @Binding var filters: Set<SunnyTag>
    /// Derived from the cards in the feed, so the strip can never offer a
    /// filter that returns nothing. Owned here because the pane owns the stores.
    let onTags: ([SunnyTag]) -> Void
    var startAt: CGFloat? = nil

    @State private var lastY: CGFloat = 0
    @State private var loading = false
    @State private var revealToken = UUID()
    @State private var debounce: Task<Void, Never>?
    @State private var digest = DigestStore()
    @State private var week = WeekStore()
    @State private var planner = PlannerStore()
    @State private var legs = LegsStore()
    @State private var rail = RailStore()
    @State private var railHidden = false
    @State private var read: Set<String> = SunnyRead.load()
    /// ⚠ PER NAME, NOT PER CARD (five-day-price.md §6). Held here rather than
    /// inside the card so an M and an L on the same ticker flip together.
    @State private var priceUnits: Set<String> = []
    /// Verification only, same gating as -filter and -scrollTo: seeds every name
    /// into the price unit so the swapped state can be screenshot and measured
    /// without a touch. The sheet requires the card's height to be identical in
    /// both states, and that is only checkable if both can be reached.
    private static let argShowPrice =
        ProcessInfo.processInfo.arguments.contains("-showPrice")

    /// The OS home-indicator row. The spec draws its own; a real app inherits it.
    private var bottomSafeArea: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .windows.first?.safeAreaInsets.bottom ?? 0
    }

    private var narrowed: Bool {
        !filters.isEmpty || !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: the items, and where each one sits

    private var items: [SunnyFeedItem] {
        var out: [SunnyFeedItem] = []
        if let w = week.card {
            /* The weekly cross-position summary. SHELL.md §9 puts it in Featured
               by name and calls it read-once. It has no ticker on purpose — it
               is about every name at once — so reading it removes it rather
               than filing it. The engine also decides whether it exists at all
               (Monday, once), which is why there is no date test here. */
            out.append(SunnyFeedItem(id: "week|" + w.label, ticker: nil, clock: true,
                                     tags: [SunnyTag("Week")], name: "last week summary",
                                     kind: .week(w)))
        }
        if let pl = planner.card {
            /* ⚠ FEATURED, AND NEVER FILED. SHELL.md §9 names "a planner that
               fired" in the entry rule, so this is the one card that is on a
               clock by definition. It carries NO read control, deliberately and
               against the generic Featured behaviour: reading a card files it
               under its name, and filing an open instruction hides the one thing
               on the screen that is asking to be done. It leaves when the gate
               shuts, which is its own lifecycle and a better one.

               `clock: true` with no id in `read` is what keeps it at the top;
               the id still changes with the contract count so it cannot go
               stale if the size is revised intraday. */
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

    /* Featured is empty on a quiet day by design, and a quiet day is the common
       case — every name currently reads new_count 0 and the engine has already
       spent this week's Monday card. That leaves the read control, the filing
       move and the empty state unverifiable from a screenshot, so this forces
       every card onto a clock. Verification only, same gating as -filter and
       -scrollTo, and it changes nothing a normal run reaches. */
    private static let forceFeatured =
        ProcessInfo.processInfo.arguments.contains("-forceFeatured")

    private var visible: [SunnyFeedItem] {
        items.filter { $0.matches(query: query, filters: filters) }
    }

    /// Nil means the card is not in the feed at all: it was on a clock, it has
    /// been read, and it has no name to file under.
    private func place(_ i: SunnyFeedItem) -> SunnyPlace? {
        if i.clock && !read.contains(i.id) { return .featured }
        if let t = i.ticker { return .ticker(t) }
        return i.clock ? nil : .misc
    }

    private var featured: [SunnyFeedItem] { visible.filter { place($0) == .featured } }
    private var misc: [SunnyFeedItem] { visible.filter { place($0) == .misc } }

    /// Sections in book order, largest position first, and only for names that
    /// actually have a card under them right now. SHELL.md §10: a name's
    /// heading is hidden unless a visible card carries that tag, or a filter
    /// leaves a heading standing over nothing.
    private var sections: [(BookName, [SunnyFeedItem])] {
        var out: [(BookName, [SunnyFeedItem])] = []
        var placed = Set<String>()
        for b in rail.book {
            let cards = visible.filter { place($0) == .ticker(b.ticker) }
            /* ⚠ A HOLDING WITH NO FEED CARD STILL GETS ITS SECTION, because it
               still gets its 5-day price card. TLT is the case: no awareness
               card exists for it, so when sections were built from feed items
               alone TLT had no heading — and 21% of the book was missing from a
               feed that showed six smaller names. Nik asked for the price week
               on ALL holdings, and a holding is a name with lots, not a name
               that happens to emit a digest.

               A name still disappears under a filter it does not match, because
               `matchesBook` runs the same query and pill test the cards run. */
            if !cards.isEmpty || (b.week != nil && matchesBook(b)) {
                out.append((b, cards)); placed.insert(b.ticker)
            }
        }
        /* A name with a card but no lots — a position closed today, a watch-list
           name that still emits a digest — still gets a section, just without a
           weight. Dropping it would make the card unreachable. */
        for t in Set(visible.compactMap { i -> String? in
            guard case .ticker(let t) = place(i) else { return nil }
            return placed.contains(t) ? nil : t
        }).sorted() {
            out.append((BookName(ticker: t, name: "", weight: 0, week: nil),
                        visible.filter { place($0) == .ticker(t) }))
        }
        return out
    }

    /// ⚠ BOOK ORDER, NOT ALPHABETICAL. SHELL.md §4: "Pills are tickers only, in
    /// section order — TLT, BABA, SCHD, VZ, O — mirroring the feed, largest
    /// position first." A strip sorted A-to-Z and a feed sorted by size disagree
    /// on every row, so the pill you reach for is never above the section you
    /// are looking at.
    ///
    /// The sheet says tickers ONLY; Nik's rule is that every card also carries a
    /// per-card tag ("NKE Awareness"), so both are here and his rule wins on
    /// what is in the strip. It does not win on the ORDER: the tags follow the
    /// tickers, in the same book order, so the two halves read as one list.
    /// The book row's own filter test. A 5-day card carries its ticker and its
    /// name, exactly as a feed card does — matching is on those two and never on
    /// what the chart happens to show.
    private func matchesBook(_ b: BookName) -> Bool {
        SunnyCard(tags: [.ticker(b.ticker)],
                  name: "\(b.ticker) \(b.name) 5-day price", size: .l)
            .matches(query: query, filters: filters)
    }

    private var presentTags: [SunnyTag] {
        var seen = Set<SunnyTag>()
        for i in items { seen.formUnion(i.tags) }
        // Every holding earns a pill, whether or not it emits a feed card —
        // otherwise TLT has a section you can see and no pill to reach it with.
        for b in rail.book where b.week != nil { seen.insert(.ticker(b.ticker)) }
        var rank: [String: Int] = [:]
        for (i, b) in rail.book.enumerated() { rank[b.ticker.lowercased()] = i }
        func order(_ t: SunnyTag) -> Int {
            let base = t.key.replacingOccurrences(of: " awareness", with: "")
            return rank[base] ?? rank.count
        }
        return seen.sorted {
            if $0.isAwareness != $1.isAwareness { return !$0.isAwareness }
            let a = order($0), b = order($1)
            return a == b ? $0.key < $1.key : a < b
        }
    }

    // MARK: body

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: S.gutter) {
                    SunnyHeading(title: "Featured")
                    if featured.isEmpty {
                        /* SHELL.md §9: Featured keeps its heading and shows one
                           line. It is hidden while a filter is on, because an
                           empty Featured under a filter means nothing. */
                        if !narrowed { SunnyEmptyLine("Nothing on a clock.") }
                    } else {
                        ForEach(featured) { card($0, featured: true) }
                    }

                    ForEach(Array(sections.enumerated()), id: \.offset) { _, s in
                        SunnyHeading(title: s.0.ticker, name: s.0.name,
                                     weight: s.0.weight > 0 ? "\(s.0.weight)%" : nil)
                        ForEach(s.1) { card($0, featured: false) }
                        /* ⚠ LAST IN THE SECTION, AND NEVER IN FEATURED. Nik:
                           "it wont be sitting in featured but on each ticker",
                           and five-day-price.md agrees — a price week is not on
                           a clock, so it has no claim on the top of the feed. It
                           also carries no read control for the same reason:
                           there is nothing to have read.

                           It sits under the awareness card rather than over it
                           because the awareness card is what CHANGED and this is
                           the standing backdrop. */
                        /* ⚠ THE LEGS WIDGET IS A REGION, NOT A CARD, and it
                           goes above the price week: the legs are the position,
                           the week is the backdrop. It owns opacity, transform
                           and clip for its zoom, so it must stay outside the
                           feed's reveal — which it is, because the reveal is
                           applied per card and this is not one. */
                        if let lp = legs.positions.first(where: { $0.ticker == s.0.ticker }) {
                            SunnyLegsRegion(p: lp)
                        }
                        if let w = s.0.week {
                            SunnyFiveDayCard(
                                ticker: s.0.ticker, m: w,
                                showPrice: Binding(
                                    get: { priceUnits.contains(s.0.ticker) },
                                    set: { on in
                                        if on { priceUnits.insert(s.0.ticker) }
                                        else { priceUnits.remove(s.0.ticker) }
                                    }))
                        }
                    }

                    /* ⚠ MISC STAYS, AND IT IS NOT THE OVERFLOW BIN. Nik: "Misc
                       stays, rail facts are only for cross-position numbers."
                       So the split is by SHAPE, not by importance: a number that
                       spans the book is a rail fact, and a CARD that belongs to
                       no single name is Misc. Today nothing lands here — the
                       week card is featured and every other card has a ticker —
                       so the heading is absent, which is the same rule every
                       name section follows. */
                    if !misc.isEmpty {
                        SunnyHeading(title: "Misc")
                        ForEach(misc) { card($0, featured: false) }
                    }

                    Color.clear.frame(height: S.railH)   // clears the dock overlay
                }
                /* ⚠ 361 CENTRED, NOT MARGIN 16. Nik's call, 2026-08-24.
                   The handoff is drawn at 393pt and the column arithmetic only
                   closes there: 16 + 175 + 11 + 175 + 16. On a wider phone
                   something has to give. Holding --margin at 16 would widen the
                   columns to 180 and the content to 370, which resizes every
                   card already signed off; holding the 361 block keeps the grid
                   exactly as drawn and spends the spare width on the margin
                   (20.5 on a 402pt device, measured).
                   The grid is the thing that was approved. The margin is what
                   flexes. Do not "fix" this back to a leading 16. */
                .frame(width: S.content)
                .padding(EdgeInsets(top: S.panePadTop, leading: S.margin,
                                    bottom: S.panePadBottom, trailing: S.margin))
            }
            .scrollIndicators(.hidden)
            .background(S.ground)
            /* ⚠ VERIFICATION ONLY, AND OFF THE NORMAL PATH ON PURPOSE.
               `.scrollPosition` was on this pane unconditionally at first. It
               has to be conditional: the modifier re-applies its binding on
               every re-render, and the dock's scroll handler re-renders the
               pane on every frame of a drag, so an always-on binding is a
               standing candidate for pinning the feed to the top. Reached only
               with -scrollTo, so a shipped run never carries it. */
            .modifier(SunnyDebugScroll(y: startAt))
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                /* ⚠ ONLY THE DOCK MOVES NOW. The filter strip used to ride this
                   same signal; SHELL.md §4 removed that — filters are the way
                   out of a long feed and must never be somewhere you scroll back
                   up to find. The dock keeps its own 12pt deadband: at 4 a
                   single thumb flick toggles it twice and the 580ms transform
                   never lands. */
                if y < S.scrollReveal { railHidden = false }
                else if y > lastY + S.scrollDeadbandRail { railHidden = true }
                else if y < lastY - S.scrollDeadbandRail { railHidden = false }
                lastY = y
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                SunnyRail(facts: rail.facts, hidden: railHidden, bottomInset: bottomSafeArea)
            }
            .ignoresSafeArea(edges: .bottom)

            if loading {
                SunnySkeleton()
                    .transition(.opacity.combined(with: .offset(y: S.overlayLift)))
            }
        }
        .onChange(of: query) { _, _ in applyChange(S.debounceQuery) }
        .onChange(of: filters) { _, _ in applyChange(S.debounceFilter) }
        .onChange(of: presentTags) { _, t in onTags(t) }
        /* Verification only: the touch bridge cannot inject a tap in this
           session, so this fires the real handler on the first featured card a
           few seconds in. Everything downstream of the tap is exercised; only
           UIKit delivering the touch is not. */
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-tapRead") else { return }
            try? await Task.sleep(for: .seconds(10))
            if let first = featured.first { markRead(first) }
        }
        .task {
            await rail.load()
            if Self.argShowPrice { priceUnits = Set(rail.book.map(\.ticker)) }
        }
        .task { await digest.load(); onTags(presentTags) }
        .task { await week.load(); onTags(presentTags) }
        .task { await planner.load() }
        .task { await legs.load() }
    }

    // MARK: a card, with or without its read control

    @ViewBuilder
    private func card(_ i: SunnyFeedItem, featured: Bool) -> some View {
        let mark: (() -> Void)? = featured ? { markRead(i) } : nil
        switch i.kind {
        case .week(let w):    SunnyWeekCard(m: w, onRead: mark)
        case .digest(let d):  SunnyDigestCard(d, onRead: mark)
        case .planner(let p): SunnyPlannerCard(m: p)      // no read control, see items
        }
    }

    /* Reading changes WHERE the card is, never what it says. SHELL.md §9
       measures the card identical before and after, and that is the point: the
       control files the card, it does not dismiss it.

       ⚠ ONE FUNCTION, SO THE PROBE CANNOT DIVERGE FROM THE BUTTON. -tapRead
       calls this, not a copy of it. A verification path that reimplements the
       thing it verifies is the shape of test that passes while the real control
       is broken, and this file has been burned by that once already. */
    private func markRead(_ i: SunnyFeedItem) {
        withAnimation(S.easeSettle(S.durRevealTransform)) {
            read.insert(i.id)
            SunnyRead.save(read)
        }
    }

    /// Every trigger cancels the previous timer (CHROME.md §8).
    private func applyChange(_ delay: Double) {
        debounce?.cancel()
        withAnimation(.easeInOut(duration: S.durOverlayIn)) { loading = true }
        debounce = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: S.durOverlayOut)) { loading = false }
                revealToken = UUID()
            }
        }
    }
}

/// Scrolls the pane to a fixed offset a few seconds after launch, so a
/// screenshot of "the feed at 1200" does not depend on a simulated drag landing
/// on the right pixel. No-op unless -scrollTo was passed.
struct SunnyDebugScroll: ViewModifier {
    let y: CGFloat?
    @State private var pos = ScrollPosition()

    func body(content: Content) -> some View {
        if let y {
            content
                .scrollPosition($pos)
                .task {
                    try? await Task.sleep(for: .seconds(6))   // let the cards land first
                    pos.scrollTo(y: y)
                }
        } else {
            content
        }
    }
}

// MARK: - section heading, 34pt

/// SHELL.md §7. Measured 361 × 34 = 10 + 18 (a 15px Inter line box) + 6.
///
/// ⚠ NEVER STICKY. Six sticky headings was tried and rejected: they all share
/// the pane as their containing block, so each stayed pinned for the whole
/// scroll and they piled up at the top edge.
///
/// Featured and Misc are the word alone. A name is three parts, and the middle
/// one MUST ellipsize — Polygon returns "Alibaba Group Holding Limited American
/// Depositary Shares, each represents eight Ordinary Shares" for BABA, which
/// overflows 361 several times over.
struct SunnyHeading: View {
    let title: String
    var name: String? = nil
    var weight: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.headingGap) {
            Text(title)
                .font(InkFont.display(S.t15, S.wSemi))
                .tracking(S.track(S.t15, -0.01))
                .foregroundStyle(S.ink)
            if let name, !name.isEmpty {
                Text(name)
                    .font(InkFont.display(S.t12, S.wMid))
                    .foregroundStyle(S.mute2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
            if let weight {
                Text(weight)
                    .font(InkFont.display(S.t14, S.wSemi))
                    .foregroundStyle(S.ink)
                    .monospacedDigit()
            }
        }
        .frame(width: S.content, alignment: .leading)
        .padding(.top, S.headingPadTop)
        .padding(.bottom, S.headingPadBottom)
        .measure("heading")
    }
}

struct SunnyEmptyLine: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text)
            .font(InkFont.display(S.t13, S.wMid))
            .foregroundStyle(S.mute2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// CHROME.md §9. Stagger counts VISIBLE cards only and caps at 300ms so a long
/// list does not feel slow.
extension View {
    func sunnyReveal(index: Int, token: UUID) -> some View {
        modifier(SunnyReveal(index: index, token: token))
    }
}

struct SunnyReveal: ViewModifier, Animatable {
    let index: Int
    let token: UUID
    @State private var shown = false

    func body(content: Content) -> some View {
        let delay = min(Double(index) * S.stagger, S.staggerCap)
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : S.revealScale)
            .offset(y: shown ? 0 : S.revealRise)
            .onAppear { fire(delay) }
            .onChange(of: token) { _, _ in shown = false; fire(delay) }
    }

    private func fire(_ delay: Double) {
        withAnimation(S.easeOut(S.durRevealOpacity).delay(delay)) { shown = true }
    }
}

// MARK: - §8 loading skeleton

struct SunnySkeleton: View {
    @State private var pulse = false
    /// The rhythm mirrors the real deck: S S / M / S S / XS.
    private let blocks: [(CGFloat, Double, Bool)] = [
        (104, 0.06, true), (148, 0.20, false), (104, 0.26, true), (72, 0.40, false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: S.gap4) {
            RoundedRectangle(cornerRadius: S.radiusPip)
                .fill(S.skeletonLabel).frame(width: 96, height: 11)
                .opacity(pulse ? 1 : 0.45)
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                if b.2 {
                    HStack(spacing: S.gap4) {
                        ForEach(0..<2, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: S.gap3)
                                .fill(S.skeleton).frame(height: b.0)
                        }
                    }
                    .opacity(pulse ? 1 : 0.45)
                } else {
                    RoundedRectangle(cornerRadius: S.gap3)
                        .fill(S.skeleton).frame(height: b.0)
                        .opacity(pulse ? 1 : 0.45)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: S.gap4, leading: S.margin, bottom: 0, trailing: S.margin))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(S.ground)
        .onAppear {
            withAnimation(.easeInOut(duration: S.pulse).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
