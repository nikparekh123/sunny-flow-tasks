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
        var rollingCt: Double = 0
        var putDelta: Double = 0
        var putFloor: Double = 0
        var putCost: Double = 0
        var putDays: Double = 30
        /// ISO. The floor page names the date the protection runs to, and deriving it
        /// from putDays would land on a day no option expires on.
        var putExpiry: String? = nil
        /// Oldest first. The edge walks these to price an assignment.
        var lots: [Lot] = []
    }
    struct Lot: Encodable, Sendable { let qty: Double; let cost: Double }
    struct Vol: Encodable, Sendable { let iv, ivPct, hv20, hv30, hv60, hv90: Double }
    struct Earn: Encodable, Sendable { let date, label: String }
    let book: Book; let vol: Vol; let earnings: Earn
    let weekendVol: Double
    let spot: Double
    var ticker: String = "NVDA"
    var style: String = "balanced"
    // The two judgements. Sent every request; the edge decays the grade itself.
    var earningsGrade: Double? = nil
    var macroBackdrop: Double? = nil
    /// ISO date. Nil means "the nearest live one" — what the planner has always
    /// done. Set when the user picks a week to roll into. The engine validates it
    /// against the live list and falls back rather than pricing a dead contract.
    var plannedExpiry: String? = nil
    /// Closed P&L, options and shares — NvPerf.realized, which docs/PNL_GLOSSARY.md
    /// makes the single definition of REALISED. Sent rather than re-derived on the
    /// edge, so the all-in figure on the sell page cannot disagree with Performance.
    var realisedPL: Double? = nil
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
    var hedgeCarry: Double?
    var ivMedian: Double?
    var splits: [Split]?
    var floorAdvice: FloorAdvice?
    var regime: Regime?
    var observations: Obs?
    var plan: Plan?
    /// The keep model. Conviction is a view on the stock; keep is what follows from it
    /// plus the event state; the hedge floor can override both.
    struct Plan: Decodable, Sendable {
        var event, price: String?
        var conviction, keepPct, baseline: Double?
        var keepDelta, targetStrike, otmTarget, expectedMove: Double?
        var expiry: String?
        var expDays: Double?
        var grade: Double?
        var convictionParts: [String: Double]?
        var hedge: Hedge?
        var picks: [Pick]?
        var pickList: [Pick] { picks ?? [] }
        struct Hedge: Decodable, Sendable {
            var carryPerDay, tradeCal, needs, quarterRunRate, margin: Double?
        }
        // Every numeric optional on purpose: a field the edge stops sending must degrade
        // the card, never fail the whole decode. Learned the hard way from `load`.
        struct Pick: Decodable, Sendable, Identifiable {
            var strike, otmPct, prem, assign, covers: Double?
            // Break-even is the strike PLUS what you collect, and you collect again every
            // roll — so the cap you actually live with is the month figure, not the strike.
            var breakEven, beWeek, beMonth, gapCost, weeksToCover: Double?
            var delta, ct, wantCt, minCt, keptPct, income: Double?
            var floorBinds, capped: Bool?
            var id: Double { strike ?? 0 }
            var binds: Bool { floorBinds ?? false }
        }
    }
    /// The observer. Six domains, one line each, and a `silent` list naming the
    /// domains that had no data — which the card shows rather than hides.
    struct Obs: Decodable, Sendable {
        var matters: [Line]?
        var quiet: [Line]?
        var silent: [String]?
        var dropped: [String]?
        var mattersList: [Line] { matters ?? [] }
        var quietList: [Line] { quiet ?? [] }
        var silentList: [String] { silent ?? [] }
        struct Line: Decodable, Sendable, Identifiable {
            let domain, tag, text: String
            var kind: String?          // measured | read
            var seen: String?          // priced | underweighted | blind
            var note: Double?
            var id: String { domain }
            /// The score cannot see this at all. The one tag worth surfacing.
            var isBlind: Bool { seen == "blind" }
        }
    }
    struct FloorAdvice: Decodable, Sendable {
        let stale: Bool
        let gapPct, floor, target: Double
        let nowValue, newCost, rollCost: Double
        var why: String?
    }
    struct Split: Decodable, Sendable, Identifiable {
        let legs: [Leg]
        let ct: Int, income: Double, deltaSold: Double, coversPct: Int, days: Int
        var normalIncome: Double?; var ivPremium: Double?
        var id: String { legs.map { "\($0.iso)-\($0.strike)-\($0.ct)" }.joined() }
        struct Leg: Decodable, Sendable { let iso, label: String; let strike: Double; let ct: Int; let income, delta: Double }
    }
    var budget: Budget?
    struct Regime: Decodable, Sendable {
        let name: String
        var why: String?
        let keepPct: Int
        var keepDelta: Double?
        var drawdown: Double?
        var daysToPrint: Int?
        var daysSincePrint: Int?
        var keepWhy: [String]?
        var measured: Measured?
        struct Measured: Decodable, Sendable {
            let band: String; let n: Int; let d30: Double; let applied: Bool
        }
    }
    struct Budget: Decodable, Sendable {
        let room, hardFloor, delta: Double
        let aggression: Double
        var capacityCt: Int?; var style: String?; var rollingCt: Int?
    }
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
        var prior: Prior?
        struct Prior: Decodable, Sendable {
            let score: Int; let stance: String; let takenOn: String
            let change: Int; let daysAgo: Int
        }
        var forceList: [Force] { forces ?? [] }
        struct Rx: Decodable, Sendable { let deltaLo, deltaHi, sizePct: Double; let tenor: String }
        struct Lots: Decodable, Sendable { let base, max: Int; var byFloor: Int?; var byAssignment: Int?; var free: Double? }
    }
    struct Force: Decodable, Sendable, Identifiable {
        let key: String; let name: String; let w: Double; let score: Double
        var family: String?          // what KIND of input this is
        var change: Double?          // vs the same factor a week ago
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
        var rollable: Int?
        var capacityCt: Int?
        var rollSource: String?
        var keptCalled: Double?
        var eventInside: Events.Cat?
        var pickStrike: Double?
        var chain: [Cell]?
        var id: String { iso }
        var loadCt: Int { load ?? 0 }
        var cells: [Cell] { chain ?? [] }
    }
    struct Cell: Decodable, Sendable, Identifiable {
        let strike, prem, delta, assign, effective, vsBasis: Double
        var perDay: Double?; var deltaSold: Double?; var freeAfter: Double?; var afterAssign: Double?; var em: Double?; var calledPerCt: Double?
        var warns: [String]?; var blocks: [String]?
        var fit: Int?; var isPick: Bool?; var rank: Int?
        var suggestCt: Int?; var credit: Double?; var income: Double?
        var netCarry: Double?; var upsideAfterMove: Double?; var perDayPkg: Double?
        var normalIncome: Double?; var ivPremium: Double?
        var calledShares: Double?; var calledPL: Double?; var calledAvg: Double?; var clearsBy: Double?
        var cappedBy: String?
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
    /// The raw response, kept so a commit can echo the plan back VERBATIM. Re-encoding
    /// from the decoded model would archive whatever the Swift structs happen to carry,
    /// not what the engine actually said — and the record has to be the latter.
    private(set) var lastRaw: Data?
    var committedIndex: Int??          // nil = untouched · .some(nil) = declined
    var committing = false
    var commitError: String?
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

    var style = "balanced"
    var rollingCt: Double = 0

    func reload(from store: NvdaStore, ticker: String) async { await load(from: store, ticker: ticker) }

    func load(from store: NvdaStore, ticker: String = "NVDA", expiry: String? = nil) async {
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
            rollingCt: rollingCt,
            putDelta: longPuts.reduce(0.0) { $0 + $1.deltaEst },
            putFloor: putFloor,
            putCost: longPuts.reduce(0.0) { $0 + $1.basis },
            // Days of cover actually bought, weighted by size. The floor is rolled,
            // so its cost is premium per cycle — not theta.
            putDays: {
                let ct = longPuts.reduce(0.0) { $0 + $1.ct }
                guard ct > 0 else { return 30 }
                let d = longPuts.reduce(0.0) { $0 + Double(Int($1.dte.prefix(while: \.isNumber)) ?? 30) * $1.ct }
                return max(1, d / ct)
            }(),
            // Earliest long put — the date the floor actually runs to. compactMap
            // because iso() returns nil on a display string it cannot parse, and a
            // nil in the middle would sort to the front as an empty date.
            putExpiry: longPuts.compactMap { Self.iso($0.expiry) }.sorted().first,
            lots: store.shareLotsFIFO.map { .init(qty: $0.qty_remaining, cost: $0.cost_per_share) })

        let vol = PV2Req.Vol(iv: ins.vol.iv ?? 0, ivPct: ins.vol.ivr ?? 50,
                             hv20: store.hv(20) ?? (ins.vol.hv30 ?? 0), hv30: ins.vol.hv30 ?? 0,
                             hv60: store.hv(60) ?? (ins.vol.hv30 ?? 0), hv90: store.hv(90) ?? (ins.vol.hv30 ?? 0))
        let req = PV2Req(book: book, vol: vol,
                         earnings: ticker == "NVDA"
                             ? .init(date: Self.earnings.date, label: Self.earnings.label)
                             : .init(date: "", label: ""),
                         weekendVol: 0.3, spot: pos.spot, ticker: ticker, style: style,
                         earningsGrade: PlannerDials.shared.grade.map(Double.init),
                         macroBackdrop: Double(PlannerDials.shared.macro),
                         plannedExpiry: expiry,
                         realisedPL: store.perf?.realized)
        do {
            let data = try await client.functions.invoke("nvda-planner",
                options: FunctionInvokeOptions(body: req), decode: { data, _ in data })
            let decoded = try JSONDecoder().decode(PV2.self, from: data)
            guard g == gen else { return }
            if decoded.ok { state = decoded; lastRaw = data; lastError = nil; committedIndex = nil }
            else { lastError = "planner unavailable" }
            isLoading = false
        } catch {
            guard g == gen else { return }
            lastError = String(describing: error); isLoading = false
        }
    }

    /// Records the decision. `index` is 1-based; nil means the answer was to do nothing,
    /// which is a decision and gets stored and scored like any other.
    func commit(_ index: Int?, why: String? = nil, store: NvdaStore, ticker: String = "NVDA") async {
        guard let raw = lastRaw,
              let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let plan = obj["plan"] else { commitError = "nothing to commit"; return }
        committing = true; commitError = nil
        var c: [String: Any] = ["plan": plan, "chosen": index as Any? ?? NSNull()]
        if let o = obj["observations"] { c["observations"] = o }
        if let m = obj["ivMedian"] { c["ivMedian"] = m }
        if let w = why { c["declinedWhy"] = w }
        c["spot"] = store.position?.spot ?? 0
        c["iv"] = store.insights?.vol.iv ?? 0
        c["book"] = ["shares": store.position?.shares ?? 0, "buyAvg": store.position?.avgBuy ?? 0]
        do {
            let body = try JSONSerialization.data(withJSONObject: ["commit": c, "ticker": ticker])
            let data = try await client.functions.invoke(
                "nvda-planner", options: FunctionInvokeOptions(body: body), decode: { d, _ in d })
            let ok = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["ok"] as? Bool ?? false
            // Only claim it landed if the edge says it did. A decision that silently
            // fails to save is worse than one that visibly fails, because you stop
            // checking.
            if ok { committedIndex = .some(index) } else { commitError = "did not save" }
        } catch { commitError = String(describing: error) }
        committing = false
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

/// The model's own vocabulary, said the way a person would say it.
private func runLabel(_ state: String) -> String {
    switch state {
    case "STRETCH": return "run up hard"
    case "WASHOUT": return "beaten down"
    case "TREND":   return "drifting"
    default:        return "mid-range"
    }
}
private func bindingLabel(_ b: String?) -> String {
    switch b {
    case "assignment": return "Called away"
    case "floor":      return "Your minimum"
    default:           return "—"
    }
}

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

    /// The most substantial ranked package across the expiries. Taking the first one
    /// meant the nearest expiry, which on a one-day tenor collects almost nothing and
    /// made the headline read $351 against $3,207 on the trade actually worth doing.
    private func topPackage(_ s: PV2) -> PV2.Cell? {
        s.exps.compactMap { $0.cells.first(where: { $0.rank == 1 }) }
              .max { ($0.income ?? 0) < ($1.income ?? 0) }
    }
    var body: some View {
        let w = s.week
        let p = s.posture
        let ev = s.events
        VStack(alignment: .leading, spacing: 0) {
            if let r = s.regime { regimeCard(r) }
            if let f = s.floorAdvice { floorCard(f) }
            if let w { stanceCard(w) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    if let g = s.gate {
                        // What today's vol is worth in money on a package actually on
                        // the table, rather than a ratio you cannot act on.
                        if let top = topPackage(s), let extra = top.ivPremium, let med = s.ivMedian {
                            PVChip(k: "IV is worth",
                                   v: (extra >= 0 ? "+" : "−") + pvUsd(abs(extra)),
                                   sub: "\(Int(g.iv.rounded()))% vs \(Int(med.rounded())) normal",
                                   hue: extra > 0 ? Ink.gain : Ink.dim)
                        } else {
                            PVChip(k: "Option pricing", v: pvDec(g.score, 2),
                                   sub: g.score >= 1 ? "richer than usual" : "cheaper than usual",
                                   hue: g.score >= 1 ? Ink.gain : Ink.dim)
                        }
                        PVChip(k: "Expected swing", v: "\(Int(g.iv.rounded()))%", sub: "\(Int(g.ivPct.rounded())) of 100 this year")
                    }
                    if let p {
                        PVChip(k: "How far it has run", v: "\(p.dev > 0 ? "+" : "")\(pvDec(p.dev, 1))", sub: runLabel(p.state))
                        PVChip(k: "Upside you own", v: pvInt(p.upsideDelta), sub: "keep at least \(pvInt(p.floor))",
                               hue: p.upsideDelta < p.floor ? Ink.delayed : Ink.text)
                        PVChip(k: "Hedge covered", v: "\(Int(p.freeroll ?? 0))%",
                               sub: p.freerollRegime == "insurance" ? "of the insurance" : "of the downside",
                               hue: (p.freeroll ?? 0) >= 100 ? Ink.gain : Ink.text)
                    }
                    if let ev {
                        PVChip(k: "Next big date", v: ev.heavy.map { "\($0.days)d" } ?? "clear",
                               sub: ev.heavy?.label ?? "nothing scheduled",
                               hue: (ev.daysToHeavy ?? 99) <= 7 ? Ink.delayed : Ink.text)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
    }

    /// What kind of week this is, and how much upside it says to hold back. This
    /// drives the weights and the budget, so it is stated plainly enough to disagree
    /// with rather than left to reshape the numbers silently.
    private func regimeCard(_ r: PV2.Regime) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(r.name).font(InkFont.mono(15, .medium)).tracking(15 * 0.06)
                    .foregroundStyle(Ink.text).lineLimit(1)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(r.keepPct)%").font(InkFont.mono(20, .medium)).tracking(20 * -0.03)
                        .foregroundStyle(Ink.text)
                    Text("KEPT BACK").font(InkFont.mono(9)).tracking(9 * 0.12).foregroundStyle(Ink.dim)
                }
            }
            if let why = r.why {
                Text(why).font(InkFont.display(13.5, .regular)).foregroundStyle(Ink.dim)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            }
            if let kd = r.keepDelta {
                Text("KEEP \(pvInt(kd)) SHARES OF UPSIDE · SELL THE REST")
                    .font(InkFont.mono(9)).tracking(9 * 0.12).foregroundStyle(Ink.dim)
                    .padding(.top, 12).lineLimit(1)
            }
            // What the keep rests on. A number derived from four prints must not read
            // with the confidence of one derived from forty, so the sample travels
            // with it rather than being buried in the response.
            if let m = r.measured {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(m.applied ? "MEASURED" : "ON RECORD")
                        .font(InkFont.mono(8.5)).tracking(8.5 * 0.14)
                        .foregroundStyle(m.applied ? Ink.gain : Ink.dim)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(m.applied ? Ink.gain : Ink.hair, lineWidth: 1))
                    Text("after \(m.band) prints it ran \(m.d30 >= 0 ? "+" : "")\(pvDec(m.d30, 1))% in 30 days")
                        .font(InkFont.display(12.5, .regular)).foregroundStyle(Ink.dim)
                    Spacer(minLength: 0)
                    Text("\(m.n) on record")
                        .font(InkFont.mono(10)).foregroundStyle(m.n < 8 ? Ink.delayed : Ink.dim).fixedSize()
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1).offset(y: -6) }
            }
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 15, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous).fill(Ink.surface))
        .padding(.horizontal, 16).padding(.bottom, 10)
    }

    /// The floor and the calls are one decision, so the floor's state belongs beside
    /// the week rather than out of sight: it is what sets how much upside you keep.
    private func floorCard(_ f: PV2.FloorAdvice) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(f.stale ? "Roll the floor" : "Floor is holding")
                    .font(InkFont.mono(13, .medium)).tracking(13 * 0.06)
                    .foregroundStyle(f.stale ? Ink.delayed : Ink.text).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(pvDec(f.gapPct, 1))% under spot")
                    .font(InkFont.mono(11)).foregroundStyle(Ink.dim).fixedSize()
            }
            if let why = f.why {
                Text(why).font(InkFont.display(13, .regular)).foregroundStyle(Ink.dim)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true).padding(.top, 9)
            }
            if f.stale {
                HStack(spacing: 0) {
                    PVFig(k: "floor now", v: pvDec(f.floor, 0), size: 15)
                    PVFig(k: "move to", v: pvDec(f.target, 0), size: 15)
                    PVFig(k: "costs", v: pvUsd(f.rollCost), size: 15)
                }
                .padding(.top, 14)
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
                .padding(.top, 14)
            }
        }
        .padding(EdgeInsets(top: 15, leading: 18, bottom: 14, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous).fill(Ink.surface))
        .padding(.horizontal, 16).padding(.bottom, 10)
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
                    if let p = w.prior {
                        Text("\(p.change >= 0 ? "+" : "−")\(abs(p.change)) VS \(p.daysAgo)D AGO")
                            .font(InkFont.mono(8.5)).tracking(8.5 * 0.12)
                            .foregroundStyle(p.change >= 0 ? Ink.gain : Ink.loss).fixedSize()
                    } else {
                        Text("WEEK SCORE").font(InkFont.mono(8.5)).tracking(8.5 * 0.14).foregroundStyle(Ink.dim)
                    }
                }
            }
            // Why the number is not the whole story: capacity can override the score.
            if let reason = w.stanceReason {
                Text(reason).font(InkFont.display(13, .regular)).foregroundStyle(Ink.delayed)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            } else if let c = w.caption, !c.isEmpty {
                Text(c.prefix(1).uppercased() + c.dropFirst() + ".")
                    .font(InkFont.display(13, .regular)).foregroundStyle(Ink.dim)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            }
            HStack(spacing: 0) {
                PVFig(k: "contracts", v: "\(w.lots.base)", sub: w.lots.max > 0 ? "of \(w.lots.max)" : nil)
                PVFig(k: "aim for", v: "\(Int(w.prescription.deltaLo * 100))–\(Int(w.prescription.deltaHi * 100))Δ")
                PVFig(k: "what limits it", v: bindingLabel(w.binding),
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
                    Text("UPSIDE LEFT IF THEY GO").font(InkFont.mono(9)).tracking(9 * 0.14)
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
                PVFig(k: "hedge stays", v: pvSigned(a.putDelta))
                PVFig(k: "minimum", v: pvInt(p.floor))
            }
            .padding(.top, 16)
            .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
            .padding(.top, 16)
            Text(bad
                 ? "Your puts cover every share, so they stay behind when the shares are called away. On these odds that leaves you pointing the wrong way."
                 : "Your puts cover every share and stay behind when the shares go. This is the upside that survives.")
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
        let dim = on ? Ink.invertDim : Ink.dim
        let ink = on ? Ink.invertText : Ink.text
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(legs.first?.expiry.uppercased() ?? iso).font(InkFont.mono(9.5)).tracking(9.5 * 0.1)
                        .foregroundStyle(dim)
                    Spacer(minLength: 0)
                    Text((legs.first?.dte ?? "").replacingOccurrences(of: "DTE", with: "DAYS").uppercased())
                        .font(InkFont.mono(9)).tracking(9 * 0.12)
                        .foregroundStyle(dim)
                }
                Text("\(Int(ct)) SOLD")
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
                    Text("TO BUY BACK").font(InkFont.mono(9)).tracking(9 * 0.1).foregroundStyle(dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 7) {
                    Text(pvSigned(onLeg).replacingOccurrences(of: pvInt(abs(onLeg)), with: pvUsd(abs(onLeg)).replacingOccurrences(of: "$", with: "$")))
                        .font(InkFont.mono(17, .regular)).tracking(17 * -0.03)
                        .foregroundStyle(on ? Ink.invertText : (onLeg >= 0 ? Ink.gain : Ink.loss)).lineLimit(1)
                    Text("MADE SO FAR").font(InkFont.mono(9)).tracking(9 * 0.1).foregroundStyle(dim)
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
                        ForEach(ranked(exps[ti])) { c in strikeCard(c, days: exps[ti].cal) }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }
            }
        }
    }

    /// Ranked packages first, then everything else so the blocked ones stay visible.
    private func ranked(_ e: PV2.Expiry) -> [PV2.Cell] {
        let top = e.cells.filter { $0.rank != nil }.sorted { ($0.rank ?? 9) < ($1.rank ?? 9) }
        return top + e.cells.filter { $0.rank == nil }
    }

    private func tenor(_ e: PV2.Expiry, _ i: Int) -> some View {
        let on = i == ti
        return Button { withAnimation(InkMotion.fast) { ti = i; pick = nil } } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(e.dow.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.1)
                    .foregroundStyle(on ? Ink.invertDim : Ink.dim)
                Text(e.label).font(InkFont.mono(15, .regular)).tracking(15 * -0.02)
                    .foregroundStyle(on ? Ink.invertText : Ink.text)
                Text(e.eventInside != nil ? (e.eventInside?.label.uppercased() ?? "") : (e.loadCt > 0 ? "\(e.loadCt) SOLD" : "\(e.cal) DAYS"))
                    .font(InkFont.mono(9)).tracking(9 * 0.1)
                    .foregroundStyle(e.eventInside != nil ? Ink.delayed : (on ? Ink.invertDim : Ink.dim))
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

    /// A package, not a strike: the instruction is "sell N at K", and the three
    /// best are ranked. Blocked strikes stay visible with their reason.
    private func strikeCard(_ c: PV2.Cell, days: Int) -> some View {
        let on = pick == c.strike || (pick == nil && c.isPick == true)
        return Group {
            if c.blocked {
                VStack(alignment: .leading, spacing: 0) {
                    Text(strikeLabel(c.strike))
                        .font(InkFont.mono(26, .medium)).tracking(26 * -0.04).foregroundStyle(Ink.text)
                    Text("NOT WORTH IT").font(InkFont.mono(9.5)).tracking(9.5 * 0.12)
                        .foregroundStyle(Ink.dim).padding(.top, 12)
                    Text(c.blockList[0]).font(InkFont.display(13.5, .regular)).foregroundStyle(Ink.dim)
                        .lineSpacing(2).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                    Spacer(minLength: 0)
                }
                .padding(EdgeInsets(top: 17, leading: 18, bottom: 16, trailing: 18))
                .frame(width: 236, height: 236, alignment: .topLeading)
                .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Ink.hair))
                .opacity(0.42)
            } else {
                Button { withAnimation(InkMotion.fast) { pick = c.strike } } label: { liveCard(c, on: on, days: days) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func strikeLabel(_ v: Double) -> String { pvDec(v, v == v.rounded() ? 0 : 1) }
    private func ordinal(_ n: Int) -> String { n == 1 ? "1ST" : n == 2 ? "2ND" : "3RD" }

    private func liveCard(_ c: PV2.Cell, on: Bool, days: Int) -> some View {
        let dim = on ? Ink.invertDim : Ink.dim
        let ink = on ? Ink.invertText : Ink.text
        let ct = c.suggestCt ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let r = c.rank {
                    Text(ordinal(r)).font(InkFont.mono(9.5, .medium)).tracking(9.5 * 0.14)
                        .foregroundStyle(r == 1 ? (on ? Ink.invertText : Ink.gain) : dim)
                }
                Spacer(minLength: 0)
                Text("\(Int((c.delta * 100).rounded()))Δ · \(Int((c.assign * 100).rounded()))% CALLED")
                    .font(InkFont.mono(9.5)).tracking(9.5 * 0.06).foregroundStyle(dim).lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("sell ").font(InkFont.display(17, .regular)).foregroundStyle(dim)
                Text("\(ct)").font(InkFont.mono(30, .medium)).tracking(30 * -0.04)
                    .foregroundStyle(ink).lineLimit(1).fixedSize()
                Text(" at ").font(InkFont.display(17, .regular)).foregroundStyle(dim)
                Text(strikeLabel(c.strike)).font(InkFont.mono(22, .medium)).tracking(22 * -0.03)
                    .foregroundStyle(ink).lineLimit(1).fixedSize()
            }
            .padding(.top, 10)

            Text("\(pvUsd(c.income ?? 0)) INCOME OVER \(days)D")
                .font(InkFont.mono(9.5)).tracking(9.5 * 0.1).foregroundStyle(dim)
                .padding(.top, 9).lineLimit(1)

            Spacer(minLength: 10)

            VStack(spacing: 7) {
                pkgLine("carries the hedge", (c.netCarry ?? 0) >= 0
                        ? "+\(pvUsd(c.netCarry ?? 0))/d" : "−\(pvUsd(abs(c.netCarry ?? 0)))/d",
                        good: (c.netCarry ?? 0) >= 0, on: on, dim: dim)
                pkgLine("upside after a move", pvInt(c.upsideAfterMove ?? 0),
                        good: (c.upsideAfterMove ?? 0) > 0, on: on, dim: dim)
                if let cb = c.clearsBy {
                    pkgLine(cb >= 0 ? "clears break-even by" : "under break-even by",
                            "$" + pvDec(abs(cb), 2), good: cb >= 0, on: on, dim: dim)
                }
            }
            .padding(.top, 12)
            .overlay(alignment: .top) {
                Rectangle().fill(on ? Ink.invertText.opacity(0.18) : Ink.hair).frame(height: 1).offset(y: -12)
            }

            HStack(alignment: .center, spacing: 10) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(on ? Ink.invertText.opacity(0.22) : Ink.hair)
                        Capsule().fill(ink).frame(width: g.size.width * min(Double(c.fit ?? 0) / 100, 1))
                    }
                }
                .frame(width: 48, height: 4)
                Spacer(minLength: 0)
                Text("\(c.fit ?? 0)").font(InkFont.mono(15, .regular)).foregroundStyle(ink).fixedSize()
                if let w = c.warnList.first {
                    Text(w).font(InkFont.mono(9)).tracking(9 * 0.08)
                        .foregroundStyle(on ? dim : Ink.delayed).lineLimit(1).truncationMode(.tail)
                }
            }
            .padding(.top, 12)
        }
        .padding(EdgeInsets(top: 15, leading: 18, bottom: 15, trailing: 18))
        .frame(width: 236, height: 236, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous)
            .fill(on ? Ink.invertBg : .clear))
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous)
            .strokeBorder(on ? .clear : Ink.hair, lineWidth: 1))
    }

    private func pkgLine(_ k: String, _ v: String, good: Bool, on: Bool, dim: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k.uppercased()).font(InkFont.mono(9)).tracking(9 * 0.1).foregroundStyle(dim)
            Spacer(minLength: 0)
            Text(v).font(InkFont.mono(12)).tracking(12 * -0.02)
                .foregroundStyle(on ? Ink.invertText : (good ? Ink.text : Ink.loss))
        }
    }
}

