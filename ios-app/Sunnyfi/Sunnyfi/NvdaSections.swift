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
            InkRoll(text: value, font: InkFont.mono(size, .light), tracking: size * -0.03, color: color)
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
            cell(a.k, a.v)
            cell(b.k, b.v).overlay(alignment: .leading) { Rectangle().fill(Ink.hair).frame(width: 1) }.padding(.leading, 12)
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
                InkSectionHead(title: "How it has performed", count: "\(p.sleeves.count + 1) cards")
                rail(p)
            }
        } else if !store.isLoading {
            nvQuiet("Performance", store.lastError ?? "Waiting for the end-of-day book.")
        }
    }

    private func rail(_ p: NvPerf) -> some View {
        // empty sleeves drift to the back at r3
        let sleeves = p.sleeves.enumerated().sorted {
            ($0.element.empty ? 1 : 0, $0.offset) < ($1.element.empty ? 1 : 0, $1.offset)
        }.map { $0.element }
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

    private func profitCard(_ p: NvPerf) -> some View {
        InkCard(compact: true) {
            InkBody(compact: true) {
                InkEyebrow(n: "01", cat: "Profit made") { InkBand(skin: .mod, text: "Lifetime") }
                NvCompactHero(value: nv2Money(p.realized), unit: "realised · booked",
                              size: 34, color: Ink.signed(p.realized >= 0))
                InkBullets(items: [
                    "$\(nv2Dec(p.perShare, 2)) a share collected, calls only",
                    "Break-even now $\(nv2Dec(p.breakEven, 2))",
                ])
                InkSpacer()
                InkBand3(items: [
                    ("Collected", inkUsd(p.lifetime)),
                    ("Per share", "$" + nv2Dec(p.perShare, 2)),
                    ("Cushion", nv2Pct(p.cushionPct)),
                ])
            }
            InkFoot(compact: true) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("SPOT VS BREAK-EVEN").font(InkFont.mono(9)).tracking(9 * 0.16).foregroundStyle(Ink.dim)
                        InkDelta(value: "$" + nv2Dec(abs(p.cushion), 2), good: p.cushion >= 0, size: 24, weight: .light)
                    }
                    Spacer(minLength: 0)
                    Text("\(nv2Pct(p.cushionPct))").font(InkFont.mono(13)).foregroundStyle(Ink.signed(p.cushion >= 0))
                }
            }
            InkStamp(state: .delayed, text: "End of day · booked at close", compact: true)
        }
    }

    private func sleeveCard(_ s: NvPerfSleeve) -> some View {
        let sold = s.name.contains("sold")
        let net = s.realized + s.unrealized
        return InkCard(relevance: s.empty ? .r3 : .r1, spine: sold ? .short : .long, compact: true) {
            InkBody(compact: true) {
                InkEyebrow(cat: s.name, glyph: s.glyph) {
                    InkBand(skin: s.empty ? .low : .mod, text: s.empty ? "None open" : "\(s.total) ct")
                }
                if s.empty {
                    NvCompactHero(value: "—", unit: "nothing written", size: 34, color: Ink.dim)
                    InkBullets(items: ["No \(s.name.lowercased()) on the book"])
                    InkSpacer()
                } else {
                    NvCompactHero(value: nv2Money(net), unit: "\(s.name.lowercased()) · net",
                                  size: 34, color: Ink.signed(net >= 0))
                    InkBullets(items: ["\(s.basisLabel) \(inkUsd(s.basis)) across \(s.total) ct"])
                    InkSpacer()
                    InkBand3(items: [(s.basisLabel, inkUsd(s.basis)), ("Contracts", "\(s.total)")])
                }
            }
            InkFoot(compact: true) {
                if s.empty {
                    Text("Sleeve appears once a leg is written.")
                        .font(InkFont.display(12, .light)).foregroundStyle(Ink.dim)
                } else {
                    NvLedger2(a: ("Realised", s.realized), b: ("Unrealised", s.unrealized))
                }
            }
            InkStamp(state: .delayed, text: "End of day · booked at close", compact: true)
        }
    }
}

// MARK: - Section 3 · Insights (volatility + protection)

struct NvdaInsightsScreen: View {
    let store: NvdaStore

