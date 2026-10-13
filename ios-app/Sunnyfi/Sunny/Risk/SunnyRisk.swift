//
//  SunnyRisk.swift
//  Sunny
//
//  Blocks 15 and 16 · Theta and Delta, the glass pair, on SunnyMountain.
//  Theta: short theta ÷ long theta, 2-week average, off the 2× line (green
//  above, brick below), a peak tag over the summit. Delta: sold Δ ÷ long Δ
//  with the healthy band 20% to 50% (yellow above 50%). Both over the
//  window since the book began, one point a trading day, today live. Drag
//  to read any day. Tiles per ticker under each; the one a theta check
//  found drags and breathes, and opens its receipt.
//

import SwiftUI

struct SunnyRisk: View {
    let home: HomePayload
    @Environment(HomeRouter.self) private var router

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                SunnyMountain(kind: .theta, home: home) { leg in router.open(.theta(leg)) }
                    .frame(width: 341)
                SunnyMountain(kind: .delta, home: home) { _ in }
                    .frame(width: 341)
            }
            .scrollTargetLayout()
            .padding(.vertical, 4)
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

struct SunnyMountain: View {
    enum Kind { case theta, delta }
    let kind: Kind
    let home: HomePayload
    let onHot: (String) -> Void
    @State private var scrub: Int?
    @Environment(\.colorScheme) private var scheme

    private static let LW: CGFloat = 262, TOP: CGFloat = 16, BOT: CGFloat = 172

    private var V: [Double] { kind == .theta ? home.history.theta.avg2w : home.history.delta.avg2w }
    private var floorV: Double { kind == .theta ? 2 : 20 }
    private let cap: Double = 50
    private var noLongs: Bool { kind == .theta ? home.risk.theta.long <= 0 : home.risk.delta.long <= 0 }

