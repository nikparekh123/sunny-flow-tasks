//
//  SunnyPlanner.swift
//  Sunny
//
//  Block 14b · Planner (handoff 23): what to sell by next Friday, one name
//  at a time. A glass chart card on top, up to four strikes under it; every
//  move redraws the chart, the expected premium and the delta. Replaces the
//  Inventory writes page: every Inventory chip and the deck's earnings card
//  open it. The rules live in PlannerMath.swift.
//

import SwiftUI
import Supabase

// MARK: - Live chain

/// chain-next's Planner read for the name on screen: every 15 s in the
/// regular session, every minute outside it, only while the Planner is open.
@MainActor @Observable
final class PlannerFeed {
    private(set) var chains: [String: PlannerChain] = [:]      // "ticker|expiry"
    private struct Req: Encodable { let ticker: String; let expiry: String }

    func run(_ t: String, _ expiry: String, calendar: [CalendarDay]) async {
        while !Task.isCancelled {
            await fetch(t, expiry)
            let step = MarketClock.isRegular(SClock.now(), calendar: calendar) ? 15.0 : 60.0
            try? await Task.sleep(for: .seconds(step))
        }
    }

    private func fetch(_ t: String, _ expiry: String) async {
        #if DEBUG && targetEnvironment(simulator)
        // Audits: a saved chain (`-preset planner.chains=<dir>`, <dir>/<T>.json).
        if let dir = DebugPreset.string("planner.chains") {
            if let d = try? Data(contentsOf: URL(fileURLWithPath: "\(dir)/\(t).json")),
               let c = try? JSONDecoder().decode(PlannerChain.self, from: d) { chains["\(t)|\(expiry)"] = c }
            return
        }
        #endif
        do {
            let c: PlannerChain = try await SupabaseService.client.functions.invoke(
                "chain-next", options: FunctionInvokeOptions(body: Req(ticker: t, expiry: expiry)))
            if c.ok { chains["\(t)|\(expiry)"] = c }
        } catch {
            // Keep the last good chain; the next pass tries again.
        }
    }
}

/// A text field being typed in: a leg's strike or its quantity.
enum PlannerField: Hashable { case k(Int), q(Int) }

// MARK: - Page

struct SunnyPlanner: View {
    let home: HomePayload
    /// The payload the words were written from (insight words change only
    /// on open and pull to refresh, README Rules · Live).
    let words: HomePayload
    /// The name on screen lives on the router, not in a Binding: a new
    /// Binding on every Home redraw redrew the Planner with it.
    @Environment(HomeRouter.self) private var router
    private var ticker: String? { router.writes }
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var feed = PlannerFeed()
    /// While a slider is held the chain stands still, so the stops under the
    /// finger never move.
    @State private var held: PlannerChain?
    @State private var holding = false
    @State private var cardW: CGFloat = 353
    /// The card on screen; swiping moves it and the chips follow (as the old
    /// writes page did, Nik 14 Oct 2026).
    @State private var page: String?
    @State private var heights: [String: CGFloat] = [:]
    @FocusState private var focus: PlannerField?
    @State private var drafts: [PlannerField: String] = [:]

