//
//  SunnyPositions.swift
//  Sunny
//
//  Blocks 12 and 13 · SunnyPositions. Glass chips pick All or a ticker
//  (least room to the short breakeven first). All: one Liquid Glass card
//  with the four book-wide totals. A ticker: one card per type it holds
//  (Calls sold · Puts sold · Calls bought · Puts bought), then Combined,
//  341 wide with the next one peeking; each with its hero (tap cycles % →
//  $ → time value, shared everywhere), the soft panel, the flat payoff of
//  the picked strike, the time strip and the strike rows.
//

import SwiftUI
import UIKit

enum PMode { case pct, usd, tv
    var next: PMode { switch self { case .pct: .usd; case .usd: .tv; case .tv: .pct } }
}

/// The priced book, built once per payload.
@MainActor
enum PCache {
    private static var key = ""
    private static var value: [PLeg] = []
    static func legs(_ home: HomePayload) -> [PLeg] {
        if key == home.builtAt { return value }
        key = home.builtAt; value = PMath.legs(home); return value
    }
}

struct PTicker: Identifiable {
    var id: String { t }
    let t: String
    let room: Double              // % to the nearest sold breakeven, ∞ without shorts
    var status: Status { room <= 0 ? .past : room < 2 ? .near : .safe }
    enum Status { case past, near, safe }
    var dot: Color { switch status { case .past: S.red; case .near: S.yellowDeep; case .safe: S.green } }
}

enum PBook {
    static func tickers(_ L: [PLeg]) -> [PTicker] {
        var seen: [String] = []
        for l in L where !seen.contains(l.t) { seen.append(l.t) }
        return seen.map { t in
            let sc = L.filter { $0.t == t && $0.sold && $0.call }, sp = L.filter { $0.t == t && $0.sold && !$0.call }
            let px = L.first { $0.t == t }!.px
            let rc = sc.isEmpty ? Double.infinity : (PMath.beShortCalls(sc) - px) / px * 100
            let rp = sp.isEmpty ? Double.infinity : (px - PMath.beShortPuts(sp)) / px * 100
            return PTicker(t: t, room: min(rc, rp))
        }
        .sorted { $0.room != $1.room ? $0.room < $1.room : $0.t < $1.t }
    }
}

// MARK: - The block

struct SunnyPositions: View {
    let home: HomePayload
    @State private var pick = "ALL"
    @State private var mode: PMode = .pct
    @State private var page: String?
    @State private var legSel: [String: String] = [:]
    @State private var tallest: CGFloat = 0
    @Environment(HomeRouter.self) private var router

    var body: some View {
        let L = PCache.legs(home)
        let tks = PBook.tickers(L)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Positions").sType(.sectionTitle, tabular: false).foregroundStyle(S.ink)
                if !tks.isEmpty { chips(tks) }
            }
            .padding(.horizontal, S.margin)
            if tks.isEmpty {
                empty.padding(.horizontal, S.margin)
            } else if pick == "ALL" || !tks.contains(where: { $0.t == pick }) {
                PAllCard(L: L, tks: tks, mode: $mode, minHeight: tallest)
                    .padding(.horizontal, S.margin)
                    .background(alignment: .top) {
                        // The first ticker's cards, laid out unseen, so All matches their height.
                        PTickerCards(home: home, L: L, ticker: tks[0].t, mode: $mode, legSel: $legSel, page: .constant(nil), measuring: true)
                            .fixedSize(horizontal: false, vertical: true)
                            .hidden()
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tallest = $0 }
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
            } else {
                PTickerCards(home: home, L: L, ticker: pick, mode: $mode, legSel: $legSel, page: $page, measuring: false)
                    .id(pick)
                    .transition(.opacity)
            }
        }
        .onChange(of: router.debugPick) { _, v in if let v { pick = v } }
    }

    private func chips(_ tks: [PTicker]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                chip("All", dot: tks[0].dot, room: nil, on: pick == "ALL") { pick = "ALL" }
                ForEach(tks) { x in
                    chip(x.t, dot: x.dot, room: x.room.isFinite && x.room > 0 ? String(format: "%.1f%%", x.room) : nil,
                         on: pick == x.t) { pick = x.t; page = nil }
                }
            }
            .padding(.top, 8).padding(.bottom, 10)
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20)
        .padding(.top, -8).padding(.bottom, -10)
    }

    private func chip(_ t: String, dot: Color, room: String?, on: Bool, tap: @escaping () -> Void) -> some View {
        Button { withAnimation(S.standard(0.35)) { tap() } } label: {
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(t).sType(SType(size: 13, weight: 600, line: 13, tracking: 0), tabular: false)
                    .foregroundStyle(on ? S.paper : S.ink)
                if let room {
                    Text(room).sType(SType(size: 13, weight: 500, line: 13, tracking: 0))
                        .foregroundStyle(on ? S.paper.opacity(0.72) : S.muted)
                }
            }
            .padding(.horizontal, 12).frame(height: 32)
            .background { if on { Capsule().fill(S.ink).shadow(color: .black.opacity(0.14), radius: 6, y: 4) } }
            .glassEffect(on ? .identity : .regular.interactive(), in: .capsule)
            .contentShape(Capsule().inset(by: -6))
        }
        .buttonStyle(SPressStyle())
        .accessibilityLabel(room.map { "\(t), \($0) to breakeven" } ?? t)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No open positions").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false)
            Text("Calls you sell or buy show up here.").sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false)
                .foregroundStyle(S.muted)
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: S.rCard))
    }
}

