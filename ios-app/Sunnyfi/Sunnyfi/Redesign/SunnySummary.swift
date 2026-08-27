//
//  SunnySummary.swift
//  Sunny — the summary list row, and the six lists built from it.
//  handoff/summary-lists.md.
//
//  ⚠ ONE ROW, THREE SLOTS, READ LEFT TO RIGHT: WHO · HOW MUCH · WHY. Subject,
//  figure, support. All six lists are this row. What changes between cards is
//  the NUMBER OF SUPPORT LINES — A one, B two, C three, and there is no four. A
//  fourth fact belongs on the name's own page. This is the same limit the
//  retired 2-up tile grid learned at three slots.
//
//  ⚠ THE RED SLOT FLIPS WITH THE SIGN OF THE FIGURE. Signed figure (net delta,
//  performance) → the FIGURE takes --loss. Unsigned (an average, a strike) →
//  the READING takes --loss-text and the figure stays --ink. Never both: one red
//  slot per row, and §0.3 picks which.
//
//  ⚠ THE EXCEPTION TEST IS DIRECTION-AWARE AND COMPUTED SERVER-SIDE. "Cost
//  above spot" and "P&L negative" both INVERT on a short leg. PEP is the book's
//  only net short and was flagged red on two cards by rules written for longs.
//  Nothing here re-derives an exception from the sign of a number.
//
//  ⚠ SUPPORT NEVER RESTATES THE FIGURE. PEP read `−45 sh` / `−45 since yest`
//  and looked like a copy-paste fault; it now reads `opened yesterday`.
//
//  ⚠ THESE SUPERSEDE SunnyAverageList AND SunnyNetDeltaList, both deleted. The
//  2-up tile grid could not carry a support stack: the figure paid for the
//  column (22px inside a 156 tile) and there was nowhere left to say why.
//

import SwiftUI

// MARK: - the row

/// The support stack's length IS the card's class, so it is not a parameter —
/// it is counted from the lines passed in.
struct SunnySummaryRow: View {
    let ticker: String
    let figure: String
    /// True only where the figure is SIGNED. An unsigned figure never takes
    /// colour however bad the reading is; that is slot 3's job.
    let figureLoss: Bool
    /// Ranked most-decisive first. One, two or three. Each line may carry its
    /// own ink — the moneyness line goes red when a short is ITM.
    let support: [(String, Bool)]
    let exception: Bool

