//
//  SunnyRollSheet.swift
//  The roll sheet (export 26, locked 23 Sep 2026): hold a sold leg's figure
//  450 ms and next Friday's write on that name rises as a glass panel 8 in from
//  the Positions card's sides and bottom. 345 × 463.
//
//  ⚠ THE BAR IS NOT A PRICE AXIS. The five levels (spot, strike, break-even,
//  ±1 SD, 20-day) sort by price and are PACKED across the 301 track by their
//  label widths with one equal gap, first label flush left, last flush right.
//  A tick sits dead-centre on its own label. Position says ORDER; distance is
//  printed, in every figure and the "end to end" span. Never `(p − lo)/(hi − lo)`,
//  never a leader, never a label moved off its tick.
//
//  ⚠ TWO RULINGS OUTRANK THE SHEET (Nik, 22 Sep 2026). The premium is the LIVE
//  MID of next Friday's strike, not the credit the pressed leg opened at; and
//  the floor is HIS OWN AVERAGE PER SIDE, not a fixed 1.06.
//
//  ⚠ NEXT FRIDAY IS THE FIRST FRIDAY AFTER THE PRESSED LEG EXPIRES.
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
    let earn: Int?
    let deltaNow: Double?, deltaAfter: Double?
    let oi: [RollChainStrike]
    /// Spot to the farthest level, %, signed along the risk direction.
    let span: Double
    /// The formatter the pack settled on: two decimals, or none for big figures.
    let wide: Bool
    /// Packed x of each level, 0...100 of the track.
    let x: (spot: Double, k: Double, be: Double, tgt: Double, avg: Double)
    let zones: [RollZone]

    func fig(_ v: Double) -> String { wide ? rsF0(v) : rsF2(v) }
}

struct RollZone: Identifiable {
    let l: Double, w: Double, tone: Tone
    var id: String { "\(tone)-\(l)" }
    enum Tone { case safe, risk, risk2, past }
}

enum RollMath {
    /// The band's width: sheet 345 less 22 padding each side.
    static let track: Double = 301
    /// Below this many points between packed labels, the figures drop decimals.
    static let minGap: Double = 10

    /// A 15/700 digit is about 9pt, a 12/400 letter about 6.7pt: the sheet's own
    /// estimate, kept so positions match the reference to the point.
    static func labelW(_ fig: String, _ word: String) -> Double {
        max(Double(fig.count) * 9, Double(word.count) * 6.7)
    }

    /// The write on this name for the first Friday after `after`.
    static func quote(t: String, call: Bool, n: Int, after: String?,
                      name: RollChainName, floor: Double) -> RollQuote? {
        let wk = name.weeks.first { after == nil || $0.w > after! } ?? name.weeks.last
        guard let week = wk, let sd = week.sd, sd > 0 else { return nil }
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

        /* ORDINAL PACK. Sorted by price, a stable tiebreak so equal prices keep
           their order; each level's slot is its label width; one gap between. */
        typealias Slot = (id: String, p: Double, w: Double)
        func pack(_ f: (Double) -> String) -> (P: [Slot], X: [String: Double], gap: Double) {
            let raw: [Slot] = [("spot", spot, labelW(f(spot), "")),
                               ("k", k, labelW(rsK(k), "strike")),
                               ("be", be, labelW(f(be), "break-even")),
                               ("tgt", tgt, labelW(f(tgt), "+1 SD")),
                               ("avg", avg, labelW(f(avg), "20-day"))]
            let P = raw.enumerated().sorted { a, b in
                a.element.p != b.element.p ? a.element.p < b.element.p : a.offset < b.offset
            }.map(\.element)
            let gap = (track - P.reduce(0) { $0 + $1.w }) / Double(P.count - 1)
            var X: [String: Double] = [:], cur = 0.0
            for s in P { X[s.id] = (cur + s.w / 2) / track * 100; cur += s.w + gap }
            return (P, X, gap)
        }
        var wide = false
        var (P, X, gap) = pack(rsF2)
        if gap < minGap { wide = true; (P, X, gap) = pack(rsF0) }

        let lo = P.first!.p, hi = P.last!.p
        let span = (call ? hi - spot : lo - spot) / spot * 100
        /* Equal prices share one x, the mean of their slots. */
        func x(_ v: Double) -> Double {
            let m = P.filter { $0.p == v }.compactMap { X[$0.id] }
            return m.isEmpty ? 0 : m.reduce(0, +) / Double(m.count)
        }
        func xe(_ v: Double) -> Double { v == hi ? 100 : v == lo ? 0 : x(v) }
        /* ⚠ ONLY THE LAST ZONE RUNS TO THE BAND'S EDGE; the others end at the
           next level's x, so no two zones overlap (export 26). */
        func seg(_ a: Double, _ b: Double, _ tone: RollZone.Tone, toEdge: Bool = false) -> RollZone {
            let xb = toEdge ? xe(b) : x(b)
            return RollZone(l: min(x(a), xb), w: abs(xb - x(a)), tone: tone)
        }
        /* Cuts are monotonic along the risk direction: a 20-day or SD inside an
           earlier zone collapses its own zone rather than painting backwards. */
        let fwd: (Double, Double) -> Double = call ? { max($0, $1) } : { min($0, $1) }
        let end = call ? hi : lo
        let near = call ? min(tgt, avg) : max(tgt, avg)
        let far = call ? max(tgt, avg) : min(tgt, avg)
        let c1 = be, c2 = fwd(c1, near), c3 = fwd(c2, far)
        let zones = [seg(k, c1, .safe), seg(c1, c2, .risk), seg(c2, c3, .risk2),
                     seg(c3, end, .past, toEdge: true)].filter { $0.w > 0.5 }

        /* A short leg's delta is the contract's, signed against him. */
        let after = pick.dl.flatMap { d in name.delta.map { $0 - d * Double(n) * 100 } }
        return RollQuote(
            t: t, call: call, spot: spot, k: k, cr: cr, be: be, tgt: tgt, avg: avg,
            onK: onK, ok: onK >= floor, floor: floor, earn: name.earn,
            deltaNow: name.delta, deltaAfter: after, oi: side,
            span: span, wide: wide,
            x: (X["spot"] ?? 0, X["k"] ?? 0, X["be"] ?? 0, X["tgt"] ?? 0, X["avg"] ?? 0),
            zones: zones)
    }
}

