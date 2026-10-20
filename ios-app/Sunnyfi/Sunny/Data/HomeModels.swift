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
    /// ES, NQ, RTY for the 7:00-9:30 cards (handoff 24, block 09).
    let futures: [Future]?
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
    /// The crash scanner (handoff 26, blocks 03b and 26).
    let aftershock: Aftershock?
    /// Each open name's strategy: rebound, ladder or aftershock (block 13b).
    let strategies: [String: String]?
    /// This week (handoff 28, block 12b): what to roll, buy and sell by Friday, one row per task.
    let thisWeek: Lenient<[WeekTask]>?
}

/// One This week row (block 12b): the CALL RULE's roll, buy and sales for a name.
struct WeekTask: Decodable, Identifiable, Hashable {
    let id: String
    let t: String
    /// roll · buy · sell · put
    let kind: String
    /// The Position card face the work is on: "sold" or "dg".
    let face: String
    let action: String
    /// The other fix for a buy: "or sell 12 fewer".
    let alt: String?
    let cost: Double
    let credit: Bool
    /// Dollar delta the task adds (a sale takes some away: negative).
    let delta: Double
    /// Where the name goes short (%), for the order.
    let sh: Double?
}

/// Delta and Gamma for one name (blocks 13 and 16): an instant jump from today's price.
struct DGBook: Decodable, Hashable {
    let px: Double
    /// One weekly SD in %.
    let sd: Double?
    /// Today's delta, shares and dollars.
    let d0: Double
    let d0Usd: Double
    /// A week of premium, dollars.
    let wk: Double
    /// Where it gets thin (under half of today's delta) and goes short, % (nil past 10%).
    let thin: Double?
    let sh: Double?
    /// A normal week's move, %, and whether it leaves less than half of today's delta.
    let m1: Double?
    let needs: Bool
    /// [move %, bought $, sold $, net $, cost $] every 0.5% from 0 to 10%.
    let ser: [[Double]]

    struct Point { let m: Double; let b: Double; let s: Double; let n: Double; let gb: Double }
    func at(_ m: Double) -> Point {
        let r = ser[safe: max(0, min(ser.count - 1, Int((m * 2).rounded())))] ?? []
        return Point(m: m, b: r[safe: 1] ?? 0, s: r[safe: 2] ?? 0, n: r[safe: 3] ?? 0, gb: r[safe: 4] ?? 0)
    }
    /// Stays long · thin · short at move m.
    enum State { case long, thin, short }
    func state(_ m: Double) -> State {
        let n = at(m).n
        return n < 0 ? .short : n < d0Usd / 2 * (1 + m / 100) ? .thin : .long
    }
    /// The jump's cost in weeks of premium.
    func weeks(_ m: Double) -> Double { wk > 0 ? at(m).gb / wk : 0 }
    func sdOf(_ m: Double) -> Double? { sd.map { $0 > 0 ? m / $0 : 0 } }
}

/// Six plain points about one name this week (14c), written on the server.
struct NameInsights: Decodable, Hashable {
    let name: String
    let day: String?
    let strategy: String?
    let points: [Point]
    struct Point: Decodable, Hashable { let lead: String; let body: String }
}

/// Aftershock: the universe, the last scans and the last two weeks of crashes,
/// biggest drop first within a day (crash-scan, read by sunny-home).
struct Aftershock: Decodable, Equatable {
    let universe: Int
    let scans: [Scan]
    let events: [Event]
    let nextScanDay: String?

    struct Scan: Decodable, Equatable { let day: String; let crashes: Int; let scannedAt: String? }
    struct Event: Decodable, Equatable, Identifiable {
        var id: String { ticker + day }
        let ticker: String
        let day: String
        let prevClose: Double
        let close: Double
        let dropPct: Double
        /// The trading day after the crash, and its close once it is in.
        let day2: String?
        let day2Close: Double?
        let day2Pct: Double?
    }
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
    /// The last regular close (before the open: the 16:00 close moves run from).
    let regular: Double?
    let regularAt: String?
    let at: String?
}

/// A front-month future for an index card: its price now (`at`, Yahoo ~10 min
/// behind) and its 16:00 price on `baseDate`, the base the card divides by.
struct Future: Decodable {
    let card: String
    let symbol: String
    let pill: String
    let price: Double?
    let at: String?
    let base: Double?
    let baseDate: String?
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
        /// Contracts rolled out of this week's Friday (block 14, handoff 24).
        let rolled: Int?
    }
    /// A week's bar: the most contracts on at once, of which `*Rolled` were
    /// closed early and reopened later (they stay here, hatched).
    struct Week: Decodable {
        let week: String; let fri: String; let calls: Int; let puts: Int
        let callsRolled: Int?; let putsRolled: Int?
        let rolledTo: String?; let rolledNames: [String]?
    }
}

