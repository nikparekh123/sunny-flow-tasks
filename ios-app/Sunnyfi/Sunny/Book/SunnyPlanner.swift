//
//  SunnyPlanner.swift
//  Sunny
//
//  Blocks 14b + 14c (handoff 27) · the Thesis and Planner screen: one pushed
//  screen, a horizontal pager of two pages. The Thesis (0) says why next
//  week's call strike sits where it does; the Planner (1) is the whole
//  package for one name: the glass position card (Strikes lanes or Week
//  zones, Position now in pairs), Suggestions and Delta. The header (Back,
//  the two sliding titles, the job line) and the name chips are shared.
//  This week's thesis on a Positions card opens it on the Thesis; an
//  Inventory chip or a Delta tile, on the Planner.
//
//  The numbers are the server's package (PlannerPackage.swift): sells by
//  OUR rule (Nik: "keep ours"), the design's upside buys and fix, NOW on the
//  next-week basis, the same number as the Delta tile.
//

import SwiftUI

struct SunnyPlanner: View {
    let home: HomePayload
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.colorScheme) private var scheme
    @State private var mode: Mode = .lanes
    /// The pager: where it scrolls to, the swipe progress (0 Thesis, 1 Planner;
    /// only the header reads it, so a swipe never redraws the cards), the page
    /// it settled on, and each page's height.
    @State private var pos = ScrollPosition()
    /// The page it opened on. Set as the pager's first offset by its edge, so
    /// the page underneath never scrolls with it (an id scroll moved both).
    private let start: Int
    @State private var pager: PagerProgress
    @State private var settled: Int
    @State private var heights: [Int: CGFloat] = [:]
    /// Entrance: the three cards fade (0.5 s) and rise 14 pt (0.6 s), 70 ms apart.
    @State private var shown = [false, false, false]
    @State private var risen = [false, false, false]
    @State private var lineDrawn = false
    @State private var dotIn = false
    /// The name on screen, kept while the page slides away (Back clears the
    /// router's name first, and the page flipped to the first name mid-slide).
    @State private var lastT: String?

    enum Mode { case lanes, week }

    init(home: HomePayload, page: Int = 1) {
        self.home = home
        var start = page
        #if DEBUG && targetEnvironment(simulator)
        if DebugPreset.bool("planner.thesis") { start = 0 }
        #endif
        self.start = start
        _pager = State(initialValue: PagerProgress(p: Double(start)))
        _settled = State(initialValue: start)
    }

    private var dark: Bool { scheme == .dark }
    private var pkgs: [PlanPkg] {
        home.writes.names.compactMap { n in
            PlanPkg(n, px: home.portfolio.first { $0.ticker == n.ticker }?.spot ?? n.spot ?? 0)
        }.sorted { $0.t < $1.t }
    }

    var body: some View {
        let all = pkgs
        let cur = all.first { $0.t == (router.writes ?? lastT) } ?? all.first
        ZStack(alignment: .top) {
            PlannerAmbient()
            // The page width is read, never written back into state: a
            // measured width fed into the layout it measures can loop.
            GeometryReader { g in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        backRow
                        PairHeader(pager: pager, go: go(to:))
                        chips(all, cur)
                        pages(cur, W: max(260, g.size.width - 2 * S.margin - 40))
                    }
                    .foregroundStyle(S.ink)
                    .padding(.horizontal, S.margin)
                    .padding(.top, 14).padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
        }
        // Back from the left edge, as iOS does, from the Thesis; on the
        // Planner the same swipe pages back to the Thesis.
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in
            let dx = v.translation.width, dy = v.translation.height
            if settled == 0, v.startLocation.x < 30, dx > 80, abs(dy) < 60 { back() }
        })
        .task(id: cur?.t) {
            lastT = cur?.t
            await entrance()
        }
        .onAppear {
            #if DEBUG && targetEnvironment(simulator)
            if DebugPreset.string("planner.view") == "week" { mode = .week }
            #endif
        }
    }

    // MARK: The pager

    /// Thesis (0) and Planner (1), one page at a time. As tall as the page
    /// you are on; the height eases 0.4 s when a page settles. 24 under each
    /// page is room for the card shadow, taken back from the layout.
    private func pages(_ cur: PlanPkg?, W: CGFloat) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 0) {
                page(0) { thesisPage(cur) }
                page(1) {
                    VStack(alignment: .leading, spacing: 16) {
                        if let p = cur { cards(p, W: W) }
                        else {
                            Text("Nothing to plan this week.").sType(.body, tabular: false).foregroundStyle(S.muted)
                        }
                    }
                }
            }
            .scrollTargetLayout()
            // Top down: the shorter page would sit centred on the taller one.
            .frame(height: heights[settled], alignment: .top)
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition($pos)
        .defaultScrollAnchor(start == 1 ? .trailing : .leading, for: .initialOffset)
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Double.self) { g in
            Double(g.contentOffset.x / max(1, g.containerSize.width))
        } action: { _, v in
            pager.p = min(1, max(0, v))
        }
        .onScrollPhaseChange { _, ph in
            if ph == .idle { settle() }
        }
        .frame(height: heights[settled])
        .animation(reduce ? nil : S.standard(0.4), value: heights[settled])
        .padding(.horizontal, -S.margin)
        .padding(.bottom, -24)
    }

    private func page<C: View>(_ i: Int, @ViewBuilder _ c: () -> C) -> some View {
        c()
            .padding(.horizontal, S.margin)
            .padding(.bottom, 24)
            .containerRelativeFrame(.horizontal)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[i] = $0 }
    }

    @ViewBuilder private func thesisPage(_ cur: PlanPkg?) -> some View {
        if let p = cur {
            PlannerThesisView(ticker: p.t, strategy: home.strategies?[p.t], th: thesisFor(p))
        }
    }

    private func settle() {
        let s = Int(pager.p.rounded())
        if s != settled { settled = s }
    }

    /// A tap on the gray title runs the same scroll, about 0.6 s.
    private func go(to i: Int) {
        guard i != settled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        let edge: Edge = i == 0 ? .leading : .trailing
        if reduce { pos.scrollTo(edge: edge) } else { withAnimation(.smooth(duration: 0.6)) { pos.scrollTo(edge: edge) } }
    }

    /// Replays on every name change; Reduce Motion shows everything at once.
    private func entrance() async {
        var t = Transaction(); t.disablesAnimations = true
        if reduce {
            withTransaction(t) { shown = [true, true, true]; risen = [true, true, true]; lineDrawn = true; dotIn = true }
            return
        }
        withTransaction(t) { shown = [false, false, false]; risen = [false, false, false]; lineDrawn = false; dotIn = false }
        try? await Task.sleep(for: .milliseconds(32))
        guard !Task.isCancelled else { return }
        for i in 0..<3 {
            withAnimation(.easeInOut(duration: 0.5).delay(Double(i) * S.stagger)) { shown[i] = true }
            withAnimation(S.standard(0.6).delay(Double(i) * S.stagger)) { risen[i] = true }
        }
        withAnimation(S.standard(0.9).delay(0.1)) { lineDrawn = true }
        withAnimation(.easeOut(duration: 0.3).delay(0.85)) { dotIn = true }
    }

    // MARK: Header and name chips

    private var backRow: some View {
        Button { back() } label: {
            Path { p in p.move(to: CGPoint(x: 8, y: 2)); p.addLine(to: CGPoint(x: 2, y: 8)); p.addLine(to: CGPoint(x: 8, y: 14)) }
                .stroke(S.ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .frame(width: 10, height: 16)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(Circle())
        }
        .buttonStyle(SPressStyle(scale: 0.95))
        .padding(-2)
        .frame(height: 40)
        .accessibilityLabel("Back")
    }

    /// Back returns to wherever the screen was opened from.
    private func back() { router.closePlanner() }

    /// The thesis for a name: NKE's read rule while it picks, else the 0.6 SD
    /// Planner rule with the name's reads; nil shows "No thesis for X yet".
    private func thesisFor(_ p: PlanPkg) -> Thesis? {
        guard let n = home.writes.names.first(where: { $0.ticker == p.t }),
              let r = n.readRule?.value ?? n.thesis?.value else { return nil }
        let off = router.pkgOff[p.t] ?? [], pick = router.pkgFix[p.t]
        return Thesis(r, p, afterP: p.pct(p.after(p.live(off: off, pick: pick))), strategy: home.strategies?[p.t])
    }

    private func chips(_ all: [PlanPkg], _ cur: PlanPkg?) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(all, id: \.t) { p in
                        let on = p.t == cur?.t, a = p.alert
                        Button { if !on { router.writes = p.t } } label: {
                            HStack(spacing: 6) {
                                if let a { BreathDot(alert: a).frame(width: 6, height: 6) }
                                Text(p.t).sType(SType(size: 13, weight: 700, line: 13, tracking: 0), tabular: false)
                                Text("\(Int(abs(p.nowPct).rounded()))%")
                                    .sType(SType(size: 13, weight: 600, line: 13, tracking: 0))
                                    .foregroundStyle(on ? S.paper.opacity(0.72) : a?.ink ?? S.muted)
                            }
                            .foregroundStyle(on ? S.paper : S.ink)
                            .padding(.horizontal, 12).frame(height: 32)
                            .background { if on { Capsule().fill(S.ink).shadow(color: .black.opacity(0.2), radius: 6, y: 4) } }
                            .glassEffect(on ? .identity : .regular.interactive(), in: .capsule)
                            .contentShape(Capsule().inset(by: -6))
                        }
                        .buttonStyle(SPressStyle(scale: 0.95))
                        .accessibilityLabel("\(p.t), \(Int(abs(p.nowPct).rounded())) percent delta left\(a == .red ? ", net short" : a == .orange ? ", thin" : "")")
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .id(p.t)
                    }
                }
                .padding(.top, 8).padding(.bottom, 10)
            }
            .contentMargins(.horizontal, S.margin, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .padding(.horizontal, -S.margin).padding(.top, -8).padding(.bottom, -10)
            .onAppear { if let t = cur?.t { proxy.scrollTo(t, anchor: .center) } }
            .onChange(of: cur?.t) { _, t in
                if let t { withAnimation(S.standard(0.4)) { proxy.scrollTo(t, anchor: .center) } }
            }
        }
    }

    // MARK: The three cards

    /// `W`: the card's inner width, 313 on a 393 phone.
    @ViewBuilder private func cards(_ p: PlanPkg, W: CGFloat) -> some View {
        let off = router.pkgOff[p.t] ?? [], pick = router.pkgFix[p.t]
        let live = p.live(off: off, pick: pick)
        let afterP = p.pct(p.after(live))
        positionCard(p, live: live, afterP: afterP, W: W).modifier(Rise(on: shown[0], up: risen[0]))
        suggestionsCard(p, off: off, pick: pick, live: live).modifier(Rise(on: shown[1], up: risen[1]))
        deltaCard(p, afterP: afterP, safeP: p.safe == nil ? nil : p.safePct(live), W: W).modifier(Rise(on: shown[2], up: risen[2]))
    }

    // MARK: Position card (glass)

    private func positionCard(_ p: PlanPkg, live: [PlanPkg.Leg], afterP: Double, W: CGFloat) -> some View {
        let every = p.held + live
        let shownLegs = every
        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(p.t).sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false)
                    Text(" " + String(format: "%.2f", p.px)).sType(SType(size: 20, weight: 500, line: 24, tracking: 0))
                        .foregroundStyle(S.muted)
                        .contentTransition(.numericText(value: p.px))
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text("By Fri").sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
                    if let d = p.nextEarnings {
                        Text("·").sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
                        Text("Earnings \(F.day(d))").sType(SType(size: 13, weight: p.e > 0 ? 700 : 500, line: 16, tracking: 0))
                            .foregroundStyle(p.e > 0 ? S.yellowDeep : S.muted)
                    }
                }
                .lineLimit(1)
            }
            .frame(height: 24)
            modeSwitch
            Group {
                if mode == .lanes { lanes(p, every: every, shown: shownLegs, W: W) } else { week(p, shown: shownLegs, W: W) }
            }
            positionNow(p)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // The corner tint follows the band after the plan.
            let tint = p.band(afterP).tint
            GeometryReader { g in
                let rx = 1.3 * g.size.width, ry = 0.4 * g.size.height
                Rectangle()
                    .fill(RadialGradient(colors: [tint.opacity(dark ? 0.2 : 0.24), tint.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: rx * 0.6))
                    .frame(width: 2 * rx, height: 2 * rx)
                    .scaleEffect(x: 1, y: ry / rx)
                    .position(x: 0, y: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .animation(.easeInOut(duration: 0.25), value: p.band(afterP))
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var modeSwitch: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(S.ink).frame(width: 72, height: 28)
                .offset(x: mode == .lanes ? 0 : 72)
            HStack(spacing: 0) {
                seg("Strikes", .lanes)
                seg("Week", .week)
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
    }

    private func seg(_ t: String, _ m: Mode) -> some View {
        Button { withAnimation(reduce ? nil : S.standard(0.3)) { mode = m } } label: {
            Text(t).sType(SType(size: 12, weight: 600, line: 12, tracking: 0), tabular: false)
                .foregroundStyle(mode == m ? S.paper : S.ink)
                .frame(width: 72, height: 28)
                .contentShape(Rectangle().inset(by: -8))   // 44 pt to the touch, 28 to the eye
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == m ? .isSelected : [])
    }

    // MARK: Chip looks

    private struct Look { let c: Color; let sc: Color; let bg: Color; let ring: Color?; let line: StrokeStyle; let lineC: Color }

    private func side(_ l: PlanPkg.Leg) -> Color { l.call ? S.green : S.blue }
    /// Tinted is long and on now; solid is short and on now; outlined is a
    /// suggestion you are keeping (dashed in Week).
    private func look(_ l: PlanPkg.Leg) -> Look {
        let c = side(l)
        if l.sugg {
            return Look(c: c, sc: c, bg: S.paper.opacity(0.85), ring: c, line: StrokeStyle(lineWidth: 1.5, dash: [4, 3]), lineC: c)
        }
        if l.short {
            return Look(c: S.paper, sc: S.paper.opacity(dark ? 0.72 : 0.85), bg: c, ring: nil, line: StrokeStyle(lineWidth: 1.5), lineC: c)
        }
        return Look(c: c, sc: c, bg: c.opacity(dark ? 0.22 : 0.14), ring: nil, line: StrokeStyle(lineWidth: 1), lineC: c.opacity(0.45))
    }

    private func legChip(_ l: PlanPkg.Leg, h: CGFloat = 20) -> some View {
        let lk = look(l)
        return HStack(spacing: 4) {
            Text(PP.k(l.k)).sType(SType(size: 12, weight: 700, line: 12, tracking: 0)).foregroundStyle(lk.c)
            Text("×\(l.n)").sType(SType(size: 11, weight: 600, line: 11, tracking: 0)).foregroundStyle(lk.sc)
        }
        .lineLimit(1).fixedSize()
        .padding(.horizontal, h == 20 ? 7 : 6)
        .frame(height: h)
        .background(Capsule().fill(lk.bg))
        .overlay { if let r = lk.ring { Capsule().strokeBorder(r, lineWidth: 1.5) } }
    }

    /// The design's width estimate, so chips stack before they touch.
    private func est(_ t: String) -> CGFloat {
        let digits = t.filter { $0.isNumber || $0 == "." }.count
        return CGFloat(digits) * 7.2 + CGFloat(t.count - digits) * 6 + 14
    }

    // MARK: Strikes · three lanes on one square-root distance axis

    private func lanes(_ p: PlanPkg, every: [PlanPkg.Leg], shown: [PlanPkg.Leg], W: CGFloat) -> some View {
        let LW = W, px = p.px
        let dS = { (k: Double) -> Double in px > 0 ? (k - px) / px * 100 : 0 }
        let tr = { (d: Double) -> Double in (d < 0 ? -1 : 1) * abs(d).squareRoot() }
        // The scale comes from everything on the chart before filters, so a
        // filter never moves it.
        let ds = every.map { dS($0.k) } + [6, -6]
        let r1 = tr(ds.max()!) * 1.06, r0 = tr(ds.min()!) * 1.06
        let Xc = { (d: Double) -> CGFloat in 24 + CGFloat((tr(d) - r0) / max(0.0001, r1 - r0)) * (LW - 48) }
        let defs: [(String, String, [PlanPkg.Ty])] = [("c", "Calls", [.lc, .sc]), ("p", "Puts", [.lp, .sp]), ("o", "OTM calls", [.oc])]
        let cx = Xc(0)
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(defs, id: \.0) { key, title, tys in
                if every.contains(where: { tys.contains($0.ty) }) {
                    lane(p, title: title, key: key, tys: tys, every: every, shown: shown, LW: LW, Xc: Xc, dS: dS)
                }
            }
            ZStack(alignment: .topLeading) {
                ForEach(axisTicks(Xc, LW: LW), id: \.0) { d, x in
                    Text(d == 0 ? "0" : "\(Int(abs(d)))%")
                        .sType(SType(size: 11, weight: d == 0 ? 700 : 600, line: 14, tracking: 0))
                        .foregroundStyle(d == 0 ? S.ink : S.pNeutral)
                        .fixedSize()
                        .position(x: x, y: 7)
                }
            }
            .frame(width: LW, height: 14)
            HStack {
                Text("← Below"); Spacer(); Text("Above →")
            }
            .sType(SType(size: 11, weight: 600, line: 13, tracking: 0.04), tabular: false)
            .textCase(.uppercase)
            .foregroundStyle(S.pNeutral)
            .padding(.top, -10)
        }
        .padding(.top, 30)
        // Today's line runs behind the lanes and their chips.
        .background(alignment: .topLeading) {
            GeometryReader { g in
                Rectangle().fill(dark ? Color.white.opacity(0.5) : S.ink.opacity(0.45))
                    .frame(width: 1.5, height: max(0, g.size.height - 22 - 32))
                    .offset(x: cx - 0.75, y: 22)
                Text(String(format: "%.2f", px))
                    .sType(SType(size: 12, weight: 700, line: 12, tracking: 0))
                    .foregroundStyle(S.paper)
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(Capsule().fill(S.ink))
                    .fixedSize()
                    .frame(width: 70)
                    .offset(x: max(0, min(LW - 70, cx - 35)))
            }
            .allowsHitTesting(false)
        }
        .frame(width: LW, alignment: .leading)
    }

    private func lane(_ p: PlanPkg, title: String, key: String, tys: [PlanPkg.Ty], every: [PlanPkg.Leg],
                      shown: [PlanPkg.Leg], LW: CGFloat, Xc: @escaping (Double) -> CGFloat,
                      dS: @escaping (Double) -> Double) -> some View {
        let held = p.held.filter { tys.contains($0.ty) }
        let lq = held.filter { !$0.short }.reduce(0) { $0 + $1.n }, sq = held.filter(\.short).reduce(0) { $0 + $1.n }
        let rowsAll = Self.place(every.filter { tys.contains($0.ty) }, LW: LW, Xc: Xc, dS: dS, est: est).rows
        let placed = Self.place(shown.filter { tys.contains($0.ty) }, LW: LW, Xc: Xc, dS: dS, est: est)
        // The lane keeps its height when a filter clears chips from it.
        let h = 6 + CGFloat(max(1, rowsAll, placed.rows)) * 40
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
                Spacer()
                Text(key == "o" ? (lq > 0 ? "\(lq) held" : "none held") : "\(lq) long · \(sq) short")
                    .sType(SType(size: 12, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.pNeutral)
            }
            .frame(height: 16)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(dark ? Color.white.opacity(0.05) : S.ink.opacity(0.035))
                ForEach(placed.chips, id: \.leg.id) { c in
                    legChip(c.leg)
                        .frame(width: c.w)
                        .offset(x: c.l, y: 6 + CGFloat(c.row) * 40)
                    Text(PP.pct(abs(dS(c.leg.k))))
                        .sType(SType(size: 11, weight: 700, line: 14, tracking: 0))
                        .foregroundStyle(S.ink)
                        .fixedSize()
                        .frame(width: 60)
                        .offset(x: c.l + c.w / 2 - 30, y: 6 + CGFloat(c.row) * 40 + 21)
                }
            }
            .frame(width: LW, height: h, alignment: .topLeading)
        }
    }

    private struct Placed { let leg: PlanPkg.Leg; let w: CGFloat; let l: CGFloat; let row: Int }
    /// Each chip centred on its strike; chips that would touch stack into rows 40 apart.
    private static func place(_ legs: [PlanPkg.Leg], LW: CGFloat, Xc: (Double) -> CGFloat, dS: (Double) -> Double,
                              est: (String) -> CGFloat) -> (chips: [Placed], rows: Int) {
        let items = legs.map { l -> (PlanPkg.Leg, CGFloat, CGFloat) in
            (l, est("\(PP.k(l.k)) ×\(l.n)"), Xc(dS(l.k)))
        }.sorted { $0.2 < $1.2 }
        var ends: [CGFloat] = [], out: [Placed] = []
        for (l, w, x) in items {
            let l0 = max(0, min(LW - w, x - w / 2))
            var r = 0
            while r < ends.count, ends[r] > l0 - 6 { r += 1 }
            if r == ends.count { ends.append(l0 + w) } else { ends[r] = l0 + w }
            out.append(Placed(leg: l, w: w, l: l0, row: r))
        }
        return (out, ends.count)
    }

    /// 0 first, then the widest steps that keep 30 pt apart.
    private func axisTicks(_ Xc: (Double) -> CGFloat, LW: CGFloat) -> [(Double, CGFloat)] {
        var kept: [(Double, CGFloat)] = [(0, Xc(0))]
        for d in [30.0, -30, 20, -20, 10, -10, 5, -5, 2, -2] {
            let x = Xc(d)
            if x >= 12, x <= LW - 12, kept.allSatisfy({ abs($0.1 - x) >= 30 }) { kept.append((d, x)) }
        }
        return kept.sorted { $0.1 < $1.1 }
    }

    // MARK: Week · the price line over the zones this week's short strikes make

    @ViewBuilder private func week(_ p: PlanPkg, shown: [PlanPkg.Leg], W: CGFloat) -> some View {
        if let g = WeekGeom(p, shown: shown, home: home, dark: dark) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    ForEach(g.zones, id: \.key) { z in
                        Rectangle().fill(z.bg).frame(width: WeekGeom.PRd, height: max(0, z.h)).offset(y: z.top)
                    }
                    if let ex = g.earnX {
                        Path { q in q.move(to: CGPoint(x: ex, y: 0)); q.addLine(to: CGPoint(x: ex, y: WeekGeom.HD)) }
                            .stroke(S.yellowDeep, style: StrokeStyle(lineWidth: 1.5, dash: [1.5, 2.5]))
                    }
                    ForEach(g.lines, id: \.leg.id) { ln in
                        let lk = look(ln.leg)
                        Path { q in q.move(to: CGPoint(x: 0, y: ln.y)); q.addLine(to: CGPoint(x: WeekGeom.PRd, y: ln.y)) }
                            .stroke(lk.lineC, style: lk.line)
                    }
                    g.path.trim(from: 0, to: lineDrawn ? 1 : 0)
                        .stroke(g.lineC, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    g.conn.stroke(S.muted, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    ForEach(g.zones.filter(\.showLabel), id: \.key) { z in
                        Text(z.label).sType(SType(size: 11, weight: 700, line: 13, tracking: 0), tabular: false)
                            .foregroundStyle(z.c)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(dark ? Color.black.opacity(0.45) : Color.white.opacity(0.72)))
                            .fixedSize()
                            .offset(x: 6, y: z.top + 5)
                    }
                    Circle().fill(S.paper)
                        .overlay(Circle().strokeBorder(g.lineC, lineWidth: 2.5))
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
                        .offset(x: g.dot.x - 6, y: g.dot.y - 6)
                        .opacity(dotIn ? 1 : 0)
                    ForEach(g.tags, id: \.key) { t in
                        Group {
                            if let l = t.leg {
                                let lk = look(l)
                                HStack(spacing: 4) {
                                    Text(t.num).sType(SType(size: 12, weight: 700, line: 12, tracking: 0)).foregroundStyle(lk.c)
                                    Text(t.sub).sType(SType(size: 11, weight: 600, line: 11, tracking: 0)).foregroundStyle(lk.sc)
                                }
                                .padding(.horizontal, 6).frame(height: 18)
                                .background(Capsule().fill(lk.bg))
                                .overlay { if let r = lk.ring { Capsule().strokeBorder(r, lineWidth: 1.5) } }
                            } else {
                                Text(t.num).sType(SType(size: 12, weight: 700, line: 12, tracking: 0)).foregroundStyle(S.paper)
                                    .padding(.horizontal, 6).frame(height: 18)
                                    .background(Capsule().fill(S.ink))
                            }
                        }
                        .fixedSize()
                        .offset(x: 208, y: t.top)
                    }
                }
                .frame(width: W, height: WeekGeom.HD, alignment: .topLeading)
                ZStack(alignment: .topLeading) {
                    ForEach(g.xl, id: \.1) { t, x in
                        Text(t).sType(SType(size: 11, weight: 500, line: 14, tracking: 0), tabular: false)
                            .foregroundStyle(S.muted).fixedSize().offset(x: x)
                    }
                }
                .frame(width: WeekGeom.PRd, height: 14, alignment: .topLeading)
            }
        } else {
            Text("Hourly closes are not in yet.").sType(.note, tabular: false).foregroundStyle(S.muted)
                .frame(height: WeekGeom.HD + 22, alignment: .center)
        }
    }

    // MARK: Position now, in pairs

    private struct PRow: Identifiable {
        let id: String; let tag: String; let tagBg: Color; let tagC: Color; let tagRing: Color?
        let t: String; let m: String; let v: String; let d: String; let dC: Color; let op: Double
    }

    private func positionNow(_ p: PlanPkg) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Position now").sType(SType(size: 17, weight: 700, line: 22, tracking: 0), tabular: false)
            ForEach(groups(p), id: \.0) { _, title, n, rows in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
                        Spacer()
                        Text(n).sType(SType(size: 12, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.pNeutral)
                    }
                    .frame(height: 20)
                    ForEach(rows) { r in prow(r) }
                }
            }
        }
        .padding(.top, 20)
        .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
    }

    private func prow(_ r: PRow) -> some View {
        HStack(spacing: 12) {
            Text(r.tag).sType(SType(size: 11, weight: 700, line: 11, tracking: 0), tabular: false)
                .foregroundStyle(r.tagC)
                .frame(width: 44, height: 22)
                .background(Capsule().fill(r.tagBg))
                .overlay { if let c = r.tagRing { Capsule().strokeBorder(c, lineWidth: 1) } }
            VStack(alignment: .leading, spacing: 2) {
                Text(r.t).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: r.tag != "None").lineLimit(1)
                Text(r.m).sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(r.v).sType(SType(size: 15, weight: 700, line: 20, tracking: 0)).lineLimit(1)
                Text(r.d).sType(SType(size: 12, weight: 500, line: 16, tracking: 0)).foregroundStyle(r.dC).lineLimit(1)
            }
            .fixedSize()
        }
        .frame(minHeight: 52)
        .opacity(r.op)
        .accessibilityElement(children: .combine)
    }

    private func groups(_ p: PlanPkg) -> [(String, String, String, [PRow])] {
        let edgeOff = dark ? Color.white.opacity(0.16) : S.ink.opacity(0.14)
        let day = { (iso: String) in PP.date(iso, today: home.today) }
        // On the next-week basis a Friday's week has already rolled: its
        // "this week" ends the Friday after (the design's Oct 16 shows Oct 23).
        let thisFri = Self.weekEnd(WeekGeom.addDays(home.today, 1))
        let row = { (l: PlanPkg.Leg, m: String) -> PRow in
            let long = !l.short
            return PRow(id: l.id, tag: long ? "Long" : "Short", tagBg: long ? S.pTrack : self.side(l).opacity(self.dark ? 0.22 : 0.14),
                        tagC: long ? S.ink : self.side(l), tagRing: nil,
                        t: "\(l.n) × \(PP.k(l.k)) \(l.call ? "C" : "P")", m: m, v: PP.dist(l.k, p.px),
                        d: PP.d(l.d) + " Δ", dC: l.d < 0 ? S.red : S.muted, op: 1)
        }
        let none = { (key: String, lab: String) in
            PRow(id: key, tag: "None", tagBg: .clear, tagC: S.muted, tagRing: edgeOff, t: lab,
                 m: "not bought yet · in Suggestions", v: "", d: "", dC: S.muted, op: 0.6)
        }
        let soldWord = { (l: PlanPkg.Leg) in (l.exp <= thisFri ? "Sold this week · " : "Sold · ") + day(l.exp) }
        let of = { (ty: PlanPkg.Ty) in p.held.filter { $0.ty == ty } }
        var out: [(String, String, String, [PRow])] = []
        let lc = of(.lc), sc = of(.sc)
        out.append(("c", "Calls", "\(lc.reduce(0) { $0 + $1.n }) long · \(sc.reduce(0) { $0 + $1.n }) short",
                    lc.map { row($0, "LEAPs · " + day($0.exp)) } + sc.map { row($0, soldWord($0)) }))
        let lp = of(.lp), sp = of(.sp)
        if !lp.isEmpty || !sp.isEmpty {
            out.append(("p", "Puts", "\(lp.reduce(0) { $0 + $1.n }) long · \(sp.reduce(0) { $0 + $1.n }) short",
                        lp.map { row($0, "Hedge · " + day($0.exp)) } + sp.map { row($0, soldWord($0)) }))
        }
        let oc = of(.oc)
        let h12 = oc.filter { $0.tenor == "12m" }, h3 = oc.filter { $0.tenor != "12m" }
        let state = !h12.isEmpty && !h3.isEmpty ? "fully set" : oc.isEmpty ? "nothing bought yet" : "partly bought"
        let up = { (xs: [PlanPkg.Leg], word: String, key: String) -> [PRow] in
            xs.isEmpty ? [none(key, word)] : xs.map { row($0, "\(word) · rolls \(day($0.roll ?? $0.exp))") }
        }
        out.append(("o", "OTM calls", state, up(h12, "12-month", "n12") + up(h3, "3-month", "n3")))
        return out
    }

    /// The Friday that ends this week (a weekend counts toward the next one).
    static func weekEnd(_ today: String) -> String {
        let p = today.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return today }
        var c = DateComponents(); c.year = p[0]; c.month = p[1]; c.day = p[2]; c.hour = 12
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        guard let d = cal.date(from: c) else { return today }
        let wd = cal.component(.weekday, from: d)          // 1 Sun ... 7 Sat
        let add = wd == 7 ? 6 : (6 - wd + 7) % 7
        let f = cal.date(byAdding: .day, value: add, to: d)!
        let fc = cal.dateComponents([.year, .month, .day], from: f)
        return String(format: "%04d-%02d-%02d", fc.year!, fc.month!, fc.day!)
    }

    // MARK: Suggestions

    private func suggestionsCard(_ p: PlanPkg, off: Set<String>, pick: String?, live: [PlanPkg.Leg]) -> some View {
        let credit = live.filter(\.short).reduce(0) { $0 + Double($1.n) * 100 * ($1.mid ?? 0) }
        let cost = live.filter { !$0.short }.reduce(0) { $0 + Double($1.n) * 100 * ($1.mid ?? 0) }
        let f = pick ?? "fq"
        /* The +1.5 SD check with the plan as it stands, before the fix (20 Oct 2026). */
        let short15 = p.safe.map { _ in p.safePct(p.live(off: off, pick: "none")) }.flatMap { $0 < 0 ? $0 : nil }
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Suggestions").sType(SType(size: 17, weight: 700, line: 22, tracking: 0), tabular: false)
                Spacer()
                Text("next week · tap to switch off").sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false)
                    .foregroundStyle(S.pNeutral)
            }
            if p.sug.isEmpty {
                Text("Everything for \(F.day(p.plannedFor)) is sold.")
                    .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(S.muted)
            } else {
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(p.sug) { l in
                        let on = !off.contains(l.id)
                        sChip(p, l, on: on) { toggle(p.t, l.id) }
                    }
                }
            }
            if !p.fix.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(S.breatheOrange).frame(width: 6, height: 6).padding(.top, 6)
                        (short15 != nil && p.safe != nil
                         ? Text("To stay safe. ").font(SType(size: 13, weight: 600, line: 18, tracking: 0).font()).foregroundStyle(S.ink)
                            + Text("At +\(F.trim(p.safe!.sd)) SD, \(PP.money(p.safe!.px)) by \(PP.weekday(p.safe!.by)), delta would be \(Int(abs(short15!).rounded()))% net short. Pick one to hold it at zero or above.")
                         : Text("To stay on target. ").font(SType(size: 13, weight: 600, line: 18, tracking: 0).font()).foregroundStyle(S.ink)
                            + Text("Still under \(Int(20 + p.e))% with the plan on. Pick one to land on \(Int(25 + p.e))%."))
                            .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false)
                            .foregroundStyle(S.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(p.fix) { l in
                            sChip(p, l, on: f == l.id) {
                                withAnimation(reduce ? nil : S.standard(0.3)) { router.pkgFix[p.t] = f == l.id ? "none" : l.id }
                            }
                        }
                    }
                }
                .padding(.top, 16)
                .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
            }
            Text("\(PP.usd(credit)) in · \(PP.usd(cost)) out")
                .sType(SType(size: 13, weight: 600, line: 16, tracking: 0))
                .contentTransition(.numericText(value: credit - cost))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(S.paper))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(S.line, lineWidth: 1))
    }

    private func toggle(_ t: String, _ id: String) {
        withAnimation(reduce ? nil : S.standard(0.3)) {
            var s = router.pkgOff[t] ?? []
            if s.contains(id) { s.remove(id) } else { s.insert(id) }
            router.pkgOff[t] = s
        }
    }

    private func sChip(_ p: PlanPkg, _ l: PlanPkg.Leg, on: Bool, tap: @escaping () -> Void) -> some View {
        let col = side(l)
        let act = (l.act ?? "") + (l.tenorWord.map { " · " + $0 } ?? "")
        let money = Double(l.n) * 100 * (l.mid ?? 0)
        return Button(action: tap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(act).sType(SType(size: 11, weight: 700, line: 13, tracking: 0), tabular: false)
                        .foregroundStyle(on ? col : S.muted).lineLimit(1)
                    Spacer(minLength: 0)
                    ZStack {
                        Circle().fill(on ? col : .clear)
                        if on {
                            Path { q in q.move(to: CGPoint(x: 4.6, y: 8.3)); q.addLine(to: CGPoint(x: 7, y: 10.6)); q.addLine(to: CGPoint(x: 11.4, y: 5.6)) }
                                .stroke(S.paper, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        } else {
                            Circle().strokeBorder(dark ? Color.white.opacity(0.3) : S.ink.opacity(0.25), lineWidth: 1.5)
                        }
                    }
                    .frame(width: 16, height: 16)
                }
                .frame(height: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(l.n) × \(PP.k(l.k)) \(l.call ? "C" : "P")").sType(SType(size: 15, weight: 600, line: 20, tracking: 0))
                    Text("\(PP.dist(l.k, p.px)) · \(PP.date(l.exp, today: home.today))")
                        .sType(SType(size: 12, weight: 600, line: 16, tracking: 0))
                    (Text("\(PP.usd(money)) \(l.fewer ? "less in" : l.short ? "in" : "out") · ")
                     + Text("\(PP.d(l.d)) Δ").foregroundStyle(l.d < 0 ? S.red : S.muted))
                        .sType(SType(size: 12, weight: 500, line: 16, tracking: 0))
                        .foregroundStyle(S.muted)
                }
                .lineLimit(1)
                .opacity(on ? 1 : 0.5)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? col.opacity(dark ? 0.14 : 0.07) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(on ? col : (dark ? Color.white.opacity(0.16) : S.ink.opacity(0.14)), lineWidth: on ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(SPressStyle(scale: 0.97))
        .accessibilityLabel("\(act), \(l.n) \(PP.k(l.k)) \(l.call ? "calls" : "puts"), \(on ? "on" : "off")")
    }

    // MARK: Delta · now against after the plan

    private func deltaCard(_ p: PlanPkg, afterP: Double, safeP: Double?, W: CGFloat) -> some View {
        let nowP = p.nowPct, e = p.e
        let bN = p.band(nowP), bA = p.band(afterP)
        let MW = W, m0 = -10.0, m1 = 50 + e
        let MX = { (v: Double) -> CGFloat in max(0, min(MW, CGFloat((v - m0) / (m1 - m0)) * MW)) }
        let nx = MX(nowP), ax = MX(afterP)
        let segs: [(Double, Double, Color)] = [
            (m0, 0, S.red.opacity(dark ? 0.32 : 0.25)),
            (0, 20 + e, S.breatheOrange.opacity(0.3)),
            (20 + e, 30 + e, Color(red: 101 / 255, green: 196 / 255, blue: 102 / 255).opacity(0.5)),
            (30 + e, m1, Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255).opacity(dark ? 0.3 : 0.16)),
        ]
        let earn = p.e > 0 ? p.nextEarnings.map { "Earnings \(F.day($0)) this week, on target is 30-40%" } : nil
        return VStack(alignment: .leading, spacing: 16) {
            Text("Delta").sType(SType(size: 17, weight: 700, line: 22, tracking: 0), tabular: false)
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(abs(nowP).rounded()))%").sType(SType(size: 28, weight: 800, line: 30, tracking: -0.02))
                        .foregroundStyle(bN.tone)
                        .contentTransition(.numericText(value: nowP))
                    Text("now · \(bN.rawValue.lowercased())").sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false)
                        .foregroundStyle(S.muted).lineLimit(1).fixedSize()
                }
                Text("→").sType(SType(size: 20, weight: 500, line: 30, tracking: 0), tabular: false)
                    .foregroundStyle(S.pNeutral).padding(.bottom, 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(abs(afterP).rounded()))%").sType(.largeNumber)
                        .foregroundStyle(bA.tone)
                        .contentTransition(.numericText(value: afterP))
                        .animation(.easeInOut(duration: 0.25), value: bA)
                    Text("after the plan · \(bA.rawValue.lowercased())").sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false)
                        .foregroundStyle(S.muted).lineLimit(1).fixedSize()
                }
            }
            ZStack(alignment: .topLeading) {
                ForEach(Array(segs.enumerated()), id: \.offset) { i, s in
                    UnevenRoundedRectangle(topLeadingRadius: i == 0 ? 4 : 0, bottomLeadingRadius: i == 0 ? 4 : 0,
                                           bottomTrailingRadius: i == segs.count - 1 ? 4 : 0, topTrailingRadius: i == segs.count - 1 ? 4 : 0)
                        .fill(s.2)
                        .frame(width: max(0, MX(s.1) - MX(s.0)), height: 8)
                        .offset(x: MX(s.0), y: 8)
                }
                Rectangle().fill(dark ? Color.white.opacity(0.45) : S.ink.opacity(0.45))
                    .frame(width: abs(ax - nx), height: 2)
                    .offset(x: min(nx, ax), y: 11)
                Circle().fill(S.paper)
                    .overlay(Circle().strokeBorder(S.muted, lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
                    .offset(x: nx - 6, y: 6)
                Circle().fill(bA.tone)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(S.paper).frame(width: 18, height: 18))
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                    .offset(x: ax - 7, y: 5)
                ForEach([0, 15 + e, 20 + e, 30 + e], id: \.self) { v in
                    Text("\(Int(v))").sType(SType(size: 11, weight: 600, line: 14, tracking: 0))
                        .foregroundStyle(S.pNeutral).fixedSize()
                        .frame(width: 30).offset(x: MX(v) - 15, y: 22)
                }
            }
            .frame(width: MW, height: 36, alignment: .topLeading)
            .animation(reduce ? nil : S.standard(0.4), value: afterP)
            VStack(alignment: .leading, spacing: 4) {
                Text("Net delta as a share of \(Int(p.base).formatted()) LEAP shares · " + (earn ?? "on target is 20-30%"))
                    .sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false)
                    .fixedSize(horizontal: false, vertical: true)
                /* The +1.5 SD check (Nik, 20 Oct 2026): safe while it stays at zero or above. */
                if let s = p.safe, let v = safeP {
                    (Text("At +\(F.trim(s.sd)) SD, \(PP.money(s.px)) by \(PP.weekday(s.by)): ")
                     + Text(v < 0 ? "\(Int(abs(v).rounded()))% net short" : "\(Int(v.rounded()))%")
                        .font(SType(size: 12, weight: 700, line: 16, tracking: 0).font(tabular: true))
                        .foregroundStyle(v < 0 ? S.red : S.ink))
                        .sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false)
                        .contentTransition(.numericText(value: v))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(S.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(S.paper))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(S.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// The entrance: fade 0.5 s and rise 14 pt 0.6 s, driven from `.task`.
private struct Rise: ViewModifier {
    let on: Bool, up: Bool
    func body(content: Content) -> some View { content.opacity(on ? 1 : 0).offset(y: up ? 0 : 14) }
}

/// The swipe progress, 0 on the Thesis, 1 on the Planner. A class, so only
/// the header that reads it redraws while the finger moves.
@Observable final class PagerProgress {
    var p: Double
    init(p: Double) { self.p = p }
}

/// The two large titles on one line (34 heavy) and the job line under them
/// (14c, Header). The strip slides 140 per page (Thesis is 120 wide, 20 gap);
/// colors and the job line cross-fade on the same progress, 1:1 with the finger.
private struct PairHeader: View {
    let pager: PagerProgress
    let go: (Int) -> Void

    var body: some View {
        let p = pager.p
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 20) {
                title("Thesis", i: 0, mix: p).frame(width: 120, alignment: .leading)
                title("Planner", i: 1, mix: 1 - p)
            }
            .offset(x: -p * 140)
            .padding(.horizontal, S.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 40, alignment: .leading)
            .clipped()
            .padding(.horizontal, -S.margin)
            ZStack(alignment: .leading) {
                Text("Why these strikes").opacity(1 - p)
                Text("What to sell for next week").opacity(p)
            }
            .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
            .foregroundStyle(S.muted)
            .lineLimit(1)
            .frame(height: 20)
            .accessibilityHidden(true)
        }
        .padding(.top, -4)
    }

    /// `mix`: 0 is the current page (S.ink), 1 the other (S.muted2).
    private func title(_ t: String, i: Int, mix: Double) -> some View {
        Button { go(i) } label: {
            Text(t).sType(.largeTitle, tabular: false)
                .foregroundStyle(S.ink.mix(with: S.pNeutral, by: min(1, max(0, mix))))
                .lineLimit(1)
                .fixedSize()
                .frame(height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mix < 0.5 ? [.isHeader, .isSelected] : [])
        .accessibilityHint(mix < 0.5 ? "" : "Shows the \(t) page")
    }
}

/// Filters wrap onto a second row (block 14b: 8 apart both ways).
struct FlowRows: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0, x + z.width > w { x = 0; y += row + spacing; row = 0 }
            x += z.width + spacing; row = max(row, z.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(w, maxX), height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > b.minX, x + z.width > b.maxX { x = b.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + spacing; row = max(row, z.height)
        }
    }
}

