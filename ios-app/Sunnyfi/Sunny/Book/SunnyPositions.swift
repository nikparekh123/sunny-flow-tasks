//
//  SunnyPositions.swift
//  Sunny
//
//  Blocks 12 and 13 (handoff 28, 20 Oct 2026) · Positions: one glass card per
//  name, safest first. The body swipes Sold · Bought · Delta and Gamma (Sold
//  first) under a Liquid Glass segmented control whose capsule rides the swipe;
//  every face is the same height, so a swipe moves nothing else on the page. A
//  name with a task open in This week gets orange dots and a row that links up
//  to it; every card ends with This week's insights (a sheet). Nothing bought:
//  Sold only, no tabs. The Sold and Bought pages and their chips are gone.
//

import SwiftUI

struct SunnyPositions: View {
    let home: HomePayload
    /// Cards keep the order this payload gives them: the insight words' copy,
    /// so they re-sort on open, pull to refresh and after the close, never on
    /// the 15 s tick (Nik, 14 Oct 2026: cards moving "all the time").
    var orderFrom: HomePayload? = nil
    @State private var seen = false
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let pages = PCache.pages(home, orderFrom: orderFrom)
        let sold = pages.first { $0.kind == .sold }, bought = pages.first { $0.kind == .bought }
        let names = (sold?.cards.map(\.t) ?? []) + (bought?.cards.map(\.t) ?? []).filter { t in !(sold?.cards.contains { $0.t == t } ?? false) }
        let fullW = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.width ?? 393
        let width = fullW - 2 * S.margin - 40
        let hours = home.hours
        let live = PChartGeom.liveSlot(sessions: hours?.days ?? [], today: home.today, now: SClock.now(), calendar: home.calendar)
        let open = MarketClock.isRegular(SClock.now(), calendar: home.calendar)
        let tasks = SunnyThisWeek.open(home, checked: router.checked)
        let all = home.thisWeek?.value ?? []
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Positions").sType(.sectionTitle, tabular: false).foregroundStyle(S.ink)
                    .accessibilityAddTraits(.isHeader)
                if !names.isEmpty { totals(sold: sold?.legs ?? [], bought: bought?.legs ?? [], tickers: names.count) }
            }
            .padding(.bottom, 8)
            if names.isEmpty {
                empty
            } else {
                ForEach(Array(names.enumerated()), id: \.element) { j, t in
                    let sc = sold?.cards.first { $0.t == t }, bc = bought?.cards.first { $0.t == t }
                    let w = home.writes.names.first { $0.ticker == t }
                    PNameCard(t: t, px: (sc ?? bc)?.px ?? 0, sold: sc, bought: bc, dg: w?.dg?.value,
                              strategy: home.strategies?[t], tasks: tasks.filter { $0.t == t },
                              hadTasks: all.contains { $0.t == t }, ringed: router.ring == t, width: width,
                              go: seen || reduce, delay: Double(min(j, 6)) * S.stagger,
                              hours: hours, live: live, today: home.today, open: open)
                        .id("pos-\(t)")
                }
            }
        }
        .padding(.horizontal, S.margin)
        .frame(maxWidth: .infinity, alignment: .leading)
        // First view animates once (block 12, Motion). The list is many screens tall, so any
        // sliver on screen counts: at 10% the cards stayed hidden under the Positions title.
        .onScrollVisibilityChange(threshold: 0.001) { v in if v { seen = true } }
    }

    /// "7 tickers · $3.7K time value · $3.8K kept · $48K bought gain".
    private func totals(sold: [PLeg], bought: [PLeg], tickers: Int) -> some View {
        let S0 = PTotals(sold), B = PTotals(bought)
        let bold = SType(size: 14, weight: 700, line: 18, tracking: 0).font(tabular: true)
        var t = Text("\(tickers)").font(bold).foregroundStyle(S.ink) + Text(tickers == 1 ? " ticker" : " tickers")
        if !sold.isEmpty {
            t = t + Text(" · ") + Text(PF.usd(S0.tv)).font(bold).foregroundStyle(S.ink) + Text(" time value · ")
                + Text(PF.usd(abs(S0.g))).font(bold).foregroundStyle(S0.up ? S.green : S.red) + Text(S0.up ? " kept" : " lost")
        }
        if !bought.isEmpty {
            t = t + Text(" · ") + Text(PF.usd(abs(B.g))).font(bold).foregroundStyle(B.up ? S.green : S.red)
                + Text(B.up ? " bought gain" : " bought loss")
        }
        return t.sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
            .foregroundStyle(S.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No open positions").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false)
            Text("Calls and puts you sell or buy show up here.")
                .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false)
                .foregroundStyle(S.muted)
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: S.rCard))
    }
}

