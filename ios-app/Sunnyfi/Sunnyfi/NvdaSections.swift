//
//  NvdaSections.swift
//  Sunnyfi — Ink rebuild · Sections 2–5
//
//  Section 2 · How it has performed   (profit + 4 sleeve cards, EOD/delayed)
//  Section 3 · Insights               (volatility gauge + protection)
//  Section 4 · Peers & ETFs           (5-session tape cards)
//  Section 5 · Historical performance (per-session gains/losses by source)
//
//  Each screen composes the same Ink primitives as Section 1 and reads its
//  memoised model off NvdaStore. Data that only accrues at the close (peers'
//  5-session tape, the history chart, realised vol) renders an honest
//  "building history" state until the EOD cron has enough sessions.
//

import SwiftUI
import UIKit

// MARK: - shared formatting

private func nv2Int(_ v: Double) -> String { Int(v.rounded()).formatted(.number.grouping(.automatic)) }
private func nv2Signed(_ v: Double) -> String { (v > 0 ? "+" : v < 0 ? "−" : "") + nv2Int(abs(v)) }
private func nv2Dec(_ v: Double, _ d: Int) -> String { String(format: "%.\(d)f", v) }
private func nv2Money(_ v: Double) -> String { (v >= 0 ? "+" : "−") + inkUsd(abs(v)) }
private func nv2Pct(_ v: Double, _ d: Int = 1) -> String { (v >= 0 ? "+" : "−") + nv2Dec(abs(v), d) + "%" }

private func stamp2(_ f: NvFresh) -> InkStamp.FreshState {
    switch f { case .live: return .live; case .delayed: return .delayed; case .stale: return .stale }
}

/// A compact card's loud number (Hero is fixed at 44; sleeves want ~34).
private struct NvCompactHero: View {
    let value: String
    var unit: String? = nil
    var size: CGFloat = 34
    var color: Color = Ink.text
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InkRoll(text: value, font: InkFont.mono(size, .medium), tracking: size * -0.03, color: color)
            if let unit {
                Text(unit.uppercased()).font(InkFont.mono(9)).tracking(9 * 0.16)
                    .foregroundStyle(Ink.dim).padding(.top, 10)
            }
        }
        .padding(.top, 18)
    }
}

/// Two signed figures in a compact foot (Realised · Unrealised, etc.).
private struct NvLedger2: View {
    let a: (k: String, v: Double); let b: (k: String, v: Double)
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            cell(a.k, a.v).padding(.trailing, 14)
            Rectangle().fill(Ink.hair).frame(width: 1)
            cell(b.k, b.v).padding(.leading, 14)
        }
    }
    private func cell(_ k: String, _ v: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(k.uppercased()).font(InkFont.mono(8.5)).tracking(8.5 * 0.14).foregroundStyle(Ink.dim)
            InkDelta(value: inkUsd(abs(v)), good: abs(v) < 0.5 ? nil : v > 0, size: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func nvQuiet(_ title: String, _ body: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title.uppercased()).font(InkFont.mono(10)).tracking(10 * 0.16).foregroundStyle(Ink.dim)
        Text(body).font(InkFont.display(13, .light)).foregroundStyle(Ink.dim)
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 40)
}

// MARK: - Section 2 · How it has performed

struct NvdaPerformanceScreen: View {
    let store: NvdaStore

    var body: some View {
        if let p = store.perf {
            VStack(alignment: .leading, spacing: 0) {
                InkSectionHead(title: "How it has performed", count: "\(p.sleeves.filter { !$0.empty }.count + 1) cards")
                rail(p)
            }
        } else if !store.isLoading {
            nvQuiet("Performance", store.lastError ?? "Waiting for the end-of-day book.")
        }
    }

