//
//  SearchPage.swift
//  Sunny
//
//  The name page (block 31, handoff Nov 2 2026): one page per name, pushed over Search by "Tell me about Nike", "Show
//  me Nike's world" or "What's happening with Nike?". The price and today's move, three sentences written for the
//  question, then the acts; this is step 1, Nike's world: the stock (the year chart card and four figures), the sector,
//  what's being said and earnings, each a kicker, one finding and the card that proves it. Every figure comes worked
//  out from sunny-search, the finding and its card from the same snapshot. Asked, 2 Nov 2026: a section with no data is
//  left out; back in the chat the turn keeps the paragraph and a button that opens the page again; a question typed
//  on the page goes back to the chat; no Go deeper or Read aloud here; a section plays its motion the first time it
//  scrolls into view.
//  Step 2, Your Nike: the name's share of the book (value now, as the Allocation card), what is held (a tile opens the
//  payoff), since it entered (Made = Realized + Open, You % over its value on the first day, from IBKR's daily report)
//  and the calls week by week. "What's happening" folds Your Nike to one line; "How's my position" folds the world
//  and puts Since you entered first. A folded act opens in place and gets a Fold pill.
//

import SwiftUI

/// What sunny-search sends for the page.
struct SXPage: Decodable, Equatable {
    struct Day: Decodable, Equatable { let pct: Double; let usd: Double? }
    struct Stat: Decodable, Equatable { let l: String; let v: String }
    struct Stock: Decodable, Equatable { let chart: SXChart; let stats: [Stat]; let src: String; let finding: String? }
    struct SectorRow: Decodable, Equatable { let k: String; let l: String; let pct: Double }
    struct Sector: Decodable, Equatable { let rows: [SectorRow]; let span: String?; let src: String; let finding: String? }
    struct Note: Decodable, Equatable { let k: String; let title: String; let line: String; let src: String }
    struct Said: Decodable, Equatable { let rows: [Note]; let src: String; let finding: String? }
    struct Move: Decodable, Equatable { let rep: String; let m: String; let pct: Double }
    struct Next: Decodable, Equatable { let day: String; let when: String?; let days: Int }
    struct Priced: Decodable, Equatable { let pct: Double; let by: String }
    struct Earnings: Decodable, Equatable { let moves: [Move]; let next: Next?; let priced: Priced?; let src: String; let finding: String? }
    struct World: Decodable, Equatable { let stock: Stock; let sector: Sector?; let said: Said?; let earnings: Earnings? }

    struct BookRow: Decodable, Equatable { let t: String; let usd: Double; let pct: Int }
    struct Book: Decodable, Equatable {
        let total: Double, rows: [BookRow], rank: Int
        /// This name's share of this week's premium sold and of the book's positive delta in dollars, %.
        let premium: Int?, delta: Int?
        let src: String, finding: String?
    }
    /// A What you hold tile: label, what is held, detail lines, a status ("81% kept") and its tone.
    struct Tile: Decodable, Equatable { let k: String; let l: String; let v: String; let d: [String]; let s: String?; let tone: String? }
    struct Hold: Decodable, Equatable { let tiles: [Tile]; let right: String?; let payoff: SXPayoff?; let finding: String? }
    /// A day since entry: [date, made $, made as % of the first day's value, the stock's move %].
    struct Pt: Decodable, Equatable {
        let d: String, made: Double, you: Double?, stock: Double?
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            d = try c.decode(String.self)
            made = try c.decode(Double.self)
            you = try c.decodeIfPresent(Double.self)
            stock = try c.decodeIfPresent(Double.self)
        }
    }
    struct Since: Decodable, Equatable {
        let from: String, to: String, fromDay: String, toDay: String
        let base: Double, made: Double, realized: Double, open: Double
        let you: Double?, stock: Double?
        let pts: [Pt]
        let src: String, finding: String?
    }
    /// A finished week: g is full, part or lost.
    struct Week: Decodable, Equatable { let fri: String; let day: String; let sold: Double; let kept: Double; let g: String }
    struct WeekNow: Decodable, Equatable { let fri: String; let day: String; let sold: Double; let kept: Double; let pct: Int; let pace: Double?; let tag: String? }
    struct Weeks: Decodable, Equatable { let weeks: [Week]; let now: WeekNow?; let from: String; let src: String; let finding: String? }
    struct Mine: Decodable, Equatable { let book: Book?; let hold: Hold?; let since: Since?; let weeks: Weeks?; let order: [String] }
    struct Folds: Decodable, Equatable { let world: String?; let mine: String? }

    let t: String, co: String, strategy: String?
    /// "all" or "news": the question it was built for.
    let ask: String
    let px: Double, day: Day?
    /// The market is open: the move is today's; otherwise it is the last close's.
    let live: Bool
    let at: String
    /// The first paragraph, numbers marked {r:x} {g:x} {b:x} as everywhere in Search.
    let lead: String
    let world: World
    /// Your Nike (step 2); nil from a server before it.
    let mine: Mine?
    /// The act the question folds: "world", "mine" or nil.
    let fold: String?
    /// A folded act's one line, numbers marked as in the paragraph.
    let folds: Folds?
}

extension EnvironmentValues {
    /// Opens a name page over Search (the button under its paragraph in the chat).
    @Entry var sxOpenPage: (SXPage) -> Void = { _ in }
}

private extension SXType {
    static let pageName = SXType(size: 34, line: 41, weight: .bold, style: .largeTitle, tracking: -0.02)
    static let pageSub = SXType(size: 15, line: 20, weight: .medium, style: .subheadline, tracking: 0)
    static let pagePrice = SXType(size: 28, line: 34, weight: .bold, style: .title1, tracking: -0.01)
    static let pageLead = SXType(size: 22, line: 29, weight: .medium, style: .title2, tracking: -0.01)
    static let act = SXType(size: 26, line: 32, weight: .bold, style: .title1, tracking: -0.015)
    static let actSub = SXType(size: 14, line: 20, weight: .medium, style: .footnote, tracking: 0)
    static let kicker = SXType(size: 13, line: 16, weight: .semibold, style: .footnote, tracking: 0)
    static let finding = SXType(size: 19, line: 25, weight: .semibold, style: .title3, tracking: -0.005)
    static let value = SXType(size: 17, line: 22, weight: .bold, style: .headline, tracking: 0)
    static let news = SXType(size: 16, line: 21, weight: .semibold, style: .callout, tracking: 0)
    static let tableRow = SXType(size: 14, line: 18, weight: .medium, style: .footnote, tracking: 0)
    static let axis = SXType(size: 11, line: 14, weight: .semibold, style: .caption2, tracking: 0)
}

