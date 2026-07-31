//
//  NvdaPositionScreen.swift
//  Sunnyfi — Ink rebuild · Section 1 · Current position
//
//  Consolidated to leg-type cards (design: "Current Position - Cards"). One
//  Total-position card (a position / delta / average switch) then ONE card per
//  option sleeve — calls sold, puts bought, calls bought — each a ledger of its
//  strikes that drills into a single strike in place. No per-strike cards, no
//  summary card, no shares card.
//

import SwiftUI

// MARK: - formatting

private func nvInt(_ v: Double) -> String { Int(v.rounded()).formatted(.number.grouping(.automatic)) }
private func nvSigned(_ v: Double) -> String { (v > 0 ? "+" : v < 0 ? "−" : "") + nvInt(abs(v)) }
private func nvDec(_ v: Double, _ d: Int) -> String { String(format: "%.\(d)f", v) }
private func nvStrike(_ v: Double) -> String { "$" + (v == v.rounded() ? nvDec(v, 0) : nvDec(v, 1)) }
/// Compact USD: $1.85M for millions, $100K / $12.3K for thousands, else grouped.
private func nvUsd(_ v: Double) -> String {
    let a = abs(v), sign = v < 0 ? "−" : ""
    func trim(_ s: String) -> String { s.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) }
    if a >= 1_000_000 { return sign + "$" + trim(String(format: a >= 10_000_000 ? "%.1f" : "%.2f", a / 1_000_000)) + "M" }
    if a >= 1_000 { return sign + "$" + trim(String(format: a >= 100_000 ? "%.0f" : "%.1f", a / 1_000)) + "K" }
    return sign + "$" + nvInt(a)
}

private func stampState(_ f: NvFresh) -> InkStamp.FreshState {
    switch f { case .live: return .live; case .delayed: return .delayed; case .stale: return .stale }
}

private func glyph(_ kind: String, _ side: String) -> String {
    kind == "call" ? (side == "short" ? "▲" : "△") : (side == "short" ? "▼" : "▽")
}

struct NvdaPositionScreen: View {
    let store: NvdaStore
    var onPlan: () -> Void = {}

    var body: some View {
        if let p = store.position {
            VStack(alignment: .leading, spacing: 0) {
                InkSectionHead(title: "Portfolio")
                rail(p)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if store.isLoading {
            quiet("Loading NVDA", "Pulling the live position…")
        } else {
            quiet("No data", store.lastError ?? "Waiting for live market data.")
        }
    }

    // Grouped rail (design: grp-h is position:sticky;left:0). The total card sits
    // alone under "Position"; the sleeve cards stack under "Contracts".
    private struct RailGroup: Identifiable { let id: String; let label: String; let glyph: String?; let count: Int; let cards: [AnyView] }

    // A sleeve card holds the design's fixed 530 height → at most STRIKES_PER_CARD
    // ledger rows fit above the foot. Sleeves with more split across sibling cards
    // ("Puts bought · 1/2", "· 2/2"); the hero + foot on each page carry the whole
    // sleeve total, so either page read alone still summarises the sleeve.
    private static let strikesPerCard = 3

    private func sleeveCardCount(_ p: NvPosition) -> Int {
        p.groups.reduce(0) { $0 + max(1, Int(ceil(Double($1.strikes.count) / Double(Self.strikesPerCard)))) }
    }

    private func groups(_ p: NvPosition) -> [RailGroup] {
        var out: [RailGroup] = [
            .init(id: "position", label: "Position", glyph: nil, count: 1,
                  cards: [AnyView(TotalPositionCard(p: p).inkEntrance(0))]),
        ]
        var cards: [AnyView] = []
        var entrance = 1
        for g in p.groups {
            let pages = stride(from: 0, to: max(1, g.strikes.count), by: Self.strikesPerCard).map { start in
                Array(g.strikes[start ..< min(start + Self.strikesPerCard, g.strikes.count)])
            }
            for (pi, slice) in pages.enumerated() {
                let num = String(format: "%02d", cards.count + 2)
                cards.append(AnyView(
                    SleeveGroupCard(leg: g, pageStrikes: slice, page: pi, pageCount: pages.count,
                                    n: num, spot: p.spot, fresh: p.fresh, freshText: p.freshText)
                        .inkEntrance(min(entrance, 4))))
                entrance += 1
            }
        }
        if !cards.isEmpty {
            out.append(.init(id: "contracts", label: "Contracts", glyph: "△", count: cards.count, cards: cards))
        }
        return out
    }

    private func rail(_ p: NvPosition) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(groups(p)) { g in
                    InkStickyGroup(label: g.label, glyph: g.glyph, count: g.count,
                                   groupWidth: CGFloat(g.cards.count) * 348 + CGFloat(max(0, g.cards.count - 1)) * 10) {
                        ForEach(Array(g.cards.enumerated()), id: \.offset) { $0.element }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 8)
        }
        .coordinateSpace(name: "inkRail")
    }

    private func quiet(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(InkFont.mono(10)).tracking(10 * 0.16).foregroundStyle(Ink.dim)
            Text(body).font(InkFont.display(13, .light)).foregroundStyle(Ink.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 120)
    }
}

// MARK: - Total position (position · delta · average switch)

private struct TotalPositionCard: View {
    let p: NvPosition
    enum Mode: String, CaseIterable { case position, delta }
    @State private var mode: Mode = .position
    @State private var openLeg: String? = nil     // drilled sleeve (delta view)

