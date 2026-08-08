//
//  NvdaPlannerV2.swift
//  Sunnyfi — Ink rebuild · Plan the next sale
//
//  The planner handoff's five layers, over nvda-planner rev 3. The screen holds no
//  finance: every figure it renders — stance, floor, fit, the net of the whole move
//  — arrives already computed, so the model stays testable on its own and the screen
//  stays swappable.
//
//  Two deliberate departures from the handoff, both forced by the real book:
//
//    · Layer 02 groups the open calls by EXPIRY, not by leg. The handoff assumes you
//      roll one leg at a time; with 60 of 65 contracts landing on one date the real
//      decision is "what do I do about Friday", and a rail of near-identical leg
//      cards buries that.
//    · A new layer sits between the week and the roll: what assignment would leave
//      you holding. The put hedge is sized to the whole share block and does not
//      leave when the shares do, so a long-only book can end up short by arithmetic.
//      It is the sharpest number on the book and the handoff's five layers have
//      nowhere to put it.
//

import SwiftUI
import Supabase

// MARK: - Request

struct PV2Req: Encodable, Sendable {
    struct Leg: Encodable, Sendable {
        let strike: Double; let ct: Double
        var expiry: String? = nil          // ISO — lets the edge weight expiry load
    }
    struct Book: Encodable, Sendable {
        let shares, buyAvg, realizedPremium, netDelta, longTheta, shortCallDelta, shortCallCt: Double
        let openShortCalls: [Leg]; let longCalls: [Leg]
        // rev 3: the hedge, so assignment and the freeroll corridor can be priced
        var longCallDelta: Double = 0
        var putDelta: Double = 0
        var putFloor: Double = 0
        var putCost: Double = 0
    }
    struct Vol: Encodable, Sendable { let iv, ivPct, hv20, hv30, hv60, hv90: Double }
    struct Earn: Encodable, Sendable { let date, label: String }
    let book: Book; let vol: Vol; let earnings: Earn
    let weekendVol: Double
    let spot: Double
}

// MARK: - Response

struct PV2: Decodable, Sendable {
    let ok: Bool
    var week: Week?
    var posture: Posture?
    var assignment: Assign?
    var events: Events?
    var book: Book?
    var gate: Gate?
    var expiries: [Expiry]?
    var refLots: Int?
    var exps: [Expiry] { expiries ?? [] }

    struct Week: Decodable, Sendable {
        let score: Int
        let stance: String
        var rawStance: String?
        var stanceReason: String?
        var binding: String?
        let prescription: Rx
        let lots: Lots
        var forces: [Force]?
        var caption: String?
        var forceList: [Force] { forces ?? [] }
        struct Rx: Decodable, Sendable { let deltaLo, deltaHi, sizePct: Double; let tenor: String }
        struct Lots: Decodable, Sendable { let base, max: Int; var byFloor: Int?; var byAssignment: Int?; var free: Double? }
    }
    struct Force: Decodable, Sendable, Identifiable {
        let key: String; let name: String; let w: Double; let score: Double
        var rows: [[String]]?; var push: String?; var contribution: Double?
        var rowList: [[String]] { rows ?? [] }
        var pushText: String { push ?? "" }
        var contrib: Double { contribution ?? 0 }
        var id: String { key }
    }
    struct Posture: Decodable, Sendable {
        let upsideDelta, floor, headroom, dev: Double
        let state: String
        var floorBase: Double?; var floorMult: Double?; var floorParts: [FloorPart]?
        var trendStrength: Double?; var trendUp: Bool?
        var freeroll: Double?; var freerollRegime: String?
        var banked: Double?; var corridor: Double?; var putCost: Double?; var maxLoss: Double?
        struct FloorPart: Decodable, Sendable, Identifiable { let k: String; let mult: Double; let why: String; var id: String { k } }
    }
    struct Assign: Decodable, Sendable {
        let sharesAfter, putDelta, deltaAfter: Double
        var expectedCalled: Double?; var deltaAfterWorst: Double?
        var coveredPct: Double?; var netShort: Bool?; var worstNetShort: Bool?; var thin: Bool?; var known: Bool?
    }
    struct Events: Decodable, Sendable {
        let density: Int; let horizon: Int
        var nearest: Cat?; var heavy: Cat?; var list: [Cat]?; var daysToHeavy: Int?
        struct Cat: Decodable, Sendable, Identifiable {
            let key, label, date: String; let days: Int; let sev: Int
            var id: String { "\(key)-\(date)-\(label)" }
        }
    }
    struct Book: Decodable, Sendable {
        let shares, buyAvg, basis, shortCallCt, freeShares: Double
        var capacity: Double?; var netDelta: Double?
    }
    struct Gate: Decodable, Sendable {
        let spot, iv, ivPct, score: Double
        var daysToEarnings: Int?; var blocked: Bool?; var flags: [Flag]?
        struct Flag: Decodable, Sendable, Identifiable { let key, level, head, body: String; var id: String { key } }
    }
    struct Expiry: Decodable, Sendable, Identifiable {
        let iso, label, dow: String
        let cal, td: Int
        var load: Int?
        var eventInside: Events.Cat?
        var pickStrike: Double?
        var chain: [Cell]?
        var id: String { iso }
        var loadCt: Int { load ?? 0 }
        var cells: [Cell] { chain ?? [] }
    }
    struct Cell: Decodable, Sendable, Identifiable {
        let strike, prem, delta, assign, effective, vsBasis: Double
        var perDay: Double?; var deltaSold: Double?; var freeAfter: Double?; var afterAssign: Double?
        var warns: [String]?; var blocks: [String]?
        var fit: Int?; var isPick: Bool?
        var fitParts: [FitPart]?
        var id: Double { strike }
        var warnList: [String] { warns ?? [] }
        var blockList: [String] { blocks ?? [] }
        var blocked: Bool { !(blocks ?? []).isEmpty }
        struct FitPart: Decodable, Sendable, Identifiable { let k: String; let w, s, contribution: Double; var id: String { k } }
    }
}

