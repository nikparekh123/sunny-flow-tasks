//
//  SunnyNewCards.swift
//  Sunny — the five cards on the New page.
//  cards/news-lead.md · analyst-action.md · median-target.md ·
//  earnings-guidance.md · the-drift.md
//
//  ⚠ A RATING CHANGE TAKES NO DIRECTION INK, AND NEITHER DOES A COUNT OF THEM.
//  Red in this deck is money the book lost; an analyst's opinion is not that.
//  The target pair is --ink like a strike, the WORD carries direction, and the
//  drift bar is --ink on --wash. An earlier build shipped `buy → hold` in
//  --loss-text and it read as the position losing money.
//
//  ⚠ AND THAT IS WHAT FREES THE 5px DOT for the one thing here worth a colour:
//  the vendor's importance flag. When the flag is absent the SLOT STAYS, so
//  every row's ticker sits on one left edge.
//

import SwiftUI

/// The shared shell. Every card on this page is free height, 21 inside.
private struct NewCard<Content: View>: View {
    let name: String
    var shadow: [SunnyShadow] = S.shadowCard
    @ViewBuilder let body_: () -> Content

    var body: some View {
        body_()
            .frame(width: S.content)
            .background(S.paper)
            .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
            .sunnyShadow(shadow)
            .monospacedDigit()
            .measure(name)
    }
}

// MARK: - 1 · the news lead

/// ⚠ ONE SLOT, THREE STATES — never three card types. Press release, article,
/// or the statement. And the card NEVER SPEAKS FOR THE STORY: the name's state
/// sits below a rule with the ticker labelling it, because `Shares −7.4%` under
/// a headline joins two things nothing in the data joins.
struct SunnyNewsLead: View {
    let lead: NewsLead?
    let filtered: Int
    let onChip: () -> Void
    let chipLabel: String

