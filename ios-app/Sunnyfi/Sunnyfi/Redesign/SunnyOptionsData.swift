//
//  SunnyOptionsData.swift
//  Sunny — the options cards' one contract.
//
//  Build sheet: OPTIONS-CARDS.md. One payload feeds both surfaces, because the
//  weekly-yield card's last bar must equal the yield-progress card's "this
//  week" figure and two endpoints would let them drift.
//

import SwiftUI

@Observable
final class OptionsStore {
    private(set) var data: OptionsPayload?
    private(set) var error: String?
    private(set) var loading = false
    private var loadedAt: Date?
    /// Freshness (hold until seen): Inventory's figures that moved on a pull.
    let invFresh = FreshTrack()
    let posFresh = FreshTrack()
    let alFresh = FreshTrack()
    let wyFresh = FreshTrack()

    /// Version bumps on every load so a screen model can key its cache off it.
    private(set) var version = 0

    func load(force: Bool = false) async {
        if loading { return }
        if !force, let at = loadedAt, Date().timeIntervalSince(at) < 300 { return }
        loading = true; defer { loading = false }
        do {
            var r = URLRequest(url: URL(string: Secrets.supabaseURL
                + "/functions/v1/options-cards")!)
            r.httpMethod = "POST"
            r.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
            r.setValue("Bearer " + Secrets.supabasePublishableKey,
                       forHTTPHeaderField: "Authorization")
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = Data("{}".utf8)
            let (d, _) = try await URLSession.shared.data(for: r)
            let p = try JSONDecoder().decode(OptionsPayload.self, from: d)
            /* Verification only: `-freshTest` starts from a doctored copy of this
               pull, so the real one lands as a change and every card's marks can
               be seen without waiting for a trade. */
            if data == nil, ProcessInfo.processInfo.arguments.contains("-freshTest"),
               let old = Self.doctored(d) {
                posFresh.observe(SunnyPositions.freshFigs(old.positions, old.longLegs?.legs ?? []))
                if let al = old.allocationCard { alFresh.observe(SunnyAllocation.freshFigs(al)) }
                wyFresh.observe(SunnyWeeklyYield.freshFigs(old.book))
                data = old
            }
            /* The first load is the baseline and marks nothing. */
            invFresh.landed(data?.inventoryCard.flatMap { o in
                p.inventoryCard.map { Self.invDiff(o, $0) } } ?? [:])
            posFresh.observe(SunnyPositions.freshFigs(p.positions, p.longLegs?.legs ?? []))
            if let al = p.allocationCard {
                alFresh.observe(SunnyAllocation.freshFigs(al), closeKey: ("a:#total", "inv"))
            }
            wyFresh.observe(SunnyWeeklyYield.freshFigs(p.book))
            data = p
            /* ⚠ THE LOADING SCREEN NEEDS THETA BEFORE THETA ARRIVES, so the
               last good answer is kept here rather than fetched again. */
            SunnyWait.remember(p)
            error = nil; loadedAt = Date(); version &+= 1
        } catch { self.error = String(describing: error) }
    }

    /// `-freshTest`'s baseline: one fewer call sold on the first name, $1k less
    /// invested on the first allocation name, the first short leg missing, and
    /// the last week's credit $100 lower.
    static func doctored(_ d: Data) -> OptionsPayload? {
        guard var j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        if var inv = j["inventoryCard"] as? [String: Any], var sold = inv["sold"] as? [String: Any],
           var calls = sold["calls"] as? [[String: Any]], let i = calls.firstIndex(where: { ($0["sold"] as? Int ?? 0) > 0 }) {
            calls[i]["sold"] = (calls[i]["sold"] as? Int ?? 1) - 1
            sold["calls"] = calls; inv["sold"] = sold; j["inventoryCard"] = inv
        }
        if var al = j["allocationCard"] as? [String: Any], var book = al["book"] as? [[String: Any]], !book.isEmpty {
            book[0]["inv"] = (book[0]["inv"] as? Double ?? 0) + 1000
            al["book"] = book; j["allocationCard"] = al
        }
        if var ps = j["positions"] as? [[String: Any]],
           let i = ps.firstIndex(where: { ($0["shorts"] as? [Any])?.isEmpty == false }),
           var sh = ps[i]["shorts"] as? [Any] {
            sh.removeFirst(); ps[i]["shorts"] = sh; j["positions"] = ps
        }
        if var bk = j["book"] as? [String: Any], var wk = bk["weekly"] as? [[String: Any]],
           let i = wk.lastIndex(where: { ($0["current"] as? Bool) == true }) {
            for f in ["credit", "gross"] { if let v = wk[i][f] as? Int { wk[i][f] = v - 100 } }
            bk["weekly"] = wk; j["book"] = bk
        }
        guard let out = try? JSONSerialization.data(withJSONObject: j) else { return nil }
        return try? JSONDecoder().decode(OptionsPayload.self, from: out)
    }