// MARK: - Store

@MainActor
@Observable
final class PlanV2Store {
    var state: PV2?
    var isLoading = true
    var lastError: String?
    private let client = SupabaseService.client
    private var gen = 0

    /// NVDA's next print. Kept here rather than in the edge so it can be corrected
    /// without a deploy; the edge also reads earnings_events and takes the nearer.
    static let earnings = (date: "2026-08-26", label: "Aug 26")

    private static let isoOut: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "America/New_York"); return f
    }()

    func load(from store: NvdaStore) async {
        guard let pos = store.position, let pnl = store.pnl, let ins = store.insights else {
            isLoading = false; lastError = "position not ready"; return
        }
        gen += 1; let g = gen
        isLoading = true

        let strikes = pos.groups.flatMap { $0.strikes }.filter { !$0.expired }
        let shorts = strikes.filter { $0.side == "short" && $0.kind == "call" }
        let longCalls = strikes.filter { $0.side == "long" && $0.kind == "call" }
        let longPuts = strikes.filter { $0.side == "long" && $0.kind == "put" }

        // The floor is the quantity-weighted put strike — exact for a single-strike
        // 1:1 hedge, and the honest average for a laddered one.
        let putCt = longPuts.reduce(0.0) { $0 + $1.ct }
        let putFloor = putCt > 0 ? longPuts.reduce(0.0) { $0 + $1.strike * $1.ct } / putCt : 0

        let book = PV2Req.Book(
            shares: pos.shares, buyAvg: pos.avgBuy, realizedPremium: pnl.premiumRealized,
            netDelta: pos.delta,
            longTheta: strikes.filter { $0.side == "long" }.reduce(0.0) { $0 + abs($1.theta ?? 0) * $1.ct * 100 },
            shortCallDelta: shorts.reduce(0.0) { $0 + abs($1.deltaEst) },
            shortCallCt: shorts.reduce(0.0) { $0 + $1.ct },
            openShortCalls: shorts.map { .init(strike: $0.strike, ct: $0.ct, expiry: Self.iso($0.expiry)) },
            longCalls: longCalls.map { .init(strike: $0.strike, ct: $0.ct, expiry: Self.iso($0.expiry)) },
            longCallDelta: longCalls.reduce(0.0) { $0 + $1.deltaEst },
            putDelta: longPuts.reduce(0.0) { $0 + $1.deltaEst },
            putFloor: putFloor,
            putCost: longPuts.reduce(0.0) { $0 + $1.basis })

        let vol = PV2Req.Vol(iv: ins.vol.iv ?? 0, ivPct: ins.vol.ivr ?? 50,
                             hv20: store.hv(20) ?? (ins.vol.hv30 ?? 0), hv30: ins.vol.hv30 ?? 0,
                             hv60: store.hv(60) ?? (ins.vol.hv30 ?? 0), hv90: store.hv(90) ?? (ins.vol.hv30 ?? 0))
        let req = PV2Req(book: book, vol: vol,
                         earnings: .init(date: Self.earnings.date, label: Self.earnings.label),
                         weekendVol: 0.3, spot: pos.spot)
        do {
            let data = try await client.functions.invoke("nvda-planner",
                options: FunctionInvokeOptions(body: req), decode: { data, _ in data })
            let decoded = try JSONDecoder().decode(PV2.self, from: data)
            guard g == gen else { return }
            if decoded.ok { state = decoded; lastError = nil } else { lastError = "planner unavailable" }
            isLoading = false
        } catch {
            guard g == gen else { return }
            lastError = String(describing: error); isLoading = false
        }
    }

    /// NvStrike carries a display expiry ("Aug 15 '26"); the edge wants ISO.
    private static let disp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d yy"; f.timeZone = TimeZone(identifier: "America/New_York"); return f
    }()
    static func iso(_ display: String) -> String? {
        let cleaned = display.replacingOccurrences(of: "\u{2019}", with: "").replacingOccurrences(of: "'", with: "")
        return disp.date(from: cleaned).map { isoOut.string(from: $0) }
    }
}