    var body: some View {
        /* The lead is the only card on this page above --shadow-card. */
        NewCard(name: "news-lead", shadow: S.shadowCardL) {
            VStack(alignment: .leading, spacing: 0) {
                if let lead {
                    Link(destination: URL(string: lead.url) ?? URL(string: "https://polygon.io")!) {
                        VStack(alignment: .leading, spacing: S.gap5 + 4) {
                            HStack(spacing: S.gap4) {
                                /* ⚠ A PRESS RELEASE OUTRANKS AN ARTICLE — 19% of
                                   the feed and close to 100% on topic — so the
                                   KIND is printed. The only kind marker on the
                                   page. */
                                if lead.kind == "press release" {
                                    Text("PRESS RELEASE")
                                        .font(S.inter(S.t11, S.wSemiN))
                                        .tracking(S.track(S.t11, S.lsNew))
                                        .foregroundStyle(S.update)
                                }
                                Text(ago(lead.hours).uppercased())
                                    .font(S.inter(S.t11, S.wSemiN))
                                    .tracking(S.track(S.t11, S.lsNew))
                                    .foregroundStyle(S.mute)
                                Spacer(minLength: 0)
                                Text("\u{2197}")
                                    .font(S.inter(S.t13, S.wMidSmN))
                                    .foregroundStyle(S.mute2)
                            }
                            .sunnyLineBox(S.t11)
                            Text(lead.title)
                                .font(S.inter(S.t26, S.wLightN))
                                .tracking(S.track(S.t26, -0.03))
                                .lineSpacing(S.t26 * 0.25)
                                .foregroundStyle(S.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(lead.publisher)
                                .font(S.inter(S.t13, S.wMidSmN))
                                .foregroundStyle(S.mute2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(S.padNewsLead)
                    }
                    .buttonStyle(.plain)

                    if let st = lead.state {
                        Rectangle().fill(S.ruleColor).frame(height: 1)
                            .padding(.horizontal, S.padNewX)
                        HStack(alignment: .firstTextBaseline, spacing: S.seamGap) {
                            Text("\(lead.ticker) TODAY")
                                .font(S.inter(S.t11, S.wSemiN))
                                .tracking(S.track(S.t11, S.lsNew))
                                .foregroundStyle(S.mute)
                            Text(stateLine(st))
                                .font(S.inter(S.t13, S.wMidSmN))
                                .foregroundStyle(S.mute2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(S.padStateRow)
                    }
                } else {
                    /* ⚠ THE STATEMENT STATE IS A SENTENCE WITH A NUMBER IN IT —
                       never a void and never an illustration. */
                    VStack(alignment: .leading, spacing: S.gap7) {
                        Text("TODAY")
                            .font(S.inter(S.t11, S.wSemiN))
                            .tracking(S.track(S.t11, S.lsNew))
                            .foregroundStyle(S.mute)
                        Text("Nothing about your names.")
                            .font(S.inter(S.t26, S.wLightN))
                            .tracking(S.track(S.t26, -0.03))
                            .foregroundStyle(S.ink)
                        HStack(spacing: S.gap6) {
                            Text("\(filtered) filtered")
                                .font(S.inter(S.t14, S.wMidSmN))
                                .foregroundStyle(S.mute2)
                            SunnyExpandChip(label: chipLabel, tap: onChip)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 24, leading: S.padNewX,
                                        bottom: 24, trailing: S.padNewX))
                }
            }
        }
    }

    /// Spot first, always. The technicals are the name's own state, not the
    /// story's consequence.
    private func stateLine(_ s: NameState) -> String {
        var out = [sPrice(s.spot)]
        if let r = s.rsi { out.append("RSI \(r)") }
        if let v = s.vs200 {
            out.append("\(sPct(abs(v))) \(v < 0 ? "under" : "over") its 200-day")
        }
        return out.joined(separator: " \u{00B7} ")
    }
}

// MARK: - 2 · the analyst action

struct SunnyAnalystCard: View {
    let a: AnalystAction

    var body: some View {
        NewCard(name: "action-\(a.ticker)-\(a.date)") {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: S.rungGap) {
                    HStack(spacing: S.gap4) {
                        /* ⚠ THE SLOT ALWAYS EXISTS. Empty when the vendor did
                           not flag it, so every ticker sits on one left edge. */
                        Circle().fill(a.importance >= 5 ? S.warn : .clear)
                            .frame(width: 5, height: 5)
                        Text("\(a.ticker) \u{00B7} \(a.state)".uppercased())
                            .font(S.inter(S.t11, S.wSemiN))
                            .tracking(S.track(S.t11, S.lsNew))
                            .foregroundStyle(S.mute)
                        Spacer(minLength: 0)
                        Text(dayLabel(a.date).uppercased())
                            .font(S.inter(S.t11, S.wSemiN))
                            .tracking(S.track(S.t11, S.lsNew))
                            .foregroundStyle(S.mute)
                    }
                    .sunnyLineBox(S.t11)
                    HStack(alignment: .center, spacing: S.gap6) {
                        /* ⚠ --ink IN EVERY CASE, INCLUDING A DOWNGRADE. */
                        Text(pair)
                            .font(S.inter(S.t26, S.wSemiN))
                            .tracking(S.track(S.t26, -0.03))
                            .foregroundStyle(S.ink)
                            .sunnyLineBox(S.t26)
                            .fixedSize()
                        VStack(alignment: .trailing, spacing: S.supportLineGap) {
                            Text(ratingWords)
                                .font(S.inter(S.t13, S.wMidSmN))
                                .foregroundStyle(S.mute2)
                                .lineLimit(1)
                            /* ⚠ THE FIRM DROPS ITS SUFFIX AND THE ANALYST HIS
                               FIRST NAME. At full length the line truncated to
                               `Truist Securities · J…` and `RBC Capital ·
                               Piral…`, which loses the analyst entirely — the
                               half of the pair that identifies the person. The
                               sheet's own reference is `Truist · Civello`. */
                            Text([shortFirm(a.firm), a.analyst.map(surname)]
                                    .compactMap { $0 }.joined(separator: " \u{00B7} "))
                                .font(S.inter(S.t13, S.wMidSmN))
                                .foregroundStyle(S.mute2)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(S.padAction)

                /* ⚠ AN INSIGHT IS NEVER ITS OWN SECTION. It arrives only
                   attached to a rating, so it sits inside that rating's card
                   under a rule. This is the only place in the product where a
                   vendor's prose is printed, and it is printed because we could
                   not write a better one — never paraphrased, never truncated
                   mid-clause. */
                if let ins = a.insight {
                    Rectangle().fill(S.ruleColor).frame(height: 1)
                        .padding(.horizontal, S.padNewX)
                    VStack(alignment: .leading, spacing: S.gap4 + 1) {
                        Text("\u{201C}\(ins.text)\u{201D}")
                            .font(S.inter(S.t15, S.wMidSmN))
                            .lineSpacing(S.t15 * 0.5)
                            .foregroundStyle(S.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(ins.firm)\u{2019}s note")
                            .font(S.inter(S.t13, S.wMidSmN))
                            .foregroundStyle(S.mute2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(S.padInsight)
                }
            }
        }
    }

    private var pair: String {
        guard let p = a.prev, let n = a.now, p > 0 || n > 0 else { return a.rating.capitalized }
        /* `47 → 42`, the sheet's own form. Cents on a strike that has none cost
           four glyphs of a 26px figure and say nothing. */
        return "\(tight(p)) \u{2192} \(tight(n))"
    }
    private var ratingWords: String {
        a.previousRating == a.rating || a.previousRating.isEmpty
            ? "\(a.rating), held" : "\(a.previousRating) \u{2192} \(a.rating)"
    }
}

/// ⚠ A RESTATEMENT IS STILL AN ACTION. Five of last week's ten were
/// restatements, and hiding them makes the section look quieter than the feed
/// is — so the rest are printed as rows, not dropped.
struct SunnyActionList: View {
    let rows: [AnalystAction]

    var body: some View {
        NewCard(name: "action-rest") {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Rectangle().fill(S.ruleColor).frame(height: 1) }
                    HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
                        Text(r.ticker)
                            .font(S.inter(S.t14, S.wSemiN))
                            .foregroundStyle(S.ink)
                            .frame(width: S.targetTickerSlot, alignment: .leading)
                        /* ⚠ THE PAIR DROPS NEEDLESS CENTS HERE. The slot is 76
                           and `84.00 → 95.00` measured past it and truncated to
                           `84.00 → …`; the sheet's own example is `47 → 42`. A
                           strike that is a whole number prints whole. */
                        Text(r.prev != nil && r.now != nil
                             ? "\(tight(r.prev!)) \u{2192} \(tight(r.now!))" : r.rating.capitalized)
                            .font(S.inter(S.t14, S.wSemiN))
                            .foregroundStyle(S.ink)
                            /* ⚠ 84, NOT THE SHEET'S 76. The reference rows are
                               two-digit strikes (`47 → 42`); this book holds
                               three-digit ones, and `185 → 190` measured past
                               76 and truncated to `185 →…`. A slot is sized to
                               the widest string it must hold, not to the
                               widest one the example happened to have. */
                            .frame(width: 84, alignment: .leading)
                            .lineLimit(1)
                        /* Same suffix rule as the card: at full length this
                           truncated to `target raised · Wolfe Rese…`. */
                        Text("\(r.state) \u{00B7} \(shortFirm(r.firm))")
                            .font(S.inter(S.t13, S.wMidSmN))
                            .foregroundStyle(S.mute2)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 14)
                }
            }
            .padding(EdgeInsets(top: 6, leading: S.padNewX, bottom: 8, trailing: S.padNewX))
        }
    }
}

// MARK: - 3 · the median target

/// ⚠ ON EVERY STATE OF THE PAGE, with that state's own numbers. It is a
/// standing fact, not an arrival: on a dead week it and the drift are the page.
struct SunnyTargetCard: View {
    let t: TargetBlock

    var body: some View {
        NewCard(name: "median-target") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: S.seamGap) {
                    HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                        Text("MEDIAN TARGET")
                            .font(S.inter(S.t11, S.wSemiN))
                            .tracking(S.track(S.t11, S.lsNew))
                            .foregroundStyle(S.mute)
                        Text("\(t.window) days")
                            .font(S.inter(S.t13, S.wMidSmN))
                            .foregroundStyle(S.mute2)
                    }
                    Spacer(minLength: 0)
                    /* ⚠ NO ROW FOR AN UNRATED INSTRUMENT. TLT is a fund and
                       nobody rates it; this count is the whole disclosure. An
                       explanatory row for an absent thing is a row about the
                       pipeline, not the book. */
                    Text("\(t.covered) OF \(t.of)")
                        .font(S.inter(S.t11, S.wSemiN))
                        .tracking(S.track(S.t11, S.lsNew))
                        .foregroundStyle(S.mute)
                }
                .padding(S.padTargetHead)

                VStack(spacing: 0) {
                    ForEach(Array(t.rows.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { Rectangle().fill(S.ruleColor).frame(height: 1) }
                        VStack(alignment: .leading, spacing: S.supportLineGap) {
                            HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
                                /* Ticker and target are the same size and weight
                                   — the name is a figure too. Hierarchy inside
                                   the row is position, not weight. */
                                Text(r.ticker)
                                    .font(S.inter(S.t14, S.wSemiN))
                                    .foregroundStyle(S.ink)
                                    .frame(width: S.targetTickerSlot, alignment: .leading)
                                /* A median target has no cents worth printing —
                                   the sheet's own reference row is `340`. */
                                Text(tight(r.target))
                                    .font(S.inter(S.t14, S.wSemiN))
                                    .foregroundStyle(S.ink)
                                    .frame(width: S.targetFigSlot, alignment: .leading)
                                /* ⚠ ONE DENOMINATOR, NAMED. The spot is printed
                                   beside it so the percentage is auditable. */
                                Text("\(r.upside.map { signedPct($0) } ?? "\u{2014}") on \(sPrice(r.spot))")
                                    .font(S.inter(S.t13, S.wMidSmN))
                                    .foregroundStyle(S.mute2)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .lineLimit(1)
                            }
                            /* ⚠ THE SECOND LINE IS THE DISAGREEMENT, and it is
                               why the drift card is gone. A median hides both
                               the spread and the dissent: NKE's 47 sits in a
                               23-to-75 range and LEN has seven of ten analysts
                               under the price. The dissent takes the sole
                               emphasis on the line because it is the only part
                               that argues against the row above it. */
                            HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
                                Text("\(tight(r.lo)) to \(tight(r.hi))")
                                    .font(S.inter(S.t13, S.wMidSmN))
                                    .foregroundStyle(S.mute2)
                                    .frame(width: S.targetTickerSlot + S.targetFigSlot + S.gap6,
                                           alignment: .leading)
                                Text(belowLine(r))
                                    .font(S.inter(S.t13, r.below > 0 ? S.wSemiN : S.wMidSmN))
                                    .foregroundStyle(r.below > 0 ? S.mute : S.mute2)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, S.targetRowPad)
                    }
                }
                .padding(EdgeInsets(top: 0, leading: S.padNewX, bottom: 6, trailing: S.padNewX))
            }
        }
    }
}

// MARK: - 4 · earnings & guidance

/// ⚠ ROWS, NOT TILES — THEY ARE CONDITIONS, NOT ANSWERS. A date and a bound are
/// things that are true until they change; a tile grid says "compare these".
struct SunnyEarningsCard: View {
    let e: EarningsBlock

