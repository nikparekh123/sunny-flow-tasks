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
    /// Freshness: the stamp rides after `right`.
    var fresh: FreshTrack? = nil
    var updating = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                Text(title).font(S.inter(S.t14, S.wBoldN))
                    .tracking(S.track(S.t14, -0.01)).foregroundStyle(S.ink)
                if !sub.isEmpty {
                    Text(sub).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
                }
            }
            .fixedSize()
            Spacer(minLength: 0)
            if let fresh {
                FreshMeta(meta: right ?? "", metaInk: S.ink2, track: fresh, updating: updating)
            } else if let right {
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
    /* ⚠ A NAME BESIDE A FIGURE IS A SUFFIX, NOT PART OF THE FIGURE. Premium
       now's "−$15 LULU" truncated to "−$15 L…" when the whole string rendered
       at 19/700: the slot is 91.67 and a four-letter ticker at figure size does
       not fit beside four digits. At 11/400 in --mute it does, and it reads as
       an annotation rather than a second figure. */
    struct Stat {
        let label: String; let value: String; let ink: Color
        var suffix: String? = nil
    }
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
                        (Text(s.value)
                            .font(S.inter(S.t19, S.wBoldN))
                            .tracking(S.track(S.t19, -0.025))
                            .foregroundStyle(s.ink)
                         + Text(s.suffix.map { " " + $0 } ?? "")
                            .font(S.inter(S.t11, S.wMidSmN))
                            .foregroundStyle(S.mute))
                            .lineLimit(1)
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

/// ⚠ NO LONGER A SECOND RULE. It existed because the weekly-yield labels sit
/// over 30pt bars and a full "$4,243" collided with its neighbour at eight
/// columns; `optMoney` abbreviates everywhere now, so the two agree by
/// construction and a figure cannot read one way on one card and another way
/// on the next. Kept as a name so its callers still read as deliberate.
func optMoneyShort(_ v: Int) -> String { optMoney(v) }

/// ⚠ K AND M, NOT SEVEN DIGITS. Nik, 14 Sep 2026: "use K and M and not use
/// 10,056 use 10K or 1k, only use specific numbers when it really necessary".
/// Every card in the deck reads money through this one function, so the rule
/// is enforced in one place rather than card by card.
///
/// The ladder is significant figures, not a fixed unit:
///   under $1,000   exact      $228    — "$0.2k" is worse than the number
///   under $100k    one place  $32.7k  — a week's credit needs the hundreds
///   under $1m      whole      $209k   — the hundreds are noise against 200,000
///   above          two places $1.25m
///
/// ⚠ AND A ROUNDED IDENTITY CAN BE OUT BY ONE IN THE LAST PLACE. $46.4k less
/// $2.2k prints as $44.2k where the exact answer is $44.1k. That is inherent to
/// rounding a subtraction and is accepted: the figures are read, not summed on
/// the page. Nothing that must audit to the dollar — the loading screen's
/// counter, a per-share credit — goes through here.
func optMoney(_ v: Int) -> String {
    let a = abs(v)
    let s: String
    switch a {
    case ..<1_000:
        s = "$\(a)"
    case ..<100_000:
        s = "$" + trimZero(String(format: "%.1f", Double(a) / 1_000)) + "k"
    case ..<1_000_000:
        s = "$\(Int((Double(a) / 1_000).rounded()))k"
    default:
        s = "$" + trimZero(String(format: "%.2f", Double(a) / 1_000_000)) + "m"
    }
    return v < 0 ? "\u{2212}" + s : s
}
/// "10.0" -> "10", "1.20" -> "1.2". A trailing zero in an abbreviation reads as
/// precision the abbreviation does not have.
private func trimZero(_ s: String) -> String {
    guard s.contains(".") else { return s }
    var out = s
    while out.hasSuffix("0") { out.removeLast() }
    if out.hasSuffix(".") { out.removeLast() }
    return out
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

// MARK: - 1 · Positions, four tabs

/* ⚠ ONE CARD IN PLACE OF TWO, from `export 17`, 15 Sep 2026. Roll check asked
   how each SOLD leg was doing; Long legs asked how each BOUGHT position was
   doing. That is one question with two switches — side (call or put) and
   direction (sold or bought) — and a switch is a tab, not a card. Both are
   deleted; nothing of either survives but this.

   ⚠ ONE FLAT LIST, WORST FIRST. No name headings and no groups. A sold row is a
   CONTRACT LINE, because NFLX 77 and NFLX 81 are two separate decisions; a
   bought row is a NAME AND SIDE, because every long call on NKE is one
   position. Both sort ascending, so what needs a look is at the top. The "name
   is a heading" grouping the two old cards shared is retired: with a tab already
   fixing the side, the ticker column is short enough to carry the strike.

   ⚠ TWO TAPS, NOT FIVE. The tabs, and the figure column. Roll check's left-side
   switch, its IV and yield taps and Long legs' window words are gone — Left to
   sell is Inventory's reading, and the windows asked a second question the hero
   already answers. */
struct SunnyPositions: View {
    let positions: [OptionsPosition]
    let legs: [LongLeg]
    let prices: [PriceRow]
    let asOf: String
    /// Freshness: a new or closed leg and a changed contract count, held until
    /// the card is seen. The % move is the market and never marks.
    var fresh: FreshTrack? = nil
    var updating = false

    /// The figures Freshness watches: contracts per row, and rows per tab.
    static func freshFigs(_ ps: [OptionsPosition], _ legs: [LongLeg]) -> [String: [String: String]] {
        var n: [String: Int] = [:]
        for p in ps {
            for s in p.shorts where s.cr != nil {
                let tab = (s.type ?? "call") == "call" ? "sc" : "sp"
                n["\(tab):\(p.t)|\(trimZero(String(format: "%.2f", s.k)))", default: 0] += s.n
            }
        }
        for l in legs { n["\(l.isCall ? "bc" : "bp"):\(l.t)", default: 0] += l.n }
        var out = n.mapValues { ["n": String($0)] }
        for t in ["sc", "sp", "bc", "bp"] {
            out["\(t):#meta"] = ["n": String(n.keys.filter { $0.hasPrefix(t + ":") }.count)]
        }
        return out
    }
    private func fr(_ key: String, _ own: Color) -> Color {
        fresh?.isMarked("\(tabRaw):\(key)", "n") == true ? S.warn : own
    }

    /* Both survive a pull: a reading the user chose, not state the data owns.
       `mode` is shared across all four tabs on purpose. */
    @AppStorage("sunnyfi.pos.tab") private var tabRaw = "sc"
    /* ⚠ THREE READINGS, NOT TWO. Nik, 15 Sep 2026: "Percentage should show %,
       Dollar should show Dollar, Time value should show time value remaining".
       The sheet has two; the third is the one figure neither of the others
       carries — what is still to decay, which on a sold leg is the money that
       comes back by expiry if nothing is done. 0 = %, 1 = $, 2 = time value. */
    @AppStorage("sunnyfi.pos.fig") private var figMode = 0
    @State private var appeared = false
    /* ⚠ A TAB CHANGE IS A QUIETER ENTRANCE THAN THE FIRST ONE. Nik, 18 Sep
       2026: "make it a little more subtle". The first load still grows every
       bar from nothing, the deck's entrance; a tab switch now starts the bars
       at 92% and fades the rows in over a quarter second with a short capped
       stagger, so the new list settles into place instead of redrawing. */
    @State private var soft = false
    /// One tab change per drag, cleared when the next drag starts.
    @State private var swiped = false
    /// Re-read on the tick so Friday 20:00 and Monday 04:00 land without a reload.
    @State private var now = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: geometry, from the sheet

    private static let nameCol: CGFloat = 70
    private static let figCol: CGFloat = 56
    private static let colGap: CGFloat = 10
    private static let barH: CGFloat = 14
    private static let rowGap: CGFloat = 16
    private static let stagger: Double = 0.040

    // MARK: the four tabs

    private enum Tab: String, CaseIterable {
        case sc, sp, bc, bp
        var label: String {
            switch self {
            case .sc: return "Calls sold"
            case .sp: return "Puts sold"
            case .bc: return "Calls bought"
            case .bp: return "Puts bought"
            }
        }
        var sold: Bool { self == .sc || self == .sp }
        var isCall: Bool { self == .sc || self == .bc }
        var scope: String { "\(isCall ? "calls" : "puts") \(sold ? "sold" : "bought")" }
    }
    private var tab: Tab { Tab(rawValue: tabRaw) ?? .sc }

    // MARK: the rows

    private struct Row: Identifiable {
        let t: String, k: String, v: Double, fig: String
        let through: Bool
        /// The leg's size and expiry.
        var n: Int = 0
        var exp: String? = nil
        var id: String { "\(t)|\(k)" }
        var up: Bool { v >= 0 }
    }

    /// One entry per open short contract line on the picked side.
    private struct Sold {
        let t: String, k: Double, n: Int, pct: Double, cr: Double
        /// The leg's expiry.
        let exp: String
        /// What is still to decay — not what the buy-back costs.
        let tv: Double
        /// The whole cost of closing the leg: intrinsic plus what is left to decay.
        let value: Double
        /// What the strike has kept (+) or given back (−).
        var usd: Double { pct / 100 * cr * 100 * Double(n) }
        var credit: Double { cr * 100 * Double(n) }
    }
    private var soldLegs: [Sold] {
        positions.flatMap { p in
            p.shorts.compactMap { s -> Sold? in
                let isCall = (s.type ?? "call") == "call"
                guard isCall == tab.isCall, let cr = s.cr else { return nil }
                return Sold(t: p.t, k: s.k, n: s.n, pct: Double(s.captured), cr: cr,
                            exp: s.exp, tv: Double(s.tv ?? 0), value: Double(s.value))
            }
        }
        .sorted { $0.pct < $1.pct }
    }

    /// One entry per name on the picked side: every long call on a name is one
    /// position, Σ mark × n against Σ cost × n.
    private struct Bought {
        let t: String, ks: [String], n: Int, now: Double, paid: Double
        /// Mark less intrinsic: the part of a long leg that still melts.
        let tv: Double
        var ch: Double { paid > 0 ? now / paid - 1 : 0 }
        var made: Double { now - paid }
    }
    private var boughtPositions: [Bought] {
        var by: [String: (ks: [String], n: Int, now: Double, paid: Double, tv: Double)] = [:]
        for l in legs where l.isCall == tab.isCall {
            var g = by[l.t] ?? ([], 0, 0, 0, 0)
            g.ks.append(String(l.k.dropLast()))
            g.n += l.n; g.now += l.m * Double(l.n); g.paid += l.cost * Double(l.n)
            /* ⚠ MONEYNESS INVERTS ON A PUT, the deck's most repeated trap. */
            let strike = Double(l.k.dropLast()) ?? 0
            let spot = prices.first { $0.ticker == l.t }?.spot ?? 0
            let intr = (l.isCall ? Swift.max(0, spot - strike) : Swift.max(0, strike - spot)) * 100
            g.tv += Swift.max(0, l.m - intr) * Double(l.n)
            by[l.t] = g
        }
        return by.map { Bought(t: $0.key, ks: $0.value.ks, n: $0.value.n,
                               now: $0.value.now, paid: $0.value.paid, tv: $0.value.tv) }
            .sorted { $0.ch < $1.ch }
    }

    private var rows: [Row] {
        if tab.sold {
            return soldLegs.map { l in
                Row(t: l.t, k: trimZero(String(format: "%.2f", l.k)), v: l.pct,
                    fig: figMode == 2 ? optMoney(Int(l.tv.rounded()))
                       : figMode == 1 ? signedMoney(l.usd)
                       : barePctInt(Int(l.pct.rounded())),
                    through: movedThrough(l.t, l.k), n: l.n, exp: l.exp)
            }
        }
        return boughtPositions.map { p in
            Row(t: p.t, k: p.ks.count == 1 ? p.ks[0] : "\(p.ks.count) strikes",
                v: p.ch * 100,
                fig: figMode == 2 ? optMoney(Int(p.tv.rounded()))
                   : figMode == 1 ? signedMoney(p.made)
                   : signedPct1(p.ch),
                through: false, n: p.n)
        }
    }

    /* ⚠ A STRIKE THE STOCK HAS MOVED THROUGH: a call below spot, a put above
       it. Red ticker with a red bar says roll it; red ticker with a green bar
       says it ran through but you are still ahead. A name with no close never
       turns red. */
    private func movedThrough(_ t: String, _ k: Double) -> Bool {
        guard let spot = prices.first(where: { $0.ticker == t })?.spot, spot > 0 else { return false }
        return tab.isCall ? spot > k : spot < k
    }

    // MARK: the axis

    private struct Axis { let min: Double, max: Double, lo: Double, hi: Double }
    /* ⚠ THE SOLD AXIS IS FIXED AND IT IS ROLL CHECK'S. +75 is three quarters of
       the credit banked; −100 is the call having doubled against you, the spot
       at the leg's break-even. The bought axis is Long legs': symmetric, so one
       name's fall reads against another's rise. */
    private var axis: Axis {
        guard !tab.sold else { return Axis(min: -125, max: 100, lo: -100, hi: 75) }
        let biggest = rows.map { abs($0.v) }.max() ?? 10
        let lim = max(10, (biggest * 1.1 / 10).rounded(.up) * 10)
        return Axis(min: -lim, max: lim, lo: -lim, hi: lim)
    }
    /// A value's place on the track, 0...1. Past the end it clamps and the
    /// figure carries the truth.
    private func x(_ a: Axis, _ v: Double) -> CGFloat {
        CGFloat((Swift.max(a.min, Swift.min(a.max, v)) - a.min) / (a.max - a.min))
    }

    // MARK: the hero and the footer

    private var keptSum: Double { soldLegs.reduce(0) { $0 + $1.usd } }
    private var creditSum: Double { soldLegs.reduce(0) { $0 + $1.credit } }
    private var madeSum: Double { boughtPositions.reduce(0) { $0 + $1.made } }
    private var paidSum: Double { boughtPositions.reduce(0) { $0 + $1.paid } }
    private var nowSum: Double { boughtPositions.reduce(0) { $0 + $1.now } }

    /* ⚠ THE WEEK IS OVER ON FRIDAY NIGHT. "kept this week" is live while the
       week is open; from Friday 20:00 ET to Monday 04:00 ET the words leave and
       the figure stands alone, because it is the week's result now rather than a
       running total. The same window Prices uses for its day chip. */
    private var weekOpen: Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let wd = cal.component(.weekday, from: now), h = cal.component(.hour, from: now)
        if wd == 7 || wd == 1 { return false }          // Sat, Sun
        if wd == 6 && h >= 20 { return false }          // Fri night
        if wd == 2 && h < 4 { return false }            // before Mon pre-market
        return true
    }

    private var tvSum: Double {
        tab.sold ? soldLegs.reduce(0) { $0 + $1.tv }
                 : boughtPositions.reduce(0) { $0 + $1.tv }
    }
    /* ⚠ THE HERO IS THE COLUMN, SUMMED. Nik, 15 Sep 2026: "on tapping the right
       numbers the main number isnt changing". It always printed dollars while
       the rows flipped underneath it, so in per-cent mode the card showed a
       column of percentages under a figure in money and the two looked like
       different questions. Every mode now has a hero that is the same reading
       as the rows above the fold. */
    private var heroText: String {
        switch figMode {
        case 1: return signedMoney(tab.sold ? keptSum : madeSum)
        case 2: return optMoney(Int(tvSum.rounded()))
        default:
            if tab.sold {
                return barePctInt(Int((creditSum > 0 ? keptSum / creditSum * 100 : 0).rounded()))
            }
            return signedPct1(paidSum > 0 ? madeSum / paidSum : 0)
        }
    }
    /* Time value left is neither a gain nor a loss — it is what has not decayed
       yet — so it takes ink, not a direction colour. */
    private var heroInk: Color {
        if figMode == 2 { return S.ink }
        return (tab.sold ? keptSum : madeSum) < 0 ? S.lossText : S.gainText
    }
    private var hero: Double { tab.sold ? keptSum : madeSum }
    /* ⚠ NOTHING IS KEPT WHILE THE LEG IS OPEN. Nik, 15 Sep 2026: "we need to
       change kept this week as we havent closed those". The hero said "kept
       this week" over a figure that is the mark, not the ledger — it would only
       be kept if every leg were closed at that moment, and a word that says
       banked over a number that moves every minute is the worst kind of wrong.
       Every reading on a sold tab is unrealised and now says so.

       The time value hero names what it is a part of: the whole cost of closing
       the side today, which is intrinsic plus what is left to decay. That is the
       only denominator time value is genuinely inside — against the credit it
       can exceed the whole, because a leg that moved against you is worth more
       than it was sold for. */
    private var closeCost: Double { soldLegs.reduce(0) { $0 + $1.value } }
    private var heroSub: String {
        if tab.sold {
            return figMode == 2 ? "of \(optMoney(Int(closeCost.rounded()))) to close"
                                : "unrealised"
        }
        if figMode == 2 { return "still to melt" }
        let up = boughtPositions.filter { $0.made >= 0 }.count
        return "\(up) of \(boughtPositions.count) up · since bought"
    }
    private var eyebrow: String {
        if figMode == 2 { return "TIME VALUE LEFT" }
        return tab.sold ? (figMode == 1 ? "KEPT OF CREDIT" : "CAPTURED OF CREDIT")
                        : (figMode == 1 ? "MADE YOU" : "CHANGE SINCE BOUGHT")
    }
    private var meta: String {
        let n = rows.count
        return tab.sold ? "\(n) leg\(n == 1 ? "" : "s")" : "\(n) position\(n == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
                HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                    Text("Positions").font(S.inter(S.t14, S.wBoldN))
                        .tracking(S.track(S.t14, -0.01)).foregroundStyle(S.ink)
                    Text(tab.scope).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
                }
                .fixedSize()
                Spacer(minLength: 0)
                FreshMeta(meta: meta, metaInk: fr("#meta", S.mute), track: fresh, updating: updating)
            }
            Spacer().frame(height: 18)
            tabRow
            Spacer().frame(height: 22)

            Text(eyebrow).font(S.inter(S.t10, S.wBoldN))
                .tracking(S.track(S.t10, S.lsLabel)).foregroundStyle(S.mute)
            Spacer().frame(height: 12)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(heroText).font(S.inter(S.t30, S.wBoldN))
                    .tracking(S.track(S.t30, -0.035))
                    .foregroundStyle(heroInk)
                    .sunnyLineBox(S.t30)
                if !heroSub.isEmpty {
                    Text(heroSub).font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer().frame(height: 28)

            marks
            Spacer().frame(height: 14)
            /* ⚠ A NEW TAB IS A NEW LIST, NOT THE OLD ONE CHANGED. Without the
               `.id`, SwiftUI diffs two unrelated sets inside one ForEach: the
               handful of rows whose id happens to survive animate their bar
               from a call's captured to a put's, the rest slide as the list
               re-lays out, and the switch reads as a morph. Nik, 15 Sep 2026:
               "Moving from calls sold to put sold there is a weird animation".
               The sheet's own rule is that the rows RE-ENTER on a tab change,
               because they are different rows. */
            VStack(alignment: .leading, spacing: Self.rowGap) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in row(r, i: i) }
            }
            .id(tabRaw)

            Spacer().frame(height: 26)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 18)
            footer
        }
        .frame(width: S.content - 48, alignment: .leading)
        .modifier(OptionalFreshSeen(track: fresh))
        /* ⚠ THE GESTURE SITS ON THE CONTENT, ABOVE THE CARD'S CHROME. Attached
           after the background and the shadow it never saw a drag at all — the
           shadow helper wraps the view in an `AnyView` and the hit test stopped
           finding it. On the content, with an explicit shape so the gaps
           between rows are live too, it gets the same drag the scroller does. */
        .contentShape(Rectangle())
        .simultaneousGesture(
            /* ⚠ IT ACTS ON CHANGE, NOT ON END. The page's scroller claims the
               pan and CANCELS this one, and a cancelled gesture never delivers
               `onEnded` — with the move in there the swipe did nothing at all,
               through a plain gesture and a simultaneous one alike. `onChanged`
               arrives before the cancellation, so the latch fires the move the
               moment the drag is unambiguous and then ignores the rest of it.

               ⚠ AND THE DOMINANCE TEST IS WHAT PROTECTS THE SCROLL. 48pt across
               and 1.6x more horizontal than vertical, the ratio the retired
               hand-rolled pager settled on; a vertical flick that happens to
               start on the card never passes it. */
            DragGesture(minimumDistance: 20)
                .onChanged { g in
                    let dx = g.translation.width, dy = g.translation.height
                    if abs(dx) < 5 && abs(dy) < 5 { swiped = false; return }
                    guard !swiped, abs(dx) > 48, abs(dx) > abs(dy) * 1.6 else { return }
                    swiped = true
                    let all = Tab.allCases
                    guard let i = all.firstIndex(of: tab) else { return }
                    let j = i + (dx < 0 ? 1 : -1)
                    /* Stops at both ends rather than wrapping: a tab that does
                       not move says THAT WAS THE END without being told. */
                    guard all.indices.contains(j) else { return }
                    withAnimation(reduceMotion ? nil : S.easeSettle(0.55)) {
                        tabRaw = all[j].rawValue
                    }
                }
                .onEnded { _ in swiped = false }
        )
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 28, trailing: 24))
        .frame(width: S.content, alignment: .top)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCardL)
        .monospacedDigit()
        /* ⚠ SWIPE MOVES THE TAB, AND IT MUST NOT EAT THE PAGE'S SCROLL. Nik,
           15 Sep 2026: "can i swipe on the card to go to next tab?". The card
           lives inside a vertical scroller, so a bare drag gesture would steal
           every vertical flick that happened to start on it — the same fight
           the retired hand-rolled pager had. Two guards: 24pt before the
           gesture engages at all, and the move only happens when the drag is
           HORIZONTALLY DOMINANT by 1.6x, the ratio that shell settled on.

           ⚠ AND IT STOPS AT BOTH ENDS RATHER THAN WRAPPING. Wrapping puts Puts
           bought one swipe left of Calls sold, so a swipe past the end silently
           teleports across the whole card; a tab that does not move says THAT
           WAS THE END without having to be told. */
        /* ⚠ SIMULTANEOUS, NOT EXCLUSIVE. A plain `.gesture` loses every drag to
           the page's scroller and the swipe did nothing at all; a high-priority
           one would win them all and kill vertical scrolling over the card.
           Simultaneous lets the scroller keep doing its job while this watches
           the same drag, and the dominance test below is what stops a vertical
           flick from changing the tab on its way past. */
        .measure("positions")
        .task(id: rows.count) {
            now = Date()
            guard !appeared, !rows.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(20))
            appeared = true
        }
        /* The entrance plays again for the new rows: cleared, then set on the
           next beat so the fade and the bar growth both have somewhere to run
           from. Without the reset the new list arrives already at full opacity
           and full width, which is the other half of the morph. */
        .task(id: tabRaw) {
            guard appeared else { return }
            soft = true
            appeared = false
            try? await Task.sleep(for: .milliseconds(20))
            appeared = true
        }
    }

    /* ⚠ THE TABS ARE NOT UNDERLINED. The picked one is bold ink with a 2pt line
       sitting on the rule, the rest muted — the deck's dotted hair marks text
       that FLIPS, not text that navigates, and an underline on four adjacent
       words reads as a heading rule. */
    private var tabRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(Tab.allCases.enumerated()), id: \.element) { i, t in
                if i > 0 { Spacer(minLength: 4) }
                /* ⚠ ONE RULE UNDER THE ROW, AND THE LINE INSIDE THE PADDING. The
                   rule used to be drawn per word, so it broke in the gaps between
                   the four tabs, and the picked tab's 2pt line was stacked under
                   the padding, making that tab 2pt taller than its neighbours.
                   The sheet's row is 22 with one rule along its bottom and the
                   line drawn on top of it. */
                VStack(spacing: 0) {
                    Text(t.label)
                        .font(S.inter(S.t12, t == tab ? S.wBoldN : S.wMidN))
                        .tracking(S.track(S.t12, -0.01))
                        .foregroundStyle(t == tab ? S.ink : S.mute)
                        .lineLimit(1)
                        .sunnyLineBox(S.t12)
                    Spacer().frame(height: 10)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(t == tab ? S.ink : .clear).frame(height: 2)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(reduceMotion ? nil : S.easeSettle(0.55)) { tabRaw = t.rawValue }
                }
            }
        }
        .background(alignment: .bottom) {
            Rectangle().fill(S.ruleColor).frame(height: 1)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: tabRaw)
    }

    /// The two outer axis values, centred on their lines.
    private var marks: some View {
        HStack(spacing: Self.colGap) {
            Color.clear.frame(width: Self.nameCol, height: 11)
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    mark(String(Int(abs(axis.lo))), lead: true)
                        .position(x: g.size.width * x(axis, axis.lo), y: 5.5)
                    mark("+" + String(Int(axis.hi)), lead: false)
                        .position(x: g.size.width * x(axis, axis.hi), y: 5.5)
                }
            }
            .frame(height: 11)
            Color.clear.frame(width: Self.figCol, height: 11)
        }
        .animation(reduceMotion ? nil : S.easeSettle(0.55), value: tabRaw)
    }
    private func mark(_ s: String, lead: Bool) -> some View {
        Text(lead ? "\u{2212}" + s : s)
            .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
            .foregroundStyle(S.mute).sunnyLineBox(S.t10).fixedSize()
    }

    @ViewBuilder private func row(_ r: Row, i: Int) -> some View {
        HStack(spacing: Self.colGap) {
            /* ⚠ EVERY CELL TAKES ITS LINE BOX, which is the sheet's
               `line-height: 1`. Without it a 13pt Text reserves ~16pt of its
               own leading, the row is sized by the text rather than by the bar,
               and the pitch measured 32 against the sheet's 30 — two points
               over on every row, thirty over the card. */
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(r.t).font(S.inter(S.t13, S.wSemiN))
                    .tracking(S.track(S.t13, -0.015))
                    .foregroundStyle(r.through ? S.lossText : S.ink)
                    .sunnyLineBox(S.t13)
                Text(r.k).font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                    .sunnyLineBox(S.t11)
                Spacer(minLength: 0)
            }
            .lineLimit(1).frame(width: Self.nameCol, alignment: .leading)

            GeometryReader { g in
                let zero = g.size.width * x(axis, 0)
                let px = g.size.width * x(axis, r.v)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4).fill(S.wash)
                        .frame(width: g.size.width, height: Self.barH)
                    RoundedRectangle(cornerRadius: 4).fill(r.up ? S.gainBar : S.lossBar)
                        .frame(width: abs(px - zero), height: Self.barH)
                        .offset(x: Swift.min(zero, px))
                        .scaleEffect(x: appeared || reduceMotion ? 1 : (soft ? 0.92 : 0),
                                     anchor: r.up ? .leading : .trailing)
                        .animation(reduceMotion ? nil : (soft
                            ? S.easeSettle(0.35).delay(softDelay(i))
                            : S.easeSettle(S.durBar).delay(Double(i) * Self.stagger)),
                                   value: appeared)
                        /* ⚠ NO VALUE GLIDE ACROSS A TAB. Within a tab a pull
                           moves a bar and it should slide; between tabs the row
                           is a different contract entirely and sliding from one
                           to the other is meaningless. Keying the glide on the
                           tab as well as the value confines it to the pull. */
                        .animation(reduceMotion ? nil : S.easeSettle(0.55), value: "\(tabRaw)|\(r.v)")
                        .animation(.easeInOut(duration: 0.3), value: r.up)
                    /* The three reference lines, reaching 4 above and below. */
                    ForEach([axis.lo, 0, axis.hi], id: \.self) { v in
                        Rectangle().fill(S.hair)
                            .frame(width: 1.5, height: Self.barH + 8)
                            .offset(x: g.size.width * x(axis, v) - 0.75, y: -4)
                            .animation(reduceMotion ? nil : S.easeSettle(0.55), value: tabRaw)
                    }
                }
            }
            .frame(height: Self.barH)

            /* ⚠ THE HINT GOES ON THE GLYPHS, NOT ON THE COLUMN. `sunnyHint` is a
               bottom overlay, so applied after the 56pt frame it drew a dotted
               rule the width of the whole figure column — a heading rule, not a
               mark on a word. On the text it hugs the number, which is what the
               sheet's `text-decoration` does. The frame comes after, so the
               column still right-aligns. */
            /* ⚠ NO SCALE FACTOR UNDER A LINE BOX. Pinning the height to 13pt is
               smaller than the text's own ~16pt line, and SwiftUI counts that as
               "does not fit" — with `minimumScaleFactor` allowed it shrank every
               figure to 79%: digits measured 7.67pt against Prices' 9.67 at the
               same 13/700. Nik, 16 Sep 2026: "why so small". The widest figure
               fits the 56pt column at full size, so the scale factor was only
               ever doing harm. */
            Text(r.fig).font(S.inter(S.t13, S.wBoldN))
                .tracking(S.track(S.t13, -0.015))
                .foregroundStyle(fr(tab.sold ? r.id : r.t,
                                    figMode == 2 ? S.ink : (r.up ? S.gainText : S.lossText)))
                .lineLimit(1)
                .sunnyLineBox(S.t13)
                .sunnyHint()
                .frame(width: Self.figCol, alignment: .trailing)
                .padding(.vertical, 8).contentShape(Rectangle())
                .onTapGesture { figMode = (figMode + 1) % 3 }
                .padding(.vertical, -8)
        }
        .frame(height: Self.barH)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .animation(reduceMotion ? nil : (soft
            ? .easeOut(duration: 0.25).delay(softDelay(i))
            : S.easeSettle(0.4).delay(Double(i) * Self.stagger)),
                   value: appeared)
    }

    /// 15ms a row, never more than 0.15s in all: fifteen rows at the first
    /// load's 40ms took over a second to arrive, which is what read as loud.
    private func softDelay(_ i: Int) -> Double { Swift.min(Double(i) * 0.015, 0.15) }

    /* ⚠ THE FOOTER FOLLOWS THE TAB, and its Paid must equal Programme's invested
       and Intrinsic value's Paid to the dollar — all three read one ledger. */
    private var footer: some View {
        HStack(alignment: .top, spacing: S.gap6) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, s in
                VStack(alignment: .leading, spacing: 5) {
                    Text(s.0).font(S.inter(S.t10, S.wBoldN))
                        .tracking(S.track(S.t10, S.lsLabel))
                        .foregroundStyle(S.mute).lineLimit(1)
                    Text(s.1).font(S.inter(S.t19, S.wBoldN))
                        .tracking(S.track(S.t19, -0.025))
                        .foregroundStyle(s.2).lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    /* ⚠ THE YIELD'S DENOMINATOR IS THE CAPITAL, NOT THE CREDIT. Nik, 15 Sep
       2026: "it need to be collected currently in calls open / total invested in
       calls bought". It read kept ÷ collected, which is the share of the credit
       still yours — the same reading the rows already carry, and it printed 21%
       under a column headed CAPTURED OF CREDIT saying the same thing. Against
       what the long legs on that side COST it becomes a real yield: the open
       calls pay 2.3% of what the LEAPs cost, the open puts 6.7% of the hedge.
       That is the figure the word promises, and it is why the word stays. */
    private var investedSum: Double {
        legs.filter { $0.isCall == tab.isCall }
            .reduce(0) { $0 + $1.cost * Double($1.n) }
    }
    private var stats: [(String, String, Color)] {
        if tab.sold {
            let yield = investedSum > 0 ? creditSum / investedSum * 100 : 0
            /* ⚠ "OPEN CREDIT", NOT "COLLECTED". Nik, 16 Sep 2026: "keep banked,
               rename positions to open credit". This figure is the credit on the
               legs open right now; Coverage's Collected is everything banked
               against the long legs since they were bought. Two quantities under
               one word read as a mismatch between the cards. */
            return [("OPEN CREDIT", optMoney(Int(creditSum.rounded())), S.ink),
                    ("WORTH NOW", optMoney(Int((creditSum - keptSum).rounded())), S.ink),
                    ("YIELD", String(format: "%.1f%%", yield), S.ink)]
        }
        return [("PAID", optMoney(Int(paidSum.rounded())), S.ink),
                ("WORTH NOW", optMoney(Int(nowSum.rounded())), S.ink),
                ("DIFFERENCE", signedMoney(nowSum - paidSum),
                 nowSum >= paidSum ? S.gainText : S.lossText)]
    }
}

// MARK: - 2 · Yield progress — RETIRED 18 Sep 2026

/* ⚠ FOLDED INTO PERFORMANCE. `export 20`: Yield progress asked one more question
   of the names Programme already lists, has this name's credit earned back its
   LEAP's time value, so it is the fourth row of WHAT IT IS MADE OF and not a
   card. The server's `yieldProgress` block stays as that row's source. */

/// A signed figure in the deck's k/M form.
func signedMoney(_ v: Double) -> String {
    let i = Int(v.rounded())
    return (i < 0 ? "" : "+") + optMoney(i)
}
private func signedPct1(_ f: Double) -> String {
    let p = f * 100
    return (p < 0 ? "\u{2212}" : "+") + String(format: "%.1f", abs(p)) + "%"
}

// MARK: - 2c · Coverage, two tabs

/* ⚠ ONE CARD IN PLACE OF CALL COVER AND PUT COVER, from `export 18`, 16 Sep
   2026. The two cover-bars cards asked one question of two sides of the book,
   and a side is a switch, not a card — the Positions rule. The puts' whole is a
   fraction of the calls', so a tab gives each side its own 132pt scale without
   the two ever being read against each other.

   ⚠ ONLY TIME VALUE HAS TO BE COVERED, unchanged from the bars and the reason the
   rings died. A long leg's intrinsic is real money that exercising returns; the
   left bar is time value and never cost or mark.

   ⚠ THE COLOUR CHANGE IS THE TARGET. Collected is `--gain-bar` up to time value's
   level and `--gain-text` past it, so the seam between the two greens sits exactly
   at the Time bar's cap and "reached or not yet" is one edge. The dashed target
   and the ghost line are retired: a day's melt is under half a per cent of the
   bar, and it now reads as a share over the Time bar instead.

   ⚠ NOTHING UNMOUNTS ON A TAB. The same three bars glide to the other side's
   heights so the eye keeps the frame and reads the change. That is the opposite
   of Positions, whose tabs swap in different ROWS; here the rows are the same two
   bars with different values. */
struct SunnyCoverage: View {
    let block: CoverBarsBlock

    /* A new key, not "sunnyfi.cov.tab": that one stored the old order, where
       2 meant All, and would have opened the reordered card on Puts. */
    @AppStorage("sunnyfi.cov.lens") private var tab = 0
    /// Shared name with the cover bars it replaces, so a reader's compare
    /// choice survives the swap.
    @AppStorage("sunnyfi.cover.week") private var byWeek = false
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let plotH: CGFloat = 132
    private static let inset: CGFloat = 28
    private static let colGap: CGFloat = 24
    private static let lift: CGFloat = 7
    private static let bleed: CGFloat = 6

    /* ⚠ ALL IS THE FIRST TAB AND THE DEFAULT (Nik, 23 Sep 2026). The book is
       one book; the sides are the split. */
    private var s: CoverSide {
        switch tab {
        case 1: return block.sides.call
        case 2: return block.sides.put
        default: return both
        }
    }

    /* ⚠ THE THIRD TAB IS THE TWO SIDES ADDED, not a third figure from the
       server (Nik, 23 Sep 2026: "one more tab saying All"). Every figure on
       this card is a sum over legs, so calls plus puts is the same card read
       over both: time value, collected, the open cap, the pace and the melt.

       ⚠ A MISSING HISTORY MAKES THE PAIR MISSING. The melt share divides by an
       earlier close, and a side with no leg priced that day ships null. Adding
       it as zero would halve the previous total and report a melt that never
       happened, so the pair is null unless both sides carry the day. */
    private var both: CoverSide {
        let c = block.sides.call, p = block.sides.put
        func pair(_ a: Int?, _ b: Int?) -> Int? {
            guard let a, let b else { return nil }
            return a + b
        }
        return CoverSide(
            label: "All", scope: "calls and puts",
            names: max(c.names, p.names),
            time: c.time + p.time,
            hist: CoverHist(yday: pair(c.hist.yday, p.hist.yday),
                            week: pair(c.hist.week, p.hist.week)),
            collected: c.collected + p.collected,
            open: pair(c.open ?? 0, p.open ?? 0),
            chist: CoverHist(yday: pair(c.chist.yday, p.chist.yday),
                             week: pair(c.chist.week, p.chist.week)),
            pace: c.pace + p.pace, melt: c.melt + p.melt)
    }
    /// The taller bar is the plot; the other is a share of it.
    /* The taller stack is the plot, and the cap is part of the stack: leaving
       it out clipped the lighter segment the moment collected plus open passed
       time value. */
    private var top: Double { Double(max(s.time, s.collected + max(0, s.open ?? 0), 1)) }
    private func h(_ v: Int) -> CGFloat { Self.plotH * CGFloat(max(0, Double(v)) / top) }
    private var over: Int { s.collected - s.time }
    /// Credit taken on legs still open: real cash, not earned yet.
    private var openCr: Int { max(0, s.open ?? 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
                HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                    Text("Coverage").font(S.inter(S.t14, S.wBoldN))
                        .tracking(S.track(S.t14, -0.01)).foregroundStyle(S.ink)
                    Text(s.scope).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
                }
                Spacer(minLength: 0)
                Text(ivDay(block.asOf)).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
            }
            Spacer().frame(height: 18)
            tabRow
            Spacer().frame(height: 26)
            HStack(alignment: .top, spacing: Self.colGap) {
                column(time: true)
                column(time: false)
            }
            .padding(.horizontal, Self.inset)
            Spacer().frame(height: 22)
            Rectangle().fill(S.ruleColor).frame(height: 1)
            Spacer().frame(height: 14)
            footer
        }
        .frame(width: S.content - 48, alignment: .leading)
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 28, trailing: 24))
        .frame(width: S.content, alignment: .top)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCardL)
        .monospacedDigit()
        .measure("coverage")
        .task(id: s.time) {
            guard !grown else { return }
            try? await Task.sleep(for: .milliseconds(20))
            grown = true
        }
    }

    /* ⚠ POSITIONS' TAB ROW, WITH TWO WORDS. The picked one is bold ink with a 2pt
       line sitting on the rule; tabs are never underlined — the line is the state,
       and a dotted hint under two words 28pt apart would read as a heading rule. */
    private var tabRow: some View {
        HStack(alignment: .bottom, spacing: 28) {
            ForEach(Array(["All", "Calls", "Puts"].enumerated()), id: \.offset) { i, label in
                /* ⚠ THE LINE SITS INSIDE THE PADDING, ON THE RULE. The row is 22:
                   12 of word and 10 below it, and the picked tab's 2pt line is drawn
                   over the bottom of that 10 — CSS's inset box-shadow. Stacked under
                   the padding instead it made the row 24 and the card 2pt tall. */
                VStack(spacing: 0) {
                    Text(label)
                        .font(S.inter(S.t12, tab == i ? S.wBoldN : S.wMidN))
                        .tracking(S.track(S.t12, -0.01))
                        .foregroundStyle(tab == i ? S.ink : S.mute)
                        .sunnyLineBox(S.t12)
                    Spacer().frame(height: 10)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(tab == i ? S.ink : .clear).frame(height: 2)
                }
                .fixedSize()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(reduceMotion ? nil : S.easeSettle(0.55)) { tab = i }
                }
            }
            Spacer(minLength: 0)
        }
        .background(alignment: .bottom) {
            Rectangle().fill(S.ruleColor).frame(height: 1)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: tab)
    }

    // MARK: a column

    @ViewBuilder private func column(time: Bool) -> some View {
        VStack(spacing: 0) {
            /* ⚠ 100% IS ALWAYS OVER TIME VALUE, even when Collected is the taller
               bar. Collected's share is of time value, and moving the reference
               would make the percentage mean two things on two days. */
            Text(time ? "100%" : sharePct)
                .font(S.inter(S.t12, S.wSemiN))
                .foregroundStyle(!time && s.covered ? S.gainText : S.ink2)
                .sunnyLineBox(S.t12)
                .frame(maxWidth: .infinity)
            Spacer().frame(height: 6)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 52)
            ZStack(alignment: .bottom) {
                Color.clear.frame(height: Self.plotH)
                if time { timeBar } else { collectedBars }
                clock(time: time)
            }
            .frame(height: Self.plotH)
            Spacer().frame(height: 14)
            Text(time ? "TIME VALUE" : "COLLECTED")
                .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute).sunnyLineBox(S.t10).lineLimit(1)
            Spacer().frame(height: 8)
            Text(optMoney(time ? s.time : s.collected))
                .font(S.inter(S.t15, S.wBoldN)).tracking(S.track(S.t15, -0.02))
                .foregroundStyle(time ? S.ink : (s.collected < 0 ? S.lossText : S.gainText))
                .sunnyLineBox(S.t15).lineLimit(1)
        }
        /* ⚠ CENTRED, NOT LEADING. At 116.5 wide a left-aligned figure floated off
           the bar it names. */
        .frame(maxWidth: .infinity)
    }

    private var timeBar: some View {
        UnevenRoundedRectangle(topLeadingRadius: S.radiusPip, topTrailingRadius: S.radiusPip)
            .fill(S.wash)
            .overlay(
                /* The edge runs over the top and down both sides, never along the
                   bottom: the floor is the axis, not the bar's outline. */
                TimeEdge(radius: S.radiusPip).stroke(S.ruleColorStrong, lineWidth: 1))
            .frame(height: max(3, h(s.time)))
            .scaleEffect(y: grown || reduceMotion ? 1 : 0, anchor: .bottom)
            .animation(reduceMotion ? nil : S.easeSettle(S.durBar), value: grown)
            .animation(reduceMotion ? nil : S.easeSettle(0.55), value: h(s.time))
    }

    @ViewBuilder private var collectedBars: some View {
        let isOver = over > 0
        let cap = openCr
        ZStack(alignment: .bottom) {
            /* ⚠ THE BASE STOPS AT THE TIME LINE. With an overage above it, its top
               corners go square and the overage carries the cap. */
            UnevenRoundedRectangle(topLeadingRadius: (isOver || cap > 0) ? 0 : S.radiusPip,
                                   topTrailingRadius: (isOver || cap > 0) ? 0 : S.radiusPip)
                .fill(S.gainBar)
                .frame(height: max(3, h(min(s.collected, s.time))))
                .scaleEffect(y: grown || reduceMotion ? 1 : 0, anchor: .bottom)
                .animation(reduceMotion ? nil : S.easeSettle(S.durBar).delay(0.07), value: grown)
            if isOver {
                /* The deeper green past the line. `--gain-text` is a text token used
                   as a fill here on purpose: it is the "+$560 over" figure standing
                   up, so the dark cap and the words read as one fact. */
                UnevenRoundedRectangle(topLeadingRadius: S.radiusPip, topTrailingRadius: S.radiusPip)
                    .fill(S.gainText)
                    .frame(height: h(over))
                    .offset(y: -h(s.time))
                    .scaleEffect(y: grown || reduceMotion ? 1 : 0, anchor: .bottom)
                    .animation(reduceMotion ? nil : S.easeSettle(S.durBar).delay(0.14), value: grown)
            }
            /* ⚠ THE LIGHTER CAP IS NOT EARNED YET. Nik, 17 Sep 2026: the solid
               bar is settled credit, and what this week's open legs have taken
               in sits above it, in the same green at a third of its weight, so
               it reads as the same money in a different state. */
            if cap > 0 {
                UnevenRoundedRectangle(topLeadingRadius: S.radiusPip, topTrailingRadius: S.radiusPip)
                    .fill(S.gainBar.opacity(0.32))
                    .frame(height: max(3, h(cap)))
                    .offset(y: -h(max(s.collected, 0)))
                    .scaleEffect(y: grown || reduceMotion ? 1 : 0, anchor: .bottom)
                    .animation(reduceMotion ? nil : S.easeSettle(S.durBar).delay(0.2), value: grown)
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
        .animation(reduceMotion ? nil : S.easeSettle(0.55), value: s.collected)
        .animation(reduceMotion ? nil : S.easeSettle(0.55), value: tab)
    }

    // MARK: the clocks

    @ViewBuilder private func clock(time: Bool) -> some View {
        let level = time ? h(s.time) : h(max(s.collected, s.time))
        VStack(spacing: 2) {
            if time {
                Text(meltShare).font(S.inter(S.t12, S.wBoldN))
                    .tracking(S.track(S.t12, -0.01)).foregroundStyle(S.ink)
                    .sunnyLineBox(S.t12)
                /* The card's one hint, on the control and never on what it changes. */
                Text(byWeek ? "since last week" : "since yesterday")
                    .font(S.inter(S.t10, S.wMidSmN)).foregroundStyle(S.mute)
                    .sunnyLineBox(S.t10)
                    .sunnyHint()
                    .padding(.vertical, 8).contentShape(Rectangle())
                    .onTapGesture { byWeek.toggle() }
                    .padding(.vertical, -8)
            } else {
                Text(meetTop).font(S.inter(S.t12, S.wBoldN))
                    .tracking(S.track(S.t12, -0.01))
                    .foregroundStyle(s.covered ? S.gainText : S.ink)
                    .sunnyLineBox(S.t12)
                Text(meetBottom).font(S.inter(S.t10, S.wMidSmN)).foregroundStyle(S.mute)
                    .sunnyLineBox(S.t10)
            }
        }
        .fixedSize()
        .padding(.horizontal, -Self.bleed)
        .offset(y: -(level + Self.lift))
        .frame(maxHeight: .infinity, alignment: .bottom)
        .animation(reduceMotion ? nil : S.easeSettle(0.55), value: level)
    }

    private var sharePct: String {
        s.time > 0 ? "\(Int((Double(s.collected) / Double(s.time) * 100).rounded()))%" : "\u{2014}"
    }
    /* ⚠ THE MELT READS AS A SHARE, NOT DOLLARS. The dollars are already under the
       bar, and a share is the same fraction on both sides so the reading survives
       the tab. Ink, never red: melting time value is the target coming closer. */
    private var meltShare: String {
        guard let prev = byWeek ? s.hist.week : s.hist.yday, prev > 0 else { return "\u{2014}" }
        let f = Double(s.time - prev) / Double(prev) * 100
        return (f < 0 ? "\u{2212}" : "+") + String(format: "%.1f%%", abs(f))
    }
    private var meetTop: String {
        if s.covered { return "covered" }
        guard let d = s.daysToMeet else { return "\u{2014}" }
        return "\(Int((Double(d) / 7).rounded())) wk"
    }
    private var meetBottom: String {
        if s.covered { return "+" + optMoney(over) + " over" }
        guard let d = s.daysToMeet else { return "no pace yet" }
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"
        return f.string(from: Date().addingTimeInterval(Double(d) * 86_400))
    }

    // MARK: the footer

    /* The two speeds of the same chase: the left bar coming down, the right one
       coming up. Their sum is what the meet clock divides by. */
    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(optMoney(-s.melt * 7)).font(S.inter(S.t11, S.wSemiN)).foregroundStyle(S.ink)
                Text("melts a week").font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(s.covered ? "still coming in a week" : "collected a week")
                    .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                /* ⚠ THE SIGN COMES FROM THE FIGURE. A week that spent more
                   buying legs back than it took in is negative, and a hardcoded
                   "+" printed "+−$507". Since 17 Sep the put side can run
                   negative: rolls cost more than the new credits. */
                Text(signedMoney(Double(s.pace)))
                    .font(S.inter(S.t11, S.wSemiN))
                    .foregroundStyle(s.pace < 0 ? S.lossText : S.gainText)
            }
        }
        .sunnyLineBox(S.t11)
    }
}