    private func rail(_ p: NvPerf) -> some View {
        // Empty sleeves (e.g. Puts sold with no short puts) are hidden entirely.
        let sleeves = p.sleeves.filter { !$0.empty }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                profitCard(p).inkEntrance(0)
                ForEach(Array(sleeves.enumerated()), id: \.element.id) { i, s in
                    sleeveCard(s).inkEntrance(min(i + 1, 4))
                }
            }
            .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 8)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
    }

    // Glossary: REALIZED is the hero (closed only); PREMIUM/COST are breakdowns;
    // NET (= realized + unrealized) in the foot. See PNL_GLOSSARY.md.
    private func profitCard(_ p: NvPerf) -> some View {
        let g = store.pnl
        let realized = g?.realized ?? p.realized
        return InkCard(compact: true, height: 236, stamp: (.delayed, "End of day · booked at close")) {
            InkBody(compact: true) {
                InkEyebrow(n: "01", cat: "Realized") { InkBand(skin: .mod, text: "Closed") }
                InkRoll(text: inkUsd(realized), font: InkFont.mono(38, .medium), tracking: 38 * -0.04,
                        color: realized >= 0 ? Ink.text : Ink.loss)
                    .padding(.top, 22)
                InkSpacer()
            }
            InkFoot(compact: true) {
                // New average = cost basis − premium collected per share (the effective
                // basis). Cushion (spot over it) + % move to the right, above the %.
                Text("New average · after premium".uppercased()).font(InkFont.mono(9)).tracking(9 * 0.16).foregroundStyle(Ink.dim)
                HStack(alignment: .firstTextBaseline) {
                    Text("$\(nv2Dec(p.breakEven, 2))").font(InkFont.mono(24, .medium)).tracking(24 * -0.03).foregroundStyle(Ink.text)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        InkDelta(value: "$\(nv2Dec(abs(p.cushion), 2))", good: p.cushion >= 0, size: 13)
                        Text("\(nv2Pct(p.cushionPct))").font(InkFont.mono(11, .medium)).foregroundStyle(p.cushionPct >= 0 ? Ink.gain : Ink.loss)
                    }
                }
            }
        }
    }

    // Minimal sleeve card: name + qty pill + realized hero. Empty sleeves are
    // filtered out upstream, so only live sleeves render here.
    private func sleeveCard(_ s: NvPerfSleeve) -> some View {
        let realizedZero = abs(s.realized) < 1
        let unit = s.name == "Shares" ? "sh" : "ct"
        return InkCard(compact: true, height: 236, stamp: (.delayed, "End of day · booked at close")) {
            InkBody(compact: true) {
                InkEyebrow(cat: s.name, glyph: s.glyph) {
                    InkBand(skin: .mod, text: "\(s.total) \(unit)")
                }
                NvCompactHero(value: realizedZero ? "$0" : nv2Money(s.realized),
                              size: 34, color: realizedZero ? Ink.dim : Ink.signed(s.realized >= 0))
                InkSpacer()
            }
        }
    }
}

// MARK: - Section 3 · Insights (volatility + protection)

struct NvdaInsightsScreen: View {
    let store: NvdaStore

    var body: some View {
        if let ins = store.insights {
            let hasVega = ins.vega?.empty == false
            VStack(alignment: .leading, spacing: 0) {
                InkSectionHead(title: "Insights", count: "\(hasVega ? 3 : 2) cards")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        volatilityCard(ins.vol).inkEntrance(0)
                        protectionCard(ins.protection).inkEntrance(1)
                        if let vg = ins.vega, !vg.empty { VegaCardView(g: vg).inkEntrance(2) }
                    }
                    .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 8)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !store.isLoading {
            nvQuiet("Insights", "Waiting for live marks.")
        }
    }