// MARK: - All (one glass card, four totals)

struct PAllCard: View {
    let L: [PLeg]
    let tks: [PTicker]
    @Binding var mode: PMode
    let minHeight: CGFloat
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    private struct Total: Identifiable { let id: String; let sold: Bool; let L: [PLeg] }

    var body: some View {
        let groups = [Total(id: "Calls sold", sold: true, L: L.filter { $0.sold && $0.call }),
                      Total(id: "Calls bought", sold: false, L: L.filter { !$0.sold && $0.call }),
                      Total(id: "Puts sold", sold: true, L: L.filter { $0.sold && !$0.call }),
                      Total(id: "Puts bought", sold: false, L: L.filter { !$0.sold && !$0.call })].filter { !$0.L.isEmpty }
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("All positions").sType(.sectionTitle, tabular: false)
                Spacer()
                Text("\(Set(L.map(\.t)).count) tickers · \(L.count) legs")
                    .sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
            }
            VStack(alignment: .leading, spacing: 28) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                    total(g).opacity(shown ? 1 : 0).offset(y: shown || reduce ? 0 : 14)
                        .animation(reduce ? .easeOut(duration: 0.2) : S.standard(0.7).delay(Double(i) * 0.07), value: shown)
                }
            }
            .padding(.vertical, 8)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: max(minHeight, 0), alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: S.rCard))
        .sunnyGlow()
        .onAppear { shown = true }
        .onDisappear { shown = false }
    }

    private func total(_ g: Total) -> some View {
        let base = g.L.reduce(0) { $0 + $1.base }, gain = g.L.reduce(0) { $0 + $1.g }
        let tv = g.L.reduce(0) { $0 + $1.tv }, now = g.L.reduce(0) { $0 + $1.now }
        let pct = base > 0 ? gain / base * 100 : 0
        let tone: Color = gain >= 0 ? S.green : S.red
        let word = g.sold ? ["captured", "kept", "time value"] : ["return", "gain", "time value"]
        let w = mode == .pct ? word[0] : mode == .usd ? word[1] : word[2]
        let big = mode == .pct ? abs(pct) : mode == .usd ? abs(gain) : tv
        var bits: [(String, String, Color)] = [(PF.usd(now), " now", S.ink)]
        if mode != .pct { bits.append((PF.pct(pct), g.sold ? " captured" : " return", tone)) }
        if mode != .tv { bits.append((PF.usd(tv), " time value", S.ink)) }
        if mode != .usd { bits.append((PF.usd(gain), g.sold ? " kept" : " gain", tone)) }
        return Button { withAnimation(.smooth(duration: S.roll)) { mode = mode.next } } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(g.id) · \(w)").sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false)
                    .foregroundStyle(S.muted)
                SNumber(value: big, format: { mode == .pct ? PF.pct($0) : PF.usd($0) })
                    .sType(.display)
                    .foregroundStyle(mode == .tv ? S.ink : tone)
                    .lineLimit(1).minimumScaleFactor(0.7)
                bits.enumerated().reduce(Text("")) { acc, e in
                    let (j, b) = e
                    return acc + Text(b.0).font(SType(size: 14, weight: 700, line: 18, tracking: 0).font(tabular: true)).foregroundStyle(b.2)
                        + Text(b.1 + (j < bits.count - 1 ? " · " : "")).foregroundStyle(S.muted)
                }
                .sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(SPressStyle())
        .accessibilityHint("Switches percent, dollars and time value")
    }
}

// MARK: - A ticker's cards

struct PTickerCards: View {
    let home: HomePayload
    let L: [PLeg]
    let ticker: String
    @Binding var mode: PMode
    @Binding var legSel: [String: String]
    @Binding var page: String?
    let measuring: Bool

    private enum Kind: String { case s, p, l, q, n }

    /// Calls sold · Puts sold · Calls bought · Puts bought, the ones held,
    /// each by strike.
    private static func groups(_ mine: [PLeg]) -> [(Kind, [PLeg])] {
        var out: [(Kind, [PLeg])] = []
        let add = { (k: Kind, sold: Bool, call: Bool) in
            let xs: [PLeg] = mine.filter { $0.sold == sold && $0.call == call }.sorted { $0.k < $1.k }
            if !xs.isEmpty { out.append((k, xs)) }
        }
        add(.s, true, true); add(.p, true, false); add(.l, false, true); add(.q, false, false)
        return out
    }

