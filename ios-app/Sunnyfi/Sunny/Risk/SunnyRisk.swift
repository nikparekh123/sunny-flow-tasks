//
//  SunnyRisk.swift
//  Sunny
//
//  Blocks 15 and 16 · Theta and Delta, the glass pair, on SunnyMountain.
//  Theta: short theta ÷ long theta, 2-week average, off the 3× line (green
//  above, brick below), a peak tag over the summit; the tile a theta check
//  found drags and breathes, and opens its receipt.
//  Delta (SunnyDelta, replaced 16 Oct 2026, handoff 25): net delta left
//  (calls bought - calls sold + puts sold - hedge puts) as a % of the shares
//  the LEAPs control, in ink, red only when the whole book is net short. The
//  mountain keeps the 20% floor only; no band words, no 30% line. A name
//  breathes orange under 20% (30% the week it reports) and red when net
//  short; any tile opens the Planner on that name. Both over the window
//  since the book began, one point a trading day, today live. Drag to read
//  any day.
//

import SwiftUI

struct SunnyRisk: View {
    let home: HomePayload
    @Environment(HomeRouter.self) private var router

    /// Handoff 28 (20 Oct 2026): Theta stands alone at full width, the Delta and
    /// Gamma map under it; the Delta card is retired.
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SunnyMountain(kind: .theta, home: home) { leg in router.open(.theta(leg)) }
            SunnyDeltaGamma(home: home)
        }
        .padding(.horizontal, S.margin)
    }
}

struct SunnyMountain: View {
    enum Kind { case theta, delta }
    let kind: Kind
    let home: HomePayload
    let onHot: (String) -> Void
    @State private var scrub: Int? = nil
    @Environment(HomeRouter.self) private var router
    @State private var preset = true
    @Environment(\.colorScheme) private var scheme

    /// Theta's plot; Delta's is the SunnyDelta reference (267 wide, 8 to 174).
    private var LW: CGFloat { kind == .theta ? 262 : 267 }
    private var TOP: CGFloat { kind == .theta ? 16 : 8 }
    private var BOT: CGFloat { kind == .theta ? 172 : 174 }

    private var V: [Double] {
        kind == .theta ? home.history.theta.avg2w
                       : (home.history.delta.netPct?.map { $0 ?? 0 } ?? home.history.delta.avg2w)
    }
    /// The Theta warning line. 3×, not the design's 2× (Nik, 13 Oct 2026: the
    /// backtest had 2× firing on under 1% of weeks; below 3× most months lost).
    static let thetaLine: Double = 3
    /// "3×", for the line's tag (inside the chart `F` is the floor value, not the formatter).
    static let thetaLineTag = F.trim(thetaLine) + "×"
    private var floorV: Double { kind == .theta ? Self.thetaLine : 20 }
    private var noLongs: Bool { kind == .theta ? home.risk.theta.long <= 0 : home.risk.delta.long <= 0 }

