//
//  SunnyDigestStore.swift
//  Sunny — the digest card's data. position-live, income_sleeve_names only.
//
//  ── Called the AWARENESS CARD ───────────────────────────────────────────────
//  Nik's name for it, short for situational awareness. Use it in conversation
//  and in comments; it is deliberately NOT on screen. The card carries no title
//  in the feed and should not gain one. The type names here predate the name
//  and are not worth churning.
//
//  The seven sections the card wants are exactly what the engine already emits,
//  so there is no shape to invent here: Analysts, Price, Company, Where you
//  stand, What is covered, The floor, Do.
//
//  No sign-in. This calls the edge function with the publishable key, exactly as
//  LiveStore does, so building or checking the card never needs Nik's passcode.
//

import SwiftUI

@Observable
final class DigestStore {
    /// One per held position. position-live already covers exactly the sleeve
    /// names that hold shares, so asking for all of them is a single call.
    var cards: [SunnyDigestCardModel] = []
    var error: String?
    private var loading = false

    func load() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/position-live") else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 60
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(Secrets.supabasePublishableKey)", forHTTPHeaderField: "Authorization")
        // peek: reading the card to build it must not consume the freshness
        // window that decides tomorrow's `new` tags.
        r.httpBody = Data("{\"peek\":true}".utf8)
        do {
            let (d, resp) = try await URLSession.shared.data(for: r)
            if let h = resp as? HTTPURLResponse, h.statusCode >= 400 { error = "HTTP \(h.statusCode)"; return }
            let p = try JSONDecoder().decode(LivePayload.self, from: d)
            cards = (p.positions ?? []).map { SunnyDigestCardModel($0, asof: p.asof ?? "") }
        } catch { self.error = String(describing: error) }
    }
}

// MARK: - wire format

private struct LivePayload: Decodable {
    var asof: String?
    var positions: [Pos]?
    struct Ev: Decodable { var text: String; var tags: [String] }
    struct Pos: Decodable {
        var ticker: String
        var spot: Double
        var analysts: [Ev]
        var price: [Ev]
        var company: [Ev]
        var new_count: Int
        var stand: [String]
        var coverage: [String]
        var floor_lines: [String]
        var `do`: [String]
        var do_lines: [DoLine]?
    }
    struct DoLine: Decodable { var text: String; var kind: String }
}

// MARK: - the card's model

struct SunnyDigestCardModel {
    /// Filter surface. CARDS.md: matching is on tags and name ONLY, never on
    /// the text inside the card.
    let tags: [SunnyTag]
    let name: String
    let timestamp: String
    let ticker: String
    let spot: String
    let newCount: Int
    let sections: [DigestSection]
    let doBlock: DigestDo?

    fileprivate init(_ p: LivePayload.Pos, asof: String) {
        // Kalam 12.5/300, and the only place a date appears on the card.
        // Nik's rule: the ticker, and the card kind. Filtering NKE finds it;
        // so does filtering NKE Awareness, which will matter once other kinds
        // of card sit on the same name.
        tags = [.ticker(p.ticker), .awareness(p.ticker)]
        name = "\(p.ticker) awareness"
        timestamp = SunnyDigestCardModel.stamp(asof)
        ticker = p.ticker
        spot = String(format: "%.2f", p.spot)
        newCount = p.new_count

        func sec(_ h: String, _ evs: [LivePayload.Ev]) -> DigestSection? {
            let ls = evs.map { DigestLine(text: $0.text, tags: DigestTag.from($0.tags)) }
            return ls.isEmpty ? nil : DigestSection(heading: h, lines: ls)
        }
        func plain(_ h: String, _ xs: [String]) -> DigestSection? {
            xs.isEmpty ? nil : DigestSection(heading: h, lines: xs.map { DigestLine(text: $0, tags: []) })
        }
        /* ⚠ THE POSITION SECTIONS ARE DELIBERATELY NOT RENDERED. Nik: "remove
           where you stand, what is covered, the floor from the awareness card,
           I want it to be more price company and analyst vs the position. We
           can add that later in a different format."

           So the card is the market read on the name, and the DO block below it
           is the only place his own position appears.

           ⚠ AND THE ENGINE STILL SENDS THEM. `stand`, `coverage` and
           `floor_lines` remain in the position-live response and remain
           non-optional here, because the build already on his phone decodes all
           three and would throw keyNotFound the moment they disappeared. This is
           a rendering decision, not a payload change. Dropping them server-side
           is the mistake that broke the live app once already. */
        sections = [
            sec("Analysts", p.analysts),
            sec("Price", p.price),
            sec("Company", p.company),
        ].compactMap { $0 }

        // Exactly one DO block, always last, and every action keeps its own
        // line. Joining the tail into a single "reason" string was what made
        // three instructions read as one sentence.
        /* ⚠ NO DO BLOCK. With Where you stand, What is covered and The floor
           gone, the card is a read on the NAME rather than on the position, and
           an instruction to sell 20 calls was the last thing dragging his own
           book back onto it. DIGEST-CARD §9 agrees by construction: the
           market-read variant has three sections and never carries a DO.

           The engine still returns `do` and `do_lines`, and DigestDo still
           exists, because both are needed the moment the position side comes
           back "in a different format". This is a rendering decision. */
        doBlock = nil
    }

    private static func stamp(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(iso.prefix(10))) else { return iso }
        let o = DateFormatter(); o.dateFormat = "d MMM"
        return "as of " + o.string(from: d)
    }
}

extension SunnyDigestCard {
    init(_ m: SunnyDigestCardModel) {
        self.init(timestamp: m.timestamp, ticker: m.ticker, spot: m.spot,
                  newCount: m.newCount, sections: m.sections, doBlock: m.doBlock)
    }
}
