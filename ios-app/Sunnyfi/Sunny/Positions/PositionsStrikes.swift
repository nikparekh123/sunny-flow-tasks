//
//  PositionsStrikes.swift
//  Sunny
//
//  Phone Intelligence is SunnyStrikes, look card (handoff 2026-11-24-final-2 §2.3; reference/SunnyStrikes.dc.html):
//  the title alone (no explainer under it), every expiry sunny-sd sends as chips, Calls | Puts, the strikes from 0.25 to
//  2 SD as tiles in one row you swipe (140 × 172, snapping to each tile, the next one peeking), then the picked strike's
//  card, then Your trade with Try in Payoff.
//    A tile, left aligned: the SD, the strike, the win rate, OI, and the level at its foot.
//    Win rate = the chance it finishes out of the money = 1 − the row's itm (the chain, this expiry).
//    OI = the chain's open interest at the strike (sunny-sd rows[].oi, Theta's chain snapshot); left out when not sent.
//    The level: "At 20-day" when a level sits on the strike (within half a strike step, at least 0.4% of the price),
//    "Hits ceiling first" for the first one the stock meets on the way; the priced move is left out of the tile.
//    Levels: the gamma walls for this expiry (ceiling, floor, flip; Home's walls when the reply has none), the nearest
//    resistance above and support below (the technicals' zones), the 20, 50, 100 and 200-day averages.
//  The strike card, top to bottom: the title ("Sell the 36 call") with one grey line ("Oct 30 · 3 days · 2.0% above
//  today") and what it collects a contract on the right; one soft box with the priced move and the trend (each with its
//  why in grey), and "Earnings Nov 18 come first." when they do; On the way up | down, the levels as rows (the name with
//  on the strike, in the way or past the strike; the price and its SD); then Contracts with Add. No win rate tile, no
//  in-the-way sentence and no Details fold (Nik, 24 Nov 2026: the tile shows the win rate and OI, the rows say it).
//  Everything is worked out once per reply (PositionsMemo.strikes); the view only picks.
//  No em dashes in any words here; no minus signs.
//

import SwiftUI

struct PosStrikes {
    struct Exp: Identifiable { let id: String; let i: Int; let l1: String; let l2: String; let label: String }
    enum LvKind { case at, way, past }
    /// A level as a row: its name ("Ceiling", "20-day average"), where it sits ("on the strike", "in the way",
    /// "past the strike"), its price and how far it is from today in SD.
    struct Lv: Identifiable { let id: String; let n: String; let w: String; let p: String; let z: String; let kind: LvKind; let price: Double }
    /// A line in the card's soft box: bold, with its why in grey under it ("" for none).
    struct Line: Identifiable { let id: String; let a: String; let b: String }
    struct Strike: Identifiable {
        let id: String
        let ex: String
        let ty: String
        let K: Double
        /// The SD level's place (0.25 → 0 ... 2 → 7).
        let i: Int
        let sd: String
        let wr: Int
        let oi: String?
        let tl: String
        let tlAt: Bool
        let pr: Double
        let title: String
        let when: String
        let lv: [Lv]
        let lines: [Line]
    }
    let t: String
    let S: Double
    let exps: [Exp]
    /// "index:c" or "index:p" → the strikes, nearest first.
    let strikes: [String: [Strike]]
    /// The expiry Intelligence opens on (this Friday's, or the next on a Friday).
    let open: Int
    /// Calls still covered at each expiry (the engine's cover check), and the calls already sold for it.
    let free: [Int: Int]
    let soldAt: [Int: Int]

    func tiles(_ ei: Int, _ side: String) -> [Strike] { strikes["\(ei):\(side)"] ?? [] }

