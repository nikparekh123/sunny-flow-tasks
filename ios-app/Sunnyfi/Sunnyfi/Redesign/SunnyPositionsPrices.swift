//
//  SunnyPositionsPrices.swift
//  Positions + Prices (final cards, 23 Sep 2026). One name is one block: its
//  price, the window's move, next earnings, what its legs have kept, over a
//  LADDER where every strike stands where it sits from the price.
//
//  ⚠ IT REPLACED POSITIONS AND PRICES (Nik, 23 Sep 2026). The roll sheet is
//  not here: it opens from a held ticker on Inventory (Nik, 24 Sep).
//
//  ⚠ THE PRICE IS THE ARROW, AND THE ARROW IS TODAY. The tick at the centre
//  points up or down by the session; behind it a wash is the picked window's
//  path, and today's segment lies over it one step deeper. The move printed
//  beside the name is the window's; the arrow is always the session's.
//
//  ⚠ STRIKES DRAW ON THE SESSION CHIP ONLY. On 1w…4w the ladder is the
//  price's path alone.
//
//  ⚠ THREE RULINGS OUTRANK THE SHEET, kept from the Positions card:
//  the Yield footer is credit ÷ what that side's long legs cost (Nik, 15 Sep);
//  the third tap on a bought tab is time value left, not mark (Nik, 15 Sep);
//  and nothing on a sold tab is "kept" while it is open, so the hero says
//  unrealised all week.
//

import SwiftUI

struct SunnyPositionsPrices: View {
    let positions: [OptionsPosition]
    let legs: [LongLeg]
    let prices: PricesBlock?
    let roll: RollCard?

    @AppStorage("sunnyfi.pp.tab") private var tabRaw = "sc"
    /// 0 = %, 1 = $, 2 = time value. Shared across the four tabs.
    @AppStorage("sunnyfi.pp.mode") private var mode = 0
    /// 0 = the session, 1…4 = weeks back. Card-local, shared across tabs.
    @State private var win = 0
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: geometry, from the sheet

    private static let track: CGFloat = 313
    /* ⚠ TYPE UP A STEP, 23 Sep 2026 (type-size change after export): the
       name line reads at 15, strikes at 12, so the labels need 46 between
       centres and the ladder 56. */
    private static let labelGap: CGFloat = 46
    private static let labelEdge: CGFloat = 16
    private static let ladderH: CGFloat = 56
    private static let blockGap: CGFloat = 22

    // MARK: the tabs

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

    // MARK: the price

    private struct Price { let spot: Double?, then: Double?, prev: Double?, move: Double? }

    /// Spot, the window's "then", yesterday's close and the window's move, all
    /// read back off Prices' percentages: `then = spot / (1 + move)`. A name
    /// Prices does not carry takes the chain's spot and no path.
    private func price(_ t: String) -> Price {
        guard let r = prices?.rows.first(where: { $0.ticker == t }), let sp = r.spot, sp > 0 else {
            return Price(spot: roll?.names[t]?.spot, then: nil, prev: nil, move: nil)
        }
        let w: PriceWindow = [.today, .w1, .w2, .w3, .w4][min(4, max(0, win))]
        let prev = r.pct.today.map { sp / (1 + $0 / 100) }
        let mv = r.pct.value(w)
        return Price(spot: sp, then: mv.map { sp / (1 + $0 / 100) } ?? sp, prev: prev, move: mv)
    }
    private func spotOf(_ t: String) -> Double? { price(t).spot }

    // MARK: the legs

    private struct Leg: Identifiable {
        let id: String
        let t: String, strike: Double, call: Bool, n: Int
        let exp: String?
        let sold: Bool
        var quiet = false
        /// Sold: captured %, credit a share, kept $, credit $, time value left $.
        var pct = 0.0, cr = 0.0, kept = 0.0, credit = 0.0, time = 0.0
        /// Bought: change since bought, made $, mark $, paid $, time value $.
        var ch = 0.0, made = 0.0, mark = 0.0, paid = 0.0, tv = 0.0
        var through = false
        var dist = 0.0
        var up: Bool { sold ? pct >= 0 : ch >= 0 }
    }