    /// Inventory, per side and name: `sold` and the credit (`cr`, which the $
    /// and % lenses both print from). A new name is `added`; a gone name marks
    /// only the Total. The Total is marked when a row on its side moved and
    /// the total itself moved.
    static func invDiff(_ a: InventoryCard, _ b: InventoryCard) -> [String: Set<String>] {
        var out: [String: Set<String>] = [:]
        for (k, o, n) in [("c", a.sold.calls, b.sold.calls), ("p", a.sold.puts, b.sold.puts)] {
            var any = false
            for r in n {
                guard let q = o.first(where: { $0.t == r.t }) else {
                    out["\(k):\(r.t)"] = ["added"]; any = true; continue
                }
                var f: Set<String> = []
                if q.sold != r.sold { f.insert("sold") }
                if q.cc != r.cc || q.cr != r.cr { f.insert("cr") }
                if !f.isEmpty { out["\(k):\(r.t)"] = f; any = true }
            }
            if o.contains(where: { q in !n.contains { $0.t == q.t } }) { any = true }
            guard any else { continue }
            let sold = { (x: [InvSold]) in x.reduce(0) { $0 + $1.sold } }
            let usd = { (x: [InvSold]) in x.reduce(0) { $0 + $1.sold * ($1.cc ?? 0) } }
            var t: Set<String> = []
            if sold(o) != sold(n) { t.insert("sold") }
            if usd(o) != usd(n) { t.insert("cr") }
            if !t.isEmpty { out["\(k):#total"] = t }
        }
        return out
    }
}

/// ⚠ CUMULATIVE AND IT NEVER RESETS. Nik, 2026-09-06: "It's a continous
/// process when new stock is added new puts are added so not it never resets
/// its continuous." Buying a tranche raises `cost` and drops the ring; the
/// weeklies climb it back. `collected` is short-PUT premium only — call
/// premium is already Yield progress's numerator and cannot discharge two
/// obligations at once.
struct PutCover: Decodable {
    let names: Int, puts: Int
    let cost: Int, collected: Int, left: Int, pace: Int
    let pct: Double
    /// 0 when already covered, or when no pace has been established yet.
    let weeksToCover: Int
    /// ⚠ THE HEDGE HAS A DEADLINE. `weeksLeft` counts to the EARLIEST long-put
    /// expiry and `need` is what it takes per week to clear `left` before it.
    /// A projection past that date describes a world where the thing being
    /// paid off still exists. Optional so an older deployment decodes.
    let expiry: String?
    let weeksLeft: Int?
    let need: Int?
    /// Borrowed, 14 Sep 2026 (`cover-rings`): the ticks outside the ring are
    /// PUTS still writeable, never calls-plus-puts the way Prices ships `free`,
    /// or the hedge would wear the call side's room as its own. `move` is the
    /// book's 1-week move exactly as Prices prints it.
    let free: Int?
    let move: Double?
}

/// ⚠ THE TWIN OF THE PUT RING, and the book-level reading of Yield progress:
/// what the LEAP calls cost against the short-call credit banked toward them.
/// `collected` is CALL premium only — short-put credit is the put ring's, the
/// other half of Nik's 2026-09-06 rule. Null until a LEAP is held.
struct CallCover: Decodable {
    let names: Int
    let cost: Int, collected: Int, left: Int, pace: Int
    let pct: Double
    /// 0 when already covered, or when no pace has been established yet.
    let weeksToCover: Int
    /// ⚠ THE WEEK IT IS COVERED, not a count of weeks. A count makes the reader
    /// do arithmetic the card has already done, and do it wrong: Nik read 36
    /// weeks as early May and it is the 24th. Always a Monday, derived from
    /// this week's. Null when there is no pace to project from.
    let by: String?
    let free: Int?
    let move: Double?
}