/// The words and numbers the cards share (block 12, Numbers).
enum PWords {
    /// Red says so in words: a bought side down is a loss, not a gain, and a
    /// sold side down is lost, not kept (Nik, 13 Oct 2026).
    static func dollars(sold: Bool, up: Bool) -> String { sold ? (up ? "kept" : "lost") : (up ? "gain" : "loss") }
}

/// The swipe progress across a card's faces (0, 1, 2). A class, so only the
/// tabs that read it redraw while the finger moves.
@Observable final class PFaceProgress {
    var p: Double = 0
    var moving = false
}

// MARK: - One name's card (block 13)

private struct PNameCard: View {
    enum Face: String, CaseIterable, Identifiable {
        case sold, bought, dg
        var id: String { rawValue }
        var label: String { switch self { case .sold: "Sold"; case .bought: "Bought"; case .dg: "Delta and Gamma" } }
    }
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce
    let t: String
    let px: Double
    let sold: PCard?
    let bought: PCard?
    let dg: DGBook?
    let strategy: String?
    /// Open today, not yet checked.
    let tasks: [WeekTask]
    /// Any task today: all checked reads "Done for this week".
    let hadTasks: Bool
    /// Opened from a tap: a 2 pt ink outline for 1.8 s.
    let ringed: Bool
    let width: CGFloat
    let go: Bool
    let delay: Double
    let hours: Hours?
    let live: Double
    let today: String
    let open: Bool

    @State private var pos = ScrollPosition()
    @State private var prog = PFaceProgress()
    /// The faces' shared height (the tallest face).
    @State private var h: CGFloat = 0

    /// One face is the card's full width; it carries the 20 pt side padding itself, so a strike
    /// tag that runs past the plot stays on its own face.
    private var pageW: CGFloat { width + 40 }
    private var faces: [Face] {
        [sold != nil ? .sold : nil, bought != nil ? .bought : nil, bought != nil && dg != nil ? .dg : nil].compactMap { $0 }
    }
    /// The faces the work is on: Sold for a roll or a sale, Delta and Gamma for a buy.
    private var workOn: Set<Face> { Set(tasks.map { $0.face == "dg" ? Face.dg : Face.sold }) }

