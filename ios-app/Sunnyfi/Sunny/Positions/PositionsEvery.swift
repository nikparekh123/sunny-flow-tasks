//
//  PositionsEvery.swift
//  Sunny
//
//  Every leg on the phone is SunnyBook, tone calm (handoff 2026-11-24 §4; reference/SunnyBook.dc.html, phone; Nik,
//  round 196): it replaces the Nov 18 Every leg rows and their Whole book row.
//    The header "Every leg · N legs · N off", the whole book in a 2-column grid (So far, Theta a day, Delta, Nearest
//    call sold, Nearest put sold, To roll), Cards | List (remembered as sunny.book196p), the chips (every expiry, Calls
//    Puts Shares, Income Hedges Long; a chip changes only itself, filled on, outlined off) with Switch off all / on all,
//    then the legs.
//    Cards: a group an expiry ("Fri Nov 27", "3 days · 4 legs", "$X so far · $Y theta a day") with its switch and a fold,
//    then a card a leg, 2 a row: calls nearest first, today's price, puts nearest first. List: a group by what each leg
//    needs (In the money, Danger, Roll, Watch, Safe, Hedges, Shares), nearest the strike first.
//    No explanation or how-to lines anywhere (Nik, 24 Nov 2026): the design's hint under the chips, "calls above, puts
//    below" and the List groups' definitions are left out; labels, figures and statuses only.
//    Each leg: its status (Danger under 0.5 SD, Watch, Safe, Roll at 90% kept, In the money, Hedge), SD sold → now,
//    kept with its bar, breakeven under 0.5 SD, so far, theta, its own 51 × 31 switch (44 pt targets).
//    Calm: colour only on Danger, In the money, Roll and losses; legs with nothing to do read grey; the kept bar is grey
//    until 90%.
//  A leg counts when its own switch and each of its chips are on: those legs drive Payoff and the Greeks (the off set
//  goes to PosName.payoff; switches still flip PosName.offs's start: sold on, the rest off).
//  SD sold → now: the SD when sold is sunny-sd's sold[].z0 (the fill's own price, IV and days); now is Sold in SD's
//  (the leg's IV over the trading days left). A hedge reads its SD from today. Tried legs (PositionsTries) sit in their
//  expiry with "from Intelligence", a switch and ✕.
//  No em dashes in any words here; no minus signs (red alone says negative).
//

import SwiftUI

// MARK: - The model

struct PosEvery {
    enum Role: String { case inc, hed, lng }
    enum Status: String { case itm, dan, roll, wat, safe, hed, none }
    enum Own { case all, some, none }

    struct Leg: Identifiable, Hashable {
        let id: String
        /// The tried strike's id (payoff_tries), nil for a leg held.
        let tryID: String?
        /// "c", "p" or "s".
        let ty: String
        let K: Double, q: Double
        /// The expiry ("2026-11-27"), "" for shares.
        let iso: String
        let exLabel: String
        let role: Role
        /// Sold or bought at (a share; shares: the cost) and the mark now.
        let at: Double?, mk: Double?
        let sf: Double, dl: Double, th: Double
        /// SD room to the strike now and when sold (below 0: in the money).
        let sN: Double?, s0: Double?
        /// Kept % (sold only).
        let kp: Int?
        let be: Double?
        /// Its own switch, and whether it counts (its switch and every chip on).
        let own: Bool, eff: Bool
        let st: Status
        var sh: Bool { ty == "s" }
        var call: Bool { ty == "c" }
        var sold: Bool { role == .inc }
        /// Nothing to do: grey (calm).
        var quiet: Bool { st != .itm && st != .dan && st != .roll }
        var name: String { sh ? "Shares" : "\(PE.fk(K)) \(call ? "call" : "put")" }
        var count: String {
            if sh { return "\(PosFmt.count(q)) at \(PosFmt.price(at ?? 0))" }
            return (sold ? "Sold ×" : "Hedge ×") + PosFmt.count(q) + (tryID != nil ? " · from Intelligence" : "")
        }
    }
    enum Item: Identifiable { case leg(Leg), today(String)
        var id: String { switch self { case .leg(let l): l.id; case .today(let t): "today" + t } }
    }
    struct Group: Identifiable {
        let id: String
        let title: String
        let sub: String
        let items: [Item]
        let legs: [Leg]
        let sf: Double, th: Double, dl: Double
        let none: Bool
        let own: Own
        /// List: the title's colour (red In the money and Danger, green Roll).
        var tone: Status = .none
    }
    struct Chip: Identifiable, Hashable { let id: String; let label: String; let on: Bool }

    let legs: [Leg]
    let byExpiry: [Group]
    let byStatus: [Group]
    let chipRows: [[Chip]]
    /// The grid legs that do not count (Payoff's off set) and the tried legs that do.
    let offGrid: Set<String>
    let onTries: [PosTryLeg]
    let sfT: Double, thT: Double, dlT: Double
    let nearC: Leg?, nearP: Leg?
    let toRoll: Int
    var anyOn: Bool { legs.contains(where: \.eff) }
    var nOff: Int { legs.filter { !$0.eff }.count }
    /// The chips Switch off all turns off: every expiry and Shares (View by Expiry, the prototype's LIVE.all).
    var allOffChips: Set<String> { Set(chipRows.first?.filter { $0.id.hasPrefix("ex:") }.map(\.id) ?? []).union(legs.contains(where: \.sh) ? ["kind:s"] : []) }

