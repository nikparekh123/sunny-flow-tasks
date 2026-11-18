//
//  PositionsIntelView.swift
//  Sunny
//
//  Intelligence for this week on the phone, round 160b (Nik, 16 Nov 2026, final; handoff 2026-11-18 CHANGES Nov 16 and
//  §2.5, SunnyPositionsPhone r160): the title and the expiry, Today's alerts, the read, then a card per lane in the order
//  Held, SD and IV, Gamma Exposure, Technicals, Move. Each card: a dot and its name, one line under it (Held: what was
//  sold for; the rest: when its source was last updated), one sentence (thick then thin), the track, three numbers.
//  Every track spans about 1.6 SD around today (wider to take in the sold strikes); a mark past it waits at the edge
//  with an arrow. The sold strikes are dashed on every track; today is the line and the tag. IV is folded into SD.
//  Copy rules: the flip reads "Calmer above" or "Faster below" from the price side; touched or closed through is said
//  once; a 0.0% move reads "Flat". View only. No em dashes in any words here.
//

import SwiftUI

struct PosIntelView: View {
    let t: String
    let intel: PosIntel?
    let failed: Bool
    let loaded: Bool
    let privacy: Bool
    @Binding var box: String?
    let reduce: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Intelligence").sType(PT.t(22, 28, 700), tabular: false).foregroundStyle(PC.ink).accessibilityAddTraits(.isHeader)
                Text(intel?.sub ?? "This week").sType(PT.t(13, 18), tabular: false).foregroundStyle(PC.mu)
            }
            if let m = intel {
                if !m.alerts.isEmpty { alerts(m) }
                theRead(m)
                ForEach(PosLane.all(m)) { L in PosLaneCard(L: L, m: m, privacy: privacy) }
            } else {
                Text(failed ? "Could not read \(t)’s option chain just now." : loaded ? "No expiries for \(t) this week." : "Reading \(t)’s option chain…")
                    .sType(PT.t(14, 20), tabular: false).foregroundStyle(PC.mu)
            }
        }
    }

    /// One chip per level hit today: closed through first (a capsule with ↑ or ↓), then touched (a yellow outline).
    private func alerts(_ m: PosIntel) -> some View {
        SXFlowGaps(column: 6, row: 6) {
            Text("TODAY").sType(PT.kicker, tabular: false).foregroundStyle(PC.mu).frame(height: 26)
            ForEach(m.alerts) { a in
                let closed = a.state != .touch
                HStack(spacing: 5) {
                    if !closed { Circle().fill(PC.touched).frame(width: 6, height: 6) }
                    Text(a.text).sType(PT.t(12, 16, 600), tabular: false).lineLimit(1)
                }
                .foregroundStyle(closed ? PC.onInk : PC.touched)
                .padding(.horizontal, 10).frame(height: 26)
                .background { Capsule().fill(closed ? PC.ink : PC.touched.opacity(0.12)) }
                .overlay { if !closed { Capsule().strokeBorder(PC.touched.opacity(0.55), lineWidth: 1) } }
                .accessibilityLabel(PosSay.words(a.text))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Alerts today")
    }

    /// The read (§3.9.4): the lead 600 in ink, the rest 400 at .72; four lines' room held; fades in on change.
    private func theRead(_ m: PosIntel) -> some View {
        let key = m.read.lead + m.read.rest
        let kick = "The read · \(m.long) · \(m.readOn)"
        return VStack(alignment: .leading, spacing: 6) {
            Text(kick.uppercased()).sType(PT.kicker, tabular: false).foregroundStyle(PC.mu)
            ZStack(alignment: .topLeading) {
                Text("\(Text(m.read.lead).font(.inter(17, 600)).foregroundStyle(PC.ink)) \(Text(m.read.rest).font(.inter(17, 400)).foregroundStyle(PC.ink.opacity(0.72)))")
                    .sType(PT.t(17, 24), tabular: false)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(key)
                    .transition(reduce ? .identity : .opacity.combined(with: .offset(y: 3)))
            }
            .animation(reduce ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.4), value: key)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PosSay.words("\(kick). \(m.read.lead) \(m.read.rest)"))
    }
}

// MARK: - The lanes (160b)

/// One lane card's content, worked out from PosIntel (r160): what it says, its colours and its marks.
struct PosLane: Identifiable {
    let id: String
    let name: String
    let dot: Color
    /// The line under the name: Held what it was sold for, the rest when the source was last updated.
    let line: String
    let thick: String
    let thin: String
    let base: Color
    let boxes: [PosIntel.Box]
    /// Marks past the track's ends (the nearest on each side waits at the edge with an arrow).
    let offs: [(p: Double, txt: String, c: Color)]