    var body: some View {
        let F = faces
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                head
                if F.count > 1 {
                    PFaceTabs(faces: F.map(\.label), dots: F.map { workOn.contains($0) }, prog: prog) { i in scroll(to: i) }
                }
            }
            .padding(.horizontal, 20)
            // Every face is the same height (the tallest), its numbers on the bottom, so a swipe moves nothing.
            ScrollView(.horizontal) {
                PEqualFaces(w: pageW) {
                    ForEach(F) { f in face(f).padding(.horizontal, 20) }
                }
                .scrollTargetLayout()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h = $0 }
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition($pos)
            .scrollIndicators(.hidden)
            .scrollDisabled(F.count < 2)
            .onScrollGeometryChange(for: Double.self) { g in Double(g.contentOffset.x / max(1, g.containerSize.width)) } action: { _, v in
                prog.p = v
            }
            .onScrollPhaseChange { _, ph in prog.moving = ph != .idle }
            .frame(width: pageW, height: h > 0 ? h : nil)
            if !tasks.isEmpty || hadTasks { rebalance.padding(.horizontal, 20) }
            Button { router.insights = t } label: {
                Text("This week's insights").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false)
                    .foregroundStyle(S.ink)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Capsule().fill(S.track))
                    .contentShape(Capsule())
            }
            .buttonStyle(SPressStyle(scale: 0.97))
            .padding(.horizontal, 20)
            .accessibilityLabel("Open this week's insights for \(t)")
        }
        .foregroundStyle(S.ink)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { PCornerGlow(status: (sold ?? bought)?.status ?? .safe) }
        .glassEffect(.regular, in: .rect(cornerRadius: S.rCard))
        // Opened from a tap: a 2 pt ink outline 2 pt outside the card for 1.8 s (block 12).
        .overlay {
            RoundedRectangle(cornerRadius: S.rCard + 4, style: .continuous)
                .strokeBorder(S.ink, lineWidth: 2)
                .padding(-4)
                .opacity(ringed ? 1 : 0)
                .animation(.easeOut(duration: 0.4), value: ringed)
                .allowsHitTesting(false)
        }
        .sunnyGlow()
        .pEnter(go, delay)
        // Opened from a tap (This week, the map, a chip): swipe to its face.
        .onChange(of: router.cardTick) { _, _ in
            guard let f = router.cardFace[t].flatMap(Face.init(rawValue:)), let i = F.firstIndex(of: f) else { return }
            scroll(to: i)
        }
        .onAppear {
            if let f = router.cardFace[t].flatMap(Face.init(rawValue:)), let i = F.firstIndex(of: f), i > 0 {
                var tr = Transaction(); tr.disablesAnimations = true
                withTransaction(tr) { pos.scrollTo(x: CGFloat(i) * pageW) }
            }
        }
    }

    /// By the face's x offset, never its id: an id scroll moves the page underneath too.
    private func scroll(to i: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        if reduce { pos.scrollTo(x: CGFloat(i) * pageW) } else { withAnimation(S.standard(0.35)) { pos.scrollTo(x: CGFloat(i) * pageW) } }
    }

    // MARK: Header

    private var head: some View {
        HStack(alignment: .center, spacing: 8) {
            if !tasks.isEmpty {
                Circle().fill(S.orange).frame(width: 10, height: 10)
                    .accessibilityLabel("Needs a rebalance")
            }
            (Text(t).font(SType(size: 20, weight: 700, line: 24, tracking: 0).font())
             + Text(" " + PF.price(px)).font(SType(size: 20, weight: 500, line: 24, tracking: 0).font(tabular: true))
                .foregroundStyle(S.muted))
                .sType(SType(size: 20, weight: 700, line: 24, tracking: 0))
                .lineLimit(1)
            Spacer(minLength: 0)
            if let name = Strategy.name(strategy) {
                Text(name).sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                    .foregroundStyle(S.muted).lineLimit(1)
            }
        }
        .frame(height: 24)
    }

    // MARK: Faces

    @ViewBuilder private func face(_ f: Face) -> some View {
        switch f {
        case .sold: if let c = sold { side(c) }
        case .bought: if let c = bought { side(c) }
        case .dg: if let d = dg { PDGFace(t: t, dg: d, width: width) }
        }
    }

    /// Sold or Bought: By Fri and the nearest strikes, the hourly line with the strikes, four numbers.
    private func side(_ c: PCard) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(c.by).foregroundStyle(S.muted)
                Spacer(minLength: 0)
                c.heads.enumerated().reduce(Text("")) { acc, e in
                    let h = e.element
                    return acc + Text(PF.dist(h.dist) + (h.dist >= 0 ? " to " : " past ") + h.word)
                        .foregroundStyle(Self.distColor(h.dist, sold: c.sold))
                        + Text(e.offset < c.heads.count - 1 ? " · " : "").foregroundStyle(S.muted)
                }
            }
            .sType(SType(size: 13, weight: 500, line: 16, tracking: 0))
            .lineLimit(1)
            PChartView(c: c, g: PChartGeom(c, width: width, hist: hours?.px[c.t] ?? [], live: live, sessions: hours?.days ?? [],
                                           ahead: c.weekExpiry.map { e in (hours?.ahead ?? []).filter { $0 <= e } } ?? [],
                                           today: today),
                       width: width, go: go, d: delay, open: open)
            Spacer(minLength: 0)
            footer(c)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y(c))
    }

    /// Gold inside 2% on a sold strike, red once a sold strike is crossed,
    /// green past a bought one; otherwise muted.
    static func distColor(_ d: Double, sold: Bool) -> Color {
        d < 0 ? (sold ? S.red : S.green) : sold && d < 2 ? S.yellowDeep : S.muted
    }

    private func footer(_ c: PCard) -> some View {
        let A = c.totals, tn = A.up ? S.green : S.red
        let usd: (Double) -> String = { PF.usd($0) }, pct: (Double) -> String = { PF.pct($0) }
        // Collected (sold) or paid (bought) first, so the rest adds up: collected
        // = kept + time value still in the option (Nik, 14 Oct 2026).
        let stats: [(Double, (Double) -> String, String, Color)] = [
            (A.base, usd, c.sold ? "collected" : "paid", S.ink),
            (A.tv, usd, "time value", S.ink),
            (abs(A.pct), pct, c.sold ? "captured" : "return", tn),
            (abs(A.g), usd, PWords.dollars(sold: c.sold, up: A.up), tn),
        ]
        return HStack(alignment: .top, spacing: 8) {
            ForEach(stats, id: \.2) { s in
                VStack(alignment: .leading, spacing: 2) {
                    SNumber(value: s.0, format: s.1, countUp: false)
                        .sType(SType(size: 17, weight: 700, line: 20, tracking: 0))
                        .foregroundStyle(s.3)
                        .lineLimit(1)
                    Text(s.2).sType(SType(size: 12, weight: 500, line: 14, tracking: 0), tabular: false)
                        .foregroundStyle(S.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 16)
        .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
    }

    private func a11y(_ c: PCard) -> String {
        let d = c.heads.map { "\(F.trim((abs($0.dist) * 10).rounded() / 10)) percent \($0.dist >= 0 ? "to" : "past") \($0.word) \(PF.strike($0.k))" }
        let g = Int(abs(c.totals.g).rounded()).formatted()
        return ([t, c.sold ? "Sold" : "Bought", PF.price(c.px)] + d + ["\(PWords.dollars(sold: c.sold, up: c.totals.up)) \(g) dollars"])
            .joined(separator: ", ")
    }

    // MARK: Rebalance row (13): up to This week, or Done for this week

    private var rebalance: some View {
        let done = tasks.isEmpty
        return Button { if !done { router.focusThisWeek(t) } } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    if done {
                        Circle().fill(S.ink)
                        Path { q in q.move(to: CGPoint(x: 6.5, y: 11.5)); q.addLine(to: CGPoint(x: 9.8, y: 14.6)); q.addLine(to: CGPoint(x: 15.6, y: 7.8)) }
                            .stroke(S.paper, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    } else {
                        Circle().fill(S.orange).frame(width: 10, height: 10)
                    }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(done ? "Done for this week" : "\(tasks.count) to do this week")
                        .sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false)
                    Text(done ? "Delta back on target" : tasks.map(\.action).joined(separator: " · "))
                        .sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                        .foregroundStyle(done ? S.green : S.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if !done {
                    Path { q in q.move(to: CGPoint(x: 1, y: 7)); q.addLine(to: CGPoint(x: 6.5, y: 1.5)); q.addLine(to: CGPoint(x: 12, y: 7)) }
                        .stroke(S.muted, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 13, height: 8)
                }
            }
            .padding(.top, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(done)
        .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
        .accessibilityLabel(done ? "Done for this week, delta back on target"
                                 : "\(tasks.count) to do this week: \(tasks.map(\.action).joined(separator: ", ")), go to This week")
    }
}

/// The faces side by side, each `w` wide and as tall as the tallest, so a face with less in it
/// keeps its numbers on the bottom and a swipe never changes the card's height.
private struct PEqualFaces: Layout {
    let w: CGFloat
    private func tallest(_ subviews: Subviews) -> CGFloat {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: w, height: nil)).height }.max() ?? 0
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: w * CGFloat(subviews.count), height: tallest(subviews))
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let h = tallest(subviews)
        for (i, v) in subviews.enumerated() {
            v.place(at: CGPoint(x: b.minX + CGFloat(i) * w, y: b.minY), proposal: ProposedViewSize(width: w, height: h))
        }
    }
}

