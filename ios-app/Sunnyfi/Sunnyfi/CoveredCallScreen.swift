//
//  CoveredCallScreen.swift
//  Sunnyfi
//
//  NVDA Position (Covered Call tab) — handoff 6. Rich-black premium-
//  harvested hero, the position swipe rail, premium-by-week, what it
//  earned, history, and the Call Planner sheet. Data from PosData.
//

import SwiftUI

struct CoveredCallScreen: View {
    let store: PortfolioStore
    @State private var sheetKey: String?
    @State private var showPlanner = false
    @State private var railPos: [String: String] = [:]

    private func posBinding(_ key: String) -> Binding<String?> {
        Binding(get: { railPos[key] }, set: { if let v = $0 { railPos[key] = v } })
    }

    @ViewBuilder private func dots(_ ids: [String], _ active: String?) -> some View {
        if ids.count > 1 {
            let idx = ids.firstIndex(of: active ?? ids.first ?? "") ?? 0
            HStack(spacing: 5) {
                ForEach(ids.indices, id: \.self) { i in
                    Circle().fill(i == idx ? Color.theme.neon : Color.theme.dusk)
                        .frame(width: 5, height: 5).animation(Motion.standard, value: idx)
                }
            }
        }
    }

    private let inkBG = Color(hex: 0x18241c)
    private let inkText = Color(hex: 0xf2eee5)
    private let limeInk = Color(hex: 0x1c260a)
    private var lime: Color { Color.theme.lime }
    private let cardW: CGFloat = 292

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
        let d = PosData.build(store: store)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let d {
                    header(d)
                    tickerRow(d).padding(.horizontal, 22)
                    lifetimeCard(d).padding(.horizontal, 22).padding(.top, 12)
                    positionRail(d)
                    weeksPanel(d).padding(.horizontal, 22).padding(.top, 12)
                    earnedPanel(d).padding(.horizontal, 22).padding(.top, 12)
                    historyPanel(d).padding(.horizontal, 22).padding(.top, 12)
                } else {
                    Text("No NVDA position yet.").font(.system(size: 14)).foregroundStyle(Color.theme.fg3).padding(40)
                }
                Color.clear.frame(height: 112)
            }
        }
        .background(Color.theme.page)
        .sheet(item: Binding(get: { sheetKey.map { Keyed(id: $0) } }, set: { sheetKey = $0?.id })) { keyed in
            if let d, let sh = d.sheets[keyed.id] {
                detailSheet(sh).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                    .presentationBackground(Color.theme.elevated)
            }
        }
        .sheet(isPresented: $showPlanner) {
            if let data = CoveredCallData.build(store: store, ticker: "NVDA") {
                CoveredCallPlanner(model: PlannerModel(store: store, data: data), onClose: { showPlanner = false })
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
            }
        }
    }

    private struct Keyed: Identifiable { let id: String }

    // ── header ──
    private func header(_ d: PosData) -> some View {
        HStack(spacing: 7) {
            Text(d.ticker).font(.mono(size: 12, weight: .semibold)).tracking(1.6).foregroundStyle(Color.theme.fg1)
            Circle().fill(Color.theme.lime).frame(width: 6, height: 6)
            Spacer()
            Text("COVERED CALL · \(d.contractsWritten) OF \(d.contractsTotal) WRITTEN")
                .font(.mono(size: 9.5, weight: .semibold)).tracking(0.5).foregroundStyle(Color.theme.fg4)
        }
        .padding(.horizontal, 22).padding(.top, 8)
    }

    // ── ticker row + planner button ──
    private func tickerRow(_ d: PosData) -> some View {
        HStack(spacing: 10) {
            Button { sheetKey = "shares" } label: {
                HStack(spacing: 8) {
                    Text(d.ticker).font(.mono(size: 11, weight: .medium)).tracking(1.4).foregroundStyle(Color.theme.fg2)
                    Text(fmtMoney(d.price, decimals: 2)).font(.mono(size: 13, weight: .medium)).foregroundStyle(Color.theme.fg1)
                    Text(fmtPct(d.chgPct)).font(.mono(size: 11.5, weight: .medium)).foregroundStyle(Color.signed(d.chgPct))
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { showPlanner = true } label: {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(Circle().fill(Color.theme.neon))
            }
            .buttonStyle(.plain)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.theme.hair).frame(height: 1) }
        .padding(.top, 6)
    }

    // ── rich-black premium harvested hero ──
    private func lifetimeCard(_ d: PosData) -> some View {
        var run = 0.0
        let cum: [(String, Double, Double)] = d.weeks.map { run += $0.v; return ($0.w, $0.v, run) }
        let maxC = max(d.premLife, 1)
        return Button { sheetKey = "prem" } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("PREMIUM HARVESTED").font(.mono(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(inkText.opacity(0.58))
                    Spacer()
                    Text("\(String(format: "%.1f", d.protectPct))% CUSHION").font(.mono(size: 8, weight: .semibold)).tracking(1)
                        .foregroundStyle(limeInk).padding(.horizontal, 9).padding(.vertical, 5).background(Capsule().fill(lime))
                }
                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    Text(fmtMoney(d.premLife, sign: true)).font(.mono(size: 42, weight: .bold)).tracking(-1.6).foregroundStyle(lime)
                    Text("LIFETIME").font(.mono(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(inkText.opacity(0.5))
                }
                .padding(.top, 18)
                Text("Write weeks on \(Int(d.shares).formatted(.number.grouping(.automatic))) shares. Week of \(d.bigWeekLabel) carried \(d.bigWeekPct)% of it.")
                    .font(.system(size: 12)).foregroundStyle(inkText.opacity(0.6)).padding(.top, 12).fixedSize(horizontal: false, vertical: true)
                // cumulative harvest columns
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(cum.enumerated()), id: \.offset) { i, c in
                        let on = i == cum.count - 1
                        VStack(spacing: 7) {
                            Text(c.2 > 0 ? (c.2 >= 1000 ? "$\(String(format: "%.1f", c.2 / 1000))K" : "$\(Int(c.2))") : "—")
                                .font(.mono(size: 9.5, weight: .semibold)).foregroundStyle(on ? lime : inkText.opacity(0.5))
                            RoundedRectangle(cornerRadius: 4).fill(on ? lime : lime.opacity(0.28))
                                .frame(height: max(4, CGFloat(c.2 / maxC) * 58))
                                .overlay { if c.1 <= 0 { RoundedRectangle(cornerRadius: 4).stroke(inkText.opacity(0.12), style: .init(lineWidth: 1, dash: [3, 3])) } }
                            Text(c.0).font(.mono(size: 8, weight: .semibold)).tracking(0.6).foregroundStyle(inkText.opacity(on ? 0.7 : 0.42)).textCase(.uppercase)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 98, alignment: .bottom).padding(.top, 22)
                HStack(spacing: 14) {
                    inkStat("Per share", "−" + fmtMoney(d.premPerShare, decimals: 2))
                    inkStat("On position value", String(format: "%.2f%%", d.premYield), divider: true)
                }
                .padding(.top, 20).padding(.top, 16)
                .overlay(alignment: .top) { Rectangle().fill(inkText.opacity(0.12)).frame(height: 1).padding(.top, 20) }
                // basis strip
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("COST BASIS").font(.mono(size: 8, weight: .semibold)).tracking(1.2).foregroundStyle(inkText.opacity(0.45))
                        Text(String(format: "%.2f", d.basisOrig)).font(.mono(size: 19, weight: .bold)).tracking(-0.5).foregroundStyle(Color(hex: 0xf4f1e8))
                    }
                    VStack(spacing: 7) {
                        Text("−\(String(format: "%.2f", d.premPerShare))").font(.mono(size: 10, weight: .bold)).foregroundStyle(limeInk)
                            .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(lime))
                        Rectangle().fill(LinearGradient(colors: [inkText.opacity(0.16), lime], startPoint: .leading, endPoint: .trailing)).frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .trailing, spacing: 7) {
                        Text("BREAK-EVEN").font(.mono(size: 8, weight: .semibold)).tracking(1.2).foregroundStyle(inkText.opacity(0.45))
                        Text(String(format: "%.2f", d.basisEff)).font(.mono(size: 19, weight: .bold)).tracking(-0.5).foregroundStyle(lime)
                    }
                }
                .padding(14).padding(.top, 20)
                .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Color.white.opacity(0.06)).overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(inkText.opacity(0.1), lineWidth: 1)))
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: Radius.xl).fill(inkBG))
            .contentShape(RoundedRectangle(cornerRadius: Radius.xl))
        }
        .buttonStyle(.plain)
    }

    private func inkStat(_ label: String, _ value: String, divider: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased()).font(.mono(size: 8, weight: .semibold)).tracking(1.2).foregroundStyle(inkText.opacity(0.45))
            Text(value).font(.mono(size: 16, weight: .bold)).tracking(-0.3).foregroundStyle(Color(hex: 0xf4f1e8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, divider ? 14 : 0)
        .overlay(alignment: .leading) { if divider { Rectangle().fill(inkText.opacity(0.12)).frame(width: 1) } }
    }

    // ── the position rail ──
    private func positionRail(_ d: PosData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("THE POSITION").font(.mono(size: 9, weight: .semibold)).tracking(2.2).foregroundStyle(Color.theme.fg4)
                Spacer()
                dots(d.cards.map(\.k), railPos["position"])
            }
            .padding(.horizontal, 22).padding(.top, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 11) {
                    ForEach(d.cards) { posCard($0, d: d).id($0.k) }
                }
                .padding(.horizontal, 22).padding(.vertical, 10).scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: posBinding("position"))
        }
    }

    private func posCard(_ it: PosCardModel, d: PosData) -> some View {
        Button { sheetKey = it.k } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(it.cat.uppercased()).font(.mono(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(Color.theme.fg3)
                    Spacer()
                    if it.k == "calls", d.strike > 0 { chip("OTM +\(String(format: "%.1f", d.strikeDist))%", .pos) }
                    else if it.k == "shares" { chip(fmtMoney(d.price, decimals: 2), .fg1) }
                    else if it.k == "uncov" { chip("\(d.dte)d cycle", .fg1) }
                }
                // Handoff: .kc-num is always --fg1 on non-ink cards.
                Text(it.num).font(.mono(size: 28, weight: .bold)).tracking(-0.9).foregroundStyle(Color.theme.fg1).padding(.top, 16)
                Text(it.unit.uppercased()).font(.mono(size: 9, weight: .medium)).tracking(0.8).foregroundStyle(Color.theme.fg4).padding(.top, 9)
                Text(it.name).font(.system(size: 17, weight: .bold)).tracking(-0.3).foregroundStyle(Color.theme.fg1).padding(.top, 15)
                    .fixedSize(horizontal: false, vertical: true)
                Text(it.sub).font(.mono(size: 12, weight: .regular)).foregroundStyle(Color.theme.fg3).padding(.top, 8)
                Spacer(minLength: 0)
                posViz(it.viz, d: d).padding(.top, 20)
            }
            .padding(17).frame(width: cardW, height: 266, alignment: .top)
            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Color.theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Color.theme.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func chip(_ t: String, _ tone: Tone) -> some View {
        Text(t).font(.system(size: 10, weight: .semibold)).foregroundStyle(tone == .pos ? Color.theme.pos : Color.theme.fg2)
            .padding(.horizontal, 9).padding(.vertical, 4).background(Capsule().fill(tone == .pos ? Color.theme.tintPos : Color.theme.tintMuted))
    }

    @ViewBuilder
    private func posViz(_ kind: String, d: PosData) -> some View {
        switch kind {
        case "basis":
            let lo = d.basisEff - 3, hi = d.basisOrig + 1
            trackViz(loBE: (d.basisEff - lo) / (hi - lo), hiPx: (d.price - lo) / (hi - lo),
                     dim: (d.basisEff - lo) / (hi - lo),
                     scale: ("BE \(fmtMoney(d.basisEff, decimals: 2))", "\(fmtMoney(d.overBE, sign: true, decimals: 2))/sh", "now \(fmtMoney(d.price, decimals: 2))"))
        case "cover":
            let lo = d.price * 0.97, hi = max(d.strike, d.price) * 1.02
            trackViz(loBE: (d.price - lo) / (hi - lo), hiPx: (d.strike - lo) / (hi - lo),
                     dim: (d.strike - lo) / (hi - lo),
                     scale: ("now \(fmtMoney(d.price, decimals: 2))", "+\(String(format: "%.1f", d.strikeDist))%", "strike \(fmtStrike(d.strike))"), markPrice: (d.price - lo) / (hi - lo))
        default:
            VStack(spacing: 11) {
                HStack(spacing: 3) {
                    ForEach(0..<10, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(Double(i) < Double(d.coveredPct) / 10 ? Color.theme.tintNeon : Color.theme.tintPos.opacity(0.35))
                            .frame(height: 11)
                    }
                }
                scaleRow("\(d.coveredPct)% covered", "", "\((d.uncovered * 100).formatted(.number.grouping(.automatic))) sh free")
            }
        }
    }

    private func trackViz(loBE: Double, hiPx: Double, dim: Double, scale: (String, String, String), markPrice: Double? = nil) -> some View {
        VStack(spacing: 11) {
            GeometryReader { g in
                let w = g.size.width
                let a = min(loBE, hiPx), b = max(loBE, hiPx)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.theme.page2).frame(height: 11)
                    Capsule().fill(Color.theme.tintNeon).frame(width: max(2, CGFloat(b - a) * w), height: 11).offset(x: CGFloat(a) * w)
                    mark(Color.theme.fg4, x: CGFloat(dim) * w)
                    mark(Color.theme.neon, x: CGFloat(markPrice ?? hiPx) * w, tall: true)
                }
            }.frame(height: 21)
            scaleRow(scale.0, scale.1, scale.2)
        }
    }

    private func mark(_ c: Color, x: CGFloat, tall: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 3, height: tall ? 23 : 21).offset(x: x - 1.5, y: tall ? -1 : 0)
    }
    private func scaleRow(_ a: String, _ b: String, _ c: String) -> some View {
        HStack {
            Text(a).font(.mono(size: 8.5, weight: .medium)).foregroundStyle(Color.theme.fg4)
            Spacer()
            if !b.isEmpty { Text(b).font(.mono(size: 8.5, weight: .medium)).foregroundStyle(Color.theme.fg4); Spacer() }
            Text(c).font(.mono(size: 8.5, weight: .medium)).foregroundStyle(Color.theme.fg4)
        }
    }

    // ── where premium lands ──
    private func weeksPanel(_ d: PosData) -> some View {
        let maxV = max(d.weeks.map(\.v).max() ?? 1, 1)
        return panel {
            HStack(alignment: .firstTextBaseline) {
                Text("Where premium lands").font(.system(size: 16, weight: .bold)).tracking(-0.3).foregroundStyle(Color.theme.fg1)
                Spacer()
                Text(fmtMoney(d.premLife, sign: true)).font(.mono(size: 15, weight: .bold)).foregroundStyle(Color.theme.pos)
            }
            Text("Premium collected per write week, newest at the right.").font(.system(size: 11.5)).foregroundStyle(Color.theme.fg3).padding(.top, 7)
            HStack(alignment: .bottom, spacing: 9) {
                ForEach(d.weeks) { wk in
                    let on = wk.w == (d.weeks.last?.w ?? "")
                    VStack(spacing: 8) {
                        Text(wk.v > 0 ? "$\(String(format: "%.1f", wk.v / 1000))K" : "—").font(.mono(size: 9.5, weight: .semibold)).foregroundStyle(on ? Color.theme.fg1 : Color.theme.fg4)
                        RoundedRectangle(cornerRadius: 5).fill(on ? Color.theme.neon : Color.theme.page2)
                            .frame(height: max(5, CGFloat(wk.v / maxV) * 104))
                            .overlay { if wk.v <= 0 { RoundedRectangle(cornerRadius: 5).stroke(Color.theme.dusk, style: .init(lineWidth: 1, dash: [3, 3])) } }
                        Text(wk.w).font(.mono(size: 8.5, weight: .semibold)).tracking(0.6).foregroundStyle(on ? Color.theme.fg1 : Color.theme.fg4).textCase(.uppercase)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 150, alignment: .bottom).padding(.top, 20)
            Text("Week of \(d.bigWeekLabel) carried \(fmtMoney(d.bigWeekVal)) of \(fmtMoney(d.premLife)) — \(d.bigWeekPct)% of everything collected.")
                .font(.system(size: 11.5)).foregroundStyle(Color.theme.fg2).lineSpacing(2)
                .padding(13).background(RoundedRectangle(cornerRadius: Radius.md).fill(Color.theme.tintNeon)).padding(.top, 18)
                .fixedSize(horizontal: false, vertical: true)
            Button { sheetKey = "prem" } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("All write weeks").font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Color.theme.fg1)
                        Text("\(d.weeks.count) weeks · \(d.weeks.filter { $0.v > 0 }.count) with writes").font(.mono(size: 10.5, weight: .regular)).foregroundStyle(Color.theme.fg4)
                    }
                    Spacer()
                    Text(fmtMoney(d.premLife, sign: true)).font(.mono(size: 14, weight: .semibold)).foregroundStyle(Color.theme.pos)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.theme.fg5)
                }
                .padding(.vertical, 15).contentShape(Rectangle())
                .overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 1) }
            }
            .buttonStyle(.plain).padding(.top, 4)
        }
    }

    // ── what the position earned ──
    private func earnedPanel(_ d: PosData) -> some View {
        let tot = d.premLife + abs(d.sharesPL)
        return panel {
            HStack(alignment: .firstTextBaseline) {
                Text("What the position earned").font(.system(size: 16, weight: .bold)).tracking(-0.3).foregroundStyle(Color.theme.fg1)
                Spacer()
                Text(fmtMoney(d.netPL, sign: true)).font(.mono(size: 15, weight: .bold)).foregroundStyle(Color.theme.pos)
            }
            Text("Premium against unrealized share loss, since the first write.").font(.system(size: 11.5)).foregroundStyle(Color.theme.fg3).padding(.top, 7)
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 3).fill(Color.theme.neon).frame(width: max(2, CGFloat(d.premLife / tot) * 300))
                RoundedRectangle(cornerRadius: 3).fill(Color.theme.tintNeg).frame(width: max(2, CGFloat(abs(d.sharesPL) / tot) * 300))
            }
            .frame(height: 20).frame(maxWidth: .infinity, alignment: .leading).clipShape(RoundedRectangle(cornerRadius: 4)).padding(.top, 18)
            Button { sheetKey = "earned" } label: {
                earnedRow("Premium income", "lifetime", fmtMoney(d.premLife, sign: true), .pos, chevron: true)
            }.buttonStyle(.plain)
            earnedRow("Shares", "unrealized vs \(fmtMoney(d.basisOrig, decimals: 2))", fmtMoney(d.sharesPL, sign: true), .neg, chevron: false)
            HStack {
                Text(String(format: "%.2f%%", d.premYield)).font(.mono(size: 32, weight: .bold)).tracking(-1.2).foregroundStyle(Color.theme.fg1)
                Spacer()
                Text("Premium collected against position value").font(.system(size: 11)).foregroundStyle(Color.theme.fg3)
                    .multilineTextAlignment(.trailing).frame(maxWidth: 160)
            }
            .padding(15).background(RoundedRectangle(cornerRadius: Radius.lg).fill(Color.theme.page2)).padding(.top, 16)
        }
    }

    private func earnedRow(_ a: String, _ b: String, _ v: String, _ tone: Tone, chevron: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(a).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Color.theme.fg1)
                Text(b).font(.mono(size: 10.5, weight: .regular)).foregroundStyle(Color.theme.fg4)
            }
            Spacer()
            Text(v).font(.mono(size: 14, weight: .semibold)).foregroundStyle(tone == .pos ? Color.theme.pos : Color.theme.neg)
            if chevron { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.theme.fg5) }
        }
        .padding(.vertical, 15).overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 1) }
    }

    // ── history ──
    private func historyPanel(_ d: PosData) -> some View {
        panel {
            Text("History").font(.system(size: 16, weight: .bold)).tracking(-0.3).foregroundStyle(Color.theme.fg1)
            Text("Legs as they were written and closed.").font(.system(size: 11.5)).foregroundStyle(Color.theme.fg3).padding(.top, 7)
            if d.hist.isEmpty {
                Text("Nothing closed yet.").font(.system(size: 13)).foregroundStyle(Color.theme.fg4).padding(.top, 14)
            } else {
                ForEach(d.hist) { h in
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(h.w).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Color.theme.fg3)
                            Text(h.note).font(.mono(size: 10.5, weight: .regular)).foregroundStyle(Color.theme.fg4)
                        }
                        Spacer()
                        Text(fmtMoney(h.v, sign: true)).font(.mono(size: 14, weight: .semibold)).foregroundStyle(Color.theme.pos)
                    }
                    .padding(.vertical, 15).overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 1) }
                }
            }
        }
    }

    // ── shared ──
    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.xl).fill(Color.theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Color.theme.hair, lineWidth: 1))
    }

    private func detailSheet(_ sh: NVSheet) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(sh.cat.uppercased()).font(.mono(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(Color.theme.neon)
                Text(sh.title).font(.system(size: 25, weight: .bold)).tracking(-0.6).foregroundStyle(Color.theme.fg1).padding(.top, 7)
                Text(sh.sub).font(.system(size: 10.5)).foregroundStyle(Color.theme.fg3).padding(.top, 8)
                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    Text(sh.hero).font(.mono(size: 44, weight: .bold)).tracking(-1.4).foregroundStyle(Color.theme.fg1)
                    Text(sh.heroUnit).font(.system(size: 10.5)).foregroundStyle(Color.theme.fg3)
                }.padding(.top, 17)
                Text(sh.line).font(.system(size: 12.5)).foregroundStyle(Color.theme.fg2).lineSpacing(3).padding(.top, 14)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach(Array(sh.rows.enumerated()), id: \.offset) { i, r in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(r.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.theme.fg1)
                                Text(r.sub).font(.system(size: 10)).foregroundStyle(Color.theme.fg3)
                            }
                            Spacer()
                            Text(r.val).font(.mono(size: 15, weight: .medium)).foregroundStyle(tc(r.tone))
                        }
                        .padding(.vertical, 12).overlay(alignment: .top) { if i > 0 { Rectangle().fill(Color.theme.hair).frame(height: 1) } }
                    }
                }.padding(.top, 8)
            }.padding(22)
        }
    }
}