/// How you like your upside packaged. A standing preference, not a weekly call:
/// it shifts which strike the ladder leans toward, never how much gets sold.
private struct PVStyle: View {
    @Binding var style: String
    var onChange: () -> Void
    private let opts: [(String, String)] = [
        ("closer", "Fewer, closer"), ("balanced", "Balanced"), ("further", "More, further"),
    ]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(opts, id: \.0) { key, label in
                let on = style == key
                Button {
                    guard !on else { return }
                    withAnimation(InkMotion.fast) { style = key }
                    onChange()
                } label: {
                    Text(label.uppercased()).font(InkFont.mono(9.5, .medium)).tracking(9.5 * 0.08)
                        .foregroundStyle(on ? Ink.invertText : Ink.dim)
                        .frame(maxWidth: .infinity).frame(minHeight: 34)
                        .background(RoundedRectangle(cornerRadius: Ink.radiusElement, style: .continuous)
                            .fill(on ? Ink.invertBg : .clear))
                        .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement, style: .continuous)
                            .strokeBorder(on ? .clear : Ink.hair, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Two expiries as one trade. Shown against the best single-expiry package on the
/// same budget, because splitting is not free: a near leg with little time left
/// spends half the budget on extrinsic that barely exists.
private struct PVSplits: View {
    let splits: [PV2.Split]
    let bestSingle: (label: String, ct: Int, strike: Double, income: Double)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(splits) { sp in card(sp) }
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            if let b = bestSingle, let top = splits.first {
                let gap = top.income - b.income
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(gap >= 0 ? "Splitting earns" : "Splitting costs")
                        .font(InkFont.display(13.5, .regular)).foregroundStyle(Ink.dim)
                    Text((gap >= 0 ? "+" : "−") + pvUsd(abs(gap)))
                        .font(InkFont.mono(15, .medium)).foregroundStyle(gap >= 0 ? Ink.gain : Ink.loss)
                    Text("against \(b.ct) at \(pvDec(b.strike, b.strike == b.strike.rounded() ? 0 : 1)) on \(b.label) alone")
                        .font(InkFont.display(13.5, .regular)).foregroundStyle(Ink.dim)
                }
                .padding(.horizontal, 16).padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func card(_ sp: PV2.Split) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sp.legs.enumerated()), id: \.offset) { i, l in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(l.ct)").font(InkFont.mono(22, .medium)).tracking(22 * -0.03)
                        .foregroundStyle(Ink.text)
                    Text(" at ").font(InkFont.display(14, .regular)).foregroundStyle(Ink.dim)
                    Text(pvDec(l.strike, l.strike == l.strike.rounded() ? 0 : 1))
                        .font(InkFont.mono(18, .medium)).foregroundStyle(Ink.text)
                    Spacer(minLength: 8)
                    Text(l.label).font(InkFont.mono(10)).foregroundStyle(Ink.dim).fixedSize()
                }
                .padding(.top, i == 0 ? 0 : 10)
            }
            Spacer(minLength: 12)
            Text(pvUsd(sp.income)).font(InkFont.mono(24, .medium)).tracking(24 * -0.03)
                .foregroundStyle(Ink.gain)
            Text("\(sp.ct) CONTRACTS · \(pvInt(sp.deltaSold))Δ · COVERS \(sp.coversPct)%")
                .font(InkFont.mono(9.5)).tracking(9.5 * 0.08).foregroundStyle(Ink.dim)
                .padding(.top, 8).lineLimit(1)
        }
        .padding(EdgeInsets(top: 16, leading: 17, bottom: 15, trailing: 17))
        .frame(width: 250, height: 186, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous)
            .strokeBorder(Ink.hair, lineWidth: 1))
    }
}

