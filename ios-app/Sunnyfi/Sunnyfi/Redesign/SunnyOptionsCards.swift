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

/// ⚠ ONE SWITCH, THREE CARDS. Roll check, Long calls and Weekly yield all
/// print a percentage that has an exact dollar twin, and the two are not
/// redundant: a percentage compares things of different sizes, dollars say
/// what a thing is worth. NKE reads fourth-worst at -17% and WORST at -$250,
/// because it is 50 contracts against BABA's 5.
///
/// ⚠ VERIFICATION ONLY on the launch argument — the simulator's touch bridge
/// crashes, so `-showMoney` forces the state and proves the RENDERING. It
/// does not test the tap, which cannot be driven here.
private var moneyByDefault: Bool {
    ProcessInfo.processInfo.arguments.contains("-showMoney")
}

/// "$4.2k" — the weekly-yield labels sit over 30pt bars and a full
/// "$4,243" collides with its neighbour at eight columns.
func optMoneyShort(_ v: Int) -> String {
    let a = abs(v)
    let s = a >= 1000
        ? "$" + String(format: "%.1f", Double(a) / 1000).replacingOccurrences(of: ".0", with: "") + "k"
        : "$\(a)"
    return v < 0 ? "\u{2212}" + s : s
}

func optMoney(_ v: Int) -> String {
    let a = abs(v)
    let s = a >= 1000 ? "$\(a / 1000),\(String(format: "%03d", a % 1000))" : "$\(a)"
    return v < 0 ? "\u{2212}" + s : s
}
/* ⚠ THE MINUS STAYS, THE PLUS GOES. Nik asked for "remove the + and - sign"
   and I removed both, which made -28% render as "28%" in red — a number
   saying one thing and a colour saying another. His reference layout settles
   it: negatives keep the minus, positives carry no plus. That is also why
   dropping the plus is safe, since it never carried information the bar's
   side of zero did not already give. */
