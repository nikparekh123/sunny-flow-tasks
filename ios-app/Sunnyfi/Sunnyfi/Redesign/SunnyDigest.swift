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
    /// Chosen by the engine, never by this file. See position-live and
    /// SunnyCardBits — a guessed bold reads as a wrong answer.
    var bold: String? = nil
    var hi: String? = nil

    /// ⚠ THE VERDICT IS NOW A BRACKET, NOT A WASH. The three highlighter washes
    /// went with the paper: on white a wash puts the verdict in competition with
    /// the amber highlighter, and with three sentiments that is four washes on
    /// one card. A bracket has no ground, which is exactly what lets it appear
    /// three times without the card becoming a sticker album.
    var bracket: BracketTag? {
        if tags.contains(.bullish) { return .bullish }
        if tags.contains(.bearish) { return .bearish }
        if tags.contains(.note) { return .note }
        return nil
    }
}

/// ⚠ THREE WASHES, NO MORE. DIGEST-CARD §5 lists exactly new / bullish / note
/// and says "No other washes." The engine also emits BEARISH and IMPORTANT,
/// which have no wash of their own, so on Nik's instruction both fold into
/// `note` — a neutral fact worth flagging. A bullet carrying both gets ONE tag,
/// not two.
enum DigestTag: String, Identifiable {
    case new, bullish, bearish, note
    var id: String { rawValue }
    var ink: Color {
        switch self {
        case .new: return S.markNewInk
        case .bullish: return S.markBullInk
        case .bearish: return S.lossText
        case .note: return S.markNoteInk
        }
    }
    var wash: Color {
        switch self {
        case .new: return S.paperMarkNew
        case .bullish: return S.paperMarkBull
        case .bearish: return S.lossWash
        case .note: return S.paperMarkNote
        }
    }
    /// Engine tags -> card washes. Order matters: `new` wins, then direction.
    static func from(_ engine: [String]) -> [DigestTag] {
        var out: [DigestTag] = []
        if engine.contains("NEW") { out.append(.new) }
        /* ⚠ BEARISH IS ITS OWN VERDICT NOW. It used to fold into `note`,
           because the paper build had only three washes and no red one. The
           white deck's brackets carry three sentiments outright, so a bearish
           line finally says so. IMPORTANT still folds into note — it is a
           flag, not a direction. */
        if engine.contains("BULLISH") { out.append(.bullish) }
        else if engine.contains("BEARISH") { out.append(.bearish) }
        else if engine.contains("IMPORTANT") { out.append(.note) }
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
    var onRead: (() -> Void)? = nil
    /// The user's flag. Deliberately NOT persisted here — it belongs with the
    /// seen state, and nothing writes it yet.
    @State private var starred = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(Array(sections.enumerated()), id: \.element.id) { _, sec in
                band(sec)
            }
            if onRead != nil { readBand }
        }
        .frame(width: S.content, alignment: .leading)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        /* ⚠ NO overflow CLIP. The paper build needed one for the dot grid; white
           has nothing to clip, and dropping it stops the shadow clipping on some
           engines. It takes --shadow-card-l despite having no size class,
           because it is the tallest thing in the feed. */
        .sunnyShadow(S.shadowCardL)
        .measure("digest-card")
    }

    // MARK: header — 78, two rows

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            // CENTRE here, not baseline: a row of same-height objects.
            HStack(alignment: .center, spacing: S.gap6) {
                HStack(alignment: .center, spacing: S.gap4) {
                    /* ⚠ THE STAR IS --ink, NEVER AMBER. Amber on this card means
                       "changed since you last read" — that is the app talking.
                       Importance is the USER talking, so the star stays out of
                       the state vocabulary entirely. It precedes the timestamp
                       because a flag qualifies the whole card and the top-left
                       corner is read first. */
                    Button { starred.toggle() } label: {
                        Text(starred ? "\u{2605}" : "\u{2606}")
                            .font(.system(size: S.tStar))
                            .foregroundStyle(S.ink)
                            .frame(width: S.hitMin, height: S.hitMin)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // The 44pt target OVERHANGS the row rather than growing it:
                    // padding the row taller breaks the 78pt header.
                    .frame(width: S.tStar, height: S.tStar)
                    Text(timestamp)
                        .font(InkFont.display(S.t10, S.wBold))
                        .tracking(S.track(S.t10, S.lsLabel))
                        .textCase(.uppercase)
                        .foregroundStyle(S.mute)
                }
                Spacer(minLength: 0)
                if newCount > 0 { SunnyChip(text: "\(newCount) new") }
            }
            // BASELINE here: a row mixing weights at one size.
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                /* Same size, separated by WEIGHT alone, so "BABA 119.53" reads
                   as one line rather than a name and a number. The name is
                   context; the price is the figure. */
                Text(ticker)
                    .font(S.inter(S.t19, S.wLightN))
                    .tracking(S.track(S.t19, -0.01))
                    .foregroundStyle(S.ink)
                Text(spot)
                    .font(S.inter(S.t19, S.wBoldN))
                    .tracking(S.track(S.t19, -0.02))
                    .foregroundStyle(S.ink)
                    .monospacedDigit()
            }
        }
        /* ⚠ PAD FIRST, THEN PIN THE WIDTH. Pinning 361 and padding after adds
           19 either side OUTSIDE the pin, so the band renders 399 wide inside a
           361 card and the chip and the heading rule run off the right edge.
           The width is the card's; the padding lives inside it. */
        .padding(EdgeInsets(top: 17, leading: 19, bottom: 15, trailing: 19))
        .frame(width: S.content, alignment: .leading)
    }

    // MARK: a band — heading then bullets. Only the header has a top padding;
    // every band's top spacing is the previous band's padding-bottom.

    private func band(_ sec: DigestSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SunnySectionHead(title: sec.heading)
            ForEach(sec.lines) { l in
                SunnyBodyLine(text: l.text, bold: l.bold, highlight: l.hi, tag: l.bracket)
            }
        }
        .padding(EdgeInsets(top: 0, leading: 19, bottom: 18, trailing: 19))
        .frame(width: S.content, alignment: .leading)
    }

    // MARK: read band — 60

    private var readBand: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button { onRead?() } label: {
                /* A 44pt row holds the pill so the hit target is right WITHOUT
                   padding the band. No rotation: the paper build's −1.1° was a
                   hand affordance and went with the hand layer. There is no
                   rotation anywhere on this card. */
                Text("Read")
                    .font(InkFont.display(S.t10, S.wBold))
                    .tracking(S.track(S.t10, S.lsLabel))
                    .textCase(.uppercase)
                    .foregroundStyle(S.mute)
                    .padding(S.padPill)
                    .overlay(Capsule().strokeBorder(S.hair, lineWidth: S.rule))
                    .frame(height: S.hitMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 0, leading: 19, bottom: 16, trailing: 19))
        .frame(width: S.content, alignment: .trailing)
    }
}

