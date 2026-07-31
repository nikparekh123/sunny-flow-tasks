//
//  NvdaPlannerPreview.swift
//  Sunnyfi — DEBUG-only visual harness for the Planner.
//
//  Renders the Planner sections against a hand-built PlannerState (numbers taken
//  from the Claude Design mockup screens) so the layout can be screenshotted
//  without the edge function or a sign-in. Launch with `-inkPlanner`.
//

#if DEBUG
import SwiftUI

extension PlannerState {
    static var mock: PlannerState {
        let gate = PGate(
            spot: 206.84, iv: 40.3, ivPct: 19, pctFactor: 0.8,
            hv20: 46.2, hv30: 45, hv60: 41.8, hv90: 39.2,
            hvTrend: "expanding", hvGap: 5.8, score: 0.72,
            scorePass: false, earningsPass: true, capacityPass: true, blocked: true,
            daysToEarnings: 27, earnings: "Aug 23",
            wash: PWash(hit: true, on: "Jul 14", amount: 3120, daysLeft: 17),
            flags: [
                PFlag(key: "score", level: "block", head: "Skip this cycle",
                      body: "Options underpriced against realized. Seller Score 0.72, implied 40.3% sits under 45% realized, and IV percentile 19 discounts it further."),
                PFlag(key: "wash", level: "note", head: "Wash-sale window open",
                      body: "Loss of $3,120 realized Jul 14, 17 days left. Assignment at a loss plus a next-day rebuy disallows it and rolls it into new basis."),
            ])
        let book = PBook(
            shares: 5001, buyAvg: 208.39, realizedPremium: 22300, netDelta: 1217, longTheta: 324,
            shortCallDelta: -270, shortCallCt: 38, longCallCt: 20, wall: 210,
            committedShares: 3800, freeShares: 1201, capacity: 12, basis: 203.93)

        func exp(_ key: String, _ label: String, _ dow: String, _ cal: Int, _ td: Int, _ we: Int, _ vd: Double,
                 _ prem: Double, _ assign: Double, _ edge: Double) -> PExpiry {
            PExpiry(key: key, iso: key, label: label, dow: dow, cal: cal, td: td, we: we, volDays: vd,
                    T: vd / 252, prem: prem, perDay: prem / Double(max(td, 1)), credit: prem * 100 * 12, assign: assign, edge: edge)
        }
        let expiries = [
            exp("2026-07-29", "Jul 29", "Wed", 2, 2, 0, 2.0, 2.68, 0.46, -34),
            exp("2026-07-31", "Jul 31", "Fri", 4, 4, 0, 4.0, 3.79, 0.47, -41),
            exp("2026-08-03", "Aug 3", "Mon", 7, 5, 2, 5.6, 4.52, 0.47, -52),
            exp("2026-08-05", "Aug 5", "Wed", 9, 7, 2, 7.6, 5.28, 0.48, -60),
        ]

        func rung(_ k: Double, _ prem: Double, _ assign: Double, _ edge: Double, _ edgePct: Double,
                  _ hi: Double, _ lo: Double, _ nda: Double, _ vsB: Double, _ side: String, _ adv: Double, _ sell: Bool) -> PRung {
            PRung(strike: k, prem: prem, fair: prem - edge / 100, sellable: sell,
                  edge: edge, edgePct: edgePct, edgeHi: hi, edgeLo: lo,
                  edgePctHi: hi / (prem * 100), edgePctLo: lo / (prem * 100), edgeCrosses: hi > 0 && lo < 0,
                  assign: assign, delta: assign + 0.03, netDeltaAfter: nda, pctLong: nda / 5001,
                  effective: k + prem, vsBasis: vsB, side: side, advCost: adv, affected: adv > 0 ? 12 : 0)
        }
        let chain = [
            rung(200, 7.58, 0.82, -23, -0.03, 5, -29, 1892, 1.54, "adverse", 12000, true),
            rung(202.5, 5.65, 0.72, -29, -0.05, 7, -37, 2013, 2.11, "adverse", 9000, true),
            rung(205, 4.00, 0.60, -33, -0.08, 8, -43, 2140, 2.57, "adverse", 6000, true),
            rung(207.5, 2.68, 0.46, -34, -0.13, 8, -43, 2320, 3.24, "adverse", 3000, true),
            rung(210, 1.72, 0.33, -30, -0.17, 8, -40, 2450, 4.31, "matched", 0, true),
            rung(212.5, 1.05, 0.22, -25, -0.24, 6, -34, 2560, 5.28, "favorable", 0, true),
            rung(215, 0.61, 0.13, -19, -0.31, 5, -27, 2650, 6.19, "favorable", 0, true),
            rung(220, 0.18, 0.04, 8, 0.44, 19, 4, 2790, 8.30, "favorable", 0, true),
            rung(227.5, 0.01, 0.00, -2, -1.0, 0, -3, 2886, 21.47, "favorable", 0, false),
        ]
        let signals = chain.map { r in
            PSignalSet(strike: r.strike, signals: [
                PSignal(k: "gate", ok: false, label: "Gate"),
                PSignal(k: "edge", ok: r.edge > 0, label: "Edge at HV30"),
                PSignal(k: "span", ok: r.edgeHi > 0 && r.edgeLo > 0, label: "Edge across lookbacks"),
                PSignal(k: "pair", ok: r.advCost == 0, label: "Long-call pairing"),
                PSignal(k: "assign", ok: r.assign <= 0.375, label: "Assignment vs your rate"),
                PSignal(k: "delta", ok: r.netDeltaAfter >= 500, label: "Net delta after"),
            ])
        }
        let rec = PRec(none: false, strike: 207.5, blocked: true,
                       why: "Lowest strike the guardrails allow, so the most premium they allow. 46% assign, −13% of premium in edge, +2,320 delta left on the book.")

        let steps: [Double] = [-5, -3, -2, -1, -0.5, 0, 0.5, 1, 2, 3, 5]
        let scenSteps = steps.map { p -> PScenStep in
            let s = 206.84 * (1 + p / 100)
            let opt = p == 0 ? 0.0 : max(0, s - 207.5)
            let shortPl = (2.68 - opt) * 100 * 12
            let sharePl = (s - 206.84) * 5001
            return PScenStep(p: p, s: s, ivUsed: max(8, 40.3 + (p < 0 ? abs(p) * 1.05 : p * -0.62)),
                             opt: opt, shortPl: shortPl.rounded(), sharePl: sharePl.rounded(), combined: (sharePl + shortPl).rounded())
        }
        let top = scenSteps.last!
        let scenario = PScenario(
            conv: "expiry", ivSource: "nvda",
            source: PIvSource(label: "NVDA · 2y regression", down: 1.05, up: -0.62, note: "504 sessions, R² 0.61"),
            T2: 0, steps: scenSteps, givenUp: top.sharePl - top.combined, topPct: 5)

        return PlannerState(
            ok: true, asOf: nil, gate: gate, book: book, settings: .default, refStrike: 207.5,
            expiries: expiries, selExpiry: "2026-07-29", chain: chain, signals: signals,
            recommendation: rec, selStrike: 207.5, scenario: scenario)
    }
}

struct InkPlannerPreview: View {
    @State private var planner: PlannerStore = {
        let p = PlannerStore()
        p.state = .mock
        p.isLoading = false
        return p
    }()

    private var anchor: String? {
        let a = ProcessInfo.processInfo.arguments
        if a.contains("-sec2") { return "expiry" }
        if a.contains("-sec3") { return "ladder" }
        if a.contains("-sec4") { return "scenario" }
        if a.contains("-sec5") { return "calibration" }
        return nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Ink.canvas.ignoresSafeArea()
            if let s = planner.state {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            GateSectionView(s: s).id("gate")
                            GuardrailsView(planner: planner)
                            ExpirySectionView(planner: planner, s: s).id("expiry")
                            LadderSectionView(planner: planner, s: s).id("ladder")
                            ScenarioSectionView(planner: planner, s: s).id("scenario")
                            CalibrationSectionView(log: planner.log).id("calibration")
                            Color.clear.frame(height: 300)
                        }
                        .padding(.horizontal, 16)
                    }
                    .onAppear { if let anchor { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo(anchor, anchor: .top) } } }
                }
                if !ProcessInfo.processInfo.arguments.contains("-noCommit") {
                    CommitBarView(planner: planner, s: s)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
