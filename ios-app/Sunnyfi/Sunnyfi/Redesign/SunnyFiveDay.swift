//
//  SunnyFiveDay.swift
//  Sunny — the 5-day price card, L. cards/five-day-price.md is normative.
//
//  ⚠ IT IS NEVER A FEATURED CARD. The sheet says so in Feed integration and Nik
//  said the same thing when he sent it: "it wont be sitting in featured but on
//  each ticker." A price week is not on a clock — nothing about it expires, and
//  nothing about it asks for a decision — so it starts in its name's section and
//  stays there. One per holding, every holding.
//
//  ⚠ BARS ARE DAILY CHANGE AGAINST A ZERO LINE, NEVER PRICE LEVEL. Five price
//  levels at this size are five bars of near-identical height; the shape of the
//  week is the whole point of the card, and only change has a shape.
//
//  ⚠ NEWEST DAY FIRST, left to right, reading back into the past like every
//  other list in the app. Only the newest day's name is in ink.
//

import SwiftUI

// MARK: - the model, as the server sends it

struct FiveDay: Decodable {
    /// ⚠ OLDEST FIRST (26 Aug 2026), reversing five-day-price.md §0.2. That rule
    /// put the newest day on the left, "reading back into the past like every
    /// other list in the app" — but a chart is not a list. On a Friday it read
    /// cleanly as Fri Thu Wed Tue Mon; on any other weekday the weekend wraps and
    /// it came out Wed Tue Mon Fri Thu, which reads as random days rather than as
    /// time running backwards. Time now runs left to right like every price
    /// chart, and today lands at the right end where the eye finishes.
    let days: [Day]
    let from: Double         // the close BEFORE the oldest bar
    let to: Double
    let week_pct: Double
    let best: Double
    let worst: Double

    struct Day: Decodable {
        let day: String      // "Mon"
        let date: String
        let pct: Double
        let usd: Double
    }
}

// MARK: - the card