private func barePctInt(_ v: Int) -> String {
    (v < 0 ? "\u{2212}" : "") + "\(abs(v))%"
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
        /// Which half of the list the row belongs to. A sold put and a sold
        /// call are opposite trades and Nik reads them as two groups.
        var isPut: Bool = false
        /// Credit minus current value, in dollars — the same quantity the
        /// percentage expresses, which is why one tap may swap them.
        var kept: Int = 0
        /* ⚠ FALSE MEANS NO CALL IS SOLD, WHICH IS NOT A CAPTURE OF ZERO.
           An uncovered name has captured nothing because there is nothing
           to capture, and the row must say that rather than draw a bar at
           the zero line as though a leg existed and had gone nowhere. */
        var covered: Bool = true
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
    /* ⚠ WORST FIRST, and the reference is unambiguous about it: -113, -111,
       14, 23 … 83. The rows are a queue of work, so the leg that needs a
       decision has to be the one your eye lands on. Unsorted meant the order
       was whatever the book happened to return. */
    private var bars: [Bar] {
        sortedBars
    }

    /* ⚠ UNCOVERED NAMES SORT ABOVE EVERYTHING, not into the numeric order.
       They have no captured value to sort BY, and they are the work that has
       not started: a name with no call earns nothing this week, while a leg
       at -28% out of the money needs no decision at all. Nik found this the
       hard way — the card said "5 legs" while he held seven LEAPs, and the
       three it could not draw (FIS, PEP, KR, whose calls expired on the
       Friday) were exactly the three needing action. */
    private var sortedBars: [Bar] { callBars + putBars }

    /* ⚠ CALLS AND PUTS ARE TWO LISTS WITH ONE RULE, not one list. Nik,
       2026-09-08: "Is there a way to separate the puts and calls here with a
       small divider line." This supersedes the 2026-09-06 ruling of a single
       sorted list; the `110P` suffix stays, because a divider groups but does
       not label.

       Worst-first still holds INSIDE each group, so each half is its own queue
       of work. A name with no call sits with the calls: that is where the
       missing leg would go. */
    private var callBars: [Bar] {
        let all = rawBars
        return all.filter { !$0.covered }.sorted { $0.ticker < $1.ticker }
             + all.filter { $0.covered && !$0.isPut }.sorted { $0.captured < $1.captured }
    }
    private var putBars: [Bar] {
        rawBars.filter { $0.covered && $0.isPut }.sorted { $0.captured < $1.captured }
    }

    private var rawBars: [Bar] {
        positions.flatMap { p -> [Bar] in
            /* A LEAP with no call against it is still a row. The card is the
               only place the book is listed against its calls, so a name it
               cannot draw is a name that cannot be noticed. */
            guard !p.shorts.isEmpty else {
                return [Bar(id: "\(p.t)-none", ticker: p.t, captured: 0,
                            itm: false, covered: false)]
            }
            let strikeCount = Dictionary(grouping: p.shorts, by: \.k).mapValues(\.count)
            return p.shorts.map { s in
                let k = s.k.formatted(.number.precision(.fractionLength(0)))
                let label: String
                if p.shorts.count <= 1 { label = p.t + (s.type == "put" ? " \(k)P" : "") }
                /* ⚠ AND THE STRIKE IS DROPPED WHEN IT COLLIDES, not kept
                   alongside the date. Two legs at 114 make "114" carry no
                   information at all; keeping it only bought "BABA 114 11 Sep",
                   which does not fit any sane name column. The date alone
                   separates them. */
                else if (strikeCount[s.k] ?? 0) > 1 {
                    label = "\(p.t)\(s.type == "put" ? " \(k)P" : "") \(shortDay(s.exp))"
                }
                /* ⚠ A PUT SUFFIXES ITS STRIKE. Without it a sold 140 call and
                   a sold 140 put on PEP render the identical row, and they are
                   opposite trades — one is assigned when the name rises and the
                   other when it falls. Nik's call, 2026-09-06. */
                else { label = "\(p.t) \(k)\(s.type == "put" ? "P" : "")" }
                return Bar(id: "\(p.t)-\(s.id)", ticker: label,
                           captured: s.captured, itm: s.itm, isPut: s.type == "put",
                           kept: s.credit - (s.priced == false ? s.credit : s.value))
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
            (bars.map { S.textW($0.covered ? barePctInt($0.captured) : "No call",
                                S.t13, S.wSemiN) }.max() ?? 0) + 3)
    }
    private var uncovered: Int { rawBars.filter { !$0.covered }.count }

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

    /* ⚠ ONE FORM, ALWAYS ROWS. The sheet escalates ≤5 bars → 6–10 paged →
       11+ rows, and both of the other two are gone for reasons this shell
       forces.

       PAGED cannot exist here: it pages on a horizontal gesture and our shell
       IS a horizontal paging ScrollView, so the card and the navigation fight
       over every drag. Nik hit that at six legs.

       BARS is gone because the FORM ITSELF MOVED. It rendered at five legs or
       fewer, so closing one call silently changed the card's shape — Nik, on
       dropping back to five: "I thought we changed the layout so that all
       tickers fit and suddenly it went back to the old layout." A card that
       re-lays-itself out as the book breathes is not a layout, it is two
       layouts and a coin toss. Bars also crowded the labels it did keep:
       five names across 323 put "BABA 114" and "BABA 115" shoulder to
       shoulder under 30pt columns.

       Rows show every leg at once, at any count, with the name on its own
       line and a measured column that fits it. The sheet's own argument for
       escalating to rows — "a card you page three times to read is a list
       pretending to be a chart" — lands at one page in a shell that owns the
       gesture, which means it lands at five legs too. */
    /* ⚠ VERIFICATION ONLY, and it exists because the touch bridge is dead —
       `-showMoney` starts the card in the dollar state so the RENDERING can be
       checked. It does not test the tap, which cannot be driven here. */
    @State private var showMoney = moneyByDefault

    var body: some View {
        rowsCard
            /* A discrete tap, so it never competes with the shell's horizontal
               paging drag. */
            .contentShape(Rectangle())
            .onTapGesture { showMoney.toggle() }
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
            /* "5 legs" was true and misleading: it counted what the card
               could draw, not what he holds. */
            /* "calls sold" while it carried only calls. It carries sold puts
               too now, and a header that names one leg type while showing both
               is the same class of lie as "5 legs" was. */
            OptHead(title: "Roll check", sub: "sold",
                    right: uncovered == 0
                        ? "\(positions.count) names"
                        : "\(uncovered) with no call")
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
                    Text("kept \(book.openWhen ?? "this week")")
                        .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
                }
            }
            Spacer().frame(height: 18)
            HStack(spacing: S.gap4) {
                Color.clear.frame(width: nameCol, height: 1)
                HStack {
                    /* No % on the axis. The eyebrow already says CAPTURED OF
                       CREDIT, and the reference layout drops it. */
                    Text("\(giveBackLine)".replacingOccurrences(of: "-", with: "\u{2212}"))
                    Spacer()
                    Text("+\(captureLine)")
                }
                .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute)
                .frame(width: track)
                Color.clear.frame(width: valCol, height: 1)
            }
            .padding(.bottom, S.gap4)
            ZStack(alignment: .topLeading) {
                VStack(spacing: S.progRowGap) {
                    ForEach(callBars) { b in rowFor(b, x: x, track: track) }
                    /* Only when both halves exist. A lone divider under an
                       all-calls book would announce a section that is not
                       there. It spans the name column and the track, stopping
                       short of the value column, so the percentages stay a
                       single unbroken edge down the right. */
                    if !callBars.isEmpty && !putBars.isEmpty {
                        Rectangle().fill(S.ruleColor)
                            .frame(width: nameCol + S.gap4 + track, height: 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(putBars) { b in rowFor(b, x: x, track: track) }
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
            /* ⚠ COLLECTED AND CURRENT VALUE ARE THE HERO'S TWO HALVES, so
               every figure on the card audits against the other two:
               5,267 − 5,441 = −174, which is what "kept this week" says.
               ROLLING is gone because colour no longer means moneyness and a
               count with nothing on screen agreeing with it is a loose end.
               Yield is GROSS — credit on the LEAP capital, before buying the
               legs back — and it is the same 2.70% the weekly-yield card
               charts for the week these legs cover, because the server
               computes it once for both. */
            OptFooter(stats: [
                .init(label: "Collected",
                      value: optMoney(book.openCredit ?? 0), ink: S.gainText),
                /* "Current value" truncated to "CURRENT VA…" in a third of
                   323 at 10px. The Long calls card already settled this
                   wording, so both now say the same thing. */
                .init(label: "Worth now",
                      value: optMoney(book.openValue ?? 0), ink: S.ink),
                .init(label: "Yield",
                      value: String(format: "%.1f%%", book.openYield ?? 0), ink: S.ink),
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
                .foregroundStyle(b.covered ? S.ink : S.mute)
                .frame(width: nameCol, alignment: .leading).lineLimit(1)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: S.radiusBar).fill(S.wash)
                /* ⚠ NO MARK AT ALL WHEN NOTHING IS SOLD. A 2pt sliver at the
                   zero line would read as a leg that captured nothing, which
                   is a different and wrong statement. */
                if b.covered {
                    RoundedRectangle(cornerRadius: S.radiusBar)
                        .fill(b.captured < 0 ? S.lossBar : S.gainBar)
                        .frame(width: max(2, x1 - x0))
                        .offset(x: x0)
                }
            }
            .frame(width: track, height: S.progRowH)
            .clipShape(RoundedRectangle(cornerRadius: S.radiusBar))
            /* ⚠ THE INK IS THE MONEY, AND IT WAS MONEYNESS UNTIL 2026-09-06.
               The reference layout coloured by moneyness — JPM at +14% RED
               because it was in the money — and I built that. Nik overruled it
               after living with it: "Bar shuold be green for anything positive
               which means if collected 1000 and current avlue is 250 which is
               positive... When red is opposite of the first one - Collected
               1000 and current value 1500."

               He is right about the failure mode. Nothing was in the money, so
               the colour channel carried NO information at all — eight green
               rows, four of them losing money. Moneyness only speaks on the
               days something is ITM; the sign speaks every day.

               ⚠ SO THE CARD NO LONGER MARKS WHICH LEG TO ROLL, and the page
               title carries that instead ("2 to roll"). The bar's SIDE of the
               centre line was already the sign, so colour and position now say
               the same thing twice — which is the price of the trade. */
            /* "No call" takes --mute: it is neither a win nor a loss, it is
               an absence, and giving it direction ink would rank it against
               figures it is not comparable to. */
            /* ⚠ ONE TAP SWAPS THE UNIT, and the two are the same fact. A
               percentage compares legs of different sizes; the dollars say
               what it is worth. NKE at -17% and BABA 114 at -23% look like
               BABA is worse, and in money NKE is the larger number because it
               is 50 contracts against 5. Both readings are true and neither
               is derivable from the row alone, which is the whole reason the
               tap exists rather than a choice of one. */
            Text(b.covered ? (showMoney ? optMoney(b.kept) : barePctInt(b.captured))
                           : "No call")
                .font(S.inter(S.t13, S.wSemiN))
                .foregroundStyle(b.covered ? (b.captured < 0 ? S.lossText : S.gainText) : S.mute)
                .frame(width: valCol, alignment: .trailing).lineLimit(1)
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
            let cap = p.invested ?? p.paid
            let pct = cap > 0 ? Double(p.collected) / Double(cap) * 100 : 0
            let prior = p.collected - p.week
            let last = cap > 0 ? Double(prior) / Double(cap) * 100 : 0
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
                    /* "paid" now covers the puts too, so the word is
                       "invested" — the label has to match the number. */
                    right: "\(optMoney(book.paid)) invested")
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

    @State private var showMoney = moneyByDefault

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
            (rows.map { S.textW(showMoney ? optMoney($0.gain) : pct($0.pct),
                                S.t13, S.wSemiN) }.max() ?? 0) + 3)
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
        card.contentShape(Rectangle()).onTapGesture { showMoney.toggle() }
    }

    private var card: some View {
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
                            Text(showMoney ? optMoney(r.gain) : pct(r.pct))
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

// MARK: - 2c · Put cover

/// The hedge, and whether it is paying for itself. Build sheet:
/// handoff/cards/put-cover.md, and every measurement here is from it.
///
/// ⚠ THE CIRCLE IS THE COMBINED COST OF EVERY PUT, AND THE AMOUNT IS PRINTED.
/// Not a target, not 100% of a rate. A ring with no amount on it is a
/// percentage wearing a costume; the reason this card may be a ring at all is
/// that its whole is real money.
///
/// ⚠ THE ARC CLAMPS AT FULL, THE NUMBER CARRIES THE OVERAGE. Past twelve
/// o'clock an arc overwrites its own start, so 105% would draw as 5%. At
/// collected ≥ cost the arc stops closed, the centre prints the true figure,
/// and the third stat flips to OVER.
///
/// ⚠ ONE SERIES, SO ONE COLOUR, and NO PER-NAME ROWS. The moment it lists
/// names it is another ranking card and the options family already has three.
/// Which names are in it is the header count.
struct SunnyPutCover: View {
    /// Null before the first put is bought. The card still draws — Nik asked
    /// to watch the circle develop as the book is built — but it draws an
    /// ABSENCE, not a zero.
    let c: PutCover?

    /* ⚠ THE RING'S CENTRE SWAPS TO DOLLARS ON A TAP, the same gesture Roll
       check, Weekly yield and Stock price carry. Nik, 2026-09-09: "when you
       tap on 4% we need to show dollar amount". The figure drops to 26 in the
       money state because "$2,179" at 30 does not fit inside the ring. */
    @State private var showMoney = moneyByDefault

    private var frac: Double {
        guard let c, c.cost > 0 else { return 0 }
        return Double(c.collected) / Double(c.cost)
    }
    private var covered: Bool { (c?.left ?? 1) <= 0 }
    private var started: Bool { (c?.cost ?? 0) > 0 }

    var body: some View {
        card.contentShape(Rectangle()).onTapGesture { showMoney.toggle() }
    }

    private var card: some View {
        OptCard(name: "put-cover") {
            /* No scope word. The sheet has "all tickers" there; Nik ruled it
               off on 2026-09-06 because not every position will carry a put,
               and naming the whole book when five of seven are in it is the
               same lie "5 legs" was. The count already says the size. */
            OptHead(title: "Put cover", sub: "",
                    right: started
                        ? "\(c!.names) name\(c!.names == 1 ? "" : "s") \u{00B7} \(c!.puts) put\(c!.puts == 1 ? "" : "s")"
                        : "none yet")
            Spacer().frame(height: 20)
            ring
            Spacer().frame(height: 14)
            Text(started
                 ? "\(optMoney(c!.collected)) of \(optMoney(c!.cost)) collected"
                 : "No puts bought yet")
                .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
                .frame(maxWidth: .infinity, alignment: .center)
            /* 6, not 12. The two lines are one statement in two parts — what
               has been collected, and what it takes to finish — and at the
               wider gap they read as two unrelated notes under the ring. */
            Spacer().frame(height: 6)
            /* One line, never a second graphic: a pace chart here would be a
               second answer competing with the ring, and the projection is one
               division. */
            Text(paceLine)
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
                .frame(maxWidth: .infinity, alignment: .center)
                .lineLimit(1)
            Spacer(minLength: S.gap7)
            /* ⚠ AN ABSENT VALUE IS A DASH, NEVER A ZERO. "$0" at 19/700 in a
               footer slot reads as a measured nothing — the book was priced
               and came to zero — which is a different and false statement. A
               dash cannot be mistaken for a measurement. */
            OptFooter(stats: started
                ? [
                    .init(label: "Put cost", value: optMoney(c!.cost), ink: S.ink),
                    .init(label: "Collected", value: optMoney(c!.collected), ink: S.gainText),
                    covered
                        ? .init(label: "Over", value: "+" + optMoney(-c!.left), ink: S.gainText)
                        : .init(label: "To cover", value: optMoney(c!.left), ink: S.ink),
                ]
                : [
                    .init(label: "Put cost", value: "\u{2014}", ink: S.mute),
                    .init(label: "Collected", value: "\u{2014}", ink: S.mute),
                    .init(label: "To cover", value: "\u{2014}", ink: S.mute),
                ])
        }
    }

    /* ⚠ THE LINE ASKS WHAT IT TAKES, NOT HOW LONG THE PACE WOULD TAKE. Nik,
       2026-09-09: "the suggestion cannot be post expiry. We need to say that
       2200 to be made to cover in 32 weeks." It read "$1,090/wk pace · full
       cover in 45 weeks" against puts that expire in 28. Dividing what is left
       by the realised pace answers a question whose premise is false. */
    private var paceLine: String {
        guard let c, started else {
            return "The ring fills as premium covers what the puts cost"
        }
        if covered { return "Covered \u{00B7} \(optMoney(c.pace))/wk still coming in" }
        guard let weeks = c.weeksLeft, weeks > 0, let need = c.need, need > 0 else {
            /* No expiry from the server, so no deadline can be stated. Fall
               back to the plain fact rather than inventing a horizon. */
            return "\(optMoney(c.left)) still to cover"
        }
        /* Already selling fast enough: say so instead of setting a target he
           is beating. */
        if c.pace >= need {
            return "On pace \u{00B7} \(optMoney(c.pace))/wk covers it in \(weeks) week\(weeks == 1 ? "" : "s")"
        }
        return "\(optMoney(need)) a week to cover in \(weeks) week\(weeks == 1 ? "" : "s")"
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(S.coverTrack, lineWidth: S.coverStroke)
            /* ⚠ CLAMPED AT 1. Trim past 1 wraps and the arc eats its own tail.
               And NO ARC AT ALL before the first put: a 0.001 stub would be a
               green pip at twelve o'clock claiming a start that has not
               happened. */
            if started {
                Circle()
                    .trim(from: 0, to: max(0.001, min(frac, 1)))
                    .stroke(S.gainBar,
                            style: StrokeStyle(lineWidth: S.coverStroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            /* The figure is a SIBLING of the arc, never rotated with it. */
            VStack(spacing: 3) {
                /* ⚠ "0%" WOULD READ AS FAILING AT SOMETHING. Before the first
                   put there is no denominator, so the centre carries a dash in
                   --mute and the label says what has not happened rather than
                   scoring it at nothing. */
                Text(started
                     ? (showMoney ? optMoney(c!.collected)
                                  : String(format: "%.0f%%", frac * 100))
                     : "\u{2014}")
                    .font(S.inter(showMoney && started ? S.t26 : S.t30, S.wBoldN))
                    .tracking(S.track(showMoney && started ? S.t26 : S.t30, -0.03))
                    .foregroundStyle(started ? S.gainText : S.mute)
                    .sunnyLineBox(showMoney && started ? S.t26 : S.t30)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(started ? "COVERED" : "NO PUTS YET")
                    .font(S.inter(S.t11, S.wBoldN)).tracking(S.track(S.t11, S.lsLabel))
                    .foregroundStyle(S.mute)
            }
        }
        .frame(width: S.coverRingD, height: S.coverRingD)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - 3 · Weekly yield

/// ⚠ A RATE TAKES NO DIRECTION INK. Yield is a rate and an average is a rate,
/// so every bar is --bar-quiet, the average line is --ink, and only the LIVE
/// WEEK takes --gain-bar. And every percentage names its denominator, which is
/// always total premium paid — the only one that makes weeks comparable.
struct SunnyWeeklyYield: View {
    let book: OptionsBook

    @State private var showMoney = moneyByDefault

    private var maxPct: Double { max(book.weekly.map(\.pct).max() ?? 1, 0.01) }

    var body: some View {
        card.contentShape(Rectangle()).onTapGesture { showMoney.toggle() }
    }

    private var card: some View {
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
                        /* A zero week still gets no label in either unit: an
                           empty bar is already the whole story, and "$0" eight
                           times is the axis row again in a worse place. */
                        Text(w.pct > 0
                             ? (showMoney ? optMoneyShort(w.credit)
                                          : String(format: "%.1f%%", w.pct))
                             : "")
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

// MARK: - stock price

/// ⚠ ROLL CHECK'S LAYOUT, A DIFFERENT SUBJECT. Nik, 2026-09-08: "Just like a
/// roll check card can we do one for stock price. Same layout as Roll check the
/// only added thing I want is adding 1 week, 2 weeks, 3 weeks and 4 weeks
/// filter", then "also need one for today", then "remove ref lines".
///
/// ⚠ SO THERE ARE NO REFERENCE LINES HERE, only the zero line. Roll check's
/// −100 and +75 are thresholds that mean something about capture; a price move
/// has no equivalent, and drawing two arbitrary verticals would invent a
/// standard the number is not being judged against.
///
/// ⚠ AND THE HERO IS WEIGHTED BY COST. The rows already say what each name did.
/// An unweighted mean would restate them and would call a 1% KR position the
/// equal of a 24% BABA one, so the server weights by the same cost basis the
/// ticker strip uses. See `feedback_metric_must_add_information`.
struct SunnyStockPrice: View {
    let prices: PricesBlock

    @State private var window: PriceWindow = .today

    private struct Row: Identifiable {
        let id: String, ticker: String, pct: Double
        let spot: Double?
    }

    /* ⚠ ONE TAP SWAPS THE COLUMN, the same gesture Roll check and Weekly yield
       already carry. Nik, 2026-09-09: "When I tap on % can we show the stock
       price for each ticker". A discrete tap, so it never competes with the
       shell's horizontal paging drag.

       ⚠ THE HERO AND THE FOOTER DO NOT SWAP. Best, Worst and Up are readings
       ABOUT the percentages; a price in those slots would answer a question
       nobody asked. Only the per-name column changes. */
    /* ⚠ VERIFICATION ONLY on the launch argument, exactly as `-showMoney` is:
       the simulator's touch bridge crashes, so `-showPrice` forces the state
       and proves the RENDERING. It does not test the tap. */
    @State private var showPrice = ProcessInfo.processInfo.arguments.contains("-showPrice")

    /// Worst first, the same queue-of-work order Roll check uses. A name with
    /// no history for this window is dropped, not drawn at zero — see the
    /// server's note on why the move is null rather than 0.
    private var rows: [Row] {
        prices.rows.compactMap { r in
            r.pct.value(window).map {
                Row(id: r.ticker, ticker: r.ticker, pct: $0, spot: r.spot)
            }
        }.sorted { $0.pct < $1.pct }
    }

    private var nameCol: CGFloat {
        min(134, max(S.progNameCol,
                     (rows.map { S.textW($0.ticker, S.t12, S.wSemiN) }.max() ?? 0) + 3))
    }
    /* ⚠ MEASURED ACROSS BOTH STATES. Sizing to whichever is showing would
       resize the column on every tap, and the track and all seven bars would
       jump with it. "$138.70" is wider than "-5.0%", so the wider of the two
       fixes the geometry once. */
    private var valCol: CGFloat {
        let w = rows.flatMap { r -> [CGFloat] in
            [S.textW(pctLabel(r.pct), S.t13, S.wSemiN),
             S.textW(priceLabel(r.spot), S.t13, S.wSemiN)]
        }.max() ?? 0
        return max(S.progValCol, w + 3)
    }
    private var rowTrack: CGFloat {
        max(110, S.content - 38 - nameCol - valCol - 2 * S.gap4)
    }

    /// One decimal, because a price move of −0.6% rounds to −1% and reads as
    /// six times the day it had. Roll check's integers are fine for capture,
    /// which is never this small.
    private func pctLabel(_ v: Double) -> String {
        String(format: "%@%.1f%%", v < 0 ? "\u{2212}" : "", abs(v))
    }
    /* Two decimals, the way a quote is written. An em dash when the price has
       not arrived, never 0.00, which would read as a stock at nothing. */
    private func priceLabel(_ v: Double?) -> String {
        guard let v, v > 0 else { return "\u{2014}" }
        return String(format: "$%.2f", v)
    }

    var body: some View {
        let vals = rows.map(\.pct)
        /* Both ends get headroom off the data, so the zero line is never pinned
           to an edge even when every name is red — which, this month, it is. */
        let mx = max(vals.max() ?? 0, 0), mn = min(vals.min() ?? 0, 0)
        let span = max(mx - mn, 1)
        let hi = mx + span * 0.08, lo = mn - span * 0.08
        let track = rowTrack
        let x = { (v: Double) in track * CGFloat((v - lo) / max(hi - lo, 0.0001)) }
        let bookPct = prices.book.value(window)

        return OptCard(name: "stock-price", fixedHeight: nil) {
            OptHead(title: "Stock price", sub: "spot",
                    right: "\(rows.count) names")
            Spacer().frame(height: S.gap7)
            VStack(alignment: .leading, spacing: 5) {
                Text("BOOK MOVE")
                    .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.mute)
                HStack(alignment: .firstTextBaseline, spacing: S.gap3) {
                    Text(bookPct.map(pctLabel) ?? "\u{2014}")
                        .font(S.inter(S.t30, S.wBoldN)).tracking(S.track(S.t30, -0.03))
                        .foregroundStyle((bookPct ?? 0) < 0 ? S.loss : S.gain)
                        .sunnyLineBox(S.t30)
                    Text(window.phrase)
                        .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
                }
            }
            Spacer().frame(height: 14)
            /* The filter. A discrete tap per pill, so it never competes with
               the shell's horizontal paging drag. */
            HStack(spacing: S.gap3) {
                ForEach(PriceWindow.allCases) { w in
                    Text(w.label)
                        .font(S.inter(S.t11, S.wSemiN))
                        .tracking(S.track(S.t11, 0.02))
                        .foregroundStyle(w == window ? S.onInk : S.mute)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 999)
                                .fill(w == window ? S.ink : S.wash))
                        .contentShape(Rectangle())
                        .onTapGesture { window = w }
                }
                Spacer(minLength: 0)
            }
            Spacer().frame(height: 16)
            ZStack(alignment: .topLeading) {
                VStack(spacing: S.progRowGap) {
                    ForEach(rows) { r in
                        HStack(spacing: S.gap4) {
                            Text(r.ticker)
                                .font(S.inter(S.t12, S.wSemiN)).tracking(S.track(S.t12, -0.01))
                                .foregroundStyle(S.ink)
                                .frame(width: nameCol, alignment: .leading).lineLimit(1)
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: S.radiusBar).fill(S.wash)
                                RoundedRectangle(cornerRadius: S.radiusBar)
                                    .fill(r.pct < 0 ? S.lossBar : S.gainBar)
                                    .frame(width: max(2, x(max(r.pct, 0)) - x(min(r.pct, 0))))
                                    .offset(x: x(min(r.pct, 0)))
                            }
                            .frame(width: track, height: S.progRowH)
                            /* The price is a fact, not a direction, so it
                               takes --ink and not the gain/loss ink. Only the
                               percentage is an opinion about the day. */
                            Text(showPrice ? priceLabel(r.spot) : pctLabel(r.pct))
                                .font(S.inter(S.t13, S.wSemiN)).monospacedDigit()
                                .foregroundStyle(showPrice ? S.ink
                                                 : (r.pct < 0 ? S.lossText : S.gainText))
                                .frame(width: valCol, alignment: .trailing).lineLimit(1)
                        }
                    }
                }
                /* The only vertical on this card. */
                Rectangle().fill(S.ruleColorStrong).frame(width: 1)
                    .offset(x: nameCol + S.gap4 + x(0), y: -4)
                    .frame(maxHeight: .infinity).padding(.bottom, -4)
            }
            Spacer().frame(height: 22)
            OptFooter(stats: [
                .init(label: "Best",
                      value: rows.last.map { pctLabel($0.pct) } ?? "\u{2014}",
                      ink: (rows.last?.pct ?? 0) < 0 ? S.lossText : S.gainText),
                .init(label: "Worst",
                      value: rows.first.map { pctLabel($0.pct) } ?? "\u{2014}",
                      ink: (rows.first?.pct ?? 0) < 0 ? S.lossText : S.gainText),
                .init(label: "Up",
                      value: "\(rows.filter { $0.pct > 0 }.count) of \(rows.count)",
                      ink: S.ink),
            ])
        }
        /* A discrete tap, so it never competes with the shell's horizontal
           paging drag. Same gesture as Roll check and Weekly yield. */
        .contentShape(Rectangle())
        .onTapGesture { showPrice.toggle() }
    }
}

// MARK: - inventory

/// ⚠ WHAT CAN STILL BE SOLD. handoff/cards/inventory.md, redesigned 8 Sep 2026.
/// The first design drew one circle per contract; NKE holds 60 calls and 30 puts
/// against that sheet's widest name of 15 and 10, so a mark per contract could
/// not stay on one line at a legible diameter. Chips carry any count.
///
/// ⚠ FREE HEIGHT. 361 is a FLOOR, never a size: no pager, no scroll, no control.
/// The list IS the card, so the card is as tall as the book.
///
/// ⚠ NO DIRECTION INK ANYWHERE. Capacity is not a gain and not a loss. Six inks,
/// and the only non-ink colours are the chip wash and the two rules.
struct SunnyInventory: View {
    let rows: [InventoryRow]

    /// Room descending, ties alphabetical. With no pager and no tabs the first
    /// chip has to be the one he would act on.
    private var withRoom: [InventoryRow] {
        rows.filter { $0.room > 0 }
            .sorted { $0.room != $1.room ? $0.room > $1.room : $0.t < $1.t }
    }
    /// A name with nothing left to sell takes no chip: it is one grey line at the
    /// foot, named but not ranked.
    private var fullySold: [InventoryRow] {
        rows.filter { $0.room == 0 && $0.held > 0 }.sorted { $0.t < $1.t }
    }
    private var openCalls: Int { rows.reduce(0) { $0 + $1.openCalls } }
    private var openPuts: Int { rows.reduce(0) { $0 + $1.openPuts } }
    private var held: Int { rows.reduce(0) { $0 + $1.held } }
    private var sold: Int { rows.reduce(0) { $0 + $1.sold } }

    /// `10c · 30p`, and a zero side is omitted — a zero in a capacity list reads
    /// as an instruction not to bother.
    private func chipCount(_ r: InventoryRow) -> String {
        [r.openCalls > 0 ? "\(r.openCalls)c" : nil,
         r.openPuts  > 0 ? "\(r.openPuts)p"  : nil]
            .compactMap { $0 }.joined(separator: " \u{00B7} ")
    }
    private func chipWidth(_ r: InventoryRow) -> CGFloat {
        12 + S.textW(r.t, S.t13, S.wSemiN) + 7
           + S.textW(chipCount(r), S.t13, S.wMidSmN) + 12
    }
    /// Greedy wrap at the 323 content column. SwiftUI has no flow container that
    /// also honours an exact 9px gap on both axes, and the sheet measures both.
    private var chipRows: [[InventoryRow]] {
        var out: [[InventoryRow]] = [], line: [InventoryRow] = [], w: CGFloat = 0
        for r in withRoom {
            let cw = chipWidth(r)
            if !line.isEmpty && w + 9 + cw > S.content - 38 {
                out.append(line); line = [r]; w = cw
            } else {
                w += (line.isEmpty ? 0 : 9) + cw; line.append(r)
            }
        }
        if !line.isEmpty { out.append(line) }
        return out
    }

    var body: some View {
        OptCard(name: "inventory", fixedHeight: nil) {
            OptHead(title: "Inventory", sub: "all tickers",
                    right: "\(rows.count) names \u{00B7} \(held) contracts")
            Spacer().frame(height: 20)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                /* 81 is a SUM, never a stored total. */
                Text("\(openCalls + openPuts)")
                    .font(S.inter(S.t22, S.wBoldN)).tracking(S.track(S.t22, -0.03))
                    .foregroundStyle(S.ink).sunnyLineBox(S.t22)
                Text("can still be sold")
                    .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
            }
            Spacer().frame(height: 8)
            Text("\(openCalls) calls \u{00B7} \(openPuts) puts \u{00B7} on \(withRoom.count) names")
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)

            Spacer().frame(height: 20)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 18)

            HStack(spacing: S.gap4) {
                Text("WHERE")
                    .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.mute)
                Spacer(minLength: 0)
                Text("\(withRoom.count) names")
                    .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
            }
            Spacer().frame(height: 13)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(chipRows.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 9) {
                        ForEach(line) { r in
                            HStack(spacing: 7) {
                                Text(r.t)
                                    .font(S.inter(S.t13, S.wSemiN)).foregroundStyle(S.ink)
                                Text(chipCount(r))
                                    .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
                            }
                            .padding(.horizontal, 12).frame(height: 28)
                            .background(Capsule().fill(S.wash))
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            /* Omitted entirely when nothing is fully sold: the line is a
               statement about names that exist, not an empty slot. */
            if !fullySold.isEmpty {
                Spacer().frame(height: 14)
                Text("\(fullySold.count) name\(fullySold.count == 1 ? "" : "s") fully sold \u{00B7} "
                     + fullySold.map(\.t).joined(separator: " \u{00B7} "))
                    .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
            }

            Spacer().frame(minHeight: 24)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 18)

            /* Calls + puts = the hero. That identity is the card's only
               self-check; if it fails, a figure is being stored somewhere it
               should be derived. Figures are 15 here, not 19 — at 19 against a
               22 hero the card had three competing sizes. */
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array([("Calls to sell", openCalls),
                               ("Puts to sell", openPuts),
                               ("Worked", 0)].enumerated()), id: \.offset) { i, cell in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(cell.0.uppercased())
                            .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                            .foregroundStyle(S.mute)
                        Text(i == 2
                             ? "\(held > 0 ? Int((Double(sold) / Double(held) * 100).rounded()) : 0)%"
                             : "\(cell.1)")
                            .font(S.inter(S.t15, S.wBoldN)).tracking(S.track(S.t15, -0.02))
                            .foregroundStyle(S.ink)
                    }
                    .padding(.leading, i == 0 ? 0 : 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - average credit

/// ⚠ PER SHARE, NEVER PER CONTRACT. handoff/cards/average-credit.md.
/// $0.60, not $60 — the number quoted when the trade is placed.
///
/// ⚠ COLOUR IS A COMPARISON THE CARD ALSO PRINTS. Each side is green at or above
/// ITS OWN past average and red below it, and that average is printed under the
/// figure and drawn as a line across its own plot. No sentence explains the test.
///
/// ⚠ THE PLOT SCALE IS PER SIDE AND TRUNCATED, so a bar is a SHAPE and not a
/// quantity. Two consequences, both deliberate: no bar is labelled, and the two
/// columns are NOT height-comparable to each other.
struct SunnyAvgCredit: View {
    let credit: CreditBlock

    private static let plotH: CGFloat = 132

    private func figure(_ ws: [CreditWeek]) -> Double? { ws.last?.perShare }
    /// The mean of the three PRIOR weeks, skipping any that did not trade.
    private func pastAvg(_ ws: [CreditWeek]) -> Double? {
        let past = ws.dropLast().compactMap(\.perShare)
        return past.isEmpty ? nil : past.reduce(0, +) / Double(past.count)
    }
    /// lo is a share of the window's own RANGE, never of its minimum: a
    /// proportional floor only pads narrow windows and puts two different weeks
    /// on the same stub.
    private func scale(_ ws: [CreditWeek]) -> (lo: Double, hi: Double) {
        let vs = ws.compactMap(\.perShare)
        guard let mn = vs.min(), let mx = vs.max() else { return (0, 1) }
        let r = (mx - mn) == 0 ? (mn == 0 ? 1 : mn) : (mx - mn)
        return (mn - r * 0.35, mx + r * 0.06)
    }
    private func frac(_ v: Double, _ s: (lo: Double, hi: Double)) -> Double {
        s.hi - s.lo <= 0 ? 0 : min(1, max(0, (v - s.lo) / (s.hi - s.lo)))
    }
    private func money2(_ v: Double) -> String { String(format: "$%.2f", v) }
    /// "9/7" — a 146px column will not hold "Sep 7" four times.
    private func key(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]) else { return iso }
        return "\(m)/\(d)"
    }
    private func headerWeek(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        let mon = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m)
        else { return iso }
        return "\(mon[m - 1]) \(d)"
    }

    @ViewBuilder private func column(_ label: String, _ ws: [CreditWeek]) -> some View {
        let fig = figure(ws), avg = pastAvg(ws), sc = scale(ws)
        /* Ink when there is no past average to judge against — a colour with
           nothing behind it would be an opinion the card cannot print. */
        let ink: Color = (fig == nil || avg == nil) ? S.ink
            : (fig! >= avg! ? S.gainText : S.lossText)
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute)
            Spacer().frame(height: 9)
            Text(fig.map(money2) ?? "\u{2014}")
                .font(S.inter(S.t22, S.wBoldN)).tracking(S.track(S.t22, -0.03))
                .foregroundStyle(ink).sunnyLineBox(S.t22)
            Spacer().frame(height: 8)
            Text(avg.map { "average \(money2($0))" } ?? "no history yet")
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
            Spacer().frame(height: 18)
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 9) {
                    ForEach(Array(ws.enumerated()), id: \.element.week) { i, w in
                        /* No bar at all when the side did not trade, and the key
                           below still prints: the gap has to read as a gap. */
                        if let v = w.perShare {
                            UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                                .fill(i == ws.count - 1 ? ink : S.barQuiet)
                                .frame(maxWidth: .infinity)
                                .frame(height: max(2, Self.plotH * frac(v, sc)))
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 1)
                        }
                    }
                }
                if let avg {
                    /* The same number printed above it, drawn where it falls.
                       --ink at 1.5: an average is a rate, so it never takes the
                       state ink. */
                    Rectangle().fill(S.ink).frame(height: 1.5)
                        .offset(y: -Self.plotH * frac(avg, sc))
                }
            }
            .frame(height: Self.plotH, alignment: .bottom)
            Spacer().frame(height: 9)
            HStack(spacing: 9) {
                ForEach(ws) { w in
                    Text(key(w.week))
                        .font(S.inter(S.t10, S.wMidSmN)).foregroundStyle(S.mute)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    var body: some View {
        let n = min(credit.calls.count, credit.puts.count)
        let thisN = (credit.calls.last?.contracts ?? 0) + (credit.puts.last?.contracts ?? 0)
        let avgN = n == 0 ? 0 : (0..<n).reduce(0) {
            $0 + credit.calls[$1].contracts + credit.puts[$1].contracts
        } / n
        OptCard(name: "avg-credit") {
            OptHead(title: "Average credit", sub: "per share",
                    right: headerWeek(credit.week))
            /* 20 is load-bearing: at 0 the CALLS/PUTS labels read as a second
               line of the header. */
            Spacer().frame(height: 20)
            HStack(alignment: .top, spacing: 15) {
                column("CALLS", credit.calls)
                /* The only rule on the card. It exists because the two columns
                   are on different scales: it says these are two readings, not
                   one four-column row. */
                Rectangle().fill(S.ruleColorStrong)
                    .frame(width: 1).frame(maxHeight: .infinity)
                column("PUTS", credit.puts)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer().frame(minHeight: 20)
            /* Contracts per WEEK, not per side — the average has to be
               comparable to the single week beside it. */
            Text("This week \(thisN) contracts \u{00B7} average \(avgN)")
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
        }
    }
}

// MARK: - 01 · Programme

/// ⚠ AM I UP, AND THEN ON WHICH NAME. handoff-final/01. Opens on All, so the
/// all-in reading is never gated behind choosing a name.
///
/// ⚠ THE HERO IS THE SUM OF ITS OWN FOOTER: `banked + owed + mark == net`.
/// Nothing here is stored; every figure is derived from the per-name rows, so a
/// corrected component moves the hero with it. A hero that can disagree with
/// its own footer is the one defect that would make this card worthless.
///
/// ⚠ SINCE 31 AUGUST, the LEAP shift. Nik, 2026-09-10. That start makes the
/// card read −$12,488 rather than the handoff's +$15,065: most of the credits
/// were earned before it, against shares he no longer holds.
struct SunnyProgramme: View {
    let block: ProgrammeBlock

    @State private var sel: String? = nil          // nil = All

    /// The All row is the SUM of the names, never a stored total.
    private var all: ProgrammeRow {
        let r = block.rows
        return ProgrammeRow(t: "All",
                            kept: r.reduce(0) { $0 + $1.kept },
                            calls: r.reduce(0) { $0 + $1.calls },
                            puts: r.reduce(0) { $0 + $1.puts },
                            owed: r.reduce(0) { $0 + $1.owed },
                            invested: r.reduce(0) { $0 + $1.invested })
    }
    private var row: ProgrammeRow {
        sel.flatMap { s in block.rows.first { $0.t == s } } ?? all
    }
    /// Names by net descending, so the best-standing name reads first.
    private var order: [ProgrammeRow] { block.rows.sorted { $0.net > $1.net } }

    private func sinceLabel() -> String {
        let p = block.since.split(separator: "-")
        let mon = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m)
        else { return block.since }
        return "since \(d) \(mon[m - 1])"
    }

    var body: some View {
        let r = row
        let markPos = r.mark >= 0
        let span = max(abs(r.kept) + abs(r.mark), 1)
        OptCard(name: "programme") {
            OptHead(title: "Programme", sub: sel == nil ? "all in" : "one name",
                    right: sinceLabel())
            Spacer().frame(height: 14)

            /* Wraps to two rows at 361 and that is fine. */
            SunnyChipWrap(items: ["All"] + order.map(\.t), selected: sel ?? "All") { tapped in
                sel = tapped == "All" ? nil : tapped
            }

            Spacer().frame(height: 20)
            Text("NET")
                .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute)
            Spacer().frame(height: 11)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(optMoney(r.net))
                    .font(S.inter(S.t22, S.wBoldN)).tracking(S.track(S.t22, -0.03))
                    .foregroundStyle(r.net < 0 ? S.lossText : S.gainText)
                    .sunnyLineBox(S.t22)
                Text("\(r.net < 0 ? "down" : "up") \(String(format: "%.1f", abs(r.pct)))%")
                    .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
            }
            Spacer().frame(height: 9)
            Text("on \(optMoney(r.invested)) invested")
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)

            Spacer().frame(height: 20)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 18)

            Text("WHAT IT IS MADE OF")
                .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute)
            Spacer().frame(height: 14)

            /* ⚠ INK BY SIGN, NEVER BY ROW. A long call can be a gain — LULU and
               BABA have been — so nothing here is hardcoded to loss ink. */
            VStack(alignment: .leading, spacing: 13) {
                ForEach(Array([("Credits kept", r.kept), ("Long calls", r.calls),
                               ("Long puts", r.puts)].enumerated()), id: \.offset) { _, cell in
                    HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
                        Text(cell.0).font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink)
                        Spacer(minLength: 0)
                        Text(optMoney(cell.1))
                            .font(S.inter(S.t14, S.wBoldN)).tracking(S.track(S.t14, -0.02))
                            .foregroundStyle(cell.1 < 0 ? S.lossText : S.gainText)
                    }
                }
            }

            Spacer().frame(height: 16)
            GeometryReader { g in
                HStack(spacing: 0) {
                    Rectangle().fill(S.gainText)
                        .frame(width: g.size.width * CGFloat(abs(r.kept)) / CGFloat(span))
                    Rectangle().fill(markPos ? S.gainText : S.lossText)
                        .frame(width: g.size.width * CGFloat(abs(r.mark)) / CGFloat(span))
                    Rectangle().fill(S.wash)
                }
            }
            .frame(height: 8).clipShape(RoundedRectangle(cornerRadius: 4))
            Spacer().frame(height: 10)
            Text("Credits are banked. The two marks move every day and are not yours until you close.")
                .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                .lineSpacing(S.t11 * 0.4).fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 20)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 18)
            OptFooter(stats: [
                .init(label: "Banked", value: optMoney(r.banked), ink: S.ink),
                /* ⚠ "Owed on open" TRUNCATED TO "OWED ON OP…" at 10/700 in a
                   third of 323. The deck settled this once already, when
                   "Current value" became "Worth now". Banked · Owed · At mark
                   reads as one set anyway. */
                .init(label: "Owed", value: optMoney(r.owed), ink: S.ink),
                .init(label: "At mark", value: optMoney(r.mark), ink: S.ink),
            ])
        }
    }
}

