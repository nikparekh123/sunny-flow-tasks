//
//  SunnyInventory.swift
//  Sunny · Inventory, two tabs and the trend. `export 22`, 20 Sep 2026.
//
//  A RUNNING INVENTORY: what is written right now, and what it pays. One tab a
//  side. A row a name — SOLD of CAN and the credit those legs took — then a
//  Total row, then twelve weeks of three series: what the book COULD have
//  written (dashed), what it DID (filled), and what that took in (the line, on
//  its own dollar scale).
//
//  ⚠ CAN IS THE FULL HELD COUNT ON BOTH SIDES. The sheet showed puts as a third
//  of held; Nik ruled on 21 Sep that the full number shows. A count past can
//  prints red and is never clipped.
//
//  ⚠ THE FLOOR IS HIS, NOT THE SHEET'S. The sheet colours the % lens against one
//  fixed 1.24. Nik's ruling of 18 Sep stands: credit over strike against his own
//  average since 31 Aug, one per side.
//
//  ⚠ AND THE HISTORY STARTS 31 AUGUST. Twelve weeks are asked for; the weeks
//  before this book existed are not invented, so the panel draws what there is.
//

import SwiftUI

// MARK: - data

struct InventoryCard: Decodable {
    let asOf: String
    let floor: InvFloor
    let sold: InvSides
    /// Monday-keyed, oldest first, the live week last.
    let weeks: [InvWeek]
    /// Puts can carry this share of held. 1/3.
    let putShare: Double?
}

struct InvSides: Decodable { let calls: [InvSold]; let puts: [InvSold] }
struct InvFloor: Decodable { let calls: Double?; let puts: Double? }

struct InvSold: Decodable {
    let t: String
    let held: Int, sold: Int
    /// The last credit written on this name and side, over its strike, %.
    let cr: Double?
    /// The credit the open legs took, $ a contract, weighted.
    let cc: Int?
}

struct InvWeek: Decodable {
    let w: String
    let calls: InvWeekSide, puts: InvWeekSide
}
struct InvWeekSide: Decodable { let sold: Int, can: Int, usd: Int }

// MARK: - the card

struct SunnyInventory: View {
    let block: InventoryCard

    @AppStorage("sunnyfi.inv.side") private var putsTab = false
    /// The credit lens: $ a contract, or % on the share against the floor.
    @AppStorage("sunnyfi.inv.pct") private var pct = false
    @State private var sel: Int? = nil
    @State private var appeared = false
    @State private var drawn: CGFloat = 0
    @State private var dots = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let inner: CGFloat = S.content - 48          // 313
    private static let nameCol: CGFloat = 52
    private static let colGap: CGFloat = 12
    private static let rowH: CGFloat = 22
    private static let panelH: CGFloat = 96
    private static let dim = 0.35

    private var puts: Bool { putsTab }
    private var floor: Double { (puts ? block.floor.puts : block.floor.calls) ?? .infinity }
    private var side: [InvSold] { puts ? block.sold.puts : block.sold.calls }
    private func week(_ w: InvWeek) -> InvWeekSide { puts ? w.puts : w.calls }

    /// One row a name, most left to sell first.
    private struct Row: Identifiable {
        let t: String, sold: Int, can: Int
        let cr: Double?, cc: Int?
        var id: String { t }
        var over: Bool { sold > can }
    }
    private var rows: [Row] {
        side.map { x in
            Row(t: x.t, sold: x.sold,
                can: puts ? Int((Double(x.held) * (block.putShare ?? 1)).rounded()) : x.held,
                cr: x.cr, cc: x.cc)
        }
        .sorted { ($0.can - $0.sold) != ($1.can - $1.sold)
            ? ($0.can - $0.sold) > ($1.can - $1.sold) : ($0.cr ?? 0) > ($1.cr ?? 0) }
    }

