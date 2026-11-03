//
//  SunnyPositions.swift
//  Sunny
//
//  Blocks 12 and 13 (handoff 30, 22 Oct 2026) · the Position cards on the
//  Positions tab: one glass card per name. The body swipes To do · Sold ·
//  Bought · Δ Γ; one control above the cards turns every card together, and
//  a swipe on any card turns them all too (Nik, 2 Nov 2026: it was one
//  control per card; it scrolls with the page, not pinned). To do comes
//  first while the name has work and goes once IBKR shows the trades
//  (nothing is ticked); it lists only what is still to place. The card is as tall as the face it is on and
//  blends between two faces mid-swipe (handoff 31). With ways (13c) the To do
//  face is SunnyWays and the count badge is its number of trades. With the
//  week's plan (handoff 32, 13e) the To do face is this week's orders
//  (SunnyOrders) and the badge counts the orders to place; the insights and
//  walls buttons are gone (Insights and Gamma are tabs). A card with nothing
//  on the face showing says so in one line ("Nothing bought").
//  Block 13i (3 Nov 2026): two faces, Position · Risk, in a segmented control inside
//  each card, linked so a turn on one card turns every card (the card touched stays
//  still on screen); To do and Δ Γ are gone from the cards (their logic stays on the
//  server: Risk reads the hedge rule's walls). Position holds Sold and Bought behind
//  All · Sold · Bought chips, shared by every card. A name with nothing bought has
//  Position only and no control. An orange dot before the ticker and on Risk while
//  the book goes short within the hedge rule's target.
//

import SwiftUI

/// One name on the Positions tab: its cards' sides, Delta and Gamma, strategy, To do and the day's move.
struct PName: Identifiable {
    var id: String { t }
    let t: String
    let px: Double
    /// The stock's move today, % (block 12: Stock up and Stock down).
    let move: Double?
    let sold: PCard?
    let bought: PCard?
    let dg: DGBook?
    let strategy: String?
    /// To do rows: this week's rolls and sales, then the calls to buy.
    let tasks: [WeekTask]
    let bars: TodoBars?
    /// The To do face as Sell and Buy with their ways (handoff 31, 13c); replaces the bars and rows.
    let ways: NameWays?
    /// The most any call sold has kept of its premium, % (Calls that kept at least).
    let kept: Double
    /// The week's plan (handoff 32): the To do face becomes its orders.
    var plan: NamePlan? = nil
    var legs: [Leg] = []
    var earnings: String? = nil
    var daily: DailyCloses? = nil

    /// The orders still to place with a plan, else the trades left with ways on, else the To do rows. Worked out
    /// once when the names are built (it was rebuilt on every redraw: a hang on the phone, 26 Oct 2026).
    var todo = 0
    var todoN: Int { todo }
    func countTodo() -> Int {
        if let p = plan { return POrders.count(POrders.build(t, p, legs: legs, dg: dg, earnings: earnings, placed: POrders.placed(t, p.week), done: POrders.done(t, p.week))) }
        return ways?.trades ?? tasks.count
    }
    var hasTodo: Bool { todoN > 0 }
    /// The Risk face (13i): the hedge rule's line and walls, for a name with something bought.
    var risk: NamePlan.Risk? { bought != nil ? plan?.risk : nil }
    /// Something left to cover within the hedge rule's target: the orange dots, the card first.
    var cover: Bool { (risk?.need ?? 0) > 0 }
    var faces: [PFace] { risk != nil ? [.position, .risk] : [.position] }

    /// Whether the card has something on a face; without it the face is one line.
    func has(_ f: PFace) -> Bool {
        switch f {
        case .position: sold != nil || bought != nil
        case .risk: risk != nil
        }
    }
    /// The Δ Γ dot, only while a buy is open: red when it goes short inside a normal week's move,
    /// orange when it runs thin inside it (block 13, Attention).
    var dgDot: Color? {
        guard tasks.contains(where: { $0.face == "dg" }), let d = dg, let sd = d.sd else { return nil }
        if let sh = d.sh, sh <= sd { return S.red }
        if let th = d.thin, th <= sd { return S.orange }
        return nil
    }
    /// What this name adds to a face's tab: an orange dot on Risk while something is left to cover (13i).
    func mark(_ f: PFace) -> PMark { f == .risk && cover ? .dot(S.orange) : .none }

    func matches(_ f: PFilter) -> Bool {
        switch f {
        case .all: true
        case .todo: hasTodo
        case .up: (move ?? 0) > 0
        case .down: (move ?? 0) < 0
        case .kept(let p): kept >= Double(p)
        }
    }
}

