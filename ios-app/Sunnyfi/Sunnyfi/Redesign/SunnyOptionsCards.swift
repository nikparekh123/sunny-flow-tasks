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

// MARK: - 1 · Roll check

/* ⚠ THIS REPLACES THE PREVIOUS ROLL CHECK, 13 Sep 2026, from the `roll-check-card`
   handoff (cards/roll-check.md, Sunny Roll Check Card.dc.html). The old card is
   deleted, not kept beside it, and the Inventory figures it had absorbed on 11 Sep
   come back as a view of their own rather than a line under each percentage.

   ⚠ ONE CARD, TWO QUESTIONS, THE SAME NAMES. Captured asks what the sold premium
   has captured, strike by strike. Left to sell asks what is still writeable, name
   by name. The switch is the end of the eyebrow line and is the only thing on it
   you can tap: no tab band, because a tab band says the two are peers being chosen
   between, and they are one question asked at two moments of the week.

   ⚠ A STRIKE IS THE UNIT OF A ROLL, never a per-name average. NFLX's two strikes
   are two decisions and averaging them would describe neither. Groups sort by
   their worst leg and legs sort worst-first inside, so the rows needing a decision
   are the rows at the top.

   ⚠ THE OTHER CARDS SUPPLY THE WHY, and this card owns none of it. Prices says the
   stock moved THROUGH the strike, which turns the strike red, and how far it ran
   this week, which is the group's meta line. Average credit says what the leg
   opened at. Premium now says what the IV is doing.

   ⚠ AND THE FOOTER MUST NOT MOVE WHEN THE VIEW DOES. Both views carry a floor so
   the stat band stays under the same thumb; the height between them is animated
   rather than cut. */
struct SunnyRollCheck: View {
    let book: OptionsBook
    let positions: [OptionsPosition]
    /// Inventory — calls and puts still writeable, per name.
    var inventory: [InventoryRow] = []
    /// Prices — spot, the day's move and the week's, plus the IV band.
    var prices: [PriceRow] = []

