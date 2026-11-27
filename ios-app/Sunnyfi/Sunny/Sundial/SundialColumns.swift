//
//  SundialColumns.swift
//  Sunny
//
//  The board's five columns (handoff 2026-11-27 README §2.3; SunnyIncomeBoard.dc.html narrow). Each column has one
//  job, so each looks different; the difference comes from structure, weight and marks, never from coloured words.
//    To sell     action: the brightest cards, the credit as the hero (32), Keep N under the leg it nets with, the
//                plan dimmer before 3:45 PM, a big-drop card on top (a green dot that breathes)
//    Close       warning: small cards under the name, an 8 pt red dot, the kept % (24) and a grey bar with a notch
//                at 50%, the buy-back and the deadline (Day 2 of 2 · 3:45 PM, or Due now)
//    Working     calm: one quiet box a name, rows only, no hero
//    Expiring    watch: a clock to the close, the distance (24), a price line with the strike in orange, what
//                happens at the close, the buy-back when it is in the money
//    Banked      done: a stack a name, its total (28) on top, the biggest loss on top; a tap fans it out
//  Motion (§2.5, none under Reduce Motion): a card rises 8 pt and fades in once (460 ms; the sections 70 ms apart,
//  the cards 30 ms), kept bars fill from the left (800 ms after 260 ms), stacks fan with an ease (450 ms).
//

import SwiftUI

// MARK: - Shared parts

/// A column's head: the title (22 bold), one grey line with the column's amount, and the plan line when given.
struct SDHead: View {
    let title: String
    let sum: String
    var note: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).sType(IncT.t(22, 26, 700), tabular: false).foregroundStyle(SDC.ink).accessibilityAddTraits(.isHeader)
            Text(sum).sType(IncT.t(15, 20)).foregroundStyle(SDC.mu)
            if let note { Text(note).sType(IncT.t(13, 17), tabular: false).foregroundStyle(SDC.mu) }
        }
        .padding(.horizontal, 2).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(SDC.l12).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// An empty column: a dashed box with "None today" (or "None yet").
struct SDNone: View {
    let text: String
    var body: some View {
        Text(text).sType(IncT.t(15, 20), tabular: false).foregroundStyle(SDC.mu)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(SDC.dash, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }
}

/// The name above a column's cards: a 20 pt logo and the name in grey.
struct SDNameRow: View {
    let t: String
    let name: String
    var body: some View {
        HStack(spacing: 8) {
            IncLogo(t: t, size: 20, ring: true)
            Text(name).sType(IncT.t(13, 16, 500), tabular: false).foregroundStyle(SDC.mu)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Rises 8 pt and fades in once (README §2.5); none under Reduce Motion.
private struct SDEnter: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown || reduce ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 8)
            .onAppear {
                guard !shown else { return }
                if reduce { shown = true } else { withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.46).delay(delay)) { shown = true } }
            }
    }
}
extension View {
    /// Column `col` (0 to 4), card `i` in it.
    func sdEnter(_ col: Int, _ i: Int) -> some View { modifier(SDEnter(delay: Double(col) * 0.07 + Double(min(i, 8)) * 0.03)) }
}

/// A grey kept bar that fills from the left (800 ms, 260 ms delay); `notch`: Close's mark at 50%.
struct SDKeptBar: View {
    let pct: Int
    let height: CGFloat
    var notch = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var grown = false
    var body: some View {
        GeometryReader { g in
            let w = g.size.width * CGFloat(min(100, max(0, pct))) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(SDC.trk)
                Rectangle().fill(SDC.fill).frame(width: w).scaleEffect(x: grown || reduce ? 1 : 0, anchor: .leading)
                if notch { Rectangle().fill(SDC.box).frame(width: 2).offset(x: g.size.width / 2 - 1) }
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
        .onAppear {
            guard !grown, !reduce else { return }
            withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.8).delay(0.26)) { grown = true }
        }
        .accessibilityHidden(true)
    }
}

