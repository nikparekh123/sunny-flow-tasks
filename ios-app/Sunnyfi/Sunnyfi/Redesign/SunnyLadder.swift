//
//  SunnyLadder.swift
//  Sunny — if exercised, the ladder. cards/exercise-ladder.md.
//
//  ⚠ A SOLD CALL AND A SOLD PUT ON ONE NAME CANNOT BOTH BE ASSIGNED. They are
//  not two list items, they are branches of one variable — where the price
//  lands. So this is a ladder of MUTUALLY EXCLUSIVE PRICE BANDS ordered high to
//  low, and exactly one rung will be true. A list of legs cannot express that,
//  and every version that tried read as two unrelated facts.
//
//  ⚠ LIKELIHOOD IS A WORD, NEVER A PERCENT. `9%` against `12.1% OTM` is a number
//  nobody can defend or check, and at figure size it became the most
//  authoritative thing on the card. Three values only.
//
//  ⚠ THE FIGURE IS WHAT YOU WOULD HOLD, not what moves. Read the figure column
//  down and you have your position in each world — 0 / 2,000 / 4,000 / 5,000 —
//  and the mutual exclusivity stops needing an explanation. The share DELTA
//  lives in support line 2.
//
//  ⚠ RED MEANS MONEY LOST, NOTHING ELSE. The verdict words are grey at every
//  value. `Likely` in red would say a probable assignment is a bad one, which is
//  not for the card to decide. --loss #A80016 does not appear on this card at
//  all: there is no dot, and the figure is a share count.
//

import SwiftUI

