//
//  OpenPremiumStrip.swift
//  Sunnyfi — Ink · the open-premium strip
//
//  Every short option still open, across the WHOLE book, on every tab.
//
//  ── Why it is global ─────────────────────────────────────────────────────────
//  Nik: "It will stay on top irrelevant whether you're Nvidia, TLT or income...
//  because of so many positions I'm kind of getting lost." Every other screen is
//  per-ticker; this is the only thing that answers "where am I" across all of
//  them, so it sits under the nav rather than inside a tab.
//
//  ── Why the strip and not the drawer ─────────────────────────────────────────
//  The first build was the drawer placement, and it failed twice over. Its sheet
//  is offset out of view when closed, and a SwiftUI offset moves the pixels but
//  NOT the hit region, so an invisible 300pt sheet sat over the ticker nav and
//  swallowed taps on TLT and Income. The measuring GeometryReader also wrote its
//  height back into state on every layout pass, so the slide animated against a
//  moving target and read as a jerk.
//
//  Claude Design's third pass chose the STRIP, and it dissolves both faults by
//  construction: it lives in normal layout flow, so there is nothing overlapping
//  anything, and it folds on HEIGHT rather than sliding, so no measurement is
//  needed and no offset exists to leak a hit region.
//
//  Spec: ~/Downloads/income_export 3. Every measure here is from that CSS —
//  46pt bar, 18pt gutters, 24/18 cell gaps, 460ms on the design's curve, a full
//  pill when collapsed, and a surface one tone off the position cards.
//
//  ── The contract ─────────────────────────────────────────────────────────────
//  Every string comes from open-premium. This file formats nothing.
//

import SwiftUI

// MARK: - payload

struct OpenPremium: Decodable {
    var ok: Bool?
    var build: String?
    var any_open: Bool?
    var tape: Tape?
    var error: String?

    struct Cell: Decodable {
        var k: String
        var v: String
        var text: Bool?
        var mark: Bool?
    }
    struct Tape: Decodable {
        var lab: String
        /// The one figure worth seeing without opening anything: what buying the
        /// whole book back would cost right now.
        var mini: String
        var cells: [Cell]
        var note: String?
    }
}

@Observable
final class OpenPremiumStore {
    var data: OpenPremium?
    private var loading = false

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/open-premium") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(Secrets.supabasePublishableKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data("{}".utf8)
        if let (d, _) = try? await URLSession.shared.data(for: req),
           let parsed = try? JSONDecoder().decode(OpenPremium.self, from: d),
           parsed.error == nil {
            data = parsed
        }
    }
}

// MARK: - the strip

struct OpenPremiumStrip: View {
    let tape: OpenPremium.Tape
    /// Persisted, as the design's `income_tape` is. Nik should not have to
    /// re-open it every time he changes tab.
    @AppStorage("income_tape_open") private var open = true

    private var motion: Animation { .timingCurve(0.32, 0.72, 0, 1, duration: 0.46) }

    /// One tone off the position cards, per the design's
    /// color-mix(in srgb, var(--ink-text) 7%, var(--ink-surface)).
    private var cardTone: some ShapeStyle { Ink.surface }

    var body: some View {
        VStack(spacing: 0) {
            bar
            if open {
                ledger
                    .transition(.opacity)
            }
        }
        .background(cardTone)
        .background(Ink.text.opacity(0.07))
        // A full pill when collapsed, the card radius when open. The shape change
        // is animated with the fold, so it reads as one movement.
        .clipShape(RoundedRectangle(cornerRadius: open ? Ink.radiusCard : 999, style: .continuous))
        .animation(motion, value: open)
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 2, trailing: 16))
    }

    private var bar: some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 12) {
                Text(tape.lab.uppercased())
                    .font(InkFont.mono(12.5)).tracking(12.5 * 0.16)
                    .foregroundStyle(Ink.dim)
                Spacer(minLength: 0)
                // Crossfades in on collapse: the label stays put and the figure
                // arrives beside it, rather than the bar re-flowing.
                Text(tape.mini)
                    .font(InkFont.mono(17)).tracking(17 * -0.02)
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                    .opacity(open ? 0 : 1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Ink.dim)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var ledger: some View {
        // 2x2. Four figures is the whole point: any more and it stops being
        // readable at a glance, which is its only job.
        let cells = tape.cells
        return VStack(alignment: .leading, spacing: 18) {
            ForEach(0..<((cells.count + 1) / 2), id: \.self) { row in
                HStack(alignment: .top, spacing: 24) {
                    ForEach(0..<2, id: \.self) { col in
                        let i = row * 2 + col
                        if i < cells.count { cell(cells[i]) } else { Spacer() }
                    }
                }
            }
            if let note = tape.note {
                Text(note).font(InkFont.mono(11.5)).tracking(11.5 * 0.04)
                    .foregroundStyle(Ink.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(EdgeInsets(top: 2, leading: 18, bottom: 18, trailing: 18))
    }

    private func cell(_ c: OpenPremium.Cell) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(c.k.uppercased()).font(InkFont.mono(12.5)).tracking(12.5 * 0.07)
                .foregroundStyle(Ink.dim).lineLimit(1).minimumScaleFactor(0.8)
            Group {
                if c.text == true {
                    Text(c.v).font(InkFont.display(15)).foregroundStyle(Ink.text)
                } else {
                    Text(c.v).font(InkFont.mono(20)).tracking(20 * -0.03)
                        .foregroundStyle(Ink.text).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .padding(.bottom, c.mark == true ? 3 : 0)
            .overlay(alignment: .bottom) {
                if c.mark == true { Rectangle().fill(Ink.text).frame(height: 1.5) }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
