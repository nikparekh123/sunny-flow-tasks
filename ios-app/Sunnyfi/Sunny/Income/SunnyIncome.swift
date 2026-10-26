//
//  SunnyIncome.swift
//  Sunny
//
//  Blocks 17 and 18 · Income (rebuilt for handoff 32, 26 Oct 2026). SunnyYield:
//  each week net on the LEAPs base, the closing cost a hatched cut-out, the
//  hedges spread to their expiry and taken off, the year at the 4-week pace.
//  SunnyPayback: made after closing costs and hedges against the same base,
//  paid back in a window between two paces, and what the LEAPs are worth.
//

import SwiftUI

// MARK: - Yield

/// Yield (handoff 32, block 17): each week net, on one base, the LEAPs held (their average cost at the week's end;
/// this week, today), the same base as Payback. Bars as tall as what was sold with the closing cost a hatched
/// cut-out from the top; a cost bigger than the sale drops below the line in red. The hedge calls and puts are
/// spread across the weeks to their expiry and taken off. The year comes from the trailing 4-week pace, never
/// one week times 52.
struct SunnyYield: View {
    let home: HomePayload
    let words: HomePayload
    @Environment(HomeRouter.self) private var router
    @State private var mode: PMode = PMode.preset(DebugPreset.string("yield.mode"))
    @State private var hidden: Set<String> = DebugPreset.set("yield.hide")

    private var P: PeriodState { router.period }

    /// One period's sums per side, the hedge charge and the net, in the mode's unit.
    private struct Sums {
        var cs = 0.0, cb = 0.0, ps = 0.0, pb = 0.0, hg = 0.0, weeks = 0
        var sold: Double { cs + ps }
        var back: Double { cb + pb }
        var net: Double { cs - cb + ps - pb - hg }
        var any: Bool { weeks > 0 }
    }

    private static func base(_ w: YieldWeek) -> Double { w.leaps ?? w.invested }

    private func value(_ w: YieldWeek, _ m: PMode? = nil) -> (Double, Double, Double, Double, Double) {
        switch m ?? mode {
        case .pct:
            let k = Self.base(w) > 0 ? 100 / Self.base(w) : 0
            return (w.callsSold * k, w.callsBack * k, w.putsSold * k, w.putsBack * k, (w.hedge ?? 0) * k)
        case .usd: return (w.callsSold, w.callsBack, w.putsSold, w.putsBack, w.hedge ?? 0)
        case .tv: return (w.callsSoldTv ?? 0, w.callsBackTv ?? 0, w.putsSoldTv ?? 0, w.putsBackTv ?? 0, w.hedge ?? 0)
        }
    }
    private func sums(_ rows: [YieldWeek], _ m: PMode? = nil) -> Sums {
        rows.reduce(into: Sums()) { s, w in
            let v = value(w, m); s.cs += v.0; s.cb += v.1; s.ps += v.2; s.pb += v.3; s.hg += v.4; s.weeks += 1
        }
    }
    private func fmt(_ v: Double) -> String { mode == .pct ? F.pct(v) : F.moneyK(v) }

    private struct Col { let id: Int; let label: String; let rows: [YieldWeek]; let now: Bool; let last: String }

    private var cols: [Col] {
        let today = home.today, a = Periods.anchor(P, today: today)
        if P.view == .week {
            let fri = Periods.thisFriday(today)
            return Periods.fridays(a).enumerated().map { i, f in
                let l = Periods.weekLabel(i, fri: f, today: today)
                return Col(id: i, label: l == "Current week" ? "This week" : l, rows: home.yield.filter { $0.fri == f }, now: f == fri, last: f)
            }
        }
        return Periods.months(a, start: Periods.bookStart(home)).map { m in
            let ym = String(format: "%@-%02d", a, m + 1)
            let rows = home.yield.filter { $0.month == ym }
            return Col(id: m, label: Periods.monthNames[m], rows: rows, now: today.hasPrefix(ym), last: rows.map(\.fri).max() ?? ym + "-28")
        }
    }

