//
//  SunnyRollSheet.swift
//  The roll sheet (export 26, locked 23 Sep 2026): hold a sold leg's figure
//  450 ms and next Friday's write on that name rises as a glass panel 8 in from
//  the Positions card's sides and bottom. 345 × 463.
//
//  ⚠ THE BAR IS NOT A PRICE AXIS. The five levels (spot, strike, break-even,
//  ±1 SD, 20-day) sort by price and are PACKED across the 301 track by their
//  label widths with one equal gap, first label flush left, last flush right.
//  A tick sits dead-centre on its own label. Position says ORDER; distance is
//  printed, in every figure and the "end to end" span. Never `(p − lo)/(hi − lo)`,
//  never a leader, never a label moved off its tick.
//
//  ⚠ TWO RULINGS OUTRANK THE SHEET (Nik, 22 Sep 2026). The premium is the LIVE
//  MID of next Friday's strike, not the credit the pressed leg opened at; and
//  the floor is HIS OWN AVERAGE PER SIDE, not a fixed 1.06.
//
//  ⚠ NEXT FRIDAY IS THE FIRST FRIDAY AFTER THE PRESSED LEG EXPIRES.
//

import SwiftUI

// MARK: - payload

struct RollCard: Decodable {
    let asOf: String?
    let floor: InvFloor
    let names: [String: RollChainName]
}

struct RollChainName: Decodable {
    let spot: Double
    let avg20: Double?
    /// Days to the next report, whenever it is.
    let earn: Int?
    /// The name's net delta now, share equivalents. Null when no leg is priced.
    let delta: Double?
    let weeks: [RollChainWeek]
    /// Today against 21 sessions ago, %. What the call split reads.
    let move21: Double?
    /// LEAP calls held on the name: the size of the week's call write.
    let held: Int?
}

struct RollChainWeek: Decodable {
    let w: String
    /// One standard deviation to this expiry, in dollars.
    let sd: Double?
    let calls: [RollChainStrike]
    let puts: [RollChainStrike]
    /// The strike nearest spot ± 1 SD, from the whole chain, not the five.
    let sdCall: RollChainStrike?
    let sdPut: RollChainStrike?
    /// The call write's split for this week (server, 23 Sep 2026).
    var split: RollSplit? = nil
    /// Live only: every call strike at or above spot, for the 1 SD fallback.
    var above: [RollChainStrike]? = nil
}

/// ⚠ THE CALL WRITE IS SPLIT. Part at the money, the rest at 1 SD; the share
/// at the money follows the last month (20 / 30 / 50 / 60%), and earnings
/// before the expiry overrides to 20%. Counts round half up server-side.
struct RollSplit: Decodable {
    let share: Double
    /// `fell` · `flat` · `up` · `up a lot` · `earnings`
    let why: String
    let atm: Int
    let sd: Int
}

struct RollChainStrike: Decodable {
    let k: Double
    let oi: Int?
    let mid: Double
    let dl: Double?
    /// The live read carries each strike's IV; the cached card does not.
    var iv: Double? = nil
}

/// ⚠ LIVE, EVERY TIME THE SHEET OPENS (Nik, 24 Sep 2026: "Refresh every time
/// we open the pop up"). He saw BABA at 110 and a write at 112, because the
/// app had loaded at yesterday's 111. `chain-next` with a ticker reads Polygon
/// there and then and writes nothing; its prices are worked out from the
/// chain's IV at the current spot, within ~3% of IBKR's mid where the last
/// trade was 7% out.
struct RollLive: Decodable {
    let spot: Double?
    let asOf: String?
    let weeks: [RollChainWeek]

    static func fetch(_ t: String) async -> RollLive? {
        var r = URLRequest(url: URL(string: Secrets.supabaseURL + "/functions/v1/chain-next")!)
        r.httpMethod = "POST"
        r.timeoutInterval = 15
        r.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + Secrets.supabasePublishableKey, forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["ticker": t])
        guard let (d, _) = try? await URLSession.shared.data(for: r),
              let live = try? JSONDecoder().decode(RollLive.self, from: d),
              live.spot != nil, !live.weeks.isEmpty else { return nil }
        return live
    }
}

extension RollChainName {
    /// The cached name with the live spot and chain laid over it. The month's
    /// move is re-read against the new spot from the same close 21 sessions back.
    func merged(_ l: RollLive) -> RollChainName {
        guard let ls = l.spot, ls > 0 else { return self }
        let m = move21.flatMap { m -> Double? in
            guard spot > 0 else { return nil }
            let c21 = spot / (1 + m / 100)
            return (ls / c21 - 1) * 100
        }
        return RollChainName(spot: ls, avg20: avg20, earn: earn, delta: delta,
                             weeks: l.weeks, move21: m, held: held)
    }
}

// MARK: - the arithmetic

/// Everything the sheet prints for one pressed leg. Pure: the view maps it to
/// inks and positions and nothing else.
struct RollQuote {
    let t: String, call: Bool
    let spot: Double, k: Double, cr: Double, be: Double, tgt: Double, avg: Double
    let onK: Double, ok: Bool, floor: Double
    let earn: Int?
    let deltaNow: Double?, deltaAfter: Double?
    let oi: [RollChainStrike]
    /// Spot to the farthest level, %, signed along the risk direction.
    let span: Double
    /// The formatter the pack settled on: two decimals, or none for big figures.
    let wide: Bool
    /// Packed x of each level, 0...100 of the track.
    let x: (spot: Double, k: Double, be: Double, tgt: Double, avg: Double)
    let zones: [RollZone]
    /// The two-leg call write (final cards, 23 Sep 2026). Nil on a put, or
    /// where the name holds no LEAP call to size the write against: the sheet
    /// then draws the one-leg reading it always did.
    var write: RollWrite? = nil

