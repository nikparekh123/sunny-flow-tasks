//
//  PositionDG.swift
//  Sunny
//
//  Block 13 (handoff 28) · the Delta and Gamma face: what happens if the stock
//  jumps 3 to 10%. Bought pulls long (green), Sold pulls short (red), Delta is
//  what is left (the ink line); a dashed line where it goes short. One slider
//  for every card and the Home map (router.jump). sunny-home prices it: every
//  open leg at its own IV, an instant jump from today's price. Handoff 32
//  (13g): with the week's plan the face runs 10% down to 10% up (PDGWide),
//  the walls on the axis, Thin under 25% of long delta, and the hedge as an
//  action with its cost, the same numbers as Gamma and To do.
//

import SwiftUI

struct PDGFace: View {
    let t: String
    let dg: DGBook
    let width: CGFloat
    /// With the week's plan and the wide series the face runs 10% down to 10% up (handoff 32, 13g).
    var plan: NamePlan? = nil
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        if let s2 = dg.ser2, s2.count >= 41 { PDGWide(t: t, dg: dg, ser: s2, width: width, plan: plan) } else { jumpFace }
    }

    @ViewBuilder private var jumpFace: some View {
        @Bindable var r = router
        let m = Double(router.jump), a = dg.at(m), st = dg.state(m)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                (Text("If \(t) jumps ") + Text("+\(router.jump)%").foregroundStyle(S.ink).font(SType(size: 13, weight: 700, line: 16, tracking: 0).font(tabular: true))
                 + Text(dg.sdOf(m).map { " · " + String(format: "%.1f", $0) + " SD" } ?? ""))
                    .sType(SType(size: 13, weight: 500, line: 16, tracking: 0))
                    .foregroundStyle(S.muted)
                    .contentTransition(.numericText(value: m))
                Spacer(minLength: 0)
                Text(Self.word(st)).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false)
                    .foregroundStyle(Self.tone(st))
                    .animation(.easeInOut(duration: 0.25), value: st)
            }
            .lineLimit(1)
            VStack(alignment: .leading, spacing: 6) {
                JumpSlider(value: $r.jump)
                VStack(alignment: .leading, spacing: 6) {
                    PDGChart(dg: dg, m: m, width: width)
                    HStack(spacing: 0) {
                        Text("0%").frame(maxWidth: .infinity, alignment: .leading)
                        Text("if it jumps 5%")
                        Text("10%").frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .sType(SType(size: 11, weight: 600, line: 14, tracking: 0))
                    .foregroundStyle(S.pNeutral)
                }
            }
            Spacer(minLength: 0)
            stats(a)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
    }

    private func stats(_ a: DGBook.Point) -> some View {
        let sd = { (x: Double) in dg.sdOf(x).map { String(format: "%.1f", $0) + " SD" } ?? "" }
        let f1 = { (x: Double) in x.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(x)) : String(format: "%.1f", x) }
        let cells: [(String, String, Color)] = [
            (dg.thin.map { "+\(f1($0))%" } ?? "Past 10%", dg.thin.map { "safe · " + sd($0) } ?? "safe", S.ink),
            (dg.sh.map { "+\(f1($0))%" } ?? "Never", dg.sh.map { "short · " + sd($0) } ?? "goes short", dg.sh == nil ? S.ink : S.red),
            (PF.usd(a.gb), "costs · " + String(format: "%.1f", dg.weeks(Double(router.jump))) + " wk", S.red),
        ]
        return HStack(alignment: .top, spacing: 8) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.0).sType(SType(size: 17, weight: 700, line: 20, tracking: 0)).foregroundStyle(c.2)
                        .contentTransition(.numericText(value: a.gb))
                    Text(c.1).sType(SType(size: 12, weight: 500, line: 14, tracking: 0)).foregroundStyle(S.muted)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 16)
        .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
        .animation(reduce ? nil : .easeOut(duration: 0.25), value: router.jump)
    }

    static func word(_ s: DGBook.State) -> String { switch s { case .long: "Stays long"; case .thin: "Thin"; case .short: "Goes short" } }
    static func tone(_ s: DGBook.State) -> Color { switch s { case .long: S.green; case .thin: S.orangeDeep; case .short: S.red } }
}

/// Bought area, Sold area, the Delta line, zero, where it goes short, the slider's move.
private struct PDGChart: View {
    let dg: DGBook
    let m: Double
    let width: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    static let H: CGFloat = 136