    static func chipOff(_ l: (ty: String, iso: String, role: Role), _ chips: Set<String>) -> Bool {
        (l.ty != "s" && chips.contains("ex:" + l.iso)) || chips.contains("kind:" + l.ty) || chips.contains("role:" + l.role.rawValue)
    }

    /// `offs`: the legs switched off (PosName.offs); `chips`: the chips off; `sold`: this name's Sold in SD rows.
    static func build(_ m: PositionsModel, inputs: JSONValue?, offs: Set<String>, chips: Set<String>, sold: [PE.SoldRow],
                      tries: [PosTryLeg], S0: Double, today: String, mins: Int, closed: Set<String>) -> PosEvery {
        let src = inputs?["names"].array.first { $0["t"].string == m.t }
        var at: [String: Double] = [:], mark: [String: Double] = [:], ivs: [String: Double] = [:]
        for l in src?["legs"].array ?? [] {
            guard let k = l["k"].string else { continue }
            if let a = l["at"].double { at[k] = a }
            if let n = l["now"].double { mark[k] = n }
            if let v = l["iv"].double, v > 0.03 { ivs[k] = v }
        }
        let nameIV = src?["iv"].double ?? m.v
        let tt0 = m.stops.first?.tt ?? 0, ids = Set(m.legs.map(\.id))
        let t0 = PE.dayNum(today) ?? 0
        let label = { (iso: String) in PosFmt.expLabel(iso, daysOut: (PE.dayNum(iso) ?? t0) - t0) }
        func room(_ put: Bool, _ K: Double, _ iv: Double, _ iso: String) -> Double? {
            let mm = PE.sdMove(iv, PE.tradingDays(today, iso, closed: closed, mins: Double(mins)))
            guard mm > 0, K > 0, S0 > 0 else { return nil }
            return (put ? log(S0 / K) : log(K / S0)) / mm
        }
        func status(_ role: Role, _ sN: Double?, _ kp: Int?, itm: Bool) -> Status {
            switch role {
            case .lng: return .none
            case .hed: return .hed
            case .inc:
                guard let s = sN else { return itm ? .itm : .wat }
                return s < 0 ? .itm : s < 0.5 ? .dan : (kp ?? 0) >= 90 ? .roll : s < 1 ? .wat : .safe
            }
        }
        var legs: [Leg] = []
        for l in m.legs {
            let ty = l.ty == .shares ? "s" : l.ty == .put ? "p" : "c", put = ty == "p"
            let role: Role = ty == "s" ? .lng : l.q < 0 ? .inc : .hed
            let own = !offs.contains(l.id), eff = own && !chipOff((ty, l.iso, role), chips)
            if ty == "s" {
                legs.append(Leg(id: l.id, tryID: nil, ty: ty, K: l.K, q: l.q, iso: "", exLabel: "", role: role, at: l.K, mk: S0,
                                sf: l.q * (S0 - l.K), dl: l.q, th: 0, sN: nil, s0: nil, kp: nil, be: nil, own: own, eff: eff, st: .none))
                continue
            }
            let a = at[l.id], k = mark[l.id]
            let sf = a != nil && k != nil ? (k! - a!) * l.q * 100 : 0
            let th = m.greeks(m.S0, tt0, off: ids.subtracting([l.id])).th
            var sN: Double?, s0: Double?
            if role == .inc, let r = sold.first(where: { $0.l.put == put && abs($0.l.K - l.K) < 1e-6 && $0.l.ex == l.iso }) {
                sN = put ? -r.z : r.z
                s0 = r.l.z0.flatMap { $0.isFinite ? (put ? -$0 : $0) : nil }
            } else {
                sN = room(put, l.K, ivs[l.id] ?? nameIV, l.iso)
            }
            let kp: Int? = role == .inc && (a ?? 0) > 0 && k != nil ? Int(PE.jsRound((1 - k! / a!) * 100)) : nil
            let be: Double? = a.map { put ? l.K - $0 : l.K + $0 }
            let itm = put ? S0 < l.K : S0 > l.K
            legs.append(Leg(id: l.id, tryID: nil, ty: ty, K: l.K, q: l.q, iso: l.iso, exLabel: label(l.iso), role: role, at: a, mk: k,
                            sf: sf, dl: m.legDelta(l, m.S0, 0), th: th, sN: sN, s0: s0, kp: kp, be: be, own: own, eff: eff,
                            st: status(role, sN, kp, itm: itm)))
        }
        var onTries: [PosTryLeg] = []
        for x in tries {
            let role: Role = x.t.side == "s" ? .inc : .hed, own = x.t.on, eff = own && !chipOff((x.t.ty, x.t.ex, role), chips)
            if eff { onTries.append(x) }
            let g = x.greeks(m.S0, tt0), put = x.put
            let mm = PE.sdMove(x.iv, PE.tradingDays(today, x.t.ex, closed: closed, mins: Double(mins)))
            let sN: Double? = mm > 0 ? (put ? log(S0 / x.t.K) : log(x.t.K / S0)) / mm : nil
            legs.append(Leg(id: "try:" + x.t.id, tryID: x.t.id, ty: x.t.ty, K: x.t.K, q: x.q, iso: x.t.ex, exLabel: label(x.t.ex), role: role,
                            at: x.en, mk: x.en, sf: 0, dl: g.d, th: g.th, sN: sN, s0: sN, kp: role == .inc ? 0 : nil,
                            be: put ? x.t.K - x.en : x.t.K + x.en, own: own, eff: eff,
                            st: status(role, sN, role == .inc ? 0 : nil, itm: put ? S0 < x.t.K : S0 > x.t.K)))
        }

        func sums(_ ls: [Leg]) -> (Double, Double, Double) {
            let on = ls.filter(\.eff)
            return (on.reduce(0) { $0 + $1.sf }, on.reduce(0) { $0 + $1.th }, on.reduce(0) { $0 + $1.dl })
        }
        func own(_ ls: [Leg]) -> Own { let n = ls.filter(\.own).count; return n == ls.count ? .all : n == 0 ? .none : .some }
        let days = { (iso: String) -> Int in (PE.dayNum(iso) ?? t0) - t0 }
        let money = { (x: Double) in PosFmt.price(x).replacingOccurrences(of: "$", with: "") }

        // Cards: a group an expiry, soonest first, then the shares.
        let isos = Array(Set(legs.filter { !$0.sh }.map(\.iso))).sorted()
        var byEx: [Group] = isos.map { iso in
            let ls = legs.filter { !$0.sh && $0.iso == iso }
            let cs = ls.filter(\.call).sorted { $0.K < $1.K }, ps = ls.filter { $0.ty == "p" }.sorted { $0.K > $1.K }
            let d = days(iso), s = sums(ls)
            let title = PosFmt.dmd(iso) + (d > 183 ? " ’\(iso.prefix(4).suffix(2))" : "")
            let when = d <= 0 ? "today" : d == 1 ? "1 day" : "\(d) days"
            let today = "\(money(S0)) today"
            return Group(id: iso, title: title, sub: "\(when) · \(ls.count) \(ls.count == 1 ? "leg" : "legs")",
                         items: cs.map { .leg($0) } + [.today(today)] + ps.map { .leg($0) }, legs: cs + ps,
                         sf: s.0, th: s.1, dl: s.2, none: !ls.contains(where: \.eff), own: own(ls))
        }
        let shs = legs.filter(\.sh)
        if !shs.isEmpty {
            let s = sums(shs)
            byEx.append(Group(id: "none", title: "Shares", sub: "no expiry", items: shs.map { .leg($0) }, legs: shs,
                              sf: s.0, th: s.1, dl: s.2, none: !shs.contains(where: \.eff), own: own(shs)))
        }
        // List: by what each leg needs, nearest the strike first (Roll: most kept first).
        // No line explaining what a status means (Nik, 24 Nov 2026: no how-to copy on the face of a screen).
        let SG: [(Status, String, String)] = [(.itm, "In the money", ""), (.dan, "Danger", ""), (.roll, "Roll", ""), (.wat, "Watch", ""),
                                              (.safe, "Safe", ""), (.hed, "Hedges", ""), (.none, "Shares", "")]
        let byStatus: [Group] = SG.compactMap { st, t, s in
            let ls = legs.filter { $0.st == st }.sorted { a, b in
                st == .roll ? (a.kp ?? 0) > (b.kp ?? 0) : (a.sN ?? .infinity) < (b.sN ?? .infinity)
            }
            guard !ls.isEmpty else { return nil }
            let x = sums(ls)
            return Group(id: "L" + st.rawValue, title: "\(t) · \(ls.count)", sub: s, items: ls.map { .leg($0) }, legs: ls,
                         sf: x.0, th: x.1, dl: x.2, none: !ls.contains(where: \.eff), own: own(ls), tone: st)
        }
        // The chips: every expiry, then Calls, Puts, Shares, then Income, Hedges, Long (only what the name holds).
        let exChips = isos.map { Chip(id: "ex:" + $0, label: label($0), on: !chips.contains("ex:" + $0)) }
        let kinds = [("c", "Calls"), ("p", "Puts"), ("s", "Shares")].filter { k in legs.contains { $0.ty == k.0 } }
            .map { Chip(id: "kind:" + $0.0, label: $0.1, on: !chips.contains("kind:" + $0.0)) }
        let roles = [(Role.inc, "Income"), (.hed, "Hedges"), (.lng, "Long")].filter { r in legs.contains { $0.role == r.0 } }
            .map { Chip(id: "role:" + $0.0.rawValue, label: $0.1, on: !chips.contains("role:" + $0.0.rawValue)) }
        let all = sums(legs)
        let soldOn = legs.filter { $0.eff && $0.sold && $0.sN != nil }
        return PosEvery(legs: legs, byExpiry: byEx, byStatus: byStatus, chipRows: [exChips, kinds, roles].filter { !$0.isEmpty },
                        offGrid: Set(legs.filter { $0.tryID == nil && !$0.eff }.map(\.id)), onTries: onTries,
                        sfT: all.0, thT: all.1, dlT: all.2,
                        nearC: soldOn.filter(\.call).min { $0.sN! < $1.sN! }, nearP: soldOn.filter { !$0.call }.min { $0.sN! < $1.sN! },
                        toRoll: legs.filter { $0.eff && $0.st == .roll }.count)
    }
}

