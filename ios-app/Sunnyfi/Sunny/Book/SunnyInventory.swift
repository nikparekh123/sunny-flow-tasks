//
//  SunnyInventory.swift
//  Sunny
//
//  Block 14 · SunnyInventory: how full the shelf is. Every LEAP can carry
//  one call sold, every put bought one put sold. The big number is calls
//  sold against the call max, the bars show calls beside puts per period
//  with each max drawn edge to edge, and a chip per name (least filled
//  first) opens the Planner on it (block 14b).
//

import SwiftUI

struct SunnyInventory: View {
    let home: HomePayload
    let words: HomePayload
    @Environment(HomeRouter.self) private var router
    @State private var hidden: Set<String> = DebugPreset.set("inv.hide")

    private var inv: Inventory { home.inventory }
    private var P: PeriodState { router.period }

    var body: some View {
        let cols = columns
        let pick = P.picked["inv"]
        let pickedCol = pick.flatMap { i in cols.first { $0.col.id == i } }
        // Now is this week's bar: rolled contracts count in it (handoff 24, block 14).
        let nowCol = cols.first { $0.col.isNow }
        let shown = pickedCol ?? nowCol
        VStack(alignment: .leading, spacing: 20) {
            SPeriodHeader(label: "Inventory", hero: hero(shown), heroValue: Double(shown?.calls ?? inv.callsSold),
                          heroColor: inv.callsMax > 0 && inv.callsSold > inv.callsMax && pickedCol == nil ? S.red : S.ink,
                          sub: sub(shown, picked: pickedCol != nil), onTap: {}, period: P,
                          canGoBack: Periods.canGoBack(P, today: home.today, start: Periods.bookStart(home)))
            VStack(alignment: .leading, spacing: 0) {
                SStatLine(items: stats(nowCol))
                SInlineInsight(lead: insight.lead, rest: insight.rest)
            }
            // No LEAPs held: header and stat line only, no chart (block 14 tile).
            if inv.callsMax > 0 {
                SViewToggle(period: P)
                SBarChart(columns: cols.map(\.col), caps: caps, picked: pick, onPick: { P.picked["inv"] = $0 },
                          grown: P.grown, rowKey: P.view.rawValue)
                VStack(alignment: .leading, spacing: 10) {
                    SLegend(rows: legend(nowCol), hidden: $hidden)
                    if let c = shown, c.rolledCalls + c.rolledPuts > 0, let to = c.rolledTo { rolledKey(c, to) }
                }
            }
            if inv.by.contains(where: { $0.callsMax > 0 }) { chips }
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sCardSurface()
    }

    // MARK: Numbers

    private func hero(_ c: Col?) -> String {
        if inv.callsMax == 0 { return "No calls to sell" }
        return "\(c?.calls ?? inv.callsSold) of \(inv.callsMax) calls"
    }
    /// "93% covered · 16 rolled · 8 left" (rolled count as sold, not as left);
    /// a picked period: "69% covered · 9 of 20 puts".
    private func sub(_ c: Col?, picked: Bool) -> String {
        if inv.callsMax == 0 { return "\(inv.putsSold) of \(inv.putsMax) puts" }
        if !picked, inv.callsSold > inv.callsMax { return "\(inv.callsSold - inv.callsMax) calls not covered" }
        let calls = c?.calls ?? inv.callsSold, rolled = c?.rolledCalls ?? 0
        let pct = Int((Double(calls) / Double(inv.callsMax) * 100).rounded())
        let r = rolled > 0 ? " · \(rolled) rolled" : ""
        if picked, let c { return "\(pct)% covered\(r) · \(c.puts) of \(inv.putsMax) puts" }
        let left = max(0, inv.callsMax - calls)
        return rolled > 0 ? "\(pct)% covered\(r) · \(left) left" : "\(pct)% covered · \(left) left to sell"
    }
    private func stats(_ now: Col?) -> [(value: String, label: String, color: Color)] {
        let calls = now?.calls ?? inv.callsSold, puts = now?.puts ?? inv.putsSold
        var s: [(value: String, label: String, color: Color)] = [(F.moneyK(inv.creditOpen), "credit", S.ink)]
        if inv.callsMax > 0 { s.append(("\(calls)", "calls sold", inv.callsSold > inv.callsMax ? S.red : S.green)) }
        if inv.putsMax > 0 || puts > 0 { s.append(("\(puts)", "puts sold", S.blue)) }
        return s
    }
    /// "Rolled to Oct 23 · NKE", under the legend (12/16 Medium, muted).
    private func rolledKey(_ c: Col, _ to: String) -> some View {
        HStack(spacing: 6) {
            S.hatchSwatch(c.rolledCalls > 0 ? S.green : S.blue, size: 8)
            Text("Rolled to \(F.day(to))" + (c.rolledNames.isEmpty ? "" : " · " + c.rolledNames.joined(separator: ", ")))
                .sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false)
                .foregroundStyle(S.muted)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
    private var insight: (lead: String, rest: String) {
        let w = words.inventory
        guard w.callsMax > 0 else { return ("No LEAPs to write against.", "Puts can still be sold against the puts bought.") }
        let pct = Int((Double(w.callsSold) / Double(w.callsMax) * 100).rounded())
        let open = w.by.filter { $0.callsMax > $0.callsSold }.sorted { ($0.callsMax - $0.callsSold) > ($1.callsMax - $1.callsSold) }
        if let top = open.first {
            return ("\(pct)% of calls covered.", "\(top.ticker) has the most room, \(top.callsSold) of \(top.callsMax).")
        }
        return ("Every LEAP carries a call.", "\(w.callsSold) of \(w.callsMax) calls sold.")
    }

    // MARK: Periods

    private struct Col {
        let col: SBarColumn; let calls: Int; let puts: Int
        var rolledCalls = 0, rolledPuts = 0
        var rolledTo: String? = nil, rolledNames: [String] = []
    }

    private var columns: [Col] {
        let today = home.today, a = Periods.anchor(P, today: today)
        let iMax = CGFloat(max(1, inv.callsMax, inv.putsMax))
        let h = { (v: Int) -> CGFloat in CGFloat(v) / iMax * (148 - 32) }
        /* A side's bar: what stayed on (solid) under what was rolled out (hatched),
           so a rolled week keeps its height (handoff 24, block 14). */
        let bar = { (n: Int?, rolled: Int, color: Color, key: String) -> SBar in
            let r = min(rolled, n ?? 0)
            return SBar(segs: [.init(value: h((n ?? 0) - r), color: color, hidden: hidden.contains(key)),
                               .init(value: h(r), color: color, hidden: hidden.contains(key), hatch: true)],
                        label: n.map { $0 > 0 ? "\($0)" : "0" } ?? "", rolled: r > 0 ? r : nil, rolledHue: color)
        }
        let make = { (i: Int, label: String, w: Inventory.Week?, now: Bool) -> Col in
            let rc = w?.callsRolled ?? 0, rp = w?.putsRolled ?? 0
            var bars: [SBar] = []
            if inv.callsMax > 0 { bars.append(bar(w?.calls, rc, S.green, "calls")) }
            if inv.putsMax > 0 { bars.append(bar(w?.puts, rp, S.blue, "puts")) }
            return Col(col: SBarColumn(id: i, label: label, bars: bars, isNow: now), calls: w?.calls ?? 0, puts: w?.puts ?? 0,
                       rolledCalls: rc, rolledPuts: rp, rolledTo: w?.rolledTo, rolledNames: w?.rolledNames ?? [])
        }
        if P.view == .week {
            let fri = Periods.thisFriday(today)
            return Periods.fridays(a).enumerated().map { i, f in
                let w = inv.weeks.first { $0.fri == f }
                return make(i, Periods.weekLabel(i, fri: f, today: today), w, f == fri)
            }
        }
        return Periods.months(a, start: Periods.bookStart(home)).map { m in
            let ym = String(format: "%@-%02d", a, m + 1)
            let w = inv.weeks.filter { $0.fri.hasPrefix(ym) }.sorted { $0.fri < $1.fri }.last
            return make(m, Periods.monthNames[m], w, today.hasPrefix(ym))
        }
    }

    private var caps: [(h: CGFloat, label: String, color: Color)] {
        let iMax = CGFloat(max(1, inv.callsMax, inv.putsMax))
        var c: [(h: CGFloat, label: String, color: Color)] = []
        if inv.callsMax > 0 { c.append((CGFloat(inv.callsMax) / iMax * 116, "max \(inv.callsMax)", S.green.opacity(hidden.contains("calls") ? 0.25 : 1))) }
        if inv.putsMax > 0 { c.append((CGFloat(inv.putsMax) / iMax * 116, "max \(inv.putsMax)", S.blue.opacity(hidden.contains("puts") ? 0.25 : 1))) }
        return c
    }

    private func legend(_ now: Col?) -> [(key: String, name: String, value: String, color: Color)] {
        var r: [(key: String, name: String, value: String, color: Color)] = []
        if inv.callsMax > 0 { r.append(("calls", "Calls on", "\(now?.calls ?? inv.callsSold) of \(inv.callsMax)", S.green)) }
        if inv.putsMax > 0 { r.append(("puts", "Puts on", "\(now?.puts ?? inv.putsSold) of \(inv.putsMax)", S.blue)) }
        return r
    }

    // MARK: Chips → the Writes sheet

    private var chips: some View {
        // Chips count calls ("NFLX 0 of 17"); a name with no calls has none (block 14, No LEAPs).
        let order = inv.by.filter { $0.callsMax > 0 }.sorted {
            let a = $0.callsMax > 0 ? Double($0.callsSold) / Double($0.callsMax) : 1
            let b = $1.callsMax > 0 ? Double($1.callsSold) / Double($1.callsMax) : 1
            return a != b ? a < b : $0.ticker < $1.ticker
        }
        return ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(order) { c in
                    Button { router.openCard(c.ticker, face: "sold") } label: {
                        HStack(spacing: 6) {
                            Text(c.ticker).sType(SType(size: 13, weight: 700, line: 13, tracking: 0), tabular: false)
                            // A name that rolled this week: "NKE ⁄ 16 rolled" (handoff 24).
                            if let r = c.rolled, r > 0 {
                                HStack(spacing: 4) {
                                    S.hatchSwatch(S.green, size: 8)
                                    Text("\(r) rolled").sType(SType(size: 13, weight: 600, line: 13, tracking: 0))
                                }
                            } else {
                                Text("\(c.callsSold) of \(c.callsMax)").sType(SType(size: 13, weight: 600, line: 13, tracking: 0))
                                    .foregroundStyle(c.callsSold > c.callsMax ? S.red : S.ink)
                            }
                        }
                        .foregroundStyle(S.ink)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(Capsule().fill(S.surface))
                        .contentShape(Capsule().inset(by: -6))
                        .overlay(alignment: .bottom) {
                            if c.callsSold > c.callsMax { Capsule().fill(S.red).frame(height: 2).padding(.horizontal, 12) }
                        }
                    }
                    .buttonStyle(SPressStyle())
                    .accessibilityHint("Opens the Writes sheet")
                }
            }
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20)
    }
}