    var body: some View {
        NewCard(name: "earnings-guidance") {
            VStack(spacing: 0) {
                ForEach(Array(e.rows.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Rectangle().fill(S.ruleColor).frame(height: 1) }
                    HStack(alignment: .top, spacing: S.gap6) {
                        Text(r.ticker)
                            .font(S.inter(S.t14, S.wSemiN))
                            .foregroundStyle(S.ink)
                            .frame(width: S.targetTickerSlot, alignment: .leading)
                        VStack(alignment: .leading, spacing: S.gap2) {
                            line(r)
                            if let s = r.support {
                                /* ⚠ THE ONLY RED IS A COLLISION THE BOOK KNOWS
                                   ABOUT, and the test is direction-aware: the
                                   same date inside a long put is protection. */
                                Text(s.text)
                                    .font(S.inter(S.t13, S.wMidSmN))
                                    .foregroundStyle(s.red ? S.lossText : S.mute2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if r.kind == "guidance" {
                                Text(guidanceSupport(r))
                                    .font(S.inter(S.t13, S.wMidSmN))
                                    .foregroundStyle(S.mute2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 15)
                }
            }
            .padding(EdgeInsets(top: 6, leading: S.padNewX, bottom: 8, trailing: S.padNewX))
        }
    }

    /// ⚠ THE COUNTDOWN IS THE BOLD, because it is the part that changes.
    @ViewBuilder private func line(_ r: EarningsBlock.Row) -> some View {
        if r.kind == "earnings", let d = r.days, let dt = r.line {
            (Text("Reports \(shortDate(String(dt.dropFirst(8)))), ")
                + Text("\(d) days").fontWeight(.semibold))
                .font(S.inter(S.t14, S.wMidSmN))
                .foregroundStyle(S.ink)
                .fixedSize(horizontal: false, vertical: true)
        } else if let lo = r.lo, let hi = r.hi {
            (Text("\(r.period ?? "") revenue ")
                + Text("\(bn(lo))\u{2013}\(bn(hi))").fontWeight(.semibold))
                .font(S.inter(S.t14, S.wMidSmN))
                .foregroundStyle(S.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// ⚠ A GUIDANCE FIGURE CARRIES ITS BASIS AND BOTH BOUNDS, and an absent
    /// guide is stated rather than omitted.
    private func guidanceSupport(_ r: EarningsBlock.Row) -> String {
        var out = [r.notes ?? "Guidance"]
        if let d = r.date { out.append(shortDate(d)) }
        out.append(r.method ?? "GAAP")
        out.append("guidance is quarterly")
        return out.joined(separator: " \u{00B7} ")
    }
    private func bn(_ v: Double) -> String {
        v >= 1e9 ? "$\(String(format: "%.2f", v / 1e9))bn"
                 : "$\(String(format: "%.0f", v / 1e6))m"
    }
}

/// `none under the price` reads as a fact; `0 of 16 below` reads as a hole in
/// the data. The count only earns digits when there is dissent to count.
private func belowLine(_ r: TargetBlock.Row) -> String {
    r.below == 0 ? "none under the price"
                 : "\(r.below) of \(r.n) under the price"
}

// MARK: - 3b · the room

/// ⚠ ONE DOT IS ONE ANALYST, and the roster barely moves between snapshots, so
/// pressing play reads as firms changing their minds rather than as a
/// different crowd walking in. That only works because the server counts FIRMS
/// and not publications; a trailing window of publications ran BABA at 2, 11,
/// 4, 4 and the animation was a reshuffle.
///
/// ⚠ STANCE IS THE ONE OPINION THIS DECK COLOURS. Everywhere else red is a
/// loss and blue is a gain on money. An analyst being bearish is neither, so
/// the card carries its own three and a legend naming them.
struct SunnyRoomCard: View {
    let r: RoomBlock
    @State private var snap: Int
    @State private var playing = false
    @State private var timer: Timer?

    /// ⚠ VERIFICATION ONLY, same reason as `-page` and `-scrollTo` on the
    /// shell: the touch bridge is dead, so a chip cannot be tapped. `-roomSnap
    /// 0` opens on the oldest snapshot, which is the only way to prove the
    /// scrubber selects anything. It does NOT prove the tap target or the
    /// transition, only that each snapshot renders its own numbers.
    private static var argSnap: Int? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-roomSnap"), i + 1 < a.count,
              let v = Int(a[i + 1]) else { return nil }
        return v
    }

    init(r: RoomBlock) {
        self.r = r
        _snap = State(initialValue: Self.argSnap ?? max(0, r.snaps - 1))
    }

    private var labels: [String] { r.rows.first?.snaps.map(\.label) ?? [] }
    private var live: Int { min(snap, (r.rows.first?.snaps.count ?? 1) - 1) }

    var body: some View {
        NewCard(name: "the-room") {
            VStack(alignment: .leading, spacing: 0) {
                head
                controls
                legend
                VStack(spacing: 0) {
                    ForEach(r.rows) { row in
                        line(row)
                    }
                    bookLine
                }
                .padding(EdgeInsets(top: 0, leading: S.padNewX, bottom: 6, trailing: S.padNewX))
            }
        }
        .onDisappear { stop() }
    }

    private var head: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.seamGap) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                Text("THE ROOM")
                    .font(S.inter(S.t11, S.wSemiN))
                    .tracking(S.track(S.t11, S.lsNew))
                    .foregroundStyle(S.mute)
                Text(labels.indices.contains(live) ? labels[live] : "")
                    .font(S.inter(S.t13, S.wMidSmN))
                    .foregroundStyle(S.ink)
            }
            Spacer(minLength: 0)
            /* TLT is a fund. Nobody has ever set a target on it, so it has no
               room, and this count is the whole disclosure. */
            Text("\(r.covered) OF \(r.of)")
                .font(S.inter(S.t11, S.wSemiN))
                .tracking(S.track(S.t11, S.lsNew))
                .foregroundStyle(S.mute)
        }
        .padding(EdgeInsets(top: 19, leading: S.padNewX, bottom: 11, trailing: S.padNewX))
    }

    private var controls: some View {
        HStack(spacing: 6) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, l in
                Button {
                    stop()
                    withAnimation(.easeInOut(duration: 0.5)) { snap = i }
                } label: {
                    Text(l)
                        .font(S.inter(S.t12, S.wSemiN))
                        .tracking(S.track(S.t12, 0.02))
                        .foregroundStyle(i == live ? S.paper : S.mute)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(Capsule().fill(i == live ? S.ink : S.roomChip))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Button { playing ? stop() : play() } label: {
                Text(playing ? "Stop" : "Play")
                    .font(S.inter(S.t12, S.wSemiN))
                    .foregroundStyle(S.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(S.paper))
                    .overlay(Capsule().stroke(S.roomEdge, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 0, leading: S.padNewX, bottom: 11, trailing: S.padNewX))
    }

    private var legend: some View {
        HStack(spacing: 13) {
            key("bearish", S.roomBear)
            key("neutral", S.roomNeu)
            key("bullish", S.roomBull)
        }
        .padding(EdgeInsets(top: 0, leading: S.padNewX, bottom: 12, trailing: S.padNewX))
    }

    private func key(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: S.roomDot, height: S.roomDot)
            Text(t.uppercased())
                .font(S.inter(S.t11, S.wSemiN))
                .tracking(S.track(S.t11, S.lsRoom))
                .foregroundStyle(S.mute2)
        }
    }

    @ViewBuilder private func line(_ row: RoomBlock.Row) -> some View {
        let s = row.snaps[live]
        let prev = live > 0 ? row.snaps[live - 1] : nil
        let d = prev.map { s.bear - $0.bear }
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: S.seamGap) {
                Text(row.ticker)
                    .font(S.inter(S.t14, S.wSemiN))
                    .foregroundStyle(S.ink)
                    .frame(width: S.targetTickerSlot, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    /* ⚠ THE SENTENCE NAMES THE PRICE IT COUNTED AGAINST, and
                       that price is the snapshot's own close. Carrying today's
                       spot backwards would restate history against a number
                       that did not exist yet. */
                    Text(s.bear > 0
                         ? "\(s.bear) bearish, under \(sPrice(s.spot))"
                         : "nobody under \(sPrice(s.spot))")
                        .font(S.inter(S.t13, s.bear > 0 ? S.wSemiN : S.wMidSmN))
                        .foregroundStyle(s.bear > 0 ? S.ink : S.mute2)
                    Text(deltaLine(d, prev))
                        .font(S.inter(S.t12, (d ?? 0) != 0 ? S.wSemiN : S.wMidSmN))
                        .foregroundStyle((d ?? 0) != 0 ? S.ink : S.mute2)
                }
                Spacer(minLength: 0)
            }
            dots(s)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(S.ruleColor).frame(height: 1) }
    }

    private func deltaLine(_ d: Int?, _ prev: RoomBlock.Snap?) -> String {
        guard let d, let prev else { return "first snapshot" }
        if d == 0 { return "no change since \(prev.label)" }
        return "\(d > 0 ? "+" : "\u{2212}")\(abs(d)) bearish since \(prev.label)"
    }

    /* ⚠ THE PITCH IS 11 AS DRAWN AND COMPRESSES ONLY WHEN A ROSTER WOULD RUN
       OFF THE CARD. The design was drawn against a 26-dot maximum; counting
       firms rather than publications puts NFLX at 34, which needs 386pt inside
       a 319pt column. Every other row keeps the drawn spacing exactly. */
    private func dots(_ s: RoomBlock.Snap) -> some View {
        let inner = S.content - S.padNewX * 2
        let n = max(s.total, 1)
        let need = CGFloat(n - 1) * S.roomPitch + S.roomGroupGap * 2 + S.roomDot
        let pitch = need <= inner ? S.roomPitch
            : max(S.roomDot, (inner - S.roomGroupGap * 2 - S.roomDot) / CGFloat(n - 1))
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(height: S.roomDot)
            ForEach(0..<n, id: \.self) { i in
                Circle()
                    .fill(i < s.bear ? S.roomBear
                          : i < s.bear + s.neu ? S.roomNeu : S.roomBull)
                    .frame(width: S.roomDot, height: S.roomDot)
                    .offset(x: CGFloat(i) * pitch
                            + (i >= s.bear ? S.roomGroupGap : 0)
                            + (i >= s.bear + s.neu ? S.roomGroupGap : 0))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bookLine: some View {
        let t = r.rows.reduce(into: (0, 0, 0)) { a, row in
            let s = row.snaps[live]; a.0 += s.bear; a.1 += s.neu; a.2 += s.bull
        }
        return HStack(alignment: .firstTextBaseline, spacing: S.seamGap) {
            Text("BOOK")
                .font(S.inter(S.t11, S.wSemiN))
                .tracking(S.track(S.t11, S.lsNew))
                .foregroundStyle(S.mute)
            Text("\(t.0) bearish \u{00b7} \(t.1) neutral \u{00b7} \(t.2) bullish")
                .font(S.inter(S.t13, S.wMidSmN))
                .foregroundStyle(S.ink)
            Spacer(minLength: 0)
        }
        .padding(.top, 12).padding(.bottom, 7)
        .overlay(alignment: .top) { Rectangle().fill(S.ruleColor).frame(height: 1) }
    }

    private func play() {
        stop()
        playing = true
        withAnimation(.easeInOut(duration: 0.5)) { snap = 0 }
        timer = Timer.scheduledTimer(withTimeInterval: 1.15, repeats: true) { t in
            if snap >= r.snaps - 1 { t.invalidate(); playing = false; return }
            withAnimation(.easeInOut(duration: 0.5)) { snap += 1 }
        }
    }

    private func stop() {
        timer?.invalidate(); timer = nil; playing = false
    }
}

// MARK: - 6 · the drift

/// Wrapping chip row. The design's chips flow onto a second line, which no
/// stock stack does.
private struct DriftFlow: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > w { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: w == .infinity ? x : w, height: y + rowH)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > b.minX, x + s.width > b.maxX { x = b.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

/// ⚠ THE CARD IS ABOUT THE TURN, NOT THE LEVEL. A name going 8% to 94% cuts in
/// a year has had a regime break; a name sitting at 80% for three years has
/// always been cut. They are identical on a price chart and opposite situations
/// to sell calls into, so the card states the level (the label) and the turn
/// (the verdict block) and never one alone.
///
/// ⚠ HEIGHT MUST SAY WHAT IT MEANS. A naked `82%` was unreadable in review, so
/// the plot carries `UP = ANALYSTS CUTTING`, the 50% line is the boundary where
/// cuts start outnumbering raises, and the turn is a WORD, never a delta chip.
///
/// ⚠ NO VALUE IS EVER MOVED TO MAKE A LABEL FIT. Four names finish inside
/// fourteen points. Labels de-collide by slotting at a forced pitch and reach
/// their line with a leader; the data is untouched.
struct SunnyDriftCard: View {
    let d: DriftBlock
    @State private var trend: DriftKind?          // nil is All
    @State private var ticker: String?            // nil is All names
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// ⚠ VERIFICATION ONLY, like `-page` and `-roomSnap`: the touch bridge is
    /// dead, so a chip cannot be tapped. `-driftTicker NKE` and `-driftTrend
    /// flat` open on a filtered state, which is the only way to prove the
    /// single-name case drops the spine and its readout.
    private static func arg(_ k: String) -> String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: k), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    private var rows: [DriftBlock.Row] {
        let t = trend ?? Self.arg("-driftTrend").flatMap {
            ["toward": DriftKind.toward, "away": .away, "flat": .flat][$0]
        }
        let k = ticker ?? Self.arg("-driftTicker")
        return d.rows.filter { (t == nil || $0.kind == t) && (k == nil || $0.ticker == k) }
    }
    /// Rank into the plum ramp is the row's position among the turned-bearish
    /// names of the WHOLE book, so filtering never repaints a survivor.
    private func hue(_ r: DriftBlock.Row) -> Color {
        switch r.kind {
        case .flat: return S.driftFlat
        case .away: return S.driftBack
        case .toward:
            let i = d.rows.filter { $0.kind == .toward }.firstIndex { $0.ticker == r.ticker } ?? 0
            return S.driftTurn[min(i, S.driftTurn.count - 1)]
        }
    }
    private func y(_ v: Int) -> CGFloat { S.driftPlotH * (1 - CGFloat(v) / 100) }
    private func drawable(_ r: DriftBlock.Row) -> [(Int, CGPoint)] {
        (0..<3).compactMap { i in
            guard let p = r.v[i], r.n[i] >= d.minActions else { return nil }
            return (i, CGPoint(x: [0, S.driftPlotW / 2, S.driftPlotW][i], y: y(p)))
        }
    }

    var body: some View {
        NewCard(name: "the-drift") {
            VStack(alignment: .leading, spacing: 0) {
                head
                hero
                chips
                Text("UP = ANALYSTS CUTTING")
                    .font(S.inter(S.t11, S.wSemiN))
                    .tracking(S.track(S.t11, 0.1))
                    .foregroundStyle(S.mute)
                    .padding(EdgeInsets(top: 16, leading: S.padNewX, bottom: 0, trailing: S.padNewX))
                chart
                if let m = midLine { midpoint(m) }
                verdicts
                Text(sentence)
                    .font(S.inter(S.t13, S.wMidN))
                    .lineSpacing(S.t13 * 0.5)
                    .foregroundStyle(S.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(EdgeInsets(top: 13, leading: S.padNewX, bottom: 19, trailing: S.padNewX))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { if !reduceMotion { withAnimation(.timingCurve(0.35, 0, 0.2, 1, duration: 1.15)) { drawn = true } } else { drawn = true } }
    }

    private var head: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.seamGap) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                Text("THE DRIFT")
                    .font(S.inter(S.t11, S.wSemiN))
                    .tracking(S.track(S.t11, S.lsNew))
                    .foregroundStyle(S.mute)
                Text("share of cuts")
                    .font(S.inter(S.t13, S.wMidN))
                    .foregroundStyle(S.mute2)
            }
            Spacer(minLength: 0)
            /* TLT is a fund and has never been rated. The count is the whole
               disclosure, and it follows the filter. */
            Text("\(rows.count) OF \(d.of)")
                .font(S.inter(S.t11, S.wSemiN))
                .tracking(S.track(S.t11, S.lsNew))
                .foregroundStyle(S.mute)
        }
        .padding(EdgeInsets(top: 19, leading: S.padNewX, bottom: 0, trailing: S.padNewX))
    }

    /* ⚠ DERIVED, NEVER AUTHORED. It answers before the chart is read. */
    private var hero: some View {
        let toward = rows.filter { $0.kind == .toward }.count
        let away = rows.filter { $0.kind == .away }.count
        let line: String
        if rows.isEmpty { line = "No names" }
        else if rows.count == 1, let r = rows.first, let a = r.first, let b = r.last {
            line = "\(r.ticker) \(a)% \u{2192} \(b)% cuts"
        } else if toward > 0 { line = "\(toward) name\(toward == 1 ? "" : "s") turned bearish" }
        else if away > 0 { line = "\(away) name\(away == 1 ? "" : "s") turned bullish" }
        else { line = "\(rows.count) names held their level" }
        let support: String
        if rows.count == 1, let r = rows.first {
            support = "\(r.n[2]) target moves in the past year, \(r.n.reduce(0, +)) across three"
        } else {
            let hi = rows.filter { ($0.last ?? 0) >= 50 }.count
            support = "analysts cut more than they raised on \(hi) of \(rows.count) in the past year"
        }
        return VStack(alignment: .leading, spacing: 5) {
            Text(line)
                .font(S.inter(S.t26, S.wSemiN))
                .tracking(S.track(S.t26, -0.02))
                .foregroundStyle(S.ink)
                .sunnyLineBox(S.t26)
            Text(support)
                .font(S.inter(S.t13, S.wMidN))
                .lineSpacing(S.t13 * 0.35)
                .foregroundStyle(S.mute2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 14, leading: S.padNewX, bottom: 0, trailing: S.padNewX))
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: 7) {
            DriftFlow(spacing: 6) {
                chip("All", trend == nil) { trend = nil }
                chip("Turned bearish", trend == .toward) { trend = .toward }
                chip("Turned bullish", trend == .away) { trend = .away }
                chip("No turn", trend == .flat) { trend = .flat }
            }
            DriftFlow(spacing: 6) {
                chip("All names", ticker == nil) { ticker = nil }
                ForEach(d.rows) { r in chip(r.ticker, ticker == r.ticker) { ticker = r.ticker } }
            }
        }
        .padding(EdgeInsets(top: 15, leading: S.padNewX, bottom: 0, trailing: S.padNewX))
    }

    /* ⚠ 44 THROUGH A BLEED, NEVER THROUGH PADDING. Padding would push the label
       off grid; the capsule stays the measured 23 high and the hit area grows
       around it. */
    private func chip(_ l: String, _ on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { tap() }
            replay()
        } label: {
            Text(l.uppercased())
                .font(S.inter(S.t11, S.wSemiN))
                .tracking(S.track(S.t11, S.lsRoom))
                .foregroundStyle(on ? S.paper : S.mute)
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(on ? S.ink : S.roomChip))
                .padding(.vertical, S.driftHitBleed)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: 23)
    }