struct PaperHeading: View {
    let text: String
    var body: some View {
        HStack(spacing: 9) {
            /* ⚠ ONE LINE, ALWAYS. A heading that wraps drags its rule down
               beside the second line and reads as broken; "What last week
               earned" did exactly that at Caveat 22. fixedSize keeps it whole
               and lets the rule take what is left. Keep headings short. */
            Text(text)                                  // sentence case, never upper
                .font(S.hand(S.tHandHead))
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
                    .font(S.hand(S.tHandTag))
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


// MARK: - the read control, paper variant

/// SHELL.md §9: on a white card the read control is a 44pt ink pill; "on a
/// paper card the same control is a Caveat pencil circle instead, matching the
/// card's hand". Every card in the feed today is paper, so this is the one that
/// gets built. The white pill is not written until a white card is featured.
///
/// ⚠ NO ROTATION. The "1 new" chip owns the only tilt on the card, and
/// DIGEST-CARD §3 says a second one makes the whole thing read as a template
/// rather than a note. This is the same shape without the tilt.
///
/// ⚠ AND IT DOES NOT INFLATE THE BAND. The visual circle is ~26pt; the 44pt hit
/// target is taken with negative vertical insets, exactly as the white pill
/// takes −14 / −13 past the card's own padding. Growing the band to 44 instead
/// would push the card's base out by 18pt and only on featured cards, so the
/// same card would measure two heights.
struct PaperReadControl: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Lowercase. awareness-card.md §6: "never `Read` and never
            // uppercase: the hand layer is sentence case everywhere on this
            // card." The white card's control says Read; this one is not that
            // control wearing paper, it is a different object.
            Text("read")
                .font(S.hand(S.tPaperChip))
                .foregroundStyle(S.paperInkHead)
                // 1 top / 2 bottom optically centres the hand, which sits high
                // in its box. 15 across, wider than the chip's 11.
                .padding(S.padRead)
                .overlay(Capsule().strokeBorder(S.readRing, lineWidth: 1.5))
                .rotationEffect(.degrees(S.readTilt))
                // The 44pt hit is the PARENT; the circle inside measures ~28 and
                // does not need to. Hit and circle are different objects here.
                .frame(height: S.hitMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
