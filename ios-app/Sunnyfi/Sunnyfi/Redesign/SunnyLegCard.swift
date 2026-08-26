//
//  SunnyLegCard.swift
//  Sunny — a week of a leg's P&L. Only the model survives here.
//
//  ⚠ THE FIVE PER-LEG CARDS ARE RETIRED (26 Aug 2026), replaced by the single
//  position card in SunnyPositionCard.swift. They are deleted rather than
//  commented out, and they should not be rebuilt from cards/position-leg.md or
//  from a screenshot.
//
//  Why they went, in Nik's words: "I feel it looses the story." Their own build
//  sheet had already recorded the reason under "open questions" — the five
//  scales are not comparable, a 110pt bar being +$2,100 on shares and +$210 on
//  calls bought — and stacking five of them in one pane is a stronger invitation
//  to compare than any single card ever is. Shares showing a loss beside calls
//  showing a profit could not be reconciled by the reader, because there was
//  nothing on screen that added them up.
//
//  The replacement takes the same weekly quantity and SUMS it across every leg,
//  which is one comparable scale and one story: what the position did that week.
//
//  `LegWeek` stays because position-legs still sends a series per leg, and
//  summing them is exactly what the position card does with it.
//

import SwiftUI

/// One week of one leg's CHANGE IN P&L.
///
/// ⚠ CHANGE IN P&L, never cash that moved. A sold put held to expiry moves cash
/// ONCE, so three of four weeks would be empty. P&L change exists every week for
/// every leg type: decay for a sold leg, mark for a bought one, price times
/// quantity for shares. It is the one quantity that lets the legs be added.
struct LegWeek: Decodable, Identifiable {
    let label: String
    let live: Bool
    let pnl: Int
    var id: String { label }
}