    /// "This week, Oct 26 to 30" · "Oct 19 to 23" · "Sep 28 to Oct 2" · "October".
    private func periodText(_ c: Col?) -> String {
        guard let c else { return Periods.label(P, today: home.today, picked: nil) }
        if P.view == .month { return Periods.longMonths[c.id] }
        let mon = MarketClock.addDays(c.last, -4).iso
        let a = PF.monthDay(mon), b = PF.monthDay(c.last)
        let range = a.prefix(3) == b.prefix(3) ? "\(a) to \(b.dropFirst(4))" : "\(a) to \(b)"
        return c.now ? "This week, \(range)" : range
    }

    /// The year from the trailing 4 weeks to the period's last week: their average net % times 52.
    private func yearPace(upTo fri: String) -> (pct: Double, weeks: Int)? {
        let ws = home.yield.filter { $0.fri <= fri && Self.base($0) > 0 }.sorted { $0.fri < $1.fri }.suffix(4)
        guard !ws.isEmpty else { return nil }
        let avg = ws.map { ($0.callsSold - $0.callsBack + $0.putsSold - $0.putsBack - ($0.hedge ?? 0)) / Self.base($0) * 100 }.reduce(0, +) / Double(ws.count)
        return (avg * 52, ws.count)
    }

    var body: some View {
        // Nothing tapped: the numbers follow the grey box, this week or this month (Nik, 14 Oct 2026).
        let cs = cols, pick = P.picked["yield"] ?? cs.first(where: \.now)?.id
        let shown = pick.map { i in cs.filter { $0.id == i } } ?? cs
        let tot = sums(shown.flatMap(\.rows))
        // Each figure is rounded first, then added, so the hero matches the stat line.
        let r = { (v: Double) in self.mode == .pct ? (v * 100).rounded() / 100 : v.rounded() }
        let net = r(tot.sold) - r(tot.back) - r(tot.hg)
        let col = pick.flatMap { i in cs.first { $0.id == i } }
        let lastRow = shown.flatMap(\.rows).max { $0.fri < $1.fri }
        let base = lastRow.map(Self.base) ?? home.payback.base ?? 0
        let pace = yearPace(upTo: col?.last ?? Periods.thisFriday(home.today))
        // Scale: the tallest sale above the line, the deepest loss below, inside 116 pt.
        let all = cs.map { sums($0.rows) }
        let up = all.map { max($0.cs, $0.ps) }.max() ?? 0, down = all.map { max($0.cb - $0.cs, $0.pb - $0.ps, 0) }.max() ?? 0
        let h = { (v: Double) -> CGFloat in CGFloat(v / max(1e-9, up + down)) * 116 }
        VStack(alignment: .leading, spacing: 20) {
            SPeriodHeader(label: "Yield", hero: tot.any ? fmt(net) : "-", heroValue: net,
                          heroColor: tot.any && net < 0 ? S.red : S.ink,
                          sub: periodText(col) + (base > 0 ? " · on \(F.moneyK(base)) in LEAPS" : ""),
                          onTap: { withAnimation(.smooth(duration: S.roll)) { mode = mode.next } }, period: P,
                          canGoBack: Periods.canGoBack(P, today: home.today, start: Periods.bookStart(home)), subLines: 2)
            VStack(alignment: .leading, spacing: 4) {
                if tot.any {
                    SStatLine(items: [(fmt(r(tot.sold)), "sold", S.ink), (fmt(r(tot.back)), "closing cost", S.red),
                                      (fmt(r(tot.hg)), tot.hg < 0 ? "hedges back" : "hedges", tot.hg < 0 ? S.green : S.red)])
                    if let p = pace {
                        SStatLine(items: [("\(Int(abs(p.pct).rounded()))%", "a year at the \(p.weeks)-week pace", p.pct < 0 ? S.red : S.ink)])
                    }
                } else {
                    SStatLine(items: [("-", "not traded yet", S.ink)])
                }
                SInlineInsight(lead: insight.lead, rest: insight.rest)
            }
            SViewToggle(period: P)
            SBarChart(columns: cs.map { c in
                let s = sums(c.rows)
                let bar = { (sold: Double, back: Double, solid: Color, key: String, label: Bool) -> SBar in
                    let kept = max(0, sold - back), cut = min(back, sold)
                    return SBar(segs: [.init(value: h(kept), color: solid, hidden: hidden.contains(key)),
                                       .init(value: h(cut), color: S.muted, hidden: hidden.contains(key + "b"), hatch: true)],
                                label: label && !c.rows.isEmpty && s.sold > 0 ? fmt(r(s.sold) - r(s.back) - r(s.hg)) : "",
                                labelColor: r(s.sold) - r(s.back) - r(s.hg) < 0 ? S.red : S.ink,
                                below: hidden.contains(key) ? 0 : h(max(0, back - sold)))
                }
                return SBarColumn(id: c.id, label: c.label,
                                  bars: [bar(s.cs, s.cb, S.green, "cs", true), bar(s.ps, s.pb, S.blue, "ps", false)],
                                  isNow: c.now)
            }, picked: pick, onPick: { P.picked["yield"] = $0 }, grown: P.grown, rowKey: P.view.rawValue)
            // Always dollars (Nik, 14 Oct 2026: the hero already gives the %).
            let money = mode == .pct ? sums(shown.flatMap(\.rows), .usd) : tot
            SLegend(rows: [("cs", "Calls sold", F.moneyK(money.cs), S.green), ("csb", "Calls · closing cost", F.moneyK(money.cb), S.muted),
                           ("ps", "Puts sold", F.moneyK(money.ps), S.blue), ("psb", "Puts · closing cost", F.moneyK(money.pb), S.muted),
                           ("hg", money.hg < 0 ? "Hedges · sold back" : "Hedges · spread", F.moneyK(money.hg), S.pNeutral),
                           ("net", "Net after hedges", F.moneyK(money.net), S.ink)],
                    hidden: $hidden)
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sCardSurface()
    }

    /// Yield up or down for N weeks in a row, or against the weeks before (net after hedges, on the LEAPs).
    private var insight: (lead: String, rest: String) {
        let w = words.yield.filter { $0.fri <= Periods.thisFriday(words.today) }.suffix(6)
        let pct = w.map { Self.base($0) > 0 ? ($0.callsSold + $0.putsSold - $0.callsBack - $0.putsBack - ($0.hedge ?? 0)) / Self.base($0) * 100 : 0 }
        guard pct.count >= 2, let last = pct.last else { return ("Nothing sold yet.", "") }
        let before = pct.dropLast(), avg = before.reduce(0, +) / Double(before.count)
        var streak = 0
        for i in stride(from: pct.count - 1, to: 0, by: -1) where (pct[i] > pct[i - 1]) == (last > pct[pct.count - 2]) { streak += 1 }
        if streak >= 2 { return ("Yield \(last > pct[pct.count - 2] ? "up" : "down") \(streak) weeks in a row.", "This week \(F.pct(last)).") }
        let diff = avg != 0 ? (last - avg) / abs(avg) * 100 : 0
        if abs(diff) < 5 { return ("About the same as before.", "This week \(F.pct(last)), the weeks before \(F.pct(avg)).") }
        return ("\(F.pct(last)) this week.", "\(Int(abs(diff).rounded()))% \(diff > 0 ? "above" : "below") the weeks before.")
    }
}

// MARK: - Payback

/// Payback (handoff 32, block 18): made, after closing costs and hedges, against what the LEAPs held cost (the
/// same base as Yield). Made = everything realized since the first LEAP plus the premium in hand on open shorts,
/// less the hedge cost spread so far on hedges still held. The date is a window between two paces, since the
/// start and the last 4 weeks, and the LEAPs' value today says whether paid back is also profit.
struct SunnyPayback: View {
    let home: HomePayload
    let words: HomePayload
    @State private var mode: PMode = PMode.preset(DebugPreset.string("pb.mode"))