/// Top and both sides of the time bar, open at the floor.
private struct TimeEdge: Shape {
    let radius: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        let x0 = r.minX + 0.5, x1 = r.maxX - 0.5, y0 = r.minY + 0.5, yb = r.maxY
        p.move(to: CGPoint(x: x0, y: yb))
        p.addLine(to: CGPoint(x: x0, y: y0 + radius))
        p.addQuadCurve(to: CGPoint(x: x0 + radius, y: y0), control: CGPoint(x: x0, y: y0))
        p.addLine(to: CGPoint(x: x1 - radius, y: y0))
        p.addQuadCurve(to: CGPoint(x: x1, y: y0 + radius), control: CGPoint(x: x1, y: y0))
        p.addLine(to: CGPoint(x: x1, y: yb))
        return p
    }
}

// MARK: - 3 · Weekly yield

/* ⚠ THIS REPLACES THE PREVIOUS WEEKLY YIELD CARD, 14 Sep 2026, from the
   `weekly-yield` handoff (cards/weekly-yield.md, Sunny Weekly Yield Card.dc.html).
   The old card is deleted, not kept beside it.

   ⚠ A RATE TAKES NO DIRECTION INK. Yield is not a gain or a loss, it is how fast
   the book earns, so seven bars are grey, the live week is the one green, and the
   average is an INK line rather than a green one. The only red on the card is the
   buyback cap: the part of a week's gross that went on closing legs early, which
   is a real loss of income and is the one thing here that earns loss ink.

   ⚠ THE AVERAGE IS OF WHAT WAS KEPT, gross less buybacks, week by week and then
   averaged. Averaging the gross and subtracting the average buyback gives the same
   answer today and a wrong one in the first week a buyback is skipped.

   ⚠ AND EACH WEEK KEEPS ITS OWN DENOMINATOR, which is where this departs from the
   sheet. The sheet divides every week by one book-wide figure; Nik's ruling of
   2026-09-08 is that a closed week can never be rewritten, so the server dates the
   ledger and a week is measured against the capital that existed while it ran. The
   week of 31 August divides by $195,510 where this week divides by $249,455, and
   both are right. See `feedback_closed_periods_never_change`. */