/// The name strip. Wrapped by hand for the same reason the inventory chips are:
/// SwiftUI has no flow container that also honours an exact gap on both axes.
private struct SunnyChipWrap: View {
    let items: [String]
    let selected: String
    let tap: (String) -> Void

    private func w(_ s: String) -> CGFloat { 20 + S.textW(s, S.t11, S.wSemiN) }

    private var rows: [[String]] {
        var out: [[String]] = [], line: [String] = [], used: CGFloat = 0
        for i in items {
            let cw = w(i)
            if !line.isEmpty && used + 6 + cw > S.content - 38 {
                out.append(line); line = [i]; used = cw
            } else { used += (line.isEmpty ? 0 : 6) + cw; line.append(i) }
        }
        if !line.isEmpty { out.append(line) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 6) {
                    ForEach(line, id: \.self) { i in
                        let on = i == selected
                        Text(i)
                            .font(S.inter(S.t11, S.wSemiN))
                            .foregroundStyle(on ? S.onInk : S.mute)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(on ? S.ink : S.paper))
                            .overlay(Capsule().stroke(on ? S.ink : S.ruleColorStrong, lineWidth: 1))
                            .contentShape(Capsule())
                            .onTapGesture { tap(i) }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - 02 · Premium now

/// ⚠ A MULTIPLE OF ITS OWN USUAL, NEVER A PERCENTILE. handoff-final/02. The
/// rank was what made the earlier version unreadable; today's IV against the
/// name's own median is the whole reading.
///
/// ⚠ THE TRACK IS THAT NAME'S OWN RANGE, so no row is comparable to any other.
/// The bar runs from the usual line to today: its LENGTH is the distance from
/// normal and its SIDE is the direction.
///
/// ⚠ AND IT SAYS THREE MONTHS BECAUSE THAT IS WHAT EXISTS. The build sheet asks
/// for a year; `ticker_iv_daily` holds 60 days. Nik chose to ship on the real
/// history and label it honestly rather than claim a year.
struct SunnyPremiumNow: View {
    let block: PremiumBlock

    private static let richAt = 1.15

    private var best: PremiumRow? { block.rows.first }
    private var window: String {
        let m = Int((Double(block.days) / 21.0).rounded())
        return m >= 12 ? "past year" : "past \(max(m, 1)) month\(m == 1 ? "" : "s")"
    }

    var body: some View {
        OptCard(name: "premium-now") {
            OptHead(title: "Premium now", sub: "vs its own usual",
                    right: fmtDayLabel(Date()))
            Spacer().frame(height: 26)

            if let b = best {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(format: "%.2f\u{00D7}", b.mult))
                        .font(S.inter(S.t22, S.wBoldN)).tracking(S.track(S.t22, -0.03))
                        .foregroundStyle(b.mult >= Self.richAt ? S.gainText : S.ink)
                        .sunnyLineBox(S.t22)
                    Text("its usual, on \(b.t)")
                        .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
                }
                Spacer().frame(height: 9)
                Text("the best the book is paying today")
                    .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
            } else {
                Text("\u{2014}").font(S.inter(S.t22, S.wBoldN)).foregroundStyle(S.mute)
                Spacer().frame(height: 9)
                Text("no name has enough history yet")
                    .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
            }

            Spacer().frame(height: 26)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 22)

            Text("EACH NAME ON ITS OWN \(window.uppercased())")
                .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute)
            Spacer().frame(height: 14)

            VStack(alignment: .leading, spacing: 30) {
                ForEach(block.rows) { r in
                    VStack(alignment: .leading, spacing: 11) {
                        HStack(spacing: 12) {
                            Text(r.t)
                                .font(S.inter(S.t13, S.wSemiN)).foregroundStyle(S.ink)
                                .frame(width: 44, alignment: .leading)
                            GeometryReader { g in
                                let lo = min(r.posNow, r.posUsual), hi = max(r.posNow, r.posUsual)
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2).fill(S.wash)
                                    /* Rich only: everything else is --hair, so the
                                       one row worth acting on is the only colour. */
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(r.mult >= Self.richAt ? S.gainBar : S.hair)
                                        .frame(width: max(2, g.size.width * CGFloat(hi - lo)))
                                        .offset(x: g.size.width * CGFloat(lo))
                                    /* The usual, overhanging the track so it can
                                       never be mistaken for a segment. */
                                    Rectangle().fill(S.ink).frame(width: 2)
                                        .frame(height: 22)
                                        .offset(x: g.size.width * CGFloat(r.posUsual) - 1)
                                }
                            }
                            .frame(height: 14)
                            /* The bar carries the state; the figure never repeats it. */
                            Text(String(format: "%.2f\u{00D7}", r.mult))
                                .font(S.inter(S.t15, S.wBoldN)).tracking(S.track(S.t15, -0.02))
                                .monospacedDigit().foregroundStyle(S.ink)
                                .lineLimit(1).fixedSize()
                                .frame(width: 46, alignment: .trailing)
                        }
                        Text(String(format: "%.1f%% today \u{00B7} %.1f%% usual", r.now, r.usual))
                            .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute2)
                            .padding(.leading, 56)
                    }
                }
            }

            Spacer(minLength: 26)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 22)
            OptFooter(stats: [
                .init(label: "Rich",
                      value: "\(block.rows.filter { $0.mult >= Self.richAt }.count)", ink: S.ink),
                .init(label: "Book IV",
                      value: block.rows.isEmpty ? "\u{2014}"
                        : String(format: "%.1f%%",
                                 block.rows.reduce(0) { $0 + $1.now } / Double(block.rows.count)),
                      ink: S.ink),
                .init(label: "Readable", value: "\(block.rows.count)", ink: S.ink),
            ])
        }
    }
}

