//
//  SunnyDigest.swift
//  Sunny — the paper digest card. DIGEST-CARD.md is the normative build sheet.
//
//  ── Called the AWARENESS CARD ───────────────────────────────────────────────
//  Nik's name for it, short for situational awareness. Use it in conversation
//  and in comments; it is deliberately NOT on screen. The card carries no title
//  in the feed and should not gain one. The type names here predate the name
//  and are not worth churning.
//
//  ── The three rules that outrank everything else (DIGEST-CARD §0) ──────────
//  1. HANDWRITING IS LABELS, TAGS, THE TICKER AND THE TIMESTAMP. NEVER A FIGURE.
//     Every number is Inter, tabular. A handwritten price reads as decorative
//     and the card stops being trustworthy at a glance.
//  2. HEIGHT FOLLOWS CONTENT. No aspect-ratio, no size class. The line count
//     changes per position; this is the documented exception to the four-size
//     table in CARDS.md.
//  3. NO FULL-BLEED DIVIDERS. Each heading grows its own rule to the right,
//     stopping at the text column. The one exception is the 2px rule above DO.
//
//  ⚠ THIS IS THE ONLY CARD ON PAPER. It earns its difference by being the only
//  one. Do not spread the treatment to feed cards, chart cards, or chrome.
//

import SwiftUI

// MARK: - payload

struct DigestSection: Identifiable {
    let id = UUID()
    let heading: String          // sentence case: Analysts, Where you stand, The floor
    let lines: [DigestLine]
}

struct DigestLine: Identifiable {
    let id = UUID()
    let text: String
    let tags: [DigestTag]
}

/// ⚠ THREE WASHES, NO MORE. DIGEST-CARD §5 lists exactly new / bullish / note
/// and says "No other washes." The engine also emits BEARISH and IMPORTANT,
/// which have no wash of their own, so on Nik's instruction both fold into
/// `note` — a neutral fact worth flagging. A bullet carrying both gets ONE tag,
/// not two.
enum DigestTag: String, Identifiable {
    case new, bullish, note
    var id: String { rawValue }
    var ink: Color {
        switch self {
        case .new: return S.markNewInk
        case .bullish: return S.markBullInk
        case .note: return S.markNoteInk
        }
    }
    var wash: Color {
        switch self {
        case .new: return S.paperMarkNew
        case .bullish: return S.paperMarkBull
        case .note: return S.paperMarkNote
        }
    }
    /// Engine tags -> card washes. Order matters: `new` wins, then direction.
    static func from(_ engine: [String]) -> [DigestTag] {
        var out: [DigestTag] = []
        if engine.contains("NEW") { out.append(.new) }
        if engine.contains("BULLISH") { out.append(.bullish) }
        else if engine.contains("BEARISH") || engine.contains("IMPORTANT") { out.append(.note) }
        return out
    }
}

/// ⚠ ONE INSTRUCTION PER LINE. DIGEST-CARD §9 gives the block a single
/// instruction plus a reason, but the engine emits DO as a LIST of discrete
/// actions — four for NKE. Folding the tail into the "reason" slot joined them
/// with spaces and produced one run-on paragraph: "…$1,610 in Buy 20 puts at
/// 40, 18 Dec… to close the floor gap Net after the floor top-up…". Three
/// separate actions with no separator. Each action now gets its own line.
struct DigestDo {
    let lines: [Line]
    struct Line: Identifiable {
        let id = UUID()
        let text: String
        /// An ACTION is something to place at the broker. A NOTE is the
        /// consequence or caveat hanging off the actions above it. The engine
        /// decides; the card must not guess from the wording.
        let isAction: Bool
    }
}

// MARK: - the card

