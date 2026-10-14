//
//  SunnyInventory.swift
//  Sunny
//
//  Block 14 · SunnyInventory: how full the shelf is. Every LEAP can carry
//  one call sold, every put bought one put sold. The big number is calls
//  sold against the call max, the bars show calls beside puts per period
//  with each max drawn edge to edge, and a chip per name (least filled
//  first) opens the Writes sheet on it.
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

// MARK: - The Writes sheet

/// One screen, sliding in from the right: the ticker row, then one glass
/// card for the name: price · By Fri bar · the write · expected credit ·
/// delta and what is held. Partial fills: what is already sold for that
/// Friday shows in grey and only the rest is suggested.
struct SunnyWritesSheet: View {
    let home: HomePayload
    @Binding var ticker: String?
    /// The card on screen; swiping moves it and the chips follow (Nik, 13 Oct
    /// 2026: "can we slide to the next ticker").
    @State private var page: String?
    @State private var heights: [String: CGFloat] = [:]
    @State private var cardW: CGFloat = 353

    var body: some View {
        let names = home.writes.names
        let cur = names.first { $0.ticker == ticker } ?? names.first
        ZStack(alignment: .top) {
            SBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Button { withAnimation(S.standard(0.45)) { ticker = nil } } label: {
                                // Apple's back button size: 44 pt circle, 17 pt semibold chevron.
                                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(S.ink)
                                    .frame(width: 44, height: 44)
                                    .glassEffect(.regular.interactive(), in: .circle)
                            }
                            .buttonStyle(SPressStyle())
                            .accessibilityLabel("Back")
                            Text("Inventory").sType(.largeTitle, tabular: false)
                        }
                        .frame(height: 40)
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(names) { n in
                                        let on = n.ticker == cur?.ticker
                                        Button { withAnimation(S.standard(0.35)) { ticker = n.ticker } } label: {
                                            HStack(spacing: 8) {
                                                Text(n.ticker).sType(SType(size: 15, weight: 500, line: 15, tracking: 0), tabular: false)
                                                Text("\(n.calls.sold) of \(n.calls.of)")
                                                    .sType(SType(size: 12, weight: 600, line: 12, tracking: 0))
                                                    .foregroundStyle(on ? S.chipOnInk.opacity(0.7) : S.muted)
                                            }
                                            .foregroundStyle(on ? S.chipOnInk : S.ink)
                                            .padding(.horizontal, 16).frame(height: 40)
                                            .background { if on { Capsule().fill(S.ink) } }
                                            .glassEffect(on ? .identity : .regular.interactive(), in: .capsule)
                                        }
                                        .buttonStyle(SPressStyle())
                                        .accessibilityAddTraits(on ? .isSelected : [])
                                        .id(n.ticker)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            .contentMargins(.horizontal, 20, for: .scrollContent)
                            .scrollIndicators(.hidden)
                            .scrollClipDisabled()
                            .padding(.horizontal, -20).padding(.vertical, -8)
                            .onAppear { if let t = cur?.ticker { proxy.scrollTo(t, anchor: .center) } }
                            .onChange(of: cur?.ticker) { _, t in
                                if let t { withAnimation(S.standard(0.4)) { proxy.scrollTo(t, anchor: .center) } }
                            }
                        }
                    }
                    if let cur { pager(names, cur) }
                    else {
                        Text("Nothing to write this week.").sType(.body, tabular: false).foregroundStyle(S.muted)
                    }
                }
                .foregroundStyle(S.ink)
                .padding(.horizontal, S.margin)
                .onGeometryChange(for: CGFloat.self) { $0.size.width - 2 * S.margin } action: { cardW = $0 }
                .padding(.top, 14).padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
        // Back from the left edge only, as iOS does, so swiping the cards
        // right goes to the previous ticker instead of closing the screen.
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.startLocation.x < 30, v.translation.width > 80, abs(v.translation.height) < 60 {
                withAnimation(S.standard(0.45)) { ticker = nil }
            }
        })
    }

    /// One card per name, side by side; snaps one at a time and is as tall as
    /// the card on screen.
    private func pager(_ names: [Writes.Name], _ cur: Writes.Name) -> some View {
        let h = heights[cur.ticker] ?? 0
        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 20) {
                ForEach(names) { n in
                    WriteCard(n: n, calendar: home.calendar)
                        .frame(width: cardW, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[n.ticker] = $0 }
                        .id(n.ticker)
                }
            }
            .scrollTargetLayout()
            .padding(.top, 8).padding(.bottom, 24)
        }
        .contentMargins(.horizontal, S.margin, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition(id: $page)
        .scrollIndicators(.hidden)
        .frame(height: h > 0 ? h + 32 : nil, alignment: .top)
        .padding(.horizontal, -S.margin).padding(.top, -8).padding(.bottom, -24)
        .animation(S.standard(0.4), value: h)
        .onChange(of: page) { _, p in if let p, p != ticker { ticker = p } }
        .onChange(of: ticker) { _, t in if let t, t != page { withAnimation(S.standard(0.45)) { page = t } } }
        .task {
            // A scroll position set before the first layout is ignored, so set it after.
            try? await Task.sleep(for: .milliseconds(60))
            page = cur.ticker
        }
    }
}