    var body: some View {
        if let ins = store.insights {
            VStack(alignment: .leading, spacing: 0) {
                InkSectionHead(title: "Insights", count: "2 reads")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        protectionCard(ins).inkEntrance(0)
                        volatilityCard(ins).inkEntrance(1)
                    }
                    .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 8)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
            }
        } else if !store.isLoading {
            nvQuiet("Insights", "Waiting for live marks.")
        }
    }

    private func protectionCard(_ ins: NvInsights) -> some View {
        let pr = ins.protection
        let covered = min(pr.coveredPct, 100)
        return InkCard {
            InkBody {
                InkEyebrow(n: "01", cat: "Downside protection", glyph: "▽") {
                    InkBand(skin: pr.empty ? .low : .mod, text: pr.empty ? "Unhedged" : "\(pr.putContracts) puts")
                }
                if pr.empty {
                    InkHero(value: "0%", unit: "of shares hedged")
                    InkBullets(items: ["No long puts on the book", "Shares carry full downside"])
                    InkSpacer()
                } else {
                    InkHero(value: "\(Int(covered.rounded()))%", unit: "of shares hedged · by delta")
                    InkBullets(items: [
                        "Floor near $\(nv2Dec(pr.floorHigh, 0)) · \(pr.putContracts) ct of puts",
                        "$\(nv2Dec(abs(pr.cushion), 2)) \(pr.cushion >= 0 ? "above" : "below") the top floor",
                    ])
                    InkSpacer()
                    InkBand3(items: [
                        ("Contracts", "\(pr.putContracts)"),
                        ("Top floor", "$" + nv2Dec(pr.floorHigh, 0)),
                        ("Covered", "\(Int(covered.rounded()))%"),
                    ])
                }
            }
            InkFoot {
                InkBars(leftK: "Shares", leftV: pr.shares, rightK: "Covered", rightV: pr.coveredShares,
                        hue: Ink.gain) {
                    InkDelta(value: "\(Int(covered.rounded()))%", good: covered >= 50, size: 17)
                }
            }
            InkStamp(state: stamp2(ins.fresh), text: freshText(ins.fresh))
        }
    }

    private func volatilityCard(_ ins: NvInsights) -> some View {
        let v = ins.vol
        let building = v.ratio == nil
        return InkCard {
            InkBody {
                InkEyebrow(n: "02", cat: "Volatility", glyph: "◇") {
                    InkBand(skin: bandSkin(v.verdict), text: v.verdict)
                }
                if let iv = v.iv {
                    InkHero(value: "\(Int((iv * 100).rounded()))%", unit: "implied · open legs")
                } else {
                    InkHero(value: "—", unit: "no live implied yet")
                }
                InkBullets(items: building
                    ? ["Realised vol needs ≥6 closes — \(v.sampleDays) so far",
                       "Reads settle once the tape fills in"]
                    : ["Implied \(pct(v.iv)) vs realised \(pct(v.hv30))",
                       "Options look \(v.verdict) to sell here"])
                InkSpacer()
                InkBand3(items: [
                    ("Implied", pct(v.iv)),
                    ("Realised", pct(v.hv30)),
                    ("Ratio", v.ratio.map { nv2Dec($0, 2) + "×" } ?? "—"),
                ])
            }
            InkFoot {
                if let iv = v.iv, let hv = v.hv30 {
                    InkBars(leftK: "Realised", leftV: hv * 100, rightK: "Implied", rightV: iv * 100,
                            hue: iv >= hv ? Ink.gain : Ink.loss) {
                        InkDelta(value: nv2Dec((v.ratio ?? 1), 2) + "×", good: iv >= hv, size: 17)
                    }
                } else {
                    Text("Volatility reads build as the daily closes accumulate.")
                        .font(InkFont.display(12.5, .light)).foregroundStyle(Ink.dim)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            InkStamp(state: building ? .stale : .delayed,
                     text: building ? "Building · \(v.sampleDays) sessions" : "End of day · realised vol")
        }
    }

    private func pct(_ v: Double?) -> String { v.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
    private func bandSkin(_ verdict: String) -> InkBand.Skin {
        switch verdict {
        case "rich":  return .hue(Ink.gain)
        case "cheap": return .hue(Ink.loss)
        case "fair":  return .mod
        default:      return .low
        }
    }
    private func freshText(_ f: NvFresh) -> String {
        switch f { case .live: return "Updated now · streaming"
        case .delayed: return "Updated recently"; case .stale: return "Stale · next at market open" }
    }
}

// MARK: - Section 4 · Peers & ETFs

struct NvdaPeersScreen: View {
    let store: NvdaStore

    var body: some View {
        if let pe = store.peers, pe.tapes.contains(where: { $0.last != nil }) {
            VStack(alignment: .leading, spacing: 0) {
                InkSectionHead(title: "Peers & ETFs", count: "\(pe.tapes.count) names")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(pe.tapes.enumerated()), id: \.element.id) { i, t in
                            tapeCard(t, fresh: pe.fresh).inkEntrance(min(i, 4))
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 8)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
            }
        } else if !store.isLoading {
            nvQuiet("Peers & ETFs", "Waiting for the tape.")
        }
    }

    private func tapeCard(_ t: NvPeerTape, fresh: NvFresh) -> some View {
        let hue = Ink.signed(t.good)
        let hasTape = t.closes.count >= 2
        return InkCard(relevance: t.ticker == "NVDA" ? .r1 : .r2, compact: true) {
            InkBody(compact: true) {
                InkEyebrow(cat: t.ticker) {
                    InkBand(skin: t.dayPct == nil ? .low : .hue(hue), text: t.dayPct.map { nv2Pct($0) } ?? "—")
                }
                NvCompactHero(value: t.last.map { "$" + nv2Dec($0, 2) } ?? "—", unit: "last", size: 32)
                if hasTape {
                    sparkline(t.closes, hue: hue).frame(height: 52).padding(.top, 18)
                } else {
                    Text("5-session tape builds after the close.")
                        .font(InkFont.display(12, .light)).foregroundStyle(Ink.dim)
                        .frame(height: 52, alignment: .leading).padding(.top, 18)
                }
                InkSpacer()
            }
            InkFoot(compact: true) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("5-SESSION").font(InkFont.mono(9)).tracking(9 * 0.16).foregroundStyle(Ink.dim)
                        InkDelta(value: t.windowPct.map { nv2Dec(abs($0), 1) + "%" } ?? "—",
                                 good: t.windowPct.map { $0 >= 0 }, size: 22, weight: .light)
                    }
                    Spacer(minLength: 0)
                    if t.closes.count >= 2 {
                        Text("$\(nv2Dec(t.closes.min() ?? 0, 0))–\(nv2Dec(t.closes.max() ?? 0, 0))")
                            .font(InkFont.mono(11)).foregroundStyle(Ink.dim)
                    }
                }
            }
            InkStamp(state: stamp2(fresh), text: t.ticker == "NVDA" ? "Streaming" : "Delayed 15 min", compact: true)
        }
    }

    private func sparkline(_ closes: [Double], hue: Color) -> some View {
        GeometryReader { g in
            let lo = closes.min() ?? 0, hi = closes.max() ?? 1
            let span = max(hi - lo, 0.0001)
            let pt: (Int, Double) -> CGPoint = { i, c in
                let x = closes.count <= 1 ? 0 : CGFloat(i) / CGFloat(closes.count - 1) * g.size.width
                let y = g.size.height - CGFloat((c - lo) / span) * (g.size.height - 4) - 2
                return CGPoint(x: x, y: y)
            }
            ZStack {
                Path { p in
                    for (i, c) in closes.enumerated() {
                        let q = pt(i, c)
                        if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
                    }
                }
                .stroke(hue, style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = closes.indices.last {
                    Circle().fill(hue).frame(width: 5, height: 5)
                        .position(pt(last, closes[last]))
                }
            }
        }
    }
}

