//
//  NvdaPlannerPreview.swift
//  Sunnyfi — DEBUG-only visual harness for the rev-2 Planner.
//
//  Renders the stepped cards against a hand-built PlannerState (numbers from the
//  planner_final mockup + the rev2/addendum fixtures) so the layout can be
//  screenshotted without the edge function or a sign-in. Launch with `-inkPlanner`.
//

#if DEBUG
import SwiftUI

extension PlannerState {
    static var mock: PlannerState {
        let gate = PGate(spot: 206.84, iv: 40.3, ivPct: 55, pctFactor: 1.0, hv20: 46.2, hv30: 45, hv60: 41.8, hv90: 39.2,
            hvTrend: "expanding", hvGap: 5.8, score: 0.90, scorePass: true, earningsPass: true, capacityPass: true, blocked: false,
            daysToEarnings: 26, earnings: "Aug 26", wash: PWash(hit: true, on: "Jul 14", amount: 3120, daysLeft: 17), flags: [])
        let book = PBook(shares: 5001, buyAvg: 208.39, realizedPremium: 22300, netDelta: 1217, longTheta: 324,
            shortCallDelta: -270, shortCallCt: 38, longCallCt: 20, wall: 210, committedShares: 3800, freeShares: 1201, capacity: 50, basis: 203.93)
        let tech = PTech(high52: 243, low52: 130, ma50: 204.79, ma200: 200.82, rsi14: 41, ath: 243, athDate: "2026-01-07", updatedAt: nil)

        func rung(_ k: Double, _ prem: Double, _ assign: Double, _ edge: Double, _ edgePct: Double, _ hi: Double, _ lo: Double, _ delta: Double, _ side: String, _ adv: Double) -> PRung {
            let intr = max(0, 206.84 - k)
            return PRung(strike: k, prem: prem, fair: prem - edge / 100, sellable: prem >= 0.05,
                intrinsic: intr, ext: prem - intr, extPct: prem > 0 ? (prem - intr) / prem : 0,
                edge: edge, edgePct: edgePct, edgeHi: hi, edgeLo: lo, edgePctHi: hi / (prem * 100), edgePctLo: lo / (prem * 100), edgeCrosses: hi > 0 && lo < 0,
                assign: assign, delta: delta, effective: k + prem, vsBasis: k + prem - 203.93, side: side, advCost: adv, affected: adv > 0 ? 20 : 0)
        }
        let chain = [
            rung(200, 7.58, 0.82, -23, -0.03, 5, -29, 0.85, "adverse", 12000),
            rung(202.5, 5.65, 0.72, -29, -0.05, 7, -37, 0.72, "adverse", 9000),
            rung(205, 4.00, 0.60, -33, -0.08, 8, -43, 0.60, "adverse", 6000),
            rung(207.5, 2.68, 0.46, -34, -0.13, 8, -43, 0.48, "adverse", 3000),
            rung(210, 1.69, 0.33, -30, -0.17, 8, -40, 0.34, "matched", 0),
            rung(212.5, 1.05, 0.22, -25, -0.24, 6, -34, 0.23, "favorable", 0),
        ]
        func exp(_ iso: String, _ label: String, _ dow: String, _ td: Int, _ we: Int, _ vd: Double) -> PExpiry {
            PExpiry(key: iso, iso: iso, label: label, dow: dow, cal: td + we, td: td, we: we, volDays: vd, T: vd / 252, chain: chain)
        }
        return PlannerState(ok: true, asOf: nil, gate: gate, book: book, technicals: tech, refStrike: 207.5, weekendVol: 0.3,
            expiries: [exp("2026-07-29", "Jul 29", "Wed", 2, 0, 2.0), exp("2026-07-31", "Jul 31", "Fri", 4, 0, 4.0),
                       exp("2026-08-03", "Aug 3", "Mon", 5, 2, 5.6), exp("2026-08-05", "Aug 5", "Wed", 7, 2, 7.6)])
    }
}

struct InkPlannerPreview: View {
    @State private var planner: PlannerStore = {
        let p = PlannerStore()
        p.state = .mock
        p.isLoading = false
        p.ct = 12
        p.selExpiry = "2026-07-31"
        p.selStrike = 207.5
        p.legs = PlannerLegs(longCalls: [(strike: 210, ct: 20)], shortCalls: [], buyAvg: 208.39, realizedPremium: 22300, shares: 5001)
        return p
    }()

    var body: some View {
        NvdaPlannerScreenPreviewHost(planner: planner)
            .preferredColorScheme(.dark)
    }
}

/// Renders the same card stack as NvdaPlannerScreen but against the injected store.
private struct NvdaPlannerScreenPreviewHost: View {
    @Bindable var planner: PlannerStore
    var body: some View {
        ZStack {
            Ink.canvas.ignoresSafeArea()
            if let s = planner.state {
                let up = PlannerEngine.upside(s.technicals, spot: s.gate.spot, planner.settings)
                let levels = planner.legs.map { PlannerEngine.levels($0, spot: s.gate.spot, candidateExpiry: planner.selExpiryDate) } ?? []
                let pick = PlannerEngine.select(planner.selExpiryObj?.chain ?? [], planner.settings, s.book, ct: planner.ct,
                    targetStrike: up.targetStrike, upsideScore: up.score, blocked: s.gate.blocked, legs: planner.legs, levels: levels, spot: s.gate.spot)
                let legsE = planner.legs ?? PlannerLegs(longCalls: [], shortCalls: [], buyAvg: s.book.buyAvg, realizedPremium: s.book.realizedPremium, shares: s.book.shares)
                let ts = up.targetStrike
                let chain = planner.selExpiryObj?.chain ?? []
                let nearest = ts.flatMap { t in chain.min { abs($0.strike - t) < abs($1.strike - t) }?.strike }
                let d = PlannerDerived(spot: s.gate.spot, book: s.book, gate: s.gate, expiry: planner.selExpiryObj, upside: up, levels: levels,
                    pick: pick, ct: planner.ct, settings: planner.settings, histAssign: planner.histAssign, selStrike: planner.selStrike,
                    legsOrEmpty: legsE, isOnTarget: { k in nearest.map { abs($0 - k) < 1e-6 } ?? false })
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            ScoreCardV(d: d).id("c1"); GuardCardV(planner: planner, d: d).id("c2"); UpsideCardV(planner: planner, d: d).id("c3")
                            SizeCardV(planner: planner, d: d).id("c4"); ExpiryCardV(planner: planner, d: d).id("c5"); StrikeCardV(planner: planner, d: d).id("c6")
                            OutlookCardV(planner: planner, d: d).id("c7"); PlanCardV(d: d).id("c8")
                            Color.clear.frame(height: 40)
                        }.padding(16)
                    }
                    .onAppear {
                        let a = ProcessInfo.processInfo.arguments
                        let target = a.contains("-c3") ? "c3" : a.contains("-c5") ? "c5" : a.contains("-c6") ? "c6" : a.contains("-c7") ? "c7" : a.contains("-c8") ? "c8" : nil
                        if let target { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo(target, anchor: .top) } }
                    }
                }
            }
        }
    }
}
#endif