    // one delta row per option sleeve (+ shares), summed from the engine's per-leg estimate
    private struct DeltaRow: Identifiable { let name, glyph, side: String; let delta: Double; let parts: [NvStrike]; var id: String { name } }
    private var deltaRows: [DeltaRow] {
        var rows = [DeltaRow(name: "Shares", glyph: "○", side: "long", delta: p.shares, parts: [])]
        for g in p.groups {
            let side = g.strikes.first?.side ?? "long"
            rows.append(DeltaRow(name: g.label, glyph: g.glyph, side: side,
                                 delta: g.strikes.reduce(0) { $0 + $1.deltaEst }, parts: g.strikes))
        }
        return rows
    }
    private var optBought: Double { p.sleeves.filter { $0.side == "long" }.reduce(0) { $0 + $1.basis } }
    private var optSold: Double { p.sleeves.filter { $0.side == "short" }.reduce(0) { $0 + $1.basis } }
    private var committed: Double { p.sharesPaid + optBought - optSold }   // capital at work

    var body: some View {
        InkCard {
            InkBody {
                InkEyebrow(cat: "Total position")
                switcher
                hero
                if mode == .delta && openLeg == nil {
                    ledger.padding(.top, 26)
                    InkSpacer()
                } else {
                    InkSpacer()
                    ledger
                }
            }
            InkFoot { foot }
            InkStamp(state: stampState(p.fresh), text: stampText)
        }
    }

    private var stampText: String {
        switch mode {
        case .delta:   return "Updated now · delta from live chain"
        case .position: return p.freshText
        }
    }

    // MARK: switcher