    var body: some View {
        let mine = L.filter { $0.t == ticker }
        let g = Self.groups(mine)
        let one = g.count == 1
        let kinds: [Kind] = g.map(\.0) + (g.count > 1 ? [.n] : [])
        let cw: CGFloat = one ? 353 : 341
        VStack(spacing: 14) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(kinds, id: \.rawValue) { k in
                        Group {
                            if k == .n {
                                PCombinedCard(home: home, L: mine, width: cw)
                            } else {
                                let legs = g.first { $0.0 == k }!.1
                                PSideCard(home: home, key: k.rawValue, L: legs, width: cw, mode: $mode,
                                          sel: Binding(get: { legSel[k.rawValue] }, set: { legSel[k.rawValue] = $0 }))
                            }
                        }
                        .frame(width: cw)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .sCardSurface()
                        .id(k.rawValue)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $page)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .scrollDisabled(one || measuring)
            if kinds.count > 1 {
                let cur = page ?? kinds[0].rawValue
                HStack(spacing: 6) {
                    ForEach(kinds, id: \.rawValue) { k in
                        Capsule().fill(k.rawValue == cur ? S.ink : S.tickMinor)
                            .frame(width: k.rawValue == cur ? 16 : 6, height: 6)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(S.standard()) { page = k.rawValue } }
                    }
                }
                .animation(S.standard(0.25), value: cur)
                .frame(maxWidth: .infinity)
                .padding(.top, -8)
            }
        }
    }
}

// MARK: - One side (calls or puts, sold or bought)

struct PSideCard: View {
    let home: HomePayload
    let key: String
    let L: [PLeg]
    let width: CGFloat
    @Binding var mode: PMode
    @Binding var sel: String?
    @State private var si: Int?
    @Environment(\.changedLegs) private var changed

    private var leg: PLeg { L.first { $0.id == sel } ?? L[0] }
    private var sold: Bool { L[0].sold }
    private var call: Bool { L[0].call }
    private var CW: CGFloat { width - 40 }
    private var W: CGFloat { CW - 44 }

    var body: some View {
        let l = leg, px = l.px
        let slots = TimeStrip.slots(until: l.expiry, long: !sold, calendar: home.calendar)
        let idx = min(si ?? slots.count - 1, slots.count - 1)
        let el = min(slots[idx].el, l.days)
        let (lo, hi) = Self.span(l)
        let stops = (0...5).map { Double($0) / 5 * l.days }
        let yr = PayoffGeom.range([l], stops: stops, lo: lo, hi: hi)
        let C = PayoffGeom.build([l], el: el, lo: lo, hi: hi, yr: yr, W: W, unbounded: sold, label: { PF.strike($0.k) })
        let base = L.reduce(0) { $0 + $1.base }, gain = L.reduce(0) { $0 + $1.g }
        let tvAll = L.reduce(0) { $0 + $1.tv }, nowAll = L.reduce(0) { $0 + $1.now }
        let pctAll = base > 0 ? gain / base * 100 : 0
        let V = PMath.pv(l, px, el)
        let tvLeg = max(0, V - (call ? max(0, px - l.k) : max(0, l.k - px))) * 100 * Double(l.q)
        let pLeg = (sold ? l.a - V : V - l.a) / l.a * 100
        let words = sold ? ["captured", "kept", "time value"] : ["return", "gain", "time value"]
        let w = mode == .pct ? words[0] : mode == .usd ? words[1] : words[2]
        let dayLbl = PTime.dayLabel(slots, idx, long: !sold)

        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                PCardHead(title: "\(l.t) \(call ? "Calls" : "Puts") \(sold ? "sold" : "bought")",
                          count: "\(L.count) \(L.count == 1 ? "leg" : "legs")")
                Button { withAnimation(.smooth(duration: S.roll)) { mode = mode.next } } label: {
                    PHero(value: mode == .pct ? abs(pctAll) : mode == .usd ? abs(gain) : tvAll,
                          text: { mode == .pct ? PF.pct($0) : PF.usd($0) },
                          tone: mode == .tv ? S.ink : gain >= 0 ? S.green : S.red, word: w)
                }
                .buttonStyle(SPressStyle())
                PSoftPanel(
                    heads: L.count > 1 ? ["\(PF.strike(l.k)) ×\(l.q) · \(dayLbl)", "Total today"] : ["\(PF.strike(l.k)) ×\(l.q) · \(dayLbl)"],
                    rows: [
                        (sold ? "credit" : "paid", [(PF.usd(l.base), S.ink), (PF.usd(base), S.ink)]),
                        ("worth now", [(PF.usd(V * 100 * Double(l.q)), S.ink), (PF.usd(nowAll), S.ink)]),
                        ("TV", [(PF.usd(tvLeg), S.ink), (PF.usd(tvAll), S.ink)]),
                        (sold ? "captured" : "return", [(PF.pct(pLeg), pLeg >= 0 ? S.green : S.red), (PF.pct(pctAll), gain >= 0 ? S.green : S.red)]),
                    ].map { ($0.0, L.count > 1 ? $0.1 : [$0.1[0]]) })
            }
            PFlatChart(C: C, W: W, CW: CW, now: px, selected: l.id, dist: PDist.of(l))
            PTimeStripView(slots: slots, si: $si, long: !sold, width: width)
            VStack(spacing: 2) {
                ForEach(L) { x in
                    let d = PDist.of(x)
                    let v = mode == .pct ? PF.pct(x.pct) : mode == .usd ? PF.usd(x.g) : PF.usd(x.tv)
                    PRow(name: PF.strike(x.k), qty: "×\(x.q)", dist: "\(d.v) \(d.m)", distColor: d.c, value: v,
                         valueColor: mode == .tv ? S.ink : x.g >= 0 ? S.green : S.red, nameW: 96,
                         selected: x.id == l.id, tap: { withAnimation(S.standard(0.3)) { sel = x.id } },
                         wash: changed.contains(x.id))
                }
            }
        }
        .foregroundStyle(S.ink)
        .padding(20)
    }

    /// The chart's price span, as the design fits each side.
    static func span(_ l: PLeg) -> (Double, Double) {
        let px = l.px, k = l.k, a = l.a
        if l.call && l.sold {
            let hi = max(k + 2 * a, k * 1.004, px * 1.01), span = max(hi - min(px, k), px * 0.04)
            return (min(px, k) - span * 0.3, hi)
        } else if l.call {
            return (min(px, k) * 0.78, max(px, k + a) + 1.4 * a)
        } else if l.sold {
            let lo = max(0.01, min(k - 2 * a, k * 0.996, px * 0.99)), span = max(max(px, k) - lo, px * 0.04)
            return (lo, max(px, k) + span * 0.3)
        }
        return (max(0.01, min(px, k - a) - 1.4 * a), max(px, k) * 1.22)
    }
}

