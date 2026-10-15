//
//  TodaySection.swift
//  Sunny
//
//  Block 08 · quick nav (Book · Risk · Income · Results) and the section
//  titles it scrolls to. Block 09 · Today: SPY · QQQ · IWM · VIX cards
//  (three in view, swipe for VIX, tap switches % and $), Overnight under
//  them 4:00 to 7:00, futures-implied prices 7:00 to 9:30 with the bell at
//  9:30 (handoff 24), Last week in their place from Friday's close to
//  Monday 4:00. New York time throughout.
//

import SwiftUI

// MARK: - 08 · Quick nav and section titles

struct SunnyQuickNav: View {
    let onTap: (HomeRouter.Section) -> Void
    var body: some View {
        HStack(spacing: 6) {
            ForEach(HomeRouter.Section.allCases) { s in
                Button { onTap(s) } label: {
                    Text(s.rawValue)
                        .sType(SType(size: 13, weight: 600, line: 13, tracking: 0), tabular: false)
                        .foregroundStyle(S.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .contentShape(Capsule().inset(by: -6))
                }
                .buttonStyle(SPressStyle())
                .accessibilityHint("Scrolls to \(s.rawValue)")
            }
        }
        .padding(.horizontal, S.margin)
    }
}

/// "Today", "Book", "Risk", "Income", "Results": Display 28/32, 800, 16 above.
struct SunnySectionTitle: View {
    let title: String
    var body: some View {
        Text(title)
            .sType(.sectionHead, tabular: false)
            .foregroundStyle(S.ink)
            .padding(.top, 16)
            .padding(.horizontal, S.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The small up or down triangle beside a change (10 × 7.5).
struct SArrow: View {
    let up: Bool
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 5, y: 0)); p.addLine(to: CGPoint(x: 10, y: 7.5)); p.addLine(to: CGPoint(x: 0, y: 7.5)); p.closeSubpath()
        }
        .frame(width: 10, height: 7.5)
        .rotationEffect(.degrees(up ? 0 : 180))
        .accessibilityHidden(true)
    }
}

// MARK: - 09 · Today

struct SunnyToday: View {
    let home: HomePayload
    @State private var dollars = DebugPreset.bool("today.usd")
    /// The 9:30 bell: cards rolled to their first prints, left to right.
    @State private var rolled: Set<String> = []
    @State private var captionGone = false         // faded out
    @State private var captionClosed = false       // its 26 pt closed
    @Environment(\.accessibilityReduceMotion) private var reduce

    private enum Mode { case cards, preMarket, futures, lastWeek }

    private var mode: Mode {
        let t = MarketClock.ny(SClock.now()), m = t.minutes
        let holiday = MarketClock.closure(t.date, home.calendar)?.kind == "closed" && t.weekday != 1 && t.weekday != 7
        if holiday { return .cards }
        let weekend = (t.weekday == 6 && m >= 16 * 60) || t.weekday == 7 || t.weekday == 1 || (t.weekday == 2 && m < 4 * 60)
        if weekend, home.lastWeek != nil { return .lastWeek }
        let trading = MarketClock.isTradingDay(t.date, weekday: t.weekday, home.calendar)
        if trading, m >= 4 * 60, m < 7 * 60 { return .preMarket }
        // 7:00 to 9:30: the cards show where futures point (handoff 24).
        if trading, m >= 7 * 60, m < 9 * 60 + 30 { return .futures }
        return .cards
    }

    /// What a card shows. Futures: the 16:00 close times (future now / its 16:00
    /// price), change against that close. A future that is stale (Yahoo is ~10
    /// min behind; past 20 min, Nik) or has no base, and VIX (no VX on Yahoo),
    /// keep the card at its close with no pill. Before the open, moves run from
    /// the last regular close (Yahoo's previous close is then the day before).
    struct Quote { let price: Double; let prev: Double; let pill: String? }