    static let sdBands: [(k: Double, c: Color)] = [(2, Color(hex: 0x42487B)), (1.5, Color(hex: 0x575D99)), (1, Color(hex: 0x7177B5)),
                                                    (0.75, Color(hex: 0x8E93C9)), (0.5, Color(hex: 0xADB1D7)), (0.25, Color(hex: 0xCDCFE5))]

    static func all(_ m: PosIntel) -> [PosLane] {
        let S = m.S, cap = { (s: String) in s.prefix(1).uppercased() + s.dropFirst() }
        let fk = { (x: Double) in PE.num(x, 2) }
        let rename: [String: String] = ["Breakeven down": "Breakeven ↓", "Breakeven up": "Breakeven ↑", "Chance of profit": "Chance ahead"]
        func boxes(_ bs: [PosIntel.Box]?) -> [PosIntel.Box] {
            (bs ?? []).map { b in
                var x = PosIntel.Box(id: b.id, label: rename[b.label] ?? b.label, dot: b.dot ?? Self.dotOf(b.label), value: b.value, valueTone: b.valueTone,
                                     sub: b.sub, subTone: b.subTone, subMoney: b.subMoney)
                if x.label == "Flip" { x.dot = .orange }
                return x
            }
        }
        // "touched" or "closed through" said once, after the rest: " Ceiling touched today."
        func hot(_ bs: [PosIntel.Box]?) -> String {
            (bs ?? []).filter { $0.sub.contains("touched") || $0.sub.contains("closed above") || $0.sub.contains("closed below") }
                .map { " \($0.label) \($0.sub)." }.joined()
        }
        var out: [PosLane] = []
        // Held: the profit zone between the breakevens, red past them.
        let L = m.LH, none = !L.has || L.none || m.held.isEmpty
        let hb = boxes(m.boxes.held)
        let bD = L.dn.map(PE.f2), bU = L.up.map(PE.f2)
        out.append(PosLane(id: "h", name: "Held", dot: PC.green, line: none ? "nothing for \(m.label)" : "sold for \(m.label)",
            thick: none ? "Nothing sold for \(m.label)." : "\(String(format: "%.1f", L.cp * 100))% chance you finish ahead.",
            thin: none ? " This fills once you sell for this week." : " You are ahead between \(bD ?? "any price") and \(bU ?? "any price").",
            base: none ? PC.faint : PC.red.opacity(0.30), boxes: none ? [] : hb,
            offs: none ? [] : [L.dn, L.up].compactMap { $0 }.map { (p: $0, txt: "BE \(String(format: "%.2f", $0))", c: PC.green) }))
        // SD and IV: one lane, IV is what the move is priced from.
        let zs = m.held.sorted { $0.K < $1.K }.map { l -> String in
            let itm = l.put ? S < l.K : S > l.K, z = abs(PE.zOf(l.K, S, m.m))
            return (l.put ? "put " : "call ") + fk(l.K) + (itm ? " is in the money" : " sits \(String(format: "%.2f", z)) SD out")
        }
        let tone = m.ivTone == .rich ? "rich" : m.ivTone == .cheap ? "cheap" : m.ivTone == .fair ? "fair" : nil
        var sdB = boxes(m.boxes.sd.filter { $0.id != "mv" })
        sdB.append(PosIntel.Box(id: "iv", label: "IV", value: String(format: "%.1f%%", m.ivNow * 100), sub: [tone.map(cap), m.ivRank.map { "rank \(Int($0))" }].compactMap { $0 }.joined(separator: " · ")))
        out.append(PosLane(id: "s", name: "SD and IV", dot: Color(hex: 0x8E93C9), line: m.upd["s"] ?? "",
            thick: "±\(String(format: "%.1f", m.m * 100))% priced in by \(m.label).",
            thin: (zs.isEmpty ? "" : " Your " + zs.joined(separator: ", your ") + ".") + " IV \(String(format: "%.1f", m.ivNow * 100))%\(tone.map { ", " + $0 } ?? "").",
            base: PC.faint, boxes: sdB, offs: []))
        // Gamma Exposure: the walls as bars (height by gamma), the flip an orange dot.
        let ce = m.lv.wall("ceiling"), fl = m.lv.wall("floor"), cS = m.held.filter { !$0.put }.min { $0.K < $1.K }, pS = m.held.filter(\.put).max { $0.K < $1.K }
        let pos = { (K: Double, W: Double) in abs(K - W) < 1e-6 ? "on" : K > W ? "above" : "under" }
        let rel = [cS.flatMap { c in ce.map { "your call sits \(pos(c.K, $0.K)) the ceiling" } }, pS.flatMap { p in fl.map { "your put \(pos(p.K, $0.K)) the floor" } }]
            .compactMap { $0 }.joined(separator: ", ")
        let flipT = m.lv.flip.map { (S >= $0 ? " Calmer above " : " Faster below ") + PE.f2($0) + "." } ?? ""
        if m.boxes.gamma != nil {
            out.append(PosLane(id: "g", name: "Gamma Exposure", dot: PC.ceiling, line: m.upd["g"] ?? "",
                thick: (ce.map { "Ceiling \(fk($0.K))" } ?? "No ceiling") + ", " + (fl.map { "floor \(fk($0.K))" } ?? "no floor") + ".",
                thin: (rel.isEmpty ? "" : " " + cap(rel) + ".") + flipT + hot(m.boxes.gamma),
                base: PC.ceiling.opacity(0.10), boxes: boxes(m.boxes.gamma),
                offs: m.lv.walls.map { w in (p: w.K, txt: "\(cap(w.kind)) \(fk(w.K))", c: w.kind == "ceiling" ? PC.ceiling : PC.floor) }))
        }
        // Technicals: support filled, resistance hatched, the averages as ticks.
        if m.boxes.tech != nil {
            let avg: [(Int, Double?)] = [(20, m.lv.pe.sma20), (50, m.lv.pe.sma50), (100, m.lv.pe.sma100), (200, m.lv.pe.sma200)]
            let held = avg.compactMap { a in a.1.flatMap { $0 < S ? a.0 : nil } }
            let rsiT = m.rsi.map { ", RSI \(Int(PE.jsRound($0))) \(PosIntel.rsiWord($0))" } ?? ""
            out.append(PosLane(id: "t", name: "Technicals", dot: PC.teal, line: m.upd["t"] ?? "",
                thick: (m.lv.pe.support.map { "Support " + PE.f2($0) } ?? "No support") + ", " + (m.lv.pe.resistance.map { "resistance " + PE.f2($0) } ?? "no resistance") + ".",
                thin: (held.isEmpty ? " Under all four averages" : " Above the " + held.map(String.init).joined(separator: ", ") + "-day " + (held.count > 1 ? "averages" : "average")) + rsiT + "." + hot(m.boxes.tech),
                base: PC.teal.opacity(0.08), boxes: boxes(m.boxes.tech),
                offs: [(m.lv.pe.support, "Support"), (m.lv.pe.resistance, "Resistance")].compactMap { p, l in p.map { (p: $0, txt: "\(l) \(String(format: "%.2f", $0))", c: PC.teal2) } }
                    + avg.compactMap { a in a.1.map { (p: $0, txt: "\(a.0)-day \(String(format: "%.2f", $0))", c: PC.teal2) } }))
        }
        // Move: last Friday's close to today, then the 5-day pace carried to the expiry (dashed).
        if let mv = m.move {
            let w = { (r: Double) -> String in abs(r) < 0.0005 ? "flat" : (r < 0 ? "down " : "up ") + String(format: "%.1f", abs(r) * 100) + "%" }
            let mo = mv.pace.map { $0.flat ? "flat" : $0.r5 < 0 ? "falling" : "rising" }
            out.append(PosLane(id: "m", name: "Move", dot: PC.muT, line: m.upd["m"] ?? "",
                thick: mv.tw.map { w($0.r) == "flat" ? "Flat this week." : cap(w($0.r)) + " this week." } ?? "This week so far.",
                thin: (mv.lw.map { " Last week " + w($0.r) } ?? "") + (mo.map { (mv.lw == nil ? " Momentum " : ", momentum ") + $0 } ?? "") + ".",
                base: PC.faint, boxes: boxes(m.boxes.move),
                offs: mv.tw.map { [(p: $0.from, txt: "Fri \(String(format: "%.2f", $0.from))", c: PC.muT)] } ?? []))
        }
        return out
    }

