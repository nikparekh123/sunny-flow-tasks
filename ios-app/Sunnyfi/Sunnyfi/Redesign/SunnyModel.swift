//
//  SunnyModel.swift
//  Sunny — the card slot contract and the filter machine. CARDS.md is normative.
//

import SwiftUI

/// CARDS.md: the tag vocabulary is a CLOSED SET. Adding one means adding a
/// filter label too, so the two cannot drift apart.
enum SunnyTag: String, CaseIterable, Identifiable {
    case tlt, nke, nvda, baba, nflx, earnings, iv
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tlt: return "TLT"; case .nke: return "NKE"; case .nvda: return "NVDA"
        case .baba: return "BABA"; case .nflx: return "NFLX"
        case .earnings: return "Earnings"; case .iv: return "IV"
        }
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
        return tags.contains { $0.rawValue.contains(q) }
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