    private enum View2 { case captured, left }
    /* ⚠ THREE STATES, NOT THE SHEET'S TWO. Nik, 2026-09-13: "we need a third one
       which is remaining". The percentage says how much of the credit is banked,
       the captured dollars say what that is worth, and REMAINING is what closing
       the leg would cost today. They are the same fact stated three ways and
       none is derivable from the row alone, which is what earns the third stop
       rather than making it a third way of saying one thing. */
    private enum Fig { case pct, captured, timeValue }
    @State private var view: View2 = .captured
    /* ⚠ VERIFICATION ONLY, the same device as `-showMoney`: the simulator's
       touch bridge crashes, so `-rollFig tv` forces the stop and proves the
       RENDERING. It does not test the tap, which cannot be driven here. */
    @State private var fig: Fig = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-rollFig"), i + 1 < a.count else { return .pct }
        switch a[i + 1] {
        case "tv": return .timeValue
        case "captured": return .captured
        default: return .pct
        }
    }()
    @State private var ivMult = false        // Left to sell: the word or the multiple
    @State private var yieldUsd = false      // Left to sell: yield % or dollars
    @State private var appeared = false
    @State private var now = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /* ⚠ THE AXIS RUNS −125 TO +100 AND THE ZERO IS NOT ITS MIDDLE. A leg can give
       back more than the credit it took (−125 is the call having more than
       doubled) but it can never capture more than all of it, so the two ends are
       not symmetric and pretending they are would put +100 in the middle of a bar
       that has nothing beyond it. */
    private let axLo: Double = -125, axHi: Double = 100
    private var track: CGFloat { S.content - 48 - 46 - 10 - 10 - 56 }
    private func x(_ p: Double) -> CGFloat {
        CGFloat((min(max(p, axLo), axHi) - axLo) / (axHi - axLo)) * track
    }
    private var zeroX: CGFloat { x(0) }

    // MARK: the week's clock

    private var etCal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return c
    }
    /* ⚠ THE WEEK IS OVER ON FRIDAY NIGHT. "kept this week" is a live figure while
       the week is open; from Friday 20:00 ET to Monday 04:00 ET the week it refers
       to has CLOSED, so the words leave and the figure stands alone as the week's
       result. The same window the Prices card uses for its day chip, so the two
       cards go quiet together. */
    private var weekOpen: Bool {
        let wd = etCal.component(.weekday, from: now), h = etCal.component(.hour, from: now)
        if wd == 7 || wd == 1 { return false }
        if wd == 6 && h >= 20 { return false }
        if wd == 2 && h < 4 { return false }
        return true
    }

    // MARK: borrowed readings

    private func px(_ t: String) -> PriceRow? { prices.first { $0.ticker == t } }
    private func inv(_ t: String) -> InventoryRow? { inventory.first { $0.t == t } }
    private func freeCalls(_ t: String) -> Int { max(0, (inv(t)?.callsHeld ?? 0) - (inv(t)?.callsSold ?? 0)) }
    private func freePuts(_ t: String) -> Int { max(0, (inv(t)?.putsHeld ?? 0) - (inv(t)?.putsSold ?? 0)) }

    /// A sold strike the stock has moved THROUGH: a call below spot, a put above it.
    private func through(_ l: OptionsPosition.ShortLeg, _ spot: Double?) -> Bool {
        guard let spot, spot > 0 else { return false }
        return (l.type ?? "call") == "put" ? spot < l.k : spot > l.k
    }

    // MARK: the two views' rows

    /* Named for the legs, not "Group": a bare `Group` shadows SwiftUI's own and
       the view builder then tries to construct this one. */
    private struct LegGroup: Identifiable {
        let id: String, t: String, meta: String, worst: Int
        let legs: [OptionsPosition.ShortLeg]
        let spot: Double?
    }
    /* ⚠ A NAME WITH NOTHING SOLD IS STILL A ROW. Nik, 2026-09-13: "KR should
       still show even if never written", and the same instruction he gave the
       old card on 11 Sep. The sheet groups by sold leg and so drops a name that
       has none, which hides exactly the name there is most to do about: KR holds
       a LEAP and has never written a call against it.

       Those names sort FIRST, alphabetically, because they are the work that has
       not started, and a captured percentage cannot rank them — there is nothing
       captured. Worst-first resumes below them. */
    /* ⚠ ONE ROW PER NAME, AND `positions` IS ONE ROW PER LEAP LEG. BABA held
       two long calls at different strikes on 14 Sep 2026 and arrived here
       twice, each copy carrying the NAME's whole short list — a duplicate
       group id, every BABA leg drawn and counted twice, and the header's leg
       count three too high. It nets out today and will come back the next time
       a name is built in two tranches. */
    private var names: [OptionsPosition] {
        var seen = Set<String>()
        return positions.filter { seen.insert($0.t).inserted }
    }
    private var groups: [LegGroup] {
        names.map { p -> LegGroup in
            let legs = p.shorts.sorted { $0.captured < $1.captured }
            let row = px(p.t)
            let wk = row?.pct.w1
            let meta = [row?.spot.map { "$" + String(format: "%.2f", $0) },
                        wk.map { signed1Pct($0) + " wk" }]
                .compactMap { $0 }.joined(separator: " \u{00B7} ")
            return LegGroup(id: p.t, t: p.t, meta: meta,
                            /* Sorts above every real reading, including a leg
                               that has given back more than its credit. */
                            worst: legs.first?.captured ?? Int.min, legs: legs,
                            spot: row?.spot)
        }
        .sorted {
            if $0.legs.isEmpty != $1.legs.isEmpty { return $0.legs.isEmpty }
            if $0.legs.isEmpty { return $0.t < $1.t }
            return $0.worst < $1.worst
        }
    }
    private var allLegs: [OptionsPosition.ShortLeg] { names.flatMap(\.shorts) }
    /// Summed from the legs the card lists, never a stored total.
    private var bookTV: Int { allLegs.reduce(0) { $0 + ($1.tv ?? 0) } }
    private var underWater: Int { allLegs.filter { $0.captured < 0 }.count }
    private var totalFree: Int { names.reduce(0) { $0 + freeCalls($1.t) + freePuts($1.t) } }
    private var kept: Int { (book.openCredit ?? 0) - (book.openValue ?? 0) }

    private struct LeftRow: Identifiable {
        let id: String, t: String, split: String
        let has: Bool, cr: Double, yld: Double, mult: Double
        let word: String, rich: Bool, move: Double?
        let free: Int, rank: Double
    }
    private var lefts: [LeftRow] {
        positions.map { p -> LeftRow in
            let fc = freeCalls(p.t), fp = freePuts(p.t), n = fc + fp
            let row = px(p.t)
            let spot = row?.spot ?? 0, cr = p.lastCr ?? 0
            let yld = spot > 0 ? cr / spot * 100 : 0
            let m = row?.iv.map { $0.usual > 0 ? $0.now / $0.usual : 1 } ?? 1
            var parts: [String] = []
            if fc > 0 { parts.append("\(fc) call" + (fc == 1 ? "" : "s")) }
            if fp > 0 { parts.append("\(fp) put" + (fp == 1 ? "" : "s")) }
            return LeftRow(
                id: p.t, t: p.t,
                /* ⚠ "fully written" IS AN ABSENCE, NOT A QUANTITY. "0 calls ·
                   0 puts free" reads as two measurements that happen to be zero. */
                split: parts.isEmpty ? "fully written" : parts.joined(separator: " \u{00B7} ") + " free",
                has: n > 0, cr: cr, yld: yld, mult: m,
                word: row?.ivWord ?? "", rich: row?.ivRich ?? false,
                move: row?.pct.today, free: n,
                /* ⚠ THE RANKING IS ROOM × WHAT IT PAYS × HOW WELL IT PAYS TODAY.
                   Free contracts alone ranks a name you cannot get a price for
                   above one you can. */
                /* A name with no history ranks on room alone, below anything
                   that has actually paid, rather than at zero. */
                rank: cr > 0 ? Double(n) * yld * m : Double(n) * 0.0001)
        }
        .sorted { $0.rank > $1.rank }
    }

    // MARK: formatting

    private func signed1Pct(_ v: Double) -> String {
        let a = String(format: "%.1f", abs(v))
        return (a == "0.0" ? "" : v < 0 ? "\u{2212}" : "+") + a + "%"
    }
    private func pct0(_ v: Int) -> String { (v < 0 ? "\u{2212}" : "") + "\(abs(v))%" }
    /// The right column's three readings of one leg.
    private func figText(_ l: OptionsPosition.ShortLeg) -> String {
        switch fig {
        case .pct:       return pct0(l.captured)
        /* Credit minus what it is worth now: the money the strike has kept, or
           given back when the option has run against you. */
        case .captured:  return optMoney(l.credit - l.value)
        /* ⚠ WHAT IS STILL TO DECAY, NOT WHAT THE BUY-BACK COSTS. Nik, 14 Sep
           2026, replacing "left to capture" here. The buy-back cost was the
           whole mark; this is the part of it that is TIME and comes back by
           Friday if he does nothing. The rest is intrinsic — the stock having
           run through the strike — and no amount of waiting returns it.

           On an out-of-the-money leg the two are the same number, and that is
           the reading rather than a fault: the whole remaining cost is decay he
           collects. A GAP between them is the intrinsic he will not get back,
           which is the roll signal. */
        case .timeValue: return optMoney(l.tv ?? 0)
        }
    }
    private func settle(_ d: Double, delay: Double = 0) -> Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: d).delay(delay)
    }

    // MARK: body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
                HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                    Text("Roll check").font(S.inter(S.t14, S.wBoldN))
                        .tracking(S.track(S.t14, -0.01)).foregroundStyle(S.ink)
                    Text("sold").font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
                }
                Spacer(minLength: 0)
                /* Both counted, never stated: the header is the card's own census. */
                Text("\(underWater) asking of \(allLegs.count) legs")
                    .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
            }

            Spacer().frame(height: 22)

            Group {
                if view == .captured { capturedView } else { leftView }
            }
            /* ⚠ A FLOOR ON BOTH VIEWS, so the footer does not travel under the
               thumb when the question changes. */
            .frame(minHeight: 300, alignment: .top)
            .animation(reduceMotion ? nil : settle(0.5), value: view)

            /* OptFooter draws the rule itself; adding one here gave the card two
               hairlines 50pt apart, which reads as a band rather than an edge. */
            Spacer().frame(height: 26)
            /* ⚠ THE FOOTER IS THE ONE HE ALREADY HAD, which overrides the sheet's
               Rolling / Left to sell / Kept. Nik, 2026-09-13: "bottom i need the
               same data as before, Credit collected current value and yireld".
               The sheet's three restate the card: ROLLING is the header's own
               count, LEFT TO SELL is the other view's hero, and KEPT is this
               view's hero printed twice. These three are the week's money and
               they audit each other — collected minus worth now IS the hero. */
            OptFooter(stats: [
                .init(label: "Collected", value: optMoney(book.openCredit ?? 0), ink: S.gainText),
                .init(label: "Worth now", value: optMoney(book.openValue ?? 0), ink: S.ink),
                .init(label: "Yield", value: String(format: "%.1f%%", book.openYield ?? 0), ink: S.ink),
            ])
        }
        .frame(width: S.content - 48, alignment: .leading)
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 28, trailing: 24))
        .frame(width: S.content, alignment: .top)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCard)
        .monospacedDigit()
        .measure("roll-check")
        /* ⚠ THE ENTRANCE IS DRIVEN BY THE DATA ARRIVING, NOT BY THE VIEW
           APPEARING. Nik, 2026-09-13: "also animation is not there". It was
           there and it had already finished: `onAppear` fires on the empty card
           while the fetch is still in flight, so `appeared` was true before a
           single bar existed and every bar rendered at full width. The flag now
           flips one frame AFTER the first non-empty render, which is the only
           moment a grow-from-zero has anything to grow. */
        .task(id: allLegs.count) {
            now = Date()
            guard !allLegs.isEmpty, !appeared else { return }
            try? await Task.sleep(for: .milliseconds(20))
            appeared = true
        }
    }

    // MARK: eyebrow + switch, shared by both views

    @ViewBuilder private func eyebrow(_ label: String, _ go: String,
                                      _ action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: S.gap6) {
            Text(label).font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute)
            Spacer(minLength: 0)
            /* ⚠ THE SWITCH CARRIES NO UNDERLINE. Its arrow is the affordance, and
               the dotted hint is reserved for a figure that FLIPS in place. Two
               different promises need two different marks. */
            HStack(spacing: 5) {
                Text(go).font(S.inter(S.t12, S.wSemiN)).tracking(S.track(S.t12, -0.01))
                    .foregroundStyle(S.ink2)
                Text("\u{2192}").font(S.inter(S.t11, S.wSemiN)).foregroundStyle(S.mute)
            }
            .padding(.vertical, 10).padding(.horizontal, 7)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .padding(.vertical, -10).padding(.horizontal, -7)
        }
        .frame(height: 12)
    }

    // MARK: captured

    @ViewBuilder private var capturedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow(fig == .timeValue ? "TIME VALUE LEFT"
                    : fig == .captured ? "CAPTURED, IN MONEY" : "CAPTURED OF CREDIT",
                    "Left to sell") { view = .left }
            Spacer().frame(height: 12)
            /* ⚠ THE HERO FOLLOWS THE COLUMN, because the eyebrow already
               does. Nik, 14 Sep 2026: "add book level on top". On the time
               value stop the hero is the whole book's time value, summed from
               the same legs listed below it, so the card cannot disagree with
               itself. Every other stop keeps "kept this week". */
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(optMoney(fig == .timeValue ? bookTV : kept))
                    .font(S.inter(S.t30, S.wBoldN)).tracking(S.track(S.t30, -0.035))
                    .foregroundStyle(fig == .timeValue ? S.gainText
                                     : (kept < 0 ? S.lossText : S.gainText))
                    .sunnyLineBox(S.t30)
                if fig == .timeValue {
                    Text("still to decay")
                        .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
                } else if weekOpen {
                    Text("kept this week")
                        .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
                }
            }
            Spacer().frame(height: 28)

            /* The two levels are ANNOTATIONS on the money axis, never gates and
               never a money hue: +75 is three quarters of the credit banked,
               −100 is the option having doubled. */
            HStack(spacing: 10) {
                Color.clear.frame(width: 46, height: 11)
                ZStack(alignment: .leading) {
                    Text("\u{2212}100").font(S.inter(S.t10, S.wBoldN))
                        .tracking(S.track(S.t10, S.lsLabel)).foregroundStyle(S.mute)
                        .fixedSize().offset(x: x(-100) - 10)
                    Text("+75").font(S.inter(S.t10, S.wBoldN))
                        .tracking(S.track(S.t10, S.lsLabel)).foregroundStyle(S.mute)
                        .fixedSize().offset(x: x(75) - 8)
                }
                .frame(width: track, height: 11, alignment: .leading)
                Color.clear.frame(width: 56, height: 11)
            }
            Spacer().frame(height: 14)

            VStack(alignment: .leading, spacing: 26) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { gi, g in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                            Text(g.t).font(S.inter(S.t15, S.wSemiN))
                                .tracking(S.track(S.t15, -0.015)).foregroundStyle(S.ink)
                            Spacer(minLength: 0)
                            /* ⚠ THE CAUSE, NOT A REPEAT. The captured figures are
                               the symptom; where the stock is and how far it ran
                               is why they read as they do. */
                            Text(g.meta).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
                        }
                        .frame(height: 15)
                        Spacer().frame(height: 14)
                        if g.legs.isEmpty {
                            /* No bar and no figure: there is no credit to have
                               captured any of, and drawing an empty track at zero
                               would say the leg exists and has gone nowhere. */
                            Text("nothing sold")
                                .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
                                .frame(height: 26, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(Array(g.legs.enumerated()), id: \.element.id) { li, l in
                                    legRow(l, spot: g.spot, delay: Double(gi * 3 + li) * 0.018)
                                }
                            }
                        }
                    }
                }
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder private func legRow(_ l: OptionsPosition.ShortLeg, spot: Double?,
                                     delay: Double) -> some View {
        let up = l.captured >= 0
        let w = abs(x(Double(l.captured)) - zeroX)
        let grown = reduceMotion || appeared
        HStack(alignment: .center, spacing: 10) {
            /* ⚠ A STRIKE IN LOSS INK IS ONE THE STOCK HAS MOVED THROUGH, and
               that is a different statement from the bar's colour. Red strike
               with a red bar says roll it; red strike with a green bar says it
               ran through and you are still ahead.

               ⚠ THE CREDIT PER SHARE UNDER THE STRIKE IS GONE, 14 Sep 2026, on
               Nik's instruction: "lets remove that data point doesn't make much
               sense thinking about it now". It printed the price the leg was
               sold at, and only on an under-water leg, so six of eighteen rows
               carried it and twelve did not — which read as data missing rather
               than as a rule. `lastCr` still feeds the Left to sell view, where
               a name's own last print IS the ranking unit.

               The 26 stays. It held two lines and now holds one, and dropping
               it to fit the strike alone would re-space every row on the card
               for a line that was only ever on a third of them. */
            Text(l.label).font(S.inter(S.t13, S.wBodyN)).tracking(S.track(S.t13, -0.01))
                .foregroundStyle(through(l, spot) ? S.lossText : S.ink2)
                .lineLimit(1)
                .frame(width: 46, height: 26, alignment: .leading)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: S.radiusBar).fill(S.wash)
                    .frame(width: track, height: 14)
                ForEach([-100.0, 0.0, 75.0], id: \.self) { v in
                    Rectangle().fill(S.hair).frame(width: 1.5, height: 22)
                        .offset(x: x(v) - 0.75)
                }
                RoundedRectangle(cornerRadius: S.radiusBar)
                    .fill(up ? S.gainBar : S.lossBar)
                    .frame(width: max(2, w), height: 14)
                    .scaleEffect(x: grown ? 1 : 0, anchor: up ? .leading : .trailing)
                    .offset(x: up ? zeroX : zeroX - max(2, w))
                    .animation(settle(0.72, delay: delay), value: appeared)
                    .animation(reduceMotion ? nil : settle(0.55), value: view)
            }
            .frame(width: track, height: 14)

            /* ⚠ TIME VALUE TAKES NO DIRECTION INK. It is money still to come
               on every leg, so it is never a gain or a loss against the
               captured reading beside it, and colouring it would have the card
               arguing that a leg deep in the money is winning because its
               decay is large. */
            Text(figText(l))
                .font(S.inter(S.t13, S.wBoldN)).tracking(S.track(S.t13, -0.015))
                .foregroundStyle(fig == .timeValue ? S.ink : (up ? S.gainText : S.lossText))
                .lineLimit(1).fixedSize()
                .sunnyHint()
                .frame(width: 56, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture {
                    fig = fig == .pct ? .captured : fig == .captured ? .timeValue : .pct
                }
        }
        .frame(height: 26)
    }

    // MARK: left to sell

    @ViewBuilder private var leftView: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("LEFT TO SELL", "Captured") { view = .captured }
            Spacer().frame(height: 12)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(totalFree)")
                    .font(S.inter(S.t30, S.wBoldN)).tracking(S.track(S.t30, -0.035))
                    .foregroundStyle(S.ink).sunnyLineBox(S.t30)
                Text("lots still writeable")
                    .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
            }
            Spacer().frame(height: 24)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lefts.enumerated()), id: \.element.id) { i, r in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 14) {
                            Text(r.t).font(S.inter(S.t15, S.wSemiN))
                                .tracking(S.track(S.t15, -0.015))
                                .foregroundStyle(r.has ? S.ink : S.mute)
                                .frame(width: 58, alignment: .leading).lineLimit(1)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(r.split).font(S.inter(S.t15, S.wSemiN))
                                    .tracking(S.track(S.t15, -0.015))
                                    .foregroundStyle(r.has ? S.ink2 : S.mute)
                                    .frame(height: 15, alignment: .leading).lineLimit(1)
                                if r.has { smallFigures(r) } else { Color.clear.frame(height: 11) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            /* The tap on the right: the rate, and what filling the
                               room would actually pay. */
                            /* ⚠ A NAME THAT HAS NEVER BEEN WRITTEN HAS NO YIELD,
                               and printing 0.0% says it was measured and pays
                               nothing. KR holds a free call and has never sold
                               one, so there is no last credit to rate it on: the
                               dash is the same absence "fully written" is. */
                            Text(r.has && r.cr > 0
                                 ? (yieldUsd ? optMoney(Int((r.cr * 100 * Double(r.free)).rounded()))
                                             : String(format: "%.1f%%", r.yld))
                                 : "\u{2014}")
                                .font(S.inter(S.t15, S.wBoldN)).tracking(S.track(S.t15, -0.02))
                                .foregroundStyle(r.has && r.cr > 0 ? S.ink : S.mute)
                                .lineLimit(1).fixedSize()
                                .sunnyHint(on: r.has && r.cr > 0)
                                .frame(minWidth: 37.5, alignment: .trailing)
                                .contentShape(Rectangle())
                                .onTapGesture { if r.has && r.cr > 0 { yieldUsd.toggle() } }
                        }
                        .padding(.vertical, 17)
                        if i < lefts.count - 1 {
                            Rectangle().fill(S.ruleColor).frame(height: 1)
                        }
                    }
                    .opacity(reduceMotion || appeared ? 1 : 0)
                    .offset(y: reduceMotion || appeared ? 0 : 4)
                    .animation(settle(0.5, delay: Double(i) * 0.045), value: appeared)
                }
            }

            Spacer().frame(height: 14)
            Text(yieldUsd
                 ? "credit if every free contract were written at the last price \u{00B7} IV against its own history"
                 : "weekly yield on the share, last written \u{00B7} IV against its own history")
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
                .fixedSize(horizontal: false, vertical: true)
        }
        .transition(.opacity)
    }

    @ViewBuilder private func smallFigures(_ r: LeftRow) -> some View {
        HStack(spacing: 6) {
            /* Same rule as the yield beside it: no last credit is a fact about
               the name, not a price of zero. */
            Text(r.cr > 0 ? "$" + String(format: "%.2f", r.cr) : "not written yet")
                .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
            if !r.word.isEmpty {
                Text("\u{00B7}").font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                Text(ivMult ? String(format: "%.2f", r.mult) + "\u{00D7} IV" : r.word)
                    .font(S.inter(S.t11, S.wMidSmN))
                    .foregroundStyle(r.rich ? S.gainText : S.mute)
                    .sunnyHint()
                    .contentShape(Rectangle())
                    .onTapGesture { ivMult.toggle() }
            }
            if let m = r.move {
                Text("\u{00B7}").font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                Text(signed1Pct(m)).font(S.inter(S.t11, S.wMidSmN))
                    .foregroundStyle(m < 0 ? S.lossText : S.gainText)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 11)
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

// MARK: - 2c · The cover rings — Call cover, then Put cover

/* ⚠ THESE TWO REPLACE THE 2 SEP PUT COVER CARD AND ADD ITS TWIN, 14 Sep 2026,
   from the `cover-rings` handoff (cards/call-cover.md, cards/put-cover.md,
   cover-data.js). The old single put ring is deleted, not kept beside them.

   ⚠ THEY ARE TWINS AND MUST LOOK IT. Same disc, stroke, ticks, centre, lines,
   footer, height. A reader who has learned one has learned the other, so the
   geometry lives once in `CoverRingCard` and the two cards are the words that
   differ: title, scope, count, third stat, and which week the move word is
   allowed to shout on.

   ⚠ ONE CALL, ONE TICK. Both read the same `options-cards` payload, so the two
   rings can never be a minute apart or disagree about the book's week.

   ⚠ WHAT CHANGED FROM THE SHEET, AND WHY — both flagged to Nik:

   1. THE PUT PACE LINE KEEPS ITS DEADLINE. The sheet reverts to "full cover in
      N weeks"; Nik ruled that out on 2026-09-09 ("the suggestion cannot be post
      expiry") and the reason still stands — at today's figures that line would
      read 40 weeks against puts that expire in 27. The call ring takes the
      sheet's line unchanged, because its LEAPs run 70 weeks out and 38 weeks is
      inside them.

   2. THE PUT CARD STILL HAS NO SCOPE WORD. The sheet prints "all tickers"; four
      of seven names hold a put, so the whole book is not in it. The call ring's
      "all LEAPs" IS true of all seven, so that one ships.

   3. THE MOVE WORD IS THE EQUAL-WEIGHT MEAN, which is what the Prices card's
      hero prints — its rows are averaged flat on the phone and never read the
      server's cost-weighted `book`. The first build here shipped the weighted
      figure and put −2.2% under two rings sitting below a card reading −1.4%.
      Caught by rendering the page. */

/// The geometry both rings are. Nothing here knows whether it is calls or puts.
private struct CoverRingCard: View {
    let name: String
    let title: String, scope: String, count: String
    /// null before the first contract of that side is held: the card draws an
    /// ABSENCE, not a zero.
    let started: Bool
    let cost: Int, collected: Int, left: Int, pace: Int
    /// The centre's second state, and the only thing the tap changes.
    let weeks: Int?
    let paceLine: String
    /// Contracts still writeable on THIS side — the ticks outside the ring.
    let free: Int, freeWord: String
    /// The book's week, and whether this ring is the one it is good news for.
    let move: Double?, moveHot: Bool
    let costLabel: String, leftLabel: String
    let emptyFigure: String, emptyLabel: String, emptyLine: String

    /* Card-local, and it survives a pull: the tap answers HOW LONG, the arc
       answers HOW FAR, and a refresh must not reset the question he asked. */
    @State private var weeksMode = false
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var frac: Double { cost > 0 ? Double(collected) / Double(cost) : 0 }
    private var covered: Bool { started && left <= 0 }

    var body: some View {
        OptCard(name: name) {
            OptHead(title: title, sub: scope, right: count)
            Spacer().frame(height: 20)
            ring
            Spacer().frame(height: 14)
            Text(started
                 ? "\(optMoney(collected)) of \(optMoney(cost)) collected"
                 : emptyLine)
                .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
                .frame(maxWidth: .infinity, alignment: .center)
                .lineLimit(1)
            /* 11 then 6: the amount and the pace are two halves of one
               statement, the free/move line is the borrowed note under both. */
            Spacer().frame(height: S.gap5)
            Text(paceLine)
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
                .frame(maxWidth: .infinity, alignment: .center)
                .lineLimit(1).minimumScaleFactor(0.85)
            Spacer().frame(height: 6)
            borrowedLine
                .frame(maxWidth: .infinity, alignment: .center)
                .lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: S.gap7)
            /* ⚠ AN ABSENT VALUE IS A DASH, NEVER A ZERO. "$0" at 19/700 reads
               as a measured nothing, which is a different and false claim. */
            OptFooter(stats: started
                ? [
                    .init(label: costLabel, value: optMoney(cost), ink: S.ink),
                    .init(label: "Collected", value: optMoney(collected), ink: S.gainText),
                    covered
                        ? .init(label: "Over", value: "+" + optMoney(-left), ink: S.gainText)
                        : .init(label: leftLabel, value: optMoney(left), ink: S.ink),
                ]
                : [
                    .init(label: costLabel, value: "\u{2014}", ink: S.mute),
                    .init(label: "Collected", value: "\u{2014}", ink: S.mute),
                    .init(label: leftLabel, value: "\u{2014}", ink: S.mute),
                ])
        }
        /* ⚠ DRIVEN BY DATA ARRIVAL, NOT BY onAppear. The card mounts empty
           while the fetch is in flight, so an onAppear entrance grows an arc
           that has nothing to grow to and is over before the figures land. */
        .task(id: collected) {
            guard started, !grown else { return }
            try? await Task.sleep(for: .milliseconds(20))
            if reduceMotion { grown = true }
            else { withAnimation(S.easeSettle(0.9).delay(0.08)) { grown = true } }
        }
    }

    /* The book's week, with the move word in direction ink only on the week
       this particular ring is the good news. */
    private var borrowedLine: some View {
        let head = Text("\(free) \(freeWord) still writeable")
            .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
        guard let move else { return head }
        let word = Text("book \(signedPct1(move)) this week")
            .font(S.inter(S.t12, moveHot ? S.wSemiN : S.wMidSmN))
            .foregroundStyle(moveHot ? (move < 0 ? S.lossText : S.gainText) : S.mute)
        return head
            + Text(" \u{00B7} ").font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
            + word
    }

    private var ring: some View {
        ZStack {
            /* ⚠ strokeBorder, NOT stroke. A centred stroke on a 176 circle
               draws 194 wide and would put the 92pt ticks INSIDE the band.
               Inset by half the width and the disc is the 176 the sheet
               measured, outer edge 88, ticks 4 clear of it. */
            Circle().strokeBorder(S.coverTrack, lineWidth: S.coverStroke)
            /* ⚠ CLAMPED AT 1. Trim past 1 wraps and the arc eats its own tail,
               so 105% would draw as 5%. The centre figure carries the overage.
               And NO ARC AT ALL before the first contract: a 0.001 stub is a
               green pip at twelve claiming a start that has not happened. */
            if started {
                Circle()
                    .inset(by: S.coverStroke / 2)
                    .trim(from: 0, to: grown ? max(0.004, min(frac, 1)) : 0)
                    .stroke(S.gainBar,
                            style: StrokeStyle(lineWidth: S.coverStroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            ticks
            /* ⚠ A SIBLING OF THE ARC, NEVER ROTATED WITH IT. Inside the
               rotated element the figure sits on its side. */
            centre
        }
        .frame(width: S.coverRingD, height: S.coverRingD)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /* ⚠ CAPACITY, NOT COVER, SO --hair AND NEVER GREEN. A green tick would
       read as a second series on a card whose whole claim is one. */
    private var ticks: some View {
        ZStack {
            if free > 0 {
                ForEach(0..<free, id: \.self) { i in
                    Rectangle().fill(S.hair)
                        .frame(width: S.coverTickW, height: S.coverTickH)
                        .offset(y: -S.coverTickR)
                        .rotationEffect(.degrees(Double(i) / Double(free) * 360))
                        .opacity(grown ? 1 : 0)
                        .animation(reduceMotion ? nil
                                   : .easeOut(duration: 0.4).delay(0.3 + Double(i) * 0.04),
                                   value: grown)
                }
            }
        }
    }

    private var centre: some View {
        VStack(spacing: 3) {
            /* ⚠ "0%" WOULD READ AS FAILING AT SOMETHING. Before the first
               contract there is no denominator, so the centre carries a dash
               and the label says what has not happened. */
            Text(started
                 ? (weeksMode ? weeksFigure : String(format: "%.0f%%", frac * 100))
                 : emptyFigure)
                .font(S.inter(S.t30, S.wBoldN))
                .tracking(S.track(S.t30, -0.03))
                .foregroundStyle(started ? S.gainText : S.mute)
                .sunnyLineBox(S.t30)
                .lineLimit(1).minimumScaleFactor(0.7)
            /* ⚠ THE LABEL IS THE HINT, THE FIGURE IS WHAT CHANGES. One dotted
               underline per tap target, and a dotted line under a 30pt numeral
               reads as a rule rather than a hint. */
            Text(started ? (weeksMode ? "TO COVER" : "COVERED") : emptyLabel)
                .font(S.inter(S.t11, S.wBoldN)).tracking(S.track(S.t11, S.lsLabel))
                .foregroundStyle(S.mute)
                .sunnyHint(on: started)
        }
        .frame(width: 140, height: 44)
        .contentShape(Rectangle())
        .onTapGesture { if started { weeksMode.toggle() } }
    }

    /* Covered is 0 weeks, not "no answer"; no pace at all is the dash. */
    private var weeksFigure: String {
        if covered { return "0 wk" }
        guard let weeks, weeks > 0 else { return "\u{2014}" }
        return "\(weeks) wk"
    }
}

/// ⚠ THE CIRCLE IS WHAT THE LEAP CALLS COST, AND THE AMOUNT IS PRINTED. The
/// same figure Programme prints as paid and Weekly yield divides by. A ring
/// with no amount on it is a percentage wearing a costume; the reason this can
/// be a ring at all is that its whole is real money.
///
/// ⚠ AND NO PER-NAME ROWS. Which name is lagging is Yield progress's job.
struct SunnyCallCover: View {
    let c: CallCover?

    var body: some View {
        CoverRingCard(
            name: "call-cover",
            title: "Call cover", scope: c == nil ? "" : "all LEAPs",
            count: c.map { "\($0.names) name\($0.names == 1 ? "" : "s")" } ?? "none yet",
            started: (c?.cost ?? 0) > 0,
            cost: c?.cost ?? 0, collected: c?.collected ?? 0,
            left: c?.left ?? 0, pace: c?.pace ?? 0,
            weeks: c?.weeksToCover,
            paceLine: line,
            free: c?.free ?? 0, freeWord: (c?.free ?? 0) == 1 ? "call" : "calls",
            move: c?.move,
            /* ⚠ AN UP WEEK IS THIS RING'S GOOD WEEK: a running stock is the
               week the short calls are paid for by the LEAP under them. */
            moveHot: (c?.move ?? 0) > 0,
            costLabel: "LEAP cost", leftLabel: "Left",
            emptyFigure: "\u{2014}", emptyLabel: "NO LEAPS YET",
            emptyLine: "No LEAP calls held yet")
    }

    /* ⚠ THE DATE, NOT THE COUNT. Nik, 14 Sep 2026: "add there the apprx date
       when the investment will be covered". "In 36 weeks" makes the reader do
       arithmetic the card has already done — he read it as early May and it is
       the 24th. Always on rather than behind the tap: the line is the same
       width either way, and the tap's "36 wk" then has something to agree
       with. Measured at 294.5 of 323 at 12/400. */
    private var line: String {
        guard let c, c.cost > 0 else {
            return "The ring fills as credit covers what the LEAPs cost"
        }
        if c.left <= 0 { return "Covered \u{00B7} \(optMoney(c.pace))/wk still coming in" }
        guard c.pace > 0, c.weeksToCover > 0, let by = c.by else {
            return "\(optMoney(c.left)) to cover \u{00B7} no pace yet"
        }
        return "\(optMoney(c.pace))/wk pace \u{00B7} covered the week of \(coverDay(by))"
    }
}

/// ⚠ THE CIRCLE IS THE COMBINED COST OF EVERY PUT, AND THE AMOUNT IS PRINTED.
///
/// ⚠ CUMULATIVE AND IT NEVER RESETS. Nik, 2026-09-06: "It's a continous process
/// when new stock is added new puts are added so not it never resets its
/// continuous." Buying a tranche raises `cost` and drops the ring; the weeklies
/// climb it back. `collected` is short-PUT premium only — call premium is the
/// call ring's numerator and one dollar cannot discharge two obligations.
///
/// ⚠ A DOWN WEEK IS THIS CARD'S GOOD WEEK. The move word takes loss ink only
/// when the book is down, because that is the week the hedge is paying for
/// itself. It is the one card in the family where red is reassurance.
struct SunnyPutCover: View {
    let c: PutCover?

    var body: some View {
        CoverRingCard(
            name: "put-cover",
            /* ⚠ NO SCOPE WORD. The sheet has "all tickers"; Nik ruled it off on
               2026-09-06 because not every position carries a put, and naming
               the whole book when four of seven are in it is a lie the count
               already corrects. */
            title: "Put cover", scope: "",
            count: c.map { "\($0.names) name\($0.names == 1 ? "" : "s") \u{00B7} \($0.puts) put\($0.puts == 1 ? "" : "s")" } ?? "none yet",
            started: (c?.cost ?? 0) > 0,
            cost: c?.cost ?? 0, collected: c?.collected ?? 0,
            left: c?.left ?? 0, pace: c?.pace ?? 0,
            weeks: c?.weeksToCover,
            paceLine: line,
            free: c?.free ?? 0, freeWord: (c?.free ?? 0) == 1 ? "put" : "puts",
            move: c?.move,
            moveHot: (c?.move ?? 0) < 0,
            costLabel: "Put cost", leftLabel: "To cover",
            emptyFigure: "\u{2014}", emptyLabel: "NO PUTS YET",
            emptyLine: "No puts bought yet")
    }

    /* ⚠ THE LINE ASKS WHAT IT TAKES, NOT HOW LONG THE PACE WOULD TAKE. Nik,
       2026-09-09: "the suggestion cannot be post expiry. We need to say that
       2200 to be made to cover in 32 weeks." It read "$1,090/wk pace · full
       cover in 45 weeks" against puts that expire in 28. Dividing what is left
       by the realised pace answers a question whose premise is false, and the
       cover-rings sheet reverting to that line does not change the arithmetic:
       today it would print 40 weeks against an expiry 27 weeks out. */
    private var line: String {
        guard let c, c.cost > 0 else {
            return "The ring fills as premium covers what the puts cost"
        }
        if c.left <= 0 { return "Covered \u{00B7} \(optMoney(c.pace))/wk still coming in" }
        /* ⚠ ON THIS RING THE DATE IS A DEADLINE, NOT A FORECAST. The call ring
           projects a pace forward and names the week it lands; here the date is
           the EARLIEST long-put expiry, which is when the cover being paid for
           stops existing. Same shape, opposite direction, so the word is "by"
           and never "covered the week of". */
        guard let weeks = c.weeksLeft, weeks > 0, let need = c.need, need > 0,
              let exp = c.expiry else {
            return "\(optMoney(c.left)) still to cover"
        }
        _ = weeks
        if c.pace >= need {
            return "On pace \u{00B7} \(optMoney(c.pace))/wk covers it by \(coverDay(exp))"
        }
        return "\(optMoney(need)) a week to cover by \(coverDay(exp))"
    }
}

/// "24 May 2027" — a date the reader can put in a diary, never a week count.
private func coverDay(_ iso: String) -> String {
    let p = iso.split(separator: "-")
    let mon = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]),
          (1...12).contains(m) else { return iso }
    return "\(d) \(mon[m - 1]) \(y)"
}

/// "−2.2%" / "+0.4%" / "0.0%" — the plus stays here, because the move word is
/// a direction and the line has no bar to read the sign off.
private func signedPct1(_ v: Double) -> String {
    let a = String(format: "%.1f", abs(v))
    if a == "0.0" { return "0.0%" }
    return (v < 0 ? "\u{2212}" : "+") + a + "%"
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
        var kept: Double { gross - bought }
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
            guard g > 0 || b > 0 else { return nil }
            return Wk(id: w.week, label: shortWeek(w.week), live: w.current ?? false,
                      gross: g / den * 100, bought: b / den * 100)
        }
    }
    /// The axis is set by the tallest GROSS bar; every height is a share of it.
    private var maxGross: Double { max(weeks.map(\.gross).max() ?? 1, 0.01) }
    private var avgKept: Double {
        weeks.isEmpty ? 0 : weeks.reduce(0) { $0 + $1.kept } / Double(weeks.count)
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
                    right: "\(weeks.count) week" + (weeks.count == 1 ? "" : "s"))
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
                        .foregroundStyle(S.ink).sunnyLineBox(S.t30)
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
                .init(label: "Kept", value: pct2(at?.kept ?? 0), ink: S.ink),
                /* ⚠ MEASURED, NOT GUESSED: "CLOSED EARLY" is 90.5 at 10/700
                   with .13em tracking, against 91.67 of slot. "PAID TO CLOSE"
                   was 91.9 and would have truncated. */
                .init(label: "Closed early",
                      value: (at.map { $0.bought > 0 ? "\u{2212}" : "" } ?? "")
                             + pct2(at?.bought ?? 0),
                      ink: (at?.bought ?? 0) > 0 ? S.lossText : S.mute),
                /* ⚠ YEARLY DOES NOT FOLLOW THE TAP, on purpose: one week
                   annualised is a forecast and this card makes none. */
                .init(label: "Yearly", value: "\(Int((avgKept * 52).rounded()))%", ink: S.ink),
            ])
        }
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
                            .frame(height: max(1, y(w.gross)))
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
                    .contentShape(Rectangle())
                    /* The tap target is the bar. No text on this card flips, so
                       nothing here carries the dotted underline: that hint marks
                       tappable TEXT and would be a lie on a week label. */
                    .onTapGesture { picked = (picked == w.id) ? nil : w.id }
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
/// known, visible when it is not.
private extension View {
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

// MARK: - the pair frame · Average credit, then Theta

/* ⚠ ONE FRAME, TWO QUESTIONS, 14 Sep 2026, from the `credit-theta` handoff
   (cards/average-credit.md, cards/theta.md, credit-theta-data.js). Average
   credit REPLACES the 8 Sep card; Theta is new.

   ⚠ NEITHER SIDE IS THE ANSWER, THE COMPARISON IS — so there is no 30pt hero
   on either card, only two 22s. A reader who has learned "figure over its own
   baseline, four bars, ink line" on one card reads the other with no
   instruction, which is the whole reason they share a frame.

   ⚠ THE BARS ARE SHAPE, NOT QUANTITY. The scale is per side and TRUNCATED
   (floor = the window's minimum less 35% of its range, ceiling = its maximum
   plus 6%), because calls running $56 to $73 on a zero-based axis draw as four
   identical slabs. Two consequences, both accepted: no bar is labelled, and the
   two columns are NOT height-comparable to each other. */

/// One side of the frame: a figure, the average it is judged against, and four
/// weeks of shape with that average drawn across them.
private struct PairCol {
    let label: String
    let figure: String
    let ink: Color
    let baseline: String
    /// oldest first, live LAST. nil where the side did not trade that week.
    let values: [Double?]
    let keys: [String]
    /// The height the ink line sits at, in the same units as `values`.
    let ref: Double?
    /// Average credit only: where this week's figure would sit at usual IV.
    let usual: Double?
}

private struct PairFrameCard<Footer: View>: View {
    let name: String
    let title: String
    let week: String
    /// The unit word beside the title. Tappable only on Theta, and only then
    /// does it carry the dotted underline — one hint per target, on the
    /// control, never on what it changes.
    let unit: String
    let onUnit: (() -> Void)?
    let left: PairCol, right: PairCol
    /* ⚠ THE COLUMNS SHARE A SCALE WHEN THE CARD PRINTS A RELATIONSHIP BETWEEN
       THEM, and not otherwise. That is the rule, and it is the correction to
       the sheet's blanket "the two columns are not height-comparable".

       Nik, 14 Sep 2026, on Theta: "graph is misleading, theta for long is less
       but still the bar is taller". He was right. Theta's two columns are two
       halves of ONE total — the card prints Net and "short collects 3.9x what
       long loses" — so a reader is meant to compare them, and a per-side scale
       drew −$279 taller than +$1,084.

       Average credit keeps the per-side scale, because its columns are two
       independent books judged against their OWN pasts and the card states no
       relationship between them. */
    var shared = false
    @ViewBuilder let footer: () -> Footer

