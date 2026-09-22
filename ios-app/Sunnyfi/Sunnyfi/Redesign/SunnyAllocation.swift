//
//  SunnyAllocation.swift
//  Allocation (export 23, 21 Sep 2026): where the capital sits, a name at a
//  time. What went in against what it is worth now; one stacked bar for the
//  spread, a ledger under it, a Total row to close it.
//
//  ⚠ EVERYTHING BOUGHT, NOT SHARES ALONE. The sheet counts shares; on this book
//  that misses the LEAPs, which is most of the money. Nik, 21 Sep: shares +
//  long calls + long puts, TLT left out. The server sums them per name
//  (`allocationCard.book[].inv / now`), so the card only sorts and prints.
//
//  ⚠ SORTED BY INVESTED, ALWAYS. The lens re-slices the shares (the bar and the
//  % column) and moves no row.
//
//  ⚠ A NAME'S COLOUR IS ITS RANK. The grey ramp carries no P&L; green and red
//  live on the NOW column and the hero delta only.
//

import SwiftUI

// MARK: - payload

struct AllocationCard: Decodable {
    let asOf: String?
    let book: [AllocName]
}

struct AllocName: Decodable {
    let t: String
    let inv: Double
    let now: Double
}

// MARK: - money

/// `usdM`: $1.74m · $470k · $28.4k · $5.4k · $840.
func usdM(_ n: Double) -> String {
    let a = abs(n), sign = n < 0 ? "\u{2212}" : ""
    if a >= 1e6 { return sign + "$" + String(format: "%.2f", a / 1e6) + "m" }
    if a >= 1e5 { return sign + "$" + String(Int((a / 1e3).rounded())) + "k" }
    if a >= 1e3 {
        var s = String(format: "%.1f", a / 1e3)
        if s.hasSuffix(".0") { s.removeLast(2) }
        return sign + "$" + s + "k"
    }
    return sign + "$" + String(Int(a.rounded()))
}

/// `signedPct` in the sheet: one decimal under 10, none over; no sign on zero.
func alPct(_ n: Double) -> String {
    let a = abs(n)
    let r = a < 10 ? String(format: "%.1f", a) : String(Int(a.rounded()))
    return ((Double(r) ?? 0) == 0 ? "" : (n < 0 ? "\u{2212}" : "+")) + r + "%"
}

// MARK: - the card

struct SunnyAllocation: View {
    let block: AllocationCard
    /// Freshness: INVESTED moves only on a trade; NOW is the market and never marks.
    var fresh: FreshTrack? = nil
    var updating = false

    static func freshFigs(_ b: AllocationCard) -> [String: [String: String]] {
        var out: [String: [String: String]] = [:]
        for x in b.book { out["a:\(x.t)"] = ["inv": usdM(x.inv)] }
        out["a:#total"] = ["inv": usdM(b.book.reduce(0) { $0 + $1.inv })]
        return out
    }
    private func fr(_ t: String, _ own: Color) -> Color {
        fresh?.isMarked("a:\(t)", "inv") == true ? S.warn : own
    }

    /// `lens` and `sel` are state; they survive a refresh of the feed.
    @AppStorage("sunnyfi.alloc.byNow") private var byNow = false
    @State private var sel: String? = nil
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let inner: CGFloat = S.content - 48          // 313
    private static let sw: CGFloat = 9
    private static let nameCol: CGFloat = 52
    private static let gap: CGFloat = 12
    private static let invCol: CGFloat = 61     // the sheet: INVESTED sets it, 60.82
    private static let nowCol: CGFloat = 48
    private static let dim = 0.35

    private struct Row: Identifiable {
        let t: String, inv: Double, now: Double
        var id: String { t }
        var d: Double { inv > 0 ? (now / inv - 1) * 100 : 0 }
    }

    private var rows: [Row] {
        block.book.map { Row(t: $0.t, inv: $0.inv, now: $0.now) }
            .sorted { $0.inv != $1.inv ? $0.inv > $1.inv : $0.t < $1.t }
    }

