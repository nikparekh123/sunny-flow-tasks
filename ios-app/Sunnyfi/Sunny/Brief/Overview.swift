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
                        BriefSentence(BriefSpan.list(o["sentence"]), base: SType(size: 28, weight: 600, line: 34, tracking: -0.015),
                                        baseColor: S.secondary, boldWeight: 600, privacy: privacy)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                        tally(o["tally"]).padding(.top, 14)
                        // The six checks as one list for VoiceOver, one stop per check ("Delta, Watch", then its number and words).
                        let checks = o["checks"].array
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(checks.enumerated()), id: \.offset) { _, c in
                                Rectangle().fill(S.hairline).frame(height: 0.5).padding(.top, 18)
                                check(c).padding(.top, 18)
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("\(checks.count) checks")
                        if !o["comingIn"].isNull {
                            Rectangle().fill(S.hairline).frame(height: 0.5).padding(.top, 18)
                            comingIn(o["comingIn"]).padding(.top, 18)
                        }
                    }
                    .padding(.horizontal, S.margin)
                    .padding(.top, 4)
                }
                .padding(.bottom, 128)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func tally(_ t: JSONValue) -> some View {
        HStack(spacing: 14) {
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
            Circle().fill(c).frame(width: 7, height: 7)
            Text(s).sType(SType(size: 14, weight: 600, line: 18, tracking: 0)).foregroundStyle(ink)
        }
    }

    private func check(_ c: JSONValue) -> some View {
        let watch = (c["status"].string ?? "").lowercased().hasPrefix("watch")
        let bigRed = c["bigColor"].string == "red"
        let said = c["chips"].array.compactMap(\.string).map { BSay.words($0, privacy: privacy) }.joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 6) {
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
            BriefSentence(BriefSpan.list(c["sentence"]), base: SType(size: 15, weight: 500, line: 21, tracking: 0), privacy: privacy)
                .fixedSize(horizontal: false, vertical: true)
            let chips = c["chips"].array.compactMap(\.string)
            if !chips.isEmpty {
                Text(chips.map { BriefWords.plain($0, privacy: privacy) }.joined(separator: "    "))
                    .accessibilityLabel(BriefMask.spoken(chips.map { BriefWords.plain($0, privacy: privacy) }.joined(separator: ", ")))
                    .sType(SType(size: 13, weight: 600, line: 18, tracking: 0))
                    .foregroundStyle(S.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // One stop: the label is the content's own aria ("Delta, Watch"); the value its number (money "hidden" under
        // privacy), sentence and chips.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(c["aria"].string ?? BSay.join([c["name"].string, c["status"].string]))
        .accessibilityValue(BSay.join([BSay.words(c["big"].string ?? c["value"].string, privacy: privacy),
                                       BSay.spans(c["sentence"], privacy: privacy), said], ". "))
    }

    private func comingIn(_ c: JSONValue) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
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
        .accessibilityValue(BSay.join([BSay.words(c["amount"].string, privacy: privacy),
                                       BSay.words(c["line"].string ?? c["sub"].string, privacy: privacy)], ". "))
    }
}
