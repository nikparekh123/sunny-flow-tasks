//
//  SunnyDeltaGamma.swift
//  Sunny
//
//  Block 16 (handoff 28, 20 Oct 2026) · the Delta and Gamma map, under Theta on
//  Home, replacing the Delta card. Every name placed by how much of today's
//  delta a jump leaves (left still long, past the dashed line short) and what
//  the jump costs in weeks of premium (higher costs more). Nine cells, gray
//  where there is nothing to do, red where you act. One slider (router.jump),
//  shared with every Position card. A tap opens that name's card on Delta and
//  Gamma. It reads the same book as the cards (writes.names[].dg).
//

import SwiftUI

struct SunnyDeltaGamma: View {
    let home: HomePayload
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.colorScheme) private var scheme

    private var names: [(t: String, dg: DGBook)] {
        home.writes.names.compactMap { n in n.dg?.value.map { (n.ticker, $0) } }.sorted { $0.t < $1.t }
    }

    var body: some View {
        @Bindable var r = router
        let N = names, m = Double(router.jump)
        let D0 = N.reduce(0) { $0 + $1.dg.d0Usd }, Dm = N.reduce(0) { $0 + $1.dg.at(m).n }
        let GB = N.reduce(0) { $0 + $1.dg.at(m).gb }, WP = N.reduce(0) { $0 + $1.dg.wk }
        let sds = N.compactMap(\.dg.sd), sdAvg = sds.isEmpty ? nil : sds.reduce(0, +) / Double(sds.count)
        VStack(alignment: .leading, spacing: 16) {
            Text("Delta and Gamma").sType(.sectionTitle, tabular: false)
            HStack {
                Text("If stocks jump")
                Spacer(minLength: 0)
                Text(sdAvg.map { String(format: "%.1f SD", m / $0) } ?? "")
                    .contentTransition(.numericText(value: m))
            }
            .sType(SType(size: 17, weight: 500, line: 22, tracking: 0))
            .foregroundStyle(S.muted)
            JumpSlider(value: $r.jump, stops: true)
            HStack(alignment: .top, spacing: 16) {
                hero(Dm < 0 ? "Short at +\(router.jump)%" : "Still long at +\(router.jump)%", PF.usd(Dm), Dm < 0 ? S.red : S.ink,
                     "down from \(PF.usd(D0))")
                hero("The jump costs", PF.usd(GB), S.red, WP > 0 ? String(format: "%.1f weeks of premium", GB / WP) : "")
            }
            Text("Right is less long, past the dashed line it's short. Higher costs more. Tap a name to open it in Positions.")
                .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                .foregroundStyle(S.muted)
                .fixedSize(horizontal: false, vertical: true)
            DGMap(names: N, m: m)
            HStack {
                Text("← still long"); Spacer(); Text("short →")
            }
            .sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false)
            .foregroundStyle(S.muted)
            .padding(.top, -6)
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: S.rCard))
        .sunnyGlow()
    }

    private func hero(_ l: String, _ v: String, _ c: Color, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).sType(SType(size: 15, weight: 600, line: 20, tracking: 0)).foregroundStyle(S.muted)
            Text(v).sType(SType(size: 28, weight: 800, line: 30, tracking: -0.02)).foregroundStyle(c)
                .contentTransition(.numericText())
            Text(sub).sType(SType(size: 13, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.muted)
        }
        .lineLimit(1).minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduce ? nil : .easeOut(duration: 0.25), value: router.jump)
    }
}