    var body: some View {
        let names = home.writes.names
        let cur = names.first { $0.ticker == ticker } ?? names.first
        ZStack(alignment: .top) {
            PlannerAmbient()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header
                        chips(names, cur)
                        if let cur { content(names, cur) }
                        else {
                            Text("Nothing to plan this week.").sType(.body, tabular: false).foregroundStyle(S.muted)
                        }
                    }
                    .foregroundStyle(S.ink)
                    .padding(.horizontal, S.margin)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width - 2 * S.margin } action: { cardW = $0 }
                    .padding(.top, 14).padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                // The row being typed in rises to the middle of what the
                // keyboard leaves, clear of the keyboard's Done button.
                .onChange(of: focus) { _, f in
                    guard let f else { return }
                    let id: Int = { switch f { case .k(let i), .q(let i): return i } }()
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        withAnimation(S.standard(0.35)) { proxy.scrollTo("row-\(id)", anchor: .center) }
                    }
                }
            }
        }
        // Back from the left edge only, as iOS does.
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.startLocation.x < 30, v.translation.width > 80, abs(v.translation.height) < 60 { close() }
        })
        .task(id: cur.map { "\($0.ticker)|\($0.expiry)" }) {
            guard let cur else { return }
            await feed.run(cur.ticker, cur.expiry, calendar: home.calendar)
        }
        .onChange(of: focus) { old, _ in if let old, let cur { commit(old, cur) } }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }.fontWeight(.semibold)
            }
        }
    }

    private func close() {
        focus = nil
        withAnimation(S.standard(0.45)) { router.writes = nil }
    }

    // MARK: Header and chips

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: close) {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(S.ink)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(Circle().inset(by: -2))
            }
            .buttonStyle(SPressStyle())
            .accessibilityLabel("Back")
            Text("Planner").sType(.largeTitle, tabular: false)
        }
        .frame(height: 40)
    }

    private func chips(_ names: [Writes.Name], _ cur: Writes.Name?) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(names) { n in
                        let on = n.ticker == cur?.ticker
                        Button { focus = nil; router.writes = n.ticker } label: {
                            HStack(spacing: 6) {
                                Text(n.ticker).sType(SType(size: 13, weight: 700, line: 13, tracking: 0), tabular: false)
                                // Calls sold for that Friday, of the LEAPs held.
                                Text("\(n.calls.sold) of \(n.leaps ?? n.calls.of)")
                                    .sType(SType(size: 13, weight: 600, line: 13, tracking: 0))
                                    .foregroundStyle(on ? S.paper.opacity(0.72) : S.ink)
                            }
                            .foregroundStyle(on ? S.paper : S.ink)
                            .padding(.horizontal, 12).frame(height: 32)
                            .background { if on { Capsule().fill(S.ink) } }
                            .glassEffect(on ? .identity : .regular.interactive(), in: .capsule)
                            .contentShape(Capsule().inset(by: -6))
                        }
                        .buttonStyle(SPressStyle())
                        .accessibilityLabel("\(n.ticker), \(n.calls.sold) of \(n.leaps ?? n.calls.of) calls sold")
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .id(n.ticker)
                    }
                }
                .padding(.vertical, 8)
            }
            .contentMargins(.horizontal, S.margin, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .padding(.horizontal, -S.margin).padding(.vertical, -8)
            .onAppear { if let t = cur?.ticker { proxy.scrollTo(t, anchor: .center) } }
            .onChange(of: cur?.ticker) { _, t in
                if let t { withAnimation(S.standard(0.4)) { proxy.scrollTo(t, anchor: .center) } }
            }
        }
    }

    // MARK: Card and strikes

    private func book(_ n: Writes.Name) -> PlannerBook {
        let key = "\(n.ticker)|\(n.expiry)"
        let px = home.portfolio.first { $0.ticker == n.ticker }?.spot ?? n.spot ?? 0
        return PlannerBook(name: n, px: px, chain: holding ? (held ?? feed.chains[key]) : feed.chains[key], today: home.today)
    }

    private func legs(_ b: PlannerBook) -> [PlanLeg] { router.plans["\(b.t)|\(b.expiry)"] ?? b.engine }
    /// Every plan change glides: lines, tags and the week's scale, 0.25 s.
    private func save(_ b: PlannerBook, _ L: [PlanLeg]) {
        withAnimation(reduce ? nil : S.standard(0.25)) { router.plans["\(b.t)|\(b.expiry)"] = L }
    }

    @ViewBuilder private func content(_ names: [Writes.Name], _ n: Writes.Name) -> some View {
        let b = book(n), L = legs(b)
        pager(names, n)
        // The strikes are the name on screen's; they rise in again on every
        // name (block 14b, Motion).
        PlannerAppear(delay: 0.08) { strikes(b, L) }
            .id("strikes-" + b.t)
    }

    /// One chart card per name, side by side; snaps one at a time and is as
    /// tall as the card on screen. The cards slide, so they do not also rise;
    /// each card's week draws in as it appears.
    private func pager(_ names: [Writes.Name], _ cur: Writes.Name) -> some View {
        let h = heights[cur.ticker] ?? 0
        return ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 20) {
                ForEach(names) { n in
                    card(n)
                        .frame(width: cardW, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[n.ticker] = $0 }
                        .id(n.ticker)
                }
            }
            .scrollTargetLayout()
            .padding(.top, 8).padding(.bottom, 24)
        }
        .contentMargins(.horizontal, S.margin, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition(id: $page)
        .scrollIndicators(.hidden)
        // The card's shadow runs past the row; clipped, it ended in a hard
        // band under the card (Nik, 14 Oct 2026).
        .scrollClipDisabled()
        .frame(height: h > 0 ? h + 32 : nil, alignment: .top)
        .padding(.horizontal, -S.margin).padding(.top, -8).padding(.bottom, -24)
        .animation(reduce ? nil : S.standard(0.4), value: h)
        .onChange(of: page) { _, p in
            if let p, p != ticker { focus = nil; router.writes = p }
        }
        .onChange(of: ticker) { _, t in
            if let t, t != page { withAnimation(reduce ? nil : S.standard(0.45)) { page = t } }
        }
        .task {
            // A scroll position set before the first layout is ignored, so set it after.
            try? await Task.sleep(for: .milliseconds(60))
            page = cur.ticker
        }
    }

    private func card(_ n: Writes.Name) -> some View {
        let b = book(n), L = legs(b)
        let hours = home.hours
        let sessions = hours?.days ?? []
        let ahead = (hours?.ahead ?? []).filter { $0 <= b.expiry }
        let hist = hours?.px[b.t] ?? []
        let live = PChartGeom.liveSlot(sessions: sessions, today: home.today, now: SClock.now(), calendar: home.calendar)
        let inner = cardW - 32
        let g = PlannerGeom(b, legs: L, width: inner, hist: hist, live: live, sessions: sessions, ahead: ahead,
                            today: home.today, per: PlannerAxis.per(ahead.count))
        return PlannerCard(b: b, legs: L, g: g, width: inner, insight: insight(n, b),
                           open: MarketClock.isRegular(SClock.now(), calendar: home.calendar))
    }

    /// Back to the engine's pick for this name (Nik, 14 Oct 2026).
    private func reset(_ b: PlannerBook) {
        focus = nil
        drafts.removeAll()
        withAnimation(reduce ? nil : S.standard(0.25)) { router.plans["\(b.t)|\(b.expiry)"] = nil }
    }

    /// "NFLX is up 6.0% over 5 days." then the 1 SD move by the expiry, from
    /// the words payload so it holds still on the tick.
    private func insight(_ n: Writes.Name, _ b: PlannerBook) -> (lead: String, rest: String) {
        let w = words.writes.names.first { $0.ticker == n.ticker } ?? n
        let px = words.portfolio.first { $0.ticker == n.ticker }?.spot ?? w.spot ?? b.px
        let first = (words.hours?.px[n.ticker] ?? []).compactMap { $0 }.first ?? px
        let ch = first > 0 ? (px / first - 1) * 100 : 0
        let lead = "\(n.ticker) is \(ch >= 0 ? "up" : "down") \(PF.dist(ch)) over 5 days."
        let sd = String(format: "$%.2f", w.sd ?? b.sd)
        let by = F.day(b.expiry)
        let rest = b.earnIn ? "Earnings \(F.day(b.earnDate ?? "")) before expiry, so 1 SD by \(by) is about \(sd)."
                            : "1 SD by \(by) is about \(sd)."
        return (lead, rest)
    }

    private func strikes(_ b: PlannerBook, _ L: [PlanLeg]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Strikes").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false)
                        .foregroundStyle(S.muted)
                    Text(L.isEmpty ? "" : "\(L.count) of 4").sType(SType(size: 13, weight: 500, line: 16, tracking: 0))
                        .foregroundStyle(S.pNeutral)
                }
                Spacer(minLength: 0)
                if router.plans["\(b.t)|\(b.expiry)"] != nil {
                    Button { reset(b) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.counterclockwise").font(.system(size: 11, weight: .bold))
                            Text("Reset").sType(SType(size: 13, weight: 600, line: 13, tracking: 0), tabular: false)
                        }
                        .foregroundStyle(S.ink)
                        .padding(.leading, 12).padding(.trailing, 14).frame(height: 32)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .contentShape(Capsule().inset(by: -6))
                    }
                    .buttonStyle(SPressStyle())
                    .accessibilityLabel("Reset to the suggested plan")
                    .transition(.opacity)
                }
                if !b.fullySold && b.canAdd(L) {
                    Button { if let N = b.add(L) { save(b, N) } } label: {
                        HStack(spacing: 6) {
                            PlannerPlus().frame(width: 10, height: 10)
                            Text("Add").sType(SType(size: 13, weight: 600, line: 13, tracking: 0), tabular: false)
                        }
                        .foregroundStyle(S.ink)
                        .padding(.leading, 12).padding(.trailing, 14).frame(height: 32)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .contentShape(Capsule().inset(by: -6))
                    }
                    .buttonStyle(SPressStyle())
                    .disabled(!b.live)
                    .transition(.opacity)
                }
            }
            .frame(height: 44)
            .overlay(alignment: .bottom) { Rectangle().fill(S.pRule).frame(height: 1) }
            ForEach(Array(L.enumerated()), id: \.element.id) { i, l in
                PlannerRow(b: b, legs: L, l: l, focus: $focus, drafts: $drafts,
                           save: { N in save(b, N) },
                           hold: { on in
                               if on { held = feed.chains["\(b.t)|\(b.expiry)"] }
                               holding = on
                           })
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(S.pRule).frame(height: 1) } }
                    .id("row-\(l.id)")
                    .transition(.opacity)
            }
            if L.isEmpty {
                Text(b.fullySold ? "\(b.t) is fully sold through \(F.day(b.expiry)). Nothing left to plan."
                                 : "No strikes planned. Add one to see what it brings in.")
                    .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                    .foregroundStyle(S.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 16)
            }
        }
        .padding(.horizontal, 4).padding(.top, 4)
    }

    /// A typed value lands on blur or Done: snapped and clamped.
    private func commit(_ f: PlannerField, _ n: Writes.Name) {
        guard let s = drafts[f] else { return }
        drafts[f] = nil
        let b = book(n), L = legs(b)
        let v = Double(s.filter { "0123456789.".contains($0) }) ?? .nan
        switch f {
        case .k(let id): save(b, b.typeStrike(L, id, v))
        case .q(let id): save(b, b.typeQty(L, id, v))
        }
    }
}

