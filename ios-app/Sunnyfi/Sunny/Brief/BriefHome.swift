//
//  BriefHome.swift
//  Sunny
//
//  New Home (block 29), top to bottom: the account strip (scrolls with the page), the account chart, the
//  deck (the day card and one alert a moment), the brief's title and date line, one lede, then the
//  numbered sections, each a kicker ("2 · Your book"), a headline and its cards.
//
//  Spacing (README 11.3, the design's CSS where they differ): 20 pt gutters; the strip at y 44, the chart 4 under it
//  (page padding 120); 24 between chart, deck and title; sections 56 apart
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
                    // The design's page starts at y 120, 4 under the strip (44 + 72).
                    AccountChart(home: home, readTick: store.readTick)
                        .padding(.top, brief.showsStrip ? 4 : 14)
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
                // The strip draws `lift` above its 72 pt slot (y 44 on a 402 pt phone); the page follows it up.
                .padding(.top, brief.showsStrip ? -AccountStrip.lift : 0)
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

/// The brief's name (32/38 heavy), the date and state (15/20 secondary), then one lede (22/29 medium, the
/// key numbers bold and coloured). With privacy on the lede switches to its percentage wording.
/// Sizes from SunnyBriefs.dc.html (head): the README's 28/34 and 13/16 are older; the design's CSS wins.
struct BriefTitle: View {
    var doc: BriefDoc?
    var moment: Moment = .open
    let privacy: Bool
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.sTypeScales) private var scales
    @State private var width: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(doc?.title ?? moment.title)
                .sType(SType(size: 32, weight: 800, line: 38, tracking: -0.02), tabular: false)
                .foregroundStyle(S.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 4)
            if let d = doc?.dateLine, !d.isEmpty {
                Text(d).sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                    .foregroundStyle(S.mutedOnPage)   // SunnyBriefs --mu #646469
                    .padding(.top, 4)
            }
            if let doc, !doc.lede.isEmpty {
                // text-wrap: pretty (never one word alone on the last line).
                BriefSentence(SentenceWrap.apply(privacy ? (doc.ledePrivacy ?? doc.lede) : doc.lede,
                                                 scales ? Self.lede.scaled(dts) : Self.lede, width: width, .pretty, privacy: privacy),
                                base: Self.lede, privacy: privacy)
                    .modifier(SentenceBox(t: Self.lede))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                    .accessibilityLabel(HomeSpeech.say(privacy ? (doc.ledePrivacy ?? doc.lede) : doc.lede, privacy: privacy))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    static let lede = SType(size: 22, weight: 500, line: 29, tracking: -0.01)
}

/// BriefSentence gives the line box; the letter spacing (-.01em lede, -.015em headline) goes on here.
struct SentenceBox: ViewModifier {
    let t: SType
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.sTypeScales) private var scales
    func body(content: Content) -> some View {
        let t = scales ? self.t.scaled(dts) : self.t
        content.tracking(t.tracking * t.size)
    }
}

// MARK: - A section

struct BriefSectionView: View {
    let section: BriefSection
    let privacy: Bool
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.sTypeScales) private var scales
    @State private var width: CGFloat = 0

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
                // text-wrap: balance (block 29).
                BriefSentence(SentenceWrap.apply(headline, scales ? Self.headline.scaled(dts) : Self.headline,
                                                 width: width - 2 * S.margin, .balance, privacy: privacy),
                              base: Self.headline, privacy: privacy)
                    .modifier(SentenceBox(t: Self.headline))
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    static let headline = SType(size: 24, weight: 700, line: 30, tracking: -0.015)
}