// MARK: - formatting

private func pvInt(_ v: Double) -> String { Int(v.rounded()).formatted(.number.grouping(.automatic)) }
private func pvSigned(_ v: Double) -> String { (v > 0 ? "+" : v < 0 ? "−" : "") + pvInt(abs(v)) }
private func pvUsd(_ v: Double) -> String {
    let a = abs(v), sign = v < 0 ? "−" : ""
    if a >= 1_000_000 { return sign + "$" + String(format: "%.1f", a / 1_000_000).replacingOccurrences(of: ".0", with: "") + "M" }
    if a >= 1_000 { return sign + "$" + String(format: "%.0f", a / 1_000) + "K" }
    return sign + "$" + pvInt(a)
}
private func pvDec(_ v: Double, _ d: Int) -> String { String(format: "%.\(d)f", v) }

private func stanceHue(_ s: String) -> Color {
    switch s {
    case "SELL HARD":   return Ink.gain
    case "SELL NORMAL": return Ink.text
    case "SELL LIGHT":  return Ink.delayed
    default:            return Ink.loss
    }
}

// MARK: - small parts

/// A 156×138 state chip — the handoff's layer-01 unit.
private struct PVChip: View {
    let k: String
    let v: String
    var sub: String = " "
    var hue: Color = Ink.text
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(k.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.1)
                .foregroundStyle(Ink.dim).lineLimit(1)
            Spacer(minLength: 0)
            InkRoll(text: v, font: InkFont.mono(26, .medium), tracking: 26 * -0.04, color: hue)
            Text(sub.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.1)
                .foregroundStyle(Ink.dim).lineLimit(1).padding(.top, 10)
        }
        .padding(EdgeInsets(top: 15, leading: 15, bottom: 14, trailing: 15))
        .frame(width: 156, height: 138, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous).fill(Ink.surface))
    }
}

/// A label + figure pair, used inside the assignment panel and the send bar.
private struct PVFig: View {
    let k: String
    let v: String
    var sub: String? = nil
    var hue: Color = Ink.text
    var size: CGFloat = 16
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(v).font(InkFont.mono(size, .regular)).tracking(size * -0.03).foregroundStyle(hue).lineLimit(1)
                if let sub { Text(sub).font(InkFont.mono(11)).foregroundStyle(Ink.dim).lineLimit(1) }
            }
            Text(k.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.1)
                .foregroundStyle(Ink.dim).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PVSectionLabel: View {
    let n: String
    let t: String
    var right: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n) · \(t)".uppercased()).font(InkFont.mono(10.5)).tracking(10.5 * 0.14)
                .foregroundStyle(Ink.dim)
            Spacer(minLength: 0)
            if let right {
                Text(right.uppercased()).font(InkFont.mono(10.5)).tracking(10.5 * 0.1).foregroundStyle(Ink.dim)
            }
        }
        .padding(.horizontal, 16).padding(.top, 26).padding(.bottom, 12)
    }
}

// MARK: - 01 · what kind of week