struct SunnyWeeklyYield: View {
    let book: OptionsBook
    /// Put cover — what the hedge needs per week before the puts expire.
    var putNeed: Int = 0
    /// Freshness: the average, the live week's kept and closed early, yearly.
    var fresh: FreshTrack? = nil
    var updating = false

    /// The figures Freshness watches, as printed, independent of a picked week.
    static func freshFigs(_ b: OptionsBook) -> [String: [String: String]] {
        let v = SunnyWeeklyYield(book: b)
        let live = v.weeks.last(where: \.live) ?? v.weeks.last
        return ["w:avg": ["v": v.pct2(v.avgKept)],
                "w:kept": ["v": v.pct2(live?.kept ?? 0)],
                "w:closed": ["v": v.pct2(live?.bought ?? 0)],
                "w:yearly": ["v": "\(Int((v.avgKept * 52).rounded()))"]]
    }
    private func fr(_ key: String, _ own: Color, live: Bool = true) -> Color {
        live && fresh?.isMarked("w:\(key)", "v") == true ? S.warn : own
    }

    /// null = the average is the reference; otherwise that week is.
    /* ⚠ VERIFICATION ONLY, the same device as `-rollFig`: the simulator's
       touch bridge crashes, so `-wyPick 2026-08-17` forces a week and proves
       the picked state RENDERS. It does not test the tap. */
    @State private var picked: String? = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-wyPick"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }()
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Wk: Identifiable {
        let id: String, label: String, live: Bool
        let gross: Double, bought: Double
        /// Next week's ghost, the same units as `gross`. 0 elsewhere.
        var plan: Double = 0
        var kept: Double { gross - bought }
        /// Nothing sold yet: the column is the outline alone.
        var ghostOnly: Bool { gross <= 0 && bought <= 0 }
    }

