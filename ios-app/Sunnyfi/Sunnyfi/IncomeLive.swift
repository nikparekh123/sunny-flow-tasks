//
//  IncomeLive.swift
//  Sunnyfi — Ink · the income sleeve's live card
//
//  What a position you ALREADY HOLD is doing, and what it needs this week.
//  Backed by the `position-live` function, which covers income_sleeve_names ONLY.
//
//  ── The contract ────────────────────────────────────────────────────────────
//  EVERY DISPLAYED STRING IS EMITTED BY THE ENGINE, tags included. This file
//  formats nothing and judges nothing. If a line reads badly or a tag is wrong,
//  the fix is in position-live, not here.
//
//  ── TWO LAYOUTS FAILED BEFORE THIS ONE. Do not reintroduce either ──────────
//  Bearish / Supportive HEADINGS failed because two labelled buckets are a
//  quota: the card had to fill both every day whether or not anything had
//  happened, so it reached for what is permanently true, a 120-day aggregate,
//  which counted one event many times. NKE's "27 analyst actions" were 14 firms
//  answering a single earnings report. Nik: "reading this every day, it feels
//  like I'm repeating the same thing."
//
//  A DATED FEED failed the opposite way. With the substance moved out, the wire
//  filled the space it left. Nik: "everything is news, where is the analyst
//  upgrade or consensus, technical indicator", and no today/yesterday stamps.
//
//  What works: DOMAIN sections with direction as a per-bullet TAG. A tag rides
//  on a bullet that already earned its place, so unlike a heading it can never
//  manufacture content. Freshness lives in the NEW tag and the header counter.
//

import SwiftUI

// MARK: - payload

struct LiveBook: Decodable {
    var ok: Bool?
    var asof: String?
    var positions: [Position]?
    var error: String?

    /// One bullet. `tags` is any of NEW, IMPORTANT, BULLISH, BEARISH, and is
    /// frequently empty: a bullet whose direction depends on your strategy
    /// rather than on the data goes untagged on purpose.
    struct Line: Decodable {
        var text: String
        var tags: [String]
    }

    struct Headline: Decodable {
        var title: String
        var publisher: String
        var url: String
        var when: String
    }

    struct Position: Decodable, Identifiable {
        var ticker: String
        var id: String { ticker }
        var spot: Double
        var analysts: [Line]
        var price: [Line]
        var company: [Line]
        var headlines: [Headline]
        /// How many bullets carry NEW. Says whether to read closely or skip,
        /// which is the whole freshness story without a timeline.
        var new_count: Int
        var since: String?
        var stand: [String]
        var coverage: [String]
        var floor_lines: [String]
        var `do`: [String]
    }
}

@Observable
final class LiveStore {
    var book: LiveBook?
    var error: String?
    private var loading = false

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/position-live") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        // 60s. It prices the live chain for every held name, so it is slower
        // than the sleeve by design.
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(Secrets.supabasePublishableKey)", forHTTPHeaderField: "Authorization")
        // No `peek`. A real open CONSUMES the freshness window, which is what
        // makes tomorrow's NEW tags mean something.
        req.httpBody = Data("{}".utf8)
        do {
            let (d, resp) = try await URLSession.shared.data(for: req)
            if let h = resp as? HTTPURLResponse, h.statusCode >= 400 { error = "HTTP \(h.statusCode)"; return }
            let parsed = try JSONDecoder().decode(LiveBook.self, from: d)
            if let e = parsed.error { error = e; return }
            book = parsed
        } catch { self.error = String(describing: error) }
    }
}

// MARK: - the card

struct LiveCard: View {
    let p: LiveBook.Position

    /* Ink: colour is data. Direction takes the loss and gain tones so the two
       coloured words are the only thing the eye catches. NEW and IMPORTANT are
       status rather than direction, so they stay in ink and lean on weight. */
    private func tone(_ tag: String) -> Color {
        switch tag {
        case "BEARISH":   return Ink.loss
        case "BULLISH":   return Ink.gain
        case "NEW":       return Ink.text.opacity(0.8)
        default:          return Ink.dim.opacity(0.75)
        }
    }

