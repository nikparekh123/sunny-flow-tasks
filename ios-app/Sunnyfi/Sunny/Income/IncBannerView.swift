//
//  IncBannerView.swift
//  Sunny
//
//  The realized-income banner on top of the Income tab (handoff-2026-11-24-income README, SunnyIncome banner bars,
//  narrow): realized income from calls and puts sold, Weekly | Monthly. Weekly opens on last week (the weekly names
//  realize on Friday), Monthly on this month. The chart is the hero: 8 bars, 140 tall, every bar stacked in full colour
//  (calls #86A8F0, puts #C8946A dark; #4F7BDA, #B5794A light), dashed grid and a value scale on the right; a tap picks
//  a bar (a soft column behind it, its value on top). A week or month that lost money draws its loss below the line in
//  red tones, never with a minus sign. Everything else is small: Realized income and the period 13 pt, the total 22,
//  the yield grey ("about N% a year", or "so far" for one not finished), Calls and Puts beside the switch, Together's
//  Sunny · Nicolay parts, then By ticker as thin 34 pt rows (logo, ticker, total, grey "avg $"), the top 5 then
//  All N names | Fewer. Card padding 16, radius 20, 14 apart.
//

import SwiftUI

struct IncBannerView: View {
    let banner: IncBanner
    let privacy: Bool
    /// Together: Sunny's and Nicolay's parts under the total, in this order.
    let accounts: [String]
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// Weekly or Monthly, and the bar picked in each (nil: the one it opens on).
    @State private var monthly = false
    @State private var pickW: String?
    @State private var pickM: String?
    @State private var allNames = false

    private static let chartH: CGFloat = 140
    /// The bars' scale height (the rest above is room for the picked value).
    private static let plotH: CGFloat = 120
    private static let gutter: CGFloat = 32
    /// The switch's thumb: white in light, a soft lift in dark, under the glass.
    private static let thumb = S.dynA(0xFFFFFF, 1, 0xFFFFFF, 0.2)