    /* ⚠ THE WEEKS THAT PRE-DATE THE BOOK ARE NOT PLOTTED. Three of the eight
       columns are zero because the structure did not exist yet, and eight
       columns with three empty ones read as three weeks that earned nothing.
       They age out of the window on their own. */
    private var weeks: [Wk] {
        book.weekly.compactMap { w -> Wk? in
            let den = Double(w.denom ?? book.paid)
            guard den > 0 else { return nil }
            let g = Double(w.gross ?? w.credit), b = Double(w.bought ?? 0)
            let p = Double(w.plan ?? 0)
            guard g > 0 || b > 0 || p > 0 else { return nil }
            return Wk(id: w.week, label: shortWeek(w.week), live: w.current ?? false,
                      gross: g / den * 100, bought: b / den * 100, plan: p / den * 100)
        }
    }
    /// The axis is set by the tallest GROSS bar; every height is a share of it.
    private var maxGross: Double { max(weeks.map { max($0.gross, $0.plan) }.max() ?? 1, 0.01) }
    /* ⚠ A WEEK THAT HAS NOT HAPPENED IS NOT A WEEK THAT RAN. Next week's bar
       takes a credit the moment one call is sold for it, and counted as a
       whole week that sliver dragged the average from 2.08% to 1.69% (24 Sep).
       The average, Yearly and the week count read up to the live week only;
       the forward bar still draws. The server's rule for the same figure. */
    private var ran: [Wk] {
        let live = weeks.last(where: \.live)?.id ?? "9999"
        return weeks.filter { !$0.ghostOnly && $0.id <= live }
    }
    private var avgKept: Double {
        let r = ran
        return r.isEmpty ? 0 : r.reduce(0) { $0 + $1.kept } / Double(r.count)
    }
    /// The week the card is reading: the picked one, else the live one.
    private var at: Wk? {
        if let picked, let w = weeks.first(where: { $0.id == picked }) { return w }
        return weeks.last(where: \.live) ?? weeks.last
    }
    private var refValue: Double {
        if let picked, let w = weeks.first(where: { $0.id == picked }) { return w.kept }
        return avgKept
    }
    /* ⚠ THE FLOOR IS WHAT THE HEDGE NEEDS A WEEK, NOT ITS WHOLE COST OVER EIGHT.
       The sheet spreads the combined put cost across the eight weeks plotted,
       which is arbitrary and, on this book, wildly wrong: $46,355 over eight
       weeks says the hedge costs 2.32% a week and puts the line above every bar.
       The puts run to March. Put cover already computes what it takes per week
       to clear them before they expire, and that is the honest line: $1,635, or
       0.66%. A week whose kept height falls under it is a week the hedge outran
       income. */
    private var floorPct: Double {
        let den = Double(book.paid)
        return den > 0 ? Double(putNeed) / den * 100 : 0
    }