    private var switcher: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases, id: \.self) { m in
                let on = mode == m
                Button { withAnimation(InkMotion.ease(0.32)) { mode = m; openLeg = nil } } label: {
                    Text(m.rawValue.uppercased()).font(InkFont.mono(9.5, .medium)).tracking(9.5 * 0.14)
                        .foregroundStyle(on ? Ink.invertText : Ink.dim)
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: Ink.radiusElement, style: .continuous)
                            .fill(on ? Ink.invertBg : .clear))
                        .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement, style: .continuous)
                            .strokeBorder(on ? Ink.text : Ink.hair, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 14)
    }

    // MARK: hero

    @ViewBuilder private var hero: some View {
        switch mode {
        case .position:
            InkHero(value: nvUsd(committed))
        case .delta:
            heroSplit(big: nvSigned(p.delta), bigUnit: "net delta · share equiv",
                      side: nvSigned(p.gamma), sideUnit: "gamma · per $1", sideColor: Ink.text)
        }
    }

    // Big figure on the left, a single secondary stat across a hairline on the right.
    private func heroSplit(big: String, bigUnit: String, side: String, sideUnit: String, sideColor: Color) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                InkRoll(text: big, font: InkFont.mono(44, .light), tracking: 44 * -0.04, color: Ink.text)
                    .fixedSize()
                Text(bigUnit.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.16)
                    .foregroundStyle(Ink.dim).padding(.top, 12).lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text(side).font(InkFont.mono(20, .light)).tracking(20 * -0.03).foregroundStyle(sideColor).fixedSize()
                Text(sideUnit.uppercased()).font(InkFont.mono(8.5)).tracking(8.5 * 0.12)
                    .foregroundStyle(Ink.dim).padding(.top, 8).fixedSize()
            }
            .padding(.leading, 14)
            .overlay(alignment: .leading) { Rectangle().fill(Ink.hair).frame(width: 1) }
        }
        .padding(.top, 24)
    }

    // MARK: ledger

    @ViewBuilder private var ledger: some View {
        switch mode {
        case .position: positionLedger
        case .delta:    if let name = openLeg, let row = deltaRows.first(where: { $0.name == name }) { deltaDrill(row) } else { deltaLedger }
        }
    }

    private var positionLedger: some View {
        VStack(spacing: 0) {
            sleeveRow("Shares", "○", nvInt(p.shares) + " sh", nvUsd(p.sharesPaid))
            ForEach(p.sleeves) { s in
                sleeveRow(s.name, glyph(s.kind, s.side), "\(s.qty) ct", nvUsd(s.basis))
            }
        }
    }

    private func sleeveRow(_ name: String, _ g: String, _ qty: String, _ basis: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 9) {
                Text(g).font(.system(size: 11)).foregroundStyle(Ink.text)
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

    // The break-even as a small waterfall: what you paid, less premium taken in,
    // equals what you effectively own it at.
    private var deltaLedger: some View {
        let maxD = max(deltaRows.map { abs($0.delta) }.max() ?? 1, 1)
        return VStack(spacing: 0) {
            ForEach(deltaRows) { r in
                Button { if !r.parts.isEmpty { withAnimation(InkMotion.ease(0.28)) { openLeg = r.name } } } label: {
                    DeltaLedgerRow(glyph: r.glyph, name: r.name, delta: r.delta, maxD: maxD)
                }
                .buttonStyle(.plain).disabled(r.parts.isEmpty)
            }
        }
    }

    private func deltaDrill(_ row: DeltaRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(InkMotion.ease(0.28)) { openLeg = nil } } label: {
                HStack(spacing: 9) {
                    Text("←").font(InkFont.mono(11)).foregroundStyle(Ink.dim)
                    Text(row.name).font(InkFont.display(13.5, .light)).foregroundStyle(Ink.text)
                    Spacer(minLength: 0)
                    Text(nvSigned(row.delta) + " Δ").font(InkFont.mono(12)).foregroundStyle(Ink.signed(row.delta >= 0))
                }
                .padding(.vertical, 11)
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(row.parts) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(nvStrike(s.strike)) · \(s.expiry)".uppercased())
                            .font(InkFont.mono(8.5)).tracking(8.5 * 0.12).foregroundStyle(Ink.dim)
                        Spacer(minLength: 0)
                        Text(s.expired ? "EXPIRED · 0" : nvSigned(s.deltaEst))
                            .font(InkFont.mono(11.5)).foregroundStyle(s.expired ? Ink.dim : Ink.signed(s.deltaEst >= 0))
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: foot

    @ViewBuilder private var foot: some View {
        switch mode {
        case .position:
            ValueFoot(committed: committed, shares: p.sharesPL, options: p.optionsPL)
        case .delta:
            ExposureFoot(net: p.delta, block: p.shares)
        }
    }
}

// MARK: - delta ledger row (centred contribution bar)

private struct DeltaLedgerRow: View {
    let glyph: String; let name: String; let delta: Double; let maxD: Double
    @State private var grow = false
    var body: some View {
        HStack(spacing: 9) {
            Text(glyph).font(.system(size: 11)).foregroundStyle(Ink.text)
            Text(name).font(InkFont.display(13.5, .light)).foregroundStyle(Ink.text).lineLimit(1)
            Spacer(minLength: 0)
            GeometryReader { g in
                let half = g.size.width / 2
                let w = max(1, CGFloat(abs(delta) / maxD) * half * (grow ? 1 : 0))
                ZStack {
                    Capsule().fill(Ink.hair)
                    Rectangle().fill(delta >= 0 ? Ink.gain : Ink.loss)
                        .frame(width: w).clipShape(Capsule())
                        .offset(x: delta >= 0 ? w / 2 : -w / 2)
                    Rectangle().fill(Ink.dim.opacity(0.6)).frame(width: 1, height: 12)
                }
                .frame(width: g.size.width, height: 6)
            }
            .frame(width: 84, height: 6)
            Text(nvSigned(delta)).font(InkFont.mono(12)).foregroundStyle(delta >= 0 ? Ink.gain : Ink.loss)
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
        .onAppear { withAnimation(InkMotion.ease(0.9).delay(0.14)) { grow = true } }
    }
}

// MARK: - exposure foot (delta view)

private struct ExposureFoot: View {
    let net: Double; let block: Double
    @State private var grow = false
    var body: some View {
        let exposed = min(abs(net), block)
        let hedgedPct = block > 0 ? Int(((1 - exposed / block) * 100).rounded()) : 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("STILL EXPOSED").font(InkFont.mono(9)).tracking(9 * 0.16).foregroundStyle(Ink.dim)
                Spacer()
                InkDelta(value: nvInt(abs(net)), good: net >= 0, size: 22, weight: .light)
            }
            GeometryReader { g in
                let ew = block > 0 ? CGFloat(exposed / block) * g.size.width : 0
                HStack(spacing: 0) {
                    Rectangle().fill(Ink.dim.opacity(0.55))
                    Rectangle().fill(net >= 0 ? Ink.gain : Ink.loss).frame(width: ew * (grow ? 1 : 0))
                }
                .clipShape(Capsule())
            }
            .frame(height: 9)
            HStack {
                Text("HEDGED \(hedgedPct)% · \(nvInt(block)) SH").font(InkFont.mono(8.5)).tracking(8.5 * 0.12).foregroundStyle(Ink.dim)
                Spacer()
                Text(net >= 0 ? "NET LONG" : "NET SHORT").font(InkFont.mono(8.5)).tracking(8.5 * 0.12).foregroundStyle(Ink.dim)
            }
        }
        .onAppear { withAnimation(InkMotion.ease(0.9).delay(0.14)) { grow = true } }
    }
}

