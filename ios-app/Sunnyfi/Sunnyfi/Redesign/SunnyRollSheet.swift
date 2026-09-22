//
//  SunnyRollSheet.swift
//  The roll sheet (export 24, 22 Sep 2026): hold a sold leg's figure 450 ms and
//  next Friday's write on that name rises from the Positions card's bottom edge.
//
//  ⚠ THE GRAPH IS THE HERO AND THE WORDS ARE LABELS. One price band, spot above
//  it, four levels below it, open interest as a row. No sentence explains the
//  band; the zones do.
//
//  ⚠ NOTHING TOUCHES THE BAND. Spot's tick floats 6 above, the level ticks 6
//  below. A mark through the band was built and rejected.
//
//  ⚠ THE PREMIUM IS THE LIVE MID (Nik, 22 Sep, decision a), not the credit the
//  pressed leg opened at, and THE FLOOR IS HIS OWN PER SIDE (decision c), not a
//  fixed 1.06: puts pay more than calls on this book.
//
//  ⚠ NEXT FRIDAY IS THE FIRST FRIDAY AFTER THE PRESSED LEG EXPIRES, so a leg
//  expiring this Friday and one expiring next Friday read different weeks.
//

import SwiftUI

// MARK: - payload

struct RollCard: Decodable {
    let asOf: String?
    let floor: InvFloor
    let names: [String: RollChainName]
}

struct RollChainName: Decodable {
    let spot: Double
    let avg20: Double?
    /// Days to the next report, whenever it is.
    let earn: Int?
    /// The name's net delta now, share equivalents. Null when no leg is priced.
    let delta: Double?
    let weeks: [RollChainWeek]
}

struct RollChainWeek: Decodable {
    let w: String
    /// One standard deviation to this expiry, in dollars.
    let sd: Double?
    let calls: [RollChainStrike]
    let puts: [RollChainStrike]
}

struct RollChainStrike: Decodable {
    let k: Double
    let oi: Int?
    let mid: Double
    let dl: Double?
}

// MARK: - the arithmetic

/// Everything the sheet prints for one pressed leg. Pure: the view maps it to
/// inks and positions and nothing else.
struct RollQuote {
    let t: String, call: Bool
    let spot: Double, k: Double, cr: Double, be: Double, tgt: Double, avg: Double
    let onK: Double, ok: Bool, floor: Double
    let sd: Double
    let earn: Int?
    let deltaNow: Double?, deltaAfter: Double?
    let oi: [RollChainStrike], topK: Double
    /// 0...100 across the band.
    let x: (spot: Double, k: Double, be: Double, tgt: Double, avg: Double)
    /// The label positions, pushed apart so four labels never collide.
    let lx: (k: Double, be: Double, tgt: Double, avg: Double)
    let zones: [RollZone]
}

struct RollZone: Identifiable {
    let l: Double, w: Double, tone: Tone
    var id: String { "\(tone)-\(l)" }
    enum Tone { case safe, risk, risk2, past }
}

enum RollMath {
    /// Four level labels on a 313 track, each about a fifth of it: ticks stay
    /// where the data puts them, labels slide apart to a 20% pitch and stay
    /// inside 10...90 so a centred label never leaves the sheet.
    static func spread(_ xs: [Double], gap: Double = 20, lo: Double = 10, hi: Double = 90) -> [Double] {
        var out = xs
        let idx = xs.indices.sorted { xs[$0] < xs[$1] }
        var prev = -Double.infinity
        for i in idx {
            out[i] = min(max(out[i], lo), hi)
            if out[i] < prev + gap { out[i] = prev + gap }
            prev = out[i]
        }
        let over = out[idx[idx.count - 1]] - hi
        if over > 0 {
            var next = Double.infinity
            for i in idx.reversed() {
                out[i] = min(out[i] - over, hi)
                if out[i] > next - gap { out[i] = next - gap }
                next = out[i]
            }
        }
        return out
    }