enum PNames {
    /// Every name with a card (TSLA sits on the Home map only): names with To do first, then the
    /// order the cards already keep, safest first.
    /// Built once per update and reused by every screen that asks (Positions, Gamma, Insights, the strip): it was
    /// rebuilt in each body on every redraw.
    private static var memoKey = "", memo: [PName] = []
    @MainActor static func build(_ home: HomePayload, orderFrom: HomePayload?) -> [PName] {
        let key = "\(home.builtAt)|\(orderFrom?.builtAt ?? "")|\(UserDefaults.standard.string(forKey: POrders.doneKey) ?? "")|\(UserDefaults.standard.string(forKey: POrders.placedKey) ?? "")"
        if key == memoKey { return memo }
        let out = make(home, orderFrom: orderFrom)
        memoKey = key; memo = out
        return out
    }
    @MainActor private static func make(_ home: HomePayload, orderFrom: HomePayload?) -> [PName] {
        let pages = PCache.pages(home, orderFrom: orderFrom)
        let sold = pages.first { $0.kind == .sold }, bought = pages.first { $0.kind == .bought }
        let names = ((sold?.cards.map(\.t) ?? []) + (bought?.cards.map(\.t) ?? [])).reduce(into: [String]()) { a, t in
            if !a.contains(t) && t != "TSLA" { a.append(t) }
        }
        let rows = home.thisWeek?.value ?? [], bars = home.todo?.value ?? [:], ways = home.ways?.value ?? [:], plans = home.plan?.value ?? [:]
        let moves = Dictionary(home.portfolio.map { ($0.ticker, $0.ranges.d) }, uniquingKeysWith: { a, _ in a })
        let all: [PName] = names.map { t -> PName in
            let sc = sold?.cards.first { $0.t == t }, bc = bought?.cards.first { $0.t == t }
            let calls = (sc?.legs ?? []).filter { $0.call && $0.base > 0 }
            return PName(t: t, px: (sc ?? bc)?.px ?? 0, move: moves[t] ?? nil, sold: sc, bought: bc,
                         dg: home.writes.names.first { $0.ticker == t }?.dg?.value, strategy: home.strategies?[t],
                         tasks: rows.filter { $0.t == t }.sorted { !$0.buy && $1.buy }, bars: bars[t], ways: ways[t],
                         kept: calls.map { $0.g / $0.base * 100 }.max() ?? 0, plan: plans[t], legs: home.legs.filter { $0.ticker == t },
                         earnings: home.writes.names.first { $0.ticker == t }?.nextEarnings?.date, daily: home.daily?.value?[t])
        }.map { n in var n = n; n.todo = n.countTodo(); return n }
        return all.filter(\.hasTodo) + all.filter { !$0.hasTodo }
    }

    /// `names` in a frozen order (the Positions tab's); names it does not know keep their own order, last.
    static func keep(_ names: [PName], _ order: [String]) -> [PName] {
        guard !order.isEmpty else { return names }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return names.enumerated().sorted { a, b in
            switch (rank[a.element.t], rank[b.element.t]) {
            case let (x?, y?): x < y
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): a.offset < b.offset
            }
        }.map(\.element)
    }
}

/// The cards, in order, each entering once (block 12, Motion). Each card carries its own Position · Risk control;
/// the faces and chips are one choice for every card (block 13i).
struct SunnyPositionCards: View {
    let home: HomePayload
    let names: [PName]
    /// Scrolls the page by this many points (the Positions tab's scroll): after a turn, the card you touched glides
    /// back to where it was, so the cards above changing height don't move it.
    var glide: ((CGFloat) -> Void)? = nil
    @State private var seen = false
    /// The face and chip every card is on.
    @State private var sw = PFaceSwitch()
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// Debug's Captured filter opens every card on Sold (block 12, Filters).
    private var keptOn: Bool { if case .kept = router.filter { true } else { false } }

