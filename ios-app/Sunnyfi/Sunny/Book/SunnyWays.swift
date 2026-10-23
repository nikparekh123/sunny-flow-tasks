//
//  SunnyWays.swift
//  Sunny
//
//  Block 13c (handoff 31, 23 Oct 2026) · the To do face of a Position card as
//  two blocks behind two chips, Sell · Oct 30 and Buy · Jan. Every trade shows
//  its ways as 124 pt square tiles in a sideways row, nearest the money first;
//  the rule's pick is green and nothing else is colored. The panel under the
//  tiles reads the tapped way as the trade. Nothing is ticked: whatever IBKR
//  shows shrinks the counts on the server, and a trade leaves once filled.
//

import SwiftUI

/// One way as a tile: ways on the same strike share one tile ("Rule · 1st wall").
struct PWay: Identifiable, Hashable {
    var id: String { ids[0] }
    var ids: [String]
    var labels: [String]
    let tile: NameWays.Tile
    var g: Double?
    var was: Double?
    var label: String { labels.joined(separator: " · ") }
}

/// One trade on the face: sell calls, sell puts, buy calls, or the put walls to buy at. With nothing to
/// trade on a side its walls still show (cw, pw, bw: Nik, 23 Oct 2026, "we can say nothing to trade in
/// the grey box but still need to show for all").
struct PTrade: Identifiable {
    enum Kind: String { case sc, sp, bc, bp, cw, pw, bw }
    let kind: Kind
    var id: String { kind.rawValue }
    let head: String
    let sub: String
    let ways: [PWay]
    /// The rule's pick (green), none on the put walls.
    let pick: String?
    var sell: Bool { kind == .sc || kind == .sp }
    var call: Bool { kind == .sc || kind == .bc }
    /// Walls only: nothing to trade on this side.
    var walls: Bool { kind == .cw || kind == .pw || kind == .bw }
    /// A trade to do (the badge counts these).
    var todo: Bool { kind == .sc || kind == .sp || kind == .bc }
}

enum PWays {
    enum Block: Hashable { case sell, buy }

    /// The trades in a block, in the design's order.
    static func trades(_ w: NameWays, _ b: Block) -> [PTrade] {
        switch b {
        case .sell:
            var out: [PTrade] = []
            let md = PF.monthDay(w.sell.exp)
            if let c = w.sell.calls, let n = c.n, n > 0, let ts = c.tiles {
                out.append(PTrade(kind: .sc, head: "Sell \(n) \(md) \(n == 1 ? "call" : "calls")",
                                  sub: "One per LEAP · \(c.rule ?? "ATM") · " + soldWords(c.sold),
                                  ways: merge(ts, rule: c.rule ?? "ATM"), pick: c.pick))
            } else if let c = w.sell.calls, let ts = c.tiles, !ts.isEmpty {
                out.append(PTrade(kind: .cw, head: "\(md) calls",
                                  sub: ((c.sold ?? 0) > 0 ? "\(c.sold!) sold · nothing left to sell" : "Nothing to sell") + " · the walls",
                                  ways: merge(ts, rule: "ATM"), pick: nil))
            }
            if let p = w.sell.puts, !p.isPaused, let n = p.n, n > 0, let ts = p.tiles {
                out.append(PTrade(kind: .sp, head: "Sell \(n) \(md) \(n == 1 ? "put" : "puts")",
                                  sub: "From the put cap · " + (p.rule == "1st wall" ? "the put wall" : "the rule's strike") + " · " + soldWords(p.sold),
                                  ways: merge(ts, rule: "Rule"), pick: p.pick))
            } else if let p = w.sell.puts, let ts = p.tiles, !ts.isEmpty {
                let why = p.isPaused ? "Paused · below the 50-day" + (p.s50.map { " \(PF.price($0))" } ?? "")
                    : (p.sold ?? 0) > 0 ? "\(p.sold!) sold · nothing left to sell" : "Nothing to sell"
                out.append(PTrade(kind: .pw, head: "\(md) puts", sub: why + " · the walls",
                                  ways: merge(ts, rule: "Rule"), pick: nil))
            }
            return out
        case .buy:
            var out: [PTrade] = []
            if let c = w.buy.calls, c.left > 0 {
                out.append(PTrade(kind: .bc, head: "Need \(us(c.need)) Δ",
                                  sub: (c.inn > 0 ? "\(us(c.inn)) in · " : "None in yet · ") + "\(us(c.left)) left · \(month(c.exp)) calls, follow the wall",
                                  ways: merge(c.tiles, rule: "Rule"), pick: c.pick))
            } else if let c = w.buy.calls, !c.tiles.isEmpty {
                out.append(PTrade(kind: .bw, head: "\(month(c.exp)) calls", sub: "Delta covered · nothing to buy · the walls",
                                  ways: merge(c.tiles, rule: "Rule"), pick: nil))
            }
            if let p = w.buy.puts, !p.tiles.isEmpty {
                out.append(PTrade(kind: .bp, head: "\(month(p.exp)) puts",
                                  sub: (p.held > 0 ? "\(p.held) held" : "None held") + " · the walls, you pick the size",
                                  ways: merge(p.tiles, rule: "Rule"), pick: nil))
            }
            return out
        }
    }

