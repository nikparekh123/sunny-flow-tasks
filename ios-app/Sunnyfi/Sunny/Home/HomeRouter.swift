//
//  HomeRouter.swift
//  Sunny
//
//  What the app has open: the tab (Home or Positions, handoff 30), a receipt
//  over the page (blocks 06 and 07), the Aftershock page (26), the name the
//  Positions tab opens on, and where quick nav scrolls (08).
//

import SwiftUI
import Observation

@MainActor
@Observable
final class HomeRouter {
    enum Receipt: Equatable {
        case report(Int)          // index into deck.reports
        case theta(String)        // a theta check's leg
    }
    enum Section: String, CaseIterable, Identifiable {
        case book = "Book", risk = "Risk", income = "Income", results = "Results"
        var id: String { rawValue }
    }
    /// The four tabs (block 12c, handoff 32) and Search, the round button right of them (block 27). Opens on Home.
    enum Tab: Hashable {
        case home, positions, gamma, insights, search
        /// Two tabs since the 6 Nov handoff (answer 7): Gamma and Insights are gone; Walls on Positions and the
        /// ticker chart do Gamma's job, Your position, To decide and the Thesis check do Insights'.
        static let bar: [Tab] = [.home, .positions]
        var title: String { switch self { case .home: "Home"; case .positions: "Positions"; case .gamma: "Gamma"; case .insights: "Insights"; case .search: "Search" } }
        var icon: String {
            switch self {
            case .home: "house.fill"; case .positions: "rectangle.stack.fill"; case .gamma: "chart.bar.doc.horizontal"
            case .insights: "lightbulb"; case .search: "magnifyingglass"
            }
        }
    }

    var tab: Tab = .home
    /// Search is a page of its own over the tab it was opened from (block 27, final Oct 28): the tab stays as it
    /// was underneath, and the back button returns to it.
    var searchOpen = false
    var searchFrom: Tab = .home
    /// A press and hold on the search button (0.45 s) opens Search already listening.
    var listenTick = 0
    /// Tapping the open tab scrolls it to the top (block 12a): each tab watches its own count.
    var topTick: [Tab: Int] = [:]
    var receipt: Receipt?

    // MARK: Positions (handoffs 28 and 30)

    /// The Delta and Gamma jump, %: one value for every card and the Home map (3 to 10).
    var jump = 7
    /// The Δ Γ face's move, % (handoff 32, 13g): one value for every card, 10% down to 10% up.
    var move = 7
    /// The name the Positions tab opens on, from a tap elsewhere (the tab takes it and clears it).
    var positionsName: String?
    /// The name Gamma and Insights are on (12c: it carries over between the two tabs).
    var focus: String?
    /// Insights opens on All the first time, then follows Gamma (12c).
    var insightsAll = true
    /// A wall chip in a To do order: Gamma on that name and chain, the wall ringed for 2.6 s (13e).
    var gammaView: String?
    var gammaRing: Double?
    func openGamma(_ t: String, view: String?, wall: Double?) {
        focus = t
        gammaView = view
        tab = .gamma
        gammaRing = wall
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6 + 0.5))
            if self.gammaRing == wall { withAnimation(.easeOut(duration: 0.4)) { self.gammaRing = nil } }
        }
    }

    /// Opens a name on the Positions tab from anywhere (the old cards' faces went on 13 Nov 2026: the tab is view
    /// only, one name at a time, so `face` is no longer used).
    func openCard(_ t: String, face: String) {
        tab = .positions
        positionsName = t
    }
    /// Week | Month and ‹ ›, shared by Inventory, Yield and Sold vs Bought.
    let period = PeriodState()
    /// The Aftershock page (block 26), pushed from its deck card (03b) and
    /// from the 4:16 PM push. Back returns where it was opened from.
    var aftershockOpen = false
    func openAftershock(animated: Bool = true) {
        withAnimation(animated ? S.standard(0.45) : nil) { aftershockOpen = true }
    }
    func closeAftershock() { withAnimation(S.standard(0.45)) { aftershockOpen = false } }
    var scrollTarget: Section?
    /// DEBUG: scroll to a block by id ("today", "portfolio", ...).
    var scrollID: String?

    func open(_ r: Receipt) { withAnimation(S.standard(0.55)) { receipt = r } }
    func closeReceipt() { withAnimation(S.standard(0.55)) { receipt = nil } }
}
