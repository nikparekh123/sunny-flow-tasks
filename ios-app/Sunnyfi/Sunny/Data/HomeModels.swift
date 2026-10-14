//
//  HomeModels.swift
//  Sunny
//
//  The Home payload, as `sunny-home` builds it into `home_snapshot` (one row,
//  rebuilt every 30 s). Snake-case keys decode with .convertFromSnakeCase;
//  anything the app does not use yet is simply not declared. Grows block by
//  block.
//

import Foundation

struct HomePayload: Decodable {
    let build: String
    let builtAt: String
    let today: String
    let tradingToday: Bool
    let calendar: [CalendarDay]
    let tradeTo415: [String]
    let fresh: Fresh
    let account: Account
    let indices: [Tape]
    let overnight: [Tape]
    let chart: Chart?
    let deck: Deck
    let lastWeek: LastWeek?
    let portfolio: [Holding]
    let watchlist: [Watch]
    let legs: [Leg]
    /// Hourly closes for the Positions Chart cards (blocks 12 and 13).
    let hours: Hours?
    let inventory: Inventory
    let writes: Writes
    let yield: [YieldWeek]
    let history: History
    let risk: Risk
    let payback: Payback
    let soldVsBought: SoldVsBought
    let performance: Performance
    let allocation: Allocation
    /// Every open theta check (block 15's breathing tile), not only today's card.
    let thetaChecks: [Deck.ThetaCheck]?
}

/// The last five sessions that have opened, 10:00 to 16:00 New York, seven
/// closes a session per ticker (nil where no quote), and the sessions still to
/// come in the next week (a sold card runs its empty hours into the expiry).
struct Hours: Decodable {
    let days: [String]
    let ahead: [String]
    let px: [String: [Double?]]
}

struct CalendarDay: Decodable, Hashable {
    let date: String
    let kind: String          // closed | early_close
    let closes: String?       // "13:00:00" on an early close
    let name: String
}

struct Fresh: Decodable {
    let marks: String?
    let quotes: String?
    let market: String?
    let trades: String?
    let accountClose: String?
}

struct Account: Decodable {
    let ok: Bool
    let value: Double?
    let today: Today?
    let marketValue: Double?
    let margin: Double?
    let cash: Double?
    let unrealized: Double?
    let timeValueSold: Double?
    let month: Period?
    let book: Period?
    let ibkrClose: IbkrClose?

    struct Today: Decodable { let amount: Double; let pct: Double?; let vs: String; let staleAnchor: Bool }
    struct Period: Decodable { let from: String; let realized: Double?; let commission: Double; let interest: Double }
    struct IbkrClose: Decodable { let date: String; let value: Double; let accounts: Int }
}

struct Tape: Decodable, Identifiable {
    var id: String { symbol }
    let symbol: String
    let label: String
    let state: String?
    let price: Double?
    let prevClose: Double?
    let changePct: Double?
    let change: Double?
    let pre: Double?
    let prePct: Double?
    let post: Double?
    let postPct: Double?
    let at: String?
}

struct LastWeek: Decodable {
    let weekStart: String
    let from: String
    let to: String
    let rows: [Row]
    let vix: Vix?
    struct Row: Decodable, Identifiable { var id: String { symbol }; let symbol: String; let changePct: Double?; let pricedMovePct: Double?; let close: Double? }
    struct Vix: Decodable { let close: Double; let changePct: Double? }
}

// MARK: - Portfolio and Watchlist (blocks 10, 11)

/// % moves per range: today, 1 to 4 weeks.
struct Moves: Decodable {
    let d: Double?, w1: Double?, w2: Double?, w3: Double?, w4: Double?
    func at(_ r: Int) -> Double? { [d, w1, w2, w3, w4][max(0, min(4, r))] }
}
struct Holding: Decodable, Identifiable {
    var id: String { ticker }
    let ticker: String
    let spot: Double?
    let exposure: Double
    let shareValue: Double?
    let optionValue: Double?
    let ranges: Moves
}
struct Watch: Decodable, Identifiable {
    var id: String { ticker }
    let ticker: String
    let price: Double?
    let ranges: Moves
}

// MARK: - Inventory and the Writes sheet (block 14)