    /* Measured, not chosen: inner 323, so 146 + 15 + 1 + 15 + 146. Four bars in
       a 146 column at gap 9 is 29.75 each, which is also the usual-IV tick's
       width because that tick spans the live bar and nothing else. */
    private var colW: CGFloat { (S.content - 38 - 15 - 1 - 15) / 2 }
    private var barW: CGFloat { (colW - 3 * 9) / 4 }
    private var plotH: CGFloat { 132 }

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OptCard(name: name) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
                HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                    Text(title).font(S.inter(S.t14, S.wBoldN))
                        .tracking(S.track(S.t14, -0.01)).foregroundStyle(S.ink)
                    Text(unit).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
                        .sunnyHint(on: onUnit != nil)
                        .contentShape(Rectangle())
                        .onTapGesture { onUnit?() }
                }
                Spacer(minLength: 0)
                Text(week).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
            }
            /* 20 is load-bearing: at 0 the two eyebrows read as a second line
               of the header rather than the tops of two columns. */
            Spacer().frame(height: 20)
            HStack(alignment: .top, spacing: 15) {
                column(left)
                /* The card's only rule. It exists because the two columns are
                   on different scales: it says these are two readings, not one
                   four-column row. */
                Rectangle().fill(S.ruleColorStrong)
                    .frame(width: 1).frame(maxHeight: .infinity)
                column(right)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 6) { footer() }
        }
        /* Driven by data arrival. onAppear fires on the empty card while the
           fetch is in flight, so the grow-from-zero has nothing to grow. */
        .task(id: left.figure + right.figure) {
            guard !appeared else { return }
            try? await Task.sleep(for: .milliseconds(20))
            appeared = true
        }
    }

    /// lo is a share of the window's own RANGE, never of its minimum: a
    /// proportional floor only pads narrow windows and puts two different
    /// weeks on the same stub.
    ///
    /// ⚠ AND A SHARED SCALE IS ZERO-BASED, not truncated. The truncation exists
    /// to separate four near-identical bars inside one column; across two
    /// columns it would inflate the smaller side — long theta at 279 against
    /// 1,319 draws 34% of the box truncated and 21% from zero, and only the
    /// second is the ratio the footer prints.
    private func scale(_ c: PairCol) -> (lo: Double, hi: Double) {
        if shared {
            let all = (left.values + right.values).compactMap { $0 }
            let mx = all.max() ?? 1
            return (0, mx <= 0 ? 1 : mx * 1.06)
        }
        let vs = c.values.compactMap { $0 }
        guard let mn = vs.min(), let mx = vs.max() else { return (0, 1) }
        let r = (mx - mn) == 0 ? (mn == 0 ? 1 : abs(mn)) : (mx - mn)
        return (mn - r * 0.35, mx + r * 0.06)
    }
    private func frac(_ v: Double, _ s: (lo: Double, hi: Double)) -> Double {
        s.hi - s.lo <= 0 ? 0 : min(1, max(0, (v - s.lo) / (s.hi - s.lo)))
    }

    @ViewBuilder private func column(_ c: PairCol) -> some View {
        let sc = scale(c)
        VStack(alignment: .leading, spacing: 0) {
            Text(c.label)
                .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute).lineLimit(1)
            Spacer().frame(height: 9)
            Text(c.figure)
                .font(S.inter(S.t22, S.wBoldN)).tracking(S.track(S.t22, -0.03))
                .foregroundStyle(c.ink).sunnyLineBox(S.t22)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer().frame(height: 8)
            Text(c.baseline)
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
                .lineLimit(1).minimumScaleFactor(0.85)
            Spacer().frame(height: 18)
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 9) {
                    ForEach(Array(c.values.enumerated()), id: \.offset) { i, v in
                        /* No bar at all when the side did not trade, and the key
                           below still prints: the gap has to read as a gap. */
                        if let v {
                            UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                                .fill(i == c.values.count - 1 ? c.ink : S.barQuiet)
                                .frame(maxWidth: .infinity)
                                .frame(height: max(2, plotH * frac(v, sc)))
                                .scaleEffect(y: appeared || reduceMotion ? 1 : 0, anchor: .bottom)
                                .animation(reduceMotion ? nil
                                           : S.easeSettle(S.durBar).delay(Double(i) * 0.07),
                                           value: appeared)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 1)
                        }
                    }
                }
                if let ref = c.ref {
                    /* The same number printed above it, drawn where it falls.
                       --ink at 1.5: an average is a rate, so it never takes the
                       state ink. */
                    Rectangle().fill(S.ink).frame(height: S.refLine)
                        .offset(y: -plotH * frac(ref, sc))
                        .opacity(appeared || reduceMotion ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(0.45),
                                   value: appeared)
                }
                /* ⚠ THE USUAL-IV TICK SPANS THE LIVE BAR AND NOTHING ELSE. It
                   is where this week's credit would sit at the book's usual IV,
                   so the gap from tick to bar top is how much of the week is
                   IV rather than writing. --hair, because it annotates the
                   money axis and is not a second series. */
                if let u = c.usual {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle().fill(S.hair)
                            .frame(width: barW, height: S.refLine)
                    }
                    .offset(y: -plotH * frac(u, sc))
                    .opacity(appeared || reduceMotion ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(0.6),
                               value: appeared)
                }
            }
            .frame(height: plotH, alignment: .bottom)
            Spacer().frame(height: 9)
            HStack(spacing: 9) {
                ForEach(Array(c.keys.enumerated()), id: \.offset) { _, k in
                    Text(k).font(S.inter(S.t10, S.wMidSmN)).foregroundStyle(S.mute)
                        .frame(maxWidth: .infinity).lineLimit(1)
                }
            }
        }
    }
}

