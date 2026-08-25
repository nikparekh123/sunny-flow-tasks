//
//  SunnyPlanner.swift
//  Sunny — the planner card (M). handoff/cards/planner-card.md.
//
//  The card that says DO SOMETHING. The only card in the deck carrying an
//  instruction, and the second of exactly two not on white.
//
//  ⚠ IT ONLY EXISTS ONCE THE TRIGGER HAS FIRED. Two red sessions back to back
//  put it in the feed. There is no waiting state, no pending state, no "1 of 2"
//  counter, no dashed circle. If the rule is not met the card is ABSENT — not
//  greyed, not conditional. A pre-planner state was tried and cut.
//
//  ⚠ THE TRIGGER COMES FROM tlt-planner, NEVER FROM A LOCAL COUNT. Reading
//  `tlt_daily_closes` on 24 Aug showed red on the 20th and red on the 21st and
//  looked armed; the engine said redStreak 0, because it reads live closes and
//  TLT was +0.68% that morning, which breaks the run. Two things counting red
//  days is how the scanner and the book ended up disagreeing about CPB. One
//  engine owns the gate.
//
//  ⚠ RULED LINES, NOT THE DIGEST'S DOT GRID. The digest is a page you read, the
//  planner is a line you write on. The two treatments stay distinct: no dots
//  here, no rules there. And no inset ring — the deckle edge is the digest's.
//
//  ⚠ THE INSTRUCTION IS HANDWRITTEN. THE EVIDENCE IS NOT. Both session
//  percentages are Inter 600 tabular. A handwritten percentage reads as
//  decorative and the trigger stops being believable.
//

import SwiftUI

struct PlannerModel {
    let zoneLabel: String        // "NOW"
    let stamp: String            // an execution DATE, never a status word
    let instruction: String      // handwritten, the only hand on the card
    let sessions: [Session]      // exactly two. never three.
    let footer: [FooterPart]

    struct Session { let pct: String }        // UNSIGNED — the red disc carries direction
    struct FooterPart { let text: String; let strong: Bool }
}

struct SunnyPlannerCard: View {
    let m: PlannerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 0)
            body_
            Spacer(minLength: 0)
            footer
        }
        .padding(S.padPlannerM)                 // 16 / 19 / 15 — NOT --pad-card-m
        .frame(maxWidth: .infinity)
        .aspectRatio(S.Size.m.ratio, contentMode: .fit)
        .background {
            ZStack {
                S.plannerGround
                RuledLines()                    // 25px pitch, 1px line
            }
        }
        // overflow: hidden is REQUIRED here, unlike white cards — the ruled
        // ground must clip to the radius.
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        // Heavier than --shadow-card because the ground is darker than white and
        // the standard shadow disappears against it. NO inset ring.
        .shadow(color: S.shadowInk(0.09), radius: 2, x: 0, y: 2)
        .shadow(color: S.shadowInk(0.10), radius: 11, x: 0, y: 9)
    }

    // MARK: header — live dot, zone label, then the stamp pushed right

    private var header: some View {
        HStack(spacing: S.gap3) {
            // Filled, never a ring. A ring means "watched, no open leg" on the
            // P&L cards; reusing it here would say the opposite.
            Circle().fill(S.plannerDot).frame(width: S.dot, height: S.dot)
            Text(m.zoneLabel)
                .font(S.inter(S.t10, S.wBoldN))
                .tracking(S.track(S.t10, 0.13))
                .foregroundStyle(S.plannerLabel)
            Spacer(minLength: 0)
            stamp
        }
        .frame(height: 22)
    }

    /// A RUBBER STAMP, not a chip — outline only, squared at 5px rather than
    /// pilled, and it carries a date, never a status word. −2.5° is the only
    /// rotation on the card, and it is deliberately not the digest chip's −1.4°.
    private var stamp: some View {
        Text(m.stamp)
            .font(S.inter(S.t11, S.wBoldN))
            .tracking(S.track(S.t11, 0.06))
            .foregroundStyle(S.stampInk)
            .padding(S.padStamp)
            .overlay(RoundedRectangle(cornerRadius: S.stampRadius)
                .strokeBorder(S.stampBorder, lineWidth: 1.5))
            .rotationEffect(.degrees(S.stampTilt))
    }

    // MARK: body — instruction takes the slack, evidence sits on its baseline

    private var body_: some View {
        // flex-end: the instruction's last line and the percentages share a
        // bottom edge. Centre-aligning makes the discs float.
        HStack(alignment: .bottom, spacing: S.gap7) {
            Text(m.instruction)
                .font(S.hand(S.tHandInstruction))
                .lineSpacing(S.leadingHand(S.tHandInstruction, S.lhHandInstruction))
                .foregroundStyle(S.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: S.gapDisc) {
                ForEach(Array(m.sessions.enumerated()), id: \.offset) { _, s in
                    VStack(spacing: S.gap2) {
                        ZStack {
                            Circle().fill(S.lossBar)
                                .frame(width: S.streakDiscM, height: S.streakDiscM)
                            // ⚠ THE GROUND COLOUR, NOT WHITE. On paper a white
                            // glyph glares; the ground reads as the sheet showing
                            // through the ink. The one place a background colour
                            // is used as a foreground, and it is intentional.
                            Text("\u{2193}")
                                .font(S.inter(S.streakGlyphM, S.wBoldN))
                                .foregroundStyle(S.plannerGround)
                        }
                        Text(s.pct)
                            .font(S.inter(S.streakPct, S.wSemiN))
                            .foregroundStyle(S.loss)
                            .monospacedDigit()
                    }
                }
            }
            .fixedSize()
        }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            ForEach(Array(m.footer.enumerated()), id: \.offset) { _, p in
                Text(p.text)
                    .font(S.inter(S.t12, p.strong ? S.wBoldN : S.wMidN))
                    .foregroundStyle(p.strong ? S.ink : S.plannerBody)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
    }
}

/// 25px pitch, 1px line. Ruled lines are NOT aligned to the type — they run
/// under it like real ruled paper, which is the point: a note written across a
/// sheet, not text set on a baseline grid.
private struct RuledLines: View {
    var body: some View {
        Canvas { ctx, size in
            var y = S.plannerRulePitch
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                         with: .color(S.plannerRuleInk))
                y += S.plannerRulePitch
            }
        }
        .allowsHitTesting(false)
    }
}
