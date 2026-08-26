//
//  SunnyPutFloor.swift
//  Sunny — the put floor card, M. cards/put-floor.md is normative.
//
//  ⚠ THE STRIKE IS THE CENTRE OF A BAND, NOT AN ENDPOINT. The card draws
//  strike ± band and a breach on EITHER side means the same thing: the strike is
//  wrong. Too far out of the money on the high side, too deep in on the low
//  side. A one-way "distance to the floor" gauge was built first and cannot see
//  the in-the-money case at all.
//
//  ⚠ THE TRIGGER READS DISTANCE, NEVER P&L. A put 12% in the money is up several
//  hundred percent and still says roll, because it has stopped being insurance
//  and become a position. TLT's 75 put is the live proof: down 38% and breached.
//
//  ⚠ RED ONLY, NEVER GREEN. Calm is an ordinary white card, so colour on this
//  card means ACT and nothing else — a card with nothing to say is silent in the
//  feed. A green/red pair was built and rejected: the calm state became the loud
//  one, and a green card in a feed of white cards shouts news that is "nothing
//  to do".
//
//  ⚠ AND IT NEVER NAMES THE ROLL. Only that it is time to roll. Strike selection
//  has its own inputs, and a card that guesses will be wrong often enough to
//  lose trust.
//

import SwiftUI

struct PutFloor: Decodable, Identifiable {
    let strike: Double
    let expiry: String
    let contracts: Double
    let dte: Int
    let debit: Int
    let value: Int
    let pnl: Int
    let pct: Double
    /// Raw and unrounded — the breach test uses this. See `shownPct`.
    let distance: Double
    var id: String { "\(strike)|\(expiry)" }
}

struct SunnyPutFloorCard: View {
    let ticker: String
    let spot: Double
    let f: PutFloor
    /// Configurable, and the card must not assume 10: every bound label, the
    /// sentence and the needle derive from it.
    var band: Double = 10