struct OptionsPayload: Decodable {
    let ok: Bool
    let date: String
    let book: OptionsBook
    let positions: [OptionsPosition]
    /// Null until a long put is held. A ring at 0% of $0 is not an empty
    /// state, it is a card with no subject, so the page drops it.
    let putCover: PutCover?
    /// Optional so a run against an older deployment decodes rather than throws.
    let callCover: CallCover?
    /// Optional so a run against an older deployment decodes rather than throws.
    let prices: PricesBlock?
    let inventory: [InventoryRow]?
    /// Credit & theta. Optional so a run against an older deployment decodes
    /// rather than throws.
    let creditTrend: CreditTrendBlock?
    /// Inventory, four tabs (`export 20`). Optional so a run against an older
    /// deployment decodes rather than throws.
    let inventoryCard: InventoryCard?
    /// Allocation (`export 23`). Optional so a run against an older
    /// deployment decodes rather than throws.
    let allocationCard: AllocationCard?
    /// The roll sheet's chain (`export 24`). Optional for the same reason.
    let rollCard: RollCard?
    /// Optional so a run against an older deployment decodes rather than throws.
    let intrinsic: IntrinsicBlock?
    let yieldProgress: YieldProgressBlock?
    let longLegs: LongLegsBlock?
    /// Optional so a run against an older deployment decodes rather than throws.
    let coverBars: CoverBarsBlock?
    /* handoff-final/, 10 Sep 2026. All optional so a run against an older
       deployment decodes rather than throws. */
    let programme: ProgrammeBlock?
    let premium: PremiumBlock?
    let toRoll: ToRollBlock?
}

/// ⚠ NOTHING HERE IS A STORED TOTAL. `mark`, `net` and `banked` are derived, so
/// a corrected component moves the hero with it. The card's whole claim is that
/// `banked + open + mark == net`; a hero that can disagree with its own footer
/// is the one defect that would make it worthless.
struct ProgrammeRow: Decodable, Identifiable {
    let t: String
    let kept: Int, calls: Int, puts: Int, invested: Int
    /// ⚠ OPEN REPLACES OWED, 17 Sep 2026. Credit taken on short legs that are
    /// still open: not earned, never added to `kept`, and the same money
    /// Coverage draws as its lighter cap. Optional so a run against an older
    /// deployment decodes rather than throws.
    let open: Int?
    var id: String { t }
    var mark: Int { calls + puts }
    var net: Int { kept + mark }
    /// Settled credit is the banked figure now; nothing open is in it.
    var banked: Int { kept }
    var pct: Double { invested > 0 ? Double(net) / Double(invested) * 100 : 0 }
}

struct ProgrammeBlock: Decodable {
    /// ⚠ TWO RATES, NOT ONE NET. Programme apportions theta to a name by its
    /// share of kept (short) and of invested (long), which a single netted
    /// figure cannot do. Short is positive, long negative, both a day.
    let thetaShortDay: Int, thetaLongDay: Int
    /// ⚠ 31 AUGUST, the LEAP shift. Nik, 2026-09-10. The handoff said 20 May,
    /// but the credits then ran back to when he still held shares while the
    /// denominator is the LEAPs and puts he holds now.
    let since: String
    let rows: [ProgrammeRow]
}

