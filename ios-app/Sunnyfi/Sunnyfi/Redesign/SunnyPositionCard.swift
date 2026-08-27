//
//  SunnyPositionCard.swift
//  Sunny — one card for the whole position. cards/tlt-position.md is normative.
//
//  ⚠ ONE CARD, NOT FIVE. This supersedes the five per-leg cards (26 Aug 2026) and
//  the tabbed drill-in region before them. The five failed for a reason their own
//  build sheet had already written down: the scales were not comparable, so
//  shares showing a loss beside calls showing a profit could not be reconciled by
//  the reader. Nik: "I feel it looses the story."
//
//  ⚠ LEGS THAT DISAGREE IN SIGN ONLY MAKE SENSE AS CONTRIBUTIONS TO ONE TOTAL.
//  So the card gives one figure (the position since open) and one chart (every
//  leg SUMMED per week, which is a single comparable scale). Nothing per-leg
//  appears, and that absence is the design rather than an omission.
//
//  ⚠ DOLLARS ONLY, NO UNIT TOGGLE. A percentage per leg is against a different
//  base each time, and that non-comparability is exactly what this card exists to
//  remove. Do not re-add the toggle the leg cards carried.
//

import SwiftUI

struct SunnyPositionCard: View {
    let p: LegsPosition

    /// Every leg summed, week by week. A week is nil only when NO leg reported
    /// one, which is a week the position did not exist — distinct from a real
    /// zero, and the column renders empty rather than flat.
    private struct Week: Identifiable {
        let label: String, live: Bool, pnl: Int
        var id: String { label }
    }

    /* ⚠ THE SERVER'S POSITION SERIES, NEVER THE PER-LEG ONES SUMMED. Summing
       here looked equivalent and was not: the per-leg arrays only cover legs
       that are still open, so a leg that expired inside the window contributed
       nothing to the week it lived and died in. NKE's week of 17 Aug came out
       −$1,668 — shares +$32 and a long put's decay — while the 20 calls sold at
       0.61 and the 20 puts sold at 0.60 that expired that Friday were not in the
       payload at all. Both halves now come from one identity server-side, where
       the expired legs are visible. */
    private var weeks: [Week] {
        (p.weeks ?? []).compactMap { w in
            guard let w else { return nil }
            return Week(label: w.label, live: w.live, pnl: w.pnl)
        }
    }