// MARK: - The tabs: a Liquid Glass segmented control whose capsule rides the swipe

private struct PFaceTabs: View {
    let faces: [String]
    let dots: [Bool]
    let prog: PFaceProgress
    let tap: (Int) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// Each tab as wide as its label (and dot), the spare width shared out evenly.
    private func widths(_ W: CGFloat) -> [CGFloat] {
        let f = SType(size: 13, weight: 600, line: 16, tracking: 0).uiFont()
        let nat = faces.enumerated().map { i, t in
            ceil((t as NSString).size(withAttributes: [.font: f]).width) + (dots[safe: i] == true ? 12 : 0) + 24
        }
        let spare = max(0, W - nat.reduce(0, +)) / CGFloat(max(1, faces.count))
        let w = nat.map { $0 + spare }, sum = w.reduce(0, +)
        return sum > W ? w.map { $0 * W / sum } : w
    }

    var body: some View {
        GeometryReader { g in
            let ws = widths(g.size.width - 4), xs = ws.indices.map { i in ws[..<i].reduce(0, +) }
            let p = min(max(prog.p, 0), Double(faces.count - 1)), lo = Int(p.rounded(.down)), hi = min(lo + 1, faces.count - 1), f = CGFloat(p - Double(lo))
            let x = xs[lo] + (xs[hi] - xs[lo]) * f, w = ws[lo] + (ws[hi] - ws[lo]) * f
            ZStack(alignment: .leading) {
                // The design's segmented track (gray 12%, dark 24%) and its capsule (white 88%, dark 20%).
                Capsule().fill(Color(red: 118 / 255, green: 118 / 255, blue: 128 / 255).opacity(scheme == .dark ? 0.24 : 0.12))
                    .overlay(Capsule().strokeBorder(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04), lineWidth: 0.5))
                Capsule().fill(Color.white.opacity(scheme == .dark ? 0.2 : 0.88))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(scheme == .dark ? 0.22 : 0.9), lineWidth: 0.5))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: scheme == .dark ? 4 : 1.5, y: scheme == .dark ? 2 : 1)
                    .frame(width: w, height: 32)
                    .scaleEffect(x: prog.moving && !reduce ? 1.06 : 1, y: prog.moving && !reduce ? 1.14 : 1)
                    .offset(x: 2 + x)
                    .animation(reduce ? nil : .easeOut(duration: 0.2), value: prog.moving)
                HStack(spacing: 0) {
                    ForEach(Array(faces.enumerated()), id: \.offset) { i, t in
                        Button { tap(i) } label: {
                            HStack(spacing: 6) {
                                Text(t).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false)
                                    .foregroundStyle(abs(Double(i) - prog.p) < 0.5 ? S.ink : S.muted).lineLimit(1)
                                if dots[safe: i] == true { Circle().fill(S.orange).frame(width: 6, height: 6) }
                            }
                            .frame(width: ws[safe: i] ?? 0, height: 36)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(abs(Double(i) - prog.p) < 0.5 ? [.isSelected, .isButton] : .isButton)
                        .accessibilityLabel(t + (dots[safe: i] == true ? ", needs a rebalance" : ""))
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .frame(height: 36)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Faces")
    }
}