// MARK: - 05 · why

/// Each force is its own card: what it says, what it is worth, and the one figure
/// behind it. The number is CONTRIBUTION (weight × score), not the raw score —
/// otherwise a .05-weight force at +45 outshouts a .23-weight force at +20 while
/// mattering a third as much. Tapping opens the rest of its rows.
private struct PVForceCard: View {
    let f: PV2.Force
    let peak: Double
    let open: Bool
    let onTap: () -> Void

    private var hue: Color { f.contrib >= 0 ? Ink.gain : Ink.loss }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(f.name).font(InkFont.mono(9.5)).tracking(9.5 * 0.1)
                        .foregroundStyle(Ink.dim).lineLimit(1)
                    Spacer(minLength: 0)
                    if let fam = f.family {
                        Text(fam).font(InkFont.mono(8.5)).tracking(8.5 * 0.1)
                            .foregroundStyle(Ink.dim).lineLimit(1)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .overlay(Capsule().strokeBorder(Ink.hair, lineWidth: 1))
                    }
                }

                Text(f.pushText.isEmpty ? "—" : f.pushText)
                    .font(InkFont.display(14.5, .regular)).foregroundStyle(Ink.text)
                    .lineSpacing(3).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                Spacer(minLength: 12)

                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    InkRoll(text: (f.contrib >= 0 ? "+" : "−") + pvDec(abs(f.contrib), 1),
                            font: InkFont.mono(30, .medium), tracking: 30 * -0.04, color: hue)
                    if let ch = f.change, abs(ch) >= 0.1 {
                        Text("\(ch >= 0 ? "+" : "−")\(pvDec(abs(ch), 1)) VS LAST WEEK")
                            .font(InkFont.mono(9)).tracking(9 * 0.1)
                            .foregroundStyle(Ink.dim).lineLimit(1)
                    }
                }

                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Ink.hair)
                        Capsule().fill(hue)
                            .frame(width: g.size.width * min(abs(f.contrib) / max(peak, 0.1), 1))
                    }
                }
                .frame(height: 4)
                .padding(.top, 14)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(rowsShown.enumerated()), id: \.offset) { _, r in
                        if r.count >= 2 {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(r[0].uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.1)
                                    .foregroundStyle(Ink.dim).lineLimit(1)
                                Text(r[1]).font(InkFont.mono(11)).foregroundStyle(Ink.text).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                .padding(.top, 14)
            }
            .padding(EdgeInsets(top: 17, leading: 17, bottom: 16, trailing: 17))
            .frame(width: 248, height: open ? 300 : 248, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous)
                .fill(open ? Ink.text.opacity(0.05) : .clear))
            .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous)
                .strokeBorder(Ink.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Collapsed shows only the headline figure; tapping brings the rest.
    private var rowsShown: [[String]] { open ? f.rowList : Array(f.rowList.prefix(1)) }
}

