//
//  SunnyOptionsCards.swift
//  Sunny — the three dashboard option cards.
//
//  Build sheet: OPTIONS-CARDS.md, Parts 1–3. Every measurement here is from
//  that sheet, which took them off the reference implementation. They are not
//  targets; they are what the card is.
//
//  ⚠ THE ONE RULE THE WHOLE FAMILY TURNS ON:
//     THE ACTION IS MONEYNESS. CAPTURED % IS THE MONEY.
//  In or at the money rolls; out of it goes to the next expiry. The bar says
//  what the week made or cost, and the two disagree often. `verdict` reads
//  `itm` and nothing else.
//

import SwiftUI

// MARK: - shared pieces

/// The card shell these six share: 361 wide, 22 radius, --pad-card-m.
private struct OptCard<Content: View>: View {
    let name: String
    var fixedHeight: CGFloat? = 361
    @ViewBuilder let body_: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { body_() }
            .padding(EdgeInsets(top: 17, leading: 19, bottom: 16, trailing: 19))
            .frame(width: S.content, height: fixedHeight, alignment: .top)
            .background(S.paper)
            .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
            .sunnyShadow(S.shadowCard)
            .monospacedDigit()
            .measure(name)
    }
}

private struct OptHead: View {
    let title: String, sub: String
    var right: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                Text(title).font(S.inter(S.t14, S.wBoldN))
                    .tracking(S.track(S.t14, -0.01)).foregroundStyle(S.ink)
                if !sub.isEmpty {
                    Text(sub).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
                }
            }
            Spacer(minLength: 0)
            if let right {
                Text(right).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
            }
        }
    }
}

/// ⚠ THE FOOTER IS IDENTICAL ON EVERY CARD THAT HAS ONE. Three flex:1 stats,
/// indented 0 / 16 / 16, label 10/700 uppercase over a 19/700 figure. Labels
/// are short BY MEASUREMENT: "Roll up and out" wrapped in the 100pt slot and
/// pushed the card 10pt past its L.
private struct OptFooter: View {
    struct Stat { let label: String; let value: String; let ink: Color }
    let stats: [Stat]
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(S.ruleColor).frame(height: 1)
            Spacer().frame(height: 14)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(stats.enumerated()), id: \.offset) { i, s in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(s.label.uppercased())
                            .font(S.inter(S.t10, S.wBoldN))
                            .tracking(S.track(S.t10, S.lsLabel))
                            .foregroundStyle(S.mute).lineLimit(1)
                        Text(s.value)
                            .font(S.inter(S.t19, S.wBoldN))
                            .tracking(S.track(S.t19, -0.025))
                            .foregroundStyle(s.ink).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, i == 0 ? 0 : S.statRulePad)
                }
            }
        }
    }
}

func optMoney(_ v: Int) -> String {
    let a = abs(v)
    let s = a >= 1000 ? "$\(a / 1000),\(String(format: "%03d", a % 1000))" : "$\(a)"
    return v < 0 ? "\u{2212}" + s : s
}
private func signedPctInt(_ v: Int) -> String {
    (v > 0 ? "+" : v < 0 ? "\u{2212}" : "") + "\(abs(v))%"
}

// MARK: - 1 · Roll check

/// ⚠ NOTHING HOLDS, AND NO LEG IS FILTERED. Selling weekly, every leg resolves
/// in its expiry week: in or at the money rolls, out of it goes to the next
/// expiry. There is no third state, no grey bar and no missing row — a reader
/// cannot tell a filtered card from a broken one.
///
/// ⚠ COLOUR IS THE ACTION; THE LEVEL LINES ARE GREY. A coloured line at +75 is
/// what made an earlier build contradict itself: a red "rolling" bar sitting
/// 49px above the red line it had supposedly crossed.
struct SunnyRollCheck: View {
    let book: OptionsBook
    let positions: [OptionsPosition]
    var captureLine: Int = 75
    var giveBackLine: Int = -100

    struct Bar: Identifiable {
        let id: String, ticker: String, captured: Int, itm: Bool
    }