    static func dotOf(_ label: String) -> PTone? {
        switch label { case "Ceiling": .ceiling; case "Floor": .floor; case "Flip": .orange; case "Support": .teal; case "Resistance": .teal2; default: nil }
    }
}

/// One lane card (r160 markup): radius 22, padding 16, the soft fill and edge; 12 between its parts.
struct PosLaneCard: View {
    let L: PosLane
    let m: PosIntel
    let privacy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Circle().fill(L.dot).frame(width: 8, height: 8)
                    Text(L.name).sType(PT.t(13, 16, 600), tabular: false).foregroundStyle(PC.say)
                }
                if !L.line.isEmpty { Text(L.line).sType(PT.t(12, 16), tabular: false).foregroundStyle(PC.mu).padding(.leading, 16) }
            }
            Text("\(Text(L.thick).font(.inter(17, 600)).foregroundStyle(PC.ink))\(Text(L.thin).font(.inter(17, 400)).foregroundStyle(PC.ink.opacity(0.72)))")
                .sType(PT.t(17, 24), tabular: false)
                .fixedSize(horizontal: false, vertical: true)
            PosLaneTrack(L: L, m: m).frame(height: 64).accessibilityHidden(true)
            if !L.boxes.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(L.boxes) { q in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                if let d = q.dot { Circle().fill(PC.of(d)).frame(width: 6, height: 6) }
                                Text(q.label).sType(PT.t(12, 16), tabular: false).foregroundStyle(PC.mu).fixedSize(horizontal: false, vertical: true)
                            }
                            Text(q.value).sType(PT.t(17, 22, 600)).foregroundStyle(PC.of(q.valueTone)).minimumScaleFactor(0.8).lineLimit(1)
                            if !q.sub.isEmpty {
                                Text(q.subMoney && privacy ? BriefMask.mask(q.sub) : q.sub).sType(PT.t(12, 16), tabular: false)
                                    .foregroundStyle(PC.of(q.subTone == .quiet ? .quiet : q.subTone)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(PosSay.words("\(q.label), \(q.value)" + (q.sub.isEmpty ? "" : ", " + (q.subMoney && privacy ? "hidden" : q.sub))))
                    }
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(PC.rule).frame(height: 1) }
            }
        }
        .padding(16)
        .modifier(PosSoftCard(radius: 22))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(PosSay.words("\(L.name). \(L.thick)\(L.thin)"))
    }
}

