//
//  PlannerPagesModel.swift
//  The planner response, as the pages need it.
//
//  Every field is optional and every list defaults to empty. That is not
//  defensive habit — the engine is deployed separately from the app, so any
//  build of this app WILL at some point meet a response older or newer than it
//  expects. A page that renders "—" for a field it did not get is correct; a
//  decode that throws takes down all seven pages over one missing key.
//
//  Nothing is computed here that the server already decides. The only local
//  arithmetic is presentational: percent-out from strike and spot, and the
//  payoff chart's geometry.
//

import Foundation

struct PPResponse: Decodable {
    var ok: Bool?
    var ticker: String?
    var book: PPBook?
    var plan: PPPlan?
    var observations: PPObservations?
    var floorAdvice: PPFloor?
    var history: PPHistory?
    var expiries: [PPExpiry]?
}

struct PPBook: Decodable { var shares: Double?; var buyAvg: Double? }

struct PPExpiry: Decodable {
    var iso: String?
    var label: String?
    /// A CONTRACT COUNT, not a sentence. The design's prototype carried a
    /// pre-cased string here; the engine sends a number, and a String? property
    /// throws on it — an optional tolerates a missing key, never a wrong type.
    /// That single mismatch was enough to fail the whole decode.
    var load: Double?
    var rollable: Double?
    var verdict: String?

    /// "60 sold for Aug 12, 60 rollable" — built here rather than on the server.
    var line: String? {
        guard let l = load, l > 0, let lab = label else { return nil }
        let rollTxt = rollable.map { $0 > 0 ? ", \(Int($0)) rollable" : "" } ?? ""
        return "\(Int(l)) sold for \(lab)\(rollTxt)"
    }
}

struct PPPlan: Decodable {
    var conviction: Int?
    var convictionParts: [String: Double]?
    var baseline: Int?
    var size: PPSize?
    var keepPct: Double?
    var keepDelta: Double?
    var keepNeutral: Double?
    var event: String?
    var price: String?
    var why: String?
    var paidVsNormal: Double?
    var expiry: String?
    var expDays: Int?
    var expectedMove: Double?
    var picks: [PPPick]?
    var hedgeNote: String?
    var tierNote: String?
    var grade: Int?
    var gradeQuarter: PPGradeQuarter?
    var gradeHistory: [PPGradeRow]?
}

struct PPSize: Decodable {
    var sold: Int?
    var full: Int?
    var strike: Double?
    var fullStrike: Double?
    /// False, and the copy must respect it: conviction moves the count, not the
    /// strike. otmTarget has no conviction term.
    var strikeMoves: Bool?
}

struct PPPick: Decodable {
    var strike: Double?
    var ct: Int?
    /// What this same tier would have sold at a neutral 50 — a real second run
    /// of the sizing, not an estimate.
    var wasCt: Int?
    var delta: Double?
    var gamma: Double?
    var iv: Double?
    var prem: Double?
    /// The engine spells it breakEven; the design's sample spelled it breakeven.
    /// Both are accepted so neither an old nor a new response loses the line.
    var breakEven: Double?
    var breakeven: Double?
    var otmPct: Double?
    /// Breakeven measured against what the shares cost, not against spot.
    var beBasisPct: Double?
    var income: Double?
    var assign: Double?
    var blocked: String?
    var priced: String?

    var be: Double? { breakEven ?? breakeven }
}

struct PPGradeQuarter: Decodable {
    var label: String?
    var reported: String?
    var sessionsAgo: Int?
    var graded: Bool?
    var nextPrint: String?
}

struct PPGradeRow: Decodable {
    var q: String?
    var on: String?
    /// Null means not graded yet. It is NOT a zero — zero is the harshest grade
    /// on the scale and the two cannot share a slot.
    var g: Int?
    var current: Bool?
}

struct PPObservations: Decodable {
    var matters: [PPNote]?
    var quiet: [PPNote]?
}

struct PPNote: Decodable {
    /// The engine calls it `tag`; the design's sample called it `lede`.
    var tag: String?
    var lede: String?
    var text: String?
    var domain: String?
    var seen: String?
    var heading: String { lede ?? tag ?? "" }
}

struct PPFloor: Decodable {
    var floor: Double?
    var gapPct: Double?
    var head: String?
    var stale: Bool?
}

struct PPHistory: Decodable {
    var trail: [PPReading]?
    var today: PPReading?
}