struct SunnyFiveDayCard: View {
    let ticker: String
    let m: FiveDay
    /// ⚠ PER NAME, NOT PER CARD (§6). The M and L cards for one ticker read the
    /// same flag and flip together, so the flag cannot live inside the card.
    @Binding var showPrice: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: S.gap7) {
            header
            chart
            Rectangle().fill(S.ruleColor).frame(height: S.rule)   // a child div, never a border
            footer
        }
        .padding(S.padCardM)
        .frame(width: S.content)
        .aspectRatio(S.Size.l.ratio, contentMode: .fit)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCardL)
        .contentShape(Rectangle())
        // The whole card is the target. A tap swaps the five values and changes
        // nothing else, so the card does not move under the finger.
        .onTapGesture { showPrice.toggle() }
        .measure("fiveday-card")
    }

    // MARK: header — 20.5

    /// Baseline, not centre: a 10px label and a 17px figure line up on nothing else.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
            SunnyCardHead(ticker: ticker, kind: "5 days")
            Spacer(minLength: 0)
            /* ⚠ OPENS LIGHT, CLOSES BOLD. The close is the LIVE price, so it is
               the answer and takes the one bold; the open is context. The pair
               is still not a direction — it is two prices — so neither end takes
               gain or loss ink.

               ⚠ AND THE ARROW IS --mute, NOT --faint. --faint measures 3.27:1 on
               white; it is documented for a 22px inactive tab label and nothing
               else, and at 17px in a light weight it was the least readable
               thing on the card. It is a mark, but a mark still has to be seen. */
            Text(rangeRuns).monospacedDigit()
        }
    }

    private var rangeRuns: AttributedString {
        var open = AttributedString(price(m.from))
        open.font = S.inter(S.t17, S.wLightN)
        open.foregroundColor = S.ink
        var arrow = AttributedString(" \u{2192} ")
        arrow.font = S.inter(S.t17, S.wMidSmN)
        arrow.foregroundColor = S.mute
        var close = AttributedString(price(m.to))
        close.font = S.inter(S.t17, S.wBoldN)
        close.foregroundColor = S.ink
        var all = open + arrow + close
        all.tracking = S.track(S.t17, -0.02)
        return all
    }

    // MARK: chart — the only flexible row

    private var chart: some View {
        HStack(spacing: S.fiveDayColGap) {
            ForEach(Array(m.days.enumerated()), id: \.offset) { i, d in
                /* The newest day is the LAST column now, not the first. */
                column(d, newest: i == m.days.count - 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func column(_ d: FiveDay.Day, newest: Bool) -> some View {
        let up = d.pct >= 0
        return VStack(spacing: S.gap4) {
            /* ⚠ THE VALUE SITS BELOW ITS BAR AND ABOVE ITS DAY NAME. It used to
               lead the column. Moving it down puts the two pieces of text that
               describe a day next to each other instead of splitting them around
               183px of chart, so a column reads as one label rather than two —
               and the bars now start from a common top edge, which makes the
               week's shape the first thing the eye lands on. */
            GeometryReader { g in
                let scale = scale(for: g.size.height)
                let zeroY = zeroY(for: g.size.height)
                let h = max(1, CGFloat(abs(d.pct)) * scale)
                ZStack(alignment: .topLeading) {
                    Color.clear
                    Rectangle().fill(S.ruleColor)
                        .frame(height: S.rule)
                        .offset(y: zeroY)
                    UnevenRoundedRectangle(
                        topLeadingRadius:     up ? S.fiveDayBarRadius : S.fiveDayBarRadiusFlat,
                        bottomLeadingRadius:  up ? S.fiveDayBarRadiusFlat : S.fiveDayBarRadius,
                        bottomTrailingRadius: up ? S.fiveDayBarRadiusFlat : S.fiveDayBarRadius,
                        topTrailingRadius:    up ? S.fiveDayBarRadius : S.fiveDayBarRadiusFlat,
                        style: .continuous)
                        .fill(up ? S.gainBar : S.lossBar)
                        .frame(height: h)
                        .offset(y: up ? zeroY - h : zeroY)
                }
                .frame(width: g.size.width, height: g.size.height)
            }

            // A SERIES IS NOT AN ANSWER: five values stay 600. Bolding all five
            // would bold nothing.
            Text(showPrice ? signedUSD(d.usd) : signedPct(d.pct))
                .font(InkFont.display(S.fiveDayValue, S.wSemi))
                .foregroundStyle(up ? S.gainText : S.lossText)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(height: S.fiveDayValue)

            Text(d.day)
                .font(S.inter(S.t12, newest ? S.wBoldN : S.wMidSmN))
                .foregroundStyle(newest ? S.ink : S.mute)
                .frame(height: S.fiveDayNameH)
        }
    }

    // MARK: footer — 36

    private var footer: some View {
        HStack(spacing: 0) {
            cell("Best day", m.best, pad: 0)
            Rectangle().fill(S.ruleColor).frame(width: S.rule)
            cell("Worst day", m.worst, pad: S.fiveDayCellPad)
            Rectangle().fill(S.ruleColor).frame(width: S.rule)
            cell("On the week", m.week_pct, pad: S.fiveDayCellPad)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// All three are DERIVED from the five days, never authored, and all three
    /// take direction ink because each one is a direction.
    private func cell(_ label: String, _ v: Double, pad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: S.fiveDayCellGap) {
            Text(label)
                .font(InkFont.display(S.fiveDayLabel, S.wBold))
                .tracking(S.track(S.fiveDayLabel, S.lsLabel))
                .foregroundStyle(S.mute)
            // Each of the three IS an answer, so all three are bold — unlike
            // the five day values, which are a series.
            Text(signedPct(v))
                .font(S.inter(S.t19, S.wBoldN))
                .tracking(S.track(S.t19, -0.025))
                .foregroundStyle(v >= 0 ? S.gain : S.loss)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The first cell carries none: its label has to start on the card's own
        // padding, not 16 inside it.
        .padding(.leading, pad)
    }

    // MARK: the derived scale

    /* ⚠ RE-DERIVED FROM THE DATA, EVERY TIME. The sheet's `top: 116` belongs to
       the week it was measured on. What is constant is the CONSTRAINT: the space
       above zero clears the largest up move, the space below clears the largest
       down move, and the tallest bar at each end keeps --five-day-headroom of
       air. Pin the 116 instead and the first week with a bigger drop draws a bar
       through the floor of its box. */
    private var maxUp: Double { max(0, m.days.map(\.pct).max() ?? 0) }
    private var maxDown: Double { max(0, -(m.days.map(\.pct).min() ?? 0)) }

    private func scale(for area: CGFloat) -> CGFloat {
        let span = maxUp + maxDown
        guard span > 0 else { return 0 }
        let usable = max(1, area - S.fiveDayHeadroom * 2)
        return usable / CGFloat(span)
    }

    private func zeroY(for area: CGFloat) -> CGFloat {
        // All five up: zero sits on the floor. All five down: it sits on the
        // ceiling. Both are correct and both fall out of this without a branch.
        guard maxUp + maxDown > 0 else { return area / 2 }
        return S.fiveDayHeadroom + CGFloat(maxUp) * scale(for: area)
    }

    // MARK: formatting

    /// U+2212, never a hyphen — it has to align in a tabular column.
    private func signedPct(_ v: Double) -> String {
        (v < 0 ? "\u{2212}" : "+") + String(format: "%.2f", abs(v)) + "%"
    }
    private func signedUSD(_ v: Double) -> String {
        (v < 0 ? "\u{2212}" : "+") + "$" + String(format: "%.2f", abs(v))
    }
    private func price(_ v: Double) -> String { String(format: "%.2f", v) }
}