/// `88.4` · `1.2` · `90.2`: no trailing zeros anywhere on the sheet.
func rsF2(_ v: Double) -> String {
    var s = String(format: "%.2f", v)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}
/// Big figures on the band: `144`, not `143.73`.
func rsF0(_ v: Double) -> String { String(Int(v.rounded())) }
/// Strikes: an integer when whole, else two decimals. `102.5` stays.
func rsK(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : rsF2(v) }
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

    private static let inner: CGFloat = 301
    private static let graphH: CGFloat = 114

    private func tone(_ t: RollZone.Tone) -> Color {
        switch t {
        case .safe: return S.gainBar
        case .risk: return S.rsZoneRisk
        case .risk2: return S.lossBar
        case .past: return S.hair
        }
    }
    private func at(_ pct: Double) -> CGFloat { Self.inner * CGFloat(pct) / 100 }
    private func rise(_ ms: Double) -> Animation? {
        reduceMotion ? nil : S.easeSettle(0.5).delay(ms / 1000)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            handle
            Spacer().frame(height: 12)
            context.rsRise(shown, rise(0))
            Spacer().frame(height: 10)
            hero.rsRise(shown, rise(60))
            Spacer().frame(height: 6)
            order.rsRise(shown, rise(90))
            Spacer().frame(height: 28)
            byFri
            Spacer().frame(height: 14)
            graph
            Spacer().frame(height: 22)
            oiHead.rsRise(shown, rise(300))
            Spacer().frame(height: 10)
            tiles.rsRise(shown, rise(340))
            Spacer().frame(height: 22)
            Rectangle().fill(S.ruleColor).frame(height: 1)
            Spacer().frame(height: 14)
            footer.rsRise(shown, rise(400))
        }
        .frame(width: Self.inner, alignment: .leading)
        .padding(EdgeInsets(top: 8, leading: 22, bottom: 24, trailing: 22))
        /* ⚠ THE PANEL IS THE SCREEN LESS 12 EACH SIDE; THE COLUMN STAYS 301.
           The band's pack is measured against 301 (`TRACK`), so the column
           keeps it and centres; only the glass grows with the phone. */
        .frame(maxWidth: .infinity, alignment: .top)
        /* ⚠ ONE GLASS LAYER, REGULAR, NEVER CLEAR (presentation spec, 23 Sep).
           The sheet is large, sits over a data card and carries 13pt muted
           type; Clear is for small marks over photos. Regular adapts to what
           is behind it, so there is no gradient, rim or second dimming layer:
           the platform draws its own edge. */
        .glassEffect(.regular.tint(S.rsGlassTint),
                     in: .rect(cornerRadius: 40, style: .continuous))
        .shadow(color: S.rsShadow1, radius: 16, x: 0, y: 12)
        .shadow(color: S.rsShadow2, radius: 3, x: 0, y: 2)
        .monospacedDigit()
        .measure("roll-sheet")
        .onAppear { shown = true }
    }

    private var handle: some View {
        HStack {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2).fill(S.hair).frame(width: 36, height: 4)
                .frame(width: 44, height: 16, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
            Spacer(minLength: 0)
        }
        .frame(width: Self.inner, height: 16)
    }

    // MARK: header · three lines

    /// `NFLX is 79 · 2.05% vs 1.06 floor`: the % is the only colour up here.
    private var context: some View {
        (Text(q.t).font(S.inter(S.t13, S.wSemiN)).foregroundStyle(S.ink)
         + Text(" is ").font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
         + Text(q.fig(q.spot)).font(S.inter(S.t13, S.wSemiN)).foregroundStyle(S.ink)
         + Text(" \u{00B7} ").font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
         + Text(rsF2(q.onK) + "%").font(S.inter(S.t13, S.wBoldN))
            .foregroundStyle(q.ok ? S.gainText : S.lossText)
         + Text(" vs " + rsF2(q.floor) + " floor").font(S.inter(S.t13, S.wMidSmN))
            .foregroundStyle(S.mute))
            .lineLimit(1).fixedSize()
            .frame(height: 15.5, alignment: .leading)
    }

    private var hero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(rsF2(q.cr)).font(S.inter(34, S.wBoldN)).tracking(S.track(34, -0.03))
                .foregroundStyle(S.ink).sunnyLineBox(34)
            Text("a share").font(S.inter(15, S.wMidSmN)).foregroundStyle(S.mute)
        }
        .frame(height: 34, alignment: .leading)
    }

    /// Its own line, always: beside the hero it clipped on `112.5 calls`.
    private var order: some View {
        (Text("sell ").font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
         + Text(rsK(q.k) + (q.call ? " calls" : " puts")).font(S.inter(S.t13, S.wBoldN))
            .foregroundStyle(S.ink)
         + Text(" for next ").font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
         + Text("Fri").font(S.inter(S.t13, S.wBoldN)).foregroundStyle(S.ink))
            .lineLimit(1).fixedSize()
            .frame(height: 15.5, alignment: .leading)
    }

    private func eyebrow(_ s: String) -> some View {
        Text(s.uppercased()).font(S.inter(S.t11, S.wBoldN)).tracking(S.track(S.t11, 0.1))
            .foregroundStyle(S.mute)
    }

    /// `BY FRI` and the span, the one place distance is summed up.
    private var byFri: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            eyebrow("By Fri")
            Spacer(minLength: 0)
            Text((q.span < 0 ? "\u{2212}" : "+") + String(format: "%.1f", abs(q.span))
                 + "% end to end")
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
        }
        .lineLimit(1)
        .frame(width: Self.inner, height: 14.5)
    }

    // MARK: the graph (301 × 114)

    private struct Level {
        let x: Double, v: String, word: String, ink: Color, tick: Color, delay: Double
    }
    private var levels: [Level] {
        [Level(x: q.x.k, v: rsK(q.k), word: "strike", ink: S.ink, tick: S.ink, delay: 200),
         Level(x: q.x.be, v: q.fig(q.be), word: "break-even", ink: S.ink, tick: S.ink, delay: 240),
         Level(x: q.x.tgt, v: q.fig(q.tgt), word: (q.call ? "+" : "\u{2212}") + "1 SD",
               ink: S.lossText, tick: S.lossBar, delay: 280),
         Level(x: q.x.avg, v: q.fig(q.avg), word: "20-day", ink: S.mute, tick: S.hair, delay: 320)]
    }

    /* Every mark placed with `.position` in a fixed 301 × 114 box: a label's
       centre IS its tick's x. y from the graph's top: spot label 0 (15.5 tall),
       spot tick 18, band 34 (12), level ticks 52, labels 78 (32.5 tall). */
    private var graph: some View {
        ZStack(alignment: .topLeading) {
            band.position(x: Self.inner / 2, y: 34 + 6)
            Text(q.fig(q.spot)).font(S.inter(S.t13, S.wBoldN)).foregroundStyle(S.ink)
                .fixedSize()
                .position(x: at(q.x.spot), y: 7.75)
                .rsRise(shown, rise(180))
            tick(S.ink)
                .position(x: at(q.x.spot), y: 18 + 5)
                .rsRise(shown, rise(180))
            ForEach(Array(levels.enumerated()), id: \.offset) { _, lv in
                tick(lv.tick)
                    .position(x: at(lv.x), y: 52 + 5)
                    .rsRise(shown, rise(lv.delay))
                VStack(spacing: 0) {
                    Text(lv.v).font(S.inter(15, S.wBoldN)).tracking(S.track(15, -0.01))
                        .foregroundStyle(lv.ink)
                    Text(lv.word).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(lv.ink)
                }
                .fixedSize()
                .position(x: at(lv.x), y: 78 + 16.25)
                .rsRise(shown, rise(lv.delay))
            }
        }
        .frame(width: Self.inner, height: Self.graphH, alignment: .topLeading)
    }

    private func tick(_ c: Color) -> some View {
        Rectangle().fill(c).frame(width: 2, height: 10)
    }

    /// One 12pt bar: solid zone inks on the track, a 1pt ring painted over them.
    private var band: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(S.rsTrack)
            ForEach(q.zones) { z in
                Rectangle().fill(tone(z.tone))
                    .frame(width: at(z.w))
                    .offset(x: at(z.l))
            }
        }
        .frame(width: Self.inner, height: 12, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(S.rsTrackEdge, lineWidth: 1))
        .scaleEffect(x: shown || reduceMotion ? 1 : 0, anchor: .leading)
        .animation(rise(120), value: shown)
    }

    // MARK: open interest

    private var oiHead: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            eyebrow("Open interest")
            Spacer(minLength: 0)
            Text((q.call ? "calls" : "puts") + " \u{00B7} next Fri")
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
        }
        .lineLimit(1)
        .frame(width: Self.inner, height: 14.5)
    }

    /// Five strikes, a faint fill each, none highlighted: a table, not buttons.
    private var tiles: some View {
        HStack(spacing: 6) {
            ForEach(Array(q.oi.enumerated()), id: \.offset) { _, o in
                VStack(spacing: 4) {
                    Text(rsK(o.k)).font(S.inter(15, S.wBoldN)).tracking(S.track(15, -0.01))
                        .foregroundStyle(S.ink)
                    Text(rsOI(o.oi)).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                /* A 6% ink fill on the glass, never a glass of its own and
                   never an outline: glass on glass muddies the hierarchy. */
                .background(S.rsTileFill,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .frame(width: Self.inner)
    }

    // MARK: footer

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            /* ⚠ THE WORD GOES BEFORE THE FIGURES DO. Real books run "645 → −219",
               wider than the sheet's "120 → 90", and the reference's ellipsis
               then cut the after figure, the one number the line is for. When
               the sentence does not fit it drops "positive". */
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
                ? "Delta " + (after > 0 ? "positive" : after < 0 ? "negative" : "flat") + " \u{00B7} "
                : "Delta "
            (Text(word).font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
             + Text("\(Int(now.rounded())) \u{2192} \(rsSigned(after))")
                .font(S.inter(S.t13, S.wBoldN)).foregroundStyle(S.ink))
                .lineLimit(1).fixedSize()
        }
    }
}

/// A delta figure with a true minus, never a hyphen.
private func rsSigned(_ v: Double) -> String {
    let i = Int(v.rounded())
    return i < 0 ? "\u{2212}\(-i)" : "\(i)"
}

// MARK: - the host

/* ⚠ FROM THE BOTTOM OF THE SCREEN, NOT OUT OF THE CARD. Nik, 23 Sep 2026:
   "card should be like a native style from the bottom of the screen". The
   panel is export 26's, unchanged; only where it lives moved. It floats 8
   above the home indicator over a full-screen dim, rises in .32s, and closes
   on a tap outside, a tap on the handle, or a swipe down, the way every sheet
   on the phone does. A system sheet was tried first and reserved a padded band
   under the footer that read as a gap; this host owns its own height. */
struct RollSheetHost: View {
    let q: RollQuote
    let onDismissed: () -> Void
    @State private var up = false
    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The panel's measured height; a drag past 30% of it closes.
    private static let height: CGFloat = 463

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottom) {
                /* The dim fades in .25s, the panel rises in .32s (the spec's
                   two timings), and the dim is light on purpose. */
                S.rsScrim
                    .opacity(up ? 1 : 0)
                    .animation(reduceMotion ? nil : S.easeSettle(0.25), value: up)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                if up {
                    SunnyRollSheet(q: q, onClose: close)
                        .offset(y: max(0, drag))
                        .gesture(
                            DragGesture()
                                .onChanged { drag = $0.translation.height }
                                .onEnded { v in
                                    if max(v.translation.height, v.predictedEndTranslation.height)
                                        > Self.height * 0.3 {
                                        close()
                                    } else {
                                        withAnimation(S.easeSettle(0.3)) { drag = 0 }
                                    }
                                })
                        /* ⚠ 12 FROM THE PHYSICAL EDGE, NOT 12 ABOVE THE SAFE
                           AREA. Nik, 23 Sep: "bottom spacing is too much". 12
                           plus the home indicator's 34 left 70 under the
                           footer; the panel floats over the indicator the way
                           the system's own sheets do, concentric with the
                           device corner. */
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .offset(y: 12)))
                }
            }
            .frame(width: g.size.width, height: g.size.height + g.safeAreaInsets.bottom,
                   alignment: .bottom)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear { withAnimation(reduceMotion ? nil : S.easeSettle(0.32)) { up = true } }
    }

    private func close() {
        withAnimation(reduceMotion ? nil : S.easeSettle(0.32)) { up = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.32)) { onDismissed() }
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