struct PPReading: Decodable {
    var date: String?
    var conviction: Int?
    var parts: [String: Double]?
}

// MARK: - Families

/// The nine conviction families, in the order the design's grid draws them when
/// nothing has moved. Caps are the engine's own, so a disc's weight is measured
/// against what that family could contribute, not against the total.
struct PPFamily: Identifiable {
    let key: String
    let cap: Double
    let oneDirectional: Bool
    let reads: String
    var id: String { key }

    static let all: [PPFamily] = [
        .init(key: "trend", cap: 22, oneDirectional: false,
              reads: "Above the 50-day (±8), above the 200-day (±10), distance from the high (−6 to +8)."),
        .init(key: "catalyst", cap: 12, oneDirectional: true,
              reads: "Print inside 7 days adds 12, inside 21 days adds 10, inside 40 days adds 4."),
        .init(key: "stretch", cap: 12, oneDirectional: true,
              reads: "(σ from the 50-day − 1.5) × 5. One-directional: it can only take conviction away."),
        .init(key: "record", cap: 8, oneDirectional: false,
              reads: "(prints better than −8% ÷ n − 0.7) × 25. Needs at least 8 prints to say anything."),
        .init(key: "relative", cap: 6, oneDirectional: false,
              reads: "The gap against SMH × 0.6."),
        .init(key: "sector", cap: 6, oneDirectional: false,
              reads: "Sector health: SMH's own trend, so a name is not credited for its group's move."),
        .init(key: "grade", cap: 8, oneDirectional: false,
              reads: "(your grade − 5) × 2, decaying over 60 sessions."),
        .init(key: "macro", cap: 12, oneDirectional: false,
              reads: "Your dial. Nothing reads it for you."),
        .init(key: "peers", cap: 8, oneDirectional: false,
              reads: "Peer print outcomes — how the group's own prints landed."),
    ]
}

/// One disc's state on the day. `computed == false` means the slot exists and
/// the number does not — a dashed ring and an em dash, never a zero.
struct PPDisc: Identifiable {
    let family: PPFamily
    let today: Double
    let series: [Double]      // oldest first, today last
    let computed: Bool
    var id: String { family.key }

    var moved: Double { series.count >= 2 ? today - series[series.count - 2] : 0 }
    /// Colour depth is weight: 26% at nothing, 100% at the family's cap.
    var strength: Double { min(1, abs(today) / max(family.cap, 0.0001)) }
}

extension PPResponse {
    /// Builds the nine discs from today's parts plus whatever history exists.
    /// A family absent from the response is `computed: false`, not zero.
    func discs() -> [PPDisc] {
        let today = history?.today?.parts ?? plan?.convictionParts ?? [:]
        let series = history?.trail ?? []
        return PPFamily.all.map { fam in
            // The engine keys these cv.trend; the snapshot strips the prefix.
            let v = today[fam.key] ?? today["cv.\(fam.key)"]
            let hist: [Double] = series.compactMap { $0.parts?[fam.key] ?? $0.parts?["cv.\(fam.key)"] }
            return PPDisc(family: fam, today: v ?? 0,
                          series: hist.isEmpty ? [v ?? 0] : hist,
                          computed: v != nil)
        }
    }

    /// Biggest mover since the previous reading first — the disc you read first
    /// is the one that changed most. With no history nothing has moved, so this
    /// falls back to the declared order rather than shuffling arbitrarily.
    func discsOrdered() -> [PPDisc] {
        let d = discs()
        guard (history?.trail?.count ?? 0) >= 2 else { return d }
        return d.sorted { abs($0.moved) > abs($1.moved) }
    }

    /// "Stretch added 8, trend added 4." Names the two biggest movers, or says
    /// plainly that nothing moved — which on a one-day-old series is the truth.
    func moversLine() -> String {
        guard (history?.trail?.count ?? 0) >= 2 else {
            return "First reading. The trail fills in from here."
        }
        let movers = discs().filter { $0.moved != 0 }
            .sorted { abs($0.moved) > abs($1.moved) }.prefix(2)
        if movers.isEmpty { return "Nothing moved since the last reading." }
        let parts = movers.map { d -> String in
            "\(d.family.key) \(d.moved > 0 ? "added" : "took back") \(Int(abs(d.moved).rounded()))"
        }
        return parts.joined(separator: ", ").prefix(1).uppercased() + parts.joined(separator: ", ").dropFirst() + "."
    }
}