    var body: some View {
        let fullW = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.width ?? 393
        let width = fullW - 2 * S.margin - 40
        let hours = home.hours
        let live = PChartGeom.liveSlot(sessions: hours?.days ?? [], today: home.today, now: SClock.now(), calendar: home.calendar)
        let open = MarketClock.isRegular(SClock.now(), calendar: home.calendar)
        // Lazy: only the cards on screen are built and redrawn on each 15 s update (Nik's phone showed a 550 ms hang
        // when all seven cards, four faces each, redrew every update; 26 Oct 2026).
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(Array(names.enumerated()), id: \.element.id) { j, n in
                PNameCard(n: n, faces: n.faces, sw: sw, ringed: router.ring == n.t, width: width,
                          go: seen || reduce, delay: Double(min(j, 6)) * S.stagger,
                          hours: hours, live: live, today: home.today, open: open, cal: home.calendar)
                    // Where each card on screen sits, for the glide after a turn (not observed: no redraws).
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: { sw.frames[n.t] = $0 }
                    // Scrolled to from a tap: the id sits on the row itself, outermost, so the lazy list can find a
                    // card it has not built yet (block 12a).
                    .id("pos-\(n.t)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // First view animates once (block 12, Motion): any sliver on screen counts.
        .onScrollVisibilityChange(threshold: 0.001) { v in if v { seen = true } }
        // Opened from a tap (the map, a chip, Insights): every card turns to that face (the old faces' names land on
        // Position or Risk), and once the page has scrolled there nothing else moves.
        .onChange(of: router.cardTick) { _, _ in
            guard let s = router.cardFace else { return }
            let (f, c) = PFace.from(s)
            if let c { sw.chip = c }
            sw.select(f, reduce: reduce, haptic: false)
        }
        // A turn by hand: the card touched glides back to where it was once the heights settle.
        .onChange(of: sw.turned) { _, _ in
            guard let a = sw.anchor else { return }
            settle(a.t, at: a.y, after: 0.4)
        }
        .onChange(of: keptOn) { _, on in sw.chip = on ? .sold : .all }
    }

    /// Once the faces have turned and the heights settled, scroll so the touched card's top is back where it was.
    private func settle(_ t: String, at y: CGFloat, after s: Double) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(reduce ? 0.05 : s))
            guard let f = sw.frames[t] else { return }
            let d = f.minY - y
            if abs(d) >= 1 { glide?(d) }
        }
    }
}

/// The face and chip every card is on. A card's control rides that card's own swipe; where it settles, every card
/// turns. The card touched is the anchor the page keeps still.
@Observable final class PFaceSwitch {
    var face: PFace = .position
    var chip: PChip = .all
    /// Bumped by a turn by hand (a tap or a swipe), for the glide.
    var turned = 0
    /// The card touched and its top before the turn, in the page's visible space.
    @ObservationIgnored var anchor: (t: String, y: CGFloat)?
    /// Each card on screen in the page's visible space (kept quietly: they change every frame).
    @ObservationIgnored var frames: [String: CGRect] = [:]

    /// A tap on a card's control or a row inside it: every card turns.
    @MainActor func select(_ f: PFace, from t: String? = nil, reduce: Bool, haptic: Bool = true) {
        if let t, let y = frames[t]?.minY { anchor = (t, y) } else if t == nil { anchor = nil }
        if haptic && f != face { UISelectionFeedbackGenerator().selectionChanged() }
        let was = face
        face = f
        if haptic && f != was { turned += 1 }
    }
    /// A card's swipe has settled on a face.
    func settle(_ f: PFace, from t: String) {
        if f != face { turned += 1 }
        face = f
    }
    /// A chip on one card: every card shows the same legs.
    @MainActor func pick(_ c: PChip, from t: String) {
        guard c != chip else { return }
        if let y = frames[t]?.minY { anchor = (t, y) }
        UISelectionFeedbackGenerator().selectionChanged()
        chip = c
        turned += 1
    }
}

/// A card's faces, in order (block 13i): Position, then Risk for a name with something bought.
enum PFace: String, CaseIterable, Identifiable {
    case position, risk
    var id: String { rawValue }
    var label: String { self == .position ? "Position" : "Risk" }
    var spoken: String { label }
    /// A face named by a link from elsewhere: the old faces' names land on these (To do and Δ Γ on Risk, Sold and
    /// Bought on Position with that chip).
    static func from(_ s: String) -> (PFace, PChip?) {
        switch s {
        case "risk", "dg", "todo": (.risk, nil)
        case "sold": (.position, .sold)
        case "bought": (.position, .bought)
        default: (.position, nil)
        }
    }
}

