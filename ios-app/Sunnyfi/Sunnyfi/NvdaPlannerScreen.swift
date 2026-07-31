//
//  NvdaPlannerScreen.swift
//  Sunnyfi — Ink rebuild · Planner (rev 2, stepped-card design)
//
//  A step bar over eight `.pc` cards: Seller score, Guardrails, Upside room,
//  How many, Which expiry, Which strike (+ Levels), What happens next, The plan.
//  All decision math is client-side (PlannerEngine) so taps hold the page still;
//  the edge is re-called only when weekend-vol changes.
//

import SwiftUI

// MARK: - palette + formatting

private let PG_UP = Ink.gain
private let PG_DOWN = Ink.loss
private func pgUsd(_ n: Double) -> String { (n < 0 ? "−$" : "$") + Int(abs(n).rounded()).formatted(.number.grouping(.automatic)) }
private func pgSigned(_ n: Double, _ dp: Int = 2) -> String { (n < 0 ? "−$" : "+$") + String(format: "%.\(dp)f", abs(n)) }
private func pgMoney(_ n: Double) -> String { (n < 0 ? "−$" : "+$") + Int(abs(n).rounded()).formatted(.number.grouping(.automatic)) }
private func pgPct(_ n: Double, _ dp: Int = 1) -> String { (n >= 0 ? "+" : "−") + String(format: "%.\(dp)f", abs(n)) + "%" }
private func grp(_ n: Double) -> String { Int(n.rounded()).formatted(.number.grouping(.automatic)) }
private func nvS(_ k: Double) -> String { k == k.rounded() ? String(Int(k)) : String(format: "%.1f", k) }
private func f1(_ v: Double) -> String { String(format: "%.1f", v) }
private func f2(_ v: Double) -> String { String(format: "%.2f", v) }

private func M(_ t: String, _ size: CGFloat, _ ls: CGFloat = 0.14, _ c: Color = Ink.dim, upper: Bool = true) -> Text {
    Text(upper ? t.uppercased() : t).font(InkFont.mono(size)).tracking(size * ls).foregroundStyle(c)
}
private func N(_ t: String, _ size: CGFloat, _ c: Color = Ink.text) -> Text {
    Text(t).font(InkFont.mono(size)).tracking(size * -0.02).foregroundStyle(c)
}

// MARK: - derived state (computed once, passed to cards)

struct PlannerDerived {
    let spot: Double
    let book: PBook
    let gate: PGate
    let expiry: PExpiry?
    var chain: [PRung] { expiry?.chain ?? [] }
    let upside: PlannerEngine.Upside
    let levels: [PlannerEngine.Level]
    let pick: PlannerEngine.Pick
    let ct: Double
    let settings: PlannerSettings
    let histAssign: Double
    let selStrike: Double?

    var selRung: PRung? { rung(selStrike) }
    func rung(_ k: Double?) -> PRung? { guard let k else { return nil }; return chain.first { abs($0.strike - k) < 1e-6 } }
    func netDeltaAfter(_ r: PRung) -> Double { PlannerEngine.netDeltaAfter(r, book, ct: ct) }
    func passes(_ r: PRung) -> Bool { PlannerEngine.passesAll(r, settings, book, ct: ct) }
    func failing(_ r: PRung) -> [String] { PlannerEngine.failing(r, settings, book, ct: ct) }
    func cleared(_ r: PRung) -> Int { PlannerEngine.cleared(r, levels) }
    func pairing(_ r: PRung) -> PlannerEngine.Pairing? { PlannerEngine.pairing(r.strike, legsOrEmpty, ct: ct, spot: spot, rallyPct: settings.rallyPct) }
    var legsOrEmpty: PlannerLegs
    func effSale(_ r: PRung) -> Double { PlannerEngine.effSale(r) }
    var isOnTarget: (Double) -> Bool
}

// MARK: - screen

struct NvdaPlannerScreen: View {
    let store: NvdaStore
    let onClose: () -> Void
    @State private var planner = PlannerStore()

    private let stepLabels = ["Read the setup", "Check your guardrails", "Read the upside room", "Set the size",
                              "Choose an expiry", "Choose a strike", "See what happens next", "Read the plan"]