// MARK: - Combined (block 13)

struct PCombinedCard: View {
    let home: HomePayload
    let L: [PLeg]
    let width: CGFloat
    @State private var si: Int?
    @Environment(\.changedLegs) private var changed

    var body: some View {
        let CW = width - 40, W = CW - 44
        let shorts = L.filter(\.sold), longs = L.filter { !$0.sold }
        let lC = longs.filter(\.call), sC = shorts.filter(\.call)
        let hasShort = !shorts.isEmpty
        let until = (hasShort ? shorts : L).map(\.expiry).max()!
        let slots = TimeStrip.slots(until: until, long: !hasShort, calendar: home.calendar)
        let idx = min(si ?? slots.count - 1, slots.count - 1)
        let endDays = (hasShort ? shorts : L).map(\.days).max() ?? 0
        let el = min(slots[idx].el, endDays)
        let px = L[0].px, ks = L.map(\.k)
        let lo = min(px, ks.min()!) * 0.9, hi = max(px * 1.08, (ks.max() ?? px) * 1.06)
        let sQ = sC.reduce(0) { $0 + $1.q }, lQ = lC.reduce(0) { $0 + $1.q }
        let stops = (0...5).map { Double($0) / 5 * endDays }
        let yr = PayoffGeom.range(L, stops: stops, lo: lo, hi: hi)
        let C = PayoffGeom.build(L, el: el, lo: lo, hi: hi, yr: yr, W: W, unbounded: sQ > lQ,
                                 label: { "\(PF.strike($0.k))\($0.call ? "C" : "P")·\($0.sold ? "S" : "B")" })
        let near = (hasShort ? shorts : L).min { abs($0.k - px) < abs($1.k - px) }!
        let net = L.reduce(0) { $0 + $1.g }
        let delta = L.reduce(0) { $0 + PMath.delta($1, px, el) }
        let longVal = PMath.value(longs, px, el)
        let income = shorts.reduce(0) { $0 + $1.base }
        let anyPuts = L.contains { !$0.call }
        let dayLbl = PTime.dayLabel(slots, idx, long: !hasShort)
        let order = longs.filter(\.call) + longs.filter { !$0.call } + shorts.filter(\.call) + shorts.filter { !$0.call }

        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                PCardHead(title: "\(L[0].t) Combined", count: "\(L.count) legs")
                PHero(value: abs(net), text: { PF.usd($0) }, tone: net >= 0 ? S.green : S.red, word: "net P/L")
                PSoftPanel(heads: ["Total \(dayLbl)"], rows: [
                    ("delta", [(PF.count(delta), delta < -0.5 ? S.red : S.ink)]),
                    (anyPuts ? "long value" : "long calls", [(PF.usd(longVal), S.ink)]),
                    (anyPuts ? "short income" : "short calls income", [(PF.usd(income), S.ink)]),
                ])
            }
            PFlatChart(C: C, W: W, CW: CW, now: px, selected: near.id, dist: PDist.of(near))
            PTimeStripView(slots: slots, si: $si, long: !hasShort, width: width)
            VStack(spacing: 2) {
                ForEach(order) { x in
                    let d = PDist.of(x)
                    PRow(name: "\(PF.strike(x.k))\(x.call ? "C" : "P")", qty: "\(x.sold ? "sold" : "bought") ×\(x.q)",
                         dist: "\(d.v) \(d.m)", distColor: d.c, value: PF.usd(x.g),
                         valueColor: x.g >= 0 ? S.green : S.red, nameW: 128, selected: false, tap: nil,
                         wash: changed.contains(x.id))
                }
            }
        }
        .foregroundStyle(S.ink)
        .padding(20)
    }
}

