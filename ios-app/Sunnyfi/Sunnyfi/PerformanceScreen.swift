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

    @State private var pid = "week"
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
    private let cardW: CGFloat = 292

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
        let d = PerfData.build(store: store)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let d {
                    header(d)
                    netCard(d).padding(.horizontal, 22).padding(.top, 12)
                    gainsPanel(d).padding(.horizontal, 22).padding(.top, 12)
                    expiryPanel(d).padding(.horizontal, 22).padding(.top, 12)
                    sourceRail(d)
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

    // ── gains & losses ──
    private func gainsPanel(_ d: PerfData) -> some View {
        let p = d.periods.first { $0.id == pid } ?? d.periods[0]
        let gains = p.bars.map { gainOf($0) }, losses = p.bars.map { abs(lossOf($0)) }
        let maxUp = max(1, gains.max() ?? 1), maxDn = max(1, losses.max() ?? 1)
        let H: CGFloat = 170
        let upH = H * CGFloat(maxUp / (maxUp + maxDn))
        let sc = H / CGFloat(maxUp + maxDn)
        let t = totals(p.bars)
        let dense = p.bars.count > 14
        return panel {
            HStack(alignment: .firstTextBaseline) {
                Text("Gains & losses").font(.system(size: 16, weight: .bold)).tracking(-0.3).foregroundStyle(Color.theme.fg1)
                Spacer()
                Text(fmtMoney(t.net, sign: true)).font(.mono(size: 15, weight: .bold)).foregroundStyle(Color.signed(t.net))
            }
            Text("Daily, split into stock and written calls. Tap a bar.").font(.system(size: 11.5)).foregroundStyle(Color.theme.fg3).padding(.top, 7)
            // period switch
            HStack(spacing: 7) {
                ForEach(d.periods) { per in
                    let active = per.id == pid
                    Button { withAnimation(Motion.standard) { pid = per.id; sel = nil } } label: {
                        Text(per.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(active ? Color.theme.page : Color.theme.fg3)
                            .frame(maxWidth: .infinity, minHeight: 32).background(Capsule().fill(active ? Color.theme.fg1 : Color.theme.page2))
                    }.buttonStyle(.plain)
                }
            }.padding(.top, 10)
            // chart
            GeometryReader { g in
                let w = g.size.width
                let bw = (w - CGFloat(p.bars.count - 1) * (dense ? 1.5 : 3)) / CGFloat(p.bars.count)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color(hex: 0x19372a, alpha: 0.3)).frame(height: 1.5).offset(y: upH)
                    HStack(alignment: .top, spacing: dense ? 1.5 : 3) {
                        ForEach(Array(p.bars.enumerated()), id: \.offset) { i, bar in
                            Button { withAnimation(Motion.standard) { sel = (sel == i ? nil : i) } } label: {
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    VStack(spacing: 0) {   // gains (up)
                                        ForEach(PerfSource.allCases, id: \.self) { s in
                                            if (on[s] ?? true), bar.val(s) > 0 {
                                                Rectangle().fill(srcColor(s)).frame(height: CGFloat(bar.val(s)) * sc)
                                            }
                                        }
                                    }
                                    .frame(height: CGFloat(gains[i]) * sc, alignment: .bottom)
                                    Color.clear.frame(height: 0)
                                    VStack(spacing: 0) {   // losses (down)
                                        ForEach(PerfSource.allCases, id: \.self) { s in
                                            if (on[s] ?? true), bar.val(s) < 0 {
                                                Rectangle().fill(srcColor(s).opacity(0.55)).frame(height: CGFloat(abs(bar.val(s))) * sc)
                                            }
                                        }
                                    }
                                    .frame(height: CGFloat(losses[i]) * sc, alignment: .top)
                                    Spacer(minLength: 0)
                                }
                                .frame(width: bw, height: H)
                                .opacity(sel == nil || sel == i ? 1 : 0.34)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(height: H).padding(.top, 18)
            // x axis
            HStack(spacing: dense ? 1.5 : 3) {
                ForEach(Array(p.bars.enumerated()), id: \.offset) { i, bar in
                    Text(p.ticks != nil ? (p.ticks?[i] ?? (sel == i ? bar.label : "")) : bar.label)
                        .font(.mono(size: 9, weight: sel == i ? .semibold : .regular))
                        .foregroundStyle(sel == i ? Color.theme.neon : Color.theme.fg4)
                        .frame(maxWidth: .infinity).lineLimit(1)
                }
            }.padding(.top, 9)
            // readout
            readout(p, gains: gains, losses: losses, t: t).padding(.top, 14).padding(.top, 13)
                .overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 1) }
            // legend
            HStack(spacing: 7) {
                ForEach(PerfSource.allCases, id: \.self) { s in
                    let v = p.bars.reduce(0.0) { $0 + $1.val(s) }
                    let isOn = on[s] ?? true
                    Button { on[s] = !isOn } label: {
                        HStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 2).fill(srcColor(s)).frame(width: 9, height: 9)
                            Text(s == .shares ? "Shares" : "Calls sold").font(.mono(size: 10.5, weight: .regular)).foregroundStyle(Color.theme.fg1)
                            Text(fmtMoney(v, sign: true)).font(.mono(size: 10, weight: .regular)).foregroundStyle(Color.signed(v))
                        }
                        .padding(.horizontal, 11).padding(.vertical, 8)
                        .background(Capsule().fill(isOn ? Color.theme.elevated : Color.theme.page2))
                        .overlay(Capsule().strokeBorder(isOn ? Color.theme.borderBright : Color.theme.dusk, style: .init(lineWidth: 1, dash: isOn ? [] : [3, 2])))
                        .opacity(isOn ? 1 : 0.42)
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }.padding(.top, 16)
        }
    }

    @ViewBuilder
    private func readout(_ p: PerfPeriodModel, gains: [Double], losses: [Double], t: (gains: Double, losses: Double, net: Double)) -> some View {
        if let i = sel {
            let b = p.bars[i]
            HStack(spacing: 10) {
                Text(b.sub).font(.mono(size: 11, weight: .semibold)).foregroundStyle(Color.theme.fg1)
                Text("↑\(fmtMoney(gainOf(b)).replacingOccurrences(of: "+", with: "")) · ↓\(fmtMoney(abs(lossOf(b))))")
                    .font(.mono(size: 11, weight: .regular)).foregroundStyle(Color.theme.fg3).lineLimit(1)
                Spacer(minLength: 0)
                Text(fmtMoney(gainOf(b) + lossOf(b), sign: true)).font(.mono(size: 11, weight: .semibold)).foregroundStyle(Color.signed(gainOf(b) + lossOf(b)))
                Button { withAnimation { sel = nil } } label: {
                    Text("CLEAR").font(.mono(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(Color.theme.neon)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Color.theme.tintNeon))
                }.buttonStyle(.plain)
            }
        } else {
            HStack {
                Text("\(p.bars.count) sessions · tap for a day").font(.mono(size: 11, weight: .regular)).foregroundStyle(Color.theme.fg3)
                Spacer()
                Text(fmtMoney(t.net, sign: true)).font(.mono(size: 11, weight: .semibold)).foregroundStyle(Color.signed(t.net))
            }
        }
    }

    // ── premium by expiry ledger ──
    private func expiryPanel(_ d: PerfData) -> some View {
        let maxUp = max(1, d.expiries.map(\.prem).max() ?? 1)
        let maxDn = max(1, d.expiries.map(\.cost).max() ?? 1)
        let H: CGFloat = 150
        let upH = H * CGFloat(maxUp / (maxUp + maxDn)), sc = H / CGFloat(maxUp + maxDn)
        return panel {
            HStack(alignment: .firstTextBaseline) {
                Text("Premium by expiry").font(.system(size: 16, weight: .bold)).tracking(-0.3).foregroundStyle(Color.theme.fg1)
                Spacer()
                Text(fmtMoney(d.expNet, sign: true)).font(.mono(size: 15, weight: .bold)).foregroundStyle(Color.theme.pos)
            }
            Text("Credit taken up, cost to close down.").font(.system(size: 11.5)).foregroundStyle(Color.theme.fg3).padding(.top, 7)
            HStack(alignment: .top, spacing: 6) {
                ForEach(d.expiries) { e in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2).fill(Color.theme.oi).frame(height: CGFloat(e.prem) * sc)
                        Rectangle().fill(Color.clear).frame(height: 0)
                        if e.cost > 0 { RoundedRectangle(cornerRadius: 2).fill(Color.theme.neg.opacity(0.55)).frame(height: CGFloat(e.cost) * sc) }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: H, alignment: upH > 0 ? .center : .top)
                    .overlay(alignment: .top) { Rectangle().fill(Color(hex: 0x19372a, alpha: 0.3)).frame(height: 1).offset(y: upH) }
                }
            }
            .frame(height: H).padding(.top, 16)
            HStack(spacing: 6) {
                ForEach(d.expiries) { e in Text(e.ex).font(.mono(size: 9, weight: .regular)).foregroundStyle(Color.theme.fg4).frame(maxWidth: .infinity) }
            }.padding(.top, 9)
            ForEach(Array(d.expiries.reversed().enumerated()), id: \.element.id) { i, e in
                Button { sheetKey = "exp-\(e.ex)" } label: {
                    HStack(spacing: 11) {
                        Text("\(d.expiries.count - i)").font(.mono(size: 11, weight: .regular)).foregroundStyle(Color.theme.fg4).frame(width: 16)
                        Text(e.ex).font(.system(size: 14.5, weight: .bold)).tracking(-0.2).foregroundStyle(Color.theme.fg1).frame(width: 50, alignment: .leading)
                        Text("\(fmtStrike(e.strike))c ×\(e.qty) · \(e.status)").font(.mono(size: 9.5, weight: .regular)).foregroundStyle(Color.theme.fg4).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(fmtMoney(e.net, sign: true)).font(.mono(size: 13, weight: .semibold)).foregroundStyle(Color.signed(e.net))
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.theme.fg5)
                    }
                    .padding(.vertical, 14).contentShape(Rectangle()).overlay(alignment: .top) { Rectangle().fill(Color.theme.hair).frame(height: 1) }
                }.buttonStyle(.plain)
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
                Text(s.empty ? "—" : fmtMoney(s.today, sign: true)).font(.mono(size: 28, weight: .bold)).tracking(-0.9)
                    .foregroundStyle(s.empty ? Color.theme.fg4 : Color.theme.fg1).padding(.top, 16)
                Text("PERFORMANCE AS OF TODAY").font(.mono(size: 9, weight: .medium)).tracking(0.8).foregroundStyle(Color.theme.fg4).padding(.top, 9)
                Text(s.name).font(.system(size: 17, weight: .bold)).tracking(-0.3).foregroundStyle(Color.theme.fg1).padding(.top, 15)
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
            .padding(17).frame(width: cardW, height: 258, alignment: .top)
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
