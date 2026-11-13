//
//  PositionsIntelModel.swift
//  Sunny
//
//  Intelligence for this week on the phone (handoff 2026-11-13-positions §3.9; App Explorations 154a, view only), from
//  the name's sunny-sd reply. Ported from the web's src/web/positions/intel.ts (levelsOf, alertsOf, intelModel) and
//  Lanes.tsx (each lane's three boxes and the pop-ups, which on the phone open in place under the boxes), with the
//  phone's differences:
//    - this week's expiry only (D1: this Friday's, or the first after it);
//    - the read is about what you sold for that expiry (the lowest call and the highest put sold), at the Held lane's
//      chance; with nothing sold, the read uses the rule's strikes as the web does with nothing picked (D6);
//    - Held only, no New or Both; Held counts only legs sold for that exact expiry (§3.9.5 zone rule);
//    - "past 4 SD" for a breakeven past the lane's grid (D3).
//  Touched and closed come only from the server's `day` block (no estimated wick). Premiums Rich / Fair / Cheap are the
//  engine's own IV verdict (calc()'s signal), as the web.
//  No em dashes in any words here.
//

import Foundation

/// A colour role; the view picks the colour for light or dark.
nonisolated enum PTone: Equatable { case ink, mu, muT, quiet, green, red, orange, touched, ceiling, floor, teal, teal2, sd(Int) }

struct PosIntel {
    /// A gamma wall with its size and how sure (nil: not sent).
    struct Wall: Equatable { let kind: String; let K: Double; let gex: Double; let conf: Int? }
    struct Levels {
        var pe = PE.Levels()
        var flip: Double? = nil
        var walls: [Wall] = []
        var zones: [SDReply.Tech.Zone] = []
        func wall(_ k: String) -> Wall? { walls.first { $0.kind == k } }
    }
    struct Alert: Identifiable { let id: String; let state: PE.LevelState; let text: String }
    /// A box under a lane: a label (with a wall icon or a dot), one number and a short line; a tap opens its detail.
    struct Box: Identifiable {
        enum Icon { case ceiling, floor, flip }
        let id: String
        let label: String
        var icon: Icon? = nil
        var dot: PTone? = nil
        let value: String
        var valueTone: PTone = .ink
        var sub: String = ""
        var subTone: PTone = .quiet
        /// The sub line carries book money (masked with privacy on).
        var subMoney = false
        var detail: Detail? = nil
    }
    /// A box's detail, in place under the boxes (the web's pop-up): title, the value, the rows, one sentence.
    struct Detail {
        struct Row: Identifiable { var id: String { l }; let l: String; let v: String; var tone: PTone = .ink; var money = false }
        let title: String; let value: String; let dot: PTone; let rows: [Row]; let say: String
    }

    let t: String
    let S: Double
    let m: Double
    let ex: String
    let label: String
    let long: String
    let cd: Double
    let td: Double
    let kind: String
    let earnIn: Bool
    let exDivIn: Bool
    let lv: Levels
    let day: PE.Day?
    var alerts: [Alert]
    let held: [PE.ShortLeg]
    let LH: PE.Lane
    let move: PE.Move?
    let ivK: [(K: Double, v: Double)]
    let ivNow: Double
    let ivRank: Double?
    let ivTone: PE.IVTone?
    let hv20: Double?
    let rsi: Double?
    let hasTech: Bool
    let read: (lead: String, rest: String)
    /// "what you sold" or "the rule's strikes".
    let readOn: String
    let scale: PE.Scale
    var boxes: (iv: [Box], sd: [Box], gamma: [Box]?, tech: [Box]?, move: [Box]?, held: [Box]?)

    var sub: String { "\(long) · \(cd <= 0 ? "ends today" : cd == 1 ? "1 day" : "\(Int(cd)) days") · \(kind)" }
    func state(_ L: Double?) -> PE.LevelState { PE.levelState(L, day) }

    // MARK: Build

