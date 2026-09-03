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
            /* ⚠ 361 IS A FLOOR, NOT A CEILING, AND THAT IS THE WHOLE FIX.
               `.frame(height:)` PROPOSES a height, it does not clamp one. Every
               fixed card measured OVER its 322 content box — yield-progress by
               33.7, pair-week 21.7, pace-ahead 18.0, name-credit 12.3,
               weekly-yield 8.0 — so the content ran past the box, ate all 22pt
               of bottom padding, and on yield-progress was CLIPPED 11.7pt below
               the card edge. The one card that measured right was the rows form,
               and it measured right because it was free-height.

               The 361 came off CSS, where line-height IS the line advance.
               SwiftUI gives every Text its own leading on top of that, so the
               same content lays out taller here and no padding number could
               have made it fit. `minHeight` keeps 361 for a card whose content
               fits and lets the rest grow, so the footer sits 22 off the floor
               on all six. Cards now vary in height with the size of the book. */
            .frame(width: S.content - 38, alignment: .top)
            .frame(minHeight: fixedHeight.map { $0 - 39 }, alignment: .top)
            /* ⚠ 22 AT THE BOTTOM, NOT THE SHEET'S 16. The sheet measured
               --pad-card-m off CSS, where a 19px figure at line-height 1 sits
               its baseline flush to the box floor. SwiftUI gives Text its own
               leading, so the same 16 left the footer figures visually touching
               the card edge on every card. The extra 6 comes out of the slack
               row, so the card still measures 361. */
            .padding(EdgeInsets(top: 17, leading: 19, bottom: 22, trailing: 19))
            .frame(width: S.content, alignment: .top)
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
/// ⚠ NO SIGN GLYPH. Nik, 2026-09-03: "remove the + and - sign green and red
/// text is enough." The bar's side of the zero line and the ink both say the
/// direction already, and "+" / "−" in a 44pt column was what pushed −158%
/// onto a second line.
private func barePctInt(_ v: Int) -> String { "\(abs(v))%" }
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
    /* ⚠ THE STRIKE IS NOT ALWAYS ENOUGH TO TELL TWO LEGS APART. It was while
       the only doubled name was NKE at 39 and 40. Then BABA went to 114 for
       4 Sep AND 114 for 11 Sep — a roll to the same strike a week out, which is
       the normal shape of this book — and both rows rendered "BABA 114". Two
       identical labels on two different legs is worse than no label.

       So the disambiguator escalates: one leg is the bare name, several legs
       take the strike, and legs that COLLIDE on a strike also take the expiry.
       Only the colliding ones, so NKE stays "NKE 39 / NKE 40" and does not
       grow a date it does not need. */
    private var bars: [Bar] {
        positions.flatMap { p -> [Bar] in
            let strikeCount = Dictionary(grouping: p.shorts, by: \.k).mapValues(\.count)
            return p.shorts.map { s in
                let k = s.k.formatted(.number.precision(.fractionLength(0)))
                let label: String
                if p.shorts.count <= 1 { label = p.t }
                /* ⚠ AND THE STRIKE IS DROPPED WHEN IT COLLIDES, not kept
                   alongside the date. Two legs at 114 make "114" carry no
                   information at all; keeping it only bought "BABA 114 11 Sep",
                   which does not fit any sane name column. The date alone
                   separates them. */
                else if (strikeCount[s.k] ?? 0) > 1 { label = "\(p.t) \(shortDay(s.exp))" }
                else { label = "\(p.t) \(k)" }
                return Bar(id: "\(p.t)-\(s.id)", ticker: label,
                           captured: s.captured, itm: s.itm)
            }
        }
    }

    /* ⚠ THE COLUMNS ARE MEASURED, NOT ASSUMED. 46 was sized for a bare
       ticker and 44 for "-111%"; the first label with a date in it truncated
       to "BABA..." and -158% wrapped onto a second line. Both columns now take
       their widest actual content and the TRACK absorbs the difference, so the
       row still totals 323 and the plot never overflows the card. */
    private var nameCol: CGFloat {
        min(134, max(S.progNameCol,
                     (bars.map { S.textW($0.ticker, S.t12, S.wSemiN) }.max() ?? 0) + 3))
    }
    private var valCol: CGFloat {
        max(S.progValCol,
            (bars.map { S.textW(barePctInt($0.captured), S.t13, S.wSemiN) }.max() ?? 0) + 3)
    }
    private var rowTrack: CGFloat {
        max(110, S.content - 38 - nameCol - valCol - 2 * S.gap4)
    }

    /// "11 Sep" — only ever appended when two legs share a strike.
    private func shortDay(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m)
        else { return iso }
        let mon = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                   "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(d) \(mon[m - 1])"
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
                Text(barePctInt(b.captured))
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
        let track: CGFloat = rowTrack
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
                Color.clear.frame(width: nameCol, height: 1)
                HStack {
                    Text("\(giveBackLine)%".replacingOccurrences(of: "-", with: "\u{2212}"))
                    Spacer()
                    Text("+\(captureLine)%")
                }
                .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute)
                .frame(width: track)
                Color.clear.frame(width: valCol, height: 1)
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
                        .offset(x: nameCol + S.gap4 + x(v), y: -4)
                        .frame(maxHeight: .infinity).padding(.bottom, -4)
                }
                Rectangle().fill(S.ruleColorStrong).frame(width: 1)
                    .offset(x: nameCol + S.gap4 + x(0), y: -4)
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
                .frame(width: nameCol, alignment: .leading).lineLimit(1)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: S.radiusBar).fill(S.wash)
                RoundedRectangle(cornerRadius: S.radiusBar)
                    .fill(b.itm ? S.lossBar : S.gainBar)
                    .frame(width: max(2, x1 - x0))
                    .offset(x: x0)
            }
            .frame(width: track, height: S.progRowH)
            .clipShape(RoundedRectangle(cornerRadius: S.radiusBar))
            Text(barePctInt(b.captured))
                .font(S.inter(S.t13, S.wSemiN))
                .foregroundStyle(b.captured < 0 ? S.lossText : S.gainText)
                .frame(width: valCol, alignment: .trailing)
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
    /* ⚠ THE DENOMINATOR IS 100, NOT THE LEADER. It used to be
       max(best, bookAverage), which made the best name's bar full-width by
       construction: NFLX at 16.9% filled the track and read as "winning",
       when all it means is it is 16.9% of the way to paying its LEAP back.
       Nik: "change from winner within them to racing to 100%". Every bar is
       now its true share of a fully repaid LEAP, so the bars are SHORT and
       that is the honest picture. The track's right edge is 100%. */
    private let fullPct: Double = 100
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
            /* ⚠ THE AXIS IS NOT DECORATION. Rescaling to 100 makes every bar
               short, and a short bar with no end marked reads as a broken
               chart rather than an early one. Same axis row as the roll-check
               card, one page across. */
            HStack(spacing: S.gap4) {
                Color.clear.frame(width: S.progNameCol, height: 1)
                HStack { Spacer(); Text("100% = PAID BACK") }
                    .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.mute)
                    .frame(width: track)
                Color.clear.frame(width: S.progValCol, height: 1)
            }
            .padding(.bottom, S.gap4)
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
                                .frame(width: max(2, track * r.pct / fullPct))
                                /* ⚠ TWO TONES, NOT A GAP. Last week used to be
                                   a 1.5pt --paper rule inset from the bar's
                                   tip, which worked when the leader filled the
                                   track. Against a 100% denominator the bars
                                   are short and most of the paid-back happened
                                   THIS week, so the rule landed near the start
                                   and severed every bar into two: NFLX and BABA
                                   read as two separate bars. Prior weeks now
                                   take --gain-span and this week keeps
                                   --gain-bar, which says the same thing in one
                                   continuous bar. */
                                .overlay(alignment: .leading) {
                                    if r.last > 0 {
                                        Rectangle().fill(S.gainSpan)
                                            .frame(width: max(1, track * r.last / fullPct))
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
                .offset(x: S.progNameCol + S.gap4 + track * bookPct / fullPct, y: -4)
                .frame(maxHeight: .infinity)
                .padding(.bottom, -4)
        }
    }
}