/// The soft corner glow from the top left, tinted by the nearest strike:
/// radial 130% × 90%, the tint at 28% (dark 22%) fading out by 60%.
private struct PCornerGlow: View {
    let status: PStatus
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = status == .safe ? S.pGlowSafe : status == .near ? S.pGlowNear : S.pGlowPast
        let c = Color(red: t.r / 255, green: t.g / 255, blue: t.b / 255)
        let a = scheme == .dark ? 0.22 : 0.28
        GeometryReader { geo in
            let rx = 1.3 * geo.size.width, ry = max(0.9 * geo.size.height, 1)
            Rectangle()
                .fill(RadialGradient(colors: [c.opacity(a), c.opacity(0)], center: .topLeading,
                                     startRadius: 0, endRadius: 0.6 * rx))
                .frame(width: geo.size.width, height: geo.size.height * rx / ry)
                .scaleEffect(x: 1, y: ry / rx, anchor: .topLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: S.rCard, style: .continuous))
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.3), value: status)
    }
}

// MARK: - Chart

private struct PChartView: View {
    let c: PCard
    let g: PChartGeom
    let width: CGFloat
    let go: Bool
    let d: Double
    let open: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let on = go || reduce
        let lineC = c.totals.weekUp ? S.green : S.red   // the week shown (Nik, 14 Oct 2026)
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                // Strikes as plain gray lines: dashed sold, dotted bought. They
                // grow out of their tags.
                ForEach(Array(g.lines.enumerated()), id: \.element.id) { k, l in
                    PHLine()
                        .stroke(S.pStrike, style: l.sold ? StrokeStyle(lineWidth: 1.5, dash: [4.5, 3])
                                                          : StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0, 3]))
                        .frame(width: g.plot, height: 1.5)
                        .animation(reduce ? nil : S.standard(0.6).delay(d + 0.15 + Double(k) * 0.05)) {
                            $0.scaleEffect(x: on ? 1 : 0.001, anchor: .trailing)
                        }
                        .offset(y: l.y)
                }
                // The hourly line: the only color on the card. Draws left to right.
                PLineShape(segments: g.segments)
                    .trim(from: 0, to: on ? 1 : 0)
                    .stroke(lineC, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .animation(reduce ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.9).delay(d + 0.1), value: on)
                    .frame(width: g.plot, height: PChartGeom.H)
                    .clipped()
                PConnectors(plot: g.plot, items: g.connectors)
                    .stroke(S.muted, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    .frame(width: width, height: PChartGeom.H)
                    .pDrop(on, d + 0.35)
                Circle().fill(S.paper)
                    .overlay(Circle().strokeBorder(lineC, lineWidth: 2.5))
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.20), radius: 1, y: 1)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
                    // Market open: a soft ring ripples out of the dot (Nik, 14 Oct 2026).
                    .background { if open && on && !reduce { PLivePulse(color: lineC) } }
                    .animation(reduce ? nil : S.standard(0.4).delay(d + 0.85)) {
                        $0.scaleEffect(on ? 1 : 0.4).opacity(on ? 1 : 0)
                    }
                    .offset(x: g.dot.x - 6, y: g.dot.y - 6)
                ForEach(Array(g.tags.enumerated()), id: \.element.id) { k, t in
                    tag(t)
                        .offset(x: g.plot + 8, y: t.top)
                        .pDrop(on, d + 0.35 + Double(min(k + 1, 8)) * 0.03)
                }
            }
            .frame(width: width, height: PChartGeom.H, alignment: .topLeading)
            // A day label at each session start; today in ink.
            ZStack(alignment: .topLeading) {
                ForEach(g.days) { x in
                    Text(x.text).sType(SType(size: 11, weight: 500, line: 14, tracking: 0), tabular: false)
                        .foregroundStyle(x.today ? S.ink : S.muted)
                        .fixedSize()
                        .offset(x: x.x)
                }
            }
            .frame(width: g.plot, height: 14, alignment: .topLeading)
        }
    }

    /// Price: ink pill. Strike: number, contracts, then its %; puts in a soft pill.
    @ViewBuilder private func tag(_ t: PChartGeom.Tag) -> some View {
        if t.isPrice {
            Text(t.num).sType(SType(size: 13, weight: 700, line: 13, tracking: 0)).foregroundStyle(S.paper)
                .padding(.horizontal, 7).frame(height: 18)
                .background(Capsule().fill(S.ink))
                .fixedSize()
        } else {
            HStack(spacing: 4) {
                Text(t.num).sType(SType(size: 13, weight: 700, line: 13, tracking: 0)).foregroundStyle(S.ink)
                // Contracts at the strike (Nik, 14 Oct 2026), then the distance.
                Text(t.qty).sType(SType(size: 11, weight: 600, line: 11, tracking: 0)).foregroundStyle(S.ink)
                Text(t.sub).sType(SType(size: 11, weight: 600, line: 11, tracking: 0)).foregroundStyle(S.muted)
            }
            .padding(.horizontal, t.isPut ? 6 : 0).frame(height: 18)
            .background { if t.isPut { Capsule().fill(S.pTrack) } }
            .fixedSize()
        }
    }
}