/// How wide a session to come is on the chart, in hourly slots (7 = a past
/// session's width). The days to next Friday share the design's three
/// sessions of width, so the past week keeps about 60% of the plot (Nik,
/// 14 Oct 2026: the squeezed axis; the design ran only to this Friday).
enum PlannerAxis {
    static func per(_ ahead: Int) -> Double {
        #if DEBUG && targetEnvironment(simulator)
        if DebugPreset.string("planner.axis") == "real" { return 7 }
        #endif
        return ahead > 0 ? min(7, 21 / Double(ahead)) : 7
    }
}

// MARK: - The chart card

private struct PlannerCard: View {
    let b: PlannerBook
    let legs: [PlanLeg]
    let g: PlannerGeom
    let width: CGFloat
    let insight: (lead: String, rest: String)
    let open: Bool                  // regular session: the price dot pulses
    @State private var go = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    // Shown from a task, after the hidden first frame is drawn, so the change
    // gets its own animated update.

    var body: some View {
        let exp = b.expected(legs), after = b.after(legs)
        VStack(alignment: .leading, spacing: 12) {
            head
            PlannerChart(g: g, width: width, go: go, open: open)
            HStack(alignment: .top, spacing: 32) {
                stat("expected") { Text(PlannerWords.usd(exp)).contentTransition(.numericText(value: exp)) }
                stat("delta") {
                    (Text(PlannerWords.delta(b.deltaNow)).foregroundStyle(S.lossInk(b.deltaNow))
                     + Text(" → ").foregroundStyle(S.pNeutral)
                     + Text(PlannerWords.delta(after)).foregroundStyle(S.lossInk(after)))
                        .contentTransition(.numericText(value: after))
                }
            }
            .animation(.smooth(duration: S.roll), value: exp)
            .animation(.smooth(duration: S.roll), value: after)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(S.yellow).frame(width: 6, height: 6)
                    .shadow(color: S.yellow.opacity(0.75), radius: 4)
                    .padding(.top, 6)
                (Text(insight.lead).font(SType(size: 13, weight: 600, line: 18, tracking: 0).font(tabular: true))
                    .foregroundStyle(S.ink)
                 + Text(" " + insight.rest))
                    .sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                    .foregroundStyle(S.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
        }
        .foregroundStyle(S.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { PlannerGlow(green: !legs.isEmpty) }
        .glassEffect(.regular, in: .rect(cornerRadius: S.rCard))
        .shadow(color: .black.opacity(0.04), radius: 1.5, y: 1)
        .shadow(color: .black.opacity(0.10), radius: 12, y: 10)
        .task { go = true }
        .accessibilityElement(children: .combine)
    }

    private var head: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            (Text(b.t).font(SType(size: 20, weight: 700, line: 24, tracking: 0).font())
             + Text(" " + PF.price(b.px)).font(SType(size: 20, weight: 500, line: 24, tracking: 0).font(tabular: true))
                .foregroundStyle(S.muted))
                .sType(SType(size: 20, weight: 700, line: 24, tracking: 0))
                .lineLimit(1)
            Spacer(minLength: 0)
            Group {
                // The Friday by date: "By Fri" means this Friday elsewhere
                // (Nik, 14 Oct 2026).
                if let d = b.earnDate {
                    Text("By \(F.day(b.expiry)) · ").foregroundStyle(S.muted)
                    + Text("Earnings \(F.day(d))").foregroundStyle(b.earnIn ? S.yellowDeep : S.muted)
                        .fontWeight(b.earnIn ? .bold : .medium)
                } else {
                    Text("By \(F.day(b.expiry))").foregroundStyle(S.muted)
                }
            }
            .sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false)
            .lineLimit(1)
        }
        .frame(height: 24)
    }

    private func stat<V: View>(_ label: String, @ViewBuilder _ value: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            value().sType(SType(size: 17, weight: 700, line: 20, tracking: 0)).lineLimit(1)
            Text(label).sType(SType(size: 12, weight: 500, line: 14, tracking: 0), tabular: false).foregroundStyle(S.muted)
        }
    }
}