    /// ⚠ ONE DECIMAL ON THE BAND (Nik, 23 Sep 2026: "keep the decimal to one
    /// not two"). Two decimals crowded the band into dropping them entirely,
    /// and NKE's 20-day then printed "37" beside a break-even of "37.38".
    func fig(_ v: Double) -> String { wide ? rsF0(v) : rsF1(v) }
}

/// ⚠ TWO LEGS, ONE HERO. Two strikes have two prices a share, so the hero is
/// the week's credit in dollars and each leg carries its own price and its %
/// of strike. The floor test is the at-the-money leg's alone: under 1% at
/// 1 SD is the design, not a warning.
struct RollWrite {
    struct Leg { let n: Int, k: Double, cr: Double, onK: Double, atm: Bool }
    enum Tone { case ink, loss, mute }
    struct Level { let id: String, p: Double, fig: String, word: String, tone: Tone, x: Double }
    struct Tile { let k: Double, oi: Int?, chosen: Bool }
    let legs: [Leg]
    let share: Double
    /// `down 6% this month` · `up 13% this month` · `earnings Thu`
    let why: String
    let leaps: Int
    let total: Double
    let levels: [Level]
    let spotX: Double
    let zones: [RollZone]
    let span: Double
    let tiles: [Tile]
    let deltaAfter: Double?
    /// ⚠ WHAT IS ALREADY SOLD FOR THAT FRIDAY (Nik, 24 Sep: "I may execute
    /// part of the order and that needs to be reflected"). The legs above are
    /// what is LEFT; these are what he has written already, by strike.
    let done: [(n: Int, k: Double)]
    var doneN: Int { done.reduce(0) { $0 + $1.n } }
    var leftN: Int { legs.reduce(0) { $0 + $1.n } }
}

struct RollZone: Identifiable {
    let l: Double, w: Double, tone: Tone
    var id: String { "\(tone)-\(l)" }
    enum Tone { case safe, risk, risk2, past }
}

enum RollMath {
    /// The band's width: sheet 345 less 22 padding each side.
    static let track: Double = 301
    /// Below this many points between packed labels, the figures drop decimals.
    static let minGap: Double = 10

    /// A 15/700 digit is about 9pt, a 12/400 letter about 6.7pt: the sheet's own
    /// estimate, kept so positions match the reference to the point.
    static func labelW(_ fig: String, _ word: String) -> Double {
        max(Double(fig.count) * 9, Double(word.count) * 6.7)
    }