/// ▲ or ▼ and the move with one decimal, never a minus sign.
private func arrowPct(_ x: Double) -> String { (x < 0 ? "▼ " : "▲ ") + String(format: "%.1f%%", abs(x)) }

// MARK: - In the chat

/// The turn's paragraph, then a button that opens the page again.
struct SXPageEntry: View {
    let p: SXPage
    @Environment(\.sxOpenPage) private var open

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SXWords(text: p.lead, type: .say)
            Button { open(p) } label: {
                HStack(spacing: 12) {
                    Text("\(p.co) page").sx(.headline).foregroundStyle(SX.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(SX.muted)
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 52)
                .modifier(SXPaper(radius: 18))
                .contentShape(.rect(cornerRadius: 18))
            }
            .buttonStyle(SPressStyle())
            .accessibilityLabel("\(p.co) page")
            .accessibilityHint("Opens the page")
        }
    }
}

// MARK: - The page

struct SXNamePage: View {
    let p: SXPage
    let close: () -> Void
    /// A question typed on the page: back to the chat as the next turn.
    let ask: (String) -> Void
    /// The mic: back to the chat, listening.
    let listen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dynamicTypeSize) private var dts
    @State private var q = ""
    @FocusState private var focused: Bool
    @State private var counted = false
    /// An act the question folded, opened by a tap (its heading then has a Fold pill).
    @State private var opened: Set<String> = []

    private var world: SXPage.World { p.world }
    private func folded(_ act: String) -> Bool { p.fold == act && !opened.contains(act) }
    private func toggle(_ act: String) {
        withAnimation(reduce ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.45)) {
            if opened.contains(act) { opened.remove(act) } else { opened.insert(act) }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            SXBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.pageRise(0)
                    Text(SXText.styled(p.lead, .pageLead, dts)).sx(.pageLead).foregroundStyle(SX.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 22)
                        .pageRise(0.08)
                    if folded("world") {
                        foldCard("\(p.co)’s world", line: p.folds?.world, spark: world.stock.chart.c) { toggle("world") }.padding(.top, 28)
                    } else {
                        worldAct.padding(.top, 28)
                    }
                    if let m = p.mine {
                        if folded("mine") {
                            foldCard("Your \(p.co)", line: p.folds?.mine, spark: nil) { toggle("mine") }.padding(.top, 28)
                        } else {
                            mineAct(m).padding(.top, 28)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 100)
                .padding(.bottom, 132)
            }
            .ignoresSafeArea(.container, edges: .top)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            fades
            topBar
            askField
            edge
        }
        .onAppear { withAnimation(reduce ? nil : .timingCurve(0.33, 1, 0.68, 1, duration: 0.9)) { counted = true } }
    }

    // MARK: Header

    private var subline: String {
        [p.t, Strategy.name(p.strategy), "in your book"].compactMap { $0 }.joined(separator: " · ")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(p.co).sx(.pageName).foregroundStyle(SX.ink).accessibilityAddTraits(.isHeader)
            Text(subline).sx(.pageSub).foregroundStyle(SX.muted)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SXCountUp(v: counted || reduce ? p.px : 0).sx(.pagePrice).foregroundStyle(SX.ink)
                if let d = p.day {
                    Text((d.pct < 0 ? "▼ " : "▲ ") + (d.usd.map { String(format: "$%.2f · ", $0) } ?? "")
                         + String(format: "%.1f%% ", abs(d.pct)) + (p.live ? "today" : "at the close"))
                        .sx(.question).foregroundStyle(d.pct < 0 ? SX.down : SX.up)
                }
            }
            .padding(.top, 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(format: "$%.2f", p.px) + (p.day.map { d in
                String(format: ", %@ %.1f percent %@", d.pct < 0 ? "down" : "up", abs(d.pct), p.live ? "today" : "at the close") } ?? ""))
        }
    }

    // MARK: Nike's world

    private var worldAct: some View {
        VStack(alignment: .leading, spacing: 0) {
            actHead("\(p.co)’s world", "The stock, and why it moves", act: "world")
            section("The stock", world.stock.finding, 0) {
                VStack(spacing: 10) {
                    SXChartCard(p: world.stock.chart)
                    SXPageStats(stats: world.stock.stats, src: world.stock.src)
                }
            }
            if let s = world.sector {
                section("The sector", s.finding, 1) { SXSectorCard(t: p.t, s: s) }
            }
            if let s = world.said {
                section("What’s being said", s.finding, 2) { SXSaidCard(t: p.t, s: s) }
            }
            if let e = world.earnings {
                section("Earnings", e.finding, 3) { SXEarningsCard(t: p.t, e: e) }
            }
        }
    }

    // MARK: Your Nike

    private func mineAct(_ m: SXPage.Mine) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            actHead("Your \(p.co)", "What you own, and how it’s done", act: "mine")
            ForEach(Array(m.order.enumerated()), id: \.element) { i, k in mineSection(k, m, i) }
        }
    }

    @ViewBuilder private func mineSection(_ k: String, _ m: SXPage.Mine, _ i: Int) -> some View {
        switch k {
        case "book": if let b = m.book { section("\(p.co) in your book", b.finding, i) { SXInBookCard(t: p.t, b: b) } }
        case "hold": if let h = m.hold { section("What you hold", h.finding, i) { SXHoldCard(t: p.t, h: h) } }
        case "since": if let s = m.since { section("Since you entered", s.finding, i) { SXSinceCard(t: p.t, s: s) } }
        case "weeks": if let w = m.weeks { section("Week by week", w.finding, i) { SXWeeksCard(t: p.t, w: w) } }
        default: EmptyView()
        }
    }

    // MARK: Acts and folds

    /// An act's hairline and heading; a Fold pill when the question had folded it and he opened it.
    private func actHead(_ title: String, _ sub: String, act: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(SX.line).frame(height: 1)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).sx(.act).foregroundStyle(SX.ink).accessibilityAddTraits(.isHeader)
                    Text(sub).sx(.actSub).foregroundStyle(SX.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if p.fold == act {
                    Button { toggle(act) } label: {
                        Text("Fold").sx(.question).foregroundStyle(SX.ink)
                            .padding(.horizontal, 14).frame(height: 32)
                            .background(SX.fill, in: .rect(cornerRadius: 16))
                            .frame(minHeight: 44).contentShape(.rect)
                    }
                    .buttonStyle(SPressStyle())
                    .accessibilityLabel("Fold \(title)")
                }
            }
            .padding(.top, 20)
        }
        .pageRise(0.06)
    }

    /// A folded act: its name, a sparkline of the year for the world, one line; a tap opens it in place.
    private func foldCard(_ title: String, line: String?, spark: [Double]?, open: @escaping () -> Void) -> some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(title).sx(.question).foregroundStyle(SX.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(SX.muted)
                }
                if let spark, spark.count > 1 { SXSpark(v: spark).frame(height: 40) }
                if let line {
                    Text(SXText.styled(line, .actSub, dts)).sx(.actSub).foregroundStyle(SX.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 14).padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SXPaper(radius: 22))
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(SPressStyle())
        .modifier(SXFoldRise())
        .accessibilityLabel("\(title), folded. " + (line.map { SXText.plain($0) } ?? ""))
        .accessibilityHint("Opens it")
    }

    /// A kicker, the finding, then the card that proves it; it rises in the first time it scrolls into view.
    private func section<C: View>(_ kicker: String, _ finding: String?, _ i: Int, @ViewBuilder card: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kicker).sx(.kicker).foregroundStyle(SX.muted)
                if let f = finding {
                    Text(SXText.styled(f, .finding, dts)).sx(.finding).foregroundStyle(SX.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            card().padding(.top, 10)
        }
        .padding(.top, 28)
        .pageRise(0.12 + Double(i) * 0.06)
    }

    // MARK: Furniture

    private var fades: some View {
        VStack(spacing: 0) {
            LinearGradient(stops: [.init(color: SX.fadeTop, location: 0.52), .init(color: SX.fadeTop.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: 112)
            Spacer(minLength: 0)
            LinearGradient(stops: [.init(color: SX.fadeBottom, location: 0.4), .init(color: SX.fadeBottom.opacity(0), location: 1)], startPoint: .bottom, endPoint: .top)
                .frame(height: 130)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Back top left: a chevron and "Search", 44 tall.
    private var topBar: some View {
        VStack {
            HStack {
                Button(action: close) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left").font(.system(size: 19, weight: .semibold))
                        Text("Search").sx(.field)
                    }
                    .foregroundStyle(SX.ink)
                    .padding(.horizontal, 8)
                    .frame(height: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(SXTextPress())
                .accessibilityLabel("Back to Search")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 54)
            Spacer()
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    /// "Ask about Nike": the question goes back to the chat as the next turn; the mic listens there.
    private var askField: some View {
        let empty = q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
            TextField("", text: $q, prompt: Text("Ask about \(p.co)").foregroundStyle(SX.muted))
                .sx(.field).foregroundStyle(SX.ink)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)
                .accessibilityLabel("Ask about \(p.co)")
            Button { empty ? listen() : send() } label: {
                Image(systemName: empty ? "mic.fill" : "arrow.up").font(.system(size: empty ? 16 : 14, weight: empty ? .medium : .bold))
                    .foregroundStyle(S.chipOnInk)
                    .frame(width: 40, height: 40).background(SX.ink, in: .circle)
                    .frame(width: 44, height: 44).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(empty ? "Ask by voice" : "Ask")
        }
        .padding(.leading, 20).padding(.trailing, 4)
        .frame(height: 52)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func send() {
        let s = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        focused = false
        q = ""
        ask(s)
    }

    /// A swipe from the left edge steps back like the button.
    private var edge: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 18).contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 8).onEnded { v in if v.translation.width > 60 { close() } })
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
    }
}

/// The price counting up from 0 (ease out cubic, 0.9 s), the same decimals and separators all the way.
private struct SXCountUp: View, Animatable {
    var v: Double
    var animatableData: Double { get { v } set { v = newValue } }
    var body: some View { Text(v.formatted(.currency(code: "USD").precision(.fractionLength(2)))) }
}

// MARK: - Motion

private extension View {
    /// Rises 12 pt and fades in (0.55 s, ease out quint) the first time it scrolls into view; at once with Reduce Motion.
    func pageRise(_ delay: Double) -> some View { modifier(SXPageRise(delay: delay)) }
}

private struct SXPageRise: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on || reduce ? 1 : 0)
            .offset(y: on || reduce ? 0 : 12)
            .onScrollVisibilityChange(threshold: 0.02) { v in
                guard v, !on, !reduce else { return }
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.55).delay(delay)) { on = true }
            }
    }
}