private struct PVWhy: View {
    let forces: [PV2.Force]
    let score: Int
    let caption: String?
    var priorNote: String? = nil
    @State private var open: String?

    var body: some View {
        let peak = forces.map { abs($0.contrib) }.max() ?? 1
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    InkRoll(text: "\(score)", font: InkFont.mono(44, .medium),
                            tracking: 44 * -0.045, color: Ink.text)
                    Text(priorNote ?? "OF 100").font(InkFont.mono(9.5)).tracking(9.5 * 0.14)
                        .foregroundStyle(Ink.dim).fixedSize()
                }
                if let caption {
                    Text(caption.prefix(1).uppercased() + caption.dropFirst() + ".")
                        .font(InkFont.display(15, .regular)).foregroundStyle(Ink.text)
                        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 18, leading: 17, bottom: 0, trailing: 17))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(forces) { f in
                        PVForceCard(f: f, peak: peak, open: open == f.key) {
                            withAnimation(InkMotion.fast) { open = open == f.key ? nil : f.key }
                        }
                    }
                }
                .padding(.horizontal, 17).padding(.top, 18).padding(.bottom, 17)
            }
        }
        .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous).fill(Ink.surface))
        .padding(.horizontal, 16)
    }
}

// MARK: - 06 · if you send it

