//
//  SunnyRiskFace.swift
//  Sunny
//
//  Block 13i (handoff 3 Nov 2026) · the Risk face of a Position card: does the book stay long if the stock rises?
//  The net delta line from today's price to the hedge rule's target, the stretch where it goes short, the low and
//  the need; then Ways to cover N on the walls of the next three weeklies and four monthlies, the result and the
//  shares toggle. Nik, 3 Nov 2026: the check is his hedge rule (+1.5 weekly SD, +2 with an Accelerator just above
//  the sale, at the week's Thursday close), not the handoff's 2 SD from today, and the first way is the hedge's own
//  pick. Every number is sunny-home's (`plan.risk`, the hedge function's terms), so Risk and the hedge plan never
//  disagree; the phone draws, reads along the line and keeps each card's pick for the session.
//

import SwiftUI

/// Each card's pick, kept for the session (a card the lazy list rebuilds keeps it), and the cards whose Risk face
/// has played its arrival.
@Observable final class PRiskPicks {
    static let shared = PRiskPicks()
    enum Sel: Hashable { case wall(String, String), shares }
    var sel: [String: Sel] = [:]
    @ObservationIgnored var arrived: Set<String> = []
}

/// A wall's words and colors (the tape's labels; open-interest walls have no dots).
enum PWallKind {
    static func name(_ l: String) -> String {
        switch l { case "ceiling": "Ceiling"; case "floor": "Floor"; case "accelerator": "Accelerator"; default: "Unclear" }
    }
    static func color(_ l: String) -> Color {
        switch l { case "ceiling": S.wallCeiling; case "floor": S.wallFloor; case "accelerator": S.wallAccel; default: S.wallUnclear }
    }
    static func dots(_ c: Int?) -> String {
        guard let c else { return "open interest" }
        let n = max(0, min(3, c))
        return String(repeating: "●", count: n) + String(repeating: "○", count: 3 - n)
    }
}

/// Dollars in full: "$21,791".
private func usdFull(_ v: Double) -> String { "$" + Int(abs(v).rounded()).formatted(.number.grouping(.automatic)) }
/// "391", "219 short".
private func deltaWords(_ v: Double) -> String { Int(abs(v).rounded()).formatted(.number.grouping(.automatic)) + (v < 0 ? " short" : "") }

struct PRiskFace: View {
    let t: String
    let r: NamePlan.Risk
    /// One call per LEAP (the plan's sale size), for "one per LEAP".
    let perLeap: Int?
    /// The calls sold for the week checked.
    let sold: [Leg]
    let width: CGFloat
    /// The card is on this face: the first time, Risk arrives.
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var drawn: CGFloat = 1
    @State private var shown: Double = 1
    @State private var grown = true
    @State private var scrub: CGFloat?
    @State private var axStep = 0
    /// The axis labels' widths, so the low's label never runs into today's or the target's.
    @State private var axL: CGFloat = 60
    @State private var axM: CGFloat = 70
    @State private var axR: CGFloat = 80

    private static let H: CGFloat = 200, yT: CGFloat = 40, yB: CGFloat = 148
    private var x0: CGFloat { 6 }
    private var x1: CGFloat { width - 6 }
    private var short: Bool { r.need > 0 }

    // MARK: Selection

    private var defaultSel: PRiskPicks.Sel? {
        if let p = r.pick, let c = r.cols.first(where: { $0.e == p.e }), let w = c.walls.first(where: { abs($0.k - p.k) < 1e-6 }) { return .wall(c.e, w.id) }
        let c = r.cols.first { !$0.weekly && $0.walls.contains { $0.side == "call" } } ?? r.cols.first { !$0.walls.isEmpty }
        return c.flatMap { c in (c.walls.first { $0.side == "call" } ?? c.walls.first).map { .wall(c.e, $0.id) } }
    }
    private var sel: PRiskPicks.Sel? {
        if let s = PRiskPicks.shared.sel[t] { if s == .shares && !short { return defaultSel }; return s }
        return defaultSel
    }
    private var picked: (col: NamePlan.Risk.Col, wall: NamePlan.Risk.Wall?)? {
        guard case .wall(let e, let id) = sel, let c = r.cols.first(where: { $0.e == e }) else { return nil }
        return (c, c.walls.first { $0.id == id })
    }
    private var sharesOn: Bool { sel == .shares }
    private func choose(_ s: PRiskPicks.Sel) {
        guard s != sel else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        if reduce { PRiskPicks.shared.sel[t] = s } else { withAnimation(S.standard(0.4)) { PRiskPicks.shared.sel[t] = s } }
    }