struct WriteCard: View {
    let n: Writes.Name
    let calendar: [CalendarDay]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(n.ticker).font(SType(size: 20, weight: 600, line: 24, tracking: 0).font())
                Text(F.level(n.spot ?? 0)).font(SType(size: 20, weight: 400, line: 24, tracking: 0).font(tabular: true))
                    .foregroundStyle(S.muted)
                if let e = n.earnings {
                    Text("earnings \(DeckBuilder.weekdays[DeckBuilder.weekday(e.date)])")
                        .sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false)
                        .foregroundStyle(S.yellowDeep)
                }
            }
            .lineLimit(1)
            if let bar = barGeometry {
                HStack {
                    Text("By Fri").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.muted)
                    Spacer()
                    Text(bar.header).sType(SType(size: 15, weight: 500, line: 20, tracking: 0)).foregroundStyle(S.muted)
                }
                .frame(height: 20)
                ByFriBar(g: bar, spot: n.spot ?? 0)
            }
            Rectangle().fill(S.surface).frame(height: 1)
            Text("The write").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.muted)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(n.already.enumerated()), id: \.offset) { _, a in
                    line(call: a.type == "call", lead: "\(a.n) × \(PF.strike(a.strike))", note: "already sold", grey: true)
                }
                ForEach(Array(n.plan.enumerated()), id: \.offset) { _, p in
                    line(call: p.type == "call", lead: "\(p.n) × \(PF.strike(p.strike))", note: p.note, grey: false)
                }
            }
            Rectangle().fill(S.surface).frame(height: 1)
            VStack(alignment: .leading, spacing: 8) {
                if n.written {
                    Text("Written").sType(.largeNumber, tabular: false)
                    Text("collected · \(n.calls.sold) of \(n.calls.of) calls" + (n.puts.of > 0 ? " · \(n.puts.sold) of \(n.puts.of) puts" : ""))
                        .sType(SType(size: 15, weight: 500, line: 20, tracking: 0)).foregroundStyle(S.muted)
                } else {
                    SNumber(value: n.expected, format: { F.money($0) }).sType(.largeNumber)
                    Text(expectedLine).sType(SType(size: 15, weight: 500, line: 20, tracking: 0)).foregroundStyle(S.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Rectangle().fill(S.surface).frame(height: 1)
            HStack {
                // Delta in shares, no minus sign: short of flat is red.
                let bold = SType(size: 15, weight: 700, line: 15, tracking: 0).font(tabular: true)
                Group {
                    if n.plan.isEmpty {
                        Text("Delta ").foregroundStyle(S.muted) + Text("-").font(bold).foregroundStyle(S.ink)
                    } else {
                        Text("Delta ").foregroundStyle(S.muted)
                            + Text(PF.count(n.delta.now)).font(bold).foregroundStyle(n.delta.now < 0 ? S.red : S.ink)
                            + Text(" → ").font(bold).foregroundStyle(S.ink)
                            + Text(PF.count(n.delta.after)).font(bold).foregroundStyle(n.delta.after < 0 ? S.red : S.ink)
                    }
                }
                .sType(SType(size: 15, weight: 500, line: 20, tracking: 0))
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                // The chips never shrink; a long delta wraps instead (block 14 tile).
                HStack(spacing: 8) {
                    if n.calls.of > 0 { held("Calls", "\(n.calls.sold) / \(n.calls.of)") }
                    if n.puts.of > 0 { held("Puts", "\(n.puts.sold) / \(n.puts.of)") }
                }
                .fixedSize()
            }
            .frame(minHeight: 24)
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: S.rCard))
    }

    private var expectedLine: String {
        let calls = n.plan.filter { $0.type == "call" }.reduce(0) { $0 + $1.n }
        let puts = n.plan.filter { $0.type == "put" }.reduce(0) { $0 + $1.n }
        var parts = ["expected", "next Fri"]
        if calls > 0 { parts.append("\(calls) calls") }
        if puts > 0 { parts.append("\(puts) puts") }
        if !n.already.isEmpty { parts.append("\(F.moneyK(n.collected)) collected") }
        return parts.joined(separator: " · ")
    }

    private func line(call: Bool, lead: String, note: String, grey: Bool) -> some View {
        HStack(spacing: 10) {
            Text(call ? "Call" : "Put").sType(.label, tabular: false)
                .foregroundStyle(call ? S.green : S.blue)
                .frame(width: 40, height: 22)
                .background(Capsule().fill(S.surface))
            Text(lead).sType(SType(size: 20, weight: 700, line: 24, tracking: 0)).foregroundStyle(grey ? S.muted : S.ink)
            Text(note).sType(SType(size: 15, weight: 400, line: 20, tracking: 0), tabular: false).foregroundStyle(S.muted)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private func held(_ kind: String, _ v: String) -> some View {
        HStack(spacing: 6) {
            Text(kind).font(SType(size: 13, weight: 500, line: 13, tracking: 0).font()).foregroundStyle(S.muted)
            Text(v).font(SType(size: 13, weight: 600, line: 13, tracking: 0).font(tabular: true))
        }
        .padding(.horizontal, 8).frame(height: 24)
        .background(Capsule().fill(S.paper))
        .overlay(Capsule().strokeBorder(S.line.opacity(0.6), lineWidth: 0.5))
    }

    // MARK: The By Fri bar

    struct BarGeo {
        let segs: [(flex: Double, color: Color)]
        let marks: [(x: Double, value: String, label: String, color: Color, tall: Bool)]
        let nowX: Double
        let header: String
    }

    /// From the put strike, through the price, to the call 1 SD strike; marks
    /// kept at least 22% of the bar apart (readable, not to scale).
    private var barGeometry: BarGeo? {
        guard let px = n.spot, px > 0 else { return nil }
        let b = n.bar
        let written = n.written
        let hasC = n.calls.of > 0 && b.sd1 != nil
        let hasP = n.puts.of > 0 && b.put != nil
        guard hasC || hasP else { return nil }
        let cStrikes: [Double] = hasC
            ? (written ? Array(Set(n.already.filter { $0.type == "call" }.map(\.strike))).sorted() : [b.call].compactMap { $0 })
            : []
        let sd = b.sd1 ?? px
        var pts = [px]
        if hasC { pts += cStrikes + [sd] + (written ? [] : [b.breakeven].compactMap { $0 }) }
        if hasP, let put = b.put { pts.append(put - px * 0.04) }
        let lo = pts.min()! - px * 0.012, hi = pts.max()! + px * 0.012
        var marks: [Double] = []
        if hasP, let put = b.put { marks.append(put) }
        if hasC { marks += cStrikes + [sd] }
        marks = Array(Set(marks)).sorted()
        let raw = { (v: Double) in (v - lo) / (hi - lo) * 100 }
        var nx = marks.map(raw)
        let MIN = 22.0, EDGE = 6.0
        for i in nx.indices { nx[i] = max(nx[i], i > 0 ? nx[i - 1] + MIN : EDGE) }
        for i in nx.indices.reversed() { nx[i] = min(nx[i], i < nx.count - 1 ? nx[i + 1] - MIN : 100 - EDGE) }
        let anchors = [(lo, 0.0)] + zip(marks, nx).map { ($0, $1) } + [(hi, 100.0)]
        let warp = { (v: Double) -> Double in
            for i in 1..<anchors.count where v <= anchors[i].0 {
                let (a, ax) = anchors[i - 1], (bb, bx) = anchors[i]
                return ax + (bb > a ? (v - a) / (bb - a) : 0) * (bx - ax)
            }
            return 100
        }
        var bounds: [(v: Double, c: Color)] = [(lo, S.line)]
        if hasP, let put = b.put { bounds[0].c = S.red; bounds.append((put, S.line)) }
        if hasC {
            if written, let first = cStrikes.first { bounds += [(first, S.green), (sd, S.line)] }
            else if let atm = b.call { bounds += [(atm, S.green), (b.breakeven ?? atm, S.red), (sd, S.line)] }
        }
        bounds.append((hi, S.line))
        let segs = (0..<(bounds.count - 1)).map { i in (max(0, warp(bounds[i + 1].v) - warp(bounds[i].v)), bounds[i].c) }.filter { $0.0 > 0 }
        let step = px < 50 ? 0.5 : px < 250 ? 1 : 5
        let fx = { (v: Double) -> String in
            let r = (v / step).rounded() * step
            return step < 1 ? F.trim(r) : String(Int(r))
        }
        var mk: [(v: Double, value: String, label: String, color: Color)] = []
        if hasP, let put = b.put { mk.append((put, fx(put), n.puts.sold > 0 && n.plan.allSatisfy { $0.type != "put" } ? "put sold" : "put strike", S.blue)) }
        if hasC {
            mk += cStrikes.map { ($0, fx($0), written ? "sold" : "call strike", S.ink) }
            mk.append((sd, fx(sd), "call 1 SD", S.red))
        }
        mk.sort { $0.v < $1.v }
        // Two marks on one strike (a call sold right at the 1 SD strike) share
        // one tick and one value, or the tall tick runs through the other's text.
        var merged: [(v: Double, value: String, label: String, color: Color)] = []
        for m in mk {
            if let last = merged.last, last.value == m.value {
                merged[merged.count - 1] = (m.v, m.value, last.label + " · " + m.label.replacingOccurrences(of: "call ", with: ""),
                                            m.label == "call 1 SD" ? m.color : last.color)
            } else { merged.append(m) }
        }
        mk = merged
        var head: [String] = []
        if hasP, let put = b.put { head.append(String(format: "%.1f%% to put", abs(put - px) / px * 100)) }
        if hasC { head.append(String(format: "%.1f%% to 1 SD", abs(sd - px) / px * 100)) }
        return BarGeo(segs: segs, marks: mk.enumerated().map { i, m in (warp(m.v), m.value, m.label, m.color, i % 2 == 1) },
                      nowX: warp(px), header: head.joined(separator: " · "))
    }
}

struct ByFriBar: View {
    let g: WriteCard.BarGeo
    let spot: Double
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                VStack(spacing: 4) {
                    Text(F.level(spot)).sType(SType(size: 15, weight: 700, line: 15, tracking: 0))
                    RoundedRectangle(cornerRadius: 1).fill(S.ink).frame(width: 2, height: 10)
                }
                .fixedSize()
                .position(x: g.nowX / 100 * w, y: 14)
                HStack(spacing: 0) {
                    ForEach(Array(g.segs.enumerated()), id: \.offset) { _, s in
                        Rectangle().fill(s.color).frame(width: max(0, s.flex / 100 * w))
                    }
                }
                .frame(width: w, height: 12, alignment: .leading)
                .clipShape(Capsule())
                .offset(y: 32)
                ForEach(Array(g.marks.enumerated()), id: \.offset) { _, m in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1).fill(m.color).frame(width: 2, height: m.tall ? 40 : 8)
                        Text(m.value).sType(SType(size: 15, weight: 700, line: 15, tracking: 0))
                        Text(m.label).sType(SType(size: 12, weight: 500, line: 12, tracking: 0), tabular: false)
                    }
                    .foregroundStyle(m.color)
                    .fixedSize()
                    .alignmentGuide(.leading) { d in -(m.x / 100 * w - d.width / 2) }
                    .offset(y: 50)
                }
            }
        }
        .frame(height: 128)
        .accessibilityElement()
        .accessibilityLabel("By Friday. " + g.marks.map { "\($0.label) \($0.value)" }.joined(separator: ", ") + ". Price \(F.level(spot)).")
    }
}
