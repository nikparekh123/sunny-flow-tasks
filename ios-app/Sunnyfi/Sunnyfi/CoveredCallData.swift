//
//  CoveredCallData.swift
//  Sunnyfi
//
//  Cycle engine for the Covered Call tab.
//
//  THE MODEL
//  A *cycle* opens when shares are purchased and closes when the short
//  call is assigned. On assignment the shares leave at the strike, P&L
//  is booked, and the next purchase opens a fresh cycle. Premium only
//  ever reduces the basis of the cycle that collected it — it does NOT
//  carry across an assignment. That reset is the whole point: each
//  cycle's adjusted basis answers "what do these particular shares
//  actually cost me right now?"
//
//  EVERYTHING IS DERIVED FROM IBKR DATA. No manual entry:
//    • cycle start / entry price  ← share_lots.acquired_date / cost_per_share
//    • cycle end / assignment     ← share_sells where source = 'assignment'
//                                   (its `price` IS the assignment strike)
//    • call leg status            ← option_trades.closed_via
//                                   (expired_worthless | rolled | assigned)
//
//  Uses allShareLotsHistory (unfiltered) because a closed cycle's entry
//  lot has qty_remaining == 0 — the shares were assigned away.
//

import Foundation

// MARK: - Model

enum CallLegStatus: String, Sendable {
    case open, expired, rolled, assigned
}

struct CoveredCallLeg: Identifiable, Sendable {
    let id: String
    let soldDate: String
    let expiry: String
    let strike: Double
    let premiumPerShare: Double
    let contracts: Double
    let status: CallLegStatus
    /// Contracts still live (pooled FIFO). > 0 only when status == .open.
    let remaining: Double
    /// Current mark per share (cost to buy back). nil = no greek yet.
    let mark: Double?

    var premiumTotal: Double { premiumPerShare * contracts * 100 }
    var dte: Int { AppDates.daysUntil(expiry) ?? 0 }
}

/// All calls sold at one (expiry, strike), netted against whatever was
/// paid to buy them back. This is the unit everything reconciles on: an
/// expiry routinely has many separate fills, and a roll/buy-back can
/// swamp the credit (NVDA 7/22: sold $2,800, bought back $11,302).
struct ExpiryRollup: Identifiable, Sendable {
    var id: String { "\(expiry)|\(strike)" }
    let expiry: String
    let strike: Double
    let contracts: Double
    let credit: Double
    let buyback: Double
    let status: CallLegStatus
    var net: Double { credit - buyback }
}

struct CoveredCallCycle: Identifiable, Sendable {
    var id: String { "\(ticker)-\(cycleStartDate)" }
    let ticker: String
    let cycleStartDate: String
    let shares: Double
    let entryPrice: Double
    let lotCount: Int
    let legs: [CoveredCallLeg]
    let cycleEndDate: String?        // nil = current, open cycle
    let assignmentStrike: Double?
    /// Premium from calls that have RESOLVED this cycle (expired /
    /// rolled / assigned), net of buybacks. This is what's locked into
    /// the basis — a still-open call's premium can still be clawed back
    /// by a roll, so it doesn't count until it resolves.
    let premiumCollected: Double
    /// Premium collected on the call currently open (pending). Shows up
    /// as the extra basis you'd pick up if it expires worthless.
    let openCallPremium: Double
    /// NET premium this cycle — every call sold, less everything paid to
    /// buy calls back. Gross alone lies badly when you roll: NVDA 7/22
    /// sold $2,800 of 205s and bought them back for $11,302. Equals the
    /// sum of the calendar circles.
    let premiumNet: Double
    /// Per (expiry, strike) rollups — the unit everything reconciles on.
    let rollups: [ExpiryRollup]
    /// Realized P&L booked when the cycle closed (shares + premium).
    let realizedPL: Double?

    var isOpen: Bool { cycleEndDate == nil }
    var premiumPerShare: Double { shares > 0 ? premiumCollected / shares : 0 }
    /// The headline: entry price less premium LOCKED IN this cycle.
    var adjustedBasis: Double { entryPrice - premiumPerShare }
    /// Where the basis lands if the open call expires worthless — the
    /// current basis less this cycle's pending open-call premium.
    var ifNotExercisedBasis: Double {
        adjustedBasis - (shares > 0 ? openCallPremium / shares : 0)
    }
    var callCount: Int { legs.count }

    /// Days since the cycle started (or its full length once closed).
    var daysHeld: Int {
        let end = cycleEndDate.flatMap(AppDates.parseISODay) ?? Date()
        guard let start = AppDates.parseISODay(cycleStartDate) else { return 0 }
        return max(0, Calendar(identifier: .gregorian)
            .dateComponents([.day], from: start, to: end).day ?? 0)
    }

    /// The call currently working, if any.
    var openLeg: CoveredCallLeg? {
        legs.first { $0.status == .open }
    }
}

struct CoveredCallPut: Sendable {
    let expiry: String
    let strike: Double
    let contracts: Double
    let costBasisPerShare: Double
    let currentMark: Double

    var cost: Double { costBasisPerShare * contracts * 100 }
    var value: Double { currentMark * contracts * 100 }
    var pnl: Double { value - cost }
    var pnlPct: Double { cost > 0 ? pnl / cost * 100 : 0 }
}

