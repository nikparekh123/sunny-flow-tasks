//
//  SunnyTickerCard.swift
//  Sunny — one ticker, one card. cards/ticker-card.md.
//
//  ⚠ THE TRANSPOSE OF THE SIX SUMMARY LISTS. A list holds one metric across many
//  names; this holds one name across many metrics. It replaces the five M cards,
//  which were one card per name PER METRIC — five cards to read one name, and a
//  page full of singletons. Nik, 27 Aug: "when I see the individual cards inside
//  each ticker, I just don't think they make a lot of sense."
//
//  ⚠ THE ROW IS THE SUMMARY LIST ROW WITH THE AXIS SWAPPED. The ticker moves to
//  the header; the METRIC takes the subject slot. Figure and support keep their
//  type, their inks and their rules exactly. Nothing here is a new design.
//
//  ⚠ METRIC ORDER IS THE SIX-LIST ORDER AND IS NEVER RE-RANKED — net delta,
//  average price, performance, then the option legs. On a list, exceptions float
//  to the top; here the six-list sequence is the spine, so a flagged row stays
//  where it belongs and the dot column does the work alone.
//
//  ⚠ A METRIC THE NAME DOES NOT HAVE IS A MISSING ROW, NEVER AN EMPTY ONE.
//  Nothing on the card announces an absence.
//

import SwiftUI

struct SunnyTickerCard: View {
    let b: BookName
    /// UNREALIZED, from position-legs, so this row and the page heading above it
    /// can never disagree.
    let current: Int?
    let allTime: Int?
    let callsSold: [OptionRow]
    let putsSold: [OptionRow]
    let putsBought: [OptionRow]

    private struct Metric: Identifiable {
        let id: String
        let label: String
        let figure: String
        let figureLoss: Bool
        let support: [(String, Bool)]
        let flagged: Bool
    }

    private var metrics: [Metric] {
        var out: [Metric] = []
        if let d = b.delta {
            out.append(Metric(
                id: "delta", label: "Net delta",
                figure: signedBare(d.net) + " sh", figureLoss: d.net < 0,
                support: [(d.change.map { $0 == 0 ? "unchanged" : "\(signedBare($0)) since yest" }
                            ?? "$\(money(d.exposure)) exposure", false)],
                flagged: d.short))
        }
        if let a = b.avg {
            let above = a.vsSpot > 0
            out.append(Metric(
                id: "avg", label: "Average price",
                figure: sPrice(a.average), figureLoss: false,
                support: [
                    ("\(sPct(abs(a.vsSpot))) \(above ? "above" : "below") spot", above),
                    ("$\(sPrice(abs(a.paid - a.average))) off \(sPrice(a.paid)) paid", false),
                ],
                flagged: above))
        }
        if let c = current {
            /* Yield is premium on what was invested, read off the same vs_paid
               the average row above uses. Premium that RAISED the average is not
               a negative yield, it is no yield. */
            let y = b.avg.map { -$0.vsPaid } ?? 0
            out.append(Metric(
                id: "perf", label: "Performance",
                figure: sK(c), figureLoss: c < 0,
                support: [
                    (allTime.map { "\(sK($0)) all time" } ?? "no history", false),
                    (y > 0.05 ? "\(sPct(y)) yield" : "no yield", false),
                ],
                flagged: c < 0))
        }
        /* One row per LEG, so a name with two strikes of one kind gets two rows.
           Netting them would print a strike that does not exist. */
        for (rows, label) in [(callsSold, "Call sold"), (putsSold, "Put sold"),
                              (putsBought, "Put bought")] {
            for r in rows where r.ticker == b.ticker {
                out.append(Metric(
                    id: "\(label)|\(r.strike)|\(r.expiry)", label: label,
                    figure: sPrice(r.strike), figureLoss: false,
                    support: [
                        (abs(r.moneyness) < 0.5 ? "ATM"
                            : "\(sPct(abs(r.moneyness))) \(r.itm ? "ITM" : "OTM")", r.exception),
                        ("\(r.contracts)× \(expShort(r.expiry))", false),
                        ("$\(money(r.opened)) → $\(money(r.now))", false),
                    ],
                    flagged: r.exception))
            }
        }
        return out
    }