    struct All {
        let base: Double, made: Double, settled: Double, open: Double, closing: Double, hedges: Double
        let start: Double, last4: Double?, value: Double
        var left: Double { max(0, base - made) }
        var pct: Double { base > 0 ? made / base * 100 : 0 }
        var done: Bool { base > 0 && made >= base }
        func weeks(_ pace: Double?) -> Int? { pace.flatMap { $0 > 0 ? Int(ceil(left / $0)) : nil } }
    }
    static func all(_ p: Payback) -> All {
        let made = p.made ?? ((p.now.allReal ?? p.now.tvPaid) + (p.now.held ?? 0))
        return All(base: p.base ?? (p.now.tvT + p.now.inT), made: made, settled: p.settled ?? made - (p.now.held ?? 0),
                   open: p.open ?? (p.now.held ?? 0), closing: p.closing ?? 0, hedges: p.hedges ?? 0,
                   start: p.paceStart ?? p.paceMade ?? p.paceTv, last4: p.paceRecent, value: p.leapsValue ?? 0)
    }
    private var pb: Payback { home.payback }
    private func dateIn(_ weeks: Int) -> String { MarketClock.addDays(home.today, weeks * 7).iso }
    /// "Aug 20, 2027"
    static func long(_ iso: String) -> String { "\(PF.monthDay(iso)), \(iso.prefix(4))" }
    /// "Aug 2027"
    static func month(_ iso: String) -> String { "\(PF.monthDay(iso).prefix(3)) \(iso.prefix(4))" }

