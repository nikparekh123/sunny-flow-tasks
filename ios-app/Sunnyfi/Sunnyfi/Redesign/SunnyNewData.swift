//
//  SunnyNewData.swift
//  Sunny — the New page's data. handoff/NEW-PAGE.md, served by `new-page`.
//
//  ⚠ EVERYTHING THAT WAS ON NEW IS GONE (29 Aug 2026). The awareness digests,
//  the planner, the week card and the three open-short figures are all off this
//  page. Nik: "everything else not on this new layout goes." What replaces them
//  is five cards and the chrome between them.
//
//  ⚠ THE PAGE RUNS ON TWO CLOCKS. News is daily — about 22 items a week — and
//  analyst actions are weekly, about ten. The lead says TODAY, the analyst seam
//  says THIS WEEK, and the header date is a DAY, never a week range.
//
//  ⚠ EVERY COUNT IS RETURNED INCLUDING 0, AND EVERY SECTION CARRIES ITS LAST
//  DATE. An empty section with no last-seen date is indistinguishable from a
//  broken feed, which is why none of these fields is optional-when-empty.
//

import SwiftUI

@Observable
final class NewPageStore {
    var page: NewPagePayload?
    var error: String?
    private var loading = false

    func load() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/new-page") else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 45
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(Secrets.supabasePublishableKey)", forHTTPHeaderField: "Authorization")
        r.httpBody = Data("{}".utf8)
        do {
            let (d, resp) = try await URLSession.shared.data(for: r)
            if let h = resp as? HTTPURLResponse, h.statusCode >= 400 { error = "HTTP \(h.statusCode)"; return }
            page = try JSONDecoder().decode(NewPagePayload.self, from: d)
        } catch { self.error = String(describing: error) }
    }
}

struct NewPagePayload: Decodable {
    let date: String
    let dates: [NewEarningsDate]
    let news: NewsBlock
    let analysts: AnalystBlock
    let targets: TargetBlock
    let room: RoomBlock?
    let drift: DriftBlock?
    let earnings: EarningsBlock
}

/// ⚠ ONE ROW PER NAME. `earnings_events` holds duplicates — NKE carries both
/// 24 Sep (confirmed, from a manual entry) and 29 Sep (Benzinga's estimate) —
/// and the server resolves them: confirmed beats estimated, then earliest.
struct NewEarningsDate: Decodable, Identifiable {
    let ticker: String
    let date: String
    let days: Int
    let label: String
    let estimated: Bool
    var id: String { ticker }
}

struct NewsBlock: Decodable {
    let lead: NewsLead?
    let links: [NewsLink]
    let filtered: Filtered
    let kept: Int
    let last: String?

    /// ⚠ A GATE THAT DOES NOT COUNT ITSELF LOOKS BROKEN, and one that does not
    /// say why is a second silent gate. Every held-back row carries a reason
    /// that is literally true of its own title.
    struct Filtered: Decodable {
        let count: Int
        let rows: [Row]
        struct Row: Decodable, Identifiable {
            let ticker: String, title: String, publisher: String, url: String
            let reason: String?
            var id: String { url + ticker }
        }
    }
}

struct NewsLead: Decodable {
    let ticker: String, title: String, url: String, publisher: String
    let hours: Int
    /// `press release` or `article`. A press release is 19% of the feed and
    /// close to 100% on topic, so the KIND is printed — the only kind marker on
    /// the page.
    let kind: String
    /// ⚠ THE CARD NEVER SPEAKS FOR THE STORY. This is the name's own state, it
    /// sits below a rule with the ticker labelling it, and it is never a
    /// consequence of the headline. `Shares −7.4%` under a headline joins two
    /// things nothing in the data joins.
    let state: NameState?
}

/// Computed live from `ticker_quotes_latest` and `daily_closes`, NOT from
/// `ticker_signals` — that table was last written 8 Jul 2026 and holds the
/// scanner universe: of nine held names it carries two, both stale.
struct NameState: Decodable {
    let spot: Double
    let rsi: Int?
    let vs200: Double?
}

struct NewsLink: Decodable, Identifiable {
    let ticker: String, title: String, url: String, publisher: String
    let hours: Int
    var id: String { url }
}

struct AnalystBlock: Decodable {
    let count: Int
    let cards: [AnalystAction]
    let rest: [AnalystAction]
    let last: String?
    let lastFirm: String?
    let lastTicker: String?
}