struct SunnyDigestCard: View {
    let timestamp: String
    let ticker: String
    let spot: String
    let newCount: Int
    let sections: [DigestSection]
    let doBlock: DigestDo?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(Array(sections.enumerated()), id: \.element.id) { i, sec in
                section(sec, isLast: i == sections.count - 1 && doBlock == nil)
            }
            if let d = doBlock {
                // The ONLY full-bleed rule on the card, and it sits immediately
                // above the DO block. Nowhere else.
                Rectangle().fill(S.paperRuleInk)
                    .frame(height: S.ruleHeavy)
                    .frame(maxWidth: .infinity)
                doBand(d)
            }
        }
        .frame(width: S.content)                       // 361, fixed. Height is an OUTPUT.
        .measure("digest-card")
        // ⚠ ONE background, not two chained. A second .background sits BEHIND
        // the first, so grain applied that way lands under the butter fill and
        // never shows. Stack them explicitly instead.
        .background {
            ZStack {
                S.paperButter
                PaperGrain()                           // one dot per 16px cell
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        // The inset ring is what makes it read as a sheet rather than a tinted
        // div. It is the part people drop; do not.
        .overlay(
            RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous)
                .strokeBorder(S.paperRing, lineWidth: 1)
        )
        .shadow(color: S.shadowInk(0.06), radius: 2, x: 0, y: 2)
        .shadow(color: S.shadowInk(0.09), radius: 11, x: 0, y: 9)
    }

    // MARK: header — 18 / 20 / 14, gap 2

    private var header: some View {
        VStack(alignment: .leading, spacing: S.gap1) {
            Text(timestamp)
                .font(S.handAlt(S.tHandMeta))
                .tracking(S.track(S.tHandMeta, 0.02))
                .foregroundStyle(S.paperInkMeta)
            // BASELINE, not centre: Caveat 26 and Inter 23 have different cap
            // heights and only a baseline lines them up.
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(ticker)
                    .font(S.hand(S.tHandTitle, 700))
                    .foregroundStyle(S.paperInkTicker)
                Text(spot)
                    .font(S.inter(S.tPaperSpot, S.wSemiN))
                    .tracking(S.track(S.tPaperSpot, -0.03))
                    .foregroundStyle(S.paperInkStrong)
                    .monospacedDigit()
                Spacer(minLength: 0)
                if newCount > 0 { chip }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 14, trailing: 20))
    }

    /// A PENCIL CIRCLE, not a filled pill. Outline only, no background.
    /// −1.4° is the ONLY rotation on the card; a second tilt makes the whole
    /// thing read as a template rather than a note.
    private var chip: some View {
        Text("\(newCount) new")
            .font(S.hand(S.tPaperChip, 600))
            .foregroundStyle(S.paperChipInk)
            // 1 top / 2 bottom optically centres Caveat, which sits high in its box.
            .padding(EdgeInsets(top: 1, leading: 11, bottom: 2, trailing: 11))
            .overlay(Capsule().strokeBorder(S.paperChipRing, lineWidth: 1.5))
            .rotationEffect(.degrees(-1.4))
    }

    // MARK: section — padding-top is ALWAYS 0; the heading's rule separates

    private func section(_ sec: DigestSection, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Text(sec.heading)                       // sentence case, never upper
                    .measure("head-" + sec.heading.prefix(6).lowercased())
                    .font(S.hand(S.tHandHead, 700))
                    .foregroundStyle(S.paperInkHead)
                // flex: 1, never a width. The rule stops at the text column —
                // that is the whole difference from the old hairline.
                RoundedRectangle(cornerRadius: 1)
                    .fill(S.paperRule)
                    .frame(height: 1.5)
                    .frame(maxWidth: .infinity)
            }
            ForEach(sec.lines) { line in bodyLine(line) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 0, leading: 20, bottom: isLast ? 20 : 16, trailing: 20))
    }

    /// Bullet is 5px (4 vanishes on butter) and offset 8 from the top, which is
    /// what optically centres it on the first line at 14.5/1.45. NOT centre
    /// alignment, which drifts on any line that wraps.
    private func bodyLine(_ line: DigestLine) -> some View {
        HStack(alignment: .top, spacing: S.gap4) {
            Circle().fill(S.paperBullet)
                .frame(width: 5, height: 5)
                .padding(.top, S.gap4)
            DigestFlow(text: line.text, tags: line.tags)
        }
    }

    // MARK: DO — 16 / 20 / 18, gap 5, on its own ground

    private func doBand(_ d: DigestDo) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Do")
                .font(S.hand(S.tHandHead, 700))
                .foregroundStyle(S.paperInkHead)
            // ⚠ DO LINES ARE BODY TYPE, BULLETED, exactly like every other line
            // on the card. DIGEST-CARD §9 puts the instruction at Inter 18/600
            // and the reason at 14/450, and Nik rejected both on sight: four
            // heavy 18pt lines stacked at the foot of the card read as a
            // different document, and two sizes inside one block read as odd.
            // Same size, same weight, same bullet — the ink and the ground are
            // what mark this block out, not the type. His call outranks §9.
            ForEach(d.lines) { line in
                HStack(alignment: .top, spacing: S.gap4) {
                    Circle().fill(S.paperBullet)
                        .frame(width: 5, height: 5)
                        .padding(.top, S.gap4)
                    Text(line.text)
                        .font(S.inter(S.tPaperBody, S.wBodyN))
                        .lineSpacing(S.leading(S.tPaperBody, S.wBodyN, S.lhPaperBody))
                        .foregroundStyle(S.paperInkDo)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 18, trailing: 20))
        .background(S.paperDoGround)
    }
}