    var body: some View {
        let a = Self.all(pb)
        let none = a.base <= 0
        let w1 = a.weeks(a.start), w2 = a.weeks(a.last4)
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Payback").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.muted)
                Button { withAnimation(.smooth(duration: S.roll)) { mode = mode.next } } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(none ? "-" : hero(a)).sType(.largeNumber)
                            .foregroundStyle(none ? S.ink : a.made < 0 ? S.red : S.green)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(none ? "nothing to pay back" : heroSub(a))
                            .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                            .foregroundStyle(S.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SPressStyle())
            }
            if none {
                SStatLine(items: [("-", "no LEAPs held", S.ink)])
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SStatLine(items: [(F.moneyK(a.start), "/ wk since start", a.start < 0 ? S.red : S.green)]
                              + (a.last4.map { [(F.moneyK($0), "/ wk last 4 weeks", $0 < 0 ? S.red : S.ink)] } ?? []))
                    window(a, w1, w2)
                    SInlineInsight(lead: insight.lead, rest: insight.rest)
                }
                chart(a, w1, w2)
                VStack(spacing: 0) {
                    row("Made", F.moneyK(a.made), a.made < 0 ? S.red : S.green, S.green,
                        Text("Settled ") + Text(F.moneyK(a.settled)).foregroundStyle(S.ink).bold() + Text(" · open this week ")
                            + Text(F.moneyK(a.open)).foregroundStyle(S.ink).bold(),
                        Text("After \(F.moneyK(a.closing)) of closing costs and " + (a.hedges < 0 ? "hedges that brought back \(F.moneyK(a.hedges))" : "\(F.moneyK(a.hedges)) of hedges")))
                    row("To go", F.moneyK(a.left), S.ink, S.pNeutral,
                        a.done ? Text("Paid back.") : (w1.map { Text(Self.long(dateIn($0))).foregroundStyle(S.ink).bold() + Text(" at \(F.moneyK(a.start)) a week since start") }
                            ?? Text("No date at the pace since start")),
                        a.done ? nil : (w2.map { Text(Self.long(dateIn($0))).foregroundStyle(S.ink).bold() + Text(" at \(F.moneyK(a.last4 ?? 0)), the last 4 weeks") }
                            ?? (a.last4 == nil ? nil : Text("No date at the last 4 weeks' pace"))))
                    let under = a.base - a.value
                    row("LEAPS today", F.moneyK(a.value), S.ink, S.blue,
                        under > 0 ? Text(F.moneyK(under)).foregroundStyle(S.red) + Text(" under the \(F.moneyK(a.base)) paid. Payback is not profit until they hold their value.")
                                  : Text(F.moneyK(-under)).foregroundStyle(S.green) + Text(" over the \(F.moneyK(a.base)) paid."), nil, last: true)
                }
            }
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sCardSurface()
    }

    /// "Paid back between Aug 2027 and Jan 2029", or one date when the paces agree to the month.
    @ViewBuilder private func window(_ a: All, _ w1: Int?, _ w2: Int?) -> some View {
        let ds = [w1, w2].compactMap { $0 }.sorted().map { Self.month(dateIn($0)) }
        Group {
            if a.done { Text("Paid back.") }
            else if ds.count == 2, ds[0] != ds[1] { Text("Paid back between ") + Text(ds[0]).bold() + Text(" and ") + Text(ds[1]).bold() }
            else if let d = ds.first { Text("Paid back by ") + Text(d).bold() }
            else { Text("Not paying back at these paces.") }
        }
        .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
        .foregroundStyle(S.ink)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func hero(_ a: All) -> String {
        switch mode {
        case .pct: return Self.pct(a.pct)
        case .usd: return PF.usd(a.made)
        case .tv: return a.done ? "done" : a.weeks(a.start).map { "\($0) wk" } ?? "-"
        }
    }
    private func heroSub(_ a: All) -> String {
        switch mode {
        case .pct: return "of \(F.moneyK(a.base)) in LEAPS made, after closing costs and hedges"
        case .usd: return "made of \(F.moneyK(a.base)) in LEAPS, after closing costs and hedges"
        case .tv: return a.done ? "paid back" : a.weeks(a.start).map { "paid back by \(Self.long(dateIn($0))) at the pace since start" } ?? "no date at this pace"
        }
    }

    /// "42%", "18.6%", "100%": one place, no trailing .0, no minus sign.
    static func pct(_ v: Double) -> String {
        let r = (abs(v) * 10).rounded() / 10
        return (r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)) + "%"
    }

    private func row(_ name: String, _ value: String, _ tone: Color, _ dot: Color, _ l1: Text, _ l2: Text?, last: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(name).sType(SType(size: 17, weight: 600, line: 22, tracking: 0), tabular: false)
                Spacer()
                Text(value).sType(SType(size: 17, weight: 700, line: 22, tracking: 0)).foregroundStyle(tone)
            }
            l1.sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let l2 {
                l2.sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(S.pGrid).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    // MARK: Chart

    /// Capital in LEAPs as a grey step line, made as a green one; from now, the two paces dashed to the capital,
    /// the window between them shaded; round gridlines in dollars.
    private func chart(_ a: All, _ w1: Int?, _ w2: Int?) -> some View {
        let ser = (pb.series2 ?? []).compactMap { r -> (d: String, cap: Double, made: Double)? in
            guard r.count >= 3, let d = r[0].string else { return nil }
            return (d, r[1].number ?? 0, r[2].number ?? 0)
        }
        let start = ser.first?.d ?? home.today
        let d1Iso = w1.map { dateIn(min($0, 78)) } ?? dateIn(26)
        let endIso = max(MarketClock.addDays(d1Iso, 30).iso, dateIn(13))
        let day = { (iso: String) -> Double in PMath.nyDate(iso, minutes: 0).timeIntervalSince1970 / 86400 }
        let d0 = day(start), d1 = max(day(endIso), d0 + 1)
        let topV = max(1, a.base, ser.map(\.cap).max() ?? 0)
        let step = topV > 200_000 ? 50_000.0 : topV > 80_000 ? 25_000.0 : 10_000.0
        let top = ceil(topV / step) * step
        let ticks = stride(from: 0.0, through: top, by: step).map { $0 }
        return GeometryReader { g in
            let W = g.size.width - 48, H: CGFloat = 176
            let X = { (iso: String) -> CGFloat in CGFloat((day(iso) - d0) / (d1 - d0)) * W }
            let Y = { (v: Double) -> CGFloat in H - CGFloat(max(0, min(top, v)) / top) * H }
            let nowX = X(home.today), nowY = Y(a.made)
            // A pace's line from now to the capital, cut at the right edge.
            let paceEnd = { (pace: Double?) -> CGPoint? in
                guard let p = pace, p > 0, !a.done else { return nil }
                let wks = a.left / p, x = X(MarketClock.addDays(home.today, Int((wks * 7).rounded())).iso)
                if x <= W { return CGPoint(x: x, y: Y(a.base)) }
                return CGPoint(x: W, y: nowY + (Y(a.base) - nowY) * (W - nowX) / max(1, x - nowX))
            }
            let e1 = paceEnd(a.start), e2 = paceEnd(a.last4)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    for v in ticks {
                        ctx.fill(Path(CGRect(x: 0, y: Y(v), width: W, height: 1)), with: .color(v == 0 ? S.ink.opacity(0.35) : S.pGrid))
                    }
                    let steps = { (val: (Int) -> Double) -> Path in
                        var p = Path()
                        for (i, r) in ser.enumerated() {
                            let x = X(r.d), y = Y(val(i))
                            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                            else { p.addLine(to: CGPoint(x: x, y: p.currentPoint?.y ?? y)); p.addLine(to: CGPoint(x: x, y: y)) }
                        }
                        return p
                    }
                    // The window between the two paces.
                    if let e1, let e2 {
                        var w = Path(); w.move(to: CGPoint(x: nowX, y: nowY)); w.addLine(to: e1)
                        if e1.x < W { w.addLine(to: CGPoint(x: W, y: e1.y)) }
                        w.addLine(to: e2); w.closeSubpath()
                        ctx.fill(w, with: .color(S.green.opacity(0.10)))
                    }
                    if !ser.isEmpty {
                        var t = steps { ser[$0].cap }
                        t.addLine(to: CGPoint(x: W, y: Y(a.base)))
                        ctx.stroke(t, with: .color(S.pNeutral), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                        let m = steps { ser[$0].made }
                        var f = m; f.addLine(to: CGPoint(x: X(ser.last!.d), y: H)); f.addLine(to: CGPoint(x: X(ser[0].d), y: H)); f.closeSubpath()
                        ctx.fill(f, with: .color(S.green.opacity(0.12)))
                        ctx.stroke(m, with: .color(S.green), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    }
                    if let e1 {
                        var p = Path(); p.move(to: CGPoint(x: nowX, y: nowY)); p.addLine(to: e1)
                        ctx.stroke(p, with: .color(S.green), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))
                    }
                    if let e2 {
                        var p = Path(); p.move(to: CGPoint(x: nowX, y: nowY)); p.addLine(to: e2)
                        ctx.stroke(p, with: .color(S.green.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1.5, 3.5]))
                    }
                    var n = Path(); n.move(to: CGPoint(x: nowX, y: 0)); n.addLine(to: CGPoint(x: nowX, y: H))
                    ctx.stroke(n, with: .color(S.ink.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
                .frame(width: W, height: H)
                Text("Capital in LEAPS · \(F.moneyK(a.base))").sType(SType(size: 11, weight: 600, line: 13, tracking: 0), tabular: false)
                    .foregroundStyle(S.muted).fixedSize()
                    .offset(x: 0, y: max(0, Y(a.base) - 16))
                if let e1, e1.x < W, let w1 {
                    Circle().fill(S.green).frame(width: 10, height: 10).overlay(Circle().stroke(S.paper, lineWidth: 2))
                        .position(e1)
                    Text(Self.long(dateIn(w1))).sType(SType(size: 11, weight: 700, line: 13, tracking: 0), tabular: false)
                        .foregroundStyle(S.green).fixedSize()
                        .position(x: min(e1.x, W - 34), y: e1.y + 14)
                }
                if let e2, let w2 {
                    Text((e2.x >= W - 0.5 ? "4-week pace · " : "") + Self.month(dateIn(w2)) + (e2.x >= W - 0.5 ? " →" : ""))
                        .sType(SType(size: 11, weight: 600, line: 13, tracking: 0), tabular: false)
                        .foregroundStyle(S.muted).fixedSize()
                        .frame(width: W - 4, alignment: .trailing)
                        .offset(y: max(0, min(H - 14, e2.y - 18)))
                }
                ForEach(Array(ticks.enumerated()), id: \.offset) { i, v in
                    Text(F.moneyK(v)).sType(SType(size: 11, weight: 600, line: 12, tracking: 0))
                        .foregroundStyle(S.muted).fixedSize()
                        .position(x: W + 26, y: Y(v))
                }
                Text("Now").sType(SType(size: 12, weight: 700, line: 12, tracking: 0), tabular: false).fixedSize()
                    .position(x: nowX, y: 186)
                ForEach(monthTicks(d0, d1), id: \.self) { iso in
                    let x = X(iso)
                    if abs(x - nowX) > 30 && x > nowX {
                        Text(monthLabel(iso)).sType(SType(size: 12, weight: 600, line: 12, tracking: 0), tabular: false)
                            .foregroundStyle(S.muted).fixedSize().position(x: x, y: 186)
                    }
                }
            }
        }
        .frame(height: 200)
        .accessibilityElement()
        .accessibilityLabel("Payback. \(F.moneyK(a.made)) made of \(F.moneyK(a.base)) in LEAPS.")
    }

    /// "Jan ’27" at a new year, else "Apr".
    private func monthLabel(_ iso: String) -> String {
        let m = Periods.monthNames[(Int(iso.dropFirst(5).prefix(2)) ?? 1) - 1]
        return iso.dropFirst(5).hasPrefix("01") ? "\(m) ’\(iso.dropFirst(2).prefix(2))" : m
    }

    /// Quarter starts after now (Jan, Apr, Jul, Oct), so the labels never touch.
    private func monthTicks(_ d0: Double, _ d1: Double) -> [String] {
        var out: [String] = []
        let f = DateFormatter(); f.timeZone = MarketClock.ny; f.dateFormat = "yyyy-MM"
        var d = Date(timeIntervalSince1970: d0 * 86400)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = MarketClock.ny
        while d.timeIntervalSince1970 / 86400 <= d1 {
            let ym = f.string(from: d); if !out.contains(ym + "-01") { out.append(ym + "-01") }
            d = cal.date(byAdding: .month, value: 1, to: d) ?? d.addingTimeInterval(86400 * 31)
        }
        let inside = out.filter { let x = PMath.nyDate($0, minutes: 0).timeIntervalSince1970 / 86400; return x > d0 + 3 && x < d1 - 3 }
        let q = inside.filter { ["01", "04", "07", "10"].contains(String($0.dropFirst(5).prefix(2))) }
        return q.count >= 2 ? q : inside
    }

    private var insight: (lead: String, rest: String) {
        let a = Self.all(words.payback)
        guard a.base > 0 else { return ("Nothing to pay back yet.", "") }
        let lead = "\(F.moneyK(a.made)) made of \(F.moneyK(a.base)) in LEAPS."
        let rest = a.done ? "The LEAPs are paid for."
            : a.weeks(a.start).map { "At \(F.moneyK(a.start)) a week since the start, paid back by \(Self.long(MarketClock.addDays(words.today, $0 * 7).iso))." } ?? "Not paying back at this pace."
        return (lead, rest)
    }
}