/// Plays once, the first time its view scrolls into view (the sector's bars, for one).
private struct SXOnceVisible: ViewModifier {
    @Binding var on: Bool
    func body(content: Content) -> some View {
        content.onScrollVisibilityChange(threshold: 0.2) { v in if v && !on { on = true } }
    }
}

// MARK: - Cards

/// Every card: radius 22, padded 16 × 18 × 14, paper with the card's shadow.
private struct SXPageCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(EdgeInsets(top: 16, leading: 18, bottom: 14, trailing: 18))
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SXPaper(radius: 22))
    }
}

/// `NKE · Title` on the left taking the room; a label on the right that never shrinks.
private struct SXCardHead: View {
    let t: String, title: String
    var right: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            (Text(t).foregroundColor(SX.ink) + Text(" · " + title).foregroundColor(SX.muted))
                .sx(.question).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let right { Text(right).sx(.time.weighted(.semibold)).foregroundStyle(SX.muted).lineLimit(1).fixedSize() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Market cap, P/E, dividend yield and the 52 weeks: a 2 by 2 grid with hairlines between, the source under it.
private struct SXPageStats: View {
    let stats: [SXPage.Stat]
    let src: String
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(stride(from: 0, to: stats.count, by: 2)), id: \.self) { i in
                if i > 0 { Rectangle().fill(SX.line).frame(height: 1) }
                HStack(spacing: 0) {
                    cell(stats[i])
                    if i + 1 < stats.count {
                        Rectangle().fill(SX.line).frame(width: 1)
                        cell(stats[i + 1])
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(SX.line).frame(height: 1)
            SXSourceLine(kind: "research", text: src)
                .padding(.vertical, 10).padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(SXPaper(radius: 18))
    }
    private func cell(_ s: SXPage.Stat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s.l).sx(.tiny).foregroundStyle(SX.muted)
            Text(s.v).sx(.value).foregroundStyle(SX.ink).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The name against its peers, its sector and the S&P 500 over a year: a bar each from a centre zero line, the scale
/// the biggest move; the averages and the index muted; the page's name ringed in ink.
private struct SXSectorCard: View {
    let t: String
    let s: SXPage.Sector
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var grown = false

    private var scale: Double { max(1e-9, s.rows.map { abs($0.pct) }.max() ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SXCardHead(t: t, title: "Peers and sector", right: s.span ?? "1 year")
            VStack(spacing: 0) {
                ForEach(Array(s.rows.enumerated()), id: \.element.k) { i, r in row(r, i) }
            }
            SXSourceLine(kind: "research", text: s.src)
        }
        .modifier(SXPageCard())
        .modifier(SXOnceVisible(on: $grown))
    }

    private func row(_ r: SXPage.SectorRow, _ i: Int) -> some View {
        let me = r.k == "me", tone: Color = me ? (r.pct < 0 ? SX.down : SX.up) : SX.muted
        return HStack(spacing: 8) {
            Text(r.l).sx(me ? .tableRow.weighted(.bold) : .tableRow).foregroundStyle(me ? SX.ink : SX.muted).lineLimit(1)
                .padding(.horizontal, me ? 6 : 0).padding(.vertical, me ? 1 : 0)
                .overlay { if me { RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(SX.ink, lineWidth: 1.5) } }
                .frame(width: 118, alignment: .leading)
            GeometryReader { g in
                let half = g.size.width / 2, len = half * min(1, abs(r.pct) / scale) * (grown || reduce ? 1 : 0)
                ZStack(alignment: .leading) {
                    Rectangle().fill(SX.muted.opacity(0.5)).frame(width: 1, height: 14).position(x: half, y: g.size.height / 2)
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(me ? tone : SX.muted.opacity(0.4))
                        .frame(width: len, height: 8)
                        .position(x: r.pct < 0 ? half - len / 2 : half + len / 2, y: g.size.height / 2)
                }
                .animation(reduce ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.7).delay(0.22 + Double(i) * 0.045), value: grown)
            }
            Text(arrowPct(r.pct)).sx(me ? .tableRow.weighted(.bold) : .tableRow).foregroundStyle(me ? tone : SX.muted)
                .lineLimit(1).fixedSize()
                .frame(width: 58, alignment: .trailing)
        }
        .frame(minHeight: 34)
        .overlay(alignment: .top) { Rectangle().fill(SX.line).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(r.l), \(r.pct < 0 ? "down" : "up") \(String(format: "%.1f", abs(r.pct))) percent in a year" + (me ? ", this name" : ""))
    }
}

/// What's being said: Nik's Investing Pro notes, a row each, the title, its first point and where it is from.
private struct SXSaidCard: View {
    let t: String
    let s: SXPage.Said
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(s.rows.enumerated()), id: \.element.k) { i, n in
                VStack(alignment: .leading, spacing: 3) {
                    Text(n.title).sx(.news).foregroundStyle(SX.ink)
                    Text(n.line).sx(.actSub.weighted(.regular)).foregroundStyle(SX.muted).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    Text(n.src).sx(.tiny).foregroundStyle(SX.research).padding(.top, 2)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(SX.line).frame(height: 1) } }
                .accessibilityElement(children: .combine)
            }
            SXSourceLine(kind: "research", text: s.src).padding(.top, 2).padding(.bottom, 8)
        }
        .padding(.top, 6).padding(.horizontal, 18).padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SXPaper(radius: 22))
    }
}

