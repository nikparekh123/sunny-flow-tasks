//
//  SunnyPositions.swift
//  Sunny
//
//  Blocks 12 and 13 (handoff 22, 13 Oct 2026) · SunnyPositions. Five pages
//  that swipe: All, Sold (Bar), Sold (Chart), Bought (Bar), Bought (Chart); a
//  side with no legs drops both. Glass chips on top follow the page, and
//  Positions is as tall as the page you are on. All is one glass card with
//  the four totals (tap one to open its side). A side opens with its total
//  for the book (tap cycles time value → % → $, shared by every page), then
//  one glass card per ticker, safest first: Bar, a price axis with every
//  strike, or Chart, the hourly price with the strikes as lines. Both styles
//  are built so Nik can use them side by side and pick one.
//

import SwiftUI

struct SunnyPositions: View {
    let home: HomePayload
    @State private var mode: PMode = PMode.preset(DebugPreset.string("pos.mode"), default: .tv)
    @State private var page: Int? = 0
    @State private var heights: [Int: CGFloat] = [:]
    @State private var seen: Set<Int> = []
    @State private var visible = false
    /// The screen's width from the start (then measured), so a page picked
    /// before the first layout lands on its edge on a 430 phone too.
    @State private var fullW: CGFloat =
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.width ?? 393
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let pages = PCache.pages(home)
        let cur = min(max(page ?? 0, 0), max(pages.count - 1, 0))
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Positions").sType(.sectionTitle, tabular: false).foregroundStyle(S.ink)
                    .accessibilityAddTraits(.isHeader)
                if !pages.isEmpty { chips(pages, cur) }
            }
            .padding(.horizontal, S.margin)
            if pages.isEmpty {
                empty.padding(.horizontal, S.margin)
            } else {
                pager(pages, cur)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fullW = $0 }
        // First view of each page animates once (block 12, Motion): a page
        // counts as seen once Positions is on screen with that page picked.
        .onScrollVisibilityChange(threshold: 0.15) { v in visible = v; if v { seen.insert(cur) } }
        .onChange(of: cur) { _, i in if visible { seen.insert(i) } }
        .onChange(of: router.debugPick) { _, v in if let v, let i = Int(v) { page = i } }
        .task {
            // Audit preset: a scroll position set before layout is ignored, so set it after.
            guard let p = DebugPreset.int("pos.page") else { return }
            try? await Task.sleep(for: .milliseconds(300))
            page = p
        }
    }

    private func go(_ i: Int) { withAnimation(S.standard(0.45)) { page = i } }

    // MARK: Chips

    private func chips(_ pages: [PPage], _ cur: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(pages) { pg in
                        PChip(page: pg, on: pg.id == cur) { go(pg.id) }.id(pg.id)
                    }
                }
                .padding(.top, 8).padding(.bottom, 10)
            }
            .contentMargins(.horizontal, S.margin, for: .scrollContent)
            .scrollIndicators(.hidden)
            // The glass chips' shadows must not be cut by the row: clipped,
            // they left a gray band with hard edges behind the chips.
            .scrollClipDisabled()
            .padding(.horizontal, -S.margin)
            .padding(.top, -8).padding(.bottom, -10)
            // Swiping moves the picked chip and keeps it in view.
            .onChange(of: cur) { _, i in withAnimation(S.standard(0.4)) { proxy.scrollTo(i, anchor: .leading) } }
        }
    }

    // MARK: Pages

    private func pager(_ pages: [PPage], _ cur: Int) -> some View {
        let pw = max(0, fullW - 2 * S.margin)
        let h = heights[cur] ?? 0
        let hours = home.hours
        let live = PChartGeom.liveSlot(sessions: hours?.days ?? [], today: home.today, now: SClock.now(), calendar: home.calendar)
        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 20) {
                ForEach(pages) { pg in
                    PPageView(page: pg, width: pw, hours: hours, live: live, today: home.today,
                              open: MarketClock.isRegular(SClock.now(), calendar: home.calendar), mode: $mode,
                              go: seen.contains(pg.id) || reduce)
                        .frame(width: pw, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[pg.id] = $0 }
                        .id(pg.id)
                }
            }
            .scrollTargetLayout()
            // Room for the glass shadows: the pager clips, the shadows must not.
            .padding(.top, 8).padding(.bottom, 24)
        }
        .contentMargins(.horizontal, S.margin, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition(id: $page)
        .scrollIndicators(.hidden)
        // As tall as the page you are on: a short page leaves no gap, and the
        // cards below move up smoothly (0.4 s).
        .frame(height: h > 0 ? h + 32 : nil, alignment: .top)
        .padding(.top, -8).padding(.bottom, -24)
        .animation(reduce ? nil : S.standard(0.4), value: h)
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

// MARK: - Chip

private struct PChip: View {
    let page: PPage
    let on: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 6) {
                Circle().fill(page.status.dot).frame(width: 8, height: 8)
                Text(page.chip).sType(SType(size: 13, weight: 600, line: 13, tracking: 0), tabular: false)
                    .foregroundStyle(on ? S.paper : S.ink)
                Text("\(page.legs.count)").sType(SType(size: 13, weight: 500, line: 13, tracking: 0))
                    .foregroundStyle(on ? S.paper.opacity(0.72) : S.muted)
            }
            .padding(.horizontal, 12).frame(height: 32)
            .background {
                if on {
                    Capsule().fill(S.ink)
                        .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
                        .shadow(color: .black.opacity(0.14), radius: 6, y: 4)
                }
            }
            .glassEffect(on ? .identity : .regular.interactive(), in: .capsule)
            .contentShape(Capsule().inset(by: -6))
            .animation(.easeOut(duration: 0.2), value: on)
        }
        .buttonStyle(PPress(scale: 0.96))
        .accessibilityLabel("\(page.chip), \(PF.count(page.legs.count, "leg"))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - One page

private struct PPageView: View {
    let page: PPage
    let width: CGFloat
    let hours: Hours?
    let live: Double
    let today: String
    let open: Bool                  // regular session: the chart dots pulse
    @Binding var mode: PMode
    let go: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if page.kind == .all {
                PAllCard(legs: page.legs, mode: $mode, go: go)
            } else {
                PSideTop(page: page, mode: $mode, go: go).pEnter(go, 0)
                ForEach(Array(page.cards.enumerated()), id: \.element.id) { j, c in
                    PTickerCard(card: c, viz: page.viz ?? .bar, width: width - 40, go: go,
                                delay: Double(min(j + 1, 6)) * S.stagger,
                                hist: hours?.px[c.t] ?? [], live: live, sessions: hours?.days ?? [],
                                ahead: c.weekExpiry.map { e in (hours?.ahead ?? []).filter { $0 <= e } } ?? [],
                                today: today, open: open)
                }
            }
        }
    }
}