/// "9/7" — a 146pt column will not hold "Sep 7" four times.
private func pairKey(_ iso: String) -> String {
    let p = iso.split(separator: "-")
    guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]) else { return iso }
    return "\(m)/\(d)"
}
private func pairWeek(_ iso: String) -> String {
    let p = iso.split(separator: "-")
    let mon = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m)
    else { return iso }
    return "\(mon[m - 1]) \(d)"
}

// MARK: - average credit

/// ⚠ PER CONTRACT, FULL STOP — $56, never $0.56. The 14 Sep sheet's rule 3, and
/// the reason the old per-share tap is gone: the book holds LEAPs, not shares,
/// so the per-share quote was a broker convention with no referent here. This
/// card now has no tap at all, and therefore no dotted underline anywhere.
///
/// ⚠ THE AVERAGE IS CREDIT ÷ CONTRACTS, NEVER THE MEAN OF WEEKLY AVERAGES. A
/// week with 105 contracts is not worth the same as a week with 46, and the two
/// methods give different answers the moment the weeks differ in size. The
/// server ships the cash and the count; this card divides.
///
/// ⚠ COLOUR IS A COMPARISON THE CARD ALSO PRINTS. Each side is green at or
/// above ITS OWN prior blend and red below it, and that blend is printed under
/// the figure and drawn as a line across its own plot. No sentence explains it.
struct SunnyAvgCredit: View {
    let credit: CreditBlock
    /// Premium now's readings, reduced to one book multiple. Null before any
    /// name has enough IV history for a median to mean anything.
    let premium: PremiumBlock?

