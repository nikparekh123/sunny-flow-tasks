//
//  SunnyCardBits.swift
//  Sunny — the pieces every white card shares. CARD-SYSTEM.md §4 and §5.
//
//  ⚠ FOUR EMPHASIS SYSTEMS, ONE JOB EACH, NEVER TWO ON A LINE. That is the whole
//  design of the white deck:
//
//      bold 700     the figure the line is about, ONE per line
//      amber wash   what changed since you last read
//      [bracket]    the verdict
//      ★ star       yours, not the app's
//
//  A line whose subject is a RELATIONSHIP gets no bold at all — the 50-day /
//  200-day line is the case, because its point is that spot sits BETWEEN two
//  levels, so neither number is the answer.
//

import SwiftUI

// MARK: - the bracket tag

/// ⚠ NO GROUND, AND THAT IS WHAT LETS IT APPEAR THREE TIMES ON ONE CARD. A wash
/// would put it in competition with the highlighter, and with three sentiments
/// that is four washes on one card. Only the WORD takes sentiment ink; the
/// brackets stay --mute-2, and that split is what makes it read as an aside
/// rather than a badge.
///
/// ⚠ .1em, NOT the .13em every other uppercase label carries. At 11px the wider
/// tracking opens the word too far and it stops reading as one unit. These are
/// the only two tracking values on any uppercase text in the deck.
enum BracketTag: String {
    case bullish, bearish, note

    var ink: Color {
        switch self {
        case .bullish: return S.gainDeep     // 9.9:1
        case .bearish: return S.lossText     // 8.9:1
        case .note:    return S.markNoteInk  // 9.12:1 on white; near-grey on butter
        }
    }

    /// Built as one attributed run so it can sit inline at the end of a body
    /// line and never wrap between the bracket and the word.
    func attributed() -> AttributedString {
        var open = AttributedString("[")
        open.foregroundColor = S.mute2
        var word = AttributedString(rawValue.uppercased())
        word.foregroundColor = ink
        var close = AttributedString("]")
        close.foregroundColor = S.mute2
        var all = open + word + close
        all.font = S.inter(S.tTagBracket, S.wBoldN)
        all.tracking = S.track(S.tTagBracket, S.lsTagBracket)
        return all
    }

    static func from(_ tags: [String]) -> BracketTag? {
        if tags.contains("BULLISH") { return .bullish }
        if tags.contains("BEARISH") { return .bearish }
        if tags.contains("NOTE") { return .note }
        return nil
    }
}

// MARK: - a body line, with its one bold and its one highlight

/// ⚠ THE ENGINE HAS TO SAY WHICH RUN IS THE BOLD. "The figure the line is about"
/// is a judgment about the sentence, and the sentence is composed server-side —
/// position-live knows that a line is about the median target and not the 71
/// analysts, and this file cannot. Until it marks the run, `bold` is nil here
/// and the line renders as plain context, which is the honest failure: a missing
/// bold reads as a quiet line, while a GUESSED bold reads as a wrong answer.
///
/// Same for the highlight. Amber means "changed since you last read", and only
/// the engine's seen-flag knows which phrase that is.
struct SunnyBodyLine: View {
    let text: String
    var bold: String? = nil          // the exact substring to set at 700
    var highlight: String? = nil     // the exact substring to wash amber
    var tag: BracketTag? = nil

    var body: some View {
        HStack(alignment: .top, spacing: S.gap4) {
            /* The one legal margin on the card, and it is DERIVED:
               (24 − 4) / 2 = 10 centres a 4px dot on the first line of a 24px
               line box. A dot cannot be centred with flexbox — align-items would
               centre it on the whole wrapped block, putting it beside line two
               of a three-line bullet. */
            Circle().fill(S.hair)
                .frame(width: S.bullet, height: S.bullet)
                .padding(.top, S.digestBulletOffset)
            Text(runs)
                .lineSpacing(S.leading(S.tDigestBody, S.wLightN, S.lhDigest))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var runs: AttributedString {
        var out = AttributedString(text)
        out.font = S.inter(S.tDigestBody, S.wLightN)
        out.foregroundColor = S.ink

        /* ⚠ THE MARKED TEXT KEEPS ITS OWN INK. A real highlighter changes the
           paper, not the pen — the moment the text takes a colour the mark stops
           being emphasis-within-a-sentence and becomes a tag, at which point two
           systems are doing one job. */
        if let h = highlight, let r = out.range(of: h) {
            out[r].backgroundColor = S.warnWash
        }
        if let b = bold, let r = out.range(of: b) {
            out[r].font = S.inter(S.tDigestBody, S.wBoldN)
        }
        if let tag {
            out += AttributedString(" ") + tag.attributed()
        }
        return out
    }
}

// MARK: - a section heading and the rule that runs out of it

/// The rule takes whatever is left, so its width is a CONSEQUENCE of the label,
/// never a value. Hard-code a width and the three headings stop ending flush the
/// moment a label changes.
struct SunnySectionHead: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(InkFont.display(S.t10, S.wBold))
                .tracking(S.track(S.t10, S.lsLabel))
                .textCase(.uppercase)
                .foregroundStyle(S.mute)
                .fixedSize()
            Rectangle().fill(S.ruleColor).frame(height: S.rule)
        }
    }
}

// MARK: - the amber chip

/// --warn-text on --warn-wash is the documented pairing. `--warn-deep` is the ink
/// for --warn-chip on an INK ground and does not belong on a wash — using it here
/// puts two different ambers on one card for one semantic.
struct SunnyChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(InkFont.display(S.t10, S.wBold))
            .tracking(S.track(S.t10, S.lsLabel))
            .textCase(.uppercase)
            .foregroundStyle(S.warnText)
            .padding(S.padChip)
            .background(S.warnWash)
            .clipShape(RoundedRectangle(cornerRadius: S.radiusChip, style: .continuous))
            .fixedSize()
    }
}

// MARK: - a card header: ticker, then what kind of card this is

/// ⚠ THIS REPLACED THE 10px UPPERCASE MICRO-LABEL. A micro-label is right for a
/// label INSIDE a card — the footer measures, the section heads — but the thing
/// that says which position a card is about is a heading, and at 10px it was the
/// smallest text on a card whose next element was 17. Card headers and interior
/// labels are two different jobs at two sizes.
struct SunnyCardHead: View {
    let ticker: String
    let kind: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
            Text(ticker)
                .font(InkFont.display(S.t14, S.wBold))
                .tracking(S.track(S.t14, -0.01))
                .foregroundStyle(S.ink)
            Text(kind)
                .font(S.inter(S.t12, S.wMidSmN))
                .foregroundStyle(S.ink2)
        }
        .fixedSize()
    }
}
