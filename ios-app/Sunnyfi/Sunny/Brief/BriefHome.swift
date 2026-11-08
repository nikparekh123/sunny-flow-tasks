//
//  BriefHome.swift
//  Sunny
//
//  New Home (block 29), top to bottom: the account strip (scrolls with the page), the account chart, the
//  deck (the day card and one alert a moment), the brief's title and date line, one lede, then the
//  numbered sections, each a kicker ("2 · Your book"), a headline and its cards.
//
//  Spacing (README 11.3): 20 pt gutters; 24 between strip, chart, deck and title; sections 56 apart
//  (padding 32 + the 24 gap); kicker to headline 8; headline to cards and card to card 20; 128 pt at the
//  bottom for the tab bar.
//
//  The account switch (block 33): this one page, never a second copy, jumps to 15% and 28 pt toward the new
//  account, then settles (S.switchFade 0.4 s opacity, S.switchMove 0.5 s move) while the strip slides its
//  names with the same move. Every card swaps to the new account at once, under the dip. A real book keeps the
//  dip until its brief lands (1.5 s at most), so the page never settles on the last book's numbers. Reduce
//  Motion: the fade only.
//

import SwiftUI

struct BriefHomeScreen: View {
    let store: HomeStore
    let home: HomePayload
    @Environment(BriefState.self) private var brief
    @Environment(HomeRouter.self) private var router
    @AppStorage(BriefPrivacy.key) private var privacy = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var pos = ScrollPosition()
    /// The account switch: the page at 15% (`faded`) and 28 pt toward the new account (`slid`), then back.
    @State private var faded = false
    @State private var slid = false
    @State private var dipDir: CGFloat = 0
    @State private var settling: Task<Void, Never>?

    /// The book this page shows. Overview keeps the last book under it, so going to or from it is no switch.
    private var pageBook: BriefAccount { brief.account == .overview ? brief.lastBook : brief.account }
    /// The page's numbers are pageBook's: the sample books swap at once, a real one once its brief has landed.
    private var pageReady: Bool {
        BriefDebug.sample || brief.book == nil || brief.book == (pageBook == .nicolay ? "N" : "S")
    }

    var body: some View {
        let moment = brief.moment()
        let doc = BriefDebug.sample ? BriefSample.doc(moment, brief.account.sampleKey) : brief.live?.doc
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if brief.showsStrip {
                    // No animation around the pick: the strip slides its own names (S.switchMove) and the page's
                    // dip runs from `dip()`, so the cards swap at once under it.
                    AccountStrip(accounts: brief.accounts, selected: brief.account) { a in brief.pick(a) }
                }
                // The page under the strip: the one view the switch dips and slides.
                VStack(alignment: .leading, spacing: 0) {
                    BriefPinBar().padding(.top, brief.pin == nil ? 0 : 8)
                    AccountChart(home: home, readTick: store.readTick)
                        .padding(.top, brief.showsStrip ? 0 : 14)
                    BriefDeck(moment: moment, doc: doc) { kind in
                        // Aftershock opens its page; Earnings season and Holiday scroll Home to the last section.
                        if kind == "aftershock" { if home.aftershock != nil { router.openAftershock() } }
                        else if let last = doc?.sections.last {
                            withAnimation(S.moving(S.page, reduce)) { proxy.scrollTo("sec-\(last.id)", anchor: .top) }
                        }
                    }
                    .padding(.top, 24)
                    if let doc {
                        BriefTitle(doc: doc, privacy: privacy)
                            .padding(.top, 24)
                            .padding(.horizontal, S.margin)
                            // The debug menu (Pass 3): a long press on the title.
                            .onLongPressGesture(minimumDuration: 1.0) { brief.debugOpen = true }
                        ForEach(doc.sections) { s in
                            BriefSectionView(section: s, privacy: privacy)
                                .padding(.top, 56)
                                .id("sec-\(s.id)")
                        }
                    } else {
                        BriefTitle(doc: nil, moment: moment, privacy: privacy)
                            .padding(.top, 24)
                            .padding(.horizontal, S.margin)
                            .onLongPressGesture(minimumDuration: 1.0) { brief.debugOpen = true }
                    }
                }
                .opacity(faded ? 0.15 : 1)
                .offset(x: slid ? 28 * dipDir : 0)
            }
            .padding(.bottom, 128)
            .containerRelativeFrame(.horizontal)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($pos)
        .overlay(alignment: .top) { BriefTopEdge() }
        .environment(\.timeValueTap, { brief.sheet = .timeValue })
        }
        .onChange(of: router.topTick[.home]) { _, _ in withAnimation(S.moving(S.page, reduce)) { pos.scrollTo(edge: .top) } }
        .onChange(of: pageBook) { _, _ in dip() }
        .onChange(of: pageReady) { _, ready in if ready && faded { settle(wait: false) } }
        .sheet(isPresented: Binding(get: { brief.debugOpen }, set: { brief.debugOpen = $0 })) {
            BriefDebugMenu().presentationDetents([.large])
        }
        .task {
            // DEBUG audits: `-pin open:week` pins a moment at launch (once the book is known).
            if let p = BriefDebug.pin, brief.pin == nil {
                for _ in 0..<20 where brief.book == nil { try? await Task.sleep(for: .milliseconds(250)) }
                await brief.applyPin(p)
            }
            // DEBUG audits: `-scroll 1600` opens Home scrolled that far, so a long page is shot in slices.
            if let y = BriefDebug.scroll {
                try? await Task.sleep(for: .milliseconds(600))
                pos.scrollTo(y: y)
            }
        }
    }

    /// The switch's first frame, drawn with no animation: 15%, and 28 pt toward the new account (not under
    /// Reduce Motion). Runs in the same update as the swap, so the new cards never show at full strength first.
    private func dip() {
        guard brief.showsStrip else { return }      // a one-book login's first load is no switch
        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t) { dipDir = brief.switchDir; faded = true; slid = !reduce }
        settle(wait: !pageReady)
    }
    /// Back to full (0.4 s) and home (0.5 s), two frames after the dip has drawn (the design's double
    /// requestAnimationFrame); a real book still loading holds the dip until it lands, 1.5 s at most.
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

