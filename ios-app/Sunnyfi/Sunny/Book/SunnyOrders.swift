//
//  SunnyOrders.swift
//  Sunny
//
//  Block 13e (handoff 32) · the To do face as this week's orders, in the order to place them, every number
//  from the week's plan (sunny-home: one hedge function for Gamma, To do and Δ Γ). Each order is its own box
//  with a status (To do, Done, Paused, Waiting, Skipped). There is no Mark done: an order clears once IBKR
//  shows the position. Before the sale, the ways are 124 pt tiles that scroll sideways; the wall chip opens
//  Gamma on that chain with the wall ringed.
//

import SwiftUI
import Supabase

struct POrder: Identifiable {
    enum Status: String { case todo = "To do", done = "Done", paused = "Paused", waiting = "Waiting", skipped = "Skipped" }
    enum Kind: String { case leaps, calls, hedge, insurance, puts }
    var id: String { kind.rawValue }
    let kind: Kind
    let status: Status
    let head: String
    let title: String
    let reason: String
    var note: String? = nil
    var wall: (k: Double, exp: String, text: String, call: Bool, label: String)? = nil
    /// A sale marked placed on the phone (the Sell button): Done until IBKR shows it, with an Undo.
    var undo = false
    /// The sale's "Done for this week" button, and its Undo once tapped (Nik, 26 Oct 2026).
    var finish = false
    var unfinish = false
}