private struct PVWeek: View {
    let s: PV2
    var body: some View {
        let w = s.week
        let p = s.posture
        let ev = s.events
        VStack(alignment: .leading, spacing: 0) {
            if let w { stanceCard(w) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    if let g = s.gate {
                        PVChip(k: "Seller score", v: pvDec(g.score, 2),
                               sub: g.score >= 1 ? "options rich" : "options cheap",
                               hue: g.score >= 1 ? Ink.gain : Ink.dim)
                        PVChip(k: "Implied vol", v: "\(Int(g.iv.rounded()))%", sub: "\(Int(g.ivPct.rounded()))th %ile")
                    }
                    if let p {
                        PVChip(k: "Momentum", v: "\(p.dev > 0 ? "+" : "")\(pvDec(p.dev, 1))σ", sub: p.state.lowercased())
                        PVChip(k: "Free delta", v: pvInt(p.upsideDelta), sub: "floor \(pvInt(p.floor))",
                               hue: p.upsideDelta < p.floor ? Ink.delayed : Ink.text)
                        PVChip(k: "Freeroll", v: "\(Int(p.freeroll ?? 0))%",
                               sub: p.freerollRegime == "insurance" ? "hedge paid for" : "of the corridor",
                               hue: (p.freeroll ?? 0) >= 100 ? Ink.gain : Ink.text)
                    }
                    if let ev {
                        PVChip(k: "Catalyst", v: ev.heavy.map { "\($0.days)d" } ?? "clear",
                               sub: ev.heavy?.label ?? "nothing scheduled",
                               hue: (ev.daysToHeavy ?? 99) <= 7 ? Ink.delayed : Ink.text)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
    }

    private func stanceCard(_ w: PV2.Week) -> some View {
        let hue = stanceHue(w.stance)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(w.stance).font(InkFont.mono(30, .medium)).tracking(30 * -0.04)
                    .foregroundStyle(hue).lineLimit(1).fixedSize()
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 5) {
                    InkRoll(text: "\(w.score)", font: InkFont.mono(24, .medium), tracking: 24 * -0.03, color: Ink.text)
                    Text("WEEK SCORE").font(InkFont.mono(8.5)).tracking(8.5 * 0.14).foregroundStyle(Ink.dim)
                }
            }
            // Why the number is not the whole story: capacity can override the score.
            if let reason = w.stanceReason {
                Text(reason).font(InkFont.display(13, .regular)).foregroundStyle(Ink.delayed)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            } else if let c = w.caption {
                Text(c).font(InkFont.display(13, .regular)).foregroundStyle(Ink.dim)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            }
            HStack(spacing: 0) {
                PVFig(k: "lots", v: "\(w.lots.base)", sub: w.lots.max > 0 ? "of \(w.lots.max)" : nil)
                PVFig(k: "delta band", v: "\(Int(w.prescription.deltaLo * 100))–\(Int(w.prescription.deltaHi * 100))Δ")
                PVFig(k: "binding", v: (w.binding ?? "—").capitalized,
                      hue: w.binding == "assignment" ? Ink.delayed : Ink.text)
            }
            .padding(.top, 18)
            .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
            .padding(.top, 18)
        }
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 17, trailing: 18))
        .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous).fill(Ink.surface))
        .padding(.horizontal, 16).padding(.bottom, 14)
    }
}

// MARK: - 02 · if they're assigned  (the addition)

private struct PVAssignment: View {
    let a: PV2.Assign
    let p: PV2.Posture
    let shortCallCt: Double
    var body: some View {
        let after = a.deltaAfter
        let worst = a.deltaAfterWorst ?? after
        let bad = after < 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    InkRoll(text: pvSigned(after), font: InkFont.mono(34, .medium), tracking: 34 * -0.04,
                            color: bad ? Ink.loss : after < p.floor ? Ink.delayed : Ink.text)
                    Text("DELTA LEFT ON THE EXPECTED PATH").font(InkFont.mono(9)).tracking(9 * 0.14)
                        .foregroundStyle(Ink.dim).padding(.top, 10).lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(pvSigned(worst)).font(InkFont.mono(17, .regular)).tracking(17 * -0.03)
                        .foregroundStyle(worst < 0 ? Ink.loss : Ink.dim)
                    Text("IF ALL \(Int(shortCallCt)) GO").font(InkFont.mono(8.5)).tracking(8.5 * 0.12)
                        .foregroundStyle(Ink.dim).fixedSize()
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Rectangle().fill(Ink.hair).frame(width: 1) }
            }
            HStack(spacing: 0) {
                PVFig(k: "called away", v: pvInt(a.expectedCalled ?? 0), sub: "sh")
                PVFig(k: "hedge holds", v: pvSigned(a.putDelta))
                PVFig(k: "floor", v: pvInt(p.floor))
            }
            .padding(.top, 16)
            .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
            .padding(.top, 16)
            Text(bad
                 ? "The hedge is sized to the whole share block and does not leave when the shares do — on these odds the book turns short."
                 : "The hedge covers the whole block, so every call assigned leaves the puts behind. This is what survives.")
                .font(InkFont.display(13, .regular)).foregroundStyle(Ink.dim)
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 17, trailing: 18))
        .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous).fill(Ink.surface))
        .padding(.horizontal, 16)
    }
}