/// "Wed 10 Sep" — the deck's own header date.
func fmtDayLabel(_ d: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f.string(from: d)
}

// MARK: - 03 · Upside left

/// ⚠ WHAT YOU MAKE WHEN THE STOCK MAKES 10%, in the unit he would quote: NKE
/// makes 5.2% when NKE makes 10%. handoff-final/03.
///
/// ⚠ THE PUTS ARE IN IT. Nik, 2026-09-10: "include puts as well". They are a
/// third of the capital, and leaving them out read 73% where the book keeps 67.
///
/// ⚠ THE AXIS RUNS PAST THE TICK ON PURPOSE. A short put that goes into the
/// money is LONG delta, so a name can make MORE than the stock does: LULU is at
/// 123% today. The tick at 10% is the move itself, so short of it is capped and
/// past it is more than the stock made.
///
/// ⚠ AND A RISING NUMBER HERE IS NOT ALWAYS GOOD NEWS. The book went 38% → 67%
/// in two days largely because short puts went against him, which the To roll
/// card is showing as a loss. Same fact, two cards, opposite feelings.
struct SunnyUpsideLeft: View {
    let block: UpsideBlock

    /* ⚠ MEASURED, NOT ASSUMED. 46 fits "8.0%" and not "13.2%", so LULU wrapped
       onto a second line and broke the row's baseline — the same lesson the
       roll-check columns learned. A name past 100% is normal here, so the
       column has to take its widest actual content. */
    private var valCol: CGFloat {
        let w = block.rows.map { S.textW(gainLabel($0.share), S.t15, S.wBoldN) }.max() ?? 0
        return max(46, w + 3)
    }
    private func gainLabel(_ share: Int) -> String {
        String(format: "%.1f%%", Double(share) / 10)
    }
    /// The longest figure the rows will print, used to reserve the column.
    private var widest: String {
        block.rows.map { gainLabel($0.share) }
            .max { S.textW($0, S.t15, S.wBoldN) < S.textW($1, S.t15, S.wBoldN) } ?? "0.0%"
    }