    private var breached: Bool { abs(f.distance) > band }
    private var ink: Color { breached ? S.onLoss : S.ink }
    private var body_: Color { breached ? S.onLossBody : S.ink2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 0)
            bandBlock
            Spacer(minLength: 0)
            footer
        }
        .padding(S.padCardM)
        .frame(width: S.content)
        .aspectRatio(S.Size.m.ratio, contentMode: .fit)
        .background(breached ? S.lossGround : S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(breached ? S.shadowCardInk : S.shadowCard)
        .measure("putfloor-card")
    }

    // MARK: header — the state word is the only thing in it that changes

    private var header: some View {
        HStack(alignment: .center, spacing: S.gap6) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                Text(ticker)
                    .font(InkFont.display(S.t14, S.wBold))
                    .tracking(S.track(S.t14, -0.01))
                    .foregroundStyle(ink)
                Text("put floor")
                    .font(S.inter(S.t12, S.wMidSmN))
                    .foregroundStyle(body_)
            }
            Spacer(minLength: 0)
            /* Calm states the RULE, breached states the INSTRUCTION. Same slot,
               same size, same weight, same tracking — the sentence and the ink
               change and nothing moves. No chip behind it: the ground is already
               carrying the alarm, and a chip on top says it twice. */
            Text(breached ? "Time to roll" : "Band ±\(Int(band))%")
                .font(InkFont.display(S.t10, S.wBold))
                .tracking(S.track(S.t10, S.lsLabel))
                .textCase(.uppercase)
                .foregroundStyle(breached ? S.onLoss : S.mute)
                .fixedSize()
        }
    }

    // MARK: the band block — spot row, rail, bound labels

    private var bandBlock: some View {
        VStack(alignment: .leading, spacing: S.gap4) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
                Text("Spot \(fmt(spot))")
                    .font(S.inter(S.t13, S.wBoldN))
                    .foregroundStyle(ink)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text(distanceRuns).monospacedDigit()
            }
            rail
            bounds
        }
    }

    /* Signed by the WORD, never a glyph. A "+9.8%" here would read as a gain,
       which is exactly the confusion the card exists to prevent: on this card
       the number is a DISTANCE and has no direction. */
    private var distanceRuns: AttributedString {
        var pctRun = AttributedString(shownPct)
        pctRun.font = S.inter(S.tDigestBody, S.wBoldN)
        pctRun.foregroundColor = ink
        var tail = AttributedString(" \(f.distance >= 0 ? "above" : "below") the \(fmtStrike(f.strike)) strike")
        // 400 on the saturated ground: a 300 loses stroke on solid red.
        tail.font = S.inter(S.tDigestBody, breached ? S.wMidSmN : S.wLightN)
        tail.foregroundColor = breached ? S.onLossBody : S.ink
        return pctRun + tail
    }

    /// ⚠ GUARD THE DISPLAY ONLY. 43.90 against 40 is exactly 9.75%, which lands
    /// at 9.7499…96 in binary and prints 9.7 under a plain rounding. The BREACH
    /// TEST uses the raw value, so a true 10.0000001% still breaches even though
    /// it prints as 10.0%.
    private var shownPct: String {
        String(format: "%.1f%%", (abs(f.distance) * 10 + 1e-6).rounded() / 10)
    }

    // MARK: the rail — five children, and the ORDER is load-bearing

    private var railW: CGFloat { S.content - S.figL * 2 }   // 323

    /* The axis spans 1.5 × the band each way, so the two bound marks land at
       16.667% / 83.333% at EVERY band value and only the needle moves. */
    private var needlePct: CGFloat {
        let span = band * S.floorSpanFactor
        return min(100 - S.floorNeedleClamp,
                   max(S.floorNeedleClamp, 50 + CGFloat(f.distance / span) * 50))
    }

    private var rail: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            RoundedRectangle(cornerRadius: S.floorTrackRadius, style: .continuous)
                .fill(breached ? S.onLossTrack : S.wash)
                .frame(width: railW, height: S.floorTrackH)
                .offset(y: S.gap2)

            /* ⚠ THE NEEDLE IS SECOND, BEFORE THE THREE MARKS, AND THAT IS NOT A
               STYLE PREFERENCE. It is the one mark whose position is not fixed,
               so it is the one that can collide — and when it does, the mark it
               lands on must win. At the measured calm case the needle's ink sits
               0.19px from the upper bound and its ring would erase 1.31px of that
               2px mark, leaving a 0.69px remnant at 1.52:1. The two then read as
               one blob, which destroys the exact reading the card exists for.
               Painting the marks after costs nothing: the needle is 18 tall
               against their 10, so its 4pt of overhang can never be covered. */
            needle
            mark(atPct: 100 / 3 / 2 * 1, w: S.floorMarkW, colour: S.hair)   // 16.667
            mark(atPct: 100 - 100 / 3 / 2, w: S.floorMarkW, colour: S.hair) // 83.333
            mark(atPct: 50, w: S.floorMarkW, colour: ink)
        }
        .frame(width: railW, height: S.floorRailH)
    }

    private var needle: some View {
        ZStack {
            // box-shadow 0 0 0 1.5px expands equally, so the ring is a slightly
            // larger rect behind. It matches the TRACK on white and the GROUND
            // on red: a white ring would vanish into the white needle.
            RoundedRectangle(cornerRadius: S.floorNeedleRadius, style: .continuous)
                .fill(breached ? S.lossGround : S.wash)
                .frame(width: S.floorNeedleW + S.floorNeedleRing * 2,
                       height: S.floorRailH + S.floorNeedleRing * 2)
            RoundedRectangle(cornerRadius: S.floorNeedleRadius, style: .continuous)
                .fill(ink)
                .frame(width: S.floorNeedleW, height: S.floorRailH)
        }
        .offset(x: railW * needlePct / 100 - (S.floorNeedleW / 2 + S.floorNeedleRing),
                y: -S.floorNeedleRing)
    }

    /// Every mark is centred on its value by pulling back half its own width.
    /// Without it a mark hangs to the right of the value it reports.
    private func mark(atPct p: CGFloat, w: CGFloat, colour: Color) -> some View {
        Rectangle().fill(colour)
            .frame(width: w, height: S.floorTrackH)
            .offset(x: railW * p / 100 - w / 2, y: S.gap2)
    }

    private var bounds: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            boundLabel(fmtStrike(f.strike * (1 - band / 100)), at: 100 / 3 / 2, ink: breached ? S.onLossBody : S.mute)
            boundLabel(fmtStrike(f.strike), at: 50, ink: ink)
            boundLabel(fmtStrike(f.strike * (1 + band / 100)), at: 100 - 100 / 3 / 2, ink: breached ? S.onLossBody : S.mute)
        }
        .frame(width: railW, height: S.t10)
    }

    private func boundLabel(_ t: String, at p: CGFloat, ink: Color) -> some View {
        Text(t)
            .font(InkFont.display(S.t10, S.wBold))
            .tracking(S.track(S.t10, S.lsLabel))
            .foregroundStyle(ink)
            .monospacedDigit()
            .fixedSize()
            .frame(width: railW * 0.34)
            .offset(x: railW * p / 100 - railW * 0.17)
    }

    // MARK: footer — never changes shape between states, only its ink darkens

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
            Text("\(Int(f.contracts)) × \(fmtStrike(f.strike)) put · \(expLabel(f.expiry)) · \(f.dte)d")
                .font(S.inter(S.t12, S.wMidSmN))
                .foregroundStyle(body_)
                .monospacedDigit()
            Spacer(minLength: 0)
            /* ⚠ ON RED THE P&L LOSES ITS DIRECTION INK, and that is the accepted
               cost. --loss cannot sit on itself. It bites on a LOW-side breach,
               where the puts are up several hundred percent and the card prints
               a gain in white on red. The reasoning holds only because the
               trigger reads distance and never P&L. */
            Text("\(signed(f.pnl)) · \(pctText(f.pct))")
                .font(S.inter(S.t12, S.wBoldN))
                .foregroundStyle(breached ? S.onLoss : S.loss)
                .monospacedDigit()
                .fixedSize()
        }
    }

    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }
    private func fmtStrike(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
    private func pctText(_ v: Double) -> String {
        (v < 0 ? "\u{2212}" : "+") + String(format: "%.0f", abs(v)) + "%"
    }
    private func expLabel(_ iso: String) -> String {
        let m = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return iso }
        return "\(m[p[1] - 1]) \(p[2])"
    }
}
