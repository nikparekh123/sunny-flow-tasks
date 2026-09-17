//
//  SunnyCreditTheta.swift
//  Sunny — Credit & theta. `export 19/credit-theta`, 17 Sep 2026.
//
//  ONE CARD FOR TWO TREND QUESTIONS: is short theta still paying for long
//  theta, and is credit getting better or worse. It replaces Average credit and
//  Theta, which drew four bars each and asked the reader to see a trend in them.
//
//  ⚠ NIK'S RULINGS, 17 Sep 2026, WHICH REPLACE THE SHEET WHERE THEY DIFFER:
//    · The Theta reading is the RATIO, short collects ÷ what the LEAPs AND the
//      long puts pay. 3.5× and above is comfortable, under 2× is danger ("anything
//      less than 2 is not worth"), between is watch. The strip under the chart
//      draws the ratio against those two lines, in place of the sheet's RSI.
//    · Credit is a PERCENT OF STRIKE, never dollars a contract. The book turned
//      over to cheaper names and $/contract fell 422 to 35 while % of strike
//      held; dollars measured the stock price. Its strip shades his usual range,
//      the middle half of every week on record.
//    · Weekly only until Monthly and Quarterly have history to cut.
//    · The sentence is one line, and a second when two things are moving. The
//      server writes it, because it reads IV and per-name theta the card never
//      sees.
//

import SwiftUI

// MARK: - data

struct CreditTrendBlock: Decodable {
    let asOf: String
    let weeks: [TrendWeek]
    let names: [TrendName]
    let theta: TrendTheta
    let credit: TrendCredit
}

struct TrendWeek: Decodable, Identifiable {
    let week: String, on: String
    /// Theta a day at that week's reading. `long` is always <= 0.
    let short: Int, long: Int, lc: Int, lp: Int, sc: Int, sp: Int
    /// null before the book held a long leg.
    let ratio: Double?
    let calls: TrendSide, puts: TrendSide
    var id: String { week }
    /// Every contract sold that week, calls and puts together, over their strikes.
    var blend: Double? {
        let nl = calls.notional + puts.notional
        return nl > 0 ? Double(calls.cash + puts.cash) / Double(nl) * 100 : nil
    }
}

struct TrendSide: Decodable {
    let n: Int, cash: Int, notional: Int
    var pct: Double? { notional > 0 ? Double(cash) / Double(notional) * 100 : nil }
}

struct TrendName: Decodable {
    let t: String
    let short: Int, lc: Int, lp: Int
    let ratio: Double?
}

struct TrendTheta: Decodable { let state: String; let lines: [String] }
struct TrendCredit: Decodable {
    let state: String; let lines: [String]
    let usualLo: Double?, usualHi: Double?
}

// MARK: - the card

struct SunnyCreditTheta: View {
    let block: CreditTrendBlock

    @AppStorage("sunnyfi.ct.tab") private var tab = 0          // 0 Theta · 1 Credit
    @State private var sel: Int? = nil
    @State private var drawn: CGFloat = 0
    @State private var dots = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let inner: CGFloat = S.content - 48          // 313
    private static let plotH: CGFloat = 120
    private static let axisH: CGFloat = 22
    private static let stripH: CGFloat = 60
    private static let stripW: CGFloat = 285
    private static let fillInk = S.driftBack                     // #1E6E68
    private static let outlineInk = S.hex(0x7C3A66)              // --drift-turn-2
    private static let stripInk = S.update                       // #2A4A6E
    private static let dim = 0.35

    /// The ratio strip's ceiling. A week at 15× is "comfortable" and nothing
    /// more; letting it set the scale would press 2× and 3.5× into the floor.
    private static let ratioTop = 6.0

    private var ws: [TrendWeek] { block.weeks }
    private var n: Int { ws.count }
    private var now: TrendWeek? { ws.last }