// MARK: - All (one glass card, four totals)

private struct PAllCard: View {
    let legs: [PLeg]
    @Binding var mode: PMode
    let go: Bool

    private var rows: [(t: String, sold: Bool, L: [PLeg])] {
        [("Calls sold", true, true), ("Puts sold", true, false), ("Calls bought", false, true), ("Puts bought", false, false)]
            .map { r in (r.0, r.1, legs.filter { $0.sold == r.1 && $0.call == r.2 }) }
            .filter { !$0.2.isEmpty }
    }

    var body: some View {
        // More room than the design's 24 / 20 / 28 (Nik, 13 Oct 2026: "feels too cramped").
        VStack(alignment: .leading, spacing: 32) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("All positions").sType(.sectionTitle, tabular: false)
                Spacer(minLength: 0)
                Text(PF.count(Set(legs.map(\.t)).count, "ticker") + " · " + PF.count(legs.count, "leg"))
                    .sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
            }
            VStack(alignment: .leading, spacing: 28) {
                ForEach(Array(rows.enumerated()), id: \.element.t) { j, r in
                    let A = PTotals(r.L)
                    // A tap switches time value → % → $ on every page, as before the
                    // redesign (Nik, 13 Oct 2026); the design's jump to that side went.
                    Button { withAnimation(.smooth(duration: S.roll)) { mode = mode.nextPositions } } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(r.t) · \(PWords.word(mode, sold: r.sold, up: A.up))")
                                .sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false)
                                .foregroundStyle(S.muted)
                            PNum(value: PWords.big(A, mode), format: PWords.format(mode), go: go,
                                 delay: 0.12 + Double(j) * S.stagger)
                                .sType(.display)
                                .foregroundStyle(PWords.tone(A, mode))
                                .lineLimit(1)
                            PWords.line(A, mode, sold: r.sold).padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PPress(scale: 0.98))
                    .pEnter(go, Double(min(j, 6)) * S.stagger)
                    .accessibilityLabel("\(r.t), \(PWords.word(mode, sold: r.sold, up: A.up)) \(PWords.format(mode)(PWords.big(A, mode)))")
                    .accessibilityHint("Switches time value, percent and dollars")
                }
            }
        }
        .foregroundStyle(S.ink)
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: S.rCard))
        .sunnyGlow()
    }
}