    /* ⚠ THE LABEL CARRIES THE STRIKE ONLY WHEN IT HAS TO. The sheet's bar
       label is the ticker, which assumes one short leg per name — and Nik runs
       two on NKE deliberately ($40 × 50 and $39 × 10), so two bars arrived
       labelled `NKE` and `NKE`, indistinguishable. The strike is appended only
       for a name with more than one leg, so the common case keeps the sheet's
       form exactly and the ambiguous one stops lying. */
    private var bars: [Bar] {
        positions.flatMap { p -> [Bar] in
            let many = p.shorts.count > 1
            return p.shorts.map { s in
                Bar(id: "\(p.t)-\(s.id)",
                    ticker: many ? "\(p.t) \(s.k.formatted(.number.precision(.fractionLength(0))))" : p.t,
                    captured: s.captured, itm: s.itm)
            }
        }
    }

    /* 10% headroom past whichever is further out, the bar or the level line.
       Without it the extreme bar tops out flush against the plot edge and hides
       the line it crossed. */
    private var scale: (up: CGFloat, down: CGFloat, k: CGFloat, zero: CGFloat) {
        let vals = bars.map { CGFloat($0.captured) }
        let up = max(CGFloat(captureLine), 0, vals.max() ?? 0) * 1.1
        let down = max(CGFloat(abs(giveBackLine)), 0, -(vals.min() ?? 0)) * 1.1
        let k = S.rollPlotH / max(up + down, 1)
        return (up, down, k, up * k)
    }

    /* ⚠ THE PAGED FORM CANNOT EXIST IN THIS SHELL, and that is a fact about
       the shell rather than a fault in the sheet. The handoff escalates
       ≤5 bars → 6–10 paged → 11+ rows, and the paged form pages on a
       HORIZONTAL gesture. Our shell IS a horizontal paging ScrollView: swiping
       sideways is how you change ticker. So the card and the navigation fight
       over every drag, which is what Nik hit at six legs.

       Rows are the answer above five here. They show every leg at once with no
       gesture at all, which is what the sheet wanted paging to achieve, and the
       sheet's own reason for escalating to rows — "a card you page three times
       to read is a list pretending to be a chart" — applies at one page in a
       shell that owns the gesture. The bar form still renders at five or
       fewer, unchanged. */
    private var useRows: Bool { bars.count > 5 }

    var body: some View {
        if useRows { rowsCard } else { barsCard }
    }

    private var barsCard: some View {
        OptCard(name: "roll-check") {
            OptHead(title: "Roll check", sub: "calls sold")
            Spacer().frame(height: S.gap7)
            keyRow
            Spacer().frame(height: S.gap5)
            plot
            Spacer(minLength: S.gap7)
            OptFooter(stats: [
                .init(label: "Rolling", value: "\(book.rolling)", ink: S.loss),
                .init(label: "Next expiry", value: "\(book.nextExpiry)", ink: S.gain),
                .init(label: "Kept", value: optMoney(book.kept),
                      ink: book.kept < 0 ? S.loss : S.gain),
            ])
        }
    }

