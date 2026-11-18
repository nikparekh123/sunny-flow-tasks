//
//  OverviewTogether.swift
//  Sunny
//
//  The Overview, both books together (handoff 2026-11-18 §4, App Explorations 165a; Nik, 17 Nov 2026: "the Overview
//  should read like Sunny and Nicolay combined, no scores"). Built on the server (sunny-home together.ts, payload
//  `together` in book S's build); this draws it:
//    1 · the two accounts as one value line (1W to All), the drag reading a day with each account's part;
//    2 · Your positions by what is held (What you sold: Calls sold, Puts sold · What you own: Shares, Hedges, Nik's
//        groups of 11 Nov 2026), Today | Unrealized, a row opening its legs with each account's part and a pill;
//    3 · Coming up across both books, this week and later;
//    4 · Realized P&L: this month, the year, and by month as stacked bars with a straight-line trend, a tap reading a
//        month; dividends kept apart.
//  A range's change leaves deposits out (Nicolay's funding is money in, not a gain). No em dashes in any words here.
//

import SwiftUI

struct OverviewTogether: View {
    let t: JSONValue
    let privacy: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    @State private var range = "1M"
    @State private var finger: CGFloat?
    @State private var unrealized = false
    @State private var openRow: String?
    @State private var allEvents = false
    @State private var month: String?

