//
//  PositionsScreen.swift
//  Sunny
//
//  Positions, one name at a time (block 31, Search Explorations 47a): the account strip (scrolls away), the
//  large title, the book's totals in one sideways row (a tap cycles time value, % change, $ change), the logo
//  strip (an orange dot = short at its priced move by Friday), the name row, then the chart card edge to edge
//  (P&L and its status, the Greeks, the payoff on the date picked, drag to set the price, the date slider),
//  Walls or Technicals, the legs (tap one to switch it off), the summary line, the fixes when short, Walls by
//  expiry, and the whole book in that name. Nothing pins except the nav bar.
//

import SwiftUI

struct BriefPositionsScreen: View {
    @Environment(BriefState.self) private var brief
    @Environment(HomeRouter.self) private var router
    @AppStorage(BriefPrivacy.key) private var privacy = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    @State private var name: String = BriefDebug.name ?? "NKE"
    @State private var stop = BriefDebug.stop ?? 0
    @State private var pos = ScrollPosition()
    @State private var price: Double?
    @State private var off: Set<String> = []
    @State private var legFilter = "All"
    @State private var layer: String? = "Walls"
    @State private var fix: String?
    @State private var totalsMode = 0
    @State private var wallsKind = "All"

    private var acct: String { brief.account.sampleKey }
    private var weekend: Bool { brief.moment() == .weekend }
    @State private var chain = 0
    @State private var scrolled: CGFloat = 0

    var body: some View {
        let names = SampleBook.names.filter { SampleBook.book(acct)[$0] != nil }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if brief.showsStrip {
                    AccountStrip(accounts: brief.accounts, selected: brief.account) { a in
                        withAnimation(reduce ? nil : S.standard(0.5)) { brief.pick(a) }
                    }
                }
                Text("Positions").sType(SType(size: 34, weight: 800, line: 40, tracking: -0.02), tabular: false)
                    .foregroundStyle(S.ink).padding(.horizontal, S.margin).padding(.top, brief.showsStrip ? 4 : 16)
                    .accessibilityAddTraits(.isHeader)
                BookTotalsRow(acct: acct, weekend: weekend, mode: $totalsMode, privacy: privacy).padding(.top, 12)
                LogoStrip(names: names, acct: acct, weekend: weekend, selected: name) { t in
                    withAnimation(reduce ? nil : S.standard(0.3)) { name = t; price = nil; off = []; fix = nil }
                }
                .padding(.top, 16)
                if let m = PositionsModel(t: name, acct: acct, weekend: weekend) {
                    NameRow(m: m).padding(.horizontal, S.margin).padding(.top, 14)
                    PositionsDetail(m: m, stop: Binding(get: { min(stop, m.stops.count - 1) }, set: { stop = $0 }), price: $price, off: $off,
                                    legFilter: $legFilter, layer: $layer, chain: $chain, fix: $fix, wallsKind: $wallsKind, privacy: privacy)
                        .padding(.top, 12)
                        .id("\(acct)-\(name)")
                }
            }
            .padding(.bottom, 128)
            .containerRelativeFrame(.horizontal)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($pos)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, v in scrolled = v }
        .task {
            if let y = BriefDebug.scroll { try? await Task.sleep(for: .milliseconds(600)); pos.scrollTo(y: y) }
        }
        .background(SBackground())
        .overlay(alignment: .top) { BriefTopEdge() }
        // The nav bar's small title once the large one has scrolled under it (block 31): "NKE Positions".
        .overlay(alignment: .top) {
            Text("\(name) Positions").font(.system(size: 17, weight: .semibold)).foregroundStyle(S.ink)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(alignment: .bottom) { Rectangle().fill(.bar).ignoresSafeArea(edges: .top).frame(height: 120, alignment: .bottom) }
                .overlay(alignment: .bottom) { Rectangle().fill(S.hairline).frame(height: 0.5) }
                .opacity(scrolled > (brief.showsStrip ? 110 : 40) ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: scrolled > (brief.showsStrip ? 110 : 40))
                .allowsHitTesting(false)
        }
        .onAppear(perform: arrive)
        .onChange(of: brief.positionsName) { _, _ in arrive() }
    }

    /// From a Your position row: that name at the Friday close stop. From the tab: the last name, today.
    private func arrive() {
        if let t = brief.positionsName { name = t }
        if brief.positionsAtFriday {
            stop = weekend ? 4 : 3; price = nil; brief.positionsAtFriday = false
        }
    }
}

// MARK: - Book totals (one sideways row)

