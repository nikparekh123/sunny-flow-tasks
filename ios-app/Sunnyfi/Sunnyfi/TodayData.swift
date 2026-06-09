//
//  TodayData.swift
//  Sunnyfi
//
//  Bucketed top-1-per-bucket ranking for the Today landing tab.
//  Pulls from existing PortfolioStore data — no new fetches here.
//
//  v1 buckets in priority order:
//    1. Markets    — broad indices (SKIPPED in Phase A; needs
//                    market_indicators table from Phase B)
//    2. Portfolio  — biggest mover among the user's positions today
//    3. Events     — soonest upcoming high-importance macro event
//    4. Earnings   — soonest upcoming earnings on a position
//                    (or a peer if no positions reporting soon)
//    5. Options    — most pressing options-book metric
//                    (expiring soon, total premium collected, etc.)
//
//  If the list ends up < 5 items (e.g., no upcoming events), we
//  fill from the portfolio runner-up so the screen always shows
//  the promised count.
//

import Foundation

@MainActor
enum TodayData {

    static let targetCount = 5

    /// Compose the ranked list of N items. Pinned items are
    /// extracted separately by the screen (it pulls full TodayItem
    /// from the full set via id lookup).
    static func compute(store: PortfolioStore, today: Date = Date()) -> [TodayItem] {
        var items: [TodayItem] = []

        // Order matters — first picks render at the top of the list.
        // IV used to be a bucket here; it's now a dedicated section
        // (IVMergedRow + IVTracker rail) rendered outside this list.
        if let p = portfolioItem(store: store)                 { items.append(p) }
        if let ev = eventsItem(store: store, today: today)     { items.append(ev) }
        if let ea = earningsItem(store: store, today: today)   { items.append(ea) }
        if let op = optionsItem(store: store, today: today)    { items.append(op) }

        // Fill remaining slots from portfolio runners-up so the
        // screen always feels full.
        let runners = portfolioRunnersUp(
            store: store,
            excludeIds: Set(items.map(\.id))
        )
        for r in runners where items.count < targetCount {
            items.append(r)
        }

        return Array(items.prefix(targetCount))
    }

    // ─── Portfolio bucket ──────────────────────────────────────

    /// The position with the largest |today's $ move|. Big-mover, not
    /// big-% — a 5% gain on a 1% weight is less interesting than a
    /// 1% gain on a 20% weight.
    private static func portfolioItem(store: PortfolioStore) -> TodayItem? {
        portfolioRanked(store: store).first
    }

    private static func portfolioRunnersUp(
        store: PortfolioStore,
        excludeIds: Set<String>
    ) -> [TodayItem] {
        portfolioRanked(store: store).filter { !excludeIds.contains($0.id) }
    }

    private static func portfolioRanked(store: PortfolioStore) -> [TodayItem] {
        // Use company.spot / company.dayPct directly (already joined
        // by the store). Filter to companies with shares.
        let totalMV = max(1, store.companies.reduce(0.0) { $0 + $1.agg.mv })

        return store.companies.compactMap { company -> (Double, TodayItem)? in
            guard let stock = company.legs.first(where: { $0.kind == .stock && $0.qty > 0 })
            else { return nil }
            let dayPct = company.dayPct
            let dollar = stock.qty * company.spot * (dayPct / 100.0)
            if abs(dollar) < 1 { return nil }  // ignore noise

            let weight = company.agg.mv / totalMV * 100
            let tone: TodayTone = dayPct >= 0 ? .pos : .neg
            let item = TodayItem(
                id: "portfolio:\(company.ticker)",
                bucket: .portfolio,
                category: "Portfolio",
                short: company.ticker,
                name: company.ticker,
                sub: "\(pctString(weight, decimals: 1)) weight · \(Int(stock.qty)) sh",
                num: pctString(dayPct, decimals: 1),
                unit: "1-DAY",
                tone: tone,
                line: "\(company.ticker) is \(dayPct >= 0 ? "up" : "down") \(absPctString(dayPct, decimals: 1)) today — a \(fmtMoney(abs(dollar))) move on your position.",
                detailTitle: "Portfolio",
                detailSub: "Ranked by today's $ move",
                detailRows: portfolioDetailRows(store: store),
                pinNarrative: PinNarrative(
                    lead: "\(company.ticker) is ",
                    value: "\(dayPct >= 0 ? "up" : "down") \(absPctString(dayPct, decimals: 1))",
                    tail: " today — \(fmtMoney(abs(dollar))) move on your position."
                )
            )
            return (abs(dollar), item)
        }
        .sorted { $0.0 > $1.0 }
        .map(\.1)
    }