    private var keyRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
            Text("CAPTURED OF CREDIT")
                .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute)
            Spacer(minLength: 0)
            HStack(spacing: S.gap5) {
                keyDash("+\(captureLine)%")
                keyDash("\(giveBackLine)%".replacingOccurrences(of: "-", with: "\u{2212}"))
            }
        }
    }

    private func keyDash(_ t: String) -> some View {
        HStack(spacing: S.gap3) {
            Rectangle().fill(S.hair).frame(width: S.levelKey, height: S.refLine)
            Text(t).font(S.inter(S.t10, S.wBoldN))
                .tracking(S.track(S.t10, S.lsLabel)).foregroundStyle(S.mute)
        }
    }

    private var plot: some View {
        let sc = scale
        let shown = bars
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(S.ruleColor).frame(height: 1).offset(y: sc.zero)
            Rectangle().fill(S.hair).frame(height: S.refLine)
                .offset(y: sc.zero - CGFloat(captureLine) * sc.k)
            Rectangle().fill(S.hair).frame(height: S.refLine)
                .offset(y: sc.zero - CGFloat(giveBackLine) * sc.k)
            HStack(spacing: 0) {
                ForEach(shown) { b in column(b, sc) }
            }
        }
        .frame(height: S.rollPlotH + S.gap5 + 31, alignment: .top)
    }

    @ViewBuilder private func column(_ b: Bar, _ sc: (up: CGFloat, down: CGFloat, k: CGFloat, zero: CGFloat)) -> some View {
        let v = CGFloat(b.captured)
        let h = abs(v) * sc.k
        /* ⚠ AN UP BAR IS OFFSET FROM THE PLOT'S BOTTOM, A DOWN BAR FROM ITS
           TOP. One shared offset sent the down bar 15.5px past the plot floor
           into the value labels; that shipped once and was caught in review. */
        let fill = b.itm ? S.lossBar : S.gainBar
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color.clear
                RoundedRectangle(cornerRadius: S.radiusBar, style: .continuous)
                    .fill(fill)
                    .frame(width: S.rollBarW, height: max(h, 1))
                    .offset(y: v >= 0 ? sc.zero - h : sc.zero)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: S.rollPlotH)
            Spacer().frame(height: S.gap5)
            VStack(spacing: S.gap3) {
                Text(signedPctInt(b.captured))
                    .font(S.inter(S.t13, S.wSemiN))
                    .foregroundStyle(b.captured < 0 ? S.lossText : S.gainText)
                    .lineLimit(1)
                Text(b.ticker)
                    .font(S.inter(S.t12, S.wBoldN)).foregroundStyle(S.ink).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: rows

    /// Free height, one row per leg. Name and value columns are `flex: none` —
    /// the summary-lists rule, learned there when a `flex: 1` ticker slot shrank
    /// under BABA and ate the row gap.
    private var rowsCard: some View {
        let hi = max(CGFloat(captureLine), CGFloat(bars.map(\.captured).max() ?? 0)) * 1.1
        let lo = min(CGFloat(giveBackLine), CGFloat(bars.map(\.captured).min() ?? 0)) * 1.1
        let track: CGFloat = 217
        let x = { (v: CGFloat) in track * (v - lo) / max(hi - lo, 1) }
        return OptCard(name: "roll-check-rows", fixedHeight: nil) {
            OptHead(title: "Roll check", sub: "calls sold", right: "\(bars.count) legs")
            Spacer().frame(height: S.gap7)
            VStack(alignment: .leading, spacing: 5) {
                Text("CAPTURED OF CREDIT")
                    .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.mute)
                HStack(alignment: .firstTextBaseline, spacing: S.gap3) {
                    Text(optMoney(book.kept))
                        .font(S.inter(S.t30, S.wBoldN)).tracking(S.track(S.t30, -0.03))
                        .foregroundStyle(book.kept < 0 ? S.loss : S.gain)
                        .sunnyLineBox(S.t30)
                    Text("kept this week")
                        .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
                }
            }
            Spacer().frame(height: 18)
            HStack(spacing: S.gap4) {
                Color.clear.frame(width: S.progNameCol, height: 1)
                HStack {
                    Text("\(giveBackLine)%".replacingOccurrences(of: "-", with: "\u{2212}"))
                    Spacer()
                    Text("+\(captureLine)%")
                }
                .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute)
                .frame(width: track)
                Color.clear.frame(width: S.progValCol, height: 1)
            }
            .padding(.bottom, S.gap4)
            ZStack(alignment: .topLeading) {
                VStack(spacing: S.progRowGap) {
                    ForEach(bars) { b in rowFor(b, x: x, track: track) }
                }
                /* The lines live in the ROW box, so each carries the name
                   column plus its gap as an offset. */
                ForEach([("give", CGFloat(giveBackLine)), ("cap", CGFloat(captureLine))], id: \.0) { _, v in
                    Rectangle().fill(S.hair).frame(width: S.refLine)
                        .offset(x: S.progNameCol + S.gap4 + x(v), y: -4)
                        .frame(maxHeight: .infinity).padding(.bottom, -4)
                }
                Rectangle().fill(S.ruleColorStrong).frame(width: 1)
                    .offset(x: S.progNameCol + S.gap4 + x(0), y: -4)
                    .frame(maxHeight: .infinity).padding(.bottom, -4)
            }
            Spacer().frame(height: 22)
            OptFooter(stats: [
                .init(label: "Rolling", value: "\(book.rolling)", ink: S.loss),
                .init(label: "Next expiry", value: "\(book.nextExpiry)", ink: S.gain),
                .init(label: "Kept", value: optMoney(book.kept),
                      ink: book.kept < 0 ? S.loss : S.gain),
            ])
        }
    }

    @ViewBuilder private func rowFor(_ b: Bar, x: (CGFloat) -> CGFloat,
                                     track: CGFloat) -> some View {
        let v = CGFloat(b.captured)
        let x0 = x(min(v, 0)), x1 = x(max(v, 0))
        HStack(spacing: S.gap4) {
            Text(b.ticker)
                .font(S.inter(S.t12, S.wSemiN)).tracking(S.track(S.t12, -0.01))
                .foregroundStyle(S.ink)
                .frame(width: S.progNameCol, alignment: .leading).lineLimit(1)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: S.radiusBar).fill(S.wash)
                RoundedRectangle(cornerRadius: S.radiusBar)
                    .fill(b.itm ? S.lossBar : S.gainBar)
                    .frame(width: max(2, x1 - x0))
                    .offset(x: x0)
            }
            .frame(width: track, height: S.progRowH)
            .clipShape(RoundedRectangle(cornerRadius: S.radiusBar))
            Text(signedPctInt(b.captured))
                .font(S.inter(S.t13, S.wSemiN))
                .foregroundStyle(b.captured < 0 ? S.lossText : S.gainText)
                .frame(width: S.progValCol, alignment: .trailing)
        }
    }
}