    /* A filter change replays the draw-on rather than snapping the chart. */
    private func replay() {
        guard !reduceMotion else { return }
        drawn = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(.timingCurve(0.35, 0, 0.2, 1, duration: 1.15)) { drawn = true }
        }
    }
}

// MARK: - the drift · the plot

extension SunnyDriftCard {

    /* ⚠ CATMULL-ROM, CONTROL OFFSETS AT A SIXTH OF THE NEIGHBOUR SPAN, and
       every control y clamped inside the box so a curve never leaves the plot.
       Three points through a naive spline overshoots on FIS and NFLX. */
    fileprivate func curve(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard pts.count >= 2 else { return p }
        p.move(to: pts[0])
        for i in 0..<(pts.count - 1) {
            let p0 = i > 0 ? pts[i - 1] : pts[i]
            let p1 = pts[i], p2 = pts[i + 1]
            let p3 = i + 2 < pts.count ? pts[i + 2] : p2
            let cy: (CGFloat) -> CGFloat = { min(max($0, 0), S.driftPlotH) }
            p.addCurve(to: p2,
                       control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6,
                                         y: cy(p1.y + (p2.y - p0.y) / 6)),
                       control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6,
                                         y: cy(p2.y - (p3.y - p1.y) / 6)))
        }
        return p
    }

    /* ⚠ SLOTS TOP-DOWN AT A FORCED 19 PITCH, then the stack shifts up whole if
       it overruns and clamps at −2. This is what solves the collision: FIS 94,
       LEN 83, NFLX 82 and NKE 80 finish inside fourteen points and their
       labels would otherwise sit on each other. No value moves. */
    fileprivate func slots() -> [(row: DriftBlock.Row, y: CGFloat)] {
        let ordered = rows.sorted { ($0.last ?? 0) > ($1.last ?? 0) }
        var out: [(DriftBlock.Row, CGFloat)] = []
        var cursor = -CGFloat.infinity
        for r in ordered {
            let want = y(r.last ?? 0) - S.driftLabelH / 2
            let slot = max(want, cursor + S.driftPitch)
            out.append((r, slot)); cursor = slot
        }
        let over = (cursor + S.driftLabelH) - S.driftPlotH
        if over > 0 { for i in out.indices { out[i].1 -= over } }
        for i in out.indices { out[i].1 = max(-2, out[i].1) }
        return out.map { (row: $0.0, y: $0.1) }
    }

    /// The book's own line: the MEDIAN cut share per block, so one name cannot
    /// move it. With a single row there is no median, and the spine, its
    /// stations and the readout row are all absent rather than an unlabelled key.
    fileprivate var spine: [CGPoint]? {
        guard rows.count > 1 else { return nil }
        let pts: [CGPoint] = (0..<3).compactMap { i in
            let vals = rows.compactMap { r -> Int? in
                guard let p = r.v[i], r.n[i] >= d.minActions else { return nil }
                return p
            }.sorted()
            guard !vals.isEmpty else { return nil }
            let m = vals.count % 2 == 1
                ? Double(vals[vals.count / 2])
                : Double(vals[vals.count / 2 - 1] + vals[vals.count / 2]) / 2
            return CGPoint(x: [0, S.driftPlotW / 2, S.driftPlotW][i],
                           y: S.driftPlotH * (1 - m / 100))
        }
        return pts.count > 1 ? pts : nil
    }

    fileprivate var midLine: String? {
        guard rows.count > 1 else { return nil }
        let parts: [String] = (0..<3).map { i in
            let vals = rows.compactMap { r -> Int? in
                guard let p = r.v[i], r.n[i] >= d.minActions else { return nil }
                return p
            }.sorted()
            guard !vals.isEmpty else { return "\u{2013}" }
            let m = vals.count % 2 == 1
                ? Double(vals[vals.count / 2])
                : Double(vals[vals.count / 2 - 1] + vals[vals.count / 2]) / 2
            return "\(Int(m.rounded()))%"
        }
        return spine == nil ? nil : "The book itself: " + parts.joined(separator: " \u{2192} ") + " cuts"
    }

    fileprivate var sentence: String {
        rows.isEmpty
            ? "No name matches that pair of filters. Clear one to bring the chart back."
            : "Height is how often analysts cut rather than raised. Above the middle line, cuts outnumber raises."
    }

    var chart: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: S.driftLead) {
                yTicks
                plot
                labelColumn
            }
            .frame(height: S.driftPlotH)
            HStack(spacing: 0) {
                xTick("3 YRS", .leading)
                xTick("2 YRS", .center)
                xTick("PAST YR", .trailing)
            }
            .frame(width: S.driftPlotW, height: 11)
            .padding(.leading, S.driftYCol + S.driftLead)
        }
        .padding(EdgeInsets(top: 9, leading: S.padNewX, bottom: 0, trailing: S.padNewX))
    }

    private func xTick(_ t: String, _ a: Alignment) -> some View {
        Text(t)
            .font(S.inter(S.t11, S.wSemiN))
            .tracking(S.track(S.t11, 0.08))
            .foregroundStyle(S.mute2)
            .frame(maxWidth: .infinity, alignment: a)
    }

    private var yTicks: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
            tick("100%", 0); tick("50%", 78.5); tick("0%", S.driftPlotH - 11)
        }
        .frame(width: S.driftYCol, height: S.driftPlotH)
    }

    private func tick(_ t: String, _ top: CGFloat) -> some View {
        Text(t)
            .font(S.inter(S.t11, S.wSemiN))
            .tracking(S.track(S.t11, S.lsRoom))
            .foregroundStyle(S.mute2)
            /* ⚠ FIXED SIZE OR `100%` WRAPS. The sheet's 30pt column is measured
               against the string, not proposed to it; letting SwiftUI negotiate
               the width broke the tick onto two lines. */
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .offset(y: top)
    }

    private var plot: some View {
        ZStack(alignment: .topLeading) {
            /* Three axes and the boundary. The 50% line is --rule-color, NOT
               the fainter grid grey: it is a reading, not a gridline. */
            ForEach([0, 1, 2], id: \.self) { i in
                Rectangle().fill(S.ruleColor)
                    .frame(width: 1, height: S.driftPlotH)
                    .offset(x: [0, S.driftPlotW / 2, S.driftPlotW][i] - 0.5)
            }
            Rectangle().fill(S.ruleColor)
                .frame(width: S.driftPlotW, height: 1)
                .offset(y: S.driftPlotH / 2)
            if let sp = spine { spineLayer(sp) }
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                lineLayer(r, i)
            }
            leaders
        }
        .frame(width: S.driftPlotW, height: S.driftPlotH, alignment: .topLeading)
    }

    /* ⚠ EVERY LINE IS DRAWN TWICE, a blurred copy under the solid one. A glow
       on a 2px stroke is the only way depth reads at this size without a
       heavier line, and a heavier line would out-shout the spine. */
    @ViewBuilder private func lineLayer(_ r: DriftBlock.Row, _ i: Int) -> some View {
        let flat = r.kind == .flat
        let col = hue(r), w: CGFloat = flat ? 1.25 : 2, op: Double = flat ? 0.55 : 1
        let pts = drawable(r)
        let runs = contiguous(pts)
        ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
            let p = curve(run.map(\.1))
            p.trimmedPath(from: 0, to: drawn ? 1 : 0)
                .stroke(col, style: StrokeStyle(lineWidth: w + 3, lineCap: .round, lineJoin: .round))
                .opacity(0.22 * op).blur(radius: 3)
            p.trimmedPath(from: 0, to: drawn ? 1 : 0)
                .stroke(col, style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
                .opacity(op)
        }
        /* ⚠ A GAP READS AS A GAP, NEVER AS NO DATA. A dotted bridge joins the
           two known points and a dashed hollow ring sits where the thin block's
           point would have been read. Interpolating it would be an invention. */
        if runs.count > 1 || pts.count < 3 { gapMarks(r, pts, col, w, op) }
        Circle().fill(col).opacity(op)
            .frame(width: flat ? 5 : 6, height: flat ? 5 : 6)
            .offset(x: S.driftPlotW - (flat ? 2.5 : 3), y: y(r.last ?? 0) - (flat ? 2.5 : 3))
            .opacity(drawn ? 1 : 0)
        /* The 2-yr block is a STATION every line passes through, not a bend. */
        if let mid = r.v[1], r.n[1] >= d.minActions {
            let rad: CGFloat = flat ? 2.4 : 3.4
            Circle().fill(S.paper)
                .overlay(Circle().stroke(col, lineWidth: flat ? 1 : 1.6))
                .frame(width: rad * 2, height: rad * 2)
                .opacity(flat ? 0.6 : 1)
                .offset(x: S.driftPlotW / 2 - rad, y: y(mid) - rad)
                .opacity(drawn ? 1 : 0)
        }
    }

    private func contiguous(_ pts: [(Int, CGPoint)]) -> [[(Int, CGPoint)]] {
        var out: [[(Int, CGPoint)]] = []
        var run: [(Int, CGPoint)] = []
        for p in pts {
            if let l = run.last, p.0 != l.0 + 1 { if run.count > 1 { out.append(run) }; run = [] }
            run.append(p)
        }
        if run.count > 1 { out.append(run) }
        return out
    }

    @ViewBuilder private func gapMarks(_ r: DriftBlock.Row, _ pts: [(Int, CGPoint)],
                                       _ col: Color, _ w: CGFloat, _ op: Double) -> some View {
        ForEach(Array(zip(pts.dropLast(), pts.dropFirst())).indices, id: \.self) { i in
            let a = pts[i], b = pts[i + 1]
            if b.0 != a.0 + 1 {
                Path { p in p.move(to: a.1); p.addLine(to: b.1) }
                    .stroke(col, style: StrokeStyle(lineWidth: 1, dash: [1, 4]))
                    .opacity(0.45)
                ForEach((a.0 + 1)..<b.0, id: \.self) { m in
                    let x = [0, S.driftPlotW / 2, S.driftPlotW][m]
                    let f = (x - a.1.x) / (b.1.x - a.1.x)
                    Circle().fill(S.paper)
                        .overlay(Circle().stroke(col, style: StrokeStyle(lineWidth: 1, dash: [1.6, 1.6])))
                        .frame(width: 7, height: 7)
                        .offset(x: x - 3.5, y: a.1.y + (b.1.y - a.1.y) * f - 3.5)
                }
            }
        }
        ForEach(pts.indices, id: \.self) { i in
            Circle().fill(col).opacity(op).frame(width: 5, height: 5)
                .offset(x: pts[i].1.x - 2.5, y: pts[i].1.y - 2.5)
        }
    }

    @ViewBuilder private func spineLayer(_ pts: [CGPoint]) -> some View {
        curve(pts).trimmedPath(from: 0, to: drawn ? 1 : 0)
            .stroke(S.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .shadow(color: S.ink.opacity(0.28), radius: 1.6, x: 0, y: 1)
        ForEach(pts.indices, id: \.self) { i in
            let rad: CGFloat = i == 1 ? 4.5 : 3.5
            Circle().fill(S.ink)
                .overlay(Circle().stroke(S.paper, lineWidth: i == 1 ? 2 : 1.5))
                .frame(width: rad * 2, height: rad * 2)
                .offset(x: pts[i].x - rad, y: pts[i].y - rad)
                .opacity(drawn ? 1 : 0)
        }
    }

    /* A 3pt stub at the line's TRUE y, then a diagonal to the slot centre. The
       label carries no turn chip: dropping it bought the plot 20pt and removed
       the review's main confusion. */
    private var leaders: some View {
        ForEach(slots(), id: \.row.id) { s in
            let endY = y(s.row.last ?? 0)
            Path { p in
                p.move(to: CGPoint(x: S.driftPlotW, y: endY))
                p.addLine(to: CGPoint(x: S.driftPlotW + 3, y: endY))
                p.addLine(to: CGPoint(x: S.driftPlotW + S.driftLead, y: s.y + S.driftLabelH / 2))
            }
            .stroke(hue(s.row), lineWidth: 1)
            .opacity(s.row.kind == .flat ? 0.22 : 0.38)
        }
    }

    private var labelColumn: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(slots(), id: \.row.id) { s in
                Text("\(s.row.ticker) \(s.row.last ?? 0)%")
                    .font(S.inter(S.t13, s.row.kind == .flat ? S.wMidN : S.wSemiN))
                    .foregroundStyle(s.row.kind == .flat ? S.mute2 : hue(s.row))
                    .lineLimit(1).fixedSize()
                    .frame(height: S.driftLabelH, alignment: .leading)
                    .offset(y: s.y)
            }
        }
        .frame(width: S.driftLabelCol, height: S.driftPlotH, alignment: .topLeading)
    }

    func midpoint(_ m: String) -> some View {
        HStack(spacing: S.gap4) {
            Capsule().fill(S.ink).frame(width: 18, height: 2.5)
            Text(m)
                .font(S.inter(S.t13, S.wSemiN))
                .foregroundStyle(S.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 15, leading: S.padNewX, bottom: 0, trailing: S.padNewX))
    }

    /* A group with no members DOES NOT RENDER. Three blocks at rest, one when
       filtered — never an empty heading standing for an absent thing. */
    var verdicts: some View {
        VStack(alignment: .leading, spacing: 0) {
            group(.toward, "Turned bearish", S.driftTurn[0])
            group(.away, "Turned bullish", S.driftBack)
            group(.flat, "No turn", S.mute2)
        }
        .padding(EdgeInsets(top: 14, leading: S.padNewX, bottom: 0, trailing: S.padNewX))
    }

    @ViewBuilder private func group(_ k: DriftKind, _ label: String, _ dot: Color) -> some View {
        let set = rows.filter { $0.kind == k }
        if !set.isEmpty {
            HStack(alignment: .top, spacing: 9) {
                Circle().fill(dot).frame(width: 7, height: 7).padding(.top, 4)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(label)
                            .font(S.inter(S.t13, S.wSemiN))
                            .foregroundStyle(S.ink).lineLimit(1)
                        Text("\(set.count)")
                            .font(S.inter(S.t11, S.wSemiN))
                            .tracking(S.track(S.t11, S.lsRoom))
                            .foregroundStyle(S.mute2)
                    }
                    Text(detail(k, set))
                        .font(S.inter(S.t13, S.wMidN))
                        .lineSpacing(S.t13 * 0.4)
                        .foregroundStyle(S.mute2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 11)
            .overlay(alignment: .top) { Rectangle().fill(S.ruleColor).frame(height: 1) }
        }
    }

    private func detail(_ k: DriftKind, _ set: [DriftBlock.Row]) -> String {
        set.map { r in
            k == .flat
                ? "\(r.ticker) " + ((r.last ?? 0) >= 60 ? "mostly cuts"
                                    : (r.last ?? 0) >= 40 ? "mixed" : "mostly raises")
                : "\(r.ticker) \(r.first ?? 0)% \u{2192} \(r.last ?? 0)%"
        }.joined(separator: ", ")
    }
}