    private static func portfolioDetailRows(store: PortfolioStore) -> [DetailRow] {
        let totalMV = max(1, store.companies.reduce(0.0) { $0 + $1.agg.mv })
        return store.companies.compactMap { c -> (Double, DetailRow)? in
            guard let s = c.legs.first(where: { $0.kind == .stock && $0.qty > 0 }) else { return nil }
            let pct = c.dayPct
            let dollar = s.qty * c.spot * (pct / 100.0)
            let weight = c.agg.mv / totalMV * 100
            let row = DetailRow(
                name: c.ticker,
                sub: "\(pctString(weight, decimals: 1)) weight · \(Int(s.qty)) sh",
                value: pctString(pct, decimals: 1),
                tone: pct >= 0 ? .pos : .neg
            )
            return (abs(dollar), row)
        }
        .sorted { $0.0 > $1.0 }
        .map(\.1)
        .prefix(7)
        .map { $0 }
    }

    // ─── Events bucket (macro_events) ──────────────────────────

    /// Soonest upcoming event with importance >= 2. Skips holidays.
    private static func eventsItem(store: PortfolioStore, today: Date) -> TodayItem? {
        let upcoming = store.allMacroEvents
            .filter { !$0.is_holiday && $0.importance >= 2 }
            .compactMap { ev -> (Int, MacroEventRow)? in
                guard let d = parseDate(ev.event_date) else { return nil }
                let days = daysBetween(today, d)
                guard days >= 0 else { return nil }
                return (days, ev)
            }
            .sorted { $0.0 < $1.0 }

        guard let (days, ev) = upcoming.first else { return nil }
        let num = dayLabel(days)
        return TodayItem(
            id: "events:\(ev.id)",
            bucket: .events,
            category: "Events",
            short: ev.category?.uppercased() ?? "EVENT",
            name: ev.name,
            sub: ev.summary ?? formatEventTime(ev),
            num: num,
            unit: days == 0 ? "today" : "UNTIL",
            tone: .neutral,
            line: ev.summary ?? "Upcoming event — \(ev.name).",
            detailTitle: "Events",
            detailSub: "",
            detailRows: upcoming.prefix(7).map { (d, e) in
                DetailRow(
                    name: e.name,
                    sub: formatEventTime(e),
                    value: dayLabel(d),
                    tone: .neutral,
                    pinId: "macro:\(e.id)"
                )
            },
            pinNarrative: PinNarrative(
                lead: "\(ev.name) lands ",
                value: days <= 1 ? num.lowercased() : "in \(num)",
                tail: " — \(ev.summary ?? "watch the print")."
            )
        )
    }

    /// Build a standalone TodayItem for a single macro event — used
    /// when the user has pinned an individual row from the Events
    /// sheet, so the home rail can render it as its own card.
    static func itemForMacroEvent(_ ev: MacroEventRow, today: Date) -> TodayItem {
        let days = parseDate(ev.event_date).map { daysBetween(today, $0) } ?? 0
        let num = dayLabel(days)
        return TodayItem(
            id: "macro:\(ev.id)",
            bucket: .events,
            category: "Events",
            short: ev.category?.uppercased() ?? "EVENT",
            name: ev.name,
            sub: ev.summary ?? formatEventTime(ev),
            num: num,
            unit: days == 0 ? "today" : "UNTIL",
            tone: .neutral,
            line: ev.summary ?? "Upcoming event — \(ev.name).",
            detailTitle: ev.name,
            detailSub: "",
            detailRows: [],
            pinNarrative: PinNarrative(
                lead: "\(ev.name) lands ",
                value: days <= 1 ? num.lowercased() : "in \(num)",
                tail: " — \(ev.summary ?? "watch the print")."
            )
        )
    }

