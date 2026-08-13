//
//  NvdaPositionScreen.swift
//  Sunnyfi — Ink rebuild · Section 1 · Current position
//
//  The NVDA/TLT handoff's Current position: a Summary card, a Shares card that
//  pulls out an Average-down panel, then one card per option sleeve. Each sleeve
//  card's hero is what the sleeve has MADE (realized + open), with an
//  intrinsic ↔ extrinsic toggle; a strike ledger sits below. No per-strike cards.
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
    // Matches inkUsd: millions to one decimal, thousands always whole.
    if a >= 1_000_000 { return sign + "$" + trim(String(format: "%.1f", a / 1_000_000)) + "M" }
    if a >= 1_000 { return sign + "$" + String(format: "%.0f", a / 1_000) + "K" }
    return sign + "$" + nvInt(a)
}
/// Signed compact USD — "+$1.85M" / "−$17.9K" — for P&L heroes.
private func nvUsdS(_ v: Double) -> String { (v >= 0 ? "+" : "−") + nvUsd(abs(v)) }

private func stampState(_ f: NvFresh) -> InkStamp.FreshState {
    switch f { case .live: return .live; case .delayed: return .delayed; case .stale: return .stale }
}

private func glyph(_ kind: String, _ side: String) -> String {
    kind == "call" ? (side == "short" ? "▲" : "△") : (side == "short" ? "▼" : "▽")
}

/// intrinsic / extrinsic in dollars for one leg (nil when it carries no live mark).
private func legIntExt(kind: String, strike: Double, mark: Double?, ct: Double, spot: Double)
    -> (int: Double, ext: Double, extPct: Double)? {
    guard let m = mark, m > 0 else { return nil }
    let raw = kind == "call" ? max(0, spot - strike) : max(0, strike - spot)
    let intPer = min(raw, m), extPer = m - intPer
    return (intPer * ct * 100, extPer * ct * 100, extPer / m * 100)
}

// MARK: - Screen

struct NvdaPositionScreen: View {
    let store: NvdaStore
    var onPlan: () -> Void = {}
    var showPlan: Bool = true          // the planner entry is NVDA-only
    @State private var avgDown = false // Average-down pull-out, lifted so it's its own snap target