// MARK: - Section 5 · Historical performance

struct NvdaHistoryScreen: View {
    let store: NvdaStore

    var body: some View {
        if let h = store.history, !h.bars.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                InkSectionHead(title: "Historical performance", count: "\(h.sessions) sessions")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) { chartCard(h).inkEntrance(0) }
                        .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 8)
                        .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
            }
        } else if !store.isLoading {
            VStack(alignment: .leading, spacing: 0) {
                InkSectionHead(title: "Gains and losses, by session", count: "Building")
                nvQuiet("History builds nightly",
                        "Each session's shares- and options-P&L is booked at the close. The chart fills in as the days accumulate.")
            }
        }
    }

    private func chartCard(_ h: NvHistory) -> some View {
        InkCard(height: 530) {
            InkBody {
                InkEyebrow(n: "01", cat: "Net by session") {
                    InkBand(skin: .hue(h.net >= 0 ? Ink.gain : Ink.loss), text: nv2Money(h.net))
                }
                InkHero(value: nv2Money(h.net), unit: "net across \(h.sessions) sessions")
                barChart(h).frame(height: 148).padding(.top, 22)
                InkSpacer()
                InkBand3(items: [
                    ("Best day", nv2Money(h.bestDay)),
                    ("Worst day", nv2Money(h.worstDay)),
                    ("Sessions", "\(h.sessions)"),
                ])
            }
            InkFoot {
                Text("Blue is a winning session, orange a losing one — shares and options combined.")
                    .font(InkFont.display(12.5, .light)).foregroundStyle(Ink.dim)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            InkStamp(state: .delayed, text: "End of day · per-session book")
        }
    }

    @State private var grow = false
    private func barChart(_ h: NvHistory) -> some View {
        let maxMag = max(h.bars.map { abs($0.total) }.max() ?? 1, 1)
        return GeometryReader { g in
            let n = max(h.bars.count, 1)
            let gap: CGFloat = 5
            let bw = max(3, (g.size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            let midY = g.size.height / 2
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Ink.hair).frame(height: 1).offset(y: midY)
                ForEach(Array(h.bars.enumerated()), id: \.element.id) { i, b in
                    let mag = CGFloat(abs(b.total) / maxMag) * (midY - 4) * (grow ? 1 : 0)
                    let up = b.total >= 0
                    Capsule()
                        .fill(up ? Ink.gain : Ink.loss)
                        .frame(width: bw, height: max(2, mag))
                        .position(x: CGFloat(i) * (bw + gap) + bw / 2,
                                  y: up ? midY - mag / 2 : midY + mag / 2)
                }
            }
            .onAppear { withAnimation(InkMotion.ease(0.9).delay(0.14)) { grow = true } }
        }
    }
}