    // 01 · Volatility — hero is the SELLER SCORE gauge (IV/HV30 × IV-percentile factor)
    private func zoneTint(_ v: NvVol) -> Color {
        if v.building { return Ink.dim }
        switch NvSellZone.tintName(v.score) {
        case "gain": return Ink.gain; case "delayed": return Ink.delayed; case "loss": return Ink.loss; default: return Ink.dim
        }
    }
    private func volatilityCard(_ v: NvVol) -> some View {
        let tint = zoneTint(v)
        return InkCard(compact: true, height: 452, stamp: (.delayed, v.building ? "Building · IV feed pending" : "Updated · every 30 min")) {
            InkBody(compact: true) {
                InkEyebrow(n: "01", cat: "Volatility") {
                    InkBand(skin: v.building ? .low : .hue(tint), text: v.building ? "Building" : v.verdict)
                }
                InkGauge(value: v.building ? 0 : v.score, range: 0.80...1.30, decimals: 2, tint: tint)
                    .frame(maxWidth: .infinity).padding(.top, 14)
                gaugeCaption(v.building ? "Seller score · IV feed pending" : "Seller score · \(v.verdict) · sell")
                InkBand3(items: [
                    ("IV", pctStr(v.iv)),
                    ("HV30", pctStr(v.hv30)),
                    ("IV %ile", v.ivr.map { "\(Int($0.rounded()))" } ?? "—"),
                ])
                InkBullets(items: v.building
                    ? ["Implied vol streams from the option chain — not live yet",
                       "Realised \(pctStr(v.hv30)) over the last month"]
                    : ["Implied \(pctStr(v.iv)) vs realised \(pctStr(v.hv30))",
                       v.ivr != nil
                          ? "IV in the \(Int((v.ivr ?? 0).rounded()))th %ile → ×\(nv2Dec(v.factor ?? 1, 1)) factor"
                          : "Percentile builds as IV history accrues"])
                InkSpacer()
            }
            InkFoot(compact: true) {
                footLabel("Now · sell timing")
                Text(v.building ? "—" : v.verdict.capitalized)
                    .font(InkFont.mono(24, .medium)).tracking(24 * -0.02).foregroundStyle(tint)
                    .lineLimit(1).fixedSize()
                footNote(v.building
                    ? "Score turns on once implied vol is streaming from the chain."
                    : (v.spread.map { "IV \(nv2Dec(abs($0), 0)) pts \($0 >= 0 ? "over" : "under") realised · " } ?? "")
                        + (v.score >= 1.0
                            ? "options rich, favourable to sell calls."
                            : "options cheap — reduce or skip this cycle."))
            }
        }
    }

    // 02 · Protection — gauge is % of shares floored by puts
    private func protectionCard(_ p: NvProtection) -> some View {
        InkCard(compact: true, height: 452, stamp: (.delayed, "Updated 16:00 · next at close")) {
            InkBody(compact: true) {
                InkEyebrow(n: "02", cat: "Protection") {
                    InkBand(skin: p.empty ? .low : .mod, text: p.empty ? "Unhedged" : "\(p.putContracts) puts")
                }
                InkGauge(value: p.empty ? 0 : p.coveredPct, suffix: "%").frame(maxWidth: .infinity).padding(.top, 14)
                gaugeCaption("Shares floored by puts")
                InkBullets(items: p.empty
                    ? ["No long puts on the book", "\(nv2Int(p.shares)) sh carry full downside"]
                    : ["\(nv2Int(p.covered)) of \(nv2Int(p.shares)) sh have a floor",
                       "Strikes $\(nv2Dec(p.floorLow, 0))–$\(nv2Dec(p.floorHigh, 0)) · \(nv2Int(p.uncovered)) sh open"])
                InkSpacer()
            }
            InkFoot(compact: true, height: 132) {
                footLabel("Cushion · spot over break-even")
                InkDelta(value: "$" + nv2Dec(abs(p.cushion), 2), good: p.cushion >= 0, size: 24, weight: .medium)
                footNote("Spot sits \(nv2Dec(abs(p.cushionPct), 1))% \(p.cushion >= 0 ? "over" : "under") break-even — the puts floor the rest.")
            }
        }
    }

    private func gaugeCaption(_ s: String) -> some View {
        Text(s.uppercased()).font(InkFont.mono(9)).tracking(9 * 0.16)
            .foregroundStyle(Ink.dim).frame(maxWidth: .infinity, alignment: .center).padding(.top, 14)
    }
    private func footLabel(_ s: String) -> some View {
        Text(s.uppercased()).font(InkFont.mono(9)).tracking(9 * 0.16).foregroundStyle(Ink.dim)
    }
    private func footNote(_ s: String) -> some View {
        inkFig(s).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
    }
    private func pctStr(_ v: Double?) -> String { v.map { "\(Int($0.rounded()))%" } ?? "—" }
}

// MARK: - 03 · Vega (scrubbable IV impact)

private func nvVegaMoney(_ v: Double) -> String {
    (v >= 0 ? "+$" : "−$") + Int(abs(v).rounded()).formatted(.number.grouping(.automatic))
}