/// The live ring: grows from the dot to 2.8x and fades in 1.6 s, rests
/// 0.4 s, repeats while the market is open. Core Animation runs it, so the
/// page is not redrawn every frame: as a SwiftUI keyframe animation inside a
/// glass card it held the app at about 80% CPU (Planner audit, 14 Oct 2026).
struct PLivePulse: View {
    let color: Color
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        PulseRing(color: color, dark: scheme == .dark)
            .frame(width: 12, height: 12)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct PulseRing: UIViewRepresentable {
    let color: Color
    let dark: Bool

    func makeUIView(context: Context) -> RingView { RingView() }
    func updateUIView(_ v: RingView, context: Context) {
        let ui = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        v.ring.fillColor = ui.withAlphaComponent(0.45).cgColor
    }

    final class RingView: UIView {
        let ring = CAShapeLayer()
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            layer.addSublayer(ring)
            NotificationCenter.default.addObserver(self, selector: #selector(restart),
                                                   name: UIApplication.willEnterForegroundNotification, object: nil)
        }
        @objc private func restart() { ring.removeAnimation(forKey: "pulse"); setNeedsLayout() }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() {
            super.layoutSubviews()
            ring.frame = bounds
            ring.path = UIBezierPath(ovalIn: bounds).cgPath
            guard ring.animation(forKey: "pulse") == nil, bounds.width > 0 else { return }
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [1, 2.8, 2.8]
            scale.keyTimes = [0, 0.8, 1]
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 0, 0]
            fade.keyTimes = [0, 0.8, 1]
            let ease = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
            scale.timingFunctions = [ease, CAMediaTimingFunction(name: .linear)]
            fade.timingFunctions = [ease, CAMediaTimingFunction(name: .linear)]
            let g = CAAnimationGroup()
            g.animations = [scale, fade]
            g.duration = 2.0
            g.repeatCount = .infinity
            g.isRemovedOnCompletion = false
            ring.add(g, forKey: "pulse")
        }
        // Back on screen or from the background: start it again.
        override func didMoveToWindow() {
            super.didMoveToWindow()
            restart()
        }
    }
}

