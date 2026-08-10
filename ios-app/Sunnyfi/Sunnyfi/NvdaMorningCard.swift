//
//  NvdaMorningCard.swift
//  One card, prepped each morning, anchored to today.
//
//  Replaces the seven-section planner. The old screen showed the same quantity under
//  different scopes without ever naming the scope — "8 of 10 contracts" beside a pick
//  of 15, "3,194 called away" beside "1,500 shares sold" — which is what made it read
//  as contradictory when every number was individually right. Here each section owns
//  one scope and says so.
//
//  What matters / what won't come from the edge's OBSERVER, not from the score's top
//  contributors. Six domains, one line each. A line tagged `blind` is something the
//  number cannot see, which is the most useful thing on the card.
//

import SwiftUI

private func mcDec(_ v: Double, _ d: Int) -> String { String(format: "%.\(d)f", v) }

// MARK: - Card

struct NvdaMorningCard: View {
    let pv: PV2
    let spot: Double
    let shares: Double
    let buyAvg: Double
    let realized: Double          // closed P&L to date, options + shares
    var iv: Double? = nil
    var ticker: String = "NVDA"

    var body: some View {
        VStack(spacing: 0) {
            dateHead
            divider
            already
            divider
            scoreAndStory
            if let o = pv.observations {
                if !o.mattersList.isEmpty { divider; list("What matters this week", o.mattersList) }
                if !o.quietList.isEmpty { divider; list("What won't matter this week", o.quietList) }
            }
            // The floor is rolled FIRST, as its own decision, so it is read before the
            // sell decision rather than after it.
            if let f = pv.floorAdvice { divider; floor(f) }
            divider
            whatToSell
            divider
            pnl
        }
        .background(Ink.surface)
        .clipShape(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous))
    }

    // MARK: sections

    private var dateHead: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Self.today).font(InkFont.serif(26))
            Spacer()
            Text(mcDec(spot, 2)).font(InkFont.mono(12))
        }
        .foregroundStyle(Ink.text)
        .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 18)
    }

    private var already: some View {
        section("Where you already are") {
            let legs = pv.expiries?.filter { $0.loadCt > 0 }.prefix(2) ?? []
            if legs.isEmpty {
                Text("Nothing open. Everything below is a new position.")
                    .font(.system(size: 14.5)).foregroundStyle(Ink.text)
            } else {
                ForEach(Array(legs)) { e in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(e.loadCt) sold for \(e.label)").font(.system(size: 14.5))
                            // An expiry with no sessions left is not a position to close,
                            // it is one to let go. Saying "pay $733" on the morning it
                            // expires worthless is the card being wrong out loud.
                            Text(e.td <= 0 ? "EXPIRES TODAY" : "\(e.td) SESSION\(e.td == 1 ? "" : "S") LEFT")
                                .font(InkFont.mono(10)).tracking(10 * 0.1).foregroundStyle(Ink.dim)
                        }
                        Spacer(minLength: 8)
                        Text(e.td <= 0 ? "let it expire" : "\(e.rollable ?? e.loadCt) rollable")
                            .font(InkFont.mono(14)).foregroundStyle(Ink.text)
                    }
                    .padding(.top, e.id == legs.first?.id ? 0 : 10)
                }
            }
        }
    }

    /// Conviction is a view on the STOCK. Keep is what follows from it plus the event
    /// state. They are shown apart so a disagreement can be about one and not the other.
    private var scoreAndStory: some View {
        section("Where this sits") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 26) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Int(pv.plan?.conviction ?? 0))")
                            .font(InkFont.mono(38, .medium)).tracking(38 * -0.04)
                        Text("CONVICTION").font(InkFont.mono(9)).tracking(9 * 0.17).foregroundStyle(Ink.dim)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(paidLabel).font(InkFont.mono(38, .medium)).tracking(38 * -0.04)
                        Text("PAID VS NORMAL").font(InkFont.mono(9)).tracking(9 * 0.17).foregroundStyle(Ink.dim)
                    }
                    Spacer(minLength: 0)
                }
                if let p = pv.plan {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("KEEP \(Int(p.keepPct ?? 0))% · \(Int(p.keepDelta ?? 0).formatted()) OF \(Int(shares).formatted()) DELTA")
                            .font(InkFont.mono(11)).tracking(11 * 0.12)
                        Text("\((p.event ?? "").replacingOccurrences(of: "CLEAR", with: "CLEAR WEEK")) · \((p.price ?? "").uppercased())")
                            .font(InkFont.mono(10)).tracking(10 * 0.13).foregroundStyle(Ink.dim)
                        if let why = pv.regime?.why {
                            Text(why).font(.system(size: 14.5)).padding(.top, 2)
                        }
                        // How far the tool moved you from your own default, and which part
                        // was instruments versus your own read. The audit line.
                        Text("BASELINE \(Int(p.baseline ?? 0)) · CONVICTION MOVED IT \(moved)")
                            .font(InkFont.mono(9)).tracking(9 * 0.15).foregroundStyle(Ink.dim).padding(.top, 4)
                    }
                }
            }
            .foregroundStyle(Ink.text)
        }
    }

    private var paidLabel: String {
        guard let m = pv.ivMedian, m > 0, let now = iv else { return "—" }
        let x = (now / m - 1) * 100
        return "\(x >= 0 ? "+" : "")\(mcDec(x, 0))%"
    }
    private var moved: String {
        guard let p = pv.plan, let k = p.keepPct, let b = p.baseline else { return "—" }
        let d = k - b
        return "\(d >= 0 ? "+" : "")\(mcDec(d, 0))"
    }

    private func list(_ title: String, _ lines: [PV2.Obs.Line]) -> some View {
        section(title) {
            VStack(alignment: .leading, spacing: 11) {
                ForEach(lines) { l in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(Ink.text).frame(width: 5, height: 5).padding(.top, 7)
                        VStack(alignment: .leading, spacing: 4) {
                            (Text(l.tag + " ").font(InkFont.mono(12.5)) + Text(l.text).font(.system(size: 14.5)))
                                .foregroundStyle(Ink.text)
                            // Only `blind` earns a line. "The score prices this" is noise;
                            // "the score cannot see this" is the warning worth printing.
                            if l.isBlind {
                                Text("THE SCORE DOES NOT SEE THIS")
                                    .font(InkFont.mono(9)).tracking(9 * 0.15).foregroundStyle(Ink.delayed)
                            }
                        }
                    }
                }
            }
        }
    }

    private var whatToSell: some View {
        let picks = pv.plan?.pickList ?? []
        return VStack(alignment: .leading, spacing: 0) {
            eyebrow("What to sell", right: expiryLabel).foregroundStyle(Ink.invertText)
            if picks.isEmpty {
                Text("Nothing worth selling").font(InkFont.mono(20)).foregroundStyle(Ink.invertText)
                Text("Nothing on the board pays for the hedge.")
                    .font(.system(size: 14.5)).foregroundStyle(Ink.invertText).padding(.top, 10)
            } else {
                ForEach(Array(picks.enumerated()), id: \.element.id) { i, c in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(i + 1)").font(InkFont.mono(12)).frame(width: 14, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(Int(c.ct ?? 0)) at \(mcDec(c.strike ?? 0, 2))").font(InkFont.mono(17))
                            // Delta KEPT, not just delta sold. Without it the three picks are
                            // not comparable and this is only a list of prices.
                            Text("\(mcDec(c.otmPct ?? 0, 2))% OUT · \(Int(c.delta ?? 0))\u{0394} · KEPT \(Int(c.keptPct ?? 0))%")
                                .font(InkFont.mono(10)).tracking(10 * 0.09).foregroundStyle(Ink.invertDim)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(inkUsd(c.income ?? 0)).font(InkFont.mono(17))
                            Text("\(Int((c.assign ?? 0) * 100))% CALLED")
                                .font(InkFont.mono(9)).tracking(9 * 0.14).foregroundStyle(Ink.invertDim)
                        }
                    }
                    .foregroundStyle(Ink.invertText)
                    .padding(.vertical, 11)
                    .overlay(alignment: .top) {
                        if i > 0 { Rectangle().fill(Ink.invertText.opacity(0.14)).frame(height: 1) }
                    }
                }
                // When the hedge floor binds you do not get the keep conviction asked for.
                // Saying both numbers is the point; hiding the gap is the failure this
                // whole rebuild removed.
                if let top = picks.first, top.binds {
                    Text("Conviction wants \(Int(top.wantCt ?? 0)). The hedge needs \(Int(top.minCt ?? 0)) to pay for itself.")
                        .font(.system(size: 13.5)).foregroundStyle(Ink.invertText)
                        .padding(.top, 12)
                } else if let h = pv.plan?.hedge, let needs = h.needs, needs > 0,
                          let cov = picks.first?.covers {
                    Text("Covers the \(inkUsd(needs)) hedge \(mcDec(cov, 1))x")
                        .font(InkFont.mono(10)).tracking(10 * 0.1)
                        .foregroundStyle(Ink.invertDim).padding(.top, 12)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.text)
    }

    private var expiryLabel: String? {
        guard let p = pv.plan, let e = p.expiry else { return nil }
        let sig = p.expectedMove.map { " · ±\(mcDec($0, 2))" } ?? ""
        return "\(e.suffix(5)) · \(Int(p.expDays ?? 0))d\(sig)"
    }

    private func floor(_ f: PV2.FloorAdvice) -> some View {
        section("Put floor") {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(f.stale ? "The floor has fallen behind" : "The floor is holding")
                        .font(.system(size: 14.5))
                    Text("\(mcDec(f.gapPct, 1))% UNDER SPOT").font(InkFont.mono(10)).tracking(10 * 0.1)
                        .foregroundStyle(Ink.dim)
                }
                Spacer(minLength: 8)
                Text(f.stale ? "roll to \(mcDec(f.target, 0))" : "no change")
                    .font(InkFont.mono(14))
            }
            .foregroundStyle(Ink.text)
        }
    }

    private var pnl: some View {
        // Share profit measures against the BUY AVERAGE, never oldest-lot cost, so the
        // planner and the position screen can never disagree.
        let top = pv.plan?.pickList.first
        let options = top?.income ?? 0
        let called = min((top?.ct ?? 0) * 100, shares)
        let withStock = options + (top.map { (($0.strike ?? 0) - buyAvg) * called } ?? 0)
        return section("If this goes through") {
            VStack(spacing: 0) {
                ledger("Options", "What you collect", options, first: true)
                ledger("With the stock",
                       top.map { "If called at \(mcDec($0.strike ?? 0, 0)), against \(mcDec(buyAvg, 2))" } ?? "-",
                       withStock)
                ledger("All in", "After the \(inkUsd(realized)) already realised", withStock + realized)
            }
        }
    }

    // MARK: pieces

    private func ledger(_ k: String, _ sub: String, _ v: Double, first: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(k).font(.system(size: 14.5))
                Text(sub.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.11).foregroundStyle(Ink.dim)
            }
            Spacer(minLength: 8)
            Text(inkUsd(v)).font(InkFont.mono(20)).foregroundStyle(v >= 0 ? Ink.gain : Ink.loss)
        }
        .foregroundStyle(Ink.text)
        .padding(.top, first ? 2 : 13)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(Ink.hair).frame(height: 1) }
        }
    }

    private func eyebrow(_ t: String, right: String? = nil) -> some View {
        HStack {
            Text(t.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.17)
            Spacer()
            if let right { Text(right.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.17) }
        }
        .padding(.bottom, 12)
    }

    private func section<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow(t).foregroundStyle(Ink.dim)
            c()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.vertical, 20)
    }

    private var divider: some View { Rectangle().fill(Ink.hair).frame(height: 1) }

    private static var today: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, d MMM"; return f.string(from: Date())
    }
}