/// Earnings: the stock the day after each of the last four reports, then the next report and the move the options price
/// to the first expiry after it.
private struct SXEarningsCard: View {
    let t: String
    let e: SXPage.Earnings
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SXCardHead(t: t, title: "Earnings", right: e.moves.isEmpty ? nil : "Last \(e.moves.count) report\(e.moves.count == 1 ? "" : "s")")
            if !e.moves.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 0) {
                        ForEach(e.moves, id: \.rep) { m in
                            VStack(spacing: 3) {
                                Text(arrowPct(m.pct)).sx(.tableRow.weighted(.bold)).foregroundStyle(m.pct < 0 ? SX.down : SX.up)
                                Text(m.m).sx(.axis).foregroundStyle(SX.muted)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(m.m): the stock \(m.pct < 0 ? "fell" : "rose") \(String(format: "%.1f", abs(m.pct))) percent the day after")
                        }
                    }
                    Text("The stock the day after").sx(.source).foregroundStyle(SX.muted)
                }
            }
            if e.next != nil || e.priced != nil {
                VStack(spacing: 12) {
                    if !e.moves.isEmpty { Rectangle().fill(SX.line).frame(height: 1) }
                    HStack(alignment: .top, spacing: 12) {
                        if let n = e.next { stat("Next report", n.day, n.when ?? "in \(n.days) day\(n.days == 1 ? "" : "s")") }
                        if let pr = e.priced { stat("Options price", String(format: "%.1f%% move", pr.pct), "by \(pr.by)") }
                    }
                }
            }
            SXSourceLine(kind: "research", text: e.src)
        }
        .modifier(SXPageCard())
    }
    private func stat(_ l: String, _ v: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(l).sx(.tiny).foregroundStyle(SX.muted)
            Text(v).sx(.value).foregroundStyle(SX.ink)
            Text(sub).sx(.source).foregroundStyle(SX.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Your Nike

private extension SX {
    /// Muted text on a tinted tile (block 31: #AEAEB2 in dark so it passes 4.5:1 on the tile).
    static let mutedOnTile = S.dyn(0x646469, 0xAEAEB2)
}

private extension SXType {
    static let big = SXType(size: 34, line: 38, weight: .bold, style: .largeTitle, tracking: -0.02)
    static let panelAmount = SXType(size: 20, line: 24, weight: .bold, style: .title3, tracking: 0)
}

/// Whole dollars, no sign: the color says up or down.
private func dollars(_ v: Double) -> String { "$" + Int(abs(v).rounded()).formatted(.number.grouping(.automatic)) }
private func tone(_ v: Double) -> Color { v < 0 ? SX.down : SX.up }

/// A folded act rises 6 and fades in (0.3 s).
private struct SXFoldRise: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var on = false
    func body(content: Content) -> some View {
        content.opacity(on || reduce ? 1 : 0).offset(y: on || reduce ? 0 : 6)
            .onAppear { withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3)) { on = true } }
    }
}