    private func shortWeek(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]) else { return iso }
        return "\(m)/\(d)"
    }
    /// "14 Sep" — the eyebrow has the whole card's width, so the week is named
    /// rather than keyed. The axis labels stay "9/14": four of them share 323.
    private func longWeek(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        let mon = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m)
        else { return iso }
        return "\(d) \(mon[m - 1])"
    }
    private func pct2(_ v: Double) -> String { String(format: "%.2f%%", v) }
    private func settle(_ d: Double, delay: Double = 0) -> Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: d).delay(delay)
    }

    private let plotH: CGFloat = 147
    private func y(_ v: Double) -> CGFloat { CGFloat(v / maxGross) * plotH }

    var body: some View {
        OptCard(name: "weekly-yield") {
            OptHead(title: "Weekly yield", sub: "on premium paid",
                    right: "\(ran.count) week" + (ran.count == 1 ? "" : "s"),
                    fresh: fresh, updating: updating)
            Spacer().frame(height: S.gap6)

            VStack(alignment: .leading, spacing: 5) {
                /* ⚠ THE EYEBROW NAMES THE WEEK IN WORDS. Nik, 14 Sep 2026:
                   "kept that week sounds very confusing we need to write the
                   week number so say week of 14th sep". "8/17" over "kept that
                   week" made the reader join two halves of one sentence across
                   a 30pt figure, and "that week" pointed at a label it did not
                   touch. The eyebrow now says which week and the line beside
                   the figure says only what the figure is. */
                Text(picked == nil ? "AVERAGE"
                     : ("WEEK OF " + longWeek(at?.id ?? "")).uppercased())
                    .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.mute)
                HStack(alignment: .firstTextBaseline, spacing: S.gap3) {
                    Text(pct2(refValue))
                        .font(S.inter(S.t30, S.wBoldN)).tracking(S.track(S.t30, -0.03))
                        .foregroundStyle(fr("avg", S.ink, live: picked == nil)).sunnyLineBox(S.t30)
                    Text(picked == nil ? "a week, kept" : "kept")
                        .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
                    Spacer(minLength: 0)
                    /* The legend explains the card's one red and does not move. */
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(S.lossBar)
                            .frame(width: 8, height: 8)
                        /* ⚠ "BOUGHT BACK" NAMED THE WRONG WEEK. Nik, 14 Sep:
                           "we haven't bought anything back this week". He had
                           not — the $2,377 capping the 9/14 bar is six closes
                           he made on the 10th and 11th, on NKE 37.5 puts and
                           LULU 97 puts that EXPIRE on the 18th. The bar buckets
                           by the week a leg covers, his own ruling of 3 Sep, so
                           the money paid to close those legs has to sit in the
                           same bar as the credit it cancels or the week would
                           show a credit he no longer holds.
                           "Closed early" describes the LEG rather than dating
                           the trade, which is the claim that was wrong. */
                        Text("closed early").font(S.inter(S.t11, S.wMidSmN))
                            .foregroundStyle(S.mute)
                    }
                    .fixedSize()
                }
            }

            Spacer().frame(height: 18)
            plot
            Spacer().frame(height: S.gap4)

            HStack(alignment: .top, spacing: S.gap4) {
                ForEach(weeks) { w in
                    let on = w.live || w.id == picked
                    Text(w.label)
                        .font(S.inter(S.t11, on ? S.wBoldN : S.wMidSmN))
                        .foregroundStyle(on ? S.ink : S.mute)
                        .lineLimit(1).fixedSize()
                        .frame(width: 30)
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: S.gap6)
            OptFooter(stats: [
                .init(label: "Kept", value: pct2(at?.kept ?? 0),
                      ink: fr("kept", S.ink, live: at?.live ?? false)),
                /* ⚠ MEASURED, NOT GUESSED: "CLOSED EARLY" is 90.5 at 10/700
                   with .13em tracking, against 91.67 of slot. "PAID TO CLOSE"
                   was 91.9 and would have truncated. */
                .init(label: "Closed early",
                      value: (at.map { $0.bought > 0 ? "\u{2212}" : "" } ?? "")
                             + pct2(at?.bought ?? 0),
                      ink: fr("closed", (at?.bought ?? 0) > 0 ? S.lossText : S.mute,
                              live: at?.live ?? false)),
                /* ⚠ YEARLY DOES NOT FOLLOW THE TAP, on purpose: one week
                   annualised is a forecast and this card makes none. */
                .init(label: "Yearly", value: "\(Int((avgKept * 52).rounded()))%",
                      ink: fr("yearly", S.ink)),
            ])
        }
        .modifier(OptionalFreshSeen(track: fresh))
        .task(id: weeks.count) {
            guard !weeks.isEmpty, !appeared else { return }
            try? await Task.sleep(for: .milliseconds(20))
            appeared = true
        }
    }

    // MARK: the plot

    @ViewBuilder private var plot: some View {
        let grown = reduceMotion || appeared
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(S.ruleColor).frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)

            HStack(alignment: .bottom, spacing: S.gap4) {
                ForEach(Array(weeks.enumerated()), id: \.element.id) { i, w in
                    /* ⚠ THE CAP IS ANCHORED AT THE BAR'S TOP, so the grey or
                       green left under it is what was kept. A cap drawn from the
                       bottom would read as the week starting in the red. */
                    ZStack(alignment: .top) {
                        Rectangle().fill(w.live ? S.gainBar : S.barQuiet)
                            .frame(height: w.ghostOnly ? 0 : max(1, y(w.gross)))
                        if w.bought > 0 {
                            /* ⚠ HATCHED ON A PAST WEEK, NEVER A LIGHTER RED.
                               Solid is the live week alone, so eight caps do not
                               read as eight exceptions — but the deck's own rule
                               is that a provisional signal cannot be LIGHTNESS
                               (the leg card measured a lighter fill at 2.07:1).
                               A hatch keeps the ink and changes the texture. */
                            Group {
                                if w.live { Rectangle().fill(S.lossBar) }
                                else { SunnyHatch(ink: S.lossBar, stripe: 1, gap: 2) }
                            }
                            .frame(height: max(1, y(w.bought)))
                        }
                    }
                    .frame(width: 30, height: max(1, y(w.gross)), alignment: .top)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: S.radiusBar,
                                                      bottomLeadingRadius: 1,
                                                      bottomTrailingRadius: 1,
                                                      topTrailingRadius: S.radiusBar))
                    .scaleEffect(y: grown ? 1 : 0, anchor: .bottom)
                    .animation(settle(0.72, delay: Double(i) * 0.055), value: appeared)
                    .animation(reduceMotion ? nil : settle(0.55), value: picked)
                    /* ⚠ THE GHOST: next week's plan as a dashed outline the bar
                       fills into. Calls only; the part already booked is the
                       solid bar inside it, so the gap is what is left to sell. */
                    .frame(width: 30, height: max(y(w.gross), y(w.plan)), alignment: .bottom)
                    .overlay(alignment: .bottom) {
                        if w.plan > 0 {
                            UnevenRoundedRectangle(topLeadingRadius: S.radiusBar,
                                                   bottomLeadingRadius: 1,
                                                   bottomTrailingRadius: 1,
                                                   topTrailingRadius: S.radiusBar)
                                .strokeBorder(S.mute, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                .frame(width: 30, height: y(w.plan))
                                .opacity(grown ? 1 : 0)
                                .animation(settle(0.5, delay: 0.6), value: appeared)
                        }
                    }
                    .contentShape(Rectangle())
                    /* The tap target is the bar. No text on this card flips, so
                       nothing here carries the dotted underline: that hint marks
                       tappable TEXT and would be a lie on a week label. */
                    /* ⚠ THE GHOST IS NOT A WEEK TO READ until something is sold
                       into it: picking it printed Kept 0.00% (Nik, 24 Sep). */
                    .onTapGesture {
                        guard !w.ghostOnly else { return }
                        picked = (picked == w.id) ? nil : w.id
                    }
                }
                /* ⚠ LEFT-ALIGNED, NOT SPREAD. Eight columns at flex:1 in 323
                   measure 34 and read chunky, so the bar is capped at 30 and
                   the slack is left on the RIGHT. Spreading them instead makes
                   the live week drift sideways every time a week is added or
                   drops out of the window, which is the one column the eye
                   goes to. */
                Spacer(minLength: 0)
            }
            .frame(height: plotH, alignment: .bottom)

            /* The average, or the week the reader picked. It SLIDES between them. */
            Rectangle().fill(S.ink)
                .frame(height: 1.5).clipShape(RoundedRectangle(cornerRadius: 1))
                .offset(y: -y(refValue))
                .opacity(grown ? 1 : 0)
                .animation(reduceMotion ? nil : settle(0.6, delay: 0.5), value: appeared)
                .animation(reduceMotion ? nil : settle(0.55), value: picked)

            if floorPct > 0 {
                Rectangle().fill(S.hair).frame(height: 1.5).offset(y: -y(floorPct))
                Text("puts " + pct2(floorPct))
                    .font(S.inter(S.t10, S.wMidSmN)).foregroundStyle(S.mute)
                    .fixedSize().offset(y: -y(floorPct) - 4 - 5)
            }
        }
        .frame(height: plotH)
    }
}

// MARK: - prices

/* ⚠ THIS REPLACES THE STOCK PRICE CARD, 12 Sep 2026, from the `prices-card`
   handoff (CARDS.md "Prices", cards/prices.md, Sunny Prices Card.dc.html). The
   old card is deleted, not kept beside it.

   The design's first rule, and the reason it is a different card rather than a
   restyle: PRICE IS THE INPUT; WHAT THE MOVE DID TO YOU IS THE STORY. Eight
   percentages on their own are a quote screen. Every row here reads four other
   cards against its move, and this card owns none of those numbers:

     ticks on the bar   roll check    the nearest sold call and put strikes
     the ticker's ink   inventory     whether there is anything left to write
     the word under it  premium now   what the name's IV is doing
     the dollars        upside left   how much of the move you actually kept

   ⚠ "TODAY" IS A FACT ABOUT THE DATA, NEVER A GUESS FROM THE CLOCK. The day
   window is named from the last close's DATE: dated today reads "today", dated
   yesterday reads "yesterday", anything else reads the weekday it was, so a
   Monday pre-market reads "Friday".

   ⚠ AND THE DAY WINDOW LEAVES THE CARD OVER THE WEEKEND. Friday 20:00 ET to
   Monday 04:00 ET there is nothing honest to call "today", so the chip and the
   word GO and 1w is the default. Removing the control beats greying it: a
   disabled "today" on a Sunday is a question the card is refusing to answer.

   ⚠ ONE AXIS, ZERO IN THE MIDDLE. The widest move × 1.1 sets both ends, so a
   long bar is a big move in every row and the rows are comparable.

   ⚠ A TAP FLIPS A COLUMN, NEVER A ROW. Per-row state would make eight rows
   eight different cards. And every text that flips carries the dotted hair
   underline — exactly that set, nothing else. */
struct SunnyPrices: View {
    let prices: PricesBlock

    private enum Fig { case pct, px, usd }
    /* ⚠ THE CARD OPENS ON THE DAY WINDOW. Nik, 14 Sep 2026: "on refresh the
       price card keep going back to 1w vs today it needs to be always today
       when refreshed." It defaulted to 1w, from the days when the day window
       left the card at the weekend; it never leaves it now, and a card that
       resets to last week every time the book reloads is answering yesterday's
       question. */
    @State private var win: Int = 0          // 0 = the day window, 1-4 weeks
    @State private var fig: Fig = .pct
    @State private var showDelta = false     // the side word: IV or delta
    /// Re-read on every appearance so Friday 20:00 and Monday 04:00 land.
    @State private var now = Date()
    /* ⚠ THE MOTION IS THE SHEET'S §7, AND THE TWO HALVES ARE DIFFERENT THINGS.
       An ENTRANCE plays once, when the card first arrives: every bar grows from
       the zero line, staggered 18ms down the rows, and the ticks fade in only
       AFTER the bars have landed, because a tick has nothing to annotate until
       its bar exists. A GLIDE plays on every later change: switching the window
       or flipping a column slides the bars and ticks to their new places rather
       than cutting, so the eye keeps hold of the row it was reading.

       `appeared` gates the first and nothing else, so a window change can never
       replay the entrance. */
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: the day window