    var body: some View {
        ZStack {
            Ink.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                nav
                steps
                content
            }
        }
        .task { await planner.load(from: store) }
    }

    private var nav: some View {
        HStack(spacing: 13) {
            Button(action: onClose) {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .regular)).foregroundStyle(Ink.text)
                    .frame(width: 38, height: 38).overlay(Circle().strokeBorder(Ink.hair, lineWidth: 1))
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 0) {
                M("NVDA · next short call", 10, 0.18)
                Text("Planner").font(InkFont.serif(28)).tracking(28 * -0.01).foregroundStyle(Ink.text).padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 15, trailing: 18))
    }

    private var steps: some View {
        let at = planner.selExpiry == nil ? 4 : planner.selStrike == nil ? 5 : 7
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 5) {
                ForEach(0..<8, id: \.self) { i in
                    Capsule().fill(i == at ? Ink.text : (i < at ? Ink.dim : Ink.hair))
                        .frame(height: i == at ? 5 : 4)
                }
            }
            HStack(spacing: 10) {
                M("step \(at + 1) of 8", 10, 0.14)
                M(stepLabels[at], 10, 0.1, Ink.text)
            }
        }
        .padding(EdgeInsets(top: 2, leading: 18, bottom: 16, trailing: 18))
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.hair).frame(height: 1) }
    }

    @ViewBuilder private var content: some View {
        if let s = planner.state, let d = derived(s) {
            ScrollView {
                VStack(spacing: 14) {
                    ScoreCardV(d: d)
                    GuardCardV(planner: planner, d: d)
                    UpsideCardV(planner: planner, d: d)
                    SizeCardV(planner: planner, d: d)
                    ExpiryCardV(planner: planner, d: d)
                    StrikeCardV(planner: planner, d: d)
                    OutlookCardV(planner: planner, d: d)
                    PlanCardV(d: d)
                    Color.clear.frame(height: 28)
                }
                .padding(16)
            }
            .opacity(planner.isLoading && planner.state == nil ? 0.4 : 1)
        } else if planner.lastError != nil {
            quiet("Planner unavailable", planner.lastError ?? "")
        } else {
            VStack { Spacer(); ProgressView().tint(Ink.dim); Spacer() }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func derived(_ s: PlannerState) -> PlannerDerived? {
        let expiry = planner.selExpiryObj
        let up = PlannerEngine.upside(s.technicals, spot: s.gate.spot, planner.settings)
        let levels = planner.legs.map { PlannerEngine.levels($0, spot: s.gate.spot, candidateExpiry: planner.selExpiryDate) } ?? []
        let pick = PlannerEngine.select(expiry?.chain ?? [], planner.settings, s.book, ct: planner.ct,
                                        targetStrike: up.targetStrike, upsideScore: up.score, blocked: s.gate.blocked,
                                        legs: planner.legs, levels: levels, spot: s.gate.spot)
        let ts = up.targetStrike
        let legsE = planner.legs ?? PlannerLegs(longCalls: [], shortCalls: [], buyAvg: s.book.buyAvg, realizedPremium: s.book.realizedPremium, shares: s.book.shares)
        let chain = expiry?.chain ?? []
        let nearestToTarget: Double? = ts.flatMap { t in chain.min { abs($0.strike - t) < abs($1.strike - t) }?.strike }
        return PlannerDerived(spot: s.gate.spot, book: s.book, gate: s.gate, expiry: expiry, upside: up, levels: levels,
                              pick: pick, ct: planner.ct, settings: planner.settings, histAssign: planner.histAssign,
                              selStrike: planner.selStrike, legsOrEmpty: legsE, isOnTarget: { k in nearestToTarget.map { abs($0 - k) < 1e-6 } ?? false })
    }

    private func quiet(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { M(t, 10, 0.16); Text(b).font(InkFont.display(12.5, .light)).foregroundStyle(Ink.dim) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.horizontal, 18).padding(.top, 40)
    }
}

// MARK: - .pc primitives

struct PCard<Content: View>: View {
    let n: String; let cat: String
    var right: AnyView? = nil
    var tint: Bool = false
    var dim: Bool = false
    @ViewBuilder let content: () -> Content

    private var textColor: Color { tint ? Ink.invertText : Ink.text }
    private var dimColor: Color { tint ? Ink.invertText.opacity(0.74) : Ink.dim }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                M("\(n) · \(cat)", 10, 0.18, dimColor).lineLimit(1)
                Spacer(minLength: 0)
                if let right { right }
            }
            .frame(minHeight: 26)
            content()
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous).fill(tint ? Ink.invertBg : Ink.surface))
        .opacity(dim ? 0.5 : 1)
        .environment(\.colorScheme, tint ? (Ink.invertBg == Color(.sRGB, white: 0.96) ? .light : .dark) : .dark)
    }
}

private func PHero(_ v: String, unit: AnyView? = nil, hue: Color = Ink.text) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        InkRoll(text: v, font: InkFont.mono(46, .light), color: hue)
        if let unit { unit }
    }
    .padding(.top, 20)
}

private func PBand(_ text: String, hue: Color? = nil, out: Bool = false) -> some View {
    let fg: Color = hue ?? (out ? Ink.text : Ink.invertText)
    return M(text, 10, 0.14, fg).padding(.horizontal, 12).padding(.vertical, 6)
        .background {
            if let hue { Capsule().fill(hue.opacity(0.16)) }
            else if out { Capsule().strokeBorder(Ink.text, lineWidth: 1) }
            else { Capsule().fill(Ink.invertBg) }
        }
}

struct PFigItem: Identifiable { let k: String; let v: String; var sub: String? = nil; var hue: Color = Ink.text; var id: String { k } }
private func PFigs(_ items: [PFigItem], tint: Bool = false) -> some View {
    let dimC = tint ? Ink.invertText.opacity(0.74) : Ink.dim
    return HStack(alignment: .top, spacing: 0) {
        ForEach(Array(items.enumerated()), id: \.element.id) { i, m in
            VStack(alignment: .leading, spacing: 10) {
                M(m.k, 9.5, 0.14, dimC).lineLimit(1)
                N(m.v, 18, m.hue).lineLimit(1)
                if let sub = m.sub { M(sub, 9.5, 0.08, dimC).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, i == 0 ? 0 : 12)
            .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(tint ? Ink.invertText.opacity(0.2) : Ink.hair).frame(width: 1) } }
        }
    }
    .padding(.top, 16)
    .overlay(alignment: .top) { Rectangle().fill(tint ? Ink.invertText.opacity(0.2) : Ink.hair).frame(height: 1) }
}

struct PKVRow: Identifiable { let k: String; let v: String; var sub: String? = nil; var hue: Color? = nil; var subHue: Color? = nil; var subCross: Bool = false; var id: String { k } }
private func PKV(_ rows: [PKVRow], tint: Bool = false) -> some View {
    let dimC = tint ? Ink.invertText.opacity(0.74) : Ink.dim
    return VStack(spacing: 0) {
        ForEach(rows) { r in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                M(r.k, 10, 0.12, dimC)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 5) {
                    N(r.v, 15, r.hue ?? (tint ? Ink.invertText : Ink.text))
                    if let sub = r.sub { M(sub, 9.5, 0.06, r.subHue ?? dimC).underline(r.subCross, color: dimC) }
                }
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { if r.id != rows.last?.id { Rectangle().fill(tint ? Ink.invertText.opacity(0.2) : Ink.hair).frame(height: 1) } }
        }
    }
    .padding(.top, 18)
}

private func PNote(_ text: String) -> some View { M(text, 11, 0.1).padding(.top, 18) }

struct PMore<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    @State private var open = false
    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(InkMotion.fast) { open.toggle() } } label: {
                HStack {
                    M(label, 10, 0.14); Spacer(minLength: 0)
                    Text(open ? "−" : "+").font(InkFont.mono(14)).foregroundStyle(Ink.dim)
                        .frame(width: 26, height: 26).overlay(Circle().strokeBorder(Ink.hair, lineWidth: 1))
                }
                .padding(.vertical, 16)
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
            }.buttonStyle(.plain)
            if open { content().padding(.bottom, 4) }
        }
        .padding(.top, 20).padding(.horizontal, -22).padding(.horizontal, 22)
    }
}

