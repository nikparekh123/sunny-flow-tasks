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
        VStack(alignment: .leading, spacing: 20) {
            SPeriodHeader(label: "Inventory", hero: hero(pickedCol), heroValue: Double(pickedCol?.calls ?? inv.callsSold),
                          heroColor: inv.callsMax > 0 && inv.callsSold > inv.callsMax && pickedCol == nil ? S.red : S.ink,
                          sub: sub(pickedCol), onTap: {}, period: P,
                          canGoBack: Periods.canGoBack(P, today: home.today, start: Periods.bookStart(home)))
            VStack(alignment: .leading, spacing: 0) {
                SStatLine(items: stats)
                SInlineInsight(lead: insight.lead, rest: insight.rest)
            }
            // No LEAPs held: header and stat line only, no chart (block 14 tile).
            if inv.callsMax > 0 {
                SViewToggle(period: P)
                SBarChart(columns: cols.map(\.col), caps: caps, picked: pick) { P.picked["inv"] = $0 }
                SLegend(rows: legend, hidden: $hidden)
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
    private func sub(_ c: Col?) -> String {
        if inv.callsMax == 0 { return "\(inv.putsSold) of \(inv.putsMax) puts" }
        if let c {
            return "\(Int((Double(c.calls) / Double(inv.callsMax) * 100).rounded()))% covered · \(c.puts) of \(inv.putsMax) puts"
        }
        if inv.callsSold > inv.callsMax { return "\(inv.callsSold - inv.callsMax) calls not covered" }
        let pct = Int((Double(inv.callsSold) / Double(inv.callsMax) * 100).rounded())
        return "\(pct)% covered · \(inv.callsMax - inv.callsSold) left to sell"
    }
    private var stats: [(value: String, label: String, color: Color)] {
        var s: [(value: String, label: String, color: Color)] = [(F.moneyK(inv.creditOpen), "credit", S.ink)]
        if inv.callsMax > 0 { s.append(("\(inv.callsSold)", "calls sold", inv.callsSold > inv.callsMax ? S.red : S.green)) }
        if inv.putsMax > 0 || inv.putsSold > 0 { s.append(("\(inv.putsSold)", "puts sold", S.blue)) }
        return s
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

    private struct Col { let col: SBarColumn; let calls: Int; let puts: Int }

    private var columns: [Col] {
        let today = home.today, a = Periods.anchor(P, today: today)
        let iMax = CGFloat(max(1, inv.callsMax, inv.putsMax))
        let h = { (v: Int) -> CGFloat in CGFloat(v) / iMax * (148 - 32) }
        let make = { (i: Int, label: String, calls: Int?, puts: Int?, now: Bool) -> Col in
            var bars: [SBar] = []
            if inv.callsMax > 0 {
                bars.append(SBar(segs: [.init(value: h(calls ?? 0), color: S.green, hidden: hidden.contains("calls"))],
                                 label: calls.map { $0 > 0 ? "\($0)" : "0" } ?? ""))
            }
            if inv.putsMax > 0 {
                bars.append(SBar(segs: [.init(value: h(puts ?? 0), color: S.blue, hidden: hidden.contains("puts"))],
                                 label: puts.map { $0 > 0 ? "\($0)" : "0" } ?? ""))
            }
            return Col(col: SBarColumn(id: i, label: label, bars: bars, isNow: now), calls: calls ?? 0, puts: puts ?? 0)
        }
        if P.view == .week {
            let fri = Periods.thisFriday(today)
            return Periods.fridays(a).enumerated().map { i, f in
                let w = inv.weeks.first { $0.fri == f }
                return make(i, "W\(i + 1)", w?.calls, w?.puts, f == fri)
            }
        }
        return Periods.months(a, start: Periods.bookStart(home)).map { m in
            let ym = String(format: "%@-%02d", a, m + 1)
            let w = inv.weeks.filter { $0.fri.hasPrefix(ym) }.sorted { $0.fri < $1.fri }.last
            return make(m, Periods.monthNames[m], w?.calls, w?.puts, today.hasPrefix(ym))
        }
    }

    private var caps: [(h: CGFloat, label: String, color: Color)] {
        let iMax = CGFloat(max(1, inv.callsMax, inv.putsMax))
        var c: [(h: CGFloat, label: String, color: Color)] = []
        if inv.callsMax > 0 { c.append((CGFloat(inv.callsMax) / iMax * 116, "max \(inv.callsMax)", S.green.opacity(hidden.contains("calls") ? 0.25 : 1))) }
        if inv.putsMax > 0 { c.append((CGFloat(inv.putsMax) / iMax * 116, "max \(inv.putsMax)", S.blue.opacity(hidden.contains("puts") ? 0.25 : 1))) }
        return c
    }

    private var legend: [(key: String, name: String, value: String, color: Color)] {
        var r: [(key: String, name: String, value: String, color: Color)] = []
        if inv.callsMax > 0 { r.append(("calls", "Calls on", "\(inv.callsSold) of \(inv.callsMax)", S.green)) }
        if inv.putsMax > 0 { r.append(("puts", "Puts on", "\(inv.putsSold) of \(inv.putsMax)", S.blue)) }
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
                    Button { withAnimation(S.standard(0.45)) { router.writes = c.ticker } } label: {
                        HStack(spacing: 6) {
                            Text(c.ticker).sType(SType(size: 13, weight: 700, line: 13, tracking: 0), tabular: false)
                            Text("\(c.callsSold) of \(c.callsMax)").sType(SType(size: 13, weight: 600, line: 13, tracking: 0))
                                .foregroundStyle(c.callsSold > c.callsMax ? S.red : S.ink)
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