/// CSS text-wrap for a sentence of runs, which SwiftUI does not have (SWrap does it for one font). The breaks are
/// worked out with each run's own font (bold runs are wider) and set as line breaks, so the text renders as wrapped.
/// Balance: the narrowest width that keeps the same number of lines. Pretty: never one word alone on the last line.
/// With privacy on it wraps (and returns) the masked words.
enum SentenceWrap {
    static func apply(_ spans: [BriefSpan], _ t: SType, width: CGFloat, _ mode: SWrap.Mode, privacy: Bool) -> [BriefSpan] {
        let shown = spans.map { BriefSpan(privacy ? BriefMask.mask($0.t) : $0.t, b: $0.b, c: $0.c) }
        guard width > 40 else { return shown }
        let full = NSMutableAttributedString()
        for r in shown {
            full.append(NSAttributedString(string: r.t, attributes: [.font: (r.b ? t.weighted(700) : t).uiFont(tabular: true),
                                                                     .kern: t.tracking * t.size]))
        }
        let str = full.string as NSString
        guard !str.contains("\n") else { return shown }
        var words: [NSRange] = [], start = -1
        for i in 0...str.length {
            let space = i == str.length || str.character(at: i) == 32
            if space, start >= 0 { words.append(NSRange(location: start, length: i - start)); start = -1 }
            else if !space, start < 0 { start = i }
        }
        guard words.count > 1 else { return shown }
        func span(_ a: Int, _ b: Int) -> CGFloat {
            ceil(full.attributedSubstring(from: NSRange(location: words[a].location,
                                                        length: NSMaxRange(words[b]) - words[a].location)).size().width)
        }
        let fit = width - 1
        func greedy(_ w: CGFloat) -> [[Int]] {
            var out: [[Int]] = [], line: [Int] = []
            for k in words.indices {
                if line.isEmpty || span(line[0], k) <= w { line.append(k) } else { out.append(line); line = [k] }
            }
            if !line.isEmpty { out.append(line) }
            return out
        }
        var best = greedy(fit)
        guard best.count > 1 else { return shown }
        switch mode {
        case .balance:
            var lo: CGFloat = 0, hi = fit
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if greedy(mid).count <= best.count { hi = mid } else { lo = mid }
            }
            best = greedy(hi)
        case .pretty:
            let n = best.count
            if best[n - 1].count == 1, best[n - 2].count >= 2 {
                let moved = best[n - 2].removeLast()
                best[n - 1].insert(moved, at: 0)
            }
        }
        // The space after each line's last word becomes a line break, in whichever run holds it.
        let breaks = Set(best.dropLast().map { NSMaxRange(words[$0[$0.count - 1]]) })
        var out: [BriefSpan] = [], at = 0
        for r in shown {
            let ns = r.t as NSString
            var u = r.t
            for b in breaks.sorted(by: >) where b >= at && b < at + ns.length && ns.character(at: b - at) == 32 {
                u = (u as NSString).replacingCharacters(in: NSRange(location: b - at, length: 1), with: "\n")
            }
            out.append(BriefSpan(u, b: r.b, c: r.c))
            at += ns.length
        }
        return out
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
                // Block 34's fill inside the glass: linear 160°, white .62 → .22 → .14 → .40 (dark .10 → .03 → .02 → .07).
                // Inset shadows paint under the content, as in CSS, so the edges sit here too.
                ZStack {
                    if BriefGlass.still { shape.fill(.ultraThinMaterial) }
                    shape.fill(Self.fill)
                    Self.edges(shape)
                }
            }
            .modifier(LiveGlass(shape: shape))
            .shadow(color: S.dynA(0x000000, 0.10, 0x000000, 0.40), radius: 12, y: 10)   // 0 10 24 -6, .1 light, .4 dark
    }

    /// The design's backdrop filter (brightness 1.06, contrast 1.05) clips the light page to white under each card, and
    /// its dark card reads near black; plain glass reads grey (245 light, 20 to 30 dark) and takes the blobs' colour.
    static let tint = S.dynA(0xFFFFFF, 0.85, 0x000000, 0.85)

    /// The CSS gradient line at 160° on a card about 362 × 300 runs from (0.3, -0.12) to (0.7, 1.12).
    private static let fill = LinearGradient(stops: [
        .init(color: S.dynA(0xFFFFFF, 0.62, 0xFFFFFF, 0.10), location: 0),
        .init(color: S.dynA(0xFFFFFF, 0.22, 0xFFFFFF, 0.03), location: 0.38),
        .init(color: S.dynA(0xFFFFFF, 0.14, 0xFFFFFF, 0.02), location: 0.62),
        .init(color: S.dynA(0xFFFFFF, 0.40, 0xFFFFFF, 0.07), location: 1),
    ], startPoint: UnitPoint(x: 0.3, y: -0.12), endPoint: UnitPoint(x: 0.7, y: 1.12))

    /// The inner edges (--csh): a 1 pt white ring (.7 / .16), a 1.5 pt top-left highlight (1 / .28), a fainter
    /// bottom-right one (.55 / .08) and a soft glow under the top edge (.9 / .12), plus the .5 pt outer ring in light.
    @ViewBuilder private static func edges(_ shape: RoundedRectangle) -> some View {
        ZStack {
            shape.fill(LinearGradient(colors: [S.dynA(0xFFFFFF, 0.9, 0xFFFFFF, 0.12), .clear],
                                      startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.12)))
                .opacity(0.35)
            shape.strokeBorder(S.dynA(0xFFFFFF, 0.7, 0xFFFFFF, 0.16), lineWidth: 1)
            shape.strokeBorder(LinearGradient(colors: [S.dynA(0xFFFFFF, 1, 0xFFFFFF, 0.28), .clear],
                                              startPoint: .topLeading, endPoint: .center), lineWidth: 1.5)
            shape.strokeBorder(LinearGradient(colors: [.clear, S.dynA(0xFFFFFF, 0.55, 0xFFFFFF, 0.08)],
                                              startPoint: .center, endPoint: .bottomTrailing), lineWidth: 1)
            shape.stroke(S.dynA(0x1D1D1F, 0.06, 0x000000, 0), lineWidth: 0.5)
        }
    }

    private struct LiveGlass: ViewModifier {
        let shape: RoundedRectangle
        func body(content: Content) -> some View {
            if BriefGlass.still { content } else { content.glassEffect(.regular.tint(BriefCardChrome.tint), in: shape) }
        }
    }
}

extension View {
    func briefCard(radius: CGFloat = 20, padding: CGFloat = 20) -> some View {
        modifier(BriefCardChrome(radius: radius, padding: padding))
    }
}