// MARK: - value foot (position view: worth now = committed + P&L)

private struct ValueFoot: View {
    let committed: Double; let shares: Double; let options: Double
    @State private var grow = false
    // Compact ($77.4K, not $77,380) so the caption never truncates at large P&L.
    private func money(_ v: Double) -> String { (v >= 0 ? "+" : "−") + inkK(abs(v)) }
    private func inkK(_ v: Double) -> String {
        v >= 1000 ? "$" + (v / 1000).formatted(.number.precision(.fractionLength(1))) + "K" : "$" + nvInt(v)
    }
    var body: some View {
        let pnl = shares + options
        let worth = committed + pnl
        let mag = max(abs(shares) + abs(options), 1)
        let pct = committed != 0 ? pnl / committed * 100 : 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("WORTH NOW").font(InkFont.mono(9)).tracking(9 * 0.16).foregroundStyle(Ink.dim)
                Spacer()
                InkRoll(text: nvUsd(worth), font: InkFont.mono(22, .light), tracking: 22 * -0.03, color: Ink.text)
            }
            GeometryReader { g in
                HStack(spacing: 0) {
                    Rectangle().fill(shares >= 0 ? Ink.gain : Ink.loss)
                        .frame(width: CGFloat(abs(shares) / mag) * g.size.width * (grow ? 1 : 0))
                    Rectangle().fill((options >= 0 ? Ink.gain : Ink.loss).opacity(0.5))
                        .frame(width: CGFloat(abs(options) / mag) * g.size.width * (grow ? 1 : 0))
                    Spacer(minLength: 0)
                }
                .background(Ink.hair)
            }
            .frame(height: 9).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            HStack(spacing: 10) {
                Text("SHARES \(money(shares)) · OPTIONS \(money(options))")
                    .font(InkFont.mono(8.5)).tracking(8.5 * 0.12).foregroundStyle(Ink.dim).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(pnl >= 0 ? "+" : "−")\(nvDec(abs(pct), 2))%")
                    .font(InkFont.mono(8.5)).tracking(8.5 * 0.12).foregroundStyle(pnl >= 0 ? Ink.gain : Ink.loss).fixedSize()
            }
        }
        .onAppear { withAnimation(InkMotion.ease(0.9).delay(0.14)) { grow = true } }
    }
}