    private var etCal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return c
    }
    /* ⚠ THE DAY WINDOW NEVER LEAVES THE CARD ANY MORE. The handoff removed it
       from Friday 20:00 ET to Monday 04:00 ET, on the argument that there is
       nothing honest to call "today" on a Sunday. True, and the wrong
       conclusion: the honest thing is to report the last session and NAME it.
       Nik, 2026-09-14: "on Monday it will show the data for Friday... we have
       to say last Friday and show the data." */
    private var wins: [Int] { [0, 1, 2, 3, 4] }
    private var window: Int { wins.contains(win) ? win : wins[0] }

    /* ⚠ THE WORD IS THE SESSION'S OWN DATE, never the clock. Today while one is
       running, yesterday if that is when it closed, otherwise the weekday it
       was — and "last Friday" rather than "Friday" once a weekend sits between,
       because on a Monday morning "Friday" alone reads as the Friday coming. */
    private var sessionWord: String {
        if prices.live == true { return "today" }
        let f = DateFormatter()
        f.calendar = etCal; f.timeZone = etCal.timeZone
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: prices.asOf) else { return "today" }
        let today = etCal.startOfDay(for: now), day = etCal.startOfDay(for: d)
        let days = etCal.dateComponents([.day], from: day, to: today).day ?? 0
        if days == 0 { return "today" }
        if days == 1 { return "yesterday" }
        f.dateFormat = "EEEE"
        let name = f.string(from: d)
        /* An earlier week, not merely an earlier day: on a Saturday, Friday is
           still this week and takes no prefix. */
        let wNow = etCal.component(.weekOfYear, from: today)
        let wThen = etCal.component(.weekOfYear, from: day)
        return wNow != wThen ? "last " + name : name
    }
    /// "Fri 11 Sep" — derived, never a literal. It shipped once as a date that
    /// was a Saturday.
    private var asOfLabel: String {
        let f = DateFormatter()
        f.calendar = etCal; f.timeZone = etCal.timeZone
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: prices.asOf) else { return "" }
        f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }
    private func windowWord(_ w: Int) -> String {
        w == 0 ? sessionWord : "\(w)w"
    }

    // MARK: the rows

    private struct Row: Identifiable {
        let id: String
        let t: String, pct: Double, spot: Double
        /// Cost basis. The card's order, and the hero's weighting.
        let weight: Int
        let free: Int, delta: Int
        let callK: Double?, putK: Double?
        let side: String, sideRich: Bool
        /// The per-share move in dollars, derived from the percentage and the
        /// spot rather than shipped: before = spot / (1 + pct/100).
        var perShare: Double { spot - spot / (1 + pct / 100) }
        /// ⚠ NET DELTA, NOT the sheet's `share kept × open contracts`. That
        /// product sizes the move by the SHORT book, which suits a book of small
        /// covered positions and not this one: NKE carries 15 short puts against
        /// 60 long calls, so it would price the move on 795 shares where the
        /// position moves like 4,400. Same question, asked correctly.
        var made: Double { perShare * Double(delta) }
    }

    private var rows: [Row] {
        prices.rows.compactMap { r -> Row? in
            let w: PriceWindow = window == 0 ? .today : window == 1 ? .w1
                               : window == 2 ? .w2 : window == 3 ? .w3 : .w4
            guard let v = r.pct.value(w), let sp = r.spot, sp > 0 else { return nil }
            return Row(id: r.ticker, t: r.ticker, pct: v, spot: sp, weight: r.weight,
                       free: r.free ?? 0, delta: r.delta ?? 0,
                       callK: r.callK, putK: r.putK,
                       side: r.ivWord ?? "", sideRich: r.ivRich)
        }
        /* ⚠ BIGGEST POSITION FIRST, WHICH OVERRIDES THE SHEET. It specifies
           "biggest gainer first"; Nik, 2026-09-12: "Can we organize by position
           size". He is right for this book. A gainer sort re-orders the whole
           card every window and every session, so the row you were reading
           moves under you, and it ranks a $6k KR position above a $75k NKE one
           for being up a tenth of a percent. Size is a fact about the book that
           holds still, and the bar already ranks the moves.

           Size is COST BASIS — what the position is built on, the same weight
           the ticker strip and the hero use. */
        .sorted { $0.weight > $1.weight }
    }
    /// One symmetric axis for every row, zero at the centre.
    private var lim: Double {
        max(rows.map { abs($0.pct) }.max() ?? 1, 0.01) * 1.1
    }
    private var mean: Double {
        rows.isEmpty ? 0 : rows.reduce(0) { $0 + $1.pct } / Double(rows.count)
    }
    private var ups: Int { rows.filter { $0.pct >= 0 }.count }

    // MARK: measured columns

    private var nameCol: CGFloat { 52 }
    private var figCol: CGFloat {
        max(62, (rows.map { S.textW(figText($0), S.t13, S.wBoldN) }.max() ?? 0) + 3)
    }
    private var barW: CGFloat { S.content - 48 - nameCol - 10 - 10 - figCol }

    /// The deck's settle curve, the same cubic the reference uses.
    private func settle(_ d: Double, delay: Double = 0) -> Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: d).delay(delay)
    }

    private func figText(_ r: Row) -> String {
        switch fig {
        case .pct: return signed1Pct(r.pct)
        case .px:  return "$" + String(format: "%.2f", r.spot)
        case .usd: return optMoney(Int(r.made.rounded()))
        }
    }
    /// A move that rounds to zero carries no sign.
    private func signed1Pct(_ v: Double) -> String {
        let a = String(format: "%.1f", abs(v))
        return (a == "0.0" ? "" : v < 0 ? "\u{2212}" : "+") + a + "%"
    }

    // MARK: body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
                HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                    Text("Prices").font(S.inter(S.t14, S.wBoldN))
                        .tracking(S.track(S.t14, -0.01)).foregroundStyle(S.ink)
                    Text("held names").font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
                }
                Spacer(minLength: 0)
                Text(asOfLabel).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
            }

            Spacer().frame(height: 22)

            /* The eyebrow is the figure column's MODE, so the label and the
               column can never disagree about what is being printed. */
            HStack(alignment: .center, spacing: S.gap6) {
                Text(fig == .px ? "PRICE" : fig == .usd ? "MADE YOU" : "CHANGE")
                    .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.mute)
                Spacer(minLength: 0)
                /* ⚠ THE CHIPS BLEED THEIR HIT AREA, they do not grow the row.
                   A 32pt target on a 12pt eyebrow row: padding reaches the
                   target and a negative margin gives the layout back. 44 would
                   collide with the header above and the hero below, and that
                   is a recorded deviation rather than an oversight. */
                HStack(spacing: 4) {
                    ForEach(wins, id: \.self) { w in
                        Text(windowWord(w))
                            .font(S.inter(S.t12, w == window ? S.wBoldN : S.wMidN))
                            .tracking(S.track(S.t12, -0.01))
                            .foregroundStyle(w == window ? S.ink : S.mute)
                            .padding(.vertical, 10).padding(.horizontal, 7)
                            .contentShape(Rectangle())
                            .onTapGesture { win = w }
                    }
                }
                .padding(.vertical, -10).padding(.horizontal, -6)
            }
            .frame(height: 12)

            Spacer().frame(height: 12)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(signed1Pct(mean))
                    .font(S.inter(S.t30, S.wBoldN)).tracking(S.track(S.t30, -0.035))
                    .foregroundStyle(mean < 0 ? S.lossText : S.gainText)
                    .sunnyLineBox(S.t30)
                Text("\(ups) of \(rows.count) up \u{00B7} "
                     + (window == 0 ? sessionWord
                        : "\(window) week" + (window == 1 ? "" : "s")))
                    .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
            }

            Spacer().frame(height: 28)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    rowFor(r, index: i)
                }
            }

            Spacer().frame(height: 16)

            Text(fig == .usd
                 ? "the move \u{00D7} the shares you are effectively long"
                 : "ticks: call strike above the bar, put strike below")
                .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
        }
        .frame(width: S.content - 48, alignment: .leading)
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 28, trailing: 24))
        .frame(width: S.content, alignment: .top)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCard)
        .monospacedDigit()
        .measure("prices")
        /* ⚠ THE SAME FIX AS ROLL CHECK: `onAppear` fires on the EMPTY card while
           the fetch is in flight, so the flag was true before a bar existed and
           the grow-from-zero had nothing to grow. It flips one frame after the
           first non-empty render instead. Once only: a window change must never
           replay the entrance, and the flag is what keeps the two kinds of
           motion apart. */
        .task(id: rows.count) {
            now = Date()
            guard !rows.isEmpty, !appeared else { return }
            try? await Task.sleep(for: .milliseconds(20))
            appeared = true
        }
    }

    // MARK: one row

    @ViewBuilder private func rowFor(_ r: Row, index: Int) -> some View {
        let half = barW / 2
        let w = CGFloat(abs(r.pct) / lim) * half
        let up = r.pct >= 0
        let grown = reduceMotion || appeared
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                /* ⚠ THE TICKER'S INK IS THE INVENTORY READING. A big mover you
                   cannot write on is less interesting than one you can. */
                Text(r.t).font(S.inter(S.t13, S.wSemiN)).tracking(S.track(S.t13, -0.01))
                    .foregroundStyle(r.free > 0 ? S.ink : S.mute).lineLimit(1)
                /* ⚠ 10px SENTENCE CASE, the deck's one exception to the 10px
                   rule, accepted because it is a tap label under a 13px ticker
                   inside a 52pt cell: at 11 "normal IV" wrapped. */
                /* ⚠ THE SLOT IS ALWAYS THERE, even when the name has no IV
                   word. The two-line cell is what sets the 27pt row, so a name
                   without enough IV history to have a median would otherwise
                   render a SHORTER row and the list's rhythm would break on
                   whichever names happen to have history. Four of our seven do
                   not. Empty, not zero: an absent median is not "normal IV". */
                Text(showDelta ? "\(r.delta) sh" : r.side)
                    .font(S.inter(S.t10, S.wMidSmN))
                    .foregroundStyle(showDelta ? S.mute : (r.sideRich ? S.gainText : S.mute))
                    .lineLimit(1).fixedSize()
                    .sunnyHint(on: showDelta || !r.side.isEmpty)
                    .frame(height: 10, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { showDelta.toggle() }
            }
            .frame(width: nameCol, height: 27, alignment: .leading)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: S.radiusBar).fill(S.wash)
                    .frame(width: barW, height: 14)
                /* ⚠ UNDER THE BAR, NOT OVER IT. Drawn last it showed through
                   every fill as a grey seam at the zero line. It reaches 4
                   above and below the track. */
                Rectangle().fill(S.hair).frame(width: 1.5, height: 22).offset(x: half - 0.75)
                /* ⚠ THE BAR GROWS FROM THE ZERO LINE, which means the anchor
                   is the side the bar STARTS on: a gain opens rightward from
                   the centre, a loss opens leftward into it. Scaling from the
                   wrong anchor slides the bar across the axis instead of
                   growing along it, and for one beat it reads as the opposite
                   move. */
                RoundedRectangle(cornerRadius: S.radiusBar)
                    .fill(up ? S.gainBar : S.lossBar)
                    .frame(width: max(2, w), height: 14)
                    .scaleEffect(x: grown ? 1 : 0, anchor: up ? .leading : .trailing)
                    .offset(x: up ? half : half - max(2, w))
                    .animation(settle(0.72, delay: Double(index) * 0.018), value: appeared)
                    .animation(reduceMotion ? nil : settle(0.55), value: window)
                    .animation(reduceMotion ? nil : settle(0.55), value: barW)
                /* ⚠ A TICK IS DRAWN ONLY WHEN IT IS ON THE AXIS. A far strike
                   pinned to the edge would lie about its distance, so it is
                   simply absent. Calls rise from the midline, puts hang from
                   it: direction is the whole distinction and there is no
                   second colour. A strike is a fact, not a gain or a loss
                   until the bar reaches it. */
                tick(r.callK, spot: r.spot, half: half, up: true, shown: grown)
                tick(r.putK, spot: r.spot, half: half, up: false, shown: grown)
            }
            .frame(width: barW, height: 14)

            Text(figText(r))
                .font(S.inter(S.t13, S.wBoldN)).tracking(S.track(S.t13, -0.015))
                .foregroundStyle(fig == .px ? S.ink : (up ? S.gainText : S.lossText))
                .lineLimit(1).fixedSize()
                /* The hint marks the tappable TEXT. Applied outside the column
                   frame it underlined 62pt of empty space to the figure's
                   left. */
                .sunnyHint()
                .frame(width: figCol, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture { fig = fig == .pct ? .px : fig == .px ? .usd : .pct }
        }
        .frame(height: 27)
    }

    @ViewBuilder private func tick(_ k: Double?, spot: Double,
                                   half: CGFloat, up: Bool, shown: Bool) -> some View {
        if let k, spot > 0 {
            let pct = (k / spot - 1) * 100
            if abs(pct) <= lim {
                Rectangle().fill(S.ink)
                    .frame(width: 2, height: 12)
                    /* 5 outside the track plus the track's own 7 = 12, so the
                       centre sits 6 off the midline and the tick stops exactly
                       on it. */
                    .offset(x: half + CGFloat(pct / lim) * half - 1,
                            y: up ? -6 : 6)
                    /* ⚠ THE TICKS ARRIVE AFTER THE BARS, by .6s. They annotate
                       the bar, so fading them in alongside it gives the row two
                       things moving and no order to read them in. */
                    .opacity(shown ? 1 : 0)
                    .animation(reduceMotion ? nil : settle(0.5, delay: 0.6), value: appeared)
                    .animation(reduceMotion ? nil : settle(0.55), value: window)
            }
        }
    }
}

/// The deck-wide tap hint, 12 Sep 2026: every text that flips on tap carries a
/// dotted hair underline, and only that text does. Silent once the card is
/// known, visible when it is not. Shared with Inventory, whose Held figure is
/// its one underline.
extension View {
    func sunnyHint(on: Bool = true) -> some View {
        self.overlay(alignment: .bottom) {
            if on { SunnyDots().frame(height: 1).offset(y: 3) }
        }
    }
}
private struct SunnyDots: View {
    var body: some View {
        GeometryReader { g in
            Path { p in
                p.move(to: .init(x: 0, y: 0.5)); p.addLine(to: .init(x: g.size.width, y: 0.5))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [1.5, 1.5]))
            .foregroundStyle(S.hair)
        }
    }
}

/* ⚠ THE INVENTORY CARD AND THE TO ROLL CARD WERE DELETED HERE, 2026-09-11,
   on Nik's instruction. Inventory's job now lives on Roll check, one muted
   line under each percentage saying what is still free to sell on that side
   of that name. To roll's per-leg figures were already on Roll check; what
   went with it was the ALL TIME block, the Kept / Rolled back / LEAP trio
   per name, and that now lives nowhere. Ask before rebuilding either. */

// MARK: - 01 · Programme

/* ⚠ REBUILT FROM `export 14`, 14 Sep 2026. Am I up, all in or one name.

   ⚠ THE TWO LEGS ARE ONE TRADE, SO ONLY THE NET IS A RESULT. Credits kept plus
   the long calls at mark plus the long puts at mark. That is the hero and the
   only figure at 22; the three parts are printed under it as what it is made
   of, never as three results of their own.

   ⚠ ONLY KEPT IS BANKED. The two marks move every day, which the note says in
   words and the bar says again in geometry.

   ⚠ STORE KEPT AND OWED, DERIVE EVERYTHING ELSE. Long calls, long puts and
   invested are read off the LONG LEGS ledger, the same array that card draws,
   so Programme and Long legs cannot disagree by a dollar and `invested` equals
   Long legs' Paid and Intrinsic value's Paid. The All row is the sum of the
   names, never a stored total.

   ⚠ AND INK IS BY SIGN, NEVER BY ROW. A long call can be a gain, so nothing
   here is hardcoded to loss ink; a hardcoded one printed +$1,180 in red.

   ⚠ SINCE 31 AUGUST, the LEAP shift. Nik, 2026-09-10. That start makes the card
   read against the LEAPs and puts he holds now rather than against credits
   earned on shares he no longer owns. */
struct SunnyProgramme: View {
    let block: ProgrammeBlock
    /// The ledger Long legs draws. One ledger, two cards.
    let legs: [LongLeg]
    /// ⚠ PERFORMANCE, 18 Sep 2026 (`export 20`): Yield progress's names, the
    /// source of the fourth row. Time value is Intrinsic's; collected is the
    /// settled credit ledger, the same one `kept` reads.
    var cover: [YieldName] = []

    @State private var sel: String? = nil          // nil = All
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct PgRow: Identifiable {
        let t: String
        let kept: Int, open: Int, calls: Int, puts: Int, inv: Int
        var id: String { t }
        var mark: Int { calls + puts }
        var net: Int { kept + mark }
        /// ⚠ BANKED IS SETTLED CREDIT, 17 Sep 2026. Nothing open counts.
        var banked: Int { kept }
        var pct: Double { inv > 0 ? Double(net) / Double(inv) * 100 : 0 }
    }

    /// Every name that has either a credit history or a long leg. A hedge-only
    /// name belongs on this card — its mark is part of the programme — and it
    /// reads Credits kept +$0 rather than being dropped.
    private var rows: [PgRow] { Self.pgRows(block, legs) }
    /// ⚠ ONE DERIVATION, TWO CARDS. The Book's Performance tab reads these
    /// rows, so the two cannot disagree by a dollar.
    static func pgRows(_ block: ProgrammeBlock, _ legs: [LongLeg]) -> [PgRow] {
        let names = Set(block.rows.map(\.t)).union(legs.map(\.t))
        return names.map { t in
            let src = block.rows.first { $0.t == t }
            let mine = legs.filter { $0.t == t }
            /* Mark against what the held contracts cost, plus what was already
               realized selling some back: the side's whole result, so moving a
               loss out of `cost` does not move the net. */
            let pnl: (Bool) -> Int = { call in
                Int(mine.filter { $0.isCall == call }
                    .reduce(0.0) { $0 + ($1.m - $1.cost) * Double($1.n) + ($1.rz ?? 0) }.rounded())
            }
            return PgRow(t: t,
                         kept: src?.kept ?? 0, open: src?.open ?? 0,
                         calls: pnl(true), puts: pnl(false),
                         inv: Int(mine.reduce(0.0) { $0 + $1.cost * Double($1.n) }.rounded()))
        }
    }
    private var all: PgRow {
        let r = rows
        return PgRow(t: "All",
                     kept: r.reduce(0) { $0 + $1.kept }, open: r.reduce(0) { $0 + $1.open },
                     calls: r.reduce(0) { $0 + $1.calls }, puts: r.reduce(0) { $0 + $1.puts },
                     inv: r.reduce(0) { $0 + $1.inv })
    }
    private var row: PgRow { sel.flatMap { s in rows.first { $0.t == s } } ?? all }
    /// Names by net descending, so the best-standing name reads first.
    private var order: [PgRow] { rows.sorted { $0.net > $1.net } }

    /* ⚠ APPORTIONED, NOT SPLIT EVENLY. The short side belongs to a name by its
       share of the credits it has kept; the long side by its share of the money
       invested. A single netted book figure could not be divided at all, which
       is why the server ships the two rates rather than their sum. */
    private var theta: Int {
        let a = all
        let short = a.kept != 0
            ? Double(block.thetaShortDay) * Double(row.kept) / Double(a.kept) : 0
        let long = a.inv > 0
            ? Double(block.thetaLongDay) * Double(row.inv) / Double(a.inv) : 0
        return sel == nil ? block.thetaShortDay + block.thetaLongDay
                          : Int((short + long).rounded())
    }