enum POrders {
    /// The week's orders for a name, To do first, then Waiting, Done, Paused, Skipped.
    static func build(_ t: String, _ p: NamePlan, legs: [Leg], dg: DGBook?, earnings: String?, placed: String? = nil, done: Bool? = nil) -> [POrder] {
        var out: [POrder] = []
        /* Done for this week: the phone's own tap wins until the server's next run agrees (sale_done). */
        let finished = (done ?? p.sell.done ?? false) && p.earnings != true && p.sell.sold < p.sell.n
        let spot = dg?.px ?? 0
        let md = PF.monthDay(p.week)
        // 1 · The sale: one call per LEAPS, at the money.
        let atm = p.sell.ways.first { $0.id == "atm" }
        // 0 · A LEAPS under 0.70 delta rolls down, same expiry, to about 0.75 (Nik, 26 Oct 2026, option B).
        for r in p.leaps ?? [] {
            let e = "\(PF.monthDay(r.exp).prefix(3)) ’\(r.exp.dropFirst(2).prefix(2))", less = r.tv.old > 0 ? Int(((1 - r.tv.new / r.tv.old) * 100).rounded()) : 0
            out.append(POrder(kind: .leaps, status: .todo, head: "Roll · \(e) · LEAPS",
                              title: "Roll \(PWords.n(r.n, "\(e) \(PF.strike(r.from.k)) call")) down to \(PF.strike(r.to.k))",
                              reason: "Delta \(String(format: "%.2f", r.from.delta)), under 0.70. The \(PF.strike(r.to.k))s have delta \(String(format: "%.2f", r.to.delta)) and \(less)% less time value to decay. "
                                + "About \(PF.usd(r.debit)) to roll: sell the \(PF.strike(r.from.k))s near \(PF.price(r.from.mark)), buy the \(PF.strike(r.to.k))s near \(PF.price(r.to.mid)).",
                              note: "Same expiry. The \(PF.strike(r.from.k))s' loss is booked; the position is the same afterwards."))
        }
        // Marked placed with the Sell button (design 13e): the way picked, until IBKR shows the fill.
        let way = p.sell.left > 0 && p.earnings != true && !finished ? placed.flatMap { id in p.sell.ways.first { $0.id == id } } : nil
        if finished {
            let k = legs.filter { $0.side == "sold" && $0.type == "call" && $0.expiry == p.week }.map(\.strike).min()
            out.append(POrder(kind: .calls, status: .done, head: "Sell · \(md) calls",
                              title: p.sell.sold == 0 ? "No calls this week" : "\(p.sell.sold) of \(p.sell.n) sold" + (k.map { " at \(PF.strike($0))" } ?? ""),
                              reason: "Done for this week" + (p.sell.sold > 0 ? ", \(p.sell.n - p.sell.sold) fewer on purpose." : "."), unfinish: true))
        } else if p.earnings == true {
            out.append(POrder(kind: .calls, status: .skipped, head: "Sell · \(md) calls", title: "No calls this week",
                              reason: "Earnings land before the \(md) expiry, so no weeklies this week."))
        } else if let w = way {
            let at = w.legs.count == 1 ? " at \(PF.strike(w.legs[0].k))" : ", " + w.legs.map { "\($0.n) at \(PF.strike($0.k))" }.joined(separator: " and ")
            out.append(POrder(kind: .calls, status: .done, head: "Sell · \(md) calls", title: "\(p.sell.n) of \(p.sell.n) sold" + at,
                              reason: "About \(PF.usd(w.premium)) collected this week.", note: "Marked placed. It clears once IBKR shows the fill.", undo: true))
        } else if p.sell.left > 0 {
            let k = atm?.legs.first?.k
            out.append(POrder(kind: .calls, status: .todo, head: "Sell · \(md) calls · \(p.sell.sold) of \(p.sell.n) sold",
                              title: "Sell \(PWords.n(p.sell.left, "\(md) call"))", reason: "One per LEAPS. Pick how to sell them:",
                              wall: k.flatMap { k in p.sell.wall.map { (k, p.week, "\(PF.strike(k)) · \(md) \(rank($0.rank)) \($0.side) wall · \(GammaText.label($0.label))", $0.call, $0.label) } },
                              finish: true))
        } else if p.sell.sold > 0 {
            let sold = legs.filter { $0.side == "sold" && $0.type == "call" && $0.expiry == p.week }
            let k = sold.map(\.strike).min(), got = sold.reduce(0.0) { $0 + $1.avg * Double($1.n) * 100 }, nSold = sold.reduce(0) { $0 + $1.n }
            var r = (nSold > 0 ? "\(PF.usd(got / Double(nSold))) each, about " : "About ") + "\(PF.usd(got)) collected."
            // The wall at the strike sold, from the week's walls.
            if let k, let w = p.walls?.first(where: { $0.side == "call" && abs($0.k - k) < 1e-6 }) {
                r += " \(PF.strike(k)) is the \(rank(w.rank)) call wall, a \(GammaText.label(w.label))" + (spot > 0 ? " \(GammaText.vs(k, spot))" : "")
                    + (w.label == "ceiling" ? ", so rallies should stall there." : ".")
            }
            out.append(POrder(kind: .calls, status: .done, head: "Sell · \(md) calls", title: "\(p.sell.sold) of \(p.sell.n) sold" + (k.map { " at \(PF.strike($0))" } ?? ""),
                              reason: r, note: "Next sale Friday. You will choose ATM, slightly OTM or a split."))
        }
        // 2 · The hedge calls, sized by the one function.
        if let h = p.hedge {
            let mon = PF.monthDay(h.exp), chip = (h.k, h.exp, "\(PF.strike(h.k)) · \(GammaText.monthShort(h.exp)) · " + (h.pick == "sd" ? "nearest +\(F.trim(h.target.sd)) SD" : "1st call wall · " + (h.label.map(GammaText.label) ?? "OI only")), true, h.label ?? "unclear")
            let through = (h.target.pct.map { "+\(F.trim($0))% " } ?? "") + "(\(F.trim(h.target.sd)) SD)"
            if let w = way {
                // After the sale: the hedge sized for the way picked (design 13e: "Sized for the 12 you sold").
                let n = w.hedge ?? h.add
                if n > 0 {
                    out.append(POrder(kind: .hedge, status: .todo, head: "Buy · \(mon) · upside hedge", title: "Buy \(PWords.n(n, "\(mon) \(PF.strike(h.k)) call"))",
                                      reason: "Sized for the \(p.sell.left) you sold. About \(PF.usd(Double(n) * h.mid * 100)). Keeps you delta positive through \(through).",
                                      wall: chip))
                } else {
                    out.append(POrder(kind: .hedge, status: .done, head: "Buy · \(mon) · upside hedge", title: "Covered · \(h.held) \(mon) calls",
                                      reason: "Sized for the \(p.sell.left) you sold, no more calls are needed. Delta stays positive through \(through)."))
                }
            } else if (finished ? h.addNow ?? h.add : h.add) > 0 {
                // Done for this week: the calls needed with nothing more sold (the server's own figure once it agrees).
                let add = finished ? h.addNow ?? h.add : h.add, cost = finished ? Double(add) * h.mid * 100 : h.cost
                let safe = dg?.thin25.map { "You are safe only to +\(F.trim($0))% today. " } ?? ""
                // Before the sale the hedge waits only when its size depends on how the calls are sold (13e, Monday);
                // when every way needs the same calls it is To do now (Nik, 26 Oct 2026: NFLX said wait for nothing).
                let sizes = Set(p.sell.ways.compactMap(\.hedge))
                if p.sell.left > 0 && p.earnings != true && !finished && sizes.count > 1 {
                    let byWay = p.sell.ways.compactMap { w in w.hedge.map { "\(w.id == "atm" ? "ATM" : w.id == "otm" ? "slightly OTM" : "split") \($0)" } }.joined(separator: ", ")
                    out.append(POrder(kind: .hedge, status: .waiting, head: "Buy · \(mon) · upside hedge",
                                      title: "Buy \(PWords.n(h.add, "\(mon) \(PF.strike(h.k)) call")) after the sale",
                                      reason: "About \(PF.usd(h.cost)). The size depends on how you sell: \(byWay).", wall: chip))
                } else {
                    out.append(POrder(kind: .hedge, status: .todo, head: "Buy · \(mon) · upside hedge", title: "Buy \(PWords.n(add, "\(mon) \(PF.strike(h.k)) call"))",
                                      reason: "About \(PF.usd(cost))" + (h.weeks.map { ", or \(F.trim(($0 * 10).rounded() / 10)) weeks of premium" } ?? "") + ". "
                                        + safe + "This keeps you delta positive through " + (h.target.pct.map { "+\(F.trim($0))% " } ?? "") + "(\(F.trim(h.target.sd)) SD).",
                                      wall: chip))
                }
            } else if h.held > 0 {
                out.append(POrder(kind: .hedge, status: .done, head: "Buy · \(mon) · upside hedge", title: "Covered · \(h.held) \(mon) calls",
                                  reason: "Delta stays positive through " + (h.target.pct.map { "+\(F.trim($0))% " } ?? "") + "(\(F.trim(h.target.sd)) SD)."))
            }
        }
        // 3 · Insurance puts at the name's ratio (default 1:2).
        if let i = p.insurance, i.add > 0 {
            let mon = PF.monthDay(i.exp)
            let leaps = legs.filter { $0.side == "bought" && $0.type == "call" && !($0.up ?? false) }.reduce(0) { $0 + $1.n }
            let ks = Set(legs.filter { $0.side == "bought" && $0.type == "put" }.map(\.strike))
            let cover = i.held == 0 ? "No insurance yet: a fall has no cover."
                : "Your \(PWords.n(i.held, "put"))" + (ks.count == 1 ? " at \(PF.strike(ks.first!))" : "") + " cover only \(share(i.held, leaps)) of the LEAPS on a fall."
            let warn = i.warn ? " That is past 4 weeks of premium." : ""
            out.append(POrder(kind: .insurance, status: .todo, head: "Buy · \(mon) · insurance",
                              title: "Buy \(PWords.n(i.add, "\(mon) \(PF.strike(i.k)) put"))",
                              reason: "About \(PF.usd(i.cost ?? 0))" + (i.weeks.map { ", \(F.trim(($0 * 10).rounded() / 10)) weeks of premium" } ?? "") + ". " + cover + warn,
                              wall: (i.k, i.exp, "\(PF.strike(i.k)) · \(GammaText.monthShort(i.exp)) · " + (i.pick == "sd" ? "nearest 1.5 SD down" : "1st put wall · " + (i.label.map(GammaText.label) ?? "OI only")), false, i.label ?? "unclear")))
        }
        // 4 · Weekly puts: only above the 50-day, by the nearest put wall, never in an earnings week.
        if p.puts.cap > 0 || !p.puts.why.isEmpty {
            if p.puts.n > 0, let k = p.puts.k {
                out.append(POrder(kind: .puts, status: .todo, head: "Sell · \(md) puts", title: "Sell \(PWords.n(p.puts.n, "\(md) \(PF.strike(k)) put"))",
                                  reason: "Just above the " + (p.puts.wall.map { "\(PF.strike($0.k)) put wall" + ($0.label == "floor" ? ", a Floor" : "") } ?? "put wall") + (p.puts.half ? ". Half size: the wall is Unclear." : ".")
                                    + (p.puts.mid.map { " About \(PF.usd($0 * Double(p.puts.n) * 100)) credit." } ?? "")))
            } else if !p.puts.why.isEmpty && p.puts.cap + (p.puts.why.contains("earnings") ? 1 : 0) > 0 {
                var why: [String] = []
                if p.puts.why.contains("below50") { why.append("\(t) is below its 50-day" + (p.puts.s50.map { " (\(PF.price($0)))" } ?? "")) }
                if p.puts.why.contains("accelerator"), let w = p.puts.wall { why.append("the \(PF.strike(w.k)) put wall is an Accelerator, so a further drop can speed up") }
                if p.puts.why.contains("earnings") { why.append("it is an earnings week") }
                if p.puts.why.contains("nowall") { why.append("there is no put wall read yet") }
                out.append(POrder(kind: .puts, status: .paused, head: "Sell · \(md) puts", title: "No puts this week",
                                  reason: (why.joined(separator: ", and ") + ".").capitalizedFirst,
                                  note: "Resumes after a close above " + (p.puts.s50.map { PF.price($0) } ?? "the 50-day") + " with a Floor below price."))
            }
        }
        let order: [POrder.Status] = [.todo, .waiting, .done, .paused, .skipped]
        return out.sorted { (order.firstIndex(of: $0.status) ?? 9) < (order.firstIndex(of: $1.status) ?? 9) }
    }