// MARK: - 03 · what you're rolling  (grouped by expiry)

private struct PVRolling: View {
    let expiries: [String: [NvStrike]]      // ISO → legs
    let order: [String]
    @Binding var sel: String?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(order, id: \.self) { iso in
                    let legs = expiries[iso] ?? []
                    let on = sel == iso
                    Button { withAnimation(InkMotion.fast) { sel = on ? nil : iso } } label: {
                        card(iso: iso, legs: legs, on: on)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
    }

    private func card(iso: String, legs: [NvStrike], on: Bool) -> some View {
        let ct = legs.reduce(0.0) { $0 + $1.ct }
        let cost = legs.reduce(0.0) { $0 + $1.current }
        let collected = legs.reduce(0.0) { $0 + $1.basis }
        let onLeg = collected - cost
        let dim = on ? Ink.invertText.opacity(0.65) : Ink.dim
        let ink = on ? Ink.invertText : Ink.text
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(legs.first?.expiry.uppercased() ?? iso).font(InkFont.mono(9.5)).tracking(9.5 * 0.1)
                        .foregroundStyle(dim)
                    Spacer(minLength: 0)
                    Text(legs.first?.dte.uppercased() ?? "").font(InkFont.mono(9)).tracking(9 * 0.12)
                        .foregroundStyle(dim)
                }
                Text("\(Int(ct)) CT")
                    .font(InkFont.mono(26, .medium)).tracking(26 * -0.045)
                    .foregroundStyle(ink).padding(.top, 12).lineLimit(1)
                Text(legs.map { pvDec($0.strike, $0.strike == $0.strike.rounded() ? 0 : 1) }.joined(separator: " · "))
                    .font(InkFont.mono(9.5)).tracking(9.5 * 0.1).foregroundStyle(dim)
                    .padding(.top, 11).lineLimit(1)
            }
            .padding(EdgeInsets(top: 16, leading: 16, bottom: 15, trailing: 16))
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("−" + pvUsd(cost)).font(InkFont.mono(17, .regular)).tracking(17 * -0.03)
                        .foregroundStyle(on ? Ink.invertText : Ink.loss).lineLimit(1)
                    Text("TO CLOSE").font(InkFont.mono(9)).tracking(9 * 0.1).foregroundStyle(dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 7) {
                    Text(pvSigned(onLeg).replacingOccurrences(of: pvInt(abs(onLeg)), with: pvUsd(abs(onLeg)).replacingOccurrences(of: "$", with: "$")))
                        .font(InkFont.mono(17, .regular)).tracking(17 * -0.03)
                        .foregroundStyle(on ? Ink.invertText : (onLeg >= 0 ? Ink.gain : Ink.loss)).lineLimit(1)
                    Text("ON THE LEGS").font(InkFont.mono(9)).tracking(9 * 0.1).foregroundStyle(dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(EdgeInsets(top: 13, leading: 16, bottom: 15, trailing: 16))
            .overlay(alignment: .top) {
                Rectangle().fill(on ? Ink.invertText.opacity(0.18) : Ink.hair).frame(height: 1)
            }
        }
        .frame(width: 232, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous)
            .fill(on ? Ink.invertBg : Ink.surface))
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous)
            .strokeBorder(on ? .clear : Ink.hair, lineWidth: 1))
    }
}

// MARK: - 04 · sell into

private struct PVLadder: View {
    let s: PV2
    let lots: Int
    @Binding var ti: Int
    @Binding var pick: Double?