/// The year as a 2 pt line, in the year's color, wiping in left to right.
private struct SXSpark: View {
    let v: [Double]
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var on = false
    var body: some View {
        SXLineShape(v: v, lo: v.min() ?? 0, hi: v.max() ?? 1)
            .trim(from: 0, to: on || reduce ? 1 : 0)
            .stroke((v.last ?? 0) < (v.first ?? 0) ? SX.down : SX.up, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .onAppear { withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.9).delay(0.15)) { on = true } }
            .accessibilityHidden(true)
    }
}

/// A series across the box, evenly spaced, lo at the bottom and hi at the top.
private struct SXLineShape: Shape {
    let v: [Double], lo: Double, hi: Double
    func path(in r: CGRect) -> Path {
        var p = Path()
        guard v.count > 1, hi > lo else { return p }
        for (i, x) in v.enumerated() {
            let pt = CGPoint(x: r.minX + r.width * Double(i) / Double(v.count - 1), y: r.maxY - r.height * (x - lo) / (hi - lo))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

/// The same series closed down to a level: the area under (or over) the line.
private struct SXAreaShape: Shape {
    let v: [Double], lo: Double, hi: Double, base: Double
    func path(in r: CGRect) -> Path {
        var p = SXLineShape(v: v, lo: lo, hi: hi).path(in: r)
        guard v.count > 1, hi > lo else { return p }
        let y = r.maxY - r.height * (base - lo) / (hi - lo)
        p.addLine(to: CGPoint(x: r.maxX, y: y))
        p.addLine(to: CGPoint(x: r.minX, y: y))
        p.closeSubpath()
        return p
    }
}

/// Dollars counting up from 0 (ease out cubic, 0.9 s).
private struct SXDollarCount: View, Animatable {
    var v: Double
    var animatableData: Double { get { v } set { v = newValue } }
    var body: some View { Text(dollars(v)) }
}

/// The name in the book: a stacked bar of every name's value now (this one in ink, the rest in gray steps), a legend,
/// then its share of this week's premium and of the delta in dollars.
private struct SXInBookCard: View {
    let t: String
    let b: SXPage.Book
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var on = false
    private static let steps: [Double] = [0.72, 0.56, 0.44, 0.34, 0.26, 0.19]

    private func color(_ r: SXPage.BookRow) -> Color {
        if r.t == t { return SX.ink }
        let i = b.rows.filter { $0.t != t }.firstIndex { $0.t == r.t } ?? 0
        return SX.muted.opacity(Self.steps[min(i, Self.steps.count - 1)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SXCardHead(t: "Your book", title: "value now", right: dollars(b.total))
            GeometryReader { g in
                let gaps = Double(max(0, b.rows.count - 1)) * 2, w = max(0, g.size.width - gaps)
                HStack(spacing: 2) {
                    ForEach(b.rows, id: \.t) { r in Rectangle().fill(color(r)).frame(width: w * r.usd / max(1, b.total)) }
                }
                .frame(width: g.size.width, alignment: .leading)
                .clipShape(.rect(cornerRadius: 7))
                .mask(alignment: .leading) { Rectangle().frame(width: on || reduce ? g.size.width : 0) }
            }
            .frame(height: 14)
            .onScrollVisibilityChange(threshold: 0.2) { v in
                if v && !on { withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.9).delay(0.25)) { on = true } }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(b.rows, id: \.t) { r in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(color(r)).frame(width: 10, height: 10)
                        Text(r.t).sx(r.t == t ? .tiny.weighted(.bold) : .tiny).foregroundStyle(SX.ink).frame(width: 44, alignment: .leading)
                        Text("\(r.pct)%").sx(.tiny).foregroundStyle(SX.ink).frame(width: 32, alignment: .trailing)
                        Text(dollars(r.usd)).sx(.source).foregroundStyle(SX.muted).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(r.t), \(r.pct) percent, \(dollars(r.usd))" + (r.t == t ? ", this name" : ""))
                }
            }
            if b.premium != nil || b.delta != nil {
                Rectangle().fill(SX.line).frame(height: 1)
                HStack(alignment: .top, spacing: 12) {
                    if let x = b.premium { stat("This week’s premium", "\(x)%") }
                    if let x = b.delta { stat("Delta in dollars", "\(x)%") }
                }
            }
            SXSourceLine(kind: "sunny", text: b.src)
        }
        .modifier(SXPageCard())
    }
    private func stat(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(l).sx(.tiny).foregroundStyle(SX.muted)
            Text(v).sx(.value).foregroundStyle(SX.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// What is held: calls sold, puts sold, calls bought, puts bought, two by two; any tile, or the row under them, opens
/// the payoff by Friday under the card.
private struct SXHoldCard: View {
    let t: String
    let h: SXPage.Hold
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var open = false

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                SXCardHead(t: t, title: "Sold and bought", right: h.right)
                VStack(spacing: 10) {
                    ForEach(Array(stride(from: 0, to: h.tiles.count, by: 2)), id: \.self) { i in
                        HStack(alignment: .top, spacing: 10) {
                            tile(h.tiles[i])
                            if i + 1 < h.tiles.count { tile(h.tiles[i + 1]) } else { Color.clear.frame(maxWidth: .infinity) }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if h.payoff != nil {
                    VStack(spacing: 0) {
                        Rectangle().fill(SX.line).frame(height: 1)
                        Button { flip() } label: {
                            HStack {
                                Text("Payoff by Friday").sx(.question).foregroundStyle(SX.ink)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(SX.muted)
                                    .rotationEffect(.degrees(open ? 180 : 0))
                            }
                            .frame(height: 44).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Payoff by Friday")
                        .accessibilityValue(open ? "Open" : "Closed")
                    }
                }
            }
            .modifier(SXPageCard())
            if open, let po = h.payoff {
                SXPayoffCard(p: po).transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
    }

    private func flip() {
        withAnimation(reduce ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.3)) { open.toggle() }
    }

    private func tile(_ x: SXPage.Tile) -> some View {
        Button { if h.payoff != nil && !open { flip() } } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(x.l).sx(.tiny).foregroundStyle(SX.mutedOnTile)
                Text(x.v).sx(.value).foregroundStyle(SX.ink).lineLimit(1).minimumScaleFactor(0.75)
                ForEach(x.d, id: \.self) { Text($0).sx(.source).foregroundStyle(SX.mutedOnTile).fixedSize(horizontal: false, vertical: true) }
                if let s = x.s {
                    Text(s).sx(.tiny).foregroundStyle(x.tone == "up" ? SX.up : x.tone == "down" ? SX.down : SX.mutedOnTile)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 10).padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: .infinity, alignment: .topLeading)
            .background(SX.fill, in: .rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(SPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(h.payoff != nil ? "Opens the payoff by Friday" : "")
    }
}

/// Since you entered: made since the first day (the big number counts up), you against the stock in %, a finger reads
/// any day; then Realized, Open and Made.
private struct SXSinceCard: View {
    let t: String
    let s: SXPage.Since
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var drawn = false
    @State private var fill = false
    @State private var counted = false
    @State private var sel: Int?

    /// Plotted in % when there is a first-day value; in dollars otherwise (and no stock line).
    private var pct: Bool { s.you != nil }
    private var mine: [Double] { s.pts.map { pct ? ($0.you ?? 0) : $0.made } }
    private var stock: [Double] { pct ? s.pts.map { $0.stock ?? 0 } : [] }
    private var range: (Double, Double) {
        let all = mine + stock + [0], lo = all.min() ?? 0, hi = all.max() ?? 1, pad = max(0.5, (hi - lo) * 0.1)
        return (lo - pad, hi + pad)
    }
    private var shown: Double { sel.map { s.pts[$0].made } ?? s.made }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SXCardHead(t: t, title: "Your position", right: "Since \(s.fromDay)")
            VStack(alignment: .leading, spacing: 2) {
                Text(label).sx(.label).foregroundStyle(SX.muted)
                Group {
                    if sel != nil { Text(dollars(shown)) } else { SXDollarCount(v: counted || reduce ? s.made : 0) }
                }
                .sx(.big).foregroundStyle(tone(shown))
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 14) {
                key(width: 14, height: 3, color: tone(s.made), name: "You", v: pct ? s.you : nil)
                if pct { key(width: 14, height: 2, color: SX.muted, name: "\(t) stock", v: s.stock) }
            }
            chart.frame(height: 160)
            axis
            Rectangle().fill(SX.line).frame(height: 1)
            HStack(alignment: .top, spacing: 12) {
                stat("Realized", s.realized)
                stat("Open", s.open)
                stat("Made", s.made)
            }
            SXSourceLine(kind: "sunny", text: s.src)
        }
        .modifier(SXPageCard())
        .onScrollVisibilityChange(threshold: 0.2) { v in
            guard v, !drawn else { return }
            withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.9)) { counted = true }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.1).delay(0.2)) { drawn = true }
            withAnimation(.easeOut(duration: 0.6).delay(0.9)) { fill = true }
        }
    }

    private var label: String {
        if let i = sel { return (s.pts[i].made < 0 ? "Down by " : "Made by ") + day(s.pts[i].d) }
        return (s.made < 0 ? "Down since " : "Made since ") + s.fromDay
    }
    private func day(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC")
        guard let d = f.date(from: iso) else { return iso }
        f.dateFormat = "MMM d"; return f.string(from: d)
    }

    private func key(width: CGFloat, height: CGFloat, color: Color, name: String, v: Double?) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: height / 2).fill(color).frame(width: width, height: height)
            Text(name).sx(.tiny).foregroundStyle(SX.muted)
            if let v { Text((v < 0 ? "▼ " : "▲ ") + String(format: "%.1f%%", abs(v))).sx(.tiny).foregroundStyle(tone(v)) }
        }
        .accessibilityElement(children: .combine)
    }

    private var chart: some View {
        let (lo, hi) = range, c = tone(s.made)
        return GeometryReader { g in
            let r = CGRect(origin: .zero, size: g.size), y0 = g.size.height * (hi - 0) / (hi - lo)
            let n = max(1, s.pts.count - 1), x = { (i: Int) in g.size.width * Double(i) / Double(n) }
            let yOf = { (v: Double) in g.size.height * (hi - v) / (hi - lo) }
            ZStack(alignment: .topLeading) {
                Path { p in p.move(to: CGPoint(x: 0, y: y0)); p.addLine(to: CGPoint(x: g.size.width, y: y0)) }
                    .stroke(SX.muted.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Text("0%").sx(.axis).foregroundStyle(SX.muted).position(x: 10, y: y0 - 9).opacity(pct ? 1 : 0)
                if !stock.isEmpty {
                    SXLineShape(v: stock, lo: lo, hi: hi).trim(from: 0, to: drawn || reduce ? 1 : 0)
                        .stroke(SX.muted, style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                }
                SXAreaShape(v: mine, lo: lo, hi: hi, base: 0).fill(c.opacity(0.1)).opacity(fill || reduce ? 1 : 0)
                SXLineShape(v: mine, lo: lo, hi: hi).trim(from: 0, to: drawn || reduce ? 1 : 0)
                    .stroke(c, style: StrokeStyle(lineWidth: 2.75, lineCap: .round, lineJoin: .round))
                if let i = sel {
                    Rectangle().fill(SX.ink).frame(width: 1, height: g.size.height).position(x: x(i), y: g.size.height / 2)
                    Circle().fill(c).frame(width: 9, height: 9).position(x: x(i), y: yOf(mine[i]))
                } else if drawn || reduce {
                    if let l = stock.last { Circle().fill(SX.muted).frame(width: 6, height: 6).position(x: g.size.width, y: yOf(l)) }
                    Circle().fill(c.opacity(0.2)).frame(width: 20, height: 20).position(x: g.size.width, y: yOf(mine.last ?? 0))
                    Circle().fill(c).frame(width: 9, height: 9).position(x: g.size.width, y: yOf(mine.last ?? 0))
                }
            }
            .frame(width: r.width, height: r.height)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in sel = min(s.pts.count - 1, max(0, Int((v.location.x / max(1, g.size.width) * Double(n)).rounded()))) }
                .onEnded { _ in sel = nil })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your position " + (s.made < 0 ? "down " : "made ") + dollars(s.made) + " since \(s.fromDay)"
            + (pct ? String(format: ", %.1f percent, the stock %.1f percent", s.you ?? 0, s.stock ?? 0) : ""))
    }

    /// Month names under the chart where a month starts, the last day at the right.
    private var axis: some View {
        GeometryReader { g in
            let n = max(1, s.pts.count - 1)
            let starts = s.pts.indices.filter { $0 > 0 && s.pts[$0].d.prefix(7) != s.pts[$0 - 1].d.prefix(7) }
            ZStack(alignment: .topLeading) {
                Text(s.fromDay).sx(.axis).foregroundStyle(SX.muted).fixedSize().position(x: 18, y: 7)
                ForEach(starts, id: \.self) { i in
                    let x = g.size.width * Double(i) / Double(n)
                    if x > 60 && x < g.size.width - 60 {
                        Text(day(s.pts[i].d).prefix(3)).sx(.axis).foregroundStyle(SX.muted).fixedSize().position(x: x, y: 7)
                    }
                }
                Text(s.toDay).sx(.axis.weighted(.bold)).foregroundStyle(SX.ink).fixedSize().position(x: g.size.width - 18, y: 7)
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    private func stat(_ l: String, _ v: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(l).sx(.tiny).foregroundStyle(SX.muted)
            Text(dollars(v)).sx(.value).foregroundStyle(tone(v)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(l), \(v < 0 ? "down" : "up") \(dollars(v))")
    }
}

/// The calls week by week: a bar a week (kept in full green, kept part outlined, lost red and down), this week dashed;
/// tap a week to read it; then this week so far against pace.
private struct SXWeeksCard: View {
    let t: String
    let w: SXPage.Weeks
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var pick: Int?
    @State private var grown = false
    @State private var filled = false

    private var full: Int { w.weeks.filter { $0.g == "full" }.count }
    private var part: Int { w.weeks.filter { $0.g == "part" }.count }
    private var lost: Int { w.weeks.filter { $0.g == "lost" }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SXCardHead(t: t, title: "Calls, week by week", right: "Since \(w.from)")
            if !w.weeks.isEmpty {
                HStack(spacing: 12) {
                    keyItem(SX.up, outline: false, "\(full) Kept in full")
                    keyItem(SX.up, outline: true, "\(part) Kept part")
                    keyItem(SX.down, outline: false, "\(lost) Lost")
                }
                bars.frame(height: 136)
                months
                panel
            }
            if let n = w.now {
                if !w.weeks.isEmpty { Rectangle().fill(SX.line).frame(height: 1) }
                soFar(n)
            }
            SXSourceLine(kind: "sunny", text: w.src)
        }
        .modifier(SXPageCard())
        .onScrollVisibilityChange(threshold: 0.2) { v in
            guard v, !grown else { return }
            grown = true
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.9).delay(0.35)) { filled = true }
        }
    }

    private func keyItem(_ c: Color, outline: Bool, _ s: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(outline ? c.opacity(0.12) : c)
                .overlay { if outline { RoundedRectangle(cornerRadius: 3).strokeBorder(c, lineWidth: 1.5) } }
                .frame(width: 11, height: 11)
            Text(s).sx(.tiny).foregroundStyle(SX.ink)
        }
    }

    /// Up from a baseline for what was kept, down for what was lost, one scale for both. The baseline sits at 92 of 136
    /// unless the losses are the bigger side; then it rises so the biggest loss fits (at most to a third of the way down).
    private var bars: some View {
        GeometryReader { g in
            let cols = w.weeks.count + (w.now == nil ? 0 : 1), room = g.size.height - 8
            let maxUp = (w.weeks.map(\.kept) + [w.now?.kept ?? 0]).map { max(0, $0) }.max() ?? 0
            let maxDn = (w.weeks.map(\.kept) + [w.now?.kept ?? 0]).map { max(0, -$0) }.max() ?? 0
            let share = maxUp + maxDn > 0 ? maxUp / (maxUp + maxDn) : 1
            let base = 4 + room * min(88.0 / 128, max(1.0 / 3, share))
            let up = base - 4, down = g.size.height - base - 4
            let per = max(maxUp / max(1, up), maxDn / max(1, down), 1e-9)
            let step = g.size.width / Double(max(1, cols))
            ZStack(alignment: .topLeading) {
                Rectangle().fill(SX.line).frame(width: g.size.width, height: 1).position(x: g.size.width / 2, y: base)
                ForEach(Array(w.weeks.enumerated()), id: \.element.fri) { i, x in
                    let h = max(3, abs(x.kept) / per) * (grown || reduce ? 1 : 0), c = x.g == "lost" ? SX.down : SX.up
                    Button { withAnimation(.smooth(duration: 0.25)) { pick = pick == i ? nil : i } } label: {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(x.g == "part" ? c.opacity(0.14) : c)
                            .overlay { if x.g == "part" { RoundedRectangle(cornerRadius: 3).strokeBorder(c, lineWidth: 1.5) } }
                            .frame(width: 15, height: h)
                            .opacity(pick == nil || pick == i ? 1 : 0.4)
                            .frame(width: step, height: g.size.height, alignment: .top)
                            .offset(y: x.kept < 0 ? base : base - h)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .position(x: step * (Double(i) + 0.5), y: g.size.height / 2)
                    .animation(reduce ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.6).delay(0.2 + Double(i) * 0.035), value: grown)
                    .accessibilityLabel("Week to \(x.day), " + (x.g == "lost" ? "lost \(dollars(x.kept))" : "kept \(dollars(x.kept)) of \(dollars(x.sold))")
                        + (x.g == "full" ? ", in full" : ""))
                }
                if let n = w.now {
                    let h = max(3, abs(n.kept) / per) * (grown || reduce ? 1 : 0), c = n.kept < 0 ? SX.down : SX.up
                    RoundedRectangle(cornerRadius: 3).strokeBorder(c, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .frame(width: 15, height: h)
                        .position(x: step * (Double(cols) - 0.5), y: n.kept < 0 ? base + h / 2 : base - h / 2)
                        .animation(reduce ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.6).delay(0.2 + Double(cols - 1) * 0.035), value: grown)
                        .accessibilityLabel("This week so far, " + (n.kept < 0 ? "behind \(dollars(n.kept))" : "kept \(dollars(n.kept))"))
                }
            }
        }
    }

    /// The first week's date, a month name where a month starts, "This week" under the dashed bar.
    private var months: some View {
        GeometryReader { g in
            let cols = w.weeks.count + (w.now == nil ? 0 : 1), step = g.size.width / Double(max(1, cols))
            ZStack(alignment: .topLeading) {
                ForEach(Array(w.weeks.enumerated()), id: \.element.fri) { i, x in
                    let first = i == 0, starts = i > 0 && x.fri.prefix(7) != w.weeks[i - 1].fri.prefix(7)
                    if (first || starts) && (w.now == nil || i < cols - 2) {
                        Text(first ? x.day : String(x.day.prefix(3))).sx(.axis).foregroundStyle(SX.muted).fixedSize()
                            .position(x: max(18, step * (Double(i) + 0.5)), y: 7)
                    }
                }
                if w.now != nil {
                    Text("This week").sx(.axis.weighted(.bold)).foregroundStyle(SX.ink).fixedSize()
                        .position(x: min(g.size.width - 26, step * (Double(cols) - 0.5)), y: 7)
                }
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    /// The picked week, or the weeks shown all together.
    private var panel: some View {
        let x = pick.map { w.weeks[$0] }
        let kept = w.weeks.reduce(0) { $0 + $1.kept }, sold = w.weeks.reduce(0) { $0 + $1.sold }
        let lostUsd = w.weeks.filter { $0.kept < 0 }.reduce(0) { $0 + $1.kept }
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let x {
                    Text("Week to \(x.day)").sx(.question).foregroundStyle(SX.ink)
                    Text(x.kept < 0 ? "Lost \(dollars(x.kept)) on \(dollars(x.sold)) sold." :
                         "Kept \(dollars(x.kept)) of \(dollars(x.sold)) sold, \(Int((x.kept / max(1, x.sold) * 100).rounded()))%.")
                        .sx(.source).foregroundStyle(SX.mutedOnTile)
                } else {
                    Text("Last \(w.weeks.count) week\(w.weeks.count == 1 ? "" : "s")").sx(.question).foregroundStyle(SX.ink)
                    Text("Net \(kept < 0 ? "lost" : "kept") \(dollars(kept)) of \(dollars(sold)) sold. Tap a week to read it.")
                        .sx(.source).foregroundStyle(SX.mutedOnTile).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                if let x {
                    Text(dollars(x.kept)).sx(.panelAmount).foregroundStyle(tone(x.kept))
                } else if lost > 0 {
                    Text(dollars(lostUsd)).sx(.panelAmount).foregroundStyle(SX.down)
                    Text("lost in \(lost) week\(lost == 1 ? "" : "s")").sx(.source).foregroundStyle(SX.mutedOnTile)
                } else {
                    Text(dollars(kept)).sx(.panelAmount).foregroundStyle(SX.up)
                }
            }
            .fixedSize()
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .frame(minHeight: 64)
        .background(SX.fill, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    /// This week so far: a bar to the share kept, a tick at pace.
    private func soFar(_ n: SXPage.WeekNow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week so far").sx(.question).foregroundStyle(SX.ink)
                Spacer(minLength: 8)
                Text(n.kept < 0 ? "\(dollars(n.kept)) behind · \(-n.pct)% lost" : "\(dollars(n.kept)) kept · \(n.pct)%")
                    .sx(.question).foregroundStyle(tone(n.kept))
            }
            GeometryReader { g in
                let k = Double(max(0, min(100, n.pct))) / 100
                ZStack(alignment: .leading) {
                    Capsule().fill(SX.track)
                    Capsule().fill(SX.up).frame(width: g.size.width * k * (filled || reduce ? 1 : 0))
                    if let pc = n.pace {
                        Rectangle().fill(SX.ink).frame(width: 2, height: 14).position(x: g.size.width * min(1, max(0, pc / 100)), y: 4)
                    }
                }
            }
            .frame(height: 8)
            if let pc = n.pace {
                Text("The tick is pace: \(Int(pc.rounded()))% kept by now")
                    .sx(.source).foregroundStyle(SX.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