// segmented control (settings + when)
struct PSeg<T: Equatable>: View {
    let opts: [T]; let cur: T; var def: T? = nil; let fmt: (T) -> String; let pick: (T) -> Void
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(opts.enumerated()), id: \.offset) { i, v in
                let on = v == cur
                Button { pick(v) } label: {
                    ZStack(alignment: .bottom) {
                        M(fmt(v), 12, -0.01, on ? Ink.invertText : Ink.dim, upper: false).frame(maxWidth: .infinity, minHeight: 42).lineLimit(1)
                        if let def, v == def { Circle().fill(on ? Ink.invertText.opacity(0.6) : Ink.dim).frame(width: 3, height: 3).padding(.bottom, 6) }
                    }
                    .background(on ? Ink.invertBg : .clear)
                    .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(Ink.hair).frame(width: 1) } }
                }.buttonStyle(.plain)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(Ink.hair, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Ink.radiusElement))
    }
}

// option card (expiry rail)
struct POpt: View {
    let on: Bool; var off: Bool = false
    let v: String; let sub: String; var sub2: String? = nil; var sub2Hue: Color? = nil; var sub3: String? = nil; var note: String? = nil
    var tag: String? = nil; var tagOut: Bool = false
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                N(v, 19, on ? Ink.invertText : Ink.text)
                M(sub, 9.5, 0.08, on ? Ink.invertText.opacity(0.72) : Ink.dim)
                if let sub2 { Text(sub2).font(InkFont.mono(12)).foregroundStyle(sub2Hue ?? (on ? Ink.invertText : Ink.text)) }
                if let sub3 { M(sub3, 9.5, 0.08, on ? Ink.invertText.opacity(0.72) : Ink.dim) }
                if let note { M(note, 8.5, 0.1, on ? Ink.invertText.opacity(0.72) : Ink.dim) }
                if let tag {
                    M(tag, 8.5, 0.12, tagOut ? (on ? Ink.invertText : Ink.text) : (on ? Ink.invertText.opacity(0.72) : Ink.dim))
                        .padding(.horizontal, tagOut ? 7 : 0).padding(.vertical, tagOut ? 3 : 0)
                        .overlay { if tagOut { Capsule().strokeBorder(on ? Ink.invertText : Ink.text, lineWidth: 1) } }
                }
            }
            .frame(minWidth: 108, alignment: .leading)
            .padding(EdgeInsets(top: 18, leading: 16, bottom: 19, trailing: 16))
            .background(RoundedRectangle(cornerRadius: Ink.radiusElement).fill(on ? Ink.invertBg : .clear))
            .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(on ? Ink.invertBg : Ink.hair, lineWidth: 1))
            .opacity(off ? 0.4 : 1)
        }.buttonStyle(.plain)
    }
}

// MARK: - 01 Seller score

struct ScoreCardV: View {
    let d: PlannerDerived
    var body: some View {
        let g = d.gate; let pass = g.score >= 0.8
        let block = g.flags.first { $0.level == "block" }
        return PCard(n: "01", cat: "Seller score", right: AnyView(PBand(g.blocked ? "Do not sell" : "Clear", hue: g.blocked ? PG_DOWN : nil))) {
            PHero(f2(g.score), unit: AnyView(
                HStack(spacing: 7) {
                    M("floor 0.80 · iv \(f1(g.iv))% vs hv30 \(f1(g.hv30))%", 10, 0.12)
                    if abs(g.hvGap) > 2 {
                        Text((g.hvTrend == "expanding" ? "▲" : "▼") + f1(g.hvGap)).font(.system(size: 10))
                            .foregroundStyle(g.hvTrend == "expanding" ? PG_DOWN : PG_UP)
                    }
                }), hue: pass ? PG_UP : PG_DOWN)
            if let block {
                M(block.head, 10.5, 0.1, PG_DOWN).padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Ink.radiusElement).fill(PG_DOWN.opacity(0.12))).padding(.top, 16)
            }
            if let w = g.wash, w.hit {
                M("wash sale · $\(grp(w.amount)) on \(w.on) · \(w.daysLeft) days left", 10, 0.1)
                    .padding(.leading, 12).padding(.top, 16)
                    .overlay(alignment: .leading) { Rectangle().fill(Ink.dim).frame(width: 2) }
            }
            PFigs([PFigItem(k: "Spot", v: "$\(f2(g.spot))"), PFigItem(k: "Implied", v: "\(f1(g.iv))%", sub: "pctile \(Int(g.ivPct.rounded()))"),
                   PFigItem(k: "Earnings", v: "\(g.daysToEarnings)d", sub: g.earnings)])
            PMore(label: "Vol detail") {
                PKV([PKVRow(k: "IV ÷ HV30", v: f2(g.iv / max(g.hv30, 0.01))), PKVRow(k: "HV 20", v: "\(f1(g.hv20))%"),
                     PKVRow(k: "HV 30", v: "\(f1(g.hv30))%"), PKVRow(k: "HV 60", v: "\(f1(g.hv60))%"), PKVRow(k: "HV 90", v: "\(f1(g.hv90))%"),
                     PKVRow(k: "Earnings date", v: "\(g.earnings) · manual"),
                     PKVRow(k: "HV30 vs HV90", v: "\(g.hvTrend == "expanding" ? "+" : "−")\(f1(g.hvGap)) pts", hue: g.hvTrend == "expanding" ? PG_DOWN : nil)])
            }
        }
    }
}

// MARK: - 02 Guardrails

struct GuardCardV: View {
    @Bindable var planner: PlannerStore
    let d: PlannerDerived
    private let hard = ["minNetDelta", "minExt", "edgeFloor"]
    private let soft = ["weekendVol", "edgeLookback", "rallyPct", "tiebreakBand"]
    private let guardOf = ["minNetDelta": "delta", "minExt": "ext", "edgeFloor": "edge"]

