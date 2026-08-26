//
//  SunnyLegCard.swift
//  Sunny — the position leg card, L. cards/position-leg.md is normative.
//
//  ⚠ ONE LEG, ONE CARD. NO TABS, NO DRILL-IN, NO REGION. The card has no states,
//  so there is nothing to transition — and that is the fix for the jerkiness,
//  not easing curves. The retired region animated its own height, picked one of
//  three grids from the leg count, and claimed opacity/transform/transition on
//  cards the feed reveal was also writing. These shells claim none of the three.
//
//  ⚠ A BAR IS THE WEEK'S CHANGE IN P&L. This amends the old "cash that moved
//  that week" rule, which fails on the commonest case: a sold put held to expiry
//  moves cash ONCE, on the day it was sold, so three of four weeks would be
//  empty. P&L change exists every week for every leg type — decay for a sold
//  leg, mark for a bought one, price times quantity for shares — so all five
//  cards share one axis definition.
//
//  ⚠ SCALES ARE PER-CARD AND NOT COMPARABLE. Each card derives its own zero
//  line from its own weeks. A 110pt bar is +$2,100 on shares and +$210 on calls
//  bought. Every bar prints its value, and these five never go in a compare view.
//

import SwiftUI

struct LegWeek: Decodable, Identifiable {
    let label: String
    let live: Bool
    let pnl: Int
    var id: String { label }
}

struct SunnyLegCard: View {
    let ticker: String
    let name: String          // "shares", "puts sold"
    let contract: String      // "10 × 82 · Dec 19" or "1,100 at 82.48"
    let weeks: [LegWeek?]     // nil = the leg did not exist that week
    let fourWeeks: Int
    let sinceOpen: Int
    /// LEFT for an option, HELD for shares. Same job — time on the position —
    /// and shares simply have no expiry. Never blank, never an em dash.
    let timeLabel: String
    let timeValue: String
    /// Percent is of cash committed for this leg. A cheap leg swings hard.
    let committed: Int
    @Binding var showPct: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: S.gap7) {
            header
            chart
            Rectangle().fill(S.ruleColor).frame(height: S.rule)
            footer
        }
        .padding(S.padCardM)
        .frame(width: S.content)
        .aspectRatio(S.Size.l.ratio, contentMode: .fit)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCardL)
        .contentShape(Rectangle())
        /* Each card owns its OWN toggle. A shared handler makes a tap on one
           card silently swap another — the reference DC keeps the legs on
           `toggleLegUnit`, deliberately separate from the 5-day card's. */
        .onTapGesture { showPct.toggle() }
        .measure("leg-card")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
            SunnyCardHead(ticker: ticker, kind: name)
            Spacer(minLength: 0)
            Text(contract)
                .font(S.inter(S.t12, S.wMidSmN))
                .foregroundStyle(S.ink2)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    // MARK: chart — four columns, the only flexible row

    private var chart: some View {
        HStack(spacing: S.legColGap) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, w in
                column(w)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func column(_ w: LegWeek?) -> some View {
        let up = (w?.pnl ?? 0) >= 0
        VStack(spacing: S.gap4) {
            GeometryReader { g in
                let zeroY = zeroY(for: g.size.height)
                let h = w == nil ? 0 : max(1, CGFloat(abs(w!.pnl)) * scale(for: g.size.height))
                ZStack(alignment: .topLeading) {
                    Color.clear
                    Rectangle().fill(S.ruleColor)
                        .frame(height: S.rule).offset(y: zeroY)
                    if let w, h > 0 {
                        bar(up: up, live: w.live)
                            .frame(height: h)
                            /* ⚠ THE UP BAR'S BOTTOM LANDS ONE PIXEL PAST THE
                               ZERO LINE — at exactly the line it reads as
                               floating above it, one past and it visibly SITS
                               on it.

                               The sheet writes that as `bottom: 68`, which is a
                               constant only because the reference card's zero is
                               at 116 in a 185 area. Take it literally on a card
                               whose zero is derived and the bar detaches: this
                               leg has one week of data, so its zero sits near
                               the floor, and `area − 68 − h` came out NEGATIVE
                               and drew the bar up through the header. The DC's
                               own calls-sold card proves the rule rather than
                               the number — zero 60, bottom 124, 185 − 124 = 61. */
                            .offset(y: up ? zeroY + S.rule - h : zeroY)
                    }
                }
                .frame(width: g.size.width, height: g.size.height)
            }
            /* The value sits BELOW its bar and directly above its label, so the
               two pieces of text describing a week read as one unit. Four values
               are a SERIES, so they stay 600 — except the live week, which is
               bold because it is the one week still moving. */
            Text(w == nil ? "" : (showPct ? pctText(w!.pnl) : signed(w!.pnl)))
                .font(S.inter(S.t13, (w?.live ?? false) ? S.wBoldN : S.wSemiN))
                .foregroundStyle(up ? S.gainText : S.lossText)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(height: S.t13)
            Text(w?.label ?? "")
                .font(S.inter(S.t12, (w?.live ?? false) ? S.wBoldN : S.wMidSmN))
                .foregroundStyle((w?.live ?? false) ? S.ink : S.mute)
                .frame(height: S.t12)
        }
    }

    /// ⚠ HATCHED AT FULL DENSITY, NEVER A LIGHTER FILL. --gain-bar is 3.11:1 on
    /// white, essentially at the non-text threshold, so EVERY green lighter than
    /// it fails 3:1 — a lighter live bar measured 2.07:1 and made the card's own
    /// premise its faintest mark. On a white ground a provisional signal cannot
    /// be lightness; it has to be pattern.
    @ViewBuilder
    private func bar(up: Bool, live: Bool) -> some View {
        let ink = up ? S.gainBar : S.lossBar
        let shape = UnevenRoundedRectangle(
            topLeadingRadius:     up ? S.fiveDayBarRadius : S.fiveDayBarRadiusFlat,
            bottomLeadingRadius:  up ? S.fiveDayBarRadiusFlat : S.fiveDayBarRadius,
            bottomTrailingRadius: up ? S.fiveDayBarRadiusFlat : S.fiveDayBarRadius,
            topTrailingRadius:    up ? S.fiveDayBarRadius : S.fiveDayBarRadiusFlat,
            style: .continuous)
        if live {
            shape.fill(ink).overlay {
                Canvas { ctx, size in
                    // 6pt stripe on a 3pt gap at 135°, in the card's ground.
                    var x = -size.height
                    while x < size.width + size.height {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x + size.height, y: size.height))
                        ctx.stroke(p, with: .color(S.paper), lineWidth: S.hatchGap)
                        x += S.hatchStripe + S.hatchGap
                    }
                }
                .allowsHitTesting(false)
            }
            .clipShape(shape)
        } else {
            shape.fill(ink)
        }
    }

    // MARK: footer — three stats

    private var footer: some View {
        HStack(spacing: 0) {
            cell("4 weeks", signed(fourWeeks), fourWeeks >= 0 ? S.gain : S.loss, pad: 0)
            Rectangle().fill(S.ruleColor).frame(width: S.rule)
            cell("Since open", signed(sinceOpen), sinceOpen >= 0 ? S.gain : S.loss, pad: S.fiveDayCellPad)
            Rectangle().fill(S.ruleColor).frame(width: S.rule)
            // Neutral ink: time is not a direction.
            cell(timeLabel, timeValue, S.ink, pad: S.fiveDayCellPad)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func cell(_ label: String, _ value: String, _ ink: Color, pad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: S.fiveDayCellGap) {
            Text(label)
                .font(InkFont.display(S.t10, S.wBold))
                .tracking(S.track(S.t10, S.lsLabel))
                .textCase(.uppercase)
                .foregroundStyle(S.mute)
            Text(value)
                .font(S.inter(S.t19, S.wBoldN))
                .tracking(S.track(S.t19, -0.025))
                .foregroundStyle(ink)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, pad)
    }

    // MARK: the scale, re-derived from this card's own weeks

    private var vals: [Int] { weeks.compactMap { $0?.pnl } }
    private var maxUp: CGFloat { CGFloat(max(0, vals.max() ?? 0)) }
    private var maxDown: CGFloat { CGFloat(max(0, -(vals.min() ?? 0))) }

    private func scale(for area: CGFloat) -> CGFloat {
        let span = maxUp + maxDown
        guard span > 0 else { return 0 }
        return max(1, area - S.fiveDayHeadroom * 2) / span
    }
    private func zeroY(for area: CGFloat) -> CGFloat {
        guard maxUp + maxDown > 0 else { return area / 2 }
        return S.fiveDayHeadroom + maxUp * scale(for: area)
    }

    private func pctText(_ v: Int) -> String {
        guard committed > 0 else { return signed(v) }
        let p = Double(v) / Double(committed) * 100
        return (p < 0 ? "\u{2212}" : "+") + String(format: "%.1f", abs(p)) + "%"
    }
}