    static func rank(_ r: Int) -> String { r == 1 ? "1st" : r == 2 ? "2nd" : "3rd" }
    private static func share(_ a: Int, _ b: Int) -> String {
        guard b > 0 else { return "none" }
        let f = Double(a) / Double(b)
        return f >= 0.95 ? "all" : f >= 0.62 ? "two thirds" : f >= 0.45 ? "half" : f >= 0.3 ? "a third" : f >= 0.2 ? "a quarter" : "a little"
    }
    /// The badge: orders still to place (To do and Waiting).
    static func count(_ os: [POrder]) -> Int { os.filter { $0.status == .todo || $0.status == .waiting }.count }
    /// Done for this week tapped on the phone: "T|week|1" (or "|0" after Undo), until the server's sale_done agrees.
    static let doneKey = "ordersSaleDone"
    /// Sales marked placed on the phone: "T|week|way" keys, cleared by Undo (and moot once IBKR shows the fill).
    static let placedKey = "ordersPlaced"
    static func placed(_ t: String, _ week: String) -> String? {
        (UserDefaults.standard.string(forKey: placedKey) ?? "").split(separator: ",").map(String.init)
            .first { $0.hasPrefix("\(t)|\(week)|") }.map { String($0.split(separator: "|").last ?? "") }
    }
    static func done(_ t: String, _ week: String) -> Bool? {
        (UserDefaults.standard.string(forKey: doneKey) ?? "").split(separator: ",").map(String.init)
            .first { $0.hasPrefix("\(t)|\(week)|") }.map { $0.hasSuffix("|1") }
    }
    /// Tell the server (sale_done, owner only), so Gamma, Insights and Δ Γ size the week the same way.
    static func markDone(_ t: String, _ week: String, _ on: Bool) async {
        struct Args: Encodable { let p_ticker: String; let p_week: String; let p_done: Bool }
        do { try await SupabaseService.client.rpc("mark_sale_done", params: Args(p_ticker: t, p_week: week, p_done: on)).execute() }
        catch { print("[POrders] mark_sale_done failed: \(error)") }
    }
}

