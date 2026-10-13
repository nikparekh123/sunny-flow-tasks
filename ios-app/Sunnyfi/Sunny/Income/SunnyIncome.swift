//
//  SunnyIncome.swift
//  Sunny
//
//  Blocks 17 and 18 · Income. SunnyWeeklyYield: what selling calls and puts
//  brought in per week or month, the closing cost the light top of each bar,
//  % → $ → time value. SunnyPayback: when the LEAPs pay for themselves, the
//  time value (paid back by selling) and the intrinsic (by the stock
//  rising), each as % of its own target, with the pace and the date.
//

import SwiftUI

// MARK: - Yield

struct SunnyYield: View {
    let home: HomePayload
    let words: HomePayload
    @Environment(HomeRouter.self) private var router
    @State private var mode: PMode = PMode.preset(DebugPreset.string("yield.mode"))
    @State private var hidden: Set<String> = DebugPreset.set("yield.hide")

    private var P: PeriodState { router.period }

    /// One period's sums: sold and closed early per side, in the mode's unit.
    private struct Sums {
        var cs = 0.0, cb = 0.0, ps = 0.0, pb = 0.0, weeks = 0
        var sold: Double { cs + ps }
        var back: Double { cb + pb }
        var any: Bool { weeks > 0 }
    }

    private func value(_ w: YieldWeek) -> (Double, Double, Double, Double) {
        switch mode {
        case .pct:
            let k = w.invested > 0 ? 100 / w.invested : 0
            return (w.callsSold * k, w.callsBack * k, w.putsSold * k, w.putsBack * k)
        case .usd: return (w.callsSold, w.callsBack, w.putsSold, w.putsBack)
        case .tv: return (w.callsSoldTv ?? 0, w.callsBackTv ?? 0, w.putsSoldTv ?? 0, w.putsBackTv ?? 0)
        }
    }
    private func sums(_ rows: [YieldWeek]) -> Sums {
        rows.reduce(into: Sums()) { s, w in
            let v = value(w); s.cs += v.0; s.cb += v.1; s.ps += v.2; s.pb += v.3; s.weeks += 1
        }
    }
    private func fmt(_ v: Double) -> String { mode == .pct ? F.pct(v) : F.moneyK(v) }

    private struct Col { let id: Int; let label: String; let rows: [YieldWeek]; let now: Bool }

    private var cols: [Col] {
        let today = home.today, a = Periods.anchor(P, today: today)
        if P.view == .week {
            let fri = Periods.thisFriday(today)
            return Periods.fridays(a).enumerated().map { i, f in
                Col(id: i, label: "W\(i + 1)", rows: home.yield.filter { $0.fri == f }, now: f == fri)
            }
        }
        return Periods.months(a, start: Periods.bookStart(home)).map { m in
            let ym = String(format: "%@-%02d", a, m + 1)
            return Col(id: m, label: Periods.monthNames[m], rows: home.yield.filter { $0.month == ym }, now: today.hasPrefix(ym))
        }
    }