    /// ⚠ NEVER MORE THAN A WEEK OUT (Nik, 24 Sep 2026: "it should not suggest
    /// anything more than a week"). The target is next Friday, whatever leg was
    /// pressed: Monday to Friday it is the Friday after this week's; on a
    /// weekend it is the coming one. A leg already written for next Friday no
    /// longer points at the week after; the sheet shows what is done instead.
    static func targetFriday(_ now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let today = cal.startOfDay(for: now)
        let wd = cal.component(.weekday, from: today)          // 1 Sun … 7 Sat
        let toFri = (6 - wd + 7) % 7
        let weekend = wd == 7 || wd == 1
        let d = cal.date(byAdding: .day, value: toFri + (weekend ? 0 : 7), to: today) ?? today
        let f = DateFormatter()
        f.calendar = cal; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    /// Days from today in New York to an ISO date.
    static func daysTo(_ iso: String) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let f = DateFormatter()
        f.calendar = cal; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return 0 }
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: d).day ?? 0
    }

    /// ⚠ THE SPLIT, the server's rule restated so a live spot can re-read it:
    /// fell 10%+ → 20% at the money, −10..+5 → 30%, +5..+15 → 50%, above → 60%;
    /// earnings on or before the expiry → 20%. Counts round half up.
    static func split(held: Int, move: Double?, earn: Int?, week: String) -> RollSplit {
        var share = 0.3, why = "flat"
        if let m = move {
            if m <= -10 { share = 0.2; why = "fell" }
            else if m < 5 { share = 0.3; why = "flat" }
            else if m < 15 { share = 0.5; why = "up" }
            else { share = 0.6; why = "up a lot" }
        }
        if let e = earn, e >= 0, e <= daysTo(week) { share = 0.2; why = "earnings" }
        let atm = Int((Double(held) * share + 0.5).rounded(.down))
        return RollSplit(share: share, why: why, atm: atm, sd: held - atm)
    }

    /// The write on this name for next Friday. `done` is what is already sold
    /// on that side for that Friday, by strike.
    static func quote(t: String, call: Bool, n: Int, name: RollChainName, floor: Double,
                      done: [(n: Int, k: Double)] = []) -> RollQuote? {
        let target = targetFriday()
        let wk = name.weeks.first { $0.w == target }
            ?? name.weeks.first { daysTo($0.w) >= 0 } ?? name.weeks.last
        guard let week = wk, let sd = week.sd, sd > 0 else { return nil }
        let spot = name.spot
        /* The strike is the nearest chain strike at or beyond spot on the leg's
           side: a call above, a put below. */
        let side = call ? week.calls : week.puts
        guard let pick = call ? side.first : side.last, pick.mid > 0, spot > 0 else { return nil }
        let k = pick.k, cr = pick.mid
        let be = call ? k + cr : k - cr
        let tgt = call ? spot + sd : spot - sd
        let avg = name.avg20 ?? spot
        let onK = cr / k * 100

        /* ORDINAL PACK. Sorted by price, a stable tiebreak so equal prices keep
           their order; each level's slot is its label width; one gap between. */
        typealias Slot = (id: String, p: Double, w: Double)
        func pack(_ f: (Double) -> String) -> (P: [Slot], X: [String: Double], gap: Double) {
            let raw: [Slot] = [("spot", spot, labelW(f(spot), "")),
                               ("k", k, labelW(rsK(k), "strike")),
                               ("be", be, labelW(f(be), "break-even")),
                               ("tgt", tgt, labelW(f(tgt), "+1 SD")),
                               ("avg", avg, labelW(f(avg), "20-day"))]
            let P = raw.enumerated().sorted { a, b in
                a.element.p != b.element.p ? a.element.p < b.element.p : a.offset < b.offset
            }.map(\.element)
            let gap = (track - P.reduce(0) { $0 + $1.w }) / Double(P.count - 1)
            var X: [String: Double] = [:], cur = 0.0
            for s in P { X[s.id] = (cur + s.w / 2) / track * 100; cur += s.w + gap }
            return (P, X, gap)
        }
        var wide = false
        var (P, X, gap) = pack(rsF1)
        if gap < minGap { wide = true; (P, X, gap) = pack(rsF0) }

        let lo = P.first!.p, hi = P.last!.p
        let span = (call ? hi - spot : lo - spot) / spot * 100
        /* Equal prices share one x, the mean of their slots. */
        func x(_ v: Double) -> Double {
            let m = P.filter { $0.p == v }.compactMap { X[$0.id] }
            return m.isEmpty ? 0 : m.reduce(0, +) / Double(m.count)
        }
        func xe(_ v: Double) -> Double { v == hi ? 100 : v == lo ? 0 : x(v) }
        /* ⚠ ONLY THE LAST ZONE RUNS TO THE BAND'S EDGE; the others end at the
           next level's x, so no two zones overlap (export 26). */
        func seg(_ a: Double, _ b: Double, _ tone: RollZone.Tone, toEdge: Bool = false) -> RollZone {
            let xb = toEdge ? xe(b) : x(b)
            return RollZone(l: min(x(a), xb), w: abs(xb - x(a)), tone: tone)
        }
        /* Cuts are monotonic along the risk direction: a 20-day or SD inside an
           earlier zone collapses its own zone rather than painting backwards. */
        let fwd: (Double, Double) -> Double = call ? { max($0, $1) } : { min($0, $1) }
        let end = call ? hi : lo
        let near = call ? min(tgt, avg) : max(tgt, avg)
        let far = call ? max(tgt, avg) : min(tgt, avg)
        let c1 = be, c2 = fwd(c1, near), c3 = fwd(c2, far)
        let zones = [seg(k, c1, .safe), seg(c1, c2, .risk), seg(c2, c3, .risk2),
                     seg(c3, end, .past, toEdge: true)].filter { $0.w > 0.5 }

        /* A short leg's delta is the contract's, signed against him. */
        let after = pick.dl.flatMap { d in name.delta.map { $0 - d * Double(n) * 100 } }
        return RollQuote(
            t: t, call: call, spot: spot, k: k, cr: cr, be: be, tgt: tgt, avg: avg,
            onK: onK, ok: onK >= floor, floor: floor, earn: name.earn,
            deltaNow: name.delta, deltaAfter: after, oi: side,
            span: span, wide: wide,
            x: (X["spot"] ?? 0, X["k"] ?? 0, X["be"] ?? 0, X["tgt"] ?? 0, X["avg"] ?? 0),
            zones: zones,
            write: call ? write(name: name, week: week, spot: spot, sd: sd, avg: avg, done: done) : nil)
    }

    /// THE CALL WRITE, TWO LEGS. The split is the server's (the counts, the
    /// share, the reason); the prices are the chain's live mids, and the
    /// levels pack the way the one-leg band does, with the 1 SD STRIKE as a
    /// level of its own.
    static func write(name: RollChainName, week: RollChainWeek, spot: Double,
                      sd: Double, avg: Double, done: [(n: Int, k: Double)] = []) -> RollWrite? {
        guard let held = name.held, held > 0,
              let atmPick = week.calls.first(where: { $0.k >= spot }) else { return nil }
        let split = Self.split(held: held, move: name.move21, earn: name.earn, week: week.w)
        let ks = (week.calls + (week.above ?? []) + (week.sdCall.map { [$0] } ?? [])).map(\.k)
        let sortedK = Array(Set(ks)).sorted()
        /* The chain's own strike spacing, for the merge test. */
        let step = zip(sortedK, sortedK.dropFirst()).map { $1 - $0 }.filter { $0 > 0 }.min() ?? 1
        /* ⚠ THE 1 SD STRIKE IS NEVER THE AT-THE-MONEY ONE. On a quiet week the
           nearest strike to spot + sd can be the first one out; then it is the
           next strike up, or the write would be one leg drawn twice. */
        var sdPick = week.sdCall
        if sdPick == nil || sdPick!.k <= atmPick.k {
            sdPick = ((week.above ?? []) + week.calls).filter { $0.k > atmPick.k }.min { $0.k < $1.k }
        }

        /* ⚠ PARTIAL FILLS. The plan is sized on every LEAP; what he has
           already sold for this Friday counts toward whichever of the two
           strikes it sits nearer, and only the rest is suggested. More than the
           plan at one strike comes out of the other. */
        let kSd = sdPick?.k ?? atmPick.k
        var doneAtm = 0, doneSd = 0
        for d in done {
            if abs(d.k - atmPick.k) <= abs(d.k - kSd) { doneAtm += d.n } else { doneSd += d.n }
        }
        let left = max(0, held - doneAtm - doneSd)
        let leftAtm = min(left, max(0, split.atm - doneAtm))
        let leftSd = left - leftAtm

        var legs: [RollWrite.Leg] = []
        if leftAtm > 0, atmPick.mid > 0 {
            legs.append(.init(n: leftAtm, k: atmPick.k, cr: atmPick.mid,
                              onK: atmPick.mid / atmPick.k * 100, atm: true))
        }
        if leftSd > 0, let p = sdPick, p.mid > 0 {
            legs.append(.init(n: leftSd, k: p.k, cr: p.mid, onK: p.mid / p.k * 100, atm: false))
        }
        guard !legs.isEmpty || !done.isEmpty else { return nil }
        let atm = legs.first { $0.atm }, sdLeg = legs.first { !$0.atm }
        let total = legs.reduce(0) { $0 + $1.cr * 100 * Double($1.n) }

        /* THE REASON, one short clause. */
        let why: String
        if split.why == "earnings", let e = name.earn {
            why = "earnings " + rsWeekday(inDays: e)
        } else if let m = name.move21 {
            why = (m < 0 ? "down " : "up ") + "\(Int(abs(m).rounded()))% this month"
        } else {
            why = "no month yet"
        }

        /* THE BAND. Spot · the at-the-money strike · its break-even · the 1 SD
           mark (merged with the strike when within a step) · the 20-day. The
           1 SD leg's own break-even sits under a label's width from its strike
           and would only crowd the band. */
        let kA = atm?.k ?? atmPick.k
        let be = atm.map { $0.k + $0.cr }
        let tgt = spot + sd
        let merge = sdLeg.map { abs(tgt - $0.k) <= step } ?? false
        var lv: [(id: String, p: Double, word: String, tone: RollWrite.Tone)] = [
            ("spot", spot, "", .ink),
            ("k", kA, atm != nil ? "strike" : "at the money", .ink)]
        if let be { lv.append(("be", be, "break-even", .ink)) }
        if let s = sdLeg, merge {
            lv.append(("sd", s.k, "1 SD strike", .loss))
        } else {
            lv.append(("tgt", tgt, "+1 SD", .loss))
            if let s = sdLeg { lv.append(("k2", s.k, "strike", .ink)) }
        }
        lv.append(("avg", avg, "20-day", .mute))

        /* ⚠ BIG FIGURES, PER LEVEL. A figure drops its decimals only when it
           is the wider part of its own label; when the word is wider the
           decimals are free and stay, so two levels never print one figure.
           Strikes are strikes; spot keeps its decimals always. */
        func pack(_ f: (Double) -> String) -> (P: [RollWrite.Level], gap: Double) {
            let raw = lv.enumerated().map { i, l -> (Int, RollWrite.Level, Double) in
                let strike = l.id == "k" || l.id == "sd" || l.id == "k2"
                let a = rsF1(l.p)
                let fig = strike ? rsK(l.p) : l.id == "spot" ? a
                    : (Double(a.count) * 9 > Double(l.word.count) * 6.7 ? f(l.p) : a)
                return (i, RollWrite.Level(id: l.id, p: l.p, fig: fig, word: l.word,
                                           tone: l.tone, x: 0), labelW(fig, l.word))
            }.sorted { $0.1.p != $1.1.p ? $0.1.p < $1.1.p : $0.0 < $1.0 }
            let gap = (track - raw.reduce(0) { $0 + $1.2 }) / Double(max(1, raw.count - 1))
            var cur = 0.0, out: [RollWrite.Level] = []
            for r in raw {
                let x = (cur + r.2 / 2) / track * 100
                out.append(.init(id: r.1.id, p: r.1.p, fig: r.1.fig, word: r.1.word, tone: r.1.tone, x: x))
                cur += r.2 + gap
            }
            return (out, gap)
        }
        var (P, gap) = pack(rsF1)
        if gap < minGap { (P, gap) = pack(rsF0) }
        let lo = P.first!.p, hi = P.last!.p
        func xOf(_ p: Double) -> Double? {
            if let q = P.first(where: { $0.p == p && $0.id != "spot" }) ?? P.first(where: { $0.p == p }) {
                return q.x
            }
            return p >= hi ? 100 : p <= lo ? 0 : nil
        }
        /* Zones from the at-the-money strike outward: safe to break-even, risk
           to the nearer of the 1 SD mark and the 20-day, risk-2 to the farther,
           past to the edge. With no at-the-money leg the safe zone is empty. */
        let tgtP = merge ? sdLeg!.k : tgt
        let near = min(tgtP, avg), far = max(tgtP, avg)
        let c1 = be ?? kA, c2 = max(c1, near), c3 = max(c2, far)
        func seg(_ a: Double, _ b: Double, _ tone: RollZone.Tone, toEdge: Bool = false) -> RollZone? {
            guard let xa = xOf(a), let xb = toEdge ? 100 : xOf(b) else { return nil }
            return RollZone(l: min(xa, xb), w: abs(xb - xa), tone: tone)
        }
        let zones = [seg(kA, c1, .safe), seg(c1, c2, .risk), seg(c2, c3, .risk2),
                     seg(c3, hi, .past, toEdge: true)].compactMap { $0 }.filter { $0.w > 0.5 }

        /* OPEN INTEREST: five tiles, both chosen strikes always among them.
           The nearest four at or above the at-the-money strike, then the 1 SD
           strike when it is not already the fifth. */
        var pool = Array(Dictionary(((week.above ?? []) + week.calls).map { ($0.k, $0) },
                                    uniquingKeysWith: { a, _ in a }).values).filter { $0.k >= kA }
        if let s = sdPick, !pool.contains(where: { $0.k == s.k }) { pool.append(s) }
        pool.sort { $0.k < $1.k }
        var pick = Array(pool.prefix(5))
        if let s = sdLeg, !pick.contains(where: { $0.k == s.k }),
           let full = pool.first(where: { $0.k == s.k }) {
            pick = Array(pool.prefix(4)) + [full]
        }
        let chosen = Set(legs.map(\.k))
        let tiles = pick.map { RollWrite.Tile(k: $0.k, oi: $0.oi, chosen: chosen.contains($0.k)) }

        /* Delta after BOTH legs: each short call takes its contract delta off. */
        var after: Double? = name.delta
        for l in legs {
            let dl = l.atm ? atmPick.dl : sdPick?.dl
            after = after.flatMap { a in dl.map { a - $0 * Double(l.n) * 100 } }
        }

        /* Strikes already sold are grouped, biggest first. */
        var byK: [Double: Int] = [:]
        for d in done { byK[d.k, default: 0] += d.n }
        let doneRows = byK.map { (n: $0.value, k: $0.key) }.sorted { $0.k < $1.k }
        return RollWrite(legs: legs, share: split.share, why: why, leaps: held, total: total,
                         levels: P.filter { $0.id != "spot" },
                         spotX: P.first { $0.id == "spot" }?.x ?? 0,
                         zones: zones, span: (hi - spot) / spot * 100, tiles: tiles,
                         deltaAfter: after, done: doneRows)
    }
}