    private static func formatEventTime(_ ev: MacroEventRow) -> String {
        let time = ev.event_time?.prefix(5) ?? ""    // HH:MM
        let date = fmtShortDate(ev.event_date)
        return time.isEmpty ? date : "\(date) · \(time) ET"
    }

    // ─── Earnings bucket (earnings_events) ─────────────────────

    /// Soonest upcoming earnings on a position (scope='position').
    /// Falls back to peer earnings if no position earnings in the
    /// next 30 days.
    private static func earningsItem(store: PortfolioStore, today: Date) -> TodayItem? {
        let position = soonestEarnings(store: store, scopes: ["position"], today: today)
        let chosen = position ?? soonestEarnings(store: store, scopes: ["position", "peer"], today: today)
        guard let (days, e) = chosen else { return nil }

        let num: String
        let unit: String
        let line: String
        if days <= 6 {
            num = dayLabel(days)
            unit = "UNTIL"
            line = "\(e.ticker) reports \(days == 0 ? "today" : days == 1 ? "tomorrow" : "in \(days) days") — \(e.scope_tag == "position" ? "you own this" : "sector peer of your book")."
        } else {
            num = dayLabel(days)
            unit = "UNTIL"
            line = "\(e.ticker) reports in \(days) days — \(e.scope_tag == "position" ? "in your book" : "peer of your positions")."
        }

        let allUpcoming = store.allEarningsEvents
            .compactMap { row -> (Int, EarningsEventRow)? in
                guard let d = parseDate(row.report_date) else { return nil }
                let days = daysBetween(today, d)
                guard days >= 0 else { return nil }
                return (days, row)
            }
            .sorted { $0.0 < $1.0 }

        return TodayItem(
            id: "earnings:\(e.id)",
            bucket: .earnings,
            category: "Earnings",
            short: e.ticker,
            name: e.company_name ?? e.ticker,
            sub: "\(fmtShortDate(e.report_date)) · \(reportTimeLabel(e.report_time))",
            num: num,
            unit: unit,
            tone: .neutral,
            line: line,
            detailTitle: "Earnings",
            detailSub: "Reports that move your book",
            detailRows: allUpcoming.prefix(7).map { (d, row) in
                DetailRow(
                    name: row.ticker,
                    sub: "\(fmtShortDate(row.report_date)) · \(reportTimeLabel(row.report_time)) · \(row.scope_tag == "position" ? "you own" : (row.sector_etf ?? "peer"))",
                    value: dayLabel(d),
                    tone: row.scope_tag == "position" ? .neon : .neutral,
                    pinId: "earnings:\(row.id)"
                )
            },
            pinNarrative: PinNarrative(
                lead: "\(e.ticker) reports in ",
                value: num,
                tail: " — \(e.scope_tag == "position" ? "in your book" : "sector peer")."
            )
        )
    }

    private static func soonestEarnings(
        store: PortfolioStore,
        scopes: [String],
        today: Date
    ) -> (Int, EarningsEventRow)? {
        store.allEarningsEvents
            .filter { scopes.contains($0.scope_tag) }
            .compactMap { row -> (Int, EarningsEventRow)? in
                guard let d = parseDate(row.report_date) else { return nil }
                let days = daysBetween(today, d)
                guard days >= 0 else { return nil }
                return (days, row)
            }
            .min { $0.0 < $1.0 }
    }

    private static func reportTimeLabel(_ rt: String?) -> String {
        switch rt {
        case "bmo": return "before open"
        case "amc": return "after close"
        case "tba": return "TBA"
        default:    return "TBA"
        }
    }

    // ─── Options bucket ────────────────────────────────────────