// MARK: - shared

/// The firm without its category word. `Truist Securities` is Truist to
/// everyone who reads it, and the suffix is what pushed the analyst's name off
/// the line. Only the suffix goes: `TD Cowen`, `Wells Fargo` and `Morgan
/// Stanley` are two-word names, not a name and a suffix.
func shortFirm(_ s: String) -> String {
    let drop: Set<String> = ["securities", "research", "capital", "group", "partners",
                             "advisors", "advisory", "markets", "inc", "inc.", "llc",
                             "&", "co", "co.", "financial", "bank", "equity"]
    let w = s.split(separator: " ").map(String.init)
    let kept = w.prefix { !drop.contains($0.lowercased()) }
    return kept.isEmpty ? s : kept.joined(separator: " ")
}

/// The analyst's surname. A full name is two words in a slot that fits one.
func surname(_ s: String) -> String {
    s.split(separator: " ").last.map(String.init) ?? s
}

/// A price with no cents when it has none — `47`, not `47.00`.
func tight(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
}

func signedPct(_ v: Double) -> String {
    (v < 0 ? "\u{2212}" : "+") + String(format: "%.1f%%", abs(v))
}

/// `2026-08-26` → `TUE 26`.
func dayLabel(_ iso: String) -> String {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "America/New_York")
    guard let d = f.date(from: iso) else { return iso }
    let o = DateFormatter(); o.dateFormat = "EEE d"; o.timeZone = f.timeZone
    return o.string(from: d)
}