    private func quote(_ t: Tape, futures: Bool) -> Quote {
        let close = t.regular ?? t.prevClose ?? t.price ?? 0
        if futures && !rolled.contains(t.symbol) {
            if let f = home.futures?.first(where: { $0.card == t.symbol }), let now = f.price, let base = f.base, base > 0,
               let at = f.at.flatMap(Self.iso), SClock.now().timeIntervalSince(at) <= 20 * 60 {
                return Quote(price: close * now / base, prev: close, pill: f.pill)
            }
            return Quote(price: close, prev: t.prevClose ?? close, pill: nil)
        }
        let price = t.price ?? close
        let preOpen = t.state == "PRE" || futures
        return Quote(price: price, prev: preOpen ? close : (t.prevClose ?? price), pill: nil)
    }
    private static func iso(_ s: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]; return f.date(from: s)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let md = mode
            VStack(alignment: .leading, spacing: 20) {
                if md == .lastWeek, let lw = home.lastWeek {
                    LastWeekCard(lw: lw).padding(.horizontal, S.margin)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        cards(futures: md == .futures)
                        let implied = md == .futures && home.indices.contains { quote($0, futures: true).pill != nil }
                        if implied || (md == .futures && !captionClosed && !rolled.isEmpty) {
                            Text("Implied by futures · since the 16:00 close")
                                .sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false)
                                .foregroundStyle(S.muted)
                                .opacity(captionGone ? 0 : 1)
                                .padding(.top, 10)
                                .frame(height: captionClosed ? 0 : 26, alignment: .top)
                                .clipped()
                                .padding(.horizontal, S.margin)
                        }
                    }
                    if md == .preMarket, !home.overnight.isEmpty {
                        OvernightCard(tapes: home.overnight).padding(.horizontal, S.margin)
                    }
                }
            }
            .task(id: md == .futures) { if md == .futures { await bell() } }
        }
    }

    // MARK: The 9:30 bell

    /// Waits for 9:30:00 New York, then rolls each card to its first regular
    /// print, left to right 70 ms apart; the pills go; the caption fades, then
    /// its space closes so the row below moves up once. Back from the
    /// background more than 60 s late, or Reduce Motion: a plain swap.
    private func bell() async {
        rolled = []; captionGone = false; captionClosed = false
        var wait = Self.secondsToBell(SClock.now())
        #if DEBUG && targetEnvironment(simulator)
        if let d = DebugPreset.double("today.bell") { wait = d }       // audits: the clock is pinned
        #endif
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        guard !Task.isCancelled else { return }
        let late = -Self.secondsToBell(SClock.now())
        let symbols = home.indices.map(\.symbol)
        if reduce || (late > 60 && DebugPreset.double("today.bell") == nil) {
            withAnimation(reduce ? .easeOut(duration: 0.2) : nil) { rolled = Set(symbols) }
            captionGone = true; captionClosed = true
            return
        }
        for (i, s) in symbols.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * S.stagger) {
                withAnimation(S.standard(0.4)) { _ = rolled.insert(s) }
            }
        }
        withAnimation(.easeOut(duration: 0.2)) { captionGone = true }
        withAnimation(S.standard(0.35).delay(0.5)) { captionClosed = true }
    }

    private static func secondsToBell(_ now: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let c = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: now)
        let s = Double((c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)) + Double(c.nanosecond ?? 0) / 1e9
        return 9.5 * 3600 - s
    }

    private func cards(futures: Bool) -> some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(home.indices) { t in
                    IndexCard(tape: t, q: quote(t, futures: futures), phase: futures && !rolled.contains(t.symbol),
                              dollars: dollars) {
                        withAnimation(S.standard(S.tap)) { dollars.toggle() }
                    }
                    .containerRelativeFrame(.horizontal, count: 3, spacing: 8)
                    .id(t.symbol)
                }
            }
            .scrollTargetLayout()
        }
        .onAppear { if DebugPreset.bool("today.vix") { proxy.scrollTo("^VIX", anchor: .trailing) } }
        .contentMargins(.horizontal, S.margin, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        }
    }
}