    var body: some View {
        let exps = s.exps
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(Array(exps.enumerated()), id: \.element.id) { i, e in tenor(e, i) } }
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
            if exps.indices.contains(ti) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(exps[ti].cells) { c in strikeCard(c, days: exps[ti].cal) }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }
            }
        }
    }

    private func tenor(_ e: PV2.Expiry, _ i: Int) -> some View {
        let on = i == ti
        return Button { withAnimation(InkMotion.fast) { ti = i; pick = nil } } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(e.dow.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.1)
                    .foregroundStyle(on ? Ink.invertText.opacity(0.65) : Ink.dim)
                Text(e.label).font(InkFont.mono(15, .regular)).tracking(15 * -0.02)
                    .foregroundStyle(on ? Ink.invertText : Ink.text)
                Text(e.eventInside != nil ? (e.eventInside?.label.uppercased() ?? "") : (e.loadCt > 0 ? "\(e.loadCt) CT" : "\(e.cal)D"))
                    .font(InkFont.mono(9)).tracking(9 * 0.1)
                    .foregroundStyle(e.eventInside != nil ? Ink.delayed : (on ? Ink.invertText.opacity(0.65) : Ink.dim))
                    .lineLimit(1)
            }
            .frame(minWidth: 78, alignment: .leading)
            .padding(EdgeInsets(top: 10, leading: 13, bottom: 11, trailing: 13))
            .background(RoundedRectangle(cornerRadius: Ink.radiusElement, style: .continuous)
                .fill(on ? Ink.invertBg : .clear))
            .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement, style: .continuous)
                .strokeBorder(on ? .clear : Ink.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func strikeCard(_ c: PV2.Cell, days: Int) -> some View {
        let on = pick == c.strike || (pick == nil && c.isPick == true)
        let dim = on ? Ink.invertText.opacity(0.65) : Ink.dim
        return Group {
            if c.blocked {
                VStack(alignment: .leading, spacing: 0) {
                    Text(pvDec(c.strike, c.strike == c.strike.rounded() ? 0 : 1))
                        .font(InkFont.mono(26, .medium)).tracking(26 * -0.04).foregroundStyle(Ink.text)
                    Text("BLOCKED").font(InkFont.mono(9)).tracking(9 * 0.12)
                        .foregroundStyle(Ink.dim).padding(.top, 13)
                    Text(c.blockList[0]).font(InkFont.display(12.5, .regular)).foregroundStyle(Ink.dim)
                        .lineSpacing(2).fixedSize(horizontal: false, vertical: true).padding(.top, 11)
                    Spacer(minLength: 0)
                }
                .padding(EdgeInsets(top: 15, leading: 15, bottom: 14, trailing: 15))
                .frame(width: 164, height: 214, alignment: .topLeading)
                .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Ink.hair))
                .opacity(0.42)
            } else {
                Button { withAnimation(InkMotion.fast) { pick = c.strike } } label: { liveCard(c, on: on, dim: dim, days: days) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func liveCard(_ c: PV2.Cell, on: Bool, dim: Color, days: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(pvDec(c.strike, c.strike == c.strike.rounded() ? 0 : 1))
                    .font(InkFont.mono(26, .medium)).tracking(26 * -0.04)
                    .foregroundStyle(on ? Ink.invertText : Ink.text)
                Spacer(minLength: 0)
                if c.isPick == true {
                    Text("PICK").font(InkFont.mono(9)).tracking(9 * 0.12).foregroundStyle(dim)
                }
            }
            Text(pvUsd(c.perDay ?? 0) + "/d").font(InkFont.mono(19, .regular)).tracking(19 * -0.03)
                .foregroundStyle(on ? Ink.invertText : Ink.gain).padding(.top, 13).lineLimit(1)
            Text("\(pvUsd(c.prem * Double(lots) * 100)) OVER \(days)D")
                .font(InkFont.mono(9)).tracking(9 * 0.1).foregroundStyle(dim).padding(.top, 8).lineLimit(1)
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                line("delta", "\(Int((c.delta * 100).rounded()))Δ", dim: dim, on: on)
                line("called", "1 in \(max(2, Int((1 / max(c.assign, 0.01)).rounded())))", dim: dim, on: on)
                line("fit", "\(c.fit ?? 0)", dim: dim, on: on)
            }
            .padding(.top, 12)
            .overlay(alignment: .top) {
                Rectangle().fill(on ? Ink.invertText.opacity(0.18) : Ink.hair).frame(height: 1)
            }
            Text((c.warnList.first ?? "").uppercased()).font(InkFont.mono(8.5)).tracking(8.5 * 0.1)
                .foregroundStyle(on ? dim : Ink.delayed).padding(.top, 11).lineLimit(1)
        }
        .padding(EdgeInsets(top: 15, leading: 15, bottom: 14, trailing: 15))
        .frame(width: 164, height: 214, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous)
            .fill(on ? Ink.invertBg : .clear))
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous)
            .strokeBorder(on ? .clear : Ink.hair, lineWidth: 1))
    }

    private func line(_ k: String, _ v: String, dim: Color, on: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k.uppercased()).font(InkFont.mono(9)).tracking(9 * 0.1).foregroundStyle(dim)
            Spacer(minLength: 0)
            Text(v).font(InkFont.mono(12)).tracking(12 * -0.02)
                .foregroundStyle(on ? Ink.invertText : Ink.text)
        }
    }
}

// MARK: - 05 · why