/// The weekday a report falls on, `days` from today in New York: `Thu`.
func rsWeekday(inDays days: Int) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    let d = cal.date(byAdding: .day, value: days, to: Date()) ?? Date()
    let f = DateFormatter()
    f.calendar = cal; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEE"
    return f.string(from: d)
}

/// ⚠ THE EARNINGS WORD. `today` · `tomorrow` · `this Thu` · `next Wed` inside
/// this Monday-to-Sunday week and the next, which is when it is LOUD; later,
/// the date: `15 Oct`. Nil when nothing is scheduled.
func rsEarnWord(inDays days: Int?) -> (word: String, loud: Bool)? {
    guard let days, days >= 0 else { return nil }
    if days == 0 { return ("today", true) }
    if days == 1 { return ("tomorrow", true) }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    cal.firstWeekday = 2
    let today = cal.startOfDay(for: Date())
    guard let d = cal.date(byAdding: .day, value: days, to: today),
          let wk0 = cal.dateInterval(of: .weekOfYear, for: today)?.start,
          let wkD = cal.dateInterval(of: .weekOfYear, for: d)?.start else { return nil }
    let weeks = (cal.dateComponents([.day], from: wk0, to: wkD).day ?? 0) / 7
    let f = DateFormatter()
    f.calendar = cal; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEE"
    if weeks == 0 { return ("this " + f.string(from: d), true) }
    if weeks == 1 { return ("next " + f.string(from: d), true) }
    f.dateFormat = "d MMM"
    return (f.string(from: d), false)
}

