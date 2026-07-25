//
//  NVDAHomeScreen.swift
//  Sunnyfi
//
//  Home tab — "NVDA Today" editorial feed (per nvda-app.jsx). Hairline
//  rows on paper, a big glance number each, a volatility verdict, a
//  5-session column chart and a news tape. Tap any row for its sheet.
//

import SwiftUI

struct NVDAHomeScreen: View {
    var store: PortfolioStore
    @State private var news: [NewsHeadline] = []
    @State private var newsLoaded = false
    @State private var sheetKey: String?

    private func tc(_ t: Tone) -> Color {
        switch t {
        case .pos: return Color.theme.pos
        case .neg: return Color.theme.neg
        case .neon: return Color.theme.neon
        case .warn: return Color.theme.warn
        case .fg1: return Color.theme.fg1
        case .fg3: return Color.theme.fg3
        }
    }

    var body: some View {
        let data = NVDAToday.build(store: store)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                brandRow.padding(.top, 8)
                if let d = data {
                    tickerStrip(d)
                    headline(d)
                    VStack(spacing: 0) {
                        volRow(d)
                        ForEach(Array(d.items.enumerated()), id: \.element.id) { idx, it in
                            row(it, lead: idx == 0)
                        }
                    }
                    .padding(.top, 6)
                    sessions(d).padding(.top, 26)
                    tape.padding(.top, 26)
                } else {
                    Text("No NVDA position yet.").font(.system(size: 14))
                        .foregroundStyle(Color.theme.fg3).padding(.top, 40)
                }
                Color.clear.frame(height: 110)
            }
            .padding(.horizontal, 22)
        }
        .background(Color.theme.page)
        .task {
            guard !newsLoaded else { return }
            newsLoaded = true
            news = await store.fetchNews(tickers: ["NVDA"])
        }
        .sheet(item: Binding(get: { sheetKey.map { Keyed(id: $0) } }, set: { sheetKey = $0?.id })) { keyed in
            if let d = data, let sh = d.sheets[keyed.id] {
                detailSheet(sh, d: d)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color.theme.elevated)
            }
        }
    }

    private struct Keyed: Identifiable { let id: String }

    // ── brand row ──
    private var brandRow: some View {
        HStack {
            HStack(spacing: 0) {
                Text("SUNNYFI").font(.system(size: 13, weight: .semibold)).tracking(2.3)
                    .foregroundStyle(Color.theme.neon)
                Rectangle().fill(Color.theme.neon).frame(width: 6, height: 12).padding(.leading, 3)
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(Color.theme.lime).frame(width: 6, height: 6)
                Text("NVDA · MARKETS OPEN").font(.numeric(size: 9.5, weight: .semibold)).tracking(0.5)
                    .foregroundStyle(Color.theme.fg3)
            }
        }
    }

    // ── ticker strip ──
    private func tickerStrip(_ d: NVDAToday) -> some View {
        Button { sheetKey = "day" } label: {
            HStack(spacing: 8) {
                Text(d.ticker).font(.numeric(size: 11, weight: .medium)).tracking(1.4).foregroundStyle(Color.theme.fg2)
                Text(fmtMoney(d.price, decimals: 2)).font(.numeric(size: 13, weight: .medium)).foregroundStyle(Color.theme.fg1)
                Text(fmtPct(d.chgPct)).font(.numeric(size: 11.5, weight: .medium)).foregroundStyle(Color.signed(d.chgPct))
                Text("·").foregroundStyle(Color.theme.fg4)
                Text("\(Int(d.shares).formatted(.number.grouping(.automatic))) SH · \(compactUSD(d.posValue))")
                    .font(.numeric(size: 9.5, weight: .medium)).tracking(0.5).foregroundStyle(Color.theme.fg4)
                Spacer(minLength: 0)
                Text(fmtMoney(d.todayPL, sign: true)).font(.numeric(size: 11, weight: .medium))
                    .foregroundStyle(Color.signed(d.todayPL))
            }
            .padding(.vertical, 13).padding(.top, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.theme.hair).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }

    // ── headline ──
    private func headline(_ d: NVDAToday) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrowDate()).font(.numeric(size: 10, weight: .semibold)).tracking(1.6)
                .foregroundStyle(Color.theme.fg3).textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(d.items.count)").font(.system(size: 34, weight: .heavy)).tracking(-1.4)
                    .foregroundStyle(Color.theme.fg1)
                Text("things to know today").font(.system(size: 30, weight: .light)).tracking(-0.6)
                    .foregroundStyle(Color.theme.fg1)
            }
            .padding(.top, 9)
            RoundedRectangle(cornerRadius: 2).fill(Color.theme.neon).frame(width: 38, height: 3).padding(.top, 15)
        }
        .padding(.top, 16)
    }

    // ── volatility row ──
    private func volRow(_ d: NVDAToday) -> some View {
        Button { sheetKey = "vol" } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("VOLATILITY · \(d.ticker)").font(.numeric(size: 9, weight: .semibold)).tracking(1.6)
                        .foregroundStyle(Color.theme.fg3)
                    Spacer()
                    ivTag(d.zone.verdict, key: d.zone.key)
                }
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(String(format: "%.1f%%", d.iv)).font(.numeric(size: 34, weight: .semibold)).tracking(-1.2)
                        .foregroundStyle(Color.theme.neon)
                    Text("implied vol").font(.numeric(size: 9.5, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(Color.theme.fg3).textCase(.uppercase)
                }
                miniGauge(marker: d.ivr)
                HStack {
                    Text("cheap").font(.numeric(size: 9, weight: .medium)).foregroundStyle(Color.theme.fg4)
                    Spacer()
                    Text("rich").font(.numeric(size: 9, weight: .medium)).foregroundStyle(Color.theme.fg4)
                }
            }
            .padding(.vertical, 18).padding(.trailing, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) { Image(systemName: "mappin").font(.system(size: 13)).foregroundStyle(Color.theme.fg4).padding(.top, 20) }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 1) }
    }

    // ── editorial row ──
    private func row(_ it: NVRow, lead: Bool) -> some View {
        Button { sheetKey = it.k } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(it.num).font(.numeric(size: lead ? 33 : 29, weight: .semibold)).tracking(-1)
                            .foregroundStyle(tc(it.tone))
                        Text(it.unit).font(.numeric(size: 9, weight: .medium)).tracking(0.8)
                            .foregroundStyle(Color.theme.fg3).textCase(.uppercase)
                    }
                    .frame(minWidth: 86, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 9) {
                            Text(String(format: "%02d", (it.k == "basis" ? 1 : it.k == "prem" ? 2 : it.k == "prot" ? 3 : it.k == "fed" ? 4 : 5)))
                                .font(.numeric(size: 11, weight: .medium)).foregroundStyle(Color.theme.neon)
                            Text(it.cat.uppercased()).font(.numeric(size: 9, weight: .semibold)).tracking(1.6)
                                .foregroundStyle(Color.theme.fg3)
                        }
                        Text(it.name).font(.system(size: lead ? 17 : 16.5, weight: .semibold)).tracking(-0.3)
                            .foregroundStyle(Color.theme.fg1).padding(.top, 8)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(it.sub).font(.numeric(size: 10.5, weight: .regular)).foregroundStyle(Color.theme.fg3)
                            .padding(.top, 6).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                rowViz(it.k)
            }
            .padding(.vertical, 19).padding(.trailing, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 1) }
    }

    // ── per-row signature visuals ──
    @ViewBuilder
    private func rowViz(_ k: String) -> some View {
        let d = NVDAToday.build(store: store)
        if let d {
            switch k {
            case "basis": basisViz(d)
            case "prem":  premViz(d)
            case "prot":  protViz(d)
            case "er":    erViz(d)
            case "fed":   fedViz()
            default: EmptyView()
            }
        }
    }

    private func basisViz(_ d: NVDAToday) -> some View {
        let lo = d.basisEff - 2, hi = d.price + 2
        func f(_ v: Double) -> CGFloat { hi > lo ? CGFloat((v - lo) / (hi - lo)) : 0.5 }
        return VStack(spacing: 9) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.theme.page2).frame(height: 6)
                    Capsule().fill(Color.theme.pos.opacity(0.4))
                        .frame(width: max(2, (f(d.price) - f(d.basisEff)) * w), height: 6).offset(x: f(d.basisEff) * w)
                    mark(Color.theme.fg4, x: f(d.basisEff) * w)
                    mark(Color.theme.neon, x: f(d.price) * w, tall: true)
                }
            }.frame(height: 14)
            scaleRow("break-even \(fmtMoney(d.basisEff, decimals: 2))", "\(fmtMoney(d.overBE, sign: true, decimals: 2))/sh", "now \(fmtMoney(d.price, decimals: 2))")
        }
    }

    private func premViz(_ d: NVDAToday) -> some View {
        let ws = Array(d.weeks.suffix(3))
        let maxV = max(ws.map { $0.1 }.max() ?? 1, 1)
        return VStack(spacing: 9) {
            ForEach(Array(ws.enumerated()), id: \.offset) { i, wk in
                let on = i == ws.count - 1
                VStack(spacing: 5) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.theme.page2).frame(height: 6)
                            Capsule().fill(on ? Color.theme.neon : Color.theme.pos.opacity(0.35))
                                .frame(width: max(2, CGFloat(wk.1 / maxV) * g.size.width), height: 6)
                        }
                    }.frame(height: 6)
                    HStack {
                        Text(wk.0).font(.numeric(size: 9, weight: on ? .semibold : .regular)).foregroundStyle(on ? Color.theme.fg2 : Color.theme.fg4)
                        Spacer()
                        Text(fmtMoney(wk.1, sign: true)).font(.numeric(size: 9, weight: on ? .semibold : .medium)).foregroundStyle(on ? Color.theme.fg1 : Color.theme.fg3)
                    }
                }
            }
        }
    }

    private func protViz(_ d: NVDAToday) -> some View {
        let cover = min(1, d.erMove > 0 ? d.protectPct / d.erMove : 0.3)
        return VStack(spacing: 9) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.theme.page2).frame(height: 6)
                    Capsule().fill(Color.theme.pos.opacity(0.5)).frame(width: max(2, cover * g.size.width), height: 6)
                    mark(Color.theme.neon, x: cover * g.size.width, tall: true)
                }
            }.frame(height: 14)
            scaleRow("\(String(format: "%.1f", d.protectPct))% covered", "break-even \(fmtMoney(d.basisEff, decimals: 2))", "±\(String(format: "%.0f", d.erMove))% move")
        }
    }

    private func erViz(_ d: NVDAToday) -> some View {
        func f(_ v: Double) -> CGFloat { d.erHigh > d.erLow ? CGFloat((v - d.erLow) / (d.erHigh - d.erLow)) : 0.5 }
        return VStack(spacing: 9) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.theme.earnings.opacity(0.16)).frame(height: 6)
                    mark(Color.theme.earnings, x: f(d.price) * w, tall: true)
                    if d.strike > 0 { mark(Color.theme.fg4, x: f(d.strike) * w, dashed: true) }
                }
            }.frame(height: 14)
            scaleRow("\(fmtMoney(d.erLow, decimals: 0)) −\(String(format: "%.0f", d.erMove))%", "now \(fmtMoney(d.price, decimals: 2))", "\(fmtMoney(d.erHigh, decimals: 0)) +\(String(format: "%.0f", d.erMove))%")
        }
    }

    private func fedViz() -> some View {
        let marks: [(Double, String)] = [(0.14, "Fed"), (0.62, "OPEX"), (0.88, "ER?")]
        return VStack(spacing: 9) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.theme.dusk).frame(height: 1).offset(y: 3)
                    Circle().fill(Color.theme.neon).frame(width: 7, height: 7)
                    ForEach(Array(marks.enumerated()), id: \.offset) { _, m in
                        VStack(spacing: 3) {
                            Circle().fill(Color.theme.fg2).frame(width: 5, height: 5)
                            Text(m.1).font(.numeric(size: 8, weight: .semibold)).tracking(0.6).foregroundStyle(Color.theme.fg3)
                        }.offset(x: m.0 * w - 6)
                    }
                }
            }.frame(height: 20)
            scaleRow("today", "", "late Aug")
        }
    }

    private func mark(_ c: Color, x: CGFloat, tall: Bool = false, dashed: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 1).fill(c)
            .frame(width: 3, height: tall ? 16 : 14)
            .offset(x: x - 1.5, y: tall ? -1 : 0)
            .opacity(dashed ? 0.6 : 1)
    }
    private func scaleRow(_ a: String, _ b: String, _ c: String) -> some View {
        HStack {
            Text(a).font(.numeric(size: 8.5, weight: .medium)).foregroundStyle(Color.theme.fg4)
            Spacer()
            if !b.isEmpty { Text(b).font(.numeric(size: 8.5, weight: .medium)).foregroundStyle(Color.theme.fg4); Spacer() }
            Text(c).font(.numeric(size: 8.5, weight: .medium)).foregroundStyle(Color.theme.fg4)
        }
    }

    // ── mini gauge (5 IV zones + marker) ──
    private func miniGauge(marker: Int) -> some View {
        let zones: [Double] = [0.09, 0.13, 0.18, 0.32, 0.34]  // opacity per zone
        return GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(Array(zones.enumerated()), id: \.offset) { i, op in
                        RoundedRectangle(cornerRadius: 2)
                            .fill((i >= 3 ? Color.theme.neon : Color.theme.fg1).opacity(op))
                            .frame(maxWidth: .infinity)
                    }
                }.frame(height: 7)
                RoundedRectangle(cornerRadius: 2).fill(Color.theme.fg1)
                    .frame(width: 3, height: 13)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.theme.page, lineWidth: 2))
                    .offset(x: CGFloat(min(100, max(0, marker))) / 100 * w - 1.5)
            }
        }.frame(height: 13)
    }

    private func ivTag(_ text: String, key: String) -> some View {
        let (bg, fg): (Color, Color) = {
            switch key {
            case "sell": return (Color.theme.neon, Color.theme.onNeon)
            case "caution": return (Color.theme.warn, .white)
            default: return (Color.theme.page2, Color.theme.fg3)
            }
        }()
        return Text(text.uppercased()).font(.numeric(size: 8, weight: .semibold)).tracking(1)
            .foregroundStyle(fg).padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(bg))
    }

    // ── last 5 sessions ──
    private func sessions(_ d: NVDAToday) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LAST 5 SESSIONS").font(.numeric(size: 9, weight: .semibold)).tracking(2)
                .foregroundStyle(Color.theme.fg3)
            HStack(alignment: .center, spacing: 6) {
                ForEach(d.days.reversed()) { s in
                    let h = max(3, CGFloat(abs(s.pct) / d.dayMax) * 40)
                    VStack(spacing: 0) {
                        VStack(spacing: 6) {
                            if s.pct > 0 {
                                Text("+\(String(format: "%.2f", s.pct))").font(.numeric(size: 10.5, weight: .medium)).foregroundStyle(Color.theme.pos)
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 3).fill(s.today ? Color.theme.neg : Color.theme.pos.opacity(0.5)).frame(width: 26, height: h)
                            } else { Spacer(minLength: 0) }
                        }.frame(height: 56, alignment: .bottom)
                        Rectangle().fill(Color.theme.dusk).frame(height: 1)
                        VStack(spacing: 6) {
                            if s.pct <= 0 {
                                RoundedRectangle(cornerRadius: 3).fill(s.today ? Color.theme.neg : Color.theme.neg.opacity(0.45)).frame(width: 26, height: h)
                                Text("−\(String(format: "%.2f", abs(s.pct)))").font(.numeric(size: 10.5, weight: .medium)).foregroundStyle(Color.theme.neg)
                                Spacer(minLength: 0)
                            } else { Spacer(minLength: 0) }
                        }.frame(height: 56, alignment: .top)
                        Text(s.label).font(.numeric(size: 8.5, weight: .semibold)).tracking(0.9)
                            .foregroundStyle(s.today ? Color.theme.fg2 : Color.theme.fg4).padding(.top, 8)
                        Text(fmtMoney(s.close, decimals: 2).replacingOccurrences(of: "$", with: ""))
                            .font(.numeric(size: 11, weight: s.today ? .semibold : .medium))
                            .foregroundStyle(s.today ? Color.theme.fg1 : Color.theme.fg2).padding(.top, 5)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 14)
            Text(sessionFoot(d)).font(.system(size: 11.5)).foregroundStyle(Color.theme.fg3)
                .padding(.top, 16).padding(.top, 2)
                .overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 1) }
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.theme.hair, lineWidth: 1))
    }

    private func sessionFoot(_ d: NVDAToday) -> String {
        let five = String(format: "%.1f", d.week5)
        let avg = String(format: "%.1f", d.avgAbs)
        let priced = String(format: "%.1f", d.pricedDay)
        return "\(five)% over 5 sessions · averaging \(avg)% a day, while options price \(priced)%."
    }

    // ── news tape ──
    private var tape: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NVDA TAPE").font(.numeric(size: 9, weight: .semibold)).tracking(2)
                .foregroundStyle(Color.theme.fg3).padding(.bottom, 12)
            if news.isEmpty {
                Text(newsLoaded ? "No fresh headlines." : "Loading headlines…")
                    .font(.system(size: 13)).foregroundStyle(Color.theme.fg3)
            } else {
                ForEach(Array(news.prefix(4).enumerated()), id: \.element.id) { i, n in
                    let content = VStack(alignment: .leading, spacing: 6) {
                        Text(n.headline).font(.system(size: 13, weight: .medium)).tracking(-0.1)
                            .foregroundStyle(Color.theme.fg1).fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Text("\((n.publisher ?? "").uppercased()) · \(relAge(n.ts))")
                            .font(.numeric(size: 9, weight: .medium)).tracking(0.5).foregroundStyle(Color.theme.fg4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, i == 0 ? 0 : 13)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Color.theme.hair).frame(height: 1) } }
                    if let u = n.url, let url = URL(string: u) {
                        Link(destination: url) { content }.buttonStyle(.plain)
                    } else { content }
                }
            }
        }
    }

    // ── detail sheet ──
    private func detailSheet(_ sh: NVSheet, d: NVDAToday) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(sh.cat.uppercased()).font(.numeric(size: 9, weight: .semibold)).tracking(1.8)
                    .foregroundStyle(Color.theme.neon)
                Text(sh.title).font(.system(size: 25, weight: .bold)).tracking(-0.6)
                    .foregroundStyle(Color.theme.fg1).padding(.top, 7)
                Text(sh.sub).font(.system(size: 10.5)).foregroundStyle(Color.theme.fg3).padding(.top, 8)

                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    Text(sh.hero).font(.numeric(size: 48, weight: .semibold)).tracking(-1.6).foregroundStyle(Color.theme.fg1)
                    Text(sh.heroUnit).font(.system(size: 10.5)).foregroundStyle(Color.theme.fg3)
                }
                .padding(.top, 17)

                if sh.isVol {
                    miniGauge(marker: d.ivr).padding(.top, 16)
                    HStack {
                        Text("IV rank \(d.ivr)").font(.numeric(size: 9, weight: .medium)).foregroundStyle(Color.theme.fg4)
                        Spacer()
                        Text("write zone ≥ 55").font(.numeric(size: 9, weight: .medium)).foregroundStyle(Color.theme.fg4)
                    }.padding(.top, 9)
                }

                Text(sh.line).font(.system(size: 12.5)).foregroundStyle(Color.theme.fg2)
                    .lineSpacing(3).padding(.top, 14).fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    ForEach(Array(sh.rows.enumerated()), id: \.offset) { i, r in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(r.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.theme.fg1)
                                Text(r.sub).font(.system(size: 10)).foregroundStyle(Color.theme.fg3)
                            }
                            Spacer()
                            Text(r.val).font(.numeric(size: 15, weight: .medium)).foregroundStyle(tc(r.tone))
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Color.theme.hair).frame(height: 1) } }
                    }
                }
                .padding(.top, 8)
            }
            .padding(22)
        }
    }

    // ── formatting helpers ──
    private func compactUSD(_ v: Double) -> String {
        if abs(v) >= 1_000_000 { return String(format: "$%.2fM", v / 1_000_000) }
        if abs(v) >= 1_000 { return String(format: "$%.0fK", v / 1_000) }
        return fmtMoney(v)
    }
    private func eyebrowDate() -> String {
        let f = DateFormatter(); f.dateFormat = "EEE MMM d"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return "Today · " + f.string(from: Date())
    }
    private func relAge(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "" }
        let s = Date().timeIntervalSince(d)
        if s < 3600 { return "\(max(1, Int(s / 60)))M AGO" }
        if s < 86_400 { return "\(Int(s / 3600))H AGO" }
        return "\(Int(s / 86_400))D AGO"
    }
}