struct Inventory: Decodable {
    let by: [By]
    let weeks: [Week]
    let callsMax: Int
    let putsMax: Int
    let callsSold: Int
    let putsSold: Int
    let creditOpen: Double
    struct By: Decodable, Identifiable {
        var id: String { ticker }
        let ticker: String
        let callsMax: Int, callsSold: Int, putsMax: Int, putsSold: Int
        let creditOpen: Double
    }
    struct Week: Decodable { let week: String; let fri: String; let calls: Int; let puts: Int }
}

struct Writes: Decodable {
    let expiry: String?
    let names: [Name]
    struct Name: Decodable, Identifiable {
        var id: String { ticker }
        let ticker: String
        let expiry: String
        let spot: Double?
        let sd: Double?
        let plan: [Plan]
        let expected: Double
        let already: [Already]
        let collected: Double
        let calls: Count
        let puts: PutCount
        let written: Bool
        let delta: Delta
        let bar: Bar
        let earnings: Earn?
        struct Plan: Decodable { let type: String; let n: Int; let strike: Double; let mid: Double?; let delta: Double?; let note: String; let credit: Double }
        struct Already: Decodable { let type: String; let n: Int; let strike: Double; let credit: Double }
        struct Count: Decodable { let sold: Int; let of: Int }
        struct PutCount: Decodable { let sold: Int; let of: Int; let bought: Int }
        struct Delta: Decodable { let now: Double; let after: Double }
        struct Bar: Decodable {
            let put: Double?, spot: Double?, call: Double?, sd1: Double?, breakeven: Double?
            let toPutPct: Double?, toSd1Pct: Double?
        }
        struct Earn: Decodable { let date: String; let time: String? }
    }
}

// MARK: - Theta and Delta (blocks 15, 16)

struct History: Decodable {
    let from: String?
    let days: [String]
    let theta: Series
    let delta: Series
    struct Series: Decodable {
        let avg2w: [Double]
        let now: Double?
        let trend: String?
    }
}

struct Risk: Decodable {
    let theta: Theta
    let delta: Delta
    struct Theta: Decodable {
        let long: Double
        let short: Double
        let by: [By]
        struct By: Decodable { let ticker: String; let net: Double; let collect: Double; let lose: Double }
    }
    struct Delta: Decodable {
        let long: Double
        let sold: Double
        let by: [By]
        struct By: Decodable { let ticker: String; let pct: Double; let long: Double; let sold: Double }
    }
}

// MARK: - Payback (block 18)

struct Payback: Decodable {
    let now: Now
    /// [day, time value target, time value paid back, intrinsic target, intrinsic paid back,
    /// all realized since the first LEAP]
    let series: [[Scalar]]
    let paceTv: Double
    let paceIntr: Double
    /// The combined pace (all realized plus the intrinsic change), a week.
    let paceAll: Double?
    /// Made (realized plus premium in hand), a week, over the last five weeks.
    let paceMade: Double?
    let newLeapDays: [String]?
    struct Now: Decodable { let d: String; let inT: Double; let tvT: Double; let inPaid: Double; let tvPaid: Double
                            let allReal: Double?; let held: Double? }
}

// MARK: - Sold vs Bought, Performance, Allocation (blocks 19-21)

struct SoldVsBought: Decodable {
    /// [day, longs' change in value (unrealized), shorts realized]
    let days: [[Scalar]]
    let openCredit: Double
}

struct Performance: Decodable {
    /// [yyyy-MM, ticker, type, $]
    let realized: [[Scalar]]
    let unrealized: [[Scalar]]
}

struct Allocation: Decodable {
    let cash: Double?
    let holdings: [Holding]
    struct Holding: Decodable, Identifiable { var id: String { ticker }; let ticker: String; let now: Double; let invested: Double }
}

// MARK: - Yield (block 17)

struct YieldWeek: Decodable {
    let week: String
    let fri: String
    let month: String
    let invested: Double
    let callsSold: Double, callsBack: Double, putsSold: Double, putsBack: Double
    let callsSoldTv: Double?, callsBackTv: Double?, putsSoldTv: Double?, putsBackTv: Double?
}

// MARK: - Account chart (block 02b)

struct Chart: Decodable {
    let from: String
    let to: String
    let lastClose: String?
    let liveLast: Bool
    let days: [String]
    let nav: [Double?]
    let margin: [Double?]
    let realizedCum: [Double?]
    let unrealized: [Double?]
    let timeValue: [Double?]
    let interestCum: [Double?]
    let commissionCum: [Double?]
    let dividendsCum: [Double?]
    let capitalLong: [Double?]
    let sharesValue: [Double?]
    let groups: [String: Group]
    let sharesTickers: [Int]
    let closed: [[Scalar]]
    let dividends: Dividends