    /* The book's IV against its usual, one number: the mean of now/usual over
       the names that have a usual. Five of seven today — FIS and KR reach
       twenty days of history on 23 and 29 September and join then. */
    private var ivMult: Double? {
        let rs = (premium?.rows ?? []).filter { $0.usual > 0 }
        guard !rs.isEmpty else { return nil }
        return rs.reduce(0) { $0 + $1.now / $1.usual } / Double(rs.count)
    }

    /// Summed from the weeks themselves, never averaged from averages.
    private func blend(_ ws: [CreditWeek]) -> Double? {
        let past = ws.dropLast()
        let n = past.reduce(0) { $0 + $1.contracts }
        let c = past.reduce(0) { $0 + ($1.cash ?? 0) }
        return n > 0 ? Double(c) / Double(n) : nil
    }

    private func col(_ label: String, _ ws: [CreditWeek]) -> PairCol {
        let fig = ws.last?.perContract, b = blend(ws)
        /* Ink when there is no prior blend to judge against — a colour with
           nothing behind it would be an opinion the card cannot print. */
        let ink: Color = (fig == nil || b == nil) ? S.ink
            : (fig! >= b! ? S.gainText : S.lossText)
        return PairCol(
            label: label,
            figure: fig.map { optMoney(Int($0.rounded())) } ?? "\u{2014}",
            ink: ink,
            baseline: b.map { "average \(optMoney(Int($0.rounded())))" } ?? "no history yet",
            values: ws.map(\.perContract), keys: ws.map { pairKey($0.week) },
            ref: b,
            usual: (fig != nil && ivMult != nil && ivMult! > 0) ? fig! / ivMult! : nil)
    }

