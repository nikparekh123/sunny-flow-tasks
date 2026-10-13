//
//  SunnyPortfolio.swift
//  Sunny
//
//  Blocks 10 and 11 · Portfolio and Watchlist, one card (UI Kit 06).
//  Portfolio: every name in the book as a block sized by exposure and
//  coloured by its move for the range; names under 4% fold into Other.
//  Watchlist: the fixed list as equal blocks, five across. One range filter
//  and one tap cycle (% → $ → price) drive both. Sizes never change with the
//  range, only colour.
//

import SwiftUI

enum TileMode { case pct, usd, price
    var next: TileMode { switch self { case .pct: .usd; case .usd: .price; case .price: .pct } }
}

struct SunnyPortfolio: View {
    let home: HomePayload
    let words: HomePayload
    @State private var range = DebugPreset.int("pf.range") ?? 0
    @State private var mode: TileMode = DebugPreset.string("pf.mode") == "usd" ? .usd : DebugPreset.string("pf.mode") == "price" ? .price : .pct
    @State private var otherOpen = DebugPreset.bool("pf.other")
    @Environment(\.colorScheme) private var scheme

    private static let ranges = ["Today", "1 week", "2 weeks", "3 weeks", "4 weeks"]
    private static let treeH: CGFloat = 232

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Portfolio").sType(.sectionTitle, tabular: false).frame(height: 24)
            filters
            portfolio
            Insight(lead: pfWords.lead, rest: pfWords.rest)
            Rectangle().fill(S.line).frame(height: 1).padding(.horizontal, -20)
            Text("Watchlist").sType(.sectionTitle, tabular: false).frame(height: 24)
            watchlist
            Insight(lead: wlWords.lead, rest: wlWords.rest)
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sCardSurface()
    }

    // MARK: Range filter

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(Self.ranges.enumerated()), id: \.offset) { i, l in
                    SFilterPill(title: l, selected: i == range) { withAnimation(.easeOut(duration: 0.35)) { range = i } }
                }
            }
            .padding(.vertical, 8)
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20)
        .padding(.vertical, -8)
    }

    // MARK: Heat

    /// Steps 0.5 / 1.5 / 3%, widened ×1.6 a week (4 weeks ×3.4).
    private func level(_ pct: Double) -> Int {
        let k = range == 0 ? 1 : 1 + Double(range) * 0.6
        let a = abs(pct)
        return a < 0.5 * k ? 0 : a < 1.5 * k ? 1 : a < 3 * k ? 2 : 3
    }
    private func heat(_ pct: Double) -> (bg: Color, white: Bool) {
        let l = level(pct)
        return ((pct >= 0 ? S.heatUp : S.heatDown)[l], scheme == .dark || l >= 2)
    }

    // MARK: Portfolio treemap

    private struct Item { let t: String; let pct: Double; let exp: Double; let imp: Double; let price: Double?; let other: Bool }

    private func items(_ h: HomePayload) -> (big: [Item], small: [Item]) {
        let all = h.portfolio.map { p -> Item in
            let pct = p.ranges.at(range) ?? 0
            return Item(t: p.ticker, pct: pct, exp: abs(p.exposure), imp: abs(p.exposure) * pct / 100, price: p.spot, other: false)
        }
        let tot = max(all.reduce(0) { $0 + $1.exp }, 1)
        return (all.filter { $0.exp / tot >= 0.04 }.sorted { $0.exp > $1.exp },
                all.filter { $0.exp / tot < 0.04 }.sorted { $0.exp > $1.exp })
    }

    @ViewBuilder private var portfolio: some View {
        let (big, small) = items(home)
        if big.isEmpty && small.isEmpty {
            Text("Nothing open yet.").sType(.body, tabular: false).foregroundStyle(S.muted)
        } else {
            VStack(spacing: 3) {
                GeometryReader { g in
                    let se = small.reduce(0) { $0 + $1.exp }
                    let sp = small.reduce(0) { $0 + $1.pct * $1.exp } / max(se, 1)
                    let all = big + (small.isEmpty ? [] : [Item(t: "Other", pct: sp, exp: se, imp: se * sp / 100, price: nil, other: true)])
                    let boxes = Treemap.squarify(all.map(\.exp), w: g.size.width + 3, h: Self.treeH + 3)
                    ForEach(Array(zip(all, boxes).enumerated()), id: \.offset) { _, pair in
                        let (it, b) = pair
                        tile(it, w: b.width, h: b.height, label: it.other ? "\(small.count) more" : nil) {
                            if it.other { withAnimation(S.standard()) { otherOpen.toggle() } } else { cycle() }
                        }
                        .position(x: b.midX, y: b.midY)
                    }
                }
                .frame(height: Self.treeH)
                if otherOpen && !small.isEmpty {
                    let cols = small.count <= 5 ? max(1, small.count) : Int(ceil(Double(small.count) / 2))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: cols), spacing: 3) {
                        ForEach(small, id: \.t) { it in tile(it, w: 76, h: 56, label: nil, fill: true) { cycle() } }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func cycle() { withAnimation(.easeOut(duration: 0.25)) { mode = mode.next } }

    private func value(_ it: Item, impact: Bool) -> String {
        switch mode {
        case .pct: return F.pct(it.pct)
        case .usd:
            if impact { return F.moneyK(it.imp) }
            let p = it.price ?? 0, chg = p - p / (1 + it.pct / 100)
            return F.money(chg, cents: true)
        case .price: return it.price.map { F.money($0, cents: true) } ?? "-"
        }
    }

    /// One block: ticker 15 + value 13 at 84 × 60 and up, 12 + 11 at 46 × 36,
    /// ticker 10 only at 28 × 18, blank below.
    private func tile(_ it: Item, w: CGFloat, h: CGFloat, label: String?, fill: Bool = false, impact: Bool = true,
                      tap: @escaping () -> Void) -> some View {
        let tier = w >= 84 && h >= 60 ? 2 : w >= 46 && h >= 36 ? 1 : w >= 28 && h >= 18 ? 0 : -1
        let (bg, white) = heat(it.pct)
        let v = label ?? value(it, impact: impact)
        return Button(action: tap) {
            VStack(spacing: tier == 2 ? 4 : 2) {
                if tier >= 0 {
                    Text(it.t).font(SType(size: [10, 12, 15][tier], weight: 700, line: 0, tracking: 0).font())
                }
                if tier >= 1 {
                    Text(v).font(SType(size: tier == 2 ? 13 : 11, weight: 600, line: 0, tracking: 0).font(tabular: true))
                        .contentTransition(.numericText())
                }
            }
            .lineLimit(1)
            .foregroundStyle(white ? Color.white : S.ink)
            .frame(width: fill ? nil : max(0, w), height: max(0, h))
            .frame(maxWidth: fill ? .infinity : nil)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(bg))
            .animation(.easeOut(duration: 0.35), value: range)
        }
        .buttonStyle(SPressStyle())
        .accessibilityLabel(it.other ? "Other, \(v)" : "\(it.t), \(it.pct >= 0 ? "up" : "down") \(F.pct(it.pct)), \(v)")
    }

    // MARK: Watchlist

    private var watchlist: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 5), spacing: 3) {
            ForEach(home.watchlist) { q in
                let pct = q.ranges.at(range) ?? 0
                tile(Item(t: q.ticker, pct: pct, exp: 0, imp: 0, price: q.price, other: false), w: 60, h: 56,
                     label: nil, fill: true, impact: false) { cycle() }
            }
        }
    }

    // MARK: Words (frozen between opens)

    /// The three biggest moves, largest first (ties by name).
    static func top3(_ xs: [(String, Double)]) -> [(String, Double)] {
        Array(xs.sorted { a, b in
            let x = abs(a.1), y = abs(b.1)
            return x != y ? x > y : a.0 < b.0
        }.prefix(3))
    }
    private var pfWords: (lead: String, rest: String) {
        let r = range
        let xs: [(String, Double)] = words.portfolio.map { p in
            let pct: Double = p.ranges.at(r) ?? 0
            return (p.ticker, abs(p.exposure) * pct / 100)
        }
        let parts: [String] = Self.top3(xs).map { m in
            let dir = m.1 < 0 ? "down" : "up"
            return "\(m.0) \(dir) \(F.moneyK(m.1))"
        }
        return Self.sentence(parts)
    }
    private var wlWords: (lead: String, rest: String) {
        let r = range
        let xs: [(String, Double)] = words.watchlist.map { q in (q.ticker, q.ranges.at(r) ?? 0) }
        let parts: [String] = Self.top3(xs).map { m in
            let dir = m.1 < 0 ? "down" : "up"
            return "\(m.0) \(dir) \(F.pct(m.1, places: 1))"
        }
        return Self.sentence(parts)
    }
    static func sentence(_ parts: [String]) -> (lead: String, rest: String) {
        guard let f = parts.first else { return ("Nothing here yet.", "") }
        let rest = parts.dropFirst()
        return (f + ".", rest.isEmpty ? "" : rest.joined(separator: ", ") + ".")
    }
}