    /// `friday` is this Friday (Home's brief); `walls` the name's per-expiry walls from Home (brief_inputs), used when the
    /// reply sends no gamma for the expiry.
    static func build(_ d: SDReply, friday: String, walls: JSONValue?) -> PosIntel? {
        guard d.ok != false, !d.exps.isEmpty,
              let ex = PE.openExpiry(d.exps.map(\.ex), friday: friday, today: MarketClock.ny(Date()).date), let e = d.exps.first(where: { $0.ex == ex }) else { return nil }
        let S = d.price, m = e.m, today = d.today ?? ""
        let held: [PE.ShortLeg] = d.sold.filter { $0.ex == e.ex && $0.got != nil && $0.n > 0 }.map { PE.ShortLeg(put: $0.put, K: $0.K, n: $0.n, p: $0.got!) }
        let LH = PE.lane(held, S, m)
        let lv = levelsOf(d, e, walls)
        let day = d.day.map { PE.Day(prev: $0.prev, high: $0.high, low: $0.low, last: $0.last, closedToday: $0.closedToday, close: $0.close) }
        let move = (d.closes ?? []).isEmpty ? nil : PE.moveOf(d.closes!.map { PE.Close(d: $0.d, c: $0.c) }, S, today, e.iv, e.td ?? 0, m)
        // The premiums' verdict: the engine's own (calc(): the 30-day IV's rank over a year and its ratio to HV20).
        let sigIv = e.sig?.first { $0.key == "iv" }?.v
        let tone: PE.IVTone? = sigIv == "Rich" ? .rich : sigIv == "Cheap" ? .cheap : sigIv == "None" ? .fair
            : PE.ivTone(e.iv, low52: d.tech?.ivLow52, high52: d.tech?.ivHigh52, rank: d.tech?.ivRank, hv20: d.tech?.hv20, has: d.tech != nil).tone
        let rank = d.tech?.ivRank.map(PE.jsRound)
        let exDiv = d.events?.exDiv, exDivIn = exDiv.map { $0 >= today && $0 <= e.ex } ?? false
        let earn = e.earn ?? false

        // The read (§3.9.4): what is sold for this expiry; with nothing sold, the rule's strikes at the rule's counts.
        let hc = held.filter { !$0.put }.min { $0.K < $1.K }, hp = held.filter(\.put).max { $0.K < $1.K }
        let pace: Double? = move?.pace.flatMap { $0.flat ? nil : $0.to }
        let read: (lead: String, rest: String), readOn: String, Kread: [Double]
        let k2 = { (K: Double) in Double(PE.num(abs(PE.zOf(K, S, m)), 2)) ?? 0 }
        if hc != nil || hp != nil {
            read = PE.theRead(PE.ReadIn(S0: S, step: PE.stepOf(S), call: hc.map { PE.ReadSide(K: $0.K, k: k2($0.K)) }, put: hp.map { PE.ReadSide(K: $0.K, k: k2($0.K)) },
                                        levels: lv.pe, uncovered: 0, newCalls: 0, earnings: earn, dividend: exDivIn, pace: pace,
                                        odds: LH.has ? LH.cp : nil, tone: tone))
            readOn = "what you sold"; Kread = []
        } else {
            // The web's defaults with nothing picked: calls to the room the shares and OTM calls leave after what is
            // already sold at this expiry or later, puts the reply's count.
            let rc = e.sug.call, rp = e.sug.put
            let heldC = d.sold.filter { !$0.put && $0.ex >= e.ex }.reduce(0) { $0 + $1.n }
            let cap = d.cover.map { ($0.shares / 100).rounded(.down) + $0.otm.filter { $0.ex >= e.ex }.reduce(0) { $0 + $1.n } } ?? Double(d.counts.calls)
            let nC = max(0, min(999, cap - heldC)), nP = max(0, min(999, Double(d.counts.puts)))
            var nw: [PE.ShortLeg] = []
            if nC > 0 { nw.append(PE.ShortLeg(put: false, K: rc.K, n: nC, p: rc.pr)) }
            if nP > 0 { nw.append(PE.ShortLeg(put: true, K: rp.K, n: nP, p: rp.pr)) }
            let LN = PE.lane(nw, S, m)
            let cov = d.cover.map { c in
                PE.coverCheck(shares: c.shares, held: d.sold.filter { !$0.put }.map { (K: $0.K, n: $0.n, ex: $0.ex) },
                              otm: c.otm.map { (n: $0.n, ex: $0.ex) }, sale: nC > 0 ? (K: rc.K, n: nC) : nil, ex: e.ex)
            }
            let both0 = nC == 0 && nP == 0
            read = PE.theRead(PE.ReadIn(S0: S, step: PE.stepOf(S), call: nC > 0 || both0 ? PE.ReadSide(K: rc.K, k: e.sug.kc) : nil,
                                        put: nP > 0 || both0 ? PE.ReadSide(K: rp.K, k: e.sug.kp) : nil, levels: lv.pe,
                                        uncovered: cov?.uncovered ?? 0, newCalls: nC, earnings: earn, dividend: exDivIn, pace: pace,
                                        odds: LN.has ? LN.cp : nil, tone: tone))
            readOn = "the rule’s strikes"; Kread = [rc.K, rp.K]
        }
        let scale = PE.priceScale(S, m, [lv.pe.ceiling, lv.pe.floor, lv.pe.accelerator, lv.flip, lv.pe.support, lv.pe.resistance,
                                        lv.pe.sma20, lv.pe.sma50, lv.pe.sma100, lv.pe.sma200] + Kread.map { Optional($0) }
                                        + held.map { Optional($0.K) } + [LH.dn, LH.up])
        let ivK = (e.ivK ?? []).compactMap { p -> (K: Double, v: Double)? in p.count >= 2 && p[0] > 0 && p[1] > 0 ? (p[0], p[1]) : nil }.sorted { $0.K < $1.K }
        var me = PosIntel(t: d.t, S: S, m: m, ex: e.ex, label: e.label, long: e.long ?? PosFmt.dmd(e.ex), cd: e.cd, td: e.td ?? 0,
                          kind: PE.expiryKind(e.ex, earnings: earn), earnIn: earn, exDivIn: exDivIn, lv: lv, day: day, alerts: [],
                          held: held, LH: LH, move: move, ivK: ivK, ivNow: e.iv, ivRank: rank, ivTone: tone, hv20: d.tech?.hv20,
                          rsi: d.tech?.rsi14, hasTech: d.tech != nil, read: read, readOn: readOn, scale: scale,
                          boxes: ([], [], nil, nil, nil, nil))
        me.alerts = me.alertsOf()
        me.boxes = me.makeBoxes(d)
        return me
    }