private struct BookTotalsRow: View {
    let acct: String
    let weekend: Bool
    @Binding var mode: Int
    let privacy: Bool
    var body: some View {
        let models = SampleBook.names.compactMap { PositionsModel(t: $0, acct: acct, weekend: weekend) }
        let hs = models.map { $0.holdings() }
        let gain = hs.reduce(0) { $0 + $1.shareGain }, tl = hs.reduce(0) { $0 + $1.timeLeaps }, to = hs.reduce(0) { $0 + $1.timeOtm }
        let ip = hs.reduce(0) { $0 + $1.ip.value }, sc = hs.reduce(0) { $0 + $1.sc.value }, sp = hs.reduce(0) { $0 + $1.sp.value }
        let shT = hs.reduce(0) { $0 + $1.sh.today }, lpT = hs.reduce(0) { $0 + $1.lp.today }, ocT = hs.reduce(0) { $0 + $1.oc.today }, ipT = hs.reduce(0) { $0 + $1.ip.today }
        let shV = hs.reduce(0) { $0 + $1.sh.value }, lpV = hs.reduce(0) { $0 + $1.lp.value }, ocV = hs.reduce(0) { $0 + $1.oc.value }
        let views = ["time value", "% today", "$ today"]
        let longItems: [(String, Double, Double, Double)] = [("Shares", gain, shT, shV), ("LEAPS", tl, lpT, lpV), ("OTM calls", to, ocT, ocV), ("Insurance puts", ip, ipT, ip)]
        Button { withAnimation(.easeOut(duration: 0.2)) { mode = (mode + 1) % 3 } } label: {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    group("Long", longItems.filter { $0.1 != 0 || $0.2 != 0 }.map { it in
                        let v = mode == 0 ? it.1 : mode == 1 ? (it.3 != 0 ? it.2 / it.3 * 100 : 0) : it.2
                        let lbl = mode == 0 ? (it.0 == "Shares" ? "Shares · gain" : it.0 == "Insurance puts" ? "Insurance puts" : "\(it.0) · time value") : "\(it.0) · \(views[mode])"
                        return (lbl, v, mode == 1)
                    })
                    Rectangle().fill(S.hairline).frame(width: 0.5, height: 56).padding(.top, 20)
                    group("Sold · left to earn", [("Calls", sc, false), ("Puts", sp, false)].filter { $0.1 != 0 })
                }
                .padding(.horizontal, S.margin)
            }
            .scrollIndicators(.hidden)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows \(views[(mode + 1) % 3]) next")
    }

    private func group(_ h: String, _ items: [(String, Double, Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(h).sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink)
            HStack(alignment: .top, spacing: 18) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                    if i > 0 { Rectangle().fill(S.hairline).frame(width: 0.5, height: 44) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(it.2 ? String(format: "%.1f%%", abs(it.1)) : BriefWords.plain(SampleEngine.fK(it.1), privacy: privacy))
                            .sType(SType(size: 22, weight: 800, line: 26, tracking: -0.01))
                            .foregroundStyle(it.1 < 0 ? S.red : S.ink)
                        Text(it.0).sType(SType(size: 12, weight: 500, line: 15, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Logo strip

private struct LogoStrip: View {
    let names: [String]
    let acct: String
    let weekend: Bool
    let selected: String
    let pick: (String) -> Void
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                ForEach(names, id: \.self) { t in
                    let on = t == selected, warn = PositionsModel(t: t, acct: acct, weekend: weekend)?.shortByFriday ?? false
                    Button { pick(t) } label: {
                        VStack(spacing: 6) {
                            ZStack(alignment: .topTrailing) {
                                BLogo(ticker: t, size: 46)
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(on ? S.ink : .clear, lineWidth: 2))
                                if warn {
                                    Circle().fill(S.act).frame(width: 11, height: 11)
                                        .overlay(Circle().strokeBorder(S.sheetFill, lineWidth: 2)).offset(x: -1, y: 1)
                                }
                            }
                            Text(t).font(.system(size: 11, weight: on ? .bold : .semibold)).foregroundStyle(on ? S.ink : S.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel((SampleBook.company[t] ?? t) + (warn ? ", short if it rises its priced move by Friday" : ""))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, S.margin)
        }
        .scrollIndicators(.hidden)
    }
}

private struct NameRow: View {
    let m: PositionsModel
    var body: some View {
        let mv = (m.S0 - m.P0) / m.P0 * 100
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(m.t).font(.system(size: 17, weight: .bold)).foregroundStyle(S.ink)
            Text(String(format: "%.2f", m.S0)).font(.system(size: 17, weight: .medium).monospacedDigit()).foregroundStyle(S.secondary)
            Text("\(mv < 0 ? "▼" : "▲") \(String(format: "%.1f", abs(mv)))%").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(mv < 0 ? S.red : S.green)
            Spacer()
            if !m.strategy.isEmpty { Text(m.strategy).font(.system(size: 13, weight: .medium)).foregroundStyle(S.secondary) }
        }
    }
}

// MARK: - The chart card and everything under it

private struct PositionsDetail: View {
    let m: PositionsModel
    @Binding var stop: Int
    @Binding var price: Double?
    @Binding var off: Set<String>
    @Binding var legFilter: String
    @Binding var layer: String?
    @Binding var chain: Int
    @Binding var fix: String?
    @Binding var wallsKind: String
    let privacy: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let st = m.stops[stop], px = price ?? m.S0, tt = st.tt
        let pl = m.pl(px, tt, off: off), g = m.greeks(px, tt, off: off), fl = m.flip(tt, off: off)
        let short = g.d < 0
        let fixes = m.fixes(px, tt, off: off)
        let picked = fixes.first { $0.id == fix }
        VStack(alignment: .leading, spacing: 0) {
            // The chart card, edge to edge on its own fill.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text("\(pl < 0 ? "Down" : "Up") \(BriefWords.plain("$" + SampleEngine.fn(pl), privacy: privacy))")
                        .sType(SType(size: 28, weight: 800, line: 32, tracking: -0.02))
                        .foregroundStyle(pl < 0 ? S.red : S.green)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(pl < 0 ? (short ? "Losing, and short" : "Losing") : short ? "Making, but short" : "Long and making")
                            .sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false)
                            .foregroundStyle(pl < 0 ? S.red : short ? S.act : S.green)
                        Text("\(m.t) at $\(String(format: "%.2f", px)) · \(st.long)").sType(BK.caption).foregroundStyle(S.secondary)
                    }
                }
                HStack(alignment: .top) {
                    greek("Delta", SampleEngine.fn(g.d), g.d < 0 ? S.red : S.ink)
                    greek("Theta", BriefWords.plain("$" + SampleEngine.fn(g.th), privacy: privacy), g.th < 0 ? S.red : S.green)
                    greek("Gamma", SampleEngine.fn(g.g), g.g < 0 ? S.red : S.ink)
                    greek("Vega", BriefWords.plain("$" + SampleEngine.fn(g.vg), privacy: privacy), g.vg < 0 ? S.red : S.ink)
                }
                PositionsChart(m: m, tt: tt, price: $price, off: off, flip: fl, extra: picked?.extra ?? [], layer: layer, chain: chain)
                    .frame(height: 190 + 40)
                DateSlider(m: m, stop: $stop)
            }
            .padding(.horizontal, S.margin)
            .padding(.vertical, 18)
            .background(S.sheetFill)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(["Walls", "Technicals"], id: \.self) { l in
                        Button { withAnimation(.easeOut(duration: 0.2)) { layer = layer == l ? nil : l } } label: {
                            Text(l).font(.system(size: 14, weight: .semibold)).foregroundStyle(layer == l ? S.sheetFill : S.ink)
                                .padding(.horizontal, 14).frame(height: 34)
                                .background(Capsule().fill(layer == l ? S.ink : S.chip))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if layer == "Walls" {
                    HStack(spacing: 8) {
                        ForEach([(0, "Weekly · Oct 30"), (3, "Monthly · Nov 20")], id: \.0) { c in
                            Button { withAnimation(.timingCurve(0.3, 1.4, 0.5, 1, duration: 0.45)) { chain = c.0 } } label: {
                                Text(c.1).font(.system(size: 13, weight: .semibold)).foregroundStyle(S.ink)
                                    .padding(.horizontal, 12).frame(height: 30)
                                    .background(Capsule().fill(chain == c.0 ? S.chip : .clear))
                                    .overlay(Capsule().strokeBorder(S.hairline, lineWidth: chain == c.0 ? 0 : 1))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        legend("—", "P&L on that date", S.ink); legend("--", "Today", S.secondary)
                        legend("|", "Turns short", S.act); legend("|", "Hurting", S.red)
                    }
                    Text("Tap a leg to switch it off").sType(BK.label, tabular: false).foregroundStyle(S.secondary)
                }
                BHairline()
                LegsList(m: m, px: px, tt: tt, off: $off, filter: $legFilter, privacy: privacy)
                BHairline()
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(short ? "Short" : "Long") \(SampleEngine.fn(g.d)) Δ at $\(String(format: "%.2f", px)), \(st.long)")
                        .sType(SType(size: 20, weight: 700, line: 24, tracking: 0)).foregroundStyle(short ? S.red : S.ink)
                    Text(short ? "Short by \(SampleEngine.fn(g.d)) shares of delta. Each fix below shows what it costs and where it leaves you."
                         : fl.map { "Nothing to add here. Drag right: you turn short above $" + String(format: "%.2f", $0) } ?? "Nothing to add here. You stay long across the chart.")
                        .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !fixes.isEmpty {
                    FixesTiles(m: m, px: px, tt: tt, off: off, fixes: fixes, picked: $fix, privacy: privacy)
                }
                WallsByExpiry(m: m, kind: $wallsKind)
                WholeBook(m: m, privacy: privacy)
            }
            .padding(.horizontal, S.margin)
            .padding(.top, 16)
        }
    }

    private func greek(_ l: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l).sType(BK.caption, tabular: false).foregroundStyle(S.secondary)
            Text(v).sType(SType(size: 15, weight: 700, line: 18, tracking: 0)).foregroundStyle(c)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func legend(_ mark: String, _ t: String, _ c: Color) -> some View {
        HStack(spacing: 4) {
            Text(mark).font(.system(size: 12, weight: .bold)).foregroundStyle(c)
            Text(t).sType(BK.label, tabular: false).foregroundStyle(S.secondary)
        }
    }
}

/// The payoff on the date picked (ink), today dashed, the turns-short line (orange dotted), the strikes under
/// it (sold solid, bought faint, red when hurting), a fix's preview dashed green, and the crosshair at the price.
/// Drag anywhere to set the price (steps of $0.05 under $50, $0.10 under $200, else $0.50).
private struct PositionsChart: View {
    let m: PositionsModel
    let tt: Double
    @Binding var price: Double?
    let off: Set<String>
    let flip: Double?
    let extra: [PositionsModel.Leg]
    var layer: String? = nil
    var chain = 0

    /// The layer's price lines: this chain's walls, or the 20-day average and the month's high and low.
    private var layerLines: [(k: Double, label: String, color: Color, dashed: Bool)] {
        if layer == "Walls" {
            let w = SampleBook.walls(m.t, chain), ex = SampleBook.expiries[chain].label
            var out: [(Double, String, Color, Bool)] = [(w.flip, "Flip · \(ex)", S.act, true)]
            if let c = w.c { out.append((c.k, "Ceiling · \(ex)", S.navy, false)) }
            if let f = w.f { out.append((f.k, "Floor · \(ex)", S.brown, false)) }
            if let a = w.a { out.append((a.k, "Accelerator · \(ex)", S.brown.opacity(0.5), false)) }
            return out.filter { $0.0 >= m.X0 && $0.0 <= m.X1 }
        }
        if layer == "Technicals" {
            let tc = m.technicals
            return [(tc.sma, "20-day"), (tc.hi, "Month high"), (tc.lo, "Month low")].compactMap { v, l in
                v.map { ($0, l, S.teal, l != "20-day") } }.filter { $0.0 >= m.X0 && $0.0 <= m.X1 }
        }
        return []
    }

    /// Greedy lanes: each label takes the first row where it clears the one before it.
    static func lanes(_ items: [(x: CGFloat, w: CGFloat)]) -> [Int] {
        var ends: [CGFloat] = [], out: [Int] = []
        for it in items {
            let left = it.x - it.w / 2
            if let i = ends.firstIndex(where: { $0 + 4 < left }) { ends[i] = it.x + it.w / 2; out.append(i) }
            else { ends.append(it.x + it.w / 2); out.append(ends.count - 1) }
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H: CGFloat = 190
            let sc = m.scale(off: off)
            let X = { (px: Double) -> CGFloat in CGFloat((px - m.X0) / (m.X1 - m.X0)) * W }
            let Y = { (p: Double) -> CGFloat in CGFloat((sc.mx - p) / (sc.mx - sc.mn)) * H }
            let px = price ?? m.S0
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    func path(_ f: (Double) -> Double) -> Path {
                        var p = Path()
                        for (i, x) in m.grid.enumerated() {
                            let pt = CGPoint(x: X(x), y: max(-30, min(H + 20, Y(f(x)))))
                            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                        }
                        return p
                    }
                    let y0 = Y(0)
                    let line = path { m.pl($0, tt, off: off) }
                    var area = line; area.addLine(to: CGPoint(x: W, y: y0)); area.addLine(to: CGPoint(x: 0, y: y0)); area.closeSubpath()
                    ctx.drawLayer { c in c.clip(to: Path(CGRect(x: 0, y: -40, width: W, height: y0 + 40))); c.fill(area, with: .color(S.green.opacity(0.12))) }
                    ctx.drawLayer { c in c.clip(to: Path(CGRect(x: 0, y: y0, width: W, height: H - y0 + 40))); c.fill(area, with: .color(S.red.opacity(0.10))) }
                    ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y0)); $0.addLine(to: CGPoint(x: W, y: y0)) }, with: .color(S.secondary.opacity(0.3)), lineWidth: 1)
                    if let f = flip, f <= m.X1 {
                        ctx.stroke(Path { $0.move(to: CGPoint(x: X(f), y: 0)); $0.addLine(to: CGPoint(x: X(f), y: H)) },
                                   with: .color(S.act), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                    }
                    if tt > 0 { ctx.stroke(path { m.pl($0, 0, off: off) }, with: .color(S.ink.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])) }
                    if !extra.isEmpty { ctx.stroke(path { m.pl($0, tt, off: off, extra: extra) }, with: .color(S.green), style: StrokeStyle(lineWidth: 2, dash: [5, 3])) }
                    ctx.stroke(line, with: .color(S.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    // Strike ticks under the plot.
                    var seen: [Double: Int] = [:]
                    for l in m.legs where l.ty != .shares && l.K >= m.X0 && l.K <= m.X1 {
                        let i = seen[l.K, default: -1] + 1; seen[l.K] = i
                        let x = X(l.K) + [0, -6, 6, -12][min(i, 3)]
                        let hurt = m.legPL(l, px, tt) < -0.5 && !off.contains(l.id)
                        let c: Color = hurt ? S.red : l.ty == .call ? S.navy : S.brown
                        let o: Double = off.contains(l.id) ? 0.12 : l.q < 0 ? 1 : 0.4
                        ctx.fill(Path(roundedRect: CGRect(x: x - 1.5, y: H + 5, width: 3, height: min(10, 3 + abs(l.q) / 60 * 7)), cornerRadius: 1.5), with: .color(c.opacity(o)))
                    }
                    // The layer's lines, under the crosshair.
                    for l in layerLines {
                        ctx.stroke(Path { $0.move(to: CGPoint(x: X(l.k), y: 0)); $0.addLine(to: CGPoint(x: X(l.k), y: H)) },
                                   with: .color(l.color.opacity(0.85)), style: StrokeStyle(lineWidth: 1.2, dash: l.dashed ? [3, 3] : []))
                    }
                    // Crosshair.
                    let cx = X(px)
                    ctx.stroke(Path { $0.move(to: CGPoint(x: cx, y: 0)); $0.addLine(to: CGPoint(x: cx, y: H)) }, with: .color(S.ink), lineWidth: 1.5)
                    let cy = Y(m.pl(px, tt, off: off))
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - 5, y: cy - 5, width: 10, height: 10)), with: .color(S.ink))
                }
                // Layer labels in lanes on chips, never overlapping.
                let sorted = layerLines.sorted { $0.k < $1.k }
                let lanes = Self.lanes(sorted.map { (X($0.k), CGFloat($0.label.count) * 5.6 + 14) })
                ForEach(Array(sorted.enumerated()), id: \.offset) { i, l in
                    let lane = lanes[i]
                    Text(l.label).font(.system(size: 10, weight: .bold)).foregroundStyle(l.color)
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(Capsule().fill(S.chip.opacity(0.95)))
                        .fixedSize()
                        .position(x: min(max(X(l.k), 40), W - 40), y: 10 + CGFloat(lane) * 22)
                }
                // The price axis.
                let step = [0.5, 1, 2, 2.5, 5, 10, 20, 25, 50].first { (m.X1 - m.X0) / $0 <= 5 } ?? 50
                ForEach(Array(stride(from: (m.X0 / step).rounded(.up) * step, through: m.X1, by: step).enumerated()), id: \.offset) { _, k in
                    Text("$\(String(format: k.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", k))")
                        .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(S.secondary)
                        .position(x: X(k), y: H + 26)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let x = m.X0 + Double(max(0, min(1, v.location.x / W))) * (m.X1 - m.X0)
                let stp = m.S0 < 50 ? 0.05 : m.S0 < 200 ? 0.1 : 0.5
                let q = (x / stp).rounded() * stp
                if q != price { price = q; UISelectionFeedbackGenerator().selectionChanged() }
            })
        }
        .accessibilityElement()
        .accessibilityLabel("Payoff for \(m.t)")
        .accessibilityValue("\(String(format: "%.2f", price ?? m.S0)) dollars, \(m.pl(price ?? m.S0, tt, off: off) < 0 ? "down" : "up") \(SampleEngine.fn(m.pl(price ?? m.S0, tt, off: off)))")
        .accessibilityAdjustableAction { d in
            let stp = m.S0 < 50 ? 0.05 : m.S0 < 200 ? 0.25 : 1
            price = (price ?? m.S0) + (d == .increment ? stp : -stp)
        }
    }
}