    struct Group: Decodable { let line: [Double]; let real: [Double]; let unreal: [Double]; let tv: [Double] }
    struct Dividends: Decodable {
        let paid: [[Scalar]]
        /// [pay date, ticker] for each name that paid (02b "Payers").
        let payers: [[String]]?
        let yieldPct: Double?
        let next: Next?
        struct Next: Decodable { let ticker: String; let exDate: String; let payDate: String?; let amount: Double? }
    }
}

// MARK: - Deck (blocks 03-07)

struct Deck: Decodable {
    let earnings: [Earning]
    let season: Season?
    let reports: [Report]?
    let thetaChecks: [ThetaCheck]?

    struct Earning: Decodable, Identifiable {
        var id: String { ticker + date }
        let ticker: String
        let date: String
        let time: String?          // amc | bmo | nil
        let estimated: Bool
        let callsOn: Int
        let putsOn: Int
        let shares: Double
        let exposure: Double
        let pricedMovePct: Double?
    }
    struct Season: Decodable {
        let quarter: String
        let starts: String
        let ends: String
        let showThrough: String
        let names: Int
        let last: String?
        let only: Only?
        struct Only: Decodable { let ticker: String; let date: String }
    }

    /// A weekly or monthly report (block 06), as saved on its day.
    struct Report: Decodable {
        let kind: String                 // weekly | monthly
        let label: String
        let mark: String
        let pending: String?
        let period: Period?
        let kept: Double?
        let realized: Double?
        let lines: [Line]?
        let commission: Double?
        let trades: Int?
        let commissionEach: Double?
        let interest: Double?
        let borrowed: Double?
        let unrealizedNow: Double?
        let best: Best?
        let comingUp: ComingUp?

        struct Period: Decodable { let from: String; let to: String }
        struct Line: Decodable { let leg: String; let how: String; let exp: String?; let amount: Double; let kind: String }
        struct Best: Decodable { let leg: String; let amount: Double; let how: String; let exp: String?; let keptPct: Double? }
        struct ComingUp: Decodable {
            let earnings: [Earn]?
            let market: [Market]?
            let macro: [Macro]?
            let exDividend: [ExDiv]?
            let longs: [Long]?
            struct Earn: Decodable { let date: String; let ticker: String; let time: String? }
            struct Market: Decodable { let date: String; let kind: String; let name: String; let closes: String? }
            struct Macro: Decodable { let date: String; let time: String?; let name: String }
            struct ExDiv: Decodable { let date: String; let ticker: String; let amount: Double?; let callsSold: Int? }
            struct Long: Decodable { let leg: String; let expiry: String; let months: Int; let sinceBoughtPct: Double? }
        }
    }

    /// A LEAP whose theta drags (block 07), with the roll that fixes it.
    struct ThetaCheck: Decodable, Identifiable {
        var id: String { leg }
        let ticker: String
        let leg: String
        let trigger: String              // growth | ratio
        let foundOn: String
        let cardToday: Bool
        let thetaNow: Double?
        let thetaThen: Double?
        let growthPct: Double?
        let ratioNow: Double?
        let ratioWithout: Double?
        let roll: Roll?

        struct Roll: Decodable {
            let error: String?
            let close: Side?
            let open: Side?
            let netDebit: Double?
            let commissionFees: Double?
            let thetaDay: Pair?
            let timeValueLeft: Pair?
            let iv: Pair?
            let delta: Pair?
            let openInterest: Pair?
            let bookRatio: Ratio?
            struct Side: Decodable { let expiry: String; let strike: Double; let contracts: Int; let price: Double? }
            struct Pair: Decodable { let old: Double?; let new: Double? }
            struct Ratio: Decodable { let now: Double?; let after: Double? }
        }
    }
}

// MARK: - Mixed arrays ([date, group, flag, amount])

enum Scalar: Decodable {
    case s(String), n(Double), null
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Double.self) { self = .n(v) }
        else { self = .s(try c.decode(String.self)) }
    }
    var string: String? { if case .s(let v) = self { return v }; return nil }
    var number: Double? { if case .n(let v) = self { return v }; return nil }
}
