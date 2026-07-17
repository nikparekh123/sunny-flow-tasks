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
    let put: CoveredCallPut?
    /// Realized P&L across every closed cycle for this ticker.
    let realizedToDate: Double

    var shares: Double { current?.shares ?? 0 }

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
    /// Shares P&L vs adjusted basis.
    var exitSharesPL: Double {
        guard let c = current else { return 0 }
        return (currentPrice - c.adjustedBasis) * c.shares
    }
    /// NET result of unwinding the open call: premium collected on it
    /// less what it costs to buy back. Because the open call's premium
    /// isn't in the basis, this line carries it — so the exit net is
    /// correct (v7's mock showed only the buyback and understated it).
    var exitCallBuyback: Double {
        guard let leg = current?.openLeg, let mark = leg.mark else { return 0 }
        return (leg.premiumPerShare - mark) * leg.remaining * 100
    }
    /// Put mark-to-market vs what was paid.
    var exitPutPL: Double { put?.pnl ?? 0 }
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
    var calendar: [CalMonth] { CoveredCallData.calendar(legs: allLegs) }
}

// MARK: - Engine

enum CoveredCallData {

    /// Lay legs onto a fixed Monday/Wednesday/Friday grid, grouped by
    /// month. Weeks with a leg render fully; past slots with no call are
    /// "none", upcoming slots (after today) are "future". Each slot
    /// carries its premium + strike so the box shows premium/share and
    /// tapping opens a detail. The M/W/F cadence is permanent for these
    /// names, so the hit/miss pattern reads like a heartbeat.
    static func calendar(legs: [CoveredCallLeg], now: Date = Date()) -> [CalMonth] {
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

        var legByDay: [String: CoveredCallLeg] = [:]
        for l in legs {
            if let d = AppDates.parseISODay(l.expiry) { legByDay[keyFmt.string(from: d)] = l }
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
        for l in legs { if let d = AppDates.parseISODay(l.expiry) { targetMonths.insert(friMonthKey(d)) } }
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
            if let leg = legByDay[key] {
                let kind: SlotKind
                switch leg.status {
                case .assigned: kind = .assigned
                case .open:     kind = .open
                default:        kind = .kept
                }
                let ct = leg.status == .open ? leg.remaining : leg.contracts
                return CalSlot(id: key + name, kind: kind, weekday: name, dateLabel: mdFmt.string(from: date),
                               premiumPerShare: leg.premiumPerShare,
                               premiumTotal: leg.premiumPerShare * ct * 100, strike: leg.strike)
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

    /// Tickers with a covered-call book — shares held plus at least one
    /// short call ever sold. Data-driven so it extends past NVDA/META
    /// automatically. Ordered by position value desc.
    static func tickers(store: PortfolioStore) -> [String] {
        let callTickers = Set(
            store.allTrades
                .filter { $0.option_type == "call" && $0.direction == "short" && $0.voided_at == nil }
                .map(\.ticker)
        )
        return store.companies
            .filter { callTickers.contains($0.ticker) }
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
        let assignments = store.allShareSells
            .filter { $0.ticker == ticker && $0.source == "assignment" }
            .sorted { $0.trade_date < $1.trade_date }

        let lots = store.allShareLotsHistory
            .filter { $0.ticker == ticker }
            .sorted { $0.acquired_date < $1.acquired_date }

        // Segment lots into cycles: each assignment ends the cycle that
        // the lots before it belong to; the remainder is the live cycle.
        var cycles: [CoveredCallCycle] = []
        var cursor: String? = nil     // exclusive lower bound (prev assignment date)

        for a in assignments {
            let window = lots.filter { lot in
                (cursor == nil || lot.acquired_date > cursor!) && lot.acquired_date <= a.trade_date
            }
            if let cycle = makeCycle(
                store: store, ticker: ticker, lots: window,
                startAfter: cursor, endDate: a.trade_date,
                assignmentStrike: a.price, sharesOverride: a.quantity,
                realized: a.realized_pl
            ) {
                cycles.append(cycle)
            }
            cursor = a.trade_date
        }

        // Live cycle — lots acquired after the last assignment.
        let liveLots = lots.filter { cursor == nil || $0.acquired_date > cursor! }
        let current = makeCycle(
            store: store, ticker: ticker, lots: liveLots,
            startAfter: cursor, endDate: nil,
            assignmentStrike: nil, sharesOverride: nil, realized: nil
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

        return CoveredCallTicker(
            ticker: ticker,
            currentPrice: spot,
            current: current,
            closed: cycles.reversed(),          // newest first for history
            put: put,
            realizedToDate: cycles.compactMap(\.realizedPL).reduce(0, +)
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
        realized: Double?
    ) -> CoveredCallCycle? {
        guard let start = lots.first?.acquired_date else { return nil }

        // Entry = weighted average cost across the cycle's lots.
        let totalQty = lots.reduce(0.0) { $0 + $1.qty_original }
        guard totalQty > 0 else { return nil }
        let entry = lots.reduce(0.0) { $0 + $1.qty_original * $1.cost_per_share } / totalQty
        // Live cycle holds what's left; a closed cycle's shares are what
        // actually got assigned away.
        let shares: Double = endDate == nil
            ? max(lots.reduce(0.0) { $0 + $1.qty_remaining }, 0)
            : (sharesOverride ?? totalQty)
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
                status: status(for: t, remaining: remaining, closes: closes),
                remaining: remaining,
                mark: mark
            )
        }

        // Premium split: only RESOLVED calls' credit counts toward the
        // basis; the still-open call's premium is pending (it can be
        // clawed back by a roll). Buybacks (debits) reduce the resolved
        // side — a roll's buyback nets against the old call there.
        let resolvedCredits = legs
            .filter { $0.status != .open }
            .reduce(0.0) { $0 + $1.premiumPerShare * $1.contracts * 100 }
        let openCredits = legs
            .filter { $0.status == .open }
            .reduce(0.0) { $0 + $1.premiumPerShare * $1.remaining * 100 }
        let debits = closes.reduce(0.0) { $0 + $1.premium * $1.contracts * 100 }
        let resolvedPremium = resolvedCredits - debits

        // Realized on a closed cycle = the share P&L snapshot booked at
        // assignment + the premium that cycle locked in.
        let realizedTotal: Double? = endDate == nil ? nil : (realized ?? 0) + resolvedPremium

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
            realizedPL: realizedTotal
        )
    }

    /// Leg status from `closed_via` on its matching close. Falls back to
    /// expiry/remaining when the sync never tagged a resolution.
    private static func status(
        for open: OptionTradeRow,
        remaining: Double,
        closes: [OptionTradeRow]
    ) -> CallLegStatus {
        if remaining > 0 {
            // Still live — unless it's already past expiry with no close,
            // in which case it lapsed worthless.
            if (AppDates.daysUntil(open.expiry) ?? 0) < 0 { return .expired }
            return .open
        }
        // Closed: find the close on the same contract and read closed_via.
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
            if let leg = tk.current?.openLeg, let mark = leg.mark {
                // Short call: collected premium less cost to close.
                t.callsUnrealized += (leg.premiumPerShare - mark) * leg.remaining * 100
            }
            t.realized += tk.realizedToDate
            if let p = tk.put {
                t.putsPL += p.pnl
                t.putsCost += p.cost
            }
        }
        return t
    }
}
