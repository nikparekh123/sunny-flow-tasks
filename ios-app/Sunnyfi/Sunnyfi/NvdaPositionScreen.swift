//
//  NvdaPositionScreen.swift
//  Sunnyfi — Ink rebuild · Section 1 · Current position
//
//  The six card species composed from the Ink primitives, driven by NvDerive.
//  Overview (summary + total) · Shares · then a group per option sleeve, one
//  card per net-open strike.
//

import SwiftUI

// MARK: - formatting

private func nvInt(_ v: Double) -> String { Int(v.rounded()).formatted(.number.grouping(.automatic)) }
private func nvSigned(_ v: Double) -> String { (v > 0 ? "+" : v < 0 ? "−" : "") + nvInt(abs(v)) }
private func nvDec(_ v: Double, _ d: Int) -> String { String(format: "%.\(d)f", v) }
private func nvMoneySigned(_ v: Double) -> String { (v >= 0 ? "+" : "−") + inkUsd(abs(v)) }

private func stampState(_ f: NvFresh) -> InkStamp.FreshState {
    switch f { case .live: return .live; case .delayed: return .delayed; case .stale: return .stale }
}

struct NvdaPositionScreen: View {
    let store: NvdaStore
    var onPlan: () -> Void = {}

    var body: some View {
        if let p = store.position {
            VStack(alignment: .leading, spacing: 0) {
                InkSectionHead(title: "Portfolio", count: "\(cardCount(p)) cards")
                rail(p)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if store.isLoading {
            quiet("Loading NVDA", "Pulling the live position…")
        } else {
            quiet("No data", store.lastError ?? "Waiting for live market data.")
        }
    }

    private func cardCount(_ p: NvPosition) -> Int { 3 + p.groups.reduce(0) { $0 + $1.strikes.count } }

    // Flat card rail: every card is a scroll-snap target (16px inset), with the
    // group label pinned above each group's first card.
    private struct RailItem: Identifiable { let id: String; let label: String?; let glyph: String?; let count: Int?; let card: AnyView }

    private func items(_ p: NvPosition) -> [RailItem] {
        var out: [RailItem] = [
            .init(id: "summary", label: "Overview", glyph: nil, count: 2, card: AnyView(summaryCard(p).inkEntrance(0))),
            .init(id: "total", label: nil, glyph: nil, count: nil, card: AnyView(totalCard(p).inkEntrance(1))),
            .init(id: "shares", label: "Shares", glyph: "○", count: 1, card: AnyView(sharesCard(p).inkEntrance(2))),
        ]
        for g in p.groups {
            for (i, s) in g.strikes.enumerated() {
                out.append(.init(id: s.id, label: i == 0 ? g.label : nil, glyph: i == 0 ? g.glyph : nil,
                                 count: i == 0 ? g.strikes.count : nil, card: AnyView(strikeCard(p, s).inkEntrance(min(i, 4)))))
            }
        }
        return out
    }

    private func rail(_ p: NvPosition) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(items(p)) { it in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 9) {
                            if let label = it.label {
                                if let g = it.glyph { Text(g).font(InkFont.mono(11)).foregroundStyle(Ink.text) }
                                Text(label.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.2).foregroundStyle(Ink.dim)
                                if let c = it.count { Text("\(c)").font(InkFont.mono(9.5)).tracking(9.5 * 0.1).foregroundStyle(Ink.text) }
                            }
                        }
                        .frame(height: 20, alignment: .leading)   // reserved so cards align
                        it.card
                    }
                    .frame(width: 348)
                }
            }
            .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 8)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
    }

    private func quiet(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(InkFont.mono(10)).tracking(10 * 0.16).foregroundStyle(Ink.dim)
            Text(body).font(InkFont.display(13, .light)).foregroundStyle(Ink.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 120)
    }

    // MARK: 01 · summary

    private func summaryCard(_ p: NvPosition) -> some View {
        let hedge = p.groups.filter { $0.strikes.first?.side == "long" }.reduce(0) { $0 + $1.strikes.count }
        return InkCard {
            InkBody {
                InkEyebrow(n: "01", cat: "Summary") { InkBand(skin: .mod, text: p.delta >= 0 ? "Net long" : "Net short") }
                InkHero(value: nvSigned(p.delta), unit: "delta")
                InkBullets(items: [
                    "Calls + puts hedge \(nvInt(p.shares)) sh",
                    "\(hedge) hedge legs · \(p.contractsOpen) contracts open",
                ])
                InkSpacer()
                InkBand3(items: [("Gamma", nvSigned(p.gamma)), ("Theta", nvMoneySigned(p.theta)), ("Spot", "$" + nvDec(p.spot, 2))])
            }
            InkFoot {
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("CURRENT P&L · UNREALIZED").font(InkFont.mono(9)).tracking(9 * 0.16).foregroundStyle(Ink.dim)
                        InkDelta(value: inkUsd(abs(p.pnl)), good: p.pnl >= 0, size: 30, weight: .light).padding(.top, 10)
                        Text("Shares \(inkUsd(abs(p.sharesPL))) · options \(inkUsd(abs(p.optionsPL)))")
                            .font(InkFont.mono(10)).tracking(10 * 0.04).foregroundStyle(Ink.dim).padding(.top, 9)
                    }
                    Spacer(minLength: 0)
                    Button(action: onPlan) {
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 17, weight: .regular))
                            .frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: Ink.radiusElement).fill(Ink.invertBg))
                            .foregroundStyle(Ink.invertText)
                    }
                    .buttonStyle(.plain)
                }
            }
            InkStamp(state: stampState(p.fresh), text: p.freshText)
        }
    }

    // MARK: 02 · total position

    private func totalCard(_ p: NvPosition) -> some View {
        let optBought = p.sleeves.filter { $0.side == "long" && $0.kind != "shares" }.reduce(0) { $0 + $1.basis }
        let optSold = p.sleeves.filter { $0.side == "short" }.reduce(0) { $0 + $1.basis }
        let capital = p.sharesPaid + optBought - optSold
        return InkCard {
            InkBody {
                InkEyebrow(n: "02", cat: "Total position") { InkBand(skin: .low, text: "\(p.sleeves.count) sleeves") }
                InkHero(value: nvInt(p.shares), unit: "shares held · \(p.contractsOpen) contracts open")
                InkSpacer()
                VStack(spacing: 0) {
                    sleeveRow("Shares", "○", nvInt(p.shares) + " sh", inkUsd(p.sharesPaid))
                    ForEach(p.sleeves) { s in
                        sleeveRow(s.name, s.kind == "call" ? (s.side == "short" ? "▲" : "△") : (s.side == "short" ? "▼" : "▽"),
                                  "\(s.qty) ct", inkUsd(s.basis))
                    }
                }
            }
            InkFoot {
                bars3("Where the capital sits", capital, [
                    ("Shares", p.sharesPaid, false),
                    ("Options bought", optBought, false),
                    ("Options sold", optSold, true),
                ])
            }
            InkStamp(state: stampState(p.fresh), text: p.freshText)
        }
    }

    private func sleeveRow(_ name: String, _ glyph: String, _ qty: String, _ basis: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 9) {
                Text(glyph).font(.system(size: 11)).foregroundStyle(Ink.text)
                Text(name).font(InkFont.display(13.5, .light)).foregroundStyle(Ink.text)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Text(qty).font(InkFont.mono(12)).foregroundStyle(Ink.dim)
                Text(basis).font(InkFont.mono(12)).foregroundStyle(Ink.text).frame(minWidth: 84, alignment: .trailing)
            }
        }
        .padding(.vertical, 13)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
    }

    @State private var barsGrow = false
    private func bars3(_ label: String, _ net: Double, _ rows: [(String, Double, Bool)]) -> some View {
        let maxV = max(rows.map(\.1).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label.uppercased()).font(InkFont.mono(9)).tracking(9 * 0.16).foregroundStyle(Ink.dim)
                Spacer()
                Text(nvMoneySigned(net)).font(InkFont.mono(17, .medium)).tracking(17 * -0.02).foregroundStyle(Ink.text)
            }
            ForEach(rows.indices, id: \.self) { i in
                let r = rows[i]
                HStack(spacing: 10) {
                    Text(r.0.uppercased()).font(InkFont.mono(8.5)).tracking(8.5 * 0.1).foregroundStyle(Ink.dim)
                        .frame(width: 86, alignment: .leading)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Ink.hair)
                            Capsule().fill(r.2 ? Ink.gain : Ink.dim)
                                .frame(width: max(2, CGFloat(r.1 / maxV) * g.size.width * (barsGrow ? 1 : 0)))
                        }
                    }.frame(height: 7)
                    Text((r.2 ? "+" : "") + inkUsd(r.1)).font(InkFont.mono(12)).foregroundStyle(r.2 ? Ink.gain : Ink.text)
                        .frame(minWidth: 66, alignment: .trailing)
                }
            }
        }
        .onAppear { withAnimation(InkMotion.ease(0.9).delay(0.14)) { barsGrow = true } }
    }

    // MARK: 03 · shares

    private func sharesCard(_ p: NvPosition) -> some View {
        let diff = p.avgBuy > 0 ? (p.spot - p.avgBuy) / p.avgBuy * 100 : 0
        return InkCard {
            InkBody {
                InkEyebrow(n: "03", cat: "Shares · long") {
                    InkBand(skin: .hue(diff >= 0 ? Ink.gain : Ink.loss), text: "\(nvDec(abs(diff), 2))% vs avg")
                }
                InkHero(value: "$" + nvDec(p.spot, 2), unit: "live spot · nvda")
                InkBullets(items: [
                    "Break-even $\(nvDec(p.breakEven, 2)) after premium",
                    "$\(nvDec(p.premiumPerShare, 2)) a share collected, calls only",
                ])
                InkSpacer()
                InkBand3(items: [("Average buy", "$" + nvDec(p.avgBuy, 2)), ("New average", "$" + nvDec(p.breakEven, 2)), ("Quantity", nvInt(p.shares))])
            }
            InkFoot {
                InkBars(leftK: "Paid", leftV: p.sharesPaid, rightK: "Value now", rightV: p.sharesValue,
                        hue: p.sharesPL >= 0 ? Ink.gain : Ink.loss) {
                    InkDelta(value: inkUsd(abs(p.sharesPL)), good: p.sharesPL >= 0, size: 17)
                }
            }
            InkStamp(state: stampState(p.fresh), text: p.freshText)
        }
    }

    // MARK: 04/05/06 · a strike (short / long / expired)

    private func strikeCard(_ p: NvPosition, _ s: NvStrike) -> some View {
        let short = s.side == "short"
        let basisK = short ? "Collected" : "Paid"
        let curK = short ? "To close" : "Value now"
        let net = short ? s.basis - s.current : s.current - s.basis
        let entry = s.ct > 0 ? s.basis / (s.ct * 100) : 0
        let gap = s.strike - p.spot
        return InkCard(spine: short ? .short : .long) {
            InkBody {
                InkEyebrow(n: "", cat: "\(s.kind == "call" ? "Call" : "Put") \(short ? "sold" : "bought")",
                           glyph: s.kind == "call" ? (short ? "▲" : "△") : (short ? "▼" : "▽")) {
                    if s.expired { InkBand(skin: .hue(Ink.loss), text: "Expired \(s.moneyness)") }
                    else { InkBand(skin: s.moneyness == "ITM" ? .mod : .low, text: s.moneyness) }
                }
                // identity line
                (Text("$\(nvDec(s.strike, s.strike == s.strike.rounded() ? 0 : 1))").foregroundStyle(Ink.text).underline(true, color: Ink.hair)
                    + Text(" · \(s.expiry) · \(s.dte)").foregroundStyle(Ink.dim))
                    .font(InkFont.mono(9)).tracking(9 * 0.1).padding(.top, 20)
                // hero: mark (or strike when expired)
                if s.expired || s.mark == nil {
                    InkHero(value: "$" + nvDec(s.strike, s.strike == s.strike.rounded() ? 0 : 1), unit: "\(s.expiry) · no live mark")
                        .padding(.top, -8)
                } else {
                    HStack(alignment: .center, spacing: 14) {
                        InkRoll(text: "$" + nvDec(s.mark ?? 0, 2), font: InkFont.mono(44, .light), tracking: 44 * -0.04, color: Ink.text)
                        Text(s.good == nil ? "·" : (entry > 0 ? "\((s.mark ?? 0) >= entry ? "+" : "−")\(nvDec(abs(((s.mark ?? 0) - entry) / entry * 100), 1))%" : ""))
                            .font(InkFont.mono(12)).foregroundStyle(Ink.signed(s.good))
                    }
                    .padding(.top, 16)
                    Text("MARK NOW · \(short ? "SOLD AT" : "PAID") $\(nvDec(entry, 2))")
                        .font(InkFont.mono(9.5)).tracking(9.5 * 0.16).foregroundStyle(Ink.dim).padding(.top, 12)
                }
                InkBullets(items: s.expired
                    ? ["Assigned in all likelihood", "Reconcile before it skews the sleeve"]
                    : ["Spot $\(nvDec(p.spot, 2)) · $\(nvDec(abs(gap), 2)) \(gap >= 0 ? "below" : "above") strike",
                       "\(Int(s.ct)) ct × $\(nvDec(s.mark ?? 0, 2)) = \(inkUsd(s.current)) \(short ? "to close" : "of value")"])
                InkSpacer()
                InkBand3(items: [("Contracts", "\(Int(s.ct))"), ("Delta", s.delta.map { nvDec($0, 3) } ?? "—"), ("Theta", s.theta.map { nvDec($0, 3) } ?? "—")])
            }
            InkFoot {
                InkBars(leftK: basisK, leftV: s.basis, rightK: curK, rightV: s.current, hue: net >= 0 ? Ink.gain : Ink.loss) {
                    InkDelta(value: inkUsd(abs(net)), good: net >= 0, size: 17)
                }
            }
            InkStamp(state: s.expired ? .stale : stampState(p.fresh), text: s.expired ? "Stale · next at broker sync" : p.freshText)
        }
    }
}