    var body: some View {
        let W = width, H = Self.H, z = H / 2
        let pts = dg.ser.compactMap { r -> (x: CGFloat, b: Double, s: Double, n: Double)? in
            guard r.count >= 4 else { return nil }
            return (CGFloat(r[0] / 10) * W, r[1], r[2], r[3])
        }
        let M = max(1, pts.map { max(abs($0.b), abs($0.s), abs($0.n)) }.max() ?? 1)
        let Y = { (v: Double) -> CGFloat in z - CGFloat(v / M) * (z - 6) }
        let a = dg.at(m), xm = CGFloat(m / 10) * W
        let area = { (f: (Double, Double, Double) -> Double) -> Path in
            Path { p in
                p.move(to: CGPoint(x: 0, y: z))
                for q in pts { p.addLine(to: CGPoint(x: q.x, y: Y(f(q.b, q.s, q.n)))) }
                p.addLine(to: CGPoint(x: W, y: z)); p.closeSubpath()
            }
        }
        ZStack(alignment: .topLeading) {
            area { b, _, _ in b }.fill(Color(red: 101 / 255, green: 196 / 255, blue: 102 / 255).opacity(0.38))
            area { _, s, _ in s }.fill(Color(red: 235 / 255, green: 75 / 255, blue: 70 / 255).opacity(0.42))
            Path { p in p.move(to: CGPoint(x: 0, y: z)); p.addLine(to: CGPoint(x: W, y: z)) }
                .stroke(S.ink.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            if let sh = dg.sh {
                let xk = CGFloat(sh / 10) * W
                Path { p in p.move(to: CGPoint(x: xk, y: 0)); p.addLine(to: CGPoint(x: xk, y: H)) }
                    .stroke(S.ink, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                Text("short at +\(sh.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(sh)) : String(format: "%.1f", sh))%")
                    .sType(SType(size: 11, weight: 600, line: 13, tracking: 0))
                    .foregroundStyle(S.ink)
                    .fixedSize()
                    .offset(x: min(xk + 5, W - 110), y: z - 22)
            }
            Path { p in p.move(to: CGPoint(x: xm, y: 0)); p.addLine(to: CGPoint(x: xm, y: H)) }
                .stroke(S.ink.opacity(0.3), lineWidth: 1)
            Path { p in for (i, q) in pts.enumerated() { let pt = CGPoint(x: q.x, y: Y(q.n)); i == 0 ? p.move(to: pt) : p.addLine(to: pt) } }
                .stroke(S.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            Text("Bought").sType(SType(size: 11, weight: 600, line: 13, tracking: 0)).foregroundStyle(S.green).offset(x: 4, y: 2)
            Text("Sold").sType(SType(size: 11, weight: 600, line: 13, tracking: 0)).foregroundStyle(S.red).offset(x: 4, y: H - 15)
            ForEach([(a.b, S.green), (a.s, S.red), (a.n, a.n < 0 ? S.red : S.ink)].indices, id: \.self) { i in
                let d = [(a.b, S.green), (a.s, S.red), (a.n, a.n < 0 ? S.red : S.ink)][i]
                Circle().fill(d.1)
                    .frame(width: 10, height: 10)
                    .background(Circle().fill(S.paper).frame(width: 14, height: 14))
                    .position(x: xm, y: Y(d.0))
            }
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .animation(reduce ? nil : .easeOut(duration: 0.22), value: m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Delta if it jumps \(Int(m)) percent: bought \(PF.usd(a.b)), sold \(PF.usd(a.s)), left \(a.n < 0 ? "short" : "long") \(PF.usd(a.n))")
    }
}

/// The jump slider, 3 to 10% in 1% steps: one value for every card and the Home map. On a card it
/// is 28 tall with a 30 x 20 thumb; on the map 40 tall with a 38 x 24 thumb and labelled stops.
struct JumpSlider: View {
    @Binding var value: Int
    /// The Home map shows the stops under the track.
    var stops = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let H: CGFloat = stops ? 40 : 28, trackY: CGFloat = stops ? 18 : 12, tw: CGFloat = stops ? 38 : 30, th: CGFloat = stops ? 24 : 20
        let dark = scheme == .dark, trk = Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255).opacity(dark ? 0.36 : 0.2)
        VStack(spacing: 2) {
            GeometryReader { g in
                let W = g.size.width, xAt = { (k: Int) -> CGFloat in tw / 2 + CGFloat(k - 3) / 7 * (W - tw) }, x = xAt(value)
                ZStack(alignment: .topLeading) {
                    Capsule().fill(trk).frame(width: W, height: 4).offset(y: trackY)
                    Capsule().fill(S.ink).frame(width: x, height: 4).offset(y: trackY)
                    if stops {
                        ForEach(3...10, id: \.self) { k in
                            Circle().fill(trk).frame(width: 4, height: 4).offset(x: xAt(k) - 2, y: 30)
                        }
                    }
                    Capsule().fill(Color.white.opacity(dark ? 0.28 : 0.6))
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(dark ? 0.3 : 0.9), lineWidth: 0.5))
                        .frame(width: tw, height: th)
                        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                        .shadow(color: .black.opacity(0.16), radius: 4, y: 3)
                        .offset(x: x - tw / 2, y: trackY + 2 - th / 2)
                }
                .frame(width: W, height: H, alignment: .topLeading)
                .contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let c = min(10, max(3, Int(((v.location.x - tw / 2) / max(1, W - tw) * 7).rounded()) + 3))
                    if c != value {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(reduce ? nil : S.standard(0.2)) { value = c }
                    }
                })
            }
            .frame(height: H)
            if stops {
                GeometryReader { g in
                    let W = g.size.width
                    ForEach(3...10, id: \.self) { k in
                        Text("\(k)%").sType(SType(size: 11, weight: 600, line: 14, tracking: 0))
                            .foregroundStyle(k == value ? S.ink : S.pNeutral)
                            .fixedSize()
                            .position(x: tw / 2 + CGFloat(k - 3) / 7 * (W - tw), y: 7)
                    }
                }
                .frame(height: 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jump")
        .accessibilityValue("\(value) percent")
        .accessibilityAdjustableAction { d in
            switch d {
            case .increment: value = min(10, value + 1)
            case .decrement: value = max(3, value - 1)
            @unknown default: break
            }
        }
    }
}

// MARK: - 13g · 10% down to 10% up

struct PDGWide: View {
    let t: String
    let dg: DGBook
    /// [move %, bought, sold, net, cost $] every 0.5% from -10 to +10 (41 rows).
    let ser: [[Double]]
    let width: CGFloat
    let plan: NamePlan?
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce

    enum State { case long, thin, short }
    private func row(_ m: Double) -> [Double] { ser[max(0, min(ser.count - 1, Int(((m + 10) * 2).rounded())))] }
    /// Thin: net under 25% of today's long delta (fixed). Short: below zero.
    private func state(_ m: Double) -> State {
        let r = row(m), n = r[safe: 3] ?? 0, long = dg.long0 ?? (ser[20][safe: 1] ?? 0)
        return n < 0 ? .short : n < 0.25 * long ? .thin : .long
    }
    static func moveText(_ m: Int) -> String { m > 0 ? "+\(m)%" : m < 0 ? "\(abs(m))% down" : "flat" }

    var body: some View {
        @Bindable var r = router
        let m = Double(router.move), st = state(m)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                (Text("If \(t) moves ") + Text(Self.moveText(router.move)).foregroundStyle(S.ink).font(SType(size: 13, weight: 700, line: 16, tracking: 0).font(tabular: true))
                 + Text(dg.sdOf(abs(m)).map { " · " + String(format: "%.1f", $0) + " SD" } ?? ""))
                    .sType(SType(size: 13, weight: 500, line: 16, tracking: 0))
                    .foregroundStyle(S.muted)
                    .contentTransition(.numericText(value: m))
                Spacer(minLength: 0)
                Text(Self.word(st)).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false)
                    .foregroundStyle(Self.tone(st))
                    .animation(.easeInOut(duration: 0.25), value: st)
            }
            .lineLimit(1)
            .padding(.bottom, -14)
            pnl(m)
            VStack(alignment: .leading, spacing: 6) {
                MoveSlider(value: $r.move, name: t)
                VStack(alignment: .leading, spacing: 6) {
                    let ws = walls
                    if !ws.isEmpty { wallLabels(ws) }
                    PDGWideChart(dg: dg, ser: ser, m: m, width: width, walls: ws)
                    HStack(spacing: 0) {
                        Text("10% down").frame(maxWidth: .infinity, alignment: .leading)
                        Text("today")
                        Text("10% up").frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .sType(SType(size: 11, weight: 600, line: 14, tracking: 0))
                    .foregroundStyle(S.muted)
                    (Text("Thin").fontWeight(.semibold).foregroundStyle(S.ink) + Text(" means net delta below 25% of long delta. ")
                     + Text("Short").fontWeight(.semibold).foregroundStyle(S.ink) + Text(" means below zero."))
                        .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false)
                        .foregroundStyle(S.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    hedge
                }
            }
            Spacer(minLength: 0)
            stats(m)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
    }

    // MARK: P&L of the move (Nik, 26 Oct 2026): every leg re-priced at once, plus shares; red, never a minus sign

    private func pnl(_ m: Double) -> some View {
        let v = row(m)[safe: 5], lo = ser.first?[safe: 5], hi = ser.last?[safe: 5]
        let word = { (x: Double) in x >= 0 ? "gain" : "loss" }, tone = { (x: Double) in x >= 0 ? S.green : S.red }
        return Group {
            if let v {
                (Text("P&L ") + Text("\(PF.usd(v)) \(word(v))").foregroundStyle(tone(v)).bold()
                 + Text(lo.map { " · 10% down \(PF.usd($0)) \(word($0))" } ?? "")
                 + Text(hi.map { " · 10% up \(PF.usd($0)) \(word($0))" } ?? ""))
                    .sType(SType(size: 13, weight: 500, line: 16, tracking: 0))
                    .foregroundStyle(S.muted)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .contentTransition(.numericText(value: v))
                    .accessibilityLabel("P and L if it moves \(Self.moveText(Int(m))): \(PF.usd(v)) \(word(v))")
            }
        }
    }

    // MARK: Walls on the axis

    struct Wall: Identifiable { let id: Int; let k: Double; let call: Bool; let label: String; let m: Double }
    /// The week's 1st and 2nd walls each side within 10% of the price.
    private var walls: [Wall] {
        (plan?.walls ?? []).enumerated().map { i, w in Wall(id: i, k: w.k, call: w.side == "call", label: w.label, m: (w.k / dg.px - 1) * 100) }
            .filter { abs($0.m) <= 10 }.sorted { $0.m < $1.m }
    }
    private func xAt(_ m: Double) -> CGFloat { CGFloat((m + 10) / 20) * width }

    /// Labels above the chart: walls on one side within 34 pt share one ("98 · 99 Accel.").
    private func wallLabels(_ ws: [Wall]) -> some View {
        var cl: [[Wall]] = []
        for w in ws {
            if let c = cl.last, let l = c.last, xAt(w.m) - xAt(l.m) < 34, c[0].call == w.call { cl[cl.count - 1].append(w) } else { cl.append([w]) }
        }
        let full = ["ceiling": "Ceiling", "floor": "Floor", "accelerator": "Accelerator", "unclear": "Unclear"]
        let short = ["ceiling": "Ceil.", "floor": "Floor", "accelerator": "Accel.", "unclear": "Unclear"]
        let font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let txts = cl.map { c in
            let same = c.allSatisfy { $0.label == c[0].label }
            return (c.map { PF.strike($0.k) }.joined(separator: " · ") + " " + (same ? ((c.count > 1 ? short : full)[c[0].label] ?? "") : "")).trimmingCharacters(in: .whitespaces)
        }
        let wds = txts.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) + 2 }
        // Centred on their walls, then pushed apart left to right (8 pt) and back inside the width.
        var ls = cl.indices.map { i in max(0, min(width - wds[i], cl[i].reduce(0) { $0 + xAt($1.m) } / CGFloat(cl[i].count) - wds[i] / 2)) }
        for i in ls.indices.dropFirst() { ls[i] = max(ls[i], ls[i - 1] + wds[i - 1] + 8) }
        for i in ls.indices.reversed() { ls[i] = min(ls[i], (i + 1 < ls.count ? ls[i + 1] - 8 : width) - wds[i]) }
        return ZStack(alignment: .topLeading) {
            ForEach(Array(cl.enumerated()), id: \.offset) { i, c in
                Text(txts[i]).sType(SType(size: 11, weight: 600, line: 14, tracking: 0))
                    .foregroundStyle(c[0].call ? S.blue : S.orangeDeep)
                    .fixedSize()
                    .offset(x: max(0, ls[i]))
                    .accessibilityLabel(c.map { "\(PF.strike($0.k)) \(full[$0.label] ?? ""), \(String(format: "%.1f", abs($0.m)))% \($0.m >= 0 ? "above" : "below")" }.joined(separator: "; "))
            }
        }
        .frame(width: width, height: 14, alignment: .topLeading)
    }

    // MARK: The hedge, from the week's plan (the same function as Gamma and To do)

    @ViewBuilder private var hedge: some View {
        if let h = plan?.hedge {
            let through = "+\(F.trim(h.target.sd)) SD" + (h.target.pct.map { " (+\(F.trim($0))%)" } ?? "")
            if h.add > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add \(PWords.n(h.add, "\(PF.monthDay(h.exp)) \(PF.strike(h.k)) call")) to stay safe through \(through).")
                        .sType(SType(size: 15, weight: 600, line: 20, tracking: 0)).foregroundStyle(S.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Hedge cost \(PF.usd(h.cost)) = \(String(format: "%.1f", h.weeks ?? 0)) weeks of premium.")
                        .sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.muted)
                }
                .padding(.vertical, 12).padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(S.surface))
                .padding(.top, 6)
            } else {
                Text("No hedge needed. Delta stays positive through \(through).")
                    .sType(SType(size: 13, weight: 600, line: 18, tracking: 0), tabular: false).foregroundStyle(S.green)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
    }

    // MARK: Safe to, goes short, the move's cost

    private func stats(_ m: Double) -> some View {
        let sd = { (x: Double) in dg.sdOf(x).map { String(format: "%.1f", $0) + " SD" } ?? "" }
        let gb = row(m)[safe: 4] ?? 0, wk = dg.wk > 0 ? gb / dg.wk : 0
        let cells: [(String, String, Color)] = [
            (dg.thin25.map { "+\(F.trim($0))%" } ?? "Past 10%", dg.thin25.map { "safe · " + sd($0) } ?? "safe", S.ink),
            (dg.sh.map { "+\(F.trim($0))%" } ?? "Never", dg.sh.map { "short · " + sd($0) } ?? "goes short", dg.sh == nil ? S.ink : S.red),
            (PF.usd(gb), "costs · " + String(format: "%.1f", wk) + " wk", S.red),
        ]
        return HStack(alignment: .top, spacing: 8) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.0).sType(SType(size: 17, weight: 700, line: 20, tracking: 0)).foregroundStyle(c.2)
                        .contentTransition(.numericText(value: gb))
                    Text(c.1).sType(SType(size: 12, weight: 500, line: 14, tracking: 0)).foregroundStyle(S.muted)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 16)
        .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
        .animation(reduce ? nil : .easeOut(duration: 0.25), value: router.move)
    }

    static func word(_ s: State) -> String { switch s { case .long: "Stays long"; case .thin: "Thin"; case .short: "Goes short" } }
    static func tone(_ s: State) -> Color { switch s { case .long: S.green; case .thin: S.orangeDeep; case .short: S.red } }
}

