//
//  BookShared.swift
//  Sunny
//
//  What the Gamma and Insights pages (no longer in the tab bar), the Walls screen, Search, the ticker chart and Risk
//  still read from the old Positions cards, kept when those cards went (13 Nov 2026, the new Positions tab, App
//  Explorations 154a): each name's card data (PName, PNames), the shared words, the strategy names, the wall words, the
//  jump slider and the Delta words. Moved here as they were, less what only the cards used.
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

    /// The To do count: the trades left with ways on, else the To do rows. (The orders count went with the old
    /// Positions cards on 13 Nov 2026; only the Gamma and Insights pages, no longer in the tab bar, read it.)
    var todo = 0
    var todoN: Int { todo }
    func countTodo() -> Int { ways?.trades ?? tasks.count }
    var hasTodo: Bool { todoN > 0 }
}

enum PNames {
    /// Every name with a card (TSLA sits on the Home map only): names with To do first, then the
    /// order the cards already keep, safest first.
    /// Built once per update and reused by every screen that asks (Positions, Gamma, Insights, the strip): it was
    /// rebuilt in each body on every redraw.
    private static var memoKey = "", memo: [PName] = []
    @MainActor static func build(_ home: HomePayload, orderFrom: HomePayload?) -> [PName] {
        let key = "\(home.builtAt)|\(orderFrom?.builtAt ?? "")"
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

// MARK: - Wall words (the To do ways' helpers, kept for Gamma and the Walls screen)

enum PWays {
    /// 2,751 · no sign.
    static func us(_ v: Double) -> String { Int(abs(v).rounded()).formatted() }
    static func usd(_ v: Double) -> String { "$" + us(v) }
    /// Gamma at a wall: $6.3M · $570K.
    static func gamma(_ g: Double) -> String {
        let a = abs(g)
        if a >= 1e6 { return "$" + String(format: "%.1f", a / 1e6) + "M" }
        if a >= 1e3 { return "$\(Int((a / 1e3).rounded()))K" }
        return "$\(Int(a.rounded()))"
    }
    /// "Jan"
    static func month(_ iso: String) -> String { String(PF.monthDay(iso).prefix(3)) }
    static func weekday(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let d = Calendar(identifier: .gregorian).date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)) else { return "Thu" }
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][Calendar(identifier: .gregorian).component(.weekday, from: d) - 1]
    }
    static func dist(_ k: Double, _ px: Double) -> Double { abs(k / px - 1) * 100 }
}

// MARK: - The jump slider and Delta words (Risk)

/// The Delta words and tones Risk reads (the old Position card's Δ Γ face).
enum PDGFace {
    static func word(_ s: DGBook.State) -> String { switch s { case .long: "Stays long"; case .thin: "Thin"; case .short: "Goes short" } }
    static func tone(_ s: DGBook.State) -> Color { switch s { case .long: S.green; case .thin: S.orangeDeep; case .short: S.red } }
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
