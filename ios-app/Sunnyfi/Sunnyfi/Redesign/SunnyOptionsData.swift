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
    let prices: PricesBlock?
    let inventory: [InventoryRow]?
    let credit: CreditBlock?
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
    var id: String { week }
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

struct PriceRow: Decodable, Identifiable {
    let ticker: String
    /// Cost basis, the same weight the ticker strip uses.
    let weight: Int
    let pct: PriceMove
    /// The card's value column swaps to this on a tap. Optional so a run
    /// against an older deployment decodes rather than throws.
    let spot: Double?
    var id: String { ticker }
}

struct PricesBlock: Decodable {
    let rows: [PriceRow]
    /// Weighted by cost, so it is what his MONEY did — the one thing the rows
    /// cannot say. Nik chose this over a plain mean, 2026-09-08.
    let book: PriceMove
    /// The close the windows are measured from.
    let asOf: String
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
        var id: String { "\(n)|\(k)|\(exp)" }
    }
}