/// ⚠ A MULTIPLE OF ITS OWN USUAL, NEVER A PERCENTILE. The rank is what made the
/// earlier version unreadable.
/// ⚠ ONE ROW A NAME, AND THE DENOMINATOR IS TIME VALUE. `export 13`,
/// 14 Sep 2026. The 2 Sep card read `collected / paid` and ranked every name
/// against the book's average — a card about how far along each name was on a
/// road whose end was the wrong place. Intrinsic is money exercising returns;
/// only the part that melts has to be earned back. Call cover's rule, one name
/// at a time, and the two cards read one book.
/// ⚠ ONE LEDGER, TWO CARDS. `export 14`, 14 Sep 2026. Long legs draws these;
/// Programme derives its Long calls, Long puts and invested from the same
/// array, so the two cards cannot disagree by a dollar. Never give Programme
/// its own copy of those three figures.
///
/// Every figure is PER CONTRACT in dollars, to the cent. Whole dollars here
/// are multiplied by `n` and put the footer's Paid $14 away from Intrinsic
/// value's.
struct LongLeg: Decodable, Identifiable {
    let t: String, k: String, n: Int
    let cost: Double, m: Double, w1: Double, w2: Double, w4: Double
    /// ⚠ REALIZED ON CONTRACTS ALREADY SOLD BACK, dollars, negative a loss.
    /// Nik, 18 Sep 2026: `cost` is now what the contracts still held cost, first
    /// in first out, so a round trip's loss no longer hides inside the price.
    /// Performance adds this back to its side's row so the net does not move.
    /// Optional so a run against an older deployment decodes.
    let rz: Double?
    var id: String { "\(t)|\(k)" }
    /// The side is the last letter of the strike and nothing else about it is
    /// read. A row is a name and a side, never a strike.
    var isCall: Bool { !k.hasSuffix("P") }
    /// A leg younger than a window carries its cost in the missing slot, so
    /// `life` and that window read the same rather than drawing out of nothing.
    func at(_ w: LongWindow) -> Double {
        switch w {
        case .w1: return w1
        case .w2: return w2
        case .w4: return w4
        case .life: return cost
        }
    }
}

enum LongWindow: String, CaseIterable {
    case w1, w2, w4, life
    var word: String {
        switch self {
        case .w1: return "1w"
        case .w2: return "2w"
        case .w4: return "4w"
        case .life: return "life"
        }
    }
    var phrase: String { self == .life ? "since bought" : "over \(word)" }
}

struct LongLegsBlock: Decodable {
    let asOf: String
    let legs: [LongLeg]
}

/// One name and one side: every long call on PEP is ONE position. The strike is
/// a fact about the contract; the reader's question is about the name.
struct LongPosition: Identifiable {
    let t: String, isCall: Bool, legs: [LongLeg]
    var id: String { "\(t)|\(isCall)" }
    var side: String { isCall ? "Calls" : "Puts" }
    var n: Int { legs.reduce(0) { $0 + $1.n } }
    var paid: Double { legs.reduce(0) { $0 + $1.cost * Double($1.n) } }
    var now: Double { legs.reduce(0) { $0 + $1.m * Double($1.n) } }
    func then(_ w: LongWindow) -> Double {
        legs.reduce(0) { $0 + $1.at(w) * Double($1.n) }
    }
    func made(_ w: LongWindow) -> Double { now - then(w) }
    /// Nil where the window has no base to measure from, rather than a zero
    /// that would draw a bar.
    func change(_ w: LongWindow) -> Double? {
        let t0 = then(w)
        return t0 > 0 ? now / t0 - 1 : nil
    }
    /// The average mark a contract, the figure column's third reading.
    var markEach: Double { n > 0 ? now / Double(n) : 0 }

    static func all(_ legs: [LongLeg]) -> [LongPosition] {
        var out: [LongPosition] = []
        for t in legs.map(\.t).reduced() {
            for call in [true, false] {
                let ls = legs.filter { $0.t == t && $0.isCall == call }
                if !ls.isEmpty { out.append(LongPosition(t: t, isCall: call, legs: ls)) }
            }
        }
        return out
    }
}

private extension Array where Element == String {
    /// First-seen order, no duplicates.
    func reduced() -> [String] {
        var seen = Set<String>(), out: [String] = []
        for x in self where seen.insert(x).inserted { out.append(x) }
        return out
    }
}

struct YieldName: Decodable, Identifiable {
    /// ⚠ CLAMPED AT ZERO BY THE SERVER. KR's LEAP is $26 deep in the money and
    /// marks below intrinsic, so its raw time value is −$109. A negative bar
    /// has no width and a ratio against a negative number says nothing; the
    /// truth is that premium has nothing left to earn back there.
    let t: String, time: Int, collected: Int, pace: Int, melt: Int
    let rolling: Bool
    /// The close at which this name's credit first crossed its time value.
    /// From the ledger, never recomputed here; null while it is still chasing.
    let coveredOn: String?
    var id: String { t }