/// The whole trade on one page: what you close, what you open, and what the shares
/// book if the new calls are exercised. Three lines and a total, because that is
/// how the decision is actually weighed.
private struct PVSend: View {
    let cell: PV2.Cell
    let closeCt: Int
    let closeCost: Double        // cash to buy them back
    let closeCollected: Double   // what you were paid to write them
    let buyAvg: Double
    let floor: Double
    let spot: Double
    let bookNet: Double          // NvPnL.net — where the whole position stands today

    var body: some View {
        let openCt = cell.suggestCt ?? 0
        let credit = cell.prem * Double(openCt) * 100
        // Buying a call back is not a loss of the whole cash cost — you were paid to
        // write it. What the leg actually books is collected less the cost to close.
        let closePL = closeCollected - closeCost
        let sharesCalled = cell.calledShares ?? Double(openCt) * 100
        // Oldest lots leave first, so this is their cost, not the book average.
        let sharesPL = cell.calledPL ?? ((cell.strike - buyAvg) * sharesCalled)
        let calledAvg = cell.calledAvg ?? buyAvg
        let bookedByTrade = closePL + credit + sharesPL
        // Most of the share gain is already in your open P&L — the shares are worth
        // spot today. Being called at the strike only ADDS the difference, so the
        // overall figure moves by that plus the new premium. Adding the whole share
        // gain would count the paper gain you already hold twice.
        let aboveToday = (cell.strike - spot) * sharesCalled
        let overall = bookNet + credit + aboveToday

        return VStack(alignment: .leading, spacing: 0) {
            Text(pvUsd(overall)).font(InkFont.mono(38, .medium)).tracking(38 * -0.04)
                .foregroundStyle(Ink.invertText).lineLimit(1)
            Text("Your whole NVDA P&L, if called at \(pvDec(cell.strike, cell.strike == cell.strike.rounded() ? 0 : 1))")
                .font(InkFont.mono(12, .medium))
                .foregroundStyle(Ink.invertDim).padding(.top, 10).lineLimit(1)

            VStack(spacing: 11) {
                leg("Where you stand today", bookNet, sub: "Realized and open, all of it")
                leg("New premium", credit, sub: "Yours either way")
                leg("Shares sold above today's price", aboveToday,
                    sub: "\(pvDec(cell.strike, 2)) against \(pvDec(spot, 2)) now")
            }
            .padding(.top, 18)
            .overlay(alignment: .top) { Rectangle().fill(Ink.invertText.opacity(0.18)).frame(height: 1) }
            .padding(.top, 18)

            Text("What the trade itself books  \(pvUsd(bookedByTrade))")
                .font(InkFont.mono(12, .medium))
                .foregroundStyle(Ink.invertDim).padding(.top, 20).lineLimit(1)

            VStack(spacing: 11) {
                leg("Close \(closeCt)", closePL,
                    sub: "\(pvUsd(closeCollected)) collected, \(pvUsd(closeCost)) to buy back")
                leg("Open \(openCt) at \(pvDec(cell.strike, cell.strike == cell.strike.rounded() ? 0 : 1))", credit,
                    sub: "Premium, if it expires worthless")
                leg("\(pvInt(sharesCalled)) shares sold at \(pvDec(cell.strike, cell.strike == cell.strike.rounded() ? 0 : 1))", sharesPL,
                    sub: "Oldest lots first, cost \(pvDec(calledAvg, 2))")
            }
            .padding(.top, 18)
            .overlay(alignment: .top) { Rectangle().fill(Ink.invertText.opacity(0.18)).frame(height: 1) }
            .padding(.top, 18)

            HStack(spacing: 0) {
                sendFig("Upside given up", "−" + pvInt(cell.deltaSold ?? 0))
                sendFig("Upside left", pvInt(cell.freeAfter ?? 0), sub: "min \(pvInt(floor))")
                sendFig("If called", pvSigned(cell.afterAssign ?? 0))
            }
            .padding(.top, 16)
            .overlay(alignment: .top) { Rectangle().fill(Ink.invertText.opacity(0.18)).frame(height: 1) }
            .padding(.top, 18)
        }
        .padding(EdgeInsets(top: 18, leading: 17, bottom: 17, trailing: 17))
        .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous).fill(Ink.invertBg))
        .padding(.horizontal, 16)
    }

    private func leg(_ k: String, _ v: Double, sub: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(k).font(InkFont.mono(12, .medium))
                    .foregroundStyle(Ink.invertDim).lineLimit(1)
                if let sub {
                    Text(sub).font(InkFont.mono(11, .medium))
                        .foregroundStyle(Ink.invertDim).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text((v >= 0 ? "+" : "−") + pvUsd(abs(v)))
                .font(InkFont.mono(20, .regular)).tracking(18 * -0.03)
                .foregroundStyle(Ink.invertText).lineLimit(1)
        }
    }

    private func sendFig(_ k: String, _ v: String, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(v).font(InkFont.mono(20, .regular)).tracking(16 * -0.03)
                    .foregroundStyle(Ink.invertText).lineLimit(1)
                if let sub { Text(sub).font(InkFont.mono(12, .medium)).foregroundStyle(Ink.invertDim) }
            }
            Text(k).font(InkFont.mono(12, .medium))
                .foregroundStyle(Ink.invertDim).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Screen