/// One stop per trading day up to the last sold expiry; the expiry Fridays tall; the date and "N trading days on".
private struct DateSlider: View {
    let m: PositionsModel
    @Binding var stop: Int
    var body: some View {
        let st = m.stops[stop]
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(st.long).sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Spacer()
                Text(stop == 0 ? (m.weekend ? "next week" : "now") : "\(stop) trading day\(stop == 1 ? "" : "s") on").sType(BK.label, tabular: false).foregroundStyle(S.secondary)
            }
            GeometryReader { g in
                let n = m.stops.count - 1, w = g.size.width - 28
                ZStack(alignment: .leading) {
                    Capsule().fill(S.chip).frame(height: 4).padding(.horizontal, 14)
                    ForEach(m.stops.indices, id: \.self) { i in
                        Rectangle().fill(S.secondary.opacity(m.stops[i].friday ? 0.9 : 0.5)).frame(width: m.stops[i].friday ? 2 : 1, height: m.stops[i].friday ? 14 : 7)
                            .offset(x: 14 + w * CGFloat(i) / CGFloat(n) - 0.5, y: 14)
                    }
                    Circle().fill(.white).frame(width: 28, height: 28).shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                        .offset(x: w * CGFloat(stop) / CGFloat(n))
                }
                .frame(height: 30)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let i = Int(((v.location.x - 14) / w * CGFloat(n)).rounded())
                    let c = min(max(i, 0), n)
                    if c != stop { withAnimation(.timingCurve(0.3, 1.4, 0.5, 1, duration: 0.45)) { stop = c }; UISelectionFeedbackGenerator().selectionChanged() }
                })
            }
            .frame(height: 30)
            HStack {
                Text(m.stops.first?.short ?? "").sType(BK.caption, tabular: false).foregroundStyle(S.secondary)
                Spacer()
                if let f = m.stops.dropLast().first(where: \.friday) {
                    Text(f.short).sType(SType(size: 11, weight: 700, line: 13, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Spacer()
                }
                Text(m.stops.last?.short ?? "").sType(BK.caption, tabular: false).foregroundStyle(S.secondary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Date")
        .accessibilityValue(st.long)
        .accessibilityAdjustableAction { d in stop = min(max(stop + (d == .increment ? 1 : -1), 0), m.stops.count - 1) }
    }
}

// MARK: - Legs

private struct LegsList: View {
    let m: PositionsModel
    let px: Double
    let tt: Double
    @Binding var off: Set<String>
    @Binding var filter: String
    let privacy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(["All", "Sold", "Long"], id: \.self) { f in
                    Button { withAnimation(.easeOut(duration: 0.2)) { filter = f } } label: {
                        Text(f).font(.system(size: 14, weight: .semibold)).foregroundStyle(filter == f ? S.sheetFill : S.ink)
                            .padding(.horizontal, 14).frame(height: 32).background(Capsule().fill(filter == f ? S.ink : S.chip))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if !off.isEmpty {
                    Button { withAnimation(.easeOut(duration: 0.2)) { off = [] } } label: {
                        Text("\(off.count) leg\(off.count > 1 ? "s" : "") off · Show all").font(.system(size: 13, weight: .semibold)).foregroundStyle(S.act)
                    }.buttonStyle(.plain)
                }
            }
            let sold = m.legs.filter { $0.group == "s" }, long = m.legs.filter { $0.group == "l" }
            if filter != "Long" {
                if sold.isEmpty { section("Sold", "Nothing sold this week", S.secondary, []) }
                else { section("Sold", total(sold), totalColor(sold), sold) }
            }
            if filter != "Sold" { section("Long", total(long), totalColor(long), long) }
            if !m.ended.isEmpty && filter != "Long" { endedSection }
        }
    }

    @State private var endedOpen = false
    /// The week that ended (weekend, answer 3): folded under "Ended Oct 30 · settled", each leg with how it ended.
    private var endedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.25)) { endedOpen.toggle() } } label: {
                HStack {
                    Text("Ended Oct 30 · settled").sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(S.secondary)
                        .rotationEffect(.degrees(endedOpen ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            if endedOpen {
                ForEach(m.ended) { l in
                    let itm = l.ty == .call ? px > l.K : px < l.K
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l.title).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                        Text(itm ? "Ended Oct 30, $\(String(format: "%.2f", abs(px - l.K))) in the money at $\(String(format: "%.2f", px)). Rolled before the close, so no shares went."
                                 : "Ended Oct 30, worth nothing at $\(String(format: "%.2f", px)): kept in full.")
                            .sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(S.chip.opacity(0.6)))
                }
            }
        }
    }

    private func sum(_ ls: [PositionsModel.Leg]) -> Double { ls.filter { !off.contains($0.id) }.reduce(0) { $0 + m.legPL($1, px, tt) } }
    private func total(_ ls: [PositionsModel.Leg]) -> String {
        let v = sum(ls); return "\(v < 0 ? "Down" : "Up") \(BriefWords.plain("$" + SampleEngine.fn(v), privacy: privacy)) from today"
    }
    private func totalColor(_ ls: [PositionsModel.Leg]) -> Color { let v = sum(ls); return abs(v) < 0.5 ? S.secondary : v < 0 ? S.red : S.green }

    private func section(_ h: String, _ v: String, _ c: Color, _ ls: [PositionsModel.Leg]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(h).sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Spacer()
                Text(v).sType(SType(size: 13, weight: 600, line: 16, tracking: 0)).foregroundStyle(c)
            }
            ForEach(ls) { l in legCard(l) }
        }
    }

    private func legCard(_ l: PositionsModel.Leg) -> some View {
        let isOff = off.contains(l.id), p = isOff ? 0 : m.legPL(l, px, tt), d = m.legDelta(l, px, tt)
        let hurt = p < -0.5 && !isOff
        let line: String = l.ty == .shares ? "Δ \(SampleEngine.fn(d)) · cost $\(String(format: "%.2f", l.K)), no decay" : "Δ \(SampleEngine.fn(d)) at $\(String(format: "%.2f", px))"
        return Button { withAnimation(.easeOut(duration: 0.2)) { if isOff { off.remove(l.id) } else { off.insert(l.id) } } } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(l.title).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Text(isOff ? "Off · tap to add back" : line).sType(SType(size: 12, weight: 500, line: 16, tracking: 0))
                        .foregroundStyle(isOff ? S.secondary : d < 0 ? S.red : S.ink)
                }
                Spacer()
                Text(isOff ? "Off" : abs(p) < 0.5 ? "$0" : BriefWords.plain("$" + SampleEngine.fn(p), privacy: privacy))
                    .sType(SType(size: 15, weight: 700, line: 20, tracking: 0))
                    .foregroundStyle(isOff || abs(p) < 0.5 ? S.secondary : p < 0 ? S.red : S.green)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hurt ? S.red.opacity(0.08) : S.chip.opacity(0.8)))
            .opacity(isOff ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l.title)
        .accessibilityValue(isOff ? "off" : "on")
        .accessibilityHint(isOff ? "Tap to add it back" : "Tap to switch it off")
    }
}