private struct VegaCardView: View {
    let g: NvVega
    @State private var iv: Double = -1                 // set to avg30 on appear
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let curIv = iv < 0 ? g.avg30 : iv
        let d = curIv - g.iv
        let total = g.net * d
        let flat = abs(d) < 0.05
        let maxImpact = max(g.legs.map { abs($0.v * d) }.max() ?? 1, 1)
        return InkCard(compact: true, height: 452, stamp: (.delayed, "Updated · streams with the chain")) {
            InkBody(compact: true) {
                InkEyebrow(n: "03", cat: "Vega") { InkBand(skin: .mod, text: g.stance) }

                // hero: what a move does · the coefficient
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(nvVegaMoney(total)).font(InkFont.mono(30, .medium)).tracking(30 * -0.04)
                            .foregroundStyle(flat ? Ink.dim : (total >= 0 ? Ink.gain : Ink.loss)).lineLimit(1)
                        Text((flat ? "IV unchanged" : "if IV \(d > 0 ? "rises to" : "falls to") \(nv2Dec(curIv, 1))%").uppercased())
                            .font(InkFont.mono(8.5)).tracking(8.5 * 0.14).foregroundStyle(Ink.dim).padding(.top, 9).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(nvVegaMoney(g.net)).font(InkFont.mono(15, .light)).tracking(15 * -0.03).foregroundStyle(Ink.text)
                        Text("PER IV POINT").font(InkFont.mono(7.5)).tracking(7.5 * 0.12).foregroundStyle(Ink.dim).padding(.top, 6).fixedSize()
                    }
                    .padding(.leading, 12).overlay(alignment: .leading) { Rectangle().fill(Ink.hair).frame(width: 1) }
                }
                .padding(.top, 16)

                // per-leg impact
                VStack(alignment: .leading, spacing: 3) {
                    Text("What each leg does".uppercased()).font(InkFont.mono(8.5)).tracking(8.5 * 0.16)
                        .foregroundStyle(Ink.dim).padding(.bottom, 5)
                    ForEach(g.legs) { leg in vegaLeg(leg, leg.v * d, maxImpact) }
                }
                .padding(.top, 13)
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1).padding(.top, -6) }
                InkSpacer()
            }
            InkFoot(compact: true) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Implied volatility".uppercased()).font(InkFont.mono(9)).tracking(9 * 0.16).foregroundStyle(Ink.dim)
                    Spacer()
                    Text("\(nv2Dec(curIv, 1))%").font(InkFont.mono(22, .medium)).tracking(22 * -0.03).foregroundStyle(Ink.text)
                }
                scrubber(curIv)
                inkFig("Now \(nv2Dec(g.iv, 1))% · 30-day average \(nv2Dec(g.avg30, 1))%"
                    + (g.daysToEarnings.map { " · earnings in \($0) days." } ?? "."))
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { if iv < 0 { iv = g.avg30 } }
    }

    private func vegaLeg(_ leg: NvVegaLeg, _ impact: Double, _ maxImpact: Double) -> some View {
        let pos = impact >= 0
        let c: Color = abs(impact) < 1 ? Ink.dim : (pos ? Ink.gain : Ink.loss)
        return HStack(spacing: 9) {
            Text(glyphFor(leg.kind, leg.side)).font(.system(size: 10)).foregroundStyle(Ink.dim).frame(width: 11, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(leg.name).font(InkFont.display(12.5, .light)).foregroundStyle(Ink.text)
                Text("\(leg.ct) ct").font(InkFont.mono(8)).tracking(8 * 0.1).foregroundStyle(Ink.text)
            }.frame(width: 104, alignment: .leading).lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.hair)
                    Capsule().fill(c).frame(width: min(geo.size.width, CGFloat(abs(impact) / maxImpact) * geo.size.width))
                }
            }.frame(height: 6)
            Text(nvVegaMoney(impact)).font(InkFont.mono(11.5)).foregroundStyle(c)
                .frame(width: 62, alignment: .trailing).lineLimit(1)
        }
        .frame(height: 26)
    }

    private func glyphFor(_ kind: String, _ side: String) -> String {
        kind == "call" ? (side == "short" ? "▲" : "△") : (side == "short" ? "▼" : "▽")
    }

    // Drag anywhere on the track; the two marks (now, 30-day avg) snap on tap.
    private func scrubber(_ curIv: Double) -> some View {
        let span = max(g.hi - g.lo, 0.01)
        return GeometryReader { geo in
            let W = geo.size.width
            let at: (Double) -> CGFloat = { CGFloat(($0 - g.lo) / span) * W }
            let up = curIv >= g.iv
            let a = min(at(g.iv), at(curIv)), b = max(at(g.iv), at(curIv))
            ZStack(alignment: .topLeading) {
                Capsule().fill(Ink.hair).frame(width: W, height: 6).offset(y: 8)
                Capsule().fill(up ? Ink.gain : Ink.loss).frame(width: max(0, b - a), height: 6).offset(x: a, y: 8)
                scrubTag("now", at(g.iv), strong: true) { setIv(g.iv) }
                scrubTag("30d avg", at(g.avg30), strong: false) { setIv(g.avg30) }
                Circle().fill(Ink.text).frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Ink.surface, lineWidth: 2))
                    .offset(x: at(curIv) - 6, y: 5)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { val in
                let frac = min(1, max(0, val.location.x / max(W, 1)))
                iv = (g.lo + frac * span).rounded()
            })
        }
        .frame(height: 52)
    }

    private func scrubTag(_ label: String, _ x: CGFloat, strong: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 5) {
                Rectangle().fill(strong ? Ink.text : Ink.dim).frame(width: 1, height: 7)
                Text(label.uppercased()).font(InkFont.mono(7.5)).tracking(7.5 * 0.1)
                    .foregroundStyle(strong ? Ink.text : Ink.dim).fixedSize()
            }
        }
        .buttonStyle(.plain)
        .offset(x: x - 20, y: 19).frame(width: 40)
    }

    private func setIv(_ v: Double) { withAnimation(reduce ? nil : InkMotion.ease(0.2)) { iv = v } }
}

