//
//  PositionsBand.swift
//  Sunny
//
//  Sold, in SD (§3.3), and the band: Price (§3.4) and Payoff at this Friday's close, read only (§3.5), on the phone
//  (App Explorations 154a). No em dashes in any words here.
//

import SwiftUI
import UIKit

// MARK: - Sold, in SD

/// The closed box: "Sold, in SD", "N within 0.5 SD" in red (or "N sold, all past 0.5 SD"), a chevron; a tap opens one
/// row per sold leg on one SD axis, in the money first, then SD now, nearest first. A row tap selects that name.
struct PosSoldInSD: View {
    let book: PosBook
    @Binding var open: Bool
    let reduce: Bool
    let pick: (String) -> Void

    var body: some View {
        let hot = book.hot
        let cap = hot > 0 ? "\(hot) within 0.5 SD" : "\(book.sold.count) sold, all past 0.5 SD"
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(S.moving(open ? .timingCurve(0.4, 0, 0.2, 1, duration: 0.45) : .timingCurve(0.22, 1, 0.36, 1, duration: 0.55), reduce)) { open.toggle() }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sold, in SD").sType(PT.t(15, 20, 600), tabular: false).foregroundStyle(PC.ink)
                        HStack(spacing: 6) {
                            if hot > 0 { Circle().fill(PC.red).frame(width: 6, height: 6) }
                            Text(cap).sType(PT.t(12, 16, 600)).foregroundStyle(hot > 0 ? PC.red : PC.mu)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(PC.muT)
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .animation(S.moving(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3), reduce), value: open)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .frame(minHeight: 52)
                .modifier(PosGlass(radius: 16, on: open))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sold, in SD, \(cap)")
            .accessibilityValue(open ? "Open" : "Closed")
            .accessibilityHint(open ? "Closes the sold legs" : "Opens every sold leg in SD")
            if open {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(book.sold) { r in PosSoldRow(r: r) { pick(r.l.t) } }
                }
                .padding(.top, 4)
                .transition(reduce ? .identity : .opacity.animation(open ? .easeOut(duration: 0.4).delay(0.12) : .easeOut(duration: 0.2)))
            }
        }
        .clipped()
    }
}