struct CoveredCallTicker: Identifiable, Sendable {
    var id: String { ticker }
    let ticker: String
    let currentPrice: Double
    let current: CoveredCallCycle?
    let closed: [CoveredCallCycle]
    let put: CoveredCallPut?     // furthest-dated put, for the one-line panel
    /// Realized P&L across every closed cycle for this ticker.
    let realizedToDate: Double
    /// Realized SHARE P&L — sum of share_sells.realized_pl (populated by
    /// the FIFO reconcile). Assignments + market sells.
    let realizedCapital: Double

    // ── Aggregates over EVERY open leg (not just the working one) ──
    let openCallContracts: Double
    let openCallAvgPremium: Double
    let openCallPremiumTotal: Double
    let openCallCostToClose: Double
    let putContracts: Double
    let putAvgCost: Double
    let putCostTotal: Double
    let putValueTotal: Double

    // ── Position-tab detail (v2) ──
    let callLegs: [OpenLegDetail]      // open short calls
    let putLegs: [OpenLegDetail]       // open long puts
    let longCallLegs: [OpenLegDetail]  // open long calls (LEAP overlay)
    /// Recent calls vs the share price at their expiry, newest first.
    let cushions: [CushionRow]
    /// Today's $ move on the share position.
    let todayPL: Double
    let dayPct: Double

    var shares: Double { current?.shares ?? 0 }

    /// Realized P&L as a % of the current cycle's invested capital.
    var realizedPct: Double {
        guard let c = current, c.entryPrice > 0, c.shares > 0 else { return 0 }
        return realizedToDate / (c.entryPrice * c.shares) * 100
    }

    /// Distance of price from adjusted basis, in percent. Negative =
    /// underwater against the cycle's real cost.
    var distanceToBasisPct: Double {
        guard let c = current, c.adjustedBasis > 0 else { return 0 }
        return (currentPrice - c.adjustedBasis) / c.adjustedBasis * 100
    }

    /// Last assignment date across closed cycles, newest first.
    var lastAssignment: String? {
        closed.compactMap(\.cycleEndDate).max()
    }

    /// Gain assignment of the current open call would book right now —
    /// (strike − adjusted basis) × shares. nil when no call is open.
    var ifExercisedGain: Double? {
        guard let c = current, let leg = c.openLeg else { return nil }
        return (leg.strike - c.adjustedBasis) * c.shares
    }

    // ── Exit math (what closing this ticker right now nets) ──
    /// Shares P&L vs RAW cost. Premium is booked in realizedToDate, so
    /// the share line must NOT also credit it (that would double-count).
    /// The exit NET is identical to the old adjusted-basis version — the
    /// premium just moves from here into realized.
    var exitSharesPL: Double {
        guard let c = current else { return 0 }
        return (currentPrice - c.entryPrice) * c.shares
    }
    /// NET result of unwinding EVERY open call: premium collected less
    /// what it costs to buy them back. Because open-call premium isn't in
    /// the basis, this line carries it, so the exit net is correct.
    var exitCallBuyback: Double { openCallPremiumTotal - openCallCostToClose }
    /// Mark-to-market across ALL open long puts vs what was paid.
    var exitPutPL: Double { putValueTotal - putCostTotal }
    var exitNet: Double { exitSharesPL + exitCallBuyback + exitPutPL }

    /// Total P&L for this ticker: realized (closed cycles) + everything
    /// currently unrealized (which is exactly the "if closed now" net).
    var totalPnL: Double { realizedToDate + exitNet }
    /// Return on the current cycle's invested capital.
    var totalPnLPct: Double {
        guard let c = current, c.entryPrice > 0, c.shares > 0 else { return 0 }
        return totalPnL / (c.entryPrice * c.shares) * 100
    }
    /// Net as % of the cycle's capital at adjusted basis.
    var exitNetPct: Double {
        guard let c = current, c.adjustedBasis > 0, c.shares > 0 else { return 0 }
        return exitNet / (c.adjustedBasis * c.shares) * 100
    }

    /// Floor strike — adjusted basis rounded UP to the next strike
    /// increment. Selling at or above this makes assignment profitable.
    func floorStrike(increment: Double = 2.5) -> Double {
        guard let c = current else { return 0 }
        return (c.adjustedBasis / increment).rounded(.up) * increment
    }

    /// Per-share loss assignment would lock in when the open call sits
    /// below the adjusted basis. nil when the call is safe / none open.
    var belowFloorLoss: Double? {
        guard let c = current, let leg = c.openLeg else { return nil }
        guard leg.strike < c.adjustedBasis else { return nil }
        return leg.strike - c.adjustedBasis   // negative
    }
}

// MARK: - Position Detail v2 surfaces

/// One open option leg, rendered in the position tabs.
struct OpenLegDetail: Identifiable, Sendable {
    let id: String
    let expiry: String
    let strike: Double
    let contracts: Double
    let costPerShare: Double     // premium paid/collected per share
    let markPerShare: Double
    /// Signed P&L for the holder. Long: (mark − cost); short: (cost − mark).
    let pnl: Double
    /// Position theta in $/day — signed so a short leg reads positive
    /// (decay works for you).
    let theta: Double
    let intrinsic: Double        // $ total
    let timeValue: Double        // $ total (extrinsic)
    let isLong: Bool
    let isCall: Bool
    /// Credit taken in (short) or cost paid (long), $ total.
    let basis: Double
    /// Cost to buy back (short) or current worth (long), $ total.
    let marketValue: Double