    var body: some View {
        let n = min(credit.calls.count, credit.puts.count)
        let thisN = (credit.calls.last?.contracts ?? 0) + (credit.puts.last?.contracts ?? 0)
        /* Contracts per WEEK, not per side, and over the PRIOR weeks only — the
           average has to be comparable to the single week beside it. */
        let priorN = n <= 1 ? 0 : (0..<(n - 1)).reduce(0) {
            $0 + credit.calls[$1].contracts + credit.puts[$1].contracts
        } / (n - 1)
        PairFrameCard(
            name: "avg-credit", title: "Average credit",
            week: pairWeek(credit.week),
            unit: "per contract", onUnit: nil,
            left: col("CALLS", credit.calls), right: col("PUTS", credit.puts)
        ) {
            Text("This week \(thisN) contract\(thisN == 1 ? "" : "s") \u{00B7} average \(priorN)")
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
                .lineLimit(1)
            /* The tick's legend, and the only reason a reader can tell the hair
               line above from the ink one. */
            if let m = ivMult, m > 0 {
                HStack(spacing: 6) {
                    Rectangle().fill(S.hair).frame(width: 12, height: S.refLine)
                    Text("at usual IV \u{00B7} book \(String(format: "%.2f", m))\u{00D7}")
                        .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                }
            }
        }
    }
}