    /// The levels at this expiry (intel.ts levelsOf): the gamma walls (the reply's, else Home's per-expiry walls), the
    /// nearest support under the price and resistance over it (their middles), the averages.
    static func levelsOf(_ d: SDReply, _ e: SDReply.Exp, _ homeWalls: JSONValue?) -> Levels {
        let S = d.price
        var lv = Levels()
        if let g = e.gamma {
            lv.flip = g.flip
            for kind in ["ceiling", "floor", "accelerator"] {
                let ws = g.walls.enumerated().filter { $0.element.kind == kind }
                    .sorted { abs($0.element.gex) != abs($1.element.gex) ? abs($0.element.gex) > abs($1.element.gex) : $0.offset < $1.offset }
                if let w = ws.first?.element { lv.walls.append(Wall(kind: kind, K: w.K, gex: abs(w.gex), conf: w.conf)) }
            }
        } else if let c = homeWalls?.array.first(where: { $0["ex"].string == e.ex }) {
            lv.flip = c["flip"].double
            if let k = c["c"]["k"].double { lv.walls.append(Wall(kind: "ceiling", K: k, gex: abs(c["c"]["gex"].double ?? 0), conf: nil)) }
            if let k = c["f"]["k"].double { lv.walls.append(Wall(kind: "floor", K: k, gex: abs(c["f"]["gex"].double ?? 0), conf: nil)) }
            if let k = c["a"]["k"].double, !(c["f"]["k"].double == k) {
                lv.walls.append(Wall(kind: "accelerator", K: k, gex: abs(c["a"]["gex"].double ?? 0), conf: nil))
            }
        }
        let zones = d.tech?.zones ?? []
        lv.zones = zones
        let sup = zones.filter { $0.kind == "support" && $0.mid < S }.max { $0.mid < $1.mid }
        let res = zones.filter { $0.kind == "resistance" && $0.mid > S }.min { $0.mid < $1.mid }
        let t = d.tech
        lv.pe = PE.Levels(ceiling: lv.wall("ceiling")?.K, floor: lv.wall("floor")?.K, accelerator: lv.wall("accelerator")?.K,
                          resistance: res?.mid, support: sup?.mid, sma20: t?.sma20, sma50: t?.sma50, sma100: t?.sma100, sma200: t?.sma200)
        return lv
    }