    var body: some View {
        HStack(alignment: .center, spacing: S.rowSlotGap) {
            /* ⚠ THE DOT GUTTER IS RESERVED ON EVERY ROW, empty when the name is
               ordinary. In a single column the tickers form a column of their
               own, and an indent on one row of seven is far more visible than
               the dot is. */
            HStack(spacing: 6) {
                Circle()
                    .fill(exception ? S.loss : .clear)
                    .frame(width: 5, height: 5)
                /* ⚠ 56 IS THE WIDEST TICKER IN THE BOOK AND IT NEVER SHRINKS.
                   At 50 and flexible, BABA (55) and NFLX (52) ate the row's
                   10pt gap and rendered as "BABA +415 sh" with 5pt of air. The
                   figures still aligned, which is exactly the kind of defect
                   that reads as a typesetting fault rather than a rule.

                   ⚠ THE TICKER TAKES --ink, NOT --mute. It is the one word on
                   the row allowed ink, because it names the figure beside it. */
                Text(ticker)
                    .font(S.inter(S.t20, S.wSemiN))
                    .tracking(S.track(S.t20, -0.01))
                    .foregroundStyle(S.ink)
                    .sunnyLineBox(S.t20)
                    .frame(width: S.tickerSlot, alignment: .leading)
                    .lineLimit(1)
            }
            .frame(width: S.tickerSlotBox, alignment: .leading)
            /* ⚠ TICKER AND FIGURE ARE THE SAME SIZE AND THAT IS THE DESIGN.
               Hierarchy inside the line is POSITION and TRACKING (−.01 on the
               name, −.02 on the value), not weight. Sizing the name down makes
               it a label rather than the thing you scan for. */
            Text(figure)
                .font(S.inter(S.t20, S.wSemiN))
                .tracking(S.track(S.t20, -0.02))
                .foregroundStyle(figureLoss ? S.loss : S.ink)
                .sunnyLineBox(S.t20)
                .fixedSize()
            /* ⚠ SUPPORT NUMBERS STAY GREY. This is the deck's one sanctioned
               break from "numbers are ink, words are grey": the whole block is
               subordinate to the figure beside it, so inking its digits would
               give the row two things at the same rank. */
            VStack(alignment: .trailing, spacing: S.supportLineGap) {
                ForEach(Array(support.enumerated()), id: \.offset) { _, line in
                    /* ⚠ THE LINE BOX IS PINNED TO 13 × 1.3, NOT LEFT TO THE
                       FONT. UIKit lays Inter at 13 out in a 15.6 box, and the
                       1.3 line-height the sheet measures is what makes a B row
                       88.8 and a C row 96.7. Unpinned, the option cards came in
                       2.7 short per row and the card heights stopped matching
                       the sheet's arithmetic. */
                    Text(line.0)
                        .font(S.inter(S.t13, S.wMidSmN))
                        .foregroundStyle(line.1 ? S.lossText : S.mute2)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(height: S.t13 * S.lhSupport)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        /* ⚠ CLASS C KEEPS THE SMALLER PADDING ON PURPOSE. Three support lines
           already give the row its height; at 26 a C row measures 108.7 and the
           option cards run past 500. The padding is the ONE thing that differs
           between classes — everything else is identical. */
        .padding(support.count >= 3 ? S.padTileRowC : S.padTileRow)
        .frame(width: S.content - S.padListX * 2, alignment: .leading)
        /* ⚠ THE RING CAME OFF WITH THE FILL. Every tile shipped white with an
           inset 1px #E7E9E5. Filling it AND keeping the ring gives the row two
           edges doing one job. Consequence to know: --rule-color is invisible on
           this ground; a rule here must step to --rule-color-strong. */
        .background(S.tileGround)
        /* ⚠ 14, NEVER 22. A 22 inside a 22 reads as a card in a card. */
        .clipShape(RoundedRectangle(cornerRadius: S.radiusTile, style: .continuous))
    }
}

// MARK: - the card

/// ⚠ NO SIZE CLASS AND NO ASPECT RATIO ON ANY OF THE SIX. Height follows the
/// row count. A fixed L caps the name count and compresses the row rhythm as the
/// book grows — the same reason the awareness card runs free.
struct SunnySummaryList<Row: Identifiable, Content: View>: View {
    let title: String
    let rows: [Row]
    /// ⚠ THE EXCEPTION COUNT IN STATE INK, or the row count in --mute when the
    /// card has no exception. The grey form is what an empty exception slot
    /// looks like, and it is a real state: puts bought is the only list where
    /// nothing can BE an exception, because protection cannot be underwater the
    /// way a short can.
    let state: String
    let stateLoss: Bool
    let name: String
    @ViewBuilder let row: (Row) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap5) {
                Text(title)
                    .font(S.inter(S.t18, S.wLightN))
                    .tracking(S.track(S.t18, -0.025))
                    .foregroundStyle(S.ink)
                Spacer(minLength: 0)
                Text(state.uppercased())
                    .font(S.inter(S.t10, S.wSemiN))
                    .tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(stateLoss ? S.lossText : S.mute)
                    .sunnyLineBox(S.t10)
            }
            .padding(.top, S.padListHeadTop)
            .padding(.bottom, S.padListHeadBottom)
            .padding(.horizontal, S.padListX)

            VStack(spacing: S.tileRowGap) {
                ForEach(rows) { row($0) }
            }
            .padding(.horizontal, S.padListX)

            /* ⚠ A LIST CARD GETS NO SUMMARY FOOTER. The standing rule from put
               floors, and clearer here: the header already prints the exception
               count and the exception is the first row. The spacer equals the
               header's top padding so the card closes symmetrically. */
            Color.clear.frame(height: 19)
        }
        .frame(width: S.content)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCardL)
        .monospacedDigit()
        .measure(name)
    }
}

// MARK: - net delta (class A)

struct SunnyDeltaList: View {
    let book: [BookName]

    private var rows: [DeltaRow] {
        book.compactMap { b in b.delta.map { DeltaRow(b: b, d: $0) } }
            .sorted { ($0.d.short ? 0 : 1, $0.b.ticker) < ($1.d.short ? 0 : 1, $1.b.ticker) }
    }
    struct DeltaRow: Identifiable { let b: BookName; let d: BookDelta; var id: String { b.ticker } }