/// The words and numbers the cards share (block 12, Numbers).
enum PWords {
    /// Red says so in words: a bought side down is a loss, not a gain, and a
    /// sold side down is lost, not kept (Nik, 13 Oct 2026).
    static func dollars(sold: Bool, up: Bool) -> String { sold ? (up ? "kept" : "lost") : (up ? "gain" : "loss") }
    /// "+$7.9K delta" when it adds (the design's one plus sign); "$36K delta" in red, no sign, when it
    /// takes some away (handoff 29: selling calls, buying puts).
    static func delta(_ v: Double) -> String { v >= 0 ? "+\(PF.usd(v)) delta" : "\(PF.usd(v)) delta" }
    /// "1 call", "40 calls"
    static func n(_ n: Int, _ w: String) -> String { "\(n) \(w)\(n == 1 ? "" : "s")" }
}

/// The swipe progress across a card's faces (0, 1, 2, 3). A class, so only the
/// tabs that read it redraw while the finger moves.
@Observable final class PFaceProgress {
    var p: Double = 0
    var moving = false
}

/// What a face's tab carries: the To do count, or a dot where the reason is.
enum PMark: Equatable {
    case none, badge(Int), dot(Color)

    /// Every card's mark on one face, for the one control: the counts added, else a dot (red over orange).
    static func sum(_ ms: [PMark]) -> PMark {
        let n = ms.reduce(0) { a, m in if case .badge(let k) = m { a + k } else { a } }
        if n > 0 { return .badge(n) }
        let dots = ms.compactMap { m -> Color? in if case .dot(let c) = m { c } else { nil } }
        return dots.contains(S.red) ? .dot(S.red) : dots.first.map { .dot($0) } ?? .none
    }
}

// MARK: - One name's card (block 13, 13i)

private struct PNameCard: View {
    typealias Face = PFace
    @Environment(\.accessibilityReduceMotion) private var reduce
    let n: PName
    /// This card's faces: Position, and Risk when something is bought.
    let faces: [Face]
    let sw: PFaceSwitch
    /// Opened from a tap: a 2 pt ink outline for 1.8 s.
    let ringed: Bool
    let width: CGFloat
    let go: Bool
    let delay: Double
    let hours: Hours?
    let live: Double
    let today: String
    let open: Bool
    let cal: [CalendarDay]

    @State private var pos = ScrollPosition()
    /// This card's own swipe: its control's thumb and its height follow it.
    @State private var prog = PFaceProgress()
    @State private var driving = false
    /// Each face's own height: the card takes the one it is on, blended mid-swipe (handoff 31).
    @State private var hs: [Face: CGFloat] = [:]

    private var t: String { n.t }
    /// One face is the card's full width; it carries the 20 pt side padding itself, so a strike
    /// tag that runs past the plot stays on its own face.
    private var pageW: CGFloat { width + 40 }