    var body: some View {
        if let p = store.position {
            VStack(alignment: .leading, spacing: 0) {
                InkSectionHead(title: "Current position", icon: showPlan ? "scope" : nil, onAction: onPlan)
                rail(p)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if store.isLoading {
            quiet("Loading NVDA", "Pulling the live position…")
        } else {
            quiet("No data", store.lastError ?? "Waiting for live market data.")
        }
    }

    private struct RailGroup: Identifiable {
        let id: String; let label: String; let glyph: String?; let count: Int; let width: CGFloat; let cards: [AnyView]
    }

    /// Even split so a 4-strike sleeve becomes two cards of two, not three and one
    /// (matches the handoff's chunkLegs). Sorted soonest-expiry first.
    private func chunk(_ strikes: [NvStrike]) -> [[NvStrike]] {
        let sorted = strikes.sorted {
            let a = $0.expired ? -1 : (Int($0.dte.prefix(while: \.isNumber)) ?? 999)
            let b = $1.expired ? -1 : (Int($1.dte.prefix(while: \.isNumber)) ?? 999)
            return a < b
        }
        let n = sorted.count
        if n <= 3 { return [sorted] }
        let parts = Int(ceil(Double(n) / 3.0))
        let base = n / parts, rem = n % parts
        var out: [[NvStrike]] = []; var i = 0
        for p in 0..<parts { let size = base + (p < rem ? 1 : 0); out.append(Array(sorted[i..<i + size])); i += size }
        return out
    }

    private func groups(_ p: NvPosition) -> [RailGroup] {
        var sharesCards: [AnyView] = [
            AnyView(SharesCard(p: p, perShare: store.perf?.perShare ?? 0, open: avgDown,
                               onToggle: { withAnimation(InkMotion.ease(0.3)) { avgDown.toggle() } }).inkEntrance(1)),
        ]
        if avgDown {
            sharesCards.append(AnyView(AverageDownCard(p: p, high52: store.high52).inkEntrance(2)))
        }
        var out: [RailGroup] = [
            .init(id: "overview", label: "Overview", glyph: nil, count: 1, width: 348,
                  cards: [AnyView(SummaryCard(p: p, pnl: store.pnl).inkEntrance(0))]),
            .init(id: "shares", label: "Shares", glyph: "○", count: sharesCards.count, width: 348, cards: sharesCards),
        ]
        var cards: [AnyView] = []
        var entrance = 2
        for g in p.groups {
            let pages = chunk(g.strikes)
            let realizedAll = store.perf?.sleeves.first(where: { $0.name == g.label })?.realized ?? 0
            for (pi, slice) in pages.enumerated() {
                let num = String(format: "%02d", cards.count + 1)
                cards.append(AnyView(
                    SleeveGroupCard(leg: g, pageStrikes: slice, page: pi, pageCount: pages.count,
                                    n: num, spot: p.spot, fresh: p.fresh, freshText: p.freshText,
                                    realized: pi == 0 ? realizedAll : 0)
                        .inkEntrance(min(entrance, 4))))
                entrance += 1
            }
        }
        if !cards.isEmpty {
            out.append(.init(id: "contracts", label: "Contracts", glyph: "△", count: cards.count,
                             width: CGFloat(cards.count) * 348 + CGFloat(max(0, cards.count - 1)) * 10, cards: cards))
        }
        return out
    }

    private struct RailItem: Identifiable {
        let id: String; let label: String?; let glyph: String?; let count: Int?; let card: AnyView
    }
    private func railItems(_ p: NvPosition) -> [RailItem] {
        var out: [RailItem] = []
        for g in groups(p) {
            for (i, card) in g.cards.enumerated() {
                out.append(RailItem(id: "\(g.id)-\(i)", label: i == 0 ? g.label : nil,
                                    glyph: i == 0 ? g.glyph : nil, count: i == 0 ? g.count : nil, card: card))
            }
        }
        return out
    }

    // Flat card rail (like Insights/History): every card is a snap target, so each
    // one rests at the same 16pt gutter — never edge-to-edge. The group label rides
    // above its first card; other cards carry an equal-height spacer to keep tops level.
    private func rail(_ p: NvPosition) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(railItems(p)) { item in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 9) {
                            if let g = item.glyph { Text(g).font(InkFont.mono(11)).foregroundStyle(Ink.text) }
                            if let l = item.label { Text(l.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.2).foregroundStyle(Ink.dim) }
                            if let c = item.count, c > 1 { Text("\(c)").font(InkFont.mono(9.5)).tracking(9.5 * 0.1).foregroundStyle(Ink.text) }
                        }
                        .frame(height: 12, alignment: .leading)
                        item.card
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 8)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
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

// MARK: - shared ledger line (a labelled figure with a subtitle)

private struct LedgerLine: View {
    let k: String; let sub: String?; let v: String; var hue: Color = Ink.text; var first: Bool = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(k).font(InkFont.display(14, .regular)).foregroundStyle(Ink.text)
                if let sub { Text(sub.uppercased()).font(InkFont.mono(10.5)).tracking(10.5 * 0.06).foregroundStyle(Ink.dim) }
            }
            Spacer(minLength: 0)
            InkRoll(text: v, font: InkFont.mono(16, .regular), tracking: 16 * -0.02, color: hue, delay: 0.1)
        }
        // 9, not 13: three ledger rows + the lot chips overflowed the fixed 496 card
        // on Average-down, and the overflow was clipped off the BOTTOM of the foot
        // (eating its padding). Cards with slack absorb this in their InkSpacer, so
        // the rhythm stays identical across the rail.
        .padding(.vertical, 9)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Ink.hair).frame(height: 1) } }
    }
}

/// Big figure on the left, a secondary stat across a hairline on the right.
private struct HeroSplit<Big: View, Side: View>: View {
    @ViewBuilder var big: Big
    @ViewBuilder var side: Side
    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) { big }.layoutPriority(1)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) { side }
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Rectangle().fill(Ink.hair).frame(width: 1) }
        }
        .padding(.top, 24)
    }
}