// MARK: - Shared bits

/// A range filter pill (UI Kit 08): 40 tall, 12/12 600, selected ink.
struct SFilterPill: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .sType(.label, tabular: false)
                .foregroundStyle(selected ? S.chipOnInk : S.ink)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background { if selected { Capsule().fill(S.ink) } }
                .glassEffect(selected ? .identity : .regular.interactive(), in: .capsule)
                .contentShape(Capsule())
        }
        .buttonStyle(SPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The insight line under a card (block 22): a small glowing sun dot, a
/// bold lead and the rest in muted, two lines at most.
struct Insight: View {
    let lead: String
    let rest: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(S.yellow).frame(width: 6, height: 6)
                .shadow(color: S.yellow.opacity(0.75), radius: 4)
                .padding(.top, 6)
            (Text(lead).foregroundStyle(S.ink).font(SType(size: 13, weight: 600, line: 18, tracking: 0).font())
             + Text(rest.isEmpty ? "" : " " + rest))
                .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false)
                .foregroundStyle(S.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

enum Treemap {
    /// Squarified layout of weights into w × h, each box shrunk by 3 for the
    /// gap (the design file's squarify, rounded the same way).
    static func squarify(_ weights: [Double], w W: CGFloat, h H: CGFloat) -> [CGRect] {
        let tot = max(weights.reduce(0, +), 1e-9)
        var rest = weights.enumerated().map { (i: $0.offset, a: $0.element / tot * Double(W * H)) }
        var x = 0.0, y = 0.0, w = Double(W), h = Double(H)
        var out = Array(repeating: CGRect.zero, count: weights.count)
        while !rest.isEmpty {
            let sh = min(w, h)
            var row: [(i: Int, a: Double)] = [], best = Double.infinity
            while !rest.isEmpty {
                let cand = row + [rest[0]]
                let s = cand.reduce(0) { $0 + $1.a }, mx = cand.map(\.a).max()!, mn = cand.map(\.a).min()!
                let worst = max(sh * sh * mx / (s * s), s * s / (sh * sh * max(mn, 1e-9)))
                if worst > best { break }
                best = worst; row = cand; rest.removeFirst()
            }
            let s = row.reduce(0) { $0 + $1.a }
            if w >= h {
                let cw = s / h; var cy = y
                for c in row { let ch = c.a / cw; out[c.i] = rect(x, cy, cw, ch); cy += ch }
                x += cw; w -= cw
            } else {
                let rh = s / w; var cx = x
                for c in row { let cw = c.a / rh; out[c.i] = rect(cx, y, cw, rh); cx += cw }
                y += rh; h -= rh
            }
        }
        return out
    }
    private static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
        let rx = x.rounded(), ry = y.rounded()
        return CGRect(x: rx, y: ry, width: (x + w).rounded() - rx - 3, height: (y + h).rounded() - ry - 3)
    }
}