// MARK: - paper primitives, shared with the Monday card

/// A section heading and the rule that runs out from it. `flex: 1` on the rule,
/// never a width — it stops at the text column, which is the whole difference
/// from the hairlines on the white cards.
struct PaperHeading: View {
    let text: String
    var body: some View {
        HStack(spacing: 9) {
            /* ⚠ ONE LINE, ALWAYS. A heading that wraps drags its rule down
               beside the second line and reads as broken; "What last week
               earned" did exactly that at Caveat 22. fixedSize keeps it whole
               and lets the rule take what is left. Keep headings short. */
            Text(text)                                  // sentence case, never upper
                .font(S.hand(S.tHandHead, 700))
                .foregroundStyle(S.paperInkHead)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            RoundedRectangle(cornerRadius: 1)
                .fill(S.paperRule)
                .frame(height: 1.5)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Bullet 5px, offset 8 from the top. NOT centre alignment, which drifts on any
/// line that wraps.
struct PaperBullet<C: View>: View {
    @ViewBuilder let content: C
    var body: some View {
        HStack(alignment: .top, spacing: S.gap4) {
            Circle().fill(S.paperBullet)
                .frame(width: 5, height: 5)
                .padding(.top, S.gap4)
            content
        }
    }
}

/// The three-layer sheet: ground, grain, deckle ring. The inset ring is what
/// makes it read as paper rather than a tinted div, and is the part people drop.
struct PaperSheet: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: S.content)
            .background { ZStack { S.paperButter; PaperGrain() } }
            .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous)
                .strokeBorder(S.paperRing, lineWidth: 1))
            .shadow(color: S.shadowInk(0.06), radius: 2, x: 0, y: 2)
            .shadow(color: S.shadowInk(0.09), radius: 11, x: 0, y: 9)
    }
}
extension View { func paperSheet() -> some View { modifier(PaperSheet()) } }

// MARK: - grain

/// One dot per 16px cell, the same grid the rest of the app is spaced on, so
/// the grain never fights the type. Do not scale it per card size.
struct PaperGrain: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)),
                             with: .color(S.paperDot))
                    x += S.paperDotSize
                }
                y += S.paperDotSize
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - tags trailing the sentence

/// DIGEST-CARD §5: "Tags trail the sentence, separated by a normal space."
///
/// SwiftUI cannot put a padded, rounded, washed pill inside a wrapping
/// paragraph — AttributedString backgrounds have neither padding nor a corner
/// radius. So the paragraph is laid out word by word and the tags are just more
/// items in the same flow. That is the only way the tag lands after the last
/// word rather than on a line of its own.
private struct DigestFlow: View {
    let text: String
    let tags: [DigestTag]

    var body: some View {
        FlowLayout(spacing: 0, lineSpacing: S.leading(S.tPaperBody, S.wBodyN, S.lhPaperBody)) {
            ForEach(Array(text.split(separator: " ").enumerated()), id: \.offset) { _, w in
                Text(String(w) + " ")
                    .font(S.inter(S.tPaperBody, S.wBodyN))
                    .foregroundStyle(S.paperInk)
                    .monospacedDigit()
            }
            ForEach(tags) { t in
                Text(t.rawValue)                        // lowercase, no tracking
                    .font(S.hand(S.tHandTag, 700))
                    .foregroundStyle(t.ink)
                    .padding(S.padMark)                 // 0 top, 1 bottom: centres Caveat
                    .background(RoundedRectangle(cornerRadius: S.radiusMark).fill(t.wash))
                    .fixedSize()                        // white-space: nowrap
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 { x = 0; y += lineH + lineSpacing; lineH = 0 }
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX; y += lineH + lineSpacing; lineH = 0
            }
            v.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}
