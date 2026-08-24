//
//  SunnyModel.swift
//  Sunny — the card slot contract and the filter machine. CARDS.md is normative.
//

import SwiftUI

/// A filter key.
///
/// ⚠ NO LONGER A CLOSED ENUM. CARDS.md fixes the vocabulary at
/// `tlt nke nvda earnings iv`, which worked while the deck was 18 fixed shells.
/// It cannot survive Nik's rule that every card carries its ticker AND a
/// per-card tag ("NKE Awareness"), because that set grows with the positions he
/// holds and with the kinds of card that exist. So the vocabulary is DERIVED
/// from the cards in the feed instead of declared ahead of them.
///
/// `key` is what matching uses and is always lowercase. `label` is what the
/// filter rail shows. Keeping them separate is what lets "NKE Awareness" be one
/// tag rather than two words that happen to sit together.
struct SunnyTag: Identifiable, Hashable, Comparable {
    let key: String
    let label: String
    var id: String { key }

    init(_ label: String) {
        self.label = label
        self.key = label.lowercased()
    }
    /// The ticker on its own.
    static func ticker(_ t: String) -> SunnyTag { SunnyTag(t.uppercased()) }
    /// The card-kind tag: "NKE Awareness".
    static func awareness(_ t: String) -> SunnyTag { SunnyTag("\(t.uppercased()) Awareness") }

    var isAwareness: Bool { key.hasSuffix(" awareness") }

    /* ⚠ IDENTITY IS THE KEY ALONE, never the label. The synthesized conformance
       hashed both, so SunnyTag("nke") and SunnyTag("NKE") were two different
       filters that matched the same cards — and the filter set is compared by
       SET INTERSECTION, so selecting one could never find a card tagged with
       the other. It showed up as a pre-filtered launch returning an empty feed
       with the pill un-highlighted: the filter was on, and nothing on earth
       carried it.

       `key` is already documented as the thing matching uses. The label is
       presentation, and two spellings of one filter are one filter. */
    static func == (a: SunnyTag, b: SunnyTag) -> Bool { a.key == b.key }
    func hash(into h: inout Hasher) { h.combine(key) }

    /// Plain tickers first, then the per-card tags, each alphabetical. Without
    /// an order the rail reshuffles whenever the position set changes.
    static func < (a: SunnyTag, b: SunnyTag) -> Bool {
        a.isAwareness == b.isAwareness ? a.key < b.key : (!a.isAwareness && b.isAwareness)
    }
}

/* ⚠ `SunnyZone` AND `SunnyDeck` ARE GONE. The zone enum carried Now / New /
   Next with a per-zone padding, and SunnyDeck was the 18-shell placeholder deck
   keyed on it. SHELL.md deletes the zones outright: a card now sits in Featured,
   under its own name, or in Misc, and where it sits is decided by `place()` in
   SunnyFeed.swift, not by how recent it is.

   The deck's original order is recorded in git, not here. Do not reconstruct
   either type from memory — a zone is not a thing the app has any more. */

/// One feed slot. `tags` and `name` are the ONLY filter surfaces.
///
/// ⚠ CARDS.md: "Filtering matches data-tags and data-name only — never element
/// text. A card whose content mentions NVDA but whose tags omit nvda will not be
/// found, and that is correct behaviour, not a bug to patch in the matcher."
struct SunnyCard: Identifiable {
    let id = UUID()
    let tags: [SunnyTag]
    let name: String
    let size: S.Size

    func matches(query: String, filters: Set<SunnyTag>) -> Bool {
        // Filter set matching is OR. Search AND filter combine with AND.
        let passesFilter = filters.isEmpty || !filters.isDisjoint(with: Set(tags))
        guard passesFilter else { return false }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        if name.lowercased().contains(q) { return true }
        return tags.contains { $0.key.contains(q) }
    }
}

/// A ticker-strip quote. CHROME.md §2: direction colour is a property of the
/// INSTRUMENT, not of the display format, so it does not change on tap.
struct SunnyQuote: Identifiable {
    let id = UUID()
    let symbol: String
    let percent: String
    let last: String
    let up: Bool
}

enum SunnyMarketState { case open, closed, holiday
    var dot: Color { switch self { case .open: return S.openDot
                                   case .closed: return S.hair
                                   case .holiday: return S.warn } }
    /// Sentence case, never uppercase.
    var label: String { switch self { case .open: return "Open"
                                      case .closed: return "Closed"
                                      case .holiday: return "Holiday" } }
}