    /// Headroom above the widest row, so nothing is ever clipped at the tick.
    private var axisMax: Double {
        let widest = Double(block.rows.map(\.share).max() ?? 100) / 10
        return max(12, (widest * 1.05).rounded(.up))
    }
    private var tickFrac: Double { Double(block.move) / axisMax }

    var body: some View {
        let cappedCount = block.rows.filter { $0.share < 100 }.count
        OptCard(name: "upside-left") {
            OptHead(title: "Upside left", sub: "if the stock makes \(block.move)%",
                    right: "whole book")
            Spacer().frame(height: 26)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "+%.1f%%", block.share * Double(block.move) / 100))
                    .font(S.inter(S.t22, S.wBoldN)).tracking(S.track(S.t22, -0.03))
                    .foregroundStyle(S.ink).sunnyLineBox(S.t22)
                Text("is what you make")
                    .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
            }
            Spacer().frame(height: 9)
            Text("\(optMoneyShort(block.up)) of a \(optMoneyShort(Int(Double(block.up) / max(block.share, 0.01) * 100))) move")
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)

            Spacer().frame(height: 26)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 22)

            /* The tick label, over the same fraction every row repeats. */
            HStack(spacing: 12) {
                Color.clear.frame(width: 44, height: 11)
                GeometryReader { g in
                    Text("\(block.move)%")
                        .font(S.inter(S.t10, S.wSemiN)).tracking(S.track(S.t10, S.lsLabel))
                        .foregroundStyle(S.mute)
                        .frame(width: 40)
                        .offset(x: g.size.width * CGFloat(tickFrac) - 20)
                }
                .frame(height: 11)
                /* The header's spacer is the WIDEST ACTUAL LABEL, drawn
                   invisibly, so the tick stays over the same fraction the rows
                   use however wide the figures turn out to be. */
                Text(widest)
                    .font(S.inter(S.t15, S.wBoldN)).tracking(S.track(S.t15, -0.02))
                    .monospacedDigit().lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: valCol, alignment: .trailing)
                    .layoutPriority(1).opacity(0)
            }
            Spacer().frame(height: 12)

            VStack(alignment: .leading, spacing: 22) {
                ForEach(block.rows) { r in
                    let gain = Double(r.share) / 10
                    HStack(spacing: 12) {
                        Text(r.t)
                            .font(S.inter(S.t13, S.wSemiN)).foregroundStyle(S.ink)
                            .frame(width: 44, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2).fill(S.wash)
                                /* One exception, one colour: only the tightest
                                   cap is inked. */
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(r.t == block.rows.first?.t ? S.lossBar : S.hair)
                                    .frame(width: max(2, g.size.width * CGFloat(min(gain / axisMax, 1))))
                                Rectangle().fill(S.ink).frame(width: 2).frame(height: 22)
                                    .offset(x: g.size.width * CGFloat(tickFrac) - 1)
                            }
                        }
                        .frame(height: 14)
                        /* ⚠ minWidth AND layoutPriority, NOT A FIXED WIDTH.
                           Nik, 2026-09-10: "I dont like % on a different line
                           looks odd" — LULU read 14.5 with the % underneath it.
                           A fixed frame lets the HStack hand the flexible bar
                           its width first and squeeze whatever is left to the
                           figure; the column has to be the rigid one and the
                           bar the one that yields. */
                        Text(gainLabel(r.share))
                            .font(S.inter(S.t15, S.wBoldN)).tracking(S.track(S.t15, -0.02))
                            .monospacedDigit().foregroundStyle(S.ink)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: valCol, alignment: .trailing)
                            .layoutPriority(1)
                    }
                }
            }

            Spacer(minLength: 26)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 22)
            OptFooter(stats: [
                .init(label: "If +\(block.move)%", value: optMoneyShort(block.up), ink: S.gainText),
                /* ⚠ DELTA-ONLY. Long puts are convex, so a real fall is better
                   than this. Left visible rather than hidden. */
                .init(label: "If \u{2212}\(block.move)%", value: optMoneyShort(block.down), ink: S.lossText),
                .init(label: "Capped", value: "\(cappedCount)", ink: S.ink),
            ])
        }
    }
}