/// The nine cells, a trail per name from today to the slider's move, the bubbles.
private struct DGMap: View {
    let names: [(t: String, dg: DGBook)]
    let m: Double
    @Environment(HomeRouter.self) private var router
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    static let H: CGFloat = 380
    static let CAP = 3.5

    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = Self.H
            let Xv = { (v: Double) -> CGFloat in 8 + CGFloat((1 - max(-1, min(1, v))) / 2) * (W - 16) }
            let Yw = { (w: Double) -> CGFloat in (H - 12) - CGFloat(min(1, max(0, w) / Self.CAP)) * (H - 24) }
            let XS = [0, Xv(0.5), Xv(0), W], YS = [0, Yw(2), Yw(1), H]
            let ink = scheme == .dark ? Color.white : S.ink
            let RK: [Color] = [ink.opacity(0.035), ink.opacity(0.075), Color(red: 235 / 255, green: 75 / 255, blue: 70 / 255).opacity(0.13),
                               Color(red: 235 / 255, green: 75 / 255, blue: 70 / 255).opacity(0.25), Color(red: 214 / 255, green: 52 / 255, blue: 55 / 255).opacity(0.42)]
            let pts = place(W: W, H: H, Xv: Xv, Yw: Yw)
            ZStack(alignment: .topLeading) {
                ForEach(0..<3, id: \.self) { i in
                    ForEach(0..<3, id: \.self) { j in
                        let x0 = XS[i] + (i > 0 ? 1 : 0), x1 = XS[i + 1] - (i < 2 ? 1 : 0)
                        let y0 = YS[j] + (j > 0 ? 1 : 0), y1 = YS[j + 1] - (j < 2 ? 1 : 0)
                        Rectangle().fill(RK[i + (2 - j)]).frame(width: max(0, x1 - x0), height: max(0, y1 - y0)).offset(x: x0, y: y0)
                    }
                }
                Path { p in p.move(to: CGPoint(x: Xv(0), y: 0)); p.addLine(to: CGPoint(x: Xv(0), y: H)) }
                    .stroke(Color(red: 179 / 255, green: 38 / 255, blue: 42 / 255).opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                label("Still long", x: (XS[0] + XS[1]) / 2, y: 14, c: S.muted)
                label("Thin", x: (XS[1] + XS[2]) / 2, y: 14, c: S.muted)
                label("Short", x: (XS[2] + XS[3]) / 2, y: 14, c: S.red)
                Text("Act first").sType(SType(size: 13, weight: 600, line: 16, tracking: 0)).foregroundStyle(S.red).fixedSize()
                    .position(x: W - 40, y: 32)
                Text("2 weeks").sType(SType(size: 13, weight: 600, line: 16, tracking: 0)).foregroundStyle(S.muted).fixedSize()
                    .position(x: W - 36, y: Yw(2) - 12)
                Text("1 week").sType(SType(size: 13, weight: 600, line: 16, tracking: 0)).foregroundStyle(S.muted).fixedSize()
                    .position(x: W - 32, y: Yw(1) - 12)
                // Trails from today to the move.
                ForEach(names, id: \.t) { n in
                    Path { p in
                        for (k, r) in n.dg.ser.enumerated() where r.count >= 5 && r[0] <= m + 0.01 {
                            let v = n.dg.d0Usd != 0 ? r[3] / (n.dg.d0Usd * (1 + r[0] / 100)) : 0
                            let pt = CGPoint(x: Xv(v), y: Yw(n.dg.wk > 0 ? r[4] / n.dg.wk : 0))
                            k == 0 ? p.move(to: pt) : p.addLine(to: pt)
                        }
                    }
                    .stroke(ink.opacity(0.24), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
                Circle().fill(S.ink).overlay(Circle().strokeBorder(S.paper, lineWidth: 2)).frame(width: 14, height: 14)
                    .position(x: Xv(1), y: Yw(0))
                Text("today").sType(SType(size: 13, weight: 600, line: 16, tracking: 0)).foregroundStyle(S.muted).fixedSize()
                    .position(x: Xv(1) + 30, y: Yw(0) - 16)
                ForEach(pts, id: \.t) { b in bubble(b) }
            }
            .frame(width: W, height: H, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .animation(reduce ? nil : .easeOut(duration: 0.25), value: m)
        }
        .frame(height: Self.H)
    }

    private func label(_ s: String, x: CGFloat, y: CGFloat, c: Color) -> some View {
        Text(s).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(c).fixedSize()
            .position(x: x, y: y)
    }

    private struct B { let t: String; let x: CGFloat; let y: CGFloat; let sz: CGFloat; let st: DGBook.State; let wk: Double }

    /// Size by today's delta; nudged apart so a bubble and its label never sit on another (Oct 20 final pass).
    private func place(W: CGFloat, H: CGFloat, Xv: (Double) -> CGFloat, Yw: (Double) -> CGFloat) -> [B] {
        let mx = max(1, names.map { abs($0.dg.d0Usd) }.max() ?? 1)
        var P = names.map { n -> (t: String, x: CGFloat, y: CGFloat, sz: CGFloat, st: DGBook.State, wk: Double) in
            let a = n.dg.at(m), v = n.dg.d0Usd != 0 ? a.n / (n.dg.d0Usd * (1 + m / 100)) : 0
            let sz = CGFloat(40 + 18 * (abs(n.dg.d0Usd) / mx).squareRoot())
            return (n.t, Xv(v), min(H - sz / 2 - 30, Yw(n.dg.weeks(m))), sz, n.dg.state(m), n.dg.weeks(m))
        }
        for _ in 0..<12 {
            for p in P.indices {
                for q in P.indices where q > p {
                    let need = (P[p].sz + P[q].sz) / 2 + 16
                    var dx = P[q].x - P[p].x, dy = P[q].y - P[p].y
                    let d = (dx * dx + dy * dy).squareRoot()
                    guard d < need else { continue }
                    if d < 0.5 { dx = 1; dy = 0 }
                    let k = (need - max(d, 0.5)) / 2 / max(d, 0.5)
                    P[p].x -= dx * k; P[p].y -= dy * k; P[q].x += dx * k; P[q].y += dy * k
                }
            }
            for i in P.indices {
                P[i].x = min(max(P[i].x, P[i].sz / 2 + 2), W - P[i].sz / 2 - 2)
                P[i].y = min(max(P[i].y, P[i].sz / 2 + 24), H - P[i].sz / 2 - 30)
            }
        }
        return P.map { B(t: $0.t, x: $0.x, y: $0.y, sz: $0.sz, st: $0.st, wk: $0.wk) }
    }

    private func bubble(_ b: B) -> some View {
        let fill: Color = b.st == .short ? S.red : b.st == .thin ? (scheme == .dark ? Color(white: 0.32) : Color(white: 0.86)) : S.paper
        let text: Color = b.st == .short ? .white : S.ink
        let held = b.t != "TSLA"
        return Button { if held { router.openCard(b.t, face: "dg") } } label: {
            VStack(spacing: 4) {
                Text(b.t).sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false)
                    .foregroundStyle(text)
                    .frame(width: b.sz, height: b.sz)
                    .background(Circle().fill(fill))
                    .overlay(Circle().strokeBorder(S.line, lineWidth: b.st == .short ? 0 : 1))
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
                Text(String(format: "%.1f wk", b.wk)).sType(SType(size: 13, weight: 600, line: 16, tracking: 0))
                    .foregroundStyle(b.st == .short ? S.red : S.muted)
                    .fixedSize()
            }
            .contentShape(Circle())
        }
        .buttonStyle(SPressStyle(scale: 0.96))
        .position(x: b.x, y: b.y + 10)
        .accessibilityLabel("\(b.t), \(PDGFace.word(b.st)), the jump costs \(String(format: "%.1f", b.wk)) weeks of premium")
        .accessibilityHint(held ? "Opens \(b.t) in Positions" : "")
    }
}