    var body: some View {
        let F = faces
        VStack(alignment: .leading, spacing: 16) {
            head.padding(.horizontal, 20)
            if F.count > 1 {
                PFaceTabs(faces: F.map(\.label), spoken: F.map(\.spoken), marks: F.map { n.mark($0) }, prog: prog, raised: false) { i in
                    guard let f = F[safe: i] else { return }
                    sw.select(f, from: t, reduce: reduce)
                }
                .padding(.horizontal, 20)
            }
            // Each face at its own height, top aligned: the card takes the one on screen and blends
            // between two mid-swipe (handoff 31, 13).
            PFaceHeight(prog: prog, heights: F.map { hs[$0] }) {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(F) { f in
                            face(f).padding(.horizontal, 20)
                                .frame(width: pageW, alignment: .topLeading)
                                .fixedSize(horizontal: false, vertical: true)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { v in setHeight(f, v) }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition($pos)
                .scrollIndicators(.hidden)
                .scrollDisabled(F.count < 2)
                .onScrollGeometryChange(for: Double.self) { g in Double(g.contentOffset.x / max(1, g.containerSize.width)) } action: { _, v in
                    prog.p = v
                }
                // A finger on this card: where it settles every card turns, and this card stays still on screen.
                .onScrollPhaseChange { _, ph in
                    prog.moving = ph != .idle
                    if ph == .interacting && !driving {
                        driving = true
                        if let y = sw.frames[t]?.minY { sw.anchor = (t, y) }
                    }
                    if ph == .idle, driving {
                        driving = false
                        if let f = F[safe: Int(prog.p.rounded())] { sw.settle(f, from: t) }
                    }
                }
            }
            .frame(width: pageW)
        }
        .foregroundStyle(S.ink)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { PCornerGlow(status: (n.sold ?? n.bought)?.status ?? .safe) }
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
        // Another card turned (or this one's control): this one follows, unless it is the one being swiped. A card
        // without that face stays where it is.
        .onChange(of: sw.face) { _, f in
            guard !driving, let i = F.firstIndex(of: f), abs(prog.p - Double(i)) > 0.01 else { return }
            if reduce { pos.scrollTo(x: CGFloat(i) * pageW) } else { withAnimation(S.standard(0.35)) { pos.scrollTo(x: CGFloat(i) * pageW) } }
        }
        // The faces changed (Risk once something is bought, or gone): stay on the face showing.
        .onChange(of: F) { _, new in
            let i = new.firstIndex(of: sw.face) ?? 0
            var tr = Transaction(); tr.disablesAnimations = true
            withTransaction(tr) { pos.scrollTo(x: CGFloat(i) * pageW) }
        }
        .onAppear {
            // Built as it scrolls on: on the face every card is on.
            if let i = F.firstIndex(of: sw.face), i > 0 {
                var tr = Transaction(); tr.disablesAnimations = true
                withTransaction(tr) { pos.scrollTo(x: CGFloat(i) * pageW) }
                prog.p = Double(i)
            }
        }
    }

    /// A face's height as measured: a change while the card is still (a chip, a pick) eases 0.3 s;
    /// mid-swipe it follows at once (Reduce Motion: always at once).
    private func setHeight(_ f: Face, _ v: CGFloat) {
        guard abs((hs[f] ?? 0) - v) > 0.5 else { return }
        if hs[f] == nil || prog.moving || reduce { hs[f] = v } else { withAnimation(S.standard(0.3)) { hs[f] = v } }
    }

    /// A row inside Position ("Goes short", "Friday's sale"): every card turns to Risk, this one stays still.
    private func openRisk() { sw.select(.risk, from: t, reduce: reduce) }

    // MARK: Header

    /// The ticker, its price and today's move; the strategy on the right; an orange dot while something is left to
    /// cover (13i).
    private var head: some View {
        HStack(alignment: .center, spacing: 8) {
            if n.cover {
                Circle().fill(S.orange).frame(width: 10, height: 10)
                    .accessibilityLabel("Needs cover")
            }
            (Text(t).font(SType(size: 20, weight: 700, line: 24, tracking: 0).font())
             + Text(" " + PF.price(n.px)).font(SType(size: 20, weight: 500, line: 24, tracking: 0).font(tabular: true))
                .foregroundStyle(S.muted)
             + (n.move.map { m in
                 Text(" " + String(format: "%.1f%%", abs(m))).font(SType(size: 15, weight: 600, line: 24, tracking: 0).font(tabular: true))
                     .foregroundStyle(m >= 0 ? S.green : S.red)
               } ?? Text("")))
                .sType(SType(size: 20, weight: 700, line: 24, tracking: 0))
                .lineLimit(1)
                .accessibilityLabel("\(t), \(PF.price(n.px))" + (n.move.map { ", \($0 >= 0 ? "up" : "down") \(String(format: "%.1f", abs($0))) percent today" } ?? ""))
            Spacer(minLength: 0)
            if let name = Strategy.name(n.strategy) {
                Text(name).sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                    .foregroundStyle(S.muted).lineLimit(1)
            }
        }
        .frame(height: 24)
    }

    // MARK: Faces

    @ViewBuilder private func face(_ f: Face) -> some View {
        switch f {
        case .position: position
        case .risk:
            if let r = n.risk {
                PRiskFace(t: t, r: r, perLeap: n.plan?.sell.n, sold: n.legs.filter { $0.side == "sold" && $0.type == "call" && $0.expiry == r.week },
                          width: width, active: sw.face == .risk)
            }
        }
    }

    /// Position (13i): the row on top when the book goes short or Friday's sale is still to place, then All · Sold ·
    /// Bought when the name has both sides (All first), else the one side it has.
    private var position: some View {
        let two = n.sold != nil && n.bought != nil
        return VStack(alignment: .leading, spacing: 18) {
            if let r = n.risk, n.cover { PGoesShortRow(r: r, tap: openRisk) }
            if let r = n.risk, let sale = r.sale { PSaleRow(sale: sale, perLeap: n.plan?.sell.n, tap: openRisk) }
            if two { PChips(chip: sw.chip) { c in sw.pick(c, from: t) } }
            legs(two ? sw.chip : (n.sold != nil ? .sold : .bought))
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private func legs(_ c: PChip) -> some View {
        switch c {
        case .all:
            if let s = n.sold, let b = n.bought, n.plan != nil,
               let v = PSoldPlan(c: s, n: n, hours: hours, live: live, today: today, cal: cal, width: width, bought: b) { v }
            else if let s = n.sold { sold(s) }
        case .sold: if let s = n.sold { sold(s) }
        case .bought:
            if let b = n.bought { if n.plan != nil { PBoughtPlan(c: b, n: n, today: today, width: width) } else { side(b) } }
        }
    }

    @ViewBuilder private func sold(_ c: PCard) -> some View {
        if n.plan != nil, let v = PSoldPlan(c: c, n: n, hours: hours, live: live, today: today, cal: cal, width: width) { v } else { side(c) }
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
        .accessibilityElement(children: .contain)
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
        return stats([
            (A.base, usd, c.sold ? "collected" : "paid", S.ink),
            (A.tv, usd, "time value", S.ink),
            (abs(A.pct), pct, c.sold ? "captured" : "return", tn),
            (abs(A.g), usd, PWords.dollars(sold: c.sold, up: A.up), tn),
        ])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y(c))
    }

    /// The numbers along a face's foot: 17 bold over a 12 label, a rule above (block 13).
    private func stats(_ s: [(Double, (Double) -> String, String, Color)]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(s, id: \.2) { s in
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
}

/// The pager's height: the face on screen, blended between two by the swipe (handoff 31, 13). Its own
/// view, so only it redraws while the finger moves; the faces inside are not rebuilt.
private struct PFaceHeight<Content: View>: View {
    let prog: PFaceProgress
    let heights: [CGFloat?]
    @ViewBuilder let content: Content
    var body: some View {
        let p = min(max(prog.p, 0), Double(max(0, heights.count - 1)))
        let lo = Int(p.rounded(.down)), hi = min(lo + 1, heights.count - 1), f = CGFloat(p - Double(lo))
        let a = heights[safe: lo] ?? nil, b = heights[safe: hi] ?? nil
        let h: CGFloat? = a.map { a in a + ((b ?? a) - a) * f }
        content.frame(height: h, alignment: .top).clipped()
    }
}

// MARK: - The tabs: a Liquid Glass segmented control whose capsule rides the swipe

private struct PFaceTabs: View {
    let faces: [String]
    let spoken: [String]
    let marks: [PMark]
    let prog: PFaceProgress
    /// The dot raised beside the label (block 13), or on its middle with 6 before it (Position · Risk, 13i).
    var raised = true
    let tap: (Int) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// Each tab as wide as its label and mark, the spare width shared out evenly.
    private func widths(_ W: CGFloat) -> [CGFloat] {
        let f = SType(size: 13, weight: 600, line: 16, tracking: 0).uiFont()
        let b = SType(size: 11, weight: 700, line: 11, tracking: 0).uiFont()
        let nat = faces.enumerated().map { i, t in
            let m: CGFloat = switch marks[safe: i] ?? .none {
            case .badge(let n): 5 + max(18, ceil(("\(n)" as NSString).size(withAttributes: [.font: b]).width) + 10)
            case .dot: 9
            case .none: 0
            }
            return ceil((t as NSString).size(withAttributes: [.font: f]).width) + m + 24
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
                        let on = abs(Double(i) - prog.p) < 0.5, m = marks[safe: i] ?? .none
                        Button { tap(i) } label: {
                            HStack(spacing: 0) {
                                Text(t).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false)
                                    .foregroundStyle(on ? S.ink : S.muted).lineLimit(1)
                                switch m {
                                case .badge(let n):
                                    // 18 tall, S.orange, dark ink in both modes (block 13, Attention).
                                    Text("\(n)").sType(SType(size: 11, weight: 700, line: 11, tracking: 0))
                                        .foregroundStyle(S.badgeInk)
                                        .padding(.horizontal, 5)
                                        .frame(minWidth: 18, minHeight: 18)
                                        .background(Capsule().fill(S.orange))
                                        .padding(.leading, 5)
                                case .dot(let c):
                                    Circle().fill(c).frame(width: 6, height: 6)
                                        .padding(.leading, raised ? 3 : 6)
                                        .offset(y: raised ? -5 : 0)
                                case .none:
                                    EmptyView()
                                }
                            }
                            .frame(width: ws[safe: i] ?? 0, height: 36)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                        .accessibilityLabel(Self.spoken(spoken[safe: i] ?? t, m))
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .frame(height: 36)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Faces")
    }

    static func spoken(_ t: String, _ m: PMark) -> String {
        switch m {
        case .badge(let n): "\(t), \(n) to do"
        case .dot: "\(t), needs attention"
        case .none: t
        }
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
struct POpacityPress: ButtonStyle {
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