    var body: some View {
        let shorts = rows.filter { $0.d.short }.count
        SunnySummaryList(
            title: "Net delta",
            rows: rows,
            state: shorts > 0 ? "\(shorts) net short" : "\(rows.count) positions",
            stateLoss: shorts > 0,
            name: "summary-delta"
        ) { r in
            SunnySummaryRow(
                ticker: r.b.ticker,
                /* ⚠ THE UNIT IS IN THE FIGURE. `+415` in a list of six could be
                   dollars; a strike and an average are unambiguous and print
                   bare. */
                figure: signedBare(r.d.net) + " sh",
                figureLoss: r.d.net < 0,
                support: [(changeLine(r.d), false)],
                exception: r.d.short)
        }
    }

    /* ⚠ NO PRIOR IS NOT A CHANGE OF ZERO, AND IT IS NOT `opened yesterday`
       EITHER. `delta_history` was first stamped on 27 Aug 2026, so on that day
       every name had a reading and none had a comparison — printing `opened
       yesterday` against a block held since March would have been a plain lie
       about nine positions at once. The line falls back to EXPOSURE, which is
       always true and is the support line the shipped net delta export has
       always carried. */
    private func changeLine(_ d: BookDelta) -> String {
        guard let c = d.change else { return "$\(money(d.exposure)) exposure" }
        if c == 0 { return "unchanged" }
        return "\(signedBare(c)) since yest"
    }
}

// MARK: - average price (class B)

struct SunnyAvgList: View {
    let book: [BookName]

    private var rows: [AvgRow] {
        book.compactMap { b in b.avg.map { AvgRow(b: b, a: $0) } }
            .sorted { ($0.a.vsSpot > 0 ? 0 : 1, $0.b.ticker) < ($1.a.vsSpot > 0 ? 0 : 1, $1.b.ticker) }
    }
    struct AvgRow: Identifiable { let b: BookName; let a: BookAverage; var id: String { b.ticker } }

    var body: some View {
        let over = rows.filter { $0.a.vsSpot > 0 }.count
        SunnySummaryList(
            title: "Average price",
            rows: rows,
            state: over > 0 ? "\(over) above spot" : "\(rows.count) positions",
            stateLoss: over > 0,
            name: "summary-average"
        ) { r in
            let above = r.a.vsSpot > 0
            SunnySummaryRow(
                ticker: r.b.ticker,
                /* An average is unsigned, so the figure stays ink however bad
                   the reading is. §0.3. */
                figure: sPrice(r.a.average),
                figureLoss: false,
                support: [
                    ("\(sPct(abs(r.a.vsSpot))) \(above ? "above" : "below") spot", above),
                    /* ⚠ THE SECOND LINE IS THE PREMIUM, NOT THE GAP TO SPOT.
                       Nik, 27 Aug, on what this line should say: "what we paid
                       less than the average." The handoff printed the spot gap
                       in dollars here, which is the line above restated in a
                       second unit — §0.5's own rule. This is the number the
                       average card exists to show: how far the writing has
                       walked the basis down from the price he actually paid. */
                    (premiumLine(r.a), false),
                ],
                exception: above)
        }
    }

    private func premiumLine(_ a: BookAverage) -> String {
        let d = a.paid - a.average
        return "$\(sPrice(abs(d))) \(d >= 0 ? "off" : "onto") \(sPrice(a.paid)) paid"
    }
}

// MARK: - performance (class B)

/// ⚠ THE FIGURE IS CURRENT, THE FIRST SUPPORT LINE IS ALL TIME. Nik, 27 Aug:
/// "in performance card, the first figure, the big one is current and then there
/// is an all-time figure." Current is the glossary's UNREALIZED, all time its
/// NET. Both come from position-legs so this card and the page heading above it
/// can never disagree.
struct SunnyPerfList: View {
    let book: [BookName]
    let positions: [LegsPosition]

    struct PerfRow: Identifiable {
        let ticker: String; let current: Int; let allTime: Int?; let yield: Double?
        var id: String { ticker }
    }

    private var rows: [PerfRow] {
        positions.map { p in
            /* ⚠ YIELD IS PREMIUM ON WHAT IS INVESTED. Nik's own worked example:
               "if we've invested 100,000, if we make 3,600, that 3.6% yield."
               That is exactly what `vs_paid` already measures — premium written
               against the price paid — so it is read, never recomputed, and the
               two cards can never disagree. Premium that RAISED the average is
               not a negative yield, it is no yield. */
            let v = book.first { $0.ticker == p.ticker }?.avg?.vsPaid
            return PerfRow(ticker: p.ticker, current: p.total, allTime: p.allTime,
                           yield: (v.map { -$0 } ?? 0) > 0.05 ? -(v ?? 0) : nil)
        }
        .sorted { ($0.current < 0 ? 0 : 1, $0.ticker) < ($1.current < 0 ? 0 : 1, $1.ticker) }
    }