    /// "Sell · Oct 30", "Buy · Jan" (the months the buys sit in).
    static func chip(_ w: NameWays, _ b: Block) -> String {
        switch b {
        case .sell: return "Sell · " + PF.monthDay(w.sell.exp)
        case .buy:
            let ms = [w.buy.calls?.exp, w.buy.puts?.exp].compactMap { $0 }.map(month).reduce(into: [String]()) { a, m in if !a.contains(m) { a.append(m) } }
            return ms.isEmpty ? "Buy" : "Buy · " + ms.joined(separator: " and ")
        }
    }

    private static func soldWords(_ n: Int?) -> String { (n ?? 0) > 0 ? "\(n!) sold" : "none sold yet" }

    /// Tiles on one strike share a tile, the wall's gamma and last week's strike kept; nearest the money first,
    /// shares last. The price is the server's spot at the build, so the order holds while the tiles are read.
    private static func merge(_ ts: [NameWays.Tile], rule: String) -> [PWay] {
        var out: [PWay] = []
        for t in ts {
            let l = label(t.id, rule: rule)
            if t.id != "sh", let i = out.firstIndex(where: { $0.tile.id != "sh" && abs($0.tile.k - t.k) < 1e-6 }) {
                out[i].ids.append(t.id); out[i].labels.append(l)
                if t.g != nil { out[i].g = t.g; out[i].was = t.was }
            } else {
                out.append(PWay(ids: [t.id], labels: [l], tile: t, g: t.g, was: t.was))
            }
        }
        return out
    }
    static func sorted(_ ws: [PWay], px: Double) -> [PWay] {
        ws.sorted { a, b in
            if a.tile.id == "sh" { return false }
            if b.tile.id == "sh" { return true }
            return abs(a.tile.k - px) < abs(b.tile.k - px)
        }
    }
    private static func label(_ id: String, rule: String) -> String {
        switch id {
        case "at": rule
        case "w": "1st wall"
        case "w2": "2nd wall"
        case "sd": "1.5 SD"
        default: "Shares"
        }
    }

    // MARK: Words and numbers

    /// 2,751 · no sign.
    static func us(_ v: Double) -> String { Int(abs(v).rounded()).formatted() }
    static func usd(_ v: Double) -> String { "$" + us(v) }
    /// Gamma at a wall: $6.3M · $570K.
    static func gamma(_ g: Double) -> String {
        let a = abs(g)
        if a >= 1e6 { return "$" + String(format: "%.1f", a / 1e6) + "M" }
        if a >= 1e3 { return "$\(Int((a / 1e3).rounded()))K" }
        return "$\(Int(a.rounded()))"
    }
    /// "Jan"
    static func month(_ iso: String) -> String { String(PF.monthDay(iso).prefix(3)) }
    static func weekday(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let d = Calendar(identifier: .gregorian).date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)) else { return "Thu" }
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][Calendar(identifier: .gregorian).component(.weekday, from: d) - 1]
    }
    static func dist(_ k: Double, _ px: Double) -> Double { abs(k / px - 1) * 100 }
}

