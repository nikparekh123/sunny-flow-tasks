//
//  IncomeLive.swift
//  Sunnyfi — Ink · the income sleeve's live card
//
//  What a position you ALREADY HOLD is doing, and what it needs this week.
//  Backed by the `position-live` function, which covers income_sleeve_names ONLY.
//
//  ── Why this is a second request and not part of income-sleeve ───────────────
//  The alternative was to have income-sleeve emit this block too. It would have
//  meant the same position arithmetic living in two functions, which is the
//  failure that has cost this project most: the scanner and the book each had
//  their own edge floor and disagreed about CPB on the same screen at the same
//  second. One computation, one owner, two calls.
//
//  ── The contract, unchanged ─────────────────────────────────────────────────
//  EVERY DISPLAYED STRING IS EMITTED BY THE ENGINE. This file formats nothing.
//  No thresholds, no rounding, no wording. If a line reads badly the fix is in
//  position-live, not here.
//
//  ── Why bullets, when the sleeve card uses prose ─────────────────────────────
//  Nik, on an earlier prose version: "too much still bullet points but human
//  tone", and then on seeing the grouped version, that it was right. The
//  distinction is that these bullets are grouped by what a signal MEANS rather
//  than where it came from. NKE carries 22 target cuts under Bearish and 70 buy
//  ratings under Supportive, and the DISAGREEMENT between them is the
//  information. Averaged into a sentence it disappears.
//

import SwiftUI

// MARK: - payload

struct LiveBook: Decodable {
    var ok: Bool?
    var asof: String?
    var positions: [Position]?
    var error: String?

    struct Position: Decodable, Identifiable {
        var ticker: String
        var id: String { ticker }
        var spot: Double
        /// Bearish · Balanced · Supportive. The engine decides; the client colours.
        var stance: String
        var bearish: [String]
        var supportive: [String]
        var catalyst: [String]
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
        // 60s, not 45. It prices the live chain for every held name, so it is
        // slower than the sleeve by design.
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(Secrets.supabasePublishableKey)", forHTTPHeaderField: "Authorization")
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

    /* Colour carries the STANCE and nothing else. Ink's rule is colour = data,
       loss = orange, gain = blue, so a bearish reading takes the loss tone and a
       supportive one the gain tone. Balanced stays in text, because a neutral
       reading painted either way is an opinion the engine did not express. */
    private var stanceTone: Color {
        switch p.stance.lowercased() {
        case "bearish": return Ink.loss
        case "supportive": return Ink.gain
        default: return Ink.text
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // eyebrow: ticker and spot, then the stance as the one coloured thing
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(p.ticker).font(InkFont.mono(13)).tracking(13 * 0.16)
                    .foregroundStyle(Ink.dim)
                Text(String(format: "%.2f", p.spot)).font(InkFont.mono(13))
                    .tracking(13 * -0.02).foregroundStyle(Ink.text)
                Spacer(minLength: 0)
                Text(p.stance.uppercased()).font(InkFont.mono(12)).tracking(12 * 0.14)
                    .foregroundStyle(stanceTone)
            }
            .padding(EdgeInsets(top: 22, leading: 22, bottom: 16, trailing: 22))

            group("Bearish", p.bearish, Ink.loss)
            group("Supportive", p.supportive, Ink.gain)
            group("Watch", p.catalyst, Ink.dim)

            Rectangle().fill(Ink.hair).frame(height: 1).padding(.vertical, 4)

            group("Where you stand", p.stand, Ink.dim)
            group("What is covered", p.coverage, Ink.dim)
            group("The floor", p.floor_lines, Ink.dim)

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
    private func group(_ label: String, _ lines: [String], _ tone: Color) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text(label.uppercased()).font(InkFont.mono(11.5)).tracking(11.5 * 0.16)
                    .foregroundStyle(tone.opacity(tone == Ink.dim ? 0.55 : 0.9))
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 9) {
                        // A dot, not a glyph bullet: it sits on the baseline and
                        // does not fight the mono figures inside the line.
                        Circle().fill(tone.opacity(0.5)).frame(width: 3.5, height: 3.5)
                            .padding(.top, 7)
                        Text(line).font(InkFont.display(14))
                            .foregroundStyle(Ink.text.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 4, leading: 22, bottom: 16, trailing: 22))
        }
    }
}