    static let LVS: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    static func build(_ d: SDReply, friday: String, today: String, homeWalls: JSONValue?) -> PosStrikes? {
        guard d.ok != false, !d.exps.isEmpty, d.price > 0 else { return nil }
        let S = d.price, t0 = PE.dayNum(today) ?? 0
        let tech = d.tech
        let f2 = { (x: Double) in String(format: "%.2f", abs(x)) }
        let lst = { (a: [String]) -> String in a.count <= 1 ? (a.first ?? "") : a.dropLast().joined(separator: ", ") + " and " + a.last! }
        let sup = tech?.zones?.filter { $0.kind == "support" && $0.mid < S }.max { $0.mid < $1.mid }?.mid
        let res = tech?.zones?.filter { $0.kind == "resistance" && $0.mid > S }.min { $0.mid < $1.mid }?.mid
        let MA: [(Int, Double?)] = [(20, tech?.sma20), (50, tech?.sma50), (100, tech?.sma100), (200, tech?.sma200)]
        // The trend line (the same for every strike).
        let have = MA.compactMap { n, v in (v ?? 0) > 0 ? (n, v!) : nil }
        let hold = have.filter { $0.1 < S }.map { String($0.0) }, under = have.filter { $0.1 >= S }.map { String($0.0) }
        let rsi = tech?.rsi14.map { Int(PE.jsRound($0)) }
        let rsT = rsi.map { $0 <= 30 ? " oversold" : $0 >= 70 ? " overbought" : "" } ?? ""
        let trend: Line? = have.isEmpty ? nil : Line(id: "tr",
            a: hold.count == have.count ? "Healthy trend." : hold.isEmpty ? "Weak trend." : "Mixed trend.",
            b: (hold.isEmpty ? "Under all \(have.count == 4 ? "four" : String(have.count)) averages" : "Above the \(lst(hold))-day")
                + (!hold.isEmpty && !under.isEmpty ? ", under the \(lst(under))-day" : "") + (rsi.map { ", RSI \($0)\(rsT)" } ?? "") + ".")
        // "Earnings Nov 18 come first." (handoff §2.3: the line alone, no why under it).
        let ernL = d.events?.earnings.map { PosFmt.md(String($0.prefix(10))) }
        let SN: [String: String] = ["Ceiling": "ceiling", "Floor": "floor", "Flip": "flip", "Resistance": "resistance", "Support": "support",
                                    "20-day average": "20-day", "50-day average": "50-day", "100-day average": "100-day", "200-day average": "200-day"]
        // The cover check (sd-engine cover()): calls covered by the shares, then the calls bought that last to each.
        let soldC = d.sold.filter { !$0.put }.map { (K: $0.K, n: $0.n, ex: $0.ex) }

        var exps: [Exp] = [], strikes: [String: [Strike]] = [:], free: [Int: Int] = [:], soldAt: [Int: Int] = [:]
        for (ei, e) in d.exps.enumerated() {
            let cd = Int(e.cd.rounded()), days = (PE.dayNum(e.ex) ?? t0) - t0
            let year = String(e.ex.prefix(4))
            exps.append(Exp(id: e.ex, i: ei, l1: PosFmt.md(e.ex), l2: days < 60 ? "\(max(0, days)) \(days == 1 ? "day" : "days")" : year, label: e.label))
            soldAt[ei] = Int(d.sold.filter { !$0.put && $0.ex == e.ex }.reduce(0) { $0 + $1.n })
            if let c = d.cover {
                let otm = c.otm.map { (n: $0.n, ex: $0.ex) }
                let base = PE.coverCheck(shares: c.shares, held: soldC, otm: otm, sale: nil, ex: e.ex)
                var lo = 0
                if base.uncovered == 0 {
                    var hi = 999
                    while lo < hi {
                        let mid = (lo + hi + 1) / 2
                        if PE.coverCheck(shares: c.shares, held: soldC, otm: otm, sale: (K: 0, n: Double(mid)), ex: e.ex).uncovered == 0 { lo = mid } else { hi = mid - 1 }
                    }
                }
                free[ei] = lo
            }
            // This expiry's walls: the reply's gamma (the biggest of each kind), else Home's.
            var ceil: Double?, floor: Double?, flip: Double?
            if let g = e.gamma {
                flip = g.flip
                ceil = g.walls.filter { $0.kind == "ceiling" }.max { abs($0.gex) < abs($1.gex) }?.K
                floor = g.walls.filter { $0.kind == "floor" }.max { abs($0.gex) < abs($1.gex) }?.K
            } else if let c = homeWalls?.array.first(where: { $0["ex"].string == e.ex }) {
                flip = c["flip"].double; ceil = c["c"]["k"].double; floor = c["f"]["k"].double
            }
            let mv = e.m
            let LV: [(String, Double)] = ([("Ceiling", ceil), ("Floor", floor), ("Flip", flip), ("Resistance", res), ("Support", sup)]
                + MA.map { ("\($0.0)-day average", $0.1) }
                + [("IV move", mv > 0 ? S * exp(mv) : nil), ("IV move", mv > 0 ? S * exp(-mv) : nil)])
                .compactMap { b, v in (v ?? 0) > 0 ? (b, v!) : nil }
            let zOf = { (p: Double) in mv > 0 ? String(format: "%.2f SD", abs(log(p / S)) / mv) : "" }
            let ks = (e.ks ?? []).sorted()
            let stepAt = { (K: Double) -> Double in
                guard let j = ks.firstIndex(where: { $0 >= K - 1e-9 }) else { return PE.stepOf(S) }
                let a = j > 0 ? K - ks[j - 1] : .infinity, b = j + 1 < ks.count ? ks[j + 1] - K : .infinity
                let s = min(a, b); return s.isFinite && s > 0 ? s : PE.stepOf(S)
            }
            // The soft box: the priced move by this expiry, the trend, and the earnings when they come first.
            var lines: [Line] = []
            if mv > 0 { lines.append(Line(id: "mv", a: "Priced to move ±$\(f2(S * mv)) (\(String(format: "%.1f", mv * 100))%)", b: "by \(e.label).")) }
            if let trend { lines.append(trend) }
            if e.earn == true, let ernL { lines.append(Line(id: "er", a: "Earnings \(ernL) come first.", b: "")) }
            for side in ["c", "p"] {
                let c = side == "c"
                let rows = (c ? e.rows?.c : e.rows?.p) ?? []
                var seen = Set<Double>(), out: [Strike] = []
                for r in rows where r.k > 0 {
                    let K = r.K
                    guard c ? K > S : K < S, !seen.contains(K), let li = LVS.firstIndex(where: { abs($0 - r.k) < 1e-6 }) else { continue }
                    seen.insert(K)
                    let pct = abs(K / S - 1) * 100
                    let wr = Int(PE.jsRound((1 - r.itm) * 100)), pr = max(0.01, r.pr)
                    let tol = max(stepAt(K) * 0.5, S * 0.004)
                    let at = LV.filter { abs($0.1 - K) <= tol }
                    let atN = Set(at.map(\.0))
                    let way = LV.filter { !atN.contains($0.0) && (c ? $0.1 > S && $0.1 < K : $0.1 < S && $0.1 > K) }.sorted { abs($0.1 - S) < abs($1.1 - S) }
                    let nx = LV.filter { !atN.contains($0.0) && (c ? $0.1 > K : $0.1 < K) }.min { abs($0.1 - K) < abs($1.1 - K) }
                    var lv: [Lv] = at.map { Lv(id: "a" + $0.0 + f2($0.1), n: $0.0, w: "on the strike", p: f2($0.1), z: zOf($0.1), kind: .at, price: $0.1) }
                        + way.map { Lv(id: "w" + $0.0 + f2($0.1), n: $0.0, w: "in the way", p: f2($0.1), z: zOf($0.1), kind: .way, price: $0.1) }
                    if let nx { lv.append(Lv(id: "x" + nx.0 + f2(nx.1), n: nx.0, w: "past the strike", p: f2(nx.1), z: zOf(nx.1), kind: .past, price: nx.1)) }
                    lv.sort { c ? $0.price < $1.price : $0.price > $1.price }
                    let lvA = at.first { SN[$0.0] != nil }, lvW = way.first { SN[$0.0] != nil }
                    let tl = lvA.map { "At " + SN[$0.0]! } ?? lvW.map { "Hits " + SN[$0.0]! + " first" } ?? ""
                    let oiT: String? = r.oi.map { $0 >= 999.5 ? PE.num($0 / 1000, 1) + "K" : String(Int($0.rounded())) }
                    out.append(Strike(id: "\(e.ex):\(side):\(PE.jsNum(K))", ex: e.ex, ty: side, K: K, i: li, sd: PE.sdK(r.k) + " SD", wr: wr, oi: oiT,
                                      tl: tl, tlAt: lvA != nil, pr: pr, title: "Sell the \(PE.fk(K)) \(c ? "call" : "put")",
                                      when: "\(e.label) · \(cd) \(cd == 1 ? "day" : "days") · \(String(format: "%.1f", pct))% \(c ? "above" : "below") today",
                                      lv: lv, lines: lines))
                }
                strikes["\(ei):\(side)"] = out
            }
        }
        let openIso = PE.openExpiry(d.exps.map(\.ex), friday: friday, today: today)
        return PosStrikes(t: d.t, S: S, exps: exps, strikes: strikes, open: d.exps.firstIndex { $0.ex == openIso } ?? 0, free: free, soldAt: soldAt)
    }
}