    var covered: Bool { collected >= time }
    /// The gap the premium still has to close, in dollars.
    var gap: Int { time - collected }
    /// ⚠ NIL WHERE TIME VALUE IS ZERO, and the card prints the dollar gap
    /// instead. A percentage of nothing is not a reading.
    var ratio: Double? { time > 0 ? Double(collected) / Double(time) : nil }
    /// Both forces at once: premium landing at this name's pace and its own
    /// time value melting. The same division Call cover does for the book.
    var days: Int? {
        let perDay = Double(pace) / 7 + Double(melt)
        guard gap > 0, perDay > 0 else { return nil }
        return Int((Double(gap) / perDay).rounded(.up))
    }
}

struct YieldProgressBlock: Decodable {
    let asOf: String
    let names: [YieldName]
}

struct PremiumRow: Decodable, Identifiable {
    let t: String
    let now: Double, usual: Double, low: Double, high: Double
    let days: Int
    /// ⚠ WHAT A 30-DELTA WEEKLY CALL PAYS A CONTRACT, priced twice — at today's
    /// IV and at the name's own usual — so the difference is vol and nothing
    /// else: same spot, same tenor, same delta. The assumptions are choices and
    /// are stated on the server: seven days because the book sells weeklies,
    /// zero rate, no dividend. Optional so an older deployment decodes.
    let pay: Int?, payU: Int?
    /// Borrowed: Left to sell's writeable contracts, and Prices' 1-week move.
    let free: Int?, move: Double?
    var id: String { t }
    var mult: Double { usual > 0 ? now / usual : 0 }
    /// Where the name's usual sits on its own range, 0...1.
    var posUsual: Double { high > low ? (usual - low) / (high - low) : 0.5 }
    var posNow: Double { high > low ? (now - low) / (high - low) : 0.5 }
}

/// ⚠ THE LONG LEGS ONLY. A short leg's intrinsic is money OWED, which inverts
/// every colour on the card; short-leg moneyness is the roll check's job.
struct IntrinsicLeg: Decodable, Identifiable {
    let k: String, label: String, sub: String
    let mark: Int, paid: Int, intr: Int
    var id: String { k }
    /// Derived, never stored: the rest of the mark once intrinsic is out.
    var time: Int { mark - intr }
    /// Signed. Negative is lost, positive is gained.
    var pnl: Int { mark - paid }
    /// ⚠ THE WHOLE IS max(paid, mark), NOT PAID. The sheet cuts PAID into
    /// intrinsic + time + lost, which only holds while the leg is DOWN. The
    /// long puts are up today, and there intrinsic + time already exceed paid,
    /// so the three shares would sum past 100% and the bar would draw off its
    /// own track. Down, the two are the same thing and nothing changes.
    var whole: Int { max(paid, mark) }
}

struct LongStrike: Decodable {
    let k: Double, exp: String
}

struct IntrinsicRow: Decodable, Identifiable {
    let t: String
    let call: LongStrike?, put: LongStrike?
    var id: String { t }
}

/// ⚠ ONLY TIME VALUE HAS TO BE COVERED, and that is the whole idea. The rings
/// measured credit against the whole COST of the long legs, which is the wrong
/// denominator: a long leg's intrinsic is real money — exercising returns it —
/// so premium only has to earn back the part that melts.
struct CoverSide: Decodable {
    let label: String, scope: String
    let names: Int
    /// mark less intrinsic, the Intrinsic card's own figure, so the two cards
    /// read one book rather than deriving "time value" twice.
    let time: Int
    /// The same figure at an earlier close. Null where no leg of this side was
    /// being priced that day: the history does not reach back yet, and a zero
    /// would draw the ghost on the floor and claim the whole bar melted.
    let hist: CoverHist
    let collected: Int
    /// ⚠ CREDIT ON LEGS STILL OPEN, and it is NOT part of `collected`. Nik,
    /// 17 Sep 2026: everywhere but Positions, Weekly yield and Credit & theta
    /// counts settled legs only, because an open leg's credit can still be
    /// handed back. The card draws this as a lighter cap above the solid bar.
    /// Optional so a run against an older deployment decodes rather than throws.
    let open: Int?
    let chist: CoverHist
    /// This week's realised credit — the rate the gap closes from the right.
    let pace: Int
    /// Time value lost a day at the current theta, positive — the rate it
    /// closes from the left.
    let melt: Int

