//
//  HomeRouter.swift
//  Sunny
//
//  What the app has open: the tab (Home or Positions, handoff 30), a receipt
//  over the page (blocks 06 and 07), the Aftershock page (26), a Position card
//  opened on a face, the Positions filter and the Insights sheet, and where
//  quick nav scrolls (08).
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
    /// The two tabs (block 12a). Opens on Home.
    enum Tab: Hashable { case home, positions }

    var tab: Tab = .home
    /// Tapping the open tab scrolls it to the top (block 12a): each tab watches its own count.
    var topTick: [Tab: Int] = [:]
    var receipt: Receipt?

    // MARK: Positions (handoffs 28 and 30)

    /// The Delta and Gamma jump, %: one value for every card and the Home map (3 to 10).
    var jump = 7
    /// A card opened from a tap: the face it opens on ("todo", "sold", "bought", "dg"), and the ring.
    var cardFace: [String: String] = [:]
    var cardTick = 0
    var ring: String?
    /// The Positions screen scrolls here, smoothly ("pos-NKE").
    var scrollTo: String?
    /// The Positions filter (block 12): one at a time.
    var filter: PFilter = .all
    /// The Insights sheet's name.
    var insights: String?

    /// Opens a name's Position card on a face from anywhere: the Positions tab, then the card
    /// scrolled under the nav bar on that face, ringed 2 pt for 1.8 s (block 12a).
    func openCard(_ t: String, face: String) {
        let switching = tab != .positions
        tab = .positions
        cardFace[t] = face
        Task { @MainActor in
            // The tab's screen is built first, so its scroll and the card's pager are there to move.
            if switching { try? await Task.sleep(for: .milliseconds(350)) }
            self.cardTick += 1
            self.scrollTo = "pos-\(t)"
            self.ring = t
            try? await Task.sleep(for: .seconds(1.8))
            if self.ring == t { withAnimation(.easeOut(duration: 0.4)) { self.ring = nil } }
        }
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

/// The Positions filter (block 12): All names, To do, the stock today, or calls that kept at least
/// a share of their premium. One at a time.
enum PFilter: Hashable {
    case all, todo, up, down, kept(Int)
    var title: String {
        switch self {
        case .all: "All names"
        case .todo: "To do"
        case .up: "Stock up"
        case .down: "Stock down"
        case .kept(let p): "Captured \(p)%"
        }
    }
    /// What the screen says when nothing matches.
    var none: String {
        switch self {
        case .all: "No names here."
        case .todo: "Nothing to do this week. Every name is full and on target."
        case .up: "No stocks are up today."
        case .down: "No stocks are down today."
        case .kept(let p): "No calls have kept \(p)% of their premium yet."
        }
    }
}