/// A flat card on the board's raised colour with a 1 pt ring.
private extension View {
    func sdBox(_ radius: CGFloat) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(SDC.box))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(SDC.ring, lineWidth: 1))
    }
}

/// Group a column's flat cards under their names, in the server's order.
private func byName<T>(_ xs: [T], _ t: (T) -> String) -> [(t: String, items: [T])] {
    var out: [(t: String, items: [T])] = []
    for x in xs {
        if let i = out.firstIndex(where: { $0.t == t(x) }) { out[i].items.append(x) } else { out.append((t(x), [x])) }
    }
    return out
}

// MARK: - To sell (action)

struct SDToSell: View {
    let board: SDBoard
    var body: some View {
        let cards = board.toSell?.cards ?? [], drops = board.drops ?? [], plan = board.final == false
        let total = board.toSell?.total ?? 0
        // Still to sell (New), apart from what was sold today (Done)
        let newN = cards.reduce(0) { $0 + $1.legs.count } + drops.count
        VStack(alignment: .leading, spacing: 12) {
            SDHead(title: "To sell", sum: newN > 0 ? SDF.signedT(total) : (cards.isEmpty ? "None" : "All sold"),
                   note: plan && newN > 0 ? "Plan · final at \(SDF.t12(board.finalAt))" : nil)
            ForEach(Array(drops.enumerated()), id: \.offset) { i, d in
                SDDropCard(drop: d, name: board.label(d.t)).sdEnter(0, i)
            }
            ForEach(Array(cards.enumerated()), id: \.element.t) { i, c in
                SDSellCard(card: c, name: board.label(c.t), plan: plan).sdEnter(0, drops.count + i)
            }
            if cards.isEmpty && drops.isEmpty { SDNone(text: "None today") }
        }
    }
}

/// One leg to sell: "10 $162.50 calls", its credit on the right when the card has two or more legs, then
/// "Dec 2 · 0.75 SD · $2.31 each", then Keep N when the sale nets with a buy-back.
/// Done and New (Nik 27 Nov): New is the ready-to-act mark (a green pill with a word), Done a quiet outlined one.
struct SDTag: View {
    let done: Bool
    var body: some View {
        Text(done ? "Done" : "New").sType(IncT.t(12, 18, 500), tabular: false)
            .foregroundStyle(done ? SDC.mu : S.dyn(0xFFFFFF, 0x171717))
            .padding(.horizontal, 7)
            .background(Capsule().fill(done ? Color.clear : SDC.green))
            .overlay { if done { Capsule().strokeBorder(SDC.mu.opacity(0.45), lineWidth: 1) } }
    }
}

struct SDSellLeg: View {
    let leg: SDBoard.Leg
    let showCredit: Bool
    /// nil: no tag (nothing sold yet today); false: New; true: Done
    var done: Bool? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(SDF.contract(leg.qty, leg.strike, leg.type)).sType(IncT.t(16, 21, 500)).foregroundStyle(done == true ? SDC.dim : SDC.ink)
                Spacer(minLength: 0)
                if showCredit, let c = leg.credit { Text(SDF.signedC(c)).sType(IncT.t(16, 21, 500)).foregroundStyle(done == true ? SDC.dim : SDC.ink) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let d = done { SDTag(done: d) }
                Text(meta).sType(IncT.t(13, 17)).foregroundStyle(SDC.mu)
            }
            if let k = leg.keep {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Keep \(k.qty)").sType(IncT.t(15, 20, 500)).foregroundStyle(SDC.ink)
                    Text("\(k.total) on \(SDF.md(leg.expiry))").sType(IncT.t(13, 17)).foregroundStyle(SDC.mu)
                }
                .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .combine)
    }
    private var meta: String {
        if done == true {
            var p = [SDF.md(leg.expiry)]
            if let x = leg.price { p.append("sold at \(SDF.money2(x))") }
            if let d = SDF.parse(leg.at) { p.append(SDF.time(d)) }
            return p.joined(separator: " · ")
        }
        var p = [SDF.md(leg.expiry)]
        if let s = leg.sd { p.append("\(SDF.sd(s)) SD") }
        if let x = leg.price { p.append("\(SDF.money2(x)) each") }
        return p.joined(separator: " · ")
    }
}