/// The bar draws CONTRIBUTION (weight × score), not the raw score — otherwise a
/// .05-weight force at +45 outdraws a .23-weight force at +20 while mattering a
/// third as much.
private struct PVForceBar: View {
    let contribution: Double
    /// Largest absolute contribution on the card — the bars read against each other,
    /// which is the only comparison that means anything inside one week.
    let peak: Double
    var body: some View {
        GeometryReader { g in
            let half = g.size.width / 2
            let frac = min(abs(contribution) / max(peak, 0.1), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.hair)
                Rectangle().fill(Ink.dim.opacity(0.5)).frame(width: 1).offset(x: half - 0.5)
                Capsule()
                    .fill(contribution >= 0 ? Ink.gain : Ink.loss)
                    .frame(width: half * frac)
                    .offset(x: contribution >= 0 ? half : half - half * frac)
            }
        }
        .frame(height: 8)
    }
}

private struct PVWhy: View {
    let forces: [PV2.Force]
    let score: Int
    let caption: String?
    @State private var open: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(forces) { f in
                VStack(alignment: .leading, spacing: 0) {
                    Button { withAnimation(InkMotion.fast) { open = open == f.key ? nil : f.key } } label: {
                        HStack(spacing: 12) {
                            Text(f.name).font(InkFont.mono(9.5)).tracking(9.5 * 0.1)
                                .foregroundStyle(open == f.key ? Ink.text : Ink.dim)
                                .frame(width: 108, alignment: .leading).lineLimit(1)
                            PVForceBar(contribution: f.contrib, peak: forces.map { abs($0.contrib) }.max() ?? 1)
                            Text("\(f.contrib >= 0 ? "+" : "−")\(pvDec(abs(f.contrib), 1))")
                                .font(InkFont.mono(12)).foregroundStyle(f.contrib >= 0 ? Ink.text : Ink.loss)
                                .frame(width: 34, alignment: .trailing)
                        }
                        .padding(.vertical, 12).padding(.horizontal, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if open == f.key {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(Array(f.rowList.enumerated()), id: \.offset) { _, r in
                                    if r.count >= 2 { PVFig(k: r[0], v: r[1], size: 14) }
                                }
                            }
                            Text("→ " + f.pushText).font(InkFont.display(12.5, .regular))
                                .foregroundStyle(Ink.delayed).lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 13).padding(.bottom, 15)
                    }
                }
                .background(open == f.key ? Ink.text.opacity(0.05) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: Ink.radiusElement, style: .continuous))
            }
            HStack(alignment: .bottom, spacing: 16) {
                Text("\(score)").font(InkFont.mono(40, .medium)).tracking(40 * -0.045)
                    .foregroundStyle(Ink.text)
                if let caption {
                    Text(caption).font(InkFont.mono(9.5)).tracking(9.5 * 0.06)
                        .foregroundStyle(Ink.dim).multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.top, 15)
            .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
            .padding(.top, 14).padding(.horizontal, 13)
        }
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous).fill(Ink.surface))
        .padding(.horizontal, 16)
    }
}

// MARK: - 06 · if you send it

