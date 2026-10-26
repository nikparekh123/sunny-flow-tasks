//
//  GammaSections.swift
//  Sunny
//
//  Block 13h · the Gamma page's cards under the ladder. The words are fixed rules over the numbers the server
//  sends (Nik, 25 Oct 2026: rules decide the facts; a model may phrase them later, checked against them).
//

import SwiftUI
import Charts

// MARK: - The read: a headline, two sentences, and this week's drift

struct GammaRead: View {
    let t: String
    let v: GammaView
    let hist: [(String, GammaView)]

    var body: some View {
        let c1 = v.walls.first { $0.call && $0.rank == 1 }
        let below = v.walls.filter { !$0.call }.sorted { $0.k > $1.k }
        let p = below.first
        SCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(headline(c1, p)).sType(SType(size: 22, weight: 800, line: 28, tracking: -0.01), tabular: false)
                    .foregroundStyle(S.ink).fixedSize(horizontal: false, vertical: true)
                Text(body1(c1, p, below)).sType(SType(size: 15, weight: 400, line: 22, tracking: 0))
                    .foregroundStyle(S.ink).fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(S.pRule).frame(height: 1).padding(.vertical, 4)
                Text("This week").sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Text(drift()).sType(SType(size: 15, weight: 400, line: 22, tracking: 0)).foregroundStyle(S.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let d = v.drift {
                    Text("Wall center \(d.pct < 0 ? "down" : "up") \(String(format: "%.1f", abs(d.pct)))% in 5 days. More than 1% \(d.pct < 0 ? "down counts as drifting lower" : "up counts as drifting higher").")
                        .sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func headline(_ c: GWall?, _ p: GWall?) -> String {
        guard let c else { return p.map { "\(GammaText.label($0.label)) at \(PF.strike($0.k)) under the price" } ?? "No clear walls" }
        switch c.label {
        case "ceiling": return p.map { "Boxed between \(PF.strike($0.k)) and \(PF.strike(c.k))" + (v.expiries.count > 1 ? " this week" : "") } ?? "Capped at \(PF.strike(c.k))"
        case "accelerator": return "Upside can run past \(PF.strike(c.k))"
        default: return "No clear ceiling" + (p.map { ", \(GammaText.label($0.label).lowercased()) at \(PF.strike($0.k))" } ?? "")
        }
    }

    private func body1(_ c: GWall?, _ p: GWall?, _ below: [GWall]) -> String {
        var s: [String] = []
        if let c {
            switch c.label {
            case "ceiling": s.append("\(PF.strike(c.k)) is the strongest Ceiling, so rallies should stall there.")
            case "accelerator": s.append("Dealers are short gamma at \(PF.strike(c.k)), so a rally can speed up through it.")
            default: s.append("The tape gives no clear read at \(PF.strike(c.k)).")
            }
        }
        if let f = v.flip {
            var x = "Price sits \(GammaText.vs(v.spot, f)) the flip"
            let accels = below.filter { $0.label == "accelerator" }
            if let p, p.label == "floor" { x += ", and \(PF.strike(p.k)) is a Floor, so drops should slow there." }
            else if !accels.isEmpty, accels.count == below.count, let p {
                x += ", and the put walls below are Accelerators, so a slip under \(PF.price(min(f, v.spot))) can speed up toward \(PF.strike(p.k))."
            } else if let p, p.label == "accelerator" { x += ", and \(PF.strike(p.k)) is an Accelerator, so a drop can speed up there." }
            else { x += "." }
            s.append(x)
        }
        return s.joined(separator: " ")
    }

    private func drift() -> String {
        guard let old = v.week, !old.isEmpty else { return "Not enough history yet: the week's drift starts once five sessions are read." }
        var moves: [String] = []
        for side in ["call", "put"] {
            guard let n = v.walls.first(where: { $0.side == side && $0.rank == 1 }), let o = old.first(where: { $0.side == side && $0.rank == 1 }),
                  abs(n.k - o.k) > 1e-6 else { continue }
            moves.append("the 1st \(side) wall \(n.k < o.k ? "slipped" : "rose") from \(PF.strike(o.k)) to \(PF.strike(n.k))")
        }
        let dir = (v.drift?.pct ?? 0) > 1 ? "Walls are moving up." : (v.drift?.pct ?? 0) < -1 ? "Walls are moving down." : "Walls are steady."
        return moves.isEmpty ? dir + " The 1st walls are where they were a week ago." : dir + " " + moves.joined(separator: " and ").capitalizedFirst + "."
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - This week's plan: the sale, the gates, the action, ATM or split

struct GammaPlanCard: View {
    let t: String
    let p: NamePlan
    let v: GammaView?
    let earnings: String?

    var body: some View {
        let atm = p.sell.ways.first { $0.id == "atm" }
        let k = atm?.legs.first?.k ?? p.sell.wall?.k
        SCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("This week's plan").sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Spacer()
                    Text("Calls, \(PF.monthDay(p.week))").sType(SType(size: 12, weight: 600, line: 12, tracking: 0), tabular: false)
                        .foregroundStyle(S.ink).padding(.horizontal, 8).frame(height: 24).background(Capsule().fill(S.track))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(saleLine(k)).sType(SType(size: 17, weight: 700, line: 22, tracking: 0)).foregroundStyle(S.ink)
                    if let k, let spot = v?.spot, p.earnings != true {
                        Text(wallWords(k) + "\(GammaText.vs(k, spot)) price, 1:1 against your LEAPS")
                            .sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(S.surface))
                Text("Same playbook on every name: deep ITM LEAPS, weekly calls sold at the money, and hedges at the hedge expiry's 1st walls. The walls decide how big the hedge must be, not where you sell.")
                    .sType(SType(size: 15, weight: 400, line: 22, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Gates").sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                ForEach(gates(k), id: \.1) { g in
                    // A hard-to-read day only caps the walls' confidence (Nik, 26 Oct 2026): a note, not a failed gate.
                    let note = g.1.hasPrefix("Hard-to-read day")
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(note ? "Note" : g.0 ? "Pass" : "Fail").sType(SType(size: 12, weight: 700, line: 12, tracking: 0), tabular: false)
                            .foregroundStyle(note ? S.muted : g.0 ? S.blue : S.orangeDeep)
                            .frame(width: 40, height: 22).background(Capsule().fill(note ? S.track : (g.0 ? S.blue : S.orange).opacity(0.14)))
                        Text(g.1).sType(SType(size: 15, weight: 400, line: 20, tracking: 0)).foregroundStyle(S.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(action(k)).sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false)
                    .foregroundStyle(S.ink)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(S.orange.opacity(0.18)))
                if let verdict = atmOrSplit() {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ATM or split?").sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                        Text(verdict).sType(SType(size: 15, weight: 400, line: 22, tracking: 0)).foregroundStyle(S.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func saleLine(_ k: Double?) -> String {
        if p.earnings == true { return "No weeklies this week · earnings" }
        if p.sell.left == 0, let k { return "Sold \(p.sell.sold) of the \(PF.strike(k)) call" + (p.sell.sold == 1 ? "" : "s") }
        if p.sell.left == 0 { return "Sold \(p.sell.sold) of \(p.sell.n) calls" }
        return "Sell \(p.sell.left) \(PF.monthDay(p.week)) calls" + (k.map { " at \(PF.strike($0))" } ?? "")
    }
    private func wallWords(_ k: Double) -> String {
        guard let w = v?.walls.first(where: { abs($0.k - k) < 1e-6 }) else { return "" }
        return "\(w.rank == 1 ? "1st" : w.rank == 2 ? "2nd" : "3rd") \(w.side) wall · \(GammaText.label(w.label)), "
    }

    /// Pass or fail, in plain words. None of them stops the call sale (Nik, 25 Oct 2026): a failed wall gate
    /// raises the hedge target, the earnings gate skips the week.
    private func gates(_ k: Double?) -> [(Bool, String)] {
        var g: [(Bool, String)] = []
        if let a = p.sell.accel {
            g.append((false, "An Accelerator at \(PF.strike(a.k)) sits within a weekly SD above, so the hedge target rises to 2 SD."))
        } else if let w = p.sell.wall, w.label == "ceiling" {
            g.append((true, "The \(PF.strike(w.k)) Ceiling sits at your strike, so the calls go out full size."))
        } else if let k {
            g.append((true, "No Accelerator just above \(PF.strike(k)), so the calls go out full size."))
        }
        if let f = v?.flip ?? p.flip, let spot = v?.spot {
            let calm = (v?.regime ?? p.regime) == "calmer"
            g.append((calm, calm ? "Price is \(GammaText.vs(spot, f)) the flip, in the calmer zone."
                                 : "Price is \(GammaText.vs(spot, f)) the flip, in the amplified zone: moves can run."))
        }
        g.append((p.earnings != true, p.earnings == true ? "Earnings week: no weeklies." : "Not earnings week" + (earnings.map { " (earnings \(PF.monthDay($0)))" } ?? "")))
        if let c = v?.coverage ?? p.coverage {
            g.append((c >= 0.5, c >= 0.5 ? "Tape coverage above 50% (\(Int((c * 100).rounded()))%)"
                                         : "Hard-to-read day: tape coverage \(Int((c * 100).rounded()))%, so no wall shows more than medium confidence"))
        }
        if let h = p.hedge, let px = h.target.px {
            g.append((h.add == 0, h.add == 0 ? "Delta stays positive through +\(F.trim(h.target.sd)) SD (\(PF.price(px)))"
                                             : "Delta goes negative before +\(F.trim(h.target.sd)) SD (\(PF.price(px))) without \(PWords.n(h.add, "more hedge call"))"))
        }
        return g
    }

    private func action(_ k: Double?) -> String {
        if p.earnings == true { return "No weeklies this week. Keep the hedge." }
        let add = p.hedge?.add ?? 0
        if p.sell.left > 0, let k { return "Sell \(p.sell.left) at \(PF.strike(k))" + (add > 0 ? ", then add \(add) hedge calls." : ".") }
        return add > 0 ? "Calls are sold. Top up the hedge." : "Calls are sold. The hedge covers the week."
    }

    /// ATM against the best other way: its extra weekly premium against the extra hedge calls it needs, once.
    private func atmOrSplit() -> String? {
        guard let atm = p.sell.ways.first(where: { $0.id == "atm" }), let alt = p.sell.ways.filter({ $0.id != "atm" }).max(by: { $0.premium < $1.premium }),
              let h = p.hedge else { return nil }
        let more = atm.premium - alt.premium, extra = max(0, (atm.hedge ?? 0) - (alt.hedge ?? 0)), once = Double(extra) * h.mid * 100
        let name = alt.id == "split" ? "a split" : "slightly OTM"
        if extra == 0 { return "ATM pays \(PF.usd(more)) more a week than \(name) and needs no extra hedge, so ATM." }
        return more > once
            ? "ATM pays \(PF.usd(more)) more a week than \(name) for \(PWords.n(extra, "extra hedge call")) (about \(PF.usd(once)) once), so ATM."
            : "\(name.capitalizedFirst) gives up \(PF.usd(more)) a week but saves \(PWords.n(extra, "hedge call")) (about \(PF.usd(once)) once), so \(name)."
    }
}

// MARK: - Hedges: calls at the 1st call wall, puts at the 1st put wall, net delta across prices

struct GammaHedges: View {
    let t: String
    let p: NamePlan
    let spot: Double
    let dg: DGBook?
    let earnings: String?

    var body: some View {
        SCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Hedges" + ((p.hedge?.exp ?? p.insurance?.exp).map { ", \(PF.monthDay($0))" } ?? ""))
                    .sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                if let h = p.hedge {
                    Text("Strikes come from the \(PF.monthDay(h.exp)) walls, the same expiry as the hedges. Rule: stay delta positive from today's price up to +\(F.trim(h.target.sd)) weekly SD" + (h.target.px.map { " (\(PF.price($0)))" } ?? "") + ", as of Thursday's close.")
                        .sType(SType(size: 15, weight: 400, line: 22, tracking: 0)).foregroundStyle(S.ink).fixedSize(horizontal: false, vertical: true)
                    box(title: "Upside: \(PF.monthDay(h.exp)) \(PF.strike(h.k)) calls",
                        right: "Held \(h.held) · " + (h.covered ? "covered" : "add \(h.add)"),
                        label: h.label, oiOnly: h.oiOnly, call: true, k: h.k, near: h.pick == "sd" ? "Nearest +\(F.trim(h.target.sd)) SD" : nil,
                        why: (h.pick == "sd" ? h.wallK.map { "The 1st call wall, \(PF.strike($0)), is too far out to hedge, so this is the strike nearest the +\(F.trim(h.target.sd)) SD price. " } ?? "" : "") + callWhy(h))
                }
                if let i = p.insurance {
                    box(title: "Downside: \(PF.monthDay(i.exp)) \(PF.strike(i.k)) puts",
                        right: "Held \(i.held) · " + (i.add == 0 ? "covered" : "add \(i.add)") + " · 1:\(Int((1 / max(0.01, i.ratio)).rounded()))",
                        label: i.label, oiOnly: i.oiOnly, call: false, k: i.k, near: i.pick == "sd" ? "Nearest 1.5 SD down" : nil,
                        why: (i.pick == "sd" ? i.wallK.map { "The 1st put wall, \(PF.strike($0)), is too far down to insure, so this is the strike nearest 1.5 SD down. " } ?? "" : "") + putWhy(i))
                }
                if let h = p.hedge { statement(h) }
                if let c = p.hedge?.curve, c.count > 2 { curve(c) }
                if let c = p.hedge?.curve, c.count > 2 { numbers(c) }
                Text(costLine()).sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(p.budget?.over == true ? S.orangeDeep : S.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func callWhy(_ h: NamePlan.Hedge) -> String {
        switch h.label {
        case "ceiling": "Price tends to stall at \(PF.strike(h.k)), so this is cheaper insurance. It pays if \(t) breaks out above the wall, where your short calls lose the most."
        case "accelerator": "Moves speed up through \(PF.strike(h.k)), so these calls gain fast once a rally starts."
        case "floor": "The wall sits under the price; these calls still add delta through a rally."
        default: h.oiOnly ? "The 1st call wall by open interest; the tape has no read for this expiry yet." : "The tape gives no clear read at \(PF.strike(h.k))."
        }
    }
    private func putWhy(_ i: NamePlan.Insurance) -> String {
        let warn = i.warn ? " The cost runs past 4 weeks of premium." : ""
        let why: String = switch i.label {
        case "accelerator": "Drops tend to speed up below \(PF.strike(i.k)), so the puts start paying right where the risk begins."
        case "floor": "Drops tend to stall at \(PF.strike(i.k)), so these puts are cheaper cover for a break below it."
        default: i.oiOnly ? "The 1st put wall by open interest; the tape has no read for this expiry yet." : "The tape gives no clear read at \(PF.strike(i.k))."
        }
        var cost = ""
        if let c = i.cost {
            cost = " About \(PF.usd(c))"
            if let w = i.weeks { cost += ", \(F.trim((w * 10).rounded() / 10)) weeks of premium" }
            cost += "."
        }
        return why + cost + warn
    }

    private func box(title: String, right: String, label: String?, oiOnly: Bool, call: Bool, k: Double, near: String? = nil, why: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).sType(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink)
                Spacer(minLength: 6)
                Text(right).sType(SType(size: 13, weight: 600, line: 18, tracking: 0)).foregroundStyle(S.muted)
            }
            HStack(spacing: 6) {
                Image(systemName: GammaText.icon(label ?? (call ? "ceiling" : "accelerator"), call: call)).font(.system(size: 10, weight: .bold))
                Text(near ?? (label.map(GammaText.label) ?? (oiOnly ? "OI only" : "Unclear")) + ", \(call ? "1st call wall" : "1st put wall")")
                    .sType(SType(size: 12, weight: 600, line: 16, tracking: 0), tabular: false)
            }
            .foregroundStyle(S.ink).padding(.horizontal, 10).frame(height: 26)
            .background(Capsule().fill(S.paper)).overlay(Capsule().strokeBorder(S.line, lineWidth: 1))
            Text(why).sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(S.surface))
        .accessibilityElement(children: .combine)
    }

    private func statement(_ h: NamePlan.Hedge) -> some View {
        let ok = h.add == 0
        let px = h.target.px.map(PF.price) ?? "the target"
        let s = ok ? "Delta stays positive through \(px)." + (h.low.map { " The lowest point is \(sh($0.d)) shares at \(PF.price($0.px))." } ?? "")
                   : "Without more calls, net delta falls to \(sh(h.low?.d ?? 0)) shares at \(PF.price(h.low?.px ?? spot)). Add \(h.add) to stay positive through \(px)."
        return Text(s).sType(SType(size: 15, weight: 600, line: 20, tracking: 0))
            .foregroundStyle(ok ? S.blue : S.red)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill((ok ? S.blue : S.red).opacity(0.10)))
            .fixedSize(horizontal: false, vertical: true)
    }
    /// Shares, a plus when positive (the delta a hedge adds, README's exception), no minus: red does that.
    private func sh(_ d: Double) -> String { (d >= 0 ? "+" : "") + PWays.us(d) }

    /// Net delta at Thursday's close across prices: now (ink), with the calls added (green, dashed when none).
    private func curve(_ c: [[Double]]) -> some View {
        let tgt = p.hedge?.target.px
        return VStack(alignment: .leading, spacing: 6) {
            Text("Net delta across prices, Thursday").sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink)
            NetDeltaChart(pts: c.map { NetDeltaChart.Pt(px: $0[0], now: $0[1], after: $0[2]) }, spot: spot, target: tgt,
                          adding: (p.hedge?.add ?? 0) > 0, lowPx: p.hedge?.low?.px, lowD: p.hedge?.low?.d)
                .frame(height: 150)
                .padding(.top, 18)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    legend(S.ink, false, "Now, \(p.hedge?.held ?? 0) hedge calls")
                    if (p.hedge?.add ?? 0) > 0 { legend(S.green, true, "With \(p.hedge?.add ?? 0) more") }
                }
                if let lo = p.hedge?.low {
                    HStack(spacing: 6) {
                        Circle().fill(S.orangeDeep).frame(width: 8, height: 8).frame(width: 14)
                        Text("Lowest point: " + (lo.d >= 0 ? "+\(PWays.us(lo.d)) shares" : "\(PWays.us(lo.d)) shares short") + " at \(PF.price(lo.px))").sType(SType(size: 12, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.muted)
                    }
                }
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(S.orange.opacity(0.25)).frame(width: 14, height: 10)
                    Text("Below zero: further rallies cost you money").sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Net delta across prices. " + (p.hedge?.low.map { "Lowest \(PWays.us($0.d)) shares at \(PF.price($0.px))" } ?? ""))
    }
    private func legend(_ c: Color, _ dashed: Bool, _ t: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(c).frame(width: 14, height: 3).opacity(dashed ? 0.8 : 1)
            Text(t).sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
        }
    }

    /// Today, at the target, at 1.5 SD down: net delta with the calls added.
    private func numbers(_ c: [[Double]]) -> some View {
        let at = { (px: Double) -> Double in
            let i = c.indices.min(by: { abs(c[$0][0] - px) < abs(c[$1][0] - px) }) ?? 0
            return c[i][2]
        }
        let cells: [(String, Double)] = [("Today", at(spot)), ("At \(PF.price(c.last![0]))", c.last![2]), ("At \(PF.price(c.first![0]))", c.first![2])]
        return HStack(spacing: 8) {
            ForEach(cells, id: \.0) { l, d in
                VStack(alignment: .leading, spacing: 2) {
                    Text(l).sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
                    Text(sh(d)).sType(SType(size: 17, weight: 700, line: 22, tracking: 0)).foregroundStyle(d < 0 ? S.red : S.ink)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(S.surface))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func costLine() -> String {
        var s: [String] = []
        if let b = p.budget {
            s.append("Hedges cost about \(Int(b.pct.rounded()))% of a week's premium, spread to their expiry.")
            if b.over { s.append("That is over the 25% budget: the insurance puts are the part to trim, for example 1:3 instead of 1:2.") }
        }
        if let e = earnings, let h = p.hedge?.exp, e <= h { s.append("\(PF.monthDay(h)) spans the next earnings report (\(PF.monthDay(e))), so these hedges also cover the week the weeklies skip.") }
        return s.joined(separator: " ")
    }
}

// MARK: - Your position: every leg and the net delta

struct GammaPosition: View {
    let t: String
    let legs: [Leg]
    let dg: DGBook?
    var name: String? = nil
    var today = ""
    /// The design's order: LEAPS, the calls sold, the hedge calls, the insurance puts, then any puts sold.
    private func order(_ l: Leg) -> Int {
        l.side == "bought" ? (l.type == "put" ? 3 : (l.up ?? false) ? 2 : 0) : (l.type == "call" ? 1 : 4)
    }
    var body: some View {
        let g = Dictionary(grouping: legs, by: { "\($0.side)|\($0.type)|\($0.strike)|\($0.expiry)" }).values.map { ls in (ls[0], ls.reduce(0) { $0 + $1.n }) }
            .sorted { (order($0.0), $0.0.expiry, $0.0.strike) < (order($1.0), $1.0.expiry, $1.0.strike) }
        SCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your \(name ?? t) position").sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    .padding(.bottom, 10)
                ForEach(g, id: \.0.id) { l, n in
                    HStack {
                        Text(word(l)).sType(SType(size: 15, weight: 400, line: 20, tracking: 0)).foregroundStyle(S.ink)
                        Spacer()
                        Text("\(n)").sType(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink)
                    }
                    .padding(.vertical, 9)
                    .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
                }
                if let d = dg {
                    Text(summary(d))
                        .sType(SType(size: 15, weight: 400, line: 22, tracking: 0)).foregroundStyle(S.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
            }
        }
    }
    /// "You are net long about 1,105 shares today. The weekly calls cap the upside each week, the Jan calls protect a
    /// breakout above 110, and the Jan puts protect a fall below 90."
    private func summary(_ d: DGBook) -> String {
        var parts: [String] = []
        if legs.contains(where: { $0.side == "sold" && $0.type == "call" }) { parts.append("the weekly calls cap the upside each week") }
        if let h = legs.filter({ $0.side == "bought" && $0.type == "call" && ($0.up ?? false) }).min(by: { $0.strike < $1.strike }) {
            parts.append("the \(String(PF.monthDay(h.expiry).prefix(3))) calls protect a breakout above \(PF.strike(h.strike))")
        }
        if let p = legs.filter({ $0.side == "bought" && $0.type == "put" }).max(by: { $0.strike < $1.strike }) {
            parts.append("the \(String(PF.monthDay(p.expiry).prefix(3))) puts protect a fall below \(PF.strike(p.strike))")
        }
        let tail = parts.isEmpty ? "" : " " + (parts.count == 1 ? parts[0] : parts.dropLast().joined(separator: ", ") + ", and " + parts.last!).capitalizedFirst + "."
        return "You are net \(d.d0 >= 0 ? "long" : "short") about \(PWays.us(abs(d.d0))) shares today." + tail
    }
    private func word(_ l: Leg) -> String {
        // "Jan 15" inside a year, "Jan ’28" past it.
        let far = !today.isEmpty && l.expiry > MarketClock.addDays(today, 365).iso
        let md = far ? "\(PF.monthDay(l.expiry).prefix(3)) ’\(l.expiry.dropFirst(2).prefix(2))" : PF.monthDay(l.expiry), k = PF.strike(l.strike)
        if l.side == "sold" { return "Short \(md) \(k) \(l.type)s" }
        if l.type == "put" { return "Long \(md) \(k) puts, insurance" }
        return (l.up ?? false) ? "Long \(md) \(k) calls, upside hedge" : "Long \(md) \(k) calls"
    }
}

// MARK: - Walls table: each wall, its label, the five-session history

struct GammaWallsTable: View {
    let v: GammaView
    let hist: [(String, GammaView)]
    let view: String
    var body: some View {
        SCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Walls").sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Text((view == "weeklies" ? "Weekly chain" : view == "all" ? "Every expiry to 45 days" : "\(PF.monthDay(view)) chain") + " gamma from the trade tape, in $ per 1% move. Small number: change over the last five sessions.")
                    .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(S.muted)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 2).padding(.bottom, 8)
                ForEach(v.walls.sorted { ($0.call ? 0 : 1, $0.rank) < ($1.call ? 0 : 1, $1.rank) }, id: \.self) { w in row(w) }
                Text(movedLine()).sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(S.muted)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                    .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
            }
        }
    }

    private func series(_ w: GWall) -> [(String, Double, Double)] {
        hist.prefix(6).compactMap { d, gv in gv.walls.first { $0.side == w.side && $0.rank == w.rank }.map { (d, $0.k, $0.gex) } }.reversed()
    }

    private func row(_ w: GWall) -> some View {
        let s = series(w), first = s.first
        let tint = w.call ? S.blue : S.orange
        let dg = first.map { abs(w.gex) - abs($0.2) }
        let pct = first.map { abs($0.2) > 0 ? (abs(w.gex) / abs($0.2) - 1) * 100 : 0 }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text("\(w.rank == 1 ? "1st" : w.rank == 2 ? "2nd" : "3rd") \(w.side)").sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(PF.strike(w.k)).sType(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink)
                    Text(GammaText.vs(w.k, v.spot)).sType(SType(size: 12, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.muted)
                }
                VStack(alignment: .trailing, spacing: 0) {
                    Text(GammaText.money(w.gex)).sType(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink)
                    // Never a minus sign (design 13h): "+0.6M", "0.1M less".
                    Text(dg.map { $0 >= 0 ? "+" + GammaText.size($0) : GammaText.size(abs($0)) + " less" } ?? " ").sType(SType(size: 12, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.muted)
                }
                .frame(width: 84, alignment: .trailing)
            }
            HStack(alignment: .center) {
                HStack(spacing: 4) {
                    Image(systemName: GammaText.icon(w.label, call: w.call)).font(.system(size: 10, weight: .bold))
                    Text(GammaText.label(w.label)).sType(SType(size: 12, weight: 700, line: 16, tracking: 0), tabular: false)
                    Text(", \(GammaText.conf(w.conf))").sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false)
                }
                .foregroundStyle(S.ink).padding(.horizontal, 8).frame(height: 24).background(Capsule().fill(S.surface))
                if let o = w.oiLabel, o != w.label, w.label != "unclear" {
                    Text("OI said \(GammaText.label(o))").sType(SType(size: 11, weight: 600, line: 14, tracking: 0), tabular: false).foregroundStyle(S.orangeDeep)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    spark(s, tint).frame(width: 60, height: 18)
                    Text(pct.map { abs($0) < 0.5 ? "same size" : $0 > 0 ? "+\(Int($0.rounded()))% size" : "\(Int(abs($0).rounded()))% smaller" } ?? "").sType(SType(size: 11, weight: 500, line: 14, tracking: 0), tabular: false).foregroundStyle(S.muted)
                }
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(w.rank == 1 ? "First" : w.rank == 2 ? "Second" : "Third") \(w.side) wall \(PF.strike(w.k)), \(GammaText.label(w.label)), \(GammaText.conf(w.conf)) confidence, \(GammaText.money(w.gex))")
    }

    /// The wall's strike over the sessions, a step line (flat while it held).
    private func spark(_ s: [(String, Double, Double)], _ tint: Color) -> some View {
        Canvas { ctx, size in
            guard s.count > 1 else { return }
            let ks = s.map(\.1), lo = ks.min()!, hi = ks.max()!, span = max(1e-9, hi - lo)
            var p = Path()
            for (i, x) in s.enumerated() {
                let px = size.width * CGFloat(i) / CGFloat(s.count - 1), py = hi == lo ? size.height / 2 : size.height * CGFloat(1 - (x.1 - lo) / span)
                if i == 0 { p.move(to: CGPoint(x: px, y: py)) } else { p.addLine(to: CGPoint(x: px, y: p.currentPoint!.y)); p.addLine(to: CGPoint(x: px, y: py)) }
            }
            ctx.stroke(p, with: .color(tint), lineWidth: 1.5)
        }
    }

    private func movedLine() -> String {
        let moved = v.walls.compactMap { w -> String? in
            guard let prev = hist.dropFirst().first?.1.walls.first(where: { $0.side == w.side && $0.rank == w.rank }), abs(prev.k - w.k) > 1e-6 else { return nil }
            return "the \(w.rank == 1 ? "1st" : w.rank == 2 ? "2nd" : "3rd") \(w.side) wall moved from \(PF.strike(prev.k)) to \(PF.strike(w.k))"
        }
        return moved.isEmpty ? "No walls moved to a new strike since the last session. When one does, its old strike shows here."
                             : moved.joined(separator: "; ").capitalizedFirst + " since the last session."
    }
}

// MARK: - Who is trading: the flow profile's inputs

struct GammaWho: View {
    let t: String
    let flow: GammaView.Flow?
    var profile: FlowProfile? = nil
    var body: some View {
        SCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Who is trading \(t)").sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Spacer()
                    Text(profile?.label ?? "Ranking pending").sType(SType(size: 12, weight: 600, line: 12, tracking: 0), tabular: false)
                        .foregroundStyle(S.ink).padding(.horizontal, 8).frame(height: 24).background(Capsule().fill(S.track))
                }
                if let p = profile {
                    (Text("\(p.retail) of 5 inputs point to retail.").bold().foregroundStyle(S.ink)
                     + Text(" Retail-heavy when at least 3 of 5 inputs rank beyond the 70th percentile in the retail direction, against \(p.universe) names. The line on each bar marks the 70th."))
                        .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(S.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(p.inputs, id: \.key) { i in ranked(i) }
                    Text("The profile only sets the starting assumption. Once tape coverage is high enough, the tape decides each label. Last \(p.sessions) sessions to \(PF.monthDay(p.asof)).")
                        .sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Retail-heavy when at least 3 of 5 inputs rank beyond the 70th percentile in the retail direction, against about 100 names (ETFs left out). The ranking is building; until then the inputs show on their own.")
                        .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(S.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let f = flow {
                        input("Volume under 7 days to expiry", "\(Int((f.under7 * 100).rounded()))%", f.under7)
                        input("Call to put volume ratio", String(format: "%.1f", f.callPut), min(1, f.callPut / 3))
                        if let m = f.median { input("Median trade size", PWords.n(Int(m), "contract"), min(1, m / 20)) }
                        if let s = f.small { input("Trades of 10 contracts or fewer", "\(Int((s * 100).rounded()))%", s) }
                    }
                }
            }
        }
    }
    /// One input: its value, a bar to its percentile toward retail (ink when it counts as retail), the 70th marked.
    private func ranked(_ i: FlowProfile.Input) -> some View {
        let v: String = {
            guard let x = i.value else { return "None" }
            switch i.key {
            case "cp": return String(format: "%.1f", x)
            case "med": return PWords.n(Int(x), "contract")
            case "own": return "\(Int(x.rounded()))%"
            default: return "\(Int((x * 100).rounded()))%"
            }
        }()
        let pct = i.pct ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(i.name).sType(SType(size: 15, weight: 400, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Spacer()
                Text(v).sType(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(S.track)
                    Capsule().fill(i.retail ? S.ink : S.muted).frame(width: g.size.width * CGFloat(min(100, max(0, pct)) / 100))
                    Rectangle().fill(S.ink).frame(width: 2, height: 14).offset(x: g.size.width * 0.7 - 1)
                }
            }
            .frame(height: 8)
            Text(i.pct.map { "\(GammaText.ordinal(Int($0))) percentile toward retail" + (i.retail ? ", counts as retail" : "") } ?? "No data")
                .sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
        }
        .accessibilityElement(children: .combine)
    }
    private func input(_ l: String, _ v: String, _ share: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(l).sType(SType(size: 15, weight: 400, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Spacer()
                Text(v).sType(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(share == nil ? S.muted : S.ink)
            }
            if let share {
                GeometryReader { g in
                    ZStack(alignment: .leading) { Capsule().fill(S.track); Capsule().fill(S.muted).frame(width: g.size.width * min(1, max(0, share))) }
                }.frame(height: 6)
            }
        }
    }
}

// MARK: - Data quality: coverage and the print types

struct GammaQuality: View {
    let v: GammaView
    var body: some View {
        SCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Data quality").sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                HStack(alignment: .firstTextBaseline) {
                    Text("Tape coverage").sType(SType(size: 15, weight: 400, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Spacer()
                    Text(v.coverage.map { "\(Int(($0 * 100).rounded()))%" } ?? "None").sType(SType(size: 28, weight: 800, line: 32, tracking: -0.01)).foregroundStyle(S.ink)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(S.track)
                        Capsule().fill(S.ink).frame(width: g.size.width * CGFloat(v.coverage ?? 0))
                        Rectangle().fill(S.orange).frame(width: 2, height: 12).offset(x: g.size.width * 0.5 - 1)
                    }
                }.frame(height: 8)
                Text("Share of today's option volume classified by side. Under 50% (the orange line) is a murky day, but each wall is still read from its own strike: one with under 40% of its trades readable shows Unclear.")
                    .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(S.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let p = v.prints {
                    Text("Volume by print type").sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink).padding(.top, 4)
                    ForEach([("single", "Single-leg"), ("multi", "Multi-leg or spread"), ("tied", "Tied-to-stock"), ("auction", "Auction or cross"), ("other", "Other")], id: \.0) { k, l in
                        HStack(spacing: 10) {
                            Text(l).sType(SType(size: 13, weight: 400, line: 18, tracking: 0), tabular: false).foregroundStyle(S.ink).frame(width: 130, alignment: .leading)
                            GeometryReader { g in
                                ZStack(alignment: .leading) { Capsule().fill(S.track); Capsule().fill(S.muted).frame(width: g.size.width * CGFloat(p[k] ?? 0)) }
                            }.frame(height: 6)
                            Text("\(Int(((p[k] ?? 0) * 100).rounded()))%").sType(SType(size: 13, weight: 600, line: 18, tracking: 0)).foregroundStyle(S.ink).frame(width: 40, alignment: .trailing)
                        }
                    }
                    Text("Tied-to-stock, block and auction prints are where institutional overwriting shows up. They are classified by price, never dropped.")
                        .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(S.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - How labels held: building until 45 sessions are read

struct GammaHeld: View {
    let sessions: Int?
    var track: GammaView.Track? = nil
    /// Nik's rule 7: never hidden; "Building: N of 45 sessions" until there are 45.
    private var ready: Bool { (track?.sessions ?? 0) >= 45 && !(track?.rows.isEmpty ?? true) }
    var body: some View {
        SCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("How labels held").sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Spacer()
                    Text(ready ? "Last \(track?.sessions ?? 0) sessions" : "Building: \(min(45, track?.sessions ?? sessions ?? 0)) of 45 sessions")
                        .sType(SType(size: 12, weight: 600, line: 12, tracking: 0), tabular: false)
                        .foregroundStyle(S.ink).padding(.horizontal, 8).frame(height: 24).background(Capsule().fill(S.yellow.opacity(0.35)))
                }
                if ready, let t = track {
                    ForEach(t.rows, id: \.kind) { r in row(r) }
                    Text("Touch: within 0.3% in the next 5 sessions. Held: closed back away within 2 sessions. Broke: closed through by 0.5%.")
                        .sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("For each label, how often price respected or broke the wall when it got within 0.3%, against random strikes the same distance away. Respect: closed back away within 2 sessions. Break: closed through by 0.5%. The scores show once the labels have a track record.")
                        .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(S.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// "Ceilings held 64% vs 52%", a bar to the rate with an orange tick at the baseline.
    private func row(_ r: GammaView.Track.Row) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(r.label).sType(SType(size: 14, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Spacer()
                (Text("\(Int(r.rate))%").bold().foregroundStyle(S.ink) + Text(" vs \(Int(r.base))%").foregroundStyle(S.muted))
                    .sType(SType(size: 14, weight: 500, line: 20, tracking: 0))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(S.track)
                    Capsule().fill(S.ink).frame(width: g.size.width * CGFloat(min(100, max(0, r.rate)) / 100))
                    Rectangle().fill(S.orangeDeep).frame(width: 2, height: 16)
                        .offset(x: g.size.width * CGFloat(min(100, max(0, r.base)) / 100) - 1)
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            Text("Orange line: \(Int(r.base))% at random strikes the same distance away. \(r.touches) touch\(r.touches == 1 ? "" : "es").")
                .sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// The Hedges card's chart: net delta at Thursday's close across prices, now and with the calls added.
struct NetDeltaChart: View {
    struct Pt: Identifiable { let px: Double; let now: Double; let after: Double; var id: Double { px } }
    let pts: [Pt]
    let spot: Double
    let target: Double?
    let adding: Bool
    let lowPx: Double?
    let lowD: Double?
    private static let axisFont = SType(size: 11, weight: 500, line: 14, tracking: 0).font(tabular: true)

    var body: some View {
        // The prices the curve covers (never from zero), and room under zero for the shaded "costs you money" band.
        let lo: Double = pts.first?.px ?? spot * 0.9, hi: Double = pts.last?.px ?? spot * 1.1
        let ys = pts.flatMap { [$0.now, $0.after] }
        let top = max(1, ys.max() ?? 1), bottom = min(-0.35 * top, (ys.min() ?? 0) * 1.15)
        Charts.Chart {
            RectangleMark(xStart: .value("lo", lo), xEnd: .value("hi", hi), yStart: .value("z", bottom), yEnd: .value("z0", 0.0))
                .foregroundStyle(S.orange.opacity(0.16))
            RuleMark(y: .value("zero", 0.0)).foregroundStyle(S.muted)
            RuleMark(x: .value("Today", spot)).foregroundStyle(S.ink)
                .annotation(position: .top, alignment: .center) {
                    Text("Today").font(Self.axisFont).fontWeight(.semibold).foregroundStyle(S.ink)
                }
            if let target { RuleMark(x: .value("Target", target)).foregroundStyle(S.muted).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3])) }
            ForEach(pts) { p in
                LineMark(x: .value("Price", p.px), y: .value("Delta", p.now), series: .value("Series", "now")).foregroundStyle(S.ink)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if adding {
                ForEach(pts) { p in
                    LineMark(x: .value("Price", p.px), y: .value("Delta", p.after), series: .value("Series", "after"))
                        .foregroundStyle(S.green).lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                }
            }
            if let lowPx, let lowD { PointMark(x: .value("Low", lowPx), y: .value("Delta", lowD)).foregroundStyle(S.orangeDeep).symbolSize(50) }
        }
        .chartXScale(domain: lo...hi)
        .chartYScale(domain: bottom...(top * 1.1))
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { v in AxisValueLabel { Text(v.as(Double.self).map(PF.price) ?? "").font(Self.axisFont) } } }
        .chartYAxis { AxisMarks(values: [0.0]) { _ in AxisValueLabel { Text("0").font(Self.axisFont) } } }
    }
}
