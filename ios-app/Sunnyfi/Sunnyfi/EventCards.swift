//
//  EventCards.swift
//  Sunnyfi
//
//  Portfolio update cards — the swipeable deck on Home, directly below
//  the value header. Recreates the design handoff (Claude design ·
//  May 31). Spec lives in design_handoff_update_cards/README.md.
//
//  Layout per card (350 × 244pt, radius 12, padding 22-22-20):
//    [kick]                                            [glyph chip]
//      ↑ tone-colored uppercase                          ↑ 38pt, tone-tinted
//
//    [spacer pushes hero into lower third]
//
//    [title] (optional)
//    [hero — money OR status]
//    [sub]
//    [foot → action pill right-aligned]
//
//  Three tones:
//    • Neutral (no class) — neon strip, kick, glyph, pill; money hero is neon
//    • Amber               — warn strip/kick/glyph/pill; status hero is FG1 white
//    • Coral               — neg strip/kick/glyph/pill; money hero is coral
//

import SwiftUI

// MARK: - Model

enum CardTone {
    case neutral, amber, coral

    var stroke: Color {
        switch self {
        case .neutral: return .theme.neon
        case .amber:   return .theme.warn
        case .coral:   return .theme.neg
        }
    }

    /// Color of money hero. Amber cards intentionally render the hero
    /// in bone-white because amber heroes communicate "be aware", not
    /// "this is a P&L number".
    var heroColor: Color {
        switch self {
        case .neutral: return .theme.neon
        case .amber:   return .theme.fg1
        case .coral:   return .theme.neg
        }
    }
}

enum EventHero {
    /// Big mono number + short caption — used when the headline IS a figure.
    case money(value: String, caption: String)
    /// Sentence with one emphasized inline span — used on amber heads-up cards.
    case status(prefix: String, em: String, suffix: String = "")
}

struct EventCard: Identifiable, Hashable {
    let id = UUID()
    let tone: CardTone
    let glyph: String          // SF Symbol name
    let kick: String           // becomes uppercased
    let title: String?         // optional
    let hero: EventHero
    let sub: String
    let actionLabel: String
    let goTicker: String?      // tap action target (open ticker / nil = no-nav)