private struct PlannerChart: View {
    let g: PlannerGeom
    let width: CGFloat
    let go: Bool
    let open: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let H = PlannerGeom.H, lineC = g.up ? S.green : S.red
        let glide: Animation? = reduce ? nil : S.standard(0.25)
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                // The report: dotted gold at that day's close.
                if let x = g.earnX {
                    PlannerVLine()
                        .stroke(S.yellowDeep, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0, 3]))
                        .frame(width: 1.5, height: H)
                        .offset(x: x - 0.75)
                }
                // One thin line at the money, labelled in the empty stretch.
                Rectangle().fill(scheme == .dark ? Color.white.opacity(0.14) : S.ink.opacity(0.12))
                    .frame(width: g.plot, height: 1)
                    .offset(y: g.atmY - 0.5)
                    .animation(glide, value: g.atmY)
                Text("ATM").sType(SType(size: 10, weight: 600, line: 12, tracking: 0), tabular: false)
                    .foregroundStyle(S.pNeutral)
                    .frame(width: g.plot, alignment: .trailing)
                    .offset(y: g.atmY - 13)
                    .animation(glide, value: g.atmY)
                // Strikes: sold in gray, planned in the side's colour.
                ForEach(g.lines) { l in
                    PlannerHLine()
                        .stroke(l.kind == .sold ? (scheme == .dark ? Color.white.opacity(0.3) : S.ink.opacity(0.26))
                                                 : (l.call ? S.green : S.blue),
                                style: StrokeStyle(lineWidth: 1.5, dash: [4.5, 3]))
                        .frame(width: g.plot, height: 1.5)
                        .offset(y: l.y - 0.75)
                        .animation(glide, value: l.y)
                }
                // The week: draws left to right; a plan change rescales it
                // inside save()'s glide. (A value-keyed animation on lo / hi
                // here looped the render and blanked the screen, 14 Oct 2026.)
                PlannerLineShape(series: g.series, lo: g.lo, hi: g.hi)
                    .trim(from: 0, to: go || reduce ? 1 : 0)
                    .stroke(lineC, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .animation(reduce ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.9).delay(0.1), value: go)
                    .frame(width: g.plot, height: H)
                    .clipped()
                PlannerConnectors(plot: g.plot, items: g.connectors)
                    .stroke(S.muted, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    .frame(width: width, height: H)
                Circle().fill(S.paper)
                    .overlay(Circle().strokeBorder(lineC, lineWidth: 2.5))
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.20), radius: 1, y: 1)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
                    // Market open: the ring Positions' dots use (Nik, 14 Oct 2026).
                    .background { if open && go && !reduce { PLivePulse(color: lineC) } }
                    .opacity(go || reduce ? 1 : 0)
                    .animation(reduce ? nil : .easeOut(duration: 0.3).delay(0.85), value: go)
                    .offset(x: g.dot.x - 6, y: g.dot.y - 6)
                    .animation(glide, value: g.dot.y)
                ForEach(g.tags) { t in
                    tag(t)
                        .offset(x: g.plot + 8, y: t.top)
                        .animation(glide, value: t.top)
                }
            }
            .frame(width: width, height: H, alignment: .topLeading)
            ZStack(alignment: .topLeading) {
                ForEach(g.days) { x in
                    Text(x.text)
                        .sType(SType(size: 11, weight: x.earn ? 700 : 500, line: 14, tracking: 0), tabular: false)
                        .foregroundStyle(x.earn ? S.yellowDeep : x.today ? S.ink : S.muted)
                        .fixedSize()
                        .offset(x: x.x)
                }
            }
            .frame(width: g.plot, height: 14, alignment: .topLeading)
        }
        .accessibilityHidden(true)
    }

    /// Price: ink pill. Sold: number, ×size %, puts in a soft pill. Planned:
    /// filled green (call) or blue (put), paper text.
    @ViewBuilder private func tag(_ t: PlannerGeom.Tag) -> some View {
        switch t.kind {
        case .price:
            Text(t.num).sType(SType(size: 13, weight: 700, line: 13, tracking: 0)).foregroundStyle(S.paper)
                .padding(.horizontal, 7).frame(height: 18)
                .background(Capsule().fill(S.ink))
                .fixedSize()
        case .sold:
            HStack(spacing: 4) {
                Text(t.num).sType(SType(size: 13, weight: 700, line: 13, tracking: 0)).foregroundStyle(S.ink)
                Text(t.sub).sType(SType(size: 11, weight: 600, line: 11, tracking: 0)).foregroundStyle(S.muted)
            }
            .padding(.horizontal, t.call ? 0 : 6).frame(height: 18)
            .background { if !t.call { Capsule().fill(S.pTrack) } }
            .fixedSize()
        case .plan:
            HStack(spacing: 4) {
                Text(t.num).sType(SType(size: 13, weight: 700, line: 13, tracking: 0))
                Text(t.sub).sType(SType(size: 11, weight: 600, line: 11, tracking: 0))
            }
            .foregroundStyle(S.paper)
            .padding(.horizontal, 7).frame(height: 18)
            .background(Capsule().fill(t.call ? S.green : S.blue))
            .fixedSize()
        }
    }
}