/// `$2,120`: whole dollars with a thousands comma, true minus.
func rsUsd0(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal; f.maximumFractionDigits = 0; f.locale = Locale(identifier: "en_US")
    let s = f.string(from: NSNumber(value: abs(v).rounded())) ?? String(Int(abs(v).rounded()))
    return (v < 0 ? "\u{2212}$" : "$") + s
}

/// `88.4` · `1.2` · `90.2`: no trailing zeros anywhere on the sheet.
func rsF2(_ v: Double) -> String {
    var s = String(format: "%.2f", v)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}
/// The band's figures: `37.4`, `104.6`, `106` (a trailing zero goes).
func rsF1(_ v: Double) -> String {
    var s = String(format: "%.1f", v)
    if s.hasSuffix(".0") { s.removeLast(2) }
    return s
}
/// Big figures on the band, only if one decimal still cannot fit: `144`.
func rsF0(_ v: Double) -> String { String(Int(v.rounded())) }
/// Strikes: an integer when whole, else two decimals. `102.5` stays.
func rsK(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : rsF2(v) }
func rsOI(_ v: Int?) -> String {
    guard let v else { return "\u{2013}" }
    return v >= 1000 ? String(format: "%.1fk", Double(v) / 1000) : String(v)
}

// MARK: - the sheet

struct SunnyRollSheet: View {
    let q: RollQuote
    /// True while the live read is out; the figures are the cached ones.
    var updating = false
    let onClose: () -> Void
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let inner: CGFloat = 301
    private static let graphH: CGFloat = 114

