//
//  SunnyNewCards.swift
//  Sunny — the five cards on the New page.
//  cards/news-lead.md · analyst-action.md · median-target.md ·
//  earnings-guidance.md · the-drift.md
//
//  ⚠ A RATING CHANGE TAKES NO DIRECTION INK, AND NEITHER DOES A COUNT OF THEM.
//  Red in this deck is money the book lost; an analyst's opinion is not that.
//  The target pair is --ink like a strike, the WORD carries direction, and the
//  drift bar is --ink on --wash. An earlier build shipped `buy → hold` in
//  --loss-text and it read as the position losing money.
//
//  ⚠ AND THAT IS WHAT FREES THE 5px DOT for the one thing here worth a colour:
//  the vendor's importance flag. When the flag is absent the SLOT STAYS, so
//  every row's ticker sits on one left edge.
//

import SwiftUI

/// The shared shell. Every card on this page is free height, 21 inside.
private struct NewCard<Content: View>: View {
    let name: String
    var shadow: [SunnyShadow] = S.shadowCard
    @ViewBuilder let body_: () -> Content

    var body: some View {
        body_()
            .frame(width: S.content)
            .background(S.paper)
            .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
            .sunnyShadow(shadow)
            .monospacedDigit()
            .measure(name)
    }
}

// MARK: - 4 · earnings & guidance

/// ⚠ ROWS, NOT TILES — THEY ARE CONDITIONS, NOT ANSWERS. A date and a bound are
/// things that are true until they change; a tile grid says "compare these".
struct SunnyEarningsCard: View {
    let e: EarningsBlock

    var body: some View {
        NewCard(name: "earnings-guidance") {
            VStack(spacing: 0) {
                ForEach(Array(e.rows.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Rectangle().fill(S.ruleColor).frame(height: 1) }
                    HStack(alignment: .top, spacing: S.gap6) {
                        Text(r.ticker)
                            .font(S.inter(S.t14, S.wSemiN))
                            .foregroundStyle(S.ink)
                            .frame(width: S.targetTickerSlot, alignment: .leading)
                        VStack(alignment: .leading, spacing: S.gap2) {
                            line(r)
                            if let s = r.support {
                                /* ⚠ THE ONLY RED IS A COLLISION THE BOOK KNOWS
                                   ABOUT, and the test is direction-aware: the
                                   same date inside a long put is protection. */
                                Text(s.text)
                                    .font(S.inter(S.t13, S.wMidSmN))
                                    .foregroundStyle(s.red ? S.lossText : S.mute2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if r.kind == "guidance" {
                                Text(guidanceSupport(r))
                                    .font(S.inter(S.t13, S.wMidSmN))
                                    .foregroundStyle(S.mute2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 15)
                }
            }
            .padding(EdgeInsets(top: 6, leading: S.padNewX, bottom: 8, trailing: S.padNewX))
        }
    }

    /// ⚠ THE COUNTDOWN IS THE BOLD, because it is the part that changes.
    @ViewBuilder private func line(_ r: EarningsBlock.Row) -> some View {
        if r.kind == "earnings", let d = r.days, let dt = r.line {
            (Text("Reports \(shortDate(String(dt.dropFirst(8)))), ")
                + Text("\(d) days").fontWeight(.semibold))
                .font(S.inter(S.t14, S.wMidSmN))
                .foregroundStyle(S.ink)
                .fixedSize(horizontal: false, vertical: true)
        } else if let lo = r.lo, let hi = r.hi {
            (Text("\(r.period ?? "") revenue ")
                + Text("\(bn(lo))\u{2013}\(bn(hi))").fontWeight(.semibold))
                .font(S.inter(S.t14, S.wMidSmN))
                .foregroundStyle(S.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// ⚠ A GUIDANCE FIGURE CARRIES ITS BASIS AND BOTH BOUNDS, and an absent
    /// guide is stated rather than omitted.
    private func guidanceSupport(_ r: EarningsBlock.Row) -> String {
        var out = [r.notes ?? "Guidance"]
        if let d = r.date { out.append(shortDate(d)) }
        out.append(r.method ?? "GAAP")
        out.append("guidance is quarterly")
        return out.joined(separator: " \u{00B7} ")
    }
    private func bn(_ v: Double) -> String {
        v >= 1e9 ? "$\(String(format: "%.2f", v / 1e9))bn"
                 : "$\(String(format: "%.0f", v / 1e6))m"
    }
}
