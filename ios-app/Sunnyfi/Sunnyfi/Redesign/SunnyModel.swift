//
//  SunnyModel.swift
//  Sunny — the card slot contract and the filter machine. CARDS.md is normative.
//

import SwiftUI

/// CARDS.md: the tag vocabulary is a CLOSED SET. Adding one means adding a
/// filter label too, so the two cannot drift apart.
enum SunnyTag: String, CaseIterable, Identifiable {
    case tlt, nke, nvda, earnings, iv
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tlt: return "TLT"; case .nke: return "NKE"; case .nvda: return "NVDA"
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

/// CARDS.md "Current deck — do not renumber". Order and sizes are normative.
/// XS cards pair up; an odd XS at the end of a zone is a defect.
enum SunnyDeck {
    static let now: [SunnyCard] = [
        .init(tags: [.tlt],  name: "TLT iShares 20+ Year Treasury bond", size: .m),
        .init(tags: [.nvda], name: "NVDA Nvidia", size: .s),
        .init(tags: [.nke],  name: "NKE Nike", size: .s),
        .init(tags: [.tlt],  name: "TLT iShares 20+ Year Treasury bond", size: .xs),
        .init(tags: [.iv],   name: "IV implied volatility", size: .xs),
    ]
    static let new: [SunnyCard] = [
        .init(tags: [.nvda], name: "NVDA Nvidia", size: .s),
        .init(tags: [.tlt],  name: "TLT iShares 20+ Year Treasury bond", size: .s),
        .init(tags: [.nke],  name: "NKE Nike", size: .m),
        .init(tags: [.tlt],  name: "TLT iShares 20+ Year Treasury bond", size: .xs),
        .init(tags: [.iv],   name: "IV implied volatility", size: .xs),
        .init(tags: [.earnings], name: "Earnings calendar", size: .s),
        .init(tags: [.nvda], name: "NVDA Nvidia", size: .s),
    ]
    static let next: [SunnyCard] = [
        .init(tags: [.tlt],  name: "TLT iShares 20+ Year Treasury bond", size: .l),
        .init(tags: [.nke],  name: "NKE Nike", size: .s),
        .init(tags: [.nvda], name: "NVDA Nvidia", size: .s),
        .init(tags: [.earnings], name: "Earnings calendar", size: .m),
        .init(tags: [.iv],   name: "IV implied volatility", size: .xs),
        .init(tags: [.tlt],  name: "TLT iShares 20+ Year Treasury bond", size: .xs),
    ]
    static func cards(_ z: SunnyZone) -> [SunnyCard] {
        switch z { case .now: return now; case .new: return new; case .next: return next }
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