// MARK: - The face

struct PWaysFace: View {
    let t: String
    let px: Double
    let w: NameWays
    /// Each card keeps its own chip and picks for the session.
    @Binding var block: PWays.Block
    @Binding var sel: [PWays.Block: String]
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let trades = PWays.trades(w, block).map { PTrade(kind: $0.kind, head: $0.head, sub: $0.sub, ways: PWays.sorted($0.ways, px: px), pick: $0.pick) }
        let cur = current(trades)
        VStack(alignment: .leading, spacing: 18) {
            chips
            let paused = block == .sell ? w.sell.puts.flatMap { $0.isPaused && ($0.tiles ?? []).isEmpty ? $0 : nil } : nil
            if trades.isEmpty && paused == nil {
                Text(block == .sell ? "Nothing to sell this week." : "Nothing to buy this week.")
                    .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                    .foregroundStyle(S.muted)
            }
            ForEach(trades) { tr in trade(tr, on: cur?.0.id == tr.id ? cur?.1.id : nil) }
            if let p = paused { pausedLine(p) }
            if let c = cur { panel(c.0, c.1, nothing: !trades.contains(where: \.todo)) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// The tapped way, else the first trade's pick (or its first way).
    private func current(_ trades: [PTrade]) -> (PTrade, PWay)? {
        if let s = sel[block] {
            let p = s.split(separator: ".").map(String.init)
            if p.count == 2, let tr = trades.first(where: { $0.id == p[0] }), let wy = tr.ways.first(where: { $0.ids.contains(p[1]) }) { return (tr, wy) }
        }
        guard let tr = trades.first(where: \.todo) ?? trades.first else { return nil }
        let wy = tr.ways.first { w in tr.pick.map { w.ids.contains($0) } ?? false } ?? tr.ways.first
        return wy.map { (tr, $0) }
    }

    // MARK: Chips

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach([PWays.Block.sell, .buy], id: \.self) { b in
                let on = b == block
                Button {
                    guard !on else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(reduce ? nil : S.standard(0.2)) { block = b }
                } label: {
                    Text(PWays.chip(w, b)).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false)
                        .foregroundStyle(on ? S.paper : S.muted)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Capsule().fill(on ? S.ink : S.track))
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(POpacityPress())
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.vertical, -6)
    }

    // MARK: A trade: its head, then its ways in a sideways row