extension GammaText {
    /// "Jan" from an ISO date.
    static func monthShort(_ iso: String) -> String { String(PF.monthDay(iso).prefix(3)) }
}

// MARK: - The face

struct POrdersFace: View {
    let t: String
    let p: NamePlan
    let n: PName
    let legs: [Leg]
    let earnings: String?
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce
    @AppStorage(POrders.doneKey) private var doneRaw = ""
    @AppStorage(POrders.placedKey) private var placedRaw = ""
    @State private var pick = "atm"
    /// The way marked placed with the Sell button this week, if any.
    private var placed: String? {
        placedRaw.split(separator: ",").map(String.init).first { $0.hasPrefix("\(t)|\(p.week)|") }.map { String($0.split(separator: "|").last ?? "") }
    }

    /// Done for this week as tapped on this phone (nil: the server decides).
    private var done: Bool? {
        doneRaw.split(separator: ",").map(String.init).first { $0.hasPrefix("\(t)|\(p.week)|") }.map { $0.hasSuffix("|1") }
    }

    var body: some View {
        let os = POrders.build(t, p, legs: legs, dg: n.dg, earnings: earnings, placed: placed, done: done)
        // No counts or re-check line on top (Nik, 26 Oct 2026): the orders, Watch this week, the footer.
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(os.enumerated()), id: \.element.id) { i, o in box(o, number: o.status == .todo || o.status == .waiting ? i + 1 : nil) }
            watch()
            Text("Orders clear on their own once IBKR shows the new position.")
                .sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: One order