/// The track: 64 tall, the lane's base 24 tall at 18 (radius 7), its marks inside, the sold strikes dashed over it, today
/// the line and the tag, the strike names over it and the marks past its ends at the edges.
struct PosLaneTrack: View {
    let L: PosLane
    let m: PosIntel

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, S = m.S, mm = m.m
            let sold = m.held.sorted { $0.K < $1.K }
            let lo = sold.reduce(S * (1 - 1.6 * mm)) { min($0, $1.K - S * mm * 0.3) }, hi = sold.reduce(S * (1 + 1.6 * mm)) { max($0, $1.K + S * mm * 0.3) }
            let X = { (p: Double) in CGFloat((p - lo) / (hi - lo)) * w }, xc = { (p: Double) in min(w, max(0, X(p))) }
            let inR = { (p: Double?) in p.map { $0 >= lo && $0 <= hi } ?? false }
            ZStack(alignment: .topLeading) {
                // The base and the lane's marks, clipped to it.
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(L.base)
                    marks(lo: lo, hi: hi, w: w, X: X, xc: xc, inR: inR)
                }
                .frame(width: w, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .offset(y: 18)
                // The sold strikes dashed, today the line.
                ForEach(Array(sold.enumerated()), id: \.offset) { _, l in
                    Path { p in p.move(to: CGPoint(x: xc(l.K), y: 16)); p.addLine(to: CGPoint(x: xc(l.K), y: 44)) }
                        .stroke(PC.ink.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
                Rectangle().fill(PC.ink).frame(width: 2, height: 32).offset(x: xc(S) - 1, y: 14)
                // The strike names over the track.
                ForEach(Array(sold.enumerated()), id: \.offset) { _, l in
                    tag("\(PE.num(l.K, 2)) \(l.put ? "put" : "call")", at: xc(l.K), w: w, y: 0, color: PC.say)
                }
                // Today's tag, then the nearest mark past each end.
                Text(String(format: "%.2f", S)).sType(PT.t(11, 16, 700)).foregroundStyle(PC.onInk).fixedSize()
                    .padding(.horizontal, 6).frame(height: 16).background(Capsule().fill(PC.ink))
                    .alignmentGuide(.leading) { d in d.width / 2 - xc(S) }.alignmentGuide(.top) { _ in -46 }
                ForEach(edges(lo: lo, hi: hi), id: \.txt) { e in
                    Text(e.txt).sType(PT.t(11, 16, 600), tabular: false).foregroundStyle(e.c).fixedSize()
                        .frame(width: w, alignment: e.left ? .leading : .trailing).offset(y: 46)
                }
            }
        }
    }

    private func tag(_ s: String, at x: CGFloat, w: CGFloat, y: CGFloat, color: Color) -> some View {
        Text(s).sType(PT.t(11, 16, 600), tabular: false).foregroundStyle(color).fixedSize()
            .alignmentGuide(.leading) { d in x < w * 0.1 ? -x : x > w * 0.9 ? d.width - x : d.width / 2 - x }
            .alignmentGuide(.top) { _ in -y }
    }