// MARK: - 2 · Yield progress

/// ⚠ SORT IS BEST FIRST, and that is why the card has NO SUMMARY FOOTER of its
/// own beyond the three stats: row 1 IS the leader. The white rule inside each
/// fill is where that name stood last week — a fixed 1.5pt rule, because a
/// proportional slice measured 2.3–5.3px across the book and died at that width.
struct SunnyYieldProgress: View {
    let book: OptionsBook
    let positions: [OptionsPosition]

    private var rows: [(t: String, pct: Double, last: Double)] {
        positions.map { p in
            let pct = p.paid > 0 ? Double(p.collected) / Double(p.paid) * 100 : 0
            let prior = p.collected - p.week
            let last = p.paid > 0 ? Double(prior) / Double(p.paid) * 100 : 0
            return (p.t, pct, last)
        }.sorted { $0.pct > $1.pct }
    }
    private var bookPct: Double {
        book.paid > 0 ? Double(book.collected) / Double(book.paid) * 100 : 0
    }
    private var maxPct: Double { max(rows.map(\.pct).max() ?? 1, bookPct, 1) }
    private let track: CGFloat = 217   // 323 − 46 − 44 − 8 − 8

    var body: some View {
        OptCard(name: "yield-progress") {
            /* ⚠ THE SUB IS GONE AND THE DENOMINATOR CARRIES THE WHOLE JOB.
               The sheet's header was "Yield progress · premium paid back · of
               $162,235 paid", which wrapped the title onto a second line at
               323. Nik's call: drop the sub, keep "$162,235 paid". The rule is
               that every percentage NAMES its denominator, not that it takes
               three phrases to do it — and "paid back" was already said by the
               hero's own label two rows down. */
            OptHead(title: "Yield progress", sub: "",
                    right: "\(optMoney(book.paid)) paid")
            Spacer().frame(height: S.gap7)
            VStack(alignment: .leading, spacing: 5) {
                Text("BOOK AVERAGE")
                    .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.mute)
                HStack(alignment: .firstTextBaseline, spacing: S.gap3) {
                    Text(String(format: "%.1f%%", bookPct))
                        .font(S.inter(S.t30, S.wBoldN)).tracking(S.track(S.t30, -0.03))
                        .foregroundStyle(S.ink).sunnyLineBox(S.t30)
                    Text("paid back").font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
                }
            }
            Spacer().frame(height: 18)
            rowsBlock
            Spacer(minLength: S.gap7)
            OptFooter(stats: [
                .init(label: "This week", value: optMoney(book.thisWeek), ink: S.gain),
                .init(label: "Collected", value: optMoney(book.collected), ink: S.ink),
                .init(label: "Legs", value: "\(book.legs)", ink: S.ink),
            ])
        }
    }

    private var rowsBlock: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: S.progRowGap) {
                ForEach(rows, id: \.t) { r in
                    HStack(spacing: S.gap4) {
                        /* ⚠ NAME AND VALUE COLUMNS ARE flex:none. The
                           summary-lists rule, learned there when a flex:1
                           ticker slot shrank under BABA and ate the row gap. */
                        Text(r.t)
                            .font(S.inter(S.t12, S.wSemiN)).tracking(S.track(S.t12, -0.01))
                            .foregroundStyle(S.ink)
                            .frame(width: S.progNameCol, alignment: .leading)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: S.radiusBar).fill(S.wash)
                            RoundedRectangle(cornerRadius: S.radiusBar).fill(S.gainBar)
                                .frame(width: max(2, track * r.pct / maxPct))
                                .overlay(alignment: .trailing) {
                                    if r.last > 0 && r.pct > r.last {
                                        Rectangle().fill(S.paper)
                                            .frame(width: S.progLastwkW)
                                            .offset(x: -track * (r.pct - r.last) / maxPct)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: S.radiusBar))
                        }
                        .frame(width: track, height: S.progRowH)
                        Text(String(format: "%.1f%%", r.pct))
                            .font(S.inter(S.t13, S.wSemiN)).foregroundStyle(S.ink)
                            .frame(width: S.progValCol, alignment: .trailing)
                    }
                }
            }
            /* The book average, positioned in the ROW BOX, so it carries the
               name column plus its gap as an offset. --ink, because an average
               is a rate and a rate takes no direction ink. */
            Rectangle().fill(S.ink)
                .frame(width: S.refLine)
                .offset(x: S.progNameCol + S.gap4 + track * bookPct / maxPct, y: -4)
                .frame(maxHeight: .infinity)
                .padding(.bottom, -4)
        }
    }
}