    private func tone(_ t: RollZone.Tone) -> Color {
        switch t {
        case .safe: return S.gainBar
        case .risk: return S.rsZoneRisk
        case .risk2: return S.lossBar
        case .past: return S.hair
        }
    }
    private func at(_ pct: Double) -> CGFloat { Self.inner * CGFloat(pct) / 100 }
    private func rise(_ ms: Double) -> Animation? {
        reduceMotion ? nil : S.easeSettle(0.5).delay(ms / 1000)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            handle
            Spacer().frame(height: 12)
            context.rsRise(shown, rise(0))
            Spacer().frame(height: 10)
            hero.rsRise(shown, rise(60))
            Spacer().frame(height: 6)
            order.rsRise(shown, rise(90))
            if let w = q.write {
                Spacer().frame(height: 22)
                writeBlock(w)
            }
            Spacer().frame(height: 28)
            byFri
            Spacer().frame(height: 14)
            graph
            Spacer().frame(height: 22)
            oiHead.rsRise(shown, rise(300))
            Spacer().frame(height: 10)
            tiles.rsRise(shown, rise(340))
            Spacer().frame(height: 22)
            Rectangle().fill(S.ruleColor).frame(height: 1)
            Spacer().frame(height: 14)
            footer.rsRise(shown, rise(400))
        }
        .frame(width: Self.inner, alignment: .leading)
        .padding(EdgeInsets(top: 8, leading: 22, bottom: 24, trailing: 22))
        /* ⚠ THE PANEL IS THE SCREEN LESS 12 EACH SIDE; THE COLUMN STAYS 301.
           The band's pack is measured against 301 (`TRACK`), so the column
           keeps it and centres; only the glass grows with the phone. */
        .frame(maxWidth: .infinity, alignment: .top)
        /* ⚠ ONE GLASS LAYER, REGULAR, NEVER CLEAR (presentation spec, 23 Sep).
           The sheet is large, sits over a data card and carries 13pt muted
           type; Clear is for small marks over photos. Regular adapts to what
           is behind it, so there is no gradient, rim or second dimming layer:
           the platform draws its own edge. */
        .glassEffect(.regular.tint(S.rsGlassTint),
                     in: .rect(cornerRadius: 40, style: .continuous))
        .shadow(color: S.rsShadow1, radius: 16, x: 0, y: 12)
        .shadow(color: S.rsShadow2, radius: 3, x: 0, y: 2)
        .monospacedDigit()
        .measure("roll-sheet")
        .onAppear { shown = true }
    }

    private var handle: some View {
        HStack {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2).fill(S.hair).frame(width: 36, height: 4)
                .frame(width: 44, height: 16, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
            Spacer(minLength: 0)
        }
        .frame(width: Self.inner, height: 16)
    }

    // MARK: header · three lines

    /// `NFLX is 79 · 2.05% vs 1.06 floor`: the % is the only colour up here.
    /// Calls: `BABA is 111.04 · 15 LEAPs`, the % moved onto the first leg.
    @ViewBuilder private var context: some View {
        if let w = q.write {
            (Text(q.t).font(S.inter(S.t13, S.wSemiN)).foregroundStyle(S.ink)
             + Text(" is ").font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
             + Text(rsF2(q.spot)).font(S.inter(S.t13, S.wSemiN)).foregroundStyle(S.ink)
             + Text(" \u{00B7} \(w.leaps) LEAP\(w.leaps == 1 ? "" : "s")")
                .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
             + Text(updating ? " \u{00B7} updating" : "")
                .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.warn))
                .lineLimit(1).fixedSize()
                .frame(height: 15.5, alignment: .leading)
        } else {
            oneLegContext
        }
    }
    private var oneLegContext: some View {
        (Text(q.t).font(S.inter(S.t13, S.wSemiN)).foregroundStyle(S.ink)
         + Text(" is ").font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
         + Text(rsF2(q.spot)).font(S.inter(S.t13, S.wSemiN)).foregroundStyle(S.ink)
         + Text(" \u{00B7} ").font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
         + Text(rsF2(q.onK) + "%").font(S.inter(S.t13, S.wBoldN))
            .foregroundStyle(q.ok ? S.gainText : S.lossText)
         + Text(" vs " + String(format: "%.2f", q.floor) + " floor").font(S.inter(S.t13, S.wMidSmN))
            .foregroundStyle(S.mute)
         + Text(updating ? " \u{00B7} updating" : "")
            .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.warn))
            .lineLimit(1).fixedSize()
            .frame(height: 15.5, alignment: .leading)
    }

    /// ⚠ CALLS: THE WEEK'S CREDIT IN DOLLARS. Two legs have two prices a
    /// share, so "a share" moved into the leg lines. Puts keep "a share".
    private var hero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(q.write.map { $0.legs.isEmpty ? "Written" : rsUsd0($0.total) } ?? rsF2(q.cr))
                .font(S.inter(34, S.wBoldN)).tracking(S.track(34, -0.03))
                .foregroundStyle(S.ink).sunnyLineBox(34)
            Text(q.write.map { w in
                     w.legs.isEmpty ? "next Fri \u{00B7} \(w.doneN) of \(w.leaps) calls"
                     : w.doneN > 0 ? "next Fri \u{00B7} \(w.leftN) of \(w.leaps) left"
                     : "next Fri \u{00B7} \(w.leaps) call\(w.leaps == 1 ? "" : "s")" }
                 ?? "a share")
                .font(S.inter(15, S.wMidSmN)).foregroundStyle(S.mute)
        }
        .lineLimit(1)
        .frame(height: 34, alignment: .leading)
    }

    /// Its own line, always: beside the hero it clipped on `112.5 calls`.
    /// Calls: the split and its reason, `30% at the money · down 6% this month`.
    @ViewBuilder private var order: some View {
        if let w = q.write {
            (Text("\(Int((w.share * 100).rounded()))% at the money")
                .font(S.inter(S.t13, S.wBoldN)).foregroundStyle(S.ink)
             + Text(" \u{00B7} " + w.why).font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute))
                .lineLimit(1).fixedSize()
                .frame(height: 15.5, alignment: .leading)
        } else {
            oneLegOrder
        }
    }
    private var oneLegOrder: some View {
        (Text("sell ").font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
         + Text(rsK(q.k) + (q.call ? " calls" : " puts")).font(S.inter(S.t13, S.wBoldN))
            .foregroundStyle(S.ink)
         + Text(" for next ").font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
         + Text("Fri").font(S.inter(S.t13, S.wBoldN)).foregroundStyle(S.ink))
            .lineLimit(1).fixedSize()
            .frame(height: 15.5, alignment: .leading)
    }

    private func eyebrow(_ s: String) -> some View {
        Text(s.uppercased()).font(S.inter(S.t11, S.wBoldN)).tracking(S.track(S.t11, 0.1))
            .foregroundStyle(S.mute)
    }

    /* THE WRITE, calls only: one line a leg, never truncated. count × strike ·
       the word · credit a share · % of strike. The first leg carries the floor
       test in its %; the second's % is plain mute. A one-LEAP name is one line. */
    private static let legCol: CGFloat = 72, legPct: CGFloat = 44

    private func writeBlock(_ w: RollWrite) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                eyebrow("The write")
                Spacer(minLength: 0)
                Text("a share \u{00B7} " + String(format: "%.2f", q.floor) + " floor")
                    .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
            }
            .lineLimit(1)
            .frame(width: Self.inner, height: 14.5)
            .rsRise(shown, rise(110))
            Spacer().frame(height: 12)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(w.legs.enumerated()), id: \.offset) { i, l in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(l.n) \u{00D7} " + rsK(l.k))
                            .font(S.inter(15, S.wBoldN)).tracking(S.track(15, -0.01))
                            .foregroundStyle(S.ink)
                            .frame(width: Self.legCol, alignment: .leading)
                        Text(l.atm ? "at the money" : "at 1 SD")
                            .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(format: "%.2f", l.cr))
                            .font(S.inter(S.t13, S.wSemiN)).foregroundStyle(S.ink)
                        Text(String(format: "%.2f%%", l.onK))
                            .font(S.inter(S.t13, l.atm ? S.wBoldN : S.wSemiN))
                            .foregroundStyle(l.atm ? (l.onK >= q.floor ? S.gainText : S.lossText) : S.mute)
                            .frame(width: Self.legPct, alignment: .trailing)
                    }
                    .lineLimit(1)
                    .frame(width: Self.inner, height: 15)
                    .rsRise(shown, rise(130 + Double(i) * 30))
                }
                /* What he has already written for this Friday, muted: the
                   suggestion above is only what is left. */
                ForEach(Array(w.done.enumerated()), id: \.offset) { i, d in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(d.n) \u{00D7} " + rsK(d.k))
                            .font(S.inter(15, S.wBoldN)).tracking(S.track(15, -0.01))
                            .foregroundStyle(S.mute)
                            .frame(width: Self.legCol, alignment: .leading)
                        Text("already sold")
                            .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .lineLimit(1)
                    .frame(width: Self.inner, height: 15)
                    .rsRise(shown, rise(130 + Double(w.legs.count + i) * 30))
                }
            }
        }
    }

    /// `BY FRI` and the span, the one place distance is summed up.
    private var byFri: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            eyebrow("By Fri")
            Spacer(minLength: 0)
            Text((span < 0 ? "\u{2212}" : "+") + String(format: "%.1f", abs(span))
                 + "% end to end")
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
        }
        .lineLimit(1)
        .frame(width: Self.inner, height: 14.5)
    }

    // MARK: the graph (301 × 114)

    private struct Level {
        let x: Double, v: String, word: String, ink: Color, tick: Color, delay: Double
    }
    private var levels: [Level] {
        if let w = q.write {
            return w.levels.enumerated().map { i, l in
                let ink: Color = l.tone == .loss ? S.lossText : l.tone == .mute ? S.mute : S.ink
                let tick: Color = l.tone == .loss ? S.lossBar : l.tone == .mute ? S.hair : S.ink
                return Level(x: l.x, v: l.fig, word: l.word, ink: ink, tick: tick,
                             delay: 200 + Double(i) * 40)
            }
        }
        return [Level(x: q.x.k, v: rsK(q.k), word: "strike", ink: S.ink, tick: S.ink, delay: 200),
         Level(x: q.x.be, v: q.fig(q.be), word: "break-even", ink: S.ink, tick: S.ink, delay: 240),
         Level(x: q.x.tgt, v: q.fig(q.tgt), word: (q.call ? "+" : "\u{2212}") + "1 SD",
               ink: S.lossText, tick: S.lossBar, delay: 280),
         Level(x: q.x.avg, v: q.fig(q.avg), word: "20-day", ink: S.mute, tick: S.hair, delay: 320)]
    }

    /* Every mark placed with `.position` in a fixed 301 × 114 box: a label's
       centre IS its tick's x. y from the graph's top: spot label 0 (15.5 tall),
       spot tick 18, band 34 (12), level ticks 52, labels 78 (32.5 tall). */
    private var graph: some View {
        ZStack(alignment: .topLeading) {
            band.position(x: Self.inner / 2, y: 34 + 6)
            Text(q.fig(q.spot))
                .font(S.inter(S.t13, S.wBoldN)).foregroundStyle(S.ink)
                .fixedSize()
                .position(x: at(spotX), y: 7.75)
                .rsRise(shown, rise(180))
            tick(S.ink)
                .position(x: at(spotX), y: 18 + 5)
                .rsRise(shown, rise(180))
            ForEach(Array(levels.enumerated()), id: \.offset) { _, lv in
                tick(lv.tick)
                    .position(x: at(lv.x), y: 52 + 5)
                    .rsRise(shown, rise(lv.delay))
                VStack(spacing: 0) {
                    Text(lv.v).font(S.inter(15, S.wBoldN)).tracking(S.track(15, -0.01))
                        .foregroundStyle(lv.ink)
                    Text(lv.word).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(lv.ink)
                }
                .fixedSize()
                .position(x: at(lv.x), y: 78 + 16.25)
                .rsRise(shown, rise(lv.delay))
            }
        }
        .frame(width: Self.inner, height: Self.graphH, alignment: .topLeading)
    }

    private var spotX: Double { q.write?.spotX ?? q.x.spot }
    private var zones: [RollZone] { q.write?.zones ?? q.zones }
    private var span: Double { q.write?.span ?? q.span }

    private func tick(_ c: Color) -> some View {
        Rectangle().fill(c).frame(width: 2, height: 10)
    }

    /// One 12pt bar: solid zone inks on the track, a 1pt ring painted over them.
    private var band: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(S.rsTrack)
            ForEach(zones) { z in
                Rectangle().fill(tone(z.tone))
                    .frame(width: at(z.w))
                    .offset(x: at(z.l))
            }
        }
        .frame(width: Self.inner, height: 12, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(S.rsTrackEdge, lineWidth: 1))
        .scaleEffect(x: shown || reduceMotion ? 1 : 0, anchor: .leading)
        .animation(rise(120), value: shown)
    }

    // MARK: open interest

    private var oiHead: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            eyebrow("Open interest")
            Spacer(minLength: 0)
            Text((q.call ? "calls" : "puts") + " \u{00B7} next Fri")
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
        }
        .lineLimit(1)
        .frame(width: Self.inner, height: 14.5)
    }

    /// Five strikes, a faint fill each: a table, not buttons. On the call
    /// write the two chosen strikes keep the fill and take a 1.5 ink ring.
    private var tiles: some View {
        let ts: [RollWrite.Tile] = q.write?.tiles
            ?? q.oi.map { RollWrite.Tile(k: $0.k, oi: $0.oi, chosen: false) }
        return HStack(spacing: 6) {
            ForEach(Array(ts.enumerated()), id: \.offset) { _, o in
                VStack(spacing: 4) {
                    Text(rsK(o.k)).font(S.inter(15, S.wBoldN)).tracking(S.track(15, -0.01))
                        .foregroundStyle(S.ink)
                    Text(rsOI(o.oi)).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                /* A 6% ink fill on the glass, never a glass of its own:
                   glass on glass muddies the hierarchy. */
                .background(S.rsTileFill,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    if o.chosen {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(S.ink, lineWidth: 1.5)
                    }
                }
            }
        }
        .frame(width: Self.inner)
    }

    // MARK: footer

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            /* ⚠ THE WORD GOES BEFORE THE FIGURES DO. Real books run "645 → −219",
               wider than the sheet's "120 → 90", and the reference's ellipsis
               then cut the after figure, the one number the line is for. When
               the sentence does not fit it drops "positive". */
            if let w = q.write {
                /* ⚠ AFTER BOTH LEGS, and the sign word is gone: the arrow
                   carries it, and "positive" pushed the row past the column. */
                /* ⚠ THE WORDS GO BEFORE THE FIGURES DO. A real book runs
                   "383 → −1117" beside "earnings in 1 day" and the row ran
                   past the column; it drops to "Delta" and then the figures. */
                if let now = q.deltaNow, let after = w.deltaAfter {
                    ViewThatFits(in: .horizontal) {
                        ForEach(["Delta, both legs \u{00B7} ", "Delta ", ""], id: \.self) { word in
                            (Text(word).font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
                             + Text("\(Int(now.rounded())) \u{2192} \(rsSigned(after))")
                                .font(S.inter(S.t13, S.wBoldN)).foregroundStyle(S.ink))
                                .lineLimit(1).fixedSize()
                        }
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    deltaLine(long: true)
                    deltaLine(long: false)
                }
            }
            Spacer(minLength: 0)
            if let e = q.earn {
                Text(earnText(e))
                    .font(S.inter(S.t13, S.wSemiN))
                    .foregroundStyle(e <= 7 ? S.warn : S.mute)
                    .lineLimit(1).fixedSize()
            }
        }
        .frame(width: Self.inner, height: 15.5, alignment: .leading)
    }

    /// Inside a week, the count; past it, the date word (`earnings 12 Nov`).
    /// The put sheet keeps the count it always had.
    private func earnText(_ e: Int) -> String {
        if e == 0 { return "earnings today" }
        if e <= 7 || q.write == nil { return "earnings in \(e) day\(e == 1 ? "" : "s")" }
        return "earnings " + (rsEarnWord(inDays: e)?.word ?? "in \(e) days")
    }

    @ViewBuilder private func deltaLine(long: Bool) -> some View {
        if let now = q.deltaNow, let after = q.deltaAfter {
            let word = long
                ? "Delta " + (after > 0 ? "positive" : after < 0 ? "negative" : "flat") + " \u{00B7} "
                : "Delta "
            (Text(word).font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
             + Text("\(Int(now.rounded())) \u{2192} \(rsSigned(after))")
                .font(S.inter(S.t13, S.wBoldN)).foregroundStyle(S.ink))
                .lineLimit(1).fixedSize()
        }
    }
}