    /// Every open short line, both sides. The tab picks which are loud.
    private var soldAll: [Leg] {
        positions.flatMap { p in
            p.shorts.enumerated().compactMap { i, s -> Leg? in
                guard let cr = s.cr else { return nil }
                let call = (s.type ?? "call") == "call"
                let spot = spotOf(p.t)
                var l = Leg(id: "\(p.t)|\(s.label)|\(s.exp)|\(i)", t: p.t, strike: s.k,
                            call: call, n: s.n, exp: s.exp, sold: true)
                l.pct = Double(s.captured); l.cr = cr
                l.credit = cr * 100 * Double(s.n)
                l.kept = l.pct / 100 * l.credit
                l.time = Double(s.tv ?? 0)
                if let spot, spot > 0 {
                    l.dist = (s.k / spot - 1) * 100
                    l.through = call ? spot > s.k : spot < s.k
                }
                return l
            }
        }
    }

    private var boughtAll: [Leg] {
        legs.filter { $0.isCall == tab.isCall }.map { g in
            let k = Double(g.k.dropLast()) ?? 0
            let spot = spotOf(g.t)
            var l = Leg(id: "\(g.t)|\(g.k)", t: g.t, strike: k, call: g.isCall, n: g.n,
                        exp: nil, sold: false)
            l.ch = g.cost > 0 ? g.m / g.cost - 1 : 0
            l.made = (g.m - g.cost) * Double(g.n)
            l.mark = g.m * Double(g.n)
            l.paid = g.cost * Double(g.n)
            if let spot, spot > 0 {
                l.dist = (k / spot - 1) * 100
                /* ⚠ MONEYNESS INVERTS ON A PUT, the deck's most repeated trap. */
                let intr = (g.isCall ? max(0, spot - k) : max(0, k - spot)) * 100
                l.tv = max(0, g.m - intr) * Double(g.n)
            }
            return l
        }
    }

    // MARK: the names

    private struct Name: Identifiable {
        let t: String
        let price: Price
        let legs: [Leg]
        let worst: Double
        let fig: String, figInk: Color
        let tInk: Color
        let earn: (word: String, loud: Bool)?
        var id: String { t }
    }

    private func figOf(_ l: Leg) -> String {
        if l.sold {
            switch mode {
            case 1: return signedMoney(l.kept)
            case 2: return optMoney(Int(l.time.rounded()))
            default: return ppPct0(l.pct)
            }
        }
        switch mode {
        case 1: return signedMoney(l.made)
        case 2: return optMoney(Int(l.tv.rounded()))
        default: return ppPct1(l.ch * 100)
        }
    }