/// Bought green above, Sold red below, net as the line; the walls, today and where it goes short.
private struct PDGWideChart: View {
    let dg: DGBook
    let ser: [[Double]]
    let m: Double
    let width: CGFloat
    let walls: [PDGWide.Wall]
    @Environment(\.accessibilityReduceMotion) private var reduce
    static let H: CGFloat = 136

    var body: some View {
        let W = width, H = Self.H, z = H / 2
        let X = { (m: Double) -> CGFloat in CGFloat((m + 10) / 20) * W }
        let pts = ser.compactMap { r -> (x: CGFloat, b: Double, s: Double, n: Double)? in
            r.count >= 4 ? (X(r[0]), r[1], r[2], r[3]) : nil
        }
        let M = max(1, pts.map { max(abs($0.b), abs($0.s), abs($0.n)) }.max() ?? 1)
        let Y = { (v: Double) -> CGFloat in z - CGFloat(v / M) * (z - 6) }
        let r = ser[max(0, min(ser.count - 1, Int(((m + 10) * 2).rounded())))]
        let a = (b: r[safe: 1] ?? 0, s: r[safe: 2] ?? 0, n: r[safe: 3] ?? 0), xm = X(m)
        let area = { (f: (Double, Double) -> Double) -> Path in
            Path { p in
                p.move(to: CGPoint(x: 0, y: z))
                for q in pts { p.addLine(to: CGPoint(x: q.x, y: Y(f(q.b, q.s)))) }
                p.addLine(to: CGPoint(x: W, y: z)); p.closeSubpath()
            }
        }
        let vline = { (x: CGFloat) in Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: H)) } }
        ZStack(alignment: .topLeading) {
            ForEach(walls) { w in
                vline(X(w.m)).stroke(w.call ? S.blue : S.orangeDeep,
                                     style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: w.label == "accelerator" ? [4, 3] : w.label == "unclear" ? [1, 3] : []))
            }
            vline(X(0)).stroke(S.ink.opacity(0.18), lineWidth: 1)
            area { b, _ in b }.fill(Color(red: 101 / 255, green: 196 / 255, blue: 102 / 255).opacity(0.38))
            area { _, s in s }.fill(Color(red: 235 / 255, green: 75 / 255, blue: 70 / 255).opacity(0.42))
            Path { p in p.move(to: CGPoint(x: 0, y: z)); p.addLine(to: CGPoint(x: W, y: z)) }
                .stroke(S.ink.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            vline(xm).stroke(S.ink.opacity(0.3), lineWidth: 1)
            if let sh = dg.sh {
                let xk = X(sh)
                vline(xk).stroke(S.ink, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                Text("short at +\(F.trim(sh))%")
                    .sType(SType(size: 11, weight: 600, line: 13, tracking: 0))
                    .foregroundStyle(S.ink)
                    .fixedSize()
                    .offset(x: xk > W * 0.72 ? xk - 92 : xk + 5, y: z - 17)
            }
            Path { p in for (i, q) in pts.enumerated() { let pt = CGPoint(x: q.x, y: Y(q.n)); i == 0 ? p.move(to: pt) : p.addLine(to: pt) } }
                .stroke(S.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            Text("Bought").sType(SType(size: 11, weight: 600, line: 13, tracking: 0)).foregroundStyle(S.green).offset(x: 4, y: 2)
            Text("Sold").sType(SType(size: 11, weight: 600, line: 13, tracking: 0)).foregroundStyle(S.red).offset(x: 4, y: H - 15)
            let dots: [(Double, Color)] = [(a.b, S.green), (a.s, S.red), (a.n, a.n < 0 ? S.red : S.ink)]
            ForEach(dots.indices, id: \.self) { i in
                Circle().fill(dots[i].1)
                    .frame(width: 10, height: 10)
                    .background(Circle().fill(S.paper).frame(width: 14, height: 14))
                    .position(x: xm, y: Y(dots[i].0))
            }
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .animation(reduce ? nil : .easeOut(duration: 0.22), value: m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Delta if it moves \(PDGWide.moveText(Int(m))): bought \(PF.count(a.b)) shares, sold \(PF.count(a.s)), left \(a.n < 0 ? "short" : "long") \(PF.count(a.n))")
    }
}

/// The move slider, 10% down to 10% up in 1% steps: a tick at today, the fill grows from the center.
/// One value for every card (router.move). 28 tall with a 30 x 20 glass thumb, as the jump slider.
struct MoveSlider: View {
    @Binding var value: Int
    let name: String
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let H: CGFloat = 28, trackY: CGFloat = 12, tw: CGFloat = 30, th: CGFloat = 20
        let dark = scheme == .dark, trk = Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255).opacity(dark ? 0.36 : 0.2)
        GeometryReader { g in
            let W = g.size.width, xAt = { (k: Int) -> CGFloat in tw / 2 + CGFloat(k + 10) / 20 * (W - tw) }, x = xAt(value), c = xAt(0)
            ZStack(alignment: .topLeading) {
                Capsule().fill(trk).frame(width: W, height: 4).offset(y: trackY)
                RoundedRectangle(cornerRadius: 1).fill(S.muted).frame(width: 2, height: 12).offset(x: c - 1, y: 8)
                Capsule().fill(S.ink).frame(width: abs(x - c), height: 4).offset(x: min(x, c), y: trackY)
                Capsule().fill(Color.white.opacity(dark ? 0.28 : 0.6))
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(dark ? 0.3 : 0.9), lineWidth: 0.5))
                    .frame(width: tw, height: th)
                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                    .shadow(color: .black.opacity(0.16), radius: 4, y: 3)
                    .offset(x: x - tw / 2, y: trackY + 2 - th / 2)
            }
            .frame(width: W, height: H, alignment: .topLeading)
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { v in
                let k = min(10, max(-10, Int(((v.location.x - tw / 2) / max(1, W - tw) * 20).rounded()) - 10))
                if k != value {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(reduce ? nil : S.standard(0.2)) { value = k }
                }
            })
        }
        .frame(height: H)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("If \(name) moves")
        .accessibilityValue(PDGWide.moveText(value))
        .accessibilityAdjustableAction { d in
            switch d {
            case .increment: value = min(10, value + 1)
            case .decrement: value = max(-10, value - 1)
            @unknown default: break
            }
        }
    }
}
