//
//  YourPosition.swift
//  Sunny
//
//  Your position (block 30): the whole book by Friday's close if the whole market moves together.
//  Title, the moment's sub line, the sentence, the payoff from 10% down to 10% up (solid = by Friday, dashed =
//  today, red below zero, green above, an orange line where the book turns short), the three numbers, the put
//  cover line, the early assignment line (ex-dividend weeks only), then By name (short, thin, long) and the
//  button into Positions. A row opens Positions on that name at the Friday close stop.
//

import SwiftUI

struct YourPositionCard: View {
    let card: JSONValue
    let privacy: Bool
    @Environment(BriefState.self) private var brief
    @Environment(HomeRouter.self) private var router

    var body: some View {
        if let m = BriefDebug.sample ? YourPositionModel.sample(acct: brief.account.sampleKey, moment: brief.moment()) : brief.live?.position {
            filled(m)
        } else {
            // A book with nothing held (README 9.4 and the cousin's empty book): the title and one line, no chart.
            VStack(alignment: .leading, spacing: 0) {
                Text("Your position").sType(BK.title, tabular: false).foregroundStyle(S.ink).accessibilityAddTraits(.isHeader)
                Text("Nothing held yet").sType(BK.sub, tabular: false).foregroundStyle(S.secondary).padding(.top, 2)
                Text("Once shares or options are in the book, this shows where it stands by Friday’s close if the whole market moves together.")
                    .sType(SType(size: 15, weight: 500, line: 21, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            }
            .briefCard()
            .padding(.horizontal, S.margin)
        }
    }

    private func filled(_ m: YourPositionModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your position").sType(BK.title, tabular: false).foregroundStyle(S.ink).accessibilityAddTraits(.isHeader)
            Text(m.subtitle).sType(BK.sub, tabular: false).foregroundStyle(S.secondary).padding(.top, 2)
            BriefSentence(m.sentence, base: SType(size: 15, weight: 500, line: 21, tracking: 0), privacy: privacy)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            PayoffChart(m: m).frame(height: 150).padding(.top, 16)
            HStack {
                ForEach(["↓ 10%", "↓ 5%", "Today", "↑ 5%", "↑ 10%"], id: \.self) { l in
                    Text(l).sType(BK.caption, tabular: false).foregroundStyle(S.secondary).frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 6)
            .accessibilityHidden(true)   // the payoff's spoken summary covers the axis
            HStack(spacing: 6) {
                Rectangle().fill(S.ink).frame(width: 14, height: 2.5)
                Text("Shares and options by Friday’s close").sType(BK.caption, tabular: false).foregroundStyle(S.secondary)
                Text("- - -").font(.system(size: 11, weight: .bold)).foregroundStyle(S.secondary)
                Text("Today").sType(BK.caption, tabular: false).foregroundStyle(S.secondary)
            }
            .padding(.top, 6)
            .accessibilityHidden(true)
            BHairline().padding(.vertical, 14)
            HStack(alignment: .top) {
                ForEach(Array(m.stats.enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BriefWords.plain(s.value, privacy: privacy)).sType(SType(size: 17, weight: 800, line: 22, tracking: 0)).foregroundStyle(BK.color(s.color))
                        Text(s.label).sType(BK.caption, tabular: false).foregroundStyle(S.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(statSpoken(s))
                }
            }
            Text(m.cover).sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            if let a = m.assign {
                Text(a).sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(S.act)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
            BHairline().padding(.vertical, 14)
            HStack(alignment: .firstTextBaseline) {
                Text("By name").sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(m.count).sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false).foregroundStyle(BK.color(m.countColor))
            }
            ForEach(Array(m.rows.enumerated()), id: \.element.id) { i, r in
                if i > 0 { BHairline() }
                Button { open(r.id) } label: { row(r) }.buttonStyle(.plain)
            }
            Button { open(nil) } label: {
                Text("Every leg in Positions").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Capsule().fill(S.chip))
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
        .briefCard()
        .padding(.horizontal, S.margin)
        .accessibilityElement(children: .contain)
    }

    private func row(_ r: YourPositionModel.Row) -> some View {
        HStack(spacing: 12) {
            BLogo(ticker: r.id, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name).sType(BK.row, tabular: false).foregroundStyle(S.ink)
                Text(r.line).sType(BK.rowSub).foregroundStyle(BK.color(r.lineColor)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(r.right).sType(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(BK.color(r.rightColor))
                Text(r.at).sType(BK.caption).foregroundStyle(S.secondary)
            }
        }
        .padding(.vertical, 10)
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

    /// A row opens Positions on that name at the Friday close stop; the button on the last name, at today.
    private func open(_ t: String?) {
        brief.positionsName = t ?? brief.positionsName
        brief.positionsAtFriday = t != nil
        router.tab = .positions
    }
}

/// The payoff: x = every name moving the same %, −10% to +10%; y = P&L. Solid ink = by Friday, dashed = today,
/// green fill above zero and red below at low alpha, the dot at today, the orange line where the book turns short.
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
                c.clip(to: Path(CGRect(x: 0, y: 0, width: W, height: y0)))
                c.fill(area, with: .color(S.green.opacity(0.14)))
            }
            ctx.drawLayer { c in
                c.clip(to: Path(CGRect(x: 0, y: y0, width: W, height: H - y0)))
                c.fill(area, with: .color(S.red.opacity(0.12)))
            }
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y0)); $0.addLine(to: CGPoint(x: W, y: y0)) }, with: .color(S.secondary.opacity(0.35)), lineWidth: 1)
            if let s = m.shortAt {
                ctx.stroke(Path { $0.move(to: CGPoint(x: X(s), y: 0)); $0.addLine(to: CGPoint(x: X(s), y: H)) }, with: .color(S.act), lineWidth: 1.5)
            }
            ctx.stroke(path(m.today), with: .color(S.ink.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            ctx.stroke(line, with: .color(S.ink), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            if let i0 = m.grid.firstIndex(of: 0) {
                let p = CGPoint(x: X(0), y: Y(m.friday[i0]))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(S.ink))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(m.aria.isEmpty ? "Your position, P&L by Friday if the market moves 10% down to 10% up." : m.aria)
    }
}