// MARK: - Colours (the design is dark; each is a light / dark pair)

enum PEC {
    static let ink = PC.ink
    static let mu = PC.mu
    /// Legs with nothing to do (#AEAEB2 dark, #8E8E93 light).
    static let quiet = S.dyn(0x8E8E93, 0xAEAEB2)
    /// Watch and Safe words (#8E8E93 dark).
    static let word = S.dyn(0x8E8E93, 0x8E8E93)
    static let red = PC.red, green = PC.green
    static let onColour = S.dyn(0xFFFFFF, 0x000000)
    static let track = S.dyn(0xE5E5EA, 0x2C2C2E)
    static let keptGrey = S.dyn(0xC7C7CC, 0x636366)
    static let dangerFill = S.dynA(0xBC2E30, 0.14, 0xFF6961, 0.18)
    static let hedgeRing = S.dynA(0x1D1D1F, 0.22, 0xFFFFFF, 0.22)
    static let tile = S.dynA(0xFFFFFF, 1, 0xFFFFFF, 0.04)
    static let tileRing = S.dynA(0x1D1D1F, 0.08, 0xFFFFFF, 0.08)
    static let rowRule = S.dynA(0x1D1D1F, 0.07, 0xFFFFFF, 0.06)
    static let groupRule = S.dynA(0x1D1D1F, 0.16, 0xFFFFFF, 0.16)
    static let switchOff = S.dynA(0x787880, 0.2, 0x787880, 0.32)
    static let chipRing = S.dynA(0x1D1D1F, 0.16, 0xFFFFFF, 0.16)
    static let chipSep = S.dynA(0x1D1D1F, 0.14, 0xFFFFFF, 0.14)
    static let segFill = S.dynA(0x1D1D1F, 0.05, 0xFFFFFF, 0.06)
}