// MARK: - A strike row

private struct PlannerRow: View {
    let b: PlannerBook
    let legs: [PlanLeg]
    let l: PlanLeg
    var focus: FocusState<PlannerField?>.Binding
    @Binding var drafts: [PlannerField: String]
    let save: ([PlanLeg]) -> Void
    let hold: (Bool) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var trackW: CGFloat = 0

    var body: some View {
        let c = l.call ? S.green : S.blue
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(c).frame(width: 6, height: 6)
                field(.k(l.id), PF.strike(l.k), keyboard: .decimalPad, label: "Strike")
                    .sType(SType(size: 15, weight: 600, line: 30, tracking: 0))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                    .frame(width: 56, height: 30)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fieldFill))
                Text(b.meta(l.k)).sType(SType(size: 12, weight: 500, line: 16, tracking: 0))
                    .foregroundStyle(S.muted).lineLimit(1).fixedSize()
                Spacer(minLength: 0)
                Text(PlannerWords.usd(b.premium(l)))
                    .sType(SType(size: 13, weight: 600, line: 16, tracking: 0))
                    .contentTransition(.numericText(value: b.premium(l)))
                    .animation(.smooth(duration: S.roll), value: b.premium(l))
                    .lineLimit(1).fixedSize()
                Button { save(legs.filter { $0.id != l.id }) } label: {
                    PlannerCross().frame(width: 28, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(POpacity())
                .padding(.trailing, -6)
                .accessibilityLabel("Remove \(PF.strike(l.k)) \(l.call ? "call" : "put")")
            }
            .frame(height: 30)
            HStack(spacing: 12) {
                PlannerSegment(call: l.call, canCall: l.call || b.free(.c, legs) > 0, canPut: !l.call || b.free(.p, legs) > 0) { side in
                    if let N = b.toSide(legs, l.id, side) { save(N) }
                }
                slider
                HStack(spacing: 0) {
                    Text("×").sType(SType(size: 13, weight: 500, line: 28, tracking: 0), tabular: false)
                        .foregroundStyle(S.pNeutral)
                    field(.q(l.id), String(l.q), keyboard: .numberPad, label: "Quantity")
                        .sType(SType(size: 14, weight: 600, line: 28, tracking: 0))
                        .padding(.leading, 2).padding(.trailing, 6)
                        .frame(width: 38, height: 28)
                }
                .padding(.leading, 8)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fieldFill))
            }
            .frame(height: 28)
        }
        .padding(.vertical, 12)
    }

    private var fieldFill: Color {
        scheme == .dark ? Color(red: 118 / 255, green: 118 / 255, blue: 128 / 255).opacity(0.24)
                        : Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255).opacity(0.12)
    }

    /// A draft while the box has focus; it lands on blur or Done.
    private func field(_ f: PlannerField, _ shown: String, keyboard: UIKeyboardType, label: String) -> some View {
        TextField(label, text: Binding(get: { drafts[f] ?? shown }, set: { drafts[f] = $0 }))
            .keyboardType(keyboard)
            .focused(focus, equals: f)
            .foregroundStyle(S.ink)
            .disabled(!b.live)
            .onChange(of: focus.wrappedValue == f) { _, on in
                // Select what is there, so typing replaces it.
                if on { DispatchQueue.main.async { UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil) } }
            }
            .accessibilityLabel(label)
    }

    /// iOS 26's own slider: eight stops from the money to 1.4 SD, a tick at
    /// each, filled in ink from the money (puts run right to left).
    private var slider: some View {
        let f = b.kf(l.side, l.k) * 7
        return Slider(value: Binding(get: { l.call ? f : 7 - f },
                                     set: { v in
                                         let j = Int(v.rounded())
                                         if let N = b.slide(legs, l.id, l.call ? j : 7 - j) { save(N) }
                                     }),
                      in: 0...7, step: 1, neutralValue: l.call ? 0 : 7,
                      label: { Text("Strike") },
                      tick: { SliderTick($0) },
                      onEditingChanged: { hold($0) })
            .tint(S.ink)
            .disabled(!b.live)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { trackW = $0 }
            // A tap anywhere on the track jumps to the nearest stop (block 14b:
            // "tap or drag anywhere"); iOS 26's slider only drags. The thumb's
            // centre runs from 19 pt in from each end.
            .simultaneousGesture(SpatialTapGesture().onEnded { v in
                guard b.live, trackW > 38 else { return }
                let j = Int((max(0, min(1, (v.location.x - 19) / (trackW - 38))) * 7).rounded())
                if let N = b.slide(legs, l.id, l.call ? j : 7 - j) { save(N) }
            })
            .accessibilityValue("\(PF.strike(l.k)), \(b.meta(l.k))")
    }
}