// MARK: - Page top (a side's total for the book)

private struct PSideTop: View {
    let page: PPage
    @Binding var mode: PMode
    let go: Bool

    var body: some View {
        let A = PTotals(page.legs)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(page.sold ? "Sold" : "Bought").sType(.sectionTitle, tabular: false).foregroundStyle(S.ink)
                Spacer(minLength: 0)
                Text(PF.count(page.tickers, "ticker") + " · " + PF.count(page.legs.count, "leg"))
                    .sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
            }
            Button { withAnimation(.smooth(duration: S.roll)) { mode = mode.nextPositions } } label: {
                VStack(alignment: .leading, spacing: 6) {
                    PNum(value: PWords.big(A, mode), format: PWords.format(mode), go: go, delay: 0.12)
                        .sType(.largeNumber)
                        .foregroundStyle(PWords.tone(A, mode))
                    Text(PWords.word(mode, sold: page.sold, up: A.up))
                        .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                        .foregroundStyle(S.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(POpacityPress())
            .accessibilityLabel("\(page.sold ? "Sold" : "Bought"), \(PWords.word(mode, sold: page.sold, up: A.up)) \(PWords.format(mode)(PWords.big(A, mode)))")
            .accessibilityHint("Switches time value, percent and dollars")
            PWords.line(A, mode, sold: page.sold)
        }
        .padding(.top, 4).padding(.bottom, 8)
    }
}

/// The words and numbers the All rows and page tops share (block 12, Numbers).
enum PWords {
    /// Red says so in words: a bought side down is a loss, not a gain, and a
    /// sold side down is lost, not kept (Nik, 13 Oct 2026).
    static func word(_ m: PMode, sold: Bool, up: Bool) -> String {
        switch m { case .tv: "time value"; case .pct: sold ? "captured" : "return"; case .usd: dollars(sold: sold, up: up) }
    }
    static func dollars(sold: Bool, up: Bool) -> String { sold ? (up ? "kept" : "lost") : (up ? "gain" : "loss") }
    static func big(_ A: PTotals, _ m: PMode) -> Double {
        switch m { case .tv: A.tv; case .pct: abs(A.pct); case .usd: abs(A.g) }
    }
    static func format(_ m: PMode) -> (Double) -> String {
        if m == .pct { return { PF.pct($0) } }
        return { PF.usd($0) }
    }
    /// Time value in ink; % and $ green when up, red when down, never a sign.
    static func tone(_ A: PTotals, _ m: PMode) -> Color { m == .tv ? S.ink : A.up ? S.green : S.red }