private func unitLabel(_ s: String) -> some View {
    Text(s.uppercased()).font(InkFont.mono(11.5, .medium)).tracking(11.5 * 0.05)
        .foregroundStyle(Ink.dim).padding(.top, 12).lineLimit(1).minimumScaleFactor(0.7)
}

// MARK: - Summary card

private struct SummaryCard: View {
    let p: NvPosition
    let pnl: NvPnL?

    private var openPnl: Double { p.sharesPL + p.optionsPL }
    private var todayStep: Double { p.spot - p.spot / (1 + p.dayChangePct / 100) }
    private var today: Double { p.delta * todayStep }
    private var longOptBasis: Double { p.sleeves.filter { $0.side == "long" }.reduce(0) { $0 + $1.basis } }
    private var cost: Double { p.sharesPaid + longOptBasis }

    var body: some View {
        InkCard(stamp: (stampState(p.fresh), p.freshText)) {
            InkBody {
                InkEyebrow(cat: "Summary") { InkBand(skin: .mod, text: p.delta >= 0 ? "Net long" : "Net short") }
                HeroSplit {
                    InkDelta(value: nvUsdS(openPnl), good: openPnl >= 0, size: 40, weight: .medium)
                    unitLabel("open · shares + options")
                } side: {
                    InkDelta(value: nvUsdS(today), good: today >= 0, size: 20)
                    Text("today · \(p.dayChangePct >= 0 ? "+" : "−")\(nvDec(abs(p.dayChangePct), 2))%".uppercased())
                        .font(InkFont.mono(10.5)).tracking(10.5 * 0.06).foregroundStyle(Ink.dim).padding(.top, 8).fixedSize()
                }
                InkSpacer()
                VStack(spacing: 0) {
                    let realized = pnl?.realized ?? 0
                    LedgerLine(k: "Total realized so far", sub: "closed positions", v: nvUsd(realized),
                               hue: Ink.signed(realized >= 0), first: true)
                    LedgerLine(k: "New average", sub: "buy average $\(nvDec(p.avgBuy, 2))", v: "$\(nvDec(p.breakEven, 2))")
                    LedgerLine(k: "Net delta", sub: "share equivalent", v: nvSigned(p.delta))
                }
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }   // divider at row top…
                .padding(.top, 20)                                                           // …with the 20pt gap above it
            }
            InkFoot { SplitFoot(shares: p.sharesPL, options: p.optionsPL, cost: cost) }
        }
    }
}

/// Shares vs options as one stacked bar — the only place the two halves compare.
private struct SplitFoot: View {
    let shares: Double; let options: Double; let cost: Double
    @State private var grow = false
    var body: some View {
        let pnl = shares + options
        let pct = cost != 0 ? pnl / cost * 100 : 0
        let mag = max(abs(shares) + abs(options), 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("WHERE IT SITS").font(InkFont.mono(9)).tracking(9 * 0.16).foregroundStyle(Ink.dim)
                Spacer()
                Text("\(pct >= 0 ? "+" : "−")\(nvDec(abs(pct), 2))% on cost").font(InkFont.mono(15)).foregroundStyle(Ink.text)
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
            HStack {
                Text("SHARES \(nvUsdS(shares))").font(InkFont.mono(8.5)).tracking(8.5 * 0.1).foregroundStyle(Ink.dim)
                Spacer()
                Text("OPTIONS \(nvUsdS(options))").font(InkFont.mono(8.5)).tracking(8.5 * 0.1).foregroundStyle(Ink.dim)
            }
        }
        .onAppear { withAnimation(InkMotion.ease(0.9).delay(0.14)) { grow = true } }
    }
}

// MARK: - Shares card + Average-down pull-out

