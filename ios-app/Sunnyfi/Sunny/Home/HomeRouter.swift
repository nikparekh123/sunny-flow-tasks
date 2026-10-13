//
//  HomeRouter.swift
//  Sunny
//
//  What Home has open: a receipt over the page (blocks 06 and 07), the
//  Writes sheet on a ticker (block 14), and where quick nav scrolls (08).
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
    var writes: String?
    var scrollTarget: Section?
    /// DEBUG: scroll to a block by id ("today", "portfolio", ...).
    var scrollID: String?
    /// DEBUG: pick a Positions chip at launch.
    var debugPick: String?

    func open(_ r: Receipt) { withAnimation(S.standard(0.55)) { receipt = r } }
    func closeReceipt() { withAnimation(S.standard(0.55)) { receipt = nil } }
}