    private func bite(_ key: String) -> (blocks: Int, frees: Int)? {
        guard let g = guardOf[key], !d.chain.isEmpty else { return nil }
        let blocked = d.chain.filter { !PlannerEngine.guardPass(g, $0, d.settings, d.book, ct: d.ct) }
        let frees = blocked.filter { r in PlannerEngine.guardKeys.allSatisfy { $0 == g || PlannerEngine.guardPass($0, r, d.settings, d.book, ct: d.ct) } }.count
        return (blocked.count, frees)
    }
    private var binding: String? {
        hard.map { ($0, bite($0)) }.filter { ($0.1?.blocks ?? 0) > 0 }
            .max { ($0.1?.frees ?? 0, $0.1?.blocks ?? 0) < ($1.1?.frees ?? 0, $1.1?.blocks ?? 0) }?.0
    }
    private var dirty: Int { (hard + soft).filter { planner.settings.fmt($0) != PlannerSettings.default.fmt($0) }.count }

    var body: some View {
        PCard(n: "02", cat: "Guardrails", right: dirty > 0 ? AnyView(M("\(dirty) changed", 9, 0.12, PG_DOWN).padding(.horizontal, 9).padding(.vertical, 5).background(Capsule().fill(PG_DOWN.opacity(0.16)))) : nil) {
            M("Blocks a strike", 9.5, 0.18).padding(.top, 20)
            PKV(hard.map { k in
                let b = bite(k); let changed = planner.settings.fmt(k) != PlannerSettings.default.fmt(k)
                let sub: String? = b.map { k == binding ? "binding · blocks \($0.blocks)\($0.frees > 0 ? ", frees \($0.frees)" : "")" : ($0.blocks > 0 ? "blocks \($0.blocks)" : "blocks none") }
                return PKVRow(k: PlannerSettings.labels[k] ?? k, v: planner.settings.fmt(k), sub: sub, hue: changed ? PG_DOWN : nil, subHue: k == binding ? PG_DOWN : nil)
            })
            M("Changes the math", 9.5, 0.18).padding(.top, 22).padding(.top, 18)
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
            PKV(softRows())
            PMore(label: "Adjust") {
                VStack(spacing: 14) {
                    settingSeg("minNetDelta", PlannerSettings.deltaOpts, PlannerSettings.fmtDelta) { v in planner.setSetting { $0.minNetDelta = v } }
                    settingSeg("minExt", PlannerSettings.extOpts, PlannerSettings.fmtPct) { v in planner.setSetting { $0.minExt = v } }
                    settingSeg("edgeFloor", PlannerSettings.edgeOpts, PlannerSettings.fmtEdge) { v in planner.setSetting { $0.edgeFloor = v } }
                    settingSeg("weekendVol", PlannerSettings.weekendOpts, PlannerSettings.fmtWeekend) { v in planner.setSetting { $0.weekendVol = v } }
                    settingSegS("edgeLookback", PlannerSettings.lookbackOpts, PlannerSettings.fmtLookback) { v in planner.setSetting { $0.edgeLookback = v } }
                    settingSeg("rallyPct", PlannerSettings.rallyOpts, PlannerSettings.fmtPct) { v in planner.setSetting { $0.rallyPct = v } }
                    settingSeg("tiebreakBand", PlannerSettings.tiebreakOpts, PlannerSettings.fmtBias) { v in planner.setSetting { $0.tiebreakBand = v } }
                    HStack { M("Dot marks the default", 9.5, 0.1); Spacer(); Button { planner.resetSettings() } label: { M("Reset", 10, 0.14, dirty > 0 ? Ink.text : Ink.dim).padding(.horizontal, 15).frame(minHeight: 36).overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(Ink.hair, lineWidth: 1)) }.buttonStyle(.plain).disabled(dirty == 0) }.padding(.top, 4)
                }
            }
        }
    }
    private func softRows() -> [PKVRow] {
        [("weekendVol", PlannerSettings.fmtWeekend(planner.settings.weekendVol)), ("edgeLookback", PlannerSettings.fmtLookback(planner.settings.edgeLookback)),
         ("rallyPct", PlannerSettings.fmtPct(planner.settings.rallyPct)), ("tiebreakBand", "×" + PlannerSettings.fmtBias(planner.settings.tiebreakBand))].map { k, v in
            let labels = ["weekendVol": "Weekend vol coefficient", "edgeLookback": "Edge lookback", "rallyPct": "Rally pct for pairing", "tiebreakBand": "Tiebreak band"]
            let changed = planner.settings.fmt(k) != PlannerSettings.default.fmt(k)
            return PKVRow(k: labels[k] ?? k, v: v, hue: changed ? PG_DOWN : nil)
        }
    }
    private func settingLabel(_ k: String) -> String {
        ["minNetDelta": "Min net delta after", "minExt": "Min extrinsic %", "edgeFloor": "Edge floor · % of premium",
         "weekendVol": "Weekend vol coefficient", "edgeLookback": "Edge lookback", "rallyPct": "Rally pct for pairing", "tiebreakBand": "Tiebreak band"][k] ?? k
    }
    @ViewBuilder private func settingSeg(_ k: String, _ opts: [Double], _ fmt: @escaping (Double) -> String, _ pick: @escaping (Double) -> Void) -> some View {
        let cur: Double = ["minNetDelta": planner.settings.minNetDelta, "minExt": planner.settings.minExt, "edgeFloor": planner.settings.edgeFloor, "weekendVol": planner.settings.weekendVol, "rallyPct": planner.settings.rallyPct, "tiebreakBand": planner.settings.tiebreakBand][k] ?? 0
        let def: Double = ["minNetDelta": 500, "minExt": 0.25, "edgeFloor": -0.40, "weekendVol": 0.3, "rallyPct": 0.15, "tiebreakBand": 1.5][k] ?? 0
        VStack(alignment: .leading, spacing: 11) {
            HStack { M(settingLabel(k), 9.5, 0.14); Spacer(); N(fmt(cur), 15, cur == def ? Ink.text : PG_DOWN) }
            PSeg(opts: opts, cur: cur, def: def, fmt: fmt, pick: pick)
        }
    }
    @ViewBuilder private func settingSegS(_ k: String, _ opts: [String], _ fmt: @escaping (String) -> String, _ pick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack { M(settingLabel(k), 9.5, 0.14); Spacer(); N(fmt(planner.settings.edgeLookback), 15, planner.settings.edgeLookback == "hv30" ? Ink.text : PG_DOWN) }
            PSeg(opts: opts, cur: planner.settings.edgeLookback, def: "hv30", fmt: fmt, pick: pick)
        }
    }
}