    var dte: Int { AppDates.daysUntil(expiry) ?? 0 }
    var pnlPct: Double { costPerShare > 0 ? (markPerShare - costPerShare) / costPerShare * 100 : 0 }
}

/// A resolved-or-open call plotted against the share price at its expiry
/// — "how close each call sat".
struct CushionRow: Identifiable, Sendable {
    let id: String
    let expiry: String
    let strike: Double
    let contracts: Double
    let priceAtExpiry: Double
    let status: CallLegStatus
    /// % the strike sat above the price. Positive = OTM cushion.
    var moneynessPct: Double {
        priceAtExpiry > 0 ? (strike - priceAtExpiry) / priceAtExpiry * 100 : 0
    }
    var premiumTotal: Double
}

enum IncomeRange: String, CaseIterable, Identifiable, Sendable {
    case month = "This month", quarter = "Quarter", all = "All time"
    var id: String { rawValue }
}

extension CoveredCallTicker {
    /// Every cycle, newest last.
    var allCycles: [CoveredCallCycle] { closed.reversed() + (current.map { [$0] } ?? []) }
    /// Every (expiry, strike) rollup across every cycle.
    var allRollups: [ExpiryRollup] { allCycles.flatMap(\.rollups) }
    /// Net premium harvested across every cycle — the hero number.
    var lifetimePremium: Double { allCycles.reduce(0) { $0 + $1.premiumNet } }
    var cycleCount: Int { allCycles.count }

    /// TOTAL MADE — the wheel owner's P&L. Premium is INCOME (never
    /// marked as a buyback liability: on assignment you deliver at the
    /// strike and keep it), shares are valued at market vs raw average.
    ///   realized  = premium banked on resolved calls + realized share
    ///               P&L (from share_sells.realized_pl, FIFO-reconciled)
    ///   running   = premium on open calls (collected) + shares vs avg
    ///               + puts marked to market
    var totalReturn: Double { premiumIncome + capitalReturn }

    /// Premium the strategy has produced, gross of any future buyback —
    /// every call sold this book, net only of buybacks ALREADY paid.
    var premiumIncome: Double { lifetimePremium }
    /// Share P&L: realized (sells) + unrealized (held shares vs average)
    /// + protective puts marked to market.
    var capitalReturn: Double { realizedCapital + exitSharesPL + exitPutPL }

    /// Realized P&L actually banked: resolved-call premium + realized
    /// share gains. (Open-call premium and unrealized shares are still
    /// running.)
    var realizedBanked: Double {
        allCycles.reduce(0) { $0 + $1.premiumCollected } + realizedCapital
    }
    /// The average that matters — raw cost less all premium made per
    /// share. "How much we've made" lowers this.
    var currentAverage: Double {
        guard let c = current, c.shares > 0 else { return current?.entryPrice ?? 0 }
        return c.entryPrice - lifetimePremium / c.shares
    }
    var totalReturnPct: Double {
        guard let c = current, c.entryPrice > 0, c.shares > 0 else { return 0 }
        return totalReturn / (c.entryPrice * c.shares) * 100
    }

    /// Annualized premium yield on capital at risk (shares × entry).
    /// Uses premiumIncome (open calls marked to market) so a position
    /// that has to buy its calls back doesn't report a phantom yield.
    var annualizedYieldPct: Double {
        guard let c = current, c.entryPrice > 0, c.shares > 0 else { return 0 }
        let capital = c.entryPrice * c.shares
        let days = max(c.daysHeld, 1)
        return premiumIncome / capital * (365.0 / Double(days)) * 100
    }

    /// Realized premium grouped by expiry weekday (Mon/Wed/Fri).
    func incomeByWeekday(_ range: IncomeRange, now: Date = Date()) -> [(day: String, amount: Double)] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let cutoff: Date? = {
            switch range {
            case .all:     return nil
            case .month:   return AppDates.startOfMonth(now)
            case .quarter: return cal.date(byAdding: .month, value: -3, to: now)
            }
        }()
        // Bucket by WHATEVER weekday each expiry actually falls on — a
        // fixed Mon/Wed/Fri skeleton silently dropped anything else and
        // could leave the chart empty.
        var buckets: [Int: Double] = [:]
        for r in allRollups where r.status != .open {
            guard let d = AppDates.parseISODay(r.expiry) else { continue }
            if let cutoff, d < cutoff { continue }
            let wd = cal.component(.weekday, from: d)
            buckets[wd, default: 0] += r.net       // net of buybacks
        }
        let names = [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"]
        guard !buckets.isEmpty else {
            return [("Mon", 0), ("Wed", 0), ("Fri", 0)]   // skeleton, never blank
        }
        return buckets.keys.sorted().map { (day: names[$0] ?? "?", amount: buckets[$0] ?? 0) }
    }
}

// MARK: - Win rate + calendar

enum SlotKind: Sendable { case assigned, kept, open, future, none }

/// A single M/W/F expiry slot on the win calendar. Carries enough to
/// render the box AND drive the tap-through detail panel.
struct CalSlot: Identifiable, Sendable {
    let id: String
    let kind: SlotKind
    let weekday: String        // "Mon" | "Wed" | "Fri"
    let dateLabel: String      // "7/14"
    let premiumPerShare: Double?
    let premiumTotal: Double?
    let strike: Double?
    var isTappable: Bool { kind != .none }
}