// MARK: - theta

/// ⚠ THE INK IS THE SIGN, NOT A VERDICT. Long legs (the LEAPs and the
/// protective puts) always LOSE decay, so that side is always loss ink; short
/// legs always COLLECT, so that side is always gain ink. Neither colour is good
/// or bad news here — the comparison lives in the ink average line. This is the
/// one card in the frame where colour does not move with the data.
///
/// ⚠ A DAY IS THE UNIT, A WEEK IS THE TAP. Theta is quoted per day, so the card
/// opens per day; the tap multiplies every dollar by 7 and nothing else moves.
/// The bars do not change — shape is shape at any unit.
///
/// ⚠ AND TWO THINGS THE SERVER HAD TO CORRECT, both flagged to Nik: a day's
/// decay is capped at what the option is still worth (raw Black-Scholes theta
/// runs to infinity at expiry and summed to $5,533 a day on a book that takes
/// $7,000 a week), and every week is read the same number of days into itself,
/// or a live Monday would be charted beside four past Fridays.
struct SunnyTheta: View {
    let block: ThetaBlock

    /* Card-local, and it survives a pull. */
    @State private var weekly = false

    private var mul: Int { weekly ? 7 : 1 }
    private func sg(_ v: Int) -> String {
        let x = v * mul
        return (x < 0 ? "" : "+") + optMoney(x)
    }