    private func ink(_ i: Int) -> Color { S.alRank[min(i, S.alRank.count - 1)] }
    private func dir(_ d: Double) -> Color { d >= 0 ? S.gainText : S.lossText }
    private func op(_ t: String) -> Double { sel == nil || sel == t ? 1 : Self.dim }
    private func pick(_ t: String) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { sel = sel == t ? nil : t }
    }

    var body: some View {
        let rs = rows
        let tInv = rs.reduce(0) { $0 + $1.inv }, tNow = rs.reduce(0) { $0 + $1.now }
        let lensTot = byNow ? tNow : tInv
        VStack(alignment: .leading, spacing: 0) {
            header(rs.count)
            Spacer().frame(height: 18)
            hero(rs, tInv: tInv, tNow: tNow)
            Spacer().frame(height: 16)
            bar(rs, total: lensTot)
            Spacer().frame(height: 22)
            ledgerHead
            ForEach(Array(rs.enumerated()), id: \.element.id) { i, r in
                row(r, i, total: lensTot)
                    .opacity(appeared || reduceMotion ? 1 : 0)
                    .animation(reduceMotion ? nil : S.easeSettle(0.4).delay(Double(i) * 0.04), value: appeared)
            }
            totalRow(tInv: tInv, tNow: tNow)
        }
        .frame(width: Self.inner, alignment: .leading)
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 28, trailing: 24))
        .frame(width: S.content, alignment: .top)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCardL)
        .monospacedDigit()
        .measure("allocation")
        .modifier(OptionalFreshSeen(track: fresh))
        .onAppear { appeared = true }
        .onChange(of: rs.map(\.t)) { _, names in
            if let s = sel, !names.contains(s) { sel = nil }
        }
    }

    // MARK: header · hero

    private func header(_ n: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                Text("Allocation").font(S.inter(S.t14, S.wBoldN))
                    .tracking(S.track(S.t14, -0.01)).foregroundStyle(S.ink)
                Text("by name").font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
            }
            .fixedSize()
            Spacer(minLength: 0)
            FreshMeta(meta: "\(n) name\(n == 1 ? "" : "s")", track: fresh, updating: updating)
        }
        .frame(height: 17)
    }

    /// Default: the book now, on what went in. A name picked: that name.
    private func hero(_ rs: [Row], tInv: Double, tNow: Double) -> some View {
        let h = sel.flatMap { s in rs.first { $0.t == s } }
        let now = h?.now ?? tNow, inv = h?.inv ?? tInv
        let d = inv > 0 ? (now / inv - 1) * 100 : 0
        let word = "now \u{00B7} " + usdM(inv) + " invested" + (h.map { " in " + $0.t } ?? "")
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                Text(usdM(now)).font(S.inter(S.t22, S.wBoldN)).tracking(S.track(S.t22, -0.03))
                    .foregroundStyle(S.ink)
                Text(word).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Text(alPct(d)).font(S.inter(S.t12, S.wSemiN)).foregroundStyle(dir(d))
                .fixedSize()
        }
        .frame(height: 22)
    }

    // MARK: the bar

    /// One stacked bar, a segment a name in ledger order, width = its share on
    /// the lens. 2 between, a segment floors at 2. A segment picks its name.
    private func bar(_ rs: [Row], total: Double) -> some View {
        let n = CGFloat(rs.count)
        let free = max(0, Self.inner - 2 * max(0, n - 1))
        /* Floor every segment at 2 and take the floor out of the rest, so the
           widths still sum to the bar. */
        let raw = rs.map { total > 0 ? CGFloat((byNow ? $0.now : $0.inv) / total) * free : 0 }
        let small = raw.filter { $0 < 2 }.count
        let spare = free - 2 * CGFloat(small)
        let bigSum = raw.filter { $0 >= 2 }.reduce(0, +)
        let w = raw.map { $0 < 2 ? 2 : (bigSum > 0 ? $0 / bigSum * spare : 0) }
        return HStack(spacing: 2) {
            ForEach(Array(rs.enumerated()), id: \.element.id) { i, r in
                Rectangle().fill(ink(i))
                    .frame(width: w[i], height: 14)
                    .opacity(op(r.t))
                    .contentShape(Rectangle())
                    .onTapGesture { pick(r.t) }
            }
        }
        .frame(width: Self.inner, height: 14, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusBar, style: .continuous))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: byNow)
    }

    // MARK: the ledger

    private var ledgerHead: some View {
        HStack(spacing: Self.gap) {
            Color.clear.frame(width: Self.sw + Self.gap + Self.nameCol, height: 1)
            /* The one underline on the card: the text that flips. */
            Text(byNow ? "BY VALUE NOW" : "BY INVESTED")
                .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute).sunnyLineBox(S.t10).sunnyHint()
                .fixedSize()
                .padding(.vertical, 10).contentShape(Rectangle())
                .onTapGesture { byNow.toggle() }
                .padding(.vertical, -10)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("INVESTED").font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute).sunnyLineBox(S.t10).fixedSize()
                .frame(width: Self.invCol, alignment: .trailing)
            Text("NOW").font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute).sunnyLineBox(S.t10)
                .frame(width: Self.nowCol, alignment: .trailing)
        }
        .frame(height: 10)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(S.ruleColor).frame(height: 1) }
    }

    private func row(_ r: Row, _ i: Int, total: Double) -> some View {
        let share = total > 0 ? (byNow ? r.now : r.inv) / total * 100 : 0
        return HStack(spacing: Self.gap) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(ink(i))
                .frame(width: Self.sw, height: Self.sw)
            Text(r.t).font(S.inter(S.t15, S.wSemiN)).tracking(S.track(S.t15, -0.015))
                .foregroundStyle(S.ink).lineLimit(1).sunnyLineBox(S.t15)
                .frame(width: Self.nameCol, alignment: .leading)
            Text(share < 0.5 ? "<1%" : "\(Int(share.rounded()))%")
                .font(S.inter(S.t12, S.wSemiN)).foregroundStyle(S.ink2).sunnyLineBox(S.t12)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(usdM(r.inv)).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(fr(r.t, S.mute))
                .lineLimit(1).sunnyLineBox(S.t12)
                .frame(width: Self.invCol, alignment: .trailing)
            Text(usdM(r.now)).font(S.inter(S.t13, S.wBoldN)).tracking(S.track(S.t13, -0.02))
                .foregroundStyle(dir(r.d)).lineLimit(1).sunnyLineBox(S.t13)
                .frame(width: Self.nowCol, alignment: .trailing)
        }
        .frame(height: 15)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(S.ruleColor).frame(height: 1) }
        .opacity(op(r.t))
        .contentShape(Rectangle())
        .onTapGesture { pick(r.t) }
    }

    /// The Total row is a row: 35, one rule under it.
    private func totalRow(tInv: Double, tNow: Double) -> some View {
        HStack(spacing: Self.gap) {
            Color.clear.frame(width: Self.sw, height: 1)
            Text("Total").font(S.inter(S.t12, S.wSemiN)).tracking(S.track(S.t12, -0.01))
                .foregroundStyle(S.mute).sunnyLineBox(S.t12)
                .frame(width: Self.nameCol, alignment: .leading)
            Spacer(minLength: 0)
            Text(usdM(tInv)).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(fr("#total", S.mute))
                .lineLimit(1).sunnyLineBox(S.t12)
                .frame(width: Self.invCol, alignment: .trailing)
            Text(usdM(tNow)).font(S.inter(S.t13, S.wBoldN)).tracking(S.track(S.t13, -0.02))
                .foregroundStyle(dir(tNow - tInv)).lineLimit(1).sunnyLineBox(S.t13)
                .frame(width: Self.nowCol, alignment: .trailing)
        }
        .frame(height: 15)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(S.ruleColor).frame(height: 1) }
    }
}
