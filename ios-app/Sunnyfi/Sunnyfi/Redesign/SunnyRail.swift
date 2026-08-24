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
            facts = p.facts ?? []
            book = p.book ?? []
        } catch { self.error = String(describing: error) }
    }
}

private struct RailPayload: Decodable { var facts: [RailFact]?; var book: [BookName]? }

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
    var id: String { ticker }
}

struct RailFact: Decodable, Identifiable {
    let key: String
    let spans: [Span]
    var id: String { key }
    struct Span: Decodable { let text: String; let kind: String }
}

// MARK: - the dock

struct SunnyRail: View {
    let facts: [RailFact]
    let hidden: Bool
    /// The bottom safe area. The spec's home-indicator row is drawn by the HTML
    /// mock; in a real app it is the OS's, so the dock's ground extends under it
    /// instead. Same intent — the two read as one surface to the frame edge.
    let bottomInset: CGFloat

    private func ink(_ kind: String) -> Color {
        switch kind {
        case "figure": return S.railFigure
        case "minor":  return S.railMinor
        default:       return S.railWord
        }
    }
    private func weight(_ kind: String) -> CGFloat { kind == "figure" ? S.wSemiN : S.wMidN }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(alignment: .center, spacing: S.railGap) {
                    ForEach(Array(facts.enumerated()), id: \.element.id) { i, f in
                        // ⚠ A RULE GOES *BETWEEN* TWO FACTS. N facts, N−1 rules.
                        // Never leading, never trailing, never inside a compound
                        // fact — a compound fact is one hit box and one name.
                        if i > 0 {
                            Rectangle().fill(S.railDivider)
                                .frame(width: 1, height: 15)
                                .padding(.bottom, S.railLift)   // centres on the lifted line
                        }
                        fact(f)
                    }
                }
                .padding(.horizontal, S.margin)
                // stretch is load-bearing: it makes each fact a full 48pt-tall
                // item, which is how the 44pt hit floor is met with no card.
                .frame(height: S.railH)
            }
            .scrollIndicators(.hidden)
            .frame(height: S.railH)
            // The ground carries on under the OS home indicator so the dock and
            // the frame edge read as one surface.
            Color.clear.frame(height: bottomInset)
        }
        .background {
            ZStack {
                // Glass, not a second floor: the feed passes under as a blur.
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(S.railGround)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        // The only upward shadow in the app. No top hairline: at 92% ink against
        // --ground the edge is already the strongest contrast on screen.
        .shadow(color: S.shadowInk(0.14), radius: 13, x: 0, y: -10)
        .offset(y: hidden ? S.railH + bottomInset : 0)
        .opacity(hidden ? 0 : 1)
        .animation(S.easeSettle(S.durRailFade), value: hidden)
        .allowsHitTesting(!hidden)
                /* Transform on --dur-rail .58s, opacity on --dur-rail-fade .44s, both
           on --ease-settle. The fade finishes first so the dock is already
           invisible while it is still travelling, which is what makes it read
           as sliding away rather than blinking out. */
        .animation(S.easeSettle(S.durRail), value: hidden)
    }

    /// One flex item. gap 6, 13px, −.005em, and `padding-bottom: 5` so the line
    /// rides 2.5pt high — it optically centres in the space ABOVE the home
    /// indicator rather than measuring centred in its own 48pt box.
    private func fact(_ f: RailFact) -> some View {
        HStack(spacing: S.gap3) {
            ForEach(Array(f.spans.enumerated()), id: \.offset) { _, s in
                Text(s.text)
                    .font(S.inter(S.tRail, weight(s.kind)))
                    .tracking(S.track(S.tRail, -0.005))
                    .foregroundStyle(ink(s.kind))
            }
        }
        .monospacedDigit()                 // set once, at the fact
        .padding(.bottom, S.railLift)
        .frame(height: S.railH)
        .fixedSize()
        .contentShape(Rectangle())
    }
}
