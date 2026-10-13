//
//  SunnyResults.swift
//  Sunny
//
//  Blocks 19, 20, 21 and 23 · Results. SunnySoldBought: longs' change in
//  value (ink) against what selling kept after buybacks (yellow), per week
//  or month, from one zero line, with the sentence. SunnyPerformance: the
//  names ranked by the period, each bar split by position type, losses left
//  of zero, with filters and the yellow summary box. SunnyAllocation: the
//  biggest holding, a segment bar and the rows.
//

import SwiftUI

// MARK: - Sold vs Bought

struct SunnySoldBought: View {
    let home: HomePayload
    @Environment(HomeRouter.self) private var router
    private var P: PeriodState { router.period }

    private struct Agg { var chg = 0.0, real = 0.0, n = 0 }
    private struct Col { let id: Int; let label: String; let agg: Agg?; let now: Bool }

    private var rows: [(d: String, chg: Double, real: Double)] {
        home.soldVsBought.days.compactMap { r in
            guard r.count >= 3, let d = r[0].string else { return nil }
            return (d, r[1].number ?? 0, r[2].number ?? 0)
        }
    }
    private func agg(_ xs: [(d: String, chg: Double, real: Double)]) -> Agg? {
        guard !xs.isEmpty else { return nil }
        return xs.reduce(into: Agg()) { $0.chg += $1.chg; $0.real += $1.real; $0.n += 1 }
    }
    private var cols: [Col] {
        let today = home.today, a = Periods.anchor(P, today: today), r = rows
        if P.view == .week {
            let fri = Periods.thisFriday(today)
            return Periods.fridays(a).enumerated().map { i, f in
                let mon = MarketClock.addDays(f, -4).iso
                return Col(id: i, label: "W\(i + 1)", agg: agg(r.filter { $0.d >= mon && $0.d <= f }), now: f == fri)
            }
        }
        return (0..<12).map { m in
            let ym = String(format: "%@-%02d", a, m + 1)
            return Col(id: m, label: Periods.monthNames[m], agg: agg(r.filter { $0.d.hasPrefix(ym) }), now: today.hasPrefix(ym))
        }
    }
    /// To the nearest 100 above $1K.
    private func q(_ v: Double) -> Double { abs(v) >= 1000 ? (v / 100).rounded() * 100 : v.rounded() }

