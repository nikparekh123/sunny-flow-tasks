//
//  TodayModels.swift
//  Sunnyfi
//
//  Data shapes for the Today landing tab. See design_handoff_today_homepage.
//
//  Two layers:
//   1. Decodable rows pulled from Supabase (MacroEventRow,
//      EarningsEventRow) — extend the existing PortfolioStore.
//   2. UI-level TodayItem / DetailRow that the ranking pipeline
//      hands to TodayScreen.
//

import Foundation

// ─── Decodable Supabase rows ──────────────────────────────────

/// Row from public.macro_events (FOMC, CPI, holidays, etc.).
struct MacroEventRow: Decodable, Sendable {
    let id: String
    let event_date: String        // YYYY-MM-DD
    let event_time: String?       // HH:MM:SS (nil for all-day)
    let country: String
    let name: String
    let category: String?
    let importance: Int           // 1-3 stars
    let forecast: String?
    let previous: String?
    let actual: String?
    let is_holiday: Bool
    let early_close: Bool
    let summary: String?
}

/// Row from public.earnings_events.
struct EarningsEventRow: Decodable, Sendable {
    let id: String
    let ticker: String
    let company_name: String?
    let report_date: String       // YYYY-MM-DD
    let report_time: String?      // 'bmo' | 'amc' | 'tba'
    let eps_forecast: Double?
    let revenue_forecast: Double?
    let market_cap: Double?
    let scope_tag: String         // 'position' | 'peer' | 'top50' | 'other'
    let peer_of_tickers: [String]?
    let sector_etf: String?
}

// ─── UI layer ─────────────────────────────────────────────────

/// The five buckets the Today list draws from. Top-1-per-bucket
/// ensures a diverse ranking (we don't want 5 portfolio rows).
enum TodayBucket: String, CaseIterable, Codable, Sendable {
    case markets, portfolio, events, earnings, options
}

enum TodayTone: String, Sendable {
    case pos, neg, neon, warn, neutral
}

/// One row on the Today list (also one pinned card if pinned).
/// `id` is the stable pin key — e.g. "portfolio:META" or
/// "earnings:META:2026-07-25".
struct TodayItem: Identifiable, Hashable, Sendable {
    let id: String
    let bucket: TodayBucket
    let category: String       // shown on the row + sheet eyebrow: "Markets", "Portfolio", …
    let short: String          // small badge: ticker or short label
    let name: String           // primary row title: "Russell 2000", "META", "FOMC"
    let sub: String            // small grey line beneath the name
    let num: String            // hero magnitude: "+5.1%", "6d", "4"
    let unit: String           // small mono label under the num: "1-DAY", "UNTIL"
    let tone: TodayTone        // colors `num`
    let line: String           // single sentence for the bottom sheet
    let detailTitle: String    // sheet hero title (often == category)
    let detailSub: String      // sheet hero subtitle
    let detailRows: [DetailRow]

    /// Narrative for a pinned card: [leadIn, coloredPhrase, tail].
    /// The middle slice renders in `tone`.
    let pinNarrative: PinNarrative?
}

struct PinNarrative: Hashable, Sendable {
    let lead: String
    let value: String
    let tail: String
}

struct DetailRow: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String
    let sub: String
    let value: String
    let tone: TodayTone
    /// Stable pin key for this row, if it represents a pinnable entity
    /// (e.g. a single macro event or earnings report). nil for rows
    /// that are just informational (option counts, etc.).
    let pinId: String?

    init(name: String, sub: String, value: String, tone: TodayTone, pinId: String? = nil) {
        self.name = name
        self.sub = sub
        self.value = value
        self.tone = tone
        self.pinId = pinId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name); hasher.combine(value)
    }
    static func == (lhs: DetailRow, rhs: DetailRow) -> Bool {
        lhs.name == rhs.name && lhs.value == rhs.value
    }
}

// ─── Pin persistence (UserDefaults) ───────────────────────────

/// Personal pin set. UserDefaults so each device has its own —
/// even on the shared SWM team account a user picks what they care
/// about. Stored as JSON array of pin keys ("portfolio:META", etc.).
@MainActor
@Observable
final class TodayPinStore {
    static let shared = TodayPinStore()
    private let key = "today.pinnedIds.v1"

    private(set) var pinnedIds: [String] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            pinnedIds = arr
        }
    }

    func isPinned(_ id: String) -> Bool { pinnedIds.contains(id) }

    func toggle(_ id: String) {
        if let idx = pinnedIds.firstIndex(of: id) {
            pinnedIds.remove(at: idx)
        } else {
            pinnedIds.append(id)
        }
        persist()
    }

    func unpin(_ id: String) {
        pinnedIds.removeAll { $0 == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pinnedIds) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