// MARK: - 2b · Long calls

/// The other half of Yield progress. That card asks how much of the LEAP the
/// premium has paid back; this one asks what the LEAP itself is worth. Same
/// denominator, same row geometry, opposite question.
///
/// ⚠ THE BARS DIVERGE OFF A CENTRE LINE, which Yield progress does not need
/// because paid-back cannot go backwards. A gain can, so zero has to be a
/// place on the track rather than the left edge. Geometry is the roll-check
/// card's, not a third invention.
///
/// ⚠ AND THE SCALE IS SYMMETRIC AROUND ZERO, floored at ±5%. Fitting the axis
/// to the data alone would make a book that moved 0.3% look identical to one
/// that moved 30%, which is the "winner within them" failure Yield progress
/// just had, one card over.
struct SunnyLeapGains: View {
    let book: OptionsBook
    let positions: [OptionsPosition]

    private var rows: [(t: String, pct: Double, gain: Int)] {
        positions.map { p in
            (p.t, p.paid > 0 ? Double(p.mark - p.paid) / Double(p.paid) * 100 : 0,
             p.mark - p.paid)
        }.sorted { $0.pct > $1.pct }
    }
    private var paid: Int { positions.reduce(0) { $0 + $1.paid } }
    private var worth: Int { positions.reduce(0) { $0 + $1.mark } }
    private var gain: Int { worth - paid }
    private var bookPct: Double { paid > 0 ? Double(gain) / Double(paid) * 100 : 0 }
    /// Symmetric, so the centre line is genuinely the centre.
    private var span: Double { max(5, (rows.map { abs($0.pct) }.max() ?? 5) * 1.1) }
    /* Measured for the same reason the roll check's is: the fixed 44 was sized
       for "-111%" and "+10.9%" wrapped onto a second line in it. */
    private var valCol: CGFloat {
        max(S.progValCol,
            (rows.map { S.textW(pct($0.pct), S.t13, S.wSemiN) }.max() ?? 0) + 3)
    }
    private var track: CGFloat {
        max(110, S.content - 38 - S.progNameCol - valCol - 2 * S.gap4)
    }