// MARK: - Screen

struct NvdaMorningCardScreen: View {
    let store: NvdaStore
    var ticker: String = "NVDA"
    var onBack: () -> Void = {}
    @State private var plan = PlanV2Store()

    var body: some View {
        VStack(spacing: 0) {
        HStack(spacing: 14) {
            Button(action: onBack) {
                Image(systemName: "arrow.left").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Ink.text).frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Ink.hair, lineWidth: 1))
            }
            Text("Plan the next sale").font(InkFont.serif(25))
            Spacer()
            Text(ticker).font(InkFont.mono(11)).tracking(11 * 0.16)
        }
        .foregroundStyle(Ink.text)
        .padding(.horizontal, 16).padding(.vertical, 14)
        Rectangle().fill(Ink.hair).frame(height: 1)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let pv = plan.state, pv.ok {
                    NvdaMorningCard(
                        pv: pv,
                        spot: store.position?.spot ?? 0,
                        shares: store.position?.shares ?? 0,
                        buyAvg: store.position?.avgBuy ?? 0,
                        realized: store.pnl?.realized ?? 0,
                        iv: store.insights?.vol.iv,
                        ticker: ticker)
                    if let silent = pv.observations?.silentList, !silent.isEmpty {
                        // Naming what the card does not know beats quietly not having it.
                        Text("NOT YET WIRED · \(silent.joined(separator: " · ").uppercased())")
                            .font(InkFont.mono(9)).tracking(9 * 0.15)
                            .foregroundStyle(Ink.dim).padding(.horizontal, 4)
                    }
                } else if plan.isLoading {
                    Text("Preparing today's card").font(InkFont.mono(12)).foregroundStyle(Ink.dim)
                } else {
                    Text(plan.lastError ?? "No plan").font(InkFont.mono(12)).foregroundStyle(Ink.loss)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 18)
        }
        }
        .background(Ink.canvas.ignoresSafeArea())
        .task { await plan.load(from: store, ticker: ticker) }
    }
}