    static func == (lhs: EventCard, rhs: EventCard) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Deriver

enum EventCardDeriver {
    static func cards(
        companies: [Company],
        allTrades: [OptionTradeRow] = [],
        allGreeks: [OptionGreeksRow] = [],
        now: Date = Date()
    ) -> [EventCard] {
        var out: [EventCard] = []

        // 0. Macro events within 5 days
        for ev in MacroEvents.upcomingWithin(5, from: now) {
            let dte = AppDates.daysUntil(ev.date, from: now) ?? 0
            let when = dte == 0 ? "today" : dte == 1 ? "tomorrow" : "in \(dte)d"
            let positionsAffected = companies.count
            out.append(EventCard(
                tone: .amber,
                glyph: "calendar.badge.exclamationmark",
                kick: "\(ev.name) · \(when) \(ev.time)",
                title: ev.summary,
                hero: .status(
                    prefix: "Covered calls — IV elevated ",
                    em: "12–18%",
                    suffix: ""
                ),
                sub: "Post-event crush 15–25% typical · positions affected: \(positionsAffected)",
                actionLabel: "See affected positions",
                goTicker: nil
            ))
        }

        // 1. Assignment booking — short option ITM, DTE ≤ 5
        for c in companies {
            for leg in c.legs where leg.kind != .stock && leg.side == .short {
                guard let dte = leg.dte, dte <= 5, dte >= 0, let strike = leg.strike else { continue }
                let isITM = leg.kind == .call ? c.spot >= strike : c.spot <= strike
                guard isITM else { continue }
                let qty = Int(abs(leg.qty))
                let premium = leg.avg * Double(qty) * 100
                let stockBasis = c.legs.first(where: { $0.kind == .stock })?.avg ?? 0
                let booked: Double = {
                    if leg.kind == .call && stockBasis > 0 {
                        return premium + (strike - stockBasis) * 100 * Double(qty)
                    }
                    return premium
                }()
                let when = dte == 0 ? "Today" : dte == 1 ? "Tomorrow" : "\(dte)d"
                let assetWord = leg.kind == .call ? "calls" : "puts"
                let assetVerb = leg.kind == .call ? "called away" : "assigned"
                out.append(EventCard(
                    tone: .neutral,
                    glyph: "checkmark.seal.fill",
                    kick: "Assignment · \(when)",
                    title: "\(c.ticker) · \(qty) \(assetWord) assigning",
                    hero: .money(value: fmtMoney(booked, sign: true), caption: "booked"),
                    sub: "at $\(Int(strike)) strike · \(qty * 100) shares \(assetVerb)",
                    actionLabel: "Open \(c.ticker)",
                    goTicker: c.ticker
                ))
            }
        }

        // 2. Earnings ahead — within 7 days
        for c in companies {
            guard let iso = c.earningsDate,
                  let dte = AppDates.daysUntil(iso, from: now),
                  (0...7).contains(dte) else { continue }
            let when = dte == 0 ? "today" : dte == 1 ? "tomorrow" : "in \(dte) days"
            let shortLeg = c.legs.first(where: { $0.kind != .stock && $0.side == .short })
            let heroEm: String = {
                guard let leg = shortLeg, abs(leg.qty) > 0 else { return "no short legs" }
                let perContractDelta = abs(leg.delta / (abs(leg.qty) * 100))
                return "Δ" + String(format: "%.2f", perContractDelta)
            }()
            out.append(EventCard(
                tone: .amber,
                glyph: "doc.text.magnifyingglass",
                kick: "Earnings · \(when.uppercased())",
                title: "\(c.ticker) reports \(when)",
                hero: .status(
                    prefix: "",
                    em: heroEm,
                    suffix: shortLeg != nil ? " short call open" : " — no short calls"
                ),
                sub: "IV crush playbook · 15–25% post-print typical",
                actionLabel: "Open \(c.ticker)",
                goTicker: c.ticker
            ))
        }

        // 3. Big move — held ticker |dayPct| ≥ 2.5%
        for c in companies where abs(c.dayPct) >= 2.5 {
            let isDown = c.dayPct < 0
            let dollarMove = c.spot * (c.dayPct / 100)
            let pctStr = (isDown ? "−" : "+") + String(format: "%.1f%%", abs(c.dayPct))
            out.append(EventCard(
                tone: isDown ? .coral : .neutral,
                glyph: isDown ? "arrow.down.right" : "arrow.up.right",
                kick: "Big move today",
                title: nil,
                hero: .money(value: pctStr, caption: "\(c.ticker) · today"),
                sub: "\(fmtMoney(dollarMove, sign: true, decimals: 2)) · spot \(fmtMoney(c.spot, decimals: 2))",
                actionLabel: "Open \(c.ticker)",
                goTicker: c.ticker
            ))
        }

        // 4. Roll candidate — short option past 80% max profit.
        // "Still open" = pooled FIFO remaining > 0, not FK-link absence
        // (the FK lies on multi-lot chains; see OptionFIFO.swift).
        let fifo = OptionFIFO.build(trades: allTrades)
        let markByTradeID: [String: Double] = Dictionary(uniqueKeysWithValues:
            allGreeks.compactMap { g in
                guard let mark = g.last_mark else { return nil }
                return (g.option_trade_id, mark)
            }
        )
        for t in allTrades where
            t.action == "open" && t.direction == "short"
            && (fifo.remainingByOpenID[t.id] ?? t.contracts) > 0.0001 {
            let mark = markByTradeID[t.id] ?? t.premium
            guard t.premium > 0 else { continue }
            let captured = (t.premium - mark) / t.premium
            if captured >= 0.80 {
                let captureBucks = (t.premium - mark) * t.contracts * 100
                let maxBucks = t.premium * t.contracts * 100
                let pctStr = "\(Int(captured * 100))%"
                out.append(EventCard(
                    tone: .neutral,
                    glyph: "arrow.triangle.2.circlepath",
                    kick: "Roll candidate",
                    title: "\(t.ticker) $\(fmtStrike(t.strike)) \(t.option_type)",
                    hero: .money(value: pctStr, caption: "of max captured"),
                    sub: "\(fmtMoney(captureBucks)) of \(fmtMoney(maxBucks)) captured · roll up + out for fresh credit?",
                    actionLabel: "Open \(t.ticker)",
                    goTicker: t.ticker
                ))
            }
        }

        // 5. MTD premium milestone
        let mtdPremium = monthToDateCredits(trades: allTrades, now: now)
        if mtdPremium > 0 {
            out.append(EventCard(
                tone: .neutral,
                glyph: "dollarsign.circle.fill",
                kick: "MTD premium",
                title: nil,
                hero: .money(value: fmtMoney(mtdPremium, sign: true), caption: "this month"),
                sub: monthProgressLine(now: now),
                actionLabel: "See performance",
                goTicker: nil
            ))
        }

        // 6. YTD pace — always-on
        let ytdPremium = yearToDateCredits(trades: allTrades, now: now)
        out.append(EventCard(
            tone: .neutral,
            glyph: "chart.line.uptrend.xyaxis",
            kick: "YTD pace",
            title: nil,
            hero: .money(value: fmtMoney(ytdPremium, sign: true), caption: "premium YTD"),
            sub: ytdPaceLine(ytd: ytdPremium, now: now),
            actionLabel: "See performance",
            goTicker: nil
        ))

        return out
    }