/// A delta figure with a true minus, never a hyphen.
private func rsSigned(_ v: Double) -> String {
    let i = Int(v.rounded())
    return i < 0 ? "\u{2212}\(-i)" : "\(i)"
}

// MARK: - the host

/* ⚠ FROM THE BOTTOM OF THE SCREEN, NOT OUT OF THE CARD. Nik, 23 Sep 2026:
   "card should be like a native style from the bottom of the screen". The
   panel is export 26's, unchanged; only where it lives moved. It floats 8
   above the home indicator over a full-screen dim, rises in .32s, and closes
   on a tap outside, a tap on the handle, or a swipe down, the way every sheet
   on the phone does. A system sheet was tried first and reserved a padded band
   under the footer that read as a gap; this host owns its own height. */
struct RollSheetHost: View {
    let q: RollQuote
    var updating = false
    let onDismissed: () -> Void
    @State private var up = false
    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The panel's measured height; a drag past 30% of it closes.
    private static let height: CGFloat = 520

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottom) {
                /* The dim fades in .25s, the panel rises in .32s (the spec's
                   two timings), and the dim is light on purpose. */
                S.rsScrim
                    .opacity(up ? 1 : 0)
                    .animation(reduceMotion ? nil : S.easeSettle(0.25), value: up)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                if up {
                    SunnyRollSheet(q: q, updating: updating, onClose: close)
                        .offset(y: max(0, drag))
                        .gesture(
                            DragGesture()
                                .onChanged { drag = $0.translation.height }
                                .onEnded { v in
                                    if max(v.translation.height, v.predictedEndTranslation.height)
                                        > Self.height * 0.3 {
                                        close()
                                    } else {
                                        withAnimation(S.easeSettle(0.3)) { drag = 0 }
                                    }
                                })
                        /* ⚠ 12 FROM THE PHYSICAL EDGE, NOT 12 ABOVE THE SAFE
                           AREA. Nik, 23 Sep: "bottom spacing is too much". 12
                           plus the home indicator's 34 left 70 under the
                           footer; the panel floats over the indicator the way
                           the system's own sheets do, concentric with the
                           device corner. */
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .offset(y: 12)))
                }
            }
            .frame(width: g.size.width, height: g.size.height + g.safeAreaInsets.bottom,
                   alignment: .bottom)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear { withAnimation(reduceMotion ? nil : S.easeSettle(0.32)) { up = true } }
    }

    private func close() {
        withAnimation(reduceMotion ? nil : S.easeSettle(0.32)) { up = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.32)) { onDismissed() }
    }
}

private extension View {
    /// The sheet's blocks rise 6 and fade in, staggered.
    func rsRise(_ shown: Bool, _ animation: Animation?) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .animation(animation, value: shown)
    }
}
