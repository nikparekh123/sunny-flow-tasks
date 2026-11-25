//
//  PositionsEvery.swift
//  Sunny
//
//  Every leg on the phone is SunnyBook, tone calm, List only (handoff 2026-11-24-final-2 §2.1; reference/SunnyBook.dc.html,
//  phone; Nik, 24 Nov 2026: "remove the card view from mobile"). A saved sunny.book196p is ignored; the web keeps Rows | List.
//    The header "Every leg · N legs · N off", the whole book in a 2-column grid (So far, Theta a day, Delta, Nearest
//    call sold, Nearest put sold, To roll), then the chips on three lines: (1) the expiries, (2) Calls, Puts, Shares,
//    (3) Sold, Bought (options only; Nik, 24 Nov 2026: never Long, Hedge or Income) with Switch off all (or on all) at
//    the right end. No dividers between chips; a line too long for the screen scrolls sideways with no scroll
//    indicator. A chip changes only itself (filled on, outlined off).
//    Then the legs, grouped by what each needs (In the money, Danger, Roll, Watch, Safe, Bought, Shares), nearest the
//    strike first.
//    No explanation or how-to lines anywhere (Nik, 24 Nov 2026): no hint under the chips and no definitions under the
//    groups; labels, figures and statuses only.
//    Each leg: SD sold → now with kept % (sold), the SD from today (bought), so far, the count, its own 51 × 31 switch
//    (44 pt targets). Calm: colour only on Danger, In the money, Roll and losses; legs with nothing to do read grey.
//  A leg counts when its own switch and each of its chips are on: those legs drive Payoff and the Greeks (the off set
//  goes to PosName.payoff; every leg starts on and a switch flips it, PosName.offs).
//  SD sold → now: the SD when sold is sunny-sd's sold[].z0 (the fill's own price, IV and days); now is Sold in SD's
//  (the leg's IV over the trading days left). A leg bought reads its SD from today. Tried legs (PositionsTries) sit in their
//  status group with "from Intelligence", a switch and ✕.
//  No em dashes in any words here; no minus signs (red alone says negative).
//

import SwiftUI

// MARK: - The model

