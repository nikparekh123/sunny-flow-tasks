//
//  SunnyLegs.swift
//  Sunny — the position legs' data. cards/position-leg.md is normative.
//
//  ⚠ THE DRILL-IN REGION IS RETIRED (25 Aug 2026) and this file is now the model
//  and the store only. What went, and why it is not rebuilt from the old sheet:
//  the region animated its own height, chose between three grids by leg count,
//  and claimed opacity/transform/transition on [data-card] while the feed reveal
//  was writing the same three. It read as jerky, and the fix was not easing
//  curves — it was removing the states. Five L cards, one per leg, have none.
//
//  ⚠ AND THE HISTORY RULE CHANGED WITH IT. A bar is the week's CHANGE IN P&L,
//  not cash that moved: a sold put held to expiry moves cash once, so three of
//  four weeks would be empty. P&L change exists every week for every leg type.
//

import SwiftUI

struct LegsPosition: Decodable, Identifiable {
    let ticker: String
    let spot: Double
    let shares: Shares
    let legs: [Leg]
    let floors: [PutFloor]
    /// ⚠ THE POSITION'S OWN WEEKLY SERIES, and the card must read THIS rather
    /// than summing the per-leg arrays. Those are mark-to-mark on legs that are
    /// still open, so a leg that expired inside the window contributes nothing
    /// to the week it lived and died in — the week its money was made. NKE's
    /// week of 17 Aug summed to −$1,668 that way: shares +$32 and a long put's
    /// decay, with 20 calls and 20 puts sold that Friday invisible. Server-side
    /// it is +$1,952.
    ///
    /// Optional so a run against an older deployment decodes rather than throws.
    let weeks: [LegWeek?]?
    /// UNREALIZED, and the page heading calls it CURRENT: the five leg cards
    /// summed, so the heading and the cards under it can never disagree.
    let total: Int
    /// Everything already closed. docs/PNL_GLOSSARY.md's REALIZED, minus the
    /// dividend term, which has no receipts table to sum — see position-legs.
    ///
    /// ⚠ OPTIONAL BECAUSE THE BACKEND IS SHARED AND ADDITIVE ONLY. A build
    /// already on Nik's phone decodes this same response; these two keys landed
    /// on 26 Aug 2026 and a run against an older deploy must decode, not throw.
    let realized: Int?
    /// REALIZED + UNREALIZED — the glossary's NET, and the heading's TOTAL.
    let allTime: Int?
    var id: String { ticker }

    struct Shares: Decodable {
        let label: String
        let pnl: Int
        let pct: Double
        let basis: Int
        let contract: String
        let market: Int
        let weeks: [LegWeek?]
        /// Days since the oldest open lot. Shares have no expiry, so the third
        /// footer stat is HELD where an option reads LEFT — same job either way.
        let held: Int
    }
    struct Leg: Decodable, Identifiable {
        let code: String        // PS · CS · PB · CB
        let label: String
        let short: Bool
        let pnl: Int
        let pct: Double
        let committed: Int
        let value: Int
        let contracts: Double
        let contract: String
        let dte: Int
        let weeks: [LegWeek?]
        var id: String { code }
    }
}

/// ⚠ THE MODEL OUTLIVED ITS CARD. `SunnyPutFloorCard` was retired on 27 Aug
/// 2026, but `floors` is still served by position-legs and still decoded here,
/// because ONE BACKEND SERVES TWO CLIENTS and the build already on Nik's phone
/// reads it. Deleting the type would make this response fail to decode on a
/// device that has not updated. Additive only, in both directions.
struct PutFloor: Decodable, Identifiable {
    let strike: Double
    let expiry: String
    let contracts: Double
    let dte: Int
    let debit: Int
    let value: Int
    let pnl: Int
    let pct: Double
    let distance: Double
    var id: String { "\(strike)|\(expiry)" }
}

@Observable
final class LegsStore {
    var positions: [LegsPosition] = []
    var error: String?
    private var loading = false

    func load() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/position-legs") else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 60
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(Secrets.supabasePublishableKey)", forHTTPHeaderField: "Authorization")
        r.httpBody = Data("{}".utf8)
        do {
            let (d, resp) = try await URLSession.shared.data(for: r)
            if let h = resp as? HTTPURLResponse, h.statusCode >= 400 { error = "HTTP \(h.statusCode)"; return }
            positions = try JSONDecoder().decode(LegsPayload.self, from: d).positions ?? []
        } catch { self.error = String(describing: error) }
    }
}

private struct LegsPayload: Decodable { var positions: [LegsPosition]? }

// MARK: - formatting shared with the cards

/// U+2212, never a hyphen — it has to align in a tabular column.
func signed(_ v: Int) -> String {
    (v < 0 ? "\u{2212}" : "+") + "$" + abs(v).formatted(.number.grouping(.automatic))
}
func money(_ v: Int) -> String { abs(v).formatted(.number.grouping(.automatic)) }