    /// $ now first, then the two values the big number is not showing.
    static func line(_ A: PTotals, _ m: PMode, sold: Bool) -> some View {
        let tn = A.up ? S.green : S.red
        var bits: [(String, String, Color)] = [(PF.usd(A.now), " now", S.ink)]
        if m != .pct { bits.append((PF.pct(A.pct), sold ? " captured" : " return", tn)) }
        if m != .tv { bits.append((PF.usd(A.tv), " time value", S.ink)) }
        if m != .usd { bits.append((PF.usd(A.g), " " + dollars(sold: sold, up: A.up), tn)) }
        let bold = SType(size: 14, weight: 700, line: 18, tracking: 0).font(tabular: true)
        return bits.enumerated().reduce(Text("")) { acc, e in
            acc + Text(e.element.0).font(bold).foregroundStyle(e.element.2)
                + Text(e.element.1 + (e.offset < bits.count - 1 ? " · " : "")).foregroundStyle(S.muted)
        }
        .sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Ticker card (block 13)

private struct PTickerCard: View {
    let card: PCard
    let viz: PViz
    let width: CGFloat              // content width: 313 on a 393 phone
    let go: Bool
    let delay: Double
    let hist: [Double?]
    let live: Double
    let sessions: [String]
    let ahead: [String]
    let today: String
    let open: Bool

    var body: some View {
        let c = card
        VStack(alignment: .leading, spacing: 18) {
            head
            if viz == .bar {
                PBarView(c: c, g: PBarGeom(c, width: width), go: go, d: delay)
            } else {
                PChartView(c: c, g: PChartGeom(c, width: width, hist: hist, live: live, sessions: sessions,
                                               ahead: ahead, today: today),
                           width: width, go: go, d: delay, open: open)
            }
            footer
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { PCornerGlow(status: c.status) }
        .glassEffect(.regular, in: .rect(cornerRadius: S.rCard))
        .sunnyGlow()
        .pEnter(go, delay)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }

    private var head: some View {
        let c = card
        return VStack(alignment: .leading, spacing: 12) {
            (Text(c.t).font(SType(size: 20, weight: 700, line: 24, tracking: 0).font())
             + Text(" " + PF.price(c.px)).font(SType(size: 20, weight: 500, line: 24, tracking: 0).font(tabular: true))
                .foregroundStyle(S.muted))
                .sType(SType(size: 20, weight: 700, line: 24, tracking: 0))
                .lineLimit(1)
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
        }
    }

    /// Gold inside 2% on a sold strike, red once a sold strike is crossed,
    /// green past a bought one; otherwise muted.
    static func distColor(_ d: Double, sold: Bool) -> Color {
        d < 0 ? (sold ? S.red : S.green) : sold && d < 2 ? S.yellowDeep : S.muted
    }

    private var footer: some View {
        let A = card.totals, tn = A.up ? S.green : S.red
        let usd: (Double) -> String = { PF.usd($0) }, pct: (Double) -> String = { PF.pct($0) }
        let stats: [(Double, (Double) -> String, String, Color)] = [
            (A.tv, usd, "time value", S.ink),
            (abs(A.pct), pct, card.sold ? "captured" : "return", tn),
            (abs(A.g), usd, PWords.dollars(sold: card.sold, up: A.up), tn),
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
        .padding(.top, 17)
        .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
    }

    private var a11y: String {
        let c = card
        let d = c.heads.map { "\(F.trim((abs($0.dist) * 10).rounded() / 10)) percent \($0.dist >= 0 ? "to" : "past") \($0.word) \(PF.strike($0.k))" }
        let g = Int(abs(c.totals.g).rounded()).formatted()
        let kept = "\(PWords.dollars(sold: c.sold, up: c.totals.up)) \(g) dollars"
        return ([c.t, PF.price(c.px)] + d + [kept]).joined(separator: ", ")
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

// MARK: - Bar

private struct PBarView: View {
    let c: PCard
    let g: PBarGeom
    let go: Bool
    let d: Double
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let on = go || reduce
        let fill = c.totals.up ? S.pFillUp : S.pFillDown
        let n = g.labels.count
        ZStack(alignment: .topLeading) {
            // The track; only the stretch where the premium holds fills in.
            ZStack(alignment: .topLeading) {
                Capsule().fill(S.pTrack)
                ForEach(Array(g.zones.enumerated()), id: \.offset) { _, z in
                    Capsule().fill(fill)
                        .animation(reduce ? nil : S.standard(0.7).delay(d + 0.2)) {
                            $0.scaleEffect(x: on ? 1 : 0.001, anchor: .leading)
                        }
                        .frame(width: max(0, z.1 - z.0), height: 14).offset(x: z.0)
                        .animation(S.standard(0.6), value: z.1 - z.0 + z.0 * 1000)
                }
            }
            .frame(width: g.W, height: 14, alignment: .topLeading)
            .clipShape(Capsule())
            .offset(y: 36)
            // Ticks, then labels: each drops 4 pt and fades in, 30 ms apart.
            ForEach(Array(g.labels.enumerated()), id: \.element.id) { k, l in
                RoundedRectangle(cornerRadius: 1).fill(S.ink)
                    .frame(width: 2, height: 6 + CGFloat(l.row) * 36)
                    .offset(x: l.x - 1, y: 54)
                    .pDrop(on, d + 0.35 + Double(min(k, 8)) * 0.03)
            }
            ForEach(Array(g.labels.enumerated()), id: \.element.id) { k, l in
                VStack(alignment: l.align.h, spacing: 0) {
                    Text(l.num).sType(PBarGeom.numType).foregroundStyle(S.ink)
                    Text(l.sub).sType(PBarGeom.subType).foregroundStyle(subColor(l.strike))
                }
                .frame(width: l.w, alignment: l.align.frame)
                .fixedSize()
                .offset(x: l.left, y: 62 + CGFloat(l.row) * 36)
                .pDrop(on, d + 0.35 + Double(min(n + k, 8)) * 0.03)
            }
            // The price: ink pill, caret, and the ringed thumb on the bar;
            // they slide in from the card's left edge, and glide on the tick.
            Text(g.pillText).sType(PBarGeom.pillType).foregroundStyle(S.paper)
                .frame(width: g.pillW, height: 24)
                .background(Capsule().fill(S.ink))
                .pSlide(on, from: g.pillLeft, d + 0.15)
                .offset(x: g.pillLeft).animation(S.standard(0.6), value: g.pillLeft)
            PCaret().fill(S.ink).frame(width: 10, height: 6)
                .offset(y: 23)
                .pSlide(on, from: g.caretLeft, d + 0.15)
                .offset(x: g.caretLeft).animation(S.standard(0.6), value: g.caretLeft)
            Circle().fill(S.paper)
                .overlay(Circle().strokeBorder(S.ink, lineWidth: 2.5))
                .frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.20), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
                .offset(y: 31)
                .pSlide(on, from: g.xp - 12, d + 0.15)
                .offset(x: g.xp - 12).animation(S.standard(0.6), value: g.xp)
        }
        .frame(width: g.W, height: g.height, alignment: .topLeading)
    }

    private func subColor(_ s: PStrike) -> Color {
        s.sold && s.dist < 0 ? S.red : s.sold && s.dist < 2 ? S.yellowDeep : S.muted
    }
}

private extension PBarGeom.Label.Align {
    var h: HorizontalAlignment { switch self { case .leading: .leading; case .center: .center; case .trailing: .trailing } }
    var frame: Alignment { switch self { case .leading: .leading; case .center: .center; case .trailing: .trailing } }
}

private struct PCaret: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath()
        return p
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

    /// Price: ink pill. Strike: number, then its %; puts in a soft pill.
    @ViewBuilder private func tag(_ t: PChartGeom.Tag) -> some View {
        if t.isPrice {
            Text(t.num).sType(SType(size: 13, weight: 700, line: 13, tracking: 0)).foregroundStyle(S.paper)
                .padding(.horizontal, 7).frame(height: 18)
                .background(Capsule().fill(S.ink))
                .fixedSize()
        } else {
            HStack(spacing: 4) {
                Text(t.num).sType(SType(size: 13, weight: 700, line: 13, tracking: 0)).foregroundStyle(S.ink)
                Text(t.sub).sType(SType(size: 11, weight: 600, line: 11, tracking: 0)).foregroundStyle(S.muted)
            }
            .padding(.horizontal, t.isPut ? 6 : 0).frame(height: 18)
            .background { if t.isPut { Capsule().fill(S.pTrack) } }
            .fixedSize()
        }
    }
}

/// The live ring: grows from the dot to 2.8x and fades in 1.6 s, rests
/// 0.4 s, repeats while the market is open.
private struct PLivePulse: View {
    let color: Color
    var body: some View {
        Circle().fill(color.opacity(0.45))
            .frame(width: 12, height: 12)
            .keyframeAnimator(initialValue: Ring(), repeating: true) { content, v in
                content.scaleEffect(v.scale).opacity(v.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(2.8, duration: 1.6)
                    LinearKeyframe(2.8, duration: 0.4)
                }
                KeyframeTrack(\.opacity) {
                    CubicKeyframe(0, duration: 1.6)
                    LinearKeyframe(0, duration: 0.4)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
    struct Ring { var scale: CGFloat = 1; var opacity: Double = 1 }
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
    /// Thumb, pill and caret slide in from the card's left edge, 0.8 s.
    func pSlide(_ on: Bool, from x: CGFloat, _ delay: Double) -> some View { modifier(PSlide(on: on, x: x, delay: delay)) }
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

private struct PSlide: ViewModifier {
    let on: Bool
    let x: CGFloat
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        // The opacity's own (faster) animation sits inside the slide's.
        content
            .opacity(on ? 1 : 0)
            .animation(reduce ? nil : .linear(duration: 0.2).delay(delay), value: on)
            .offset(x: on ? 0 : -x)
            .animation(reduce ? nil : S.standard(0.8).delay(delay), value: on)
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