    // MARK: - Helpers

    private static func monthToDateCredits(trades: [OptionTradeRow], now: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? cal.timeZone
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return 0 }
        let cutoff = Fmt.ymdET.string(from: monthStart)
        return trades
            .filter { $0.action == "open" && $0.direction == "short" && String($0.trade_date.prefix(10)) >= cutoff }
            .reduce(0) { $0 + $1.premium * $1.contracts * 100 }
    }

    private static func yearToDateCredits(trades: [OptionTradeRow], now: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? cal.timeZone
        guard let yearStart = cal.date(from: cal.dateComponents([.year], from: now)) else { return 0 }
        let cutoff = Fmt.ymdET.string(from: yearStart)
        return trades
            .filter { $0.action == "open" && $0.direction == "short" && String($0.trade_date.prefix(10)) >= cutoff }
            .reduce(0) { $0 + $1.premium * $1.contracts * 100 }
    }

    private static func monthProgressLine(now: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? cal.timeZone
        let dayOfMonth = cal.component(.day, from: now)
        let range = cal.range(of: .day, in: .month, for: now) ?? 1..<32
        let totalDays = range.count
        let remaining = max(0, totalDays - dayOfMonth)
        return "Day \(dayOfMonth) of \(totalDays) · \(remaining) day\(remaining == 1 ? "" : "s") left"
    }

    private static func ytdPaceLine(ytd: Double, now: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? cal.timeZone
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: now) ?? 1
        let frac = max(0.01, Double(dayOfYear) / 365.0)
        let projected = ytd / frac
        let pctYear = Int(frac * 100)
        return "On pace for \(fmtMoney(projected)) · \(pctYear)% of year done"
    }
}

// MARK: - Card view

/// Single card matching the handoff spec (350×244, padding 22-22-20).
struct EventCardView: View {
    let card: EventCard
    let onTapAction: () -> Void