    private var names: [String] { t["names"].array.compactMap(\.string) }

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            top
            positions
            coming
            realized
        }
    }

    // MARK: - 1 · Together

    private struct Pt { let d: String; let v: [Double?]; let dep: Double }
    /// The closes, then now (when today has no close yet).
    private var points: [Pt] {
        var p = t["line"].array.map { x in Pt(d: x["d"].string ?? "", v: x["v"].array.map(\.double), dep: x["dep"].double ?? 0) }
        if let l = t["live"]["d"].string, p.last?.d != l {
            p.append(Pt(d: l, v: t["live"]["v"].array.map(\.double), dep: 0))
        }
        return p
    }
    private func total(_ p: Pt) -> Double { p.v.reduce(0) { $0 + ($1 ?? 0) } }

    /// Each range's first index, and its words; only the ranges the line reaches back to.
    private func ranges(_ p: [Pt]) -> [(k: String, i: Int, w: String)] {
        let n = p.count, today = p.last?.d ?? ""
        guard n > 1 else { return [] }
        let lastBefore = { (d: String) -> Int? in p.lastIndex { $0.d < d } }
        var out: [(String, Int, String)] = []
        if n > 5 { out.append(("1W", n - 6, "past week")) }
        if let i = lastBefore(String(today.prefix(8)) + "01") { out.append(("MTD", i, "this month")) }
        if n > 21 { out.append(("1M", n - 22, "past month")) }
        if n > 63 { out.append(("3M", n - 64, "past 3 months")) }
        if let i = lastBefore(String(today.prefix(4)) + "-01-01") { out.append(("YTD", i, "this year")) }
        if n > 252 { out.append(("1Y", n - 253, "past year")) }
        out.append(("All", 0, "since \(Self.md(p[0].d))"))
        return out.map { (k: $0.0, i: $0.1, w: $0.2) }
    }

    private var top: some View {
        let p = points, rs = ranges(p)
        let r = rs.first { $0.k == range } ?? rs.first { $0.k == "1M" } ?? rs.last
        let s = r?.i ?? 0, e = max(s, p.count - 1)
        let j = finger.map { s + Int((CGFloat(e - s) * $0).rounded()) } ?? e
        let v0 = p.indices.contains(s) ? total(p[s]) : 0, vj = p.indices.contains(j) ? total(p[j]) : 0
        let dep = p.indices.contains(j) && j > s ? p[(s + 1)...j].reduce(0) { $0 + $1.dep } : 0
        // The change leaves deposits out; its % is on what was there at the start plus what came in since.
        let dv = vj - v0 - dep, pct = abs(v0 + dep) > 0 ? dv / abs(v0 + dep) : 0
        let todayAmt = t["live"]["today"].double ?? 0
        let head = finger == nil ? "Together · \(p.last.map { Self.wmd($0.d) } ?? "")" : (p.indices.contains(j) ? Self.wmd(p[j].d) : "")
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(head).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    Spacer(minLength: 12)
                    if finger == nil {
                        Text("\(todayAmt < 0 ? "▼" : "▲") \(k(todayAmt)) today").sType(SType(size: 13, weight: 600, line: 18, tracking: 0))
                            .foregroundStyle(tone(todayAmt))
                    }
                }
                Text(privacy ? BriefMask.shown : F.money(vj)).sType(SType(size: 34, weight: 800, line: 40, tracking: -0.02)).foregroundStyle(S.ink)
                    .contentTransition(reduce ? .identity : .numericText(value: vj))
                (Text("\(dv < 0 ? "▼" : "▲") \(k(dv)) · \(Self.pc(pct))").fontWeight(.bold).foregroundStyle(tone(dv))
                 + Text(" \(finger == nil ? (r?.w ?? "") : "from \(p.indices.contains(s) ? Self.wmd(p[s].d) : "")")").foregroundStyle(S.secondary))
                    .sType(SType(size: 15, weight: 500, line: 20, tracking: 0))
                HStack(spacing: 16) {
                    ForEach(Array(names.enumerated()), id: \.offset) { i, n in
                        let v = p.indices.contains(j) ? (p[j].v.indices.contains(i) ? p[j].v[i] : nil) : nil
                        if let v {
                            (Text("\(n) ").foregroundStyle(S.secondary) + Text(k(v)).fontWeight(.semibold).foregroundStyle(S.ink))
                                .sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                        }
                    }
                }
                .padding(.top, 2)
            }
            .accessibilityElement(children: .combine)
            chart(p, s: s, e: e, j: j, up: dv >= 0)
                .frame(height: 200)
                .padding(.top, 8)
            HStack(spacing: 2) {
                ForEach(rs, id: \.k) { x in
                    let on = x.k == (r?.k ?? "")
                    Button { withAnimation(S.moving(.easeOut(duration: 0.25), reduce)) { range = x.k; finger = nil } } label: {
                        Text(x.k).sType(SType(size: 13, weight: on ? 700 : 600, line: 16, tracking: 0), tabular: false)
                            .foregroundStyle(on ? S.ink : S.secondary)
                            .frame(minWidth: 40, minHeight: 30).padding(.horizontal, 8)
                            .background(on ? S.dynA(0x767680, 0.12, 0x767680, 0.24) : .clear, in: Capsule())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.horizontal, -6)
        }
    }

    private func chart(_ p: [Pt], s: Int, e: Int, j: Int, up: Bool) -> some View {
        // Drawn less the money put in since the range's first day (a book starting counts as money in), so the line
        // is what the two made and never jumps on a deposit; the figures above stay the real values.
        var cum = 0.0
        let vs = (s...e).map { i -> Double in if i > s { cum += p[i].dep }; return total(p[i]) - cum }
        let lo0 = vs.min() ?? 0, hi0 = vs.max() ?? 1, pad = (hi0 - lo0) * 0.1 == 0 ? 1 : (hi0 - lo0) * 0.1
        let lo = lo0 - pad, hi = hi0 + pad, c = up ? S.green : S.red
        return GeometryReader { g in
            let w = g.size.width, h = g.size.height, n = max(1, vs.count - 1)
            let X = { (q: Int) in CGFloat(q) / CGFloat(n) * w }, Y = { (v: Double) in CGFloat((hi - v) / (hi - lo)) * h }
            let path = { (a: Int, b: Int) in Path { pp in
                guard b > a else { return }
                for q in a...b { let pt = CGPoint(x: X(q), y: Y(vs[q])); if q == a { pp.move(to: pt) } else { pp.addLine(to: pt) } }
            } }
            let jj = j - s
            ZStack(alignment: .topLeading) {
                Path { pp in pp.move(to: CGPoint(x: 0, y: Y(vs[0]))); pp.addLine(to: CGPoint(x: w, y: Y(vs[0]))) }
                    .stroke(S.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0, 5]))
                if finger != nil { path(jj, n).stroke(c.opacity(0.22), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)) }
                path(0, finger != nil ? jj : n).stroke(c, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if finger != nil {
                    Rectangle().fill(S.secondary.opacity(0.35)).frame(width: 1, height: h).offset(x: X(jj))
                    Circle().fill(c).frame(width: 10, height: 10).background(Circle().fill(S.paper).padding(-2.5)).position(x: X(jj), y: Y(vs[jj]))
                }
                Color.clear.contentShape(Rectangle())
                    .gesture(ScrubGesture(onChange: { x in finger = min(max(x / max(1, w), 0), 1) }, onEnd: { finger = nil }))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Both accounts together")
        .accessibilityValue("\(privacy ? "hidden" : F.money(total(p[s]))) to \(privacy ? "hidden" : F.money(total(p[e])))")
    }

    // MARK: - 2 · Your positions

    private var positions: some View {
        let f = unrealized ? "all" : "today"
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Your positions").sType(SType(size: 22, weight: 700, line: 28, tracking: -0.01), tabular: false).foregroundStyle(S.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                seg
            }
            .padding(.bottom, 4)
            ForEach(Array(t["positions"].array.enumerated()), id: \.offset) { _, g in
                VStack(alignment: .leading, spacing: 0) {
                    Text(g["l"].string ?? "").sType(SType(size: 13, weight: 600, line: 18, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                        .padding(.bottom, 6)
                    ForEach(Array(g["rows"].array.enumerated()), id: \.offset) { _, r in posRow(r, f) }
                }
                .padding(.top, 10)
            }
            Text(unrealized ? "What you own against what you paid; what you sold against what you collected. Both accounts added."
                 : "Each leg against yesterday’s close, both accounts added. A tap shows the names and each account’s part.")
                .sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                .padding(.top, 8)
                .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
        }
    }

    private var seg: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(S.dynA(0xFFFFFF, 0.88, 0xFFFFFF, 0.2))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .frame(width: 96, height: 30)
                .offset(x: unrealized ? 98 : 2)
                .animation(S.moving(.timingCurve(0.34, 1.36, 0.64, 1, duration: 0.45), reduce), value: unrealized)
            HStack(spacing: 0) {
                ForEach([false, true], id: \.self) { u in
                    Button { unrealized = u } label: {
                        Text(u ? "Unrealized" : "Today").sType(SType(size: 14, weight: unrealized == u ? 600 : 500, line: 18, tracking: 0), tabular: false)
                            .foregroundStyle(unrealized == u ? S.ink : S.secondary)
                            .frame(width: 98, height: 34).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(unrealized == u ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
        .frame(width: 196, height: 34)
        .background(Capsule().fill(S.dynA(0x767680, 0.12, 0x767680, 0.24)))
        .sensoryFeedback(.selection, trigger: unrealized)
    }

    private func posRow(_ r: JSONValue, _ f: String) -> some View {
        let key = r["k"].string ?? "", isOpen = openRow == key, v = r[f].double ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(S.moving(.easeInOut(duration: 0.25), reduce) ?? .linear(duration: 0)) { openRow = isOpen ? nil : key }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r["l"].string ?? "").sType(SType(size: 17, weight: 600, line: 22, tracking: 0), tabular: false).foregroundStyle(S.ink)
                        Text(sub(r)).sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(k(v)).sType(SType(size: 17, weight: 700, line: 22, tracking: 0)).foregroundStyle(tone(v))
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(S.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .frame(minHeight: 44).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(BSay.words("\(r["l"].string ?? ""), \(unrealized ? "unrealized" : "today") \(v < -0.5 ? "down " : v > 0.5 ? "up " : "")\(k(v)). \(sub(r))", privacy: privacy))
            .accessibilityHint(isOpen ? "Hides the names" : "Shows the names")
            if isOpen {
                VStack(spacing: 0) {
                    ForEach(Array(r["items"].array.enumerated()), id: \.offset) { _, it in item(it, f, sold: r["sold"].bool) }
                }
                .padding(.trailing, 22).padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
    }

    /// "69 calls · 5 names · 26% captured", "of $4.1K collected", "4,980 shares · 4 names", "8 hedge calls · 30 hedge puts".
    private func sub(_ r: JSONValue) -> String {
        let n = r["n"].double ?? 0, nn = Int(r["names"].double ?? 0), who = r["only"].string.map { "\($0) only" } ?? "\(nn) names"
        let base = r["base"].double ?? 0, all = r["all"].double ?? 0
        switch r["k"].string ?? "" {
        case "cs", "ps":
            let what = r["k"].string == "cs" ? "calls" : "puts"
            let pc = base > 0 ? Int((all / base * 100).rounded()) : 0
            // "so far": kept out of what was collected since each leg was sold (the design's sample said "this week").
            return unrealized ? "of \(k(base)) collected" : "\(Self.n0(n)) \(what) · \(who)\(base > 0 ? " · \(abs(pc))% \(pc < 0 ? "lost" : "captured") so far" : "")"
        case "sh": return unrealized ? "on \(k(base)) paid" : "\(Self.n0(n)) shares · \(who)"
        default:
            let c = r["hedgeCalls"].double ?? 0, p = r["hedgePuts"].double ?? 0
            return unrealized ? "on \(k(base)) paid" : [c > 0 ? "\(Self.n0(c)) hedge calls" : "", p > 0 ? "\(Self.n0(p)) hedge puts" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    private func item(_ it: JSONValue, _ f: String, sold: Bool) -> some View {
        let v = it[f].double ?? 0, tk = it["t"].string ?? ""
        let n = it["n"].double ?? 0, lab = it["label"].string ?? ""
        let what = lab == "shares" ? "\(Self.n0(n)) shares" : "\(lab) · \(Self.n0(n)) \(n == 1 ? "contract" : "contracts")"
        let parts = Array(it["parts"].array.enumerated()).compactMap { i, p -> (String, Double)? in
            guard case .object = p, names.indices.contains(i) else { return nil }
            return (names[i], p[f].double ?? 0)
        }
        return HStack(alignment: .center, spacing: 10) {
            BLogo(ticker: tk, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(it["name"].string ?? tk).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Text(what).sType(SType(size: 12, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.secondary).fixedSize(horizontal: false, vertical: true)
                if names.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, x in
                            (Text("\(x.0) ").foregroundStyle(S.secondary) + Text(k(x.1)).fontWeight(.semibold).foregroundStyle(tone(x.1)))
                                .sType(SType(size: 12, weight: 500, line: 16, tracking: 0)).lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(k(v)).sType(SType(size: 14, weight: 600, line: 18, tracking: 0))
                .foregroundStyle(v > 0.5 || v < -0.5 ? (S.dyn(0xFFFFFF, 0x000000)) : S.ink)
                .padding(.horizontal, 9).frame(minWidth: 68, minHeight: 30)
                .background(v > 0.5 ? S.green : v < -0.5 ? S.red : S.dynA(0x767680, 0.16, 0x767680, 0.32), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BSay.words("\(it["name"].string ?? tk), \(what), \(v < -0.5 ? "down " : v > 0.5 ? "up " : "")\(k(v))\(parts.count > 1 ? ", " + parts.map { "\($0.0) \(k($0.1))" }.joined(separator: ", ") : "")", privacy: privacy))
    }

    // MARK: - 3 · Coming up

    private var coming: some View {
        let ev = t["events"].array, shown = allEvents ? ev : Array(ev.prefix(5))
        return VStack(alignment: .leading, spacing: 6) {
            Text("Coming up").sType(SType(size: 22, weight: 700, line: 28, tracking: -0.01), tabular: false).foregroundStyle(S.ink)
                .padding(.bottom, 4).accessibilityAddTraits(.isHeader)
            if ev.isEmpty {
                Text("Nothing on the calendar for either book in the next six weeks.").sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false)
                    .foregroundStyle(S.secondary)
            }
            ForEach([true, false], id: \.self) { week in
                let items = shown.filter { $0["week"].bool == week }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(week ? "This week" : "Later").sType(SType(size: 13, weight: 600, line: 18, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                            .padding(.bottom, 6)
                        ForEach(Array(items.enumerated()), id: \.offset) { _, e in
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(e["wd"].string ?? "").sType(SType(size: 12, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                                    Text(e["md"].string ?? "").sType(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink).lineLimit(1)
                                }
                                .frame(width: 56, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e["title"].string ?? "").sType(SType(size: 16, weight: 600, line: 21, tracking: 0), tabular: false).foregroundStyle(S.ink)
                                    if let s = e["sub"].string, !s.isEmpty {
                                        Text(BriefWords.plain(s, privacy: privacy)).sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 10)
                            .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, 10)
                }
            }
            if ev.count > 5 {
                Button { withAnimation(S.moving(.easeInOut(duration: 0.25), reduce) ?? .linear(duration: 0)) { allEvents.toggle() } } label: {
                    Text(allEvents ? "Show fewer" : "Show all \(ev.count)").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false)
                        .foregroundStyle(S.ink).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 4 · Realized P&L

    private var realized: some View {
        let R = t["realized"], months = R["byMonth"].array
        let sel = month ?? months.last?["m"].string
        return VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Realized P&L").sType(SType(size: 22, weight: 700, line: 28, tracking: -0.01), tabular: false).foregroundStyle(S.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("What closed or expired, both accounts").sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(S.secondary)
            }
            .padding(.bottom, 8)
            realRow("This month", R["month"]["per"])
            realRow("Year to date", R["year"]["per"])
            if !months.isEmpty { bars(months, sel: sel, trend: R["trend"]) }
            let dv = R["dividends"]["year"].array.compactMap(\.double)
            if dv.reduce(0, +) > 0.5 {
                let who = zip(names, dv).filter { $0.1 > 0.5 }
                Text(BriefWords.plain("Dividends, kept apart: \(k(dv.reduce(0, +))) this year" + (names.count > 1 && who.count > 0 ? " · " + who.map { "\($0.0) \(k($0.1))" }.joined(separator: " · ") : ""), privacy: privacy))
                    .sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.secondary)
                    .padding(.top, 10)
                    .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
            }
        }
    }

    private func realRow(_ l: String, _ per: JSONValue) -> some View {
        let vs = per.array.map { $0.double ?? 0 }, tot = vs.reduce(0, +)
        return VStack(alignment: .trailing, spacing: 2) {
            HStack {
                Text(l).sType(SType(size: 17, weight: 500, line: 22, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Spacer()
                Text(k(tot)).sType(SType(size: 17, weight: 700, line: 22, tracking: 0)).foregroundStyle(tone(tot))
            }
            if names.count > 1 {
                HStack(spacing: 12) {
                    ForEach(Array(zip(names, vs).enumerated()), id: \.offset) { _, x in
                        (Text("\(x.0) ").foregroundStyle(S.secondary) + Text(k(x.1)).fontWeight(.semibold).foregroundStyle(tone(x.1)))
                            .sType(SType(size: 12, weight: 500, line: 16, tracking: 0))
                    }
                }
            }
        }
        .frame(minHeight: 44).padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    /// Stacked bars a month (each account's part; a month that lost runs down from the baseline in red), the dashed
    /// straight-line trend through the totals, a tap reading a month under the chart.
    private func bars(_ months: [JSONValue], sel: String?, trend: JSONValue) -> some View {
        let tots = months.map { $0["total"].double ?? 0 }
        let pos = months.map { m in m["per"].array.map { max(0, $0.double ?? 0) }.reduce(0, +) }
        let neg = months.map { m in m["per"].array.map { min(0, $0.double ?? 0) }.reduce(0, +) }
        let fit = trend["fit"].array.compactMap(\.double)
        let hi = max(1, (pos + fit).max() ?? 1) * 1.02, lo = min(0, (neg + fit).min() ?? 0) * 1.02
        let H: CGFloat = 132, Y = { (v: Double) in CGFloat((hi - v) / (hi - lo)) * H }
        let cols = [S.green, S.dynA(0x327133, 0.36, 0x65C466, 0.42)], negCols = [S.red, S.dynA(0xBC2E30, 0.36, 0xFF6961, 0.42)]
        let pick = months.first { $0["m"].string == sel } ?? months.last
        let slope = trend["slope"].double ?? 0
        let today = t["today"].string ?? "", dd = Int(today.suffix(2)) ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("By month").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    ForEach(Array(names.enumerated()), id: \.offset) { i, n in
                        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(cols[min(i, 1)]).frame(width: 8, height: 8); Text(n) }
                    }
                    if !fit.isEmpty {
                        HStack(spacing: 5) {
                            Path { p in p.move(to: CGPoint(x: 0, y: 2)); p.addLine(to: CGPoint(x: 14, y: 2)) }
                                .stroke(S.ink.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])).frame(width: 14, height: 4)
                            Text("Trend")
                        }
                    }
                }
                .sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary)
            }
            HStack(spacing: 0) {
                ForEach(Array(months.enumerated()), id: \.offset) { i, m in
                    let on = m["m"].string == pick?["m"].string
                    Text(k(tots[i])).sType(SType(size: 12, weight: on ? 700 : 500, line: 16, tracking: 0)).foregroundStyle(on ? tone(tots[i]) : S.secondary)
                        .frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .padding(.bottom, -4)
            .accessibilityHidden(true)
            GeometryReader { g in
                let w = g.size.width, cw = w / CGFloat(max(1, months.count)), bw = min(48, cw * 0.62)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(S.line).frame(width: w, height: 1).offset(y: Y(0))
                    ForEach(Array(months.enumerated()), id: \.offset) { i, m in
                        let per = m["per"].array.map { $0.double ?? 0 }, on = m["m"].string == pick?["m"].string
                        let x0 = cw * CGFloat(i) + (cw - bw) / 2
                        // Up from the baseline: each account's gain stacked (Sunny first); down: each account's loss.
                        let ups = per.map { max(0, $0) }, downs = per.map { min(0, $0) }
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(ups.enumerated()), id: \.offset) { a, v in
                                if v > 0 {
                                    let below = ups.prefix(a).reduce(0, +)
                                    Rectangle().fill(cols[min(a, 1)]).frame(width: bw, height: max(0, Y(below) - Y(below + v))).offset(x: x0, y: Y(below + v))
                                }
                            }
                            ForEach(Array(downs.enumerated()), id: \.offset) { a, v in
                                if v < 0 {
                                    let above = downs.prefix(a).reduce(0, +)
                                    Rectangle().fill(negCols[min(a, 1)]).frame(width: bw, height: max(0, Y(above + v) - Y(above))).offset(x: x0, y: Y(above))
                                }
                            }
                        }
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 3, bottomTrailingRadius: 3, topTrailingRadius: 6).offset(x: x0).size(width: bw, height: H))
                        .opacity(on ? 1 : 0.55)
                        .animation(.easeOut(duration: 0.25), value: on)
                        Color.clear.frame(width: cw, height: H).contentShape(Rectangle()).offset(x: cw * CGFloat(i))
                            .onTapGesture { month = m["m"].string }
                            .accessibilityElement()
                            .accessibilityLabel(BSay.words("\(m["l"].string ?? "")\(m["part"].bool ? " to \(Self.md(today))" : ""): \(k(tots[i]))", privacy: privacy))
                            .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                    }
                    if fit.count == months.count, fit.count > 1 {
                        Path { p in
                            for (i, v) in fit.enumerated() {
                                let pt = CGPoint(x: cw * (CGFloat(i) + 0.5), y: Y(v))
                                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                            }
                        }
                        .stroke(S.ink.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 4]))
                        .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: H)
            HStack(spacing: 0) {
                ForEach(Array(months.enumerated()), id: \.offset) { _, m in
                    let on = m["m"].string == pick?["m"].string
                    VStack(spacing: 0) {
                        Text(m["s"].string ?? "").sType(SType(size: 12, weight: on ? 700 : 500, line: 16, tracking: 0), tabular: false).foregroundStyle(on ? S.ink : S.secondary)
                        if m["part"].bool { Text("to \(dd)").sType(SType(size: 11, weight: 500, line: 14, tracking: 0)).foregroundStyle(S.secondary) }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, -4)
            .accessibilityHidden(true)
            if let pk = pick {
                let tot = pk["total"].double ?? 0, per = pk["per"].array
                VStack(alignment: .leading, spacing: 4) {
                    (Text("\(pk["l"].string ?? "")\(pk["part"].bool ? " to \(Self.md(today))" : "") ") + Text(k(tot)).foregroundStyle(tone(tot)))
                        .sType(SType(size: 14, weight: 600, line: 20, tracking: 0)).foregroundStyle(S.ink)
                    if names.count > 1 {
                        HStack(spacing: 12) {
                            ForEach(Array(names.enumerated()), id: \.offset) { i, n in
                                let v = per.indices.contains(i) ? per[i].double : nil
                                (Text("\(n) ").foregroundStyle(S.secondary) + (v.map { Text(k($0)).fontWeight(.semibold).foregroundStyle(tone($0)) } ?? Text("not yet").foregroundStyle(S.secondary)))
                                    .sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                            }
                        }
                    }
                }
                .padding(.top, 10)
                .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
                .accessibilityElement(children: .combine)
            }
            if fit.count > 1 {
                let starts = t["realized"]["starts"].array
                let since = starts.count > 1 ? " \(starts[1]["name"].string ?? "") from \(starts[1]["md"].string ?? "")." : ""
                (Text("Trend \(slope < 0 ? "▼" : "▲") \(k(slope)) a month").fontWeight(.semibold).foregroundStyle(tone(slope))
                 + Text(" since \(trend["since"].string ?? ""), \(names.count > 1 ? "both accounts" : "your account").\(since) \(months.last?["l"].string ?? "") runs to \(Self.wmd(today)).").foregroundStyle(S.secondary))
                    .sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 14).padding(.bottom, 6)
        .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
    }

    // MARK: - Words

    private func k(_ v: Double) -> String { privacy ? BriefMask.shown : F.moneyK(v) }
    private func tone(_ v: Double) -> Color { v > 0.5 ? S.green : v < -0.5 ? S.red : S.secondary }
    static func n0(_ v: Double) -> String { Int(v.rounded()).formatted(.number.grouping(.automatic)) }
    static func pc(_ x: Double) -> String { let a = abs(x) * 100; return String(format: a > 0 && a < 0.1 ? "%.2f%%" : "%.1f%%", a) }
    private static let MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let WD = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static func md(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return iso }
        return "\(MON[p[1] - 1]) \(p[2])"
    }
    static func wmd(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let d = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: p[0], month: p[1], day: p[2], hour: 12)) else { return iso }
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return "\(WD[c.component(.weekday, from: d) - 1]) \(md(iso))"
    }
}