    private func x(_ v: Double) -> CGFloat {
        track * CGFloat((v + span) / (2 * span))
    }
    private func pct(_ v: Double) -> String {
        (v > 0 ? "+" : v < 0 ? "\u{2212}" : "") + String(format: "%.1f%%", abs(v))
    }

    var body: some View {
        OptCard(name: "leap-gains") {
            OptHead(title: "Long calls", sub: "", right: "\(optMoney(paid)) paid")
            Spacer().frame(height: S.gap7)
            VStack(alignment: .leading, spacing: 5) {
                Text("BOOK GAIN")
                    .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.mute)
                HStack(alignment: .firstTextBaseline, spacing: S.gap3) {
                    /* A gain is signed P&L, not a rate, so it DOES take
                       direction ink. The weekly-yield card's "a rate takes no
                       direction ink" rule does not reach this figure. */
                    Text(pct(bookPct))
                        .font(S.inter(S.t30, S.wBoldN)).tracking(S.track(S.t30, -0.03))
                        .foregroundStyle(gain < 0 ? S.loss : S.gain)
                        .sunnyLineBox(S.t30)
                    Text("unrealised").font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
                }
            }
            Spacer().frame(height: 18)
            HStack(spacing: S.gap4) {
                Color.clear.frame(width: S.progNameCol, height: 1)
                HStack {
                    Text(pct(-span)); Spacer(); Text(pct(span))
                }
                .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute)
                .frame(width: track)
                Color.clear.frame(width: valCol, height: 1)
            }
            .padding(.bottom, S.gap4)
            ZStack(alignment: .topLeading) {
                VStack(spacing: S.progRowGap) {
                    ForEach(rows, id: \.t) { r in
                        let x0 = x(min(r.pct, 0)), x1 = x(max(r.pct, 0))
                        HStack(spacing: S.gap4) {
                            Text(r.t)
                                .font(S.inter(S.t12, S.wSemiN)).tracking(S.track(S.t12, -0.01))
                                .foregroundStyle(S.ink)
                                .frame(width: S.progNameCol, alignment: .leading).lineLimit(1)
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: S.radiusBar).fill(S.wash)
                                RoundedRectangle(cornerRadius: S.radiusBar)
                                    .fill(r.pct < 0 ? S.lossBar : S.gainBar)
                                    .frame(width: max(2, x1 - x0))
                                    .offset(x: x0)
                            }
                            .frame(width: track, height: S.progRowH)
                            .clipShape(RoundedRectangle(cornerRadius: S.radiusBar))
                            Text(pct(r.pct))
                                .font(S.inter(S.t13, S.wSemiN))
                                .foregroundStyle(r.pct < 0 ? S.lossText : S.gainText)
                                .frame(width: valCol, alignment: .trailing)
                        }
                    }
                }
                Rectangle().fill(S.ruleColorStrong).frame(width: 1)
                    .offset(x: S.progNameCol + S.gap4 + x(0), y: -4)
                    .frame(maxHeight: .infinity).padding(.bottom, -4)
            }
            Spacer(minLength: S.gap7)
            OptFooter(stats: [
                .init(label: "Paid", value: optMoney(paid), ink: S.ink),
                .init(label: "Worth now", value: optMoney(worth), ink: S.ink),
                .init(label: "Gain", value: optMoney(gain), ink: gain < 0 ? S.loss : S.gain),
            ])
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
            Spacer(minLength: S.gap6)
            OptFooter(stats: [
                .init(label: "This week", value: optMoney(book.thisWeek), ink: S.gain),
                .init(label: "Best week", value: optMoney(book.bestWeek), ink: S.ink),
                .init(label: "Yearly", value: String(format: "%.0f%%", book.yearly), ink: S.ink),
            ])
        }
    }

    /* ⚠ THE WEEK NUMBERS ARE GONE AND THE VALUE SITS ON THE BAR. Nik:
       "Remove W1, ... W8 text we dont need the text also on bars can you add %
       value on top of the bars." W1…W8 named a column without saying anything
       about it, and the reader still had to measure a bar against a line to
       learn the number. The figure on the bar answers it directly.

       A zero week gets NO label. Five "0.0%" on five empty bars is the axis
       row again in a worse place; the empty bar is already the whole story. */
    private let capH: CGFloat = 14      // the figure above a bar
    private var barMaxH: CGFloat { S.weekPlotH - capH - 4 }

    private var plot: some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(S.ruleColor).frame(height: 1)
            HStack(alignment: .bottom, spacing: S.gap4) {
                ForEach(book.weekly) { w in
                    /* Server-flagged, never the last index: the window now
                       reaches into weeks already sold but not yet begun. */
                    let live = w.current ?? false
                    VStack(spacing: 4) {
                        Text(w.pct > 0 ? String(format: "%.1f%%", w.pct) : "")
                            .font(S.inter(S.t10, live ? S.wBoldN : S.wMidSmN))
                            .foregroundStyle(live ? S.ink : S.mute)
                            .lineLimit(1).fixedSize()
                            .frame(height: capH)
                        UnevenRoundedRectangle(topLeadingRadius: S.radiusBar,
                                               bottomLeadingRadius: 1, bottomTrailingRadius: 1,
                                               topTrailingRadius: S.radiusBar)
                            .fill(live ? S.gainBar : S.barQuiet)
                            .frame(height: max(1, barMaxH * w.pct / maxPct))
                    }
                    .frame(maxWidth: S.weekBarMax)
                }
            }
            Rectangle().fill(S.ink).frame(height: S.refLine)
                .offset(y: -barMaxH * book.avgPct / maxPct)
        }
        .frame(height: S.weekPlotH, alignment: .bottom)
    }

}