/// Call / Put on a glass capsule; a side with nothing free is dimmed and
/// does nothing.
private struct PlannerSegment: View {
    let call: Bool
    let canCall: Bool
    let canPut: Bool
    let pick: (PlanLeg.Side) -> Void
    @Namespace private var ns
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            button("Call", on: call, enabled: canCall, fill: S.green) { pick(.c) }
            button("Put", on: !call, enabled: canPut, fill: S.blue) { pick(.p) }
        }
        .padding(2)
        .glassEffect(.regular, in: .capsule)
        .animation(S.standard(0.3), value: call)
    }

    /// Readable at a glance (Nik, 14 Oct 2026: "hardly readable"): the side
    /// it is on is filled in its own colour, green call, blue put, as its dot
    /// and chart tag; the other side's word is ink.
    private func button(_ t: String, on: Bool, enabled: Bool, fill: Color, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(t).sType(SType(size: 13, weight: 600, line: 13, tracking: 0), tabular: false)
                .foregroundStyle(on ? S.paper : S.ink)
                .frame(width: 42, height: 24)
                .background {
                    if on {
                        Capsule().fill(fill)
                            .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.15), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "seg", in: ns)
                    }
                }
                // Taller to touch, never wider: the two halves must not
                // overlap, or a tap on one lands on the other.
                .padding(.vertical, 10).contentShape(Rectangle()).padding(.vertical, -10)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        // The side it is on does nothing (toSide ignores it); a side with
        // nothing free takes no taps. Not .disabled: that greys the label.
        .allowsHitTesting(enabled)
        .accessibilityLabel(t)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct POpacity: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.5 : 1)
    }
}