    var body: some View {
        let down = rows.filter { $0.current < 0 }.count
        SunnySummaryList(
            title: "Performance",
            rows: rows,
            state: down > 0 ? "\(down) down" : "\(rows.count) positions",
            stateLoss: down > 0,
            name: "summary-performance"
        ) { r in
            SunnySummaryRow(
                ticker: r.ticker,
                figure: sK(r.current),
                figureLoss: r.current < 0,
                support: [
                    (r.allTime.map { "\(sK($0)) all time" } ?? "no history", false),
                    (r.yield.map { "\(sPct($0)) yield" } ?? "no yield", false),
                ],
                exception: r.current < 0)
        }
    }
}

// MARK: - the three option lists (class C)

/// ⚠ THE STATE WORD IS THE LIST'S OWN, and the first support line is always
/// ITM · ATM · OTM. ATM is the ±0.5% band. All three lists are this one view:
/// what differs is the title, the word for its exception, and whether an
/// exception is possible at all.
struct SunnyOptionList: View {
    let title: String
    let stateWord: String
    let rows: [OptionRow]
    let name: String

    var body: some View {
        let ex = rows.filter(\.exception).count
        SunnySummaryList(
            title: title,
            rows: rows,
            state: ex > 0 ? "\(ex) \(stateWord)" : "\(rows.count) open",
            stateLoss: ex > 0,
            name: name
        ) { r in
            SunnySummaryRow(
                ticker: r.ticker,
                figure: sPrice(r.strike),
                figureLoss: false,
                support: [
                    (moneyness(r), r.exception),
                    /* ⚠ `8× Oct 17`, NEVER `8 contracts · Oct 17` — that runs
                       128px at this size and crowds the figure. */
                    ("\(r.contracts)× \(expShort(r.expiry))", false),
                    ("$\(money(r.opened)) → $\(money(r.now))", false),
                ],
                exception: r.exception)
        }
    }

    private func moneyness(_ r: OptionRow) -> String {
        abs(r.moneyness) < 0.5 ? "ATM" : "\(sPct(abs(r.moneyness))) \(r.itm ? "ITM" : "OTM")"
    }
}

// MARK: - formatting

/// U+2212, never a hyphen: these have to align in a tabular column.
func signedBare(_ v: Int) -> String {
    (v < 0 ? "\u{2212}" : "+") + abs(v).formatted(.number.grouping(.automatic))
}

/// ⚠ FOUR DIGITS AND UP DROP THE CENTS — `1,042`, not `1,042.00`. A
/// five-character figure is 58px and a nine-character one 88px, and it takes
/// that 30px straight out of the support column, which is the tightest
/// measurement on the card.
func sPrice(_ v: Double) -> String {
    v >= 1000 ? v.rounded().formatted(.number.grouping(.automatic))
              : String(format: "%.2f", v)
}

func sPct(_ v: Double) -> String { String(format: "%.1f%%", v) }

/// Thousands above $1,000, whole dollars below. `+$158` and `−$2.0K` on one
/// card is the design: below a thousand the exact figure is short enough to
/// print, and rounding it to `$0.2K` throws away the only precision there is.
func sK(_ v: Int) -> String {
    let sign = v < 0 ? "\u{2212}" : "+"
    let a = abs(v)
    return a >= 1000 ? "\(sign)$\(String(format: "%.1f", Double(a) / 1000))K"
                     : "\(sign)$\(a.formatted(.number.grouping(.automatic)))"
}

/// `2026-10-17` → `Oct 17`. No year: nothing in the open book is more than
/// fifteen months out, and the year would cost the support line 5 characters it
/// has not got.
func expShort(_ iso: String) -> String {
    let m = ["01": "Jan", "02": "Feb", "03": "Mar", "04": "Apr", "05": "May", "06": "Jun",
             "07": "Jul", "08": "Aug", "09": "Sep", "10": "Oct", "11": "Nov", "12": "Dec"]
    let p = iso.split(separator: "-")
    guard p.count == 3, let mm = m[String(p[1])] else { return iso }
    return "\(mm) \(Int(p[2]) ?? 0)"
}