    private func sinceLabel() -> String {
        let p = block.since.split(separator: "-")
        let mon = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m)
        else { return block.since }
        return "since \(d) \(mon[m - 1])"
    }

    var body: some View {
        let r = row
        OptCard(name: "programme", fixedHeight: nil) {
            OptHead(title: sel ?? "Performance", sub: sel == nil ? "all in" : "one name",
                    right: sinceLabel())
            Spacer().frame(height: 14)

            /* ⚠ THE PILLS ARE THE SWITCH, SO THEY CARRY NO UNDERLINE. A filled
               pill is its own state, and this is the one card in the deck with
               no tap hint anywhere: every figure on it is printed, nothing
               flips. */
            SunnyChipWrap(items: ["All"] + order.map(\.t), selected: sel ?? "All") { tapped in
                sel = tapped == "All" ? nil : tapped
            }

            Spacer().frame(height: 20)
            /* ⚠ EVERY LINE TAKES ITS LINE BOX, the sheet's `line-height: 1`.
               Without it each 13 to 14pt row reserved ~17 and the card ran 24
               over the measured 520.8. */
            Text("NET")
                .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute).sunnyLineBox(S.t10)
            Spacer().frame(height: 11)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(optMoney(r.net))
                    .font(S.inter(S.t22, S.wBoldN)).tracking(S.track(S.t22, -0.03))
                    .foregroundStyle(r.net < 0 ? S.lossText : S.gainText)
                    .sunnyLineBox(S.t22)
                Text("\(r.net < 0 ? "down" : "up") \(String(format: "%.1f", abs(r.pct)))%")
                    .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
            }
            Spacer().frame(height: 8)
            Text("on \(optMoney(r.inv)) invested")
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute).sunnyLineBox(S.t12)
            Spacer().frame(height: 6)
            /* The rate the two sides run at while nothing is traded: the shorts
               collect decay, the longs pay it. */
            Text("theta \(theta < 0 ? "\u{2212}" : "+")\(optMoney(abs(theta))) a day")
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute).sunnyLineBox(S.t12)

            Spacer().frame(height: 20)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 18)

            Text("WHAT IT IS MADE OF")
                .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute).sunnyLineBox(S.t10)
            Spacer().frame(height: 14)
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
                    .frame(height: S.t14)
                }
                coveredRow
            }

            Spacer().frame(height: 16)
            makeUpBar(r)
            Spacer().frame(height: 10)
            /* Line-height 1.4, measured: two lines are 30.8, so the gap between
               them is what is left of 15.4 after the font's own line. */
            Text("Credits are banked. The two marks move every day and are not yours until you close.")
                .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                .lineSpacing(max(0, S.t11 * 1.4 - (S.interUI(S.t11, S.wMidSmN)?.lineHeight ?? 13.3)))
                .fixedSize(horizontal: false, vertical: true)

            /* ⚠ ONE RULE, NOT TWO. `OptFooter` draws its own, and this card was
               drawing a second one 18pt above it. Every other card in the deck
               lets the footer carry the line. */
            Spacer(minLength: 20)
            OptFooter(stats: [
                .init(label: "Banked", value: optMoney(r.banked), ink: S.ink),
                /* ⚠ "Open", NOT "Owed", 17 Sep 2026: what the open legs took
                   in, the figure Coverage caps its bar with. The old slot said
                   what closing them would cost, a fact about legs no card on
                   this page counts any more.
                   ⚠ "Owed on open" TRUNCATED TO "OWED ON OP…" at 10/700 in a
                   third of 323. Banked · Owed · At mark reads as one set. */
                .init(label: "Open", value: optMoney(r.open), ink: S.ink),
                .init(label: "At mark", value: optMoney(r.mark), ink: S.ink),
            ])
        }
    }

    /* ⚠ THE FOURTH ROW: COVER, WHICH IS PROGRESS AND NEVER LOSS. `export 20`.
       All prints the book's collected OF its time value in dollars, because a
       book ratio hides the names still behind. A name prints its share with
       the clock as a note. `--ink` until time value is earned back,
       `--gain-text` after, and never red: a name that has not caught up yet
       has not lost anything. The denominator is time value, never what was
       paid; intrinsic is real money and does not need covering. */
    @ViewBuilder private var coveredRow: some View {
        let c = coverReading
        HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
            Text(c.label).font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(c.note).font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                Text(c.value)
                    .font(S.inter(S.t14, S.wBoldN)).tracking(S.track(S.t14, -0.02))
                    .foregroundStyle(c.ink)
            }
            .lineLimit(1).fixedSize()
        }
        .frame(height: S.t14)
    }

    private var coverReading: (label: String, note: String, value: String, ink: Color) {
        if sel == nil {
            let time = cover.reduce(0) { $0 + $1.time }
            let got = cover.reduce(0) { $0 + $1.collected }
            return ("Collected", "of \(optMoney(time)) time value", optMoney(got),
                    time > 0 && got >= time ? S.gainText : S.ink)
        }
        guard let n = cover.first(where: { $0.t == sel }), n.time > 0,
              let ratio = n.ratio else {
            return ("Covered", "no long call to cover", "\u{2013}", S.mute)
        }
        let pct = "\(Int((ratio * 100).rounded()))%"
        if ratio >= 1 { return ("Covered", "time value earned back", pct, S.gainText) }
        let note = n.days.map { "\(max(1, Int((Double($0) / 7).rounded()))) wk to go" } ?? "no pace yet"
        return ("Covered", note, pct, S.ink)
    }

    /* ⚠ THE GREEN IS CUT BY NAME, AND THE CUTS ARE A SECOND PICKER. In the All
       view every name that has kept something is its own segment, proportional
       to what it kept, so the bar says which names the banked money came from
       as well as how much of the net is banked at all. Tapping a cut selects
       that name; tapping the single cut in a one-name view goes back to All.

       ⚠ AND IT USES TEXT INKS, NOT BAR INKS. At 8pt tall `--gain-bar` reads
       lighter than the figures above it and the bar stopped looking like the
       same quantity. */
    @ViewBuilder private func makeUpBar(_ r: PgRow) -> some View {
        let span = CGFloat(max(abs(r.kept) + abs(r.mark), 1))
        let cuts: [PgRow] = sel == nil
            ? order.filter { $0.kept > 0 }
            : [r]
        GeometryReader { g in
            let keptW = g.size.width * CGFloat(abs(r.kept)) / span
            HStack(spacing: 0) {
                HStack(spacing: 2) {
                    ForEach(cuts) { c in
                        Rectangle().fill(S.gainText)
                            .frame(width: max(0, keptW * CGFloat(c.kept)
                                              / CGFloat(max(1, cuts.reduce(0) { $0 + $1.kept }))))
                            .contentShape(Rectangle())
                            .onTapGesture { sel = (sel == nil) ? c.t : nil }
                    }
                }
                .frame(width: keptW, alignment: .leading)
                Rectangle().fill(r.mark >= 0 ? S.gainText : S.lossText)
                    .frame(width: g.size.width * CGFloat(abs(r.mark)) / span)
                    .animation(.easeInOut(duration: 0.3), value: r.mark >= 0)
                Rectangle().fill(S.wash)
            }
            .animation(reduceMotion ? nil : S.easeSettle(0.55), value: keptW)
        }
        .frame(height: 8).clipShape(RoundedRectangle(cornerRadius: 4))
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
                        /* 23 tall, the sheet's: 5 + 11 at line-height 1 + 5 + the
                           1px border each side. At the font's own line it was 23.3,
                           and two rows put the card 0.6 over. */
                        Text(i)
                            .font(S.inter(S.t11, S.wSemiN))
                            .foregroundStyle(on ? S.pillInk : S.mute)
                            .frame(height: S.t11 + 2)
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

// MARK: - intrinsic value

/* ⚠ THIS REPLACES THE SPLIT-BAR INTRINSIC VALUE CARD OF THE SAME MORNING,
   14 Sep 2026, from the `intrinsic-bars` handoff. The old one laid the three
   shares along one horizontal bar and repeated them per leg; a reader could not
   tell the whole from a share. Standing them beside a Paid bar makes the sum
   visible, and the per-leg blocks are gone — the puts are 1% of paid and two
   more bars of the same three colours doubled the ink for a rounding error.

   ⚠ PAID IS A BAR, AND THE OTHER THREE ARE CUT FROM IT. Intrinsic + time +
   lost = paid to the dollar, and the three heights sum to the first.

   ⚠ TWO CLOCKS, AND THAT IS ALL THE PROSE. Over Paid and Intrinsic: how long
   the book's own net theta takes to earn back everything spent on the long
   legs, and the date. Over Time: when the time value is gone, which is the
   EARLIEST long call expiry — a floor for the whole share, not an average.
   Nothing over Lost, because nothing brings it back.

   ⚠ AND THE PLOT'S WHOLE IS max(paid, mark), the same amendment the split bar
   needed and for the same reason: the sheet fixes Paid at full height and cuts
   the rest from it, which only holds while the long side is DOWN. Up, intrinsic
   and time already exceed paid and the two bars would draw off the top of the
   plot. Down — as it is today — paid is the larger and nothing changes. */
struct SunnyIntrinsic: View {
    let block: IntrinsicBlock
    /// Prices' spot per name and the close it is measured from.
    let prices: [PriceRow]
    let asOf: String
    /// The book's weekly credit. Every clock on the card is a bar divided by
    /// the average week.
    let book: OptionsBook

    private enum Money: String { case inM, atM, outM }
    /* ⚠ VERIFICATION ONLY, the same device as `-rollFig`: the touch bridge
       crashes, so `-ivFilter at` and `-ivDays` force the states. */
    @State private var filter: Money? = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-ivFilter"), i + 1 < a.count else { return nil }
        switch a[i + 1] {
        case "in": return .inM
        case "at": return .atM
        case "out": return .outM
        default: return nil
        }
    }()
    @State private var days = ProcessInfo.processInfo.arguments.contains("-ivDays")
    @State private var now = Date()
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// ±2% of the strike is AT it, and `--warn` means that and nothing else.
    private static let atBand = 0.02
    private static let plotH: CGFloat = 132

    // MARK: the four figures

    private var sums: (paid: Int, mark: Int, intr: Int, time: Int, pnl: Int, whole: Int) {
        let mark = block.legs.reduce(0) { $0 + $1.mark }
        let paid = block.legs.reduce(0) { $0 + $1.paid }
        let intr = block.legs.reduce(0) { $0 + $1.intr }
        return (paid, mark, intr, mark - intr, mark - paid, max(paid, mark))
    }
    private func frac(_ n: Int, _ whole: Int) -> Double {
        whole > 0 ? min(1, max(0, Double(n) / Double(whole))) : 0
    }
    private func pct(_ n: Int, _ whole: Int) -> String {
        "\(whole > 0 ? Int((Double(n) / Double(whole) * 100).rounded()) : 0)%"
    }

    // MARK: the four clocks

    /* ⚠ EVERY CLOCK IS THE SAME QUESTION AT THE SAME RATE: how many weeks of
       the book's own income it takes to cover THAT bar. Nik, 14 Sep 2026: "we
       can't say overall it's going to take 40 weeks but the time value will
       take 71 weeks, that just doesn't make any sense."

       He was right, and the sheet's design was the cause. It put an EARN-BACK
       clock over Paid and Intrinsic and an EXPIRY DATE over Time — two
       different units in the same slot, on the same card, in the same type. A
       reader compares them because they look identical, and they cannot be
       compared at all.

       One rate everywhere, and the weeks then inherit the bars' own arithmetic:
       intrinsic + time + lost = paid in dollars, so 14 + 24 + 2 = 40 in weeks.
       Paid is DERIVED from the three rather than divided separately, so the
       identity holds at every future state rather than merely today.

       ⚠ THE RATE IS THE AVERAGE WEEK'S CREDIT, NOT THETA AND NOT LAST WEEK.
       Nik, 14 Sep 2026: "use the weekly credit pace instead of theta, but avg
       credit not the last weeks credit." It measures $5,417 — he guessed
       $5,000 — against theta's $6,433, so the book reads 48 weeks rather than
       40. Theta is what the book would collect if nothing moved; this is what
       he has actually been paid, and paying a LEAP back is done with money
       collected rather than money modelled.

       ⚠ AVERAGED OVER THE WEEKS THAT RAN, NEVER THE CALENDAR — the divisor Nik
       ruled on for the weekly yield, and the same `kept` figure that card
       averages (gross less what buying legs back cost), so the two cards cannot
       disagree about what an average week is. A week with no trade at all is
       not a week that earned nothing; it is a week the programme had not
       started.

       ⚠ AND COMPLETED WEEKS ONLY. Nik, 14 Sep 2026. The live week is a
       fraction of itself until Friday, so counting it made the average light on
       a Monday and full by the close, and the clock drifted a week across every
       week. Dropping it costs one week of staleness and buys a figure that only
       moves when a week actually ends — the right trade for a projection.

       ⚠ THIS NOW DIFFERS FROM WEEKLY YIELD BY ONE WEEK, and deliberately: that
       card's average line is a reading OF the weeks it draws, so the live bar
       belongs in it. This is a RATE projected forward, where a half-finished
       week is not a rate. Flagged to Nik with the change.

       ⚠ NEVER A NEGATIVE WEEK, AND NEVER ONE BUILT ON NOTHING. Before the first
       week closes there is no average to project, so the clocks leave rather
       than quoting a partial week as if it were a rate. */
    private var rateWeek: Double? {
        /* ⚠ FINISHED MEANS BEFORE THIS WEEK, not "not current": the window
           reaches forward, and next week's ghost gains a credit the moment a
           call is sold for it. That week has not run. */
        let now = book.weekly.first { $0.current == true }?.week ?? "9999"
        let done = book.weekly.filter {
            $0.week < now && (($0.gross ?? $0.credit) > 0 || ($0.bought ?? 0) > 0)
        }
        guard !done.isEmpty else { return nil }
        let mean = Double(done.reduce(0) { $0 + $1.credit }) / Double(done.count)
        return mean > 0 ? mean : nil
    }
    private struct Clock { let wk: String; let when: String }
    private var clocks: (paid: Clock, intr: Clock, time: Clock, pnl: Clock)? {
        guard let r = rateWeek, r > 0 else { return nil }
        let s = sums
        let w: (Int) -> Int = { max(0, Int((Double(abs($0)) / r).rounded())) }
        let wi = w(s.intr), wt = w(s.time), wl = w(s.pnl)
        /* Down, paid is the three added; up, the gain is already inside mark and
           comes back off. Either way the printed weeks match the printed
           dollars, which is the whole point of one rate. */
        let wp = max(0, s.pnl < 0 ? wi + wt + wl : wi + wt - wl)
        /* ⚠ LOST IS THE ONE CLOCK THAT LOOKS BACKWARDS, so it carries no date.
           Nik, 14 Sep 2026: "reframe this, cost 3 weeks of income, no need for
           dates." The other three are a projection — this much income and the
           bar is covered on that date. The loss is already spent: dating it
           would say the market takes it again in October. Same unit, opposite
           direction, and the sub-line is what says so. */
        return (clock(wp), clock(wi), clock(wt),
                Clock(wk: "\(wl) wk", when: "of income"))
    }
    private func clock(_ weeks: Int) -> Clock {
        Clock(wk: "\(weeks) wk", when: dayPlus(Double(weeks) * 7))
    }

    private var etCal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return c
    }
    private func daysTo(_ iso: String) -> Int {
        let f = DateFormatter(); f.calendar = etCal; f.timeZone = etCal.timeZone
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return 0 }
        return max(0, etCal.dateComponents([.day], from: etCal.startOfDay(for: now),
                                           to: etCal.startOfDay(for: d)).day ?? 0)
    }
    private func dayPlus(_ n: Double) -> String {
        let d = etCal.date(byAdding: .day, value: Int(n.rounded()),
                           to: etCal.startOfDay(for: now)) ?? now
        let f = DateFormatter(); f.calendar = etCal; f.timeZone = etCal.timeZone
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }

    // MARK: the pills

    private func spot(_ t: String) -> Double? {
        guard let v = prices.first(where: { $0.ticker == t })?.spot, v > 0 else { return nil }
        return v
    }
    /* Signed in the holder's favour: a long call above its strike reads +. */
    private func money(_ s: Double, _ k: Double) -> (state: Money, dist: Double) {
        guard k > 0 else { return (.outM, 0) }
        let d = (s - k) / k
        return (abs(d) <= Self.atBand ? .atM : d > 0 ? .inM : .outM, d)
    }
    private func dot(_ m: Money) -> Color {
        switch m { case .inM: return S.gainBar; case .atM: return S.warn; case .outM: return S.lossBar }
    }
    private struct Pill: Identifiable {
        let id: String, t: String, state: Money, text: String
    }
    /// In → at → out, alphabetical inside. The long CALLS only: the puts are
    /// the roll check's job and 1% of paid.
    private var pills: [Pill] {
        let rank: (Money) -> Int = { m in
            switch m { case .inM: return 0; case .atM: return 1; case .outM: return 2 }
        }
        return block.rows.compactMap { r -> Pill? in
            guard let c = r.call, let s = spot(r.t) else { return nil }
            let m = money(s, c.k)
            return Pill(id: r.t, t: r.t, state: m.state,
                        text: days ? "\(daysTo(c.exp))d" : signedPct0(m.dist * 100))
        }
        .sorted { rank($0.state) == rank($1.state) ? $0.t < $1.t : rank($0.state) < rank($1.state) }
    }

    // MARK: body

    var body: some View {
        let s = sums
        OptCard(name: "intrinsic") {
            OptHead(title: "Intrinsic value", sub: "the long legs", right: ivDay(asOf))
            Spacer().frame(height: 20)

            HStack(alignment: .top, spacing: 12) {
                let k = clocks
                column("PAID", optMoney(s.paid), S.ink, "100%",
                       frac(s.paid, s.whole), .solid(S.ink), k?.paid, 0)
                column("INTRINSIC", optMoney(s.intr), S.gainText, pct(s.intr, s.whole),
                       frac(s.intr, s.whole), .solid(S.gainBar), k?.intr, 1)
                column("TIME", optMoney(s.time), S.ink, pct(s.time, s.whole),
                       frac(s.time, s.whole), .hatch, k?.time, 2)
                /* ⚠ AND LOST CARRIES ONE TOO, on Nik's instruction: the loss is
                   worth two weeks of income, and a bar with no clock beside
                   three that have one reads as the one the card cannot answer
                   for. */
                s.pnl < 0
                    ? column("LOST", optMoney(s.pnl), S.lossText, pct(-s.pnl, s.whole),
                             frac(-s.pnl, s.whole), .solid(S.lossBar), k?.pnl, 3)
                    : column("GAINED", "+" + optMoney(s.pnl), S.gainText, pct(s.pnl, s.whole),
                             frac(s.pnl, s.whole), .solid(S.gainBar), k?.pnl, 3)
            }

            Spacer(minLength: 8)
            Spacer().frame(height: 22)
            Rectangle().fill(S.ruleColor).frame(height: 1)
            Spacer().frame(height: 18)
            filterRow
            Spacer().frame(height: 14)
            pillRow
        }
        .task(id: asOf) {
            now = Date()
            guard !grown else { return }
            try? await Task.sleep(for: .milliseconds(20))
            grown = true
        }
    }

    private enum Fill { case solid(Color), hatch }

    /* ⚠ THE EYEBROWS CARRY NO SWATCH: the bar directly above each one is the
       swatch. And the share sits ABOVE the column while the dollars sit below,
       the same reading as Call cover — fraction on top, money underneath. */
    @ViewBuilder
    private func column(_ label: String, _ fig: String, _ ink: Color, _ share: String,
                        _ f: Double, _ fill: Fill,
                        _ clock: Clock?, _ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(share).font(S.inter(S.t12, S.wSemiN)).foregroundStyle(S.ink2)
                .frame(maxWidth: .infinity, alignment: .center).lineLimit(1)
            Spacer().frame(height: 6)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            /* 52 is what makes room for the two-line clock above a full-height
               bar; at anything less the clock sits on the share rule. */
            Spacer().frame(height: 52)
            ZStack(alignment: .bottom) {
                Color.clear.frame(height: Self.plotH)
                bar(fill)
                    /* A 0% share still prints a sliver, so the column reads as
                       measured-and-tiny rather than absent. */
                    .frame(height: max(3, Self.plotH * f))
                    .scaleEffect(y: grown || reduceMotion ? 1 : 0, anchor: .bottom)
                    .animation(reduceMotion ? nil
                               : S.easeSettle(S.durBar).delay(Double(i) * 0.07), value: grown)
                if let clock {
                    /* The clock rides its bar's top and travels with it. It may
                       overhang the column, which is how "24 May 2027" fits in
                       71.75pt. */
                    VStack(spacing: 2) {
                        Text(clock.wk).font(S.inter(S.t12, S.wBoldN))
                            .tracking(S.track(S.t12, -0.01)).foregroundStyle(S.ink)
                        Text(clock.when).font(S.inter(S.t10, S.wMidSmN))
                            .foregroundStyle(S.mute)
                    }
                    .fixedSize()
                    .offset(y: -(max(3, Self.plotH * f) + 7))
                    .animation(reduceMotion ? nil : S.easeSettle(0.55), value: f)
                }
            }
            .frame(height: Self.plotH)
            Spacer().frame(height: 14)
            Text(label).font(S.inter(S.t10, S.wBoldN))
                .tracking(S.track(S.t10, S.lsLabel)).foregroundStyle(S.mute)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer().frame(height: 8)
            Text(fig).font(S.inter(S.t15, S.wBoldN)).tracking(S.track(S.t15, -0.02))
                .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func bar(_ f: Fill) -> some View {
        switch f {
        case .solid(let c):
            UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2).fill(c)
        case .hatch:
            /* ⚠ 2 OVER 3, NOT THE SPLIT BAR'S 1 OVER 2. At 132pt the fine hatch
               reads as flat grey and the time share stops looking like time. */
            SunnyHatch(ink: S.hair, stripe: 2, gap: 3)
                .background(S.wash)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2))
        }
    }

    private var filterRow: some View {
        HStack(spacing: 6) {
            pill(nil, "All"); pill(.inM, "In"); pill(.atM, "At"); pill(.outM, "Out")
            Spacer(minLength: 0)
            Text(days ? "show % from strike" : "show days left")
                .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                .lineLimit(1).fixedSize()
                .sunnyHint()
                .padding(.vertical, 10).contentShape(Rectangle())
                .onTapGesture { days.toggle() }
                .padding(.vertical, -10)
        }
    }
    @ViewBuilder private func pill(_ m: Money?, _ label: String) -> some View {
        let on = filter == m
        HStack(spacing: 6) {
            if let m { Circle().fill(dot(m)).frame(width: 7, height: 7) }
            Text(label).font(S.inter(S.t11, S.wSemiN))
                .foregroundStyle(on ? S.pillInk : S.mute)
        }
        .padding(.vertical, 5).padding(.horizontal, 10)
        .background(Capsule().fill(on ? S.ink : S.paper)
            .overlay(Capsule().stroke(on ? S.ink : S.ruleColorStrong, lineWidth: 1)))
        .contentShape(Capsule())
        .onTapGesture { filter = m }
    }

    /* ⚠ A FILTER DIMS, IT NEVER HIDES. The row keeps its shape, so the reader
       sees how many names are NOT that state. */
    private var pillRow: some View {
        SunnyWrap(spacing: 8, lineSpacing: 8) {
            ForEach(pills) { p in
                HStack(spacing: 7) {
                    Circle().fill(dot(p.state)).frame(width: 8, height: 8)
                    Text(p.t).font(S.inter(S.t12, S.wSemiN)).foregroundStyle(S.ink)
                    Text(p.text).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
                }
                .padding(.vertical, 7).padding(.horizontal, 11)
                .background(Capsule().stroke(S.ruleColorStrong, lineWidth: 1))
                .opacity(filter != nil && filter != p.state ? 0.25 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.55), value: filter)
            }
        }
    }
}