    private func box(_ o: POrder, number: Int?) -> some View {
        let open = o.status == .todo
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                badge(o, number)
                Text(o.head).sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                Text(o.status.rawValue).sType(SType(size: 12, weight: 600, line: 12, tracking: 0), tabular: false)
                    .foregroundStyle(o.status == .todo ? S.orangeDeep : o.status == .done ? S.green : S.muted)
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(o.status == .todo ? S.orange.opacity(0.16) : o.status == .done ? S.green.opacity(0.14) : S.track))
            }
            Text(o.title).sType(SType(size: open ? 20 : 17, weight: open ? 700 : 600, line: open ? 24 : 22, tracking: 0)).foregroundStyle(S.ink)
                .fixedSize(horizontal: false, vertical: true)
            // No copy under the title (Nik, 26 Oct 2026: "they are getting too long"); reason and note stay for VoiceOver.
            if o.kind == .calls, o.status == .todo { ways() }
            if let w = o.wall, !(o.kind == .calls && o.status == .todo) { wallChip(w) }
            // No See Δ Γ or Skip this week (Nik, 26 Oct 2026); Done for this week on the sale.
            if o.finish || o.unfinish || o.undo {
                HStack(spacing: 8) {
                    if o.finish { pill("Done for this week") { setDone(true) } }
                    if o.unfinish { pill("Undo") { setDone(false) } }
                    if o.undo { pill("Undo") { setPlaced(nil) } }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(S.paper.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(open ? S.orange.opacity(0.7) : S.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityHint([o.reason, o.note ?? ""].filter { !$0.isEmpty }.joined(separator: " "))
    }

    @ViewBuilder private func badge(_ o: POrder, _ n: Int?) -> some View {
        switch o.status {
        case .todo:
            Text("\(n ?? 1)").sType(SType(size: 12, weight: 700, line: 12, tracking: 0)).foregroundStyle(S.badgeInk)
                .frame(width: 22, height: 22).background(Circle().fill(S.orange))
        case .done:
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(S.green)
                .frame(width: 22, height: 22).background(Circle().fill(S.green.opacity(0.14)))
        default:
            Image(systemName: o.status == .skipped ? "forward.end" : "pause").font(.system(size: 10, weight: .bold)).foregroundStyle(S.muted)
                .frame(width: 22, height: 22).background(Circle().fill(S.track))
        }
    }

    private func pill(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                .frame(maxWidth: .infinity).frame(height: 44).background(Capsule().fill(S.track)).contentShape(Capsule())
        }
        .buttonStyle(SPressStyle(scale: 0.97))
    }

    /// Mark this week's sale placed with a way, or clear it (Undo).
    private func setPlaced(_ way: String?) {
        var xs = placedRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("\(t)|\(p.week)|") }
        if let way { xs.append("\(t)|\(p.week)|\(way)") }
        UINotificationFeedbackGenerator().notificationOccurred(way == nil ? .warning : .success)
        withAnimation(reduce ? nil : S.standard(0.35)) { placedRaw = xs.joined(separator: ",") }
    }

    /// Done for this week, or its Undo: kept on the phone at once and sent to the server (owner only).
    private func setDone(_ on: Bool) {
        var xs = doneRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("\(t)|\(p.week)|") }
        xs.append("\(t)|\(p.week)|\(on ? 1 : 0)")
        UINotificationFeedbackGenerator().notificationOccurred(on ? .success : .warning)
        withAnimation(reduce ? nil : S.standard(0.35)) { doneRaw = xs.joined(separator: ",") }
        let t = t, week = p.week
        Task { await POrders.markDone(t, week, on) }
    }

    /// "110 · Jan 1st call wall · Ceiling": opens Gamma on that chain with the wall ringed (13e).
    private func wallChip(_ w: (k: Double, exp: String, text: String, call: Bool, label: String)) -> some View {
        Button { router.openGamma(t, view: w.exp, wall: w.k) } label: {
            HStack(spacing: 6) {
                Image(systemName: GammaText.icon(w.label, call: w.call)).font(.system(size: 10, weight: .bold))
                Text(w.text).sType(SType(size: 12, weight: 600, line: 16, tracking: 0), tabular: false).lineLimit(1)
            }
            .foregroundStyle(S.ink).padding(.horizontal, 10).frame(height: 28)
            .background(Capsule().fill(S.track))
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(POpacityPress())
        .accessibilityHint("Opens Gamma on this wall")
    }

    // MARK: Before the sale: the ways as tiles, the wall box, one Sell button

    private func ways() -> some View {
        let ws = p.sell.ways, cur = ws.first { $0.id == pick } ?? ws.first
        return VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(ws) { w in
                        Button { UISelectionFeedbackGenerator().selectionChanged(); withAnimation(reduce ? nil : S.standard(0.2)) { pick = w.id } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.id == "atm" ? "ATM" : w.id == "otm" ? "Slightly OTM" : "Split")
                                    .sType(SType(size: 11, weight: 600, line: 13, tracking: 0), tabular: false).foregroundStyle(S.muted)
                                Text(w.id == "split" ? w.legs.map { "\($0.n)" }.joined(separator: " + ") : PF.strike(w.legs.first?.k ?? 0))
                                    .sType(SType(size: 17, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink)
                                Text(w.id == "split" ? w.legs.map { PF.strike($0.k) }.joined(separator: " · ") : String(format: "%@%.1f%%", w.pct >= 0 ? "+" : "", w.pct))
                                    .sType(SType(size: 11, weight: 600, line: 13, tracking: 0)).foregroundStyle(S.muted)
                                Spacer(minLength: 0)
                                Text(PF.usd(w.premium)).sType(SType(size: 15, weight: 700, line: 18, tracking: 0)).foregroundStyle(S.ink)
                                Text("Hedge: " + (w.hedge.map { PWords.n($0, "call") } ?? "none")).sType(SType(size: 11, weight: 600, line: 13, tracking: 0)).foregroundStyle(S.muted)
                            }
                            .padding(.vertical, 12).padding(.horizontal, 14)
                            .frame(width: 124, height: 124, alignment: .topLeading)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(S.surface))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(w.id == pick ? S.ink : S.line, lineWidth: w.id == pick ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(w.id == pick ? [.isSelected, .isButton] : .isButton)
                    }
                }
                .scrollTargetLayout().padding(.vertical, 2)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            if let k = p.sell.ways.first(where: { $0.id == "atm" })?.legs.first?.k { wallBox(k) }
            if let cur {
                // Tapped once the order is placed in IBKR (the app never trades): the sale shows Done with an Undo and the
                // hedge, sized for this way, becomes To do (design 13e). IBKR's fill replaces it on the next sync.
                Button { setPlaced(cur.id) } label: {
                    Text("Sell \(cur.legs.reduce(0) { $0 + $1.n }) at " + cur.legs.map { PF.strike($0.k) }.joined(separator: " and "))
                        .sType(SType(size: 17, weight: 600, line: 22, tracking: 0), tabular: false).foregroundStyle(S.paper)
                        .frame(maxWidth: .infinity).frame(height: 50).background(Capsule().fill(S.ink)).contentShape(Capsule())
                }
                .buttonStyle(SPressStyle(scale: 0.97))
                .accessibilityHint("Marks the sale placed; the hedge for it becomes the next order")
            }
        }
    }

    private func wallBox(_ k: Double) -> some View {
        let w = p.sell.wall
        let head = w.map { "\(PF.strike(k)) is also the \(POrders.rank($0.rank)) \($0.side) wall · \(GammaText.label($0.label))" } ?? "\(PF.strike(k)) has no wall today"
        var body = p.sell.accel.map { "An Accelerator at \(PF.strike($0.k)) sits within a weekly SD above, so the hedge target rises to 2 SD. The sale still goes out full size." }
            ?? (w?.label == "ceiling" ? "Full size passes: the Ceiling sits at your strike and no Accelerator is above it." : "Full size: no Accelerator just above the strike.")
        if let a = p.sell.ways.first(where: { $0.id == "atm" }), let o = p.sell.ways.first(where: { $0.id == "otm" }), a.premium > o.premium {
            let extra = (a.hedge ?? 0) - (o.hedge ?? 0)
            body += " ATM pays \(PF.usd(a.premium - o.premium)) more a week than slightly OTM" + (extra > 0 ? " for \(PWords.n(extra, "extra hedge call"))." : ".")
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: GammaText.icon(w?.label ?? "unclear", call: true)).font(.system(size: 10, weight: .bold))
                Text(head).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false)
            }
            .foregroundStyle(S.ink)
            Text(body).sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(S.surface))
    }

    // MARK: Watch this week

    private func watch() -> some View {
        var rows: [(String, String)] = []
        let spot = n.px
        if let a = p.recheck.above, let w = p.walls?.first(where: { $0.side == "call" && abs($0.k - a) < 1e-6 }) {
            rows.append((PF.strike(a), "Call wall, \(GammaText.vs(a, spot)). " + (w.label == "ceiling" ? "A close over it means the Ceiling broke." : w.label == "accelerator" ? "A rally can speed up through it." : "No clear read.")))
        }
        if let b = p.recheck.below, let w = p.walls?.first(where: { $0.side == "put" && abs($0.k - b) < 1e-6 }) {
            rows.append((PF.strike(b), "\(POrders.rank(w.rank)) put wall, \(GammaText.vs(b, spot)). " + (w.label == "accelerator" ? "Drops can speed up under it." : w.label == "floor" ? "Drops should slow there." : "No clear read.")))
        }
        if let th = n.dg?.thin25 { rows.append(("+\(F.trim(th))%", "Where your delta turns thin" + ((p.hedge?.add ?? 0) > 0 ? " until the hedge is added." : "."))) }
        if let e = earnings { rows.append((PF.monthDay(e), "Earnings. No weeklies that week.")) }
        return Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Watch this week").sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    ForEach(rows, id: \.0) { r in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(r.0).sType(SType(size: 13, weight: 700, line: 18, tracking: 0)).foregroundStyle(S.ink).frame(width: 56, alignment: .leading)
                            Text(r.1).sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(S.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
        }
    }
}

extension String {
    func ifEmpty(_ s: String) -> String { isEmpty ? s : self }
}
