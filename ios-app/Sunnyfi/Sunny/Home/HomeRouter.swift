//
//  HomeRouter.swift
//  Sunny
//
//  What Home has open: a receipt over the page (blocks 06 and 07), the
//  Planner on a ticker (block 14b), and where quick nav scrolls (08).
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

    var receipt: Receipt?
    /// Week | Month and ‹ ›, shared by Inventory, Yield and Sold vs Bought.
    let period = PeriodState()
    /// The ticker the Planner (block 14b) is open on.
    var writes: String?
    /// Whether the Planner is up. Home reads this, not `writes`, so swiping
    /// between names in the Planner no longer redraws the whole Home page.
    var plannerOpen = false
    func openPlanner(_ t: String, animated: Bool = true) {
        writes = t
        withAnimation(animated ? S.standard(0.45) : nil) { plannerOpen = true }
    }
    func closePlanner() {
        withAnimation(S.standard(0.45)) { plannerOpen = false }
        writes = nil
    }
    /// Each name's plan, kept until the app closes ("ticker|expiry"; a name
    /// with no entry shows the engine's pick, live).
    var plans: [String: [PlanLeg]] = [:]
    var scrollTarget: Section?
    /// DEBUG: scroll to a block by id ("today", "portfolio", ...).
    var scrollID: String?
    /// DEBUG: open a Positions page (its index) at launch.
    var debugPick: String?

    func open(_ r: Receipt) { withAnimation(S.standard(0.55)) { receipt = r } }
    func closeReceipt() { withAnimation(S.standard(0.55)) { receipt = nil } }
}
