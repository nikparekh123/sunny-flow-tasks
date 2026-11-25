//
//  IncCalModel.swift
//  Sunny
//
//  The Income calendar's words (handoff 2026-11-24 late §1.3; SunnyIncomeCal.dc.html renderVals, the app's props:
//  narrow, view m, views m, quiet fold). Four weeks Mon to Fri from this week's Monday. For All and for each name:
//  what each day holds (one name: a tile a rung; All: a line a name, the quiet ones folded into one grey line), the
//  compact cell's word or % and its count, the dashed day where the next rung lands, and the status line's count.
//  Built once per build with IncModel (BriefState.setIncome), never in a body.
//
//  A strike is never invented: a next rung without a listed strike shows no strike (no next tile on its day; a roll
//  reads "Roll to Dec 7" without one). No em dashes, no minus signs in any words here.
//

import Foundation

nonisolated struct IncCal: Hashable {
    /// A weekday in the four weeks.
    struct Day: Identifiable, Hashable {
        let id: Int
        let iso: String
        let w: Int
        /// Mon 0 to Fri 4.
        let d: Int
        /// The pill: "Nov 23" on the first Monday and on a Monday in a month's first week, else "24".
        let pill: String
        /// Over the open day: "Tue Nov 24 · today".
        let title: String
        let today: Bool
        let past: Bool
        /// A market holiday (the server's calendar).
        let closed: Bool
    }
    enum Ring: Hashable { case itm, act, run }
    /// A rung on its day (one name): strike ×count, the big % kept, the action, one grey line.
    struct Leg: Identifiable, Hashable {
        let id: String
        let lab: String
        let big: String
        /// "kept" | "lost".
        let bw: String
        let tone: IncTone
        let act: String?
        let sub: String?
        let ring: Ring
        let rank: Int
        let kp: Int
        /// "167.5 call ×3".
        let nm: String
        /// All's word: "In the money" | "Roll" | "73%".
        let word: String
        /// The compact cell's word: "ITM" | "Roll" | "73%".
        let short: String
        let speech: String
    }
    /// A name on its day (All): logo, ticker, the word; the strike and action in grey under it. A tap opens the name.
    struct Row: Identifiable, Hashable {
        var id: String { t }
        let t: String
        let tTone: IncTone
        let word: String
        let wTone: IncTone
        let why: String
        let rank: Int
        let kp: Int
        let speech: String
    }
    /// The dashed box: where the next rung lands.
    struct Next: Identifiable, Hashable { let id: String; let top: String; let main: String }
    /// What a day holds (opened under its week) and its compact cell.
    struct Box: Hashable {
        var legs: [Leg] = []
        var rows: [Row] = []
        var more: String?
        var nx: [Next] = []
        /// The cell: the big word or count, its colour, the small word under it.
        var big = ""
        var bigTone: IncTone = .mu
        var sm = ""
        var dashed = false
        var filled = false
        var empty: Bool { legs.isEmpty && rows.isEmpty && nx.isEmpty && more == nil }
        var speech = ""
    }
    struct Status: Hashable {
        /// How many need you (in the money + ready to roll); 0 reads "All quiet".
        let need: Int
        let tone: IncTone
        let word: String
        /// "1 in the money · 1 to roll", or "Nearest roll · NKE 36 call at 73%".
        let sub: String
    }
    struct Scope: Hashable { let boxes: [Box]; let status: Status }

    let days: [Day]
    /// "Nov 23 to Dec 18" and "4 weeks · today Tue Nov 24".
    let range: String
    let rangeSub: String
    let all: Scope
    let by: [String: Scope]

    func scope(_ t: String?) -> Scope { t.flatMap { by[$0] } ?? all }

    // MARK: - Build

    private static let DN = ["Mon", "Tue", "Wed", "Thu", "Fri"]
    private static let MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    static func build(today: String, rungs: [IncRung], names: [IncName], closed: Set<String>) -> IncCal {
        // The four weeks from this week's Monday (a weekend opens on next week, as the server's calendar).
        let t0 = Ymd(today) ?? Ymd.now
        let wd = t0.weekday   // 1 Sun ... 7 Sat
        let mon0 = t0.adding(wd == 1 ? 1 : wd == 7 ? 2 : -(wd - 2))
        var days: [Day] = []
        for w in 0..<4 {
            for d in 0..<5 {
                let x = mon0.adding(7 * w + d)
                let iso = x.iso
                let mo = MON[x.m - 1]
                let td = iso == today
                days.append(Day(id: w * 5 + d, iso: iso, w: w, d: d,
                                pill: d == 0 && (w == 0 || x.d <= 7) ? "\(mo) \(x.d)" : "\(x.d)",
                                title: "\(DN[d]) \(mo) \(x.d)" + (td ? " · today" : ""),
                                today: td, past: iso < today, closed: closed.contains(iso)))
            }
        }
        let first = days[0], last = days[days.count - 1]
        let f = Ymd(first.iso)!, l = Ymd(last.iso)!
        let range = "\(MON[f.m - 1]) \(f.d) to " + (f.m == l.m ? "\(l.d)" : "\(MON[l.m - 1]) \(l.d)")
        let rangeSub = "4 weeks · today \(IncFmt.dmd(today))"

        // Each name's rungs in the payload's order (calls by strike, then puts), and the days its next rungs land:
        // where each rung on its nearest expiry goes, and the name's landing day.
        let byT = Dictionary(grouping: rungs, by: \.t)
        var land: [String: Set<String>] = [:]
        var nearest: [String: String] = [:]
        for n in names {
            let rs = byT[n.t] ?? []
            var s = Set<String>()
            if let e0 = rs.map(\.ex).min() {
                nearest[n.t] = e0
                for r in rs where r.ex == e0 { if let x = r.next { s.insert(x.ex) } }
            }
            if let e = n.nextEx { s.insert(e) }
            land[n.t] = s
        }

        func legsOn(_ t: String, _ iso: String) -> [Leg] {
            (byT[t] ?? []).filter { $0.ex == iso }.map(leg).enumerated()
                .sorted { $0.element.rank != $1.element.rank ? $0.element.rank < $1.element.rank : $0.offset < $1.offset }
                .map(\.element)
        }

        // One name.
        var by: [String: Scope] = [:]
        for n in names {
            let boxes: [Box] = days.map { x in
                var b = Box()
                b.legs = legsOn(n.t, x.iso)
                let landing = land[n.t]?.contains(x.iso) == true
                if landing, let e0 = nearest[n.t] {
                    b.nx = (byT[n.t] ?? []).filter { $0.ex == e0 }.compactMap { r -> Next? in
                        guard let nx = r.next, nx.ex == x.iso, let K = nx.K else { return nil }
                        let ty = r.call ? " call" : " put"
                        return Next(id: "nx" + r.id, top: "Next · from \(r.exL)’s \(IncFmt.fk(r.K))\(ty)",
                                    main: IncFmt.fk(K) + ty + (nx.pr.map { " · " + IncFmt.f2($0) } ?? ""))
                    }
                }
                let cnt = b.legs.count
                let top = b.legs.first
                b.big = top?.short ?? ""
                b.bigTone = top?.tone ?? .mu
                b.sm = cnt > 0 ? "\(cnt) \(cnt == 1 ? "leg" : "legs")" : landing ? "next" : ""
                b.dashed = landing && cnt == 0
                b.filled = cnt > 0
                b.speech = speech(x, legs: b.legs.map(\.speech), rest: b.nx.map { "\($0.top), \($0.main)" }, landing: landing && b.nx.isEmpty)
                return b
            }
            by[n.t] = Scope(boxes: boxes, status: status(byT[n.t] ?? [], one: true))
        }

        // All: a line a name, the ones that need you first; the quiet ones behind one grey line.
        let allBoxes: [Box] = days.map { x in
            var b = Box()
            let rs: [Row] = names.compactMap { n -> Row? in
                let l = legsOn(n.t, x.iso)
                guard let t0 = l.first else { return nil }
                let nN = l.filter { $0.rank < 2 }.count
                let word = t0.ring == .run ? t0.word : t0.ring == .act && nN > 1 ? "\(nN) to roll" : t0.word
                let why: String
                if t0.ring == .run {
                    if l.count == 1 { why = "\(t0.nm) · \(t0.big) \(t0.bw)" }
                    else if Set(l.map(\.bw)).count == 1 { why = "\(l.count) legs · " + and(l.map(\.big)) + " \(t0.bw)" }
                    else { why = "\(l.count) legs · " + and(l.map { "\($0.big) \($0.bw)" }) }
                } else {
                    why = t0.nm + (t0.act.map { " · " + $0 } ?? "")
                }
                return Row(t: n.t, tTone: t0.ring == .run ? .quiet : .ink, word: word, wTone: t0.tone, why: why,
                           rank: t0.rank, kp: t0.kp, speech: IncSay.words("\(n.t), \(word). \(why)."))
            }.enumerated().sorted {
                let a = $0.element, c = $1.element
                if a.rank != c.rank { return a.rank < c.rank }
                if a.kp != c.kp { return a.kp > c.kp }
                return $0.offset < $1.offset
            }.map(\.element)
            let need = rs.filter { $0.rank < 2 }.count
            let itm = rs.contains { $0.rank == 0 }
            b.rows = rs.filter { $0.rank < 2 }
            let quiet = rs.filter { $0.rank == 2 }
            if !quiet.isEmpty {
                b.more = "\(quiet.count)\(b.rows.isEmpty ? "" : " more") running on their own · " + and(quiet.map(\.t))
            }
            let lnd = names.filter { land[$0.t]?.contains(x.iso) == true }.map(\.t)
            if !lnd.isEmpty { b.nx = [Next(id: "nxA", top: "Next rungs", main: and(lnd))] }
            let cnt = rs.count
            b.big = need > 0 ? "\(need)" : cnt > 0 ? "\(cnt)" : ""
            b.bigTone = need > 0 ? (itm ? .red : .green) : .quiet
            b.sm = need > 0 ? "to act" : cnt > 0 ? "running" : lnd.isEmpty ? "" : "next"
            b.dashed = !lnd.isEmpty && cnt == 0
            b.filled = cnt > 0
            b.speech = speech(x, legs: rs.map(\.speech), rest: b.nx.map { "\($0.top), \($0.main)" }, landing: false)
            return b
        }
        return IncCal(days: days, range: range, rangeSub: rangeSub,
                      all: Scope(boxes: allBoxes, status: status(rungs, one: false)), by: by)
    }

    /// SunnyIncomeCal leg(): the big % kept (red in the money or at a loss, green at 90% to roll, grey running), the
    /// action only when it needs you, the grey line (the phone's open days always have room for it).
    private static func leg(_ r: IncRung) -> Leg {
        let ring: Ring = r.itm ? .itm : r.roll ? .act : .run
        let kp = r.kp
        let lo = (kp ?? 0) < 0
        let tone: IncTone = ring == .itm || lo ? .red : ring == .act ? .green : .quiet
        let ty = r.call ? " call" : " put"
        let nm = IncFmt.fk(r.K) + ty + " ×\(r.q)"
        let big = kp.map { "\(abs($0))%" } ?? ""
        let bw = kp == nil ? "no mark" : lo ? "lost" : "kept"
        var act: String?
        var sub: String?
        switch ring {
        case .itm:
            act = "In the money by \(IncFmt.f2(r.intr))"
            sub = "Breakeven \(IncFmt.f2(r.be)) · you decide"
        case .act:
            let wait = (kp ?? 100) < 95 ? "or wait for 95%" : nil
            if let n = r.next {
                // "Roll to Dec 7 157.5 · 7.50": the strike and premium only when the chain lists them.
                act = "Roll to \(n.exL)" + (n.K.map { " " + IncFmt.fk($0) } ?? "") + (n.K != nil ? n.pr.map { " · " + IncFmt.f2($0) } ?? "" : "")
                var parts: [String] = []
                if n.K != nil, let pr = n.pr {
                    let d = n.d ?? (pr - r.at)
                    parts.append(abs(d) < 0.005 ? "the same as this one" : "\(d > 0 ? "↑" : "↓") \(IncFmt.f2(abs(d))) vs this one")
                }
                parts.append("\(IncFmt.fk(n.z)) SD from today")
                if let wait { parts.append(wait) }
                sub = parts.joined(separator: " · ")
            } else {
                act = "Ready to roll"
                sub = wait.map { $0.prefix(1).uppercased() + $0.dropFirst() }
            }
        case .run:
            if let kp {
                sub = (lo ? "Down \(IncFmt.f2((r.mk ?? r.at) - r.at)) a share" : "\(90 - kp)% to the roll") + " · sold at \(IncFmt.f2(r.at))"
            } else {
                sub = "Sold at \(IncFmt.f2(r.at))"
            }
        }
        let word = ring == .itm ? "In the money" : ring == .act ? "Roll" : big
        let short = ring == .itm ? "ITM" : ring == .act ? "Roll" : big
        let kept = kp.map { lo ? "\(abs($0)) percent lost" : "\($0) percent kept" } ?? "no mark"
        return Leg(id: r.id, lab: nm, big: big, bw: bw, tone: tone, act: act, sub: sub, ring: ring,
                   rank: ring == .itm ? 0 : ring == .act ? 1 : 2, kp: kp ?? 0, nm: nm, word: word, short: short,
                   speech: IncSay.words("\(r.t) \(nm), \(kept)" + (act.map { ". \($0)" } ?? "") + (sub.map { ". \($0)" } ?? "")))
    }

    /// The status: how many need you (red when any is in the money, else green), or All quiet with the nearest roll.
    private static func status(_ sold: [IncRung], one: Bool) -> Status {
        let itmN = sold.filter(\.itm).count, rollN = sold.filter(\.roll).count, need = itmN + rollN
        if need > 0 {
            let sub = [itmN > 0 ? "\(itmN) in the money" : nil, rollN > 0 ? "\(rollN) to roll" : nil].compactMap { $0 }.joined(separator: " · ")
            return Status(need: need, tone: itmN > 0 ? .red : .green, word: need == 1 ? "needs you" : "need you", sub: sub)
        }
        let near = sold.filter { !$0.itm && ($0.kp ?? 100) < 90 }.max { ($0.kp ?? 0) < ($1.kp ?? 0) }
        var sub = "Nothing sold"
        if let r = near {
            let name: String = (one ? "" : r.t + " ") + IncFmt.fk(r.K) + (r.call ? " call" : " put")
            sub = "Nearest roll · \(name) at \(r.kp ?? 0)%"
        }
        return Status(need: 0, tone: .quiet, word: "All quiet", sub: sub)
    }

    /// "Tuesday November 24, today: NVDA 167.5 call times 3, ...", or ", nothing expires".
    private static func speech(_ x: Day, legs: [String], rest: [String], landing: Bool) -> String {
        let said = legs + rest + (landing ? ["the next rung lands"] : [])
        return IncSay.words(x.title.replacingOccurrences(of: " · today", with: ", today")
                            + (said.isEmpty ? (x.closed ? ", market closed" : ", nothing expires") : ": " + said.joined(separator: "; ")))
    }

    /// "A", "A and B", "A, B and C".
    static func and(_ a: [String]) -> String {
        a.count < 2 ? a.joined() : a.dropLast().joined(separator: ", ") + " and " + a[a.count - 1]
    }
}

/// A calendar day from "2026-11-24", counted in UTC so no time zone moves it.
private nonisolated struct Ymd {
    let y: Int, m: Int, d: Int
    private static let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    init?(_ iso: String) {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return nil }
        y = p[0]; m = p[1]; d = p[2]
    }
    private init(_ date: Date) {
        let c = Self.cal.dateComponents([.year, .month, .day], from: date)
        y = c.year ?? 2026; m = c.month ?? 1; d = c.day ?? 1
    }
    static var now: Ymd { Ymd(Date()) }
    private var date: Date { Self.cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12)) ?? Date() }
    /// 1 Sunday ... 7 Saturday.
    var weekday: Int { Self.cal.component(.weekday, from: date) }
    func adding(_ n: Int) -> Ymd { Ymd(Self.cal.date(byAdding: .day, value: n, to: date) ?? date) }
    var iso: String { String(format: "%04d-%02d-%02d", y, m, d) }
}