private struct PLineShape: Shape {
    let segments: [[CGPoint]]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for s in segments {
            guard let f = s.first else { continue }
            p.move(to: f)
            for q in s.dropFirst() { p.addLine(to: q) }
        }
        return p
    }
}

private struct PHLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p
    }
}

/// A 1 pt connector from the plot's edge (x 240) to a tag moved off its line (x 246).
private struct PConnectors: Shape {
    let plot: CGFloat
    let items: [(y: CGFloat, cy: CGFloat)]
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in items { p.move(to: CGPoint(x: plot, y: i.y)); p.addLine(to: CGPoint(x: plot + 6, y: i.cy)) }
        return p
    }
}

// MARK: - Motion and parts

extension PStatus {
    /// Green on your side, gray inside 1%, red on the wrong side.
    var dot: Color { switch self { case .safe: S.green; case .near: S.pNeutral; case .past: S.red } }
}

private extension View {
    /// Cards and totals rise 14 pt and fade in, 0.6 s, the first time their page shows.
    func pEnter(_ go: Bool, _ delay: Double) -> some View { modifier(PEnter(on: go, delay: delay)) }
    /// Ticks, labels and tags drop 4 pt and fade in, 0.4 s.
    func pDrop(_ on: Bool, _ delay: Double) -> some View { modifier(PDrop(on: on, delay: delay)) }
}