struct AnalystAction: Decodable, Identifiable {
    let ticker: String, date: String
    /// ⚠ THE STATE IS A WORD AND THE WORD TAKES NO DIRECTION INK EITHER. Red is
    /// loss in this deck and a downgrade is an opinion; an earlier build shipped
    /// `buy → hold` in --loss-text and it read as the position losing money.
    let state: String
    let prev: Double?
    let now: Double?
    let rating: String, previousRating: String, action: String
    let firm: String
    let analyst: String?
    /// The vendor's own 0–5 flag. It is the one thing on the row worth a colour,
    /// which is what freed the 5px dot for it.
    let importance: Int
    let insight: Insight?
    var id: String { ticker + date + firm }

    struct Insight: Decodable { let text: String; let firm: String }
}

/// ⚠ A MEDIAN OF ACTIONS ACTUALLY SET, never a consensus endpoint. The 90-day
/// window is short enough that it cannot straddle a split — the consensus feed
/// pools across NFLX's Nov 2025 10:1 and reports a $1.22 low against an $80
/// spot. A name nobody rates gets NO ROW: TLT is a fund, and the header's
/// `8 OF 9` is the whole disclosure.
struct TargetBlock: Decodable {
    let window: Int, covered: Int, of: Int
    let rows: [Row]
    struct Row: Decodable, Identifiable {
        let ticker: String
        let target: Double, spot: Double
        let upside: Double?
        let n: Int
        /// The live range and how many of those targets sit under the price.
        /// A median alone hides both the disagreement and the dissent.
        let lo: Double, hi: Double, below: Int
        var id: String { ticker }
    }
}

/// ⚠ ONE DOT PER FIRM, NOT PER PUBLICATION, which is what lets the four
/// snapshots animate as defection rather than as a reshuffle. A firm is in the
/// room if it set a target inside the year before that snapshot, and it brings
/// its most recent one. Each snapshot carries its OWN close: `4 bearish, under
/// 86` has to mean under the price that day.
struct RoomBlock: Decodable {
    let snaps: Int, covered: Int, of: Int
    let rows: [Row]
    struct Row: Decodable, Identifiable {
        let ticker: String
        let snaps: [Snap]
        var id: String { ticker }
    }
    struct Snap: Decodable {
        let label: String, date: String
        let spot: Double
        let bear: Int, neu: Int, bull: Int
        var total: Int { bear + neu + bull }
    }
}

/// ⚠ RAW COUNTS SHIP AND THE THRESHOLD LIVES HERE. A block under `minActions`
/// draws no point, and the card marks the hole with a dotted bridge and a
/// dashed hollow ring — which it can only do because it knows the block exists
/// and is thin. `pct` nil beside a real `n` is that fact.
///
/// Rows arrive sorted by turn descending, so a row's index among the
/// turned-bearish names IS its rank into the plum ramp.
struct DriftBlock: Decodable {
    let span: Int, minActions: Int, covered: Int, of: Int
    let rows: [Row]
    struct Row: Decodable, Identifiable {
        let ticker: String
        let v: [Int?], n: [Int]
        let turn: Int
        var id: String { ticker }
        /// The sheet's three classes. Anything not a turn either way is flat.
        var kind: DriftKind { turn >= 50 ? .toward : turn <= -25 ? .away : .flat }
        var last: Int? { v.compactMap { $0 }.last }
        var first: Int? { v.compactMap { $0 }.first }
    }
}

enum DriftKind { case toward, away, flat }

struct EarningsBlock: Decodable {
    let count: Int
    let rows: [Row]
    /// One shape, two kinds — a date and a bound are both things that are true
    /// until they change, which is why they are rows and not tiles.
    struct Row: Decodable, Identifiable {
        let kind: String
        let ticker: String
        let line: String?, days: Int?, estimated: Bool?
        let support: Support?
        let period: String?, method: String?, date: String?, notes: String?
        let lo: Double?, hi: Double?
        var id: String { kind + ticker + (date ?? line ?? "") }
        /// ⚠ DIRECTION-AWARE. Earnings inside a SHORT put's life is exposure;
        /// inside a BOUGHT put's life the cover is doing its job. Same date,
        /// different ink.
        struct Support: Decodable { let text: String; let red: Bool }
    }
}

/// ⚠ THE NEVER-EMPTY FLOOR, AND THEREFORE ALWAYS LAST. It is the one block with
/// something to say in every state, which is why a dead week still has a page.
/// Nothing else on the page may be padded to fill space.
/* ⚠ `DriftBlock` IS DELETED, AND SO IS THE PROPERTY. An optional Decodable
   still THROWS on a shape mismatch — `decodeIfPresent` only tolerates a
   missing key, not a changed one — so leaving a stale model behind for a field
   the server had reshaped took the whole page down to "the feed did not
   answer". An unmodelled key is ignored; a wrongly modelled one is fatal.
   The server still serves `drift` for older builds. */