// MARK: - 04 · To roll

/// ⚠ NO ASSIGNMENT LANGUAGE ANYWHERE. This book rolls. handoff-final/04.
///
/// ⚠ THE LEFT HALF IS THE LEG, THE RIGHT HALF IS THE NAME, and the right half
/// is labelled ALL TIME because that scope change is otherwise invisible: Nik
/// read "Kept $4,035" as belonging to the $110 put beside it and asked where
/// the card said otherwise. It did not.
///
/// The label also settles the duplicate. When a name has an in-the-money call
/// AND put they land in different groups and both carry the same history; with
/// ALL TIME on each that reads as one standing fact stated twice, and without
/// it, it reads as a bug.
struct SunnyToRoll: View {
    let block: ToRollBlock

    private var calls: [RollLeg] { block.legs.filter { $0.side == "call" }.sorted { $0.loss > $1.loss } }
    private var puts: [RollLeg] { block.legs.filter { $0.side == "put" }.sorted { $0.loss > $1.loss } }
    private var sold: Int { block.legs.reduce(0) { $0 + $1.sold } }
    private var buy: Int { block.legs.reduce(0) { $0 + $1.now } }

    var body: some View {
        OptCard(name: "to-roll", fixedHeight: nil) {
            OptHead(title: "To roll", sub: "as of today", right: fmtDayLabel(Date()))
            Spacer().frame(height: 26)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(optMoney(sold - buy))
                    .font(S.inter(S.t22, S.wBoldN)).tracking(S.track(S.t22, -0.03))
                    .foregroundStyle(sold - buy < 0 ? S.lossText : S.gainText)
                    .sunnyLineBox(S.t22)
                Text("to roll all \(block.legs.count)")
                    .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
            }
            Spacer().frame(height: 9)
            Text("sold for \(optMoney(sold)) \u{00B7} buying back at \(optMoney(buy))")
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)