// MARK: - Section 4 · Peers & ETFs

struct NvdaPeersScreen: View {
    let store: NvdaStore

    var body: some View {
        if let pe = store.peers, pe.tapes.contains(where: { $0.last != nil }) {
            let shares = store.position?.shares ?? 0
            VStack(alignment: .leading, spacing: 0) {
                InkSectionHead(title: "Peers & ETFs", count: "\(pe.tapes.count) cards")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(["self", "ETFs", "Peers"], id: \.self) { g in
                            let list = pe.tapes.filter { $0.group == g }
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 9) {
                                    Text((g == "self" ? "NVDA" : g).uppercased())
                                        .font(InkFont.mono(9.5)).tracking(9.5 * 0.2).foregroundStyle(Ink.dim)
                                    Text("\(list.count)").font(InkFont.mono(9.5)).tracking(9.5 * 0.1).foregroundStyle(Ink.text)
                                }
                                .frame(height: 20, alignment: .leading)
                                HStack(alignment: .top, spacing: 10) {
                                    ForEach(Array(list.enumerated()), id: \.element.id) { i, t in
                                        TapeCardView(t: t, n: peerIndex(pe.tapes, t), shares: shares, fresh: pe.fresh)
                                            .inkEntrance(min(i, 4))
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !store.isLoading {
            nvQuiet("Peers & ETFs", "Waiting for the tape.")
        }
    }

    private func peerIndex(_ all: [NvPeerTape], _ t: NvPeerTape) -> String {
        String(format: "%02d", (all.firstIndex(where: { $0.id == t.id }) ?? 0) + 1)
    }
}

/// One peer tape — big live price, a tappable 5-session dot strip, and a
/// sleeve/gap foot. Matches the design's TapeCard (compact, 392 tall).
private struct TapeCardView: View {
    let t: NvPeerTape
    let n: String
    let shares: Double
    let fresh: NvFresh
    @State private var day: Int? = nil

    var body: some View {
        let sel = day.flatMap { t.days.indices.contains($0) ? t.days[$0] : nil }
        let price = sel?.close ?? t.last
        let pct = sel?.pct ?? t.net
        let up = pct.map { $0 >= 0 }
        return InkCard(compact: true, height: 392, stamp: (stamp2(fresh), "Updated now · streaming")) {
            InkBody(compact: true) {
                InkEyebrow(n: n, cat: t.ticker) { InkBand(skin: .low, text: t.name) }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(price.map { "$" + nv2Dec($0, 2) } ?? "—")
                        .font(InkFont.mono(32, .medium)).tracking(32 * -0.04).foregroundStyle(Ink.text)
                    if let pct { InkDelta(value: nv2Dec(abs(pct), 1) + "%", good: up, size: 17) }
                }
                .padding(.top, 20)
                Text((sel.map { $0.label + " close" } ?? "Last · five sessions").uppercased())
                    .font(InkFont.mono(9.5)).tracking(9.5 * 0.16).foregroundStyle(Ink.dim).padding(.top, 10)
                InkSpacer()
                dotStrip
            }
            InkFoot(compact: true, height: 112) {
                if t.group == "self" {
                    footLine("Five sessions · your sleeve",
                             value: (t.net).map { inkUsd(abs(shares * (t.last ?? 0) * $0 / 100)) },
                             good: (t.net).map { $0 >= 0 }, trailing: "\(nv2Int(shares)) shares")
                } else {
                    footLine("Gap to NVDA",
                             value: t.vsNvda.map { nv2Dec(abs($0), 1) + " pts" },
                             good: t.vsNvda.map { $0 >= 0 },
                             trailing: (t.vsNvda.map { $0 >= 0 ? "ahead of you" : "behind you" }) ?? "")
                }
            }
        }
    }

    private var dotStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(t.days.prefix(5).enumerated()), id: \.element.id) { i, d in
                Button {
                    day = (day == i) ? nil : i
                } label: {
                    VStack(spacing: 10) {
                        Text(d.label.uppercased()).font(InkFont.mono(8)).tracking(8 * 0.1)
                            .foregroundStyle(Ink.dim).lineLimit(1)
                        Circle()
                            .fill(d.pct == 0 ? Color.clear : (d.pct < 0 ? Ink.loss : Ink.text))
                            .overlay { if d.pct == 0 { Circle().strokeBorder(Ink.dim, lineWidth: 1.5) } }
                            .frame(width: 9, height: 9)
                        Text((d.pct < 0 ? "−" : "+") + nv2Dec(abs(d.pct), 1))
                            .font(InkFont.mono(11, .medium)).foregroundStyle(d.pct < 0 ? Ink.loss : Ink.text)
                    }
                    .frame(maxWidth: .infinity)
                    .inkRelevance(day == nil || day == i ? .r1 : .r3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 18).padding(.bottom, 2)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
        .padding(.top, 14)
    }

    private func footLine(_ label: String, value: String?, good: Bool?, trailing: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.uppercased()).font(InkFont.mono(9)).tracking(9 * 0.16).foregroundStyle(Ink.dim)
            HStack(alignment: .firstTextBaseline) {
                if let value { InkDelta(value: value, good: good, size: 24, weight: .medium) }
                else { Text("—").font(InkFont.mono(24, .medium)).foregroundStyle(Ink.dim) }
                Spacer(minLength: 0)
                Text(trailing).font(InkFont.mono(10.5)).foregroundStyle(Ink.dim)
            }
        }
    }
}

// MARK: - Section 5 · Historical performance

struct NvdaHistoryScreen: View {
    let store: NvdaStore