    var body: some View {
        let ws = block.weeks
        let now = ws.last
        let prior = ws.dropLast()
        /* A PLAIN mean: theta is already a rate, so there is no contract count
           to weight the weeks by. */
        let lA = prior.isEmpty ? 0 : prior.reduce(0) { $0 + $1.long } / prior.count
        let sA = prior.isEmpty ? 0 : prior.reduce(0) { $0 + $1.short } / prior.count
        /* Bars plot the ABSOLUTE value on each side's own scale, so both columns
           rise as the book grows even though one side is negative. */
        let lCol = PairCol(
            /* ⚠ LOSES, NOT PAYS. Nik, 14 Sep 2026. "Pays" reads as the long
               side EARNING — it is the word for a dividend or a coupon — when
               it is the side that hands money back every day. "Loses" says
               which direction the money goes with no second reading. */
            label: "LONG \u{00B7} LOSES",
            figure: sg(now?.long ?? 0), ink: S.lossText,
            baseline: "average \(sg(lA))",
            values: ws.map { Double(abs($0.long)) }, keys: ws.map { pairKey($0.week) },
            ref: Double(abs(lA)), usual: nil)
        let sCol = PairCol(
            label: "SHORT \u{00B7} COLLECTS",
            figure: sg(now?.short ?? 0), ink: S.gainText,
            baseline: "average \(sg(sA))",
            values: ws.map { Double(abs($0.short)) }, keys: ws.map { pairKey($0.week) },
            ref: Double(abs(sA)), usual: nil)
        let net = (now?.long ?? 0) + (now?.short ?? 0)
        PairFrameCard(
            name: "theta", title: "Theta",
            week: pairWeek(now?.week ?? ""),
            unit: weekly ? "a week" : "a day",
            onUnit: { weekly.toggle() },
            left: lCol, right: sCol, shared: true
        ) {
            /* ⚠ NET IS THE CARD'S ANSWER, so it is the one ink line down here.
               Neither column is a result on its own: the long side paying is
               the cost of holding the position the short side collects
               against, and they are one trade. */
            Text("Net \(sg(net)) \(weekly ? "a week" : "a day") \u{00B7} average \(sg(lA + sA))")
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink)
                .lineLimit(1).minimumScaleFactor(0.85)
            Text(coverLine(now))
                .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
    }

    /* ⚠ THE RATIO ALONE FLATTERS ITSELF. "Short collects 3.9× what long loses"
       is the whole story on a quiet week and half of it on a 4% week, so
       Prices' move sits beside it: decay is only free when the book sits
       still, and the move is the ABSOLUTE one because a book with one name up
       6% and another down 6% has not sat still. */
    private func coverLine(_ now: ThetaWeek?) -> String {
        let mv = block.move.map { "book moved \(String(format: "%.1f", $0))%" }
            ?? "book move unknown"
        guard let now, now.long < 0 else { return mv }
        let r = Double(now.short) / Double(-now.long)
        return "short collects \(String(format: "%.1f", r))\u{00D7} what long loses \u{00B7} " + mv
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
    /// Theta's net a day. The earn-back clock is paid divided by it.
    let theta: ThetaBlock?

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

       The rate is Theta's NET a day, times seven — the same figure the card
       already used for the earn-back clock, so the 40 weeks he accepted has not
       moved. Flagged: the weekly credit pace ($4.9k) is the other candidate and
       would read slower.

       ⚠ NEVER A NEGATIVE WEEK. If the book's net decay is not positive there is
       nothing earning anything back, and every clock leaves rather than
       printing a number that points into the past. */
    private var rateWeek: Double? {
        guard let net = theta?.weeks.last?.net, net > 0 else { return nil }
        return Double(net) * 7
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
        return (clock(wp), clock(wi), clock(wt), clock(wl))
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
                .foregroundStyle(on ? S.onInk : S.mute)
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
private func ivDay(_ iso: String) -> String {
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



