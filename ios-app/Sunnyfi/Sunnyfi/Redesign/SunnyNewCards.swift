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
                        HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
                            /* Ticker and target are the same size and weight —
                               the name is a figure too. Hierarchy inside the row
                               is position, not weight. */
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

// MARK: - 5 · the drift

/// ⚠ NEVER EMPTY, THEREFORE ALWAYS LAST. The one block with something to say in
/// every state, which is why a dead week still has a page.
///
/// ⚠ THE BAR IS A SHARE OF ACTIONS, NEVER A PRICE, and it is --ink: 185 lowers
/// is a fact about analysts, not a loss in the book. A red bar would say the
/// position is down, which this card does not know.
struct SunnyDriftCard: View {
    let d: DriftBlock

    var body: some View {
        NewCard(name: "the-drift") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: S.seamGap) {
                    HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                        Text("SHARE LOWERED")
                            .font(S.inter(S.t11, S.wSemiN))
                            .tracking(S.track(S.t11, S.lsNew))
                            .foregroundStyle(S.mute)
                        Text("since \(sinceLabel)")
                            .font(S.inter(S.t13, S.wMidSmN))
                            .foregroundStyle(S.mute2)
                    }
                    Spacer(minLength: 0)
                    /* Same disclosure as the target card, and the same absence:
                       TLT is a fund, so nobody has ever set a target on it. */
                    Text("\(d.blocks.count) OF 9")
                        .font(S.inter(S.t11, S.wSemiN))
                        .tracking(S.track(S.t11, S.lsNew))
                        .foregroundStyle(S.mute)
                }
                .padding(S.padTargetHead)

                VStack(spacing: 0) {
                    ForEach(Array(d.blocks.enumerated()), id: \.element.id) { i, b in
                        if i > 0 { Rectangle().fill(S.ruleColor).frame(height: 1) }
                        row(b)
                    }
                }
                .padding(.horizontal, S.padNewX)

                /* ⚠ EXACTLY ONE MEDIAN SENTENCE ON THE CARD, on the name whose
                   drift is the argument. Eight of them would be a second table.
                   Standing below the rows it has to NAME its name; inline under
                   one block it did not. */
                if let b = d.blocks.first(where: { $0.ticker == d.sentenceOn }),
                   b.medians.count >= 2,
                   let f = b.medians.first, let l = b.medians.last {
                    (Text("\(b.ticker)\u{2019}s median target has walked ")
                        + Text("\(tight(f.median)) \u{2192} \(tight(l.median))").fontWeight(.semibold)
                        + Text(" since \(f.year)."))
                        .font(S.inter(S.t15, S.wMidSmN))
                        .lineSpacing(S.t15 * 0.4)
                        .foregroundStyle(S.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(EdgeInsets(top: 16, leading: S.padNewX,
                                            bottom: 0, trailing: S.padNewX))
                }

                Text("Every target an analyst set on these names since \(sinceLabel), counted.")
                    .font(S.inter(S.t13, S.wMidSmN))
                    .lineSpacing(S.t13 * 0.45)
                    .foregroundStyle(S.mute2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(EdgeInsets(top: 12, leading: S.padNewX,
                                        bottom: 20, trailing: S.padNewX))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sinceLabel: String {
        d.blocks.compactMap { $0.medians.first?.year }.min() ?? "2023"
    }

    /* ⚠ ONE LINE PER NAME. Eight full blocks would run past 800pt and the
       section is the page's floor, not its argument. The bar is a FIXED width
       so the eight rows compare against each other and not against the width
       of whatever sits beside them. */
    @ViewBuilder private func row(_ b: DriftBlock.Block) -> some View {
        HStack(alignment: .center, spacing: S.gap6) {
            Text(b.ticker)
                .font(S.inter(S.t14, S.wSemiN))
                .foregroundStyle(S.ink)
                .frame(width: S.targetTickerSlot, alignment: .leading)
            Text("\(b.pct)%")
                .font(S.inter(S.t14, S.wSemiN))
                .foregroundStyle(S.ink)
                .frame(width: S.driftPctSlot, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(S.wash)
                Capsule().fill(S.ink)
                    .frame(width: max(2, S.driftBarW * CGFloat(b.pct) / 100))
            }
            .frame(width: S.driftBarW, height: S.driftBarH)
            /* ⚠ A COUNT AND A PAIR, OR NOTHING. The percentage is only legible
               next to the counts it came from. */
            Text("\(b.cuts) of \(b.actions)")
                .font(S.inter(S.t13, S.wMidSmN))
                .foregroundStyle(S.mute2)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(1)
        }
        .padding(.vertical, S.driftRowPad)
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