private struct SharesCard: View {
    let p: NvPosition
    let perShare: Double
    let open: Bool
    let onToggle: () -> Void
    var body: some View {
        InkCard(stamp: (stampState(p.fresh), p.freshText)) {
            InkBody {
                InkEyebrow(cat: "Shares · long") {
                    Button(action: onToggle) {
                        HStack(spacing: 7) {
                            Text(open ? "Close" : "Average down").font(InkFont.mono(10)).tracking(10 * 0.07)
                            Text(open ? "←" : "→").font(.system(size: 11))
                        }
                        .foregroundStyle(open ? Ink.invertText : Ink.text)
                        .padding(.horizontal, 12).frame(minHeight: 30)
                        .background(Capsule().fill(open ? Ink.invertBg : .clear))
                        .overlay(Capsule().strokeBorder(open ? .clear : Ink.hair, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                HeroSplit {
                    InkDelta(value: nvUsdS(p.sharesPL), good: p.sharesPL >= 0, size: 40, weight: .medium)
                    unitLabel("open · shares")
                } side: {
                    InkRoll(text: "$\(nvDec(p.spot, 2))", font: InkFont.mono(20, .regular), tracking: 20 * -0.03, color: Ink.text)
                    Text("LIVE SPOT").font(InkFont.mono(10.5)).tracking(10.5 * 0.06)
                        .foregroundStyle(Ink.dim).padding(.top, 8).fixedSize()
                }
                if perShare > 0 {
                    InkBullets(items: ["$\(nvDec(perShare, 2)) a share collected — calls only"])
                }
                InkSpacer()
                InkBand3(items: [("Average buy", "$\(nvDec(p.avgBuy, 2))"),
                                 ("New average", "$\(nvDec(p.breakEven, 2))"),
                                 ("Quantity", nvInt(p.shares))])
            }
            InkFoot {
                InkBars(leftK: "Paid", leftV: p.sharesPaid, rightK: "Value now", rightV: p.sharesValue,
                        hue: p.sharesPL >= 0 ? Ink.gain : Ink.loss) {
                    InkDelta(value: nvUsd(abs(p.sharesPL)), good: p.sharesPL >= 0, size: 17)
                }
            }
        }
    }
}

private struct AverageDownCard: View {
    let p: NvPosition
    let high52: Double?
    @State private var lot = 500
    var body: some View {
        let qty = p.shares
        let avg = qty + Double(lot) > 0 ? (qty * p.avgBuy + Double(lot) * p.spot) / (qty + Double(lot)) : p.avgBuy
        let cut = p.avgBuy - avg
        let costNow = Double(lot) * p.spot
        let high = high52 ?? p.avgBuy
        let offHigh = high > 0 ? (avg - high) / high * 100 : 0
        let trig: [(p: Int, price: Double, avg: Double)] = [1, 2].map { pc in
            let price = p.spot * (1 - Double(pc) / 100)
            return (pc, price, (qty * p.avgBuy + Double(lot) * price) / (qty + Double(lot)))
        }
        return InkCard(stamp: (.live, "Priced off live spot")) {
            InkBody {
                InkEyebrow(cat: "Average down") { InkBand(skin: .mod, text: "\(lot) sh") }
                HeroSplit {
                    InkRoll(text: "$\(nvDec(avg, 2))", font: InkFont.mono(40, .medium), tracking: 40 * -0.04, color: Ink.text)
                    unitLabel("new average")
                } side: {
                    InkDelta(value: "−$\(nvDec(cut, 2))", good: true, size: 20)
                    Text("off $\(nvDec(p.avgBuy, 2))".uppercased()).font(InkFont.mono(10.5)).tracking(10.5 * 0.06)
                        .foregroundStyle(Ink.dim).padding(.top, 8).fixedSize()
                }
                HStack(spacing: 4) {
                    ForEach([500, 1000, 1500, 2000], id: \.self) { n in
                        let on = lot == n
                        Button { withAnimation(InkMotion.fast) { lot = n } } label: {
                            Text("\(n)").font(InkFont.mono(11.5)).tracking(11.5 * -0.01)
                                .foregroundStyle(on ? Ink.invertText : Ink.dim)
                                .frame(maxWidth: .infinity).frame(minHeight: 34)
                                .background(RoundedRectangle(cornerRadius: Ink.radiusElement, style: .continuous).fill(on ? Ink.invertBg : .clear))
                                .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement, style: .continuous).strokeBorder(on ? Ink.text : Ink.hair, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 14)
                InkSpacer()
                VStack(spacing: 0) {
                    LedgerLine(k: "Costs", sub: "at $\(nvDec(p.spot, 2))", v: nvUsd(costNow), first: true)
                    LedgerLine(k: "Block becomes", sub: "shares held", v: nvInt(qty + Double(lot)))
                    LedgerLine(k: "Below the high", sub: "52-week $\(nvDec(high, 2))",
                               v: high52 == nil ? "—" : "\(nvDec(offHigh, 1))%", hue: Ink.gain)
                }
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
            }
            InkFoot {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ADD AGAIN AT").font(InkFont.mono(9)).tracking(9 * 0.16).foregroundStyle(Ink.dim)
                    HStack(spacing: 0) {
                        ForEach(trig, id: \.p) { x in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("$\(nvDec(x.price, 2))").font(InkFont.mono(16)).tracking(16 * -0.02).foregroundStyle(Ink.text)
                                Text("−\(x.p)% · avg $\(nvDec(x.avg, 2))".uppercased()).font(InkFont.mono(8.5)).tracking(8.5 * 0.1).foregroundStyle(Ink.dim)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, x.p == 2 ? 12 : 0)
                            .overlay(alignment: .leading) { if x.p == 2 { Rectangle().fill(Ink.hair).frame(width: 1) } }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Sleeve group card (one per leg type · total made + int/ext toggle)

private struct SleeveGroupCard: View {
    let leg: NvGroup
    let pageStrikes: [NvStrike]
    var page: Int = 0
    var pageCount: Int = 1
    let n: String
    let spot: Double
    let fresh: NvFresh
    let freshText: String
    let realized: Double
    @State private var open: Int? = nil
    @State private var intrinsic = false

    var body: some View {
        let short = pageStrikes.first?.side == "short"
        let ct = pageStrikes.reduce(0) { $0 + $1.ct }
        // `current` is (mark ?? 0), so an unmarked LIVE leg reads as worth nothing and
        // a long position books its whole cost as a loss — the −$87K on 75 puts that
        // had not moved. Only legs we can actually price contribute to value or P&L;
        // an expired leg is genuinely worth zero and stays in. Paid is summed over
        // every leg regardless, because that money was really spent.
        let priced = pageStrikes.filter { ($0.mark ?? 0) > 0 || $0.expired }
        let basis = pageStrikes.reduce(0) { $0 + $1.basis }
        let pricedBasis = priced.reduce(0) { $0 + $1.basis }
        let cur = priced.reduce(0) { $0 + $1.current }
        let net = short ? pricedBasis - cur : cur - pricedBasis   // unrealized, priced legs only
        let ie = pageStrikes.reduce((int: 0.0, ext: 0.0)) { acc, s in
            guard let x = legIntExt(kind: s.kind, strike: s.strike, mark: s.mark, ct: s.ct, spot: spot) else { return acc }
            return (acc.int + x.int, acc.ext + x.ext)
        }
        let soonest = pageStrikes.map { $0.expired ? 0 : (Int($0.dte.prefix(while: \.isNumber)) ?? 999) }.min() ?? 999
        let cat = pageCount > 1 ? "\(leg.label) · \(page + 1)/\(pageCount)" : leg.label
        let sub = realized != 0 ? "\(nvUsd(realized)) realized"
            : (page == 0 ? "nothing realized yet" : "this expiry group")

        return InkCard(stamp: (stampState(fresh), soonest <= 1 ? "Updated now · nearest leg expires today" : freshText)) {
            InkBody {
                InkEyebrow(n: n, cat: cat, glyph: leg.glyph) {
                    InkBand(skin: .low, text: "\(Int(ct.rounded())) ct")
                }
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        InkDelta(value: nvUsdS(net), good: net >= 0, size: 40, weight: .medium)   // unrealized
                        Text(sub.uppercased()).font(InkFont.mono(11.5, .medium)).tracking(11.5 * 0.05)
                            .foregroundStyle(Ink.dim).padding(.top, 12).lineLimit(1)              // realized
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                    Button { withAnimation(InkMotion.fast) { intrinsic.toggle() } } label: {
                        VStack(alignment: .trailing, spacing: 0) {
                            InkRoll(text: nvUsd(intrinsic ? ie.int : ie.ext), font: InkFont.mono(20, .regular), tracking: 20 * -0.03, color: Ink.text)
                            Text((intrinsic ? "intrinsic" : "extrinsic left").uppercased()).font(InkFont.mono(10.5)).tracking(10.5 * 0.06)
                                .foregroundStyle(Ink.dim).underline(true, color: Ink.hair).padding(.top, 8).fixedSize()
                        }
                        .padding(.leading, 14)
                        .overlay(alignment: .leading) { Rectangle().fill(Ink.hair).frame(width: 1) }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 20)
                VStack(spacing: 0) {
                    ForEach(Array(pageStrikes.enumerated()), id: \.offset) { _, s in
                        Button { withAnimation(InkMotion.fast) { intrinsic.toggle() } } label: {
                            LedgerRow(s: s, spot: spot, intrinsic: intrinsic)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 20)   // each row draws its own top hairline; no container rule
                InkSpacer()
            }
            InkFoot {
                InkBars(leftK: short ? "Collected" : "Paid", leftV: basis,
                        rightK: short ? "To close" : "Value now", rightV: cur,
                        hue: net >= 0 ? Ink.gain : Ink.loss) {
                    InkDelta(value: nvUsd(abs(net)), good: net >= 0, size: 17)
                }
            }
        }
    }
}

// MARK: - ledger row (a strike inside a sleeve card · reads int or ext)

private struct LedgerRow: View {
    let s: NvStrike
    let spot: Double
    let intrinsic: Bool
    var body: some View {
        let days = s.expired ? 0 : (Int(s.dte.prefix(while: \.isNumber)) ?? 999)
        let rank: InkRelevance = (s.expired || days <= 7) ? .r1 : days <= 200 ? .r2 : .r3
        let x = legIntExt(kind: s.kind, strike: s.strike, mark: s.mark, ct: s.ct, spot: spot)
        let value = x.map { intrinsic ? $0.int : $0.ext }
        let pct = x.map { Int((intrinsic ? 100 - $0.extPct : $0.extPct).rounded()) }
        let whenStr = s.expired ? "Expired" : (days == 0 ? "Today" : days == 1 ? "Tomorrow" : s.expiry)
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(nvStrike(s.strike)).font(InkFont.mono(15.5)).tracking(15.5 * -0.01).foregroundStyle(Ink.text)
                    Text("\(Int(s.ct)) CT").font(InkFont.mono(10.5)).tracking(10.5 * 0.06).foregroundStyle(Ink.dim)
                }
                Text("\(whenStr) · \(s.moneyness)".uppercased())
                    .font(InkFont.mono(10.5)).tracking(10.5 * 0.06).foregroundStyle(Ink.dim)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                Text(value == nil ? "—" : nvUsd(value!)).font(InkFont.mono(15.5)).tracking(15.5 * -0.02).foregroundStyle(Ink.text)
                Text(pct == nil ? "no mark" : "\(pct!)% of mark").font(InkFont.mono(10.5)).tracking(10.5 * 0.06).foregroundStyle(Ink.dim)
            }
        }
        .frame(minHeight: 46)
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
        .inkRelevance(rank)
    }
}

#if DEBUG
/// Renders the Shares + Average-down pair standalone so their body/foot padding
/// is measurable without driving the rail. -inkAvg.
struct NvdaAvgDownPreviewHarness: View {
    let store: NvdaStore
    var body: some View {
        if let p = store.position {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    InkSectionHead(title: "Average down")
                    AverageDownCard(p: p, high52: store.high52).padding(.horizontal, 16)
                    SharesCard(p: p, perShare: store.perf?.perShare ?? 0, open: false, onToggle: {})
                        .padding(.horizontal, 16).padding(.top, 24)
                }
            }
        }
    }
}

/// Renders one sleeve card standalone so the ledger (where the double-hairline
/// lived) is visible for QA. -inkSleeve.
struct NvdaSleevePreviewHarness: View {
    let store: NvdaStore
    var body: some View {
        if let p = store.position, let g = p.groups.first {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    InkSectionHead(title: "Sleeve card")
                    SleeveGroupCard(leg: g, pageStrikes: Array(g.strikes.prefix(3)), page: 0, pageCount: 1,
                                    n: "01", spot: p.spot, fresh: p.fresh, freshText: p.freshText, realized: 15700)
                        .padding(.horizontal, 16)
                }
            }
        }
    }
}
#endif
