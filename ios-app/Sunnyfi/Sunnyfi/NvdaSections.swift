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

    // Glossary: REALIZED is the hero (closed only); PREMIUM/COST are breakdowns;
    // NET (= realized + unrealized) in the foot. See PNL_GLOSSARY.md.
    private func profitCard(_ p: NvPerf) -> some View {
        let g = store.pnl
        let realized = g?.realized ?? p.realized
        return InkCard(compact: true) {
            InkBody(compact: true) {
                InkEyebrow(n: "01", cat: "Realized") { InkBand(skin: .mod, text: "Closed") }
                VStack(alignment: .leading, spacing: 0) {
                    InkRoll(text: inkUsd(realized), font: InkFont.mono(38, .light), tracking: 38 * -0.04,
                            color: realized >= 0 ? Ink.text : Ink.loss)
                    Text("Realized · closed only".uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.16)
                        .foregroundStyle(Ink.dim).padding(.top, 11)
                }
                .padding(.top, 22)
                InkBullets(items: g.map { g in [
                    "Premium \(inkUsd(g.premiumTotal)) · \(inkUsd(g.premiumRealized)) realised, \(inkUsd(g.premiumUnrealized)) open",
                    "Hedge cost \(inkUsd(g.costTotal)) · break-even $\(nv2Dec(p.breakEven, 2))",
                ] } ?? [
                    "$\(nv2Dec(p.perShare, 2)) a share collected, calls only",
                    "Cost basis $\(nv2Dec(p.costBasis, 2)) → break-even $\(nv2Dec(p.breakEven, 2))",
                ])
                InkSpacer()
            }
            InkFoot(compact: true) {
                // New average = cost basis − premium collected per share (the effective
                // basis). Cushion (spot over it) + % move to the right, above the %.
                Text("New average · after premium".uppercased()).font(InkFont.mono(9)).tracking(9 * 0.16).foregroundStyle(Ink.dim)
                HStack(alignment: .firstTextBaseline) {
                    Text("$\(nv2Dec(p.breakEven, 2))").font(InkFont.mono(28, .light)).tracking(28 * -0.03).foregroundStyle(Ink.text)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 3) {
                        InkDelta(value: "$\(nv2Dec(abs(p.cushion), 2))", good: p.cushion >= 0, size: 14)
                        Text("\(nv2Pct(p.cushionPct))").font(InkFont.mono(11)).foregroundStyle(Ink.dim)
                    }
                }
            }
            InkStamp(state: .delayed, text: "End of day · booked at close", compact: true)
        }
    }

    private func sleeveCard(_ s: NvPerfSleeve) -> some View {
        // This section is REALIZED performance — the headline is realized only.
        // Open mark gains (e.g. unclosed long puts) are shown separately as
        // "Open · unrealised" so they never read as booked profit.
        let realizedZero = abs(s.realized) < 1
        let isShares = s.name == "Shares"
        let unit = isShares ? "sh" : "ct"
        let qtyLabel = isShares ? "Quantity" : "Contracts"
        return InkCard(relevance: s.empty ? .r3 : .r1, compact: true) {
            InkBody(compact: true) {
                InkEyebrow(cat: s.name, glyph: s.glyph) {
                    InkBand(skin: s.empty ? .low : .mod, text: s.empty ? (isShares ? "None held" : "None open") : "\(s.total) \(unit)")
                }
                if s.empty {
                    NvCompactHero(value: "—", unit: isShares ? "no shares held" : "nothing written", size: 34, color: Ink.dim)
                    InkBullets(items: ["No \(s.name.lowercased()) on the book"])
                    InkSpacer()
                } else {
                    NvCompactHero(value: realizedZero ? "$0" : nv2Money(s.realized),
                                  unit: realizedZero ? "nothing realised yet" : "realised · booked",
                                  size: 34, color: realizedZero ? Ink.dim : Ink.signed(s.realized >= 0))
                    InkBullets(items: ["\(s.basisLabel) \(inkUsd(s.basis)) across \(s.total) \(unit)"])
                    InkSpacer()
                    InkBand3(items: [(s.basisLabel, inkUsd(s.basis)), (qtyLabel, "\(s.total)")])
                }
            }
            InkFoot(compact: true) {
                if s.empty {
                    Text("Sleeve appears once a leg is written.")
                        .font(InkFont.display(12, .light)).foregroundStyle(Ink.dim)
                } else {
                    NvLedger2(a: ("Realised", s.realized), b: ("Open · unrealised", s.unrealized))
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
                InkSectionHead(title: "Insights", count: "2 cards")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        volatilityCard(ins.vol).inkEntrance(0)
                        protectionCard(ins.protection).inkEntrance(1)
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
        return InkCard(compact: true, height: 452) {
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
                    .font(InkFont.mono(24, .light)).tracking(24 * -0.02).foregroundStyle(tint)
                    .lineLimit(1).fixedSize()
                footNote(v.building
                    ? "Score turns on once implied vol is streaming from the chain."
                    : (v.spread.map { "IV \(nv2Dec(abs($0), 0)) pts \($0 >= 0 ? "over" : "under") realised · " } ?? "")
                        + (v.score >= 1.0
                            ? "options rich, favourable to sell calls."
                            : "options cheap — reduce or skip this cycle."))
            }
            InkStamp(state: .delayed, text: v.building ? "Building · IV feed pending" : "Updated · every 30 min", compact: true)
        }
    }

    // 02 · Protection — gauge is % of shares floored by puts
    private func protectionCard(_ p: NvProtection) -> some View {
        InkCard(compact: true, height: 452) {
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
                InkDelta(value: "$" + nv2Dec(abs(p.cushion), 2), good: p.cushion >= 0, size: 24, weight: .light)
                footNote("Spot sits \(nv2Dec(abs(p.cushionPct), 1))% \(p.cushion >= 0 ? "over" : "under") break-even — the puts floor the rest.")
            }
            InkStamp(state: .delayed, text: "Updated 16:00 · next at close", compact: true)
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
        return InkCard(compact: true, height: 392) {
            InkBody(compact: true) {
                InkEyebrow(n: n, cat: t.ticker) { InkBand(skin: .low, text: t.name) }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(price.map { "$" + nv2Dec($0, 2) } ?? "—")
                        .font(InkFont.mono(32, .light)).tracking(32 * -0.04).foregroundStyle(Ink.text)
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
            InkStamp(state: stamp2(fresh), text: "Updated now · streaming", compact: true, flat: true)
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
                            .font(InkFont.mono(10.5)).foregroundStyle(d.pct < 0 ? Ink.loss : Ink.text)
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
                if let value { InkDelta(value: value, good: good, size: 24, weight: .light) }
                else { Text("—").font(InkFont.mono(24, .light)).foregroundStyle(Ink.dim) }
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
                InkSectionHead(title: "Historical performance", count: "1 card")
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

/// The gains-up / losses-down session chart with a month rail and per-source
/// filter chips — the design's single History card (348 × 540).
private struct HistoryCardView: View {
    let h: NvHistory
    @State private var mi: Int
    @State private var pick: Int? = nil
    @State private var on: [String: Bool]
    private let barH: CGFloat = 52

    init(h: NvHistory) {
        self.h = h
        _mi = State(initialValue: max(0, h.months.count - 1))
        var d: [String: Bool] = [:]
        for s in h.sources { d[s.key] = !s.empty && s.key != "putsSold" }
        _on = State(initialValue: d)
    }

    private var m: NvHistMonth { h.months[min(mi, h.months.count - 1)] }
    private func gain(_ b: NvHistBar) -> Double { h.sources.reduce(0) { a, s in a + ((on[s.key] ?? false) && (b.vals[s.key] ?? 0) > 0 ? b.vals[s.key]! : 0) } }
    private func loss(_ b: NvHistBar) -> Double { h.sources.reduce(0) { a, s in a + ((on[s.key] ?? false) && (b.vals[s.key] ?? 0) < 0 ? b.vals[s.key]! : 0) } }
    private var peak: Double {
        max(h.months.flatMap { $0.bars }.map { max(gain($0), -loss($0)) }.max() ?? 1, 1)
    }

    var body: some View {
        let bars = m.bars
        let gains = bars.reduce(0) { $0 + gain($1) }
        let losses = bars.reduce(0) { $0 + loss($1) }
        let net = gains + losses
        let done = bars.filter { !$0.pending }.count
        let sel = pick.flatMap { bars.indices.contains($0) ? bars[$0] : nil }
        return InkCard(height: 540) {
            InkBody {
                InkEyebrow(n: "01", cat: "Gains & losses") { InkBand(skin: .mod, text: m.label) }
                InkDelta(value: inkUsd(abs(net)), good: net >= 0, size: 36, weight: .light).padding(.top, 16)
                Text("Net · \(m.label) · \(done) of \(bars.count) sessions".uppercased())
                    .font(InkFont.mono(9.5)).tracking(9.5 * 0.16).foregroundStyle(Ink.dim).padding(.top, 9)
                chart(bars).padding(.top, 16)
                InkSpacer()
                monthRail.padding(.top, 12)
                sourceRail.padding(.top, 4)
            }
            InkFoot {
                if let sel { sessionFoot(sel) } else { totalsFoot(gains, losses) }
            }
            InkStamp(state: .delayed, text: "Updated 16:00 · next at close")
        }
    }

    // dual bars: gains grow up from the midline, losses down
    @State private var grow = false
    private func chart(_ bars: [NvHistBar]) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(bars.enumerated()), id: \.element.id) { i, b in
                    Button { pick = (pick == i) ? nil : i } label: {
                        VStack(spacing: 0) {
                            VStack(spacing: 0) { Spacer(minLength: 0)
                                Rectangle().fill(b.pending ? Ink.hair : Ink.text)
                                    .frame(height: max(1, gain(b) / peak * barH * (grow ? 1 : 0)))
                                    .clipShape(RoundedCorner(radius: 2, corners: [.topLeft, .topRight]))
                            }.frame(height: barH)
                            VStack(spacing: 0)  {
                                Rectangle().fill(b.pending ? Ink.hair : Ink.loss)
                                    .frame(height: max(1, -loss(b) / peak * barH * (grow ? 1 : 0)))
                                    .clipShape(RoundedCorner(radius: 2, corners: [.bottomLeft, .bottomRight]))
                                Spacer(minLength: 0)
                            }.frame(height: barH)
                        }
                        .frame(maxWidth: .infinity)
                        .inkRelevance(pick == nil || pick == i ? .r1 : .r3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay(alignment: .center) { Rectangle().fill(Ink.hair).frame(height: 1) }
            HStack {
                Text("\(m.short) \(bars.first?.label ?? "")").font(InkFont.mono(8)).tracking(8 * 0.1).foregroundStyle(Ink.dim)
                Spacer()
                Text("\(m.short) \(bars.last?.label ?? "")").font(InkFont.mono(8)).tracking(8 * 0.1).foregroundStyle(Ink.dim)
            }
        }
        .onAppear { withAnimation(InkMotion.ease(0.9).delay(0.14)) { grow = true } }
    }

    private var monthRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(h.months.enumerated()), id: \.element.id) { i, mo in
                    let selp = i == mi
                    Button { mi = i; pick = nil } label: {
                        Text(mo.short.uppercased()).font(InkFont.mono(9)).tracking(9 * 0.14)
                            .foregroundStyle(selp ? Ink.invertText : Ink.dim)
                            .padding(.horizontal, 11).frame(minHeight: 26)
                            .background(RoundedRectangle(cornerRadius: Ink.radiusElement).fill(selp ? Ink.invertBg : .clear))
                            .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(selp ? .clear : Ink.hair, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
        .padding(.top, 14)
    }

    private var sourceRail: some View {
        let live = h.sources.filter { !$0.empty }
        let all = live.allSatisfy { on[$0.key] ?? false }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    for s in h.sources { on[s.key] = s.empty ? false : !all }
                } label: { chip("All", nil, active: all, dashed: false) }
                    .buttonStyle(.plain)
                Rectangle().fill(Ink.hair).frame(width: 1, height: 18)
                ForEach(h.sources.sorted { ($0.empty ? 1 : 0) < ($1.empty ? 1 : 0) }) { s in
                    Button { if !s.empty { on[s.key]?.toggle() } } label: {
                        chip(s.label, s.glyph, active: (on[s.key] ?? false) && !s.empty, dashed: s.empty)
                    }
                    .buttonStyle(.plain).disabled(s.empty)
                }
            }
        }
        .padding(.top, 4)
    }

    private func chip(_ label: String, _ glyph: String?, active: Bool, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            if let glyph { Text(glyph).font(.system(size: 9)) }
            Text(label.uppercased()).font(InkFont.mono(9)).tracking(9 * 0.08)
        }
        .foregroundStyle(active ? Ink.invertText : Ink.dim)
        .padding(.horizontal, 9).frame(minHeight: 26)
        .background(RoundedRectangle(cornerRadius: Ink.radiusElement).fill(active ? Ink.invertBg : .clear))
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement)
            .strokeBorder(active ? Color.clear : Ink.hair, style: .init(lineWidth: 1, dash: dashed ? [3, 3] : [])))
    }

    private func totalsFoot(_ gains: Double, _ losses: Double) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("GAINS VS LOSSES").font(InkFont.mono(9)).tracking(9 * 0.16).foregroundStyle(Ink.dim)
                Spacer()
                Text("TAP A SESSION").font(InkFont.mono(10)).tracking(10 * 0.1).foregroundStyle(Ink.dim)
            }
            HStack(spacing: 22) {
                col("Gains", inkUsd(gains), Ink.text)
                col("Losses", inkUsd(abs(losses)), Ink.loss)
            }
        }
    }
    private func sessionFoot(_ b: NvHistBar) -> some View {
        let total = gain(b) + loss(b)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(b.sub.uppercased()).font(InkFont.mono(9)).tracking(9 * 0.16).foregroundStyle(Ink.text)
                Spacer()
                InkDelta(value: inkUsd(abs(total)), good: total >= 0, size: 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(h.sources.filter { (on[$0.key] ?? false) && (b.vals[$0.key] ?? 0) != 0 }) { s in
                        let v = b.vals[s.key] ?? 0
                        VStack(alignment: .leading, spacing: 7) {
                            Text("\(s.glyph) \(s.label)".uppercased()).font(InkFont.mono(8)).tracking(8 * 0.1)
                                .foregroundStyle(Ink.dim).lineLimit(1)
                            Text((v < 0 ? "−" : "+") + inkUsd(abs(v)))
                                .font(InkFont.mono(15)).foregroundStyle(v < 0 ? Ink.loss : Ink.text)
                        }
                    }
                }
            }
        }
    }
    private func col(_ k: String, _ v: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(k.uppercased()).font(InkFont.mono(8.5)).tracking(8.5 * 0.12).foregroundStyle(Ink.dim)
            Text(v).font(InkFont.mono(22, .light)).foregroundStyle(color)
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
