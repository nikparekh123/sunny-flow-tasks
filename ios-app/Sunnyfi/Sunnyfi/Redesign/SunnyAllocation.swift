//
//  SunnyAllocation.swift
//  Allocation payload and money helpers, read by The Book. The Allocation
//  card itself was unmounted on 23 Sep and deleted on 8 Oct 2026. Originally
//  (export 23, 21 Sep 2026): where the capital sits, a name at a
//  time. What went in against what it is worth now; one stacked bar for the
//  spread, a ledger under it, a Total row to close it.
//
//  ⚠ EVERYTHING BOUGHT, NOT SHARES ALONE. The sheet counts shares; on this book
//  that misses the LEAPs, which is most of the money. Nik, 21 Sep: shares +
//  long calls + long puts, TLT left out. The server sums them per name
//  (`allocationCard.book[].inv / now`), so the card only sorts and prints.
//
//  ⚠ SORTED BY INVESTED, ALWAYS. The lens re-slices the shares (the bar and the
//  % column) and moves no row.
//
//  ⚠ A NAME'S COLOUR IS ITS RANK. The grey ramp carries no P&L; green and red
//  live on the NOW column and the hero delta only.
//

import SwiftUI

// MARK: - payload

struct AllocationCard: Decodable {
    let asOf: String?
    let book: [AllocName]
}

struct AllocName: Decodable {
    let t: String
    let inv: Double
    let now: Double
}

// MARK: - money

/// `usdM`: $1.74m · $470k · $28.4k · $5.4k · $840.
func usdM(_ n: Double) -> String {
    let a = abs(n), sign = n < 0 ? "\u{2212}" : ""
    if a >= 1e6 { return sign + "$" + String(format: "%.2f", a / 1e6) + "m" }
    if a >= 1e5 { return sign + "$" + String(Int((a / 1e3).rounded())) + "k" }
    if a >= 1e3 {
        var s = String(format: "%.1f", a / 1e3)
        if s.hasSuffix(".0") { s.removeLast(2) }
        return sign + "$" + s + "k"
    }
    return sign + "$" + String(Int(a.rounded()))
}

/// `signedPct` in the sheet: one decimal under 10, none over; no sign on zero.
func alPct(_ n: Double) -> String {
    let a = abs(n)
    let r = a < 10 ? String(format: "%.1f", a) : String(Int(a.rounded()))
    return ((Double(r) ?? 0) == 0 ? "" : (n < 0 ? "\u{2212}" : "+")) + r + "%"
}