struct SunnyLadderCard: View {
    let ticker: String
    let e: BookExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap5) {
                Text(ticker)
                    .font(S.inter(S.t20, S.wSemiN))
                    .tracking(S.track(S.t20, -0.01))
                    .foregroundStyle(S.ink)
                /* Spot, once, for the whole card. No rung repeats it: a rung's
                   title already states its band, and the live rung is marked by
                   its ground. */
                Text("if exercised \u{00B7} spot \(sPrice(e.spot))")
                    .font(S.inter(S.t13, S.wMidSmN))
                    .foregroundStyle(S.mute2)
                Spacer(minLength: 0)
                /* ⚠ NEVER AN EXCEPTION COUNT. A ladder has no exceptions, only
                   one true rung. */
                Text("\(e.legs) \(e.legs == 1 ? "leg" : "legs")".uppercased())
                    .font(S.inter(S.t10, S.wSemiN))
                    .tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.mute)
                    .sunnyLineBox(S.t10)
            }
            /* ⚠ THE HEADER IS PINNED TO THE TICKER'S LINE BOX. The sheet
               measures 55 = 19 + 20 + 16, which is a 20px ticker at line-height
               1; UIKit lays Inter at 20 in a 24 box and the card came in 4.3
               tall, which then read as a rhythm fault against the six lists. */
            .frame(height: S.t20)
            .padding(.top, S.padCardHeadTop)
            .padding(.bottom, S.padCardHeadBottom)
            .padding(.horizontal, S.padListX)

            VStack(spacing: S.tileRowGap) {
                ForEach(e.rungs) { rung($0) }
            }
            .padding(.horizontal, S.padListX)

            Color.clear.frame(height: 19)
        }
        .frame(width: S.content)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCardL)
        .monospacedDigit()
        .measure("ladder-\(ticker)")
    }

    @ViewBuilder
    private func rung(_ r: BookExercise.Rung) -> some View {
        VStack(alignment: .leading, spacing: S.rungGap) {
            HStack(spacing: 6) {
                /* ⚠ NO DOT GUTTER. Three rungs of one card are compared on their
                   shared left edge; an indent on the live rung cost the other two
                   their alignment. The title is fixed and non-wrapping so a
                   longer band fails loudly instead of reflowing. */
                Text(title(r).uppercased())
                    .font(S.inter(S.t11, S.wSemiN))
                    .tracking(S.track(S.t11, S.lsRung))
                    .foregroundStyle(S.ink)
                    .sunnyLineBox(S.t11)
                    .fixedSize()
                /* ⚠ THE ARROW READS THE SHARE COUNT, NOT THE PRICE. Every rung
                   already names a price band in its title, so an arrow repeating
                   it would say nothing. Ink, never state colour: a direction is
                   neither good nor bad. And 6 after the title, not pinned to the
                   far corner, where it read as an ornament the eye had to pair
                   with something 200 away. */
                Text(r.shareDelta > 0 ? "\u{2191}" : r.shareDelta < 0 ? "\u{2193}" : "\u{2194}")
                    .font(S.inter(S.t15, S.wMidSmN))
                    .foregroundStyle(S.ink)
                    .sunnyLineBox(S.t15)
            }
            HStack(alignment: .center, spacing: S.gap6) {
                /* ⚠ THE FIGURE SLOT IS FIXED so support starts at the same x on
                   every rung. The support block's LEFT edge is this card's
                   column. */
                VStack(alignment: .leading, spacing: S.verdictGap) {
                    /* The unit is a support-size suffix, not part of the figure.
                       At 30 `sh` cost ~30 of the slot and wrapped `1,610 sh` onto
                       two lines. */
                    HStack(alignment: .firstTextBaseline, spacing: S.figUnitGap) {
                        Text(money(r.held))
                            .font(S.inter(S.t30, S.wSemiN))
                            .tracking(S.track(S.t30, S.lsTight))
                            .foregroundStyle(S.ink)
                        Text("sh")
                            .font(S.inter(S.t14, S.wMidSmN))
                            .foregroundStyle(S.mute2)
                    }
                    .sunnyLineBox(S.t30)
                    /* ⚠ THE VERDICT SITS UNDER THE FIGURE, NOT IN THE CORNER.
                       The number and its verdict are one thought; reading 1,610
                       and then jumping to the far corner for `unlikely` made the
                       reader do the joining. */
                    Text(r.verdict.uppercased())
                        .font(S.inter(S.t10, S.wSemiN))
                        .tracking(S.track(S.t10, S.lsLabel))
                        .foregroundStyle(S.mute)
                        .sunnyLineBox(S.t10)
                }
                .frame(width: S.figSlot, alignment: .leading)
                /* ⚠ SUPPORT IS LEFT-ALIGNED, the only card in the family that
                   is. A list right-aligns support because it must form a column
                   against six other rows. Here the three lines are one paragraph
                   about one world, and a ragged left edge made them read as three
                   separate facts. */
                VStack(alignment: .leading, spacing: S.supportLineGapLg) {
                    ForEach(Array(support(r).enumerated()), id: \.offset) { _, l in
                        Text(l.0)
                            .font(S.inter(S.t14, S.wMidSmN))
                            .foregroundStyle(l.1 ? S.lossText : S.mute2)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(height: S.t14 * S.lhSupportLg)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(S.padRung)
        .frame(width: S.content - S.padListX * 2, alignment: .leading)
        .frame(minHeight: S.rungMinH)
        .background(r.live ? S.tileGroundLive : S.tileGround)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusTile, style: .continuous))
    }

    /// The band, high to low. An en dash between two prices, which is what a
    /// numeric range takes.
    private func title(_ r: BookExercise.Rung) -> String {
        if r.hi == nil, let lo = r.lo { return "Above \(sPrice(lo))" }
        if r.lo == nil, let hi = r.hi { return "Below \(sPrice(hi))" }
        guard let lo = r.lo, let hi = r.hi else { return "" }
        return "\(sPrice(lo)) \u{2013} \(sPrice(hi))"
    }

    /// Three fixed jobs: what happens, shares and cash, the price you end at.
    private func support(_ r: BookExercise.Rung) -> [(String, Bool)] {
        var out: [(String, Bool)] = [(what(r), false)]
        if let c = r.credit {
            /* ⚠ A BOTH-EXPIRE BAND CREDITS EVERY LEG THAT EXPIRES. Crediting one
               set of two is a defect the sheet names by name. */
            out.append(("keep $\(money(c)) credit", false))
        } else {
            out.append(("\(signedBare(r.shareDelta)) sh, \(sK(r.cash))", false))
        }
        /* ⚠ LINE 3 SPLITS BY DIRECTION. A call assigned SELLS shares, so the
           decisive fact is realized P&L. A put assigned BUYS them, so it is the
           new average. Same slot, because both answer: what does this leave me
           holding, and at what price. And it carries BOTH averages — what the
           basis was is half the answer. */
        if let n = r.newAvg {
            out.append(("avg \(sPrice(r.oldAvg)) \u{2192} \(sPrice(n))", false))
        } else if let rz = r.realized {
            out.append(("realized \(sK(rz))", rz < 0))
        } else {
            out.append(("avg holds \(sPrice(r.oldAvg))", false))
        }
        return out
    }

    private func what(_ r: BookExercise.Rung) -> String {
        if r.calls > 0 && r.puts > 0 { return "both assigned" }
        if r.calls > 0 {
            if r.callLegs == 1 { return "call assigned" }
            if r.calls == r.callLegs { return r.callLegs == 2 ? "both calls assigned" : "all calls assigned" }
            return r.calls == 1 ? "first call assigned" : "\(r.calls) calls assigned"
        }
        if r.puts > 0 {
            if r.putLegs == 1 { return "put assigned" }
            if r.puts == r.putLegs { return r.putLegs == 2 ? "both sets assigned" : "all sets assigned" }
            return r.puts == 1 ? "first set assigned" : "\(r.puts) sets assigned"
        }
        let n = r.callLegs + r.putLegs
        /* With one leg there is no "both", and "it expires" makes the reader go
           back up the card to find out what "it" was. Name the leg. */
        if n == 1 { return r.callLegs == 1 ? "the call expires" : "the put expires" }
        return n == 2 ? "both expire" : "all expire"
    }
}