struct IndexCard: View {
    let tape: Tape
    let q: SunnyToday.Quote
    /// True while the card shows the futures morning; flipping it at the bell
    /// rolls the old number out and the first print in.
    let phase: Bool
    let dollars: Bool
    let onTap: () -> Void

    private var level: Bool { tape.symbol.hasPrefix("^") }

    var body: some View {
        let price = q.price, prev = q.prev
        let diff = price - prev, pct = prev != 0 ? diff / prev * 100 : 0
        let up = diff >= 0, tone = up ? S.green : S.red
        let shown = dollars ? (level ? F.level(diff) : "$" + F.level(diff)) : F.pct(pct)
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(tape.label).sType(.ticker, tabular: false)
                    if let p = q.pill {
                        // ES · NQ · RTY: 18 tall, radius 9, 0 6, S.yellow, ink, 11/11 Bold.
                        Text(p).sType(SType(size: 11, weight: 700, line: 11, tracking: 0), tabular: false)
                            .foregroundStyle(S.ink)
                            .padding(.horizontal, 6).frame(height: 18)
                            .background(Capsule().fill(S.yellow))
                            .transition(.scale(scale: 0.6).combined(with: .opacity).animation(.easeOut(duration: 0.2)))
                    }
                }
                Spacer(minLength: 0)
                ZStack(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text((level ? "" : "$") + F.level(price))
                            .sType(.price)
                            .contentTransition(.numericText(value: price))
                        HStack(spacing: 4) {
                            SArrow(up: up).foregroundStyle(tone)
                            Text(shown).sType(.change).foregroundStyle(tone)
                                .contentTransition(.numericText(value: dollars ? diff : pct))
                        }
                    }
                    .id(phase)
                    .transition(.bellRoll)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(S.ink)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 145)
            .background(RoundedRectangle(cornerRadius: S.rChip, style: .continuous).fill(S.paper))
            .overlay(RoundedRectangle(cornerRadius: S.rChip, style: .continuous).strokeBorder(S.line, lineWidth: 1))
            .animation(.smooth(duration: S.roll), value: price)
        }
        .buttonStyle(SPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tape.label) \((level ? "" : "$") + F.level(price)), \(up ? "up" : "down") \(shown)"
                            + (q.pill.map { ", implied by \($0) futures" } ?? ""))
        .accessibilityHint(dollars ? "Shows percent" : "Shows dollars")
    }
}

/// The bell's roll: the old number rises 19 pt and fades, the new one comes up
/// from 19 pt below (0.4 s S.ease.standard, opacity 0.3 s).
private struct BellShift: ViewModifier {
    let y: CGFloat
    func body(content: Content) -> some View { content.offset(y: y) }
}
extension AnyTransition {
    static var bellRoll: AnyTransition {
        .asymmetric(
            insertion: AnyTransition.modifier(active: BellShift(y: 19), identity: BellShift(y: 0)).animation(S.standard(0.4))
                .combined(with: AnyTransition.opacity.animation(.easeOut(duration: 0.3))),
            removal: AnyTransition.modifier(active: BellShift(y: -19), identity: BellShift(y: 0)).animation(S.standard(0.4))
                .combined(with: AnyTransition.opacity.animation(.easeOut(duration: 0.3))))
    }
}

struct OvernightCard: View {
    let tapes: [Tape]
    private static let short = ["Nikkei 225": "Nikkei", "DAX": "DAX", "Nifty 50": "Nifty", "Shanghai Composite": "Shanghai"]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Overnight").sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false)
                Spacer()
                Text("Since US close").sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false)
                    .foregroundStyle(S.muted)
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(tapes.filter { $0.changePct != nil }) { t in
                    let v = t.changePct ?? 0
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Self.short[t.label] ?? t.label)
                            .sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false)
                            .foregroundStyle(S.muted).lineLimit(1)
                        HStack(spacing: 4) {
                            SArrow(up: v >= 0)
                            Text(F.pct(v)).sType(.change)
                        }
                        .foregroundStyle(v >= 0 ? S.green : S.red)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(t.label) \(v >= 0 ? "up" : "down") \(F.pct(v))")
                }
            }
        }
        .foregroundStyle(S.ink)
        .padding(.vertical, 16).padding(.horizontal, 20)
        .background(RoundedRectangle(cornerRadius: S.rChip, style: .continuous).fill(S.paper))
        .overlay(RoundedRectangle(cornerRadius: S.rChip, style: .continuous).strokeBorder(S.line, lineWidth: 1))
    }
}

