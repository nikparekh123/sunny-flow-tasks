//
//  SunnyAverage.swift
//  Sunny — the average price cards. average-price.md and average-combined.md.
//
//  Two cards, one number. The LIST goes on New in the morning and shows every
//  position at once; the COMBINED S card lives on each name's page. Nik:
//  "the full card comes on featured and then individual cards come on ticker."
//
//  ⚠ THE AVERAGE IS BUY PRICE MINUS PREMIUM WRITTEN, not minus realized. Chosen
//  by Nik on 26 Aug over docs/PNL_GLOSSARY.md's NEW AVERAGE, which subtracts
//  REALIZED instead. The two disagree hard on this book — NKE reads 37.79 UNDER
//  spot one way and 44.41 OVER it the other — and five of nine cards change
//  ground colour between them. This is the income sleeve's own number, the one
//  that walks down every week he writes, which is the thing the sleeve exists to
//  show. The glossary's version answers what Total already answers on the page
//  heading above these cards.
//
//  ⚠ EVERY PERCENTAGE NAMES ITS REFERENCE, AND `under` / `over` ARE WORDS. A
//  basis BELOW spot is good here, so a bare −5.4% would invert the deck's
//  red-is-negative reading. The two percentages also move independently — one is
//  premium against what he paid, the other is the result against the market — so
//  neither can be the silent default.
//

import SwiftUI

// MARK: - the list, free height, on New

/// ⚠ NO SIZE CLASS AND NO ASPECT RATIO. The position count varies, and the free
/// height is what pays for 22px figures: the card grows one row per position
/// rather than compressing the rhythm. A fixed 361 × 361 fits four rows and
/// clips the fifth. If a pane ever needs it shorter the answer is a shorter
/// LIST, never smaller type.
struct SunnyAverageList: View {
    let book: [BookName]

    private var rows: [(Int, BookName, BookAverage)] {
        book.enumerated().compactMap { i, b in
            guard let a = b.avg else { return nil }
            return (i + 1, b, a)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            /* ⚠ THE PADDING IS ON THE CHILDREN, NOT THE CARD. The rows block
               needs its own 19 so the separators run the full inner width; a
               card-level padding would inset them and leave each one floating
               short of the type above it. */
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, r in
                    row(r.0, r.1, r.2, last: idx == rows.count - 1)
                }
            }
            .padding(.horizontal, S.avgPadX)
            /* An empty spacer, deliberately. The last row carries no separator,
               so nothing marks the end of the list but air — this makes that air
               equal the header's top padding and the card closes symmetrically.
               It carries no content: a total under a list of separate averages
               would be a second definition of the word on the same card. */
            Color.clear.frame(height: S.avgFootH)
        }
        .frame(width: S.content)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCardL)
        .measure("average-list")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.gap5) {
            Text("Average price")
                .font(S.inter(S.t19, S.wSemiN))
                .tracking(S.track(S.t19, -0.025))
                .foregroundStyle(S.ink)
            Spacer(minLength: 0)
            /* "positions", not "tickers": a name held in two lots is one
               position with one combined average. */
            Text("\(rows.count) positions".uppercased())
                .font(S.inter(S.t10, S.wBoldN))
                .tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute)
                .sunnyLineBox(S.t10)
        }
        .padding(.top, S.avgHeadTop)
        .padding(.horizontal, S.avgPadX)
        .padding(.bottom, S.avgHeadBottom)
    }

    @ViewBuilder
    private func row(_ n: Int, _ b: BookName, _ a: BookAverage, last: Bool) -> some View {
        VStack(alignment: .leading, spacing: S.avgRowGap) {
            /* ⚠ WITHIN A LINE, HIERARCHY IS WEIGHT, NOT SIZE. Ticker and average
               are both 22, at 300 and 700. Sizing the name down turns it into a
               label, and it is the thing being scanned for. */
            HStack(alignment: .firstTextBaseline, spacing: S.gap5) {
                /* The index is the one cell that is not data — it counts — so it
                   takes the lightest weight and stays out of the tabbing. */
                Text("\(n)")
                    .font(S.inter(S.t16, S.wLightN))
                    .foregroundStyle(S.mute2)
                    .frame(width: S.avgIndexW, alignment: .leading)
                Text(b.ticker)
                    .font(S.inter(S.t22, S.wLightN))
                    .tracking(S.track(S.t22, -0.01))
                    .foregroundStyle(S.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                /* The average is --ink, never green. It is a cost basis, not a
                   direction; only the vs-spot cell takes a direction ink. */
                Text(money2(a.average))
                    .font(S.inter(S.t22, S.wBoldN))
                    .tracking(S.track(S.t22, -0.02))
                    .foregroundStyle(S.ink)
            }
            HStack(alignment: .firstTextBaseline, spacing: S.gap5) {
                Text("\(pct(a.vsPaid)) \(a.vsPaid <= 0 ? "below" : "above") \(money2(a.paid))")
                    .font(S.inter(S.t14, S.wMidSmN))
                    .foregroundStyle(S.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                /* ⚠ NOWRAP IN A FIXED CELL, ON PURPOSE. This is the only string
                   whose length is unpredictable. Wrapping would double the row
                   while leaving scrollHeight untouched, so the card-level
                   overflow check could never see it; clipping fails visibly. */
                Text(spotPhrase(a.vsSpot))
                    .font(S.inter(S.t14, S.wBoldN))
                    .foregroundStyle(a.vsSpot <= 0 ? S.gainText : S.lossText)
                    .lineLimit(1)
                    .frame(width: S.avgSpotW, alignment: .trailing)
            }
            /* The indent is the index column plus its gap, so both reference
               cells start on the ticker's spine and the index reads as a marker
               beside the block rather than a fourth column of data. */
            .padding(.leading, S.avgIndexW + S.gap5)
        }
        .padding(.vertical, S.avgRowPadY)
        .frame(width: S.content - S.avgPadX * 2, alignment: .leading)
        /* ⚠ THE SEPARATOR BELONGS TO THE ROW, and the last row carries none. An
           overlaid rule costs no height and is pinned to the row's own bottom
           edge, where a sibling divider takes a share of the stack's spacing on
           both sides and drifts off the line it divides. */
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(S.ruleColor).frame(height: S.rule) }
        }
    }
}