// MARK: - Sleeve group card (one per leg type)

private struct SleeveGroupCard: View {
    let leg: NvGroup                 // whole sleeve — hero + foot totals read from this
    let pageStrikes: [NvStrike]      // this card's slice of the ledger
    var page: Int = 0
    var pageCount: Int = 1
    let n: String
    let spot: Double
    let fresh: NvFresh
    let freshText: String
    @State private var open: Int? = nil

    var body: some View {
        let short = leg.strikes.first?.side == "short"
        let ct = leg.strikes.reduce(0) { $0 + $1.ct }
        let basis = leg.strikes.reduce(0) { $0 + $1.basis }
        let cur = leg.strikes.reduce(0) { $0 + $1.current }
        let net = short ? basis - cur : cur - basis
        let soonest = leg.strikes.map { $0.expired ? 0 : (Int($0.dte.prefix(while: \.isNumber)) ?? 999) }.min() ?? 999
        let cat = pageCount > 1 ? "\(leg.label) · \(page + 1)/\(pageCount)" : leg.label
        return InkCard {
            InkBody {
                InkEyebrow(n: n, cat: cat, glyph: leg.glyph) {
                    InkBand(skin: .low, text: "\(leg.strikes.count) strike\(leg.strikes.count == 1 ? "" : "s")")
                }
                VStack(alignment: .leading, spacing: 10) {
                    InkDelta(value: inkUsd(abs(net)), good: net >= 0, size: 40, weight: .light)
                    Text("\(net >= 0 ? "open gain" : "open cost") · \(Int(ct.rounded())) ct across \(leg.strikes.count)".uppercased())
                        .font(InkFont.mono(9.5)).tracking(9.5 * 0.16).foregroundStyle(Ink.dim)
                }
                .padding(.top, 18)
                VStack(spacing: 0) {
                    if let i = open, i < pageStrikes.count {
                        LegDetail(leg: leg, s: pageStrikes[i], spot: spot) { withAnimation(InkMotion.ease(0.28)) { open = nil } }
                    } else {
                        ForEach(Array(pageStrikes.enumerated()), id: \.offset) { idx, s in
                            Button { withAnimation(InkMotion.ease(0.28)) { open = idx } } label: {
                                LedgerRow(s: s)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 18)
                InkSpacer()
            }
            InkFoot {
                InkBars(leftK: short ? "Collected" : "Paid", leftV: basis,
                        rightK: short ? "To close" : "Value now", rightV: cur,
                        hue: net >= 0 ? Ink.gain : Ink.loss) {
                    InkDelta(value: inkUsd(abs(net)), good: net >= 0, size: 17)
                }
            }
            InkStamp(state: stampState(fresh), text: soonest <= 1 ? "Updated now · nearest leg expires today" : freshText)
        }
    }
}

// MARK: - ledger row (a strike inside a sleeve card)

private struct LedgerRow: View {
    let s: NvStrike
    var body: some View {
        let short = s.side == "short"
        let entry = s.ct > 0 ? s.basis / (s.ct * 100) : 0
        let now = s.mark ?? 0
        let pct = entry > 0 ? (now - entry) / entry * 100 : 0
        let days = s.expired ? 0 : (Int(s.dte.prefix(while: \.isNumber)) ?? 999)
        let rank: InkRelevance = (s.expired || days <= 7) ? .r1 : days <= 200 ? .r2 : .r3
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(nvStrike(s.strike)).font(InkFont.mono(14.5)).tracking(14.5 * -0.01).foregroundStyle(Ink.text)
                        .overlay(alignment: .bottom) { Rectangle().fill(Ink.hair).frame(height: 1).offset(y: 2) }
                    Text("\(Int(s.ct)) CT").font(InkFont.mono(9)).tracking(9 * 0.1).foregroundStyle(Ink.dim)
                }
                Text((s.expired ? "Expired \(s.moneyness) · \(s.expiry)" : "\(s.expiry) · \(s.dte) · \(s.moneyness)").uppercased())
                    .font(InkFont.mono(8.5)).tracking(8.5 * 0.1).foregroundStyle(Ink.dim)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Text(s.mark == nil ? "—" : "$\(nvDec(now, 2))").font(InkFont.mono(14.5)).tracking(14.5 * -0.02).foregroundStyle(Ink.text)
                Text(s.expired || s.mark == nil ? "—" : "\(pct >= 0 ? "+" : "−")\(nvDec(abs(pct), 1))%")
                    .font(InkFont.mono(9)).foregroundStyle(s.good == nil ? Ink.dim : Ink.signed(s.good))
            }
        }
        .frame(minHeight: 46)
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
        .inkRelevance(rank)
    }
}

