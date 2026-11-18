//
//  PositionsBand.swift
//  Sunny
//
//  The band: Price (§3.4) and Payoff at this Friday's close, read only (§3.5), on the phone
//  (App Explorations 154a). No em dashes in any words here.
//

import SwiftUI
import UIKit

// MARK: - Price

/// Handoff 2026-11-13-positions 2 §3.4 on the phone (154a; Nik, 13 Nov 2026: "Just price chart"): the past week in
/// hours with no fill, ending in a ring at today, the days to the Friday kept open after it, the strike lines (sold
/// dashed, bought dotted) to an 88 pt tag column, the day names under it, then "Past week ▼ 0.2% · sold dashed, bought
/// dotted · to Fri Nov 20". The model is PosPrice (the shared price-chart.ts, ported). The scrub stays (Nik): a
/// sideways drag, its own layer (PosPriceScrub), so a drag redraws only the line under the finger and its dot.
struct PosPriceChart: View {
    let price: PosPrice?
    let failed: Bool
    /// The 1 SD layer (round 164, remembered as `sunny.cone164`, as the web keeps it).
    @Binding var cone: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    private let H = PosPrice.CH, TAGW: CGFloat = 96

    /// Calls blue, puts brown (162a).
    static func tc(_ put: Bool, _ a: Double = 1) -> Color { (put ? PC.floor : PC.ceiling).opacity(a) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let p = price {
                if p.coneOk {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(S.moving(.timingCurve(0.22, 1, 0.36, 1, duration: 0.55), reduce) ?? .linear(duration: 0)) { cone.toggle() }
                        } label: {
                            // On: the ink capsule with the page's colour on it (it read black on black in light mode, Nik 18 Nov).
                            // Plain glass, not .interactive(): on iOS 27 that took the touches around it (the Payoff scrub).
                            Text("1 SD").sType(PT.t(13, 16, 600), tabular: false).foregroundStyle(cone ? PC.onInk : PC.ink)
                                .padding(.horizontal, 12).frame(minHeight: 30)
                                .background { if cone { Capsule().fill(PC.ink) } }
                                .glassEffect(cone ? .identity : .regular, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("1 SD cone, when the price could reach your strikes")
                        .accessibilityAddTraits(cone ? [.isSelected, .isButton] : .isButton)
                        .sensoryFeedback(.selection, trigger: cone)
                    }
                }
                chart(p).frame(height: H)
                labels(p).frame(height: 16)
                // One line, as the design (SunnyPositionsPhone): "Past week ▼ 15.3% · to Fri Nov 20". The how-to note is
                // gone (Nik, 18 Nov 2026), and it no longer grows when 1 SD is on, which jumped the page.
                (Text("Past week ") + Text("\(p.move < 0 ? "▼" : "▲") \(PE.pcx(p.move))").foregroundStyle(p.move < 0 ? PC.red : PC.green)
                 + Text(" · to \(p.fridayWords)"))
                    .sType(PT.t(12, 16), tabular: true).foregroundStyle(PC.mu)
                    .accessibilityLabel(PosSay.words("Past week \(p.move < 0 ? "down" : "up") \(PE.pcx(p.move)), to \(p.fridayWords)"))
                if !p.near.isEmpty { nearCard(p) }
            } else {
                Group {
                    if failed { Text("No price history for this name yet.").sType(PT.t(13, 18), tabular: false).foregroundStyle(PC.mu) }
                    else { ProgressView().controlSize(.regular) }
                }
                .frame(maxWidth: .infinity, minHeight: H)
            }
        }
    }

    private func chart(_ p: PosPrice) -> some View {
        let col = p.up ? PC.green : PC.red
        return GeometryReader { g in
            let pw = max(1, g.size.width - TAGW)
            ZStack(alignment: .topLeading) {
                // 162a: the room between the nearest sold strikes (it goes while the cone is on).
                if let r = p.room {
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(PC.green.opacity(0.10)).frame(width: pw, height: max(0, r.bottom - r.top)).offset(y: r.top)
                        if r.up { Rectangle().fill(PC.red.opacity(0.08)).frame(width: pw, height: r.top) }
                        if r.dn { Rectangle().fill(PC.red.opacity(0.08)).frame(width: pw, height: max(0, H - r.bottom)).offset(y: r.bottom) }
                    }
                    .opacity(p.coneOn ? 0 : 1)
                }
                // 164: the cone, on the scale before it widened, riding the same transform as the price line.
                if let c = p.cone {
                    let P = { (ys: [CGFloat]) in Path { pp in for (i, y) in ys.enumerated() { let pt = CGPoint(x: CGFloat(c.X[i]) * pw, y: y); if i == 0 { pp.move(to: pt) } else { pp.addLine(to: pt) } } } }
                    let poly = { (f: ([CGFloat], [CGFloat])) in Path { pp in
                        for (i, y) in f.0.enumerated() { let pt = CGPoint(x: CGFloat(c.X[i]) * pw, y: y); if i == 0 { pp.move(to: pt) } else { pp.addLine(to: pt) } }
                        for (i, y) in f.1.enumerated().reversed() { pp.addLine(to: CGPoint(x: CGFloat(c.X[i]) * pw, y: y)) }
                        pp.closeSubpath()
                    } }
                    ZStack(alignment: .topLeading) {
                        if let f = c.fG { poly(f).fill(PC.green.opacity(0.24)) }
                        if let f = c.fU { poly(f).fill(PC.red.opacity(0.45)) }
                        if let f = c.fD { poly(f).fill(PC.red.opacity(0.45)) }
                        P(c.YU).stroke(PC.ink.opacity(0.8), lineWidth: 1)
                        P(c.YD).stroke(PC.ink.opacity(0.8), lineWidth: 1)
                    }
                    .frame(width: pw, height: H, alignment: .topLeading)
                    .scaleEffect(x: 1, y: p.tfSy, anchor: .top).offset(y: p.tfTy)
                    .clipped()
                    .opacity(p.coneOn ? 1 : 0)
                }
                ForEach(p.lines) { l in
                    Path { $0.move(to: CGPoint(x: 0, y: l.y)); $0.addLine(to: CGPoint(x: pw, y: l.y)) }
                        .stroke(Self.tc(l.put, l.sold ? 0.9 : 0.55), style: l.sold ? StrokeStyle(lineWidth: 1.5, dash: [4, 3]) : StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0.1, 3]))
                    if l.shown && !l.name.isEmpty {
                        Text(l.name).sType(PT.t(12, 14, 600), tabular: true).foregroundStyle(Self.tc(l.put, l.sold ? 1 : 0.85))
                            .padding(.horizontal, 3)
                            .background(RoundedRectangle(cornerRadius: 3).fill(p.coneOn ? PC.page : .clear))
                            .fixedSize()
                            .frame(width: pw - 4, alignment: .trailing)
                            .offset(y: l.y + l.lt)
                    }
                }
                // The price line, on the scale before the cone widened it; the past week dims under the cone.
                Path { path in
                    for (i, q) in p.pts.enumerated() {
                        let pt = CGPoint(x: CGFloat(q.x) * pw, y: p.yb(q.v))
                        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                }
                .stroke(col, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: pw, height: H, alignment: .topLeading)
                .scaleEffect(x: 1, y: p.tfSy, anchor: .top).offset(y: p.tfTy)
                .opacity(p.coneOn ? 0.35 : 1)
                if let c = p.cone, p.coneOn {
                    ForEach(c.drops, id: \.id) { q in
                        Path { $0.move(to: CGPoint(x: CGFloat(q.x) * pw, y: q.y)); $0.addLine(to: CGPoint(x: CGFloat(q.x) * pw, y: H)) }
                            .stroke(Self.tc(q.put, 0.8), style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
                    }
                    ForEach(c.dots, id: \.id) { q in
                        Circle().fill(Self.tc(q.put)).frame(width: 9, height: 9).background(Circle().fill(PC.page).padding(-2))
                            .position(x: CGFloat(q.x) * pw, y: q.y)
                    }
                }
                Circle().strokeBorder(col, lineWidth: 2.5).background(Circle().fill(PC.page)).frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    .position(x: CGFloat(p.dotX) * pw, y: p.dotY)
                // The tag column: a short connector when a tag leaves its line, then the tags.
                ForEach(p.conn) { c in
                    Path { $0.move(to: CGPoint(x: pw, y: c.y0)); $0.addLine(to: CGPoint(x: pw + 8, y: c.y1)) }.stroke(PC.ink.opacity(0.4), lineWidth: 1)
                }
                ForEach(p.tags) { t in tag(t).offset(x: pw + 9, y: t.top) }
                PosPriceScrub(p: p, col: col, pw: pw)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PosSay.words("Price chart, past week, \(PosFmt.price(p.pts.last?.v ?? 0)) today. " + p.tags.filter { !$0.px }.map { "\($0.title)" + ($0.zTone == .red ? ", close" : $0.zTone == .orange ? ", near" : "") }.joined(separator: "; ")))
    }

    /// The nearest sold call and put, nearest first: "Sold call 36  ↑2.0% · 0.46 SD", and with the cone on, the day it
    /// first reaches it ("the cone reaches it Wed") or "outside the cone to Fri".
    private func nearCard(_ p: PosPrice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(p.near) { n in
                HStack(spacing: 10) {
                    Path { $0.move(to: CGPoint(x: 0, y: 1)); $0.addLine(to: CGPoint(x: 18, y: 1)) }
                        .stroke(Self.tc(n.put), style: StrokeStyle(lineWidth: 2, dash: [4, 3])).frame(width: 18, height: 2)
                    Text(n.name).sType(PT.t(15, 20, 600), tabular: true).foregroundStyle(Self.tc(n.put))
                    Text(n.d).sType(PT.t(14, 20, 600)).foregroundStyle(n.tone == .red ? PC.red : n.tone == .orange ? PC.orange : PC.mu).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(PosSay.words("\(n.name), \(n.d)" + (p.coneOn && !n.itm ? ", " + (n.reach != nil ? "the cone reaches it \(n.day ?? "")" : "outside the cone to \(n.fri)") : "")))
                if p.coneOn && !n.itm {
                    Text(n.reach != nil ? "The cone reaches it \(n.day ?? "")" : "Outside the cone to \(n.fri)").sType(PT.t(13, 18), tabular: false).foregroundStyle(PC.mu)
                        .padding(.leading, 28).padding(.top, -6)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

/// Nik, 14 Nov 2026 ("4 + 2"): bright text on a solid pill so the numbers read. Sold: the strike 700 ink, the %
    /// in how close it is (red under 0.5 SD or in the money, orange to 1 SD, bright grey past; Sold in SD's rings);
    /// bought: the strike 600 bright grey, the % #AEAEB2; puts in a grey capsule; today's price a white capsule.
    private func tag(_ t: PosPrice.Tag) -> some View {
        // 162a: the strike and its SD on this week's move ("36 0.46 SD"); without an IV, the % as before.
        let zt = t.zTone ?? t.tone
        let pc = zt == .red ? PC.red : zt == .orange ? PC.orange : t.sold ? PC.bright : PC.muT
        return HStack(spacing: 4) {
            Text(t.sd != nil ? t.k : t.n).font(.inter(13, t.px || t.sold ? 700 : 600, tabular: true)).foregroundStyle(t.px ? PC.onInk : t.sold ? PC.ink : PC.bright)
            if !t.px { Text((t.sd ?? t.s) + (t.fold > 0 ? " +\(t.fold)" : "")).font(.inter(12, t.sold ? 600 : 500, tabular: true)).foregroundStyle(pc) }
        }
        .lineLimit(1)
        .padding(.horizontal, t.px ? 8 : t.put ? 7 : 0)
        .frame(height: PosPrice.TH)
        .background(Capsule().fill(t.px ? PC.ink : t.put ? (t.sold ? PC.pillSold : PC.pillBought) : .clear))
        .fixedSize()
    }

    private func labels(_ p: PosPrice) -> some View {
        GeometryReader { g in
            let pw = max(1, g.size.width - TAGW)
            ZStack(alignment: .topLeading) {
                ForEach(p.xl) { x in
                    Text(x.t).sType(PT.t(12, 16, x.put != nil ? 700 : 400), tabular: false)
                        .foregroundStyle(x.put.map { Self.tc($0) } ?? (x.now ? PC.ink : PC.mu)).fixedSize()
                        .offset(x: x.put != nil ? CGFloat(x.x) * pw - 12 : CGFloat(x.x) * pw)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The Price chart's scrub on its own (only this redraws while the finger moves): the line follows the finger up to
/// today's dot, the dot slides along the price line, and the read beside it is the nearest hour: "Wed Nov 12 · 11 AM",
/// "Thu Nov 12 close" or "Now", the price, and the move since the week began.
private struct PosPriceScrub: View {
    let p: PosPrice
    let col: Color
    let pw: CGFloat
    @State private var fx: CGFloat?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let fx {
                let x = min(Double(fx / pw), p.dotX), P = p.pts
                let j = Self.seg(P, x), a = P[j], b = P[min(j + 1, P.count - 1)]
                let w = b.x > a.x ? max(0, min(1, (x - a.x) / (b.x - a.x))) : 0
                let near = w < 0.5 ? a : b, mv = P[0].v > 0 ? near.v / P[0].v - 1 : 0
                Rectangle().fill(PC.mu.opacity(0.6)).frame(width: 1, height: PosPrice.CH).offset(x: CGFloat(x) * pw - 0.5)
                Circle().fill(col).frame(width: 11, height: 11).background(Circle().fill(PC.page).padding(-2))
                    .position(x: CGFloat(x) * pw, y: p.y(a.v + (b.v - a.v) * w))
                PosScrubTip(rows: [(Self.when(near), PC.mu, false), (PosFmt.price(near.v), PC.ink, true),
                                   ("\(mv < 0 ? "▼" : "▲") \(PE.pcx(mv)) since \(Self.when(P[0]).replacingOccurrences(of: " close", with: ""))", mv < 0 ? PC.red : PC.green, false)],
                            x: CGFloat(x) * pw, w: pw)
            }
            Color.clear.frame(width: pw, height: PosPrice.CH).contentShape(Rectangle())
                .gesture(PosScrubPan(moved: { lx in
                    var tx = Transaction(); tx.disablesAnimations = true; withTransaction(tx) { fx = max(0, min(pw, lx)) }
                }, ended: { var tx = Transaction(); tx.disablesAnimations = true; withTransaction(tx) { fx = nil } }))
        }
        .frame(width: pw, height: PosPrice.CH, alignment: .topLeading)
    }

    /// The segment of the line a fraction across sits on.
    static func seg(_ P: [PosPrice.Point], _ x: Double) -> Int {
        var lo = 0, hi = P.count - 1
        while hi - lo > 1 { let m = (lo + hi) / 2; if P[m].x <= x { lo = m } else { hi = m } }
        return lo
    }
    static func when(_ q: PosPrice.Point) -> String {
        if q.now { return "Now" }
        let d = PosPrice.dayWords(q.d)
        guard let h = q.h else { return d }
        return h == 9 || h == 16 ? "\(d) close" : "\(d) · \(h > 12 ? h - 12 : h) \(h >= 12 ? "PM" : "AM")"
    }
}

// MARK: - Payoff, with the date and range sliders

/// README §3.5 with rounds 168b and Nov 18 (phone): the P&L by price from today's marks, the priced move shaded, where
/// it peaks ("Makes the most at $41.69 by Fri Nov 13"), the dot at today's price; under it a date slider (each trading
/// day from today to the day the nearest sold legs expire: "At expiration" at its end, "N days to expiration" before)
/// and a range slider (±5% to ±50%, opens ±12%, Reset once moved), then the Greeks at that date. The P&L scale holds
/// across the dates so the curve is seen to change. A target set on the web shows as a dashed line, a ring and a pill.
struct PosPayoffView: View {
    let t: String
    let S0: Double
    let p: PosName.Payoff
    let privacy: Bool
    /// Some leg is switched off in Every leg.
    var changed = false
    let dates: [PosName.DateStop]
    @Binding var at: Int
    @Binding var rangePct: Int
    /// A target price set on the web (payoff_targets), or nil.
    var target: Double? = nil
    private let H: CGFloat = 180
    /// How far across the chart the finger is while it scrubs sideways (0 to 1). Held in a reference only the headline
    /// and the scrub layer read, so a drag redraws those two and never the shaded curve or the Greeks (Nik, 13 Nov
    /// 2026: "Why is the scrub so jerky").
    @State private var scrub = PosScrubAt()

    private var r: Double { p.range }
    private func xp(_ x: Double) -> CGFloat { CGFloat((x / S0 - (1 - r)) / (2 * r)) }

    var body: some View {
        let peak = p.peak
        let right = peak == nil ? "Keeps making more past ↑\(p.top)% \(p.byT)" : p.peakPast ? "Already past its best \(p.byT)" : "Makes the most at \(PosFmt.price(peak!)) \(p.byT)"
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                PosPayoffHead(t: t, S0: S0, p: p, privacy: privacy, scrub: scrub)
                Spacer(minLength: 0)
                Text(right).sType(PT.t(13, 18, 600)).foregroundStyle(peak != nil ? PC.orange : PC.ink).multilineTextAlignment(.trailing)
                    .accessibilityLabel(PosSay.words(right))
            }
            if let tg = target { targetLine(tg) }
            chart.frame(height: H)
            axis.frame(height: 16)
            if dates.count > 1 { dateSlider.padding(.top, 6) }
            rangeSlider
            VStack(spacing: 0) {
                Rectangle().fill(PC.rule).frame(height: 1)
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        greek("Delta", PosFmt.side(p.d), p.d < 0 ? PC.orange : PC.ink, said: PosFmt.side(p.d))
                        greek("Theta a day", privacy ? BriefMask.shown : PosFmt.money(p.th), sign(p.th), said: PosSay.signed(p.th, privacy))
                    }
                    GridRow {
                        greek("Gamma", "\(PosFmt.count(p.g)) a $1", p.g < 0 ? PC.red : PC.ink, said: "\(p.g < 0 ? "short" : "long") \(PosFmt.count(p.g)) a dollar")
                        greek("Vega", privacy ? BriefMask.shown : PosFmt.money(p.vg), sign(p.vg), said: PosSay.signed(p.vg, privacy))
                    }
                }
                .padding(.top, 8)
            }
            // No how-to note under the Greeks (Nik, 18 Nov 2026: "I don't need jargon on how to use the slider").
        }
    }

    /// "At your target $38.00 · ↑7.7%, by Fri Oct 30: $5.6K" (the web's headline line; off the chart, only this).
    private func targetLine(_ tg: Double) -> some View {
        let v = PosPayoffHead.plAt(p, S0, tg), m = tg / S0 - 1
        return (Text("At your target \(PosFmt.price(tg)) · \(m >= 0 ? "↑" : "↓")\(PE.pcx(m)), \(p.byT): ").foregroundStyle(PC.mu)
                + Text(privacy ? BriefMask.shown : PosFmt.money(v)).foregroundStyle(sign(v)).fontWeight(.semibold))
            .sType(PT.t(13, 18), tabular: true)
            .accessibilityLabel(PosSay.words("At your target \(PosFmt.price(tg)), \(p.byT), \(PosSay.signed(v, privacy))"))
    }

    private func sign(_ v: Double) -> Color { v > 0.5 ? PC.green : v < -0.5 ? PC.red : PC.ink }
    private func greek(_ l: String, _ v: String, _ c: Color, said: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(l) · \(p.dateLabel)").sType(PT.t(11, 14), tabular: false).foregroundStyle(PC.mu)
            Text(v).sType(PT.t(16, 20, 600)).foregroundStyle(c).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PosSay.words("\(l), \(p.dateLabel), \(said)"))
    }

    // MARK: The sliders

    private var dateSlider: some View {
        let N = dates.count - 1, cur = dates[min(max(0, at), N)]
        let lab = cur.days == 0 && cur.i == 0 ? "Today" : cur.full
        let sub = cur.days == 0 && cur.i == 0 ? "\(cur.date) · now" : "close · in \(cur.days) \(cur.days == 1 ? "day" : "days")"
        // No "At expiration" / "N days to expiration" on the right (Nik, 18 Nov 2026, as on the web); VoiceOver still says it.
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                (Text(lab).fontWeight(.semibold).foregroundStyle(PC.ink) + Text(" · \(sub)").foregroundStyle(PC.mu))
                    .sType(PT.t(14, 18), tabular: true).lineLimit(1)
                Spacer(minLength: 0)
            }
            PosSlider(value: $at, lo: 0, hi: N, label: "Date the curve is drawn for",
                      said: { i in let d = dates[min(max(0, i), N)]; return (d.days == 0 && d.i == 0 ? "Today, now" : "\(d.full) close, in \(d.days) \(d.days == 1 ? "day" : "days")") + (i >= N ? ". At expiration\(d.ends.isEmpty ? "" : ", " + d.ends.lowercased())" : "") })
            GeometryReader { g in
                let w = g.size.width, ax = { (i: Int) in 17 + (w - 34) * CGFloat(i) / CGFloat(max(1, N)) }
                let few = N <= 8
                let picked = few ? Array(0...N) : [0] + { let fr = (1..<N).filter { dates[$0].friday }; return fr.count > 2 ? [fr[fr.count / 2]] : [] }() + [N]
                // No two labels touch (Nik, 18 Nov 2026: "Wed" ran into "Fri Nov 27" at a larger text size): each is measured
                // at the size it is drawn, and a middle label that would touch its neighbour or the last one is left out.
                let fs = UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 11)
                let wOf = { (s: String) -> CGFloat in ceil((s as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: fs, weight: .medium)]).width) }
                let span = { (i: Int) -> (CGFloat, CGFloat) in
                    let tw = wOf(Self.tickText(dates, i, N, few))
                    return i == 0 ? (0, tw) : i == N ? (w - tw, w) : (ax(i) - tw / 2, ax(i) + tw / 2)
                }
                let shown: [Int] = {
                    let end = span(N).0
                    var out = [0], right = span(0).1
                    for i in picked where i != 0 && i != N {
                        let (a, b) = span(i)
                        if a >= right + 6 && b <= end - 6 { out.append(i); right = b }
                    }
                    return N > 0 ? out + [N] : out
                }()
                ZStack(alignment: .topLeading) {
                    ForEach(0...N, id: \.self) { i in
                        if few || dates[i].friday || i == N {
                            Rectangle().fill(i == N ? PC.ink.opacity(0.7) : Color.white.opacity(0.22))
                                .frame(width: 1, height: i == N ? 8 : dates[i].friday ? 6 : 4).offset(x: ax(i))
                        }
                    }
                    ForEach(shown, id: \.self) { i in
                        Text(Self.tickText(dates, i, N, few)).sType(PT.t(11, 14), tabular: false).foregroundStyle(i == at ? PC.ink : PC.mu).fixedSize()
                            .frame(width: 90, alignment: i == 0 ? .leading : i == N ? .trailing : .center)
                            .offset(x: i == 0 ? 0 : i == N ? w - 90 : ax(i) - 45, y: 11)
                    }
                }
            }
            .frame(height: 28)
            .padding(.top, -10)
            .accessibilityHidden(true)
        }
    }

    /// A tick's words: "Today", the weekday ("Thu"), and the last stop in full ("Fri Nov 27").
    private static func tickText(_ dates: [PosName.DateStop], _ i: Int, _ N: Int, _ few: Bool) -> String {
        let md = dates[i].date.split(separator: " ").dropFirst().joined(separator: " ")
        return i == 0 ? "Today" : i == N ? (few ? "\(dates[i].wd) \(md)" : md) : few ? dates[i].wd : md
    }

    private var rangeSlider: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                (Text("Range ").foregroundStyle(PC.mu) + Text("±\(rangePct)%").fontWeight(.semibold).foregroundStyle(PC.ink))
                    .sType(PT.t(14, 18), tabular: true)
                Spacer(minLength: 0)
                if rangePct != 12 {
                    Button { withAnimation(S.fade) { rangePct = 12 } } label: {
                        // Plain glass, not .interactive() (Nik, 18 Nov 2026: with the range moved, the Payoff would not scrub on
                        // his iOS 27 phone, and it came back on Reset; the interactive glass took the touches around it).
                        Text("Reset").sType(PT.t(12, 16, 600), tabular: false).foregroundStyle(PC.ink)
                            .padding(.horizontal, 12).frame(minHeight: 28)
                            .glassEffect(.regular, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset the range to plus or minus 12 percent")
                    .transition(.opacity)
                }
            }
            .frame(minHeight: 28)
            .padding(.top, 10)
            PosSlider(value: $rangePct, lo: 5, hi: 50, label: "Price range of the chart", said: { "Plus or minus \($0) percent" })
            HStack {
                Text("±5%"); Spacer(); Text("±50%")
            }
            .sType(PT.t(11, 14), tabular: false).foregroundStyle(PC.mu)
            .padding(.top, -10)
            .accessibilityHidden(true)
        }
    }

    // MARK: The chart

    private var chart: some View {
        let ys = p.ys, yp = (p.yHi - p.yLo) * 0.12 == 0 ? 1 : (p.yHi - p.yLo) * 0.12
        let lo = p.yLo - yp, hi = p.yHi + yp, inner = H - 16
        let fy = { (v: Double) in 8 + CGFloat((hi - v) / (hi - lo)) * inner }
        return GeometryReader { g in
            let w = g.size.width, zy = fy(0)
            let line = Path { path in
                for (i, v) in ys.enumerated() {
                    let pt = CGPoint(x: CGFloat(i) / CGFloat(ys.count - 1) * w, y: fy(v))
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
            }
            let area = Path { path in path.addPath(line); path.addLine(to: CGPoint(x: w, y: zy)); path.addLine(to: CGPoint(x: 0, y: zy)); path.closeSubpath() }
            ZStack(alignment: .topLeading) {
                if p.mv > 0 {
                    let bL = max(0, xp(S0 * exp(-p.mv))) * w, bR = min(1, xp(S0 * exp(p.mv))) * w
                    LinearGradient(stops: [.init(color: PC.ink.opacity(0), location: 0), .init(color: PC.ink.opacity(0.06), location: 0.2),
                                           .init(color: PC.ink.opacity(0.06), location: 0.8), .init(color: PC.ink.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
                        .frame(width: max(0, bR - bL), height: H).offset(x: bL)
                }
                ZStack {
                    area.fill(LinearGradient(colors: [PC.green.opacity(0.4), PC.green.opacity(0)], startPoint: .top, endPoint: .bottom))
                    line.stroke(PC.green, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                }
                .mask(Rectangle().frame(height: max(0, zy)).frame(maxHeight: .infinity, alignment: .top))
                ZStack {
                    area.fill(LinearGradient(colors: [PC.red.opacity(0), PC.red.opacity(0.4)], startPoint: .top, endPoint: .bottom))
                    line.stroke(PC.red, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                }
                .mask(Rectangle().frame(height: max(0, H - zy)).frame(maxHeight: .infinity, alignment: .bottom))
                Path { path in path.move(to: CGPoint(x: 0, y: zy)); path.addLine(to: CGPoint(x: w, y: zy)) }.stroke(PC.ink.opacity(0.3), lineWidth: 1)
                Path { path in path.move(to: CGPoint(x: w / 2, y: 8)); path.addLine(to: CGPoint(x: w / 2, y: H - 8)) }.stroke(PC.ink.opacity(0.3), lineWidth: 1)
                if let pk = p.peak, !p.peakPast, xp(pk) <= 1 {
                    Path { path in path.move(to: CGPoint(x: xp(pk) * w, y: 8)); path.addLine(to: CGPoint(x: xp(pk) * w, y: H - 8)) }
                        .stroke(PC.orange, style: StrokeStyle(lineWidth: 1.5, dash: [1.5, 2.5]))
                }
                if let tg = target, xp(tg) >= 0, xp(tg) <= 1 {
                    let tx = xp(tg) * w, tv = PosPayoffHead.plAt(p, S0, tg)
                    Path { path in path.move(to: CGPoint(x: tx, y: 8)); path.addLine(to: CGPoint(x: tx, y: H - 8)) }
                        .stroke(PC.ink.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Circle().stroke(PC.ink, lineWidth: 2).frame(width: 12, height: 12).position(x: tx, y: fy(tv))
                    Text("Target \(PosFmt.price(tg))").sType(PT.t(11, 14, 600), tabular: true).foregroundStyle(PC.ink)
                        .padding(.horizontal, 7).frame(height: 20)
                        .background(Capsule().fill(PC.pillSold))
                        .fixedSize()
                        .position(x: min(max(tx, 46), w - 46), y: 10)
                }
                Circle().fill(PC.dot).frame(width: 12, height: 12).overlay(Circle().stroke(PC.dotRing, lineWidth: 3).padding(-1.5))
                    .offset(x: w / 2 - 6, y: fy(p.v0) - 6)
                PosPayoffScrub(scrub: scrub, w: w, H: H, fy: fy, at: { PosPayoffHead.lerp(p.ys, $0) })
            }
        }
        .animation(nil, value: p.ys)
        .accessibilityHidden(true)
    }

    private var axis: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .topLeading) {
                Rectangle().fill(PC.rule).frame(height: 1)
                ForEach([-1.0, -0.5, 0, 0.5, 1.0], id: \.self) { f in
                    let x = CGFloat(f + 1) / 2 * w
                    Text(PosFmt.price(S0 * (1 + f * r))).sType(PT.t(11, 13)).foregroundStyle(PC.mu).fixedSize()
                        .frame(width: 80, alignment: f == -1 ? .leading : f == 1 ? .trailing : .center)
                        .offset(x: f == -1 ? 0 : f == 1 ? w - 80 : x - 40, y: 3)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The Payoff's sliders (168b, as the web's): a 4 pt track, the filled part white, a 34 × 22 capsule thumb, white at
/// rest and glass while it is dragged (it grows a little on a spring). A sideways drag moves it (an up or down drag still
/// scrolls the page), a tap jumps to that step, VoiceOver adjusts it a step at a time. One selection tick per step.
struct PosSlider: View {
    @Binding var value: Int
    let lo: Int, hi: Int
    let label: String
    let said: (Int) -> String
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, span = max(1, hi - lo)
            let f = CGFloat(value - lo) / CGFloat(span), x = 17 + (w - 34) * f
            let step = { (lx: CGFloat) -> Int in lo + Int((max(0, min(1, (lx - 17) / max(1, w - 34))) * CGFloat(span)).rounded()) }
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color(.sRGB, red: 118 / 255, green: 118 / 255, blue: 128 / 255, opacity: 0.32)).frame(height: 4).offset(y: 20)
                Capsule().fill(PC.ink).frame(width: max(0, x), height: 4).offset(y: 20)
                Group {
                    if dragging {
                        Capsule().fill(.clear).glassEffect(.regular, in: .capsule)
                    } else {
                        Capsule().fill(Color.white).shadow(color: .black.opacity(0.3), radius: 1, y: 1).shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                    }
                }
                .frame(width: 34, height: 22)
                .scaleEffect(dragging ? 1.16 : 1)
                .position(x: x, y: 22)
                .animation(reduce ? nil : .timingCurve(0.34, 1.36, 0.64, 1, duration: 0.22), value: dragging)
                Color.clear.contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { pt in value = step(pt.x) }
                    .gesture(PosScrubPan(moved: { lx in
                        if !dragging { dragging = true }
                        let v = step(lx); if v != value { value = v }
                    }, ended: { dragging = false }))
            }
        }
        .frame(height: 44)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(said(value))
        .accessibilityAdjustableAction { d in
            switch d {
            case .increment: value = min(hi, value + 1)
            case .decrement: value = max(lo, value - 1)
            @unknown default: break
            }
        }
    }
}

// MARK: - Payoff scrub

/// Where the finger is on the Payoff chart, 0 to 1 across, nil at rest.
@Observable final class PosScrubAt { var f: Double? }

/// The Payoff headline: the P&L at today's price, or at the price under the finger while it scrubs (the old payoff's
/// way), back to today when it lifts. Two lines kept either way, so nothing below jumps.
private struct PosPayoffHead: View {
    let t: String, S0: Double, p: PosName.Payoff, privacy: Bool
    let scrub: PosScrubAt
    var body: some View {
        let at = scrub.f.map { f in (x: S0 * (1 - p.range + 2 * p.range * f), v: Self.lerp(p.ys, f)) }
        let v0 = at?.v ?? p.v0, x0 = at?.x ?? S0
        let move = at.map { a -> String in
            let m = a.x / S0 - 1
            return abs(m) < 0.0005 ? "" : " (\(m > 0 ? "↑" : "↓")\(String(format: "%.1f", abs(m) * 100))%)"
        } ?? ""
        VStack(alignment: .leading, spacing: 2) {
            Text(privacy ? BriefMask.shown : PosFmt.money(v0)).sType(PT.t(26, 32, 700, tr: -0.02))
                .foregroundStyle(v0 > 0.5 ? PC.green : v0 < -0.5 ? PC.red : PC.ink)
            Text("If \(t) is at \(PosFmt.price(x0))\(move) \(p.byT)\(at == nil ? ", from today’s marks" : "")").sType(PT.t(12, 16)).foregroundStyle(PC.mu)
                .lineLimit(2, reservesSpace: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PosSay.words("\(PosSay.signed(v0, privacy)) if \(t) is at \(PosFmt.price(x0)) \(p.byT), from today’s marks"))
    }
    /// The P&L at a price on the curve (a target), read off its points; nil off the chart is clamped to its ends.
    static func plAt(_ p: PosName.Payoff, _ S0: Double, _ x: Double) -> Double {
        lerp(p.ys, (x / S0 - (1 - p.range)) / (2 * p.range))
    }
    /// The P&L at a fraction across the chart's range, read on the straight line between its two points.
    static func lerp(_ ys: [Double], _ f: Double) -> Double {
        let n = ys.count
        guard n > 1 else { return ys.first ?? 0 }
        let k = max(0, min(1, f)) * Double(n - 1), i = min(n - 2, Int(k)), w = k - Double(i)
        return ys[i] + (ys[i + 1] - ys[i]) * w
    }
}

/// The Payoff chart's scrub layer: the line under the finger and a dot on the curve; it alone redraws with the finger.
private struct PosPayoffScrub: View {
    let scrub: PosScrubAt
    let w: CGFloat, H: CGFloat
    let fy: (Double) -> CGFloat
    let at: (Double) -> Double
    var body: some View {
        ZStack(alignment: .topLeading) {
            if let f = scrub.f {
                let x = CGFloat(f) * w, v = at(f)
                Rectangle().fill(PC.mu.opacity(0.6)).frame(width: 1, height: H - 16).offset(x: x - 0.5, y: 8)
                Circle().fill(v >= 0 ? PC.green : PC.red).frame(width: 11, height: 11).background(Circle().fill(PC.page).padding(-2))
                    .position(x: x, y: fy(v))
            }
            Color.clear.frame(width: w, height: H).contentShape(Rectangle())
                .gesture(PosScrubPan(moved: { lx in
                    var tx = Transaction(); tx.disablesAnimations = true
                    withTransaction(tx) { scrub.f = Double(max(0, min(1, lx / max(1, w)))) }
                }, ended: { var tx = Transaction(); tx.disablesAnimations = true; withTransaction(tx) { scrub.f = nil } }))
        }
        .frame(width: w, height: H, alignment: .topLeading)
    }
}

// MARK: - Scrub

/// A sideways drag on a chart (Nik 13 Nov 2026: scrub Price and Payoff "like before"). It begins only when the finger
/// moves more across than up or down, and the page's scroll waits for it to fail, so a drag up or down still scrolls the
/// page. `moved` gets the finger's x in the chart; `ended` when it lifts. No haptic (a continuous drag, Pass 5).
struct PosScrubPan: UIGestureRecognizerRepresentable {
    var moved: (CGFloat) -> Void
    var ended: () -> Void
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let p = g as? UIPanGestureRecognizer else { return true }
            let v = p.velocity(in: p.view)
            return abs(v.x) > abs(v.y)
        }
        /// Alongside anything else on the screen (a glass button's own touch handling, iOS 27), except the page's
        /// scroll, which waits for this one to fail (below).
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool {
            !(o.view is UIScrollView && o is UIPanGestureRecognizer)
        }
        /// The scroll view's pan waits for this one to fail.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy o: UIGestureRecognizer) -> Bool {
            o.view is UIScrollView && o is UIPanGestureRecognizer
        }
    }
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        g.maximumNumberOfTouches = 1
        g.delegate = context.coordinator
        return g
    }
    func handleUIGestureRecognizerAction(_ g: UIPanGestureRecognizer, context: Context) {
        switch g.state {
        case .began, .changed: moved(context.converter.localLocation.x)
        default: ended()
        }
    }
}

/// The read beside the scrub line: small rows on the chart chip, to the right of the line, or to its left past 60%.
struct PosScrubTip: View {
    let rows: [(String, Color, Bool)]
    let x: CGFloat
    let w: CGFloat
    var body: some View {
        let right = x > w * 0.6
        VStack(alignment: right ? .trailing : .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                Text(r.0).sType(r.2 ? PT.t(15, 20, 700) : PT.t(11, 14, 500), tabular: true).foregroundStyle(r.1).lineLimit(1)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(PC.labelBg))
        .fixedSize()
        .frame(width: w, alignment: right ? .trailing : .leading)
        .offset(x: right ? x - w - 8 : x + 8, y: 2)
        .allowsHitTesting(false)
    }

    private static let iso: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let out: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "MMM d"; return f
    }()
    /// "Sep 11".
    static func day(_ s: String) -> String { iso.date(from: String(s.prefix(10))).map { out.string(from: $0) } ?? s }
}
