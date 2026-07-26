//
//  PerformanceScreen.swift
//  Sunnyfi
//
//  NVDA Performance (Perf tab) — handoff 6. Rich-black Net P&L card,
//  a Gains & losses stacked chart with the Week/Month/Year switch and a
//  source-toggle legend, the premium-by-expiry ledger, and the by-source
//  rail. Data from PerfData.
//

import SwiftUI

struct PerformanceScreen: View {
    let store: PortfolioStore
    let auth: AuthStore
    @Environment(\.navBarChrome) private var navChrome

    @State private var monthIdx: Int?   // Gains & losses month rail (nil = latest)
    @State private var on: [PerfSource: Bool] = [.shares: true, .calls: true]
    @State private var sel: Int?
    @State private var sheetKey: String?
    @State private var srcPos: String?

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
    private let cardW: CGFloat = 320

    private func tc(_ t: Tone) -> Color {
        switch t {
        case .pos: return Color.theme.pos; case .neg: return Color.theme.neg
        case .neon: return Color.theme.neon; case .warn: return Color.theme.warn
        case .fg1: return Color.theme.fg1; case .fg3: return Color.theme.fg3
        }
    }
    private func srcColor(_ k: String) -> Color {
        switch k { case "oi": return Color.theme.oi; case "earnings": return Color.theme.earnings
        case "gold": return Color.theme.gold; case "note": return Color.theme.note; default: return Color.theme.neon }
    }
    private func srcColor(_ s: PerfSource) -> Color { s == .shares ? Color.theme.neon : Color.theme.oi }