    /// The dashed line: the book after the picked buy, or with the shares.
    private var after: [Double]? {
        if sharesOn { return r.d.map { $0 + Double(r.need) } }
        return picked?.wall?.after
    }

    // MARK: Scales

    private var top: Double { r.px.last ?? r.target.px ?? r.spot }
    private var px0: Double { r.px.first ?? r.spot }
    private func X(_ p: Double) -> CGFloat { x0 + CGFloat((p - px0) / max(1e-9, top - px0)) * (x1 - x0) }
    /// One scale for every way, so picking a wall never rescales the chart.
    private var vRange: (lo: Double, hi: Double) {
        var lo = 0.0, hi = 0.0
        var all = [r.d]
        for c in r.cols { for w in c.walls { if let a = w.after { all.append(a) } } }
        if r.need > 0 { all.append(r.d.map { $0 + Double(r.need) }) }
        for a in all { for v in a { lo = min(lo, v); hi = max(hi, v) } }
        return (lo, hi)
    }
    private func Yc(_ v: Double, _ R: (lo: Double, hi: Double)) -> CGFloat {
        Self.yT + CGFloat((R.hi - v) / max(1e-9, R.hi - R.lo)) * (Self.yB - Self.yT)
    }
    private var lowI: Int { r.d.indices.min { r.d[$0] < r.d[$1] } ?? 0 }
    private var zone: (lo: Double, hi: Double)? {
        let neg = r.d.indices.filter { r.d[$0] < 0 }
        guard let a = neg.first, let b = neg.last else { return nil }
        return (r.px[a], r.px[b])
    }
    /// Net delta at a price, along the line.
    private func net(at p: Double) -> Double {
        guard r.px.count > 1 else { return r.d.first ?? 0 }
        if p <= r.px[0] { return r.d[0] }
        for i in 1..<r.px.count where p <= r.px[i] {
            let f = (p - r.px[i - 1]) / max(1e-9, r.px[i] - r.px[i - 1])
            return r.d[i - 1] + f * (r.d[i] - r.d[i - 1])
        }
        return r.d.last ?? 0
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            story
            VStack(alignment: .leading, spacing: 0) {
                chart
                axis.padding(.top, -8)
            }
            ways
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: active, initial: true) { _, on in if on { arrive() } }
    }

    /// The first time a card lands on Risk: the line draws, the low and labels fade in, the walls grow, the ◆ pop.
    private func arrive() {
        guard !PRiskPicks.shared.arrived.contains(t) else { return }
        PRiskPicks.shared.arrived.insert(t)
        guard !reduce else { return }
        drawn = 0; shown = 0; grown = false
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.8)) { drawn = 1 }
        withAnimation(.easeOut(duration: 0.3).delay(0.5)) { shown = 1 }
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.45)) { grown = true }
    }

    // MARK: Story

    private var story: some View {
        let ks = Array(Set(sold.map(\.strike))).sorted().map { "$" + PF.strike($0) }.joined(separator: " and ")
        let q = sold.reduce(0) { $0 + $1.n }
        func per(_ n: Int) -> String {
            guard let L = perLeap, L > 0 else { return "" }
            return n == L ? ", one per LEAP" : n > L ? ", more than your \(L) LEAPS" : " against \(L) LEAPS"
        }
        let bold = SType(size: 16, weight: 700, line: 22, tracking: 0).font(tabular: true)
        var s = Text("")
        if let sale = r.sale {
            s = Text("Selling Friday’s ") + Text("\(sale.n) calls at $\(PF.strike(sale.k))").font(bold) + Text(per(sale.n))
        } else if q > 0 {
            s = Text("With Friday’s ") + Text("\(q) \(q == 1 ? "call" : "calls") at \(ks)").font(bold) + Text(per(q))
        } else {
            s = Text("Nothing sold this week")
        }
        let sd = PF.strike(r.target.sd), day = Self.weekday(r.by)
        if short {
            s = s + Text(", the book goes short above $\(PF.price(r.short ?? r.low.px)). ")
                + Text("Checked to $\(PF.price(top)) at \(day)’s close, \(sd) weekly SD.").foregroundStyle(S.muted)
        } else {
            s = s + Text(", delta stays above zero all the way to $\(PF.price(top)) at \(day)’s close, \(sd) weekly SD.")
        }
        return s.sType(SType(size: 16, weight: 500, line: 22, tracking: 0))
            .foregroundStyle(S.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func weekday(_ iso: String) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
        guard let d = f.date(from: iso) else { return "Thursday" }
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][c.component(.weekday, from: d) - 1]
    }

    // MARK: Chart

    private var chart: some View {
        let R = vRange, y0 = Yc(0, R), li = lowI
        let lx = X(r.px[safe: li] ?? r.low.px), ly = Yc(r.d[safe: li] ?? r.low.d, R)
        let xs = r.px.map { X($0) }
        let ny = Yc(r.d.first ?? 0, R)
        let pv = after.map { a in a.map { Yc($0, R) } }
        let nyP = min(ny, pv?.first ?? ny)
        let edge = lx > width - 83
        let lc = r.low.d < 0 ? S.red : S.green
        let br = ly - y0
        return ZStack(alignment: .topLeading) {
            // The stretch where it goes short.
            Path { p in
                p.move(to: CGPoint(x: x0, y: y0))
                for (i, v) in r.d.enumerated() { p.addLine(to: CGPoint(x: xs[i], y: Yc(min(0, v), R))) }
                p.addLine(to: CGPoint(x: x1, y: y0)); p.closeSubpath()
            }
            .fill(S.downTint)
            .opacity(shown)
            Rectangle().fill(S.muted.opacity(0.45)).frame(width: width, height: 1).offset(y: y0 - 0.5)
            if short {
                Path { p in p.move(to: CGPoint(x: lx, y: ly)); p.addLine(to: CGPoint(x: lx, y: y0)) }
                    .stroke(S.orangeDeep, style: StrokeStyle(lineWidth: 2, dash: [2, 3]))
                    .opacity(shown)
            }
            PRiskLine(xs: xs, ys: PVec(pv.map { $0.map(Double.init) } ?? r.d.map { Double(Yc($0, R)) }))
                .stroke(S.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 5]))
                .opacity(pv == nil ? 0 : 1)
                .animation(reduce ? nil : .easeOut(duration: 0.25), value: pv == nil)
            PRiskLine(xs: xs, ys: PVec(r.d.map { Double(Yc($0, R)) }))
                .trim(from: 0, to: drawn)
                .stroke(S.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            Circle().fill(S.ink).overlay(Circle().stroke(S.paper, lineWidth: 2)).frame(width: 10, height: 10)
                .position(x: xs.first ?? x0, y: ny)
            Circle().fill(lc).overlay(Circle().stroke(S.paper, lineWidth: 2)).frame(width: 12, height: 12)
                .position(x: lx, y: ly)
                .opacity(shown)
            // "391 now", above the higher of today and the dashed line.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(deltaWords(r.d.first ?? 0)).sType(SType(size: 24, weight: 800, line: 28, tracking: -0.02))
                    .foregroundStyle((r.d.first ?? 0) < 0 ? S.red : S.ink)
                Text("now").sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
            }
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(S.chartChip))
            .fixedSize()
            .offset(x: 12, y: max(0, nyP - 36))
            .opacity(scrub == nil ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: scrub == nil)
            // The low: "219 short" under it, "31" above it.
            Text(deltaWords(r.low.d)).sType(SType(size: 17, weight: 800, line: 22, tracking: 0))
                .foregroundStyle(lc)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(S.chartChip))
                .fixedSize()
                .position(x: min(max(lx, 40), width - 40), y: (short ? ly + 10 : max(0, ly - 32)) + 11)
                .opacity(shown)
            if short {
                let need = Text("\(Int(r.need).formatted()) to buy").sType(SType(size: 13, weight: 700, line: 16, tracking: 0))
                    .foregroundStyle(S.orangeDeep)
                    .padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(S.chartChip))
                    .fixedSize()
                let ndT = br >= 30 ? (ly + y0) / 2 - 8 : y0 - 22
                Group {
                    if edge { need.frame(width: max(0, lx - 10), alignment: .trailing).offset(y: ndT) }
                    else { need.offset(x: lx + 10, y: ndT) }
                }
                .opacity(shown)
            }
            if let x = scrub { scrubLayer(x, R) }
        }
        .frame(width: width, height: Self.H, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(ScrubGesture(onChange: { x in
            let v = min(max(x, x0), x1)
            if scrub == nil { UISelectionFeedbackGenerator().selectionChanged() }
            scrub = v
        }, onEnd: { scrub = nil }))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(t) net delta from $\(PF.price(px0)) to $\(PF.price(top)), now \(deltaWords(r.d.first ?? 0)), lowest \(deltaWords(r.low.d)) at $\(PF.price(r.low.px)).")
        .accessibilityValue(axStep == 0 ? "" : axRead)
        .accessibilityAdjustableAction { d in axStep = min(10, max(0, axStep + (d == .increment ? 1 : -1))) }
    }

    private var axRead: String {
        let p = px0 + (top - px0) * Double(axStep) / 10, v = net(at: p)
        return "\(deltaWords(v)) at $\(PF.price(p))"
    }

    /// The finger on the line: a thin guide, a ring on the line, the readout on a chip centered on the finger.
    private func scrubLayer(_ x: CGFloat, _ R: (lo: Double, hi: Double)) -> some View {
        let p = px0 + Double((x - x0) / max(1, x1 - x0)) * (top - px0), v = net(at: p), y = Yc(v, R)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(S.ink.opacity(0.3)).frame(width: 1.5, height: 126).offset(x: x - 0.75, y: 30)
            Circle().fill(S.paper).overlay(Circle().strokeBorder(S.ink, lineWidth: 2.5))
                .frame(width: 12, height: 12)
                .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                .position(x: x, y: y)
            PRiskReadout(v: v, price: p, x: x, width: width)
        }
        .allowsHitTesting(false)
    }

    // MARK: Axis

    private var axis: some View {
        let li = lowI, lx = X(r.px[safe: li] ?? r.low.px), edge = lx > width - 83
        let sd = PF.strike(r.target.sd) + " weekly SD"
        let lc = r.low.d < 0 ? S.red : S.green
        // The low's label centered on the low, slid clear of the two ends; with no room it folds away (the low's own
        // chip on the chart still says it).
        let lo = x0 + axL + 8 + axM / 2, hi = x1 - axR - 8 - axM / 2
        let mx = min(max(lx, lo), hi), fits = lo <= hi
        return ZStack(alignment: .topLeading) {
            axItem("$" + PF.price(px0), !short && lx < 76 ? "today · lowest" : "today", S.ink, .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { axL = $0 }
                .offset(x: x0)
            axItem("$" + PF.price(top), edge ? (short ? "most short" : "lowest") + " · " + sd : sd, edge ? lc : S.ink, .trailing)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { axR = $0 }
                .frame(width: x1, alignment: .trailing)
            if !edge && lx >= 76 {
                axItem("$" + PF.price(r.low.px), short ? "most short" : "lowest", lc, .center)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { axM = $0 }
                    .position(x: mx, y: 15)
                    .opacity(fits ? 1 : 0)
            }
        }
        .frame(width: width, height: 32, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func axItem(_ v: String, _ s: String, _ c: Color, _ a: HorizontalAlignment) -> some View {
        VStack(alignment: a, spacing: 0) {
            Text(v).sType(SType(size: 13, weight: 700, line: 16, tracking: 0)).foregroundStyle(c)
            Text(s).sType(SType(size: 11, weight: 500, line: 14, tracking: 0), tabular: false).foregroundStyle(S.muted)
        }
        .fixedSize()
    }

    // MARK: Ways

    private var ways: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(short ? "Ways to cover \(r.need.formatted())" : "Walls, if you want more")
                    .sType(SType(size: 20, weight: 700, line: 24, tracking: 0))
                Text(short ? "Tap a wall. The dashed line is the book after that buy." : "Delta stays above zero, so these only add more.")
                    .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                    .foregroundStyle(S.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            legend
            PRiskWalls(t: t, r: r, sel: sharesOn ? nil : picked.map { ($0.col.e, $0.wall?.id) }, grown: grown, reduce: reduce,
                       active: active, zone: zone, short: short) { e, id in choose(.wall(e, id)) }
            result
            if short, let sh = r.shares {
                Button { choose(sharesOn ? (defaultSel ?? .shares) : .shares) } label: {
                    Text("Or \(sh.n.formatted()) shares · \(usdFull(sh.cost))")
                        .sType(SType(size: 15, weight: 600, line: 20, tracking: 0))
                        .foregroundStyle(sharesOn ? S.paper : S.ink)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(Capsule().fill(sharesOn ? S.ink : S.pTrack))
                        .animation(reduce ? nil : .easeOut(duration: 0.2), value: sharesOn)
                }
                .buttonStyle(POpacityPress())
                .accessibilityValue(sharesOn ? "On" : "Off")
                .accessibilityAddTraits(sharesOn ? .isSelected : [])
            }
        }
        .padding(.top, 18)
        .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
    }

    private var legend: some View {
        let labels = Set(r.cols.flatMap { $0.walls.map(\.label) })
        return PRiskWrap(h: 12, v: 4) {
            swatch(Capsule().fill(S.wallCeiling).frame(width: 14, height: 3), "Ceiling")
            swatch(Capsule().fill(S.wallFloor).frame(width: 14, height: 3), "Floor")
            swatch(PDash(color: S.wallAccel, on: 4, off: 2).frame(width: 14, height: 3), "Accelerator")
            if labels.contains(where: { !["ceiling", "floor", "accelerator"].contains($0) }) {
                swatch(Capsule().fill(S.wallUnclear).frame(width: 14, height: 3), "Unclear")
            }
            swatch(Rectangle().fill(S.ink).frame(width: 8, height: 8).rotationEffect(.degrees(45)).frame(width: 12, height: 12), "Yours")
            swatch(PDash(color: S.ink, on: 3, off: 2).frame(width: 14, height: 1.5), "Today $" + PF.price(r.spot))
            if zone != nil {
                swatch(RoundedRectangle(cornerRadius: 3).fill(S.downTint).overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(S.red, lineWidth: 1)).frame(width: 12, height: 10), "Goes short")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func swatch(_ m: some View, _ s: String) -> some View {
        HStack(spacing: 5) {
            m
            Text(s).sType(SType(size: 12, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.muted)
        }
    }

    // MARK: Result

    private var resultParts: (t: String, s: String, low: Double?) {
        if sharesOn, let sh = r.shares {
            return ("\(sh.n.formatted()) shares", "\(usdFull(sh.cost)) · kept as shares, not spent", r.d.map { $0 + Double(r.need) }.min())
        }
        guard let p = picked else { return ("No walls saved", "", nil) }
        let exp = PF.monthDay(p.col.e)
        guard let w = p.wall else { return ("No walls saved for \(exp)", "", nil) }
        let at = "\(PWallKind.name(w.label)) at $\(PF.strike(w.k)) · \(exp)"
        if short {
            if w.n > 0 {
                let more = w.held > 0 ? " more" : ""
                return ("\(w.n)\(more) \(w.n == 1 ? "call" : "calls") at $\(PF.strike(w.k)) · \(exp)",
                        "\(usdFull(w.cost ?? 0)) · \(PWallKind.name(w.label)) \(PWallKind.dots(w.conf)) · \(String(format: "%.2f", w.dLow ?? 0)) Δ each at the low",
                        w.lowAfter)
            }
            if w.quoted == false { return (at, "No price saved for this strike", nil) }
            return (at, "Too far out to cover it", nil)
        }
        let mine = p.col.yours.map { ($0.side == "sold" ? "you sold " : "you hold ") + "\($0.n) × $\(PF.strike($0.k))" + ($0.type == "put" ? " puts" : "") }
        let price = w.mid.map { "$\(String(format: "%.2f", $0)) a call" } ?? "no price saved"
        return (at, [PWallKind.dots(w.conf), price, "\(p.col.days) days"].joined(separator: " · ")
                    + (mine.isEmpty ? "" : " · " + mine.joined(separator: ", ")), nil)
    }

    private var result: some View {
        let R = resultParts
        return VStack(alignment: .leading, spacing: 4) {
            Text(R.t).sType(SType(size: 20, weight: 700, line: 24, tracking: 0))
                .fixedSize(horizontal: false, vertical: true)
            if !R.s.isEmpty {
                Text(R.s).sType(SType(size: 15, weight: 500, line: 20, tracking: 0)).foregroundStyle(S.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let lo = R.low {
                (Text("Lowest after the buy: ") + Text(deltaWords(lo)).foregroundStyle(lo < 0 ? S.red : S.green))
                    .sType(SType(size: 15, weight: 600, line: 20, tracking: 0))
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .onChange(of: R.t + R.s) { _, _ in AccessibilityNotification.Announcement(R.t + ". " + R.s).post() }
    }
}

/// The readout while dragging: "185 short at $107.14", centered on the finger and kept inside the chart.
private struct PRiskReadout: View {
    let v: Double, price: Double, x: CGFloat, width: CGFloat
    @State private var w: CGFloat = 120
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(deltaWords(v)).sType(SType(size: 24, weight: 800, line: 28, tracking: -0.02)).foregroundStyle(v < 0 ? S.red : S.ink)
            Text("at $" + PF.price(price)).sType(SType(size: 13, weight: 600, line: 16, tracking: 0)).foregroundStyle(S.muted)
        }
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(S.chartChip))
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w = $0 }
        .offset(x: max(0, min(width - w, x - w / 2)))
    }
}

// MARK: - The walls row

/// Weeklies then monthlies, one row that scrolls sideways edge to edge; the picked column filled, its wall thick.
private struct PRiskWalls: View {
    let t: String
    let r: NamePlan.Risk
    /// The picked column and wall (nil with shares on).
    let sel: (e: String, id: String?)?
    let grown: Bool
    let reduce: Bool
    let active: Bool
    let zone: (lo: Double, hi: Double)?
    let short: Bool
    let tap: (String, String) -> Void

    static let H: CGFloat = 184, colW: CGFloat = 64

    private var groups: [(key: String, title: String, cols: [NamePlan.Risk.Col])] {
        [("w", "Weeklies", r.cols.filter(\.weekly)), ("m", "Monthlies", r.cols.filter { !$0.weekly })].filter { !$0.cols.isEmpty }
    }
    private var scale: (lo: Double, hi: Double) {
        let ks = [r.spot, r.px.last ?? r.spot] + r.cols.flatMap { c in c.walls.map(\.k) + c.yours.map(\.k) }
        var lo = ks.min() ?? r.spot, hi = ks.max() ?? r.spot
        let pd = (hi - lo) * 0.07; lo -= pd; hi += pd
        return (lo, hi)
    }
    private func Y(_ k: Double) -> CGFloat { let s = scale; return CGFloat((s.hi - k) / max(1e-9, s.hi - s.lo)) * Self.H }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        ForEach(groups, id: \.key) { g in
                            Text(g.title).sType(SType(size: 12, weight: 600, line: 16, tracking: 0), tabular: false)
                                .foregroundStyle(S.muted)
                                .padding(.bottom, 6)
                                .frame(width: width(g.cols.count), alignment: .leading)
                                .overlay(alignment: .bottom) { Rectangle().fill(S.pRule).frame(height: 1) }
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                    HStack(spacing: 14) {
                            ForEach(groups, id: \.key) { g in
                                HStack(spacing: 6) {
                                    ForEach(Array(g.cols.enumerated()), id: \.element.id) { j, c in
                                        PRiskCol(c: c, Y: Y, sel: sel?.e == c.e ? (sel?.id ?? "") : nil, grown: grown, reduce: reduce,
                                                 delay: Double(j) * 0.018) { id in tap(c.e, id) }
                                            .id(c.e)
                                    }
                                }
                            }
                    }
                    .frame(height: Self.H, alignment: .topLeading)
                    // Under the columns, across the whole row: the stretch that goes short, today, the low.
                    .background(alignment: .topLeading) {
                        ZStack(alignment: .topLeading) {
                            if let z = zone {
                                RoundedRectangle(cornerRadius: 6).fill(S.downTint)
                                    .frame(height: max(0, Y(z.lo) - Y(z.hi)))
                                    .offset(y: Y(z.hi))
                            }
                            PDash(color: S.ink.opacity(0.55), on: 4, off: 3).frame(height: 1.5).offset(y: Y(r.spot) - 0.75)
                            if short {
                                PDash(color: S.red, on: 1.5, off: 2.5, round: true).frame(height: 1.5).offset(y: Y(r.low.px) - 0.75)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    HStack(spacing: 14) {
                        ForEach(groups, id: \.key) { g in
                            HStack(spacing: 6) {
                                ForEach(g.cols) { c in
                                    let on = sel?.e == c.e
                                    VStack(spacing: 0) {
                                        Text(PF.monthDay(c.e)).sType(SType(size: 12, weight: on ? 700 : 600, line: 16, tracking: 0))
                                            .foregroundStyle(on ? S.ink : S.muted)
                                        Text("\(c.days) \(c.days == 1 ? "day" : "days")").sType(SType(size: 11, weight: 500, line: 14, tracking: 0))
                                            .foregroundStyle(S.muted)
                                    }
                                    .lineLimit(1)
                                    .frame(width: Self.colW)
                                    .accessibilityHidden(true)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
            // The picked column scrolls into view when the face opens.
            .onChange(of: active, initial: true) { _, on in
                guard on, let e = sel?.e else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(60))
                    if reduce { proxy.scrollTo(e, anchor: .center) } else { withAnimation(S.standard(0.45)) { proxy.scrollTo(e, anchor: .center) } }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Walls by expiry, weeklies then monthlies, tap one to see the book after buying calls there")
    }

    private func width(_ n: Int) -> CGFloat { CGFloat(n) * Self.colW + CGFloat(max(0, n - 1)) * 6 }
}

/// One expiry's column: its walls as bars at their strikes with the strike above (under it when the label above
/// would touch the one before), what you sold or hold as ◆, a 30 pt tap band across each wall.
private struct PRiskCol: View {
    let c: NamePlan.Risk.Col
    let Y: (Double) -> CGFloat
    /// The picked wall's id when this column is picked ("" with the column picked and no wall), else nil.
    let sel: String?
    let grown: Bool
    let reduce: Bool
    let delay: Double
    let tap: (String) -> Void

    private static let W: CGFloat = 64, H: CGFloat = 184

    var body: some View {
        let ws = c.walls.sorted { $0.k < $1.k }
        // Labels top down: above the bar when there is room under the one before, else under it.
        var ty: [String: CGFloat] = [:]
        var last: CGFloat = -99
        for w in ws.reversed() {
            let y = Y(w.k), up = y - 17
            ty[w.id] = up >= last + 1 ? up : y + 6
            last = (ty[w.id] ?? 0) + 14
        }
        // ◆ that touch go to opposite sides of the column.
        var diamonds: [(id: String, y: CGFloat, left: Bool)] = []
        var py: CGFloat = -99, n = 0
        for (i, q) in c.yours.sorted(by: { $0.k > $1.k }).enumerated() {
            let y = Y(q.k)
            n = y - py < 11 ? n + 1 : 0
            py = y
            diamonds.append(("\(i)\(q.k)\(q.side)\(q.type)", y, n % 2 == 1))
        }
        let on = sel != nil
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(on ? S.pTrack : Color.clear)
                .animation(reduce ? nil : .easeOut(duration: 0.2), value: on)
            ForEach(ws) { w in
                let picked = sel == w.id, y = Y(w.k), col = PWallKind.color(w.label)
                let inset = (w.label == "accelerator" ? 0.22 : 0.12) * Self.W, h: CGFloat = picked ? 5 : 3
                Group {
                    if w.label == "accelerator" {
                        PDash(color: col, on: 5, off: 3).frame(width: Self.W - 2 * inset, height: h)
                    } else {
                        RoundedRectangle(cornerRadius: 3).fill(col).frame(width: Self.W - 2 * inset, height: h)
                    }
                }
                .scaleEffect(x: grown ? 1 : 0.001, anchor: .center)
                .animation(reduce ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.45).delay(delay), value: grown)
                .offset(x: inset, y: y - (picked ? 1 : 0))
                .animation(reduce ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.2), value: picked)
                Text(PF.strike(w.k)).sType(SType(size: 12, weight: picked ? 800 : 700, line: 14, tracking: 0))
                    .foregroundStyle(col)
                    .lineLimit(1)
                    .frame(width: Self.W)
                    .offset(y: ty[w.id] ?? (y - 17))
                    .allowsHitTesting(false)
                Button { tap(w.id) } label: { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .frame(width: Self.W, height: 30)
                    .offset(y: y - 15)
                    .accessibilityLabel("\(PF.monthDay(c.e)) \(PF.strike(w.k)) \(PWallKind.name(w.label))")
                    .accessibilityAddTraits(picked ? [.isSelected] : [])
            }
            ForEach(diamonds, id: \.id) { d in
                Rectangle().fill(S.ink)
                    .overlay(Rectangle().strokeBorder(S.paper, lineWidth: 2))
                    .frame(width: 10, height: 10)
                    .rotationEffect(.degrees(45))
                    .scaleEffect(grown ? 1 : 0.3)
                    .opacity(grown ? 1 : 0)
                    .animation(reduce ? nil : .spring(response: 0.35, dampingFraction: 0.6).delay(0.3), value: grown)
                    .position(x: d.left ? Self.W * 0.06 + 5 : Self.W * 0.94 - 5, y: d.y)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if c.walls.isEmpty {
                Button { tap("") } label: { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .frame(width: Self.W, height: Self.H)
                    .accessibilityLabel("\(PF.monthDay(c.e)), no walls saved")
            }
        }
        .frame(width: Self.W, height: Self.H, alignment: .topLeading)
    }
}

// MARK: - Parts

/// A dashed horizontal stroke filling its frame (the Accelerator, today's price).
struct PDash: View {
    let color: Color
    let on: CGFloat
    let off: CGFloat
    var round = false
    var body: some View {
        GeometryReader { g in
            Path { p in p.move(to: CGPoint(x: 0, y: g.size.height / 2)); p.addLine(to: CGPoint(x: g.size.width, y: g.size.height / 2)) }
                .stroke(color, style: StrokeStyle(lineWidth: g.size.height, lineCap: round ? .round : .butt, dash: [on, off]))
        }
    }
}

/// The net delta line through fixed x positions, its y values animatable so a picked wall morphs the dashed line.
struct PRiskLine: Shape {
    let xs: [CGFloat]
    var ys: PVec
    var animatableData: PVec { get { ys } set { ys = newValue } }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for (i, x) in xs.enumerated() where i < ys.v.count {
            let pt = CGPoint(x: x, y: ys.v[i])
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

/// An array of doubles that SwiftUI can animate between (same length both ends).
struct PVec: VectorArithmetic {
    var v: [Double]
    init(_ v: [Double]) { self.v = v }
    static var zero: PVec { PVec([]) }
    private static func zip(_ a: [Double], _ b: [Double], _ f: (Double, Double) -> Double) -> [Double] {
        (0..<max(a.count, b.count)).map { f($0 < a.count ? a[$0] : 0, $0 < b.count ? b[$0] : 0) }
    }
    static func + (a: PVec, b: PVec) -> PVec { PVec(zip(a.v, b.v, +)) }
    static func - (a: PVec, b: PVec) -> PVec { PVec(zip(a.v, b.v, -)) }
    mutating func scale(by r: Double) { v = v.map { $0 * r } }
    var magnitudeSquared: Double { v.reduce(0) { $0 + $1 * $1 } }
}

/// A wrap with its own row and column gaps (the legend: 4 between rows, 12 between items).
private struct PRiskWrap: Layout {
    var h: CGFloat
    var v: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let W = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, w: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > W { y += row + v; x = 0; row = 0 }
            x += z.width + h; row = max(row, z.height); w = max(w, x - h)
        }
        return CGSize(width: proposal.width ?? w, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > b.minX && x + z.width > b.maxX { y += row + v; x = b.minX; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + h; row = max(row, z.height)
        }
    }
}