    var gap: Int { time - collected }
    var covered: Bool { gap <= 0 }
    /// The two rates together. Null when neither side is moving.
    var daysToMeet: Int? {
        guard gap > 0 else { return 0 }
        let perDay = Double(pace) / 7 + Double(melt)
        return perDay > 0 ? Int((Double(gap) / perDay).rounded(.up)) : nil
    }
}
struct CoverHist: Decodable {
    let yday: Int?, week: Int?
}
struct CoverBarsBlock: Decodable {
    let asOf: String
    let sides: CoverSides
}
struct CoverSides: Decodable {
    let call: CoverSide, put: CoverSide
}

struct IntrinsicBlock: Decodable {
    let legs: [IntrinsicLeg], rows: [IntrinsicRow]
}

struct PremiumBlock: Decodable {
    /// How much history actually exists, so the card can label itself honestly
    /// rather than claiming a year it does not have.
    let days: Int
    let rows: [PremiumRow]
}

struct RollLeg: Decodable, Identifiable {
    let t: String, side: String
    let n: Int
    let strike: Double
    let sold: Int, now: Int
    let exp: String
    var id: String { "\(t)-\(side)-\(strike)-\(exp)" }
    var loss: Int { now - sold }
    var lossPct: Double { sold > 0 ? Double(loss) / Double(sold) * 100 : 0 }
}

/// ⚠ PER NAME, NOT PER LEG, which is why the card labels it ALL TIME. Nik read
/// "Kept $4,035" as belonging to the $110 put beside it and asked where the
/// card said otherwise; it did not.
struct RollName: Decodable {
    let collected: Int, given: Int, leap: Int
    var kept: Int { collected - given }
}

struct ToRollBlock: Decodable {
    /// The same figure Weekly yield prints, so the page agrees with itself.
    let week: Int
    let legs: [RollLeg]
    let names: [String: RollName]
}

/// ⚠ HELD AND SOLD ARE BOTH CURRENTLY OPEN, and `held - sold` is the only
/// derived figure on the inventory card — never stored, so a corrected count
/// fixes every chip, both footer figures and the header in one edit.
struct InventoryRow: Decodable, Identifiable {
    let t: String
    let callsHeld: Int, callsSold: Int, putsHeld: Int, putsSold: Int
    var id: String { t }
    var openCalls: Int { callsHeld - callsSold }
    var openPuts: Int { putsHeld - putsSold }
    /// What can still be sold on this name. The chip order is this, descending.
    var room: Int { openCalls + openPuts }
    var held: Int { callsHeld + putsHeld }
    var sold: Int { callsSold + putsSold }
}

/// ⚠ THE WINDOWS COUNT TRADING SESSIONS, NOT CALENDAR DAYS. A week is five
/// sessions, so "1 week" means the same thing in a holiday week as in any
/// other. `today` is spot against the latest close.
struct PriceMove: Decodable {
    let today: Double?, w1: Double?, w2: Double?, w3: Double?, w4: Double?
    func value(_ w: PriceWindow) -> Double? {
        switch w {
        case .today: return today
        case .w1:    return w1
        case .w2:    return w2
        case .w3:    return w3
        case .w4:    return w4
        }
    }
}

enum PriceWindow: String, CaseIterable, Identifiable {
    case today, w1, w2, w3, w4
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: return "Today"
        case .w1:    return "1W"
        case .w2:    return "2W"
        case .w3:    return "3W"
        case .w4:    return "4W"
        }
    }
    /// What the hero says it is measuring, in words the card can print.
    var phrase: String {
        switch self {
        case .today: return "today"
        case .w1:    return "over 1 week"
        case .w2:    return "over 2 weeks"
        case .w3:    return "over 3 weeks"
        case .w4:    return "over 4 weeks"
        }
    }
}

/// Today's implied volatility against the name's own median. Absent when the
/// name has too little history for a median to mean anything.
struct PriceIV: Decodable { let now: Double, usual: Double }