/// The logo (32), the name and the credit as the hero (32 bold).
private struct SDCardTop: View {
    let t: String
    let name: String
    let credit: Double
    var heroColor: Color = SDC.ink
    var body: some View {
        HStack(spacing: 10) {
            IncLogo(t: t, size: 32, ring: true)
            Text(name).sType(IncT.t(17, 22, 500), tabular: false).foregroundStyle(SDC.ink).lineLimit(1)
            Spacer(minLength: 8)
            Text(SDF.signedC(credit)).sType(IncT.t(32, 36, 700, tr: -0.02).heroic).foregroundStyle(heroColor).lineLimit(1)
        }
    }
}

struct SDSellCard: View {
    let card: SDBoard.SellCard
    let name: String
    let plan: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let done = card.done ?? [], many = card.legs.count + done.count > 1
            SDCardTop(t: card.t, name: name, credit: card.legs.isEmpty ? (card.doneCredit ?? 0) : card.credit,
                      heroColor: plan || card.legs.isEmpty ? SDC.dim : SDC.ink)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(card.legs.enumerated()), id: \.offset) { _, l in SDSellLeg(leg: l, showCredit: many, done: done.isEmpty ? nil : false) }
                ForEach(Array(done.enumerated()), id: \.offset) { _, l in SDSellLeg(leg: l, showCredit: many, done: true) }
            }
            VStack(alignment: .leading, spacing: 3) {
                if let r = card.reason { Text(r).sType(IncT.t(13, 17), tabular: false).foregroundStyle(SDC.mu) }
                Text(card.safe ?? "Safe to +20%").sType(IncT.t(13, 17), tabular: false).foregroundStyle(SDC.mu)
                if let b = card.basis { Text(SDF.basis(b)).sType(IncT.t(13, 17), tabular: false).foregroundStyle(SDC.mu) }
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(SDC.l8).frame(height: 1) }
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 18)
        // Light: white with a soft shadow, on the card's shape only (none for the plan).
        .background(
            RoundedRectangle(cornerRadius: 18).fill(plan ? SDC.plan : SDC.sell)
                .shadow(color: .black.opacity(scheme == .light && !plan ? 0.16 : 0), radius: 14, y: 12)
                .shadow(color: .black.opacity(scheme == .light && !plan ? 0.04 : 0), radius: 2, y: 2)
        )
        .overlay {
            if plan {
                RoundedRectangle(cornerRadius: 18).strokeBorder(SDC.planDash, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            } else if scheme == .dark {
                RoundedRectangle(cornerRadius: 18).strokeBorder(SDC.sellRing, lineWidth: 1)
            }
        }
    }
}

/// The big drop (README §2.3): "Big drop · 11:20 AM", the logo row with the credit, the line it crossed (20 bold)
/// after a green dot whose ring breathes, then the puts.
struct SDDropCard: View {
    let drop: SDBoard.Drop
    let name: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Big drop" + (SDF.parse(drop.at).map { " · " + SDF.time($0) } ?? "") + (drop.price.map { " · " + SDF.money2($0) } ?? ""))
                .sType(IncT.t(13, 16, 500), tabular: false).foregroundStyle(SDC.mu)
            SDCardTop(t: drop.t, name: name, credit: drop.credit)
            HStack(spacing: 8) {
                SDPulseDot()
                Text(drop.line ?? "").sType(IncT.t(20, 24, 700)).foregroundStyle(SDC.ink)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(drop.legs.enumerated()), id: \.offset) { _, l in SDSellLeg(leg: l, showCredit: drop.legs.count > 1) }
            }
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 18)
        .background(
            RoundedRectangle(cornerRadius: 18).fill(SDC.sell)
                .shadow(color: .black.opacity(scheme == .light ? 0.16 : 0), radius: 14, y: 12)
        )
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(SDC.dropRing, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }
}

