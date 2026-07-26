//
//  NVDAHomeScreen.swift
//  Sunnyfi
//
//  Home tab — "NVDA Today" (handoff 6). Card grammar in horizontal swipe
//  rails: a rich-black Volatility decision card + NVDA/SMH/QQQ 5-session
//  cards, then grouped numbered cards (Income / Position / Calendar), then
//  the tape. Themed via Color.theme (light paper / dark).
//

import SwiftUI

struct NVDAHomeScreen: View {
    var store: PortfolioStore
    @State private var news: [NewsHeadline] = []
    @State private var newsLoaded = false
    @State private var sheetKey: String?

    // Rich-black anchor card — always dark (it's the anchor), not fg1 which
    // flips in dark mode.
    private let inkBG = Color(hex: 0x18241c)
    private let inkText = Color(hex: 0xf2eee5)
    private let limeInk = Color(hex: 0x1c260a)
    private var lime: Color { Color.theme.lime }
    private let cardW: CGFloat = 290

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
                brandRow.padding(.horizontal, 22).padding(.top, 8)
                if let d = data {
                    tickerStrip(d).padding(.horizontal, 22)
                    headline(d).padding(.horizontal, 22)
                    decisionRail(d)
                    groupsSection(d)
                    tape.padding(.horizontal, 22).padding(.top, 8)
                } else {
                    Text("No NVDA position yet.").font(.system(size: 14))
                        .foregroundStyle(Color.theme.fg3).padding(40)
                }
                Color.clear.frame(height: 112)
            }
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

    // ── ticker strip (minimal) ──
    private func tickerStrip(_ d: NVDAToday) -> some View {
        Button { sheetKey = "day" } label: {
            HStack(spacing: 8) {
                Text(d.ticker).font(.numeric(size: 11, weight: .medium)).tracking(1.4).foregroundStyle(Color.theme.fg2)
                Text(fmtMoney(d.price, decimals: 2)).font(.numeric(size: 13, weight: .medium)).foregroundStyle(Color.theme.fg1)
                Text(fmtPct(d.chgPct)).font(.numeric(size: 11.5, weight: .medium)).foregroundStyle(Color.signed(d.chgPct))
                Spacer(minLength: 0)
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
                Text("\(d.items.count)").font(.system(size: 34, weight: .heavy)).tracking(-1.4).foregroundStyle(Color.theme.fg1)
                Text("things to know today").font(.system(size: 30, weight: .light)).tracking(-0.6).foregroundStyle(Color.theme.fg1)
            }
            .padding(.top, 9)
            RoundedRectangle(cornerRadius: 2).fill(Color.theme.neon).frame(width: 38, height: 3).padding(.top, 15)
        }
        .padding(.top, 16)
    }

    // ── "The decision" rail: vol card + session cards ──
    private func decisionRail(_ d: NVDAToday) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("THE DECISION").font(.numeric(size: 9, weight: .semibold)).tracking(2.2)
                .foregroundStyle(Color.theme.fg4).padding(.horizontal, 22).padding(.top, 22)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 11) {
                    volCard(d).frame(width: cardW)
                    ForEach(d.refSeries) { s in sessionCard(s).frame(width: cardW) }
                }
                .padding(.horizontal, 22).padding(.vertical, 10)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private func volCard(_ d: NVDAToday) -> some View {
        Button { sheetKey = "vol" } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("VOLATILITY · \(d.ticker)").font(.numeric(size: 9, weight: .semibold)).tracking(1.6)
                        .foregroundStyle(inkText.opacity(0.58))
                    Spacer()
                    ivTag(d.zone.verdict, key: d.zone.key, onInk: true)
                }
                Text(String(format: "%.1f%%", d.iv)).font(.numeric(size: 28, weight: .bold)).tracking(-0.9)
                    .foregroundStyle(lime).padding(.top, 16)
                Text("IMPLIED VOL").font(.numeric(size: 9, weight: .medium)).tracking(0.8)
                    .foregroundStyle(inkText.opacity(0.5)).padding(.top, 9)
                Text(d.zone.sub.prefix(1).uppercased() + d.zone.sub.dropFirst())
                    .font(.system(size: 17, weight: .bold)).tracking(-0.3).foregroundStyle(Color(hex: 0xf4f1e8)).padding(.top, 15)
                Text("rank \(d.ivr) · realized \(String(format: "%.0f", d.iv - (d.spread ?? 0)))%")
                    .font(.numeric(size: 12, weight: .regular)).foregroundStyle(inkText.opacity(0.6)).padding(.top, 8)
                HStack(spacing: 12) {
                    inkStat("\(d.ivWindowDays >= 220 ? "52w" : "\(d.ivWindowDays)d") IV range", String(format: "%.0f–%.0f%%", d.ivLow, d.ivHigh))
                    inkStat("Implied − realized", (d.spread ?? 0) >= 0 ? "+\(String(format: "%.1f", d.spread ?? 0))" : String(format: "%.1f", d.spread ?? 0), divider: true)
                }
                .padding(.top, 20)
                Spacer(minLength: 0)
                miniGauge(marker: d.ivr, onInk: true).padding(.top, 20)
                HStack {
                    Text("cheap").font(.numeric(size: 9, weight: .medium)).foregroundStyle(inkText.opacity(0.42))
                    Spacer()
                    Text("rich").font(.numeric(size: 9, weight: .medium)).foregroundStyle(inkText.opacity(0.42))
                }
                .padding(.top, 8)
            }
            .padding(17)
            .frame(maxHeight: .infinity, alignment: .top)
            .frame(height: 330)
            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(inkBG))
            .contentShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
    }

    private func inkStat(_ label: String, _ value: String, divider: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.numeric(size: 8, weight: .semibold)).tracking(1.2)
                .foregroundStyle(inkText.opacity(0.45))
            Text(value).font(.numeric(size: 14, weight: .bold)).tracking(-0.2).foregroundStyle(Color(hex: 0xf4f1e8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, divider ? 12 : 0)
        .overlay(alignment: .leading) { if divider { Rectangle().fill(inkText.opacity(0.12)).frame(width: 1) } }
    }

    private func sessionCard(_ s: RefSeries) -> some View {
        let down = s.net < 0
        let ratio = s.priced > 0 ? s.avg / s.priced : 1
        let verdict = ratio > 1.10 ? "Moving more than priced" : ratio < 0.90 ? "Quieter than priced" : "Moving as priced"
        return Button { if s.tk == "NVDA" { sheetKey = "day" } } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(s.tk) · 5 SESSIONS").font(.numeric(size: 9, weight: .semibold)).tracking(1.6)
                        .foregroundStyle(Color.theme.fg3)
                    Spacer()
                    Text(fmtMoney(s.last, decimals: 2)).font(.numeric(size: 10, weight: .semibold))
                        .foregroundStyle(Color.theme.fg2).padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Color.theme.tintMuted))
                }
                Text("\(down ? "−" : "+")\(String(format: "%.1f", abs(s.net)))%")
                    .font(.numeric(size: 28, weight: .bold)).tracking(-0.9)
                    .foregroundStyle(down ? Color.theme.neg : Color.theme.pos).padding(.top, 16)
                Text(s.sub.uppercased()).font(.numeric(size: 9, weight: .medium)).tracking(0.8)
                    .foregroundStyle(Color.theme.fg4).padding(.top, 9)
                Text(verdict).font(.system(size: 17, weight: .bold)).tracking(-0.3)
                    .foregroundStyle(Color.theme.fg1).padding(.top, 15)
                Text("avg \(String(format: "%.1f", s.avg))%/day · priced \(String(format: "%.1f", s.priced))%")
                    .font(.numeric(size: 12, weight: .regular)).foregroundStyle(Color.theme.fg3).padding(.top, 8)
                Spacer(minLength: 0)
                sparkline(s).frame(height: 82).padding(.top, 20)
                HStack(spacing: 0) {
                    ForEach(s.days) { day in
                        VStack(spacing: 5) {
                            Text(day.label.uppercased()).font(.numeric(size: 8, weight: .semibold)).tracking(0.8)
                                .foregroundStyle(day.today ? Color.theme.fg2 : Color.theme.fg4)
                            Text("\(day.pct > 0 ? "+" : "−")\(String(format: "%.2f", abs(day.pct)))%")
                                .font(.numeric(size: 10, weight: .semibold)).foregroundStyle(day.pct > 0 ? Color.theme.pos : Color.theme.neg)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 6)
            }
            .padding(17)
            .frame(height: 330, alignment: .top)
            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Color.theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Color.theme.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func sparkline(_ s: RefSeries) -> some View {
        let vals = s.days.map(\.close)
        let lo = (vals.min() ?? 0), hi = (vals.max() ?? 1)
        let pad = (hi - lo) * 0.18 + 0.0001
        let mn = lo - pad, mx = hi + pad
        let down = s.net < 0
        return GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let x: (Int) -> CGFloat = { i in CGFloat(i) * w / 4 }
            let y: (Double) -> CGFloat = { v in CGFloat(1 - (v - mn) / (mx - mn)) * (h - 14) + 8 }
            ZStack {
                // dashed 5-day-start baseline
                Path { p in p.move(to: .init(x: 0, y: y(s.days.first?.close ?? 0))); p.addLine(to: .init(x: w, y: y(s.days.first?.close ?? 0))) }
                    .stroke(Color.theme.fg4, style: .init(lineWidth: 1, dash: [3, 3]))
                Path { p in
                    for (i, day) in s.days.enumerated() {
                        let pt = CGPoint(x: x(i), y: y(day.close))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(Color.theme.fg1, style: .init(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                ForEach(Array(s.days.enumerated()), id: \.offset) { i, day in
                    Circle().fill(day.today ? (day.pct < 0 ? Color.theme.neg : Color.theme.pos) : Color.theme.fg2)
                        .frame(width: day.today ? 9 : 5.2, height: day.today ? 9 : 5.2)
                        .overlay { if day.today { Circle().strokeBorder(Color.theme.elevated, lineWidth: 2) } }
                        .position(x: x(i), y: y(day.close))
                }
            }
        }
    }

    // ── grouped numbered cards ──
    private func groupsSection(_ d: NVDAToday) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(grouped(d.items), id: \.0) { grp in
                VStack(alignment: .leading, spacing: 0) {
                    Text(grp.0.uppercased()).font(.numeric(size: 9, weight: .semibold)).tracking(2.2)
                        .foregroundStyle(Color.theme.fg4).padding(.horizontal, 22).padding(.top, 20)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 11) {
                            ForEach(grp.1, id: \.1.id) { pair in groupCard(pair.1, idx: pair.0) }
                        }
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                }
            }
        }
    }

    private func groupCard(_ it: NVRow, idx: Int) -> some View {
        Button { sheetKey = it.k } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Text(String(format: "%02d", idx + 1)).font(.numeric(size: 11.5, weight: .bold)).foregroundStyle(Color.theme.neon)
                    Text(it.cat.uppercased()).font(.numeric(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(Color.theme.fg3)
                    Spacer(minLength: 0)
                }
                Text(it.num).font(.numeric(size: 28, weight: .bold)).tracking(-0.9).foregroundStyle(tc(it.tone)).padding(.top, 16)
                Text(it.unit.uppercased()).font(.numeric(size: 9, weight: .medium)).tracking(0.8).foregroundStyle(Color.theme.fg4).padding(.top, 9)
                Text(it.name).font(.system(size: 17, weight: .bold)).tracking(-0.3).foregroundStyle(Color.theme.fg1)
                    .padding(.top, 15).fixedSize(horizontal: false, vertical: true)
                Text(it.sub).font(.numeric(size: 12, weight: .regular)).foregroundStyle(Color.theme.fg3).padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                rowViz(it.k).padding(.top, 20)
            }
            .padding(17)
            .frame(width: cardW, height: 266, alignment: .top)
            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Color.theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Color.theme.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // ── signature visuals ──
    @ViewBuilder
    private func rowViz(_ k: String) -> some View {
        if let d = NVDAToday.build(store: store) {
            switch k {
            case "prem":  premViz(d)
            case "prot":  protViz(d)
            case "basis": basisViz(d)
            case "fed":   fedViz()
            case "er":    erViz(d)
            default: EmptyView()
            }
        }
    }

    private func premViz(_ d: NVDAToday) -> some View {
        let ws = Array(d.weeks.suffix(3))
        let maxV = max(ws.map { $0.1 }.max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(ws.enumerated()), id: \.offset) { i, wk in
                let on = i == ws.count - 1
                VStack(spacing: 6) {
                    Text(wk.1 >= 1000 ? "$\(String(format: "%.1f", wk.1 / 1000))K" : "$\(Int(wk.1))")
                        .font(.numeric(size: 9.5, weight: .semibold)).foregroundStyle(on ? Color.theme.fg1 : Color.theme.fg4)
                    RoundedRectangle(cornerRadius: 4).fill(on ? Color.theme.neon : Color.theme.neon.opacity(0.22))
                        .frame(height: max(6, CGFloat(wk.1 / maxV) * 58))
                    Text(wk.0).font(.numeric(size: 8, weight: .semibold)).tracking(0.7)
                        .foregroundStyle(on ? Color.theme.fg2 : Color.theme.fg4).textCase(.uppercase)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 96, alignment: .bottom)
    }

    private func trackViz(fillFrac: CGFloat, markFrac: CGFloat, dimMarkFrac: CGFloat?, scale: (String, String, String)) -> some View {
        VStack(spacing: 11) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.theme.page2).frame(height: 11)
                    Capsule().fill(Color.theme.tintNeon).frame(width: max(2, fillFrac * w), height: 11)
                    if let dm = dimMarkFrac { mark(Color.theme.fg4, x: dm * w) }
                    mark(Color.theme.neon, x: markFrac * w, tall: true)
                }
            }.frame(height: 21)
            scaleRow(scale.0, scale.1, scale.2)
        }
    }

    private func basisViz(_ d: NVDAToday) -> some View {
        let lo = d.basisEff - 2, hi = d.price + 2
        func f(_ v: Double) -> CGFloat { hi > lo ? CGFloat((v - lo) / (hi - lo)) : 0.5 }
        return trackViz(fillFrac: f(d.price) - f(d.basisEff) + 0.0, markFrac: f(d.price), dimMarkFrac: f(d.basisEff),
                        scale: ("BE \(fmtMoney(d.basisEff, decimals: 2))", "\(fmtMoney(d.overBE, sign: true, decimals: 2))/sh", "now \(fmtMoney(d.price, decimals: 2))"))
            .overlay(alignment: .leading) { EmptyView() }
    }

    private func protViz(_ d: NVDAToday) -> some View {
        let cover = min(1, d.erMove > 0 ? d.protectPct / d.erMove : 0.3)
        return VStack(spacing: 11) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.theme.page2).frame(height: 11)
                    Capsule().fill(Color.theme.tintNeon).frame(width: max(2, cover * w), height: 11)
                    mark(Color.theme.neon, x: cover * w, tall: true)
                }
            }.frame(height: 21)
            scaleRow("\(String(format: "%.1f", d.protectPct))% covered", "BE \(fmtMoney(d.basisEff, decimals: 2))", "±\(String(format: "%.0f", d.erMove))% move")
        }
    }

    private func erViz(_ d: NVDAToday) -> some View {
        func f(_ v: Double) -> CGFloat { d.erHigh > d.erLow ? CGFloat((v - d.erLow) / (d.erHigh - d.erLow)) : 0.5 }
        return VStack(spacing: 11) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color.theme.earnings.opacity(0.16)).frame(height: 15)
                    mark(Color.theme.earnings, x: f(d.price) * w, tall: true)
                    if d.strike > 0 { mark(Color.theme.fg4, x: f(d.strike) * w, dashed: true) }
                }
            }.frame(height: 21)
            scaleRow("\(fmtMoney(d.erLow, decimals: 0)) −\(String(format: "%.0f", d.erMove))%", "now \(fmtMoney(d.price, decimals: 2))", "\(fmtMoney(d.erHigh, decimals: 0)) +\(String(format: "%.0f", d.erMove))%")
        }
    }

    private func fedViz() -> some View {
        let marks: [(Double, String)] = [(0.14, "Fed"), (0.62, "OPEX"), (0.88, "ER?")]
        return VStack(spacing: 11) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.theme.dusk).frame(height: 1).offset(y: 4)
                    Circle().fill(Color.theme.neon).frame(width: 9, height: 9)
                    ForEach(Array(marks.enumerated()), id: \.offset) { _, m in
                        VStack(spacing: 4) {
                            Circle().fill(Color.theme.fg2).frame(width: 7, height: 7)
                            Text(m.1).font(.numeric(size: 8.5, weight: .semibold)).tracking(0.6).foregroundStyle(Color.theme.fg3)
                        }.offset(x: m.0 * w - 8)
                    }
                }
            }.frame(height: 38)
            scaleRow("today", "", "late Aug")
        }
    }

    private func mark(_ c: Color, x: CGFloat, tall: Bool = false, dashed: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 3, height: tall ? 23 : 21)
            .offset(x: x - 1.5, y: tall ? -1 : 0).opacity(dashed ? 0.6 : 1)
    }
    private func scaleRow(_ a: String, _ b: String, _ c: String) -> some View {
        HStack {
            Text(a).font(.numeric(size: 8.5, weight: .medium)).foregroundStyle(Color.theme.fg4)
            Spacer()
            if !b.isEmpty { Text(b).font(.numeric(size: 8.5, weight: .medium)).foregroundStyle(Color.theme.fg4); Spacer() }
            Text(c).font(.numeric(size: 8.5, weight: .medium)).foregroundStyle(Color.theme.fg4)
        }
    }

    // ── mini gauge ──
    private func miniGauge(marker: Int, onInk: Bool = false) -> some View {
        let base = onInk ? Color.white : Color.theme.fg1
        let ops: [Double] = onInk ? [0.10, 0.14, 0.18, 0.42, 0.42] : [0.09, 0.13, 0.18, 0.34, 0.34]
        return GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill((i == 3 ? (onInk ? Color.theme.lime : Color.theme.neon) : i == 4 ? Color.theme.ivAmber : base).opacity(ops[i]))
                            .frame(maxWidth: .infinity)
                    }
                }.frame(height: onInk ? 10 : 8)
                RoundedRectangle(cornerRadius: 2).fill(onInk ? Color(hex: 0xf2eee5) : Color.theme.fg1)
                    .frame(width: 3, height: onInk ? 18 : 16)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(onInk ? Color(hex: 0x18241c) : Color.theme.page, lineWidth: 2))
                    .offset(x: CGFloat(min(100, max(0, marker))) / 100 * w - 1.5)
            }
        }.frame(height: onInk ? 18 : 16)
    }

    private func ivTag(_ text: String, key: String, onInk: Bool = false) -> some View {
        let (bg, fg): (Color, Color) = {
            switch key {
            case "sell": return onInk ? (Color.theme.lime, limeInk) : (Color.theme.neon, Color.theme.onNeon)
            case "caution": return (Color.theme.ivAmber, limeInk)
            default: return onInk ? (Color.white.opacity(0.13), Color(hex: 0xe9ede0)) : (Color.theme.tintMuted, Color.theme.fg3)
            }
        }()
        return Text(text.uppercased()).font(.numeric(size: 8, weight: .semibold)).tracking(1)
            .foregroundStyle(fg).padding(.horizontal, 9).padding(.vertical, 5).background(Capsule().fill(bg))
    }

    // ── news tape ──
    private var tape: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NVDA TAPE").font(.numeric(size: 9, weight: .semibold)).tracking(2)
                .foregroundStyle(Color.theme.fg3).padding(.bottom, 12)
            if news.isEmpty {
                Text(newsLoaded ? "No fresh headlines." : "Loading headlines…").font(.system(size: 13)).foregroundStyle(Color.theme.fg3)
            } else {
                ForEach(Array(news.prefix(4).enumerated()), id: \.element.id) { i, n in
                    let content = VStack(alignment: .leading, spacing: 6) {
                        Text(n.headline).font(.system(size: 13, weight: .medium)).tracking(-0.1)
                            .foregroundStyle(Color.theme.fg1).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                        Text("\((n.publisher ?? "").uppercased()) · \(relAge(n.ts))")
                            .font(.numeric(size: 9, weight: .medium)).tracking(0.5).foregroundStyle(Color.theme.fg4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, i == 0 ? 0 : 13)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Color.theme.hair).frame(height: 1) } }
                    if let u = n.url, let url = URL(string: u) { Link(destination: url) { content }.buttonStyle(.plain) } else { content }
                }
            }
        }
    }

    // ── detail sheet ──
    private func detailSheet(_ sh: NVSheet, d: NVDAToday) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(sh.cat.uppercased()).font(.numeric(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(Color.theme.neon)
                Text(sh.title).font(.system(size: 25, weight: .bold)).tracking(-0.6).foregroundStyle(Color.theme.fg1).padding(.top, 7)
                Text(sh.sub).font(.system(size: 10.5)).foregroundStyle(Color.theme.fg3).padding(.top, 8)
                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    Text(sh.hero).font(.numeric(size: 48, weight: .bold)).tracking(-1.6).foregroundStyle(Color.theme.fg1)
                    Text(sh.heroUnit).font(.system(size: 10.5)).foregroundStyle(Color.theme.fg3)
                }.padding(.top, 17)
                if sh.isVol {
                    miniGauge(marker: d.ivr).padding(.top, 16)
                    HStack {
                        Text("IV rank \(d.ivr)").font(.numeric(size: 9, weight: .medium)).foregroundStyle(Color.theme.fg4)
                        Spacer()
                        Text("write zone ≥ 55").font(.numeric(size: 9, weight: .medium)).foregroundStyle(Color.theme.fg4)
                    }.padding(.top, 9)
                }
                Text(sh.line).font(.system(size: 12.5)).foregroundStyle(Color.theme.fg2).lineSpacing(3)
                    .padding(.top, 14).fixedSize(horizontal: false, vertical: true)
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
                }.padding(.top, 8)
            }.padding(22)
        }
    }

    // ── helpers ──
    private func grouped(_ items: [NVRow]) -> [(String, [(Int, NVRow)])] {
        var groups: [(String, [(Int, NVRow)])] = []
        for (i, it) in items.enumerated() {
            if let g = it.grp { groups.append((g, [(i, it)])) }
            else if !groups.isEmpty { groups[groups.count - 1].1.append((i, it)) }
        }
        return groups
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