struct CalWeek: Identifiable, Sendable {
    let id: String
    let label: String          // Monday "M/d"
    let mon: CalSlot
    let wed: CalSlot
    let fri: CalSlot
    var slots: [CalSlot] { [mon, wed, fri] }
}

struct CalMonth: Identifiable, Sendable {
    let id: String
    let label: String          // "June 2026"
    let weeks: [CalWeek]
    let assigned: Int
    let kept: Int
    let open: Int
    var resolved: Int { assigned + kept }
    var winRatePct: Double { resolved > 0 ? Double(assigned) / Double(resolved) * 100 : 0 }
    var allSlots: [CalSlot] { weeks.flatMap(\.slots) }
}

extension CoveredCallTicker {
    /// Every call ever sold on this ticker, across all cycles.
    var allLegs: [CoveredCallLeg] {
        closed.flatMap(\.legs) + (current?.legs ?? [])
    }
    private var resolvedLegs: [CoveredCallLeg] {
        allLegs.filter { $0.status == .expired || $0.status == .rolled || $0.status == .assigned }
    }
    /// Win = the call was EXERCISED (assigned). Rate over resolved calls.
    var winsCount: Int { resolvedLegs.filter { $0.status == .assigned }.count }
    var resolvedCount: Int { resolvedLegs.count }
    var winRatePct: Double { resolvedCount > 0 ? Double(winsCount) / Double(resolvedCount) * 100 : 0 }

    /// Month-by-month, week-by-week, expiry-by-expiry win calendar.
    var calendar: [CalMonth] { CoveredCallData.calendar(rollups: allRollups) }
}

// MARK: - Engine

enum CoveredCallData {

    /// Lay legs onto a fixed Monday/Wednesday/Friday grid, grouped by
    /// month. Weeks with a leg render fully; past slots with no call are
    /// "none", upcoming slots (after today) are "future". Each slot
    /// carries its premium + strike so the box shows premium/share and
    /// tapping opens a detail. The M/W/F cadence is permanent for these
    /// names, so the hit/miss pattern reads like a heartbeat.
    static func calendar(rollups: [ExpiryRollup], now: Date = Date()) -> [CalMonth] {
        // Collapse (expiry, strike) rollups to ONE entry per expiry — an
        // expiry can hold several strikes and many fills.
        struct DayAgg { var net = 0.0; var contracts = 0.0; var strikes: [Double] = []; var status = CallLegStatus.expired }
        var byDay: [String: DayAgg] = [:]
        for r in rollups {
            let k = String(r.expiry.prefix(10))
            var a = byDay[k] ?? DayAgg()
            a.net += r.net
            a.contracts += r.contracts
            a.strikes.append(r.strike)
            // assigned wins, then open, else kept
            if r.status == .assigned { a.status = .assigned }
            else if r.status == .open, a.status != .assigned { a.status = .open }
            byDay[k] = a
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        cal.firstWeekday = 2
        let today = cal.startOfDay(for: now)

        let mdFmt = DateFormatter(); mdFmt.dateFormat = "M/d"; mdFmt.timeZone = cal.timeZone
        let monthFmt = DateFormatter(); monthFmt.dateFormat = "LLLL yyyy"; monthFmt.timeZone = cal.timeZone
        let keyFmt = DateFormatter(); keyFmt.dateFormat = "yyyy-MM-dd"; keyFmt.timeZone = cal.timeZone

        func monday(_ d: Date) -> Date {
            cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)) ?? d
        }

        // Target months: any month holding a leg's expiry-week, plus the
        // current month. EACH renders its FULL M/W/F skeleton (every
        // Friday-week of the month), so no circle is ever missing — past
        // gaps show as "none", after-today as "future".
        func friMonthKey(_ d: Date) -> String {
            let fri = cal.date(byAdding: .day, value: 4, to: monday(d)) ?? d
            let c = cal.dateComponents([.year, .month], from: fri)
            return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        }
        var targetMonths = Set<String>()
        for k in byDay.keys { if let d = AppDates.parseISODay(k) { targetMonths.insert(friMonthKey(d)) } }
        let tc = cal.dateComponents([.year, .month], from: today)
        targetMonths.insert(String(format: "%04d-%02d", tc.year ?? 0, tc.month ?? 0))

        var mondays = Set<Date>()
        for mk in targetMonths {
            let parts = mk.split(separator: "-")
            guard parts.count == 2, let y = Int(parts[0]), let mo = Int(parts[1]) else { continue }
            var comps = DateComponents(); comps.year = y; comps.month = mo; comps.day = 1
            guard let first = cal.date(from: comps),
                  let range = cal.range(of: .day, in: .month, for: first) else { continue }
            for day in 0..<range.count {
                guard let d = cal.date(byAdding: .day, value: day, to: first) else { continue }
                if cal.component(.weekday, from: d) == 6 {   // Friday
                    mondays.insert(cal.date(byAdding: .day, value: -4, to: d) ?? d)
                }
            }
        }

        func slot(_ date: Date, _ name: String) -> CalSlot {
            let key = keyFmt.string(from: date)
            if let a = byDay[key] {
                let kind: SlotKind
                switch a.status {
                case .assigned: kind = .assigned
                case .open:     kind = .open
                default:        kind = .kept
                }
                let perShare = a.contracts > 0 ? a.net / (a.contracts * 100) : 0
                return CalSlot(id: key + name, kind: kind, weekday: name, dateLabel: mdFmt.string(from: date),
                               premiumPerShare: perShare,
                               premiumTotal: a.net,
                               strike: Set(a.strikes).count == 1 ? a.strikes.first : nil)
            }
            return CalSlot(id: key + name, kind: date > today ? .future : .none,
                           weekday: name, dateLabel: mdFmt.string(from: date),
                           premiumPerShare: nil, premiumTotal: nil, strike: nil)
        }