struct PriceRow: Decodable, Identifiable {
    let ticker: String
    /// Cost basis, the same weight the ticker strip uses.
    let weight: Int
    let pct: PriceMove
    /// The card's value column swaps to this on a tap. Nik, 2026-09-09:
    /// "When I tap on % can we show the stock price for each ticker".
    let spot: Double?
    /* ⚠ FOUR READINGS BORROWED FROM FOUR OTHER CARDS, and the card owns none of
       them. The design's first rule: price is the input, what the move did to
       you is the story. All five are optional so a run against an older
       deployment decodes rather than throws. */
    /// Inventory — contracts still writeable. 0 mutes the ticker.
    let free: Int?
    /// Upside left — net delta in share equivalents, signed. The move in
    /// dollars is this times the per-share move.
    let delta: Int?
    /// Roll check — the nearest sold call and put strikes, drawn as ticks.
    let callK: Double?
    let putK: Double?
    /// Premium now — the word under the ticker.
    let iv: PriceIV?
    var id: String { ticker }

    /// The thresholds Premium now prints, so the two cards cannot disagree.
    var ivWord: String? {
        guard let iv, iv.usual > 0 else { return nil }
        let m = iv.now / iv.usual
        return m >= 1.15 ? "rich IV" : m < 0.95 ? "thin IV" : "normal IV"
    }
    var ivRich: Bool {
        guard let iv, iv.usual > 0 else { return false }
        return iv.now / iv.usual >= 1.15
    }
}

struct PricesBlock: Decodable {
    let rows: [PriceRow]
    /// Weighted by cost, so it is what his MONEY did — the one thing the rows
    /// cannot say. Nik chose this over a plain mean, 2026-09-08.
    let book: PriceMove
    /// ⚠ THE DATE THE DAY WINDOW DESCRIBES, not simply the last close. It is
    /// today while a session is running and the last close's date otherwise,
    /// so the chip's word and its figures can never come apart.
    let asOf: String
    /// True while a session is running. The day window is then spot against the
    /// last close; otherwise it is the last close against the one before it.
    let live: Bool?
    /// ⚠ THE LAST COMPLETED SESSION, WHICH IS NOT `asOf`. While a session is
    /// running `asOf` is today; this is the thing that actually closed. The
    /// pull control prints it on done. Optional so an older deployment decodes.
    let lastClose: String?
}

struct OptionsBook: Decodable {
    /// ⚠ `paid` IS TOTAL INVESTED — LEAPs plus long puts. `leapPaid` is the
    /// LEAP half alone, kept for anything that means the calls specifically.
    let paid: Int, collected: Int, windowCredit: Int
    let leapPaid: Int?
    let weekly: [BookWeek]
    let avgPct: Double
    /// Weeks with a credit. The average divides by THIS, not by 8.
    let liveWeeks: Int
    let thisWeek: Int, bestWeek: Int
    /// ⚠ NOT A FORECAST. The eight-week average × 52. The one-word label the
    /// sheet mandates cannot carry that caveat, so it lives here.
    let yearly: Double
    let legs: Int
    /// `bars` ≤5 · `paged` 6–10 · `rows` 11+. The leg count picks it and
    /// nothing else does.
    let form: String
    let rolling: Int, nextExpiry: Int, kept: Int
    /// The roll check footer, computed server-side so it can never disagree
    /// with the weekly-yield card, which charts the same credit.
    let openCredit: Int?, openValue: Int?, openYield: Double?
    /// ⚠ WHICH WEEK THE OPEN LEGS ACTUALLY COVER, not an assumption that it is
    /// this one. On a weekend the ISO week that contains today is the one that
    /// just ENDED, so the card used to print "kept this week" over credit for
    /// legs expiring the following Friday.
    let openWhen: String?