    /// The write on this name for the first Friday after `after`.
    static func quote(t: String, call: Bool, n: Int, after: String?,
                      name: RollChainName, floor: Double) -> RollQuote? {
        let wk = name.weeks.first { after == nil || $0.w > after! } ?? name.weeks.last
        guard let week = wk, let sd = week.sd, week.sd ?? 0 > 0 else { return nil }
        let spot = name.spot
        /* The strike is the nearest chain strike at or beyond spot on the leg's
           side: a call above, a put below. */
        let side = call ? week.calls : week.puts
        guard let pick = call ? side.first : side.last, pick.mid > 0, spot > 0 else { return nil }
        let k = pick.k, cr = pick.mid
        let be = call ? k + cr : k - cr
        let tgt = call ? spot + sd : spot - sd
        let avg = name.avg20 ?? spot
        let onK = cr / k * 100
        /* The band's scale is the five price levels; the OI strikes have their
           own row. A floor of 1.5 × sd on the range so an at-the-money write
           still spreads, then 8% air each side. */
        var lo0 = min(spot, k, be, tgt, avg), hi0 = max(spot, k, be, tgt, avg)
        let minRange = sd * 1.5
        if hi0 - lo0 < minRange {
            let c = (hi0 + lo0) / 2
            lo0 = c - minRange / 2; hi0 = c + minRange / 2
        }
        let pad = (hi0 - lo0) * 0.08
        let lo = lo0 - pad, hi = hi0 + pad
        let x = { (v: Double) in (v - lo) / (hi - lo) * 100 }
        let seg = { (a: Double, b: Double, tone: RollZone.Tone) in
            RollZone(l: min(x(a), x(b)), w: abs(x(b) - x(a)), tone: tone)
        }
        let end = call ? hi : lo
        let zones = [seg(k, be, .safe), seg(be, tgt, .risk),
                     seg(tgt, avg, .risk2), seg(avg, end, .past)].filter { $0.w > 0.5 }
        let lxs = spread([x(k), x(be), x(tgt), x(avg)])
        let top = side.max { ($0.oi ?? 0) < ($1.oi ?? 0) } ?? pick
        /* A short leg's delta is the contract's, signed against him. */
        let after = pick.dl.flatMap { d in name.delta.map { $0 - d * Double(n) * 100 } }
        return RollQuote(
            t: t, call: call, spot: spot, k: k, cr: cr, be: be, tgt: tgt, avg: avg,
            onK: onK, ok: onK >= floor, floor: floor, sd: sd, earn: name.earn,
            deltaNow: name.delta, deltaAfter: after,
            oi: call ? side : side, topK: top.k,
            x: (x(spot), x(k), x(be), x(tgt), x(avg)),
            lx: (lxs[0], lxs[1], lxs[2], lxs[3]),
            zones: zones)
    }
}

/// `88.4` · `1.2` · `90.2` — no trailing zeros anywhere on the sheet.
func rsF2(_ v: Double) -> String {
    let r = (v * 100).rounded() / 100
    return r == r.rounded() ? String(Int(r)) : String(format: "%g", r)
}
func rsOI(_ v: Int?) -> String {
    guard let v else { return "\u{2013}" }
    return v >= 1000 ? String(format: "%.1fk", Double(v) / 1000) : String(v)
}

// MARK: - the sheet

struct SunnyRollSheet: View {
    let q: RollQuote
    let onClose: () -> Void
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let inner: CGFloat = S.content - 48      // 313
    private static let bandH: CGFloat = 22
    private static let graphH: CGFloat = 104