/// The Week view's geometry: five sessions of hourly closes, then the hours
/// to the shorts' Friday; zones by this week's short strikes; tags stacked
/// down the right in clusters that never overlap.
struct WeekGeom {
    static let HD: CGFloat = 340, PRd: CGFloat = 200, PT: CGFloat = 20
    struct Zone { let key: String; let top: CGFloat; let h: CGFloat; let bg: Color; let label: String; let c: Color; let showLabel: Bool }
    struct Line { let leg: PlanPkg.Leg; let y: CGFloat }
    struct Tag { let key: String; let leg: PlanPkg.Leg?; let num: String; let sub: String; let y: CGFloat; var top: CGFloat = 0; var cy: CGFloat = 0 }
    let zones: [Zone], lines: [Line], tags: [Tag], path: Path, conn: Path, lineC: Color
    let dot: CGPoint, earnX: CGFloat?, xl: [(String, CGFloat)]

    init?(_ p: PlanPkg, shown: [PlanPkg.Leg], home: HomePayload, dark: Bool) {
        guard let hours = home.hours, let raw = hours.px[p.t], !raw.isEmpty, p.px > 0 else { return nil }
        let px = p.px, HD = Self.HD, PRd = Self.PRd
        let shortExp = p.held.filter(\.short).map(\.exp).min() ?? p.plannedFor
        let ahead = hours.ahead.filter { $0 <= shortExp }
        let sessions = hours.days + ahead
        var hist = raw
        // The line ends on today's price.
        if let li = hist.lastIndex(where: { $0 != nil }) { hist[li] = px }
        let NH = hist.count, Fut = ahead.count * 7
        let Xd = { (i: Int) -> CGFloat in CGFloat(i) / CGFloat(max(1, NH - 1 + Fut)) * PRd }
        let iv = p.iv ?? 0.4
        let ewd = iv * (5.0 / 252).squareRoot() * (p.e > 0 ? 1.5 : 1)
        let dx = { (k: Double) in abs(k - px) / px * 100 }
        let vals = hist.compactMap { $0 }
        let near = shown.filter { dx($0.k) <= 8 }.map(\.k)
        let lo1 = (vals + [px * (1 - 1.2 * ewd)] + near).min()!, hi1 = (vals + [px * (1 + 1.2 * ewd)] + near).max()!
        let pd = (hi1 - lo1) * 0.06, loD = lo1 - pd, hiD = hi1 + pd
        let Yd = { (v: Double) -> CGFloat in CGFloat((hiD - v) / (hiD - loD)) * HD }
        // Zones from the shorts held now (not suggestions).
        let sC = shown.filter { !$0.sugg && $0.ty == .sc }.map(\.k), sP = shown.filter { !$0.sugg && $0.ty == .sp }.map(\.k)
        let cE = sC.min(), pE = sP.max()
        let yc = cE.map(Yd) ?? 0, yp = pE.map(Yd) ?? HD
        let G = S.green, BL = S.blue, GOLD = S.yellowDeep
        var z: [Zone] = []
        if let cE { z.append(Zone(key: "call", top: 0, h: yc, bg: Color(red: 101 / 255, green: 196 / 255, blue: 102 / 255).opacity(0.16),
                                  label: "Called away above \(PP.k(cE))", c: G, showLabel: yc > 20)) }
        z.append(Zone(key: "keep", top: yc, h: max(0, yp - yc), bg: Color(red: 247 / 255, green: 206 / 255, blue: 70 / 255).opacity(dark ? 0.14 : 0.2),
                      label: "Premium kept", c: GOLD, showLabel: yp - yc > 20))
        if let pE { z.append(Zone(key: "put", top: yp, h: HD - yp,
                                  bg: dark ? Color(red: 58 / 255, green: 134 / 255, blue: 247 / 255).opacity(0.2)
                                           : Color(red: 115 / 255, green: 182 / 255, blue: 249 / 255).opacity(0.18),
                                  label: "Assigned below \(PP.k(pE))", c: BL, showLabel: HD - yp > 20)) }
        zones = z
        lines = shown.filter { dx($0.k) <= 8 }.map { Line(leg: $0, y: Yd($0.k)) }
        // Tags: the price, then every leg; far strikes pin to the top or bottom with an arrow.
        var tg: [Tag] = [Tag(key: "px", leg: nil, num: String(format: "%.2f", px), sub: "", y: Yd(px))]
        for l in shown {
            let far = dx(l.k) > 8, up = l.k > px
            tg.append(Tag(key: l.id, leg: l, num: (far ? (up ? "↑ " : "↓ ") : "") + PP.k(l.k),
                          sub: "×\(l.n) \(PP.pct(dx(l.k)))", y: far ? (up ? 0 : HD) : Yd(l.k)))
        }
        tg.sort { $0.y < $1.y }
        var cl: [[Tag]] = tg.map { [$0] }
        var tops: [CGFloat] = []
        let PT = Self.PT
        func place(_ cc: [Tag]) -> CGFloat {
            let t0: CGFloat
            if let j = cc.firstIndex(where: { $0.key == "px" }) { t0 = cc[j].y - PT / 2 - CGFloat(j) * PT }
            else { t0 = cc.enumerated().reduce(0) { $0 + $1.element.y - CGFloat($1.offset) * PT } / CGFloat(cc.count) - PT / 2 }
            return max(0, min(HD - PT * CGFloat(cc.count), t0))
        }
        tops = cl.map(place)
        var merged = true, it = 0
        while merged && it < 30 {
            merged = false; it += 1
            for i in 0..<max(0, cl.count - 1) where tops[i] + CGFloat(cl[i].count) * PT > tops[i + 1] {
                let cc = cl[i] + cl[i + 1]
                cl.replaceSubrange(i...i + 1, with: [cc]); tops.replaceSubrange(i...i + 1, with: [place(cc)])
                merged = true; break
            }
        }
        var placed: [Tag] = []
        for (ci, cc) in cl.enumerated() {
            for (i, var g) in cc.enumerated() {
                g.cy = tops[ci] + CGFloat(i) * PT + PT / 2
                g.top = tops[ci] + CGFloat(i) * PT + 1
                placed.append(g)
            }
        }
        tags = placed
        var cn = Path()
        for g in placed where g.key != "px" && abs(g.cy - g.y) > 3 && g.y > 0 && g.y < HD {
            cn.move(to: CGPoint(x: PRd, y: g.y)); cn.addLine(to: CGPoint(x: PRd + 6, y: g.cy))
        }
        conn = cn
        var pth = Path(), started = false, lastI = 0
        for (i, v) in hist.enumerated() {
            guard let v else { continue }
            let pt = CGPoint(x: Xd(i), y: Yd(v))
            if started { pth.addLine(to: pt) } else { pth.move(to: pt); started = true }
            lastI = i
        }
        path = pth
        // Green when the price is up on the week's first close, red when down.
        let monday = SunnyPlanner.weekEnd(home.today)
        let wkStart = sessions.firstIndex { $0 >= Self.addDays(monday, -4) } ?? max(0, hours.days.count - 1)
        let ref = hist[min(hist.count - 1, wkStart * 7)...].compactMap { $0 }.first ?? vals.first ?? px
        lineC = px >= ref ? G : S.red
        dot = CGPoint(x: Xd(lastI), y: Yd(px))
        if p.e > 0, let d = p.nextEarnings, let si = sessions.firstIndex(of: d) { earnX = Xd(si * 7 + 6) } else { earnX = nil }
        // Labels: the first session, the Monday, and the shorts' Friday.
        var labs: [(String, CGFloat)] = []
        if let f = sessions.first { labs.append((Self.wd(f), 0)) }
        if let mi = sessions.indices.first(where: { $0 > 0 && Self.wd(sessions[$0]) == "Mon" }) { labs.append(("Mon", Xd(mi * 7))) }
        if sessions.count > 1, let li = sessions.indices.last, !labs.contains(where: { $0.1 == Xd(li * 7) }) {
            labs.append((Self.wd(sessions[li]), Xd(li * 7)))
        }
        xl = labs
    }

    static func wd(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return "" }
        var c = DateComponents(); c.year = p[0]; c.month = p[1]; c.day = p[2]; c.hour = 12
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        guard let d = cal.date(from: c) else { return "" }
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][cal.component(.weekday, from: d) - 1]
    }
    static func addDays(_ iso: String, _ n: Int) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return iso }
        var c = DateComponents(); c.year = p[0]; c.month = p[1]; c.day = p[2]; c.hour = 12
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        guard let d = cal.date(from: c), let x = cal.date(byAdding: .day, value: n, to: d) else { return iso }
        let fc = cal.dateComponents([.year, .month, .day], from: x)
        return String(format: "%04d-%02d-%02d", fc.year!, fc.month!, fc.day!)
    }
}
