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

    /// Plain tickers first, then the per-card tags, each alphabetical. Without
    /// an order the rail reshuffles whenever the position set changes.
    static func < (a: SunnyTag, b: SunnyTag) -> Bool {
        a.isAwareness == b.isAwareness ? a.key < b.key : (!a.isAwareness && b.isAwareness)
    }
}

enum SunnyZone: String, CaseIterable, Identifiable {
    case now, new, next
    var id: String { rawValue }
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    /// CHROME.md §6 — each zone carries its own padding and they are not equal.
    var padding: EdgeInsets {
        switch self {
        case .now:  return EdgeInsets(top: 4,  leading: 16, bottom: 0,  trailing: 16)
        case .new:  return EdgeInsets(top: 12, leading: 16, bottom: 0,  trailing: 16)
        case .next: return EdgeInsets(top: 12, leading: 16, bottom: 40, trailing: 16)
        }
    }
}

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

/// The feed's non-digest cards.
///
/// ⚠ EMPTY ON PURPOSE. CARDS.md ships 18 placeholder shells across the three
/// zones — correct shells with empty interiors, meant to be filled one at a
/// time. Once the digest cards carried real content the shells stopped reading
/// as "not built yet" and started reading as broken cards, and they polluted
/// the filter row: they carry tlt / nvda / earnings / iv tags, so the row
/// offered filters that could only ever return blanks. Removed on Nik's call.
///
/// The deck order is kept in the comment below so it can be restored exactly
/// when real cards arrive. Do not renumber it.
///
///   Now   M(tlt) · S(nvda) · S(nke) · XS(tlt) · XS(iv)
///   New   S(nvda) · S(tlt) · M(nke) · XS(tlt) · XS(iv) · S(earnings) · S(nvda)
///   Next  L(tlt) · S(nke) · S(nvda) · M(earnings) · XS(iv) · XS(tlt)
enum SunnyDeck {
    static func cards(_ z: SunnyZone) -> [SunnyCard] { [] }
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
