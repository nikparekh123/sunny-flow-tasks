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
            data = try JSONDecoder().decode(OptionsPayload.self, from: d)
            error = nil; loadedAt = Date(); version &+= 1
        } catch { self.error = String(describing: error) }
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
    let credit: CreditBlock?
    /// Optional so a run against an older deployment decodes rather than throws.
    let theta: ThetaBlock?
    /* handoff-final/, 10 Sep 2026. All optional so a run against an older
       deployment decodes rather than throws. */
    let programme: ProgrammeBlock?
    let premium: PremiumBlock?
    let upside: UpsideBlock?
    let toRoll: ToRollBlock?
}

/// ⚠ NOTHING HERE IS A STORED TOTAL. `mark`, `net` and `banked` are derived, so
/// a corrected component moves the hero with it. The card's whole claim is that
/// `banked + owed + mark == net`; a hero that can disagree with its own footer
/// is the one defect that would make it worthless.
struct ProgrammeRow: Decodable, Identifiable {
    let t: String
    let kept: Int, calls: Int, puts: Int, owed: Int, invested: Int
    var id: String { t }
    var mark: Int { calls + puts }
    var net: Int { kept + mark }
    /// `owed` is always <= 0, so this adds back what is still owed on open legs.
    var banked: Int { kept - owed }
    var pct: Double { invested > 0 ? Double(net) / Double(invested) * 100 : 0 }
}

struct ProgrammeBlock: Decodable {
    /// ⚠ 31 AUGUST, the LEAP shift. Nik, 2026-09-10. The handoff said 20 May,
    /// but the credits then ran back to when he still held shares while the
    /// denominator is the LEAPs and puts he holds now.
    let since: String
    let rows: [ProgrammeRow]
}

/// ⚠ A MULTIPLE OF ITS OWN USUAL, NEVER A PERCENTILE. The rank is what made the
/// earlier version unreadable.
struct PremiumRow: Decodable, Identifiable {
    let t: String
    let now: Double, usual: Double, low: Double, high: Double
    let days: Int
    var id: String { t }
    var mult: Double { usual > 0 ? now / usual : 0 }
    /// Where the name's usual sits on its own range, 0...1.
    var posUsual: Double { high > low ? (usual - low) / (high - low) : 0.5 }
    var posNow: Double { high > low ? (now - low) / (high - low) : 0.5 }
}

struct PremiumBlock: Decodable {
    /// How much history actually exists, so the card can label itself honestly
    /// rather than claiming a year it does not have.
    let days: Int
    let rows: [PremiumRow]
}

/// `share` is how much of the LEAP's own exposure survives everything sold
/// against it. It CAN exceed 100: a short put that goes into the money is long
/// delta, so it adds exposure back.
struct UpsideRow: Decodable, Identifiable {
    let t: String, share: Int
    var id: String { t }
}

struct UpsideBlock: Decodable {
    let move: Int
    let share: Double
    /// ⚠ `down` IS DELTA-ONLY AND THEREFORE WRONG AT THE EDGES. Long puts are
    /// convex, so a real fall is BETTER than this figure. Fixing it means
    /// running the payoff engine, not scaling this.
    let up: Int, down: Int
    let rows: [UpsideRow]
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

/// ⚠ `perShare` IS null, NOT 0, WHEN THE SIDE DID NOT TRADE THAT WEEK. Nik's
/// ruling 2026-09-08: no bar, key still shown. Zero would say "sold at nothing"
/// and would drag the plot's floor down, flattening the weeks that did trade.
struct CreditWeek: Decodable, Identifiable {
    let week: String, contracts: Int
    let perShare: Double?
    /// ⚠ THE CASH, SO THE CARD DIVIDES AND NEVER STORES AN AVERAGE. The blend
    /// across weeks is sum(cash) / sum(contracts) — a week with 105 contracts
    /// is not worth the same as a week with 46. Optional so a run against an
    /// older deployment decodes rather than throws.
    let cash: Int?
    var id: String { week }
    /// What one contract sold for that week. The unit the book is in: it holds
    /// LEAPs, not shares, so the contract price is the fill he sees.
    var perContract: Double? {
        guard let cash, contracts > 0 else { return nil }
        return Double(cash) / Double(contracts)
    }
}

/// ⚠ A DAY'S DECAY, AND THE INK IS THE SIGN. `long` is what the LEAPs and the
/// protective puts pay every day and is always negative; `short` is what the
/// sold legs collect and is always positive. Neither is good or bad news — the
/// comparison is the average line, not the hue.
struct ThetaWeek: Decodable, Identifiable {
    let week: String
    /// The day this week was actually read at — every week is measured the same
    /// number of days into itself, or a Monday would be compared to a Friday.
    let on: String
    let long: Int, short: Int
    var id: String { week }
    var net: Int { long + short }
}

struct ThetaBlock: Decodable {
    let weeks: [ThetaWeek]
    /// Prices' mean ABSOLUTE 1-week move. Decay is only free when the book sits
    /// still, and a book with one name up 6% and another down 6% has not.
    let move: Double?
}

struct CreditBlock: Decodable {
    let week: String
    let calls: [CreditWeek], puts: [CreditWeek]
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
        var id: String { "\(n)|\(k)|\(exp)|\(type ?? "")" }
        /// Strike + side, the roll check's row label: `77C`, `37.5P`.
        var label: String {
            let ks = k == k.rounded() ? String(Int(k)) : String(format: "%.1f", k)
            return ks + ((type ?? "call") == "put" ? "P" : "C")
        }
    }
}