// MARK: - Small shapes

private struct PlannerCross: View {
    var body: some View {
        ZStack {
            Capsule().fill(S.pNeutral).frame(width: 12, height: 1.5).rotationEffect(.degrees(45))
            Capsule().fill(S.pNeutral).frame(width: 12, height: 1.5).rotationEffect(.degrees(-45))
        }
    }
}

private struct PlannerPlus: View {
    var body: some View {
        ZStack {
            Capsule().fill(S.ink).frame(width: 10, height: 1.5)
            Capsule().fill(S.ink).frame(width: 1.5, height: 10)
        }
    }
}

/// The week's line: x in points, y mapped from price with lo / hi here, so
/// a change of scale animates.
private struct PlannerLineShape: Shape {
    let series: [CGPoint]
    var lo: Double
    var hi: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(lo, hi) }
        set { lo = newValue.first; hi = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let H = rect.height, span = max(hi - lo, 0.0001)
        let pts = series.map { CGPoint(x: $0.x, y: H - CGFloat((Double($0.y) - lo) / span) * H) }
        guard let f = pts.first else { return p }
        p.move(to: f)
        for q in pts.dropFirst() { p.addLine(to: q) }
        return p
    }
}

private struct PlannerHLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p
    }
}

private struct PlannerVLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); return p
    }
}