struct PosEvery {
    /// Sold and Bought are options only; shares are their own (the Shares chip).
    enum Role: String { case sold, bought, shares }
    enum Status: String { case itm, dan, roll, wat, safe, bought, none }
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
        var sold: Bool { role == .sold }
        /// Nothing to do: grey (calm).
        var quiet: Bool { st != .itm && st != .dan && st != .roll }
        var name: String { sh ? "Shares" : "\(PE.fk(K)) \(call ? "call" : "put")" }
        var count: String {
            if sh { return "\(PosFmt.count(q)) at \(PosFmt.price(at ?? 0))" }
            return (sold ? "Sold ×" : "Bought ×") + PosFmt.count(q) + (tryID != nil ? " · from Intelligence" : "")
        }
    }
    struct Group: Identifiable {
        let id: String
        let title: String
        let sub: String
        let legs: [Leg]
        let sf: Double, th: Double, dl: Double
        let none: Bool
        let own: Own
        /// List: the title's colour (red In the money and Danger, green Roll).
        var tone: Status = .none
    }
    struct Chip: Identifiable, Hashable { let id: String; let label: String; let on: Bool }

    let legs: [Leg]
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
            case .shares: return .none
            case .bought: return .bought
            case .sold:
                guard let s = sN else { return itm ? .itm : .wat }
                return s < 0 ? .itm : s < 0.5 ? .dan : (kp ?? 0) >= 90 ? .roll : s < 1 ? .wat : .safe
            }
        }
        var legs: [Leg] = []
        for l in m.legs {
            let ty = l.ty == .shares ? "s" : l.ty == .put ? "p" : "c", put = ty == "p"
            let role: Role = ty == "s" ? .shares : l.q < 0 ? .sold : .bought
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
            if role == .sold, let r = sold.first(where: { $0.l.put == put && abs($0.l.K - l.K) < 1e-6 && $0.l.ex == l.iso }) {
                sN = put ? -r.z : r.z
                s0 = r.l.z0.flatMap { $0.isFinite ? (put ? -$0 : $0) : nil }
            } else {
                sN = room(put, l.K, ivs[l.id] ?? nameIV, l.iso)
            }
            let kp: Int? = role == .sold && (a ?? 0) > 0 && k != nil ? Int(PE.jsRound((1 - k! / a!) * 100)) : nil
            let be: Double? = a.map { put ? l.K - $0 : l.K + $0 }
            let itm = put ? S0 < l.K : S0 > l.K
            legs.append(Leg(id: l.id, tryID: nil, ty: ty, K: l.K, q: l.q, iso: l.iso, exLabel: label(l.iso), role: role, at: a, mk: k,
                            sf: sf, dl: m.legDelta(l, m.S0, 0), th: th, sN: sN, s0: s0, kp: kp, be: be, own: own, eff: eff,
                            st: status(role, sN, kp, itm: itm)))
        }
        var onTries: [PosTryLeg] = []
        for x in tries {
            let role: Role = x.t.side == "s" ? .sold : .bought, own = x.t.on, eff = own && !chipOff((x.t.ty, x.t.ex, role), chips)
            if eff { onTries.append(x) }
            let g = x.greeks(m.S0, tt0), put = x.put
            let mm = PE.sdMove(x.iv, PE.tradingDays(today, x.t.ex, closed: closed, mins: Double(mins)))
            let sN: Double? = mm > 0 ? (put ? log(S0 / x.t.K) : log(x.t.K / S0)) / mm : nil
            legs.append(Leg(id: "try:" + x.t.id, tryID: x.t.id, ty: x.t.ty, K: x.t.K, q: x.q, iso: x.t.ex, exLabel: label(x.t.ex), role: role,
                            at: x.en, mk: x.en, sf: 0, dl: g.d, th: g.th, sN: sN, s0: sN, kp: role == .sold ? 0 : nil,
                            be: put ? x.t.K - x.en : x.t.K + x.en, own: own, eff: eff,
                            st: status(role, sN, role == .sold ? 0 : nil, itm: put ? S0 < x.t.K : S0 > x.t.K)))
        }

        func sums(_ ls: [Leg]) -> (Double, Double, Double) {
            let on = ls.filter(\.eff)
            return (on.reduce(0) { $0 + $1.sf }, on.reduce(0) { $0 + $1.th }, on.reduce(0) { $0 + $1.dl })
        }
        func own(_ ls: [Leg]) -> Own { let n = ls.filter(\.own).count; return n == ls.count ? .all : n == 0 ? .none : .some }
        let isos = Array(Set(legs.filter { !$0.sh }.map(\.iso))).sorted()
        // List: by what each leg needs, nearest the strike first (Roll: most kept first).
        // No line explaining what a status means (Nik, 24 Nov 2026: no how-to copy on the face of a screen).
        let SG: [(Status, String, String)] = [(.itm, "In the money", ""), (.dan, "Danger", ""), (.roll, "Roll", ""), (.wat, "Watch", ""),
                                              (.safe, "Safe", ""), (.bought, "Bought", ""), (.none, "Shares", "")]
        let byStatus: [Group] = SG.compactMap { st, t, s in
            let ls = legs.filter { $0.st == st }.sorted { a, b in
                st == .roll ? (a.kp ?? 0) > (b.kp ?? 0) : (a.sN ?? .infinity) < (b.sN ?? .infinity)
            }
            guard !ls.isEmpty else { return nil }
            let x = sums(ls)
            return Group(id: "L" + st.rawValue, title: "\(t) · \(ls.count)", sub: s, legs: ls,
                         sf: x.0, th: x.1, dl: x.2, none: !ls.contains(where: \.eff), own: own(ls), tone: st)
        }
        // The chips: every expiry, then Calls, Puts, Shares, then Sold, Bought (only what the name holds).
        let exChips = isos.map { Chip(id: "ex:" + $0, label: label($0), on: !chips.contains("ex:" + $0)) }
        let kinds = [("c", "Calls"), ("p", "Puts"), ("s", "Shares")].filter { k in legs.contains { $0.ty == k.0 } }
            .map { Chip(id: "kind:" + $0.0, label: $0.1, on: !chips.contains("kind:" + $0.0)) }
        let roles = [(Role.sold, "Sold"), (.bought, "Bought")].filter { r in legs.contains { $0.role == r.0 } }
            .map { Chip(id: "role:" + $0.0.rawValue, label: $0.1, on: !chips.contains("role:" + $0.0.rawValue)) }
        let all = sums(legs)
        let soldOn = legs.filter { $0.eff && $0.sold && $0.sN != nil }
        return PosEvery(legs: legs, byStatus: byStatus, chipRows: [exChips, kinds, roles].filter { !$0.isEmpty },
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
    static let red = PC.red, green = PC.green
    static let tile = S.dynA(0xFFFFFF, 1, 0xFFFFFF, 0.04)
    static let tileRing = S.dynA(0x1D1D1F, 0.08, 0xFFFFFF, 0.08)
    static let rowRule = S.dynA(0x1D1D1F, 0.07, 0xFFFFFF, 0.06)
    static let switchOff = S.dynA(0x787880, 0.2, 0x787880, 0.32)
    static let chipRing = S.dynA(0x1D1D1F, 0.16, 0xFFFFFF, 0.16)
}