// MARK: - 03 Upside room

struct UpsideCardV: View {
    @Bindable var planner: PlannerStore
    let d: PlannerDerived
    private var u: PlannerEngine.Upside { d.upside }
    private var dirty: Int {
        [(planner.settings.wRange, 0.30), (planner.settings.wAth, 0.30), (planner.settings.wRsi, 0.20), (planner.settings.wMa, 0.20)].filter { $0.0 != $0.1 }.count
    }
    var body: some View {
        PCard(n: "03", cat: "Upside room", right: AnyView(M(u.available ? "\(Int((u.score ?? 0).rounded())) / 100" : "off", 10, 0.14))) {
            if !u.available {
                PNote("Technicals unavailable — bias is off")
            } else {
                let sc = u.score ?? 0
                PHero("\(Int(sc.rounded()))", unit: AnyView(M("\(u.bandHead) · \(u.bandBias)", 10, 0.12)),
                      hue: sc < 30 ? PG_DOWN : sc >= 60 ? PG_UP : Ink.text)
                if let rp = u.rangePos, let lo = u.low52, let hi = u.high52 {
                    HStack(spacing: 11) {
                        M("52w range", 9.5, 0.14)
                        N("\(Int(rp.rounded()))", 15)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Ink.hair).frame(height: 3)
                                Circle().fill(Ink.text).frame(width: 10, height: 10).offset(x: min(g.size.width - 10, max(0, rp / 100 * g.size.width - 5)))
                            }.frame(height: 10)
                        }.frame(height: 10)
                        M("$\(Int(lo)) / $\(Int(hi))", 9.5, 0.06)
                    }.padding(.top, 20)
                }
                PKV(componentRows())
                if u.mixed { M("mixed signals · components disagree by \(Int(((([u.rangePos, u.athProx, u.rsiComp, u.maComp].compactMap { $0 }).max() ?? 0) - (([u.rangePos, u.athProx, u.rsiComp, u.maComp].compactMap { $0 }).min() ?? 0)).rounded())) pts", 10, 0.1, PG_DOWN).padding(.leading, 12).padding(.top, 16).overlay(alignment: .leading) { Rectangle().fill(PG_DOWN).frame(width: 2) } }
                if let cap = u.caption { M(cap, 10, 0.1).padding(.top, 12) }
                PMore(label: "Adjust weights" + (dirty > 0 ? " · \(dirty) changed" : "")) {
                    VStack(spacing: 14) {
                        wSeg("Range", planner.settings.wRange, 0.30) { v in planner.setSetting { $0.wRange = v } }
                        wSeg("Off ATH", planner.settings.wAth, 0.30) { v in planner.setSetting { $0.wAth = v } }
                        wSeg("RSI(14)", planner.settings.wRsi, 0.20) { v in planner.setSetting { $0.wRsi = v } }
                        wSeg("Vs 50/200d", planner.settings.wMa, 0.20) { v in planner.setSetting { $0.wMa = v } }
                        settingSeg("ATH full room", PlannerSettings.athRoomOpts, planner.settings.athFullRoom, 30, PlannerSettings.fmtRoom) { v in planner.setSetting { $0.athFullRoom = v } }
                        settingSeg("Bias max %", PlannerSettings.biasMaxOpts, planner.settings.biasMax, 2.5, PlannerSettings.fmtBias) { v in planner.setSetting { $0.biasMax = v } }
                        settingSeg("Bias span", PlannerSettings.biasSpanOpts, planner.settings.biasSpan, 3.5, PlannerSettings.fmtBias) { v in planner.setSetting { $0.biasSpan = v } }
                    }
                }
            }
        }
    }
    private func componentRows() -> [PKVRow] {
        var rows: [PKVRow] = []
        if let p = u.athProx { rows.append(PKVRow(k: "Off ATH", v: "\(Int(p.rounded()))", sub: u.pctOffAth.map { "\(Int($0.rounded()))% off · $\(Int(u.ath ?? 0)) \(u.athDate.map { "on " + shortDate($0) } ?? "")" })) }
        if let r = u.rsiComp { rows.append(PKVRow(k: "RSI(14)", v: "\(Int(r.rounded()))", sub: r < 30 ? "oversold" : r > 70 ? "overbought" : "neutral")) }
        if let m = u.maComp, let d50 = u.dev50, let d200 = u.dev200 { rows.append(PKVRow(k: "Vs 50/200d", v: "\(Int(m.rounded()))", sub: "\(pgPct(d50)) / \(pgPct(d200))", hue: nil)) }
        return rows
    }
    private func shortDate(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return iso }
        let mon = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(mon[p[1]]) \(p[2])"
    }
    @ViewBuilder private func wSeg(_ label: String, _ cur: Double, _ def: Double, _ pick: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack { M(label, 9.5, 0.14); Spacer(); N("\(Int((cur * 100).rounded()))%", 15, cur == def ? Ink.text : PG_DOWN) }
            PSeg(opts: PlannerSettings.weightOpts, cur: cur, def: def, fmt: { "\(Int($0 * 100))%" }, pick: pick)
        }
    }
    @ViewBuilder private func settingSeg(_ label: String, _ opts: [Double], _ cur: Double, _ def: Double, _ fmt: @escaping (Double) -> String, _ pick: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack { M(label, 9.5, 0.14); Spacer(); N(fmt(cur), 15, cur == def ? Ink.text : PG_DOWN) }
            PSeg(opts: opts, cur: cur, def: def, fmt: fmt, pick: pick)
        }
    }
}

// MARK: - 04 How many