struct Writes: Decodable {
    let expiry: String?
    let names: [Name]
    /// Names with no chain cached for that Friday (left out of `names`).
    let missing: [String]?
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
        /// The Planner (block 14b): LEAPs held, and the next report even when
        /// it falls after the expiry.
        let leaps: Int?
        let nextEarnings: Earn?
        /// The package (handoff 25): what is held, next week's plan and the fix,
        /// in share-equivalent delta. `now` is the Delta tile's number.
        let pkg: Pkg?
        /// The weekly read rule and Our thesis (block 14c): NKE only for now.
        /// Lenient, so a change in its shape never costs the whole payload.
        let readRule: Lenient<ReadRule>?
        /// Delta and Gamma (handoff 28): the face, the Home map and the Insights delta point.
        let dg: Lenient<DGBook>?
        /// This week's insights (14c).
        let insights: Lenient<NameInsights>?
        /// Every other name's Thesis page (handoff 27): the 0.6 SD Planner rule with the name's reads.
        let thesis: Lenient<ReadRule>?
        struct Pkg: Decodable {
            /// LEAP shares (contracts × 100): the denominator of every %.
            let base: Double
            /// 10 the week the name reports (every band edge moves up), else 0.
            let e: Double
            let now: Double
            let nowPct: Double
            let held: [Held]
            let sug: [Sug]
            let fix: [Sug]
            let after0: Double
            let after0Pct: Double
            let leapValue: Double?
            let budget: Double?
            let w: Double?
            /// The chain's IV at the money (the Week view's range).
            let iv: Double?
            /// The plan repriced 1.5 SD up on the Thursday before the expiry (Nik, 20 Oct 2026):
            /// the price, the day, and net delta there before any fix.
            let safe: Safe?
            /// The quarterly call: 1.5 SD to its expiry.
            let q: Quarterly?
            struct Safe: Decodable, Hashable { let sd: Double; let px: Double; let by: String; let d15: Double; let pct: Double }
            struct Quarterly: Decodable, Hashable { let k: Double; let exp: String; let mid: Double; let sd: Double }
            /// ty: lc LEAP · sc call sold · lp hedge put · sp put sold · oc upside call.
            /// `stays`: still on at the plan's Friday. `d`: signed delta, shares.
            struct Held: Decodable, Hashable {
                let ty: String; let n: Int; let k: Double; let exp: String; let d: Double; let stays: Bool
                let tenor: String?; let roll: String?
                /// Signed delta at +1.5 SD on the Thursday before the expiry, shares.
                let d15: Double?
            }
            struct Sug: Decodable, Identifiable, Hashable {
                let id: String; let ty: String; let act: String; let tenor: String?
                let n: Int; let k: Double; let exp: String; let mid: Double; let d: Double
                let d15: Double?
            }
        }
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
        /// Delta only: the hedge puts' delta each day (16 Oct 2026).
        let hedge: [Double?]?
        /// Delta only: net delta left each day, % of LEAP shares, and its parts.
        let netPct: [Double?]?
        let net: [Double?]?
        let shares: [Double?]?
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
    /// Short = everything sold, calls and puts, as sizes; long = every call
    /// bought (LEAPs and upside calls); hedge = the puts bought (Nik, 16 Oct 2026).
    /// Net delta left = calls bought - calls sold + puts sold - hedge puts, as
    /// a % of the shares the LEAPs control (`pct`, `pctNow`).
    struct Delta: Decodable {
        let long: Double
        let sold: Double
        let hedge: Double?
        let net: Double?
        let shares: Double?
        let pctNow: Double?
        let by: [By]
        struct By: Decodable, Identifiable {
            var id: String { ticker }
            let ticker: String; let pct: Double; let long: Double; let sold: Double; let hedge: Double?
            let net: Double?; let shares: Double?
            /// sell · fine · watch · buy_back, judged on next week (16 Oct 2026).
            let tag: String?
            /// red (net short) · orange (under 20%, 30% the week it reports) · nil.
            let alert: String?
            let earningsWeek: Bool?
        }
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

/// Decodes to nil instead of failing the payload.
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from d: Decoder) throws { value = try? T(from: d) }
}

/// A name's weekly read rule (sunny-home `read_rule`; docs/STRATEGIES.md, NKE
/// weekly rule): the seven reads, the steps off the 0.6 SD baseline, the
/// pick and the one call strike every card uses.
struct ReadRule: Decodable {
    let of: Int
    let calls: Int
    let spot: Double
    let sd: Double?
    let baseline: Double?
    let pickSd: Double?
    /// "0.6 SD", "1 SD", or the skip.
    let pick: String?
    let strike: Double?
    let strikePct: Double?
    /// The share sold at the money when a read steps closer (0 otherwise).
    let atmShare: Double?
    let steps: [Step]
    let reads: Reads
    /// The receipt, when the server writes it (the CALL RULE, 20 Oct 2026): label, value, tone ("red"/"ink").
    let lines: [Line]?

    struct Step: Decodable { let read: String; let label: String; let step: String }
    struct Line: Decodable { let label: String; let value: String; let tone: String? }
    struct Read: Decodable {
        let read: String
        let fact: String
        let value: Double?
        let analyst: Double?
        let model: Double?
    }
    struct Reads: Decodable {
        let fundamentals: Read?
        let technicals: Read?
        let iv: Read?
        let history: Read?
        let momentum: Read?
        let events: Read?
        let breakout: Read?
        let inputs: Inputs?
        let thesis: Facts?
    }
    struct Inputs: Decodable {
        let iv: Double?
        let rich: Double?
        let hv20Ex: Double?
        let ivRank: Double?
        let exDiv: String?
        let exDivEstimated: Bool?
        let nextEarnings: String?
    }
    /// The prices behind the reads: moving averages, the 5-day-ago close, the
    /// month's range, the 12-month move, the usual IV.
    struct Facts: Decodable {
        let sma10: Double?
        let sma50: Double?
        let sma100: Double?
        let sma200: Double?
        let sma200Ago: Double?
        let close5: Double?
        let mLo: Double?
        let mHi: Double?
        let chg252: Double?
        let ivUsual: Double?
        // .convertFromSnakeCase turns sma200_21 into sma20021.
        enum CodingKeys: String, CodingKey {
            case sma10, sma50, sma100, sma200, close5, mLo, mHi, chg252, ivUsual
            case sma200Ago = "sma20021"
        }
    }
}