/// The ready-to-act dot (8 pt green) that sends out a soft ring every 2.2 s (scale to 2.8×, fading out).
struct SDPulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var on = false
    var body: some View {
        ZStack {
            if !reduce {
                Circle().fill(SDC.green).frame(width: 8, height: 8)
                    .scaleEffect(on ? 2.8 : 1).opacity(on ? 0 : 0.55)
            }
            Circle().fill(SDC.green).frame(width: 8, height: 8)
        }
        .frame(width: 8, height: 8)
        .onAppear {
            guard !reduce else { return }
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) { on = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Close (warning)

struct SDCloseColumn: View {
    let board: SDBoard
    var body: some View {
        let cards = board.close?.cards ?? []
        VStack(alignment: .leading, spacing: 12) {
            SDHead(title: "Close", sum: cards.isEmpty ? "None" : "\(SDF.kT(board.close?.total ?? 0)) to buy back")
            ForEach(byName(cards, \.t), id: \.t) { g in
                VStack(alignment: .leading, spacing: 8) {
                    SDNameRow(t: g.t, name: board.label(g.t))
                    ForEach(Array(g.items.enumerated()), id: \.offset) { i, c in SDCloseCard(card: c).sdEnter(1, i) }
                }
            }
        }
    }
}

struct SDCloseCard: View {
    let card: SDBoard.CloseCard
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 7) {
                Circle().fill(SDC.red).frame(width: 8, height: 8).padding(.top, 6).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(SDF.contract(card.qty, card.strike, card.type ?? "call")).sType(IncT.t(15, 20, 500)).foregroundStyle(SDC.ink)
                    Text("\(SDF.md(card.expiry)) · \(SDF.money2(card.soldAt)) → \(SDF.money2(card.now))").sType(IncT.t(13, 17)).foregroundStyle(SDC.mu)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(card.keptPct)%").sType(IncT.t(24, 28, 700, tr: -0.01)).foregroundStyle(SDC.ink)
                Text("kept").sType(IncT.t(13, 16), tabular: false).foregroundStyle(SDC.mu)
            }
            SDKeptBar(pct: card.keptPct, height: 6, notch: true)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Buy back \(SDF.kC(card.buyBack))").sType(IncT.t(14, 19, 500)).foregroundStyle(SDC.ink)
                Spacer(minLength: 0)
                Text(deadline).sType(IncT.t(13, 17), tabular: false).foregroundStyle(SDC.mu)
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
        .sdBox(14)
        .accessibilityElement(children: .combine)
    }
    /// Before 3:45 PM "Day 2 of 2 · 3:45 PM"; from 3:45 PM until IBKR's buy-back arrives "Due now".
    private var deadline: String {
        card.due == true ? "Due now" : "Day \(card.day ?? 2) of \(card.of ?? 2) · \(SDF.t12(card.deadline ?? "15:45"))"
    }
}

// MARK: - Working (calm)

struct SDWorkingColumn: View {
    let board: SDBoard
    var body: some View {
        let groups = board.working?.groups ?? []
        VStack(alignment: .leading, spacing: 12) {
            SDHead(title: "Working", sum: groups.isEmpty ? "None" : "\(SDF.kT(board.working?.total ?? 0)) to go")
            ForEach(Array(groups.enumerated()), id: \.element.t) { i, g in
                SDWorkBox(group: g, name: board.label(g.t)).sdEnter(2, i)
            }
            if groups.isEmpty { SDNone(text: "None") }
        }
    }
}