struct SizeCardV: View {
    @Bindable var planner: PlannerStore
    let d: PlannerDerived
    var body: some View {
        let maxCt = max(1, d.book.capacity)
        let presets = Array(Set([1, max(1, Int((maxCt / 4).rounded())), max(2, Int((maxCt / 2).rounded())), Int(maxCt)])).sorted()
        return PCard(n: "04", cat: "How many", right: AnyView(M("max \(Int(maxCt)) ct · \(grp(d.book.freeShares)) sh free", 10, 0.14))) {
            HStack {
                stepBtn("−") { planner.ct = max(1, planner.ct - 1) }
                Spacer(minLength: 0)
                VStack(spacing: 8) { N("\(Int(planner.ct))", 40, Ink.text); M("contracts", 9.5, 0.16) }
                Spacer(minLength: 0)
                stepBtn("+") { planner.ct = min(maxCt, planner.ct + 1) }
            }.padding(.top, 20)
            HStack(spacing: 0) {
                ForEach(Array(presets.enumerated()), id: \.offset) { i, v in
                    let on = planner.ct == Double(v)
                    Button { planner.ct = Double(v) } label: {
                        M(v == Int(maxCt) ? "all \(v)" : "\(v)", 12, -0.01, on ? Ink.invertText : Ink.dim, upper: false)
                            .frame(maxWidth: .infinity, minHeight: 42).background(on ? Ink.invertBg : .clear)
                            .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(Ink.hair).frame(width: 1) } }
                    }.buttonStyle(.plain)
                }
            }.overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(Ink.hair, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: Ink.radiusElement)).padding(.top, 18)
            if let r = d.selRung {
                HStack(alignment: .top, spacing: 0) {
                    quadCell("credit", pgUsd(PlannerEngine.credit(r, ct: planner.ct)), PG_UP)
                    quadCell("committed", "\(grp(planner.ct * 100)) sh", Ink.text)
                    quadCell("net Δ after", (d.netDeltaAfter(r) >= 0 ? "+" : "−") + grp(abs(d.netDeltaAfter(r))), d.netDeltaAfter(r) < 0 ? PG_DOWN : Ink.text)
                }.padding(.top, 20)
            }
        }
    }
    private func stepBtn(_ s: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) { Text(s).font(InkFont.mono(22)).foregroundStyle(Ink.text).frame(width: 54, height: 54).overlay(Circle().strokeBorder(Ink.hair, lineWidth: 1)) }.buttonStyle(.plain)
    }
    private func quadCell(_ k: String, _ v: String, _ hue: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) { M(k, 9.5, 0.14); N(v, 18, hue) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 05 Which expiry

struct ExpiryCardV: View {
    @Bindable var planner: PlannerStore
    let d: PlannerDerived
    var body: some View {
        let ref = planner.state?.refStrike ?? 0
        let rows = (planner.state?.expiries ?? []).map { e -> (PExpiry, Double, Double, Double, Bool) in
            let r = e.chain.min { abs($0.strike - ref) < abs($1.strike - ref) }
            let prem = r?.prem ?? 0
            return (e, prem, prem / Double(max(e.td, 1)), prem * 100 * d.book.capacity, prem < 0.05)
        }
        let best = rows.max { $0.2 < $1.2 }?.0.iso
        return PCard(n: "05", cat: "Which expiry", right: AnyView(M("priced at \(nvS(ref))", 10, 0.14))) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(rows, id: \.0.iso) { e, prem, perDay, credit, thin in
                        POpt(on: planner.selExpiry == e.iso || (planner.selExpiry == nil && e.iso == planner.state?.expiries.first?.iso && false), off: thin,
                             v: e.label, sub: "\(e.dow.lowercased()) · \(e.td) td", sub2: "$\(f2(perDay)) a day", sub3: "\(pgUsd(credit)) credit",
                             note: "\(e.td) td + \(e.we) we", tag: e.iso == best ? "most a day" : (thin ? "too thin" : nil), tagOut: e.iso == best) {
                            planner.selExpiry = e.iso; planner.selStrike = nil
                        }
                    }
                }.padding(.top, 18)
            }
            if let a = d.expiry {
                PFigs([PFigItem(k: "Trading days", v: "\(a.td)"), PFigItem(k: "Weekends", v: "\(a.we)"), PFigItem(k: "Vol days", v: f1(a.volDays))])
            } else { PNote("Pick an expiry") }
        }
    }
}

// MARK: - 06 Which strike + Levels