    private func tone(_ t: RollZone.Tone) -> Color {
        switch t {
        case .safe: return S.rsZoneSafe
        case .risk: return S.rsZoneRisk
        case .risk2: return S.rsZoneRisk2
        case .past: return S.rsZonePast
        }
    }
    private func at(_ pct: Double) -> CGFloat { Self.inner * CGFloat(pct) / 100 }
    private func rise(_ delay: Double) -> Animation? {
        reduceMotion ? nil : S.easeSettle(0.5).delay(delay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            handle
            Spacer().frame(height: 18)
            context.rsRise(shown, rise(0))
            Spacer().frame(height: 10)
            hero.rsRise(shown, rise(0.06))
            Spacer().frame(height: 28)
            eyebrow("By Fri").rsRise(shown, rise(0.12))
            Spacer().frame(height: 14)
            graph
            Spacer().frame(height: 22)
            oiHead.rsRise(shown, rise(0.3))
            Spacer().frame(height: 10)
            tiles.rsRise(shown, rise(0.34))
            Spacer().frame(height: 22)
            Rectangle().fill(S.ruleColor).frame(height: 1)
            Spacer().frame(height: 14)
            footer.rsRise(shown, rise(0.4))
        }
        .frame(width: Self.inner, alignment: .leading)
        .padding(EdgeInsets(top: 10, leading: 24, bottom: 28, trailing: 24))
        /* ⚠ THE SHEET TAKES THE CARD'S WIDTH, it does not state its own. Setting
           361 here let it sit a hair wider than the card it rises inside, and
           the right-hand level label and the last tile ran past the card edge
           on device. `maxWidth: .infinity` inside the overlay can only ever be
           the card. */
        .frame(maxWidth: .infinity, alignment: .top)
        .background(S.paper)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16,
                                          style: .continuous))
        .shadow(color: S.rsShadow, radius: 12, x: 0, y: -8)
        .monospacedDigit()
        .measure("roll-sheet")
        .onAppear { shown = true }
    }

    private var handle: some View {
        HStack {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2).fill(S.hair).frame(width: 36, height: 4)
            Spacer(minLength: 0)
        }
        .frame(width: Self.inner, height: 20, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
    }

    /// `BABA is 116.5 · sell 117 calls for next Fri` — one line, never wrapped.
    private var context: some View {
        (Text(q.t).font(S.inter(S.t12, S.wSemiN)).foregroundStyle(S.ink)
         + Text(" is ").font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
         + Text(rsF2(q.spot)).font(S.inter(S.t12, S.wSemiN)).foregroundStyle(S.ink)
         + Text(" \u{00B7} sell ").font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
         + Text(rsF2(q.k) + (q.call ? " calls" : " puts")).font(S.inter(S.t12, S.wBoldN)).foregroundStyle(S.ink)
         + Text(" for next ").font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
         + Text("Fri").font(S.inter(S.t12, S.wBoldN)).foregroundStyle(S.ink))
            .lineLimit(1).fixedSize()
            .frame(height: 14.5, alignment: .leading)
    }

    /// The credit a share at 30, with the one colour on the top half beside it.
    private var hero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(rsF2(q.cr)).font(S.inter(S.t30, S.wBoldN)).tracking(S.track(S.t30, -0.03))
                .foregroundStyle(S.ink).sunnyLineBox(S.t30)
            (Text("a share \u{00B7} ").font(S.inter(S.t14, S.wMidSmN)).foregroundStyle(S.mute)
             + Text(String(format: "%.2f%%", q.onK)).font(S.inter(S.t14, S.wBoldN))
                .foregroundStyle(q.ok ? S.gainText : S.lossText)
             + Text(" vs " + String(format: "%.2f", q.floor) + " floor")
                .font(S.inter(S.t14, S.wMidSmN)).foregroundStyle(S.mute))
                .lineLimit(1)
        }
        .frame(height: 30, alignment: .leading)
    }

    private func eyebrow(_ s: String) -> some View {
        Text(s.uppercased()).font(S.inter(S.t11, S.wSemiN)).tracking(S.track(S.t11, 0.08))
            .foregroundStyle(S.mute).frame(height: 13, alignment: .leading)
    }

    // MARK: the graph

    /* ⚠ EVERY MARK IS PLACED WITH `.position`, NEVER AN ALIGNMENT GUIDE. The
       first build centred the labels by moving their leading guide, which moves
       the ZSTACK's leading with them: the band slid 27pt right and the +1 SD
       label hung off the sheet. `.position` places a child in a fixed box and
       changes nothing else. */
    private var graph: some View {
        ZStack(alignment: .topLeading) {
            band
                .position(x: Self.inner / 2, y: 32 + Self.bandH / 2)
            Text(rsF2(q.spot)).font(S.inter(S.t11, S.wBoldN)).foregroundStyle(S.ink)
                .fixedSize()
                .position(x: at(min(92, max(8, q.x.spot))), y: 6)
                .rsRise(shown, rise(0.18))
            tick(S.ink)
                .position(x: at(q.x.spot), y: 21)
                .rsRise(shown, rise(0.18))
            ForEach(Array(levels.enumerated()), id: \.offset) { i, lv in
                tick(lv.tickInk)
                    .position(x: at(lv.x), y: 65)
                    .rsRise(shown, rise(0.2 + Double(i) * 0.04))
                VStack(spacing: 0) {
                    Text(lv.v).font(S.inter(S.t13, S.wBoldN)).foregroundStyle(lv.ink)
                    Text(lv.word).font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(lv.ink)
                }
                .fixedSize()
                /* Clamped like the spot label: a centred label at the very end
                   of the track would hang off the sheet. */
                .position(x: at(min(90, max(10, lv.lx))), y: 88)
                .rsRise(shown, rise(0.2 + Double(i) * 0.04))
            }
        }
        .frame(width: Self.inner, height: Self.graphH, alignment: .topLeading)
    }

    private func tick(_ c: Color) -> some View {
        Rectangle().fill(c).frame(width: 2, height: 10)
    }

    private var band: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(S.wash)
            ForEach(q.zones) { z in
                Rectangle().fill(tone(z.tone))
                    .frame(width: at(z.w))
                    .offset(x: at(z.l))
            }
        }
        .frame(width: Self.inner, height: Self.bandH, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .scaleEffect(x: shown || reduceMotion ? 1 : 0, anchor: .leading)
        .animation(rise(0.12), value: shown)
    }

    private struct Level { let x: Double, lx: Double, v: String, word: String, ink: Color, tickInk: Color }
    private var levels: [Level] {
        [Level(x: q.x.k, lx: q.lx.k, v: rsF2(q.k), word: "strike", ink: S.ink, tickInk: S.ink),
         Level(x: q.x.be, lx: q.lx.be, v: rsF2(q.be), word: "break-even", ink: S.ink, tickInk: S.ink),
         Level(x: q.x.tgt, lx: q.lx.tgt, v: rsF2(q.tgt),
               word: (q.call ? "+" : "\u{2212}") + "1 SD", ink: S.lossText, tickInk: S.lossBar),
         Level(x: q.x.avg, lx: q.lx.avg, v: rsF2(q.avg), word: "20-day", ink: S.mute, tickInk: S.hair)]
    }

    // MARK: open interest

    private var oiHead: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            eyebrow("Open interest")
            Spacer(minLength: 0)
            Text((q.call ? "calls" : "puts") + " \u{00B7} next Fri")
                .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
        }
        .frame(width: Self.inner, alignment: .leading)
    }

    /// Five strikes; the one carrying the most open interest is filled.
    private var tiles: some View {
        HStack(spacing: 6) {
            ForEach(Array(q.oi.enumerated()), id: \.offset) { _, o in
                let on = o.k == q.topK
                VStack(spacing: 4) {
                    Text(rsF2(o.k)).font(S.inter(S.t13, S.wBoldN))
                        .foregroundStyle(on ? S.paper : S.ink)
                    Text(rsOI(o.oi)).font(S.inter(S.t11, S.wMidSmN))
                        .foregroundStyle(on ? S.paper : S.mute)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(on ? S.ink : S.wash)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .frame(width: Self.inner)
    }

    // MARK: footer

    /* ⚠ THE WORD GOES BEFORE THE FIGURES DO. "Delta is positive · 162 → 118"
       beside "earnings in 63 days" is wider than 313, and the sheet's rule is
       one line that is never cut, so the sentence drops to "Delta 162 → 118"
       when the two do not fit. The figures never shrink. */
    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                deltaLine(long: true)
                deltaLine(long: false)
            }
            Spacer(minLength: 0)
            if let e = q.earn {
                Text("earnings in \(e) day\(e == 1 ? "" : "s")")
                    .font(S.inter(S.t13, S.wSemiN))
                    .foregroundStyle(e <= 7 ? S.warn : S.mute)
                    .lineLimit(1).fixedSize()
            }
        }
        .frame(width: Self.inner, height: 15.5, alignment: .leading)
    }

    @ViewBuilder private func deltaLine(long: Bool) -> some View {
        if let now = q.deltaNow, let after = q.deltaAfter {
            let word = long
                ? "Delta is " + (after > 0 ? "positive" : after < 0 ? "negative" : "flat") + " \u{00B7} "
                : "Delta "
            (Text(word).font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
             + Text("\(Int(now.rounded())) \u{2192} \(Int(after.rounded()))")
                .font(S.inter(S.t13, S.wBoldN)).foregroundStyle(S.ink))
                .lineLimit(1).fixedSize()
        }
    }
}

private extension View {
    /// The sheet's blocks rise 6 and fade in, staggered.
    func rsRise(_ shown: Bool, _ animation: Animation?) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .animation(animation, value: shown)
    }
}
