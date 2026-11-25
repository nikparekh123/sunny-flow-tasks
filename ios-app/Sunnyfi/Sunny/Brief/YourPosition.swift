//
//  YourPosition.swift
//  Sunny
//
//  Your position (block 30): the whole book by Friday's close if the whole market moves together.
//  Title, the moment's sub line, the sentence, the payoff from 10% down to 10% up (solid = by Friday, dashed =
//  today, the area above and below zero in grey (focus, 25 Nov), an orange line where the book turns short), the three numbers, the put
//  cover line, the early assignment line (ex-dividend weeks only), then By name (short, thin, long) and the
//  button into Positions. A row opens Positions on that name at the Friday close stop.
//  Focus (25 Nov): words are neutral (ink 15 pt and up, grey under), the three numbers carry + or −, a name's
//  "makes the most" line keeps a red dot when it is short (a warning); the Short / Thin pills keep their colour.
//

import SwiftUI

struct YourPositionCard: View {
    let card: JSONValue
    let privacy: Bool
    @Environment(BriefState.self) private var brief
    @Environment(HomeRouter.self) private var router

    var body: some View {
        if let m = BriefDebug.sample ? YourPositionModel.sample(acct: brief.account.sampleKey, moment: brief.moment()) : brief.live?.position {
            // README 9.4 (Audit 7): IBKR late in the session = the last values with "As of", and no makes-the-most
            // line (as Positions does). Never on a pinned moment or the sample.
            if !BriefDebug.sample, let t = brief.asOf() { filled(Self.lateCopy(m), asOf: t) } else { filled(m) }
        } else {
            // A book with nothing held (README 9.4 and the cousin's empty book): the title and one line, no chart.
            VStack(alignment: .leading, spacing: 0) {
                Text("Your position").sType(BK.title, tabular: false).foregroundStyle(S.ink).accessibilityAddTraits(.isHeader)
                Text("Nothing held yet").sType(Self.sub, tabular: false).foregroundStyle(S.secondary).padding(.top, 4)
                Text("Once shares or options are in the book, this shows where it stands by Friday’s close if the whole market moves together.")
                    .sType(SType(size: 15, weight: 500, line: 21, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 16)
            }
            .briefCard()
            .padding(.horizontal, S.margin)
        }
    }

    /// The card while IBKR is late: the first sentence only (where the book stands now), no orange line on the chart,
    /// no makes-the-most words on the rows. The figures stay, marked "As of".
    static func lateCopy(_ m: YourPositionModel) -> YourPositionModel {
        var c = m
        if let end = m.sentence.firstIndex(where: { $0.t.contains(". ") || $0.t.hasSuffix(".") }) { c.sentence = Array(m.sentence[...end]) }
        c.shortAt = nil
        c.rows = m.rows.map { .init(id: $0.id, name: $0.name, line: "", lineColor: $0.lineColor, right: $0.right, rightColor: $0.rightColor, at: $0.at, st: $0.st) }
        return c
    }

    private func filled(_ m: YourPositionModel, asOf: Date? = nil) -> some View {
        // SunnyBriefs.dc.html `pos`: blocks 16 apart; title and sub 4 apart.
        VStack(alignment: .leading, spacing: 0) {
            Text("Your position").sType(BK.title, tabular: false).foregroundStyle(S.ink).accessibilityAddTraits(.isHeader)
            Text(m.subtitle).sType(Self.sub, tabular: false).foregroundStyle(S.secondary).padding(.top, 4)
            if let t = asOf {
                Text("As of \(PositionsTab.asOfWords(t)) · IBKR data is late").sType(BK.sub, tabular: false).foregroundStyle(SF.word(BK.sub.size)).padding(.top, 4)
            }
            BriefSentence(m.sentence, base: SType(size: 17, weight: 500, line: 24, tracking: 0), privacy: privacy)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
            // The chart, its axis and legend, 6 apart.
            PayoffChart(m: m).frame(height: 150).padding(.top, 16)
            BAxis(marks: [(0, 0), (0.25, 0.5), (0.5, 0.5), (0.75, 0.5), (1, 1)]) {
                ForEach(["↓ 10%", "↓ 5%", "Today", "↑ 5%", "↑ 10%"], id: \.self) { l in
                    Text(l).sType(SType(size: 12, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                }
            }
            .padding(.top, 6)
            .environment(\.sTypeScales, false)   // chart labels keep their size: the axis is drawn to it (they collided at large text)
            .accessibilityHidden(true)   // the payoff's spoken summary covers the axis
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(S.ink).frame(width: 14, height: 3)
                    Text("Shares and options by Friday’s close").sType(Self.legend, tabular: false)
                }
                HStack(spacing: 5) {
                    Path { $0.move(to: CGPoint(x: 0, y: 0.75)); $0.addLine(to: CGPoint(x: 14, y: 0.75)) }
                        .stroke(S.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                        .frame(width: 14, height: 1.5)
                    Text("Today").sType(Self.legend, tabular: false)
                }
            }
            .foregroundStyle(S.secondary)
            .padding(.top, 6)
            .accessibilityHidden(true)
            // The three numbers under a rule (padding-top 14), 8 apart.
            BHairline().padding(.top, 16)
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(m.stats.enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BK.signed(BriefWords.plain(s.value, privacy: privacy), s.color) ?? "").sType(SType(size: 17, weight: 700, line: 20, tracking: 0))
                            .foregroundStyle(BK.word(s.color, 17)).lineLimit(1)
                        Text(s.label).sType(SType(size: 12, weight: 500, line: 14, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(statSpoken(s))
                }
            }
            .padding(.top, 14)
            Text(m.cover).sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            if let a = m.assign {
                Text(a).sType(SType(size: 13, weight: 600, line: 18, tracking: 0), tabular: false).foregroundStyle(SF.word(13))
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            }
            // By name under a rule: the header (4 under it), then rows of at least 56 with a rule between.
            BHairline().padding(.top, 16)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("By name").sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text(m.count).sType(SType(size: 13, weight: 600, line: 18, tracking: 0), tabular: false).foregroundStyle(BK.word(m.countColor, 13))
                    .multilineTextAlignment(.trailing)
            }
            .padding(.top, 14)
            .padding(.bottom, 4)
            ForEach(Array(m.rows.enumerated()), id: \.element.id) { i, r in
                if i > 0 { BHairline() }
                Button { open(r.id) } label: { row(r).frame(minHeight: i > 0 ? 55 : 56) }.buttonStyle(.plain)
            }
            Button { open(nil) } label: {
                Text("Every leg in Positions").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Capsule().fill(BB.fill))
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
        .briefCard()
        .padding(.horizontal, S.margin)
        .accessibilityElement(children: .contain)
    }

    /// A name's net delta by Friday from today (left) to three priced moves up (right): solid while long, dotted where it
    /// turns short, a dashed zero line, the dot at the priced move (point 4 of 13).
    static func deltaLine(_ c: [Double]) -> some View {
        let lo = min(0, c.min() ?? 0), hi = max(0, c.max() ?? 0), pad = (hi - lo) * 0.08 == 0 ? 1 : (hi - lo) * 0.08
        let a = lo - pad, b = hi + pad, n = c.count - 1
        return GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let X = { (i: Int) in CGFloat(i) / CGFloat(n) * w }, Y = { (v: Double) in CGFloat((b - v) / (b - a)) * h }
            let seg = { (long: Bool) in Path { p in
                for i in 0..<n where (c[i] >= 0 && c[i + 1] >= 0) == long {
                    p.move(to: CGPoint(x: X(i), y: Y(c[i]))); p.addLine(to: CGPoint(x: X(i + 1), y: Y(c[i + 1])))
                }
            } }
            let k = min(4, n), tone = c[k] < 0 ? S.red : c[k] < 0.25 * (c.first.map { max($0, 1) } ?? 1) ? S.act : S.secondary
            ZStack(alignment: .topLeading) {
                Path { p in p.move(to: CGPoint(x: 0, y: Y(0))); p.addLine(to: CGPoint(x: w, y: Y(0))) }
                    .stroke(S.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [1.5, 3]))
                seg(true).stroke(S.secondary, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                seg(false).stroke(S.red, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [2, 2.5]))
                Circle().fill(tone).frame(width: 5, height: 5).position(x: X(k), y: Y(c[k]))
            }
        }
        .accessibilityHidden(true)
    }