    /// The most pressing options metric. For v1: total open call
    /// premium collected. Could expand to "expiring this week" etc.
    private static func optionsItem(store: PortfolioStore, today: Date) -> TodayItem? {
        let openShortCalls = store.allTrades.filter {
            $0.action == "open"
                && $0.option_type == "call"
                && $0.direction == "short"
                && store.remainingContracts(for: $0) > 0
        }
        guard !openShortCalls.isEmpty else { return nil }

        let collected = openShortCalls.reduce(0.0) { sum, t in
            sum + store.remainingContracts(for: t) * t.premium * 100
        }
        let count = openShortCalls.reduce(0.0) { sum, t in
            sum + store.remainingContracts(for: t)
        }

        // Expiring within 7 days
        let expiringSoon = openShortCalls.filter { trade in
            guard let dte = AppDates.daysUntil(trade.expiry, from: today) else { return false }
            return dte <= 7 && dte >= 0
        }
        let expiringQty = expiringSoon.reduce(0.0) { sum, t in
            sum + store.remainingContracts(for: t)
        }

        let line: String
        let pinValue: String
        let pinTail: String
        if expiringQty > 0 {
            line = "\(Int(expiringQty)) short calls expiring this week — decide roll vs assignment for any near-the-money."
            pinValue = "\(Int(expiringQty)) calls"
            pinTail = " expire within 7 days — review for roll vs assignment."
        } else {
            line = "Open call credit is \(fmtMoney(collected)) across \(Int(count)) contracts."
            pinValue = fmtMoney(collected)
            pinTail = " open call credit across \(Int(count)) contracts."
        }

        return TodayItem(
            id: "options:open_calls",
            bucket: .options,
            category: "Options",
            short: "Calls",
            name: expiringQty > 0 ? "Covered calls expiring" : "Open call credit",
            sub: expiringQty > 0
                ? "\(Int(expiringQty)) within 7 days"
                : "\(Int(count)) contracts open",
            num: expiringQty > 0 ? "\(Int(expiringQty))" : fmtMoney(collected),
            unit: expiringQty > 0 ? "EXPIRING" : "COLLECTED",
            tone: expiringQty > 0 ? .warn : .neon,
            line: line,
            detailTitle: "Options",
            detailSub: "Open positions and decay",
            detailRows: optionsDetailRows(store: store, today: today),
            pinNarrative: PinNarrative(
                lead: "",
                value: pinValue,
                tail: pinTail
            )
        )
    }

    private static func optionsDetailRows(store: PortfolioStore, today: Date) -> [DetailRow] {
        let openTrades = store.allTrades.filter {
            $0.action == "open" && store.remainingContracts(for: $0) > 0
        }
        let calls = openTrades.filter { $0.option_type == "call" && $0.direction == "short" }
        let puts  = openTrades.filter { $0.option_type == "put"  && $0.direction == "long" }

        let callCount = calls.reduce(0.0) { $0 + store.remainingContracts(for: $1) }
        let putCount  = puts.reduce(0.0)  { $0 + store.remainingContracts(for: $1) }
        let callCredit = calls.reduce(0.0) { $0 + store.remainingContracts(for: $1) * $1.premium * 100 }
        let putCost    = puts.reduce(0.0)  { $0 + store.remainingContracts(for: $1) * $1.premium * 100 }

        let expiringCalls = calls.filter {
            guard let dte = AppDates.daysUntil($0.expiry, from: today) else { return false }
            return dte <= 7 && dte >= 0
        }
        let expiringQty = expiringCalls.reduce(0.0) { $0 + store.remainingContracts(for: $1) }

        return [
            DetailRow(name: "Open call credit", sub: "premium collected", value: fmtMoney(callCredit), tone: .neon),
            DetailRow(name: "Covered calls",    sub: "contracts open",   value: "\(Int(callCount))",   tone: .neutral),
            DetailRow(name: "Expiring ≤ 7d",    sub: "near term",         value: "\(Int(expiringQty))",  tone: expiringQty > 0 ? .warn : .neutral),
            DetailRow(name: "Protective puts",  sub: "contracts open",   value: "\(Int(putCount))",     tone: .neutral),
            DetailRow(name: "Put cost",          sub: "premium paid",     value: fmtMoney(putCost),     tone: .neg),
        ]
    }