    /// Text and its tags as one attributed run, so the tags sit at the end of
    /// the sentence and wrap with it instead of being pinned to a column.
    private func bullet(_ l: LiveBook.Line) -> AttributedString {
        var s = AttributedString(l.text)
        s.font = InkFont.display(14)
        s.foregroundColor = Ink.text.opacity(0.92)
        for t in l.tags {
            var tag = AttributedString("  \(t)")
            tag.font = InkFont.mono(10.5)
            tag.foregroundColor = tone(t)
            s += tag
        }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(p.ticker).font(InkFont.mono(13)).tracking(13 * 0.16)
                    .foregroundStyle(Ink.dim)
                Text(String(format: "%.2f", p.spot)).font(InkFont.mono(13))
                    .tracking(13 * -0.02).foregroundStyle(Ink.text)
                Spacer(minLength: 0)
                Text(p.new_count > 0 ? "\(p.new_count) NEW" : "NOTHING NEW")
                    .font(InkFont.mono(11)).tracking(11 * 0.14)
                    .foregroundStyle(p.new_count > 0 ? Ink.text.opacity(0.8) : Ink.dim.opacity(0.55))
            }
            .padding(EdgeInsets(top: 22, leading: 22, bottom: 16, trailing: 22))

            section("Analysts", p.analysts)
            section("Price", p.price)
            section("Company", p.company)

            if !p.headlines.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("HEADLINES").font(InkFont.mono(11.5)).tracking(11.5 * 0.16)
                        .foregroundStyle(Ink.dim.opacity(0.55))
                    ForEach(Array(p.headlines.enumerated()), id: \.offset) { _, h in
                        headlineRow(h)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 4, leading: 22, bottom: 16, trailing: 22))
            }

            Rectangle().fill(Ink.hair).frame(height: 1).padding(.vertical, 4)

            plain("Where you stand", p.stand)
            plain("What is covered", p.coverage)
            plain("The floor", p.floor_lines)

            /* DO is inverted, because it is the only part that asks for an
               action. Everything above it is a reading. */
            if !p.`do`.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("DO").font(InkFont.mono(12)).tracking(12 * 0.2)
                        .foregroundStyle(Ink.invertDim)
                    ForEach(Array(p.`do`.enumerated()), id: \.offset) { _, line in
                        Text(line).font(InkFont.display(14.5))
                            .foregroundStyle(Ink.invertText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 18, leading: 22, bottom: 22, trailing: 22))
                .background(Ink.invertBg)
            }
        }
        .background(Ink.surface)
        .clipShape(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous)
            .stroke(Ink.hair, lineWidth: 1))
    }

    @ViewBuilder
    private func headlineRow(_ h: LiveBook.Headline) -> some View {
        let row = VStack(alignment: .leading, spacing: 3) {
            Text(h.title).font(InkFont.display(14))
                .foregroundStyle(Ink.text.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Text("\(h.publisher) · \(h.when)").font(InkFont.mono(10.5))
                .foregroundStyle(Ink.dim.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A dead link is worse than none, so only wrap when there is a URL.
        if let u = URL(string: h.url), !h.url.isEmpty {
            Link(destination: u) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }

    @ViewBuilder
    private func section(_ label: String, _ lines: [LiveBook.Line]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text(label.uppercased()).font(InkFont.mono(11.5)).tracking(11.5 * 0.16)
                    .foregroundStyle(Ink.dim.opacity(0.55))
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(Ink.dim.opacity(0.5)).frame(width: 3.5, height: 3.5)
                            .padding(.top, 7)
                        Text(bullet(l)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 4, leading: 22, bottom: 16, trailing: 22))
        }
    }

    @ViewBuilder
    private func plain(_ label: String, _ lines: [String]) -> some View {
        if !lines.isEmpty {
            section(label, lines.map { LiveBook.Line(text: $0, tags: []) })
        }
    }
}