struct SDWorkBox: View {
    let group: SDBoard.WorkGroup
    let name: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                IncLogo(t: group.t, size: 20, ring: true)
                Text(name).sType(IncT.t(14, 19, 500), tabular: false).foregroundStyle(SDC.ink2)
                Spacer(minLength: 0)
                Text(group.legs.count == 1 ? "1 leg" : "\(group.legs.count) legs").sType(IncT.t(13, 16)).foregroundStyle(SDC.mu)
            }
            .padding(.top, 10).padding(.bottom, 9)
            ForEach(Array(group.legs.enumerated()), id: \.offset) { _, l in row(l) }
        }
        .padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 3)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(SDC.ring, lineWidth: 1))
    }

    private func row(_ l: SDBoard.WorkLeg) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(SDF.contract(l.qty, l.strike, l.type)).sType(IncT.t(14, 19, 500)).foregroundStyle(SDC.ink2)
                Spacer(minLength: 0)
                Text(l.keptPct < 0 ? "\u{2212}\(abs(l.keptPct))%" : "\(l.keptPct)%").sType(IncT.t(14, 19, 500)).foregroundStyle(SDC.ink2)
            }
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 6) {
                    Text(meta(l)).sType(IncT.t(13, 17)).foregroundStyle(SDC.mu).lineLimit(1)
                    if l.itm == true {
                        // In the money: an 8 pt red dot and the words, in place of the SD. No action: Sundial holds.
                        Circle().fill(SDC.red).frame(width: 8, height: 8).accessibilityHidden(true)
                        Text("In the money").sType(IncT.t(13, 17), tabular: false).foregroundStyle(SDC.mu)
                    }
                }
                Spacer(minLength: 0)
                SDKeptBar(pct: max(0, l.keptPct), height: 3).frame(width: 56)
            }
        }
        .padding(.top, 9).padding(.bottom, 10)
        .overlay(alignment: .top) { Rectangle().fill(SDC.l8).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private func meta(_ l: SDBoard.WorkLeg) -> String {
        var p = [SDF.md(l.expiry)]
        if let d = l.daysLeft { p.append(SDF.days(d)) }
        if l.itm == true { return p.joined(separator: " · ") + " ·" }
        if let s = l.sd { p.append("\(SDF.sd(s)) SD") }
        return p.joined(separator: " · ")
    }
}

// MARK: - Expiring today (careful watch)

struct SDExpiringColumn: View {
    let board: SDBoard
    var body: some View {
        let cards = board.expiring?.cards ?? [], total = board.expiring?.total ?? 0
        VStack(alignment: .leading, spacing: 12) {
            SDHead(title: "Expiring today",
                   sum: cards.isEmpty ? "None" : total > 0 ? "\(SDF.kT(total)) to buy back" : (cards.count == 1 ? "1 leg" : "\(cards.count) legs"))
            ForEach(byName(cards, \.t), id: \.t) { g in
                VStack(alignment: .leading, spacing: 8) {
                    SDNameRow(t: g.t, name: board.label(g.t))
                    ForEach(Array(g.items.enumerated()), id: \.offset) { i, c in
                        SDExpCard(card: c, name: board.label(c.t), closeAt: board.closeAt).sdEnter(3, i)
                    }
                }
            }
            if cards.isEmpty { SDNone(text: "None today") }
        }
    }
}

