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
    var ticker: String = "NVDA"

    private var picks: [PV2.Cell] {
        // Top three across the two nearest expiries. `fit` is strike-varying, so it is
        // the right ranking here; the week score sizes the trade, it does not choose.
        let pool = pv.expiries?.prefix(2).flatMap(\.cells) ?? []
        return Array(pool.filter { ($0.blocks ?? []).isEmpty }
            .sorted { ($0.fit ?? 0) > ($1.fit ?? 0) }
            .prefix(3))
    }

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
            divider
            whatToSell
            if let f = pv.floorAdvice { divider; floor(f) }
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

    private var scoreAndStory: some View {
        section("Score and story") {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(pv.week?.score ?? 0)")
                        .font(InkFont.mono(42, .medium)).tracking(42 * -0.04)
                    Text("OF 100").font(InkFont.mono(9)).tracking(9 * 0.17).foregroundStyle(Ink.dim)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(pv.regime?.name ?? "").font(InkFont.mono(15)).tracking(15 * 0.04)
                    if let r = pv.regime {
                        Text("KEEP \(Int(r.keepDelta ?? 0).formatted()) SHARES OF UPSIDE · \(r.keepPct)%")
                            .font(InkFont.mono(10)).tracking(10 * 0.13).foregroundStyle(Ink.dim)
                    }
                    if let why = pv.regime?.why {
                        Text(why).font(.system(size: 14.5)).padding(.top, 4)
                    }
                }
            }
            .foregroundStyle(Ink.text)
        }
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
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("What to sell", right: picks.isEmpty ? nil : "\(picks.count) picks")
                .foregroundStyle(Ink.invertText)
            if picks.isEmpty {
                // A card that always produces an order becomes a treadmill that writes
                // calls in weeks that do not pay for the floor. Declining is an answer.
                Text("Nothing worth selling").font(InkFont.mono(20)).foregroundStyle(Ink.invertText)
                Text("Every strike on the board is blocked or fails to cover the floor's carry.")
                    .font(.system(size: 14.5)).foregroundStyle(Ink.invertText).padding(.top, 10)
            } else {
                ForEach(Array(picks.enumerated()), id: \.element.id) { i, c in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(i + 1)").font(InkFont.mono(12)).frame(width: 14, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("sell \(c.suggestCt ?? 0) at \(mcDec(c.strike, c.strike == c.strike.rounded() ? 0 : 1))")
                                .font(InkFont.mono(17))
                            Text("\(Int((c.delta * 100).rounded()))\u{0394} · \(Int((c.assign * 100).rounded()))% CALLED")
                                .font(InkFont.mono(10)).tracking(10 * 0.09).foregroundStyle(Ink.invertDim)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(inkUsd(c.income ?? (c.prem * 100 * Double(c.suggestCt ?? 0))))
                                .font(InkFont.mono(17))
                            Text("INCOME").font(InkFont.mono(9)).tracking(9 * 0.14).foregroundStyle(Ink.invertDim)
                        }
                    }
                    .foregroundStyle(Ink.invertText)
                    .padding(.vertical, 11)
                    .overlay(alignment: .top) {
                        if i > 0 { Rectangle().fill(Ink.invertText.opacity(0.14)).frame(height: 1) }
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.text)
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
        // Three numbers, in the order they compound. Share profit measures against the
        // BUY AVERAGE, not oldest-lot cost — the planner and the position screen have to
        // agree or the card starts arguing with itself.
        let top = picks.first
        let ct = Double(top?.suggestCt ?? 0)
        let options = top?.income ?? 0
        let called = min(ct * 100, shares)
        let withStock = options + (top.map { ($0.strike - buyAvg) * called } ?? 0)
        return section("If this goes through") {
            VStack(spacing: 0) {
                ledger("Options", "What you collect", options, first: true)
                ledger("With the stock", top.map { "If called at \(mcDec($0.strike, 0)), against \(mcDec(buyAvg, 2))" } ?? "-", withStock)
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