// MARK: - Parts

enum PDist {
    /// "0.8%" "OTM", green on your side (sold OTM, bought ITM), red past it.
    static func of(_ l: PLeg) -> (v: String, m: String, c: Color) {
        let d = (l.call ? l.k - l.px : l.px - l.k) / l.px * 100
        let ok = l.sold ? d > 0 : d < 0
        return (String(format: "%.1f%%", abs(d)), d > 0 ? "OTM" : d < 0 ? "ITM" : "ATM", ok ? S.green : S.red)
    }
}

enum PTime {
    static let mon = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static func dayLabel(_ s: [TimeSlot], _ i: Int, long: Bool) -> String {
        if i == 0 { return "Now" }
        if i == s.count - 1 { return "Exp" }
        let x = s[i]
        if long { return F.day(x.date) }
        return "\(DeckBuilder.weekdays[DeckBuilder.weekday(x.date)]) \(clock(x.minutes ?? 0))"
    }
    static func clock(_ m: Int) -> String {
        let h = m / 60, mm = m % 60, h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", h12, mm, h >= 12 ? "PM" : "AM")
    }
    /// "Now (5 DTE)" · "Oct 14, 2:15 PM (2 DTE)" · "Oct 14, 2026 (100 DTE)"
    static func chip(_ s: [TimeSlot], _ i: Int, long: Bool) -> String {
        let end = s[s.count - 1].date
        let dte = { (d: String) -> Int in
            let a = PMath.nyDate(d, minutes: 0), b = PMath.nyDate(end, minutes: 0)
            return max(0, Int((b.timeIntervalSince(a) / 86400).rounded()))
        }
        if i == 0 { return "Now (\(dte(s[0].date)) DTE)" }
        let x = s[i]
        let when = long ? "\(F.day(x.date)), \(x.date.prefix(4))" : "\(F.day(x.date)), \(clock(x.minutes ?? 0))"
        return "\(when) (\(dte(x.date)) DTE)"
    }
}

struct PCardHead: View {
    let title: String
    let count: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).sType(.sectionTitle, tabular: false).lineLimit(1)
            Spacer(minLength: 0)
            Text(count).sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false)
                .foregroundStyle(S.muted).lineLimit(1)
        }
    }
}

struct PHero: View {
    let value: Double
    let text: (Double) -> String
    let tone: Color
    let word: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SNumber(value: value, format: text)
                .sType(.largeNumber)
                .foregroundStyle(tone)
            Text(word).sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(S.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The soft panel: labels left, the picked strike's column, then Total in
/// quieter 13 pt grey, coloured only for gains and losses.
struct PSoftPanel: View {
    let heads: [String]
    let rows: [(String, [(String, Color)])]
    /// 96 as designed; a little less with two columns so labels never cut.
    private var col: CGFloat { heads.count > 1 ? 84 : 96 }
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ForEach(Array(heads.enumerated()), id: \.offset) { j, h in
                    Text(h).sType(SType(size: 12, weight: j == 0 ? 700 : 600, line: 14, tracking: 0))
                        .foregroundStyle(j == 0 ? S.ink : S.muted)
                        .lineLimit(1).fixedSize()
                        .frame(minWidth: col, alignment: .trailing)
                }
            }
            .frame(height: 30)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(r.0).sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false)
                        .foregroundStyle(S.muted).lineLimit(1).fixedSize()
                    Spacer(minLength: 0)
                    ForEach(Array(r.1.enumerated()), id: \.offset) { j, cell in
                        Text(cell.0)
                            .sType(SType(size: j == 0 ? 15 : 13, weight: j == 0 ? 700 : 600, line: 18, tracking: 0))
                            .foregroundStyle(j == 0 || cell.1 != S.ink ? cell.1 : S.muted)
                            .contentTransition(.numericText())
                            .lineLimit(1).fixedSize()
                            .frame(minWidth: col, alignment: .trailing)
                    }
                }
                .frame(height: 34)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [S.pSoftTop, S.pSoftBot], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(S.pSoftRim, lineWidth: 0.5))
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .trim(from: 0.0, to: 1.0).stroke(S.pSoftLip, lineWidth: 1)
                        .mask(alignment: .top) { Rectangle().frame(height: 2) }
                }
                .shadow(color: S.ink.opacity(0.03), radius: 1, y: 1)
        }
    }
}