// MARK: - Fixes

private struct FixesTiles: View {
    let m: PositionsModel
    let px: Double
    let tt: Double
    let off: Set<String>
    let fixes: [PositionsModel.Fix]
    @Binding var picked: String?
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fixes").sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
            HStack(alignment: .top, spacing: 8) {
                ForEach(fixes) { f in
                    let ad = m.delta(px, tt, off: off, extra: f.extra), ap = m.pl(px, tt, off: off, extra: f.extra), on = picked == f.id
                    Button { withAnimation(.easeOut(duration: 0.2)) { picked = on ? nil : f.id } } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(f.title).sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink)
                            Text(BriefWords.plain("$" + SampleEngine.fn(f.cost), privacy: privacy)).sType(SType(size: 17, weight: 800, line: 22, tracking: 0)).foregroundStyle(S.ink)
                            Text(f.act).sType(SType(size: 11, weight: 500, line: 14, tracking: 0), tabular: false).foregroundStyle(S.secondary).fixedSize(horizontal: false, vertical: true)
                            Text("Then \(ad < 0 ? "short" : "long") \(SampleEngine.fn(ad)) Δ · \(ap < 0 ? "down" : "up") \(BriefWords.plain("$" + SampleEngine.fn(ap), privacy: privacy))")
                                .sType(SType(size: 11, weight: 700, line: 14, tracking: 0), tabular: false).foregroundStyle(ad < 0 ? S.red : S.green)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(S.chip))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? S.ink : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Walls by expiry

private struct WallsByExpiry: View {
    let m: PositionsModel
    @Binding var kind: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Walls by expiry").sType(BK.title, tabular: false).foregroundStyle(S.ink)
            Text("Ceiling and floor for every chain, on the chart’s prices. Shaded is the move priced to that date. Tap a row to draw it on the chart.")
                .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(S.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(["All", "Weeklies", "Monthlies"], id: \.self) { k in
                    Button { withAnimation(.easeOut(duration: 0.2)) { kind = k } } label: {
                        Text(k).font(.system(size: 14, weight: .semibold)).foregroundStyle(kind == k ? S.sheetFill : S.ink)
                            .padding(.horizontal, 14).frame(height: 32).background(Capsule().fill(kind == k ? S.ink : S.chip))
                    }.buttonStyle(.plain)
                }
            }
            let rows = SampleBook.expiries.enumerated().filter { kind == "All" || (kind == "Weeklies" ? $0.element.kind == "Weekly" : $0.element.kind == "Monthly") }
            GeometryReader { g in
                let lw: CGFloat = 76, w = g.size.width - lw
                let X = { (px: Double) -> CGFloat in lw + CGFloat((px - m.X0) / (m.X1 - m.X0)) * w }
                ZStack(alignment: .topLeading) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { r, item in
                        let (e, ex) = item
                        let wl = SampleBook.walls(m.t, e), y = CGFloat(r) * 42
                        let band = m.S0 * m.v * (Double(ex.trading) / 252).squareRoot()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ex.label).sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink)
                            Text("\(ex.kind) · \(ex.days)d").sType(SType(size: 11, weight: 500, line: 13, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                        }
                        .offset(y: y + 6)
                        Capsule().fill(S.chip).frame(width: max(0, X(min(m.X1, m.S0 + band)) - X(max(m.X0, m.S0 - band))), height: 10)
                            .offset(x: X(max(m.X0, m.S0 - band)), y: y + 16)
                        Rectangle().fill(S.act).frame(width: 1, height: 18).opacity(0.8).offset(x: X(wl.flip), y: y + 12)
                        // Labels in lanes: a wall within 30 pt of the one before it puts its number below the bar.
                        let ms = [wl.a.map { ($0.k, S.brown.opacity(0.4)) }, wl.f.map { ($0.k, S.brown) }, wl.c.map { ($0.k, S.navy) }]
                            .compactMap { $0 }.sorted { $0.0 < $1.0 }
                        ForEach(Array(ms.enumerated()), id: \.offset) { i, mk in
                            let close = i > 0 && abs(X(min(max(mk.0, m.X0), m.X1)) - X(min(max(ms[i - 1].0, m.X0), m.X1))) < 30
                            marker(mk.0, mk.1, X, y, below: close)
                        }
                        if r < rows.count - 1 { Rectangle().fill(S.hairline).frame(height: 0.5).offset(y: y + 41) }
                    }
                    Rectangle().fill(S.ink).frame(width: 1, height: CGFloat(rows.count) * 42).offset(x: X(m.S0))
                }
            }
            .frame(height: CGFloat(rows.count) * 42)
            HStack(spacing: 10) {
                key(S.navy, "Ceiling"); key(S.brown, "Floor"); key(S.brown.opacity(0.4), "Accelerator"); key(S.act, "Flip"); key(S.ink, "Today")
            }
        }
        .briefCard()
    }

    @ViewBuilder private func marker(_ k: Double, _ c: Color, _ X: (Double) -> CGFloat, _ y: CGFloat, below: Bool = false) -> some View {
        let inRange = k >= m.X0 && k <= m.X1
        let x = X(min(max(k, m.X0), m.X1))
        let label = inRange ? String(format: "%g", k) : "\(String(format: "%g", k)) \(k > m.X1 ? "→" : "←")"
        RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 5, height: 16).offset(x: x - 2.5, y: y + 13)
        Text(label).font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(c).fixedSize()
            .offset(x: below ? x - 6 : x + 5, y: below ? y + 29 : y + 14)
    }
    private func key(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 1.5).fill(c).frame(width: 4, height: 12); Text(t).sType(BK.caption, tabular: false).foregroundStyle(S.secondary) }
    }
}