        // Group weeks by the FRIDAY's month (the primary weekly expiry),
        // so a Mon 6/30 week whose Fri is 7/3 files under July.
        var byMonth: [String: [(Date, CalWeek)]] = [:]
        for m in mondays {
            let wed = cal.date(byAdding: .day, value: 2, to: m) ?? m
            let fri = cal.date(byAdding: .day, value: 4, to: m) ?? m
            let week = CalWeek(id: keyFmt.string(from: m), label: mdFmt.string(from: m),
                               mon: slot(m, "Mon"), wed: slot(wed, "Wed"), fri: slot(fri, "Fri"))
            let fc = cal.dateComponents([.year, .month], from: fri)
            byMonth[String(format: "%04d-%02d", fc.year ?? 0, fc.month ?? 0), default: []].append((m, week))
        }

        var months: [CalMonth] = []
        for key in byMonth.keys.sorted() {
            let weeks = byMonth[key]!.sorted { $0.0 < $1.0 }.map(\.1)
            let slots = weeks.flatMap(\.slots)
            let label = weeks.first
                .flatMap { AppDates.parseISODay($0.id) }
                .map { cal.date(byAdding: .day, value: 4, to: $0) ?? $0 }
                .map { monthFmt.string(from: $0) } ?? key
            months.append(CalMonth(
                id: key, label: label, weeks: weeks,
                assigned: slots.filter { $0.kind == .assigned }.count,
                kept: slots.filter { $0.kind == .kept }.count,
                open: slots.filter { $0.kind == .open }.count
            ))
        }
        return months
    }

    /// Tickers surfaced on this tab. Scoped to NVDA while the strategy
    /// is being validated — add symbols here (or return nil to disable
    /// the filter) to widen it.
    static let allowed: Set<String>? = ["NVDA"]

    /// Tickers with a covered-call book — shares held plus at least one
    /// short call ever sold. Data-driven so it extends automatically
    /// once `allowed` is widened. Ordered by position value desc.
    static func tickers(store: PortfolioStore) -> [String] {
        let callTickers = Set(
            store.allTrades
                .filter { $0.option_type == "call" && $0.direction == "short" && $0.voided_at == nil }
                .map(\.ticker)
        )
        return store.companies
            .filter { callTickers.contains($0.ticker) }
            .filter { allowed?.contains($0.ticker) ?? true }
            .compactMap { c -> (String, Double)? in
                let qty = c.legs.first(where: { $0.kind == .stock })?.qty ?? 0
                let lots = store.allShareLotsHistory.contains { $0.ticker == c.ticker }
                guard qty > 0 || lots else { return nil }
                return (c.ticker, qty * c.spot)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    static func build(store: PortfolioStore, ticker: String) -> CoveredCallTicker? {
        guard let company = store.companies.first(where: { $0.ticker == ticker }) else { return nil }
        let spot = company.spot

        // ── Cycle boundaries: assignment sells, oldest → newest ──
        //
        // IBKR-synced trades arrive with closed_via NULL and their share
        // sells tagged source='ibkr_flex' (only 8 legacy rows carry
        // 'assignment'), so we can't rely on either tag. Infer instead
        // from the unmistakable signature of an assignment: shares sold
        // at EXACTLY a short call's strike, on or near that call's expiry.
        let shortCalls = store.allTrades.filter {
            $0.ticker == ticker && $0.option_type == "call"
                && $0.direction == "short" && $0.action == "open" && $0.voided_at == nil
        }
        func matchingCall(_ s: ShareSellRow) -> OptionTradeRow? {
            guard let price = s.price, let d = AppDates.parseISODay(s.trade_date) else { return nil }
            return shortCalls.first { c in
                guard let e = AppDates.parseISODay(c.expiry) else { return false }
                return abs(c.strike - price) < 0.01
                    && abs(e.timeIntervalSince(d)) <= 4 * 86_400
            }
        }
        let assignments = store.allShareSells
            .filter { $0.ticker == ticker }
            .filter { $0.source == "assignment" || matchingCall($0) != nil }
            .sorted { $0.trade_date < $1.trade_date }

        // Contract keys (strike|expiry) that were called away — drives the
        // per-leg "assigned" status when closed_via is missing.
        var assignedKeys = Set<String>()
        for s in assignments {
            if let c = matchingCall(s) { assignedKeys.insert("\(c.strike)|\(c.expiry)") }
        }

        // Only a FULL call-away ends a cycle. A partial assignment (e.g.
        // NVDA 7/20: 200 of ~1,800 shares) is an event INSIDE the cycle —
        // resetting on it would split a continuously-held position and
        // shred its basis, premium and history. Threshold: the sale has
        // to take ~all of the shares held.
        let heldNow = company.legs.first { $0.kind == .stock && $0.qty > 0 }?.qty ?? 0
        let cycleEnders = assignments.filter { a in
            guard let q = a.quantity, heldNow > 0 else { return false }
            return q >= heldNow * 0.9
        }

        let lots = store.allShareLotsHistory
            .filter { $0.ticker == ticker }
            .sorted { $0.acquired_date < $1.acquired_date }

        // Segment lots into cycles: each assignment ends the cycle that
        // the lots before it belong to; the remainder is the live cycle.
        var cycles: [CoveredCallCycle] = []
        var cursor: String? = nil     // exclusive lower bound (prev assignment date)

        for a in cycleEnders {
            let window = lots.filter { lot in
                (cursor == nil || lot.acquired_date > cursor!) && lot.acquired_date <= a.trade_date
            }
            if let cycle = makeCycle(
                store: store, ticker: ticker, lots: window,
                startAfter: cursor, endDate: a.trade_date,
                assignmentStrike: a.price, sharesOverride: a.quantity,
                assignedKeys: assignedKeys,
                realized: a.realized_pl
            ) {
                cycles.append(cycle)
            }
            cursor = a.trade_date
        }

        // Live cycle — shares + entry from the IBKR-reconciled position
        // (the real current holding), lots only for the start date.
        let liveLots = lots.filter { cursor == nil || $0.acquired_date > cursor! }
        let stockLeg = company.legs.first { $0.kind == .stock && $0.qty > 0 }
        let liveStart = liveLots.first?.acquired_date
            ?? store.allTrades
                .filter { $0.ticker == ticker && $0.action == "open"
                        && $0.option_type == "call" && $0.direction == "short"
                        && $0.voided_at == nil && (cursor == nil || $0.trade_date > cursor!) }
                .map(\.trade_date).min()
        let current = makeCycle(
            store: store, ticker: ticker, lots: liveLots,
            startAfter: cursor, endDate: nil,
            assignmentStrike: nil,
            sharesOverride: stockLeg?.qty,
            entryOverride: stockLeg?.avg,
            startOverride: liveStart,
            assignedKeys: assignedKeys,
            realized: nil
        )

        // ── Put leg (per ticker, survives cycle resets) ──
        let putLeg = store.allTrades
            .filter {
                $0.ticker == ticker && $0.option_type == "put" && $0.direction == "long"
                    && $0.action == "open" && $0.voided_at == nil
                    && store.remainingContracts(for: $0) > 0
            }
            // Long-dated protection: the furthest expiry is the one.
            .sorted { $0.expiry > $1.expiry }
            .first
        let put: CoveredCallPut? = putLeg.map { t in
            let remaining = store.remainingContracts(for: t)
            let mark = store.allGreeks.first(where: { $0.option_trade_id == t.id })?.last_mark ?? t.premium
            return CoveredCallPut(
                expiry: t.expiry, strike: t.strike, contracts: remaining,
                costBasisPerShare: t.premium, currentMark: mark
            )
        }

        // ── Aggregates over EVERY open leg (the qty cards + exit math) ──
        func mark(_ t: OptionTradeRow) -> Double {
            store.allGreeks.first(where: { $0.option_trade_id == t.id })?.last_mark ?? t.premium
        }
        let openCalls = store.allTrades.filter {
            $0.ticker == ticker && $0.option_type == "call" && $0.direction == "short"
                && $0.action == "open" && $0.voided_at == nil && store.remainingContracts(for: $0) > 0
        }
        var ccCt = 0.0, ccPrem = 0.0, ccClose = 0.0
        for t in openCalls {
            let r = store.remainingContracts(for: t)
            ccCt += r; ccPrem += r * t.premium * 100; ccClose += r * mark(t) * 100
        }
        let openPuts = store.allTrades.filter {
            $0.ticker == ticker && $0.option_type == "put" && $0.direction == "long"
                && $0.action == "open" && $0.voided_at == nil && store.remainingContracts(for: $0) > 0
        }
        var pCt = 0.0, pCost = 0.0, pVal = 0.0
        for t in openPuts {
            let r = store.remainingContracts(for: t)
            pCt += r; pCost += r * t.premium * 100; pVal += r * mark(t) * 100
        }

        // ── Per-leg detail for the position tabs ──
        func legDetail(_ t: OptionTradeRow, isLong: Bool) -> OpenLegDetail {
            let r = store.remainingContracts(for: t)
            let m = mark(t)
            let mult = r * 100
            let isCall = t.option_type == "call"
            let g = store.allGreeks.first { $0.option_trade_id == t.id }
            // Short legs collect decay, so flip the sign — a short leg's
            // theta should read positive.
            let theta = (g?.theta ?? 0) * (isLong ? 1 : -1) * mult
            let intrinsicPS = isCall ? max(spot - t.strike, 0) : max(t.strike - spot, 0)
            let signed = isLong ? (m - t.premium) : (t.premium - m)
            return OpenLegDetail(
                id: t.id, expiry: t.expiry, strike: t.strike, contracts: r,
                costPerShare: t.premium, markPerShare: m, pnl: signed * mult,
                theta: theta,
                intrinsic: intrinsicPS * mult,
                timeValue: max(0, m - intrinsicPS) * mult,
                isLong: isLong, isCall: isCall,
                basis: t.premium * mult, marketValue: m * mult
            )
        }
        let callLegs = openCalls
            .sorted { $0.expiry < $1.expiry }
            .map { legDetail($0, isLong: false) }
        let putLegs = openPuts
            .sorted { $0.expiry < $1.expiry }
            .map { legDetail($0, isLong: true) }
        let longCallLegs = store.allTrades
            .filter {
                $0.ticker == ticker && $0.option_type == "call" && $0.direction == "long"
                    && $0.action == "open" && $0.voided_at == nil && store.remainingContracts(for: $0) > 0
            }
            .sorted { $0.expiry < $1.expiry }
            .map { legDetail($0, isLong: true) }

        // ── Cushion rows: each call vs the share price at its expiry ──
        let closesByDate: [String: Double] = Dictionary(
            store.dailyCloses.filter { $0.ticker == ticker }.map { ($0.date, $0.close_price) },
            uniquingKeysWith: { a, _ in a }
        )
        // One row per (expiry, strike) — combine every fill on a strike,
        // not one row per execution.
        let allRolls = (cycles.flatMap(\.rollups) + (current?.rollups ?? []))
            .sorted { $0.expiry > $1.expiry }
        let cushions: [CushionRow] = allRolls.prefix(8).map { r in
            let px = r.status == .open ? spot : (closesByDate[String(r.expiry.prefix(10))] ?? spot)
            return CushionRow(
                id: r.id, expiry: r.expiry, strike: r.strike, contracts: r.contracts,
                priceAtExpiry: px, status: r.status, premiumTotal: r.net
            )
        }

        return CoveredCallTicker(
            ticker: ticker,
            currentPrice: spot,
            current: current,
            closed: cycles.reversed(),          // newest first for history
            put: put,
            // Realized = premium banked on every RESOLVED call (closed
            // cycles' realizedPL already folds theirs in; add the live
            // cycle's resolved premium) + assignment share gains. The
            // open call's premium is NOT here — it's still pending.
            realizedToDate: cycles.compactMap(\.realizedPL).reduce(0, +) + (current?.premiumCollected ?? 0),
            realizedCapital: store.allShareSells
                .filter { $0.ticker == ticker }
                .reduce(0.0) { $0 + $1.realized_pl },
            openCallContracts: ccCt,
            openCallAvgPremium: ccCt > 0 ? ccPrem / (ccCt * 100) : 0,
            openCallPremiumTotal: ccPrem,
            openCallCostToClose: ccClose,
            putContracts: pCt,
            putAvgCost: pCt > 0 ? pCost / (pCt * 100) : 0,
            putCostTotal: pCost,
            putValueTotal: pVal,
            callLegs: callLegs,
            putLegs: putLegs,
            longCallLegs: longCallLegs,
            cushions: cushions,
            todayPL: (stockLeg?.qty ?? 0) * spot * (company.dayPct / 100),
            dayPct: company.dayPct
        )
    }

    /// Build one cycle from its lots + the call legs sold inside its window.
    private static func makeCycle(
        store: PortfolioStore,
        ticker: String,
        lots: [ShareLotRow],
        startAfter: String?,
        endDate: String?,
        assignmentStrike: Double?,
        sharesOverride: Double?,
        entryOverride: Double? = nil,
        startOverride: String? = nil,
        assignedKeys: Set<String> = [],
        realized: Double?
    ) -> CoveredCallCycle? {
        // The live cycle's shares + entry come from the IBKR-reconciled
        // position (overrides), not the lot sum, so the count matches the
        // real holding even when share_lots history is partial.
        guard let start = startOverride ?? lots.first?.acquired_date else { return nil }

        let totalQty = lots.reduce(0.0) { $0 + $1.qty_original }
        let weightedEntry = totalQty > 0
            ? lots.reduce(0.0) { $0 + $1.qty_original * $1.cost_per_share } / totalQty : 0
        let entry = entryOverride ?? weightedEntry
        let shares: Double = {
            if let o = sharesOverride { return o }
            return endDate == nil ? max(lots.reduce(0.0) { $0 + $1.qty_remaining }, 0) : totalQty
        }()
        guard shares > 0 else { return nil }

        // ── Call legs sold inside this cycle's window ──
        let opens = store.allTrades.filter {
            $0.ticker == ticker && $0.option_type == "call" && $0.direction == "short"
                && $0.action == "open" && $0.voided_at == nil
                && $0.trade_date >= start
                && (endDate == nil || $0.trade_date <= endDate!)
        }
        .sorted { $0.trade_date < $1.trade_date }

        let closes = store.allTrades.filter {
            $0.ticker == ticker && $0.option_type == "call" && $0.direction == "short"
                && $0.action == "close" && $0.voided_at == nil
                && $0.trade_date >= start
                && (endDate == nil || $0.trade_date <= endDate!)
        }

        let legs: [CoveredCallLeg] = opens.map { t in
            let remaining = store.remainingContracts(for: t)
            let mark = store.allGreeks.first(where: { $0.option_trade_id == t.id })?.last_mark
            return CoveredCallLeg(
                id: t.id,
                soldDate: t.trade_date,
                expiry: t.expiry,
                strike: t.strike,
                premiumPerShare: t.premium,
                contracts: t.contracts,
                status: status(for: t, remaining: remaining, closes: closes, assignedKeys: assignedKeys),
                remaining: remaining,
                mark: mark
            )
        }

        // ── Roll up per (expiry, strike) ──
        // An expiry routinely has many fills (7/17 had eight), and a
        // buy-back can exceed the credit, so every premium figure is
        // derived from these netted rollups rather than raw legs.
        let closeByKey = Dictionary(grouping: closes) { "\($0.expiry)|\($0.strike)" }
        let rollups: [ExpiryRollup] = Dictionary(grouping: legs) { "\($0.expiry)|\($0.strike)" }
            .map { _, group -> ExpiryRollup in
                let first = group[0]
                let key = "\(first.expiry)|\(first.strike)"
                let credit = group.reduce(0.0) { $0 + $1.premiumPerShare * $1.contracts * 100 }
                let buyback = (closeByKey[key] ?? []).reduce(0.0) { $0 + $1.premium * $1.contracts * 100 }
                let st: CallLegStatus = group.contains { $0.status == .assigned } ? .assigned
                    : group.contains { $0.status == .open } ? .open
                    : group.contains { $0.status == .rolled } ? .rolled : .expired
                return ExpiryRollup(
                    expiry: first.expiry, strike: first.strike,
                    contracts: group.reduce(0.0) { $0 + $1.contracts },
                    credit: credit, buyback: buyback, status: st
                )
            }
            .sorted { $0.expiry < $1.expiry }

        // Net across everything sold this cycle.
        let premiumNet = rollups.reduce(0.0) { $0 + $1.net }
        // Locked into the basis: only what's RESOLVED (an open call can
        // still be bought back at a loss, as 7/22 showed).
        let resolvedPremium = rollups.filter { $0.status != .open }.reduce(0.0) { $0 + $1.net }
        let openCredits = rollups.filter { $0.status == .open }.reduce(0.0) { $0 + $1.net }

        // Realized on a closed cycle = share P&L at assignment + the
        // premium that cycle locked in. IBKR-synced sells come through
        // with realized_pl = 0, so derive the share side from the
        // assignment strike vs this cycle's entry when it's missing.
        let assignedShareGain: Double = {
            if let r = realized, r != 0 { return r }
            guard let k = assignmentStrike, endDate != nil else { return 0 }
            return (k - entry) * shares
        }()
        let realizedTotal: Double? = endDate == nil ? nil : assignedShareGain + resolvedPremium

        return CoveredCallCycle(
            ticker: ticker,
            cycleStartDate: start,
            shares: shares,
            entryPrice: entry,
            lotCount: lots.count,
            legs: legs,
            cycleEndDate: endDate,
            assignmentStrike: assignmentStrike,
            premiumCollected: resolvedPremium,
            openCallPremium: openCredits,
            premiumNet: premiumNet,
            rollups: rollups,
            realizedPL: realizedTotal
        )
    }

    /// Leg status from `closed_via` on its matching close. Falls back to
    /// expiry/remaining when the sync never tagged a resolution.
    private static func status(
        for open: OptionTradeRow,
        remaining: Double,
        closes: [OptionTradeRow],
        assignedKeys: Set<String>
    ) -> CallLegStatus {
        let key = "\(open.strike)|\(open.expiry)"
        if remaining > 0 {
            // An assigned call gets NO close row from IBKR, so it still
            // reads as open here. Check assignment before assuming a
            // past-expiry leg simply lapsed worthless.
            if (AppDates.daysUntil(open.expiry) ?? 0) < 0 {
                return assignedKeys.contains(key) ? .assigned : .expired
            }
            return .open
        }
        // Closed. Inferred assignment wins over the (usually NULL)
        // closed_via tag.
        if assignedKeys.contains(key) { return .assigned }
        let match = closes.first {
            $0.strike == open.strike && $0.expiry == open.expiry
                && ($0.closes_trade_id == open.id || $0.closed_via != nil)
        }
        switch match?.closed_via {
        case "assigned":          return .assigned
        case "rolled":            return .rolled
        case "expired_worthless": return .expired
        default:                  return .expired
        }
    }

    // MARK: - Portfolio roll-up (the sticky tally)

    struct Tally: Sendable {
        /// (price − adjusted basis) × shares, across all tickers.
        var sharesUnrealized: Double = 0
        /// Mark-to-market on open short calls (credit still to be earned).
        var callsUnrealized: Double = 0
        /// Realized P&L from every closed cycle.
        var realized: Double = 0
        /// Long-dated put mark-to-market.
        var putsPL: Double = 0
        var putsCost: Double = 0

        var sharesAndCalls: Double { sharesUnrealized + callsUnrealized + realized }
        var putsPct: Double { putsCost > 0 ? putsPL / putsCost * 100 : 0 }
        var net: Double { sharesAndCalls + putsPL }
    }

    /// Realized / unrealized / total, over a ticker set. The Performance
    /// page renders THIS — same engine as the Covered Call tally — so the
    /// two surfaces can never disagree.
    struct PnL: Sendable {
        let realized: Double
        let unrealized: Double
        var total: Double { realized + unrealized }
    }

    static func pnl(store: PortfolioStore, tickers: [String]) -> PnL {
        let t = tally(store: store, tickers: tickers)
        return PnL(
            realized: t.realized,
            unrealized: t.sharesUnrealized + t.callsUnrealized + t.putsPL
        )
    }

    static func tally(store: PortfolioStore, tickers: [String]) -> Tally {
        var t = Tally()
        for sym in tickers {
            guard let tk = build(store: store, ticker: sym) else { continue }
            t.sharesUnrealized += tk.exitSharesPL
            t.callsUnrealized += tk.exitCallBuyback   // all open calls, premium − buyback
            t.realized += tk.realizedToDate
            t.putsPL += tk.exitPutPL                  // all open puts, MTM
            t.putsCost += tk.putCostTotal
        }
        return t
    }
}