    var body: some View {
        let d = store.cachedPerformance()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let d {
                    header(d)
                    netCard(d).padding(.horizontal, 22).padding(.top, 12)
                    monthChart(d).padding(.horizontal, 22).padding(.top, 12)
                    sourceRail(d)
                } else {
                    Text("No NVDA position yet.").font(.system(size: 14)).foregroundStyle(Color.theme.fg3).padding(40)
                }
                Color.clear.frame(height: 112)
            }
        }
        .background(Color.theme.page)
        .reportsNavScroll(navChrome)
        .sheet(item: Binding(get: { sheetKey.map { Keyed(id: $0) } }, set: { sheetKey = $0?.id })) { keyed in
            if let d, let sh = d.sheets[keyed.id] {
                detailSheet(sh).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                    .presentationBackground(Color.theme.elevated)
            }
        }
    }

    private struct Keyed: Identifiable { let id: String }

    private func header(_ d: PerfData) -> some View {
        HStack(spacing: 7) {
            Text("\(d.ticker) PERFORMANCE").font(.mono(size: 12, weight: .semibold)).tracking(1.6).foregroundStyle(Color.theme.fg1)
            Circle().fill(Color.theme.lime).frame(width: 6, height: 6)
            Spacer()
            Text("COVERED CALL · \(Int(d.shares).formatted(.number.grouping(.automatic))) SHARES")
                .font(.mono(size: 9.5, weight: .semibold)).tracking(0.5).foregroundStyle(Color.theme.fg4)
        }
        .padding(.horizontal, 22).padding(.top, 8)
    }

    // ── rich-black net P&L ──
    private func netCard(_ d: PerfData) -> some View {
        let tot = d.premLife + abs(d.sharesPL)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("NET P&L · SINCE FIRST WRITE").font(.mono(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(inkText.opacity(0.58))
                Spacer()
                Text("\(String(format: "%.2f", d.premYield))% OF VALUE").font(.mono(size: 8, weight: .semibold)).tracking(1)
                    .foregroundStyle(limeInk).padding(.horizontal, 9).padding(.vertical, 5).background(Capsule().fill(lime))
            }
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Text(fmtMoney(d.netPL, sign: true)).font(.mono(size: 42, weight: .bold)).tracking(-1.6)
                    .foregroundStyle(d.netPL >= 0 ? lime : Color(hex: 0xe59a83))
                Text("ALL IN").font(.mono(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(inkText.opacity(0.5))
            }.padding(.top, 18)
            Text("Premium \(fmtMoney(d.premLife, sign: true)) against \(fmtMoney(d.sharesPL, sign: true)) on the stock.")
                .font(.system(size: 12)).foregroundStyle(inkText.opacity(0.6)).padding(.top, 12)
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(lime).frame(width: max(2, CGFloat(d.premLife / tot) * 300))
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xc96a4f)).frame(width: max(2, CGFloat(abs(d.sharesPL) / tot) * 300))
            }
            .frame(height: 14).frame(maxWidth: .infinity, alignment: .leading).clipShape(RoundedRectangle(cornerRadius: 3)).padding(.top, 20)
            HStack(spacing: 14) {
                inkStat("Premium", fmtMoney(d.premLife, sign: true), color: lime)
                inkStat("Shares", fmtMoney(d.sharesPL, sign: true), color: Color(hex: 0xe59a83), divider: true)
            }
            .padding(.top, 18).padding(.top, 16)
            .overlay(alignment: .top) { Rectangle().fill(inkText.opacity(0.12)).frame(height: 1).padding(.top, 18) }
        }
        .padding(18).background(RoundedRectangle(cornerRadius: Radius.xl).fill(inkBG))
    }

    private func inkStat(_ label: String, _ value: String, color: Color, divider: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased()).font(.mono(size: 8, weight: .semibold)).tracking(1.2).foregroundStyle(inkText.opacity(0.45))
            Text(value).font(.mono(size: 16, weight: .bold)).tracking(-0.3).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, divider ? 14 : 0)
        .overlay(alignment: .leading) { if divider { Rectangle().fill(inkText.opacity(0.12)).frame(width: 1) } }
    }

    // ── gains & losses · one month at a time (handoff 7) ──
    private struct LegendItem: Identifiable { let label: String; let colorKey: String; let source: PerfSource?; var id: String { label } }
    private var legendItems: [LegendItem] {
        [.init(label: "Shares", colorKey: "neon", source: .shares),
         .init(label: "Calls sold", colorKey: "oi", source: .calls),
         .init(label: "Calls bought", colorKey: "earnings", source: nil),
         .init(label: "Puts sold", colorKey: "gold", source: nil),
         .init(label: "Puts bought", colorKey: "note", source: nil)]
    }

    private func barGain(_ b: PerfBar) -> Double { PerfSource.allCases.reduce(0) { $0 + (((on[$1] ?? true) && b.val($1) > 0) ? b.val($1) : 0) } }
    private func barLoss(_ b: PerfBar) -> Double { PerfSource.allCases.reduce(0) { $0 + (((on[$1] ?? true) && b.val($1) < 0) ? b.val($1) : 0) } }
    private func monthNet(_ bars: [PerfBar]) -> Double { bars.reduce(0) { $0 + barGain($1) + barLoss($1) } }
    private func barSegs(_ b: PerfBar) -> [SBCSeg] {
        PerfSource.allCases.compactMap { s in
            guard (on[s] ?? true), b.val(s) != 0 else { return nil }
            return SBCSeg(v: b.val(s), color: srcColor(s))
        }
    }
    private func compactSigned(_ v: Double) -> String {
        let s = v > 0 ? "+" : v < 0 ? "−" : ""
        let a = abs(v)
        if a >= 1000 { return s + "$" + String(format: a >= 10000 ? "%.0f" : "%.1f", a / 1000) + "K" }
        return s + "$" + String(format: "%.0f", a)
    }

    private func monthChart(_ d: PerfData) -> some View {
        let mIdx = d.months.isEmpty ? 0 : min(monthIdx ?? (d.months.count - 1), d.months.count - 1)
        let bars = d.months.indices.contains(mIdx) ? d.months[mIdx].bars : []
        let net = monthNet(bars)
        return panel {
            HStack(alignment: .firstTextBaseline) {
                Text("Gains & losses").font(.system(size: 16, weight: .bold)).tracking(-0.3).foregroundStyle(Color.theme.fg1)
                Spacer()
                Text(fmtMoney(net, sign: true)).font(.mono(size: 15, weight: .bold)).foregroundStyle(Color.signed(net))
            }
            Text("Daily, split into stock and written calls. Tap a bar.").font(.system(size: 11.5)).foregroundStyle(Color.theme.fg3).padding(.top, 7)
            // month rail
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(d.months.enumerated()), id: \.element.id) { i, mm in
                        let active = i == mIdx
                        Button { withAnimation(Motion.standard) { monthIdx = i; sel = nil } } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(mm.short.uppercased()).font(.mono(size: 12, weight: .bold)).tracking(0.4)
                                    .foregroundStyle(active ? Color.theme.page : Color.theme.fg2)
                                Text(compactSigned(monthNet(mm.bars))).font(.mono(size: 11, weight: .semibold))
                                    .foregroundStyle(active ? Color.theme.lime : Color.theme.fg4)
                            }
                            .frame(minWidth: 76, alignment: .leading).padding(.horizontal, 13).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(active ? Color.theme.fg1 : Color.theme.page2))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .padding(.horizontal, -16).padding(.top, 14)
            // the one bar-chart vocabulary
            SunnyBarChart(
                bars: bars.enumerated().map { i, bar in SBCBar(key: "\(i)", label: bar.label, sub: bar.sub, segs: barSegs(bar)) },
                height: 180, sel: sel, onSel: { sel = $0 }, topLabel: "Gain", bottomLabel: "Loss")
            // readout
            readout(bars: bars).padding(.top, 14).padding(.top, 13)
                .overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 1) }
            // five-source legend (shares + calls sold live; the rest honest empties)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) { ForEach(legendItems) { legendChip($0, bars: bars) } }
            }
            .padding(.horizontal, -16).padding(.top, 16)
        }
    }

    private func legendChip(_ item: LegendItem, bars: [PerfBar]) -> some View {
        let disabled = item.source == nil
        let isOn = item.source.map { on[$0] ?? true } ?? false
        let v = item.source.map { s in bars.reduce(0.0) { $0 + $1.val(s) } } ?? 0
        let live = isOn && !disabled
        return Button {
            if let s = item.source { on[s] = !(on[s] ?? true) }
        } label: {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2).fill(srcColor(item.colorKey)).frame(width: 9, height: 9)
                Text(item.label).font(.mono(size: 10.5, weight: .regular)).foregroundStyle(Color.theme.fg1)
                Text(disabled ? "—" : fmtMoney(v, sign: true)).font(.mono(size: 10, weight: .regular))
                    .foregroundStyle(disabled ? Color.theme.fg4 : Color.signed(v))
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(Capsule().fill(live ? Color.theme.elevated : Color.theme.page2))
            .overlay(Capsule().strokeBorder(live ? Color.theme.borderBright : Color.theme.dusk, style: .init(lineWidth: 1, dash: live ? [] : [3, 2])))
            .opacity(live ? 1 : 0.5)
        }
        .buttonStyle(.plain).disabled(disabled)
    }

    @ViewBuilder
    private func readout(bars: [PerfBar]) -> some View {
        if let i = sel, bars.indices.contains(i) {
            let b = bars[i]
            let g = barGain(b), l = barLoss(b)
            HStack(spacing: 10) {
                Text(b.sub).font(.mono(size: 11, weight: .semibold)).foregroundStyle(Color.theme.fg1)
                Text("↑\(fmtMoney(g).replacingOccurrences(of: "+", with: "")) · ↓\(fmtMoney(abs(l)))")
                    .font(.mono(size: 11, weight: .regular)).foregroundStyle(Color.theme.fg3).lineLimit(1)
                Spacer(minLength: 0)
                Text(fmtMoney(g + l, sign: true)).font(.mono(size: 11, weight: .semibold)).foregroundStyle(Color.signed(g + l))
                Button { withAnimation { sel = nil } } label: {
                    Text("CLEAR").font(.mono(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(Color.theme.neon)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Color.theme.tintNeon))
                }.buttonStyle(.plain)
            }
        } else {
            HStack {
                Text("\(bars.count) sessions · tap for a day").font(.mono(size: 11, weight: .regular)).foregroundStyle(Color.theme.fg3)
                Spacer()
                Text(fmtMoney(monthNet(bars), sign: true)).font(.mono(size: 11, weight: .semibold)).foregroundStyle(Color.signed(monthNet(bars)))
            }
        }
    }

    // ── by-source rail ──
    private func sourceRail(_ d: PerfData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PERFORMANCE BY SOURCE").font(.mono(size: 9, weight: .semibold)).tracking(2.2).foregroundStyle(Color.theme.fg4)
                Spacer()
                dots(d.sources.map(\.key), srcPos)
            }
            .padding(.horizontal, 22).padding(.top, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 11) { ForEach(d.sources) { sourceCard($0).id($0.key) } }
                    .padding(.horizontal, 22).padding(.vertical, 10).scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $srcPos)
        }
    }

    private func sourceCard(_ s: PerfSrc) -> some View {
        let pos = !s.empty && s.today > 0
        return Button { sheetKey = s.key } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2).fill(srcColor(s.colorKey)).frame(width: 8, height: 8)
                        Text(s.label.uppercased()).font(.mono(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(Color.theme.fg3)
                    }
                    Spacer()
                    Text(s.chip).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(s.empty ? Color.theme.fg2 : (pos ? Color.theme.pos : Color.theme.neg))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(s.empty ? Color.theme.tintMuted : (pos ? Color.theme.tintPos : Color.theme.tintNeg)))
                }
                // Handoff: .kc-num is always --fg1 on non-ink cards (empty keeps its muted intent).
                Text(s.empty ? "—" : fmtMoney(s.today, sign: true)).font(.mono(size: 34, weight: .bold)).tracking(-0.9)
                    .foregroundStyle(s.empty ? Color.theme.fg4 : Color.theme.fg1).padding(.top, 16)
                Text("PERFORMANCE AS OF TODAY").font(.mono(size: 9, weight: .medium)).tracking(0.8).foregroundStyle(Color.theme.fg4).padding(.top, 9)
                Text(s.name).font(.system(size: 21, weight: .bold)).tracking(-0.3).foregroundStyle(Color.theme.fg1).padding(.top, 15)
                    .fixedSize(horizontal: false, vertical: true)
                Text(s.sub).font(.system(size: 12)).foregroundStyle(Color.theme.fg3).padding(.top, 8).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: 14) {
                    srcStat(s.flowLbl, s.flowVal, muted: s.empty)
                    srcStat(s.nowLbl, s.nowVal, muted: s.empty, divider: true)
                }
                .padding(.top, 16).padding(.top, 14)
                .overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 1).padding(.top, 16) }
            }
            .padding(17).frame(width: cardW, height: 365, alignment: .top)
            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Color.theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Color.theme.hair, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func srcStat(_ label: String, _ value: String, muted: Bool, divider: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased()).font(.mono(size: 8, weight: .semibold)).tracking(1.2).foregroundStyle(Color.theme.fg4)
            Text(value).font(.mono(size: 15, weight: .bold)).tracking(-0.2).foregroundStyle(muted ? Color.theme.fg4 : Color.theme.fg1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, divider ? 14 : 0)
        .overlay(alignment: .leading) { if divider { Rectangle().fill(Color.theme.hair).frame(width: 1) } }
    }

    // ── shared ──
    private func gainOf(_ b: PerfBar) -> Double { PerfSource.allCases.reduce(0.0) { (on[$1] ?? true) && b.val($1) > 0 ? $0 + b.val($1) : $0 } }
    private func lossOf(_ b: PerfBar) -> Double { PerfSource.allCases.reduce(0.0) { (on[$1] ?? true) && b.val($1) < 0 ? $0 + b.val($1) : $0 } }
    private func totals(_ bars: [PerfBar]) -> (gains: Double, losses: Double, net: Double) {
        var g = 0.0, l = 0.0; bars.forEach { g += gainOf($0); l += lossOf($0) }; return (g, l, g + l)
    }

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
                Text(sh.title).font(.system(size: 23, weight: .bold)).tracking(-0.6).foregroundStyle(Color.theme.fg1).padding(.top, 7)
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