private struct PVSend: View {
    let cell: PV2.Cell
    let lots: Int
    let closeCost: Double
    let floor: Double
    var body: some View {
        let credit = cell.prem * Double(lots) * 100
        let net = credit - closeCost
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(pvUsd(net)).font(InkFont.mono(34, .medium)).tracking(34 * -0.04)
                        .foregroundStyle(Ink.invertText)
                    Text("NET CREDIT · CLOSE AND REWRITE").font(InkFont.mono(9.5)).tracking(9.5 * 0.1)
                        .foregroundStyle(Ink.invertText.opacity(0.65)).padding(.top, 10).lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("−" + pvUsd(closeCost)).font(InkFont.mono(11)).foregroundStyle(Ink.invertText.opacity(0.65))
                    Text("+" + pvUsd(credit)).font(InkFont.mono(11)).foregroundStyle(Ink.invertText.opacity(0.65))
                }
            }
            HStack(spacing: 0) {
                sendFig("delta sold", "−" + pvInt(cell.deltaSold ?? 0))
                sendFig("free Δ after", pvInt(cell.freeAfter ?? 0), sub: "→\(pvInt(floor))")
                sendFig("after assignment", pvSigned(cell.afterAssign ?? 0))
            }
            .padding(.top, 16)
            .overlay(alignment: .top) { Rectangle().fill(Ink.invertText.opacity(0.18)).frame(height: 1) }
            .padding(.top, 18)
        }
        .padding(EdgeInsets(top: 18, leading: 17, bottom: 17, trailing: 17))
        .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous).fill(Ink.invertBg))
        .padding(.horizontal, 16)
    }

    private func sendFig(_ k: String, _ v: String, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(v).font(InkFont.mono(16, .regular)).tracking(16 * -0.03).foregroundStyle(Ink.invertText).lineLimit(1)
                if let sub { Text(sub).font(InkFont.mono(10)).foregroundStyle(Ink.invertText.opacity(0.65)) }
            }
            Text(k.uppercased()).font(InkFont.mono(9)).tracking(9 * 0.1)
                .foregroundStyle(Ink.invertText.opacity(0.65)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Screen

struct NvdaPlannerV2Screen: View {
    let store: NvdaStore
    var onBack: () -> Void = {}
    /// DEBUG fixture injection — renders without a network round-trip.
    var injected: PV2? = nil
    /// DEBUG: start at layer 03, so the lower half can be screenshotted without a swipe.
    var lowerOnly: Bool = false
    @State private var plan = PlanV2Store()
    @State private var ti = 0
    @State private var pick: Double?
    @State private var rollSel: String?

    var body: some View {
        ZStack {
            Ink.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    InkSectionHead(title: "Plan the next sale")
                    if let s = plan.state, s.ok {
                        content(s)
                    } else if plan.isLoading {
                        quiet("Pricing the chain", "Reading the book and the calendar…")
                    } else {
                        quiet("Planner unavailable", plan.lastError ?? "No response from the model.")
                    }
                    Color.clear.frame(height: 60)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task {
            if let injected { plan.state = injected; plan.isLoading = false; return }
            await plan.load(from: store)
        }
    }

    @ViewBuilder private func content(_ s: PV2) -> some View {
        let exp = s.exps.indices.contains(ti) ? s.exps[ti] : nil
        let cur: PV2.Cell? = exp.flatMap { e in
            e.cells.first { pick == $0.strike && !$0.blocked } ?? e.cells.first { $0.isPick == true }
        }

        if !lowerOnly {
            PVSectionLabel(n: "01", t: "What kind of week is it")
            PVWeek(s: s)

            if let a = s.assignment, let p = s.posture, a.known == true {
                PVSectionLabel(n: "02", t: "If they're assigned")
                PVAssignment(a: a, p: p, shortCallCt: s.book?.shortCallCt ?? 0)
            }
        }

        let groups = rollingGroups()
        if !groups.order.isEmpty {
            PVSectionLabel(n: "03", t: "What you're rolling", right: "\(groups.order.count) dates")
            PVRolling(expiries: groups.byIso, order: groups.order, sel: $rollSel)
        }

        PVSectionLabel(n: "04", t: "Sell into", right: s.week.map { "\($0.lots.base) lots" })
        PVLadder(s: s, lots: max(s.week?.lots.base ?? 1, 1), ti: $ti, pick: $pick)

        if let c = cur, let w = s.week {
            PVSectionLabel(n: "05", t: "Why \(pvDec(c.strike, c.strike == c.strike.rounded() ? 0 : 1))")
            PVWhy(forces: w.forceList, score: w.score, caption: w.caption)

            PVSectionLabel(n: "06", t: "If you send it")
            PVSend(cell: c, lots: max(w.lots.base, 1),
                   closeCost: rollSel.flatMap { groups.byIso[$0] }?.reduce(0) { $0 + $1.current } ?? 0,
                   floor: s.posture?.floor ?? 0)
        } else if exp != nil {
            Text("Every strike at this expiry is blocked.")
                .font(InkFont.display(13, .regular)).foregroundStyle(Ink.delayed)
                .padding(.horizontal, 16).padding(.top, 16)
        }
    }

    /// Open short calls, grouped by expiry — the unit the decision is actually made in.
    private func rollingGroups() -> (byIso: [String: [NvStrike]], order: [String]) {
        guard let pos = store.position else { return ([:], []) }
        let shorts = pos.groups.flatMap { $0.strikes }
            .filter { $0.side == "short" && $0.kind == "call" && !$0.expired }
        var byIso: [String: [NvStrike]] = [:]
        for s in shorts { byIso[PlanV2Store.iso(s.expiry) ?? s.expiry, default: []].append(s) }
        let order = byIso.keys.sorted()
        return (byIso, order)
    }

    private func quiet(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t.uppercased()).font(InkFont.mono(10)).tracking(10 * 0.16).foregroundStyle(Ink.dim)
            Text(b).font(InkFont.display(13, .light)).foregroundStyle(Ink.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 60)
    }
}