// MARK: - the five, in fixed order

/// Shares, then puts sold, calls sold, puts bought, calls bought. A leg with no
/// contracts produces no card — not an empty one.
///
/// ⚠ BOUGHT AND SOLD STAY SEPARATE CARDS. They are opposite exposures and
/// netting them hides the structure. The only case for combining two legs is a
/// TRUE spread — same ticker, same expiry, same type — where they only make
/// sense together.
struct SunnyLegCards: View {
    let p: LegsPosition?
    @Binding var units: Set<String>

    var body: some View {
        if let p {
            SunnyLegCard(
                ticker: p.ticker, name: "shares",
                contract: p.shares.contract,
                weeks: p.shares.weeks,
                fourWeeks: p.shares.weeks.compactMap { $0?.pnl }.reduce(0, +),
                sinceOpen: p.shares.pnl,
                timeLabel: "Held", timeValue: "\(p.shares.held)d",
                committed: p.shares.basis,
                showPct: bind("\(p.ticker)|SH"))
            ForEach(p.legs) { l in
                SunnyLegCard(
                    ticker: p.ticker, name: l.label.lowercased(),
                    contract: l.contract,
                    weeks: l.weeks,
                    fourWeeks: l.weeks.compactMap { $0?.pnl }.reduce(0, +),
                    sinceOpen: l.pnl,
                    timeLabel: "Left", timeValue: "\(l.dte)d",
                    committed: l.committed,
                    showPct: bind("\(p.ticker)|\(l.code)"))
            }
        }
    }

    private func bind(_ key: String) -> Binding<Bool> {
        Binding(get: { units.contains(key) },
                set: { on in if on { units.insert(key) } else { units.remove(key) } })
    }
}