    /// Today's alerts (§3.9.2, intel.ts alertsOf): closed through first, then touched.
    func alertsOf() -> [Alert] {
        let all: [(String, String, Double?, Bool)] = [
            ("ce", "Ceiling", lv.pe.ceiling, true), ("fl", "Floor", lv.pe.floor, true), ("fp", "Flip", lv.flip, true), ("ac", "Accelerator", lv.pe.accelerator, true),
            ("su", "Support", lv.pe.support, false), ("re", "Resistance", lv.pe.resistance, false),
            ("m20", "20-day", lv.pe.sma20, false), ("m50", "50-day", lv.pe.sma50, false), ("m100", "100-day", lv.pe.sma100, false), ("m200", "200-day", lv.pe.sma200, false)]
        let hit = all.compactMap { k, name, L, w -> (String, String, Double, Bool, PE.LevelState)? in
            guard let L, L.isFinite else { return nil }
            let s = state(L)
            return s == .idle ? nil : (k, name, L, w, s)
        }
        let sorted = hit.enumerated().sorted { p, q in
            let a = p.element.4 == .touch ? 1 : 0, b = q.element.4 == .touch ? 1 : 0
            return a != b ? a < b : p.offset < q.offset
        }.map(\.element)
        return sorted.map { k, name, L, w, s in
            let closed = s != .touch
            let v = w && k != "fp" ? PE.num(L, 2) : String(format: "%.2f", L)
            return Alert(id: k, state: s, text: "\(closed ? (s == .up ? "↑ " : "↓ ") : "")\(name) \(v) · \(closed ? (s == .up ? "closed above" : "closed below") : "touched")")
        }
    }

    // MARK: The boxes and their details (Lanes.tsx, the phone's 154a)

    static let stateWords: [PE.LevelState: String] = [.idle: "not reached today", .touch: "touched today", .up: "closed above today", .dn: "closed below today"]
    private static func pc1(_ x: Double) -> String { String(format: "%.1f", abs(x) * 100) + "%" }
    private static func arw(_ r: Double) -> String { (r < 0 ? "↓" : "↑") + pc1(r) }
    private static func dots(_ c: Int?) -> String { c.map { String(repeating: "●", count: $0) + String(repeating: "○", count: max(0, 3 - $0)) } ?? "" }
    private static func conf(_ c: Int?) -> String { c.map { ["", "low", "medium", "high"][max(0, min(3, $0))] } ?? "not sent" }
    static func rsiWord(_ r: Double) -> String { r <= 30 ? "oversold" : r >= 70 ? "overbought" : "neutral" }
    private func sdz(_ x: Double) -> String { String(format: "%.1f", abs(PE.zOf(x, S, m))) + " SD" }
    private func dist(_ x: Double) -> String { "\(x >= S ? "↑" : "↓")\(Self.pc1(x / S - 1)) · \(sdz(x))" }
    private func todayRow(_ s: PE.LevelState) -> Detail.Row {
        Detail.Row(l: "Today", v: (Self.stateWords[s] ?? "").replacingOccurrences(of: " today", with: ""), tone: s == .touch ? .touched : s == .idle ? .muT : .ink)
    }
    private func stateSub(_ s: PE.LevelState) -> PTone { s == .touch ? .touched : s == .idle ? .quiet : .ink }
    private func wkSd(_ r: Double, _ iv: Double) -> String { iv > 0 ? String(format: "%.1f", abs(log(r)) / (iv * (5.0 / 252).squareRoot())) + " SD" : "-" }

