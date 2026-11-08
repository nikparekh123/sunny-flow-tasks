//
//  Overview.swift
//  Sunny
//
//  Overview (block 32, Search Explorations 42a): the coach's report on both books, in rates rather than
//  dollars so a book a third the size compares fairly. The strip on top (Overview selected), a header line,
//  one sentence (28/34 semibold, secondary with the key words in ink), the tally, six checks separated by
//  hairlines, then Coming in. Same screen background as Home; the tab bar and Search are away.
//

import SwiftUI

struct OverviewScreen: View {
    @Environment(BriefState.self) private var brief
    @AppStorage(BriefPrivacy.key) private var privacy = false
    @State private var pos = ScrollPosition()

    var body: some View {
        let o = BriefDebug.sample ? BriefSample.overview["privacyOff"] : (brief.liveOverview ?? .null)
        ZStack(alignment: .top) {
            SBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AccountStrip(accounts: brief.accounts, selected: brief.account) { a in
                        // The strip animates its own names (S.switchMove); HomeView animates Overview's exit.
                        brief.pick(a)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        if let h = o["header"].string {
                            Text(h).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                                .accessibilityLabel(BSay.words(h))
                                .accessibilityAddTraits(.isHeader)
                        }
                        // The design's head: 14 apart, then 24 to the list's top rule (New Home iPhone Preview, bo).
                        BriefSentence(BriefSpan.list(o["sentence"]), base: Self.sentence,
                                        baseColor: S.secondary, boldWeight: 600, privacy: privacy)
                            .modifier(OverviewTracking(t: Self.sentence))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 14)
                        tally(o["tally"]).padding(.top, 14)
                        // The six checks as one list for VoiceOver, one stop per check ("Delta, Watch", then its number and words).
                        // Each 18 above and below its content, a 1 pt rule between.
                        let checks = o["checks"].array
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(checks.enumerated()), id: \.offset) { i, c in
                                BHairline().padding(.top, i == 0 ? 24 : 18)
                                check(c).padding(.top, 18)
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("\(checks.count) checks")
                        if !o["comingIn"].isNull {
                            BHairline().padding(.top, 18)
                            comingIn(o["comingIn"]).padding(.top, 16)
                        }
                    }
                    .padding(.horizontal, S.margin)
                    // The design's page starts at 126 (50 + 76), 10 under the strip (44 + 72). The strip keeps a 72 pt slot
                    // under the safe area and draws `lift` higher, so the page pulls up by `lift` (as Home does).
                    .padding(.top, 10 - AccountStrip.lift)
                }
                .padding(.bottom, 128)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
            .scrollPosition($pos)
            .task {
                // DEBUG audits: `-scroll 900` opens Overview scrolled that far, so the page is shot in slices.
                if let y = BriefDebug.scroll { try? await Task.sleep(for: .milliseconds(600)); pos.scrollTo(y: y) }
            }
        }
    }

    /// The design's sentence 28/34 semibold (-.02em) and a check's sentence 15/21 medium.
    private static let sentence = SType(size: 28, weight: 600, line: 34, tracking: -0.02)
    private static let checkLine = SType(size: 15, weight: 500, line: 21, tracking: 0)

    /// Spoken parts as sentences: each part's own full stop dropped before the ". " join, so a sentence that
    /// ends in one never reads ".." ("of what both books hold. Puts cover").
    static func sentences(_ parts: [String?]) -> String {
        BSay.join(parts.map { p in
            guard var t = p?.trimmingCharacters(in: .whitespaces) else { return nil }
            while t.hasSuffix(".") { t.removeLast() }
            return t
        }, ". ")
    }

    private func tally(_ t: JSONValue) -> some View {
        // The design's tally wraps, 16 across and 6 down; 8 pt dots, 6 to their words.
        SXFlowGaps(column: 16, row: 6) {
            ForEach(Array(t.array.enumerated()), id: \.offset) { _, x in
                switch x["dot"].string {
                case "green": dot(S.green, x["t"].string ?? "", S.green)
                case "orange": dot(S.act, x["t"].string ?? "", S.act)
                default: Text(x["t"].string ?? "").sType(SType(size: 14, weight: 600, line: 18, tracking: 0)).foregroundStyle(S.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)   // "3 on track, 3 to watch, 5 trades to place"
    }

    private func dot(_ c: Color, _ s: String, _ ink: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(s).sType(SType(size: 14, weight: 600, line: 18, tracking: 0)).foregroundStyle(ink)
        }
    }

    private func check(_ c: JSONValue) -> some View {
        let watch = (c["status"].string ?? "").lowercased().hasPrefix("watch")
        let bigRed = c["bigColor"].string == "red"
        let said = c["chips"].array.compactMap(\.string).map { BSay.words($0, privacy: privacy) }.joined(separator: ", ")
        // The design's check: a grid 4 apart (name and status, the big number, the sentence, the chips 4 lower).
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(c["name"].string ?? "").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(watch ? S.act : S.green).frame(width: 7, height: 7)
                    Text(c["status"].string ?? "").sType(SType(size: 13, weight: 600, line: 18, tracking: 0), tabular: false)
                        .foregroundStyle(watch ? S.act : S.green)
                }
            }
            BriefWords.line(c["big"].string ?? c["value"].string, privacy: privacy)
                .sType(SType(size: 40, weight: 800, line: 46, tracking: -0.03))
                .foregroundStyle(bigRed ? S.red : S.ink)
            BriefSentence(BriefSpan.list(c["sentence"]), base: Self.checkLine, privacy: privacy)
                .fixedSize(horizontal: false, vertical: true)
            let chips = c["chips"].array.compactMap(\.string)
            if !chips.isEmpty {
                // One chip per account, wrapping 16 across and 4 down.
                SXFlowGaps(column: 16, row: 4) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, x in
                        Text(BriefWords.plain(x, privacy: privacy))
                            .sType(SType(size: 13, weight: 600, line: 18, tracking: 0))
                            .foregroundStyle(S.secondary)
                    }
                }
                .padding(.top, 4)
                .accessibilityLabel(BriefMask.spoken(chips.map { BriefWords.plain($0, privacy: privacy) }.joined(separator: ", ")))
            }
        }
        // One stop: the label is the content's own aria ("Delta, Watch"); the value its number (money "hidden" under
        // privacy), sentence and chips.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(c["aria"].string ?? BSay.join([c["name"].string, c["status"].string]))
        .accessibilityValue(Self.sentences([BSay.words(c["big"].string ?? c["value"].string, privacy: privacy),
                                            BSay.spans(c["sentence"], privacy: privacy), said]))
    }

    private func comingIn(_ c: JSONValue) -> some View {
        // The design's grid: 2 apart, the title and amount on one baseline.
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(c["title"].string ?? "Coming in").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Spacer()
                BriefWords.line(c["amount"].string, privacy: privacy).sType(SType(size: 17, weight: 800, line: 22, tracking: 0)).foregroundStyle(S.green)
            }
            BriefWords.line(c["line"].string ?? c["sub"].string, privacy: privacy)
                .sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // "Coming in, $6,245. Dividends by Dec 8 ..." with every amount "hidden" under privacy.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(c["title"].string ?? "Coming in")
        .accessibilityValue(Self.sentences([BSay.words(c["amount"].string, privacy: privacy),
                                            BSay.words(c["line"].string ?? c["sub"].string, privacy: privacy)]))
    }
}

/// BriefSentence sets the fonts and the line box but not the tracking: the design's sentence is -.02em.
private struct OverviewTracking: ViewModifier {
    let t: SType
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.sTypeScales) private var scales
    func body(content: Content) -> some View {
        let st = scales ? t.scaled(dts) : t
        content.tracking(st.tracking * st.size)
    }
}