/// Words as VoiceOver says them: the runs joined, " · " a pause, and with privacy on a hidden book figure
/// ($••• on screen) said as "hidden".
private enum HomeSpeech {
    static func say(_ spans: [BriefSpan], privacy: Bool) -> String {
        BriefWords.plain(spans.map(\.t).joined(), privacy: privacy)
            .replacingOccurrences(of: "$•••", with: "hidden")
            .replacingOccurrences(of: " · ", with: ", ")
    }
}

/// The soft edge under the status bar while a page scrolls (block 29: 76 pt, blur 6): the screen's own top
/// colour fading out, over a blur that fades the same way, so the clock never sits on a card.
struct BriefTopEdge: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                    .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                LinearGradient(colors: [S.dyn(0xEEF2F0, 0x0A0F0C), S.dyn(0xEEF2F0, 0x0A0F0C).opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
            }
            .frame(height: 76)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

// MARK: - Title and lede

/// The brief's name (28/34 bold), the date and state (13/16 secondary), then one lede (22/29 medium, the
/// key numbers bold and coloured). With privacy on the lede switches to its percentage wording.
struct BriefTitle: View {
    var doc: BriefDoc?
    var moment: Moment = .open
    let privacy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(doc?.title ?? moment.title)
                .sType(SType(size: 28, weight: 700, line: 34, tracking: -0.015), tabular: false)
                .foregroundStyle(S.ink)
                .accessibilityAddTraits(.isHeader)
            if let d = doc?.dateLine, !d.isEmpty {
                Text(d).sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false)
                    .foregroundStyle(S.secondaryOnPage)
                    .padding(.top, 2)
            }
            if let doc, !doc.lede.isEmpty {
                BriefSentence(privacy ? (doc.ledePrivacy ?? doc.lede) : doc.lede,
                                base: SType(size: 22, weight: 500, line: 29, tracking: -0.01), privacy: privacy)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
                    .accessibilityLabel(HomeSpeech.say(privacy ? (doc.ledePrivacy ?? doc.lede) : doc.lede, privacy: privacy))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - A section

struct BriefSectionView: View {
    let section: BriefSection
    let privacy: Bool

    var body: some View {
        let headline = privacy ? (section.headlinePrivacy ?? section.headline) : section.headline
        VStack(alignment: .leading, spacing: 0) {
            // Kicker and headline are one heading (block 29): "Your book, Down $13,740, most of it Lululemon."
            // The section number is left out of speech.
            VStack(alignment: .leading, spacing: 0) {
                Text("\(section.num) · \(section.kicker)")
                    .sType(SType(size: 13, weight: 700, line: 16, tracking: 0.02), tabular: false)
                    .foregroundStyle(S.secondaryOnPage)
                    .padding(.horizontal, S.margin)
                BriefSentence(headline, base: SType(size: 24, weight: 700, line: 30, tracking: -0.015), privacy: privacy)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, S.margin)
                    .padding(.top, 8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(section.kicker), \(HomeSpeech.say(headline, privacy: privacy))")
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 20) {
                ForEach(Array(section.cards.enumerated()), id: \.offset) { _, card in
                    BriefCardView(card: card, privacy: privacy)
                }
            }
            .padding(.top, 20)
        }
    }
}

// MARK: - The glass every Home card sits on (block 34)

/// Live Liquid Glass, as the design draws it. If scrolling stutters on the phone, `still` switches every
/// card to a material that looks the same, and live glass stays on the tab bar, Search, the strip and the
/// deck (answer 11).
enum BriefGlass {
    static var still = false
}

struct BriefCardChrome: ViewModifier {
    var radius: CGFloat = 20
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if BriefGlass.still { shape.fill(.ultraThinMaterial) }
            }
            .modifier(LiveGlass(shape: shape))
            .shadow(color: S.dynA(0x000000, 0.10, 0x000000, 0.40), radius: 12, y: 8)   // block 34: .1 light, .4 dark
    }

    private struct LiveGlass: ViewModifier {
        let shape: RoundedRectangle
        func body(content: Content) -> some View {
            if BriefGlass.still { content } else { content.glassEffect(.regular, in: shape) }
        }
    }
}

extension View {
    func briefCard(radius: CGFloat = 20, padding: CGFloat = 20) -> some View {
        modifier(BriefCardChrome(radius: radius, padding: padding))
    }
}