    var body: some View {
        let cs = cols, pick = P.picked["yield"]
        let shown = pick.map { i in cs.filter { $0.id == i } } ?? cs
        let tot = sums(shown.flatMap(\.rows))
        // Each figure is rounded first, then added, so the hero matches the stat line.
        let r = { (v: Double) in self.mode == .pct ? (v * 100).rounded() / 100 : v.rounded() }
        let net = r(tot.sold) - r(tot.back)
        let per = P.view == .week ? (pick == nil ? 12.0 : 52.0) : (pick == nil ? 12.0 / Double(max(1, Set(shown.flatMap(\.rows).map(\.month)).count)) : 12.0)
        let yr = net * per
        let word = mode == .pct ? "yield" : mode == .usd ? "kept" : "time value"
        let label = Periods.label(P, today: home.today, picked: pick)
        let maxSold = max(1, cs.map { sums($0.rows) }.map { max($0.cs, $0.ps) }.max() ?? 1)
        let h = { (v: Double) -> CGFloat in CGFloat(v / maxSold) * 116 }
        VStack(alignment: .leading, spacing: 20) {
            SPeriodHeader(label: "Yield", hero: tot.any ? fmt(net) : "-", heroValue: net,
                          heroColor: tot.any && net < 0 ? S.red : S.ink, sub: "\(label) · \(word)",
                          onTap: { withAnimation(.smooth(duration: S.roll)) { mode = mode.next } }, period: P,
                          canGoBack: Periods.canGoBack(P, today: home.today, start: Periods.bookStart(home)))
            VStack(alignment: .leading, spacing: 0) {
                if tot.any {
                    SStatLine(items: [(fmt(r(tot.sold)), "sold", S.ink), (fmt(r(tot.back)), "closed early", S.red),
                                      (mode == .pct ? "\(Int(abs(yr).rounded()))%" : F.moneyK(yr), "/ yr", yr < 0 ? S.red : S.ink)])
                } else {
                    SStatLine(items: [("-", "not traded yet", S.ink)])
                }
                SInlineInsight(lead: insight.lead, rest: insight.rest)
            }
            SViewToggle(period: P)
            SBarChart(columns: cs.map { c in
                let s = sums(c.rows)
                let bar = { (sold: Double, back: Double, dark: Color, light: Color, key: String) -> SBar in
                    let kept = max(0, sold - back), top = min(back, sold)
                    return SBar(segs: [.init(value: h(kept), color: dark, hidden: hidden.contains(key)),
                                       .init(value: h(top), color: light, hidden: hidden.contains(key + "b"))],
                                label: c.rows.isEmpty || sold == 0 ? "" : fmt(sold - back),
                                labelColor: sold - back < 0 ? S.red : S.ink)
                }
                return SBarColumn(id: c.id, label: c.label,
                                  bars: [bar(s.cs, s.cb, S.green, S.callsBack, "cs"), bar(s.ps, s.pb, S.blue, S.putsBack, "ps")],
                                  isNow: c.now)
            }, picked: pick) { P.picked["yield"] = $0 }
            SLegend(rows: [("cs", "Calls sold", fmt(tot.cs), S.green), ("csb", "Calls · Closing Cost", fmt(tot.cb), S.callsBack),
                           ("ps", "Puts sold", fmt(tot.ps), S.blue), ("psb", "Puts · Closing Cost", fmt(tot.pb), S.putsBack)],
                    hidden: $hidden)
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sCardSurface()
    }

    /// Yield up or down for N weeks in a row, or against the weeks before.
    private var insight: (lead: String, rest: String) {
        let w = words.yield.filter { $0.fri <= Periods.thisFriday(words.today) }.suffix(6)
        let pct = w.map { $0.invested > 0 ? ($0.callsSold + $0.putsSold - $0.callsBack - $0.putsBack) / $0.invested * 100 : 0 }
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

/// One Payback (Nik, 13 Oct 2026): everything made since the first LEAP (sold
/// premium, puts and calls bought, shares, any close) plus the change in the
/// LEAPs' intrinsic, against the whole LEAP cost. Replaces block 18's two lines
/// (time value by premium, intrinsic by the stocks). Below zero is not drawn.
struct SunnyPayback: View {
    let home: HomePayload
    let words: HomePayload
    @State private var mode: PMode = PMode.preset(DebugPreset.string("pb.mode"))

    private struct All {
        let target: Double, made: Double, intr: Double, pace: Double
        var paid: Double { made + intr }
        var pct: Double { target > 0 ? paid / target * 100 : 0 }
        var weeks: Int? { pace > 0 ? Int(ceil(max(0, target - paid) / pace)) : nil }
        var done: Bool { target > 0 && paid >= target }
    }
    private static func all(_ p: Payback) -> All {
        All(target: p.now.tvT + p.now.inT, made: p.now.allReal ?? p.now.tvPaid, intr: p.now.inPaid,
            pace: p.paceAll ?? (p.paceTv + p.paceIntr))
    }
    private var pb: Payback { home.payback }
    private func dateIn(_ weeks: Int) -> String { MarketClock.addDays(home.today, weeks * 7).iso }
    private func short(_ iso: String) -> String { "\(Int(iso.suffix(2)) ?? 0) \(F.day(iso).prefix(3)) \(iso.dropFirst(2).prefix(2))" }
    private func long(_ iso: String) -> String { "\(Int(iso.suffix(2)) ?? 0) \(F.day(iso).prefix(3)) \(iso.prefix(4))" }

    var body: some View {
        let a = Self.all(pb)
        let none = a.target <= 0
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Payback").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.muted)
                Button { withAnimation(.smooth(duration: S.roll)) { mode = mode.next } } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(none ? "-" : hero(a)).sType(.largeNumber)
                            .foregroundStyle(none ? S.ink : a.paid < 0 ? S.red : S.green)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(none ? "nothing to pay back" : heroSub(a))
                            .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                            .foregroundStyle(S.muted).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SPressStyle())
            }
            if none {
                SStatLine(items: [("-", "no LEAPs held", S.ink)])
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    SStatLine(items: [(F.moneyK(a.pace), "/ wk", a.pace < 0 ? S.red : S.green)]
                              + (a.done ? [("", "paid back", S.green)]
                                 : a.weeks.map { [(short(dateIn($0)), "paid back", S.ink)] } ?? [("no date", "at this pace", S.ink)]))
                    SInlineInsight(lead: insight.lead, rest: insight.rest)
                }
                chart(a)
                VStack(spacing: 0) {
                    row("Made", F.moneyK(a.made), a.made < 0 ? S.red : S.ink, S.green,
                        "everything realized since the first LEAP")
                    row("Intrinsic", F.moneyK(a.intr), a.intr < 0 ? S.red : S.ink, S.blue,
                        "the stocks' move since each LEAP was bought")
                }
            }
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sCardSurface()
    }