// MARK: - The whole book in this name

private struct WholeBook: View {
    let m: PositionsModel
    let privacy: Bool
    var body: some View {
        let h = m.holdings()
        VStack(alignment: .leading, spacing: 8) {
            Text("Whole \(m.t) book").sType(BK.title, tabular: false).foregroundStyle(S.ink)
            Text("Everything you hold in \(SampleBook.company[m.t] ?? m.t), today").sType(BK.sub, tabular: false).foregroundStyle(S.secondary)
            Text("Long").sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink).padding(.top, 6)
            ForEach([("Shares", h.sh), ("LEAPS", h.lp), ("OTM calls", h.oc), ("Insurance puts", h.ip)].filter { $0.1.value != 0 }, id: \.0) { r in
                BHairline()
                row(r.0, SampleEngine.fK(r.1.value), "\(r.1.today < 0 ? "▼" : "▲") \(SampleEngine.fK(r.1.today)) today", r.1.today < 0 ? S.red : S.green)
            }
            let sold = [("Calls", h.sc), ("Puts", h.sp)].filter { $0.1.value != 0 || $0.1.today != 0 }
            if !sold.isEmpty {
                Text("Sold · left to earn").sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink).padding(.top, 10)
                ForEach(sold, id: \.0) { r in
                    BHairline()
                    row(r.0, SampleEngine.fK(r.1.value), "\(SampleEngine.fK(r.1.today)) kept", S.green)
                }
            }
        }
        .briefCard()
    }
    private func row(_ l: String, _ v: String, _ sub: String, _ c: Color) -> some View {
        HStack {
            Text(l).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
            Spacer()
            Text(BriefWords.plain(v, privacy: privacy)).sType(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink)
            Text(BriefWords.plain(sub, privacy: privacy)).sType(SType(size: 13, weight: 600, line: 16, tracking: 0)).foregroundStyle(c).frame(minWidth: 100, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}
