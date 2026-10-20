//
//  PositionDG.swift
//  Sunny
//
//  Block 13 (handoff 28) · the Delta and Gamma face: what happens if the stock
//  jumps 3 to 10%. Bought pulls long (green), Sold pulls short (red), Delta is
//  what is left (the ink line); a dashed line where it goes short. One slider
//  for every card and the Home map (router.jump). sunny-home prices it: every
//  open leg at its own IV, an instant jump from today's price.
//

import SwiftUI

struct PDGFace: View {
    let t: String
    let dg: DGBook
    let width: CGFloat
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        @Bindable var r = router
        let m = Double(router.jump), a = dg.at(m), st = dg.state(m)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                (Text("If \(t) jumps ") + Text("+\(router.jump)%").foregroundStyle(S.ink).font(SType(size: 15, weight: 700, line: 20, tracking: 0).font())
                 + Text(dg.sdOf(m).map { " · " + String(format: "%.1f", $0) + " SD" } ?? ""))
                    .sType(SType(size: 15, weight: 500, line: 20, tracking: 0))
                    .foregroundStyle(S.muted)
                    .contentTransition(.numericText(value: m))
                Spacer(minLength: 0)
                Text(Self.word(st)).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false)
                    .foregroundStyle(Self.tone(st))
                    .animation(.easeInOut(duration: 0.25), value: st)
            }
            .lineLimit(1)
            JumpSlider(value: $r.jump)
            PDGChart(dg: dg, m: m, width: width)
            HStack(spacing: 0) {
                Text("0%").frame(maxWidth: .infinity, alignment: .leading)
                Text("if it jumps 5%")
                Text("10%").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .sType(SType(size: 13, weight: 500, line: 16, tracking: 0))
            .foregroundStyle(S.muted)
            stats(a)
        }
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
                    Text(c.0).sType(SType(size: 20, weight: 700, line: 24, tracking: -0.01)).foregroundStyle(c.2)
                        .contentTransition(.numericText(value: a.gb))
                    Text(c.1).sType(SType(size: 13, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.muted)
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
                    .sType(SType(size: 13, weight: 600, line: 16, tracking: 0))
                    .foregroundStyle(S.ink)
                    .fixedSize()
                    .offset(x: min(xk + 5, W - 110), y: z - 22)
            }
            Path { p in p.move(to: CGPoint(x: xm, y: 0)); p.addLine(to: CGPoint(x: xm, y: H)) }
                .stroke(S.ink.opacity(0.3), lineWidth: 1)
            Path { p in for (i, q) in pts.enumerated() { let pt = CGPoint(x: q.x, y: Y(q.n)); i == 0 ? p.move(to: pt) : p.addLine(to: pt) } }
                .stroke(S.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            Text("Bought").sType(SType(size: 13, weight: 600, line: 16, tracking: 0)).foregroundStyle(S.green).offset(x: 4, y: 2)
            Text("Sold").sType(SType(size: 13, weight: 600, line: 16, tracking: 0)).foregroundStyle(S.red).offset(x: 4, y: H - 18)
            ForEach([(a.b, S.green), (a.s, S.red), (a.n, a.n < 0 ? S.red : S.ink)].indices, id: \.self) { i in
                let d = [(a.b, S.green), (a.s, S.red), (a.n, a.n < 0 ? S.red : S.ink)][i]
                Circle().fill(d.1)
                    .overlay(Circle().strokeBorder(S.paper, lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
                    .position(x: xm, y: Y(d.0))
            }
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .animation(reduce ? nil : .easeOut(duration: 0.22), value: m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Delta if it jumps \(Int(m)) percent: bought \(PF.usd(a.b)), sold \(PF.usd(a.s)), left \(a.n < 0 ? "short" : "long") \(PF.usd(a.n))")
    }
}

/// The jump slider, 3 to 10% in 1% steps: one value for every card and the Home map.
struct JumpSlider: View {
    @Binding var value: Int
    /// The Home map shows the stops under the track.
    var stops = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { g in
                let W = g.size.width, x = CGFloat(value - 3) / 7 * (W - 36) + 18
                ZStack(alignment: .leading) {
                    Capsule().fill(S.track).frame(height: 5)
                    Capsule().fill(S.ink).frame(width: x, height: 5)
                    Capsule().fill(Color.white.opacity(0.85))
                        .frame(width: 38, height: 26)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
                        .offset(x: x - 19)
                }
                .frame(height: 36)
                .contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let c = min(10, max(3, Int(((v.location.x - 18) / max(1, W - 36) * 7).rounded()) + 3))
                    if c != value {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(reduce ? nil : .easeOut(duration: 0.22)) { value = c }
                    }
                })
            }
            .frame(height: 36)
            if stops {
                GeometryReader { g in
                    let W = g.size.width
                    ForEach(3...10, id: \.self) { k in
                        VStack(spacing: 6) {
                            Circle().fill(S.muted.opacity(0.4)).frame(width: 4, height: 4)
                            Text("\(k)%").sType(SType(size: 13, weight: k == value ? 700 : 500, line: 16, tracking: 0))
                                .foregroundStyle(k == value ? S.ink : S.muted)
                                .fixedSize()
                        }
                        .position(x: CGFloat(k - 3) / 7 * (W - 36) + 18, y: 13)
                    }
                }
                .frame(height: 26)
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