    private func hero(_ a: All) -> String {
        switch mode {
        case .pct: return Self.pct(a.pct)
        case .usd: return PF.usd(a.paid)
        case .tv: return a.done ? "done" : a.weeks.map { "\($0) wk" } ?? "-"
        }
    }
    private func heroSub(_ a: All) -> String {
        switch mode {
        case .pct: return "of the LEAP cost paid back"
        case .usd: return "of \(F.moneyK(a.target)) the LEAPs cost"
        case .tv: return a.done ? "paid back" : a.weeks.map { "paid back by \(long(dateIn($0)))" } ?? "no date at this pace"
        }
    }

    /// "42%", "18.6%", "100%": one place, no trailing .0, no minus sign.
    static func pct(_ v: Double) -> String {
        let r = (abs(v) * 10).rounded() / 10
        return (r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)) + "%"
    }

    private func row(_ name: String, _ value: String, _ tone: Color, _ dot: Color, _ note: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(name).sType(SType(size: 15, weight: 600, line: 15, tracking: 0), tabular: false)
                Spacer()
                Text(value).sType(SType(size: 15, weight: 700, line: 15, tracking: 0)).foregroundStyle(tone)
            }
            Text(note).sType(SType(size: 13, weight: 500, line: 13, tracking: 0), tabular: false)
                .foregroundStyle(S.muted).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 60)
        .overlay(alignment: .bottom) { Rectangle().fill(S.pGrid).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    // MARK: Chart

    private func chart(_ a: All) -> some View {
        let ser = pb.series.compactMap { r -> (d: String, pct: Double)? in
            guard r.count >= 5, let d = r[0].string else { return nil }
            let target = (r[1].number ?? 0) + (r[3].number ?? 0)
            let made = r.count >= 6 ? (r[5].number ?? 0) : (r[2].number ?? 0)
            return (d, target > 0 ? (made + (r[4].number ?? 0)) / target * 100 : 0)
        }
        let start = ser.first?.d ?? home.today
        let endIso = ([home.today] + [a.weeks.map { min(dateIn($0), dateIn(52)) }].compactMap { $0 }).max()!
        let day = { (iso: String) -> Double in PMath.nyDate(iso, minutes: 0).timeIntervalSince1970 / 86400 }
        let d0 = day(start), d1 = max(day(endIso), d0 + 1)
        return GeometryReader { g in
            let W = g.size.width - 44, H: CGFloat = 176
            let X = { (iso: String) -> CGFloat in CGFloat((day(iso) - d0) / (d1 - d0)) * W }
            let Y = { (pct: Double) -> CGFloat in H - CGFloat(max(0, min(100, pct)) / 100) * H }
            let nowX = X(home.today)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    for i in 0..<5 {
                        let y = CGFloat(i) / 4 * H
                        ctx.fill(Path(CGRect(x: 0, y: y, width: W, height: 1)), with: .color(i == 0 ? S.ink.opacity(0.35) : S.pGrid))
                    }
                    if !ser.isEmpty {
                        var p = Path()
                        for (i, r) in ser.enumerated() {
                            let x = X(r.d), y = Y(r.pct)
                            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                            else { p.addLine(to: CGPoint(x: x, y: p.currentPoint?.y ?? y)); p.addLine(to: CGPoint(x: x, y: y)) }
                        }
                        var f = p; f.addLine(to: CGPoint(x: X(ser.last!.d), y: H)); f.addLine(to: CGPoint(x: X(ser[0].d), y: H)); f.closeSubpath()
                        ctx.fill(f, with: .linearGradient(Gradient(colors: [S.green.opacity(0.22), S.green.opacity(0)]),
                                                          startPoint: .zero, endPoint: CGPoint(x: 0, y: H)))
                        ctx.stroke(p, with: .color(S.green), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    }
                    // At the current pace to 100%.
                    if let w = a.weeks, !a.done {
                        var p = Path(); p.move(to: CGPoint(x: nowX, y: Y(a.pct))); p.addLine(to: CGPoint(x: X(dateIn(w)), y: Y(100)))
                        ctx.stroke(p, with: .color(S.green.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4]))
                    }
                    var n = Path(); n.move(to: CGPoint(x: nowX, y: 0)); n.addLine(to: CGPoint(x: nowX, y: H))
                    ctx.stroke(n, with: .color(S.ink.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    // A new LEAP raises the target: a small mark on its day.
                    for d in pb.newLeapDays ?? [] where d >= start {
                        ctx.fill(Path(CGRect(x: X(d) - 0.75, y: H - 6, width: 1.5, height: 6)), with: .color(S.muted.opacity(0.6)))
                    }
                }
                .frame(width: W, height: H)
                if let w = a.weeks, !a.done {
                    Circle().fill(S.green).frame(width: 10, height: 10).overlay(Circle().stroke(S.paper, lineWidth: 2))
                        .position(x: X(dateIn(w)), y: 0)
                }
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach([100, 75, 50, 25, 0], id: \.self) { v in
                        Text("\(v)%").sType(SType(size: 11, weight: 600, line: 12, tracking: 0)).foregroundStyle(S.muted)
                        if v > 0 { Spacer(minLength: 0) }
                    }
                }
                .frame(width: 40, height: H + 12, alignment: .trailing)
                .offset(x: W + 4, y: -6)
                Text("Now").sType(SType(size: 12, weight: 600, line: 12, tracking: 0), tabular: false).fixedSize()
                    .position(x: nowX, y: 186)
                ForEach(monthTicks(d0, d1), id: \.self) { iso in
                    let x = X(iso)
                    if abs(x - nowX) > 28 {
                        Text(Periods.monthNames[(Int(iso.dropFirst(5).prefix(2)) ?? 1) - 1])
                            .sType(SType(size: 12, weight: 600, line: 12, tracking: 0), tabular: false)
                            .foregroundStyle(S.muted).fixedSize().position(x: x, y: 186)
                    }
                }
            }
        }
        .frame(height: 200)
        .accessibilityElement()
        .accessibilityLabel("Payback. \(Self.pct(a.pct)) of the LEAP cost \(a.paid < 0 ? "behind" : "paid back").")
    }

    private func monthTicks(_ d0: Double, _ d1: Double) -> [String] {
        var out: [String] = []
        let f = DateFormatter(); f.timeZone = MarketClock.ny; f.dateFormat = "yyyy-MM"
        var d = Date(timeIntervalSince1970: d0 * 86400)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = MarketClock.ny
        while d.timeIntervalSince1970 / 86400 <= d1 {
            let ym = f.string(from: d); if !out.contains(ym + "-01") { out.append(ym + "-01") }
            d = cal.date(byAdding: .month, value: 1, to: d) ?? d.addingTimeInterval(86400 * 31)
        }
        return out.filter { let x = PMath.nyDate($0, minutes: 0).timeIntervalSince1970 / 86400; return x > d0 + 3 && x < d1 - 3 }
    }

    /// Ahead or behind, and whether the pace closes the gap.
    private var insight: (lead: String, rest: String) {
        let a = Self.all(words.payback)
        guard a.target > 0 else { return ("Nothing to pay back yet.", "") }
        let lead = a.paid >= 0 ? "\(Self.pct(a.pct)) of the LEAPs paid back." : "\(F.moneyK(a.paid)) behind on the LEAPs."
        let rest = a.pace > 0
            ? "At \(F.moneyK(a.pace)) a week, done in \(a.weeks ?? 0) weeks."
            : "Income is \(F.moneyK(a.made)) so far, but the stocks are \(F.moneyK(a.intr)) under where the LEAPs were bought."
        return (lead, rest)
    }
}
