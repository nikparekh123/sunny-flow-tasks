//
//  HomeRouter.swift
//  Sunny
//
//  What Home has open: a receipt over the page (blocks 06 and 07), the
//  Aftershock page (26), a Position card opened on a face and the Insights
//  sheet (handoff 28; the Planner and Thesis are retired), and where quick
//  nav scrolls (08).
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

    // MARK: The Book (handoff 28)

    /// The Delta and Gamma jump, %: one value for every card and the Home map (3 to 10).
    var jump = 7
    /// A card opened from a tap: the face it opens on ("sold", "bought", "dg"), and the ring.
    var cardFace: [String: String] = [:]
    var cardTick = 0
    var ring: String?
    /// The Home page scrolls here, smoothly ("pos-NKE", "thisweek").
    var scrollTo: String?
    /// This week's rows highlighted from a card's rebalance row (1.8 s).
    var nxRing: String?
    /// This week's side, "s" Short or "l" Long (handoff 29): opens on Short, holds while the app is open.
    var weekSide = "s"
    /// This week shows its five most urgent per side until Show more.
    var weekMore = false
    /// The Insights sheet's name.
    var insights: String?
    /// To do: rows ticked, kept on the phone as they read when ticked, keyed "id@held" so a ticked row
    /// and its follow-up after a partial fill both stay in Done today (Nik, 21 Oct 2026). Last 7 days.
    var checked: [String: DoneTask] = {
        guard let d = UserDefaults.standard.data(forKey: "toDo.done"),
              let v = try? JSONDecoder().decode([String: DoneTask].self, from: d) else { return [:] }
        let cut = String(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7 * 86_400)).prefix(10))
        return v.filter { $0.value.day >= cut }
    }()
    func check(_ r: WeekTask, day: String) {
        let h = r.held ?? 0
        checked["\(r.id)@\(h)"] = DoneTask(id: r.id, day: day, held: h, t: r.t, kind: r.kind, face: r.face,
                                             action: r.action, cost: r.cost, credit: r.credit, delta: r.delta)
        save()
    }
    func uncheck(_ key: String) { checked[key] = nil; save() }
    private func save() {
        if let d = try? JSONEncoder().encode(checked) { UserDefaults.standard.set(d, forKey: "toDo.done") }
    }

    /// Opens a name's Position card on a face: scroll to it, swipe to the face, ring it 1.8 s.
    func openCard(_ t: String, face: String) {
        cardFace[t] = face
        cardTick += 1
        scrollTo = "pos-\(t)"
        ring = t
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            if self.ring == t { withAnimation(.easeOut(duration: 0.4)) { self.ring = nil } }
        }
    }
    /// From a card's rebalance row: up to This week, that name's text lit for 1.8 s.
    func focusThisWeek(_ t: String) {
        scrollTo = "thisweek"
        withAnimation(.easeInOut(duration: 0.4)) { nxRing = t }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            if self.nxRing == t { withAnimation(.easeInOut(duration: 0.4)) { self.nxRing = nil } }
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
    /// DEBUG: open a Positions page (its index) at launch.
    var debugPick: String?

    func open(_ r: Receipt) { withAnimation(S.standard(0.55)) { receipt = r } }
    func closeReceipt() { withAnimation(S.standard(0.55)) { receipt = nil } }
}