    /// The tab's shown legs (loud and quiet) and their names, worst first.
    private var model: (legs: [Leg], loud: [Leg], names: [Name], lim: Double) {
        var shown: [Leg], loud: [Leg]
        if tab.sold {
            /* ⚠ THE TAB'S SIDE ONLY. The sheet drew the other side quiet so a
               name read whole; Nik, 23 Sep 2026: "dont show puts on calls
               sold". A grey put a point from a call pushed the call's label
               off its own bar (NFLX 72P beside 73C). */
            loud = soldAll.filter { $0.call == tab.isCall }
            shown = loud
        } else {
            shown = boughtAll; loud = shown
        }
        /* ONE SCALE FOR THE TAB: the farthest strike or the farthest window
           "then" × 1.25 (sold) or 1.15 (bought), rounded up to a five. */
        var dists = shown.map(\.dist)
        for t in Set(shown.map(\.t)) {
            let p = price(t)
            if let s = p.spot, let th = p.then, s > 0 { dists.append((th / s - 1) * 100) }
        }
        let f = tab.sold ? 1.25 : 1.15
        let lim = max(5, ((dists.map { abs($0) }.max() ?? 0) * f / 5).rounded(.up) * 5)

        var order: [String] = []
        for l in shown where !order.contains(l.t) { order.append(l.t) }
        var names = order.map { t -> Name in
            let ls = shown.filter { $0.t == t }.sorted { $0.dist < $1.dist }
            let ld = ls.filter { !$0.quiet }
            let fig: String, ink: Color, worst: Double
            if tab.sold {
                let kept = ld.reduce(0) { $0 + $1.kept }, credit = ld.reduce(0) { $0 + $1.credit }
                let time = ld.reduce(0) { $0 + $1.time }
                fig = mode == 1 ? signedMoney(kept) : mode == 2 ? optMoney(Int(time.rounded()))
                    : ppPct0(credit > 0 ? kept / credit * 100 : 0)
                ink = mode == 2 ? S.ink : kept < 0 ? S.lossText : S.gainText
                worst = ld.map(\.pct).min() ?? 0
            } else {
                let made = ld.reduce(0) { $0 + $1.made }, paid = ld.reduce(0) { $0 + $1.paid }
                let tv = ld.reduce(0) { $0 + $1.tv }
                fig = mode == 1 ? signedMoney(made) : mode == 2 ? optMoney(Int(tv.rounded()))
                    : ppPct1(paid > 0 ? made / paid * 100 : 0)
                ink = mode == 2 ? S.ink : made < 0 ? S.lossText : S.gainText
                worst = paid > 0 ? made / paid : 0
            }
            return Name(t: t, price: price(t), legs: ls, worst: worst, fig: fig, figInk: ink,
                        tInk: tab.sold && ld.contains(where: \.through) ? S.lossText : S.ink,
                        earn: rsEarnWord(inDays: roll?.names[t]?.earn))
        }
        names.sort { $0.worst < $1.worst }
        return (shown, loud, names, lim)
    }

    // MARK: the hero and the footer

    private func heroParts(_ loud: [Leg]) -> (hero: String, ink: Color, sub: String, eyebrow: String) {
        if tab.sold {
            let kept = loud.reduce(0) { $0 + $1.kept }, credit = loud.reduce(0) { $0 + $1.credit }
            let time = loud.reduce(0) { $0 + $1.time }
            let thr = loud.filter(\.through).count
            switch mode {
            case 1: return (signedMoney(kept), kept < 0 ? S.lossText : S.gainText,
                            "unrealised \u{00B7} " + (thr > 0 ? "\(thr) through" : "none through"),
                            "KEPT OF CREDIT")
            case 2: return (optMoney(Int(time.rounded())), S.ink,
                            "of \(optMoney(Int((credit - kept).rounded()))) to close", "TIME VALUE LEFT")
            default: return (ppPct0(credit > 0 ? kept / credit * 100 : 0), kept < 0 ? S.lossText : S.gainText,
                             "unrealised \u{00B7} " + (thr > 0 ? "\(thr) through" : "none through"),
                             "CAPTURED OF CREDIT")
            }
        }
        let made = loud.reduce(0) { $0 + $1.made }, paid = loud.reduce(0) { $0 + $1.paid }
        let tv = loud.reduce(0) { $0 + $1.tv }
        let names = Set(loud.map(\.t))
        let up = names.filter { t in loud.filter { $0.t == t }.reduce(0) { $0 + $1.made } >= 0 }.count
        switch mode {
        case 1: return (signedMoney(made), made < 0 ? S.lossText : S.gainText,
                        "\(up) of \(names.count) up \u{00B7} since bought", "MADE YOU")
        case 2: return (optMoney(Int(tv.rounded())), S.ink, "still to melt", "TIME VALUE LEFT")
        default: return (ppPct1(paid > 0 ? made / paid * 100 : 0), made < 0 ? S.lossText : S.gainText,
                         "\(up) of \(names.count) up \u{00B7} since bought", "CHANGE SINCE BOUGHT")
        }
    }