    var body: some View {
        let n = V.count
        let idx = min(scrub ?? n - 1, max(0, n - 1))
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(kind == .theta ? "Theta" : "Delta").sType(.sectionTitle, tabular: false)
                if noLongs || n == 0 {
                    Text("-").sType(.largeNumber).padding(.top, 6).frame(height: 40, alignment: .bottom)
                    Text(kind == .theta ? "no long theta" : "no long delta")
                        .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(S.muted)
                } else {
                    let h = hero(idx)
                    Text(h.text).sType(.largeNumber).foregroundStyle(h.color)
                        .contentTransition(.numericText(value: V[idx]))
                        .padding(.top, 6)
                    (Text("\(scrub == nil ? "Now" : F.day(home.history.days[safe: idx] ?? "")) · \(h.sub) ")
                     + Text("· \(h.trend)").foregroundStyle(h.trendColor))
                        .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                        .foregroundStyle(S.muted)
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .frame(height: 20)
                }
            }
            if !noLongs && n > 1 { chart(idx) }
            tiles
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: S.rCard))
        .sunnyGlow()
    }

    // MARK: Words

    private func hero(_ i: Int) -> (text: String, color: Color, sub: String, trend: String, trendColor: Color) {
        let v = V[i], v0 = V[max(0, i - 5)]
        if kind == .theta {
            let tr = v < v0 * 0.95 ? "downslope" : v > v0 * 1.05 ? "climbing" : "steady"
            return (String(format: "%.2f×", v), v < 2 ? S.red : S.ink, v < 2 ? "below 2×" : "above 2×", tr, tr == "downslope" ? S.red : S.muted)
        }
        let L = home.risk.delta.long, out = v < 20 || v > 50
        let tr = v < 20 ? "underselling" : v > 50 ? "capping upside" : "healthy"
        return ("\(Int(v.rounded()))%", out ? S.yellowDeep : S.ink, "\(nK(L * v / 100)) of \(nK(L)) Δ sold", tr, out ? S.yellowDeep : S.green)
    }
    /// 1.7K · 860: whole hundreds above 1,000.
    private func nK(_ v: Double) -> String {
        var x = abs(v); x = x >= 1000 ? (x / 100).rounded() * 100 : x.rounded()
        return x >= 1000 ? F.trim(x / 1000) + "K" : String(Int(x))
    }

    // MARK: The mountain

    @ViewBuilder private func chart(_ idx: Int) -> some View {
        let n = V.count, F = floorV, LW = Self.LW
        let vmin = min(V.min()!, F), vmax = max(V.max()!, F, kind == .delta ? cap : F)
        let pad = (vmax - vmin) * 0.08
        let lo = vmin - (vmin < F ? pad : pad * 0.5), hi = vmax + pad
        let X = { (i: Int) -> CGFloat in CGFloat(i) / CGFloat(max(1, n - 1)) * LW }
        let Y = { (v: Double) -> CGFloat in Self.TOP + CGFloat(1 - (v - lo) / (hi - lo)) * (Self.BOT - Self.TOP) }
        let BL = Y(F), capY = Y(cap), ey = Y(V[n - 1])
        let upC: Color = kind == .theta ? Color(hex: 0x65C466) : S.ink
        let upA: Double = kind == .theta ? 0.5 : (scheme == .dark ? 0.32 : 0.18)
        let faint: Color = scheme == .dark ? Color.white.opacity(0.45) : S.muted
        let brick = Color(hex: 0xC7454A)
        let pk = V.indices.max { V[$0] < V[$1] } ?? 0
        let showPk = kind == .theta && Double(pk) < Double(n) * 0.9
        let days = home.history.days
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                let line = { (f: (Double) -> Double) -> Path in
                    var p = Path()
                    for i in 0..<n { let pt = CGPoint(x: X(i), y: Y(f(V[i]))); i == 0 ? p.move(to: pt) : p.addLine(to: pt) }
                    return p
                }
                let area = { (f: @escaping (Double) -> Double, base: CGFloat) -> Path in
                    var p = line(f); p.addLine(to: CGPoint(x: LW, y: base)); p.addLine(to: CGPoint(x: 0, y: base)); p.closeSubpath(); return p
                }
                ctx.fill(area({ max(F, $0) }, BL),
                         with: .linearGradient(Gradient(colors: [upC.opacity(upA), upC.opacity(0)]),
                                               startPoint: CGPoint(x: 0, y: Self.TOP), endPoint: CGPoint(x: 0, y: BL)))
                ctx.fill(area({ min(F, $0) }, BL),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0xEB4B46).opacity(0.08), Color(hex: 0xEB4B46).opacity(0.55)]),
                                               startPoint: CGPoint(x: 0, y: BL), endPoint: CGPoint(x: 0, y: Self.BOT)))
                if kind == .delta {
                    ctx.fill(area({ max(50, $0) }, capY), with: .color(Color(hex: 0xF7CE46).opacity(0.38)))
                    var c = Path(); c.move(to: CGPoint(x: 0, y: capY)); c.addLine(to: CGPoint(x: LW, y: capY))
                    ctx.stroke(c, with: .color(S.ink.opacity(0.22)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                var b = Path(); b.move(to: CGPoint(x: 0, y: BL)); b.addLine(to: CGPoint(x: LW, y: BL))
                ctx.stroke(b, with: .color(S.ink.opacity(0.22)), lineWidth: 1)
                ctx.stroke(line { $0 }, with: .color(S.ink.opacity(0.92)), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                if scrub != nil {
                    ctx.fill(Path(CGRect(x: X(idx) - 0.5, y: 8, width: 1, height: 196 - 30)), with: .color(S.pGrid.opacity(3)))
                }
            }
            .frame(width: 301, height: 196)
            Circle().fill(scrub != nil ? S.ink : (V[n - 1] < F ? brick : upC)).frame(width: 6, height: 6)
                .overlay(Circle().stroke(S.paper, lineWidth: 2))
                .position(x: X(idx), y: Y(V[idx]))
            if showPk {
                tag("Peak " + fmt(V[pk]), color: scheme == .dark ? S.yellow : S.yellowDeep, weight: 600)
                    .position(x: X(pk), y: Y(V[pk]) - 11)
            }
            tag(fmt(V[n - 1]), color: V[n - 1] < F ? S.red : S.ink, weight: 700)
                .alignmentGuide(.leading) { _ in -(LW + 7) }.alignmentGuide(.top) { d in -(ey - d.height / 2) }
            let by = abs(BL - ey) < 11 ? BL + (BL > ey ? 11 : -11) : BL
            tag(kind == .theta ? "2×" : "20%", color: faint, weight: 600)
                .alignmentGuide(.leading) { _ in -(LW + 7) }.alignmentGuide(.top) { d in -(by - d.height / 2) }
            if kind == .delta && abs(capY - ey) >= 11 {
                tag("50%", color: faint, weight: 600)
                    .alignmentGuide(.leading) { _ in -(LW + 7) }.alignmentGuide(.top) { d in -(capY - d.height / 2) }
            }
            ForEach(months(days), id: \.m) { o in
                tag(Periods.monthNames[o.m - 1].uppercased(), color: faint, weight: 600)
                    .position(x: X((o.a + o.b) / 2), y: 190)
            }
        }
        .frame(width: 301, height: 196, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(ScrubGesture(onChange: { x in
            let j = max(0, min(n - 1, Int((x / LW * CGFloat(n - 1)).rounded())))
            if j != scrub { UISelectionFeedbackGenerator().selectionChanged(); scrub = j }
        }, onEnd: { withAnimation(S.standard(0.3)) { scrub = nil } }))
        .accessibilityElement()
        .accessibilityLabel("\(kind == .theta ? "Theta" : "Delta") over time, now \(fmt(V[n - 1]))")
        .accessibilityAdjustableAction { dir in
            let j = max(0, min(n - 1, (scrub ?? n - 1) + (dir == .increment ? 1 : -1))); scrub = j
        }
    }

    private func fmt(_ v: Double) -> String { kind == .theta ? String(format: "%.1f×", v) : "\(Int(v.rounded()))%" }

    private func tag(_ t: String, color: Color, weight: CGFloat) -> some View {
        Text(t).sType(SType(size: 11, weight: weight, line: 13, tracking: 0.02)).foregroundStyle(color).fixedSize()
    }

    private func months(_ days: [String]) -> [(m: Int, a: Int, b: Int)] {
        var out: [(m: Int, a: Int, b: Int)] = []
        for (i, d) in days.enumerated() {
            let m = Int(d.dropFirst(5).prefix(2)) ?? 1
            if let last = out.last, last.m == m { out[out.count - 1].b = i } else { out.append((m, i, i)) }
        }
        return out
    }

    // MARK: Tiles

    private var tiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind == .theta ? "By position · net θ per day" : "By position · short Δ of long Δ")
                .sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(tileData.enumerated()), id: \.offset) { _, t in tile(t) }
                }
                .padding(.vertical, 4)
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
        }
    }

    private struct Tile { let name: String; let value: String; let tone: Color; let sub: String; let hot: String? }

    private var tileData: [Tile] {
        if kind == .theta {
            let hot = Dictionary((home.thetaChecks ?? []).map { ($0.ticker, $0.leg) }, uniquingKeysWith: { a, _ in a })
            var t = home.risk.theta.by.sorted { abs($0.net) > abs($1.net) }.map {
                Tile(name: $0.ticker, value: PF.usd($0.net), tone: $0.net >= 0 ? S.green : S.red,
                     sub: "\(PF.usd($0.collect)) collect · \(PF.usd($0.lose)) lose", hot: hot[$0.ticker])
            }
            // A dragging position moves to the front.
            t.sort { ($0.hot != nil ? 0 : 1) < ($1.hot != nil ? 0 : 1) }
            return t
        }
        return home.risk.delta.by.filter { $0.long > 0 }.sorted { $0.pct > $1.pct }.map {
            Tile(name: $0.ticker, value: "\(Int($0.pct.rounded()))%", tone: $0.pct < 20 || $0.pct > 50 ? S.yellowDeep : S.green,
                 sub: "\(nK($0.sold)) of \(nK($0.long)) Δ", hot: nil)
        }
    }

    private func tile(_ t: Tile) -> some View {
        Button { if let leg = t.hot { onHot(leg) } } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(t.name).sType(SType(size: 13, weight: 600, line: 13, tracking: 0), tabular: false)
                    Spacer(minLength: 8)
                    Circle().fill(t.hot != nil ? S.yellow : .clear).frame(width: 6, height: 6)
                }
                Text(t.value).sType(SType(size: 20, weight: 800, line: 20, tracking: -0.02)).foregroundStyle(t.tone)
                Text(t.hot != nil ? "losing faster · tap" : t.sub)
                    .sType(SType(size: 12, weight: 500, line: 14, tracking: 0))
                    .foregroundStyle(t.hot != nil ? (scheme == .dark ? S.yellow : S.yellowDeep) : (scheme == .dark ? Color.white.opacity(0.86) : S.ink))
                    .lineLimit(1).fixedSize()
            }
            .foregroundStyle(S.ink)
            .padding(12)
            .frame(minWidth: 104, alignment: .leading)
            .background {
                if t.hot != nil {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(scheme == .dark ? S.yellow.opacity(0.16) : S.yellowTint)
                        .modifier(Breathe())
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(scheme == .dark ? Color.white.opacity(0.12) : Color.white)
                        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 1, y: 1)
                }
            }
        }
        .buttonStyle(SPressStyle())
        .disabled(t.hot == nil)
        .accessibilityLabel("\(t.name) \(t.value), \(t.hot != nil ? "losing faster, opens the theta check" : t.sub)")
    }
}

/// The dragging tile breathes (2.4 s); Reduce Motion holds it still.
struct Breathe: ViewModifier {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .scaleEffect(on && !reduce ? 1.04 : 1)
            .opacity(on && !reduce ? 0.8 : 1)
            .onAppear {
                guard !reduce else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { on = true }
            }
    }
}
