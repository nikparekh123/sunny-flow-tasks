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
