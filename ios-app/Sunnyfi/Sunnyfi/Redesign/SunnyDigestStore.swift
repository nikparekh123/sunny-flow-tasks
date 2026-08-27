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
        /* `peek` is now redundant — position-live v22 never writes the seen
           table on a fetch — but it is still sent, because it costs nothing and
           an older deployment of the function would consume the window without
           it. Belt and braces on the one thing that is invisible when it goes
           wrong: a burned window looks exactly like a quiet day. */
        r.httpBody = Data("{\"peek\":true}".utf8)
        do {
            let (d, resp) = try await URLSession.shared.data(for: r)
            if let h = resp as? HTTPURLResponse, h.statusCode >= 400 { error = "HTTP \(h.statusCode)"; return }
            let p = try JSONDecoder().decode(LivePayload.self, from: d)
            cards = (p.positions ?? []).map { SunnyDigestCardModel($0, asof: p.asof ?? "") }
        } catch { self.error = String(describing: error) }
    }

    /* ── the Read control is what advances the freshness window ─────────────
       ⚠ MARKING IS A READ, NOT A FETCH. Until 26 Aug position-live advanced the
       window whenever anyone asked it for cards, so a probe, a refresh or a
       background task could empty a day on Nik's behalf — and a diagnostic
       `curl -d '{}'` did exactly that while this was being built. The server
       and the screen now mean the same thing by "read": this fires from the
       same `markRead` the Read pill calls, and nothing else moves it.

       Fire-and-forget on purpose. The card has already moved to its name's page
       locally; a failed mark means it comes back tomorrow, which is a far better
       failure than a card that vanishes because a write succeeded and the UI
       did not. */
    func markSeen(_ ticker: String) async {
        guard !SunnyProbe.on else { return }
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/position-live") else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 20
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(Secrets.supabasePublishableKey)", forHTTPHeaderField: "Authorization")
        r.httpBody = Data("{\"seen\":[\"\(ticker.uppercased())\"]}".utf8)
        _ = try? await URLSession.shared.data(for: r)
    }
}

/// ⚠ A VERIFICATION RUN MUST NOT SPEND HIS FEED. Every launch argument here is
/// one only I ever pass, and any of them means this launch is a screenshot or a
/// measurement rather than Nik reading his cards. Local filing still runs, so
/// the card still moves to its name's page and that half is fully exercised —
/// but the server window is left alone. The guard sits on the WRITE, not on the
/// feature.
///
/// ⚠ `-tapRead` IS DELIBERATELY NOT IN THIS SET. Its entire purpose is to fire
/// the real Read handler end to end, and a probe that skips the write would
/// verify everything except the thing most likely to be broken — the exact
/// shape of test this file has been burned by before. So it DOES spend one
/// name's window, and that is the price of it being a real test. Use it on
/// purpose, not by habit.
enum SunnyProbe {
    static let on: Bool = {
        let a = Set(ProcessInfo.processInfo.arguments)
        return !a.isDisjoint(with: ["-forceFeatured", "-showPrice",
                                    "-page", "-scrollTo", "-measure"])
    }()
}

// MARK: - wire format

private struct LivePayload: Decodable {
    var asof: String?
    var positions: [Pos]?
    struct Ev: Decodable {
        var text: String
        var tags: [String]
        /// The one bold run and the amber phrase, both chosen by the engine —
        /// see position-live. Optional so an older deployment still decodes.
        var bold: String?
        var hi: String?
    }
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
        /// The date of the newest EVENT on the card. Optional so a response
        /// from before it existed still decodes.
        var freshest: String?
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
    /// ⚠ THE ISO DATE OF THE NEWEST EVENT ON THE CARD, and the card's IDENTITY.
    /// The feed keys its read state on this, not on the new count: `digest|BABA|1`
    /// today and `digest|BABA|1` tomorrow are two different cards wearing one id,
    /// so reading the first filed the second before it was ever shown. This
    /// moves only when something actually arrives.
    let freshest: String
    let sections: [DigestSection]
    let doBlock: DigestDo?

    fileprivate init(_ p: LivePayload.Pos, asof: String) {
        // Kalam 12.5/300, and the only place a date appears on the card.
        // Nik's rule: the ticker, and the card kind. Filtering NKE finds it;
        // so does filtering NKE Awareness, which will matter once other kinds
        // of card sit on the same name.
        tags = [.ticker(p.ticker), .awareness(p.ticker)]
        name = "\(p.ticker) awareness"
        timestamp = SunnyDigestCardModel.stamp(p.freshest, asof: asof)
        ticker = p.ticker
        spot = String(format: "%.2f", p.spot)
        newCount = p.new_count
        freshest = p.freshest ?? ""

        func sec(_ h: String, _ evs: [LivePayload.Ev]) -> DigestSection? {
            let ls = evs.map { DigestLine(text: $0.text, tags: DigestTag.from($0.tags),
                                          bold: $0.bold, hi: $0.hi) }
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

    /* ⚠ THE AGE OF THE NEWEST FACT, NOT THE DATE OF THE REQUEST.
       This used to print `asof`, which is always today, so a card built
       entirely from 39-day-old analyst actions read "as of 25 Aug" and looked
       freshly updated. Nik: "we don't see stale news, miss the latest thinking
       nothing happened." The one line that should have warned him was the line
       telling him everything was fine.

       It pairs with the "N new" chip: when something IS new the chip says so
       and this reads "latest today"; when nothing is, this is the only thing on
       the card that can tell him how long it has been quiet. LEN currently
       reads 6 Aug, nineteen days.

       Falls back to the old behaviour when `freshest` is absent, so a stale
       deployment of the engine does not blank the line. */
    private static func stamp(_ freshest: String?, asof: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let iso = freshest, let d = f.date(from: String(iso.prefix(10))) else {
            guard let a = f.date(from: String(asof.prefix(10))) else { return asof }
            let o = DateFormatter(); o.dateFormat = "d MMM"
            return "as of " + o.string(from: a)
        }
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: d), to: Calendar.current.startOfDay(for: Date())).day ?? 0
        if days <= 0 { return "latest today" }
        if days == 1 { return "latest yesterday" }
        let o = DateFormatter(); o.dateFormat = "d MMM"
        return "latest \(o.string(from: d)), \(days) days ago"
    }
}

extension SunnyDigestCard {
    init(_ m: SunnyDigestCardModel, onRead: (() -> Void)? = nil) {
        self.init(timestamp: m.timestamp, ticker: m.ticker, spot: m.spot,
                  newCount: m.newCount, sections: m.sections, doBlock: m.doBlock,
                  onRead: onRead)
    }
}