// MARK: - leg detail (drill-in, replaces the ledger)

private struct LegDetail: View {
    let leg: NvGroup
    let s: NvStrike
    let spot: Double
    let onBack: () -> Void
    var body: some View {
        let short = s.side == "short"
        let entry = s.ct > 0 ? s.basis / (s.ct * 100) : 0
        let gap = s.strike - spot
        let rows: [(String, String)] = [
            (short ? "Sold at" : "Paid", "$" + nvDec(entry, 2)),
            (short ? "To close" : "Value now", inkUsd(s.current)),
            ("Spot gap", "$" + nvDec(abs(gap), 2) + (gap >= 0 ? " below" : " above")),
            ("Delta · theta", "\(s.delta.map { nvDec($0, 2) } ?? "—") · \(s.theta.map { nvDec($0, 2) } ?? "—")"),
        ]
        return VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("←").font(InkFont.mono(11)).foregroundStyle(Ink.dim)
                    Text(nvStrike(s.strike)).font(InkFont.mono(14.5)).tracking(14.5 * -0.01).foregroundStyle(Ink.text)
                    Text("\(s.expiry) · \(s.dte)".uppercased()).font(InkFont.mono(8.5)).tracking(8.5 * 0.1).foregroundStyle(Ink.dim)
                    Spacer(minLength: 0)
                    Text("\(Int(s.ct)) ct").font(InkFont.mono(12)).foregroundStyle(Ink.dim)
                }
                .padding(.vertical, 11)
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(rows.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline) {
                        Text(rows[i].0.uppercased()).font(InkFont.mono(8.5)).tracking(8.5 * 0.12).foregroundStyle(Ink.dim)
                        Spacer()
                        Text(rows[i].1).font(InkFont.mono(11.5)).foregroundStyle(Ink.text)
                    }
                }
            }
            .padding(.top, 3)
        }
    }
}