    private func stats(_ loud: [Leg]) -> [(String, String, Color)] {
        if tab.sold {
            let kept = loud.reduce(0) { $0 + $1.kept }, credit = loud.reduce(0) { $0 + $1.credit }
            /* ⚠ THE YIELD'S DENOMINATOR IS THE CAPITAL, NOT THE CREDIT (Nik,
               15 Sep): the open credit against what that side's long legs cost. */
            let inv = legs.filter { $0.isCall == tab.isCall }.reduce(0) { $0 + $1.cost * Double($1.n) }
            return [("OPEN CREDIT", optMoney(Int(credit.rounded())), S.ink),
                    ("WORTH NOW", optMoney(Int((credit - kept).rounded())), S.ink),
                    ("YIELD", String(format: "%.1f%%", inv > 0 ? credit / inv * 100 : 0), S.ink)]
        }
        let paid = loud.reduce(0) { $0 + $1.paid }, mark = loud.reduce(0) { $0 + $1.mark }
        return [("PAID", optMoney(Int(paid.rounded())), S.ink),
                ("WORTH NOW", optMoney(Int(mark.rounded())), S.ink),
                ("DIFFERENCE", signedMoney(mark - paid), mark >= paid ? S.gainText : S.lossText)]
    }

    // MARK: the window