    var body: some View {
        let per = periods
        let si = selectedIndex(per)
        let sel = per.indices.contains(si) ? per[si] : nil
        VStack(alignment: .leading, spacing: 14) {
            header(sel)
            if !per.isEmpty {
                VStack(spacing: 8) {
                    chart(per, si)
                    labels(per, si)
                }
            }
            if let sel { tickers(sel) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sunnyGlass(radius: 20)
    }

    // MARK: Periods

    /// The last 8 weeks, or every month, from the first with any income.
    private var periods: [IncBanner.Period] {
        let all = monthly ? banner.months : Array(banner.weeks.suffix(8))
        guard let f = all.firstIndex(where: { abs($0.total) >= 0.5 }) else { return all }
        return Array(all[f...])
    }
    private func selectedIndex(_ per: [IncBanner.Period]) -> Int {
        if let k = monthly ? pickM : pickW, let i = per.firstIndex(where: { $0.id == k }) { return i }
        guard !per.isEmpty else { return 0 }
        // Weekly opens on last week while this one is under way; Monthly on this month.
        if !monthly, per.count > 1, per.last?.cur == true { return per.count - 2 }
        return per.count - 1
    }

    // MARK: Header

    @ViewBuilder private func header(_ sel: IncBanner.Period?) -> some View {
        let c = sel?.c ?? 0, p = sel?.p ?? 0, t = c + p
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Text("Realized income").foregroundStyle(IncC.ink).fontWeight(.semibold))  \(Text(sel?.cap ?? "").foregroundStyle(IncC.mu))")
                    .sType(IncT.t(13, 18), tabular: false)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) { total(t); yield(sel, t) }
                    VStack(alignment: .leading, spacing: 2) { total(t); yield(sel, t) }
                }
                if accounts.count > 1, let sel {
                    accountParts(sel)
                }
            }
            // Calls and Puts beside the switch; the switch wraps under them when both do not fit (flex-wrap).
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    legends(c, p)
                    Spacer(minLength: 4)
                    switcher
                }
                VStack(alignment: .leading, spacing: 8) {
                    legends(c, p)
                    switcher
                }
            }
        }
    }

    private func total(_ t: Double) -> some View {
        Text(IncFmt.dollars(t, privacy)).sType(IncT.t(22, 28, 700, tr: -0.02))
            .foregroundStyle(t < 0 && !privacy ? IncC.red : IncC.ink)
            .lineLimit(1).fixedSize()
            .accessibilityLabel(privacy ? "hidden" : (t < 0 ? "lost " : "") + IncFmt.dollars(t, false))
    }

    /// Yield = the period's income ÷ what the shares cost; a full week × 52, a full month × 12; one not finished
    /// says "so far". None while the period lost money.
    @ViewBuilder private func yield(_ sel: IncBanner.Period?, _ t: Double) -> some View {
        if let sel, banner.capital > 0, t > 0 {
            let y = t / banner.capital * 100
            let v = String(format: y < 1 ? "%.2f" : "%.1f", y) + "%"
            let a = sel.cur ? "so far" : "about \(Int((y * (monthly ? 12 : 52)).rounded()))% a year"
            Text("\(v) yield · \(a)").sType(IncT.t(13, 18)).foregroundStyle(IncC.mu).lineLimit(1)
        }
    }

    /// "Sunny $5,373 · Nicolay $1,293" (12/16 grey; a loss in red).
    private func accountParts(_ sel: IncBanner.Period) -> some View {
        let parts = accounts.map { a -> Text in
            let v = sel.bk[a]?.total ?? 0
            return Text("\(a) \(Text(IncFmt.dollars(v, privacy)).foregroundStyle(v < 0 && !privacy ? IncC.red : IncC.mu))")
        }
        var line = Text("")
        for (i, p) in parts.enumerated() { line = i == 0 ? p : Text("\(line) · \(p)") }
        return line.sType(IncT.t(12, 16)).foregroundStyle(IncC.mu)
            .accessibilityLabel(accounts.map { a in
                let v = sel.bk[a]?.total ?? 0
                return "\(a) \(privacy ? "hidden" : (v < 0 ? "lost " : "") + IncFmt.dollars(v, false))"
            }.joined(separator: ", "))
    }

    private func legends(_ c: Double, _ p: Double) -> some View {
        HStack(spacing: 12) {
            legend(IncC.calls, "Calls", c)
            legend(IncC.puts, "Puts", p)
        }
    }

    private func legend(_ c: Color, _ l: String, _ v: Double) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(c).frame(width: 8, height: 8)
            Text("\(l) \(Text(IncFmt.dollars(v, privacy)).foregroundStyle(v < 0 && !privacy ? IncC.red : IncC.mu))")
                .sType(IncT.t(12, 16)).foregroundStyle(IncC.mu).lineLimit(1).fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(l) \(privacy ? "hidden" : (v < 0 ? "lost " : "") + IncFmt.dollars(v, false))")
    }

    /// Weekly | Monthly: a 2 pt track, 68 pt buttons 30 tall, the picked one on a glass thumb that slides.
    private var switcher: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { m in
                let on = m == monthly
                Button {
                    guard !on else { return }
                    withAnimation(S.moving(S.spring, reduce) ?? S.fade) { monthly = m }
                } label: {
                    Text(m ? "Monthly" : "Weekly")
                        .sType(IncT.t(12, 16, on ? 600 : 500), tabular: false)
                        .foregroundStyle(on ? IncC.ink : IncC.mu)
                        .padding(.horizontal, 10)
                        .frame(minWidth: 68, minHeight: 30)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .background(alignment: .leading) {
            GeometryReader { g in
                Capsule().fill(Self.thumb)
                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                    .glassEffect(.regular, in: .capsule)
                    .frame(width: g.size.width / 2, height: g.size.height)
                    .offset(x: monthly ? g.size.width / 2 : 0)
            }
        }
        .padding(2)
        .background(Capsule().fill(IncC.segTrack))
        .sensoryFeedback(.selection, trigger: monthly)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weekly or monthly")
    }

    // MARK: The chart

    /// The scale: a round step about a third of the range; gains above the zero line, losses below it.
    private struct Scale { let step: Double; let top: Double; let bot: Double; var range: Double { top + bot } }
    private func scale(_ per: [IncBanner.Period]) -> Scale {
        let up = per.map { max($0.c, 0) + max($0.p, 0) }.max() ?? 0
        let dn = per.map { -(min($0.c, 0) + min($0.p, 0)) }.max() ?? 0
        let span = max(1, up + dn)
        let raw = span / 3, p10 = pow(10, floor(log10(raw))), m = raw / p10
        let step = (m <= 1 ? 1 : m <= 2 ? 2 : m <= 2.5 ? 2.5 : m <= 5 ? 5 : 10) * p10
        return Scale(step: step, top: step * ceil(up / step), bot: dn > 0 ? step * ceil(dn / step) : 0)
    }

    private func chart(_ per: [IncBanner.Period], _ si: Int) -> some View {
        let sc = scale(per)
        let k = Self.plotH / max(1, sc.range)
        let zero = sc.bot * k
        return ZStack(alignment: .bottomLeading) {
            // Dashed grid with the value on the right, the zero line solid.
            ForEach(Array(gridValues(sc).enumerated()), id: \.offset) { _, v in
                let y = zero + v * k
                ZStack(alignment: .trailing) {
                    Line().stroke(IncC.line(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
                    Text(IncFmt.money(v, privacy)).font(.inter(11, 400, tabular: true))
                        .foregroundStyle(v < 0 ? IncC.red : IncC.mu)
                        .lineLimit(1).fixedSize()
                }
                .frame(height: 14)
                .offset(y: -(y - 7))
            }
            Rectangle().fill(IncC.line(0.08)).frame(height: 1)
                .padding(.trailing, Self.gutter)
                .offset(y: -zero)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(per.enumerated()), id: \.element.id) { i, x in
                    bar(x, on: i == si, k: k, zero: zero)
                }
            }
            .padding(.trailing, Self.gutter)
        }
        .frame(height: Self.chartH)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Realized by \(monthly ? "month" : "week"), pick one to read it")
    }

    private func gridValues(_ sc: Scale) -> [Double] {
        let n = Int((sc.top / sc.step).rounded()), m = Int((sc.bot / sc.step).rounded())
        return (0..<n).map { Double($0 + 1) * sc.step } + (0..<m).map { -Double($0 + 1) * sc.step }
    }

    /// One column: the soft column behind the picked one (radius 8 on top), its value 6 above the bar, the gains
    /// stacked up from the zero line (puts on top of calls), the losses hanging under it; an empty period a 2 pt stub.
    private func bar(_ x: IncBanner.Period, on: Bool, k: CGFloat, zero: CGFloat) -> some View {
        // A part that is not nothing shows at least 2 pt, so a small week still reads as a bar.
        func h(_ v: Double) -> CGFloat { abs(v) < 0.5 ? 0 : max(2, abs(v) * k) }
        let cU = h(max(x.c, 0)), pU = h(max(x.p, 0)), cD = h(min(x.c, 0)), pD = h(min(x.p, 0))
        let empty = abs(x.total) < 0.5 && cU + pU + cD + pD < 0.5
        return Button {
            if monthly { pickM = x.id } else { pickW = x.id }
        } label: {
            ZStack(alignment: .bottom) {
                UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8, style: .continuous)
                    .fill(on ? IncC.soft : .clear)
                VStack(spacing: 0) {
                    if on && !empty {
                        Text(IncFmt.money(x.total, privacy)).font(.inter(12, 700, tabular: true))
                            .foregroundStyle(x.total < 0 && !privacy ? IncC.red : IncC.ink)
                            .lineLimit(1).fixedSize()
                            .padding(.bottom, 6)
                    }
                    VStack(spacing: pU > 0 && cU > 0 ? 1 : 0) {
                        if pU > 0 { Rectangle().fill(IncC.puts).frame(height: pU) }
                        if cU > 0 { Rectangle().fill(IncC.calls).frame(height: cU) }
                        if empty { Rectangle().fill(IncC.track).frame(height: 2) }
                    }
                    .frame(maxWidth: 20)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous))
                    VStack(spacing: pD > 0 && cD > 0 ? 1 : 0) {
                        if cD > 0 { Rectangle().fill(IncC.callsLoss).frame(height: cD) }
                        if pD > 0 { Rectangle().fill(IncC.putsLoss).frame(height: pD) }
                    }
                    .frame(maxWidth: 20)
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4, style: .continuous))
                    Color.clear.frame(height: max(0, zero - cD - pD))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(S.fade, value: on)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(x.cap.components(separatedBy: " · ").first ?? x.l), \(privacy ? "hidden" : (x.total < 0 ? "lost " : "") + IncFmt.dollars(x.total, false)) realized")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The bars' labels: 10 pt, the picked one bold; past five bars every other one is left out so they never touch.
    private func labels(_ per: [IncBanner.Period], _ si: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(per.enumerated()), id: \.element.id) { i, x in
                let on = i == si
                Text(on || i % 2 == 0 || per.count <= 5 ? x.l : "")
                    .font(.inter(10, on ? 700 : 500, tabular: true))
                    .foregroundStyle(on ? IncC.ink : IncC.mu)
                    .lineLimit(1).fixedSize()
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 14)
        .padding(.trailing, Self.gutter)
        .accessibilityHidden(true)
    }

    // MARK: By ticker

    private func tickers(_ sel: IncBanner.Period) -> some View {
        let rows = banner.tickers.map { t -> (t: String, v: Double) in (t, sel.by[t]?.total ?? 0) }
            .sorted { $0.v != $1.v ? $0.v > $1.v : $0.t < $1.t }
        let shown = allNames ? rows : Array(rows.prefix(5))
        return VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 0) {
                ForEach(shown, id: \.t) { r in
                    HStack(spacing: 8) {
                        IncLogo(t: r.t, size: 18, ratio: 0.62)
                        Text(r.t).sType(IncT.t(13, 18, 600), tabular: false).foregroundStyle(IncC.ink)
                        Spacer(minLength: 8)
                        Text(IncFmt.dollars(r.v, privacy)).sType(IncT.t(13, 18, 600))
                            .foregroundStyle(r.v < 0 && !privacy ? IncC.red : IncC.ink)
                        Text(banner.avg[r.t].map { "avg $" + IncFmt.f2($0) } ?? "no shares")
                            .sType(IncT.t(12, 16)).foregroundStyle(IncC.mu)
                            .frame(minWidth: 76, alignment: .trailing)
                    }
                    .lineLimit(1)
                    .frame(minHeight: 34)
                    .overlay(alignment: .bottom) { Rectangle().fill(IncC.line(0.06)).frame(height: 1) }
                    .opacity(r.v > 0 ? 1 : 0.5)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(r.t), \(privacy ? "hidden" : (r.v < 0 ? "lost " : "") + IncFmt.dollars(r.v, false)) realized"
                                        + (banner.avg[r.t].map { ", share average \(IncFmt.f2($0)) dollars" } ?? ", no shares"))
                }
            }
            if rows.count > 5 {
                Button {
                    withAnimation(S.moving(S.page, reduce) ?? S.fade) { allNames.toggle() }
                } label: {
                    Text(allNames ? "Fewer" : "All \(rows.count) names").sType(IncT.t(12, 16, 600), tabular: false).foregroundStyle(IncC.mu)
                        .frame(minHeight: 32, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
            }
        }
    }
}

/// A horizontal line across its frame.
private struct Line: Shape {
    func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p }
}
