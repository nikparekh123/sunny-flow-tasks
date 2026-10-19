//
//  GalleryHost.swift
//  Sunny
//
//  DEBUG, simulator only: one block alone on the screen, as its Build
//  Blocks gallery tile, for the audits. `-gallery <block>`; `-preset
//  g.bottom=1` shows the bottom of a tall block.
//

import SwiftUI

#if DEBUG
struct GalleryHost: View {
    let block: String
    let store: HomeStore
    let home: HomePayload
    @Environment(HomeRouter.self) private var router

    var body: some View {
        let words = store.words ?? home
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content(words).id("block")
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                if DebugPreset.bool("g.bottom") {
                    Task { try? await Task.sleep(for: .milliseconds(300)); proxy.scrollTo("end", anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder private func content(_ words: HomePayload) -> some View {
        switch block {
        case "status":
            StatusLine(store: store).padding(.horizontal, S.margin)
        case "account":
            VStack(alignment: .leading, spacing: 10) {
                StatusLine(store: store).padding(.horizontal, S.margin)
                AccountChart(home: home)
            }
        case "chart":
            AccountChart(home: home)
        case "deck":
            SunnyDeck(cards: DeckBuilder.cards(home), today: home.today) { _ in }.padding(.horizontal, S.margin)
        case "aftershock-card":
            if let a = home.aftershock {
                SunnyAftershockCard(data: a, calendar: home.calendar, onTap: {}, onDismiss: {}).padding(.horizontal, S.margin)
            }
        case "today":
            SunnyToday(home: home)
        case "portfolio":
            SunnyPortfolio(home: home, words: words).padding(.horizontal, S.margin)
        case "positions":
            SunnyPositions(home: home)
        case "inventory":
            SunnyInventory(home: home, words: words).padding(.horizontal, S.margin)
        case "theta":
            SunnyMountain(kind: .theta, home: home) { _ in }.frame(width: 341).padding(.horizontal, S.margin)
        case "delta":
            SunnyMountain(kind: .delta, home: home) { _ in }.frame(width: 341).padding(.horizontal, S.margin)
        case "yield":
            SunnyYield(home: home, words: words).padding(.horizontal, S.margin)
        case "payback":
            SunnyPayback(home: home, words: words).padding(.horizontal, S.margin)
        case "svb":
            SunnySoldBought(home: home).padding(.horizontal, S.margin)
        case "performance":
            SunnyPerformance(words: words).padding(.horizontal, S.margin)
        case "allocation":
            SunnyAllocation(home: home, words: words).padding(.horizontal, S.margin)
        default:
            Text("No gallery for \(block)").padding()
        }
    }
}
#endif