struct PRow: View {
    let name: String
    let qty: String
    let dist: String
    let distColor: Color
    let value: String
    let valueColor: Color
    let nameW: CGFloat
    let selected: Bool
    let tap: (() -> Void)?
    var wash = false
    var body: some View {
        let row = HStack(spacing: 10) {
            (Text(name).font(SType(size: 15, weight: 600, line: 18, tracking: 0).font())
             + Text(" " + qty).font(SType(size: 15, weight: 500, line: 18, tracking: 0).font()).foregroundStyle(S.muted))
                .lineLimit(1)
                .frame(width: nameW, alignment: .leading)
            Text(dist).sType(SType(size: 13, weight: 600, line: 16, tracking: 0)).foregroundStyle(distColor)
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            Text(value).sType(SType(size: 15, weight: 700, line: 18, tracking: 0)).foregroundStyle(valueColor)
                .contentTransition(.numericText())
                .frame(width: 64, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(height: 44)
        .padding(.horizontal, 8)
        .modifier(Wash(on: wash))
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? S.pRowSel : .clear))
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        if let tap {
            Button(action: tap) { row }.buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            row.accessibilityElement(children: .combine)
        }
    }
}

// MARK: - The flat payoff chart

struct PFlatChart: View {
    let C: PayoffChart
    let W: CGFloat
    let CW: CGFloat
    let now: Double
    let selected: String
    let dist: (v: String, m: String, c: Color)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                // Faint vertical grid at the price ticks.
                for t in C.xTicks {
                    ctx.fill(Path(CGRect(x: t.x - 0.5, y: 22, width: 1, height: 130)), with: .color(S.pGrid))
                }
                let area = { (pts: [CGPoint]) -> Path in var p = Path(); p.addLines(pts); p.closeSubpath(); return p }
                ctx.fill(area(C.posArea), with: .color(S.pGainFill))
                ctx.fill(area(C.negArea), with: .color(S.pLossFill))
                var nowL = Path(); nowL.move(to: CGPoint(x: C.nx, y: 22)); nowL.addLine(to: CGPoint(x: C.nx, y: 152))
                ctx.stroke(nowL, with: .color(S.pNowLine), lineWidth: 1.5)
                var zero = Path(); zero.move(to: CGPoint(x: 0, y: C.zy)); zero.addLine(to: CGPoint(x: W, y: C.zy))
                ctx.stroke(zero, with: .color(S.pZero), lineWidth: 1)
                for s in C.segs {
                    var p = Path(); p.addLines(s.pts)
                    ctx.stroke(p, with: .color(s.loss ? S.red : S.green),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                for x in C.markers {
                    var t = Path()
                    t.move(to: CGPoint(x: x - 4, y: PayoffGeom.B - 7)); t.addLine(to: CGPoint(x: x + 4, y: PayoffGeom.B - 7))
                    t.addLine(to: CGPoint(x: x, y: PayoffGeom.B)); t.closeSubpath()
                    ctx.fill(t, with: .color(S.red))
                }
                // Strike ticks under the plot.
                for k in C.strikes {
                    ctx.fill(Path(CGRect(x: k.x - 0.5, y: 152, width: 1, height: 5)), with: .color(S.ink))
                }
            }
            .frame(width: W, height: PayoffGeom.H)

            // The price over the now line.
            Text("$" + F.level(now))
                .sType(SType(size: 12, weight: 600, line: 16, tracking: 0))
                .foregroundStyle(S.muted).fixedSize()
                .alignmentGuide(.leading) { d in
                    C.nx < 34 ? -(C.nx - 4) : C.nx > W - 34 ? -(C.nx + 4 - d.width) : -(C.nx - d.width / 2)
                }
            if let d = C.dot {
                Circle().fill(d.gain ? S.green : S.red).frame(width: 8, height: 8)
                    .overlay(Circle().stroke(S.paper, lineWidth: 2))
                    .position(x: d.x, y: d.y)
            }
            ForEach(Array(C.be.enumerated()), id: \.offset) { _, b in
                Circle().fill(S.pBeDot).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(S.paper, lineWidth: 2))
                    .background(Circle().stroke(S.pBeRing, lineWidth: 1).padding(-2.5))
                    .position(x: b.x, y: C.zy)
                let right = b.falling ? b.x < W - 64 : b.x < 64
                Text("$" + F.level(b.price))
                    .sType(SType(size: 11, weight: 700, line: 14, tracking: 0))
                    .foregroundStyle(S.yellowDeep)
                    .padding(.horizontal, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(S.paper))
                    .fixedSize()
                    .alignmentGuide(.leading) { d in right ? -(b.x + 8) : -(b.x - 8 - d.width) }
                    .alignmentGuide(.top) { _ in -(C.zy - 21) }
            }
            // Price ticks, kept clear of the strike labels.
            let labels = strikeLabels
            ForEach(Array(C.xTicks.enumerated()), id: \.offset) { _, t in
                let lbl = "$" + (abs(t.v - t.v.rounded()) < 1e-6 ? String(Int(t.v.rounded())) : String(format: t.step < 0.1 ? "%.2f" : "%.1f", t.v))
                let clash = labels.contains { abs($0.x - t.x) < $0.w / 2 + CGFloat(lbl.count) * 3.2 + 8 }
                if !clash {
                    Text(lbl).sType(SType(size: 11, weight: 500, line: 13, tracking: 0)).foregroundStyle(S.muted).fixedSize()
                        .position(x: t.x, y: 160 + 6.5)
                }
            }
            ForEach(Array(labels.enumerated()), id: \.offset) { _, k in
                (Text(k.text).foregroundStyle(S.ink) + Text(k.dist).foregroundStyle(dist.c))
                    .sType(SType(size: 11, weight: 700, line: 13, tracking: 0))
                    .fixedSize()
                    .position(x: k.x, y: 160 + 6.5)
            }
            // P/L ticks on the right.
            ForEach(Array(C.yTicks.enumerated()), id: \.offset) { _, y in
                Text(PF.usd(y.v)).sType(SType(size: 11, weight: 600, line: 13, tracking: 0))
                    .foregroundStyle(y.v < 0 ? S.red : S.muted).fixedSize()
                    .frame(width: CW, alignment: .trailing)
                    .position(x: CW / 2, y: y.y)
            }
        }
        .frame(width: CW, height: PayoffGeom.H, alignment: .topLeading)
        .accessibilityElement()
        .accessibilityLabel("Payoff chart. Price \(F.money(now, cents: true))."
                            + (C.be.isEmpty ? "" : " Breakeven \(C.be.map { F.money($0.price, cents: true) }.joined(separator: " and ")).")
                            + " Profit or loss now \(PF.usd(C.plNow)) \(C.plNow >= 0 ? "gain" : "loss").")
    }

    /// Strike labels; the picked strike carries its distance, "34 (0.8% OTM)".
    private var strikeLabels: [(x: CGFloat, w: CGFloat, text: String, dist: String)] {
        C.strikes.filter { !$0.label.isEmpty }.map { k in
            let withDist = k.id == selected && !k.label.contains("–")
            let d = withDist ? " (\(dist.v) \(dist.m))" : ""
            let w = CGFloat((k.label + d).count) * 6.4 + 6
            let x = withDist ? max(w / 2, min(W - w / 2, k.x)) : k.center
            return (x, w, k.label, d)
        }
    }
}