// MARK: - the combined card, S, one per name

/// ⚠ THE GROUND IS THE READING. `--gain-wash` while the average sits UNDER spot,
/// `--loss-wash` when it sits over. The colour is not decoration and not a
/// category, it is the answer — and it is what lets this be an S at all.
///
/// ⚠ THE CARD SHOWS THE ANSWER, NEVER THE DERIVATION. An earlier build was an L
/// showing both lots, the premium subtraction and a per-share column; all of it
/// existed to derive one figure that was already printed underneath it. Anything
/// that only explains how a number was reached belongs on a drill-down.
struct SunnyAverageCard: View {
    let ticker: String
    let a: BookAverage

    private var under: Bool { a.vsSpot <= 0 }
    /// On a saturated ground every ink is the one deep step. Nothing from the
    /// white list card carries over, and there is no third tier: a dimmer green
    /// measured under 4.5:1.
    private var ink: Color { under ? S.gainDeep : S.lossText }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap3) {
                Text(ticker)
                Spacer(minLength: 0)
                Text(a.lots == 1 ? "One lot" : "\(a.lots) lots")
            }
            .font(S.inter(S.t10, S.wBoldN))
            .tracking(S.track(S.t10, S.lsLabel))
            .textCase(.uppercase)
            .foregroundStyle(ink)
            .sunnyLineBox(S.t10)

            Spacer(minLength: 0)

            /* The figure and its reading are ONE unit and must never be split by
               the space-between slack. */
            VStack(alignment: .leading, spacing: S.gap3) {
                Text(money2(a.average))
                    .font(S.inter(S.avgFigure, S.wBoldN))
                    .tracking(S.track(S.avgFigure, S.lsTighter))
                    .foregroundStyle(ink)
                    /* line-height .9, not 1: at 1 the block runs 57 and the
                       slack falls to 60, which reads cramped rather than
                       composed. */
                    .sunnyLineBox(S.avgFigure * S.avgFigureLH)
                Text(spotPhrase(a.vsSpot))
                    .font(S.inter(S.t13, S.wBoldN))
                    .foregroundStyle(ink)
                    .sunnyLineBox(S.t13)
            }

            Spacer(minLength: 0)

            Text("\(a.shares.formatted(.number.grouping(.automatic))) sh · \(a.cost.formatted(.number.grouping(.automatic)))")
                .font(S.inter(S.t12, S.wMidSmN))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(S.padCard)
        .frame(width: S.col, height: S.col, alignment: .leading)
        .background(under ? S.gainWash : S.lossWash)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCard)
        .measure("average-card")
    }
}

// MARK: - shared

/// Two decimals, grouped. A basis is a price, so it never abbreviates.
private func money2(_ v: Double) -> String {
    v.formatted(.number.precision(.fractionLength(2)).grouping(.automatic))
}

private func pct(_ v: Double) -> String {
    String(format: "%.1f%%", abs(v))
}

/// ⚠ `under` / `over` IN WORDS, NEVER A SIGN. A basis below spot is GOOD here,
/// so a bare minus would read as bad and invert the whole deck's convention.
private func spotPhrase(_ vsSpot: Double) -> String {
    "\(pct(vsSpot)) \(vsSpot <= 0 ? "under" : "over") spot"
}