struct SDExpCard: View {
    let card: SDBoard.ExpCard
    let name: String
    let closeAt: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SDClock(closeAt: closeAt)
            VStack(alignment: .leading, spacing: 2) {
                Text(SDF.contract(card.qty, card.strike, card.type)).sType(IncT.t(15, 20, 500)).foregroundStyle(SDC.ink)
                Text("\(SDF.md(card.expiry)) · \(name) \(SDF.money2(card.price))").sType(IncT.t(13, 17)).foregroundStyle(SDC.mu)
            }
            HStack(alignment: .center, spacing: 8) {
                if card.itm == true { Circle().fill(SDC.red).frame(width: 8, height: 8).accessibilityHidden(true) }
                Text(SDF.money2(card.distance)).sType(IncT.t(24, 28, 700, tr: -0.01)).foregroundStyle(SDC.ink)
                Text(card.itm == true ? "in the money" : "away" + (card.sd.map { " · \(SDF.sd($0)) SD" } ?? ""))
                    .sType(IncT.t(13, 16), tabular: false).foregroundStyle(SDC.mu)
            }
            if let line = card.line { priceLine(line) }
            VStack(alignment: .leading, spacing: 2) {
                Text("At the close").sType(IncT.t(13, 16), tabular: false).foregroundStyle(SDC.mu)
                Text(card.outcome ?? "").sType(IncT.t(15, 20, 500), tabular: false).foregroundStyle(SDC.ink)
                if let bb = card.buyBack, bb > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Buy back \(SDF.kC(bb))").sType(IncT.t(14, 19, 500)).foregroundStyle(SDC.ink)
                        Spacer(minLength: 0)
                        Text("Before \(SDF.t12(closeAt ?? "16:00"))").sType(IncT.t(13, 17), tabular: false).foregroundStyle(SDC.mu)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(SDC.l8).frame(height: 1) }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        .sdBox(16)
        .accessibilityElement(children: .combine)
    }

    /// The price line: a 2 pt grey track, the gap between price and strike in grey, the strike as a 2 pt orange tick
    /// with "$137" under it, the price as a 10 pt dot (line.lo to line.hi from the server).
    private func priceLine(_ l: SDBoard.Line) -> some View {
        GeometryReader { g in
            let w = g.size.width, span = max(0.0001, l.hi - l.lo)
            let kx = w * CGFloat(min(1, max(0, (card.strike - l.lo) / span)))
            let px = w * CGFloat(min(1, max(0, (card.price - l.lo) / span)))
            ZStack(alignment: .topLeading) {
                Capsule().fill(SDC.trk).frame(width: w, height: 2).offset(y: 6)
                Rectangle().fill(SDC.mu).frame(width: abs(kx - px), height: 2).offset(x: min(kx, px), y: 6)
                RoundedRectangle(cornerRadius: 1).fill(SDC.orange).frame(width: 2, height: 14).offset(x: kx - 1)
                Circle().fill(SDC.ink).frame(width: 10, height: 10).offset(x: px - 5, y: 2)
                Text("$\(SDF.strike(card.strike))").sType(IncT.t(12, 14)).foregroundStyle(SDC.mu).fixedSize()
                    .position(x: min(max(kx, 18), w - 18), y: 25)
            }
        }
        .frame(height: 32)
        .accessibilityHidden(true)
    }
}