struct StrikeCardV: View {
    @Bindable var planner: PlannerStore
    let d: PlannerDerived
    var body: some View {
        let e = d.expiry
        return PCard(n: "06", cat: "Which strike", right: AnyView(M("\(e?.label ?? "") · \(e?.td ?? 0) td", 10, 0.14))) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(d.chain) { strikeOpt($0) } }.padding(.top, 18)
            }
            levelsPanel.padding(.top, 20)
            if let r = d.selRung {
                PFigs([PFigItem(k: "Extrinsic", v: "\(Int((r.extPct * 100).rounded()))%", sub: "$\(f2(r.ext)) of $\(f2(r.prem))", hue: r.extPct < d.settings.minExt ? PG_DOWN : Ink.text),
                       PFigItem(k: "Assign", v: "\(Int((r.assign * 100).rounded()))%"),
                       PFigItem(k: "Edge", v: pgSigned(r.edge, 0), hue: r.edge < 0 ? PG_DOWN : PG_UP)])
                let fails = d.failing(r)
                if !fails.isEmpty { M("Fails \(fails.map { PlannerEngine.guardLabel($0) }.joined(separator: ", "))", 10.5, 0.1, PG_DOWN).padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: Ink.radiusElement).fill(PG_DOWN.opacity(0.12))).padding(.top, 16) }
            } else { PNote("Pick a strike") }
        }
    }

    private func strikeOpt(_ r: PRung) -> some View {
        let on = d.selStrike.map { abs($0 - r.strike) < 1e-6 } ?? false
        let off = !d.passes(r)
        let isPick = !d.pick.none && (d.pick.strike.map { abs($0 - r.strike) < 1e-6 } ?? false)
        let onTarget = d.isOnTarget(r.strike)
        let clears = d.cleared(r); let total = d.levels.count
        let pair = d.pairing(r)
        let fg: (Color) -> Color = { on ? Ink.invertText : $0 }
        return Button { planner.selStrike = r.strike } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    N(nvS(r.strike), 19, fg(Ink.text))
                    if isPick { tag("best pick", out: true, on: on) } else if onTarget { tag("on target", out: true, on: on) }
                }
                M(pgPct((r.strike - d.spot) / d.spot * 100) + " from spot", 9, 0.08, fg(Ink.dim))
                Text("ext \(Int((r.extPct * 100).rounded()))%").font(InkFont.mono(12)).foregroundStyle(r.extPct < d.settings.minExt ? PG_DOWN : fg(Ink.text))
                M("\(pgUsd(PlannerEngine.credit(r, ct: d.ct))) · \(Int((r.assign * 100).rounded()))% assign", 9, 0.08, fg(Ink.dim))
                M("clears \(clears) of \(total)", 8.5, 0.1, clears == total ? PG_UP : fg(Ink.dim))
                if let p = pair { M("\(Int(p.pairedCt)) ct paired · \(pgMoney(p.netAtRally)) at +\(Int((d.settings.rallyPct * 100).rounded()))%", 8.5, 0.1, fg(Ink.dim)) }
                if off { M("blocked · \(d.failing(r).first.map { PlannerEngine.guardRead($0, r, d.book, ct: d.ct) } ?? "")", 8.5, 0.1, fg(Ink.dim)) }
            }
            .frame(minWidth: 150, alignment: .leading)
            .padding(EdgeInsets(top: 18, leading: 16, bottom: 19, trailing: 16))
            .background(RoundedRectangle(cornerRadius: Ink.radiusElement).fill(on ? Ink.invertBg : .clear))
            .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(on ? Ink.invertBg : Ink.hair, lineWidth: 1))
            .opacity(off && !on ? 0.42 : 1)
        }.buttonStyle(.plain)
    }
    private func tag(_ s: String, out: Bool, on: Bool) -> some View {
        M(s, 8.5, 0.12, on ? Ink.invertText : Ink.text).padding(.horizontal, 7).padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(on ? Ink.invertText : Ink.text, lineWidth: 1))
    }

    // §4.2 Levels sub-panel
    private var levelsPanel: some View {
        let effSale = d.selRung.map { d.effSale($0) }
        return VStack(alignment: .leading, spacing: 0) {
            M("Levels", 9.5, 0.18).padding(.bottom, 10)
            VStack(spacing: 0) {
                if let es = effSale, let r = d.selRung {
                    levelRow(price: es, label: "eff sale · \(nvS(r.strike))", highlight: true, muted: false)
                }
                ForEach(d.levels.sorted { $0.price > $1.price }) { lv in
                    let muted = effSale.map { lv.price > $0 } ?? false
                    levelRow(price: lv.price, label: lv.label, highlight: lv.type == "spot", muted: muted)
                }
            }
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard).strokeBorder(Ink.hair, lineWidth: 1))
    }
    private func levelRow(price: Double, label: String, highlight: Bool, muted: Bool) -> some View {
        HStack(spacing: 12) {
            N("$\(f2(price))", 12, highlight ? Ink.text : (muted ? Ink.dim : Ink.text)).frame(width: 68, alignment: .leading)
            Rectangle().fill(highlight ? Ink.text : Ink.hair).frame(height: 1).frame(width: 24)
            M(label, 8.5, 0.1, highlight ? Ink.text : (muted ? Ink.dim.opacity(0.6) : Ink.dim))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .opacity(muted ? 0.6 : 1)
    }
}

// MARK: - 07 What happens next

struct OutlookCardV: View {
    @Bindable var planner: PlannerStore
    let d: PlannerDerived
    private let shown: [Double] = [-5, -3, -1, 0, 1, 3, 5]
    private let whenLabels = ["expiry": "at expiry", "half": "halfway", "t1": "tomorrow"]

    var body: some View {
        guard let r = d.selRung, let e = d.expiry else {
            return AnyView(PCard(n: "07", cat: "What happens next", dim: true) { PNote("Pick a strike to model the outcomes") })
        }
        let co = (down: 1.05, up: -0.62)
        let T2: Double = planner.when == "expiry" ? 0 : planner.when == "half" ? e.T / 2 : max(e.volDays - 1, 0.25) / 252
        func ivAt(_ s: Double) -> Double { max(8, d.gate.iv + (s < d.spot ? (d.spot - s) / d.spot * 100 * co.down : (s - d.spot) / d.spot * 100 * co.up)) }
        func diffAt(_ s: Double) -> Double { (r.prem - PlannerEngine.bsCall(s, r.strike, T2, ivAt(s) / 100)) * 100 * d.ct }
        let rows = shown.map { p -> (Double, Double, Double, Double) in let s = d.spot * (1 + p / 100); return (p, s, ivAt(s), diffAt(s)) }
        var cross: Double? = nil
        var sx = d.spot * 0.9; while sx <= d.spot * 1.25 { if diffAt(sx) < 0 { cross = sx; break }; sx += 0.05 }
        let maxAbs = max(rows.map { abs($0.3) }.max() ?? 1, 1)
        let worst = rows.last?.3 ?? 0

        return AnyView(PCard(n: "07", cat: "What happens next", right: AnyView(M("\(nvS(r.strike)) C · \(Int(d.ct)) ct", 10, 0.14))) {
            PSeg(opts: ["expiry", "half", "t1"], cur: planner.when, fmt: { whenLabels[$0] ?? $0 }, pick: { planner.when = $0 }).padding(.top, 18)
            VStack(alignment: .leading, spacing: 9) {
                N(cross == nil ? "The sale wins at every price shown" : "Better off up to $\(f2(cross!))", 17)
                Text(cross == nil ? "the credit covers the capped upside across the range" : "that is \(pgPct((cross! / d.spot - 1) * 100)) from spot. Above it the cap costs more than the credit.")
                    .font(InkFont.display(12.5, .light)).foregroundStyle(Ink.dim).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: Ink.radiusElement).fill(Ink.text.opacity(0.06))).padding(.top, 20)
            VStack(spacing: 0) {
                ForEach(rows, id: \.0) { p, s, iv, diff in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(p > 0 ? "+" : p < 0 ? "−" : "±")\(Int(abs(p)))%").font(InkFont.mono(16)).tracking(16 * -0.03).foregroundStyle(p == 0 ? Ink.dim : Ink.text)
                            M("$\(Int(s))\(planner.when == "expiry" ? "" : " · iv \(Int(iv))")", 9.5, -0.01, Ink.dim, upper: false)
                        }.frame(width: 84, alignment: .leading)
                        GeometryReader { g in
                            ZStack {
                                Rectangle().fill(Ink.hair).frame(width: 1).frame(maxWidth: .infinity, alignment: .center)
                                if diff >= 0 { Capsule().fill(PG_UP).frame(width: abs(diff) / maxAbs * g.size.width / 2, height: 8).offset(x: abs(diff) / maxAbs * g.size.width / 4) }
                                else { Capsule().fill(PG_DOWN).frame(width: abs(diff) / maxAbs * g.size.width / 2, height: 8).offset(x: -abs(diff) / maxAbs * g.size.width / 4) }
                            }
                        }.frame(height: 20)
                        N((diff >= 0 ? "+" : "−") + "$" + grp(abs(diff)), 14, diff < 0 ? PG_DOWN : PG_UP).frame(width: 82, alignment: .trailing)
                    }
                    .padding(.vertical, 11)
                    .background(p == 0 ? Ink.text.opacity(0.05) : .clear)
                    .overlay(alignment: .bottom) { Rectangle().fill(Ink.hair).frame(height: 1) }
                }
            }.padding(.top, 16)
            HStack { M("participation given up at +\(Int(abs(shown.last ?? 5)))%", 10, 0.14); Spacer(); N(pgUsd(abs(worst)), 16, worst < 0 ? PG_DOWN : Ink.text) }.padding(.top, 16)
            HStack { Spacer(); M("iv response · nvda 2y regression\(planner.when == "expiry" ? " · settles at intrinsic" : "")", 9.5, 0.1) }.padding(.top, 12)
        })
    }
}

