//
//  SunnySummary.swift
//  Sunny — the family's shared notation. handoff/summary-lists.md.
//
//  ⚠ THE SIX SUMMARY LISTS AND THE FIVE M CARDS ARE RETIRED (27 Aug 2026), one
//  day after they shipped. What survives is this file's notation, which the
//  ticker card and the ladder both read: `8× Oct 17`, `$680 → $1,020`, four
//  digits drop the cents, U+2212 and never a hyphen.
//
//  The lists went because New measured 6,107 of standing aggregate against a
//  665 pane, so whatever was actually new that morning sat nine screens down —
//  and a card leads with what CHANGED, never a total. The strip is already the
//  cross-name view; a card on New that ranks nine names is the retired Featured
//  page coming back in through a card.
//
//  The M cards went because they were one card per name PER METRIC — five cards
//  to read one name, and a page of singletons. cards/ticker-card.md is their
//  replacement and says so in its own first line.
//
//  ⚠ THE LIST ROW ITSELF IS NOT LOST. cards/ticker-card.md is that row with the
//  axis swapped: the ticker moved to the header and the metric took the subject
//  slot. Everything the row learned — the three slots, the support classes, one
//  red slot per row, the direction-aware exception test — is still shipped, one
//  card over.
//

import SwiftUI

// MARK: - formatting, shared by every card in the family

/// U+2212, never a hyphen: these have to align in a tabular column.
func signedBare(_ v: Int) -> String {
    (v < 0 ? "\u{2212}" : "+") + abs(v).formatted(.number.grouping(.automatic))
}

/// ⚠ FOUR DIGITS AND UP DROP THE CENTS — `1,042`, not `1,042.00`. A
/// five-character figure is 58px and a nine-character one 88px, and it takes
/// that 30px straight out of the support column, which is the tightest
/// measurement on the card.
func sPrice(_ v: Double) -> String {
    v >= 1000 ? v.rounded().formatted(.number.grouping(.automatic))
              : String(format: "%.2f", v)
}

func sPct(_ v: Double) -> String { String(format: "%.1f%%", v) }

/// Thousands above $1,000, whole dollars below. `+$158` and `−$2.0K` on one
/// card is the design: below a thousand the exact figure is short enough to
/// print, and rounding it to `$0.2K` throws away the only precision there is.
func sK(_ v: Int) -> String {
    let sign = v < 0 ? "\u{2212}" : "+"
    let a = abs(v)
    return a >= 1000 ? "\(sign)$\(String(format: "%.1f", Double(a) / 1000))K"
                     : "\(sign)$\(a.formatted(.number.grouping(.automatic)))"
}

/// `2026-10-17` → `Oct 17`. No year: nothing in the open book is more than
/// fifteen months out, and the year would cost the support line 5 characters it
/// has not got.
func expShort(_ iso: String) -> String {
    let m = ["01": "Jan", "02": "Feb", "03": "Mar", "04": "Apr", "05": "May", "06": "Jun",
             "07": "Jul", "08": "Aug", "09": "Sep", "10": "Oct", "11": "Nov", "12": "Dec"]
    let p = iso.split(separator: "-")
    guard p.count == 3, let mm = m[String(p[1])] else { return iso }
    return "\(mm) \(Int(p[2]) ?? 0)"
}