// MARK: - 3 · Weekly yield

/// ⚠ A RATE TAKES NO DIRECTION INK. Yield is a rate and an average is a rate,
/// so every bar is --bar-quiet, the average line is --ink, and only the LIVE
/// WEEK takes --gain-bar. And every percentage names its denominator, which is
/// always total premium paid — the only one that makes weeks comparable.
struct SunnyWeeklyYield: View {
    let book: OptionsBook

    private var maxPct: Double { max(book.weekly.map(\.pct).max() ?? 1, 0.01) }

    var body: some View {
        OptCard(name: "weekly-yield") {
            /* ⚠ THE WINDOW AND THE DIVISOR ARE DIFFERENT NUMBERS, and the
               header now says so. The bars chart all eight weeks because a
               zero week is a fact; the average divides by the weeks the book
               actually ran, because five weeks before the position existed
               dragged a 2.78% rate to 1.04%. */
            OptHead(title: "Weekly yield", sub: "on premium paid",
                    right: "\(book.liveWeeks) of \(book.weekly.count) weeks")
            Spacer().frame(height: S.gap6)
            VStack(alignment: .leading, spacing: 5) {
                Text("AVERAGE")
                    .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.mute)
                HStack(alignment: .firstTextBaseline, spacing: S.gap3) {
                    Text(String(format: "%.2f%%", book.avgPct))
                        .font(S.inter(S.t30, S.wBoldN)).tracking(S.track(S.t30, -0.03))
                        .foregroundStyle(S.ink).sunnyLineBox(S.t30)
                    Text("a week").font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
                }
            }
            Spacer().frame(height: 18)
            plot
            Spacer().frame(height: S.gap4)
            labels
            Spacer(minLength: S.gap6)
            OptFooter(stats: [
                .init(label: "This week", value: optMoney(book.thisWeek), ink: S.gain),
                .init(label: "Best week", value: optMoney(book.bestWeek), ink: S.ink),
                .init(label: "Yearly", value: String(format: "%.0f%%", book.yearly), ink: S.ink),
            ])
        }
    }

    private var plot: some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(S.ruleColor).frame(height: 1)
            HStack(alignment: .bottom, spacing: S.gap4) {
                ForEach(Array(book.weekly.enumerated()), id: \.element.id) { i, w in
                    let live = i == book.weekly.count - 1
                    UnevenRoundedRectangle(topLeadingRadius: S.radiusBar,
                                           bottomLeadingRadius: 1, bottomTrailingRadius: 1,
                                           topTrailingRadius: S.radiusBar)
                        .fill(live ? S.gainBar : S.barQuiet)
                        .frame(maxWidth: S.weekBarMax)
                        .frame(height: max(1, S.weekPlotH * w.pct / maxPct))
                }
            }
            Rectangle().fill(S.ink).frame(height: S.refLine)
                .offset(y: -S.weekPlotH * book.avgPct / maxPct)
        }
        .frame(height: S.weekPlotH, alignment: .bottom)
    }

    private var labels: some View {
        HStack(spacing: S.gap4) {
            ForEach(Array(book.weekly.enumerated()), id: \.element.id) { i, _ in
                let live = i == book.weekly.count - 1
                /* The sheet writes these `Wk 1`…`Wk 8`. Nik's call on
                   2026-09-02: `W1`. Eight labels in 323 with a space in each
                   crowd the row, and the axis is unambiguous without it. */
                Text("W\(i + 1)")
                    .font(S.inter(S.t11, live ? S.wBoldN : S.wMidSmN))
                    .foregroundStyle(live ? S.ink : S.mute)
                    .frame(maxWidth: S.weekBarMax)
                    .lineLimit(1)
            }
        }
    }
}