private struct PEnter: ViewModifier {
    let on: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        // Value-keyed, not `animation(_:body:)`: offsets inside a body-scoped
        // animation jumped (audit, 13 Oct 2026: no rise, no slide).
        let shown = on || reduce
        content
            .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 14)
            .animation(reduce ? nil : S.standard(0.6).delay(delay), value: shown)
    }
}

private struct PDrop: ViewModifier {
    let on: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0).offset(y: on ? 0 : -4)
            .animation(reduce ? nil : S.standard(0.4).delay(delay), value: on)
    }
}

/// A big number that counts up from 0 the first time its page shows (0.9 s
/// ease-out, from `delay`), then rolls its digits on every change.
private struct PNum: View {
    let value: Double
    let format: (Double) -> String
    let go: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown: Double = 0
    @State private var started = false
    @State private var counting = false

    var body: some View {
        Group {
            if counting {
                PCounting(value: shown, format: format)
            } else {
                Text(format(started ? shown : reduce ? value : 0)).contentTransition(.numericText(value: shown))
            }
        }
        .onAppear { if go { start() } }
        .onChange(of: go) { _, g in if g { start() } }
        .onChange(of: value) { _, v in
            guard started else { return }
            if counting || reduce { shown = v } else { withAnimation(.smooth(duration: S.roll)) { shown = v } }
        }
    }

    private func start() {
        guard !started else { return }
        started = true
        if reduce { shown = value; return }
        counting = true
        shown = 0
        withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.9).delay(delay)) { shown = value } completion: { counting = false }
    }
}

private struct PCounting: View, Animatable {
    var value: Double
    let format: (Double) -> String
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { Text(format(value)) }
}

private struct PPress: ButtonStyle {
    let scale: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: S.tap), value: configuration.isPressed)
    }
}

/// The page-top number dims while pressed (the design's active opacity .6).
private struct POpacityPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: S.tap), value: configuration.isPressed)
    }
}

// MARK: - Strategy (block 13b)

/// The three strategy tags (Nik, 19 Oct 2026: the names are placeholders for now).
enum Strategy {
    static func name(_ s: String?) -> String? {
        switch s { case "aftershock": "Aftershock"; case "rebound": "Rebound"; case "ladder": "Ladder"; default: nil }
    }
    /// The Thesis page's opening line per strategy (14c), and its section order.
    static func premise(_ s: String?) -> String? {
        switch s {
        case "ladder": "sell calls on the LEAP shares every week, one rung above the price."
        case "aftershock": "after a 15% one-day drop that holds on Day 2, sell calls closer while the crash premium lasts."
        case "rebound": "off the low and turning up, so calls go further out to leave room for the climb."
        default: nil
        }
    }
    /// Section ids f(undamentals) p(rice) i(v) e(vents) d(elta); Portfolio delta always last.
    static func order(_ s: String?) -> [String] {
        switch s {
        case "aftershock": ["e", "p", "i", "f", "d"]
        case "rebound": ["p", "f", "i", "e", "d"]
        default: ["f", "p", "i", "e", "d"]
        }
    }
}