    var body: some View {
        let rs = rows
        let sold = rs.reduce(0) { $0 + $1.sold }, can = rs.reduce(0) { $0 + $1.can }
        VStack(alignment: .leading, spacing: 0) {
            header(rs.count)
            Spacer().frame(height: 18)
            tabRow
            Spacer().frame(height: 22)
            ledgerHead
            ForEach(Array(rs.enumerated()), id: \.element.id) { i, r in
                row(r)
                    .opacity(appeared || reduceMotion ? 1 : 0)
                    .animation(reduceMotion ? nil : S.easeSettle(0.4).delay(Double(i) * 0.04), value: appeared)
            }
            totalRow(rs, sold: sold, can: can)
            Spacer().frame(height: 22)
            hero(sold: sold, can: can)
            Spacer().frame(height: 14)
            legend(sold: sold, can: can)
            Spacer().frame(height: 14)
            panel
            Spacer().frame(height: 8)
            axis
        }
        .frame(width: Self.inner, alignment: .leading)
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 28, trailing: 24))
        .frame(width: S.content, alignment: .top)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCardL)
        .monospacedDigit()
        .measure("inventory")
        .onAppear { if !appeared { appeared = true; redraw() } }
    }

    /// The curves draw in on load and on a tab change, never on the pull.
    private func redraw() {
        sel = nil
        guard !reduceMotion else { drawn = 1; dots = true; return }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { drawn = 0; dots = false }
        withAnimation(S.easeSettle(0.9)) { drawn = 1 }
        withAnimation(.easeOut(duration: 0.3).delay(0.75)) { dots = true }
    }

    // MARK: header · tabs

    private func header(_ n: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                Text("Inventory").font(S.inter(S.t14, S.wBoldN))
                    .tracking(S.track(S.t14, -0.01)).foregroundStyle(S.ink)
                Text("open now").font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
            }
            Spacer(minLength: 0)
            Text("\(n) name\(n == 1 ? "" : "s")").font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
        }
        .frame(height: 17)
    }

    private var tabRow: some View {
        HStack(alignment: .bottom, spacing: 28) {
            ForEach([false, true], id: \.self) { p in
                VStack(spacing: 0) {
                    Text(p ? "Puts" : "Calls")
                        .font(S.inter(S.t12, p == puts ? S.wBoldN : S.wMidN))
                        .tracking(S.track(S.t12, -0.01))
                        .foregroundStyle(p == puts ? S.ink : S.mute)
                        .sunnyLineBox(S.t12)
                    Spacer().frame(height: 10)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(p == puts ? S.ink : .clear).frame(height: 2)
                }
                .fixedSize()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard p != puts else { return }
                    putsTab = p
                    redraw()
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 22, alignment: .bottom)
        .background(alignment: .bottom) { Rectangle().fill(S.ruleColor).frame(height: 1) }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: putsTab)
    }

    // MARK: the ledger

    private var ledgerHead: some View {
        HStack(spacing: Self.colGap) {
            Color.clear.frame(width: Self.nameCol, height: 1)
            Text("SOLD OF HELD")
                .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute).sunnyLineBox(S.t10)
                .frame(maxWidth: .infinity, alignment: .leading)
            /* The one underline on the card: the text that flips. */
            Text(pct ? "CREDIT \u{00B7} %" : "CREDIT \u{00B7} $")
                .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute).sunnyLineBox(S.t10).sunnyHint()
                .fixedSize()
                .padding(.vertical, 10).contentShape(Rectangle())
                .onTapGesture { pct.toggle() }
                .padding(.vertical, -10)
        }
        .frame(height: 10)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(S.ruleColor).frame(height: 1) }
    }

    private func row(_ r: Row) -> some View {
        HStack(spacing: Self.colGap) {
            Text(r.t).font(S.inter(S.t15, S.wSemiN)).tracking(S.track(S.t15, -0.015))
                .foregroundStyle(S.ink).lineLimit(1).sunnyLineBox(S.t15)
                .frame(width: Self.nameCol, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(r.sold)").font(S.inter(S.t22, S.wBoldN)).tracking(S.track(S.t22, -0.03))
                    .foregroundStyle(r.over ? S.lossText : (r.sold > 0 ? S.ink : S.mute))
                Text("of \(r.can)").font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
            }
            .lineLimit(1).fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
            credit(r)
        }
        .frame(height: Self.rowH)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Rectangle().fill(S.ruleColor).frame(height: 1) }
    }

    /// The $ lens reads the total taken in, with the per-contract price after it
    /// in brackets (Nik, 21 Sep). The % lens is credit over strike, unchanged.
    @ViewBuilder private func credit(_ r: Row) -> some View {
        let ink: Color = {
            guard r.sold > 0 else { return S.mute }
            guard pct else { return S.ink }
            return (r.cr ?? 0) >= floor ? S.gainText : S.lossText
        }()
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if r.sold > 0, !pct, let cc = r.cc {
                Text(optMoney(r.sold * cc)).font(S.inter(S.t13, S.wBoldN)).tracking(S.track(S.t13, -0.02))
                    .foregroundStyle(ink)
                Text("(\(optMoney(cc)))").font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
            } else {
                Text(r.sold > 0 && pct ? (r.cr.map { String(format: "%.2f%%", $0) } ?? "\u{2013}") : "\u{2013}")
                    .font(S.inter(S.t13, S.wBoldN)).tracking(S.track(S.t13, -0.02))
                    .foregroundStyle(ink)
            }
        }
        .lineLimit(1).fixedSize()
        .padding(.vertical, 10).contentShape(Rectangle())
        .onTapGesture { pct.toggle() }
        .padding(.vertical, -10)
    }

    /// The Total row is a row: same height, same rule. The credit is weighted by
    /// contracts sold, never a plain mean.
    private func totalRow(_ rs: [Row], sold: Int, can: Int) -> some View {
        let n = rs.reduce(0) { $0 + $1.sold }
        let cc = n > 0 ? rs.reduce(0.0) { $0 + Double($1.sold) * Double($1.cc ?? 0) } / Double(n) : 0
        let cr = n > 0 ? rs.reduce(0.0) { $0 + Double($1.sold) * ($1.cr ?? 0) } / Double(n) : 0
        let usd = rs.reduce(0) { $0 + $1.sold * ($1.cc ?? 0) }
        return HStack(spacing: Self.colGap) {
            Text("Total").font(S.inter(S.t12, S.wSemiN)).tracking(S.track(S.t12, -0.01))
                .foregroundStyle(S.mute).sunnyLineBox(S.t12)
                .frame(width: Self.nameCol, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(sold)").font(S.inter(S.t22, S.wBoldN)).tracking(S.track(S.t22, -0.03))
                    .foregroundStyle(S.ink)
                Text("of \(can)").font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
            }
            .lineLimit(1).fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(n == 0 ? "\u{2013}" : (pct ? String(format: "%.2f%%", cr) : optMoney(usd)))
                    .font(S.inter(S.t13, S.wBoldN)).tracking(S.track(S.t13, -0.02))
                    .foregroundStyle(n == 0 ? S.mute : (pct ? (cr >= floor ? S.gainText : S.lossText) : S.ink))
                Text(pct || n == 0 ? "avg" : "(\(optMoney(Int(cc.rounded()))) avg)")
                    .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
            }
            .lineLimit(1).fixedSize()
            .contentShape(Rectangle())
            .onTapGesture { pct.toggle() }
        }
        .frame(height: Self.rowH)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Rectangle().fill(S.ruleColor).frame(height: 1) }
    }

    // MARK: the trend

    /// The twelve weeks, with the live one replaced by the ledger so the panel's
    /// end, the Total row and the legend cannot disagree.
    private func series(sold: Int, can: Int) -> [InvWeekSide] {
        var out = block.weeks.map(week)
        if !out.isEmpty {
            let usd = rows.reduce(0) { $0 + $1.sold * ($1.cc ?? 0) }
            out[out.count - 1] = InvWeekSide(sold: sold, can: can, usd: usd)
        }
        return out
    }

    private func share(_ sold: Int, _ can: Int) -> Int {
        can > 0 ? Int((Double(sold) / Double(can) * 100).rounded()) : 0
    }

    private func hero(sold: Int, can: Int) -> some View {
        let w = series(sold: sold, can: can)
        let now = share(sold, can)
        let first = w.first.map { share($0.sold, $0.can) } ?? now
        let d = now - first
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                Text("\(now)%").font(S.inter(S.t22, S.wBoldN)).tracking(S.track(S.t22, -0.03))
                    .foregroundStyle(S.ink).sunnyLineBox(S.t22)
                Text("of can, sold this week").font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
            }
            Spacer(minLength: 0)
            Text(d == 0 ? "flat \u{00B7} \(w.count) wks"
                 : "\(d > 0 ? "+" : "\u{2212}")\(abs(d)) pts \u{00B7} \(w.count) wks")
                .font(S.inter(S.t12, S.wSemiN))
                .foregroundStyle(d == 0 ? S.mute : (d > 0 ? S.gainText : S.lossText))
                .fixedSize()
        }
        .frame(height: 22)
    }

    private enum Series { case can, sold, credit }
    private func ink(_ s: Series) -> Color {
        switch s {
        case .can: return S.hair
        case .sold: return S.ctFill
        case .credit: return S.ctOutline
        }
    }

    private func legend(sold: Int, can: Int) -> some View {
        let usd = rows.reduce(0) { $0 + $1.sold * ($1.cc ?? 0) }
        return HStack(spacing: 14) {
            item(.can, "Can sell", "\(can)")
            item(.sold, "Sold", "\(sold)")
            item(.credit, "Credit", optMoney(usd))
            Spacer(minLength: 0)
        }
        .frame(height: 11)
    }

    private func item(_ s: Series, _ word: String, _ fig: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(s == .sold ? ink(s) : .clear)
                .overlay(RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(ink(s), style: StrokeStyle(lineWidth: 1.5,
                                                             dash: s == .can ? [2, 2] : [])))
                .frame(width: 9, height: 9)
            Text(word).font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute).sunnyLineBox(S.t11)
            Text(fig).font(S.inter(S.t11, S.wSemiN)).foregroundStyle(S.ink).sunnyLineBox(S.t11)
        }
        .fixedSize()
    }

    /* ⚠ TWO SCALES. Sold and Can sell are contracts and share one; Credit is
       dollars and never shares an axis with a contract count. */
    private var panel: some View {
        let rs = rows
        let w = series(sold: rs.reduce(0) { $0 + $1.sold }, can: rs.reduce(0) { $0 + $1.can })
        let n = w.count
        let counts = w.map { Double($0.sold) } + w.map { Double($0.can) }
        let yC = scale(counts), yU = scale(w.map { Double($0.usd) })
        let xs: (Int) -> CGFloat = { i in n <= 1 ? Self.inner / 2 : CGFloat(i) / CGFloat(n - 1) * Self.inner }
        let can = w.enumerated().map { CGPoint(x: xs($0.offset), y: yC(Double($0.element.can))) }
        let sold = w.enumerated().map { CGPoint(x: xs($0.offset), y: yC(Double($0.element.sold))) }
        let usd = w.enumerated().map { CGPoint(x: xs($0.offset), y: yU(Double($0.element.usd))) }
        return ZStack(alignment: .topLeading) {
            Group {
                if can.count > 1 {
                    /* A limit is printed, not drawn. */
                    catmull(can).stroke(S.hair, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
                if sold.count > 1 {
                    catmull(sold).closed(to: Self.panelH, sold)
                        .fill(LinearGradient(colors: [S.ctFill.opacity(0.55), S.ctFill.opacity(0.02)],
                                             startPoint: .top, endPoint: .bottom))
                        .opacity(Double(drawn))
                    catmull(sold).trimmedPath(from: 0, to: drawn)
                        .stroke(S.ctFill, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if usd.count > 1 {
                    catmull(usd).trimmedPath(from: 0, to: drawn)
                        .stroke(S.ctOutline, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
                ForEach(Array([(can.last, S.hair), (sold.last, S.ctFill), (usd.last, S.ctOutline)]
                    .compactMap { p, c in p.map { ($0, c) } }.enumerated()), id: \.offset) { _, e in
                    endDot(e.0, e.1)
                }
            }
            .opacity(sel == nil ? 1 : Self.dim)
            if let i = sel, i < n {
                let x = xs(i)
                Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: Self.panelH)) }
                    .stroke(S.hair, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                dot(can[i], S.hair); dot(sold[i], S.ctFill); dot(usd[i], S.ctOutline)
                callout(i, x: x, w: w)
            }
        }
        .frame(width: Self.inner, height: Self.panelH, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: sel)
    }

    /// Floor = min − 25% of the range, ceiling = max + 10%, 8 of pad on top.
    private func scale(_ vals: [Double]) -> (Double) -> CGFloat {
        let mn = vals.min() ?? 0, mx = vals.max() ?? 1
        let r = (mx - mn) != 0 ? (mx - mn) : (abs(mn) * 0.1 != 0 ? abs(mn) * 0.1 : 1)
        let lo = mn - r * 0.25, hi = mx + r * 0.1
        return { v in 8 + (Self.panelH - 8) * CGFloat(1 - (v - lo) / (hi - lo)) }
    }

    private func endDot(_ p: CGPoint, _ c: Color) -> some View { dot(p, c).opacity(dots ? 1 : 0) }
    private func dot(_ p: CGPoint, _ c: Color) -> some View {
        Circle().fill(c)
            .overlay(Circle().strokeBorder(S.paper, lineWidth: 1.5).padding(-1.5))
            .frame(width: 7, height: 7)
            .position(p)
    }

    @ViewBuilder private func callout(_ i: Int, x: CGFloat, w: [InvWeekSide]) -> some View {
        let live = i == w.count - 1
        HStack(spacing: 5) {
            Text(live ? "This week" : "Wk of \(shortDate(block.weeks[i].w))")
                .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
            Text("\(w[i].sold) of \(w[i].can)").font(S.inter(S.t11, S.wSemiN)).foregroundStyle(S.ink)
            Text("\(share(w[i].sold, w[i].can))%").font(S.inter(S.t11, S.wSemiN)).foregroundStyle(S.ink2)
            Text(optMoney(w[i].usd)).font(S.inter(S.t11, S.wSemiN)).foregroundStyle(S.ctOutline)
        }
        .lineLimit(1).sunnyLineBox(S.t11)
        .padding(EdgeInsets(top: 2, leading: 6, bottom: 3, trailing: 6))
        .background(S.paper, in: RoundedRectangle(cornerRadius: S.radiusChip))
        .overlay(RoundedRectangle(cornerRadius: S.radiusChip).strokeBorder(S.ruleColor, lineWidth: 1))
        .fixedSize()
        .alignmentGuide(.leading) { d in
            if x < 70 { return 0 }
            if x > Self.inner - 70 { return d.width - Self.inner }
            return d.width / 2 - x
        }
    }

    // MARK: the axis

    private var axis: some View {
        let n = block.weeks.count
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(S.ruleColor).frame(width: Self.inner, height: 1).offset(y: 2)
            ForEach(0..<n, id: \.self) { i in
                let live = i == n - 1, hot = live || i == sel
                let x = n <= 1 ? Self.inner / 2 : CGFloat(i) / CGFloat(n - 1) * Self.inner
                VStack(spacing: 6) {
                    Circle().fill(hot ? S.ink : S.hair).frame(width: 5, height: 5)
                    Text(live ? "This wk" : shortDate(block.weeks[i].w))
                        .font(S.inter(S.t10, hot ? S.wSemiN : S.wMidSmN))
                        .foregroundStyle(hot ? S.ink : S.mute)
                        .lineLimit(1).fixedSize().sunnyLineBox(S.t10)
                        .opacity(labelShown(i, n) ? 1 : 0)
                }
                .fixedSize()
                .opacity(sel == nil || sel == i ? 1 : Self.dim)
                .frame(width: 26, height: 44, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture { sel = (sel == i) ? nil : i }
                .position(x: x, y: 22)
            }
        }
        .frame(width: Self.inner, height: 22, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: sel)
    }

    private func labelShown(_ i: Int, _ n: Int) -> Bool {
        if let s = sel {
            if i == s { return true }
            if abs(i - s) == 1 { return false }
        }
        if i == n - 1 { return true }
        let step = n > 6 ? 2 : 1
        guard i % step == 0 else { return false }
        if step == 2 && n - 1 - i == 1 { return false }
        return true
    }

    // MARK: geometry · words

    private func catmull(_ p: [CGPoint]) -> Path {
        Path { path in
            guard let first = p.first else { return }
            path.move(to: first)
            for i in 0..<(p.count - 1) {
                let p0 = i > 0 ? p[i - 1] : p[i], p1 = p[i], p2 = p[i + 1]
                let p3 = i + 2 < p.count ? p[i + 2] : p2
                let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                path.addCurve(to: p2, control1: c1, control2: c2)
            }
        }
    }

    private func shortDate(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m) else { return iso }
        return "\(d) \(["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][m - 1])"
    }
}