            Spacer().frame(height: 26)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 22)

            /* ⚠ AN EMPTY GROUP IS HIDDEN, not shown as a bare heading. Today no
               call is in the money, so CALLS would otherwise be a label with
               nothing under it. */
            if !calls.isEmpty { group("CALLS", calls) }
            if !calls.isEmpty && !puts.isEmpty { Spacer().frame(height: 26) }
            if !puts.isEmpty { group("PUTS", puts) }
            if block.legs.isEmpty {
                Text("Nothing is in the money")
                    .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
            }

            Spacer(minLength: 26)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 22)
            OptFooter(stats: [
                .init(label: "This week", value: optMoney(block.week), ink: S.ink),
                .init(label: "To close", value: optMoney(buy), ink: S.lossText),
                .init(label: "Net", value: optMoney(block.week - buy), ink: S.ink),
            ])
        }
    }

    @ViewBuilder private func group(_ label: String, _ legs: [RollLeg]) -> some View {
        Text(label)
            .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
            .foregroundStyle(S.mute)
        Spacer().frame(height: 18)
        VStack(alignment: .leading, spacing: 30) {
            ForEach(legs) { l in row(l) }
        }
    }

    @ViewBuilder private func row(_ l: RollLeg) -> some View {
        let h = block.names[l.t]
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(l.t)
                        .font(S.inter(S.t14, S.wBoldN)).tracking(S.track(S.t14, -0.01))
                        .foregroundStyle(S.ink)
                    Text("\(priceShortLabel(l.strike)) \u{00D7} \(l.n)")
                        .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute2)
                    Spacer(minLength: 0)
                }
                Spacer().frame(height: 13)
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(optMoney(-l.loss))
                        .font(S.inter(S.t19, S.wBoldN)).tracking(S.track(S.t19, -0.03))
                        .foregroundStyle(S.lossText)
                    Text("\(Int(l.lossPct.rounded()))%")
                        .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
                }
                Spacer().frame(height: 10)
                Text("sold \(optMoney(l.sold)) \u{2192} buy \(optMoney(l.now))")
                    .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(S.ruleColor).frame(width: 1).frame(maxHeight: .infinity)

            /* ⚠ 132 WIDE, AND DO NOT NARROW IT. "Rolled back" wraps below ~78
               and breaks the baseline of the whole column. */
            VStack(alignment: .leading, spacing: 11) {
                Text("ALL TIME")
                    .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.mute)
                hist("Kept", optMoney(h?.kept ?? 0), S.ink2)
                hist("Rolled back", optMoney(-(h?.given ?? 0)), S.lossText)
                hist("LEAP", optMoney(h?.leap ?? 0), (h?.leap ?? 0) < 0 ? S.lossText : S.gainText)
            }
            .frame(width: 132, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func hist(_ k: String, _ v: String, _ ink: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(k).font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute).lineLimit(1)
            Spacer(minLength: 0)
            Text(v).font(S.inter(S.t12, S.wSemiN)).foregroundStyle(ink).lineLimit(1)
        }
    }
}

/// "$37.50" / "$110" — a strike, without cents when it has none.
func priceShortLabel(_ v: Double) -> String {
    v == v.rounded() ? String(format: "$%.0f", v) : String(format: "$%.2f", v)
}