/// What is picked in Intelligence, per name: the expiry, the side and the SD level.
struct PosStrikeSel: Hashable { var ex: Int?; var side = "c"; var lv = 3 }

// MARK: - The view

struct PosStrikesView: View {
    let t: String
    let m: PosStrikes?
    let failed: Bool
    let loaded: Bool
    @Binding var sel: PosStrikeSel
    /// Contracts added per strike ("2026-11-27:c:160" → 2).
    @Binding var trade: [String: Int]
    /// The trade here is the one in Payoff (the button undoes it).
    let tried: Bool
    let onTry: ([(ty: String, K: Double, ex: String, n: Int)]) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce

    private static let selSub = S.dyn(0xC8C8C8, 0x383838)
    private static let tileFill = S.dynA(0xFAFAFA, 0.9, 0xFAFAFA, 0.06)
    private static let tileRing = S.dynA(0x212121, 0.08, 0xFAFAFA, 0.10)
    private static let stepFill = Color(.sRGB, red: 118 / 255, green: 118 / 255, blue: 128 / 255, opacity: 0.24)
    /// The card's soft box (rgba(255,255,255,.05) in the design) and its section rules (.10).
    private static let softFill = S.dynA(0x212121, 0.04, 0xFAFAFA, 0.05)
    private static let cardRule = S.dynA(0x212121, 0.10, 0xFAFAFA, 0.10)