    // ─── (former IV bucket removed) ────────────────────────────
    // The day-over-day IV-change bucket that lived here is gone.
    // IV now has its own dedicated section on the Today screen
    // (IVMergedRow + IVTracker rail) backed by the Seller Score
    // model — see IVCard.swift, IVSheet.swift, IVTracker.swift.

    /// Build a standalone TodayItem for a single earnings event —
    /// used when the user has pinned an individual row from the
    /// Earnings sheet.
    static func itemForEarnings(_ e: EarningsEventRow, today: Date) -> TodayItem {
        let days = parseDate(e.report_date).map { daysBetween(today, $0) } ?? 0
        let num = dayLabel(days)
        let line = "\(e.ticker) reports \(days == 0 ? "today" : days == 1 ? "tomorrow" : "in \(days) days") — \(e.scope_tag == "position" ? "in your book" : "sector peer of your positions")."
        return TodayItem(
            id: "earnings:\(e.id)",
            bucket: .earnings,
            category: "Earnings",
            short: e.ticker,
            name: e.company_name ?? e.ticker,
            sub: "\(fmtShortDate(e.report_date)) · \(reportTimeLabel(e.report_time))",
            num: num,
            unit: "UNTIL",
            tone: .neutral,
            line: line,
            detailTitle: e.company_name ?? e.ticker,
            detailSub: "",
            detailRows: [],
            pinNarrative: PinNarrative(
                lead: "\(e.ticker) reports ",
                value: days <= 1 ? (days == 0 ? "today" : "tomorrow") : "in \(num)",
                tail: " — \(e.scope_tag == "position" ? "in your book" : "sector peer")."
            )
        )
    }

    // ─── Helpers ───────────────────────────────────────────────

    /// "TODAY" / "TOMORROW" / "Nd" — used for day-countdown values
    /// across the Today screen and sheets.
    static func dayLabel(_ days: Int) -> String {
        switch days {
        case 0:  return "TODAY"
        case 1:  return "TOMORROW"
        default: return "\(days)d"
        }
    }

    /// "Jun 9, 26" — app-wide short date format. Input is the
    /// canonical "yyyy-MM-dd" string we store in Supabase; output
    /// is the human-readable short form used on cards, sheets, and
    /// row subs.
    static func fmtShortDate(_ ymd: String) -> String {
        guard let d = parseDate(ymd) else { return ymd }
        let out = DateFormatter()
        out.dateFormat = "MMM d, yy"
        out.timeZone = TimeZone(identifier: "America/New_York")
        return out.string(from: d)
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s + "T12:00:00Z") { return d }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "America/New_York")
        return df.date(from: s)
    }

    private static func daysBetween(_ from: Date, _ to: Date) -> Int {
        let cal = Calendar(identifier: .gregorian)
        let d1 = cal.startOfDay(for: from)
        let d2 = cal.startOfDay(for: to)
        return cal.dateComponents([.day], from: d1, to: d2).day ?? 0
    }

    private static func pctString(_ v: Double, decimals: Int) -> String {
        let sign = v >= 0 ? "+" : "−"   // proper minus sign
        let abs = String(format: "%.\(decimals)f", Swift.abs(v))
        return "\(sign)\(abs)%"
    }

    /// "0.9%" — for use INSIDE narratives where the direction is
    /// already conveyed in words ("up" / "down"). Avoids the
    /// awkward "down +0.9%" phrasing.
    private static func absPctString(_ v: Double, decimals: Int) -> String {
        let abs = String(format: "%.\(decimals)f", Swift.abs(v))
        return "\(abs)%"
    }

    private static func fmtMoney(_ v: Double) -> String {
        let abs = Swift.abs(v)
        if abs >= 1_000_000 { return String(format: "$%.2fM", v / 1_000_000) }
        if abs >= 1_000     { return String(format: "$%.1fK", v / 1_000) }
        return String(format: "$%.0f", v)
    }
}