struct NvdaPlannerV2Screen: View {
    let store: NvdaStore
    var ticker: String = "NVDA"
    var onBack: () -> Void = {}
    /// DEBUG fixture injection — renders without a network round-trip.
    var injected: PV2? = nil
    /// DEBUG: start at layer 03, so the lower half can be screenshotted without a swipe.
    var lowerOnly: Bool = false
    /// DEBUG: only the last two layers.
    var tailOnly: Bool = false
    @State private var plan = PlanV2Store()
    @State private var ti = 0
    @State private var pick: Double?
    @State private var rollSel: String?
    @State private var style = "balanced"

    var body: some View {
        ZStack {
            Ink.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
            // Presented full-screen, so the dismiss has to live on the screen itself.
            HStack(spacing: 13) {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Ink.text)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(Ink.hair, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Text("Plan the next sale")
                    .font(InkFont.serif(27, .regular)).foregroundStyle(Ink.text)
                Spacer(minLength: 0)
                Text(ticker).font(InkFont.mono(11.5)).tracking(11.5 * 0.12).foregroundStyle(Ink.dim)
            }
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 16)
            .overlay(alignment: .bottom) { Rectangle().fill(Ink.hair).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let s = plan.state, s.ok {
                        content(s)
                    } else if plan.isLoading {
                        quiet("Working it out", "Reading your position and the calendar…")
                    } else {
                        quiet("Planner unavailable", plan.lastError ?? "No response from the model.")
                    }
                    Color.clear.frame(height: 60)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            }
        }
        .task {
            if let injected { plan.state = injected; plan.isLoading = false; return }
            await plan.load(from: store, ticker: ticker)
        }
    }

    @ViewBuilder private func content(_ s: PV2) -> some View {
        let exp = s.exps.indices.contains(ti) ? s.exps[ti] : nil
        let cur: PV2.Cell? = exp.flatMap { e in
            e.cells.first { pick == $0.strike && !$0.blocked } ?? e.cells.first { $0.isPick == true }
        }

        if !lowerOnly && !tailOnly {
            PVSectionLabel(n: "01", t: "What kind of week is it")
            PVWeek(s: s)

            if let a = s.assignment, let p = s.posture, a.known == true {
                PVSectionLabel(n: "02", t: "If they get called away")
                PVAssignment(a: a, p: p, shortCallCt: s.book?.shortCallCt ?? 0)
            }
        }

        let groups = rollingGroups()
        if !groups.order.isEmpty && !tailOnly {
            PVSectionLabel(n: "03", t: "What you already sold", right: "\(groups.order.count) dates")
            PVRolling(expiries: groups.byIso, order: groups.order, sel: $rollSel)
                .onChange(of: rollSel) { _, new in
                    // Picking legs to close hands their lots back, so capacity and
                    // every package count change. Clearing it returns to the default
                    // assumption that you are rolling whatever expires first.
                    plan.rollingCt = new.flatMap { groups.byIso[$0] }?.reduce(0) { $0 + $1.ct } ?? 0
                    replan(s)
                }
        }

        if !tailOnly {
            PVSectionLabel(n: "04", t: "What to sell",
                           right: s.budget.map { "sell \(pvInt($0.delta)) upside" })
            PVStyle(style: $style) { replan(s) }
                .padding(.bottom, 12)
            PVLadder(s: s, lots: max(s.week?.lots.base ?? 1, 1), ti: $ti, pick: $pick)
        }

        if let c = cur, let w = s.week {
            if let sp = s.splits, sp.count >= 1 {
            PVSectionLabel(n: "05", t: "Or split it across two dates", right: "\(sp.count)")
            PVSplits(splits: sp, bestSingle: bestSingle(s))
        }

        PVSectionLabel(n: "06", t: "Why \(pvDec(c.strike, c.strike == c.strike.rounded() ? 0 : 1))", right: "Tap for detail")
            PVWhy(forces: w.forceList, score: w.score, caption: w.caption,
                  priorNote: w.prior.map { "OF 100 · WAS \($0.score)" })

            PVSectionLabel(n: "07", t: "If you place it")
            let closing = rollSel.flatMap { groups.byIso[$0] } ?? []
            PVSend(cell: c,
                   closeCt: Int(closing.reduce(0) { $0 + $1.ct }),
                   closeCost: closing.reduce(0) { $0 + $1.current },
                   closeCollected: closing.reduce(0) { $0 + $1.basis },
                   buyAvg: s.book?.buyAvg ?? 0,
                   floor: s.posture?.floor ?? 0,
                   spot: s.gate?.spot ?? 0,
                   bookNet: store.pnl?.net ?? 0)
        } else if exp != nil {
            Text("Nothing on this date is worth selling — try another date.")
                .font(InkFont.display(13, .regular)).foregroundStyle(Ink.delayed)
                .padding(.horizontal, 16).padding(.top, 16)
        }
    }

    private func replan(_ current: PV2) {
        plan.style = style
        Task { await plan.load(from: store, ticker: ticker) }
    }

    /// The best single-expiry package on the same budget — the thing a split has to
    /// beat, and usually does not when the near leg has no time left in it.
    private func bestSingle(_ s: PV2) -> (label: String, ct: Int, strike: Double, income: Double)? {
        var best: (String, Int, Double, Double)? = nil
        for e in s.exps.prefix(2) {
            for c in e.cells where c.rank == 1 {
                if best == nil || (c.income ?? 0) > best!.3 {
                    best = (e.label, c.suggestCt ?? 0, c.strike, c.income ?? 0)
                }
            }
        }
        return best.map { (label: $0.0, ct: $0.1, strike: $0.2, income: $0.3) }
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