    var body: some View {
        let m = metrics
        let flags = m.filter(\.flagged).count
        VStack(alignment: .leading, spacing: 0) {
            /* ⚠ SPOT IS STATED ONCE, FOR THE WHOLE CARD. No row repeats it —
               that is what makes every percentage on the card auditable, the
               same reason the retired M printed spot beside the average. */
            HStack(alignment: .firstTextBaseline, spacing: S.gap5) {
                Text(b.ticker)
                    .font(S.inter(S.t20, S.wSemiN))
                    .tracking(S.track(S.t20, -0.01))
                    .foregroundStyle(S.ink)
                if let spot = b.avg?.spot ?? b.exercise?.spot {
                    Text("spot \(sPrice(spot))")
                        .font(S.inter(S.t13, S.wMidSmN))
                        .foregroundStyle(S.mute2)
                }
                Spacer(minLength: 0)
                /* ⚠ AN EMPTY EXCEPTION SLOT IS A GREY WORD, NEVER AN ABSENCE. */
                Text((flags > 0 ? "\(flags) flagged" : "Nothing flagged").uppercased())
                    .font(S.inter(S.t10, S.wSemiN))
                    .tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(flags > 0 ? S.lossText : S.mute)
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
                ForEach(m) { row($0) }
            }
            .padding(.horizontal, S.padListX)

            Color.clear.frame(height: 19)
        }
        .frame(width: S.content)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCardL)
        .monospacedDigit()
        .measure("ticker-\(b.ticker)")
    }

    @ViewBuilder
    private func row(_ m: Metric) -> some View {
        VStack(alignment: .leading, spacing: S.tileCornerGap) {
            /* The dot gutter is reserved on every row, empty when the metric is
               ordinary, so every label starts 28 in from the card edge. */
            HStack(spacing: 6) {
                Circle().fill(m.flagged ? S.loss : .clear).frame(width: 5, height: 5)
                Text(m.label.uppercased())
                    .font(S.inter(S.t10, S.wSemiN))
                    .tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.mute)
                    .sunnyLineBox(S.t10)
            }
            HStack(alignment: .center, spacing: S.gap6) {
                /* ⚠ 26, NOT THE LIST ROW'S 20. The 20 exists because a list
                   row's figure shares its line with a 20px ticker and the two
                   must read as equals. Here there is no ticker in the row — the
                   figure is the only number in the tile. */
                Text(m.figure)
                    .font(S.inter(S.t26, S.wSemiN))
                    .tracking(S.track(S.t26, S.lsTight))
                    .foregroundStyle(m.figureLoss ? S.loss : S.ink)
                    .sunnyLineBox(S.t26)
                    .fixedSize()
                /* Support keeps the list row's RIGHT alignment, unlike the
                   ladder: the five stacks on this card do form a column against
                   each other, which is the argument that right-aligns them on a
                   list. */
                VStack(alignment: .trailing, spacing: S.supportLineGap) {
                    ForEach(Array(m.support.enumerated()), id: \.offset) { _, l in
                        Text(l.0)
                            .font(S.inter(S.t13, S.wMidSmN))
                            .foregroundStyle(l.1 ? S.lossText : S.mute2)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(height: S.t13 * S.lhSupport)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(S.padTileCorner)
        /* ⚠ FIXED, NOT MIN. Every row is 109 whatever its support count: five
           metrics stacked read as a ledger, and a ragged stack of five is noise
           the list cards never had to carry. The body row takes the slack, so a
           one-line support still centres its figure against a three-line one. */
        .frame(width: S.content - S.padListX * 2, height: S.tileCornerRowH, alignment: .leading)
        .background(S.tileGround)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusTile, style: .continuous))
    }
}
