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

import SwiftUI

struct BriefHomeScreen: View {
    let store: HomeStore
    let home: HomePayload
    @Environment(BriefState.self) private var brief
    @Environment(HomeRouter.self) private var router
    @AppStorage(BriefPrivacy.key) private var privacy = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var pos = ScrollPosition()

    var body: some View {
        let moment = brief.moment()
        let doc = BriefDebug.sample ? BriefSample.doc(moment, brief.account.sampleKey) : nil
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if brief.showsStrip {
                    AccountStrip(accounts: brief.accounts, selected: brief.account) { a in
                        withAnimation(reduce ? nil : S.standard(0.5)) { brief.pick(a) }
                    }
                }
                AccountChart(home: home, readTick: store.readTick)
                    .padding(.top, brief.showsStrip ? 0 : 14)
                BriefDeck(moment: moment, doc: doc) { kind in
                    // Aftershock opens its page; Earnings season and Holiday scroll Home to the last section.
                    if kind == "aftershock" { if home.aftershock != nil { router.openAftershock() } }
                    else if let last = doc?.sections.last {
                        withAnimation(reduce ? nil : .timingCurve(0.45, 0, 0.25, 1, duration: 1.0)) { proxy.scrollTo("sec-\(last.id)", anchor: .top) }
                    }
                }
                .padding(.top, 24)
                if let doc {
                    BriefTitle(doc: doc, privacy: privacy)
                        .padding(.top, 24)
                        .padding(.horizontal, S.margin)
                    ForEach(doc.sections) { s in
                        BriefSectionView(section: s, privacy: privacy)
                            .padding(.top, 56)
                            .id("sec-\(s.id)")
                    }
                } else {
                    BriefTitle(doc: nil, moment: moment, privacy: privacy)
                        .padding(.top, 24)
                        .padding(.horizontal, S.margin)
                }
            }
            .padding(.bottom, 128)
            .containerRelativeFrame(.horizontal)
            .id(brief.account)
            .transition(reduce ? .opacity : .opacity.combined(with: .offset(x: 28 * brief.switchDir)))
        }
        .scrollIndicators(.hidden)
        .scrollPosition($pos)
        .overlay(alignment: .top) { BriefTopEdge() }
        .environment(\.timeValueTap, { brief.sheet = .timeValue })
        }
        .onChange(of: router.topTick[.home]) { _, _ in withAnimation(reduce ? nil : S.standard(0.45)) { pos.scrollTo(edge: .top) } }
        .task {
            // DEBUG audits: `-scroll 1600` opens Home scrolled that far, so a long page is shot in slices.
            if let y = BriefDebug.scroll {
                try? await Task.sleep(for: .milliseconds(600))
                pos.scrollTo(y: y)
            }
        }
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
                    .foregroundStyle(S.secondary)
                    .padding(.top, 2)
            }
            if let doc, !doc.lede.isEmpty {
                BriefWords.text(privacy ? (doc.ledePrivacy ?? doc.lede) : doc.lede,
                                base: SType(size: 22, weight: 500, line: 29, tracking: -0.01), privacy: privacy)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
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
        VStack(alignment: .leading, spacing: 0) {
            Text("\(section.num) · \(section.kicker)")
                .sType(SType(size: 13, weight: 700, line: 16, tracking: 0.02), tabular: false)
                .foregroundStyle(S.secondary)
                .padding(.horizontal, S.margin)
            BriefWords.text(privacy ? (section.headlinePrivacy ?? section.headline) : section.headline,
                            base: SType(size: 24, weight: 700, line: 30, tracking: -0.015), privacy: privacy)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, S.margin)
                .padding(.top, 8)
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
            .shadow(color: .black.opacity(0.08), radius: 12, y: 8)
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