    var body: some View {
        if let h = store.history, h.months.contains(where: { !$0.bars.isEmpty }) {
            VStack(alignment: .leading, spacing: 0) {
                InkSectionHead(title: "Historical performance")
                // Single card — render directly (no horizontal scroll) so its
                // internal month/source chip rails receive taps.
                HistoryCardView(h: h).inkEntrance(0)
                    .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !store.isLoading {
            VStack(alignment: .leading, spacing: 0) {
                InkSectionHead(title: "Historical performance", count: "Building")
                nvQuiet("History builds nightly",
                        "Each session's shares- and options-P&L is booked at the close. The chart fills in as the days accumulate.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The gains-up / losses-down chart, one bar per PERIOD — monthly or weekly.
/// Tap a bar to make it the hero; the top-three sources for that period read
/// below, and the foot carries the range total with its best and worst period.
private struct HistoryCardView: View {
    let h: NvHistory
    enum Mode: String, CaseIterable { case month, week }
    @State private var mode: Mode = .month
    @State private var pick: Int? = nil
    @State private var grow = false

    private struct Period: Identifiable {
        let id: String; let label: String; let sub: String; let n: Int; let net: Double; let vals: [String: Double]
    }

    private static let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }()
    private static let isoFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "America/New_York"); return f }()
    private static let monShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let monLong = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    private var sessions: [(date: Date, vals: [String: Double])] {
        h.months.flatMap { $0.bars }.filter { !$0.pending }
            .compactMap { b in Self.isoFmt.date(from: b.iso).map { ($0, b.vals) } }
            .sorted { $0.0 < $1.0 }
    }

    private func periods() -> [Period] {
        let cal = Self.cal
        var map: [String: Period] = [:]; var order: [String] = []
        for s in sessions {
            let key: String, label: String, sub: String
            if mode == .month {
                let c = cal.dateComponents([.year, .month], from: s.date)
                key = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 1)
                label = Self.monShort[(c.month ?? 1) - 1]
                sub = "\(Self.monLong[(c.month ?? 1) - 1]) \(c.year ?? 0)"
            } else {
                let back = (cal.component(.weekday, from: s.date) + 5) % 7        // days since Monday
                let mon = cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: s.date)) ?? s.date
                let c = cal.dateComponents([.month, .day], from: mon)
                key = Self.isoFmt.string(from: mon)
                label = "\(c.day ?? 0)"
                sub = "Week of \(Self.monShort[(c.month ?? 1) - 1]) \(c.day ?? 0)"
            }
            if map[key] == nil { order.append(key); map[key] = Period(id: key, label: label, sub: sub, n: 0, net: 0, vals: [:]) }
            let cur = map[key]!
            var vals = cur.vals; var net = cur.net
            for (k, v) in s.vals { vals[k, default: 0] += v; net += v }
            map[key] = Period(id: key, label: cur.label, sub: cur.sub, n: cur.n + 1, net: net, vals: vals)
        }
        let all = order.compactMap { map[$0] }
        return mode == .week ? Array(all.suffix(12)) : all
    }

    @ViewBuilder var body: some View {
        let ps = periods()
        if ps.isEmpty { EmptyView() } else { card(ps) }
    }

    private func card(_ ps: [Period]) -> some View {
        let idx = min(pick ?? ps.count - 1, ps.count - 1)
        let p = ps[idx]
        let peak = max(ps.map { abs($0.net) }.max() ?? 1, 1)
        let total = ps.reduce(0) { $0 + $1.net }
        let best = ps.max { $0.net < $1.net } ?? p
        let worst = ps.min { $0.net < $1.net } ?? p
        let parts = Array(p.vals.filter { $0.value != 0 }.sorted { abs($0.value) > abs($1.value) }.prefix(3))
        return InkCard(height: 560, stamp: (.delayed, "Updated 16:00 · next at close")) {
            InkBody {
                InkEyebrow(cat: "Gains & losses") { InkBand(skin: .mod, text: mode == .month ? "By month" : "By week") }
                toggle
                heroRow(p)
                chart(ps, idx: idx, peak: peak)
                InkSpacer()
                sourceRows(parts)
            }
            InkFoot { footView(total: total, best: best, worst: worst) }
        }
    }

    private var toggle: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases, id: \.self) { md in
                let on = mode == md
                Button { withAnimation(InkMotion.fast) { mode = md; pick = nil } } label: {
                    Text((md == .month ? "Monthly" : "Weekly").uppercased()).font(InkFont.mono(10.5, .medium)).tracking(10.5 * 0.07)
                        .foregroundStyle(on ? Ink.invertText : Ink.dim)
                        .frame(maxWidth: .infinity).frame(minHeight: 32)
                        .background(RoundedRectangle(cornerRadius: Ink.radiusElement, style: .continuous).fill(on ? Ink.invertBg : .clear))
                        .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement, style: .continuous).strokeBorder(on ? Ink.text : Ink.hair, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 14)
    }

