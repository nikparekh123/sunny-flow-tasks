//
//  SunnySummaryM.swift
//  Sunny — the five M cards. summary-lists.md §10.
//
//  ⚠ THE M IS THE ROW ROTATED. The list answers *which of my names*; the M
//  answers *this name*. Same reading order, turned from horizontal to vertical:
//  subject on top, figure in the middle, support at the bottom. Nothing new is
//  said — an M is a row with room. Three rules the rotation forces:
//
//  1. SUPPORT IS LEFT-ALIGNED. In a row it is right-aligned because it must form
//     a column against six other rows. Alone there is nothing to align to, so it
//     hangs off the same left edge as the figure.
//  2. NO DOT. The 5px dot exists to indent one row out of seven; with no column
//     to break, a state becomes a WORD IN STATE INK, top right.
//  3. THE STATE WORD IS NEVER REPEATED IN THE SUPPORT. The call card's state is
//     ITM, so its support carries size and money only.
//
//  ⚠ EVERY M IN THIS FAMILY IS WHITE, NOT --tile-ground. An M sits on the feed
//  ground #F7F8F6; a #F5F5F7 card on it is two points of difference and stops
//  having an edge. Grey is what a tile INSIDE a card wears.
//
//  ⚠ THERE ARE FIVE, NOT SIX. Performance has no M. Nik, 27 Aug: "we already
//  have performance data on top so we don't need it" — the page heading prints
//  Current and Total two rows above, and a second card would be two readings of
//  one number.
//

import SwiftUI

/// The shell all five share. Figure is --t-39 on every one of them: on an M the
/// figure IS the card.
struct SunnySummaryM: View {
    let ticker: String
    let kind: String
    let state: String?
    let figure: String
    let figureLoss: Bool
    /// Two lines, left-aligned, 14/1.4 in --ink-2. Never three: the M has the
    /// room the row did not, and it spends it on air rather than on a fourth
    /// fact.
    let support: [String]
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(ticker.uppercased())
                    .font(S.inter(S.t10, S.wSemiN))
                    .tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.ink)
                Text("  \u{00B7} \(kind)".uppercased())
                    .font(S.inter(S.t10, S.wSemiN))
                    .tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.mute)
                Spacer(minLength: S.gap4)
                if let state {
                    Text(state.uppercased())
                        .font(S.inter(S.t10, S.wSemiN))
                        .tracking(S.track(S.t10, S.lsLabel))
                        .foregroundStyle(S.lossText)
                }
            }
            .sunnyLineBox(S.t10)
            Spacer(minLength: 0)
            Text(figure)
                .font(S.inter(S.t39, S.wSemiN))
                .tracking(S.track(S.t39, -0.04))
                .foregroundStyle(figureLoss ? S.loss : S.ink)
                .sunnyLineBox(S.t39)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(support.enumerated()), id: \.offset) { _, l in
                    Text(l)
                        .font(S.inter(S.t14, S.wMidSmN))
                        .foregroundStyle(S.ink2)
                        .lineLimit(1)
                        .frame(height: S.t14 * 1.4, alignment: .leading)
                }
            }
        }
        .padding(S.padCardM)
        .frame(width: S.content, height: S.content * 174 / 361, alignment: .leading)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        /* --shadow-card, not -l. An M is not an L. */
        .sunnyShadow(S.shadowCard)
        .monospacedDigit()
        .measure(name)
    }
}

// MARK: - the five

struct SunnyDeltaM: View {
    let ticker: String
    let d: BookDelta

    var body: some View {
        SunnySummaryM(
            ticker: ticker, kind: "Net delta",
            state: d.short ? "Net short" : nil,
            figure: signedBare(d.net),
            figureLoss: d.net < 0,
            support: [
                /* The unit moves off the figure and into the support here: with
                   39px of figure and a whole card naming it, `sh` would be the
                   only abbreviation on the page. */
                d.short ? "shares short, net" : "shares long, net",
                /* Same fallback as the list row: exposure until there is a
                   prior reading to compare against. */
                d.change.map { $0 == 0 ? "unchanged since yest" : "\(signedBare($0)) since yest" }
                    ?? "$\(money(d.exposure)) exposure",
            ],
            name: "m-delta-\(ticker)")
    }
}

struct SunnyAvgM: View {
    let ticker: String
    let a: BookAverage

    var body: some View {
        let above = a.vsSpot > 0
        return SunnySummaryM(
            ticker: ticker, kind: "Average price",
            state: above ? "Above spot" : nil,
            figure: sPrice(a.average),
            figureLoss: false,
            support: [
                /* ⚠ BOTH READINGS ON ONE LINE, joined by `or`. They are the same
                   fact in two units and a second line would rank one above the
                   other. */
                "\(sPct(abs(a.vsSpot)))\(above ? " above" : " below"), or $\(sPrice(abs(a.average - a.spot))) a share",
                /* ⚠ SPOT IS PRINTED so the percentage above it is auditable on
                   the page. Both denominators were live at one point and the
                   difference is visible — BABA measured 9.3% of cost against
                   8.5% of spot. */
                "spot \(sPrice(a.spot))",
            ],
            name: "m-average-\(ticker)")
    }
}

/// The three option Ms. `state` is the list's own exception word and, per §10.3,
/// the support below never says it again — which is why a call sold prints no
/// moneyness line while a put sold folds it in beside the size.
struct SunnyOptionM: View {
    let kind: String
    let stateWord: String
    let r: OptionRow

    var body: some View {
        SunnySummaryM(
            ticker: r.ticker, kind: kind,
            state: r.exception ? stateWord : nil,
            figure: sPrice(r.strike),
            figureLoss: false,
            support: [
                /* ⚠ ONLY THE CALL CARD DROPS ITS MONEYNESS, and it drops it
                   because ITM is literally its state word — printing it twice is
                   §10.3's fault. `Underwater` is a different fact from `5.2%
                   ITM` (a short put can be underwater while still out of the
                   money), so the put cards keep both. */
                dropsMoneyness ? "\(r.contracts)× \(expShort(r.expiry))"
                               : "\(r.contracts)× \(expShort(r.expiry)), \(money2Way(r))",
                "$\(money(r.opened)) → $\(money(r.now))",
            ],
            name: "m-\(kind.lowercased().replacingOccurrences(of: " ", with: "-"))-\(r.ticker)-\(Int(r.strike))")
    }

    private var dropsMoneyness: Bool { r.exception && stateWord == "ITM" }

    private func money2Way(_ r: OptionRow) -> String {
        abs(r.moneyness) < 0.5 ? "ATM" : "\(sPct(abs(r.moneyness))) \(r.itm ? "ITM" : "OTM")"
    }
}