    static let sub = SType(size: 15, weight: 500, line: 20, tracking: 0)
    static let legend = SType(size: 12, weight: 500, line: 16, tracking: 0)

    /// A By name row: 32 logo, 10 apart, name 15/20 over its line 13/17, the delta 15/20 over "at" 12/15; 8 above and below.
    private func row(_ r: YourPositionModel.Row) -> some View {
        HStack(spacing: 10) {
            BLogo(ticker: r.id, size: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(r.name).sType(BK.row, tabular: false).foregroundStyle(S.ink)
                if !r.line.isEmpty {
                    // A short name's line is a warning: neutral words with the red dot before them (§2.3); thin
                    // (orange, a watch) has no dot.
                    (r.lineColor == "red" ? SF.dot(.danger) + Text(r.line) : Text(r.line))
                        .sType(SType(size: 13, weight: 600, line: 17, tracking: 0)).foregroundStyle(BK.word(r.lineColor, 13)).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The rail's row style (Nov 17): a small line (net delta by Friday as the price rises to three priced
            // moves, dotted where it turns short, the dot at the priced move), then a pill (Short red, Thin orange,
            // Long grey) with "at ↑2.9%" under it.
            if r.curve.count > 1 { Self.deltaLine(r.curve).frame(width: 52, height: 24) }
            VStack(alignment: .trailing, spacing: 2) {
                let tone = r.rightColor == "red" ? S.red : r.rightColor == "orange" ? S.act : nil
                Text(r.right).sType(SType(size: 14, weight: 600, line: 18, tracking: 0)).lineLimit(1)
                    .foregroundStyle(tone == nil ? S.ink : S.dyn(0xFAFAFA, 0x171717))
                    .padding(.horizontal, 9).frame(minWidth: 68, minHeight: 30)
                    .background(tone ?? S.dynA(0x808080, 0.16, 0x808080, 0.32), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                if !r.at.isEmpty {   // empty for a name with no option prices (no priced move)
                    Text(r.at).sType(SType(size: 12, weight: 500, line: 15, tracking: 0)).foregroundStyle(S.secondary).lineLimit(1)
                }
            }
            .fixedSize()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BriefWords.speech("\(r.name), \(r.line), \(r.right) \(r.at)"))
        .accessibilityHint("Opens Positions")
    }

    /// "15 thousand dollars if up 5 percent"; a red figure is a loss: "lost 8 thousand dollars if down 5 percent";
    /// privacy: "hidden if up 5 percent".
    private func statSpoken(_ s: (value: String, label: String, color: String)) -> String {
        var v = s.value.trimmingCharacters(in: .whitespaces)
        let neg = v.hasPrefix("-") || v.hasPrefix("\u{2212}")
        if neg { v.removeFirst() }
        let shown = BriefWords.plain(v, privacy: privacy)
        let lost = !shown.contains(BriefMask.shown) && (neg || s.color == "red")
        return BriefWords.speech((lost ? "lost " : "") + shown + " " + s.label)
    }

    /// A row opens Positions on that name; the button on the last name viewed.
    private func open(_ t: String?) {
        brief.positionsName = t ?? brief.positionsName
        router.tab = .positions
    }
}

/// The payoff: x = every name moving the same %, −10% to +10%; y = P&L. Solid ink = by Friday, dashed = today,
/// the area above and below zero neutral grey at low alpha (focus §2.4: it was green and red), the dot at today, the
/// orange line where the book turns short.
struct PayoffChart: View {
    let m: YourPositionModel
    var body: some View {
        Canvas { ctx, size in
            let all = m.friday + m.today
            let mx = max(all.max() ?? 1, 1) * 1.1, mn = min(all.min() ?? -1, -1) * 1.1
            let W = size.width, H = size.height
            let X = { (v: Double) -> CGFloat in CGFloat((v + 10) / 20) * W }
            let Y = { (p: Double) -> CGFloat in CGFloat((mx - p) / (mx - mn)) * H }
            func path(_ a: [Double]) -> Path {
                var p = Path()
                for (i, v) in a.enumerated() { let pt = CGPoint(x: X(m.grid[i]), y: Y(v)); i == 0 ? p.move(to: pt) : p.addLine(to: pt) }
                return p
            }
            let line = path(m.friday), y0 = Y(0)
            var area = line
            area.addLine(to: CGPoint(x: W, y: y0)); area.addLine(to: CGPoint(x: 0, y: y0)); area.closeSubpath()
            ctx.drawLayer { c in
                c.clip(to: Path(CGRect(x: -4, y: -30, width: W + 8, height: y0 + 30)))
                c.fill(area, with: .color(S.pNeutral.opacity(0.14)))
            }
            ctx.drawLayer { c in
                c.clip(to: Path(CGRect(x: -4, y: y0, width: W + 8, height: 240)))
                c.fill(area, with: .color(S.pNeutral.opacity(0.12)))
            }
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y0)); $0.addLine(to: CGPoint(x: W, y: y0)) }, with: .color(S.secondary.opacity(0.45)), lineWidth: 1)
            if let s = m.shortAt {
                ctx.stroke(Path { $0.move(to: CGPoint(x: X(s), y: 0)); $0.addLine(to: CGPoint(x: X(s), y: H)) }, with: .color(S.act),
                           style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
            }
            ctx.stroke(path(m.today), with: .color(S.secondary), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            ctx.stroke(line, with: .color(S.ink), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            if let i0 = m.grid.firstIndex(of: 0) {
                let p = CGPoint(x: X(0), y: Y(m.friday[i0]))
                let dot = Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                ctx.fill(dot, with: .color(S.ink))
                ctx.stroke(dot, with: .color(S.paper), lineWidth: 2)   // SVG order: the paper stroke sits over the fill
            }
        }
        // Where the book makes the most (the design's "Short above ↑4.2%"; Nik retired "short above", 7 Nov 2026) over
        // the orange line (12/15 bold), flipped left past 220 of 313.
        .overlay(alignment: .topLeading) {
            if let s = m.shortAt {
                let f = CGFloat((s + 10) / 20)
                BAxis(marks: [(f, f > 220 / 313 ? 1 : 0)]) {
                    Text("Makes the most at ↑" + SampleEngine.f1(s) + "%").sType(SType(size: 12, weight: 700, line: 15, tracking: 0))
                        .foregroundStyle(SF.word(12)).lineLimit(1).padding(.horizontal, 4)   // a word: grey; the line keeps its orange
                }
                .offset(y: -2)
                .environment(\.sTypeScales, false)   // a chart label, drawn to the chart
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(m.aria.isEmpty ? "Your position, P&L by Friday if the market moves 10% down to 10% up." : m.aria)
    }
}