struct PosSoldRow: View {
    let r: PE.SoldRow
    let tap: () -> Void
    var body: some View {
        let c = PC.tone(r.tone), lc = r.tone == .quiet ? PC.muT.opacity(0.55) : c, mc = move
        let what = "\(PE.fk(r.l.K)) \(r.l.put ? "puts" : "calls") · \(r.l.exLabel) · \(Int(r.l.n))"
        let sdNow = String(format: "%.2f", r.a) + " SD" + (r.itm ? " in" : "")
        let kept = r.kept.map { $0 >= 0 ? "\(Int(PE.jsRound($0 * 100)))% kept" : "\(Int(PE.jsRound(-$0 * 100)))% lost" }
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(r.l.t).sType(PT.t(15, 20, 600), tabular: false).foregroundStyle(PC.ink)
                        Text(what).sType(PT.t(12, 16)).foregroundStyle(PC.mu).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        if let a0 = r.a0 {
                            Text(String(format: "%.2f", a0)).sType(PT.t(13, 18, 500)).foregroundStyle(PC.quiet)
                            Text("→").sType(PT.t(13, 18, 600)).foregroundStyle(mc ?? PC.quiet)
                        }
                        Text(sdNow).sType(PT.t(13, 18, 600)).foregroundStyle(mc ?? PC.ink)
                    }
                    .fixedSize()
                }
                track(lc: lc, c: c).frame(height: 18)
                SXFlowGaps(column: 8, row: 2) {
                    Text("\(r.l.entry.map(PosFmt.price) ?? "-") → \(r.l.mark.map(PosFmt.price) ?? "-")").foregroundStyle(PC.muT)
                    if let kept { Text(kept).foregroundStyle((r.kept ?? 0) >= 0 ? PC.green : PC.red) }
                    if r.showBE, let be = r.be {
                        HStack(spacing: 0) {
                            Text("BE \(String(format: "%.2f", be))").foregroundStyle(PC.ink)
                            Text(" · \(r.past ? "past it" : String(format: "%.2f", abs(r.zb ?? 0)) + " SD away")").foregroundStyle(PC.mu)
                        }
                    }
                }
                .sType(PT.t(12, 16))
            }
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .overlay(alignment: .bottom) { Rectangle().fill(PC.rule.opacity(0.75)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PosSay.words("\(r.l.t) \(PE.fk(r.l.K)) \(r.l.put ? "puts" : "calls") \(r.l.exLabel), \(Int(r.l.n)) contracts, "
                                         + (r.a0 != nil ? "sold \(String(format: "%.2f", r.a0!)) SD out, " : "")
                                         + "now \(String(format: "%.2f", r.a)) SD \(r.itm ? "in the money" : "out")"
                                         + (kept.map { ", \($0)" } ?? "")
                                         + (r.showBE && r.be != nil ? ", breakeven \(String(format: "%.2f", r.be!))\(r.past ? ", past it" : "")" : "")))
        .accessibilityHint("Opens \(r.l.t) and its Intelligence")
    }

    /// SD now against SD when sold (Nik 13 Nov 2026): further is good for a seller, green; closer red; nil (ink) with no
    /// SD when sold or no change. The red, orange and quiet distance tones stay on the track's dots only.
    private var move: Color? {
        guard let a0 = r.a0 else { return nil }
        if r.closer == true { return PC.red }
        return (r.itm ? -r.a : r.a) > a0 + 0.005 ? PC.green : nil
    }

    /// 2.2 SD each side of today's line with the 0.5, 1, 1.5 and 2 SD bands; the dot is the strike now, the hollow dot
    /// where it sat when sold (dotted to the dot), the tick its breakeven.
    private func track(lc: Color, c: Color) -> some View {
        GeometryReader { g in
            let w = g.size.width, X = { (f: Double) in CGFloat(f) * w }
            let xp = { (z: Double) in CGFloat(0.5 + max(-PE.TRACK_SD, min(PE.TRACK_SD, z)) / PE.TRACK_SD / 2) * w }
            ZStack(alignment: .topLeading) {
                ForEach([2.0, 1.5, 1, 0.5], id: \.self) { k in
                    Rectangle().fill(PC.sdBand).frame(width: CGFloat(k / PE.TRACK_SD) * w, height: 18).offset(x: xp(-k))
                }
                Rectangle().fill(PC.today).frame(width: 1.5, height: 18).offset(x: w / 2 - 0.75)
                if let x0 = r.x0 {
                    Path { p in p.move(to: CGPoint(x: min(X(x0), X(r.x)), y: 8)); p.addLine(to: CGPoint(x: max(X(x0), X(r.x)), y: 8)) }
                        .stroke(PC.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [1.5, 2.5]))
                    Circle().strokeBorder(PC.ink.opacity(0.4), lineWidth: 1.5).frame(width: 9, height: 9).offset(x: X(x0) - 4.5, y: 4)
                }
                if let xb = r.xb {
                    Rectangle().fill(lc).opacity(0.5).frame(width: abs(X(r.x) - X(xb)), height: 2).offset(x: min(X(r.x), X(xb)), y: 8)
                    RoundedRectangle(cornerRadius: 1).fill(lc).frame(width: 2, height: 12).offset(x: X(xb) - 1, y: 3)
                }
                Circle().fill(r.itm ? PC.red : PC.page).overlay(Circle().strokeBorder(c, lineWidth: 2)).frame(width: 11, height: 11).offset(x: X(r.x) - 5.5, y: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Price

/// The past 3 months of closes with today's price at the end, the name's strikes on the line (sold solid, bought
/// dotted), the price pill at the end of the line.
struct PosPriceChart: View {
    let price: PosPrice?
    let strikes: [PosName.Strike]
    let S0: Double
    let failed: Bool
    private let H: CGFloat = 210
    /// The close under the finger while it scrubs sideways (Nik 13 Nov 2026, "like before"); nil at rest.
    @State private var si: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let p = price {
                chart(p).frame(height: H)
                Text("Past 3 months \(Text("\(p.chg < 0 ? "▼" : "▲") \(PE.pcx(p.chg))").font(.inter(12, 600, tabular: true)).foregroundStyle(p.chg < 0 ? PC.red : PC.green)) · your strikes: sold solid, bought dotted")
                    .sType(PT.t(12, 16)).foregroundStyle(PC.mu)
                    .accessibilityLabel(PosSay.words("Past 3 months \(p.chg < 0 ? "down" : "up") \(PE.pcx(p.chg)), your strikes: sold solid, bought dotted"))
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
        let up = p.chg >= 0, col = up ? PC.green : PC.red
        let Ks = strikes.map(\.K)
        var lo = min(p.pts.min() ?? S0, Ks.min() ?? .infinity), hi = max(p.pts.max() ?? S0, Ks.max() ?? -.infinity)
        let pd = (hi - lo) * 0.07 == 0 ? S0 * 0.05 : (hi - lo) * 0.07
        lo -= pd; hi += pd
        let cy = { (v: Double) in CGFloat((hi - v) / (hi - lo)) }
        // The labels sit just over their lines, pushed apart (16 pt) so none overlap.
        let ys = strikes.map { cy($0.K) * H }
        let order = ys.indices.sorted { ys[$0] < ys[$1] }
        var ly = ys.map { max(16, $0 - 2) }
        var prev: CGFloat = -100
        for i in order { ly[i] = max(ly[i], prev + 17); prev = ly[i] }
        if let last = order.last, ly[last] > H { let shift = ly[last] - H; for i in order { ly[i] -= shift } }
        return GeometryReader { g in
            let w = g.size.width
            let line = Path { path in
                for (i, v) in p.pts.enumerated() {
                    let pt = CGPoint(x: CGFloat(i) / CGFloat(p.pts.count - 1) * w, y: cy(v) * H)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
            }
            ZStack(alignment: .topLeading) {
                Path { path in path.addPath(line); path.addLine(to: CGPoint(x: w, y: H)); path.addLine(to: CGPoint(x: 0, y: H)); path.closeSubpath() }
                    .fill(LinearGradient(colors: [col.opacity(0.26), col.opacity(0)], startPoint: .top, endPoint: .bottom))
                line.stroke(col, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                ForEach(Array(strikes.enumerated()), id: \.element.id) { i, s in
                    let y = ys[i]
                    Path { path in path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: w - 62, y: y)) }
                        .stroke(PC.ink.opacity(s.sold ? 0.55 : 0.5), style: s.sold ? StrokeStyle(lineWidth: 1) : StrokeStyle(lineWidth: 1.5, dash: [1.5, 2.5]))
                    Text(s.label).sType(PT.t(11, 14, 500)).foregroundStyle(PC.muT).lineLimit(1)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(PC.labelBg))
                        .fixedSize()
                        .offset(y: ly[i] - 16)
                }
                Text(PosFmt.price(S0)).sType(PT.t(11, 14, 700)).foregroundStyle(PC.onInk)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(PC.ink))
                    .fixedSize()
                    .frame(width: w, alignment: .trailing)
                    .offset(y: cy(S0) * H - 9)
                // Under the finger: a line down the chart, a dot on the close, and its date, price and the move since
                // the first close (the ticker chart's read), beside the line.
                if let i = si, p.pts.indices.contains(i) {
                    let x = CGFloat(i) / CGFloat(p.pts.count - 1) * w, v = p.pts[i], mv = v / p.pts[0] - 1
                    Rectangle().fill(PC.mu.opacity(0.6)).frame(width: 1, height: H).offset(x: x - 0.5)
                    Circle().fill(col).frame(width: 11, height: 11).background(Circle().fill(PC.page).padding(-2))
                        .offset(x: x - 5.5, y: cy(v) * H - 5.5)
                    PosScrubTip(rows: [(p.dates[i] == p.today ? "Today" : PosScrubTip.day(p.dates[i]), PC.mu, false),
                                       (PosFmt.price(v), PC.ink, true),
                                       ("\(mv < 0 ? "▼" : "▲") \(PE.pcx(mv)) since \(PosScrubTip.day(p.dates[0]))", mv < 0 ? PC.red : PC.green, false)],
                                x: x, w: w)
                }
                Color.clear.contentShape(Rectangle())
                    .gesture(PosScrubPan(moved: { lx in
                        let i = Int((max(0, min(1, lx / max(1, w))) * CGFloat(p.pts.count - 1)).rounded())
                        if i != si { var tx = Transaction(); tx.disablesAnimations = true; withTransaction(tx) { si = i } }
                    }, ended: { var tx = Transaction(); tx.disablesAnimations = true; withTransaction(tx) { si = nil } }))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PosSay.words("Price chart, past 3 months, \(PosFmt.price(S0)) today. Your strikes: " + strikes.map(\.label).joined(separator: "; ")))
    }
}

// MARK: - Payoff at this Friday's close

/// README §3.5, read only: the P&L by price at this Friday's close from today's marks, ±12% of the price, the priced
/// move shaded, where the P&L peaks (Nik's "Makes the most at $41.69 by Fri Nov 13"), the dot at today's price, then
/// the Greeks at that date.
struct PosPayoffView: View {
    let t: String
    let S0: Double
    let p: PosName.Payoff
    let privacy: Bool
    /// Some leg is switched off in Every leg.
    var changed = false
    private let H: CGFloat = 180
    /// How far across the chart the finger is while it scrubs sideways (0 to 1); nil at rest, the headline reads today.
    @State private var sx: Double?

    var body: some View {
        let peak = p.peak
        let right = peak == nil ? "Keeps making more past ↑\(p.top)% \(p.byT)" : p.peakPast ? "Already past its best \(p.byT)" : "Makes the most at \(PosFmt.price(peak!)) \(p.byT)"
        // While the finger scrubs, the headline reads the P&L at the price under it (the old payoff's way), then goes
        // back to today's price when it lifts.
        let at = sx.map { f in (x: S0 * (0.88 + 0.24 * f), v: lerp(f)) }
        let v0 = at?.v ?? p.v0, x0 = at?.x ?? S0
        let move = at.map { a -> String in
            let m = a.x / S0 - 1
            return abs(m) < 0.0005 ? "" : " (\(m > 0 ? "↑" : "↓")\(String(format: "%.1f", abs(m) * 100))%)"
        } ?? ""
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(privacy ? BriefMask.shown : PosFmt.money(v0)).sType(PT.t(26, 32, 700, tr: -0.02))
                        .foregroundStyle(v0 > 0.5 ? PC.green : v0 < -0.5 ? PC.red : PC.ink)
                    // Two lines kept either way, so nothing below jumps while the finger scrubs.
                    Text("If \(t) is at \(PosFmt.price(x0))\(move) \(p.byT)\(at == nil ? ", from today’s marks" : "")").sType(PT.t(12, 16)).foregroundStyle(PC.mu)
                        .lineLimit(2, reservesSpace: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(PosSay.words("\(PosSay.signed(v0, privacy)) if \(t) is at \(PosFmt.price(x0)) \(p.byT), from today’s marks"))
                Spacer(minLength: 0)
                Text(right).sType(PT.t(13, 18, 600)).foregroundStyle(peak != nil ? PC.orange : PC.ink).multilineTextAlignment(.trailing)
                    .accessibilityLabel(PosSay.words(right))
            }
            chart.frame(height: H)
            axis.frame(height: 16)
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
            Text(changed ? "At the Friday close, only the legs switched on. Shaded: the priced move." : "At the Friday close. Shaded: the priced move.").sType(PT.t(12, 16), tabular: false).foregroundStyle(PC.mu)
        }
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

    private var chart: some View {
        let ys = p.ys, lo0 = min(0, ys.min() ?? 0), hi0 = max(0, ys.max() ?? 0), yp = (hi0 - lo0) * 0.12 == 0 ? 1 : (hi0 - lo0) * 0.12
        let lo = lo0 - yp, hi = hi0 + yp, inner = H - 16
        let fy = { (v: Double) in 8 + CGFloat((hi - v) / (hi - lo)) * inner }
        let xp = { (x: Double) in CGFloat((x / S0 - 0.88) / 0.24) }
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
                Circle().fill(PC.dot).frame(width: 12, height: 12).overlay(Circle().stroke(PC.dotRing, lineWidth: 3).padding(-1.5))
                    .offset(x: w / 2 - 6, y: fy(p.v0) - 6)
                if let f = sx {
                    let x = CGFloat(f) * w, v = lerp(f)
                    Rectangle().fill(PC.mu.opacity(0.6)).frame(width: 1, height: H - 16).offset(x: x - 0.5, y: 8)
                    Circle().fill(v >= 0 ? PC.green : PC.red).frame(width: 11, height: 11).background(Circle().fill(PC.page).padding(-2))
                        .offset(x: x - 5.5, y: fy(v) - 5.5)
                }
                Color.clear.contentShape(Rectangle())
                    .gesture(PosScrubPan(moved: { lx in
                        let f = Double(max(0, min(1, lx / max(1, w))))
                        var tx = Transaction(); tx.disablesAnimations = true; withTransaction(tx) { sx = f }
                    }, ended: { var tx = Transaction(); tx.disablesAnimations = true; withTransaction(tx) { sx = nil } }))
            }
        }
        .accessibilityHidden(true)
    }

    /// The P&L at a fraction across the ±12% grid, read on the straight line between its two points.
    private func lerp(_ f: Double) -> Double {
        let ys = p.ys, n = ys.count
        guard n > 1 else { return ys.first ?? 0 }
        let k = max(0, min(1, f)) * Double(n - 1), i = min(n - 2, Int(k)), w = k - Double(i)
        return ys[i] + (ys[i + 1] - ys[i]) * w
    }

    private var axis: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .topLeading) {
                Rectangle().fill(PC.rule).frame(height: 1)
                ForEach([-12, -6, 0, 6, 12], id: \.self) { pc in
                    let x = CGFloat(pc + 12) / 24 * w
                    Text(PosFmt.price(S0 * (1 + Double(pc) / 100))).sType(PT.t(11, 13)).foregroundStyle(PC.mu).fixedSize()
                        .frame(width: 80, alignment: pc == -12 ? .leading : pc == 12 ? .trailing : .center)
                        .offset(x: pc == -12 ? 0 : pc == 12 ? w - 80 : x - 40, y: 3)
                }
            }
        }
        .accessibilityHidden(true)
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