    private func trade(_ tr: PTrade, on: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr.head).sType(SType(size: 17, weight: 700, line: 22, tracking: 0))
                    .foregroundStyle(S.ink)
                Text(tr.sub).sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                    .foregroundStyle(S.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(tr.ways) { wy in tile(tr, wy, selected: on == wy.id) }
                }
                .scrollTargetLayout()
                .padding(.top, 2).padding(.bottom, 4)
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
        }
    }

    /// The tile's five lines: label, strike, distance, then two values and the wall's gamma.
    private func tile(_ tr: PTrade, _ wy: PWay, selected: Bool) -> some View {
        let v = values(tr, wy), pick = tr.pick.map { wy.ids.contains($0) } ?? false
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduce ? nil : S.standard(0.2)) { sel[block] = "\(tr.id).\(wy.id)" }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(wy.label).sType(SType(size: 11, weight: 600, line: 13, tracking: 0), tabular: false).foregroundStyle(S.muted)
                Text(v.k).sType(SType(size: 17, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink)
                Text(v.dist).sType(SType(size: 11, weight: 600, line: 13, tracking: 0)).foregroundStyle(S.muted)
                Text(v.v3).sType(SType(size: 12, weight: 600, line: 14, tracking: 0)).foregroundStyle(v.v3c)
                    .frame(minHeight: 14).padding(.top, 7)
                Text(v.v4).sType(SType(size: 12, weight: 600, line: 14, tracking: 0)).foregroundStyle(v.v4c)
                if let gx = v.gx {
                    Text(gx).sType(SType(size: 11, weight: 600, line: 13, tracking: 0), tabular: false).foregroundStyle(S.muted)
                }
            }
            .lineLimit(1)
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(width: 124, height: 124, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pick ? S.greenTint : S.tile))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? S.ink : pick ? S.green : S.line, lineWidth: selected ? 2 : pick ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(v.a)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private struct Values {
        var k: String, dist: String, v3: String, v3c: Color, v4: String, v4c: Color, gx: String?, a: String
    }

    private func values(_ tr: PTrade, _ wy: PWay) -> Values {
        let x = wy.tile, us = PWays.us, usd = PWays.usd
        if x.id == "sh" {
            let n = Double(x.n ?? 0), cost = x.cost ?? n * px
            return Values(k: us(n), dist: "at $" + PF.price(px), v3: "", v3c: S.ink, v4: usd(cost), v4c: S.ink, gx: "kept",
                          a: "Shares, \(us(n)) shares at \(PF.price(px)), \(us(cost)) dollars, kept as shares")
        }
        let dp = PWays.dist(x.k, px), up = x.k >= px
        let dist = (up ? "↑ " : "↓ ") + String(format: "%.1f%%", dp)
        let gx = wy.g.map(PWays.gamma)
        var a = "\(wy.label), \(PF.strike(x.k)), \(String(format: "%.1f", dp)) percent \(up ? "above" : "below")"
        let ga = wy.g.map { ", gamma \(String(format: "%.1f", $0 / 1e6)) million" } ?? ""
        switch tr.kind {
        case .sc, .sp:
            let n = Double(sellN(tr)), dN = -n * 100 * (x.d ?? 0), cr = n * 100 * (x.mid ?? 0)
            a += ", delta \(dN < 0 ? "given up" : "added") \(us(dN)), \(us(cr)) dollars credit" + ga
            return Values(k: PF.strike(x.k), dist: dist, v3: dv(dN), v3c: dN < 0 ? S.red : S.ink, v4: usd(cr), v4c: S.green, gx: gx, a: a)
        case .bc:
            let n = x.n ?? 0, cost = x.cost ?? 0
            a += ", \(PF.count(n, "call")), \(us(cost)) dollars" + ga
            return Values(k: PF.strike(x.k), dist: dist, v3: PF.count(n, "call"), v3c: S.ink, v4: usd(cost), v4c: S.ink, gx: gx, a: a)
        case .bp, .cw, .pw, .bw:
            let each = (x.mid ?? 0) * 100, d = abs(x.d ?? 0)
            a += ", \(us(each)) dollars each, delta \(String(format: "%.2f", d)) each" + ga
            return Values(k: PF.strike(x.k), dist: dist, v3: usd(each) + " each", v3c: S.ink, v4: String(format: "%.2f Δ each", d), v4c: S.ink, gx: gx, a: a)
        }
    }

    private func sellN(_ tr: PTrade) -> Int { (tr.kind == .sc ? w.sell.calls?.n : w.sell.puts?.n) ?? 0 }
    /// Delta as the tiles write it: no sign when it is given up (red), a plus when it adds.
    private func dv(_ v: Double) -> String { v < 0 ? PWays.us(v) : "+" + PWays.us(v) }

    // MARK: Puts paused (Nik, 23 Oct 2026): one line

    private func pausedLine(_ p: NameWays.Trade) -> some View {
        (Text("Puts paused").font(SType(size: 13, weight: 600, line: 18, tracking: 0).font()).foregroundStyle(S.ink)
         + Text(p.s50.map { " · below the 50-day \(PF.price($0))" } ?? " · below the 50-day")
            .font(SType(size: 13, weight: 500, line: 18, tracking: 0).font(tabular: true)).foregroundStyle(S.muted))
            .sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
            .accessibilityLabel("Puts paused, below the 50-day average" + (p.s50.map { " of \(PF.price($0))" } ?? ""))
    }

    // MARK: The panel: the tapped way as the trade

    private func panel(_ tr: PTrade, _ wy: PWay, nothing: Bool) -> some View {
        let x = wy.tile, us = PWays.us, usd = PWays.usd, k = PF.strike(x.k), pxT = "$" + PF.price(px)
        var head = "", tail = "", tailC = S.ink, l1 = ""
        var parts: [(String, Color)] = []
        let near = (wy.g.map { PWays.gamma($0) + " gamma · " } ?? "")
            + String(format: "%.1f%% ", PWays.dist(x.k, px)) + (x.k >= px ? "above " : "below ") + pxT
            + (wy.was.map { abs($0 - x.k) < 1e-6 ? " · same as last week" : " · was \(PF.strike($0)) last week" } ?? "")
        switch tr.kind {
        case .sc, .sp:
            let n = sellN(tr), dN = -Double(n) * 100 * (x.d ?? 0), cr = Double(n) * 100 * (x.mid ?? 0)
            let dM = -Double(n) * 100 * (x.d15 ?? x.d ?? 0), mv = tr.kind == .sc ? w.sell.mv : w.sell.mvDn
            head = "Sell \(n) \(tr.kind == .sc ? "calls" : "puts") at \(k) · \(wy.label) · \(PF.monthDay(w.sell.exp)) · "
            tail = usd(cr) + " credit"; tailC = S.green; l1 = near
            let c: (Double) -> Color = { $0 < 0 ? S.red : S.ink }
            parts = [(dN < 0 ? "Gives up " : "Adds ", S.ink), (dv(dN) + " Δ", c(dN)), (" now", S.ink)]
            if let mv { parts += [(" · ", S.ink), (dv(dM) + " Δ", c(dM)), (" if $\(PF.price(mv)) by \(PWays.weekday(w.sell.by))", S.ink)] }
        case .bc:
            let c = w.buy.calls
            if x.id == "sh" {
                let n = Double(x.n ?? 0)
                head = "Buy \(us(n)) shares at \(pxT) · "; tail = usd(x.cost ?? n * px)
                l1 = "Kept as shares, not spent · 1.00 Δ each"
                parts = [("Fills the ", S.ink), ("\(us(c?.left ?? n)) Δ left", S.ink)]
            } else {
                head = "Buy \(x.n ?? 0) \(PWays.month(c?.exp ?? "")) calls at \(k) · \(wy.label) · "; tail = usd(x.cost ?? 0); l1 = near
                parts = [("Fills the ", S.ink), ("\(us(c?.left ?? 0)) Δ left", S.ink),
                         (" · " + String(format: "%.2f", x.de ?? x.d ?? 0) + " Δ each" + (c?.basis == "thu" ? " by \(PWays.weekday(w.sell.by))" : ""), S.ink)]
            }
        case .cw, .pw, .bw:
            // Nothing to trade on this side: say so, then the tapped wall as data.
            head = nothing ? "Nothing to trade" : tr.kind == .cw ? "No calls to sell" : tr.kind == .pw ? "No puts to sell" : "No calls to buy"
            l1 = "\(k) · \(wy.label) · " + near
            parts = [(usd((x.mid ?? 0) * 100) + " each · " + String(format: "%.2f", abs(x.d ?? 0)) + " Δ each", S.ink)]
        case .bp:
            let p = w.buy.puts
            head = "Buy \(PWays.month(p?.exp ?? "")) puts at \(k) · \(wy.label) · "; tail = usd((x.mid ?? 0) * 100) + " each"; l1 = near
            parts = [(String(format: "%.2f", abs(x.d ?? 0)) + " Δ each · ", S.ink),
                     ((p?.held ?? 0) > 0 ? "\(p!.held) \(p!.held == 1 ? "put" : "puts") held" : "none held yet", S.ink)]
        }
        return VStack(alignment: .leading, spacing: 4) {
            (Text(head).foregroundStyle(S.ink) + Text(tail).foregroundStyle(tailC))
                .sType(SType(size: 15, weight: 600, line: 20, tracking: 0))
                .fixedSize(horizontal: false, vertical: true)
            Text(l1).sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                .foregroundStyle(S.muted)
                .fixedSize(horizontal: false, vertical: true)
            parts.reduce(Text("")) { $0 + Text($1.0).foregroundStyle($1.1) }
                .sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                .fixedSize(horizontal: false, vertical: true)
        }
        .contentTransition(.numericText())
        .padding(.vertical, 12).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(S.track))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