// MARK: - The view

struct PosEveryBook: View {
    let t: String
    let m: PosEvery
    let privacy: Bool
    let toggle: (PosEvery.Leg) -> Void
    let setL: ([PosEvery.Leg], Bool) -> Void
    let chip: (String) -> Void
    let all: () -> Void
    let remove: (PosEvery.Leg) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Every leg").sType(PT.t(20, 26, 700), tabular: false).foregroundStyle(PEC.ink).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Text("\(m.legs.count) \(m.legs.count == 1 ? "leg" : "legs")" + (m.nOff > 0 ? " · \(m.nOff) off" : ""))
                        .sType(PT.t(13, 18), tabular: true).foregroundStyle(PEC.mu).lineLimit(1)
                }
                sums
                chips
            }
            VStack(alignment: .leading, spacing: 18) { ForEach(m.byStatus) { listGroup($0) } }
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

    // MARK: The chips (handoff 2026-11-24-final-2 §2.1)

    /// Three lines: the expiries, then Calls Puts Shares, then Sold Bought with Switch off all at the right end of the
    /// last line. No dividers; each line scrolls sideways on its own when it runs past the screen (no indicator).
    private var chips: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(m.chipRows.enumerated()), id: \.offset) { i, row in
                HStack(alignment: .center, spacing: 6) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) { ForEach(row) { chipButton($0) } }
                            .padding(.horizontal, 2)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .padding(.horizontal, -2)
                    if i == m.chipRows.count - 1 { allButton }
                }
                .frame(height: 44)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Switch legs on and off")
    }

    private func chipButton(_ c: PosEvery.Chip) -> some View {
        Button { chip(c.id) } label: {
            Text(c.label).sType(PT.t(14, 18, 600), tabular: false).foregroundStyle(c.on ? PC.onInk : PC.quiet).lineLimit(1)
                .padding(.horizontal, 13).frame(height: 34)
                .background { Capsule().fill(c.on ? PEC.ink : .clear) }
                .overlay { if !c.on { Capsule().strokeBorder(PEC.chipRing, lineWidth: 1) } }
                .frame(height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(c.label)
        .accessibilityValue(c.on ? "on" : "off")
        .accessibilityHint(c.on ? "Switches its legs off" : "Switches its legs on")
        .sensoryFeedback(.selection, trigger: c.on)
    }

    private var allButton: some View {
        Button(action: all) {
            Text(m.anyOn ? "Switch off all" : "Switch on all").sType(PT.t(14, 18, 600), tabular: false).foregroundStyle(PEC.ink).lineLimit(1)
                .padding(.horizontal, 13).frame(height: 34)
                .overlay { Capsule().strokeBorder(PEC.chipRing, lineWidth: 1) }
                .frame(height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    // MARK: One leg

    /// A leg's colours and words (calm: grey when it has nothing to do).
    private struct Look {
        let tx: Color, word: String, sdc: Color, arc: Color, sd0: String, sdN: String
        let px2: String, px2c: Color, sf: String, sfc: Color
    }
    private func look(_ l: PosEvery.Leg) -> Look {
        let q = l.quiet, TX = q ? PEC.quiet : PEC.ink
        let qc = { (x: Double) -> Color in x <= -0.5 ? PEC.red : q ? TX : cl(x) }
        let word: String = switch l.st {
        case .itm: "In the money"
        case .dan: "Danger"
        case .wat: "Watch"
        case .safe: "Safe"
        case .roll: "Roll"
        case .bought: "Bought"
        case .none: ""
        }
        let sN = l.sN ?? 0, s0 = l.s0
        let dS = l.sold && s0 != nil ? Int(PE.jsRound(sN * 100)) - Int(PE.jsRound(s0! * 100)) : 0
        let gn = l.role == .bought && (l.at ?? 0) > 0 ? Int(PE.jsRound(((l.mk ?? 0) / l.at! - 1) * 100)) : 0
        let px2 = l.sold ? ((l.kp ?? 0) >= 0 ? "\(l.kp ?? 0)% kept" : "\(abs(l.kp ?? 0))% lost") : l.role == .bought ? "\(gn >= 0 ? "Up" : "Down") \(abs(gn))%" : ""
        let added = l.tryID != nil
        return Look(tx: TX, word: word,
                    sdc: l.sold && sN < 0.5 ? PEC.red : TX, arc: q ? PEC.mu : dS < 0 ? PEC.red : dS > 0 ? PEC.green : PEC.mu,
                    sd0: l.sold ? (s0.map { $0 < 0 ? "In the money" : f2($0) } ?? "") : "",
                    sdN: l.sh || l.sN == nil ? "" : sN < 0 ? "In the money" : "\(f2(sN)) SD",
                    px2: px2, px2c: (l.sold && (l.kp ?? 0) < 0) || (l.role == .bought && gn < 0) ? PEC.red : PEC.mu,
                    sf: added ? "new" : km(l.sf), sfc: added ? PEC.mu : qc(l.sf))
    }

    private func said(_ l: PosEvery.Leg, _ k: Look) -> String {
        var parts = [l.name, l.sh ? "" : l.exLabel, l.count, k.word]
        if l.sold { parts.append("sold at \(k.sd0.isEmpty ? "an SD not saved" : k.sd0 == "In the money" ? "in the money" : k.sd0 + " SD"), now \(k.sdN.lowercased())") }
        else if !k.sdN.isEmpty { parts.append(k.sdN) }
        parts += [k.px2, l.tryID != nil ? "new" : "\(l.sf < 0 ? "down" : "up") \(PosSay.money(l.sf, privacy)) so far", l.eff ? "" : "off"]
        return PosSay.words(parts.filter { !$0.isEmpty }.joined(separator: ", "))
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

    /// "$X so far · $Y theta a day", each figure bold in its colour.
    private func groupLine(_ g: PosEvery.Group) -> some View {
        (Text(km(g.sf)).fontWeight(.bold).foregroundStyle(g.none ? PEC.mu : cl(g.sf)) + Text(" so far · ")
         + Text(km(g.th)).fontWeight(.bold).foregroundStyle(g.none ? PEC.mu : cl(g.th)) + Text(" theta a day"))
            .sType(PT.t(12, 16), tabular: true).foregroundStyle(PEC.mu).lineLimit(1).minimumScaleFactor(0.85)
    }

    // MARK: The list (by what each leg needs)

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
                Text(l.tryID != nil ? (l.sold ? "Sold ×" : "Bought ×") + PosFmt.count(l.q) : l.count).sType(PT.t(12, 16), tabular: true).foregroundStyle(PEC.mu)
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