    private func heroRow(_ p: Period) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                InkDelta(value: nv2Money(p.net), good: p.net >= 0, size: 40, weight: .medium)
                Text(p.sub.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.16).foregroundStyle(Ink.dim).padding(.top, 12).lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(p.n)").font(InkFont.mono(20)).tracking(20 * -0.03).foregroundStyle(Ink.text)
                Text("SESSIONS").font(InkFont.mono(8.5)).tracking(8.5 * 0.12).foregroundStyle(Ink.dim).padding(.top, 8)
            }
            .padding(.leading, 14).overlay(alignment: .leading) { Rectangle().fill(Ink.hair).frame(width: 1) }
        }
        .padding(.top, 18)
    }

    private func chart(_ ps: [Period], idx: Int, peak: Double) -> some View {
        let H: CGFloat = 48
        return VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(ps.enumerated()), id: \.element.id) { i, x in
                    let up = x.net >= 0
                    let hgt = max(2, CGFloat(abs(x.net) / peak) * H * (grow ? 1 : 0))
                    Button { pick = i } label: {
                        VStack(spacing: 0) {
                            VStack(spacing: 0) { Spacer(minLength: 0)
                                if up {
                                    Rectangle().fill(i == idx ? Ink.text : Ink.dim).frame(height: hgt)
                                        .clipShape(RoundedCorner(radius: 3, corners: [.topLeft, .topRight]))
                                }
                            }.frame(height: H)
                            VStack(spacing: 0) {
                                if !up {
                                    Rectangle().fill(Ink.loss).opacity(i == idx ? 1 : 0.55).frame(height: hgt)
                                        .clipShape(RoundedCorner(radius: 3, corners: [.bottomLeft, .bottomRight]))
                                }
                                Spacer(minLength: 0)
                            }.frame(height: H)
                        }
                        .frame(maxWidth: .infinity)
                        .inkRelevance(i == idx ? .r1 : .r3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay(alignment: .center) { Rectangle().fill(Ink.hair).frame(height: 1) }
            HStack(spacing: 3) {
                ForEach(Array(ps.enumerated()), id: \.element.id) { i, x in
                    Text(x.label).font(InkFont.mono(10)).foregroundStyle(i == idx ? Ink.text : Ink.dim)
                        .frame(maxWidth: .infinity).lineLimit(1).inkRelevance(i == idx ? .r1 : .r3)
                }
            }
        }
        .padding(.top, 18)
        .onAppear { withAnimation(InkMotion.ease(0.7).delay(0.1)) { grow = true } }
    }

    private func sourceRows(_ parts: [Dictionary<String, Double>.Element]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, e in
                let src = h.sources.first { $0.key == e.key }
                HStack(spacing: 10) {
                    Text(src?.glyph ?? "·").font(.system(size: 12)).foregroundStyle(Ink.dim)
                    Text(src?.label ?? e.key).font(InkFont.display(14, .regular)).foregroundStyle(Ink.text).lineLimit(1)
                    Spacer(minLength: 0)
                    Text((e.value >= 0 ? "+" : "−") + inkUsd(abs(e.value)))
                        .font(InkFont.mono(14.5)).tracking(14.5 * -0.02).foregroundStyle(e.value >= 0 ? Ink.text : Ink.loss)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Ink.hair).frame(height: 1) } }
            }
        }
        .padding(.top, 14)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
    }

    private func footView(total: Double, best: Period, worst: Period) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text((mode == .month ? "Year to date" : "Last 12 weeks").uppercased())
                    .font(InkFont.mono(9)).tracking(9 * 0.16).foregroundStyle(Ink.dim)
                Spacer()
                InkDelta(value: nv2Money(total), good: total >= 0, size: 20, weight: .medium)
            }
            HStack {
                Text("BEST \(best.label) \(nv2Money(best.net))").font(InkFont.mono(9)).tracking(9 * 0.1).foregroundStyle(Ink.dim)
                Spacer()
                Text("WORST \(worst.label) \(nv2Money(worst.net))").font(InkFont.mono(9)).tracking(9 * 0.1).foregroundStyle(Ink.dim)
            }
        }
    }
}

/// Rounded-corner clip for the history bars (top-only / bottom-only radii).
private struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}