    private var etCal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return c
    }
    /// today · yesterday · the weekday of the last close. A fact about the
    /// data's date, never a clock guess.
    private var sessionWord: String {
        guard let p = prices else { return "today" }
        if p.live == true { return "today" }
        let f = DateFormatter()
        f.calendar = etCal; f.timeZone = etCal.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: p.asOf) else { return "today" }
        let days = etCal.dateComponents([.day], from: etCal.startOfDay(for: d),
                                        to: etCal.startOfDay(for: Date())).day ?? 0
        if days == 0 { return "today" }
        if days == 1 { return "yesterday" }
        f.dateFormat = "EEEE"
        return f.string(from: d)
    }

    // MARK: body

    var body: some View {
        let m = model
        let h = heroParts(m.loud)
        let soon = m.names.filter { $0.earn?.loud == true }
        let rest = m.names.filter { $0.earn?.loud != true }
        VStack(alignment: .leading, spacing: 0) {
            header(m)
            Spacer().frame(height: 18)
            tabRow
            Spacer().frame(height: 22)
            eyebrowRow(h.eyebrow)
            Spacer().frame(height: 12)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(h.hero).font(S.inter(S.t30, S.wBoldN)).tracking(S.track(S.t30, -0.035))
                    .foregroundStyle(h.ink).sunnyLineBox(S.t30)
                Text(h.sub).font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer().frame(height: 28)
            legend(m.lim)
            Spacer().frame(height: 18)

            VStack(alignment: .leading, spacing: 0) {
                if !soon.isEmpty {
                    reporting(soon, lim: m.lim)
                    Spacer().frame(height: Self.blockGap)
                }
                VStack(alignment: .leading, spacing: Self.blockGap) {
                    ForEach(Array(rest.enumerated()), id: \.element.id) { i, n in
                        block(n, lim: m.lim, i: i + soon.count)
                    }
                }
            }
            .id(tabRaw)

            Spacer().frame(height: 26)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 18)
            footer(stats(m.loud))
        }
        .frame(width: Self.track, alignment: .leading)
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 28, trailing: 24))
        .frame(width: S.content, alignment: .top)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCardL)
        .monospacedDigit()
        .measure("positions-prices")
        .task(id: tabRaw) {
            appeared = false
            try? await Task.sleep(for: .milliseconds(20))
            appeared = true
        }
    }

    private func header(_ m: (legs: [Leg], loud: [Leg], names: [Name], lim: Double)) -> some View {
        let n = m.loud.count
        let meta = tab.sold
            ? "\(n) leg\(n == 1 ? "" : "s") \u{00B7} \(m.names.count) name\(m.names.count == 1 ? "" : "s")"
            : "\(n) position\(n == 1 ? "" : "s") \u{00B7} \(m.names.count) name\(m.names.count == 1 ? "" : "s")"
        return HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                Text("Positions").font(S.inter(S.t14, S.wBoldN))
                    .tracking(S.track(S.t14, -0.01)).foregroundStyle(S.ink)
                Text(tab.scope).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
            }
            .fixedSize()
            Spacer(minLength: 0)
            Text(meta).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute).lineLimit(1)
        }
    }

    /// Four words on one rule; the picked one ink 700 with a 2pt line on it.
    private var tabRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(Tab.allCases.enumerated()), id: \.element) { i, t in
                if i > 0 { Spacer(minLength: 4) }
                VStack(spacing: 0) {
                    Text(t.label)
                        .font(S.inter(S.t12, t == tab ? S.wBoldN : S.wMidN))
                        .tracking(S.track(S.t12, -0.01))
                        .foregroundStyle(t == tab ? S.ink : S.mute)
                        .lineLimit(1).sunnyLineBox(S.t12)
                    Spacer().frame(height: 10)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(t == tab ? S.ink : .clear).frame(height: 2)
                }
                .contentShape(Rectangle())
                .onTapGesture { tabRaw = t.rawValue }
            }
        }
        .background(alignment: .bottom) { Rectangle().fill(S.ruleColor).frame(height: 1) }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: tabRaw)
    }

    /// The eyebrow names the figure; the five chips pick the window. The
    /// chips are 32 tall to the finger and bleed so the row lays out at 12.
    private func eyebrowRow(_ eyebrow: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
            Text(eyebrow).font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute).lineLimit(1).fixedSize()
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                ForEach(0..<5, id: \.self) { w in
                    Text(w == 0 ? sessionWord : "\(w)w")
                        .font(S.inter(S.t12, w == win ? S.wBoldN : S.wMidN))
                        .tracking(S.track(S.t12, -0.01))
                        .foregroundStyle(w == win ? S.ink : S.mute)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 5).padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .onTapGesture { win = w }
                }
            }
            .padding(.horizontal, -5).padding(.vertical, -10)
        }
        .frame(height: 12)
    }

    private func legend(_ lim: Double) -> some View {
        HStack(spacing: 0) {
            Text("\u{2212}\(Int(lim))%")
            Spacer(minLength: 0)
            Text("PRICE")
            Spacer(minLength: 0)
            Text("+\(Int(lim))%")
        }
        .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
        .foregroundStyle(S.mute)
        .sunnyLineBox(S.t10)
    }

    /// Names reporting this week or next, lifted into a warn wash on top.
    private func reporting(_ ns: [Name], lim: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("REPORTING").font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.warn)
                Spacer(minLength: 0)
                Text("\(ns.count) name\(ns.count == 1 ? "" : "s") this week or next")
                    .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
            }
            .sunnyLineBox(S.t11)
            Spacer().frame(height: 16)
            VStack(alignment: .leading, spacing: Self.blockGap) {
                ForEach(Array(ns.enumerated()), id: \.element.id) { i, n in block(n, lim: lim, i: i) }
            }
            Spacer().frame(height: 14)
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 4, trailing: 14))
        .background(S.ppReportWash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, -14)
    }

    // MARK: one name, one block

    private func block(_ n: Name, lim: Double, i: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(n.t).font(S.inter(S.t15, S.wSemiN)).tracking(S.track(S.t15, -0.015))
                        .foregroundStyle(n.tInk)
                    if let s = n.price.spot {
                        /* ⚠ PRICE, MOVE AND DATE AT ONE SIZE, price and date in
                           ink (Nik, 23 Sep 2026). The loud earnings word keeps
                           its warn ink: it is the one that asks for attention. */
                        Text(String(format: "$%.2f", s)).font(S.inter(S.t13, S.wBoldN))
                            .foregroundStyle(S.ink)
                    }
                    if let mv = n.price.move {
                        Text(ppSigned1(mv)).font(S.inter(S.t13, S.wSemiN))
                            .foregroundStyle(mv < 0 ? S.lossText : S.gainText)
                    }
                    if let e = n.earn {
                        Text(e.word).font(S.inter(S.t13, e.loud ? S.wBoldN : S.wMidSmN))
                            .foregroundStyle(e.loud ? S.warn : S.ink)
                    }
                }
                .lineLimit(1).fixedSize()
                Spacer(minLength: 0)
                Text(n.fig).font(S.inter(S.t15, S.wBoldN)).tracking(S.track(S.t15, -0.02))
                    .foregroundStyle(n.figInk).lineLimit(1).fixedSize()
                    .sunnyHint()
                    .padding(.vertical, 8).padding(.leading, 12).contentShape(Rectangle())
                    .onTapGesture { flip() }
                    .padding(.vertical, -8).padding(.leading, -12)
            }
            .sunnyLineBox(S.t15)
            ladder(n, lim: lim, i: i)
        }
        .opacity(appeared || reduceMotion ? 1 : 0)
        .animation(reduceMotion ? nil : S.easeSettle(0.4).delay(Double(i) * 0.04), value: appeared)
    }

    private func flip() { mode = (mode + 1) % 3 }

    /// x on the track, px: spot at the centre, `lim` % at each end.
    private func lx(_ p: Double, _ spot: Double, _ lim: Double) -> CGFloat {
        Self.track * CGFloat(0.5 + (p / spot - 1) * 100 / lim * 0.5)
    }

    /// Strike labels keep 46 between centres, nudged outward (a pass each
    /// way), then clamped 16 from the ends. Pills never move.
    private func slots(_ xs: [CGFloat]) -> [CGFloat] {
        var l = xs
        guard l.count > 1 else { return l.map { min(Self.track - Self.labelEdge, max(Self.labelEdge, $0)) } }
        for i in 1..<l.count where l[i] - l[i - 1] < Self.labelGap { l[i] = l[i - 1] + Self.labelGap }
        for i in stride(from: l.count - 2, through: 0, by: -1) where l[i + 1] - l[i] < Self.labelGap {
            l[i] = l[i + 1] - Self.labelGap
        }
        return l.map { min(Self.track - Self.labelEdge, max(Self.labelEdge, $0)) }
    }

    /* THE LADDER, 313 × 56. Strike labels 0–12, the rail zone 20–34 (wash,
       today, pills), figures 45–56; the rail a hairline at 26.5; the price tick
       2 × 18 at 18–36 with a 14 × 8 head, top 10 (up) or 36 (down). */
    @ViewBuilder private func ladder(_ n: Name, lim: Double, i: Int) -> some View {
        let W = Self.track
        ZStack(alignment: .topLeading) {
            Rectangle().fill(S.ruleColorStrong).frame(width: W, height: 1)
                .position(x: W / 2, y: 26.5)
            if let spot = n.price.spot, spot > 0 {
                let path = pathOf(n.price, spot: spot, lim: lim)
                let clamp = { (v: CGFloat) in min(W, max(0, v)) }
                let xThen = n.price.then.map { clamp(lx($0, spot, lim)) } ?? W / 2
                let xPrev = path.hasT ? clamp(lx(n.price.prev!, spot, lim)) : W / 2
                seg(from: xThen, fill: path.up ? S.ppWashSafe : S.ppWashRisk, delay: i)
                seg(from: xPrev, fill: path.tUp ? S.ppTodaySafe : S.ppTodayRisk, delay: i)
                if win == 0 {
                    let xs = n.legs.map { lx($0.strike, spot, lim) }
                    let ls = slots(xs)
                    ForEach(Array(n.legs.enumerated()), id: \.element.id) { j, l in
                        strike(l, x: xs[j], lx: ls[j], j: j)
                    }
                }
                let ink: Color = path.still ? S.mute : path.tUp ? S.gainText : S.lossText
                Rectangle().fill(ink).frame(width: 2, height: 18).position(x: W / 2, y: 27)
                Arrow(up: path.tUp).fill(ink).frame(width: 14, height: 8)
                    .position(x: W / 2, y: path.tUp ? 14 : 40)
            }
        }
        .frame(width: W, height: Self.ladderH, alignment: .topLeading)
    }

    /// A wash from `x` to the centre, grown from the centre outward.
    private func seg(from x: CGFloat, fill: Color, delay i: Int) -> some View {
        let c = Self.track / 2
        return RoundedRectangle(cornerRadius: 4).fill(fill)
            .frame(width: abs(c - x), height: 14)
            .scaleEffect(x: appeared || reduceMotion ? 1 : 0, anchor: x < c ? .trailing : .leading)
            .animation(reduceMotion ? nil : S.easeSettle(S.durBar).delay(Double(i) * 0.04), value: appeared)
            .position(x: (min(c, x) + max(c, x)) / 2, y: 27)
    }

    private struct PathRead { let up: Bool, tUp: Bool, hasT: Bool, still: Bool }
    private func pathOf(_ p: Price, spot: Double, lim: Double) -> PathRead {
        let then = p.then ?? spot
        let up = spot >= then
        let hasT = p.prev != nil && p.prev != spot
        return PathRead(up: up, tUp: hasT ? spot >= p.prev! : up, hasT: hasT,
                        still: !hasT && (p.then == nil || p.then == spot))
    }

    @ViewBuilder private func strike(_ l: Leg, x: CGFloat, lx: CGFloat, j: Int) -> some View {
        let q = l.quiet
        let kInk: Color = q ? S.mute : l.through ? S.lossText : S.ink
        let bar: Color = q ? S.hair : l.up ? S.gainBar : S.lossBar
        let ink: Color = q ? S.mute : mode == 2 ? S.ink : l.up ? S.gainText : S.lossText
        let delay = reduceMotion ? nil : S.easeSettle(0.5).delay(0.2 + Double(j) * 0.06)
        Group {
            RoundedRectangle(cornerRadius: 3).fill(bar).frame(width: 6, height: 14)
                .position(x: x, y: 27)
            Text(rsK(l.strike)).font(S.inter(S.t12, S.wBoldN)).tracking(S.track(S.t12, -0.01))
                .foregroundStyle(kInk).fixedSize().sunnyLineBox(S.t12)
                .position(x: lx, y: 6)
            Text(figOf(l)).font(S.inter(S.t11, S.wSemiN))
                .foregroundStyle(ink).fixedSize().sunnyLineBox(S.t11)
                .position(x: lx, y: 50.5)
        }
        .opacity(appeared || reduceMotion ? 1 : 0)
        .animation(delay, value: appeared)
        /* The hit area: 46 × 56 on the label, invisible. A tap flips the whole
           card. The roll sheet lives on Inventory's tickers now (Nik, 24 Sep). */
        Color.clear.frame(width: 46, height: Self.ladderH).contentShape(Rectangle())
            .onTapGesture { flip() }
            .position(x: lx, y: Self.ladderH / 2)
    }

    private func footer(_ st: [(String, String, Color)]) -> some View {
        HStack(alignment: .top, spacing: S.gap6) {
            ForEach(Array(st.enumerated()), id: \.offset) { _, s in
                VStack(alignment: .leading, spacing: 5) {
                    Text(s.0).font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                        .foregroundStyle(S.mute).lineLimit(1)
                    Text(s.1).font(S.inter(S.t19, S.wBoldN)).tracking(S.track(S.t19, -0.025))
                        .foregroundStyle(s.2).lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The price's arrow head, 14 × 8.
private struct Arrow: Shape {
    let up: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        if up {
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        } else {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }
}

/// Sold: `−113%` · `83%`.
private func ppPct0(_ v: Double) -> String {
    (v < 0 ? "\u{2212}" : "") + "\(Int(abs(v).rounded()))%"
}
/// Bought and moves: `+13.5%` · `−2.1%`.
private func ppPct1(_ v: Double) -> String {
    (v < 0 ? "\u{2212}" : "+") + String(format: "%.1f", abs(v)) + "%"
}
private func ppSigned1(_ v: Double) -> String {
    let a = String(format: "%.1f", abs(v))
    return (a == "0.0" ? "" : v < 0 ? "\u{2212}" : "+") + a + "%"
}