// MARK: - 08 The plan

struct PlanCardV: View {
    let d: PlannerDerived
    var body: some View {
        guard let r = d.selRung, let e = d.expiry else {
            return AnyView(PCard(n: "08", cat: "The plan", dim: true) { PNote("Pick a strike and an expiry to build the plan") })
        }
        let credit = PlannerEngine.credit(r, ct: d.ct)
        let bleed = d.book.longTheta > 0 ? credit / d.book.longTheta : 0
        let signals = PlannerEngine.signals(r, d.settings, d.book, ct: d.ct, blocked: d.gate.blocked, histAssign: d.histAssign)
        let bad = signals.filter { !$0.ok }.count
        let clears = d.cleared(r); let pair = d.pairing(r)
        let wallStrike = d.legsOrEmpty.longCalls.first.map { nvS($0.strike) } ?? "—"
        let ticket = "SELL \(Int(d.ct)) NVDA \(e.label) \(nvS(r.strike)) C LMT \(f2(r.prem))"
        let dimC = Ink.invertText.opacity(0.74)
        return AnyView(PCard(n: "08", cat: "The plan", tint: true) {
            VStack(alignment: .leading, spacing: 11) {
                N("\(e.label) · \(nvS(r.strike)) C · \(Int(d.ct)) ct", 20, Ink.invertText)
                InkRoll(text: pgUsd(credit), font: InkFont.mono(34, .light), color: PG_UP)
                M(r.intrinsic > 0.005 ? "$\(grp(r.ext * 100 * d.ct)) ext · $\(grp(r.intrinsic * 100 * d.ct)) int" : "all extrinsic · credit at mid", 9.5, 0.16, dimC)
            }.padding(.top, 20)
            HStack(spacing: 10) {
                HStack(spacing: 3) { ForEach(Array(signals.enumerated()), id: \.offset) { _, s in Circle().fill(s.ok ? dimC.opacity(0.55) : PG_DOWN).frame(width: 7, height: 7) } }
                M("\(bad) of \(signals.count) signals negative", 10.5, 0.1, bad > signals.count / 2 ? PG_DOWN : Ink.invertText)
            }.padding(.top, 18)
            M(ticket, 10, 0.06, dimC).lineLimit(1).padding(.top, 12)
            PKV([
                PKVRow(k: "Covers option bleed", v: "\(f1(bleed)) days", sub: "$\(grp(d.book.longTheta)) a day", hue: bleed >= 1 ? PG_UP : PG_DOWN),
                PKVRow(k: "Assignment", v: "\(Int((r.assign * 100).rounded()))% vs your \(Int((d.histAssign * 100).rounded()))%", hue: r.assign > d.histAssign * 1.5 ? PG_DOWN : nil),
                PKVRow(k: "Net Δ after", v: (d.netDeltaAfter(r) >= 0 ? "+" : "−") + grp(abs(d.netDeltaAfter(r))), sub: "\(Int((PlannerEngine.pctLong(r, d.book, ct: d.ct) * 100).rounded()))% long", hue: d.netDeltaAfter(r) < 0 ? PG_DOWN : nil),
                PKVRow(k: "Edge", v: pgSigned(r.edge, 0), sub: "\(r.edgeHi >= 0 ? "+" : "−")\(Int(abs(r.edgeHi)))  to \(r.edgeLo >= 0 ? "+" : "−")\(Int(abs(r.edgeLo))) across lookbacks", hue: r.edge < 0 ? PG_DOWN : PG_UP, subCross: r.edgeCrosses),
                PKVRow(k: "Clears", v: "\(clears) of \(d.levels.count) levels", sub: d.levels.filter { $0.price <= d.effSale(r) }.compactMap { levelShort($0.type) }.joined(separator: ", ")),
                PKVRow(k: "Paired", v: pair.map { "\(Int($0.pairedCt)) ct vs \(Int($0.adverseCt + $0.favorableCt)) long at \(wallStrike)" } ?? "—", sub: pair.map { "\(pgMoney($0.netAtRally)) at +\(Int((d.settings.rallyPct * 100).rounded()))%" }, hue: nil, subHue: (pair?.netAtRally ?? 0) < 0 ? PG_DOWN : nil),
            ], tint: true)
        })
    }
    private func levelShort(_ type: String) -> String? {
        ["buyavg": "buy avg", "basis": "adj basis", "long": "long calls", "short": "short calls", "spot": "spot"][type]
    }
}