    private var fg1: Color { .theme.fg1 }
    private var fg2: Color { .theme.fg2 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Background gradient + corner glow live in the background modifier.
            cardBackground

            // Content (kick / spacer / title / hero / sub / foot)
            VStack(alignment: .leading, spacing: 0) {
                Text(card.kick.uppercased())
                    .font(.ui(size: 11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(card.tone.stroke)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.trailing, 50)                // clear glyph chip

                Spacer(minLength: 8)

                if let title = card.title {
                    Text(title)
                        .font(.ui(size: 16.5, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(fg1)
                        .lineLimit(2)
                        .padding(.bottom, 7)
                }

                hero

                Text(card.sub)
                    .font(.ui(size: 12.5))
                    .lineSpacing(2)
                    .foregroundStyle(fg2)
                    .lineLimit(3)
                    .frame(maxWidth: 268, alignment: .leading)
                    .padding(.top, 9)

                HStack(spacing: 0) {
                    Spacer()
                    actionPill
                }
                .padding(.top, 16)
            }
            .padding(EdgeInsets(top: 22, leading: 22, bottom: 20, trailing: 22))

            // Glyph chip — top-right
            glyphChip
                .padding(20)
        }
        .frame(height: 244)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Left tone strip (3pt). Inside the clipShape so the corners round with the card.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(card.tone.stroke)
                .frame(width: 3)
        }
        // Hairline on top/right/bottom (skip the left edge — strip covers it).
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.theme.hair, lineWidth: 1)
                .mask(
                    // Hide the leftmost 3pt of the stroke so the tone strip is the only thing on that edge.
                    Rectangle()
                        .padding(.leading, 3)
                )
        )
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        switch card.hero {
        case .money(let value, let caption):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(value)
                    .font(.numeric(size: 38, weight: .medium))
                    .tracking(-1.6)
                    .foregroundStyle(card.tone.heroColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(caption)
                    .font(.ui(size: 13, weight: .medium))
                    .tracking(-0.1)
                    .foregroundStyle(fg2)
            }
        case .status(let prefixT, let em, let suffixT):
            // Concatenated Text so the emphasized span renders inline.
            (
                Text(prefixT).foregroundStyle(fg1)
              + Text(em).foregroundStyle(card.tone.stroke)
                    .font(.numeric(size: 18, weight: .medium))
              + Text(suffixT).foregroundStyle(fg1)
            )
            .font(.ui(size: 18, weight: .semibold))
            .lineSpacing(3)
            .tracking(-0.2)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Glyph chip

    @ViewBuilder
    private var glyphChip: some View {
        Image(systemName: card.glyph)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(card.tone.stroke)
            .frame(width: 38, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(card.tone.stroke.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(card.tone.stroke.opacity(0.22), lineWidth: 1)
                    )
            )
    }

    // MARK: - Action pill

    @ViewBuilder
    private var actionPill: some View {
        Button(action: onTapAction) {
            HStack(spacing: 7) {
                Text(card.actionLabel)
                    .font(.ui(size: 12.5, weight: .semibold))
                Text("→")
                    .font(.numeric(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(card.tone.stroke)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                // Tone-tinted flat fill (Navi is flat — no backdrop blur).
                Capsule()
                    .fill(card.tone.stroke.opacity(0.13))
                    .overlay(
                        Capsule()
                            .strokeBorder(card.tone.stroke.opacity(0.34), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Background

    private var cardBackground: some View {
        ZStack(alignment: .topTrailing) {
            // Card tint gradient — runs 155° in the spec (top-left → bottom-right-ish).
            LinearGradient(
                stops: [
                    .init(color: Color.theme.surface.opacity(0.55), location: 0),
                    .init(color: Color.theme.page2.opacity(0.72), location: 1)
                ],
                startPoint: UnitPoint(x: 0.13, y: 0),
                endPoint:   UnitPoint(x: 0.87, y: 1)
            )

            // Corner glow — faint radial of the tone color, top-right.
            // ~9% opacity per spec.
            RadialGradient(
                colors: [card.tone.stroke.opacity(0.09), .clear],
                center: UnitPoint(x: 0.85, y: 0.15),
                startRadius: 0,
                endRadius: 140
            )
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Stack (section header + paged TabView + dots)

/// "Portfolio updates · {idx+1} / {total}" header + horizontally-paged
/// card track + tappable pager dots. One card visible per page; iOS
/// TabView's page swipe handles snap, rubber-band, and threshold.
struct EventCardStack: View {
    let cards: [EventCard]
    let onOpen: (String) -> Void

    @State private var index: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHead
            TabView(selection: $index) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { i, c in
                    EventCardView(card: c) {
                        if let t = c.goTicker { onOpen(t) }
                    }
                    .padding(.horizontal, 2)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 256)                  // 244 card + a touch of breathing room

            HStack(spacing: 6) {
                ForEach(cards.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Color.theme.neon : Color.theme.fg4)
                        .frame(width: i == index ? 14 : 5, height: 5)
                        .animation(.easeInOut(duration: 0.3), value: index)
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.42)) { index = i }
                        }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var sectionHead: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Portfolio updates")
                .font(.ui(size: 18, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(Color.theme.fg1)
            Spacer()
            // Counter — DM Mono, muted. Live-updates with the active card.
            Text("\(index + 1) / \(cards.count)")
                .font(.numeric(size: 11, weight: .medium))
                .tracking(-0.2)
                .foregroundStyle(Color.theme.fg3)
        }
    }
}