// MARK: - The view

struct PosEveryBook: View {
    let t: String
    let m: PosEvery
    let privacy: Bool
    @Binding var look: String
    /// A group's fold, set by a tap ("tiles|Nov 27" → open); a group with nothing on starts folded.
    let folds: [String: Bool]
    let fold: (String, Bool) -> Void
    let toggle: (PosEvery.Leg) -> Void
    let setL: ([PosEvery.Leg], Bool) -> Void
    let chip: (String) -> Void
    let all: () -> Void
    let remove: (PosEvery.Leg) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var isList: Bool { look == "list" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Every leg").sType(PT.t(20, 26, 700), tabular: false).foregroundStyle(PEC.ink).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("\(m.legs.count) \(m.legs.count == 1 ? "leg" : "legs")" + (m.nOff > 0 ? " · \(m.nOff) off" : ""))
                    .sType(PT.t(13, 18), tabular: true).foregroundStyle(PEC.mu).lineLimit(1)
            }
            sums
            viewSwitch
            chips
            if isList {
                VStack(alignment: .leading, spacing: 18) { ForEach(m.byStatus) { listGroup($0) } }
            } else {
                VStack(alignment: .leading, spacing: 18) { ForEach(m.byExpiry) { cardGroup($0) } }
            }
        }
    }

    // MARK: The whole book

    private func km(_ v: Double) -> String { privacy ? BriefMask.shown : PosFmt.money(v) }
    private func dTx(_ v: Double) -> String { (v < 0 ? "short " : "long ") + PosFmt.count(v) }
    private func f2(_ x: Double) -> String { String(format: "%.2f", abs(x)) }
    /// Calm: a gain reads in ink, a loss red, nothing grey.
    private func cl(_ v: Double) -> Color { v >= 0.5 ? PEC.ink : v <= -0.5 ? PEC.red : PEC.mu }

    private var sums: some View {
        let near = { (l: PosEvery.Leg) in "\(PE.fk(l.K)) \(l.exLabel) · " + ((l.sN ?? 0) < 0 ? "in the money" : "\(f2(l.sN ?? 0)) SD") }
        var items: [(String, String, String, Color)] = [
            ("sf", "So far", km(m.sfT), cl(m.sfT)), ("th", "Theta a day", km(m.thT), cl(m.thT)), ("dl", "Delta", dTx(m.dlT), m.dlT < 0 ? PEC.red : PEC.ink)]
        if let c = m.nearC { items.append(("nc", "Nearest call sold", near(c), (c.sN ?? 0) < 0.5 ? PEC.red : PEC.ink)) }
        if let p = m.nearP { items.append(("np", "Nearest put sold", near(p), (p.sN ?? 0) < 0.5 ? PEC.red : PEC.ink)) }
        if m.toRoll > 0 { items.append(("nr", "To roll", "\(m.toRoll) at 90% kept", PEC.green)) }
        let rows = stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<min($0 + 2, items.count)]) }
        return Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 10) {
            ForEach(rows.indices, id: \.self) { i in
                GridRow {
                    ForEach(rows[i], id: \.0) { x in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(x.1.uppercased()).sType(PT.t(11, 14, 600, tr: 0.05), tabular: false).foregroundStyle(PEC.mu)
                            Text(x.2).sType(PT.t(15, 20, 700)).foregroundStyle(x.3).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(PosSay.words("\(x.1), \(x.2)"))
                    }
                    if rows[i].count == 1 { Color.clear.frame(height: 1) }
                }
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(PC.rule).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(PC.rule).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The whole \(t) book")
    }

    /// Cards | List: a pill on a faint track, the picked one white with black words (the design's phone views).
    private var viewSwitch: some View {
        HStack(spacing: 0) {
            ForEach([("tiles", "Cards"), ("list", "List")], id: \.0) { k, l in
                let on = (k == "list") == isList
                Button { withAnimation(S.moving(.easeOut(duration: 0.2), reduce) ?? .linear(duration: 0)) { look = k } } label: {
                    Text(l).sType(PT.t(14, 18, 600), tabular: false).foregroundStyle(on ? PC.onInk : PEC.ink)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background { if on { Capsule().fill(PEC.ink) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(2)
        .background(Capsule().fill(PEC.segFill))
        .overlay(Capsule().strokeBorder(PC.rule, lineWidth: 1))
        .sensoryFeedback(.selection, trigger: look)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View")
    }

    /// Every chip is its own switch (filled on, outlined off); a hairline between the rows; Switch off all at the end.
    private var chips: some View {
        PosFlow(column: 6, row: 0) {
            ForEach(Array(m.chipRows.enumerated()), id: \.offset) { i, row in
                if i > 0 { Rectangle().fill(PEC.chipSep).frame(width: 1, height: 20).padding(.horizontal, 4).frame(height: 44).accessibilityHidden(true) }
                ForEach(row) { c in
                    Button { chip(c.id) } label: {
                        Text(c.label).sType(PT.t(14, 18, 600), tabular: false).foregroundStyle(c.on ? PC.onInk : PC.quiet).lineLimit(1)
                            .padding(.horizontal, 13).frame(height: 34)
                            .background { Capsule().fill(c.on ? PEC.ink : .clear) }
                            .overlay { if !c.on { Capsule().strokeBorder(PEC.chipRing, lineWidth: 1) } }
                            .frame(height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(c.label)
                    .accessibilityValue(c.on ? "on" : "off")
                    .accessibilityHint(c.on ? "Switches its legs off" : "Switches its legs on")
                    .sensoryFeedback(.selection, trigger: c.on)
                }
            }
            Button(action: all) {
                Text(m.anyOn ? "Switch off all" : "Switch on all").sType(PT.t(14, 18, 600), tabular: false).foregroundStyle(PEC.ink).lineLimit(1)
                    .padding(.horizontal, 13).frame(height: 34)
                    .overlay { Capsule().strokeBorder(PEC.chipRing, lineWidth: 1) }
                    .frame(height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutValue(key: PosFlowEnd.self, value: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Switch legs on and off")
    }

    // MARK: Cards (a group an expiry, a card a leg, 2 a row)

    private func isOpen(_ g: PosEvery.Group, _ v: String) -> Bool { folds["\(v)|\(g.id)"] ?? !g.none }

    private func cardGroup(_ g: PosEvery.Group) -> some View {
        let open = isOpen(g, "tiles")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                PosSwitch(state: g.own, label: (g.own == .none ? "Switch on every leg in " : "Switch off every leg in ") + g.title) {
                    setL(g.legs, g.own == .none)
                }
                Button {
                    withAnimation(S.moving(.easeInOut(duration: 0.25), reduce) ?? .linear(duration: 0)) { fold("tiles|\(g.id)", !open) }
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(g.title).sType(PT.t(15, 20, 700), tabular: false).foregroundStyle(PEC.ink)
                            Text(g.sub).sType(PT.t(12, 16), tabular: true).foregroundStyle(PEC.mu).lineLimit(1)
                            groupLine(g)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(PEC.quiet)
                            .rotationEffect(.degrees(open ? 0 : -90))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(g.none ? 0.45 : 1)
                .accessibilityLabel(PosSay.words("\(g.title), \(g.sub)"))
                .accessibilityValue(open ? "open" : "folded")
                .accessibilityHint(open ? "Folds the group" : "Opens the group")
            }
            .padding(.top, 8)
            .overlay(alignment: .top) { Rectangle().fill(PEC.groupRule).frame(height: 1) }
            if open {
                Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(chunks(g.items), id: \.first!.id) { row in
                        if row.count == 1, case .today(let tx) = row[0] {
                            GridRow {
                                HStack(spacing: 8) {
                                    Text(tx).sType(PT.t(11, 14, 700), tabular: true).foregroundStyle(PEC.ink).lineLimit(1)
                                        .layoutPriority(1)
                                    Rectangle().fill(PEC.ink.opacity(0.4)).frame(minWidth: 12, maxWidth: .infinity).frame(height: 1)
                                }
                                .padding(.vertical, 2)
                                .gridCellColumns(2)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(PosSay.words(tx))
                            }
                        } else {
                            GridRow {
                                ForEach(row) { it in
                                    if case .leg(let l) = it { tile(l) }
                                }
                                if row.count == 1 { Color.clear.frame(height: 1) }
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    /// The legs two a row; today's line on its own row.
    private func chunks(_ items: [PosEvery.Item]) -> [[PosEvery.Item]] {
        var out: [[PosEvery.Item]] = [], cur: [PosEvery.Item] = []
        for it in items {
            if case .today = it { if !cur.isEmpty { out.append(cur); cur = [] }; out.append([it]); continue }
            cur.append(it)
            if cur.count == 2 { out.append(cur); cur = [] }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// "$X so far · $Y theta a day", each figure bold in its colour.
    private func groupLine(_ g: PosEvery.Group) -> some View {
        (Text(km(g.sf)).fontWeight(.bold).foregroundStyle(g.none ? PEC.mu : cl(g.sf)) + Text(" so far · ")
         + Text(km(g.th)).fontWeight(.bold).foregroundStyle(g.none ? PEC.mu : cl(g.th)) + Text(" theta a day"))
            .sType(PT.t(12, 16), tabular: true).foregroundStyle(PEC.mu).lineLimit(1).minimumScaleFactor(0.85)
    }

    // MARK: One leg

    private struct Look {
        let tx: Color, pill: (String, Color, Color, Color?)?, ring: Color, ringW: CGFloat
        let sdc: Color, arc: Color, sd0: String, sdN: String, bigN: String, bigU: String, bigL: String
        let px1: String, px2: String, px2c: Color, kw: Double, kbg: Color, sf: String, sfc: Color, ftV: String, ftL: String, ftc: Color
    }
    private func look(_ l: PosEvery.Leg) -> Look {
        let q = l.quiet, TX = q ? PEC.quiet : PEC.ink
        let qc = { (x: Double) -> Color in x <= -0.5 ? PEC.red : q ? TX : cl(x) }
        let pill: (String, Color, Color, Color?)? = switch l.st {
        case .itm: ("In the money", PEC.red, PEC.onColour, nil)
        case .dan: ("Danger", PEC.dangerFill, PEC.red, nil)
        case .wat: ("Watch", .clear, PEC.word, nil)
        case .safe: ("Safe", .clear, PEC.word, nil)
        case .roll: ("Roll", PEC.green, PEC.onColour, nil)
        case .hed: ("Hedge", .clear, PEC.mu, PEC.hedgeRing)
        case .none: nil
        }
        let ring: Color = l.st == .itm ? PEC.red : l.st == .dan ? PEC.red.opacity(0.6) : l.st == .roll ? PEC.green.opacity(0.65) : PEC.tileRing
        let sN = l.sN ?? 0, s0 = l.s0
        let dS = l.sold && s0 != nil ? Int(PE.jsRound(sN * 100)) - Int(PE.jsRound(s0! * 100)) : 0
        let gn = l.role == .hed && (l.at ?? 0) > 0 ? Int(PE.jsRound(((l.mk ?? 0) / l.at! - 1) * 100)) : 0
        let px2 = l.sold ? ((l.kp ?? 0) >= 0 ? "\(l.kp ?? 0)% kept" : "\(abs(l.kp ?? 0))% lost") : l.role == .hed ? "\(gn >= 0 ? "Up" : "Down") \(abs(gn))%" : ""
        let px1 = l.sh ? "\(PosFmt.price(l.at ?? 0)) → \(PosFmt.price(l.mk ?? 0))" : "\(f2(l.at ?? 0)) → \(f2(l.mk ?? 0))"
        let added = l.tryID != nil
        return Look(tx: TX, pill: pill, ring: ring, ringW: l.st == .itm ? 1.5 : 1,
                    sdc: l.sold && sN < 0.5 ? PEC.red : TX, arc: q ? PEC.mu : dS < 0 ? PEC.red : dS > 0 ? PEC.green : PEC.mu,
                    sd0: l.sold ? (s0.map { $0 < 0 ? "In the money" : f2($0) } ?? "") : "",
                    sdN: l.sh || l.sN == nil ? "" : sN < 0 ? "In the money" : "\(f2(sN)) SD",
                    bigN: l.sh ? PosFmt.price(l.mk ?? 0) : l.sN == nil ? "" : f2(sN), bigU: l.sh || l.sN == nil ? "" : sN < 0 ? "SD past" : "SD",
                    bigL: l.sh ? "price now" : l.sold ? (sN < 0.5 && l.be != nil ? "Breakeven \(f2(l.be!))" : "SD sold → now") : "SD from today",
                    px1: px1, px2: px2, px2c: (l.sold && (l.kp ?? 0) < 0) || (l.role == .hed && gn < 0) ? PEC.red : PEC.mu,
                    kw: Double(max(0, min(100, l.kp ?? 0))) / 100, kbg: (l.kp ?? 0) >= 90 ? PEC.green : PEC.keptGrey,
                    sf: added ? "new" : km(l.sf), sfc: added ? PEC.mu : qc(l.sf),
                    ftV: l.sh ? dTx(l.dl) : km(l.th), ftL: l.sh ? "Delta" : "Theta a day", ftc: l.sh ? TX : qc(l.th))
    }

    private func said(_ l: PosEvery.Leg, _ k: Look) -> String {
        var parts = [l.name, l.sh ? "" : l.exLabel, l.count, k.pill?.0 ?? ""]
        if l.sold { parts.append("sold at \(k.sd0.isEmpty ? "an SD not saved" : k.sd0 == "In the money" ? "in the money" : k.sd0 + " SD"), now \(k.sdN.lowercased())") }
        else if !k.sdN.isEmpty { parts.append(k.sdN) }
        parts += [k.px2, l.tryID != nil ? "new" : "\(l.sf < 0 ? "down" : "up") \(PosSay.money(l.sf, privacy)) so far", l.eff ? "" : "off"]
        return PosSay.words(parts.filter { !$0.isEmpty }.joined(separator: ", "))
    }

    private func pillView(_ p: (String, Color, Color, Color?)) -> some View {
        Text(p.0).sType(PT.t(11, 13, 700), tabular: false).foregroundStyle(p.2).lineLimit(1)
            .padding(.horizontal, 7).frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(p.1))
            .overlay { if let r = p.3 { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(r, lineWidth: 1) } }
            .fixedSize()
    }

    private func xButton(_ l: PosEvery.Leg) -> some View {
        Button { remove(l) } label: {
            Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(PEC.ink)
                .frame(width: 26, height: 26).background(Circle().fill(PC.closeFill))
                .frame(width: 34, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Take off \(l.name) \(l.exLabel), tried from Intelligence")
    }

    private func tile(_ l: PosEvery.Leg) -> some View {
        let k = look(l), op: Double = l.eff ? 1 : 0.4
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 4) {
                if let p = k.pill { pillView(p).opacity(op) }
                Spacer(minLength: 0)
                if l.tryID != nil { xButton(l) }
                PosSwitch(state: l.own ? .all : .none, label: (l.own ? "Switch off " : "Switch on ") + l.name + (l.sh ? "" : " " + l.exLabel)) { toggle(l) }
            }
            .padding(.trailing, -2)
            VStack(alignment: .leading, spacing: 1) {
                Text(l.name).sType(PT.t(15, 20, 700), tabular: true).foregroundStyle(k.tx).lineLimit(1)
                Text(l.count).sType(PT.t(12, 16), tabular: true).foregroundStyle(PEC.mu).fixedSize(horizontal: false, vertical: true)
            }
            .opacity(op)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if l.sold && !k.sd0.isEmpty {
                        Text(k.sd0).sType(PT.t(12, 16), tabular: true).foregroundStyle(PEC.mu)
                        Text("→").sType(PT.t(12, 16, 700), tabular: false).foregroundStyle(k.arc)
                    }
                    Text(k.bigN).sType(PT.t(22, 26, 700, tr: -0.01)).foregroundStyle(k.sdc)
                    Text(k.bigU).sType(PT.t(12, 16), tabular: false).foregroundStyle(PEC.mu)
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                Text(k.bigL).sType(PT.t(11, 14), tabular: true).foregroundStyle(PEC.mu).lineLimit(1).minimumScaleFactor(0.8)
            }
            .opacity(op)
            if !l.sh {
                VStack(alignment: .leading, spacing: 5) {
                    if l.sold {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(PEC.track)
                                Capsule().fill(k.kbg).frame(width: g.size.width * k.kw)
                            }
                        }
                        .frame(height: 4)
                        .accessibilityHidden(true)
                    }
                    (Text(k.px1).foregroundStyle(k.tx) + Text(k.px2.isEmpty ? "" : " · " + k.px2).foregroundStyle(k.px2c))
                        .sType(PT.t(12, 16), tabular: true).lineLimit(2).minimumScaleFactor(0.9).fixedSize(horizontal: false, vertical: true)
                }
                .opacity(op)
            }
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(k.sf).sType(PT.t(14, 18, 700)).foregroundStyle(k.sfc)
                    Text("So far").sType(PT.t(11, 14), tabular: false).foregroundStyle(PEC.mu)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(k.ftV).sType(PT.t(14, 18, 600)).foregroundStyle(k.ftc)
                    Text(k.ftL).sType(PT.t(11, 14), tabular: false).foregroundStyle(PEC.mu)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.top, 8)
            .overlay(alignment: .top) { Rectangle().fill(PEC.rowRule).frame(height: 1) }
            .opacity(op)
        }
        .padding(.top, 4).padding(.leading, 12).padding(.trailing, 10).padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PEC.tile))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(k.ring, lineWidth: k.ringW))
        .animation(S.moving(.easeOut(duration: 0.2), reduce), value: l.eff)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(said(l, k))
    }

    // MARK: List (by what each leg needs)

    private func listGroup(_ g: PosEvery.Group) -> some View {
        let tc: Color = g.none ? PEC.mu : g.tone == .itm || g.tone == .dan ? PEC.red : g.tone == .roll ? PEC.green : PEC.ink
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                PosSwitch(state: g.own, label: (g.own == .none ? "Switch on every leg in " : "Switch off every leg in ") + g.title) {
                    setL(g.legs, g.own == .none)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(g.title).sType(PT.t(15, 20, 700), tabular: true).foregroundStyle(tc)
                    if !g.sub.isEmpty { Text(g.sub).sType(PT.t(12, 16), tabular: false).foregroundStyle(PEC.mu).lineLimit(1) }
                    groupLine(g)
                }
                .opacity(g.none ? 0.45 : 1)
                .accessibilityElement(children: .combine)
            }
            VStack(spacing: 0) {
                ForEach(Array(g.legs.enumerated()), id: \.element.id) { i, l in
                    listRow(l).overlay(alignment: .top) { if i > 0 { Rectangle().fill(PEC.rowRule).frame(height: 1) } }
                }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(PEC.tile))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(PEC.tileRing, lineWidth: 1))
        }
    }

    private func listRow(_ l: PosEvery.Leg) -> some View {
        let k = look(l), op: Double = l.eff ? 1 : 0.4
        return HStack(alignment: .center, spacing: 10) {
            PosSwitch(state: l.own ? .all : .none, label: (l.own ? "Switch off " : "Switch on ") + l.name + (l.sh ? "" : " " + l.exLabel)) { toggle(l) }
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(l.name).sType(PT.t(15, 20, 600), tabular: true).foregroundStyle(k.tx)
                    Text(l.exLabel).sType(PT.t(12, 16), tabular: true).foregroundStyle(PEC.mu)
                }
                .lineLimit(1)
                let line = (k.sd0.isEmpty ? Text("") : Text(k.sd0 + " ").foregroundStyle(PEC.mu) + Text("→ ").fontWeight(.bold).foregroundStyle(k.arc))
                    + Text(k.sdN).fontWeight(.semibold).foregroundStyle(k.sdc)
                    + Text(k.px2.isEmpty ? "" : " · " + k.px2).foregroundStyle(k.px2c)
                if !(k.sdN.isEmpty && k.px2.isEmpty) { line.sType(PT.t(12, 16), tabular: true).lineLimit(2).minimumScaleFactor(0.9).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(op)
            if l.tryID != nil { xButton(l) }
            VStack(alignment: .trailing, spacing: 1) {
                Text(k.sf).sType(PT.t(15, 20, 700)).foregroundStyle(k.sfc)
                Text(l.tryID != nil ? (l.sold ? "Sold ×" : "Hedge ×") + PosFmt.count(l.q) : l.count).sType(PT.t(12, 16), tabular: true).foregroundStyle(PEC.mu)
            }
            .lineLimit(1)
            .opacity(op)
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .frame(minHeight: 60)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(said(l, k))
    }
}

// MARK: - The iOS switch (51 × 31, a 44 pt target; a group's switch can be part on)

struct PosSwitch: View {
    let state: PosEvery.Own
    let label: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                Capsule().fill(state == .all ? PEC.green : state == .some ? PEC.green.opacity(0.45) : PEC.switchOff)
                    .animation(.easeOut(duration: 0.25), value: state)
                Circle().fill(Color.white)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.04), lineWidth: 0.5))
                    .frame(width: 27, height: 27)
                    .offset(x: state == .all ? 22 : state == .some ? 12 : 2)
                    .animation(reduce ? nil : .timingCurve(0.34, 1.36, 0.64, 1, duration: 0.3), value: state)
            }
            .frame(width: 51, height: 31)
            .frame(width: 51, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: state)
        .accessibilityLabel(label)
        .accessibilityValue(state == .all ? "on" : state == .some ? "part on" : "off")
        .accessibilityAddTraits(.isToggle)
    }
}

// MARK: - A flow of chips; one marked PosFlowEnd sits at the right end of its line (the design's margin-left: auto)

struct PosFlowEnd: LayoutValueKey { static let defaultValue = false }

struct PosFlow: Layout {
    var column: CGFloat, row: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, h: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > w { y += h + row; x = 0; h = 0 }
            x += z.width + column; h = max(h, z.height); widest = max(widest, x - column)
        }
        return CGSize(width: w.isFinite ? w : widest, height: y + h)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, h: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > b.minX && x + z.width > b.maxX + 0.5 { y += h + row; x = b.minX; h = 0 }
            let end = s[PosFlowEnd.self]
            s.place(at: CGPoint(x: end ? b.maxX - z.width : x, y: y), proposal: ProposedViewSize(z))
            x += z.width + column; h = max(h, z.height)
        }
    }
}