    /* ⚠ THE ROWS ARE PROPORTIONAL, NEVER FIXED-HEIGHT. Fixed heights inside a
       flexible parent leave the parent to absorb the slack, and at one point 140
       of the chart was dead space split above and below by centring. The split is
       max positive against max negative, so the zero line sits where the DATA
       puts it and both extremes reach their edge. Change the data and these two
       numbers change with it; nothing else does. */
    private var maxUp: Double { Double(max(0, weeks.map(\.pnl).max() ?? 0)) }
    private var maxDown: Double { Double(abs(min(0, weeks.map(\.pnl).min() ?? 0))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            /* No caption beside the figure. "since open, all five legs" was built
               and removed: it restated what the card is, and the leg count is
               already in the pill. */
            Text(signed(p.total))
                .font(S.inter(S.t34, S.wBoldN))
                .tracking(S.track(S.t34, S.lsTighter))
                .foregroundStyle(p.total < 0 ? S.loss : S.gain)
                .monospacedDigit()
                .sunnyLineBox(S.t34)
                .padding(.top, S.posFigureTop)
            chart
        }
        .padding(S.padCardM)
        .frame(width: S.content)
        .aspectRatio(S.Size.l.ratio, contentMode: .fit)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCardL)
        .measure("position-card")
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: S.gap6) {
            HStack(alignment: .firstTextBaseline, spacing: S.headingGap) {
                Text(p.ticker)
                    .font(S.inter(S.t15, S.wBoldN))
                    .tracking(S.track(S.t15, -0.01))
                Text("position")
                    .font(S.inter(S.t15, S.wLightN))
                    .tracking(S.track(S.t15, -0.01))
            }
            .foregroundStyle(S.ink)
            Spacer(minLength: 0)
            /* An OUTLINE, never a fill. A filled pill at this size outweighs the
               ticker beside it. The count is shares plus every option leg. */
            Text("\(1 + p.legs.count) legs".uppercased())
                .font(S.inter(S.t10, S.wBoldN))
                .tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute)
                .padding(.vertical, S.posPillPadV)
                .padding(.horizontal, S.posPillPadH)
                .overlay(Capsule().strokeBorder(S.hair, lineWidth: 1))
        }
    }

    // MARK: chart

    private var chart: some View {
        VStack(spacing: S.posChartGap) {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    bars(geo.size.height, up: true)
                        .frame(height: rowH(geo.size.height, up: true))
                    /* ⚠ ONE CONTINUOUS RULE, never one segment per column. Drawn
                       inside each bar column it came out in four pieces with
                       three gaps, which reads as four mini-charts — the exact
                       fragmentation this card replaced. */
                    Rectangle().fill(S.hair)
                        .frame(height: S.rule)
                    bars(geo.size.height, up: false)
                        .frame(height: rowH(geo.size.height, up: false))
                }
            }
            labels
        }
        .padding(.top, S.posChartPadTop)
        .padding(.bottom, S.posChartPadBottom)
        .frame(maxHeight: .infinity)
    }

    private func rowH(_ total: CGFloat, up: Bool) -> CGFloat {
        let usable = max(0, total - S.rule)
        let span = maxUp + maxDown
        guard span > 0 else { return up ? usable : 0 }
        return usable * CGFloat((up ? maxUp : maxDown) / span)
    }

    private func bars(_ total: CGFloat, up: Bool) -> some View {
        let row = rowH(total, up: up)
        let peak = up ? maxUp : maxDown
        return HStack(alignment: up ? .bottom : .top, spacing: S.posBarGap) {
            ForEach(weeks) { w in
                /* A column with no bar on this side of the line renders an EMPTY
                   cell, not a zero-height bar — the cell holds the column's width
                   so the labels below stay aligned with the bars above. */
                let mine = up ? w.pnl > 0 : w.pnl < 0
                let h = (peak > 0 && mine)
                    ? row * CGFloat(Double(abs(w.pnl)) / peak) : 0
                ZStack(alignment: up ? .bottom : .top) {
                    Color.clear
                    if mine { bar(w, height: h, up: up) }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func bar(_ w: Week, height: CGFloat, up: Bool) -> some View {
        let ink = w.pnl < 0 ? S.lossBar : S.gainBar
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: up ? S.posBarRadius : 0,
            bottomLeadingRadius: up ? 0 : S.posBarRadius,
            bottomTrailingRadius: up ? 0 : S.posBarRadius,
            topTrailingRadius: up ? S.posBarRadius : 0,
            style: .continuous)
        /* ⚠ THE LIVE WEEK IS HATCHED AT FULL BAR DENSITY, never a lighter fill.
           --gain-bar is 3.11:1 on white, so every green lighter than it fails
           3:1; the lighter version measured 2.07:1 and made the card's own live
           figure its faintest mark. The 1px inset ring keeps the hatched bar's
           edge readable where the stripes meet the ground. */
        if w.live {
            shape.fill(.clear)
                .overlay { SunnyHatch(ink: ink).clipShape(shape) }
                .overlay(shape.strokeBorder(ink, lineWidth: 1))
                .frame(width: S.posBarW, height: height)
        } else {
            shape.fill(ink).frame(width: S.posBarW, height: height)
        }
    }

    private var labels: some View {
        HStack(alignment: .top, spacing: S.posBarGap) {
            ForEach(weeks) { w in
                VStack(spacing: S.gap2) {
                    /* The -text ladder step, not --gain/--loss: at 13px those are
                       the 12-14px steps. Only the 34px figure is large enough for
                       --gain. */
                    Text(signed(w.pnl))
                        .font(S.inter(S.t13, S.wBoldN))
                        .tracking(S.track(S.t13, -0.01))
                        .foregroundStyle(w.pnl < 0 ? S.lossText : S.gainText)
                        .monospacedDigit()
                        .sunnyLineBox(S.t13)
                    /* The live week's date is the one 700 in the row — it marks
                       which column is incomplete, so the hatch is not the only
                       carrier of that fact. */
                    Text(w.live ? "Live" : w.label)
                        .font(S.inter(S.t11, w.live ? S.wBoldN : S.wMidSmN))
                        .foregroundStyle(w.live ? S.ink : S.mute)
                        .sunnyLineBox(S.t11)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// 45° stripes at full bar ink. A `repeating-linear-gradient` has no SwiftUI
/// equivalent, so it is drawn.
///
/// ⚠ `nonisolated` IS REQUIRED. Under Swift's default main-actor isolation a
/// `Shape` conformance fails to build without it, because `path(in:)` is
/// nonisolated in the protocol.
struct SunnyHatch: View {
    let ink: Color

    var body: some View {
        Canvas { ctx, size in
            let step = S.posHatchStripe + S.posHatchGap
            let reach = size.width + size.height
            var x = -size.height
            while x < reach {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                ctx.stroke(p, with: .color(ink),
                           style: StrokeStyle(lineWidth: S.posHatchStripe))
                x += step
            }
        }
    }
}

// MARK: - the fan-out

/// What a name page shows for its position: one card for the legs.
///
/// ⚠ THE PUT FLOOR CARDS ARE RETIRED (27 Aug 2026). Nik: "we have a put floor
/// card that we need to remove. Remove all the put floor card." The floor's own
/// facts did not go with it — every put bought is a row on the puts bought list
/// and an M on its name's page, carrying the strike, the size, the expiry, the
/// distance to spot and what the cover has cost. What the floor card added on
/// top of that was a drawn band, and a band is a graphic where a number would
/// do. `floors` is still decoded from position-legs and still served: ONE
/// BACKEND, TWO CLIENTS, and the build already on his phone reads it.
struct SunnyPositionCards: View {
    let p: LegsPosition?

    var body: some View {
        if let p { SunnyPositionCard(p: p) }
    }
}
