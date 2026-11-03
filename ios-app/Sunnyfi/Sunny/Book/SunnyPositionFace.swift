//
//  SunnyPositionFace.swift
//  Sunny
//
//  Block 13i (handoff 3 Nov 2026) · the Position face's parts: the row on top when the book goes short within the
//  hedge rule's target (or Friday's sale is still to place), both opening Risk; the All · Sold · Bought chips,
//  shared by every card; and All's legs and three numbers (this week on both sides: what the sold legs have kept,
//  what the bought legs moved since Friday's close, the two together).
//

import SwiftUI

/// Position's view of the legs: this week on both sides, Sold, Bought. One choice for every card.
enum PChip: String, CaseIterable, Identifiable {
    case all, sold, bought
    var id: String { rawValue }
    var label: String { switch self { case .all: "All"; case .sold: "Sold"; case .bought: "Bought" } }
}

/// "Goes short above $103.29 · 5 calls at $110, Nov 20, would cover it · see Risk": the same price as Risk's story,
/// the calls Risk's first way buys. A tap opens Risk.
struct PGoesShortRow: View {
    let r: NamePlan.Risk
    let tap: () -> Void

    private var line: String {
        if let p = r.pick, let c = r.cols.first(where: { $0.e == p.e }), let w = c.walls.first(where: { abs($0.k - p.k) < 1e-6 }), w.n > 0 {
            return "\(w.n) \(w.n == 1 ? "call" : "calls") at $\(PF.strike(w.k)), \(PF.monthDay(c.e)), would cover it · see Risk"
        }
        return "Ways to cover \(r.need.formatted()) Δ · see Risk"
    }

    var body: some View {
        let title = "Goes short above $" + PF.price(r.short ?? r.low.px)
        Button(action: tap) {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(S.orange).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).sType(SType(size: 15, weight: 600, line: 20, tracking: 0)).foregroundStyle(S.orangeDeep)
                    Text(line).sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.mutedOnTile)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PChevron()
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(S.thinTint))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(POpacityPress())
        .accessibilityLabel("\(title). \(line)")
        .accessibilityHint("Opens Risk")
    }
}

/// "Friday's sale: 12 calls at $100 · One per LEAP, not placed yet. Risk already counts it." A tap opens Risk.
struct PSaleRow: View {
    let sale: NamePlan.Way.Leg
    let perLeap: Int?
    let tap: () -> Void

    var body: some View {
        let title = "Friday’s sale: \(sale.n) \(sale.n == 1 ? "call" : "calls") at $\(PF.strike(sale.k))"
        let line = (sale.n == perLeap ? "One per LEAP, not placed yet." : "Not placed yet.") + " Risk already counts it."
        Button(action: tap) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).sType(SType(size: 15, weight: 600, line: 20, tracking: 0)).foregroundStyle(S.ink)
                    Text(line).sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.mutedOnTile)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PChevron()
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(S.pTrack))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(POpacityPress())
        .accessibilityLabel("\(title), not placed yet. Risk already counts it.")
        .accessibilityHint("Opens Risk")
    }
}

private struct PChevron: View {
    var body: some View {
        Path { q in q.move(to: CGPoint(x: 1.2, y: 1.2)); q.addLine(to: CGPoint(x: 5.8, y: 6)); q.addLine(to: CGPoint(x: 1.2, y: 10.8)) }
            .stroke(S.mutedOnTile, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .frame(width: 7, height: 12)
            .accessibilityHidden(true)
    }
}

/// All · Sold · Bought: 32 tall capsules on a 44 hit area, the picked one ink.
struct PChips: View {
    let chip: PChip
    let tap: (PChip) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PChip.allCases) { c in
                let on = c == chip
                Button { tap(c) } label: {
                    Text(c.label).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false)
                        .foregroundStyle(on ? S.paper : S.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Capsule().fill(on ? S.ink : S.pTrack))
                        .frame(height: 44)
                        .contentShape(Rectangle())
                        .animation(reduce ? nil : .easeOut(duration: 0.2), value: on)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.vertical, -6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Legs")
    }
}

/// One leg row: what it is and what it did, the amount on the right in up or down color (no minus sign).
struct PLegRow: Identifiable { let id: String; let t: String; let sub: String; let v: Double; let word: String }

/// Every sold leg, one row per type and expiry (Nik, 3 Nov 2026: Sold shows every call and put sold, next week's too):
/// what it collected, what is left to earn, what it has kept.
func pSoldRows(_ sold: [PLeg]) -> [PLegRow] {
    let groups = Dictionary(grouping: sold) { "\($0.call ? 0 : 1)|\($0.expiry)" }
    return groups.keys.sorted { a, b in
        let x = a.split(separator: "|"), y = b.split(separator: "|")
        return x[1] != y[1] ? x[1] < y[1] : x[0] < y[0]
    }.map { key in
        let a = groups[key]!, call = a[0].call
        var qs: [Double: Int] = [:]
        for l in a { qs[l.k, default: 0] += l.q }
        let A = PTotals(a)
        let t = (call ? "Sold calls " : "Sold puts ") + qs.keys.sorted().map { "\(PF.strike($0)) ×\(qs[$0]!)" }.joined(separator: " and ")
            + ", " + PF.monthDay(a[0].expiry)
        return PLegRow(id: "s" + key, t: t, sub: "Collected \(PF.usd(A.base)) · \(PF.usd(A.tv)) left to earn", v: A.g,
                       word: PF.pct(A.pct) + (A.g >= 0 ? " kept" : " lost"))
    }
}

/// Leg rows, a hairline above each.
struct PLegRows: View {
    let rows: [PLegRow]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { r in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.t).sType(SType(size: 15, weight: 600, line: 20, tracking: 0)).foregroundStyle(S.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(r.sub).sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(PF.usd(r.v)).sType(SType(size: 15, weight: 700, line: 20, tracking: 0))
                        Text(r.word).sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                    }
                    .foregroundStyle(r.v >= 0 ? S.green : S.red)
                    .fixedSize()
                }
                .padding(.vertical, 12)
                .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(r.t), \(r.sub), \(r.v >= 0 ? "up" : "down") \(PF.usd(r.v)) \(r.word)")
            }
        }
    }
}

/// All's legs (every sold leg says what it has kept, bought rows how much they moved since Friday's close) and the
/// three numbers under them.
struct PAllRows: View {
    let sold: [PLeg]
    let bought: PCard
    let n: PName
    let today: String

    private var rows: [PLegRow] {
        let bp = PBoughtPlan(c: bought, n: n, today: today, width: 0)
        func boughtRow(_ key: String, _ name: String, _ a: [PLeg]) -> PLegRow? {
            guard let r = bp.row(key, name, a) else { return nil }
            return PLegRow(id: key, t: r.t, sub: r.sub, v: PTotals(a).week, word: "this week")
        }
        return pSoldRows(sold) + [boughtRow("lp", "LEAPS", bp.leaps), boughtRow("hc", "Hedge call", bp.hedges),
                                  boughtRow("ip", "Insurance put", bp.puts)].compactMap { $0 }
    }

    var body: some View {
        let kept = PTotals(sold).g, wk = PTotals(bought.legs).week, net = kept + wk
        VStack(alignment: .leading, spacing: 16) {
            PLegRows(rows: rows)
            PSideStats(cells: [(PF.usd(kept), kept >= 0 ? "kept on sold" : "lost on sold", kept >= 0 ? S.green : S.red),
                               (PF.usd(wk), "bought, this week", wk >= 0 ? S.green : S.red),
                               (PF.usd(net), "net so far", net >= 0 ? S.green : S.red)])
        }
    }
}