/// A 16 pt ring that empties as the session runs out, with "0:14" (h:mm) and grey "to the close".
struct SDClock: View {
    let closeAt: String?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let close = SDF.todayAt(closeAt ?? "16:00", tl.date) ?? tl.date
            let secs = max(0, close.timeIntervalSince(tl.date)), mins = Int((secs / 60).rounded(.up))
            let session = SDF.hmParts(closeAt ?? "16:00").map { Double(($0.0 * 60 + $0.1) - 570) * 60 } ?? 23_400
            HStack(spacing: 8) {
                ZStack {
                    Circle().stroke(SDC.trk, lineWidth: 2)
                    Circle().trim(from: 0, to: CGFloat(min(1, secs / max(1, session))))
                        .stroke(SDC.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                }
                .frame(width: 12, height: 12).padding(2)
                Text("\(mins / 60):\(String(format: "%02d", mins % 60))").sType(IncT.t(15, 20, 500)).foregroundStyle(SDC.ink)
                Text("to the close").sType(IncT.t(13, 16), tabular: false).foregroundStyle(SDC.mu)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Banked this week (a stack a name)

struct SDBankedColumn: View {
    let board: SDBoard
    var body: some View {
        let groups = board.banked?.groups ?? []
        VStack(alignment: .leading, spacing: 12) {
            SDHead(title: "Banked this week", sum: groups.isEmpty ? "None" : SDF.signedT(board.banked?.total ?? 0))
            ForEach(Array(groups.enumerated()), id: \.element.t) { i, g in
                SDStack(group: g, name: board.label(g.t)).sdEnter(4, i)
            }
            if groups.isEmpty { SDNone(text: "None yet") }
        }
    }
}

/// Folded: the top card in full, the next two as edges 6 pt below at 95% and 90% and darker, text hidden; a grey
/// "3 legs" under it. A tap fans it out (each card its own row, 8 apart) and the label reads "Fold".
struct SDStack: View {
    let group: SDBoard.BankGroup
    let name: String
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var open = false
    @State private var pressed = false

    var body: some View {
        let n = group.legs.count
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                IncLogo(t: group.t, size: 24, ring: true)
                Text(name).sType(IncT.t(15, 20, 500), tabular: false).foregroundStyle(SDC.ink)
                Spacer(minLength: 8)
                Text(SDF.signedC(group.total)).sType(IncT.t(28, 32, 700, tr: -0.01).heroic).foregroundStyle(SDC.ink)
            }
            .padding(.horizontal, 2)
            .accessibilityElement(children: .combine)
            Button {
                withAnimation(reduce ? S.fade : .timingCurve(0.32, 0.72, 0, 1, duration: 0.45)) { open.toggle() }
            } label: {
                VStack(spacing: 0) {
                    ForEach(Array(group.legs.enumerated()), id: \.offset) { i, l in
                        card(l, i)
                            .zIndex(Double(10 - i))
                            .padding(.top, i == 0 ? 0 : open ? 8 : i < 3 ? -53 : -59)
                            .scaleEffect(open || i == 0 ? 1 : i == 1 ? 0.95 : 0.9, anchor: .bottom)
                            .opacity(open || i < 3 ? 1 : 0)
                    }
                }
                .scaleEffect(pressed && !reduce ? 0.99 : 1)
                .contentShape(.rect)
            }
            .buttonStyle(SDStackPress(pressed: $pressed))
            .accessibilityLabel("\(name), \(n == 1 ? "1 leg" : "\(n) legs")")
            .accessibilityHint(n > 1 ? (open ? "Folds the stack" : "Fans out the stack") : "")
            if n > 1 || open {
                Text(open ? "Fold" : "\(n) legs").sType(IncT.t(13, 16), tabular: false).foregroundStyle(SDC.mu).padding(.horizontal, 2)
            }
        }
    }

    private func card(_ l: SDBoard.BankLeg, _ i: Int) -> some View {
        let full = open || i == 0
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(SDF.contract(l.qty, l.strike, l.type)).sType(IncT.t(14, 19, 500)).foregroundStyle(SDC.ink).lineLimit(1)
                Spacer(minLength: 0)
                Text(SDF.signedC(l.kept)).sType(IncT.t(14, 19, 500)).foregroundStyle(SDC.ink)
            }
            Text("\(SDF.md(l.expiry)) · \(l.how)").sType(IncT.t(13, 17), tabular: false).foregroundStyle(SDC.mu)
        }
        .opacity(full ? 1 : 0)
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 11)
        .frame(maxWidth: .infinity, minHeight: 59, maxHeight: 59, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(full ? SDC.box : i == 1 ? SDC.e1 : SDC.e2))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(SDC.ring, lineWidth: 1))
    }
}

/// A press dips the stack 1% (README §2.5).
private struct SDStackPress: ButtonStyle {
    @Binding var pressed: Bool
    func makeBody(configuration c: Configuration) -> some View {
        c.label.onChange(of: c.isPressed) { _, p in withAnimation(.easeOut(duration: 0.25)) { pressed = p } }
    }
}