    struct BookWeek: Decodable, Identifiable {
        let week: String, credit: Int, pct: Double
        /// ⚠ THE LIVE BAR IS NOT THE LAST ONE any more. The window reaches
        /// forward into weeks already sold, so the server says which column is
        /// the current week and the card must not infer it from an index.
        /// Optional so an older payload still decodes.
        let current: Bool?
        /* ⚠ GROSS AND BOUGHT-BACK ARE TWO FACTS, NOT ONE NET. The weekly-yield
           card draws the week's gross credit as the bar and what it cost to
           close legs as a red cap ON that bar, so a week that sold $9,527 and
           spent $2,377 buying back reads as both rather than as $7,150.
           `credit` is still the net and every other card uses it:
           gross − bought == credit, always. Optional so an older payload
           decodes. */
        let gross: Int?
        let bought: Int?
        /// What this week was measured against. A closed week keeps its own
        /// denominator, so a LEAP bought on a Tuesday cannot rewrite it.
        let denom: Int?
        var id: String { week }
    }
}

struct OptionsPosition: Decodable, Identifiable {
    let t: String, co: String
    let leap: String
    /// ⚠ TWO DIFFERENT QUANTITIES THAT USED TO SHARE A FIELD. `paid` is the
    /// LEAP's cost and only that, because `mark - paid` is its gain. `invested`
    /// is the capital this name has to earn back — the LEAP plus its long puts
    /// — and it is what every yield on the page divides by. Nik, 2026-09-08:
    /// "it shuold consider the total investment of the account not just calls."
    /// Optional so a run against an older deployment decodes rather than throws.
    let paid: Int, mark: Int
    let invested: Int?
    /// ⚠ A CHANGE IN MARK, NOT CASH THAT MOVED. A LEAP held all week moves no
    /// cash and still gains or loses every week.
    let markWeek: Int
    /// Every credit ever on the name, Nik's ruling. It predates the LEAP, which
    /// is why `windowCredit` exists beside it: the eight bars total THAT.
    let collected: Int
    let windowCredit: Int
    /// Weeks with a credit, the divisor for this name's average.
    let liveWeeks: Int
    let week: Int
    let weekly: [Int]
    let weeksRun: Int, weeksLeft: Int
    let longN: Int, shortN: Int
    let dLong: Double, dShort: Double
    /// Share equivalents, signed, with the two leg counts weighted separately —
    /// the book runs 15 long against 14 short on NFLX on purpose.
    let netDelta: Int
    let shorts: [ShortLeg]
    /// What this name last wrote at, per share. The ranking unit of Left to sell.
    let lastCr: Double?
    var id: String { t }

    struct ShortLeg: Decodable, Identifiable {
        let n: Int, k: Double, exp: String
        let credit: Int, value: Int
        /// THE ACTION. `verdictOf` reads this and nothing else. Already
        /// inverted server-side for a put, so the client never re-derives it.
        let itm: Bool
        /// "call" or "put". Optional so an older payload still decodes.
        let type: String?
        /// ⚠ FALSE MEANS NO MARK EXISTS YET, NOT BREAK-EVEN. An unpriced leg
        /// used to compute captured = 100%: a call sold minutes ago read as a
        /// perfect capture. The server now sends value == credit for those so
        /// they net to zero everywhere; this says not to believe the figure.
        let priced: Bool?
        /// THE MONEY, of the credit received. Disagrees with `itm` often, and
        /// that disagreement is the point.
        let captured: Int
        let delta: Double
        let contract: String
        /* ⚠ THE CREDIT PER SHARE THE LEG OPENED AT, the number quoted when the
           trade is placed and the only one comparable against a chain. The roll
           check prints it under an under-water strike, so the roll can be judged
           against what the next strike out pays today, and multiplies it by the
           captured percentage to turn that percentage into dollars. Optional so
           a run against an older deployment decodes. */
        let cr: Double?
        let opened: String?
        /// ⚠ WHAT IS STILL TO DECAY, not what the buy-back costs. `value` is
        /// the whole cost of closing the leg; this is the part that is time and
        /// comes back by expiry if nothing is done. The rest is intrinsic and
        /// is gone. On an out-of-the-money leg the two are the SAME number, and
        /// that is the reading: the whole remaining cost is decay he collects.
        /// Optional so a run against an older deployment decodes.
        let tv: Int?
        var id: String { "\(n)|\(k)|\(exp)|\(type ?? "")" }
        /// Strike + side, the roll check's row label: `77C`, `37.5P`.
        var label: String {
            let ks = k == k.rounded() ? String(Int(k)) : String(format: "%.1f", k)
            return ks + ((type ?? "call") == "put" ? "P" : "C")
        }
    }
}