struct LastWeekCard: View {
    let lw: LastWeek
    private static let scale = 3.0     // one ±3% scale for every row

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Last week").sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false)
                Spacer()
                Text(range).sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
            }
            .padding(.bottom, 12)
            ForEach(lw.rows) { r in
                row(r.symbol, move: r.changePct ?? 0, priced: r.pricedMovePct, close: r.close)
            }
            if let v = lw.vix { row("VIX", move: v.changePct ?? 0, priced: nil, close: v.close, isVix: true) }
            Text("Grey band · the move options priced in for the week. Dot · what happened.")
                .sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false)
                .foregroundStyle(S.muted)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
        }
        .foregroundStyle(S.ink)
        .padding(.top, 16).padding(.bottom, 12).padding(.horizontal, 20)
        .background(RoundedRectangle(cornerRadius: S.rChip, style: .continuous).fill(S.paper))
        .overlay(RoundedRectangle(cornerRadius: S.rChip, style: .continuous).strokeBorder(S.line, lineWidth: 1))
    }

    /// "Oct 5 to 9" · "Sep 28 to Oct 2"
    private var range: String {
        let to = DeckBuilder.lastTrading(onOrBefore: lw.to)
        return lw.from.prefix(7) == to.prefix(7) ? "\(F.day(lw.from)) to \(DeckBuilder.dayNum(to))" : "\(F.day(lw.from)) to \(F.day(to))"
    }

    @ViewBuilder private func row(_ t: String, move: Double, priced: Double?, close: Double?, isVix: Bool = false) -> some View {
        let up = move >= 0, tone = up ? S.green : S.red
        HStack(spacing: 12) {
            Text(t).sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false).frame(width: 44, alignment: .leading)
            if let e = priced {
                GeometryReader { g in
                    let w = g.size.width, s = Self.scale
                    let lo = (0.5 - e / s * 0.5) * w, bw = e / s * w
                    let dot = max(0.03, min(0.97, 0.5 + move / s * 0.5)) * w
                    ZStack(alignment: .topLeading) {
                        Capsule().fill(S.surface).frame(height: 2).offset(y: 9)
                        Capsule().fill(S.line).frame(width: max(0, bw), height: 8).offset(x: lo, y: 6)
                        Rectangle().fill(S.muted).frame(width: 1, height: 12).offset(x: w / 2 - 0.5, y: 4)
                        Circle().fill(tone).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(S.paper, lineWidth: 2))
                            .offset(x: dot - 5, y: 5)
                    }
                }
                .frame(height: 20)
            } else {
                Text("Closed at \(isVix ? F.level(close ?? 0) : "$" + F.level(close ?? 0))")
                    .sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false)
                    .foregroundStyle(S.muted).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    SArrow(up: up)
                    Text(F.pct(move, places: 1)).sType(.change)
                }
                .foregroundStyle(tone)
                Text(priced.map { "±\(String(format: "%.1f", $0))% priced" } ?? "on the week")
                    .sType(SType(size: 12, weight: 500, line: 14, tracking: 0), tabular: false)
                    .foregroundStyle(S.muted).lineLimit(1)
            }
            .frame(width: 76, alignment: .trailing)
        }
        .frame(height: 52)
        .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(t) \(up ? "up" : "down") \(F.pct(move, places: 1)) on the week" + (priced.map { ", options priced \(String(format: "%.1f", $0)) percent" } ?? ""))
    }
}