    private func edges(lo: Double, hi: Double) -> [(txt: String, c: Color, left: Bool)] {
        var out: [(txt: String, c: Color, left: Bool)] = []
        if let o = L.offs.filter({ $0.p < lo }).max(by: { $0.p < $1.p }) { out.append(("← " + o.txt, o.c, true)) }
        if let o = L.offs.filter({ $0.p > hi }).min(by: { $0.p < $1.p }) { out.append((o.txt + " →", o.c, false)) }
        return out
    }

    @ViewBuilder
    private func marks(lo: Double, hi: Double, w: CGFloat, X: @escaping (Double) -> CGFloat, xc: @escaping (Double) -> CGFloat, inR: @escaping (Double?) -> Bool) -> some View {
        let S = m.S, mm = m.m
        switch L.id {
        case "h":
            if !L.boxes.isEmpty {
                let a = m.LH.dn.map(xc) ?? 0, b = m.LH.up.map(xc) ?? w
                Rectangle().fill(PC.green.opacity(0.55)).frame(width: max(0, b - a), height: 24).offset(x: a)
                ForEach([m.LH.dn, m.LH.up].compactMap { $0 }.filter { inR($0) }, id: \.self) { p in
                    Rectangle().fill(PC.green).frame(width: 2, height: 24).offset(x: X(p) - 1)
                }
            }
        case "s":
            ForEach(PosLane.sdBands, id: \.k) { b in
                let a = xc(S * (1 - b.k * mm)), c = xc(S * (1 + b.k * mm))
                Rectangle().fill(b.c).frame(width: max(0, c - a), height: 24).offset(x: a)
            }
        case "g":
            let gmax = max(1, m.lv.walls.map(\.gex).max() ?? 1)
            ForEach(m.lv.walls.filter { inR($0.K) }, id: \.kind) { wl in
                let h = 7 + wl.gex / gmax * 17
                UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                    .fill(wl.kind == "ceiling" ? PC.ceiling : wl.kind == "floor" ? PC.floor : PC.floor.opacity(0.55))
                    .frame(width: 6, height: h).offset(x: X(wl.K) - 3, y: 24 - h)
            }
            if let f = m.lv.flip, inR(f) { Circle().fill(PC.orange).frame(width: 10, height: 10).offset(x: X(f) - 5, y: 7) }
        case "t":
            let zw = S * mm * 0.14
            if let sp = m.lv.pe.support, inR(sp) {
                Rectangle().fill(PC.teal.opacity(0.55)).frame(width: max(0, xc(sp + zw) - xc(sp - zw)), height: 24).offset(x: xc(sp - zw))
            }
            if let rs = m.lv.pe.resistance, inR(rs) {
                PosHatch(color: PC.teal2.opacity(0.75))
                    .frame(width: max(0, xc(rs + zw) - xc(rs - zw)), height: 24).clipped().offset(x: xc(rs - zw))
            }
            ForEach([(20, m.lv.pe.sma20), (50, m.lv.pe.sma50), (100, m.lv.pe.sma100), (200, m.lv.pe.sma200)].filter { inR($0.1) }, id: \.0) { a in
                let x = X(a.1!)
                Rectangle().fill(PC.teal2).frame(width: 2, height: 24).offset(x: x - 1)
                Text("\(a.0)d").sType(PT.t(11, 24, 600), tabular: false).foregroundStyle(PC.teal2).fixedSize()
                    .offset(x: x > w * 0.88 ? x - 28 : x + 4)
            }
        case "m":
            if let tw = m.move?.tw {
                let lc = tw.from, a = min(xc(lc), xc(S)), b = max(xc(lc), xc(S))
                RoundedRectangle(cornerRadius: 2).fill(S >= lc ? PC.green : PC.red).frame(width: max(0, b - a), height: 3).offset(x: a, y: 10.5)
                if inR(lc) {
                    Circle().fill(PC.page).overlay(Circle().strokeBorder(PC.muT, lineWidth: 2)).frame(width: 10, height: 10).offset(x: X(lc) - 5, y: 7)
                }
            }
            if let p = m.move?.pace, !p.flat, abs(p.to - S) > 1e-6 {
                Path { q in q.move(to: CGPoint(x: xc(min(S, p.to)), y: 12)); q.addLine(to: CGPoint(x: xc(max(S, p.to)), y: 12)) }
                    .stroke(PC.muT, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
        default: EmptyView()
        }
    }
}
