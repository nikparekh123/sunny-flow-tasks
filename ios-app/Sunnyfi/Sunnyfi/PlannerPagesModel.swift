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
    /// The P&L already banked this year, which is what the all-in figure folds in.
    /// Pre-formatted by the engine off NvPerf.realized — the glossary's definition.
    var outcome: PPOutcome?
}

struct PPOutcome: Decodable { var realised: Double?; var realisedLabel: String? }

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
    var priceMove: Double?

    /// PRE / CLEAR / POST and down / flat / up are how the ENGINE reasons. Printed
    /// straight onto the card they read as "CLEAR. flat." — a debug line, not a
    /// sentence. Mapped here rather than in the view so both pages say it the same.
    var eventPhrase: String? {
        switch (event ?? "").uppercased() {
        case "PRE":   return "Into the print"
        case "CLEAR": return "A clear week"
        case "POST":  return "After the print"
        default:      return event
        }
    }
    var pricePhrase: String? {
        let move = priceMove.map { String(format: "%.1f%%", abs($0)) }
        switch (price ?? "").lowercased() {
        case "down": return move.map { "down \($0) from the high" } ?? "price is down"
        case "up":   return move.map { "up \($0)" } ?? "price is up"
        case "flat": return move.map { "\($0) off the high" } ?? "price is flat"
        default:     return price
        }
    }
    var why: String?
    var paidVsNormal: Double?
    var expiry: String?
    /// The weeks that can actually be written. The picker must offer these and
    /// nothing else — an expiry the engine will not price is not a choice.
    var expiryOptions: [String]?
    var expiryAsked: String?
    /// False when a requested expiry was rejected and the nearest used instead.
    /// The UI has to say so: silently showing the asked-for week would put a
    /// contract on screen that cannot be sold.
    var expiryHonoured: Bool?
    var expDays: Int?
    var expectedMove: Double?
    var picks: [PPPick]?
    /// The next two expiries, each fully priced. Not four, not "the first one past
    /// the print" — the two weeks that actually get written.
    var chains: [PPChain]?
    /// The whole answer, in two numbers. Everything else falls out of these once
    /// a week is chosen.
    var mechanism: PPMechanism?
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

/// How much exposure to keep, and how far out to sell it. Both numbers in both
/// units, because they are one decision counted two ways: delta is what the model
/// sizes on, shares is what actually gets called away.
struct PPMechanism: Decodable {
    /// What conviction asked for, against what the chain could deliver. They differ
    /// when the hedge floor binds, and that gap must stay visible.
    var keepPctTarget: Double?
    var keepPct: Double?
    var keepDelta: Double?
    var soldDelta: Double?
    var totalDelta: Double?
    var contracts: Int?
    var coveredShares: Double?
    var freeShares: Double?
    var otmPct: Double?
    /// True when the strike IS the money. The distance is a deliberate setting
    /// now, so the page states it rather than warning that it sits inside a sigma.
    var atTheMoney: Bool?
    var strike: Double?
    /// The distance measured in the move the market is pricing. Below 1.0 the
    /// strike sits INSIDE one sigma, which reads as safely out and is not.
    var sigmas: Double?
    var expectedMove: Double?
    var expiry: String?
    var expDays: Int?
}

/// One expiry, with its own event state, keep and three tiers. Two of these.
struct PPChain: Decodable {
    var expiry: String?
    var chip: String?
    var expCode: String?
    var expDays: Int?
    /// "print inside" or nil — what this week resolves to, which moves its sizing.
    var event: String?
    var note: String?
    var keepPct: Double?
    var size: PPSize?
    var picks: [PPPick]?
}

/// Above the strike, between, below. Every covered call has exactly these three.
struct PPWorld: Decodable { var when: String?; var then: String? }

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
    /// Assignment odds as a percent — the page states them, never recomputes them.
    var called: Int?
    var uncovered: Double?
    /// Pre-formatted so three figures that must agree cannot round apart.
    var label: String?
    /// Credit per calendar day. The only figure that makes two expiries comparable:
    /// totals flatter the longer week, rates do not.
    var creditPerDay: Double?
    var out: PPOut?
    var tier: String?
    var rec: Bool?
    /// What this tier DOES, in the server's words — it names figures, so it is not
    /// assembled in the app where it could contradict them.
    var stance: String?
    var worlds: [PPWorld]?
    /// "$1,034/day", pre-formatted. The number is also on creditPerDay.
    var creditPerDayLabel: String?

    var be: Double? { breakEven ?? breakeven }
}

/// The same outcome in three widening frames. Strings from the server.
/// `all` is nil when realised P&L was not sent — omitted, never guessed.
struct PPOut: Decodable {
    var opt: String?
    var stockOpt: String?
    var all: String?
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

/// What the floor is worth in the fall it was bought for. Hedged and unhedged are
/// stated separately on purpose: one netted number hides which half is which.
struct PPStress: Decodable {
    var to: Double?
    var dropPct: Double?
    var hedgedLabel: String?
    var unhedgedLabel: String?
    var savedLabel: String?
}

/// Three points and the frame. The line is DRAWN in the app, never derived — this
/// is the one chart whose shape could otherwise disagree with the figures beside it.
struct PPPayoffLine: Decodable {
    var lo: Double?
    var hi: Double?
    var floor: Double?
    var spot: Double?
    var points: [PPPayoffPoint]?
}
struct PPPayoffPoint: Decodable { var px: Double?; var pl: Double? }

struct PPFloor: Decodable {
    var floor: Double?
    /// Positive = spot sits ABOVE the floor, which is the normal case. Negative
    /// means price has come back through it, so the unit cannot read "under spot"
    /// in both directions.
    var gapPct: Double?
    /// The engine's sentence. The design's sample called this `head` and carried a
    /// short verdict; the engine writes the whole reason. Both accepted.
    var why: String?
    var head: String?
    var target: Double?
    var stale: Bool?
    // The sleeve: how much of the book is actually under the floor, and what it cost.
    var puts: Int?
    var covers: Double?
    var prem: Double?
    var days: Int?
    var expiry: String?
    var cost: Double?
    var costLabel: String?
    var breakeven: Double?
    var stress: PPStress?
    var payoff: PPPayoffLine?

    var gapLine: String? {
        guard let g = gapPct else { return nil }
        return String(format: "%.1f%% %@ spot", abs(g), g >= 0 ? "under" : "above")
    }
    /// A verdict in a few words, since the engine only supplies the long form.
    var verdict: String {
        if let h = head { return h }
        guard let g = gapPct else { return "No floor set" }
        if stale == true { return "The floor has drifted from spot" }
        if g < 0 { return "Price has come back through the floor" }
        return "The floor is doing its job"
    }
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