// MARK: - The time strip

/// Scrolls under a fixed centre line: 15-minute steps to the Friday close
/// when sold, a day a step when bought. Native scroll, snapping to steps, a
/// selection haptic per step; ‹ Now and Exp › slide in once that end has
/// scrolled out of view.
struct PTimeStripView: View {
    let slots: [TimeSlot]
    @Binding var si: Int?
    let long: Bool
    let width: CGFloat
    @State private var pos = ScrollPosition(x: 0)
    @State private var ready = false

    private var px: CGFloat { long ? 2 : 5.5 }
    private var last: Int { slots.count - 1 }
    private var cur: Int { min(si ?? last, last) }

    var body: some View {
        VStack(spacing: 6) {
            Text(PTime.chip(slots, cur, long: long))
                .sType(SType(size: 13, weight: 700, line: 13, tracking: 0))
                .foregroundStyle(S.ink)
                .padding(.horizontal, 12).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(S.surface))
                .contentTransition(.numericText())
            ZStack {
                ScrollView(.horizontal) {
                    strip.frame(width: CGFloat(last) * px + width, height: 52)
                }
                .scrollPosition($pos)
                .scrollTargetBehavior(StepSnap(step: px))
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
                    guard ready else { return }
                    let n = max(0, min(last, Int((x / px).rounded())))
                    if n != cur { UISelectionFeedbackGenerator().selectionChanged(); si = n }
                }
                Rectangle().fill(S.tickMajor).frame(width: 1, height: 54).offset(y: -2)
                    .allowsHitTesting(false)
                HStack {
                    tag(now: true).offset(x: cur > 0 && CGFloat(cur) * px > width / 2 - 34 ? 0 : -width * 0.3)
                        .opacity(cur > 0 && CGFloat(cur) * px > width / 2 - 34 ? 1 : 0)
                    Spacer()
                    tag(now: false).offset(x: CGFloat(last - cur) * px > width / 2 - 34 ? 0 : width * 0.3)
                        .opacity(CGFloat(last - cur) * px > width / 2 - 34 ? 1 : 0)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .animation(S.sheet(0.45), value: cur)
            }
            .frame(width: width, height: 52)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, -20)
        .onAppear {
            pos.scrollTo(x: CGFloat(cur) * px)
            Task { try? await Task.sleep(for: .milliseconds(80)); ready = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Day and time, \(PTime.chip(slots, cur, long: long))")
        .accessibilityAdjustableAction { dir in
            let n = max(0, min(last, cur + (dir == .increment ? 1 : -1)))
            si = n; pos.scrollTo(x: CGFloat(n) * px)
        }
    }

    private var strip: some View {
        let lead = width / 2
        return Canvas { ctx, size in
            for i in 0...last {
                let s = slots[i]
                let tick = i == 0 || i == last || (long ? i % 7 == 0 : (s.minutes ?? 0) % 30 == 0)
                guard tick else { continue }
                let major = i == 0 || i == last || (long ? [91, 182, 273, 365, 730].contains(i) : (s.open || s.noon))
                let h: CGFloat = major ? 18 : 10, x = lead + CGFloat(i) * px
                ctx.fill(Path(CGRect(x: x - 0.5, y: size.height - 4 - h, width: 1, height: h)),
                         with: .color(major ? S.tickMajor : S.tickMinor))
            }
            for l in labels {
                let t = ctx.resolve(Text(l.t).font(SType(size: 13, weight: 500, line: 16, tracking: 0).font(tabular: true))
                    .foregroundStyle(S.tickMajor))
                ctx.draw(t, at: CGPoint(x: lead + CGFloat(l.i) * px, y: 6 + 8), anchor: .center)
            }
        }
    }

    private var labels: [(i: Int, t: String)] {
        var o: [(i: Int, t: String)] = []
        for (i, s) in slots.enumerated() where i > 0 && i < last {
            if long {
                if s.date.hasSuffix("-01") {
                    let m = Int(s.date.dropFirst(5).prefix(2)) ?? 1
                    o.append((i, m == 1 ? "Jan '\(s.date.dropFirst(2).prefix(2))" : PTime.mon[m - 1]))
                }
            } else if s.open {
                let p = s.date.split(separator: "-").compactMap { Int($0) }
                o.append((i, "\(p[1])/\(p[2])"))
            } else if s.noon { o.append((i, "12 PM")) }
        }
        let w = { (t: String) -> CGFloat in CGFloat(t.count) * 7 + 4 }
        let fits = { (a: (i: Int, t: String), b: (i: Int, t: String)) -> Bool in
            CGFloat(abs(b.i - a.i)) * px > (w(a.t) + w(b.t)) / 2 + 10
        }
        var kept: [(i: Int, t: String)] = [(0, "Now")]
        let ex = (i: last, t: "Exp")
        for q in o where fits(kept[kept.count - 1], q) && fits(q, ex) { kept.append(q) }
        kept.append(ex)
        return kept
    }

    private func tag(now: Bool) -> some View {
        Button {
            let n = now ? 0 : last
            withAnimation(S.standard(0.6)) { pos.scrollTo(x: CGFloat(n) * px) }
        } label: {
            HStack(spacing: 5) {
                if now { Image(systemName: "chevron.left").font(.system(size: 9, weight: .heavy)) }
                Text(now ? "Now" : "Exp").sType(SType(size: 13, weight: 700, line: 13, tracking: 0), tabular: false)
                if !now { Image(systemName: "chevron.right").font(.system(size: 9, weight: .heavy)) }
            }
            .foregroundStyle(S.ink)
            .padding(.leading, now ? 9 : 11).padding(.trailing, now ? 11 : 9)
            .frame(height: 28)
            .background(UnevenRoundedRectangle(topLeadingRadius: now ? 0 : 14, bottomLeadingRadius: now ? 0 : 14,
                                               bottomTrailingRadius: now ? 14 : 0, topTrailingRadius: now ? 14 : 0)
                .fill(S.paper))
            .overlay(UnevenRoundedRectangle(topLeadingRadius: now ? 0 : 14, bottomLeadingRadius: now ? 0 : 14,
                                            bottomTrailingRadius: now ? 14 : 0, topTrailingRadius: now ? 14 : 0)
                .stroke(S.line, lineWidth: 1))
        }
        .buttonStyle(SPressStyle())
        .accessibilityLabel(now ? "Back to now" : "Jump to expiry")
    }
}

/// Lands a scroll on a whole step.
struct StepSnap: ScrollTargetBehavior {
    let step: CGFloat
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        target.rect.origin.x = (target.rect.origin.x / step).rounded() * step
    }
}