    var body: some View {
        let cs = cols, pick = P.picked["svb"]
        let shown = pick.map { i in cs.filter { $0.id == i } } ?? cs
        let X = shown.compactMap(\.agg).reduce(nil as Agg?) { acc, a in var x = acc ?? Agg(); x.chg += a.chg; x.real += a.real; x.n += a.n; return x }
        let net = X.map { q($0.chg) + q($0.real) } ?? 0
        let current = pick.map { i in cs.first { $0.id == i }?.now ?? false } ?? (P.back == 0)
        let label = Periods.label(P, today: home.today, picked: pick)
        let unit = pick != nil ? (P.view == .week ? "week" : "month") : (P.view == .week ? "month" : "year")
        let s = sentence(X, unit: unit, current: current)
        VStack(alignment: .leading, spacing: 20) {
            SPeriodHeader(label: "Sold vs Bought", hero: X == nil ? "-" : F.moneyK(net), heroValue: net,
                          heroColor: X == nil ? S.ink : net < 0 ? S.red : S.green,
                          sub: "\(label) · net" + (current && X != nil ? " · \(F.moneyK(home.soldVsBought.openCredit)) open" : ""),
                          onTap: {}, period: P)
            VStack(alignment: .leading, spacing: 0) {
                if let X {
                    SStatLine(items: [(F.moneyK(q(X.chg)), X.chg < 0 ? "longs lost" : "longs added", X.chg < 0 ? S.red : S.green),
                                      (F.moneyK(q(X.real)), X.real < 0 ? "shorts cost" : "shorts kept", X.real < 0 ? S.red : S.green)])
                } else {
                    SStatLine(items: [("-", "not traded yet", S.ink)])
                }
                SInlineInsight(lead: s.lead, rest: s.rest)
            }
            SViewToggle(period: P)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    legendDot(S.ink, "Bought")
                    legendDot(S.deckYellow, "Sold, net of closes")
                }
                chart(cs, pick: pick)
            }
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sCardSurface()
    }

    private func legendDot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(t).sType(SType(size: 12, weight: 600, line: 14, tracking: 0), tabular: false).foregroundStyle(S.muted)
        }
    }

    /// Black then yellow per period from one zero line; above made money,
    /// below lost it; the label at each bar's end, red below.
    private func chart(_ cs: [Col], pick: Int?) -> some View {
        let vals = cs.compactMap(\.agg).flatMap { [$0.chg, $0.real] }
        let pos = max(0, vals.max() ?? 0), neg = max(0, -(vals.min() ?? 0))
        let K = 130 / max(1, pos + neg)
        let upH = (pos * K).rounded() + (pos > 0 ? 16 : 0), dnH = (neg * K).rounded() + (neg > 0 ? 16 : 0)
        let bar = { (v: Double) -> CGFloat in v == 0 ? 0 : max(3, CGFloat((abs(v) * K).rounded())) }
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 40) {
                    ForEach(cs, id: \.id) { c in
                        let fade = pick != nil && pick != c.id
                        Button { withAnimation(S.standard(0.35)) { P.picked["svb"] = pick == c.id ? nil : c.id } } label: {
                            VStack(spacing: 0) {
                                HStack(alignment: .bottom, spacing: 6) {
                                    ForEach(0..<2, id: \.self) { j in
                                        let v = j == 0 ? (c.agg?.chg ?? 0) : (c.agg?.real ?? 0)
                                        VStack(spacing: 4) {
                                            if v > 0 { Text(F.moneyK(v)).sType(SType(size: 11, weight: 600, line: 12, tracking: 0)).fixedSize() }
                                            UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 1, bottomTrailingRadius: 1, topTrailingRadius: 5)
                                                .fill(j == 0 ? S.ink : S.deckYellow).frame(height: v > 0 ? bar(v) : 0)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                                .frame(height: CGFloat(upH), alignment: .bottom)
                                Rectangle().fill(S.muted.opacity(0.35)).frame(height: 1).padding(.horizontal, -20)
                                HStack(alignment: .top, spacing: 6) {
                                    ForEach(0..<2, id: \.self) { j in
                                        let v = j == 0 ? (c.agg?.chg ?? 0) : (c.agg?.real ?? 0)
                                        VStack(spacing: 4) {
                                            UnevenRoundedRectangle(topLeadingRadius: 1, bottomLeadingRadius: 5, bottomTrailingRadius: 5, topTrailingRadius: 1)
                                                .fill(j == 0 ? S.ink : S.deckYellow).frame(height: v < 0 ? bar(v) : 0)
                                            if v < 0 { Text(F.moneyK(v)).sType(SType(size: 11, weight: 600, line: 12, tracking: 0)).foregroundStyle(S.red).fixedSize() }
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                                .frame(height: CGFloat(dnH), alignment: .top)
                                Text(c.label).sType(SType(size: 12, weight: c.now ? 700 : 600, line: 12, tracking: 0), tabular: false)
                                    .foregroundStyle(c.now ? S.ink : S.muted).frame(height: 14).padding(.top, 12)
                            }
                            .frame(width: 80)
                            .background {
                                if c.now { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(S.pGrid).padding(.horizontal, -12).padding(.top, -10).padding(.bottom, -8) }
                            }
                            .opacity(fade ? 0.35 : 1)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(c.id)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
            .onAppear { if let n = cs.first(where: \.now)?.id { proxy.scrollTo(n, anchor: .center) } }
        }
    }

    /// The sentence, picked by the two signs (block 19).
    private func sentence(_ X: Agg?, unit: String, current: Bool) -> (lead: String, rest: String) {
        guard let X else { return ("Nothing yet.", "No trades in this \(unit).") }
        let g = F.moneyK(X.chg), r = F.moneyK(X.real), d = F.moneyK(X.chg + X.real)
        let tail = current ? " so far, with \(F.moneyK(home.soldVsBought.openCredit)) still open." : "."
        if X.chg > 0 && X.real < 0 {
            if X.chg / -X.real >= 1 {
                return ("Worth it.", "What you own gained \(g) (unrealized). Buying back what you sold cost \(r) (realized). You’re \(d) ahead" + tail)
            }
            return ("Paid more than it made.", "Buybacks cost \(r) (realized), more than the \(g) gain on what you own (unrealized). You’re \(d) behind" + tail)
        }
        if X.chg >= 0 { return ("Both sides up.", "What you own gained \(g) (unrealized) and you kept \(r) of what you sold (realized)" + tail) }
        if X.real >= 0 {
            let pct = X.chg != 0 ? Int((X.real / -X.chg * 100).rounded()) : 0
            return ("Cushioned.", "What you own fell \(g) (unrealized). You kept \(r) of what you sold (realized), \(pct)% of the drop" + tail)
        }
        return ("Rough \(unit).", "What you own fell \(g) (unrealized) and buybacks cost \(r) (realized)" + tail)
    }
}

// MARK: - Performance

struct SunnyPerformance: View {
    let words: HomePayload
    @State private var realized = true
    @State private var unrealized = false
    @State private var period: Int?          // nil = YTD, else a month index
    @State private var types: Set<String> = []
    @State private var focus: String?
    @State private var started = false

    private struct T { let key: String; let name: String; let color: Color }
    private static let types: [T] = [
        T(key: "calls sold", name: "Calls sold", color: Color(hex: 0x3B873D)), T(key: "puts sold", name: "Puts sold", color: Color(hex: 0x366DEB)),
        T(key: "calls bought", name: "Calls bought", color: Color(hex: 0x65C466)), T(key: "puts bought", name: "Puts bought", color: Color(hex: 0x73B6F9)),
        T(key: "shares", name: "Shares", color: Color(hex: 0xF2A93B)),
    ]

    /// Months from the first with data to now (yyyy-MM).
    private var months: [String] {
        let all = (words.performance.realized + words.performance.unrealized).compactMap { $0.first?.string }
        let first = all.min() ?? String(words.today.prefix(7)), last = String(words.today.prefix(7))
        var out: [String] = [], m = first
        while m <= last {
            out.append(m)
            let y = Int(m.prefix(4))!, mo = Int(m.suffix(2))!
            m = String(format: "%04d-%02d", mo == 12 ? y + 1 : y, mo == 12 ? 1 : mo + 1)
        }
        return out
    }
    private func on(_ k: String) -> Bool { types.isEmpty || types.contains(k) }

    /// ticker -> type -> month -> $
    private var data: [String: [String: [String: Double]]] {
        var d: [String: [String: [String: Double]]] = [:]
        let add = { (rows: [[Scalar]]) in
            for r in rows where r.count >= 4 {
                guard let m = r[0].string, let t = r[1].string, let k = r[2].string, let v = r[3].number else { continue }
                d[t, default: [:]][k, default: [:]][m, default: 0] += v
            }
        }
        if realized { add(words.performance.realized) }
        if unrealized { add(words.performance.unrealized) }
        return d
    }

    typealias Ranked = (t: String, segs: [(Double, Color, String)], up: Double, dn: Double)

    private static func value(_ D: [String: [String: [String: Double]]], _ t: String, _ k: String, _ per: String?) -> Double {
        let byM: [String: Double] = D[t]?[k] ?? [:]
        if let per { return byM[per] ?? 0 }
        return byM.values.reduce(0, +)
    }
    private func monthNet(_ D: [String: [String: [String: Double]]], _ t: String, _ m: String) -> Double {
        var s = 0.0
        for ty in Self.types where on(ty.key) { s += D[t]?[ty.key]?[m] ?? 0 }
        return s
    }
    private func rank(_ D: [String: [String: [String: Double]]], _ per: String?) -> [Ranked] {
        var out: [Ranked] = []
        for t in D.keys {
            var segs: [(Double, Color, String)] = []
            for ty in Self.types where on(ty.key) { segs.append((Self.value(D, t, ty.key, per), ty.color, ty.name)) }
            let up = segs.reduce(0.0) { $0 + max(0, $1.0) }, dn = segs.reduce(0.0) { $0 + max(0, -$1.0) }
            if up + dn > 0.5 { out.append((t, segs, up, dn)) }
        }
        return out.sorted { ($0.up - $0.dn) > ($1.up - $1.dn) }
    }

    var body: some View {
        let ms = months, D = data
        let per = period.flatMap { ms[safe: $0] }
        let pv: (String, String) -> Double = { t, k in Self.value(D, t, k, per) }
        let net: (String, String) -> Double = { t, m in self.monthNet(D, t, m) }
        let list = rank(D, per)
        let none = !realized && !unrealized
        let tot: Double = list.reduce(0.0) { $0 + $1.up - $1.dn }
        let series: [Double] = ms.map { m in D.keys.reduce(0.0) { $0 + monthNet(D, $1, m) } }
        let pIdx = period
        let prev: Double? = pIdx.flatMap { $0 > 0 ? series[$0 - 1] : nil }
        let delta = prev.map { tot - $0 }
        let pctRaw = prev.flatMap { abs($0) >= 100 ? Int((abs(delta!) / abs($0) * 100).rounded()) : nil }
        let pct = pctRaw.flatMap { $0 <= 300 ? $0 : nil }
        let ytd = series.reduce(0, +)
        let bestIx = series.indices.max { series[$0] < series[$1] } ?? 0
        let monthName = { (ym: String) in Periods.monthNames[(Int(ym.suffix(2)) ?? 1) - 1] }
        let mu = max(1, list.map(\.up).max() ?? 1), md = max(0, list.map(\.dn).max() ?? 0), span = mu + md
        let x0 = md / span
        let year = String(words.today.prefix(4))
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Performance").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.muted)
                VStack(alignment: .leading, spacing: 6) {
                    Text(none ? "$0" : F.moneyK(tot)).sType(.largeNumber).foregroundStyle(tot < 0 ? S.red : S.ink)
                        .contentTransition(.numericText(value: tot))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(per.map { "\(monthName($0).uppercased()) \($0.prefix(4))" } ?? "YTD \(year)")
                            .sType(SType(size: 15, weight: 600, line: 20, tracking: 0.02), tabular: false)
                        Text(per == nil ? "\(ms.first.map(monthName) ?? "Jan") to \(ms.last.map(monthName) ?? "")"
                             : delta == nil ? "first month on record"
                             : "vs \(monthName(ms[pIdx! - 1]).uppercased()) · \(F.moneyDelta(delta!))" + (pct.map { " · \($0)%" } ?? ""))
                            .sType(SType(size: 13, weight: 600, line: 16, tracking: 0))
                            .foregroundStyle(per == nil || delta == nil ? S.muted : delta! < 0 ? S.red : S.green)
                            .lineLimit(1)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                let n = Double(max(1, ms.count))
                let lossMonths = series[bestIx] < 0
                if unrealized && !realized {
                    SStatLine(items: [(F.moneyK(ytd), "open", ytd < 0 ? S.red : S.ink),
                                      (ms.isEmpty ? "-" : monthName(ms[bestIx]), lossMonths ? "least open loss" : "best month opened", lossMonths ? S.red : S.green)])
                } else {
                    SStatLine(items: [(F.moneyK(ytd), "ytd", ytd < 0 ? S.red : S.ink), (F.moneyK(ytd / n), "per mo", ytd < 0 ? S.red : S.ink),
                                      (ms.isEmpty ? "-" : monthName(ms[bestIx]), lossMonths ? "smallest loss" : "best month", lossMonths ? S.red : S.green)])
                }
                SInlineInsight(lead: list.first.map { "\($0.t) \(unrealized && !realized ? "leads your open book." : "is your best performer.")" } ?? "Nothing yet.",
                               rest: "Companies rank by the period you pick. The strip on each row shows each month. Tap a row to focus on it.")
            }
            filters(ms)
            summaryBox(list: list, perLabel: per.map { "in \(monthName($0))" } ?? "this year", none: none, ms: ms, net: net, pv: pv)
            leaderboard(list, x0: x0, span: span, ms: ms, net: net, col: per.map(monthName) ?? "YTD",
                        colA: (per.map(monthName) ?? "Year to date") + " by position")
            legend(list: list, pv: pv, label: (focus ?? "All companies") + " · " + (per.map(monthName) ?? "YTD"))
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sCardSurface(glow: unrealized)
        .onAppear { if !started { started = true; period = months.count - 1 } }
    }

    // Filters: Realized · Unrealized, position types, then the period.
    private func filters(_ ms: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            chipRow {
                chip("Realized", on: realized) { realized.toggle() }
                chip("Unrealized", on: unrealized) { unrealized.toggle() }
            }
            chipRow {
                chip("All", on: types.isEmpty) { types = [] }
                ForEach(Self.types, id: \.key) { t in
                    chip(t.name, on: types.contains(t.key), dot: t.color, dotOn: on(t.key)) {
                        if types.contains(t.key) { types.remove(t.key) } else { types.insert(t.key) }
                        if types.count >= Self.types.count { types = [] }
                    }
                }
            }
            Rectangle().fill(S.line).frame(height: 1).padding(.vertical, 6)
            ScrollViewReader { proxy in
                chipRow {
                    chip("YTD", on: period == nil) { period = nil }
                    ForEach(Array(ms.enumerated()), id: \.offset) { i, m in
                        chip(Periods.monthNames[(Int(m.suffix(2)) ?? 1) - 1], on: period == i) { period = i }.id(i)
                    }
                }
                .onAppear { proxy.scrollTo(ms.count - 1, anchor: .trailing) }
            }
        }
    }

    private func chipRow<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        ScrollView(.horizontal) { HStack(spacing: 6) { c() }.padding(.vertical, 8) }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20).padding(.vertical, -8)
    }

    private func chip(_ t: String, on: Bool, dot: Color? = nil, dotOn: Bool = true, tap: @escaping () -> Void) -> some View {
        Button { withAnimation(S.standard(0.3)) { focus = nil; tap() } } label: {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8).opacity(dotOn ? 1 : 0.35) }
                Text(t).sType(.label, tabular: false)
            }
            .foregroundStyle(on ? S.chipOnInk : S.ink)
            .padding(.horizontal, 12).frame(height: 32)
            .background { if on { Capsule().fill(S.chipOn) } }
            .glassEffect(on ? .identity : .regular.interactive(), in: .capsule)
        }
        .buttonStyle(SPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func summaryBox(list: [(t: String, segs: [(Double, Color, String)], up: Double, dn: Double)], perLabel: String, none: Bool,
                            ms: [String], net: (String, String) -> Double, pv: (String, String) -> Double) -> some View {
        let ctxTypes: String = {
            let k = types.sorted().joined(separator: ",")
            if types.isEmpty { return "All positions" }
            if k == "calls sold,puts sold" { return "Calls + puts sold" }
            if k == "calls bought,puts bought" { return "Calls + puts bought" }
            if k == "calls bought,calls sold" { return "All calls" }
            if k == "puts bought,puts sold" { return "All puts" }
            let names = Self.types.filter { types.contains($0.key) }.map(\.name)
            return names.count == 1 ? names[0] : names.count == 2 ? names[0] + " + " + names[1].lowercased() : "\(names.count) position types"
        }()
        let head = none ? "Nothing selected"
            : [focus, period.flatMap { ms[safe: $0] }.map { Periods.monthNames[(Int($0.suffix(2)) ?? 1) - 1] } ?? "YTD",
               realized && unrealized ? "Realized + unrealized" : realized ? "Realized" : "Unrealized", ctxTypes].compactMap { $0 }.joined(separator: " · ")
        let typeTotals = Self.types.filter { on($0.key) }.map { t -> (String, Double) in
            (t.name, focus.map { pv($0, t.key) } ?? list.reduce(0) { $0 + pv($1.t, t.key) })
        }
        let topT = typeTotals.max { $0.1 < $1.1 }
        let money = { (v: Double) -> Text in Text(F.moneyK(v)).fontWeight(.semibold).foregroundColor(v < 0 ? S.red : S.yellowInk) }
        var sentence = Text("")
        if none {
            sentence = Text("Turn on Realized or Unrealized to see how your positions performed.")
        } else if let f = focus, let r = list.first(where: { $0.t == f }) {
            let v = r.up - r.dn
            let best = ms.indices.max { net(f, ms[$0]) < net(f, ms[$1]) }.map { Periods.monthNames[(Int(ms[$0].suffix(2)) ?? 1) - 1] } ?? ""
            sentence = Text(f).fontWeight(.semibold) + Text(v < 0 ? " lost " : " made ") + money(v)
                + Text(" \(perLabel), mostly \(topT?.0.lowercased() ?? "") (") + money(topT?.1 ?? 0) + Text("). Best month \(best).")
        } else if let top = list.first, let bot = list.last {
            sentence = Text(top.t).fontWeight(.semibold) + Text(" led \(perLabel) with ") + money(top.up - top.dn) + Text(", ")
                + Text(bot.t).fontWeight(.semibold) + Text(bot.up - bot.dn < 0 ? " lost " : " trailed at ") + money(bot.up - bot.dn)
                + Text(". Mostly \(topT?.0.lowercased() ?? ""), ") + money(topT?.1 ?? 0) + Text(".")
        } else {
            sentence = Text("Nothing closed \(perLabel) yet.")
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(head).sType(SType(size: 12, weight: 700, line: 16, tracking: 0), tabular: false).lineLimit(2)
            sentence.sType(SType(size: 13, weight: 400, line: 18, tracking: 0)).lineLimit(2)
        }
        .foregroundStyle(S.yellowInk)
        .padding(.top, 12).padding(.bottom, 13).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(S.yellowTint))
        .id(head)
        .transition(.opacity)
    }

    private func leaderboard(_ list: [(t: String, segs: [(Double, Color, String)], up: Double, dn: Double)], x0: Double, span: Double,
                             ms: [String], net: @escaping (String, String) -> Double, col: String, colA: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                Color.clear.frame(width: 40)
                Text(colA).frame(maxWidth: .infinity, alignment: .leading)
                Text("Trend").frame(width: 54, alignment: .leading)
                Text(col).frame(width: 52, alignment: .trailing)
            }
            .sType(SType(size: 11, weight: 600, line: 12, tracking: 0), tabular: false)
            .foregroundStyle(S.muted)
            .padding(.bottom, 6)
            ForEach(list, id: \.t) { r in
                let v = r.up - r.dn
                Button { withAnimation(S.standard(0.3)) { focus = focus == r.t ? nil : r.t } } label: {
                    HStack(spacing: 10) {
                        Text(r.t).sType(SType(size: 12, weight: 700, line: 14, tracking: 0), tabular: false).frame(width: 40, alignment: .leading)
                        GeometryReader { g in
                            let w = g.size.width, zx = CGFloat(x0) * w
                            ZStack(alignment: .leading) {
                                Rectangle().fill(S.line).frame(width: 1, height: 26).offset(x: zx, y: 0)
                                HStack(spacing: 0) {
                                    ForEach(Array(r.segs.filter { $0.0 > 0 }.enumerated()), id: \.offset) { _, s in
                                        Rectangle().fill(s.1).frame(width: CGFloat(s.0 / span) * w)
                                    }
                                }
                                .frame(height: 12)
                                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 6, topTrailingRadius: 6))
                                .offset(x: zx)
                                UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, bottomTrailingRadius: 0, topTrailingRadius: 0)
                                    .fill(S.red).frame(width: CGFloat(r.dn / span) * w, height: 12)
                                    .offset(x: zx - CGFloat(r.dn / span) * w)
                            }
                            .frame(height: 12)
                            .frame(maxHeight: .infinity)
                        }
                        .frame(height: 26)
                        spark(r.t, ms: ms, net: net)
                        Text(F.moneyK(v)).sType(SType(size: 13, weight: 700, line: 16, tracking: 0))
                            .foregroundStyle(v < 0 ? S.red : S.ink).frame(width: 52, alignment: .trailing)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(focus == r.t ? S.surface : .clear))
                    .padding(.horizontal, -8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(r.t) \(v < 0 ? "lost" : "made") \(F.moneyK(v))")
            }
        }
    }

    /// A small bar per month: the picked month full, the rest at 30%.
    private func spark(_ t: String, ms: [String], net: (String, String) -> Double) -> some View {
        let nets = ms.map { net(t, $0) }
        let mu = max(0, nets.max() ?? 0), md = max(0, -(nets.min() ?? 0)), sp = max(1, mu + md), PV: CGFloat = 20
        let hU = mu + md > 0 ? (PV * CGFloat(mu / sp)).rounded() : PV
        let h = { (x: Double) -> CGFloat in x == 0 ? 0 : max(2, (CGFloat(abs(x) / sp) * PV).rounded()) }
        return VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(nets.enumerated()), id: \.offset) { i, x in
                    RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: 0x3B873D)).frame(width: 4, height: x > 0 ? h(x) : 0)
                        .opacity(period == nil || period == i ? 1 : 0.3)
                    if i < nets.count - 1 { Spacer(minLength: 0) }
                }
            }
            .frame(height: hU, alignment: .bottom)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(nets.enumerated()), id: \.offset) { i, x in
                    RoundedRectangle(cornerRadius: 1.5).fill(S.red).frame(width: 4, height: x < 0 ? h(x) : 0)
                        .opacity(period == nil || period == i ? 1 : 0.3)
                    if i < nets.count - 1 { Spacer(minLength: 0) }
                }
            }
            .frame(height: PV - hU, alignment: .top)
        }
        .frame(width: 54)
    }

    private func legend(list: [(t: String, segs: [(Double, Color, String)], up: Double, dn: Double)], pv: @escaping (String, String) -> Double, label: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label).sType(SType(size: 12, weight: 600, line: 14, tracking: 0), tabular: false).foregroundStyle(S.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), alignment: .leading, spacing: 14) {
                ForEach(Self.types.filter { on($0.key) }, id: \.key) { t in
                    let v = focus.map { pv($0, t.key) } ?? list.reduce(0) { $0 + pv($1.t, t.key) }
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2).fill(t.color).frame(width: 4)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.name).sType(SType(size: 13, weight: 400, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted).lineLimit(1)
                            Text(v == 0 ? "-" : F.moneyK(v)).sType(SType(size: 15, weight: 700, line: 15, tracking: 0))
                                .foregroundStyle(v < 0 ? S.red : S.ink)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Allocation

struct SunnyAllocation: View {
    let home: HomePayload
    let words: HomePayload
    @State private var dollars = false
    @State private var picked: String?
    @State private var more = false

    private static let palette: [Color] = [0x3B873D, 0x65C466, 0x366DEB, 0x73B6F9, 0xF7CE46, 0x996C23, 0x6E6E73].map { Color(hex: $0) }

    var body: some View {
        // Share of what: value now (Nik took the proposal). Cash stays out of the three numbers.
        let hs = home.allocation.holdings.filter { $0.now > 0 }.sorted { $0.now > $1.now }
        let cash = max(0, home.allocation.cash ?? 0)
        let items: [(name: String, usd: Double, color: Color)] = hs.enumerated().map { i, h in (h.ticker, h.now, Self.palette[i % Self.palette.count]) }
            + (cash > 0 ? [("Cash", cash, S.ink)] : [])
        let total = max(1, items.reduce(0) { $0 + $1.usd })
        let hMax = items.map(\.usd).max() ?? 1
        let lead = items.first
        let sel = picked.flatMap { p in items.first { $0.name == p } }
        let hero = sel ?? lead
        let pct = { (v: Double) -> String in v / total * 100 < 1 ? "<1%" : String(format: "%.1f%%", v / total * 100) }
        let top3 = items.filter { $0.name != "Cash" }.prefix(3).reduce(0) { $0 + $1.usd }
        let invested = hs.reduce(0) { $0 + $1.invested }, now = hs.reduce(0) { $0 + $1.now }, diff = now - invested
        let shown = more ? items : Array(items.prefix(4))
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Allocation").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.muted)
                Button { withAnimation(.smooth(duration: S.roll)) { dollars.toggle() } } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let h = hero {
                            Text("\(dollars ? F.moneyK(h.usd) : pct(h.usd)) in \(h.name)").sType(.largeNumber)
                                .foregroundStyle(sel == nil && h.usd / total > 0.3 ? S.red : S.ink)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        } else {
                            Text("-").sType(.largeNumber)
                        }
                        Text(sel.map { "\(dollars ? pct($0.usd) : F.moneyK($0.usd)) · #\((items.firstIndex { $0.name == sel!.name } ?? 0) + 1) of \(items.count)" }
                             ?? "\(items.count) \(items.count == 1 ? "holding" : "holdings") · top 3 = \(Int((top3 / total * 100).rounded()))%")
                            .sType(SType(size: 15, weight: 500, line: 20, tracking: 0)).foregroundStyle(S.muted).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SPressStyle())
            }
            VStack(alignment: .leading, spacing: 0) {
                SStatLine(items: [(F.moneyK(invested), "invested", S.ink), (F.moneyK(now), "now", S.ink),
                                  (F.moneyK(diff), diff < 0 ? "down" : "up", diff < 0 ? S.red : S.green)])
                SInlineInsight(lead: insight.lead, rest: insight.rest)
            }
            GeometryReader { g in
                let avail = g.size.width - CGFloat(max(0, items.count - 1)) * 3
                HStack(spacing: 3) {
                    ForEach(items, id: \.name) { it in
                        RoundedRectangle(cornerRadius: 4).fill(it.color)
                            .frame(width: max(2, avail * CGFloat(it.usd / total)))
                            .opacity(sel != nil && sel!.name != it.name ? 0.35 : 1)
                            .onTapGesture { withAnimation(S.standard(0.3)) { picked = picked == it.name ? nil : it.name } }
                    }
                }
            }
            .frame(height: 40)
            VStack(spacing: 0) {
                ForEach(shown, id: \.name) { it in
                    Button { withAnimation(S.standard(0.3)) { picked = picked == it.name ? nil : it.name } } label: {
                        HStack(spacing: 12) {
                            Circle().fill(S.surface).frame(width: 40, height: 40)
                                .overlay(Circle().fill(it.color).frame(width: 10, height: 10))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(it.name).sType(SType(size: 15, weight: 600, line: 15, tracking: 0), tabular: false)
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(S.pGrid.opacity(2))
                                        Capsule().fill(it.color).frame(width: g.size.width * CGFloat(it.usd / hMax))
                                    }
                                }
                                .frame(height: 4)
                            }
                            Text(dollars ? F.moneyK(it.usd) : pct(it.usd)).sType(SType(size: 15, weight: 700, line: 15, tracking: 0))
                        }
                        .frame(height: 64)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(picked == it.name ? S.surface : .clear))
                        .overlay(alignment: .bottom) { Rectangle().fill(S.pGrid).frame(height: 1).padding(.horizontal, 8) }
                        .padding(.horizontal, -8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if items.count > 4 {
                Button { withAnimation(S.standard()) { more.toggle() } } label: {
                    Text(more ? "Show less" : "Show more").sType(.label, tabular: false).foregroundStyle(S.ink)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(SPressStyle())
            }
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sCardSurface()
    }

    /// "Comfortable with NKE at 39%?"
    private var insight: (lead: String, rest: String) {
        let hs = words.allocation.holdings.filter { $0.now > 0 }.sorted { $0.now > $1.now }
        let tot = hs.reduce(0) { $0 + $1.now }
        guard let a = hs.first, tot > 0 else { return ("Nothing held yet.", "") }
        let p = Int((a.now / tot * 100).rounded())
        let second = hs.dropFirst().first.map { Int(($0.now / tot * 100).rounded()) }
        return ("Comfortable with \(a.ticker) at \(p)%?",
                (second.map { "No other holding is above \($0)%. " } ?? "") + "Concentration is the risk to watch.")
    }
}