    private func km(_ x: Double) -> String { PosFmt.money(x) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The title alone, then the content (Nik, 24 Nov 2026: no explainer under it).
            Text("Intelligence").sType(PT.t(22, 28, 700), tabular: false).foregroundStyle(PC.ink).accessibilityAddTraits(.isHeader)
            if let m, !m.exps.isEmpty {
                content(m)
            } else {
                Text(failed ? "Could not read \(t)’s option chain just now." : loaded ? "No expiries for \(t) yet." : "Reading \(t)’s option chain…")
                    .sType(PT.t(14, 20), tabular: false).foregroundStyle(PC.mu)
            }
        }
    }

    @ViewBuilder private func content(_ m: PosStrikes) -> some View {
        let ei = min(max(0, sel.ex ?? m.open), m.exps.count - 1), e = m.exps[ei]
        let tiles = m.tiles(ei, sel.side)
        let pick = tiles.first { $0.i == sel.lv } ?? tiles.min { abs($0.i - sel.lv) < abs($1.i - sel.lv) }
        expiryChips(m, ei)
        Picker("Calls or puts", selection: Binding(get: { sel.side }, set: { sel.side = $0 })) {
            Text("Calls").tag("c")
            Text("Puts").tag("p")
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .sensoryFeedback(.selection, trigger: sel.side)
        if tiles.isEmpty {
            Text("No strikes from 0.25 to 2 SD for \(e.label) yet.").sType(PT.t(14, 20), tabular: false).foregroundStyle(PC.mu)
        } else {
            tileRow(tiles, pick?.id, page: "\(ei):\(sel.side)")
            if let s = pick { card(m, e, ei, s) }
        }
        // Your trade shows once a contract is added (no empty-state how-to line).
        if trade.values.contains(where: { $0 > 0 }) { yourTrade(m) }
    }

    private func expiryChips(_ m: PosStrikes, _ ei: Int) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(m.exps) { x in
                    let on = x.i == ei, n = trade.keys.filter { $0.hasPrefix(x.id + ":") && (trade[$0] ?? 0) > 0 }.count
                    Button { sel.ex = x.i } label: {
                        VStack(spacing: 1) {
                            Text(x.l1).sType(PT.t(14, 18, 600), tabular: true).foregroundStyle(on ? PC.onInk : PC.ink)
                            Text(x.l2).sType(PT.t(12, 14), tabular: true).foregroundStyle(on ? Self.selSub : PC.mu)
                        }
                        .lineLimit(1)
                        .padding(.horizontal, 12).frame(minWidth: 64).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? PC.ink : Self.tileFill))
                        .overlay {
                            if !on { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(n > 0 ? PC.ink.opacity(0.7) : Self.tileRing, lineWidth: n > 0 ? 1.5 : 1) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(PosSay.words("\(x.label), \(x.l2)") + (n > 0 ? ", \(n) in your trade" : ""))
                    .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.bottom, 2)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.horizontal, -16)
        .sensoryFeedback(.selection, trigger: sel.ex)
    }

    /// The strikes in one row you swipe (handoff §2.3): it snaps to each tile, no scrollbar, the next tile peeks at the
    /// edge. The design's row reaches 6 pt past the content on each side (the count badge sits over a tile's corner).
    /// A new expiry or side brings the picked tile into view; a tap never moves the row.
    private func tileRow(_ tiles: [PosStrikes.Strike], _ picked: String?, page: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(tiles) { s in tile(s, on: s.id == picked).id(s.id) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8).padding(.bottom, 10)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 6, for: .scrollContent)
            .padding(.horizontal, -6)
            .padding(.top, -8).padding(.bottom, -10)
            .onAppear { if let picked { proxy.scrollTo(picked, anchor: .leading) } }
            .onChange(of: page) { _, _ in
                guard let picked else { return }
                withAnimation(S.moving(.easeOut(duration: 0.3), reduce)) { proxy.scrollTo(picked, anchor: .leading) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Strikes from 0.25 to 2 SD")
    }

    /// A strike tile, 140 × 172, radius 18, left aligned: the SD 14 grey, the strike 30 bold, the win rate 17 bold, OI 14
    /// grey, the level 14 at the foot. The picked tile is filled (white in dark, as the design).
    private func tile(_ s: PosStrikes.Strike, on: Bool) -> some View {
        let n = trade[s.id] ?? 0, fg = on ? PC.onInk : PC.ink, sc = on ? Self.selSub : PC.mu
        let lc = on ? (s.tlAt ? PC.onInk : Self.selSub) : (s.tlAt ? PC.ink : PC.muT)
        return Button { sel.lv = s.i } label: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.sd).sType(PT.t(14, 18, 500), tabular: true).foregroundStyle(sc)
                    Text(PE.fk(s.K)).sType(PT.t(30, 34, 700, tr: -0.02)).foregroundStyle(fg).minimumScaleFactor(0.7)
                    Text("\(s.wr)% win").sType(PT.t(17, 22, 700)).foregroundStyle(fg).padding(.top, 6)
                    if let oi = s.oi { Text("OI \(oi)").sType(PT.t(14, 18)).foregroundStyle(sc) }
                }
                Spacer(minLength: 0)
                // At the foot (the design's margin-top: auto; 4 of gap and 10 above it).
                if !s.tl.isEmpty {
                    Text(s.tl).sType(PT.t(14, 19, s.tlAt ? 600 : 500), tabular: false).foregroundStyle(lc)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
                }
            }
            .lineLimit(1)
            .padding(.top, 14).padding(.horizontal, 14).padding(.bottom, 16)
            .frame(width: 140, alignment: .topLeading)
            .frame(minHeight: 172, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? PC.ink : Self.tileFill))
            .overlay { if !on { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Self.tileRing, lineWidth: 1) } }
            .overlay(alignment: .topTrailing) {
                if n > 0 {
                    Text("\(n)").sType(PT.t(11, 13, 700)).foregroundStyle(PC.onInk)
                        .padding(.horizontal, 5).frame(minWidth: 18).frame(height: 18)
                        .background(Capsule().fill(PC.ink))
                        .background(Capsule().fill(PC.page).padding(-2))
                        .offset(x: 4, y: -5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PosSay.words("\(PE.fk(s.K)) \(s.ty == "c" ? "call" : "put"), \(s.sd), \(s.wr)% win rate" + (s.oi.map { ", open interest \($0)" } ?? "") + (s.tl.isEmpty ? "" : ", " + s.tl.lowercased())))
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .sensoryFeedback(.selection, trigger: on)
    }

    /// The picked strike's card (handoff §2.3): the header, the soft box, On the way up | down, then Contracts with Add.
    private func card(_ m: PosStrikes, _ e: PosStrikes.Exp, _ ei: Int, _ s: PosStrikes.Strike) -> some View {
        let n = trade[s.id] ?? 0, c = s.ty == "c"
        let nCx = trade.filter { $0.key.hasPrefix(e.id + ":c:") }.reduce(0) { $0 + $1.value }
        let cov: String = c ? (m.free[ei].map { free in
            free > 0 ? "\(free) more \(free == 1 ? "call" : "calls") covered for \(e.l1)" + (nCx > free ? ": \(nCx - free) of yours not" : "")
                : "No covered calls left for \(e.l1)" + ((m.soldAt[ei] ?? 0) > 0 ? ", \(m.soldAt[ei]!) already sold" : "")
        } ?? "") : "Sets aside \(km(s.K * 100)) a contract" + (n > 0 ? ", \(km(s.K * 100 * Double(n))) in all" : "")
        return VStack(alignment: .leading, spacing: 16) {
            // 1. The title and one grey line; what it collects a contract, big, on the right.
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title).sType(PT.t(20, 26, 700), tabular: true).foregroundStyle(PC.ink)
                    Text(s.when).sType(PT.t(14, 20), tabular: true).foregroundStyle(PC.mu).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(km(s.pr * 100)).sType(PT.t(34, 38, 800, tr: -0.03)).foregroundStyle(PC.ink)
                    Text("a contract").sType(PT.t(13, 18), tabular: false).foregroundStyle(PC.mu)
                }
                .lineLimit(1)
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(PosSay.words("Collects \(km(s.pr * 100)) a contract"))
            }
            // 2. The priced move and the trend, each with its why in grey.
            if !s.lines.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(s.lines) { ln in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ln.a).sType(PT.t(17, 23, 600), tabular: true).foregroundStyle(PC.ink)
                            if !ln.b.isEmpty { Text(ln.b).sType(PT.t(14, 20), tabular: true).foregroundStyle(PC.mu) }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, 14).padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Self.softFill))
            }
            // 3. On the way up | down: the levels as rows.
            VStack(alignment: .leading, spacing: 0) {
                // A plain word as written, 13 pt 500 grey, no tracking (focus §2.5).
                Text(c ? "On the way up" : "On the way down").sType(PT.t(13, 18, 500), tabular: false).foregroundStyle(SF.grey)
                    .padding(.bottom, 4)
                    .accessibilityLabel(c ? "On the way up" : "On the way down")
                    .accessibilityAddTraits(.isHeader)
                if s.lv.isEmpty {
                    Text("Nothing between today and the strike.").sType(PT.t(15, 21), tabular: false).foregroundStyle(PC.muT).padding(.vertical, 8)
                }
                ForEach(s.lv) { v in
                    let col = v.kind == .at ? PC.ink : v.kind == .way ? PC.bright : PC.mu
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.n).sType(PT.t(17, 22, 600), tabular: false).foregroundStyle(col)
                            Text(v.w).sType(PT.t(13, 18), tabular: false).foregroundStyle(PC.mu)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(v.p).sType(PT.t(17, 22, 600)).foregroundStyle(col)
                            Text(v.z).sType(PT.t(13, 18)).foregroundStyle(PC.mu)
                        }
                        .fixedSize()
                    }
                    .lineLimit(1)
                    .frame(minHeight: 56)
                    .padding(.vertical, 8)
                    .padding(.bottom, 1)
                    .overlay(alignment: .bottom) { Rectangle().fill(PEC.rowRule).frame(height: 1) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(PosSay.words("\(v.n), \(v.w), \(v.p), \(v.z)"))
                }
            }
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(Self.cardRule).frame(height: 1) }
            // 4. Contracts with Add.
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(n > 0 ? "Collects \(km(s.pr * 100 * Double(n)))" : "Contracts").sType(PT.t(16, 21, 600), tabular: true).foregroundStyle(PC.ink)
                    if !cov.isEmpty { Text(cov).sType(PT.t(13, 18), tabular: true).foregroundStyle(PC.mu).fixedSize(horizontal: false, vertical: true) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if n == 0 {
                    Button { bump(s.id, 1) } label: {
                        Text("Add").sType(PT.t(15, 20, 600), tabular: false).foregroundStyle(PC.onInk)
                            .padding(.horizontal, 20).frame(height: 44).background(Capsule().fill(PC.ink))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a contract, sell the \(PE.fk(s.K)) \(c ? "call" : "put") for \(e.label)")
                } else {
                    HStack(spacing: 0) {
                        Button { bump(s.id, -1) } label: {
                            Image(systemName: "minus").font(.system(size: 17, weight: .medium)).foregroundStyle(PC.ink).frame(width: 48, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel("One fewer")
                        Text("\(n)").sType(PT.t(17, 22, 700)).foregroundStyle(PC.ink).frame(minWidth: 28)
                        Button { bump(s.id, 1) } label: {
                            Image(systemName: "plus").font(.system(size: 17, weight: .medium)).foregroundStyle(PC.ink).frame(width: 48, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel("One more")
                    }
                    .background(Capsule().fill(Self.stepFill))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(n) contracts")
                }
            }
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(Self.cardRule).frame(height: 1) }
        }
        .padding(.top, 20).padding(.horizontal, 18).padding(.bottom, 18)
        .sunnyGlass(radius: 22)
        .sensoryFeedback(.increase, trigger: n)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The \(PE.fk(s.K)) \(c ? "call" : "put") for \(e.label)")
    }

    private func bump(_ id: String, _ d: Int) {
        let v = max(0, (trade[id] ?? 0) + d)
        if v == 0 { trade[id] = nil } else { trade[id] = v }
    }

    /// Your trade: each strike added, what it collects, Try in Payoff (then In Payoff · Undo).
    private func yourTrade(_ m: PosStrikes) -> some View {
        let all = m.strikes.values.flatMap { $0 }
        let rows = trade.keys.sorted().compactMap { k -> (k: String, s: PosStrikes.Strike, n: Int)? in
            guard let n = trade[k], n > 0, let s = all.first(where: { $0.id == k }) else { return nil }
            return (k, s, n)
        }
        let tot = rows.reduce(0) { $0 + $1.s.pr * 100 * Double($1.n) }, hold = rows.filter { $0.s.ty == "p" }.reduce(0) { $0 + $1.s.K * 100 * Double($1.n) }
        let nC = rows.filter { $0.s.ty == "c" }.count, nP = rows.count - nC
        let exL = { (iso: String) in m.exps.first { $0.id == iso }?.label ?? PosFmt.md(iso) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Your trade").sType(PT.t(13, 18, 600), tabular: false).foregroundStyle(PC.ink).accessibilityAddTraits(.isHeader)
            ForEach(rows, id: \.k) { r in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    (Text("Sell \(r.n) × \(PE.fk(r.s.K)) \(r.s.ty == "c" ? "call" : "put") ") + Text(exL(r.s.ex)).foregroundStyle(PC.mu))
                        .sType(PT.t(14, 20), tabular: true).foregroundStyle(PC.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(km(r.s.pr * 100 * Double(r.n))).sType(PT.t(14, 20, 600)).foregroundStyle(PC.ink)
                }
                .accessibilityElement(children: .combine)
            }
            if !rows.isEmpty {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(km(tot)) in").sType(PT.t(20, 24, 700)).foregroundStyle(PC.ink)
                        Text("premium" + (hold > 0 ? " · \(km(hold)) set aside for the puts" : "") + (nC > 0 && nP > 0 ? " · calls and puts" : ""))
                            .sType(PT.t(12, 16), tabular: true).foregroundStyle(PC.mu).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        onTry(tried ? [] : rows.map { (ty: $0.s.ty, K: $0.s.K, ex: $0.s.ex, n: $0.n) })
                    } label: {
                        Text(tried ? "In Payoff · Undo" : "Try in Payoff").sType(PT.t(15, 20, 600), tabular: false)
                            // No green on the words (focus §2.1); the tinted capsule behind them stays.
                            .foregroundStyle(PC.ink).lineLimit(1)
                            .padding(.horizontal, 18).frame(height: 44)
                            .background { if tried { Capsule().fill(PC.green.opacity(0.18)) } }
                            .glassEffect(tried ? .identity : .regular, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(tried ? "Takes the trade out of Payoff" : "Adds the trade to Payoff and Every leg")
                    .sensoryFeedback(.success, trigger: tried)
                }
                .padding(.top, 8)
                .overlay(alignment: .top) { Rectangle().fill(PC.rule).frame(height: 1) }
            }
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sunnyGlass(radius: 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your trade")
    }
}