    // MARK: body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer().frame(height: 18)
            tabRow
            Spacer().frame(height: 22)
            hero
            Spacer().frame(height: 14)
            legend
            Spacer().frame(height: 14)
            chart
            Spacer().frame(height: 8)
            axis
            Spacer().frame(height: 22)
            Rectangle().fill(S.ruleColor).frame(height: 1)
            Spacer().frame(height: 16)
            sentence
            Spacer().frame(height: 12)
            strip
        }
        .frame(width: Self.inner, alignment: .leading)
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 28, trailing: 24))
        .frame(width: S.content, alignment: .top)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCardL)
        .monospacedDigit()
        .measure("credit-theta")
        .onAppear { redraw() }
    }

    private func redraw() {
        sel = nil
        guard !reduceMotion else { drawn = 1; dots = true; return }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { drawn = 0; dots = false }
        withAnimation(S.easeSettle(0.9)) { drawn = 1 }
        withAnimation(.easeOut(duration: 0.3).delay(0.75)) { dots = true }
    }

    // MARK: header · tabs

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                Text("Credit & theta").font(S.inter(S.t14, S.wBoldN))
                    .tracking(S.track(S.t14, -0.01)).foregroundStyle(S.ink)
                Text("the book").font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
            }
            Spacer(minLength: 0)
            Text(ivDay(block.asOf)).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
        }
        .frame(height: 17)
    }

    /* ⚠ COVERAGE'S TAB ROW, with the lens on the same rule. The lens word goes
       bold and carries no line: the line belongs to the question tabs. Only
       Weekly is shown until the other lenses have history. */
    private var tabRow: some View {
        HStack(alignment: .bottom, spacing: 28) {
            ForEach(Array(["Theta", "Credit"].enumerated()), id: \.offset) { i, label in
                VStack(spacing: 0) {
                    Text(label)
                        .font(S.inter(S.t12, tab == i ? S.wBoldN : S.wMidN))
                        .tracking(S.track(S.t12, -0.01))
                        .foregroundStyle(tab == i ? S.ink : S.mute)
                        .sunnyLineBox(S.t12)
                    Spacer().frame(height: 10)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(tab == i ? S.ink : .clear).frame(height: 2)
                }
                .fixedSize()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard tab != i else { return }
                    tab = i
                    redraw()
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                Text("Weekly").font(S.inter(S.t11, S.wBoldN)).foregroundStyle(S.ink)
                    .sunnyLineBox(S.t11)
                Spacer().frame(height: 10)
            }
            .fixedSize()
        }
        .frame(height: 22, alignment: .bottom)
        .background(alignment: .bottom) {
            Rectangle().fill(S.ruleColor).frame(height: 1)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: tab)
    }

    // MARK: hero

    private enum Band { case comfortable, watch, danger }
    private func band(_ r: Double) -> Band { r >= 3.5 ? .comfortable : (r >= 2 ? .watch : .danger) }

    @ViewBuilder private var hero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if tab == 0 {
                let r = now?.ratio
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    big(r.map(ratioText) ?? "\u{2013}")
                    if let r {
                        let b = band(r)
                        small(b == .comfortable ? "comfortable" : (b == .watch ? "watch" : "danger"),
                              weight: S.wSemiN,
                              ink: b == .comfortable ? S.gainText : (b == .watch ? S.mute : S.lossText))
                    }
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    big(signedMoney(Double((now?.short ?? 0) + (now?.long ?? 0))))
                    small("net a day", weight: S.wMidSmN, ink: S.mute)
                }
                .fixedSize()
            } else {
                let p = now?.blend
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    big(p.map(pctText) ?? "\u{2013}")
                    small("of strike", weight: S.wMidSmN, ink: S.mute)
                }
                Spacer(minLength: 0)
                if let p, let lo = block.credit.usualLo, let hi = block.credit.usualHi {
                    small(p > hi ? "above your usual" : (p < lo ? "below your usual" : "in your usual range"),
                          weight: S.wSemiN,
                          ink: p > hi ? S.gainText : (p < lo ? S.lossText : S.mute))
                        .fixedSize()
                }
            }
        }
        .frame(height: 22)
    }

    private func big(_ s: String) -> some View {
        Text(s).font(S.inter(S.t22, S.wBoldN)).tracking(S.track(S.t22, -0.03))
            .foregroundStyle(S.ink).lineLimit(1).fixedSize()
    }
    private func small(_ s: String, weight: CGFloat, ink: Color) -> some View {
        Text(s).font(S.inter(S.t12, weight)).foregroundStyle(ink).lineLimit(1).fixedSize()
    }

    private func ratioText(_ r: Double) -> String {
        (r >= 10 ? String(format: "%.0f", r) : String(format: "%.1f", r)) + "\u{00D7}"
    }
    private func pctText(_ p: Double) -> String { String(format: "%.2f", p) + "%" }

    // MARK: legend

    private var legend: some View {
        HStack(spacing: 14) {
            if tab == 0 {
                entry(filled: true, "Long pays", optMoney(now?.long ?? 0))
                entry(filled: false, "Short collects", signedMoney(Double(now?.short ?? 0)))
            } else {
                entry(filled: true, "Calls", now?.calls.pct.map(pctText) ?? "\u{2013}")
                entry(filled: false, "Puts", now?.puts.pct.map(pctText) ?? "\u{2013}")
            }
            Spacer(minLength: 0)
        }
        .frame(height: 11)
    }

    private func entry(filled: Bool, _ word: String, _ fig: String) -> some View {
        let ink = filled ? Self.fillInk : Self.outlineInk
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(filled ? ink : .clear)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(ink, lineWidth: 1.5))
                .frame(width: 9, height: 9)
            Text(word).font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                .sunnyLineBox(S.t11)
            Text(fig).font(S.inter(S.t11, S.wSemiN)).foregroundStyle(S.ink)
                .sunnyLineBox(S.t11)
        }
        .fixedSize()
    }

    // MARK: chart

    /// The two series a tab: FILLED first, OUTLINE second. Theta draws both as
    /// magnitudes so the gap between them is the distance on screen.
    private var series: (fill: [Double?], line: [Double?]) {
        tab == 0
            ? (ws.map { Double(abs($0.long)) }, ws.map { Double($0.short) })
            : (ws.map { $0.calls.pct }, ws.map { $0.puts.pct })
    }

    private func xAt(_ i: Int, _ w: CGFloat) -> CGFloat {
        n <= 1 ? w / 2 : CGFloat(i) / CGFloat(n - 1) * w
    }

    /// The trend scale: floor = min − 25% of the range, ceiling = max + 10%.
    /// Both series share it. Lines show shape; the figures print the quantity.
    private func trendScale(_ vals: [Double], h: CGFloat, padTop: CGFloat) -> (Double) -> CGFloat {
        let mn = vals.min() ?? 0, mx = vals.max() ?? 1
        let r = (mx - mn) != 0 ? (mx - mn) : (abs(mn) * 0.1 != 0 ? abs(mn) * 0.1 : 1)
        let lo = mn - r * 0.25, hi = mx + r * 0.1
        return { v in padTop + (h - padTop) * CGFloat(1 - (v - lo) / (hi - lo)) }
    }

    /* ⚠ A WEEK A SIDE DID NOT TRADE BREAKS THE LINE, it is never bridged. One put
       sold on 13 Jul and none until 10 Aug drew as a straight slide across four
       empty weeks, a trend that never happened. A run of one week draws nothing. */
    private func runs(_ vals: [Double?], x: (Int) -> CGFloat, y: (Double) -> CGFloat) -> [[CGPoint]] {
        var out: [[CGPoint]] = [], cur: [CGPoint] = []
        for (i, v) in vals.enumerated() {
            if let v { cur.append(CGPoint(x: x(i), y: y(v))) }
            else { if cur.count > 1 { out.append(cur) }; cur = [] }
        }
        if cur.count > 1 { out.append(cur) }
        return out
    }

    private var chart: some View {
        let s = series
        let all = (s.fill + s.line).compactMap { $0 }
        let y = trendScale(all, h: Self.plotH, padTop: 8)
        let fr = runs(s.fill, x: { xAt($0, Self.inner) }, y: y)
        let lr = runs(s.line, x: { xAt($0, Self.inner) }, y: y)
        let picked = sel
        return ZStack(alignment: .topLeading) {
            Group {
                ForEach(fr.indices, id: \.self) { k in
                    catmull(fr[k]).closed(to: Self.plotH, fr[k])
                        .fill(LinearGradient(colors: [Self.fillInk.opacity(0.55), Self.fillInk.opacity(0.02)],
                                             startPoint: .top, endPoint: .bottom))
                        .opacity(Double(drawn))
                    catmull(fr[k]).trimmedPath(from: 0, to: drawn)
                        .stroke(Self.fillInk, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                ForEach(lr.indices, id: \.self) { k in
                    catmull(lr[k]).trimmedPath(from: 0, to: drawn)
                        .stroke(Self.outlineInk, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
                if let v = s.fill.last, let v { endDot(CGPoint(x: Self.inner, y: y(v)), Self.fillInk, r: 3.5) }
                if let v = s.line.last, let v { endDot(CGPoint(x: Self.inner, y: y(v)), Self.outlineInk, r: 3.5) }
            }
            .opacity(picked == nil ? 1 : Self.dim)

            if let i = picked {
                let x = xAt(i, Self.inner)
                Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: Self.plotH)) }
                    .stroke(S.hair, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                if let v = s.fill[i] { dot(CGPoint(x: x, y: y(v)), Self.fillInk, r: 3.5) }
                if let v = s.line[i] { dot(CGPoint(x: x, y: y(v)), Self.outlineInk, r: 3.5) }
                callout(i, x: x)
            }
        }
        .frame(width: Self.inner, height: Self.plotH, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: sel)
    }

    private func endDot(_ p: CGPoint, _ ink: Color, r: CGFloat) -> some View {
        dot(p, ink, r: r).opacity(dots ? 1 : 0)
    }

    private func dot(_ p: CGPoint, _ ink: Color, r: CGFloat) -> some View {
        Circle().fill(ink)
            .overlay(Circle().strokeBorder(S.paper, lineWidth: 1.5).padding(-1.5))
            .frame(width: r * 2, height: r * 2)
            .position(p)
    }

    // MARK: callout

    @ViewBuilder private func callout(_ i: Int, x: CGFloat) -> some View {
        let w = ws[i]
        let (fig, figNow, diff): (String, String, String) = {
            if tab == 0 {
                let a = w.ratio, b = now?.ratio
                let d = (a != nil && b != nil) ? b! - a! : nil
                return (a.map(ratioText) ?? "\u{2013}", "",
                        d.map { signedStep($0, "%.1f", "\u{00D7}") } ?? "\u{2013}")
            } else {
                let a = w.blend, b = now?.blend
                let d = (a != nil && b != nil) ? b! - a! : nil
                return (a.map(pctText) ?? "\u{2013}", "",
                        d.map { signedStep($0, "%.2f", " pts") } ?? "\u{2013}")
            }
        }()
        let second: (String, String) = {
            if tab == 0 {
                let net = w.short + w.long, nn = (now?.short ?? 0) + (now?.long ?? 0)
                return (signedMoney(Double(net)), signedMoney(Double(nn - net)))
            } else {
                let a = w.ratio, b = now?.ratio
                let d = (a != nil && b != nil) ? b! - a! : nil
                return (a.map(ratioText) ?? "\u{2013}",
                        d.map { signedStep($0, "%.1f", "\u{00D7}") } ?? "\u{2013}")
            }
        }()
        let _ = figNow
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text(pairLabel(w.week) + " \u{00B7} ").font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                Text(fig).font(S.inter(S.t11, S.wSemiN)).foregroundStyle(S.ink)
                Text(" \u{00B7} ").font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                Text(second.0).font(S.inter(S.t11, S.wSemiN)).foregroundStyle(S.ink)
            }
            .sunnyLineBox(S.t11)
            HStack(spacing: 0) {
                Text("vs now \u{00B7} ").font(S.inter(S.t10, S.wMidSmN)).foregroundStyle(S.mute)
                Text(diff).font(S.inter(S.t10, S.wSemiN)).foregroundStyle(stepInk(diff))
                Text(" \u{00B7} ").font(S.inter(S.t10, S.wMidSmN)).foregroundStyle(S.mute)
                Text(second.1).font(S.inter(S.t10, S.wSemiN)).foregroundStyle(stepInk(second.1))
            }
            .sunnyLineBox(S.t10)
        }
        .padding(EdgeInsets(top: 2, leading: 6, bottom: 3, trailing: 6))
        .background(S.paper, in: RoundedRectangle(cornerRadius: S.radiusChip))
        .overlay(RoundedRectangle(cornerRadius: S.radiusChip).strokeBorder(S.ruleColor, lineWidth: 1))
        .fixedSize()
        .alignmentGuide(.leading) { d in
            /* Anchored at the bucket, pinned inside the plot near either edge. */
            if x < 70 { return 0 }
            if x > Self.inner - 70 { return d.width - Self.inner }
            return d.width / 2 - x
        }
    }

    /// A change that rounds to nothing prints "flat", never "−0.0×".
    private func signedStep(_ v: Double, _ fmt: String, _ unit: String) -> String {
        let t = String(format: fmt, abs(v))
        if Double(t) == 0 { return "flat" }
        return (v < 0 ? "\u{2212}" : "+") + t + unit
    }
    private func stepInk(_ s: String) -> Color {
        s == "flat" || s == "+$0" ? S.mute : (s.hasPrefix("\u{2212}") ? S.lossText : S.gainText)
    }

    private func pairLabel(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]) else { return iso }
        let mon = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][m - 1]
        return "\(d) \(mon)"
    }

    // MARK: axis

    private func labelShown(_ i: Int) -> Bool {
        let live = n - 1
        if let s = sel {
            if i == s { return true }
            if abs(i - s) == 1 { return false }
        }
        if i == live { return true }
        let step = n > 6 ? 2 : 1
        guard i % step == 0 else { return false }
        /* A shown label beside the live one hides. */
        if step == 2 && live - i == 1 { return false }
        return true
    }

    private var axis: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(S.ruleColor).frame(width: Self.inner, height: 1).offset(y: 2)
            ForEach(0..<n, id: \.self) { i in
                let hot = i == n - 1 || i == sel
                VStack(spacing: 6) {
                    Circle().fill(hot ? S.ink : S.hair).frame(width: 5, height: 5)
                    Text(pairLabel(ws[i].week))
                        .font(S.inter(S.t10, hot ? S.wSemiN : S.wMidSmN))
                        .foregroundStyle(hot ? S.ink : S.mute)
                        .lineLimit(1).fixedSize()
                        .sunnyLineBox(S.t10)
                        .opacity(labelShown(i) ? 1 : 0)
                }
                .fixedSize()
                .opacity(sel == nil || sel == i ? 1 : Self.dim)
                .frame(width: 26, height: 44, alignment: .top)
                .padding(.top, 0)
                .contentShape(Rectangle())
                .onTapGesture { sel = (sel == i) ? nil : i }
                .position(x: xAt(i, Self.inner), y: 22)
            }
        }
        .frame(width: Self.inner, height: Self.axisH, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: sel)
    }

    // MARK: sentence

    private var lines: [String] { tab == 0 ? block.theta.lines : block.credit.lines }

    private var sentence: some View {
        let lh = (S.interUI(S.t12, S.wMidSmN)?.lineHeight ?? 14.5)
        return Text(lines.joined(separator: "\n"))
            .font(S.inter(S.t12, S.wMidSmN))
            .lineSpacing(max(0, 16.2 - lh))
            .multilineTextAlignment(.center)
            .foregroundStyle(S.ink2)
            .padding(.horizontal, 12)
            .frame(width: Self.inner, alignment: .top)
            .frame(minHeight: 32, alignment: .top)
    }

    // MARK: strip

    private var stateInk: Color {
        switch tab == 0 ? block.theta.state : block.credit.state {
        case "Strengthening": return S.gainText
        case "Weakening": return S.lossText
        default: return S.mute
        }
    }

    private var strip: some View {
        let W = Self.stripW, H = Self.stripH
        let y: (Double) -> CGFloat
        let vals: [Double?]
        let bandHi: Double?, bandLo: Double?
        let hiLabel: String, loLabel: String
        if tab == 0 {
            y = { v in 4 + 52 * CGFloat(1 - min(max(v, 0), Self.ratioTop) / Self.ratioTop) }
            vals = ws.map(\.ratio)
            bandHi = 3.5; bandLo = 2
            hiLabel = "3.5\u{00D7}"; loLabel = "2\u{00D7}"
        } else {
            vals = ws.map(\.blend)
            let lo = block.credit.usualLo, hi = block.credit.usualHi
            var dom = vals.compactMap { $0 }
            if let lo { dom.append(lo) }
            if let hi { dom.append(hi) }
            let mn = dom.min() ?? 0, mx = dom.max() ?? 1
            let r = mx - mn > 0 ? mx - mn : 1
            let a = mn - r * 0.25, b = mx + r * 0.1
            y = { v in 4 + 52 * CGFloat(1 - (v - a) / (b - a)) }
            bandHi = hi; bandLo = lo
            /* One decimal: the strip's 28pt gutter holds "1.2%", not "1.19%". */
            hiLabel = hi.map { String(format: "%.1f", $0) + "%" } ?? ""
            loLabel = lo.map { String(format: "%.1f", $0) + "%" } ?? ""
        }
        let xs: (Int) -> CGFloat = { i in self.n <= 1 ? W / 2 : CGFloat(i) / CGFloat(self.n - 1) * W }
        let rr = runs(vals, x: xs, y: y)
        return ZStack(alignment: .topLeading) {
            if let bh = bandHi, let bl = bandLo {
                let top = y(bh), bot = y(bl)
                Rectangle().fill(S.wash).frame(width: W, height: max(0, bot - top)).offset(y: top)
                ForEach([top, bot], id: \.self) { yy in
                    Path { p in p.move(to: CGPoint(x: 0, y: yy)); p.addLine(to: CGPoint(x: W, y: yy)) }
                        .stroke(S.hair, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                Text(hiLabel).font(S.inter(S.t10, S.wMidSmN)).foregroundStyle(S.mute)
                    .fixedSize().sunnyLineBox(S.t10)
                    .frame(width: Self.inner, alignment: .trailing).offset(y: top - 5)
                Text(loLabel).font(S.inter(S.t10, S.wMidSmN)).foregroundStyle(S.mute)
                    .fixedSize().sunnyLineBox(S.t10)
                    .frame(width: Self.inner, alignment: .trailing).offset(y: bot - 5)
            }
            ForEach(rr.indices, id: \.self) { k in
                catmull(rr[k]).closed(to: H, rr[k])
                    .fill(LinearGradient(colors: [Self.stripInk.opacity(0.3), Self.stripInk.opacity(0.04)],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(Double(drawn))
                catmull(rr[k]).trimmedPath(from: 0, to: drawn)
                    .stroke(Self.stripInk, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            if let v = vals.last, let v {
                Circle().fill(Self.stripInk).frame(width: 5, height: 5)
                    .position(x: W, y: y(v)).opacity(dots ? 1 : 0)
            }
            HStack(spacing: 5) {
                Text("Trend").font(S.inter(S.t10, S.wSemiN)).foregroundStyle(S.mute)
                    .sunnyLineBox(S.t10)
                Text(tab == 0 ? block.theta.state : block.credit.state)
                    .font(S.inter(S.t10, S.wSemiN)).foregroundStyle(stateInk)
                    .sunnyLineBox(S.t10)
            }
            .fixedSize()
            .padding(EdgeInsets(top: 0, leading: 0, bottom: 3, trailing: 5))
            .background(S.paper)
        }
        .frame(width: Self.inner, height: H, alignment: .topLeading)
    }

    // MARK: geometry

    /// Catmull-Rom through every point, as cubic Béziers. The sheet's curvePath.
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
}

private extension Path {
    /// The curve closed down to the floor, for the filled series.
    func closed(to floor: CGFloat, _ p: [CGPoint]) -> Path {
        var out = self
        guard let a = p.first, let b = p.last else { return out }
        out.addLine(to: CGPoint(x: b.x, y: floor))
        out.addLine(to: CGPoint(x: a.x, y: floor))
        out.closeSubpath()
        return out
    }
}
