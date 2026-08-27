//
//  SunnyRail.swift
//  Sunny — the always-on dock. CHROME.md §2, handoff/cards/text-rail.md.
//
//  ⚠ CHROME, NOT A CARD, AND NOT THE FEED. It carries no ground per fact, no
//  radius, no shadow, no slot. Card mode was built and rejected: cards in the
//  dock repeat the feed's radius, shadow and paper two pixels under the feed
//  itself, so the eye cannot separate chrome from content.
//
//  ⚠ IT LIVES INSIDE THE PANE WRAPPER, WHICH MUST CLOSE BEFORE THE HOME ROW.
//  It is an absolute overlay, so it costs the pane no layout height — that is
//  what lets it slide away without leaving a 48pt gap. Put it in the frame as a
//  flex row and it takes space it should not; let the wrapper stay open and its
//  bottom edge resolves to the frame bottom and paints over the indicator.
//
//  ⚠ AND EVERY INK IS JUDGED AGAINST THE COMPOSITE. The ground is translucent:
//  rgba(20,23,15,.92) over --ground resolves to rgb(38,41,34), costing a
//  solid-ink palette ~40% of its contrast. Paper inks die outright here —
//  --gain #00722F measures 1.9:1. Nothing dimmer than --rail-minor, ever.
//
//  ⚠ ONE SIZE. 13px for every word and every figure. The cost was accepted
//  knowingly: size is no longer available as a signal, only colour is, so
//  nothing in the dock can outrank anything else.
//

import SwiftUI

// MARK: - store

@Observable
final class RailStore {
    var facts: [RailFact] = []
    /// Chrome for the pane, not for the dock: the shell's section headings.
    var book: [BookName] = []
    var openShorts: OpenShorts?
    var error: String?
    private var loading = false

    func load() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/sunny-rail") else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 30
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(Secrets.supabasePublishableKey)", forHTTPHeaderField: "Authorization")
        r.httpBody = Data("{}".utf8)
        do {
            let (d, resp) = try await URLSession.shared.data(for: r)
            if let h = resp as? HTTPURLResponse, h.statusCode >= 400 { error = "HTTP \(h.statusCode)"; return }
            let p = try JSONDecoder().decode(RailPayload.self, from: d)
            openShorts = p.open_shorts
            facts = p.facts ?? []
            book = p.book ?? []
        } catch { self.error = String(describing: error) }
    }
}

private struct RailPayload: Decodable {
    var facts: [RailFact]?
    var book: [BookName]?
    var open_shorts: OpenShorts?
}

/// The open short book, for the New page's three figures.
///
/// ⚠ NONE OF THESE IS A DIRECTION, so none takes gain or loss ink. The deck
/// reserves colour for direction and a balance is not one.
struct OpenShorts: Decodable {
    let contracts: Int
    /// What he was paid to write the options still open.
    let credit: Int
    /// ⚠ TOTAL VALUE LEFT is the whole mark, intrinsic included: everything
    /// still standing in the open shorts. Nik picked this on 26 Aug over "credit
    /// less cost to close", which is what has been CAPTURED rather than what is
    /// left.
    let value: Int
    let intrinsic: Int
    /// ⚠ THE EXTRINSIC PART, and the only one of the three he earns by waiting.
    /// Intrinsic is settled by where the stock is, not by the clock. On this
    /// book intrinsic is nearly four fifths of the cost to close, so these two
    /// figures sit far apart and the gap is the interesting part.
    let time_value: Int
}

/// One name in the book, largest first. SHELL.md §7: a section heading is the
/// ticker, the full company name, and the weight — and none of that is
/// derivable from the cards, which know a ticker and nothing else.
///
/// Weight is a COST basis, matching the `Income invested` fact on the dock, so
/// a heading can never disagree with the number a few rows below it.
struct BookName: Decodable, Identifiable {
    let ticker: String
    let name: String
    let weight: Int
    /// The five-day price week. Optional because a name with fewer than two
    /// closes has no week to draw, and a card that invents one is worse than a
    /// card that is absent.
    let week: FiveDay?
    /// The average price cards' data. Optional so a run against an older
    /// deployment of sunny-rail decodes rather than throws.
    let avg: BookAverage?
    /// The net delta cards' data. Null when a leg has no delta yet — see the
    /// note on BookDelta.
    let delta: BookDelta?
    var id: String { ticker }
}

/// ⚠ THE AVERAGE IS BUY PRICE MINUS PREMIUM WRITTEN, not minus realized. Nik
/// chose this on 26 Aug over the glossary's NEW AVERAGE. The two disagree hard:
/// NKE reads 37.79 UNDER spot one way and 44.41 OVER it the other, and five of
/// nine cards change ground colour between them. Computed in sunny-rail, never
/// on the client — two cards read it and they must never disagree.
struct BookAverage: Decodable {
    let shares: Int
    let lots: Int
    let cost: Int
    let paid: Double
    let average: Double
    let spot: Double
    /// Premium against what he paid. Negative means the premium brought it down.
    let vsPaid: Double
    /// The resulting basis against the market. Negative is GOOD, which is why
    /// the cards spell `under` and `over` rather than showing a sign.
    let vsSpot: Double

    enum CodingKeys: String, CodingKey {
        case shares, lots, cost, paid, average, spot
        case vsPaid = "vs_paid"
        case vsSpot = "vs_spot"
    }
}

/// The position's directional exposure in SHARES: what he is actually long or
/// short once the options are counted.
///
/// ⚠ NULL WHEN ANY OPEN LEG HAS NO DELTA, and the name then shows no tile and no
/// card. A missing greek is not a zero: ten short puts filled minutes ago are
/// worth a few hundred shares of exposure, and counting them as nothing prints a
/// confident wrong number. Same rule the rest of the deck follows — no price, no
/// week. The greeks cron fills it within the quarter hour and the name returns
/// on its own.
struct BookDelta: Decodable {
    /// shares + Σ (long ? +1 : −1) × contracts × 100 × delta. Polygon's delta is
    /// already signed by option type, so a short call reduces exposure and a
    /// short put adds it without any special case.
    let net: Int
    let short: Bool
    /// The NOTIONAL. The card names it `exposure` because a signed dollar figure
    /// in this deck otherwise reads as P&L.
    let exposure: Int
}

struct RailFact: Decodable, Identifiable {
    let key: String
    let spans: [Span]
    var id: String { key }
    struct Span: Decodable { let text: String; let kind: String }
}

// MARK: - the dock is retired

/* ⚠ THE ALWAYS-ON RAIL IS GONE (26 Aug 2026) and the view that drew it is
   deleted, not commented out. SHELL-PAGED.md §9: two navigations for one app,
   and the strip already names every destination.

   ⚠ THIS REVERSES AN EARLIER INSTRUCTION. Nik's line on the previous shell was
   "the text rail at the bottom will stay as is", and it did stay until the shell
   under it was replaced. If the facts are wanted back they need a home in the
   paged shell, not the old dock — a 48pt overlay belongs to a feed you scroll,
   and there is no longer one feed to scroll.

   THE FILE STAYS because `book` lives here: the strip's names, weights and
   five-day series all come from sunny-rail, which is why the store is still
   fetched on every launch. `facts` is still decoded and now goes unused; it is
   left in the payload rather than dropped from the response, because ONE
   BACKEND SERVES TWO CLIENTS and a removed field throws keyNotFound in the
   build already on Nik's phone. Additive only, in both directions. */