    private func makeBoxes(_ d: SDReply) -> (iv: [Box], sd: [Box], gamma: [Box]?, tech: [Box]?, move: [Box]?, held: [Box]?) {
        // IV
        let iv: [Box] = [
            Box(id: "ivn", label: "IV now", value: Self.pc1(ivNow), sub: earnIn ? "earnings \(d.events?.earnings.map(PosFmt.md) ?? "before expiry")" : "at the money",
                subTone: earnIn ? .orange : .quiet),
            Box(id: "ivr", label: "IV rank", value: ivRank.map { String(Int($0)) } ?? "-", sub: ivRank != nil ? "of 100, past year" : "not sent yet"),
            Box(id: "ivh", label: "vs HV20", value: ivTone == .rich ? "Rich" : ivTone == .cheap ? "Cheap" : ivTone == .fair ? "Fair" : "-",
                sub: hv20.map { "HV20 \(Self.pc1($0))" } ?? "not sent yet"),
        ]
        // SD (nothing picked on the phone)
        let lo1 = PE.atSd(S, -1, m), hi1 = PE.atSd(S, 1, m)
        let sd: [Box] = [
            Box(id: "lo", label: "1 SD low", value: PE.f2(lo1), sub: "↓\(Self.pc1(m))"),
            Box(id: "hi", label: "1 SD high", value: PE.f2(hi1), sub: "↑\(Self.pc1(m))"),
            Box(id: "mv", label: "Move by \(label)", value: "±\(Self.pc1(m))", sub: "1 SD"),
        ]
        // Gamma Exposure
        let ce = lv.wall("ceiling"), fl = lv.wall("floor"), ac = lv.wall("accelerator"), flip = lv.flip
        func wPop(_ kind: String, _ x: Double, _ g: Double?, _ c: Int?, _ dc: PTone, _ say: String) -> Detail {
            var rows = [Detail.Row(l: "From today", v: dist(x))]
            if let g { rows.append(.init(l: kind == "Ceiling" ? "Call gamma" : kind == "Floor" ? "Put gamma" : "Gamma", v: PosFmt.money(g))) }
            if kind != "Flip" && kind != "Accelerator" { rows.append(.init(l: "How sure", v: c != nil ? "\(Self.dots(c)) \(Self.conf(c))" : Self.conf(c))) }
            if kind == "Flip" { rows.append(.init(l: "Now", v: S >= x ? "above it, calmer" : "below it, choppier")) }
            rows.append(todayRow(state(x)))
            return Detail(title: kind, value: kind == "Flip" ? PE.f2(x) : PE.num(x, 2), dot: dc, rows: rows, say: say)
        }
        func wBox(_ k: String, _ l: String, _ w: Wall?, _ icon: Box.Icon, _ dc: PTone, _ say: String) -> Box {
            guard let w else { return Box(id: k, label: l, icon: icon, value: "none", valueTone: .muT) }
            let s = state(w.K)
            return Box(id: k, label: l, icon: icon, value: PE.num(w.K, 2), sub: s != .idle ? Self.stateWords[s]! : "\(PosFmt.money(w.gex))\(w.conf != nil ? " " + Self.dots(w.conf) : "")",
                       subTone: stateSub(s), detail: wPop(l, w.K, w.gex, w.conf, dc, say))
        }
        let hasW = !lv.walls.isEmpty || flip != nil
        var gamma: [Box]? = nil
        if hasW {
            var fb = Box(id: "fp", label: "Flip", icon: .flip, value: "none", valueTone: .muT)
            if let flip {
                let s = state(flip)
                fb = Box(id: "fp", label: "Flip", icon: .flip, value: PE.f2(flip), sub: s != .idle ? Self.stateWords[s]! : "calmer above", subTone: stateSub(s),
                         detail: wPop("Flip", flip, nil, nil, .orange, "Where dealer gamma turns over. Above it moves get damped, below it they get bigger."))
            }
            gamma = [
                wBox("ce", "Ceiling", ce, .ceiling, .ceiling, "The strike with the most call gamma for \(label). Dealers sell into rallies here, so the price tends to stall under it."),
                wBox("fl", "Floor", fl, .floor, .floor, "The strike with the most put gamma for \(label). Dealers buy into dips here, so the price tends to hold above it."),
                fb,
            ]
            _ = ac
        }
        // Technicals
        var tech: [Box]? = nil
        if hasTech {
            func zone(_ x: Double?, kind: String) -> SDReply.Tech.Zone? { x.flatMap { m0 in lv.zones.first { $0.kind == kind && abs($0.mid - m0) < 1e-9 } } }
            func zBox(_ k: String, _ l: String, _ x: Double?, kind: String) -> Box {
                guard let x else { return Box(id: k, label: l, dot: .teal2, value: "none", valueTone: .muT) }
                let s = state(x), z = zone(x, kind: kind)
                var rows: [Detail.Row] = []
                if let z { rows.append(.init(l: "Zone", v: "\(PE.f2(z.lo)) to \(PE.f2(z.hi))")) }
                rows.append(.init(l: "From today", v: dist(x)))
                if let z { let n = Int(z.strength); rows.append(.init(l: "Turned there", v: "\(n) \(n == 1 ? "time" : "times")")) }
                if let r = rsi { rows.append(.init(l: "RSI", v: "\(Int(PE.jsRound(r))), \(Self.rsiWord(r))")) }
                rows.append(todayRow(s))
                return Box(id: k, label: l, dot: .teal2, value: PE.f2(x), sub: s != .idle ? Self.stateWords[s]! : sdz(x), subTone: stateSub(s),
                           detail: Detail(title: l, value: PE.f2(x), dot: .teal2, rows: rows,
                                          say: k == "su" ? "Where buying has turned the price up before." : "Where selling has turned the price down before."))
            }
            let third: Box = exDivIn && d.events?.exDiv != nil
                ? Box(id: "xd", label: "Ex-dividend", value: PosFmt.md(d.events!.exDiv!), valueTone: .orange, sub: "early assignment")
                : Box(id: "rsi", label: "RSI", value: rsi.map { String(Int(PE.jsRound($0))) } ?? "-", sub: rsi.map { Self.rsiWord($0) } ?? "not sent yet")
            tech = [zBox("su", "Support", lv.pe.support, kind: "support"), zBox("re", "Resistance", lv.pe.resistance, kind: "resistance"), third]
        }
        // Move
        var mvb: [Box]? = nil
        if let mo = move {
            var b: [Box] = []
            if let lw = mo.lw {
                b.append(Box(id: "lw", label: "Last week", value: Self.arw(lw.r), valueTone: lw.r < 0 ? .red : .green, sub: "closed \(PE.f2(lw.to))",
                             detail: Detail(title: "Last week", value: Self.arw(lw.r), dot: lw.r < 0 ? .red : .green,
                                            rows: [.init(l: PosFmt.dmd(lw.fromD), v: PE.f2(lw.from)), .init(l: PosFmt.dmd(lw.toD), v: PE.f2(lw.to)),
                                                   .init(l: "Move", v: Self.arw(lw.r), tone: lw.r < 0 ? .red : .green), .init(l: "In SD", v: wkSd(lw.to / lw.from, ivNow)),
                                                   .init(l: "Range of closes", v: "\(PE.f2(lw.lo)) to \(PE.f2(lw.hi))")],
                                            say: "Close to close, against a one-week SD at today’s IV.")))
            } else { b.append(Box(id: "lw", label: "Last week", value: "-", valueTone: .muT)) }
            if let tw = mo.tw {
                b.append(Box(id: "tw", label: "This week", value: Self.arw(tw.r), valueTone: tw.r < 0 ? .red : .green, sub: "since Fri · \(String(format: "%.1f", tw.sd)) SD",
                             detail: Detail(title: "This week", value: Self.arw(tw.r), dot: tw.r < 0 ? .red : .green,
                                            rows: [.init(l: "Fri close", v: PE.f2(tw.from)), .init(l: "Today", v: PE.f2(S)),
                                                   .init(l: "Move", v: Self.arw(tw.r), tone: tw.r < 0 ? .red : .green), .init(l: "In SD", v: String(format: "%.1f", tw.sd) + " SD")],
                                            say: "Friday’s close to today.")))
            } else { b.append(Box(id: "tw", label: "This week", value: "-", valueTone: .muT)) }
            if let p = mo.pace {
                let word = p.flat ? "Flat" : p.r5 < 0 ? "Falling" : "Rising", tn: PTone = p.flat ? .muT : p.r5 < 0 ? .red : .green
                var rows = [Detail.Row(l: "5-day", v: Self.arw(p.r5), tone: p.r5 < 0 ? .red : .green)]
                if let r20 = p.r20 { rows.append(.init(l: "20-day", v: Self.arw(r20), tone: r20 < 0 ? .red : .green)) }
                if let r = rsi { rows.append(.init(l: "RSI", v: "\(Int(PE.jsRound(r))), \(Self.rsiWord(r))")) }
                rows.append(.init(l: "By \(label)", v: PE.f2(p.to) + (p.capped ? ", capped" : "")))
                b.append(Box(id: "mo", label: "Momentum", value: word, valueTone: p.flat ? .ink : p.r5 < 0 ? .red : .green, sub: "5-day \(Self.arw(p.r5))",
                             detail: Detail(title: "Momentum", value: word, dot: tn, rows: rows,
                                            say: "Where the price lands by \(label) if the last 5 days’ pace holds. A guide, not a forecast.")))
            } else { b.append(Box(id: "mo", label: "Momentum", value: "-", valueTone: .muT)) }
            mvb = b
        }
        // Held
        var hb: [Box]? = nil
        if LH.has {
            let L = LH, ab = L.callsAlone != nil && L.putsAlone != nil
            let beT = { (x: Double) in "\(x >= self.S ? "↑" : "↓")\(Self.pc1(x / self.S - 1)) · \(String(format: "%.2f", abs(PE.zOf(x, self.S, self.m)))) SD" }
            let sdd = { (a1: Double, a0: Double) in "+" + String(format: "%.2f", abs(PE.crossAdds(a1, a0, self.S, self.m))) + " SD" }
            let sides = [L.calls > 0 ? "\(Int(L.calls)) \(L.calls == 1 ? "call" : "calls")" : "", L.puts > 0 ? "\(Int(L.puts)) \(L.puts == 1 ? "put" : "puts")" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
            let base: [Detail.Row] = [.init(l: "Sold", v: sides), .init(l: "Premium", v: PosFmt.money(L.inc), money: true), .init(l: "Chance of profit", v: Self.pc1(L.cp))]
            func beBox(_ k: String, _ x: Double?, dn: Bool) -> Box {
                let l = "Breakeven \(dn ? "down" : "up")"
                if L.none { return Box(id: k, label: l, value: "none", valueTone: .muT) }
                guard let x else { return Box(id: k, label: l, value: "past 4 SD", valueTone: .muT) }
                var rows = [Detail.Row(l: "From today", v: beT(x))]
                if ab {
                    let alone = dn ? L.putsAlone! : L.callsAlone!
                    rows += [.init(l: dn ? "Puts alone" : "Calls alone", v: "\(PE.f2(alone)) · \(sdz(alone))"), .init(l: "The cross adds", v: sdd(x, alone))]
                }
                rows += base
                let say = ab ? (dn ? "The puts break even here with the calls’ premium on top. Alone they would at \(PE.f2(L.putsAlone!))."
                                   : "The calls break even here with the puts’ premium on top. Alone they would at \(PE.f2(L.callsAlone!)).")
                    : "One side only, so no cross."
                return Box(id: k, label: l, value: PE.f2(x), sub: dist(x),
                           detail: Detail(title: "Held · \(l.lowercased())", value: PE.f2(x), dot: .sd(PE.sdLevel(abs(PE.zOf(x, S, m)))), rows: rows, say: say))
            }
            hb = [beBox("lo", L.dn, dn: true),
                  Box(id: "cp", label: "Chance of profit", value: L.none ? "0.0%" : Self.pc1(L.cp), sub: "\(PosFmt.money(L.inc)) premium", subMoney: true),
                  beBox("hi", L.up, dn: false)]
        }
        return (iv, sd, gamma, tech, mvb, hb)
    }
}