/// "+23%" / "−8%" — a distance that rounds to zero carries no sign.
private func signedPct0(_ v: Double) -> String {
    let a = Int(abs(v).rounded())
    return (a == 0 ? "" : v < 0 ? "\u{2212}" : "+") + "\(a)%"
}
/// "Fri 11 Sep" from the server's ISO close date. Every date on a card is
/// derived or it is wrong.
/// "Mon 14 Sep". The deck's one date form, on every card header and on
/// the Options page title.
func ivDay(_ iso: String) -> String {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
    guard let d = f.date(from: iso) else { return iso }
    let o = DateFormatter(); o.dateFormat = "EEE d MMM"
    return o.string(from: d)
}

/// A wrapping row. SwiftUI has no flex-wrap, and the pill count is the card's
/// height, so the rows have to be laid out rather than guessed at.
struct SunnyWrap: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    private func rows(_ sub: Subviews, _ w: CGFloat) -> [[Int]] {
        var out: [[Int]] = [[]], x: CGFloat = 0
        for (i, v) in sub.enumerated() {
            let s = v.sizeThatFits(.unspecified).width
            if !out[out.count - 1].isEmpty && x + spacing + s > w {
                out.append([i]); x = s
            } else {
                if !out[out.count - 1].isEmpty { x += spacing }
                out[out.count - 1].append(i); x += s
            }
        }
        return out
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let w = proposal.width ?? 0
        let rs = rows(subviews, w)
        let h = rs.reduce(0.0) { acc, r in
            acc + (r.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0)
        } + lineSpacing * CGFloat(max(0, rs.count - 1))
        return CGSize(width: w, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for r in rows(subviews, bounds.width) {
            var x = bounds.minX
            let rh = r.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
            for i in r {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (rh - s.height) / 2),
                                  proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += rh + lineSpacing
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
    /// Prices' last close, so every date on the card is derived.
    let asOf: String

    private static let richAt = 1.15

    /* ⚠ THE FIGURE COLUMN FLIPS, NOT A ROW. Prices' rule. Card-local and it
       survives the pull. `-pnPay` forces it: the touch bridge crashes. */
    @State private var pay = ProcessInfo.processInfo.arguments.contains("-pnPay")

    private var best: PremiumRow? { block.rows.first }

    /* The names paying most and least against their OWN usual, in dollars a
       contract. Both are the same subtraction, so neither can be the other's
       opposite by accident. Rows with no priced contract sit out. */
    private var extremes: (most: PremiumRow?, least: PremiumRow?) {
        let priced = block.rows.filter { $0.pay != nil && $0.payU != nil }
        guard !priced.isEmpty else { return (nil, nil) }
        let d: (PremiumRow) -> Int = { ($0.pay ?? 0) - ($0.payU ?? 0) }
        return (priced.max { d($0) < d($1) }, priced.min { d($0) < d($1) })
    }
    private func payStat(_ label: String, _ r: PremiumRow?, _ ink: Color) -> OptFooter.Stat {
        guard let r, let p = r.pay, let u = r.payU else {
            return .init(label: label, value: "\u{2014}", ink: S.mute)
        }
        let d = p - u
        return .init(label: label, value: (d < 0 ? "\u{2212}" : "+") + optMoney(abs(d)),
                     ink: d == 0 ? S.ink : ink, suffix: r.t)
    }
    /* "falling · 55 free" — Prices' direction then Left to sell's room. Under
       half a percent either way is flat: a book does not move by 0.2%. */
    private func subRight(_ r: PremiumRow) -> String {
        let mv = r.move ?? 0
        let dir = abs(mv) < 0.5 ? "flat" : mv > 0 ? "rising" : "falling"
        let f = r.free ?? 0
        return "\(dir) \u{00B7} " + (f > 0 ? "\(f) free" : "fully written")
    }

    private var window: String {
        let m = Int((Double(block.days) / 21.0).rounded())
        return m >= 12 ? "past year" : "past \(max(m, 1)) month\(m == 1 ? "" : "s")"
    }

    var body: some View {
        OptCard(name: "premium-now") {
            OptHead(title: "Premium now", sub: "vs its own usual",
                    right: ivDay(asOf))
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
                            /* The bar carries the state; the figure never
                               repeats it. Tapping any figure flips EVERY one:
                               per-row state would make five rows five cards. */
                            Text(pay && r.pay != nil
                                 ? optMoney(r.pay!)
                                 : String(format: "%.2f\u{00D7}", r.mult))
                                .font(S.inter(S.t15, S.wBoldN)).tracking(S.track(S.t15, -0.02))
                                .monospacedDigit().foregroundStyle(S.ink)
                                .lineLimit(1).fixedSize()
                                .sunnyHint(on: r.pay != nil)
                                .frame(width: 46, alignment: .trailing)
                                .contentShape(Rectangle())
                                .onTapGesture { if r.pay != nil { pay.toggle() } }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(pay && r.pay != nil && r.payU != nil
                                 ? "\(optMoney(r.pay!)) today \u{00B7} \(optMoney(r.payU!)) usual"
                                 : String(format: "%.1f%% today \u{00B7} %.1f%% usual", r.now, r.usual))
                                .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute2)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            /* ⚠ RICH WITH NO ROOM IS NOISE. The green lights
                               only when the name is rich AND has contracts left
                               to write: IV you cannot sell into is a fact about
                               the market, not an action. And rich-and-falling
                               is fear while rich-and-rising is chase — the same
                               multiple, a different trade — so Prices' week
                               move sits in front of the count. */
                            Text(subRight(r))
                                .font(S.inter(S.t11, S.wMidSmN))
                                .foregroundStyle((r.free ?? 0) > 0 && r.mult >= Self.richAt
                                                 ? S.gainText : S.mute2)
                                .lineLimit(1).fixedSize()
                        }
                        .padding(.leading, 56)
                    }
                }
            }

            Spacer(minLength: 26)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 22)
            /* ⚠ THE FOOTER ANSWERS THE CARD'S OWN QUESTION NOW. It read
               `Rich 1 · Book IV 41.9% · Readable 5`: the hero restated, a mean
               of five IVs with no reference — on a card whose whole premise is
               that an IV means nothing without the name's own usual — and a
               count of its own rows. It now says whether anyone is paying more
               than usual, who, and by how much, in dollars a contract, which is
               the unit the figure tap already speaks. */
            OptFooter(stats: [
                .init(label: "Above usual",
                      value: "\(block.rows.filter { $0.mult > 1 }.count) of \(block.rows.count)",
                      ink: S.ink),
                payStat("Paying most", extremes.most, S.gainText),
                payStat("Paying least", extremes.least, S.lossText),
            ])
        }
    }
}

/// "Wed 10 Sep" — the deck's own header date.
func fmtDayLabel(_ d: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f.string(from: d)
}