    var body: some View {
        let n = V.count
        let pre = preset ? DebugPreset.int(kind == .theta ? "theta.scrub" : "delta.scrub") : nil
        let idx = min(scrub ?? pre ?? n - 1, max(0, n - 1))
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(kind == .theta ? "Theta" : "Delta").sType(.sectionTitle, tabular: false)
                if noLongs || n == 0 {
                    Text("-").sType(.largeNumber).padding(.top, 6).frame(height: 40, alignment: .bottom)
                    Text(kind == .theta ? "Now · no long theta" : "Now · no long delta")
                        .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(S.muted)
                } else {
                    let h = hero(idx)
                    let when = scrub == nil && pre == nil ? "Now" : F.day(home.history.days[safe: idx] ?? "")
                    Text(h.text).sType(.largeNumber).foregroundStyle(h.color)
                        .contentTransition(.numericText(value: V[idx]))
                        .padding(.top, 6)
                    Group {
                        if kind == .theta {
                            Text("\(when) · \(h.sub) ") + Text("· \(h.trend)").foregroundStyle(h.trendColor)
                        } else {
                            Text("\(when) · \(h.sub)")
                        }
                    }
                        .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                        .foregroundStyle(S.muted)
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .frame(height: 20)
                    if kind == .delta {
                        // Hedge delta is negative: its number is red (no minus sign).
                        let hg = hedgeAt(idx, live: scrub == nil && pre == nil) ?? 0
                        (Text("Hedge puts · ") + Text("\(nK(hg)) Δ").foregroundStyle(hg > 0 ? S.red : S.ink))
                            .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                            .foregroundStyle(S.muted)
                            .contentTransition(.numericText(value: hg))
                            .lineLimit(1)
                            .frame(height: 20)
                    }
                }
            }
            if !noLongs && n > 1 { chart(idx, dragging: scrub != nil || pre != nil) }
            if !tileData.isEmpty { tiles }   // Delta with no longs: no mountain, no tiles
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: S.rCard))
        .sunnyGlow()
    }

    /// The hedge puts' delta: now, or the day under the finger.
    private func hedgeAt(_ i: Int, live: Bool) -> Double? {
        if live { return home.risk.delta.hedge }
        return home.history.delta.hedge?[safe: i] ?? nil
    }

    // MARK: Words

    private func hero(_ i: Int) -> (text: String, color: Color, sub: String, trend: String, trendColor: Color) {
        let v = V[i], v0 = V[max(0, i - 5)]
        if kind == .theta {
            let tr = v < v0 * 0.95 ? "downslope" : v > v0 * 1.05 ? "climbing" : "steady"
            let L = Self.thetaLine
            return (String(format: "%.2f×", v), v < L ? S.red : S.ink, v < L ? "below \(F.trim(L))×" : "above \(F.trim(L))×", tr, tr == "downslope" ? S.red : S.muted)
        }
        let live = i == V.count - 1 && scrub == nil
        let net = live ? (home.risk.delta.net ?? 0) : (home.history.delta.net?[safe: i] ?? nil) ?? 0
        let shares = live ? (home.risk.delta.shares ?? 0) : (home.history.delta.shares?[safe: i] ?? nil) ?? 0
        // Ink; red only when the whole book is net short. Never a minus sign.
        return ("\(Int(abs(v).rounded()))%", v < 0 ? S.red : S.ink, "\(nK(net)) Δ left of \(nK(shares))", "", S.muted)
    }
    /// 1.7K · 860: whole hundreds above 1,000.
    private func nK(_ v: Double) -> String {
        var x = abs(v); x = x >= 1000 ? (x / 100).rounded() * 100 : x.rounded()
        return x >= 1000 ? F.trim(x / 1000) + "K" : String(Int(x))
    }

    // MARK: The mountain

    @ViewBuilder private func chart(_ idx: Int, dragging: Bool) -> some View {
        let n = V.count, F = floorV, LW = LW, TOP = TOP, BOT = BOT
        let vmin = min(V.min()!, F), vmax = max(V.max()!, F)
        let pad = (vmax - vmin) * 0.08
        let lo = kind == .delta ? vmin - pad : vmin - (vmin < F ? pad : pad * 0.5), hi = vmax + pad
        let X = { (i: Int) -> CGFloat in CGFloat(i) / CGFloat(max(1, n - 1)) * LW }
        let Y = { (v: Double) -> CGFloat in TOP + CGFloat(1 - (v - lo) / (hi - lo)) * (BOT - TOP) }
        let BL = Y(F), ey = Y(V[n - 1])
        let upC: Color = kind == .theta ? Color(hex: 0x65C466) : S.ink
        let upA: Double = kind == .theta ? 0.5 : (scheme == .dark ? 0.32 : 0.18)
        let faint: Color = kind == .delta ? S.pNeutral : scheme == .dark ? Color.white.opacity(0.45) : S.muted
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
                                               startPoint: CGPoint(x: 0, y: TOP), endPoint: CGPoint(x: 0, y: BL)))
                ctx.fill(area({ min(F, $0) }, BL),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0xEB4B46).opacity(0.08), Color(hex: 0xEB4B46).opacity(0.55)]),
                                               startPoint: CGPoint(x: 0, y: BL), endPoint: CGPoint(x: 0, y: BOT)))
                var b = Path(); b.move(to: CGPoint(x: 0, y: BL)); b.addLine(to: CGPoint(x: LW, y: BL))
                ctx.stroke(b, with: .color(S.ink.opacity(0.22)), lineWidth: 1)
                ctx.stroke(line { $0 }, with: .color(S.ink.opacity(0.92)), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                if dragging {
                    ctx.fill(Path(CGRect(x: X(idx) - 0.5, y: 8, width: 1, height: 196 - 30)), with: .color(S.pGrid.opacity(3)))
                }
            }
            .frame(width: 301, height: 196)
            Circle().fill(kind == .delta ? (V[idx] < F ? S.red : S.ink) : dragging ? S.ink : (V[n - 1] < F ? brick : upC))
                .frame(width: 6, height: 6)
                .overlay(Circle().stroke(S.paper, lineWidth: 2))
                .position(x: X(idx), y: Y(V[idx]))
            if showPk {
                tag("Peak " + fmt(V[pk]), color: scheme == .dark ? S.yellow : S.yellowDeep, weight: 600)
                    .position(x: X(pk), y: Y(V[pk]) - 11)
            }
            tag(fmt(V[n - 1]), color: V[n - 1] < F ? S.red : S.ink, weight: 700)
                .alignmentGuide(.leading) { _ in -(LW + 7) }.alignmentGuide(.top) { d in -(ey - d.height / 2) }
            let by = abs(BL - ey) < 11 ? BL + (BL > ey ? 11 : -11) : BL
            tag(kind == .theta ? Self.thetaLineTag : "20%", color: faint, weight: 600)
                .alignmentGuide(.leading) { _ in -(LW + 7) }.alignmentGuide(.top) { d in -(by - d.height / 2) }
            // Delta labels a month only once it has five sessions (SunnyDelta).
            ForEach(months(days).filter { kind == .theta || $0.b - $0.a >= 4 }, id: \.m) { o in
                tag(Periods.monthNames[o.m - 1].uppercased(), color: faint, weight: 600)
                    .position(x: X((o.a + o.b) / 2), y: 190)
            }
        }
        .frame(width: 301, height: 196, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(ScrubGesture(onChange: { x in
            let j = max(0, min(n - 1, Int((x / LW * CGFloat(n - 1)).rounded())))
            if j != scrub { UISelectionFeedbackGenerator().selectionChanged(); scrub = j }
        }, onEnd: { withAnimation(S.standard(0.3)) { scrub = nil; preset = false } }))
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
            Text(kind == .theta ? "By position · net θ per day" : "By position · net Δ left · now")
                .sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(tileData.enumerated()), id: \.offset) { _, t in tile(t) }
                }
                // Room for a breathing tile's 16 pt glow (SunnyDelta: 10 pt in the scroller).
                .padding(.vertical, 10)
            }
            .padding(.vertical, -6)
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
        }
    }

    private struct Tile {
        let name: String; let value: String; let tone: Color; let sub: String; let hot: String?
        var by: Risk.Delta.By? = nil
        var alert: DeltaAlert? = nil
    }

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
        // Red first, then orange, then the rest by delta left, highest first.
        let rows = home.risk.delta.by.filter { ($0.shares ?? 0) > 0 }.map { b in
            (b, DeltaAlert(b.alert) ?? DeltaAlert(pct: b.pct, earningsWeek: b.earningsWeek == true))
        }
        return rows.sorted { ($0.1?.rank ?? 2, -$0.0.pct) < ($1.1?.rank ?? 2, -$1.0.pct) }.map { b, a in
            let sub = a == .red ? "net short" : a == .orange && b.earningsWeek == true ? "earnings week" : "\(nK(b.net ?? 0)) Δ left"
            return Tile(name: b.ticker, value: "\(Int(abs(b.pct).rounded()))%", tone: a?.ink ?? S.ink, sub: sub,
                        hot: nil, by: b, alert: a)
        }
    }

    @ViewBuilder private func tile(_ t: Tile) -> some View {
        if kind == .delta { deltaTile(t) } else { thetaTile(t) }
    }

    /// SunnyDelta's tile: a calm solid pill on glass, or breathing orange / red.
    /// Any tile opens the Planner on that name; the fix lives there.
    private func deltaTile(_ t: Tile) -> some View {
        Button { router.openCard(t.name, face: "dg") } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(t.name).sType(SType(size: 13, weight: 600, line: 13, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Spacer(minLength: 0)
                    Group { if let a = t.alert { BreathDot(alert: a) } else { Color.clear } }.frame(width: 6, height: 6)
                }
                Text(t.value).sType(SType(size: 20, weight: 800, line: 20, tracking: -0.02)).foregroundStyle(t.tone)
                    .contentTransition(.numericText(value: t.by?.pct ?? 0))
                Text(t.sub).sType(SType(size: 11, weight: 500, line: 13, tracking: 0))
                    .foregroundStyle(t.alert?.ink ?? S.muted)
                    .lineLimit(1).fixedSize()
            }
            .padding(12)
            .frame(minWidth: 104, alignment: .leading)
            .background {
                if let a = t.alert {
                    AlertBreath(alert: a, radius: S.rTile)
                } else {
                    RoundedRectangle(cornerRadius: S.rTile, style: .continuous)
                        .fill(scheme == .dark ? Color.white.opacity(0.12) : Color.white)
                        .overlay {
                            RoundedRectangle(cornerRadius: S.rTile, style: .continuous)
                                .strokeBorder(scheme == .dark ? Color.white.opacity(0.14) : S.ink.opacity(0.06), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 1, y: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: S.rTile, style: .continuous))
        }
        .buttonStyle(SPressStyle(scale: 0.96))
        .accessibilityLabel("\(t.name) \(t.value)\(t.alert == .red ? ", net short" : t.alert == .orange ? ", thin" : ""), opens the Planner")
    }

    private func thetaTile(_ t: Tile) -> some View {
        Button {
            if let leg = t.hot { onHot(leg) }
        } label: {
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