/// A 1 pt connector from the plot's edge to a tag moved off its line.
private struct PlannerConnectors: Shape {
    let plot: CGFloat
    let items: [(y: CGFloat, cy: CGFloat)]
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in items { p.move(to: CGPoint(x: plot, y: i.y)); p.addLine(to: CGPoint(x: plot + 6, y: i.cy)) }
        return p
    }
}

/// The corner glow: green while there is something planned, gray when not;
/// radial 130% × 90% from the top left, 28% (dark 22%) fading out by 60%.
private struct PlannerGlow: View {
    let green: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = green ? S.pGlowSafe : S.pGlowNear
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
        .animation(.easeInOut(duration: 0.3), value: green)
    }
}

/// The page behind the glass: S.screen with three soft washes, green left,
/// blue right, yellow low (light 26 / 18 / 24%, dark 16 / 14 / 12%).
private struct PlannerAmbient: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                S.screen
                wash(Color(red: 101 / 255, green: 196 / 255, blue: 102 / 255).opacity(dark ? 0.16 : 0.26),
                     at: CGPoint(x: 0, y: 0.34 * h), rx: 0.7 * w, ry: 0.34 * h)
                wash((dark ? Color(red: 58 / 255, green: 134 / 255, blue: 247 / 255)
                           : Color(red: 115 / 255, green: 182 / 255, blue: 249 / 255)).opacity(dark ? 0.14 : 0.18),
                     at: CGPoint(x: w, y: 0.22 * h), rx: 0.6 * w, ry: 0.30 * h)
                wash(Color(red: 247 / 255, green: 206 / 255, blue: 70 / 255).opacity(dark ? 0.12 : 0.24),
                     at: CGPoint(x: 0.9 * w, y: 0.92 * h), rx: 0.8 * w, ry: 0.36 * h)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func wash(_ c: Color, at p: CGPoint, rx: CGFloat, ry: CGFloat) -> some View {
        Rectangle()
            .fill(RadialGradient(colors: [c, c.opacity(0)], center: .center, startRadius: 0, endRadius: rx * 0.7))
            .frame(width: 2 * rx, height: 2 * rx)
            .scaleEffect(x: 1, y: ry / rx)
            .position(p)
    }
}

// MARK: - Entrance

/// Rises in once when it appears (the strikes, 80 ms after the card).
private struct PlannerAppear<Content: View>: View {
    let delay: Double
    @ViewBuilder var content: Content
    @State private var go = false
    var body: some View {
        content.modifier(PlannerEnter(go: go, delay: delay)).task { go = true }
    }
}

/// Rises 14 pt and fades in: opacity 0.5 s ease out, move 0.6 s, after
/// `delay`. Reduce Motion: there at once.

private struct PlannerEnter: ViewModifier {
    let go: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            // The fade is scoped to opacity alone; stacked value-keyed, its
            // ease-out also drove the rise (measured, 14 Oct 2026). The rise
            // stays value-keyed: a scoped animation jumps offsets.
            .animation(reduce ? nil : .easeOut(duration: 0.5).delay(delay)) { $0.opacity(go || reduce ? 1 : 0) }
            .offset(y: go || reduce ? 0 : 14)
            .animation(reduce ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.6).delay(delay), value: go)
    }
}
